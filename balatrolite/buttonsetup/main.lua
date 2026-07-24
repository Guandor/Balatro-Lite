-- Balatro Lite button setup.
--
-- Handhelds disagree about which physical button is A. Some print the Xbox
-- arrangement, some the Nintendo one, and the SDL mapping a device ships with
-- does not always agree with its own case lettering -- so the button under the
-- player's thumb can report itself as something else, or as nothing at all.
-- Balatro only ever sees SDL's names, so the fix belongs below the game: this
-- asks for each button by the letter printed on the device, writes an SDL
-- mapping that matches the hardware, and the launcher hands that mapping to
-- the game through SDL_GAMECONTROLLERCONFIG.
--
-- The game and its saves are untouched. The only thing written is one mapping
-- line in the port's saves folder, and that file is also the record of having
-- run: deleting it is how the player asks for the questions again.

local mapping = require('mapping')

local OUTPUT_PATH = os.getenv('BALATRO_PM_BUTTON_MAP_FILE')
local FONT_PATH = os.getenv('BALATRO_PM_BUTTON_FONT')

-- Nothing here may leave the device sitting on a screen it cannot get off, so
-- every state has a way out that needs no particular button to work: an idle
-- run gives up on its own, and the wizard is skipped rather than retried.
local IDLE_TIMEOUT = 60
local NO_PAD_TIMEOUT = 12
local OPTIONAL_SKIP = 8
-- One press must not answer two questions.
local INPUT_COOLDOWN = 0.3
local AXIS_TRAVEL = 0.6
local AXIS_RETURN = 0.35
local MESSAGE_TIME = 1.6

-- The four the player actually asks about. A device that already has a usable
-- SDL mapping needs no more than these: everything else in that mapping was
-- right to begin with.
local FACE_STEPS = {
    {control = 'a', cue = 'A', prompt = 'Press the button marked A'},
    {control = 'b', cue = 'B', prompt = 'Press the button marked B'},
    {control = 'x', cue = 'X', prompt = 'Press the button marked X'},
    {control = 'y', cue = 'Y', prompt = 'Press the button marked Y'},
}

-- Asked only when SDL has no mapping for the device at all, in which case none
-- of its buttons reach the game and the short version would not be enough.
local REST_STEPS = {
    {control = 'dpup', cue = 'UP', prompt = 'Press D-pad UP'},
    {control = 'dpdown', cue = 'DOWN', prompt = 'Press D-pad DOWN'},
    {control = 'dpleft', cue = 'LEFT', prompt = 'Press D-pad LEFT'},
    {control = 'dpright', cue = 'RIGHT', prompt = 'Press D-pad RIGHT'},
    {control = 'start', cue = 'START', prompt = 'Press START'},
    {control = 'back', cue = 'SELECT', prompt = 'Press SELECT'},
    {control = 'leftshoulder', cue = 'L1', prompt = 'Press the LEFT shoulder button',
     optional = true},
    {control = 'rightshoulder', cue = 'R1', prompt = 'Press the RIGHT shoulder button',
     optional = true},
}

local BG = {0.09, 0.13, 0.17}
local PANEL = {0.16, 0.22, 0.28}
local ACCENT = {0.99, 0.37, 0.33}
local TEXT = {0.96, 0.96, 0.94}
local DIM = {0.62, 0.68, 0.72}

local state = 'intro'
local pad, base_mapping
local steps, step_index = FACE_STEPS, 1
local learned = {}
local built_mapping
local axis_rest, axis_held = {}, {}
local cooldown, idle, message, message_timer, optional_timer = 0, 0, nil, 0, 0
local fonts, font_data

--------------------------------------------------------------------------- io

local function write_output(contents)
    if not OUTPUT_PATH then return false end
    local file = io.open(OUTPUT_PATH, 'w')
    if not file then return false end
    file:write(contents)
    file:close()
    return true
end

-- A run that ends without an answer still records that it happened. Otherwise
-- a device that cannot complete the wizard -- no controller, a crash, a player
-- who walked away -- would meet it again on every single launch.
local function finish_without_mapping(reason)
    write_output('# Balatro Lite button setup: ' .. reason .. '.\n' ..
        '# The device\'s own button mapping is being used.\n' ..
        '# Delete this file to be asked about the buttons again.\n')
    love.event.quit()
end

local function save_and_quit()
    write_output('# Balatro Lite button setup.\n' ..
        '# Delete this file to be asked about the buttons again.\n' ..
        built_mapping .. '\n')
    state = 'saved'
    message_timer = 1.2
end

-- An unhandled error would otherwise park the device on LÖVE's error screen,
-- which on a handheld cannot be dismissed. Record the skip and get out of the
-- way so the game still launches.
function love.errorhandler(_)
    pcall(finish_without_mapping, 'setup could not run')
    return function() return 0 end
end

------------------------------------------------------------------- appearance

local function build_fonts()
    local h = love.graphics.getHeight()
    local function make(fraction)
        local size = math.max(10, math.floor(h*fraction))
        if font_data then
            local ok, font = pcall(love.graphics.newFont, font_data, size)
            if ok then return font end
        end
        return love.graphics.newFont(size)
    end
    fonts = {title = make(0.045), cue = make(0.13), body = make(0.062),
             hint = make(0.038)}
end

function love.load()
    -- The port's own font, read straight off disk: this is a bare LÖVE game
    -- folder, so the file is outside its filesystem and cannot be required.
    if FONT_PATH then
        local file = io.open(FONT_PATH, 'rb')
        if file then
            local contents = file:read('*a')
            file:close()
            local ok, data = pcall(love.filesystem.newFileData, contents, 'ui.ttf')
            if ok then font_data = data end
        end
    end
    build_fonts()
end

function love.resize()
    build_fonts()
end

---------------------------------------------------------------------- capture

local function begin_steps()
    -- getGamepadMappingString is what SDL would use for this pad as things
    -- stand. When there is one, the answers are patched into it; when there is
    -- not, the device is unmapped and the long form has to build one.
    base_mapping = nil
    if love.joystick.getGamepadMappingString then
        local ok, existing = pcall(love.joystick.getGamepadMappingString, pad:getGUID())
        if ok and existing and existing ~= '' then base_mapping = existing end
    end

    steps = {}
    for _, step in ipairs(FACE_STEPS) do steps[#steps + 1] = step end
    if not base_mapping then
        for _, step in ipairs(REST_STEPS) do steps[#steps + 1] = step end
    end

    -- Triggers rest at one end of their travel rather than in the middle, so
    -- rest is whatever each axis reads before anything has been touched.
    axis_rest, axis_held = {}, {}
    for i = 1, pad:getAxisCount() do axis_rest[i] = pad:getAxis(i) end

    step_index, learned = 1, {}
    state = 'prompt'
    optional_timer = 0
end

local function restart_steps()
    learned = {}
    step_index = 1
    state = 'prompt'
    optional_timer = 0
    message, message_timer = nil, 0
end

local function finish_steps()
    built_mapping = mapping.build(pad:getGUID(), pad:getName(), learned, base_mapping)
    -- Apply it here so the confirmation below is answered through the mapping
    -- that is about to be saved, rather than through the old one.
    if love.joystick.loadGamepadMappings then
        pcall(love.joystick.loadGamepadMappings, built_mapping)
    end
    state = 'confirm'
end

local function advance()
    if step_index > #steps then
        finish_steps()
    else
        optional_timer = 0
    end
end

local function record(input)
    local step = steps[step_index]
    if not step then return end

    for _, entry in ipairs(learned) do
        if entry.input == input then
            message = 'That is already ' .. entry.control:upper() ..
                '. Try a different button.'
            message_timer = MESSAGE_TIME
            return
        end
    end

    learned[#learned + 1] = {control = step.control, input = input}
    step_index = step_index + 1
    cooldown = INPUT_COOLDOWN
    message, message_timer = nil, 0
    advance()
end

-- Any pad may claim the wizard on its first press; after that only that one is
-- listened to, so a second controller cannot answer half the questions.
local function accepts(joystick)
    if state == 'intro' then return true end
    return pad ~= nil and joystick == pad
end

local function handle(joystick, input)
    idle = 0
    if cooldown > 0 or not accepts(joystick) then return end

    if state == 'intro' then
        pad = joystick
        cooldown = INPUT_COOLDOWN
        begin_steps()
    elseif state == 'prompt' then
        record(input)
    elseif state == 'confirm' then
        -- The confirmation is meant to be answered through the new mapping,
        -- but a device SDL still refuses to treat as a gamepad would have no
        -- way to answer at all. The raw inputs just learned stand in for it.
        for _, entry in ipairs(learned) do
            if entry.input == input then
                if entry.control == 'a' then
                    cooldown = INPUT_COOLDOWN
                    save_and_quit()
                elseif entry.control == 'b' then
                    cooldown = INPUT_COOLDOWN
                    restart_steps()
                end
                return
            end
        end
    end
end

function love.joystickpressed(joystick, button)
    handle(joystick, 'b' .. (button - 1))
end

function love.joystickhat(joystick, hat, direction)
    -- Diagonals are two directions at once and belong to neither.
    local mask = mapping.HAT_MASK[direction]
    if not mask then return end
    handle(joystick, 'h' .. (hat - 1) .. '.' .. mask)
end

function love.gamepadpressed(joystick, button)
    if state ~= 'confirm' or not accepts(joystick) or cooldown > 0 then return end
    idle = 0
    if button == 'a' then
        cooldown = INPUT_COOLDOWN
        save_and_quit()
    elseif button == 'b' then
        cooldown = INPUT_COOLDOWN
        restart_steps()
    end
end

function love.keypressed(key)
    idle = 0
    if key == 'escape' then
        finish_without_mapping('setup was skipped')
    end
end

local function poll_axes()
    if not pad then return end
    for i = 1, pad:getAxisCount() do
        local travel = pad:getAxis(i) - (axis_rest[i] or 0)
        if not axis_held[i] and math.abs(travel) > AXIS_TRAVEL then
            axis_held[i] = true
            handle(pad, (travel > 0 and '+a' or '-a') .. (i - 1))
        elseif axis_held[i] and math.abs(travel) < AXIS_RETURN then
            axis_held[i] = false
        end
    end
end

function love.update(dt)
    cooldown = math.max(0, cooldown - dt)
    if message_timer > 0 then
        message_timer = message_timer - dt
        if message_timer <= 0 and state ~= 'saved' then message = nil end
    end

    if state == 'saved' then
        if message_timer <= 0 then love.event.quit() end
        return
    end

    poll_axes()

    idle = idle + dt
    if state == 'intro' and #love.joystick.getJoysticks() == 0 then
        if idle > NO_PAD_TIMEOUT then
            finish_without_mapping('no controller was detected')
        end
        return
    end
    if idle > IDLE_TIMEOUT then
        finish_without_mapping('setup timed out')
        return
    end

    -- A device without shoulder buttons still has to be able to get past the
    -- question about them.
    local step = steps[step_index]
    if state == 'prompt' and step and step.optional then
        optional_timer = optional_timer + dt
        if optional_timer > OPTIONAL_SKIP then
            step_index = step_index + 1
            optional_timer = 0
            advance()
        end
    end
end

------------------------------------------------------------------------- draw

local function set_colour(colour, alpha)
    love.graphics.setColor(colour[1], colour[2], colour[3], alpha or 1)
end

local function centred(font, text, y, colour)
    love.graphics.setFont(font)
    set_colour(colour or TEXT)
    love.graphics.printf(text, 0, y, love.graphics.getWidth(), 'center')
    return y + font:getHeight()
end

local function draw_cue(text, y)
    local font = fonts.cue
    local w = font:getWidth(text) + font:getHeight()*0.9
    local h = font:getHeight()*1.5
    local x = (love.graphics.getWidth() - w)/2
    set_colour(PANEL)
    love.graphics.rectangle('fill', x, y, w, h, h*0.28)
    set_colour(ACCENT)
    love.graphics.setLineWidth(math.max(2, h*0.045))
    love.graphics.rectangle('line', x, y, w, h, h*0.28)
    love.graphics.setFont(font)
    set_colour(TEXT)
    love.graphics.printf(text, x, y + (h - font:getHeight())/2, w, 'center')
    return y + h
end

-- One pip per question, filled in as they are answered.
local function draw_progress(y)
    local total = #steps
    if total == 0 then return end
    local radius = math.max(3, love.graphics.getHeight()*0.009)
    local gap = radius*3.2
    local x = (love.graphics.getWidth() - gap*(total - 1))/2
    for i = 1, total do
        if i <= #learned then set_colour(ACCENT) else set_colour(DIM, 0.45) end
        love.graphics.circle('fill', x + gap*(i - 1), y, radius)
    end
end

function love.draw()
    local w, h = love.graphics.getDimensions()
    set_colour(BG)
    love.graphics.rectangle('fill', 0, 0, w, h)

    centred(fonts.title, 'BALATRO LITE  ·  BUTTON SETUP', h*0.06, DIM)

    if state == 'intro' then
        local y = centred(fonts.body, 'Which button is A is up to your device,', h*0.3)
        y = centred(fonts.body, 'not up to the game.', y)
        centred(fonts.body, 'Press any button to begin.', y + h*0.06, ACCENT)
        if #love.joystick.getJoysticks() == 0 then
            centred(fonts.hint, 'No controller detected. Skipping shortly.', h*0.8, DIM)
        else
            centred(fonts.hint,
                'Answer with the letters printed on your device.\n' ..
                'Nothing is saved until you confirm at the end.', h*0.78, DIM)
        end
    elseif state == 'prompt' then
        local step = steps[step_index]
        if step then
            local y = draw_cue(step.cue, h*0.26)
            y = centred(fonts.body, step.prompt, y + h*0.05)
            if message then
                centred(fonts.hint, message, y + h*0.03, ACCENT)
            elseif step.optional then
                centred(fonts.hint,
                    string.format('No such button? Wait %d seconds to skip it.',
                        math.max(0, math.ceil(OPTIONAL_SKIP - optional_timer))),
                    y + h*0.03, DIM)
            end
            centred(fonts.hint,
                string.format('%d of %d', step_index, #steps), h*0.85, DIM)
            draw_progress(h*0.93)
        end
    elseif state == 'confirm' then
        local y = centred(fonts.body, 'Buttons set.', h*0.28, TEXT)
        y = centred(fonts.body, 'Press A to save.', y + h*0.06, ACCENT)
        y = centred(fonts.body, 'Press B to start over.', y)
        centred(fonts.hint,
            'These are the buttons you just pressed, so if the wrong one\n' ..
            'answers this, start over.', h*0.8, DIM)
    elseif state == 'saved' then
        centred(fonts.body, 'Saved. Starting Balatro...', h*0.45)
    end
end
