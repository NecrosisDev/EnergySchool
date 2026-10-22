-- Builds the Energy page the game reads from the installed one: the installed power tree with our
-- nodes appended, and the installed icon sheet with our cells added. Runs on a runtime worker (no
-- game API; tasks.worker), so nothing of the game's is ever shipped: the installed bytes come from
-- the archive at load time and only our nodes and our painted cells come with the mod.
--
-- Formats (the ExaniMate service's pwr.py and rfi.py, which build.py's --reference output uses; the
-- offline test checks this module against it byte for byte):
-- * .pwr: u32 magic AFCE01CE, u32 FE01CD00, u32 body length; body = 0x28-byte head, u32 node count,
--   nodes {u32 power, name, description; f32 x, y; u32 link count; links {f32, f32, u32 parent, u32 0}};
--   then u32 ABCD0000, u32 length, u32 ABCDAD00, u32 length, 4-byte language, u32 length, the string
--   table (12 bytes, u32 count, count + 1 u32 offsets, u32 blob length, blob of {u32 length, bytes}).
-- * .rfi: 8 u32 {magic, width, height, 1, code, image flags (0x00080000 = mipmaps), flags
--   (0x40000000 = run-length packed), unpacked bytes}, then the pixels, rows bottom first, every mip
--   level after the last (halving while width + height > 2).
local MAGIC_PWR, TAG_NODES, TAG_STRINGS, TAG_LANGUAGE = 0xAFCE01CE, 0xFE01CD00, 0xABCD0000, 0xABCDAD00
local MAGIC_RFI, FLAG_RLE, FLAG_MIPS = 0x1D2D3DC6, 0x40000000, 0x00080000
local RLE_T = 0xC2
local CELL = 512

local function u32(s, p)
    return (string.unpack("<I4", s, p + 1))
end

-- Power tree ------------------------------------------------------------------------------------------

local function parse_tree(data)
    assert(#data >= 0x38 and u32(data, 0) == MAGIC_PWR and u32(data, 4) == TAG_NODES, "not a power tree")
    local tree = { head = data:sub(13, 0x34), nodes = {} }
    local p = 0x38
    for _ = 1, u32(data, 0x34) do
        local power, name, desc, x, y, n = string.unpack("<I4I4I4ffI4", data, p + 1)
        p = p + 24
        local links = {}
        for k = 1, n do
            links[k] = { string.unpack("<ffI4I4", data, p + 1) }
            links[k][5] = nil
            p = p + 16
        end
        tree.nodes[#tree.nodes + 1] = { power = power, name = name, desc = desc, x = x, y = y, links = links }
    end
    assert(p == 12 + u32(data, 8) and u32(data, p) == TAG_STRINGS and u32(data, p + 8) == TAG_LANGUAGE,
           "unexpected layout after the nodes")
    tree.language = data:sub(p + 17, p + 20)
    local q = p + 24
    tree.string_head = data:sub(q + 1, q + 16)
    local count = u32(data, q + 12)
    tree.offsets = {}
    for i = 0, count do
        tree.offsets[i + 1] = u32(data, q + 16 + 4 * i)
    end
    local r = q + 16 + 4 * (count + 1)
    local length = u32(data, r)
    tree.blob = data:sub(r + 5, r + 4 + length)
    assert(r + 4 + length == #data, "the string table does not end at the file end")
    return tree
end

local function pack_tree(tree)
    local body = { tree.head, string.pack("<I4", #tree.nodes) }
    for _, n in ipairs(tree.nodes) do
        body[#body + 1] = string.pack("<I4I4I4ffI4", n.power, n.name, n.desc, n.x, n.y, #n.links)
        for _, link in ipairs(n.links) do
            body[#body + 1] = string.pack("<ffI4I4", link[1], link[2], link[3], link[4])
        end
    end
    body = table.concat(body)
    local offsets = {}
    for i, v in ipairs(tree.offsets) do
        offsets[i] = string.pack("<I4", v)
    end
    local strings = tree.string_head:sub(1, 12) .. string.pack("<I4", #tree.offsets - 1) .. table.concat(offsets)
        .. string.pack("<I4", #tree.blob) .. tree.blob
    local language = tree.language .. string.pack("<I4", #strings) .. strings
    local inner = string.pack("<I4I4", TAG_LANGUAGE, #language) .. language
    return string.pack("<I4I4I4", MAGIC_PWR, TAG_NODES, #body) .. body .. string.pack("<I4I4", TAG_STRINGS, #inner) .. inner
end

-- A new string, appended to the blob; returns its index (the last offset stays the empty string's).
local function add_text(tree, text)
    local at = #tree.blob
    tree.blob = tree.blob .. string.pack("<I4", #text) .. text
    table.insert(tree.offsets, #tree.offsets, at)
    return #tree.offsets - 2
end

-- Where a link's line meets each ring, as turns from +y signed by x (0x1db920 / 0x1db9e0), with a
-- slight bend like the shipped links.
local LINK_CURVE = 0.03
local function ring_angle(dx, dy)
    local angle = math.acos(math.max(-1.0, math.min(1.0, dy / math.sqrt(dx * dx + dy * dy)))) / (2 * math.pi)
    return dx < 0 and -angle or angle
end
local function wrap(turns)
    return (turns + 0.5) % 1.0 - 0.5
end

local function merge_tree(installed, nodes)
    local tree = parse_tree(installed)
    for _, node in ipairs(tree.nodes) do
        for _, ours in ipairs(nodes) do
            if node.power & 0x3FFFF == ours.power then
                error("the installed Energy page already has power " .. string.format("0x%X", ours.power))
            end
        end
    end
    local base = #tree.nodes
    for i, ours in ipairs(nodes) do
        -- `parent` counts the page's nodes (installed first, then ours in order): 1 is Shock.
        local parent = ours.parent <= 0 and ours.parent or (ours.parent_is_ours and base + ours.parent or ours.parent)
        local p = assert(tree.nodes[parent], "no parent node " .. tostring(parent))
        local link = { wrap(ring_angle(p.x - ours.x, p.y - ours.y) + LINK_CURVE),
                       wrap(ring_angle(ours.x - p.x, ours.y - p.y) - LINK_CURVE), parent, 0 }
        tree.nodes[base + i] = { power = ours.power | ((ours.technique or 0) << 28), name = add_text(tree, ours.name),
                                 desc = add_text(tree, ours.description), x = ours.x, y = ours.y, links = { link } }
    end
    return pack_tree(tree)
end

-- Icon sheet ------------------------------------------------------------------------------------------

local function rle_unpack(src, at, size)
    local out, n, i = {}, 0, at
    local lim = 0x100 - RLE_T
    while n < size do
        local b = src:byte(i)
        i = i + 1
        if b > lim then
            out[#out + 1] = src:sub(i, i + 2):rep(b - lim + 1)
            n = n + 3 * (b - lim + 1)
            i = i + 3
        else
            out[#out + 1] = src:sub(i, i + 3 * (b + 1) - 1)
            n = n + 3 * (b + 1)
            i = i + 3 * (b + 1)
        end
    end
    assert(n == size and i == #src + 1, "bad run-length stream")
    return table.concat(out)
end

-- Header and level-0 rows (bottom first) of a 24-bit sheet.
local function read_sheet(data)
    local h = { string.unpack("<I4I4I4I4I4I4I4I4", data) }
    assert(h[1] == MAGIC_RFI and h[5] & 0x800CFFFF == 0xC600, "not a 24-bit RGB .rfi")
    local width, height = h[2], h[3]
    local pixels = h[7] & FLAG_RLE ~= 0 and rle_unpack(data, 33, h[8]) or data:sub(33, 32 + h[8])
    return h, width, height, pixels:sub(1, width * height * 3)
end

-- One pixel per entry as r << 16 | g << 8 | b.
local function to_ints(level, out, at)
    for i = 1, #level, 3 do
        local r, g, b = level:byte(i, i + 2)
        out[at] = r << 16 | g << 8 | b
        at = at + 1
    end
    return at
end

-- 2x2 box filter (the usual mip step, as rfi.downsample), reading pixel ints from `src` at `from`.
local function downsample(px, from, w, h, at)
    local nw, nh = math.max(1, w // 2), math.max(1, h // 2)
    for y = 0, nh - 1 do
        for x = 0, nw - 1 do
            local r, g, b = 0, 0, 0
            for dy = 0, 1 do
                for dx = 0, 1 do
                    local v = px[from + math.min(y * 2 + dy, h - 1) * w + math.min(x * 2 + dx, w - 1)]
                    r, g, b = r + (v >> 16), g + ((v >> 8) & 0xFF), b + (v & 0xFF)
                end
            end
            px[at] = (r // 4) << 16 | (g // 4) << 8 | (b // 4)
            at = at + 1
        end
    end
    return at, nw, nh
end

-- Greedy run-length coder for 3-byte pixels (as rfi.rle_pack: a run of 2+ equal pixels, else literals).
local function rle_pack(px, n)
    local lim = 0x100 - RLE_T
    local max_run, max_lit = 255 - lim + 1, lim + 1
    local out = {}
    local i = 1
    while i <= n do
        local j = i + 1
        while j <= n and j - i < max_run and px[j] == px[i] do
            j = j + 1
        end
        if j - i >= 2 then
            out[#out + 1] = string.char(j - i + lim - 1) .. string.pack(">I3", px[i])
            i = j
        else
            local k = i + 1
            while k <= n and k - i < max_lit do
                if k + 1 <= n and px[k + 1] == px[k] then
                    break
                end
                k = k + 1
            end
            local chunk = { string.char(k - i - 1) }
            for q = i, k - 1 do
                chunk[#chunk + 1] = string.pack(">I3", px[q])
            end
            out[#out + 1] = table.concat(chunk)
            i = k
        end
    end
    return table.concat(out)
end

-- Our sheet (cells 1.. painted, cell 0 left black; level 0 only) with every cell the installed sheet
-- has copied in, written in the installed sheet's format (its pixel code, mipmaps and packing).
local function merge_sheet(installed, ours)
    local h, iw, ih, ipx = read_sheet(installed)
    local _, w, hh, opx = read_sheet(ours)
    assert(iw % CELL == 0 and ih % CELL == 0 and w % CELL == 0 and hh % CELL == 0 and iw <= w, "sheet sizes")
    -- Cells are numbered left to right, top to bottom; rows are stored bottom first.
    local rows = {}
    local per_row, installed_cells = iw // CELL, (iw // CELL) * (ih // CELL)
    for s = 0, hh - 1 do
        local row = opx:sub(s * w * 3 + 1, (s + 1) * w * 3)
        local top = hh - 1 - s                       -- this stored row, counted from the top
        local cell_row = top // CELL
        for cx = 0, w // CELL - 1 do
            local cell = cell_row * (w // CELL) + cx
            if cell < installed_cells then
                -- The same cell in the installed sheet, at the same height inside the cell.
                local icx, icy = cell % per_row, cell // per_row
                local itop = icy * CELL + top % CELL
                local is = ih - 1 - itop
                local piece = ipx:sub(is * iw * 3 + icx * CELL * 3 + 1, is * iw * 3 + (icx + 1) * CELL * 3)
                row = row:sub(1, cx * CELL * 3) .. piece .. row:sub((cx + 1) * CELL * 3 + 1)
            end
        end
        rows[s + 1] = row
    end
    local px = {}
    local at = to_ints(table.concat(rows), px, 1)
    if h[6] & FLAG_MIPS ~= 0 then
        local from, lw, lh = 1, w, hh
        while lw + lh > 2 do
            local start = at
            at, lw, lh = downsample(px, from, lw, lh, at)
            from = start
        end
    end
    local n = at - 1
    local flags, body = h[7], nil
    if flags & FLAG_RLE ~= 0 then
        body = rle_pack(px, n)
    else
        local raw = {}
        for i = 1, n do
            raw[i] = string.pack(">I3", px[i])
        end
        body = table.concat(raw)
    end
    return string.pack("<I4I4I4I4I4I4I4I4", MAGIC_RFI, w, hh, h[4], h[5], h[6], flags, n * 3) .. body
end

-- The worker's entry: input {pwr, sheet, cells, nodes}; returns {pwr, sheet}.
return function(input)
    return { pwr = merge_tree(input.pwr, input.nodes), sheet = merge_sheet(input.sheet, input.cells) }
end
