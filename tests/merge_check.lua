-- Runs scripts/merge.lua on the installed files in <reference folder> and checks it against the
-- Python merge build.py wrote there, byte for byte. Usage: lua merge_check.lua <mod folder> <reference folder>
local root, ref = arg[1], arg[2]
local function read(path) local f = assert(io.open(path, "rb")) local s = f:read("a") f:close() return s end
local env = { math = math, string = string, table = table, ipairs = ipairs, pairs = pairs, assert = assert, error = error,
              tostring = tostring, type = type }
local merge = assert(loadfile(root .. "/scripts/merge.lua", "t", env))()
local nodes = assert(loadfile(root .. "/scripts/page.lua", "t", {}))()
local started = os.clock()
local out = merge({ pwr = read(ref .. "/installed.pwr"), sheet = read(ref .. "/installed.rfi"), cells = read(ref .. "/cells.rfi"), nodes = nodes })
local seconds = os.clock() - started
local function same(name, got, want)
    if got == want then print(string.format("ok  %s matches the Python merge (%d bytes)", name, #got)) return true end
    local at = 1 while got:byte(at) == want:byte(at) do at = at + 1 end
    print(string.format("FAIL %s: %d bytes vs %d, first difference at byte %d", name, #got, #want, at - 1))
    return false
end
local ok = same("pwr_energy.pwr", out.pwr, read(ref .. "/merged.pwr"))
ok = same("thmnrgico1.rfi", out.sheet, read(ref .. "/merged.rfi")) and ok
print(string.format("merge took %.1f s of CPU", seconds))
os.exit(ok and 0 or 1)
