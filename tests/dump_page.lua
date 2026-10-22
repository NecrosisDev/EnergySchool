-- Prints scripts/page.lua as JSON for build.py --reference. Usage: lua dump_page.lua <mod folder>
local nodes = assert(loadfile(arg[1] .. "/scripts/page.lua", "t", {}))()
local function str(s)
    return '"' .. s:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"'
end
local out = {}
for _, n in ipairs(nodes) do
    out[#out + 1] = string.format('{"power": %d, "x": %.17g, "y": %.17g, "parent": %d, "parent_is_ours": %s, '
        .. '"technique": %d, "name": %s, "description": %s}', n.power, n.x, n.y, n.parent,
        tostring(n.parent_is_ours == true), n.technique or 0, str(n.name), str(n.description))
end
io.write("[" .. table.concat(out, ", ") .. "]")
