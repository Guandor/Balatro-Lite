-- Headless harness for balatrolite/buttonsetup: stubs LÖVE, drives the state
-- machine, and checks the mapping line that comes out the other end. The
-- button setup is the one part of this port that cannot be tried out on a
-- desktop, so it is checked here instead of on a handheld.
--
-- Not part of the port: port.json ships "Balatro Lite.sh" and the balatrolite
-- folder, and this is in neither.
--
--   SETUP_DIR=balatrolite/buttonsetup BALATRO_PM_BUTTON_MAP_FILE=/tmp/map.txt \
--       luajit tests/buttonsetup_spec.lua

local DIR = os.getenv('SETUP_DIR')
local OUT = os.getenv('BALATRO_PM_BUTTON_MAP_FILE')
package.path = DIR .. '/?.lua;' .. package.path

local failures = 0
local function check(name, cond, extra)
    if cond then
        print('  ok   ' .. name)
    else
        failures = failures + 1
        print('  FAIL ' .. name .. (extra and ('  <' .. tostring(extra) .. '>') or ''))
    end
end

local function read_output()
    local f = io.open(OUT, 'r')
    if not f then return nil end
    local c = f:read('*a')
    f:close()
    return c
end

local function mapping_line(contents)
    if not contents then return nil end
    for line in contents:gmatch('[^\n]+') do
        if not line:match('^#') and line:match('%S') then return line end
    end
    return nil
end

--------------------------------------------------------------------- love stub

local function make_font()
    return {
        getHeight = function() return 20 end,
        getWidth = function(_, s) return #tostring(s)*10 end,
    }
end

local quit_called

local function fresh_love(joysticks, mapping_string)
    quit_called = false
    local G = {}
    for _, name in ipairs({'setColor', 'rectangle', 'circle', 'printf', 'setFont',
                           'setLineWidth', 'clear'}) do
        G[name] = function() end
    end
    G.getWidth = function() return 1280 end
    G.getHeight = function() return 720 end
    G.getDimensions = function() return 1280, 720 end
    G.newFont = function() return make_font() end

    return {
        graphics = G,
        filesystem = {newFileData = function() return {} end},
        event = {quit = function() quit_called = true end},
        timer = {getDelta = function() return 1/60 end},
        joystick = {
            getJoysticks = function() return joysticks end,
            getGamepadMappingString = function()
                if mapping_string then return mapping_string end
                error('no mapping')
            end,
            loadGamepadMappings = function() return true end,
        },
    }
end

local function make_pad(axes)
    local values = axes or {}
    return {
        getGUID = function() return '19000000010000000100000000010000' end,
        getName = function() return 'Retro, Handheld' end,
        getAxisCount = function() return #values end,
        getAxis = function(_, i) return values[i] end,
        _axes = values,
    }
end

local function load_main()
    local chunk = assert(loadfile(DIR .. '/main.lua'))
    chunk()
end

local function tick(n)
    for _ = 1, (n or 1) do love.update(1/60) end
end

-- Enough frames to clear the input cooldown between presses. Every settle also
-- draws, so a drawing mistake in any state shows up as an error here.
local function settle()
    tick(30)
    love.draw()
end

------------------------------------------------------------------------ tests

local BASE = '19000000010000000100000000010000,Retro Handheld,' ..
    'a:b1,b:b0,x:b3,y:b2,back:b8,start:b9,dpup:h0.1,dpdown:h0.4,' ..
    'leftshoulder:b4,platform:Linux,'

print('short path: device already has a mapping, only the four faces are asked')
do
    os.remove(OUT)
    local pad = make_pad({0, 0, -1})
    love = fresh_love({pad}, BASE)
    load_main()
    love.load()

    love.joystickpressed(pad, 1)          -- intro: begin
    settle()

    love.joystickpressed(pad, 2)          -- A -> b1
    settle()
    love.joystickpressed(pad, 1)          -- B -> b0
    settle()
    love.joystickpressed(pad, 4)          -- X -> b3
    settle()
    love.joystickpressed(pad, 3)          -- Y -> b2
    settle()

    check('nothing written before confirming', read_output() == nil)

    love.gamepadpressed(pad, 'a')
    tick(120)
    check('quits after saving', quit_called)

    local line = mapping_line(read_output())
    check('mapping written', line ~= nil)
    check('A learned', line and line:find('a:b1,', 1, true), line)
    check('B learned', line and line:find('b:b0,', 1, true), line)
    check('X learned', line and line:find('x:b3,', 1, true), line)
    check('Y learned', line and line:find('y:b2,', 1, true), line)
    check('base entries survive', line and line:find('dpup:h0.1', 1, true) and
        line:find('start:b9', 1, true), line)
    check('device name kept, commas stripped',
        line and line:find(',Retro Handheld,', 1, true), line)
    check('platform present', line and line:find('platform:Linux', 1, true), line)
    check('one entry per control', select(2, line:gsub('a:b', '')) == 1, line)
end

print('swapped labels: the physical button marked A reports as b')
do
    os.remove(OUT)
    local pad = make_pad({})
    love = fresh_love({pad}, BASE)
    load_main()
    love.load()
    love.joystickpressed(pad, 1) settle()
    love.joystickpressed(pad, 1) settle()   -- A pressed -> raw b0
    love.joystickpressed(pad, 2) settle()   -- B pressed -> raw b1
    love.joystickpressed(pad, 3) settle()   -- X -> b2
    love.joystickpressed(pad, 4) settle()   -- Y -> b3
    love.gamepadpressed(pad, 'a')
    tick(120)
    local line = mapping_line(read_output())
    check('A now points at the raw button the player calls A',
        line and line:find('a:b0,', 1, true), line)
    check('B follows', line and line:find('b:b1,', 1, true), line)
end

print('duplicate presses are refused')
do
    os.remove(OUT)
    local pad = make_pad({})
    love = fresh_love({pad}, BASE)
    load_main()
    love.load()
    love.joystickpressed(pad, 1) settle()
    love.joystickpressed(pad, 5) settle()   -- A -> b4
    love.joystickpressed(pad, 5) settle()   -- same button again: refused
    love.joystickpressed(pad, 6) settle()   -- B -> b5
    love.joystickpressed(pad, 7) settle()
    love.joystickpressed(pad, 8) settle()
    love.gamepadpressed(pad, 'a')
    tick(120)
    local line = mapping_line(read_output())
    check('the repeat did not answer the next question',
        line and line:find('a:b4,', 1, true) and line:find('b:b5,', 1, true), line)
end

print('a base entry pointing at a face button loses to the answer')
do
    os.remove(OUT)
    -- This base mapping has the D-pad bound to buttons, and dpup is sitting on
    -- the same raw button the player calls A.
    local BROKEN = '19000000010000000100000000010000,Retro Handheld,' ..
        'a:b1,b:b0,x:b3,y:b2,dpup:b0,dpdown:b7,start:b9,platform:Linux,'
    local pad = make_pad({})
    love = fresh_love({pad}, BROKEN)
    load_main()
    love.load()
    love.joystickpressed(pad, 1) settle()
    love.joystickpressed(pad, 1) settle()   -- A -> b0, which base calls dpup
    love.joystickpressed(pad, 2) settle()
    love.joystickpressed(pad, 3) settle()
    love.joystickpressed(pad, 4) settle()
    love.gamepadpressed(pad, 'a')
    tick(120)
    local line = mapping_line(read_output())
    check('the answer is kept', line and line:find('a:b0,', 1, true), line)
    check('the double binding is dropped', line and not line:find('dpup', 1, true), line)
    check('unrelated base entries stay', line and line:find('dpdown:b7,', 1, true) and
        line:find('start:b9,', 1, true), line)
end

print('long path: no mapping at all, so everything is asked')
do
    os.remove(OUT)
    local pad = make_pad({0, 0})
    love = fresh_love({pad}, nil)
    load_main()
    love.load()
    love.joystickpressed(pad, 1) settle()

    for i = 1, 4 do love.joystickpressed(pad, i) settle() end     -- a b x y
    love.gamepadpressed(pad, 'a')
    tick(120)
    check('the four faces alone do not end an unmapped device\'s setup',
        read_output() == nil, read_output())

    love.joystickhat(pad, 1, 'u') settle()
    love.joystickhat(pad, 1, 'd') settle()
    love.joystickhat(pad, 1, 'l') settle()
    love.joystickhat(pad, 1, 'r') settle()
    love.joystickpressed(pad, 9) settle()                          -- start
    love.joystickpressed(pad, 10) settle()                         -- back
    love.joystickpressed(pad, 11) settle()                         -- L1
    love.joystickpressed(pad, 12) settle()                         -- R1

    love.gamepadpressed(pad, 'a')
    tick(120)
    local line = mapping_line(read_output())
    check('built from nothing', line ~= nil)
    check('dpad hats', line and line:find('dpup:h0.1', 1, true) and
        line:find('dpright:h0.2', 1, true) and line:find('dpdown:h0.4', 1, true) and
        line:find('dpleft:h0.8', 1, true), line)
    check('start and select', line and line:find('start:b8,', 1, true) and
        line:find('back:b9,', 1, true), line)
    check('shoulders', line and line:find('leftshoulder:b10,', 1, true) and
        line:find('rightshoulder:b11,', 1, true), line)
    check('guid first', line and line:match('^19000000010000000100000000010000,'), line)
end

print('optional steps skip themselves so a device without them is not stuck')
do
    os.remove(OUT)
    local pad = make_pad({})
    love = fresh_love({pad}, nil)
    load_main()
    love.load()
    love.joystickpressed(pad, 1) settle()
    for i = 1, 4 do love.joystickpressed(pad, i) settle() end
    love.joystickhat(pad, 1, 'u') settle()
    love.joystickhat(pad, 1, 'd') settle()
    love.joystickhat(pad, 1, 'l') settle()
    love.joystickhat(pad, 1, 'r') settle()
    love.joystickpressed(pad, 9) settle()
    love.joystickpressed(pad, 10) settle()
    tick(60*9)   -- wait out L1
    tick(60*9)   -- wait out R1
    love.gamepadpressed(pad, 'a')
    tick(120)
    local line = mapping_line(read_output())
    check('reached the end without shoulder buttons', line ~= nil)
    check('no shoulder entries invented',
        line and not line:find('leftshoulder', 1, true), line)
end

print('axes are learned, and their resting position is not mistaken for a press')
do
    os.remove(OUT)
    local pad = make_pad({0, 0, -1})      -- axis 3 is a trigger, resting at -1
    love = fresh_love({pad}, nil)
    load_main()
    love.load()
    love.joystickpressed(pad, 1) settle()
    tick(60)
    check('resting trigger did not answer the A question', read_output() == nil)

    love.joystickpressed(pad, 1) settle() -- a
    love.joystickpressed(pad, 2) settle() -- b
    love.joystickpressed(pad, 3) settle() -- x
    love.joystickpressed(pad, 4) settle() -- y
    pad._axes[2] = -1                     -- stick pushed up
    tick(5)
    pad._axes[2] = 0
    settle()
    local line
    love.joystickhat(pad, 1, 'd') settle()
    love.joystickhat(pad, 1, 'l') settle()
    love.joystickhat(pad, 1, 'r') settle()
    love.joystickpressed(pad, 9) settle()
    love.joystickpressed(pad, 10) settle()
    tick(60*18)
    love.gamepadpressed(pad, 'a')
    tick(120)
    line = mapping_line(read_output())
    check('axis captured for dpup', line and line:find('dpup:-a1,', 1, true), line)
end

print('a run that ends without answers still records that it happened')
do
    os.remove(OUT)
    love = fresh_love({}, nil)
    load_main()
    love.load()
    tick(60*15)
    local contents = read_output()
    check('marker written when no controller shows up', contents ~= nil)
    check('marker carries no mapping', mapping_line(contents) == nil, contents)
    check('quit', quit_called)
end

print('escape skips')
do
    os.remove(OUT)
    local pad = make_pad({})
    love = fresh_love({pad}, BASE)
    load_main()
    love.load()
    love.keypressed('escape')
    check('skipped without a mapping', mapping_line(read_output()) == nil)
    check('quit', quit_called)
end

print('start over throws the answers away')
do
    os.remove(OUT)
    local pad = make_pad({})
    love = fresh_love({pad}, BASE)
    load_main()
    love.load()
    love.joystickpressed(pad, 1) settle()
    for i = 1, 4 do love.joystickpressed(pad, i) settle() end
    love.gamepadpressed(pad, 'b')          -- start over
    settle()
    love.joystickpressed(pad, 5) settle()
    love.joystickpressed(pad, 6) settle()
    love.joystickpressed(pad, 7) settle()
    love.joystickpressed(pad, 8) settle()
    love.gamepadpressed(pad, 'a')
    tick(120)
    local line = mapping_line(read_output())
    check('second run of answers is the one saved',
        line and line:find('a:b4,', 1, true) and not line:find('a:b0,', 1, true), line)
end

os.remove(OUT)
print(failures == 0 and 'ALL PASS' or (failures .. ' FAILURES'))
os.exit(failures == 0 and 0 or 1)
