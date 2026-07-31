-- PortMaster handheld layout for Balatro.
--
-- This file is injected into the user's licensed Balatro archive by the
-- Balatro Lite launcher.
-- It deliberately overrides only presentation functions; game rules and saves are
-- left untouched. Every measurement below is derived from the panel the game is
-- actually running on, so one patched archive is portable across devices.

-- Within the supported 1:1 to 2.4:1 range, the room is given the panel's own
-- aspect ratio and the desktop border is dropped, so the logical playfield covers
-- every pixel instead of sitting inside letterbox margins. Stock Balatro's
-- 20x11.5 room plus its border is a 22x12.9 logical window; on a 1024x768 panel
-- its width limits rendering to about 46.5 pixels per tile. The 4:3 room below
-- maps to 60 pixels per tile, about 29% larger.
--
-- The room is then grown from a 4:3 reference until it satisfies both of that
-- reference's dimensions, so one build serves every panel: 4:3 keeps exactly the
-- proportions everything here is tuned against, wider panels gain width at the
-- same height, and squarer ones gain height at the same width.
local REFERENCE_W = 17.0667
local REFERENCE_H = 12.8

local function display_ratio()
    local w, h
    if love.graphics and love.graphics.getDimensions then
        w, h = love.graphics.getDimensions()
    end
    if not (w and h and w > 0 and h > 0) and love.window then
        local ok, dw, dh = pcall(love.window.getDesktopDimensions)
        if ok and dw and dh and dh > 0 then w, h = dw, dh end
    end
    if not (w and h and w > 0 and h > 0) then return REFERENCE_W/REFERENCE_H end
    -- Portrait panels are clamped to square: love.resize refuses to scale a room
    -- taller than it is wide, so anything past that would letterbox regardless.
    return math.min(math.max(w/h, 1.0), 2.4)
end

local RATIO = display_ratio()
local ROOM_W = math.max(REFERENCE_W, REFERENCE_H*RATIO)
local ROOM_H = ROOM_W/RATIO
-- Every edge keeps this gap, so nothing is flush against the bezel.
local SAFE_MARGIN = 0.2
-- CardArea hangs its "cards left" counter below itself, and the play/discard
-- buttons hang below the hand. The desktop room padding used to catch both; this
-- layout has no padding, so the bottom row of areas is inset by that much more.
local BOTTOM_INSET = SAFE_MARGIN + 0.42
local HUD_ROW_H = 1.72
local OWNED_CARDS_Y = 2.18
-- Below the owned cards and the "3/5" counters that hang under them.
local RUN_OVERLAY_Y = 5.02
local OWNED_JOKER_SCALE = 0.95
local HAND_W = 6.8*G.CARD_W
-- Measured height of a blind-selection column: its cards, tag, and skip button.
local BLIND_SELECT_H = 7.7

-- Status bar cells are proportional to the room so the bar reaches both margins.
-- The 0.9 covers the root, row, and inter-cell padding the layout engine adds.
local HUD_INNER_W = ROOM_W - SAFE_MARGIN*2 - 0.9
local HUD_BLIND_W = HUD_INNER_W*0.29
local HUD_SCORE_W = HUD_INNER_W*0.165
local HUD_HAND_W = HUD_INNER_W*0.315
local HUD_META_W = HUD_INNER_W*0.23

-- Sizes the bar's readouts are pinned to. Each row is then built a little taller
-- than its capped text, so a value that rescales itself never resizes its row.
local SCORE_SCALE = 0.8
local SCORE_TEXT_W = HUD_SCORE_W - 0.26
local TARGET_SCALE = 0.42
-- The hand readout draws itself into fixed boxes (see FixedText), so these are
-- the sizes of those boxes rather than caps a measured layout has to respect.
local HAND_TEXT_SCALE = 0.48
-- The level rides beside the name at a fraction of its size.
local HAND_LEVEL_MULT = 0.72
local HAND_NUM_SCALE = 0.84
local HAND_NUM_BOX_W = 2.0
local HAND_BOX_PAD = 0.06
local DOLLARS_SCALE = 0.62
local DOLLARS_W = 1.24
local BLIND_NAME_SCALE = 0.5
local BLIND_NAME_W = HUD_BLIND_W - 1.05

G.F_SMALL_SCREEN_UI = true
G.F_HIDE_BG = true
G.TILE_W = ROOM_W
G.TILE_H = ROOM_H
G.FPS_CAP = 60

-- Face button lettering is a property of the handheld, not of the archive, so
-- the launcher passes it in the environment and the same build stays portable
-- between devices. set_globals derives button_mapping from these when the Game
-- is constructed, which has already happened by the time this file is read.
--
-- This is the fallback for devices known to print their letters in the other
-- order. Once the player has answered the launcher's button setup, the pad is
-- corrected below the game instead -- SDL reports the letters the player gave
-- it -- and the launcher stops setting this, because the two would cancel out.
if os.getenv('BALATRO_PM_SWAP_FACE_BUTTONS') == '1' then
    G.F_SWAP_AB_BUTTONS = true
    G.F_SWAP_XY_BUTTONS = true
    G.button_mapping = {a='b', b='a', y='x', x='y'}
end

-- Game:init_window reserves a one tile horizontal and 0.7 tile vertical border
-- around the room, which on a handheld is only ever letterboxing. Rebuild the
-- window transform without it; love.resize then maps the room onto the whole
-- display because the room and the panel share an aspect ratio.
local original_init_window = Game.init_window
function Game:init_window(...)
    local result = original_init_window(self, ...)
    self.ROOM_PADDING_W = 0
    self.ROOM_PADDING_H = 0
    self.WINDOWTRANS.w = self.TILE_W
    self.WINDOWTRANS.h = self.TILE_H
    self.window_prev.w = self.WINDOWTRANS.w*self.TILESIZE*self.TILESCALE
    self.window_prev.h = self.WINDOWTRANS.h*self.TILESIZE*self.TILESCALE
    self.window_prev.orig_ratio = self.WINDOWTRANS.w/self.WINDOWTRANS.h
    return result
end

-- Saved desktop graphics settings otherwise override the launcher's defaults.
-- Each of these is a per-frame cost on a handheld GPU: crt and bloom are
-- full-screen shader work, shadows double every card's draw calls, and reduced
-- motion drops the per-letter and per-card wobble.
local original_start_up = Game.start_up
function Game:start_up(...)
    local result = original_start_up(self, ...)
    self.SETTINGS.GRAPHICS.crt = 0
    self.SETTINGS.GRAPHICS.bloom = 0
    self.SETTINGS.GRAPHICS.shadows = 'Off'
    self.SETTINGS.screenshake = false
    self.SETTINGS.reduced_motion = true

    -- Match the atlas to the render size rather than always paying for the 2x
    -- sheets. A 480p panel draws cards at about 77 pixels wide, which is what
    -- the 1x atlas already is, so the larger sheets only cost memory and
    -- sampling bandwidth there. Saved so the reload happens once, not per boot.
    local atlas = (love.graphics.getHeight() <= 540) and 1 or 2
    if self.SETTINGS.GRAPHICS.texture_scaling ~= atlas then
        self.SETTINGS.GRAPHICS.texture_scaling = atlas
        self:set_render_settings()
        self:save_settings()
    end
    return result
end

-- Use the Brick's vertical pixels instead of preserving a desktop-width playfield.
-- Gameplay cards retain their normal dimensions; only the persistent owned-Joker
-- strip is reduced, without changing its capacity or any card behaviour.
local function resize_owned_joker(card)
    if not card then return end
    local target_w = G.CARD_W*OWNED_JOKER_SCALE
    local target_h = G.CARD_H*OWNED_JOKER_SCALE
    if math.abs(card.T.w-target_w) > 0.001 or
       math.abs(card.T.h-target_h) > 0.001 then
        card:hard_set_T(nil, nil, target_w, target_h)
    end
end

local function compact_owned_jokers()
    if not G.jokers then return end
    G.jokers.T.w = 4.9*G.CARD_W*OWNED_JOKER_SCALE
    G.jokers.T.h = 0.95*G.CARD_H*OWNED_JOKER_SCALE
    G.jokers.card_w = G.CARD_W*OWNED_JOKER_SCALE
    for _, card in ipairs(G.jokers.cards) do resize_owned_joker(card) end
    G.jokers:align_cards()
    G.jokers:hard_set_cards()
end

-- Newly purchased Jokers enter the existing area after start_run has completed.
local original_cardarea_emplace = CardArea.emplace
function CardArea:emplace(card, ...)
    if self == G.jokers then resize_owned_joker(card) end
    return original_cardarea_emplace(self, card, ...)
end

-- CardArea:move re-drives the hand to G.TILE_H minus its height on every frame,
-- which parks it flush against the bottom edge. Show that one call a shorter room
-- so the hand keeps the same border as everything else and its card counter, and
-- the play/discard/sort buttons that hang beneath it, stay on screen.
local original_cardarea_move = CardArea.move
function CardArea:move(dt)
    if self == G.hand then
        local room_h = G.TILE_H
        G.TILE_H = room_h - BOTTOM_INSET
        original_cardarea_move(self, dt)
        G.TILE_H = room_h
        return
    end
    return original_cardarea_move(self, dt)
end

-- Every visible CardArea lazily builds a box holding a translucent black plate
-- the size of itself, with its "5/5" counter underneath. The counter is worth
-- keeping and the plate is not, so hide just that row the first time the box
-- exists -- hiding it rather than clearing its colour also drops the fill, since
-- a fully transparent node is still drawn. The shop's voucher slot is left alone:
-- its plate is nil-coloured already and carries the restock message as a child.
local original_cardarea_draw = CardArea.draw
function CardArea:draw(...)
    local result = original_cardarea_draw(self, ...)
    local box = self.children.area_uibox
    if box and not box.small_screen_plate_hidden then
        box.small_screen_plate_hidden = true
        local plate = box.UIRoot and box.UIRoot.children and box.UIRoot.children[1]
        if plate and plate.config and plate.config.colour then
            plate.states.visible = false
        end
    end
    return result
end

-- The desktop main menu places its four large buttons beside a separate
-- language/social column. Together their reserved widths sit almost exactly on
-- the edge of a 4:3 handheld room, and localized labels can push them past it.
-- Compact only this menu: preserve the button arrangement and hit targets while
-- reducing label text, wide reservations, and generous desktop padding.
local original_main_menu_buttons = create_UIBox_main_menu_buttons
local function compact_main_menu_node(node)
    if not node then return end
    local config = node.config
    if config then
        if config.scale then config.scale = config.scale*0.78 end
        if config.minw and config.minw >= 2 then
            config.minw = config.minw*0.86
        end
        if config.maxw and config.maxw >= 2 then
            config.maxw = config.maxw*0.86
        end
        if config.padding and config.padding >= 0.1 then
            config.padding = config.padding*0.8
        end
    end
    if node.nodes then
        for _, child in pairs(node.nodes) do
            compact_main_menu_node(child)
        end
    end
end

function create_UIBox_main_menu_buttons(...)
    local result = original_main_menu_buttons(...)
    compact_main_menu_node(result)
    return result
end

-- The launcher asks which physical button is which on the first start and keeps
-- the answer in this file. Removing it is the whole of "ask me again", so the
-- options menu gets an entry that does exactly that. The setup itself runs
-- before the game, where it can hand the mapping to SDL before anything opens
-- the pad, so this schedules it rather than showing it now.
local BUTTON_MAP_FILE = os.getenv('BALATRO_PM_BUTTON_MAP_FILE')

local function button_setup_is_pending()
    if not BUTTON_MAP_FILE then return false end
    local file = io.open(BUTTON_MAP_FILE, 'r')
    if not file then return true end
    file:close()
    return false
end

local function node_holds_button(node)
    if type(node) ~= 'table' then return false end
    if node.config and node.config.button then return true end
    if node.nodes then
        for _, child in pairs(node.nodes) do
            if node_holds_button(child) then return true end
        end
    end
    return false
end

-- The stock menu is a list of UIBox_button results sitting in one node list.
-- Rather than assume where that list is, find it -- the one with the most
-- direct children that lead to a button -- and add to it. The new entry is then
-- built and placed exactly like its neighbours, whatever the layout around them
-- turns out to be, and a menu this fails to recognise is simply left alone.
local function find_button_list(node, best)
    if type(node) ~= 'table' or type(node.nodes) ~= 'table' then return best end
    local count = 0
    for _, child in pairs(node.nodes) do
        if node_holds_button(child) then count = count + 1 end
    end
    -- Two, so that a lone button in a wrapper is never mistaken for the list.
    if count >= 2 and count > (best and best.count or 0) then
        best = {list = node.nodes, count = count}
    end
    for _, child in pairs(node.nodes) do
        best = find_button_list(child, best)
    end
    return best
end

local function button_setup_node()
    return UIBox_button{
        id = 'small_screen_button_setup',
        label = {button_setup_is_pending() and 'Buttons: On Restart'
            or 'Set Up Buttons'},
        button = 'small_screen_button_setup',
        minw = 5, colour = G.C.BLUE
    }
end

-- Neighbours in that list may be wrapped a layer deep. Match whatever shape
-- they have, so the new entry lines up with them instead of beside them.
local function shaped_like(sibling, node)
    if type(sibling) ~= 'table' or sibling.config and sibling.config.button then
        return node
    end
    if type(sibling.nodes) ~= 'table' or #sibling.nodes ~= 1 then return node end
    return {n = sibling.n, config = {align = sibling.config and sibling.config.align},
        nodes = {node}}
end

local function append_to_button_list(definition)
    local best = find_button_list(definition, nil)
    if not best then return end
    local sibling
    for _, child in pairs(best.list) do
        if node_holds_button(child) then sibling = child end
    end
    local ok, node = pcall(button_setup_node)
    if ok and node then
        best.list[#best.list+1] = shaped_like(sibling, node)
    end
end

-- The menu builds itself from a list of entries before any of it becomes a node
-- tree. Adding to that list is worth a little bookkeeping: the entry is then
-- built and placed by the stock code, exactly like the ones beside it. The tree
-- is only searched when this menu turns out not to be built that way.
local building_options, added_to_contents = false, false

if type(create_UIBox_generic_options) == 'function' then
    local original_generic = create_UIBox_generic_options
    function create_UIBox_generic_options(args, ...)
        if building_options and type(args) == 'table' and
           type(args.contents) == 'table' then
            local ok, node = pcall(button_setup_node)
            if ok and node then
                args.contents[#args.contents+1] = node
                added_to_contents = true
            end
        end
        return original_generic(args, ...)
    end
end

local function add_button_setup_option(build, ...)
    if not BUTTON_MAP_FILE then return build(...) end
    building_options, added_to_contents = true, false
    local ok, definition = pcall(build, ...)
    building_options = false
    if not ok then error(definition) end
    if not added_to_contents then
        pcall(append_to_button_list, definition)
    end
    return definition
end

local rebuild_options

G.FUNCS.small_screen_button_setup = function()
    if BUTTON_MAP_FILE then os.remove(BUTTON_MAP_FILE) end
    -- Reopen the menu so the entry reports back, rather than looking unpressed.
    if rebuild_options then
        pcall(function()
            G.FUNCS.overlay_menu{definition = rebuild_options()}
        end)
    end
end

if type(create_UIBox_options) == 'function' then
    local original_options = create_UIBox_options
    rebuild_options = function(...)
        return add_button_setup_option(original_options, ...)
    end
    function create_UIBox_options(...)
        return rebuild_options(...)
    end
elseif G.UIDEF and type(G.UIDEF.options) == 'function' then
    local original_options = G.UIDEF.options
    rebuild_options = function(...)
        return add_button_setup_option(original_options, ...)
    end
    G.UIDEF.options = rebuild_options
end

function set_screen_positions()
    if G.STAGE == G.STAGES.RUN then
        compact_owned_jokers()

        G.deck.T.x = ROOM_W - G.deck.T.w - SAFE_MARGIN
        G.deck.T.y = ROOM_H - G.deck.T.h - BOTTOM_INSET

        -- The reclaimed width goes to the hand, which is the only area whose
        -- cards were overlapping by more than half a card at eight cards. The
        -- area still stops clear of the deck.
        G.hand.T.w = HAND_W
        G.hand.T.x = SAFE_MARGIN +
            math.max(0, (G.deck.T.x - 0.15 - SAFE_MARGIN - G.hand.T.w)/2)
        -- CardArea:move drives the hand to exactly this line, so start it there.
        G.hand.T.y = ROOM_H - G.hand.T.h - BOTTOM_INSET

        G.play.T.x = (ROOM_W - G.play.T.w)/2
        -- 3.6 above the hand on a 4:3 room, but centred in the free band on a
        -- squarer one, where holding that gap would leave a hole in the middle.
        G.play.T.y = math.min(G.hand.T.y - 3.6,
            (RUN_OVERLAY_Y + G.hand.T.y - G.play.T.h)/2)

        G.jokers.T.x = SAFE_MARGIN
        G.jokers.T.y = OWNED_CARDS_Y

        G.consumeables.T.x = ROOM_W - G.consumeables.T.w - SAFE_MARGIN
        G.consumeables.T.y = OWNED_CARDS_Y

        G.discard.T.x = math.min(G.play.T.x + G.play.T.w + 0.15,
            ROOM_W - G.discard.T.w - SAFE_MARGIN)
        G.discard.T.y = G.play.T.y

        G.hand:hard_set_VT()
        G.play:hard_set_VT()
        G.jokers:hard_set_VT()
        G.consumeables:hard_set_VT()
        G.deck:hard_set_VT()
        G.discard:hard_set_VT()
        G.hand:align_cards()
    elseif G.STAGE == G.STAGES.MAIN_MENU and G.title_top then
        G.title_top.T.x = G.TILE_W/2 - G.title_top.T.w/2
        G.title_top.T.y = G.TILE_H/2 - G.title_top.T.h/2 -
            ((G.STATE == G.STATES.DEMO_CTA and 2) or
             (G.debug_splash_size_toggle and 2 or 1.2))
        G.title_top:hard_set_VT()
    end
end

-- Stock tutorial steps are attached to the desktop sidebar and sometimes place
-- Jimbo beyond the left or top edge. Keep the narration in a consistent safe
-- region while retaining each step's highlights, input listener, and snap target.
local original_tutorial_info = tutorial_info

local function append_unique(list, node)
    if not node then return end
    for _, existing in ipairs(list) do
        if existing == node then return end
    end
    list[#list+1] = node
end

local function append_shop_highlights(list)
    append_unique(list, G.shop)
    append_unique(list, G.SHOP_SIGN)
    append_unique(list, G.shop_jokers)
    append_unique(list, G.shop_vouchers)
    append_unique(list, G.shop_booster)
    return list
end

function tutorial_info(args)
    -- Recreate the stock tutorial shade with a real controller shortcut for Skip.
    -- Start is otherwise unused while a tutorial step owns input.
    if not G.OVERLAY_TUTORIAL then
        local overlay_colour = {0.32,0.36,0.41,0}
        ease_value(overlay_colour, 4, 0.6, nil, 'REAL', true, 0.4)
        G.OVERLAY_TUTORIAL = UIBox{
            definition={n=G.UIT.ROOT, config={align='cm', padding=32.05,
                r=0.1, colour=overlay_colour, emboss=0.05}, nodes={
                {n=G.UIT.R, config={align='tr', minh=G.ROOM.T.h,
                    minw=G.ROOM.T.w}, nodes={
                    UIBox_button{
                        id='small_screen_skip_tutorial',
                        label={localize('b_skip')..' >'},
                        button='skip_tutorial_section', minw=1.3, scale=0.45,
                        colour=G.C.JOKER_GREY,
                        focus_args={button='start', set_button_pip=true,
                            orientation='tr'}
                    }
                }}
            }},
            config={align='cm', offset={x=0,y=3.2},
                major=G.ROOM_ATTACH, bond='Weak'}
        }
    end

    args.attach = {
        major=G.ROOM_ATTACH,
        type='cm',
        offset={x=0, y=1.05},
        bond='Weak'
    }
    args.pos = {x=G.TILE_W/2, y=G.TILE_H/2 + 1.05}
    args.align = args.align or 'tm'

    -- The desktop tutorial only redraws one shop card above its dark shade.
    -- On the Brick that reads as an absent shop, so keep the complete storefront
    -- visible and interactive throughout shop tutorial steps.
    if args.text_key and string.sub(args.text_key, 1, 2) == 's_' then
        local original_highlight = args.highlight
        args.highlight = function()
            local list = type(original_highlight) == 'function' and
                original_highlight() or original_highlight or {}
            return append_shop_highlights(list)
        end
    end
    return original_tutorial_info(args)
end

local original_add_speech_bubble = Card_Character.add_speech_bubble
function Card_Character:add_speech_bubble(...)
    local result = original_add_speech_bubble(self, ...)
    if self.children.speech_bubble then
        self.children.speech_bubble:set_alignment({lr_clamp=true})
    end
    return result
end

-- Start opens the pause menu, and closes it again. The stock controller binds
-- that to the escape key alone -- as a gamepad button Start does nothing outside
-- the splash screen -- so on a handheld there is no way to reach it. Two claims
-- come first, in the order the stock handler would resolve them: a tutorial step
-- owns the button while its Skip prompt is up, and any on-screen button that has
-- registered Start keeps it. Menus that refuse the escape key are left closed.
local original_button_press_update = Controller.button_press_update
function Controller:button_press_update(button, dt)
    if button == 'start' and not self.locks.frame then
        if G.OVERLAY_TUTORIAL then
            self.frame_buttonpress = true
            G.FUNCS.skip_tutorial_section()
            return
        end
        local claimed = self.button_registry[button]
        claimed = claimed and claimed[1] and not claimed[1].node.under_overlay
        if not claimed then
            self.frame_buttonpress = true
            if G.STATE == G.STATES.SPLASH then
                G:delete_run()
                G:main_menu()
            elseif not G.OVERLAY_MENU then
                G.FUNCS:options()
            elseif not G.OVERLAY_MENU.config.no_esc then
                G.FUNCS:exit_overlay_menu()
            end
            return
        end
    end
    return original_button_press_update(self, button, dt)
end

local function dyn(ref_table, ref_value, colour, scale, id, extra)
    local config = {
        string = {{ref_table = ref_table, ref_value = ref_value}},
        colours = {colour},
        font = G.LANGUAGES['en-us'].font,
        shadow = true,
        silent = true,
        scale = scale
    }
    local node_config = {id=id}
    if extra then
        for k, v in pairs(extra) do
            if k == 'prefix' then
                config.string[1].prefix = v
            elseif k == 'func' then
                node_config.func = v
            else
                config[k] = v
            end
        end
    end
    node_config.object = DynaText(config)
    return {n=G.UIT.O, config=node_config}
end

-- Largest scale at which a string still fits a given width, mirroring the
-- measurement engine/ui.lua does when it lays a text node out. Relying on the
-- node's own maxw is not enough here: that path rewrites the child's scale in
-- place and only runs when the box is recalculated, while these readouts have
-- funcs that reset their scale on every value change.
local function fit_scale(text, max_w, font, cap)
    font = font or G.LANG.font
    local width = font.FONT:getWidth(text or '')*(font.squish or 1)*
        font.FONTSCALE/G.TILESIZE
    if width <= 0 then return cap end
    return math.min(cap, max_w/width)
end

-- Text height, by the same measurement, is FONT:getHeight()*scale*FONTSCALE*
-- TEXT_HEIGHT_SCALE/TILESIZE. Rows are given a minh above whatever their capped
-- text can reach, so a readout that rescales itself never resizes its row.
local function text_height(scale, font)
    font = font or G.LANG.font
    return font.FONT:getHeight()*scale*font.FONTSCALE*
        font.TEXT_HEIGHT_SCALE/G.TILESIZE
end

-- Hold a DynaText at a fixed size instead of the size the game picks from the
-- value's magnitude or the name's length. Shrinking below the cap to fit the
-- width is fine -- the row is pinned taller than the cap, so a smaller readout
-- simply sits centred in it.
-- A readout that owns its own box.
--
-- Everything in this bar was laid out by measuring text, and that is what kept
-- moving it. A DynaText measures itself; the game rescales it from the value's
-- magnitude; its node takes that size; every container above it follows. Capping
-- the scales, declaring node heights and budgeting the padding each narrowed
-- that path without closing it -- the layout still had a route from the string
-- to the height of the bar.
--
-- These nodes declare a fixed w and h, which calculate_xywh uses instead of
-- measuring anything at all, and the object below draws its own string inside
-- that box: centred, and scaled down only when it would otherwise run past the
-- edge. There is no longer a path from any string to any dimension.
local FixedText = Moveable:extend()

function FixedText:init(W, H, args)
    Moveable.init(self, 0, 0, W, H)
    self.states.collide.can = false
    self.states.hover.can = false
    self.states.click.can = false
    self.states.drag.can = false
    self.font = args.font or G.LANG.font
    self.colour = args.colour or G.C.UI.TEXT_LIGHT
    self.max_scale = args.scale or 0.5
    self.gap = args.gap or 0
    self.parts = {}
    if getmetatable(self) == FixedText then
        table.insert(G.I.MOVEABLE, self)
    end
end

-- Parts are drawn as one line, so a name and its level stay centred together
-- rather than each being centred in a slot of its own.
function FixedText:set_parts(parts)
    for i = 1, #parts do
        local part = self.parts[i]
        if not part then
            part = {text = false, drawable = love.graphics.newText(self.font.FONT, '')}
            self.parts[i] = part
        end
        local text = parts[i].text or ''
        if part.text ~= text then
            part.text = text
            part.drawable:set(text)
            part.width = self.font.FONT:getWidth(text)
        end
        part.colour = parts[i].colour or self.colour
        part.mult = parts[i].mult or 1
    end
    for i = #self.parts, #parts + 1, -1 do self.parts[i] = nil end
end

function FixedText:set_text(text, colour)
    self:set_parts({{text = text, colour = colour}})
end

function FixedText:draw()
    if not self.states.visible then return end
    local font = self.font
    -- Pixels to tiles at scale 1, the same conversion engine/ui.lua uses when it
    -- lays out and draws a text node.
    local unit = font.FONTSCALE/G.TILESIZE
    local natural, shown = 0, 0
    for _, part in ipairs(self.parts) do
        if part.width and part.width > 0 then
            natural = natural + part.width*part.mult
            shown = shown + 1
        end
    end
    if natural <= 0 then return end
    local gaps = math.max(0, shown - 1)*self.gap
    local width = natural*unit
    local scale = math.min(self.max_scale, (self.T.w - gaps)/width)
    local x = 0.5*(self.T.w - width*scale - gaps)

    prep_draw(self, 1)
    for _, part in ipairs(self.parts) do
        if part.width and part.width > 0 then
            -- Each part sits centred on the box's own middle, so a smaller
            -- suffix rides with the text it follows rather than its top edge.
            local part_scale = scale*part.mult
            local height = font.FONT:getHeight()*part_scale*unit*
                font.TEXT_HEIGHT_SCALE
            love.graphics.setColor(part.colour)
            love.graphics.draw(part.drawable,
                x + font.TEXT_OFFSET.x*part_scale*unit,
                0.5*(self.T.h - height) + font.TEXT_OFFSET.y*part_scale*unit,
                0, part_scale*(font.squish or 1)*unit, part_scale*unit)
            x = x + part.width*unit*part_scale + self.gap
        end
    end
    love.graphics.pop()
end

-- The game pulses, quivers and refreshes these objects while a hand is scored.
-- Keep that surface; juice_up already carries the pop, and the rest described
-- per-letter animation that no longer exists here.
function FixedText:pulse(amount)
    self:juice_up(0.4*(amount or 0.2), 0.05)
end
function FixedText:set_quiver() end
function FixedText:update_text() end
function FixedText:align_letters() end

local function pin_dyna_scale(e, text, max_w, cap)
    local obj = e.config.object
    if not obj then return end
    if e.small_screen_fit_text == text and
       e.small_screen_fit_width == max_w and
       e.small_screen_fit_cap == cap then return end
    e.small_screen_fit_text = text
    e.small_screen_fit_width = max_w
    e.small_screen_fit_cap = cap
    local target = fit_scale(text, max_w, obj.font, cap)
    if math.abs((obj.scale or 0) - target) > 0.001 then
        obj.scale = target
        obj:update_text()
    end
end

local function label(text, scale, colour, id)
    return {n=G.UIT.T, config={id=id, text=text, scale=scale,
        colour=colour or G.C.UI.TEXT_LIGHT, shadow=true}}
end

local function gap(width, height)
    return {n=G.UIT.C, config={minw=width or 0.08, minh=height or 0.08}, nodes={}}
end

-- The desktop shop is a two-row panel next to a 4.7x3.1 animated sign that alone
-- is taller than the band this layout has to spend. Keep the game's familiar
-- arrangement -- controls beside the card row, voucher and packs beneath -- drop
-- the sign, and size the panel to fill the band under the owned-card strip.
--
--   +-------------------------------------------+
--   | [ Next  ] | [ card  card  card  card    ] |
--   | [ Reroll] |                               |
--   | [ Ante N voucher ] | [ pack      pack   ] |
--   +-------------------------------------------+
--
-- Every plate holds only R children: the layout engine measures a container that
-- mixes rows and bare objects as if they sat side by side, which is what made the
-- old voucher plate too wide and too short for its contents.
function G.UIDEF.shop()
    local slots = G.GAME.shop.joker_max

    G.shop_jokers = CardArea(0, ROOM_H + 5,
        slots*1.05*G.CARD_W, 1.05*G.CARD_H,
        {card_limit=slots, type='shop', highlight_limit=1})
    G.shop_vouchers = CardArea(0, ROOM_H + 5,
        2.1*G.CARD_W, 1.05*G.CARD_H,
        {card_limit=1, type='shop', highlight_limit=1})
    -- 2.55 card widths leave the two packs just clear of each other.
    G.shop_booster = CardArea(0, ROOM_H + 5,
        2.55*G.CARD_W, 1.15*G.CARD_H,
        {card_limit=2, type='shop', highlight_limit=1,
            card_w=1.27*G.CARD_W})

    -- Keep the global expected by the tutorial, but omit the decorative sign.
    G.SHOP_SIGN = UIBox{
        definition={n=G.UIT.ROOT, config={align='cm', minw=0.01,
            minh=0.01, colour=G.C.CLEAR}, nodes={}},
        config={align='tli', offset={x=-20,y=-20}, major=G.ROOM_ATTACH}
    }
    G.SHOP_SIGN.states.visible = false

    local function plate(width, nodes)
        return {n=G.UIT.C, config={align='cm', padding=0.15, minw=width,
            r=0.15, colour=G.C.L_BLACK, emboss=0.05}, nodes=nodes}
    end

    local function area_row(area)
        return {n=G.UIT.R, config={align='cm'}, nodes={
            {n=G.UIT.O, config={object=area}}
        }}
    end

    local controls = {n=G.UIT.C, config={align='cm', padding=0.08}, nodes={
        {n=G.UIT.R, config={id='next_round_button', align='cm', minw=3.0,
            minh=1.45, padding=0.06, r=0.14, colour=G.C.RED,
            one_press=true, button='toggle_shop', hover=true, shadow=true}, nodes={
            {n=G.UIT.R, config={align='cm', padding=0.04,
                focus_args={button='y', orientation='cr'}, func='set_button_pip'}, nodes={
                {n=G.UIT.R, config={align='cm', maxw=2.5}, nodes={
                    label(localize('b_next_round_1'), 0.42)
                }},
                {n=G.UIT.R, config={align='cm', maxw=2.5}, nodes={
                    label(localize('b_next_round_2'), 0.42)
                }}
            }}
        }},
        {n=G.UIT.R, config={align='cm', minw=3.0, minh=1.5,
            padding=0.06, r=0.14, colour=G.C.GREEN,
            button='reroll_shop', func='can_reroll', hover=true, shadow=true}, nodes={
            {n=G.UIT.R, config={align='cm', padding=0.04,
                focus_args={button='x', orientation='cr'}, func='set_button_pip'}, nodes={
                {n=G.UIT.R, config={align='cm', maxw=2.5}, nodes={
                    label(localize('k_reroll'), 0.42)
                }},
                {n=G.UIT.R, config={align='cm'}, nodes={
                    label(localize('$'), 0.5),
                    {n=G.UIT.T, config={ref_table=G.GAME.current_round,
                        ref_value='reroll_cost', scale=0.6, colour=G.C.WHITE,
                        shadow=true}}
                }}
            }}
        }}
    }}

    -- A shelf that stays wider than its cards reads as a shop with room on it,
    -- and keeps the panel steady when a Voucher raises the slot count.
    local card_shelf = plate(math.max(7.9, G.shop_jokers.T.w + 1.4), {
        area_row(G.shop_jokers)
    })

    local voucher = plate(nil, {
        {n=G.UIT.R, config={align='cm', maxw=G.shop_vouchers.T.w}, nodes={
            {n=G.UIT.T, config={text=localize{type='variable',
                key='ante_x_voucher', vars={G.GAME.round_resets.ante}},
                scale=0.3, colour=G.C.UI.TEXT_LIGHT, shadow=true}}
        }},
        area_row(G.shop_vouchers)
    })

    local boosters = plate(nil, {area_row(G.shop_booster)})

    -- Only maxh: when a node carries both, an overflow in either direction is
    -- resolved against maxw, which would scale a panel narrower than the room
    -- up rather than down. maxh alone shrinks the panel to fit the band.
    return {n=G.UIT.ROOT, config={align='cm', padding=0.03,
        maxh=ROOM_H-RUN_OVERLAY_Y-SAFE_MARGIN,
        colour=G.C.CLEAR}, nodes={
        {n=G.UIT.R, config={align='cm', padding=0.08, r=0.16,
            colour=G.C.DYN_UI.BOSS_MAIN, emboss=0.05}, nodes={
            {n=G.UIT.R, config={align='cm', padding=0.06}, nodes={
                controls, card_shelf
            }},
            {n=G.UIT.R, config={align='cm', padding=0.06}, nodes={
                voucher, boosters
            }}
        }}
    }}
end

-- Retain the stock blind cards and callbacks, but give the selector the full room
-- width and a hard vertical budget below the owned-card strip. The prompt remains
-- in the HUD's blind cell, scaled to that cell instead of spilling across the bar.
local original_blind_select_uidef = create_UIBox_blind_select
function create_UIBox_blind_select(...)
    local result = original_blind_select_uidef(...)
    result.config.minw = ROOM_W - SAFE_MARGIN*2
    result.config.maxw = ROOM_W - SAFE_MARGIN*2
    result.config.maxh = ROOM_H - RUN_OVERLAY_Y - SAFE_MARGIN
    if result.nodes and result.nodes[1] and result.nodes[1].config then
        result.nodes[1].config.padding = 0.12
    end
    if G.blind_prompt_box then
        G.blind_prompt_box.UIRoot.config.maxw = HUD_BLIND_W - 0.2
        G.blind_prompt_box.UIRoot.config.maxh = 1.5
        G.blind_prompt_box:recalculate()
    end
    return result
end

-- A single horizontal status bar replaces the desktop HUD's tall left sidebar.
-- All IDs used by scoring, easing, tutorials, and blind logic are preserved.
function create_UIBox_HUD()
    local panel = G.C.DYN_UI.BOSS_MAIN
    local inset = G.C.DYN_UI.BOSS_DARK
    -- Measured, not guessed: the numeric readouts are built with the en-us font
    -- whatever the profile language is, and the hand name uses the profile's.
    local numeric = G.LANGUAGES['en-us'].font
    local score_row_h = text_height(SCORE_SCALE, numeric) + 0.04
    local target_row_h = text_height(TARGET_SCALE) + 0.04
    local dollars_box_h = text_height(DOLLARS_SCALE, numeric) + 0.08

    -- Hand readout boxes. Each of these is a declared size: the row heights are
    -- the text heights they were built for, and nothing measured contributes.
    local name_box_w = HUD_HAND_W - 0.06
    local name_box_h = text_height(HAND_TEXT_SCALE)
    local num_text_w = HAND_NUM_BOX_W - 2*HAND_BOX_PAD
    local num_text_h = text_height(HAND_NUM_SCALE, numeric)
    local num_box_h = num_text_h + 2*HAND_BOX_PAD
    -- Every term here is declared, so this is the cell's height, not a budget
    -- it might exceed. All four cells take it, which keeps the panels level.
    local row_h = math.max(HUD_ROW_H, name_box_h + num_box_h + 0.06 + 0.09)

    local hand_line_text = FixedText(name_box_w, name_box_h,
        {scale=HAND_TEXT_SCALE, gap=0.1})
    local hand_chips_text = FixedText(num_text_w, num_text_h,
        {scale=HAND_NUM_SCALE, font=numeric})
    local hand_mult_text = FixedText(num_text_w, num_text_h,
        {scale=HAND_NUM_SCALE, font=numeric})

    local blind_slot = {n=G.UIT.C, config={
        id='row_blind', align='cm', minw=HUD_BLIND_W, minh=row_h,
        r=0.1, colour=inset
    }, nodes={}}

    -- Score and requirement belong to each other: the number you have over the
    -- number you need. Both readouts fit themselves to SCORE_TEXT_W, so a seven
    -- digit score cannot widen the cell and push the bar past the margins.
    local score = {n=G.UIT.C, config={
        id='row_dollars_chips', align='cm', minw=HUD_SCORE_W, minh=row_h,
        padding=0.06, r=0.1, colour=panel, emboss=0.05
    }, nodes={
        {n=G.UIT.R, config={align='cm', minw=HUD_SCORE_W-0.12, minh=score_row_h,
            r=0.08, colour=inset}, nodes={
            {n=G.UIT.T, config={ref_table=G.GAME, ref_value='chips_text',
                lang=G.LANGUAGES['en-us'], scale=SCORE_SCALE, colour=G.C.WHITE,
                id='chip_UI_count', func='chip_UI_set', shadow=true,
                no_recalc=true}}
        }},
        {n=G.UIT.R, config={align='cm', minh=target_row_h}, nodes={
            {n=G.UIT.T, config={id='small_screen_blind_target',
                ref_table={val=''}, ref_value='val', scale=TARGET_SCALE,
                colour=G.C.RED, shadow=true, func='small_screen_blind_target',
                no_recalc=true}}
        }}
    }}

    local current_hand = {n=G.UIT.C, config={
        id='hand_text_area', align='cm', minw=HUD_HAND_W, minh=row_h,
        padding=0.03, r=0.1, colour=darken(G.C.BLACK, 0.1), emboss=0.05
    }, nodes={
        -- The hand name and its level on one line, then the chips and mult in
        -- their plates. Every node here carries its own w and h, so the cell is
        -- the same size whatever a hand is called and however large its numbers
        -- get -- the strings live inside the boxes rather than defining them.
        {n=G.UIT.R, config={align='cm', minh=name_box_h}, nodes={
            {n=G.UIT.O, config={id='hand_name', w=name_box_w, h=name_box_h,
                object=hand_line_text, func='small_screen_hand_line'}},
            -- The game reaches for these two by ID: it pulses the hand total
            -- through the object of one and colours the level through the
            -- config of the other. start_run points the total at hand_name.
            {n=G.UIT.B, config={id='hand_chip_total', w=0, h=0}},
            {n=G.UIT.B, config={id='hand_level', w=0, h=0,
                colour=G.C.UI.TEXT_LIGHT}}
        }},
        {n=G.UIT.R, config={align='cm', minh=num_box_h, padding=0.03}, nodes={
            {n=G.UIT.C, config={id='hand_chip_area', align='cm',
                minw=HAND_NUM_BOX_W, minh=num_box_h, padding=HAND_BOX_PAD,
                r=0.08, colour=G.C.UI_CHIPS, emboss=0.05}, nodes={
                {n=G.UIT.O, config={id='flame_chips', func='flame_handler',
                    no_role=true, object=Moveable(0,0,0,0), w=0, h=0}},
                {n=G.UIT.O, config={id='hand_chips', w=num_text_w, h=num_text_h,
                    object=hand_chips_text, func='hand_chip_UI_set'}}
            }},
            gap(0.08),
            label('X', 0.55, G.C.UI_MULT),
            gap(0.08),
            {n=G.UIT.C, config={id='hand_mult_area', align='cm',
                minw=HAND_NUM_BOX_W, minh=num_box_h, padding=HAND_BOX_PAD,
                r=0.08, colour=G.C.UI_MULT, emboss=0.05}, nodes={
                {n=G.UIT.O, config={id='flame_mult', func='flame_handler',
                    no_role=true, object=Moveable(0,0,0,0), w=0, h=0}},
                {n=G.UIT.O, config={id='hand_mult', w=num_text_w, h=num_text_h,
                    object=hand_mult_text, func='hand_mult_UI_set'}}
            }}
        }}
    }}

    local meta = {n=G.UIT.C, config={align='cm', minw=HUD_META_W, minh=row_h,
        padding=0.07, r=0.1, colour=panel, emboss=0.05}, nodes={
        {n=G.UIT.R, config={align='cm', minh=0.72}, nodes={
            {n=G.UIT.C, config={align='cm', minw=1.3, minh=dollars_box_h,
                padding=0.03, r=0.08, colour=inset}, nodes={
                dyn(G.GAME, 'dollars', G.C.MONEY, DOLLARS_SCALE, 'dollar_text_UI',
                    {prefix=localize('$'), bump=true,
                        func='small_screen_dollars'})
            }},
            gap(0.06),
            {n=G.UIT.C, config={id='hud_hands', align='cm', minw=1.0,
                minh=0.66, padding=0.03, r=0.08, colour=inset}, nodes={
                label('H', 0.32, G.C.BLUE),
                gap(0.04),
                dyn(G.GAME.current_round, 'hands_left', G.C.BLUE, 0.54, 'hand_UI_count')
            }},
            gap(0.06),
            {n=G.UIT.C, config={align='cm', minw=1.0, minh=0.66,
                padding=0.03, r=0.08, colour=inset}, nodes={
                label('D', 0.32, G.C.RED),
                gap(0.04),
                dyn(G.GAME.current_round, 'discards_left', G.C.RED, 0.54, 'discard_UI_count')
            }}
        }},
        {n=G.UIT.R, config={align='cm', minh=0.72}, nodes={
            {n=G.UIT.C, config={id='hud_ante', align='cm', minw=1.72,
                minh=0.66, padding=0.03, r=0.08, colour=inset}, nodes={
                label('A', 0.32, G.C.IMPORTANT),
                gap(0.04),
                dyn(G.GAME.round_resets, 'ante', G.C.IMPORTANT, 0.54, 'ante_UI_count'),
                label('/', 0.28),
                {n=G.UIT.T, config={ref_table=G.GAME, ref_value='win_ante',
                    scale=0.32, colour=G.C.WHITE, shadow=true}}
            }},
            gap(0.06),
            {n=G.UIT.C, config={align='cm', minw=1.14, minh=0.66,
                padding=0.03, r=0.08, colour=inset}, nodes={
                label('R', 0.32, G.C.IMPORTANT),
                gap(0.04),
                dyn(G.GAME, 'round', G.C.IMPORTANT, 0.54, 'round_UI_count')
            }},
            gap(0.06),
            {n=G.UIT.C, config={id='run_info_button', align='cm', minw=0.48,
                minh=0.66, padding=0.03, r=0.08, colour=G.C.RED,
                hover=true, button='run_info', shadow=true,
                focus_args={button=G.F_GUIDE and 'guide' or 'back', orientation='bm'}}, nodes={
                label('i', 0.34)
            }}
        }}
    }}

    -- No backing plate: each cell carries its own panel, so a strip behind them
    -- only greys out the table. minw still spans the room to keep the row
    -- centred on the same line whatever the cells measure.
    return {n=G.UIT.ROOT, config={align='cm', padding=0.06, minw=ROOM_W-SAFE_MARGIN*2,
        colour=G.C.CLEAR}, nodes={
        {n=G.UIT.R, config={id='row_round', align='cm', padding=0.06,
            r=0.1, colour=G.C.CLEAR}, nodes={
            blind_slot, gap(0.1), score, gap(0.1),
            current_hand, gap(0.1), meta
        }}
    }}
end

-- The requirement moved to the score cell, so this panel is now identity only:
-- the blind's chip beside its name, with the debuff lines under it. That matters
-- for more than tidiness. HUD_blind_debuff forces each debuff row to 0.35 with
-- 0.36 text, so the old four-row panel measured 2.29 against a 1.72 slot: it was
-- centred on the slot, and its bottom row -- the score you needed -- was drawn
-- underneath the Joker strip. Three rows fit the slot with the debuffs shown,
-- and collapse to the name alone when a blind has none.
function create_UIBox_HUD_blind()
    local box_w = HUD_BLIND_W - 0.12
    local inner_w = box_w - 0.12
    G.GAME.blind:change_dim(0.62, 0.62)
    local hidden_reward = {text=''}
    return {n=G.UIT.ROOT, config={id='HUD_blind', func='HUD_blind_visible',
        align='cm', minw=box_w, maxw=box_w, minh=1.5,
        padding=0.05, r=0.1,
        colour=G.C.BLACK, emboss=0.05}, nodes={
        {n=G.UIT.R, config={align='cm', minh=text_height(BLIND_NAME_SCALE) + 0.08,
            maxw=inner_w, r=0.08,
            padding=0.03, colour=G.C.DYN_UI.MAIN}, nodes={
            {n=G.UIT.O, config={object=G.GAME.blind, draw_layer=1}},
            {n=G.UIT.O, config={id='HUD_blind_name',
                func='small_screen_blind_name', object=DynaText({
                string={{ref_table=G.GAME.blind, ref_value='loc_name'}},
                colours={G.C.UI.TEXT_LIGHT}, shadow=true, rotate=true,
                silent=true, float=true, scale=BLIND_NAME_SCALE, y_offset=-2})}}
        }},
        {n=G.UIT.R, config={align='cm', minh=0.27, maxw=inner_w,
            colour=G.C.DYN_UI.DARK}, nodes={
            {n=G.UIT.T, config={ref_table={val=''}, ref_value='val', scale=0.31,
                colour=G.C.UI.TEXT_LIGHT, func='HUD_blind_debuff_prefix'}},
            {n=G.UIT.T, config={id='HUD_blind_debuff_1',
                ref_table=G.GAME.blind.loc_debuff_lines, ref_value=1,
                scale=0.31, colour=G.C.UI.TEXT_LIGHT, func='HUD_blind_debuff'}}
        }},
        {n=G.UIT.R, config={align='cm', minh=0.27, maxw=inner_w,
            colour=G.C.DYN_UI.DARK}, nodes={
            {n=G.UIT.T, config={id='HUD_blind_debuff_2',
                ref_table=G.GAME.blind.loc_debuff_lines, ref_value=2,
                scale=0.31, colour=G.C.UI.TEXT_LIGHT, func='HUD_blind_debuff'}}
        }},
        -- Blind.lua drives both of these IDs during its reveal animation, and
        -- hides dollars_to_be_earned by way of its grandparent node -- so keep
        -- them, nested deep enough that the hidden grandparent is this dead row
        -- and not the panel itself. HUD_blind_count keeps no scaling func: it is
        -- the score cell that shows the requirement now.
        {n=G.UIT.R, config={align='cm', minh=0.001}, nodes={
            {n=G.UIT.C, config={align='cm'}, nodes={
                {n=G.UIT.T, config={id='HUD_blind_count', ref_table=G.GAME.blind,
                    ref_value='chip_text', scale=0.001, colour=G.C.CLEAR,
                    no_recalc=true}},
                {n=G.UIT.O, config={id='dollars_to_be_earned', object=DynaText({
                    string={{ref_table=hidden_reward, ref_value='text'}},
                    colours={G.C.CLEAR}, silent=true, scale=0.01})}}
            }}
        }}
    }}
end

-- Requirement readout for the score cell. Balatro already formats the target on
-- the blind itself, so this only decides when it is meaningful to show. A slash
-- rather than a localized "score at least": the cell is 2.6 tiles wide, and the
-- number has to stay the thing you read.
G.FUNCS.small_screen_blind_target = function(e)
    local blind = G.GAME.blind
    local active = blind and blind.blind_set and blind.name and blind.name ~= ''
    local text = active and ('/ '..(blind.chip_text or '')) or ''
    if e.small_screen_target_text == text then return end
    e.small_screen_target_text = text
    e.config.ref_table.val = text
    e.config.scale = fit_scale(text, SCORE_TEXT_W,
        (e.config.lang or G.LANG).font, TARGET_SCALE)
end

-- scale_number keeps the round score roughly six characters wide, which the
-- desktop sidebar has room for and this cell does not. Cap it by measurement so
-- the number shrinks to its box instead of the box growing into the margin.
local original_chip_UI_set = G.FUNCS.chip_UI_set
G.FUNCS.chip_UI_set = function(e)
    local previous = G.GAME.chips_text
    original_chip_UI_set(e)
    if e.small_screen_chip_text ~= G.GAME.chips_text or
       previous ~= G.GAME.chips_text then
        e.small_screen_chip_text = G.GAME.chips_text
        e.config.scale = fit_scale(G.GAME.chips_text, SCORE_TEXT_W,
            (e.config.lang or G.LANG).font, e.config.scale)
    end
end

-- The hand readout is fed strings; its boxes were sized when the HUD was built.
-- The stock funcs still run first for their bookkeeping and their scoring juice
-- -- the scale they write lands on a field FixedText ignores.
--
-- One object owns the line: the selected hand's name, or its final total once
-- the hand has been submitted, followed by the level in whatever colour the game
-- has assigned it. The stock pair of texts cannot overlap because there is only
-- one of them.
G.FUNCS.small_screen_hand_line = function(e)
    local hand = G.GAME.current_round.current_hand
    if hand.handname ~= hand.handname_text then
        hand.handname_text = hand.handname
    end
    local total = ''
    if type(hand.chip_total) == 'number' and hand.chip_total >= 1 then
        total = number_format(hand.chip_total)
    end
    hand.chip_total_text = total

    local primary = hand.handname_text
    if primary == nil or primary == '' then primary = total end
    local level_node = G.hand_text_area and G.hand_text_area.hand_level
    e.config.object:set_parts({
        {text=primary},
        {text=hand.hand_level, mult=HAND_LEVEL_MULT,
            colour=level_node and level_node.config.colour or nil}
    })
end

local original_hand_chip_UI_set = G.FUNCS.hand_chip_UI_set
G.FUNCS.hand_chip_UI_set = function(e)
    original_hand_chip_UI_set(e)
    e.config.object:set_text(G.GAME.current_round.current_hand.chip_text)
end

local original_hand_mult_UI_set = G.FUNCS.hand_mult_UI_set
G.FUNCS.hand_mult_UI_set = function(e)
    original_hand_mult_UI_set(e)
    e.config.object:set_text(G.GAME.current_round.current_hand.mult_text)
end

-- DynaText only applies its own maxw when it is constructed, so the money and
-- blind name readouts need the same treatment to stay inside their panels.
G.FUNCS.small_screen_dollars = function(e)
    pin_dyna_scale(e, localize('$')..tostring(G.GAME.dollars or 0),
        DOLLARS_W, DOLLARS_SCALE)
end

G.FUNCS.small_screen_blind_name = function(e)
    pin_dyna_scale(e, (G.GAME.blind and G.GAME.blind.loc_name) or '',
        BLIND_NAME_W, BLIND_NAME_SCALE)
end

-- Move the compact HUD to the top after the run objects have been created.
local original_start_run = Game.start_run
function Game:start_run(...)
    local result = original_start_run(self, ...)
    -- update_hand_text pulses the hand total through its object. There is no
    -- separate total text any more, so point that lookup at the line itself.
    if G.hand_text_area and G.hand_text_area.handname then
        G.hand_text_area.chip_total = G.hand_text_area.handname
    end
    if self.HUD then
        self.HUD:set_alignment({major=G.ROOM_ATTACH, type='tmi',
            offset={x=0, y=SAFE_MARGIN}, bond='Strong'})
        self.HUD:align_to_major()
        self.HUD:recalculate()
    end
    return result
end

-- The cash-out screen, the booster packs and the deck preview are all centred on
-- the hand by the stock game, which is the same thing as the screen centre on a
-- desktop layout. Here it is not: the hand shares its row with the deck, so it
-- sits left of centre to clear it, and everything anchored to it inherited that
-- offset. Nudge those boxes back to the middle of the room without touching the
-- vertical placement or the entrance animations the game drives through it.
local function centre_on_room(box)
    if not box or not G.hand then return end
    local shift = ROOM_W/2 - (G.hand.T.x + G.hand.T.w/2)
    if math.abs(box.alignment.offset.x - shift) > 0.001 then
        box.alignment.offset.x = shift
        box:align_to_major()
    end
end

local function pin_run_overlay(box, y, x)
    if not box then return end
    box:set_alignment({major=G.ROOM_ATTACH, type='tmi',
        offset={x=x or 0, y=y}, bond='Strong'})
    -- Source transitions rewrite the offset after constructing these boxes. Force
    -- a fresh alignment so the desktop animation cannot pull them under Jokers.
    box.alignment.prev_type = nil
    box:align_to_major()
    box:hard_set_VT()
end

-- Centre the panel in the space that is actually free: the whole content band
-- vertically, and everything left of the deck horizontally, so it is never
-- crowded against the card stack. Measured once per shop so the pin cannot
-- jitter, and it falls back to the top of the band if the panel is oversized.
local shop_pin_box, shop_pin_x, shop_pin_y
local function shop_pin()
    if G.shop ~= shop_pin_box then
        shop_pin_box, shop_pin_x, shop_pin_y = G.shop, nil, nil
    end
    if not shop_pin_y then
        local w = (G.shop and G.shop.T.w) or 0
        local h = (G.shop and G.shop.T.h) or 0
        local deck_x = (G.deck and G.deck.T.x) or (ROOM_W - SAFE_MARGIN)
        local band_bottom = ROOM_H - SAFE_MARGIN

        shop_pin_x = math.min(0, (SAFE_MARGIN + deck_x - 0.15)/2 - ROOM_W/2)
        shop_pin_x = math.max(shop_pin_x, SAFE_MARGIN + w/2 - ROOM_W/2)

        shop_pin_y = RUN_OVERLAY_Y
        if h > 0 and h < band_bottom - RUN_OVERLAY_Y then
            shop_pin_y = RUN_OVERLAY_Y + (band_bottom - RUN_OVERLAY_Y - h)/2
        end
    end
    return shop_pin_x, shop_pin_y
end

-- The shop transition normally targets a negative offset relative to the hand.
-- Re-pin the panel on every shop frame, since a queued desktop entrance event
-- also rewrites its offset shortly after construction.
local original_update_shop = Game.update_shop
function Game:update_shop(dt)
    local result = original_update_shop(self, dt)
    if G.shop then
        local x, y = shop_pin()
        pin_run_overlay(G.shop, y, x)
    end
    if G.SHOP_SIGN then G.SHOP_SIGN.states.visible = false end
    return result
end

-- Blind selection gets the same explicit lower content zone. Owned Jokers and
-- consumables remain visible for decision-making, but can no longer cover a blind.
-- Cash out, the five booster pack types, and the deck preview. Each keeps the
-- vertical placement and the slide-in the stock game gives it; only the
-- horizontal centring is corrected.
local original_update_round_eval = Game.update_round_eval
function Game:update_round_eval(dt)
    local result = original_update_round_eval(self, dt)
    centre_on_room(G.round_eval)
    return result
end

for _, pack in ipairs({'arcana', 'spectral', 'standard', 'buffoon', 'celestial'}) do
    local name = 'update_'..pack..'_pack'
    local original = Game[name]
    Game[name] = function(self, dt)
        local result = original(self, dt)
        centre_on_room(G.booster_pack)
        return result
    end
end

local original_update_selecting_hand = Game.update_selecting_hand
function Game:update_selecting_hand(dt)
    local result = original_update_selecting_hand(self, dt)
    centre_on_room(G.deck_preview)
    return result
end

local original_update_blind_select = Game.update_blind_select
function Game:update_blind_select(dt)
    local result = original_update_blind_select(self, dt)
    -- The selector carries 0.12 of padding above its cards, so pin it that much
    -- higher than the band top: the blinds start exactly under the owned cards
    -- and the skip tags stay inside the bottom margin. Its own height cannot be
    -- measured -- each column is padded to a fixed ten tiles for the pop-up
    -- animation -- so a taller band is shared out from the known content height.
    if G.blind_select then
        local band = ROOM_H - SAFE_MARGIN - RUN_OVERLAY_Y
        pin_run_overlay(G.blind_select, RUN_OVERLAY_Y - 0.12 +
            math.max(0, (band - BLIND_SELECT_H)/2))
    end
    return result
end

-- Card descriptions are the smallest important text in the desktop UI. Increase
-- only text nodes in freshly generated ability tables, leaving menu geometry and
-- dynamic score text alone.
local function enlarge_description_text(node)
    if type(node) ~= 'table' then return end
    if node.n == G.UIT.T and node.config and node.config.scale then
        node.config.scale = math.min(0.52, node.config.scale*1.22)
    end
    if node.nodes then
        for _, child in ipairs(node.nodes) do enlarge_description_text(child) end
    elseif not node.config then
        for _, child in ipairs(node) do enlarge_description_text(child) end
        for _, key in ipairs({'main', 'info', 'name', 'type'}) do
            if node[key] then enlarge_description_text(node[key]) end
        end
    end
end

local original_ability_table = Card.generate_UIBox_ability_table
function Card:generate_UIBox_ability_table(...)
    local result = original_ability_table(self, ...)
    enlarge_description_text(result)
    return result
end

-- Keep transient UI inside the logical room. The stock engine only supports a
-- horizontal clamp, so tall controller-hover descriptions can still escape above
-- the HUD or below the bottom edge on a 4:3 screen.
local function clamp_popup_to_room(box)
    local max_x = math.max(SAFE_MARGIN, G.ROOM.T.w - box.T.w - SAFE_MARGIN)
    local max_y = math.max(SAFE_MARGIN, G.ROOM.T.h - box.T.h - SAFE_MARGIN)
    box.T.x = math.min(math.max(box.T.x, SAFE_MARGIN), max_x)
    box.T.y = math.min(math.max(box.T.y, SAFE_MARGIN), max_y)

    local visual_max_x = math.max(SAFE_MARGIN,
        G.ROOM.T.w - box.VT.w - SAFE_MARGIN)
    local visual_max_y = math.max(SAFE_MARGIN,
        G.ROOM.T.h - box.VT.h - SAFE_MARGIN)
    box.VT.x = math.min(math.max(box.VT.x, SAFE_MARGIN), visual_max_x)
    box.VT.y = math.min(math.max(box.VT.y, SAFE_MARGIN), visual_max_y)
end

local original_uibox_move = UIBox.move
function UIBox:move(dt)
    if self.config and self.config.instance_type == 'POPUP' then
        Moveable.move(self, dt)
        clamp_popup_to_room(self)
        Moveable.move(self.UIRoot, dt)
        return
    end
    return original_uibox_move(self, dt)
end

-- Unlock notifications use the desktop room's fixed width (20 logical tiles),
-- which is wider than this layout. Preserve the banner look with safe side margins.
local original_notify_alert = create_UIBox_notify_alert
function create_UIBox_notify_alert(...)
    local result = original_notify_alert(...)
    local function fit_banner(node)
        if type(node) ~= 'table' then return end
        if node.config and node.config.minw and node.config.minw > ROOM_W then
            node.config.minw = ROOM_W - SAFE_MARGIN*2
        end
        if node.nodes then
            for _, child in ipairs(node.nodes) do fit_banner(child) end
        end
    end
    fit_banner(result)
    return result
end

-- Mark card descriptions for the engine-wide popup clamp, especially the leftmost
-- shop slot, top-row Jokers, and rightmost consumable.
local original_align_h_popup = Card.align_h_popup
function Card:align_h_popup(...)
    local result = original_align_h_popup(self, ...)
    result.lr_clamp = true
    return result
end

-- Keep the RNG stream and the particle system's logical capacity exactly as the
-- stock game expects, but make every third visual particle a lightweight ghost.
-- Creation still consumes every random value; ghosts age out on the same frame,
-- while avoiding movement math and draw calls for one third of the density.
local PERF_OPTIMIZATIONS = os.getenv('BALATRO_PM_PERF_OPTIMIZATIONS') ~= '0'
if PERF_OPTIMIZATIONS then
-- A DynaText normally walks and realigns every glyph on every update. Reduced
-- motion suppresses all continuous glyph animation, so static strings only need
-- alignment on their first update or after their text changes. Pop timing and
-- multi-string cycles keep the original per-frame path until they settle.
local original_dyna_text_update = DynaText.update
function DynaText:update(dt)
    if not G.SETTINGS.reduced_motion then
        return original_dyna_text_update(self, dt)
    end

    local focused = self.strings[self.focused_string]
    local previous_string = focused and focused.string
    self:update_text()
    focused = self.strings[self.focused_string]
    local current_string = focused and focused.string
    if not self.small_screen_letters_aligned or
       previous_string ~= current_string or self.config.pop_in or
       self.config.pop_out or self.pop_cycle then
        self:align_letters()
        self.small_screen_letters_aligned = true
    else
        self.string = current_string
    end
end

-- UI object nodes force their DynaText child to recalculate movement every
-- frame. Once the node has updated, release that force: normal parent movement,
-- text-size changes, alignment changes, and juice still wake Moveable itself.
local original_ui_element_update_object = UIElement.update_object
function UIElement:update_object(...)
    local result = original_ui_element_update_object(self, ...)
    local object = self.config.object
    if G.SETTINGS.reduced_motion and object and
       getmetatable(object) == DynaText then
        object.config.refresh_movement = false
    end
    return result
end

-- Settled face-down cards in the live draw pile need no per-card tooltip or
-- status maintenance. Resume the full update immediately for a flip, deck
-- inspection, focus, or as soon as a card moves to any other area. Permanent
-- debuffs remain enforced; deck/card-area input handling is unchanged.
local original_card_update = Card.update
function Card:update(dt)
    if G.SETTINGS.reduced_motion and self.area == G.deck and
       not G.VIEWING_DECK and self.facing == 'back' and
       self.sprite_facing == 'back' and not self.pinch.x and
       not self.states.focus.is and not self.children.focused_ui then
        if self.ability and self.ability.perma_debuff then self.debuff = true end
        return
    end
    return original_card_update(self, dt)
end

-- Once the draw pile and all of its cards have settled, its absolute target
-- positions are unchanged. Avoid rewriting every buried card's target each
-- frame, but invalidate immediately for pile motion, shuffling, count changes,
-- dragging, a face-up card, or deck inspection.
local original_cardarea_align_cards = CardArea.align_cards
function CardArea:align_cards(...)
    if not (G.SETTINGS.reduced_motion and self == G.deck and
            not G.VIEWING_DECK and (self.shuffle_amt or 0) == 0) then
        return original_cardarea_align_cards(self, ...)
    end

    local cache = self.small_screen_deck_alignment
    local stable = cache and cache.count == #self.cards and
        cache.x == self.T.x and cache.y == self.T.y and
        cache.w == self.T.w and cache.h == self.T.h
    if stable then
        for i = 1, #self.cards do
            local card = self.cards[i]
            if card.states.drag.is or card.facing == 'front' or
               not card.STATIONARY then
                stable = false
                break
            end
        end
    end
    if stable then return end

    local result = original_cardarea_align_cards(self, ...)
    self.small_screen_deck_alignment = cache or {}
    cache = self.small_screen_deck_alignment
    cache.count, cache.x, cache.y = #self.cards, self.T.x, self.T.y
    cache.w, cache.h = self.T.w, self.T.h
    return result
end

local original_particles_update = Particles.update
function Particles:update(dt)
    local old_count = #self.particles
    local result = original_particles_update(self, dt)
    for i = old_count + 1, #self.particles do
        self.small_screen_particle_sequence =
            (self.small_screen_particle_sequence or 0) + 1
        if self.small_screen_particle_sequence % 3 == 0 then
            self.particles[i].small_screen_ghost = true
            self.particles[i].draw = false
        end
    end
    return result
end

function Particles:move(dt)
    if G.SETTINGS.paused and not self.created_on_pause then return end

    Moveable.move(self, dt)
    if self.timer_type ~= 'REAL' then dt = dt*G.SPEEDFACTOR end

    for i = #self.particles, 1, -1 do
        local particle = self.particles[i]
        particle.age = particle.age + dt

        if particle.small_screen_ghost then
            particle.draw = false
            if particle.age > self.lifespan then
                table.remove(self.particles, i)
            end
        else
            particle.draw = true
            particle.e_vel = particle.e_vel or dt*self.scale
            particle.e_prev = particle.e_curr
            particle.e_curr = math.min(2*math.min(
                (particle.age/self.lifespan)*self.scale,
                self.scale*((self.lifespan - particle.age)/self.lifespan)),
                self.scale)
            particle.e_vel = (particle.e_curr - particle.e_prev)*self.scale*dt +
                (1-self.scale*dt)*particle.e_vel
            particle.scale = particle.scale + particle.e_vel
            particle.scale = math.min(2*math.min(
                (particle.age/self.lifespan)*self.scale,
                self.scale*((self.lifespan - particle.age)/self.lifespan)),
                self.scale)

            if particle.scale < 0 then
                table.remove(self.particles, i)
            else
                particle.offset.x = particle.offset.x +
                    particle.velocity*math.sin(particle.dir)*dt
                particle.offset.y = particle.offset.y +
                    particle.velocity*math.cos(particle.dir)*dt
                particle.facing = particle.facing + particle.r_vel*dt
                particle.velocity = math.max(0,
                    particle.velocity - particle.velocity*0.07*dt)
            end
        end
    end
end
end

-- With reduced motion, REAL_SHADER is fixed at 300 and the background's spin
-- settles to a constant. Render that stable two-iteration shader once and reuse
-- one normal-format framebuffer until any shader input changes. Palette eases
-- still render live into the cache on every changed frame, then settle again.
local background_cache = {
    canvas = nil,
    width = 0,
    height = 0,
    disabled_width = 0,
    disabled_height = 0,
    key = {},
}

local function release_background_cache()
    if background_cache.canvas then
        background_cache.canvas:release()
        background_cache.canvas = nil
    end
    background_cache.width = 0
    background_cache.height = 0
    background_cache.key[1] = nil
end

local function background_values_match(width, height)
    local key = background_cache.key
    local colours = G.C.BACKGROUND
    return key[1] == width and key[2] == height and
        key[3] == G.TIMERS.REAL_SHADER and key[4] == G.TIMERS.BACKGROUND and
        key[5] == colours.contrast and key[6] == G.ARGS.spin.amount and
        key[7] == colours.C[1] and key[8] == colours.C[2] and
        key[9] == colours.C[3] and key[10] == colours.C[4] and
        key[11] == colours.L[1] and key[12] == colours.L[2] and
        key[13] == colours.L[3] and key[14] == colours.L[4] and
        key[15] == colours.D[1] and key[16] == colours.D[2] and
        key[17] == colours.D[3] and key[18] == colours.D[4]
end

local function remember_background_values(width, height)
    local key = background_cache.key
    local colours = G.C.BACKGROUND
    key[1], key[2] = width, height
    key[3], key[4] = G.TIMERS.REAL_SHADER, G.TIMERS.BACKGROUND
    key[5], key[6] = colours.contrast, G.ARGS.spin.amount
    key[7], key[8], key[9], key[10] =
        colours.C[1], colours.C[2], colours.C[3], colours.C[4]
    key[11], key[12], key[13], key[14] =
        colours.L[1], colours.L[2], colours.L[3], colours.L[4]
    key[15], key[16], key[17], key[18] =
        colours.D[1], colours.D[2], colours.D[3], colours.D[4]
end

local function ensure_background_canvas(width, height)
    if background_cache.canvas and
       (background_cache.width ~= width or background_cache.height ~= height) then
        release_background_cache()
    end
    if background_cache.canvas then return true end
    if background_cache.disabled_width == width and
       background_cache.disabled_height == height then return false end

    local ok, canvas = pcall(love.graphics.newCanvas, width, height, {
        format = 'normal', readable = true, msaa = 0, dpiscale = 1
    })
    if not ok or not canvas then
        background_cache.disabled_width = width
        background_cache.disabled_height = height
        return false
    end
    canvas:setFilter('nearest', 'nearest')
    background_cache.canvas = canvas
    background_cache.width = width
    background_cache.height = height
    background_cache.disabled_width = 0
    background_cache.disabled_height = 0
    return true
end

local function render_background_cache(sprite, width, height)
    local previous_canvas = love.graphics.getCanvas()
    love.graphics.push('all')
    love.graphics.setCanvas(background_cache.canvas)
    love.graphics.origin()
    love.graphics.clear(0, 0, 0, 0)

    local ok, message = pcall(function()
        local step = sprite.draw_steps[1]
        local shader = G.SHADERS.background
        for _, uniform in ipairs(step.send) do
            local value = uniform.val
            if value == nil then
                value = uniform.func and uniform.func() or
                    uniform.ref_table[uniform.ref_value]
            end
            shader:send(uniform.name, value)
        end
        love.graphics.setShader(shader)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle('fill', 0, 0, width, height)
        love.graphics.setShader()
    end)
    love.graphics.setCanvas(previous_canvas)
    love.graphics.pop()
    if not ok then error(message) end
end

local function draw_cached_background(sprite)
    love.graphics.push('all')
    love.graphics.origin()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode('alpha', 'premultiplied')
    love.graphics.draw(background_cache.canvas, 0, 0)
    love.graphics.pop()

    add_to_drawhash(sprite)
    for key, child in pairs(sprite.children) do
        if key ~= 'h_popup' then child:draw() end
    end
    add_to_drawhash(sprite)
    sprite:draw_boundingrect()
end

if PERF_OPTIMIZATIONS then
local original_sprite_draw = Sprite.draw
function Sprite:draw(overlay)
    local is_background = self == G.SPLASH_BACK and self.draw_steps and
        self.draw_steps[1] and self.draw_steps[1].shader == 'background'
    if not (is_background and G.SETTINGS.reduced_motion and G.CANVAS and
            G.C.BACKGROUND and G.ARGS.spin) then
        return original_sprite_draw(self, overlay)
    end

    local width, height = G.CANVAS:getDimensions()
    if not ensure_background_canvas(width, height) then
        return original_sprite_draw(self, overlay)
    end

    if not background_values_match(width, height) then
        local ok = pcall(render_background_cache, self, width, height)
        if not ok then
            release_background_cache()
            background_cache.disabled_width = width
            background_cache.disabled_height = height
            return original_sprite_draw(self, overlay)
        end
        remember_background_values(width, height)
    end
    return draw_cached_background(self)
end
end
