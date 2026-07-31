-- SDL controller mapping strings.
--
-- A mapping line is a GUID, a display name, and then any number of
-- `control:input` pairs, e.g.
--
--   03000000...,Anbernic gamepad,a:b1,b:b0,dpup:h0.1,platform:Linux,
--
-- The wizard only ever learns a handful of controls, so the device's existing
-- mapping is used as the base and the learned entries replace their
-- counterparts in it. Everything the device already had right -- sticks,
-- triggers, the D-pad -- is carried across untouched.
--
-- Kept separate from main.lua because it is the only part with a right and a
-- wrong answer that can be checked without a handheld in front of you.

local M = {}

-- SDL hat bitmask, as it appears after the dot in `dpup:h0.1`.
M.HAT_MASK = {u = 1, r = 2, d = 4, l = 8}

function M.split(mapping)
    local fields = {}
    for field in string.gmatch(mapping, '[^,]+') do
        fields[#fields + 1] = field
    end
    return fields
end

-- The set of controls a mapping already binds, by name.
function M.controls(mapping)
    local bound = {}
    if not mapping or mapping == '' then return bound end
    local fields = M.split(mapping)
    for i = 3, #fields do
        local control = fields[i]:match('^([^:]+):')
        if control then bound[control] = true end
    end
    return bound
end

-- A name with a comma in it would be read back as an extra control field.
function M.sanitize_name(name)
    name = (name or ''):gsub(',', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if name == '' then name = 'Controller' end
    return name
end

-- learned is an ordered list of {control=..., input=...}, so the same answers
-- always produce the same line regardless of table iteration order.
function M.build(guid, name, learned, base)
    local order, values = {}, {}
    local function put(control, input)
        if values[control] == nil then order[#order + 1] = control end
        values[control] = input
    end

    if base and base ~= '' then
        local fields = M.split(base)
        -- The base line's own name is the one the device is known by; keep it.
        if fields[2] and fields[2] ~= '' then name = fields[2] end
        for i = 3, #fields do
            local control, input = fields[i]:match('^([^:]+):(.+)$')
            if control then put(control, input) end
        end
    end

    for _, entry in ipairs(learned) do
        put(entry.control, entry.input)
    end

    -- An answer was given with the button in hand; a base entry that claims the
    -- same input for something else was already wrong, and is the reason for
    -- being here at all. Drop it rather than leave SDL with one input bound
    -- twice, which would make that button do both things at once.
    local claimed = {}
    for _, entry in ipairs(learned) do claimed[entry.input] = entry.control end
    for control, input in pairs(values) do
        if claimed[input] and claimed[input] ~= control then
            values[control] = nil
        end
    end

    -- SDL ignores a mapping whose platform is not the one it is running on.
    put('platform', 'Linux')

    local out = {guid, M.sanitize_name(name)}
    for _, control in ipairs(order) do
        if values[control] then
            out[#out + 1] = control .. ':' .. values[control]
        end
    end
    return table.concat(out, ',') .. ','
end

return M
