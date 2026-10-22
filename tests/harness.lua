-- Runs scripts/main.lua against a stub of the runtime (API.md 0.28.0 plus the requests in
-- RUNTIME-REQUESTS.md). Checks the addon's own logic only, not the runtime or the game.
-- Usage: lua harness.lua <mod folder>
local root = assert(arg[1], "mod folder")

local function new(opts)
    opts = opts or {}
    local s = { logs = {}, now = 100, timers = {}, afters = {}, handlers = {}, sent = {}, spent = {}, wheel = {},
                lights = {}, sounds = {}, gestures = {}, fx = {}, focus = opts.focus or 1, last_power = 0,
                iteration = opts.iteration, weapons = opts.weapons or { 0x1234, 0 }, facing = opts.facing,
                foes = opts.foes or {}, fire = opts.fire ~= false }
    local caps = { ["events.lifecycle"] = true, timers = true, ["powers.cast"] = true, ["powers.focus"] = true,
                   ["characters.read"] = true, ["characters.awareness"] = true, ["inventory.read"] = true,
                   ["world.lights"] = true, ["ui.sound"] = true, ["effects.fire"] = opts.fx == true }
    local env = { math = math, string = string, table = table, ipairs = ipairs, pairs = pairs, next = next,
                  tonumber = tonumber, tostring = tostring, type = type, error = error, assert = assert, pcall = pcall }
    env.log = { info = function(m) s.logs[#s.logs + 1] = "info: " .. m end, warn = function(m) s.logs[#s.logs + 1] = "warn: " .. m end }
    env.api = { has_capability = function(name) return caps[name] == true end }
    env.events = { on = function(name, fn) s.handlers[name] = fn end }
    env.addons = { send = function(target, topic, value)
        assert(target == "com.necrosis.fire")
        if not s.fire then return false end
        s.sent[#s.sent + 1] = { topic = topic, value = value } return true end }
    env.timers = {
        every = function(sec, fn) s.timers[#s.timers + 1] = { sec = sec, fn = fn, due = s.now + sec } return #s.timers end,
        after = function(sec, fn) s.timers[#s.timers + 1] = { sec = sec, fn = fn, due = s.now + sec, once = true } return #s.timers end,
        cancel = function(id) if s.timers[id] then s.timers[id].fn = nil end return true end,
        now = function() return s.now end,
    }
    env.powers = {
        caster = function() return { focus = s.focus, last_power = s.last_power, techniques = { iteration = s.iteration } } end,
        spend_focus = function(a) s.spent[#s.spent + 1] = a s.focus = s.focus - a return true end,
        gesture = function(kind) s.gestures[#s.gestures + 1] = kind return true end,
    }
    if opts.wheel then env.powers.wheel = function(p, outcome) s.wheel[#s.wheel + 1] = outcome return true end end
    env.characters = {
        snapshot = function()
            return { characters = { { handle = 1, is_player = true, position = { 0, 0, 0 }, facing = s.facing } } }
        end,
        awareness = function()
            local rows = { { handle = 1, is_player = true, position = { 0, 0, 0 } } }
            for _, f in ipairs(s.foes) do rows[#rows + 1] = f end
            return { characters = rows }
        end,
    }
    env.inventory = { snapshot = function() return { weapons = { { item_id = s.weapons[1] }, { item_id = s.weapons[2] } } } end }
    env.lights = { set = function(name, spec) s.lights[name] = spec return true end,
                   remove = function(name) s.lights[name] = nil return true end }
    env.ui = { sound = function(name) s.sounds[#s.sounds + 1] = name return true end }
    if opts.fx then
        env.effects = { attach_fire = function(name, target) s.fx[name] = target return true end,
                        remove_fire = function(name) s.fx[name] = nil return true end,
                        spawn_fire_jet = function(spec) s.jet = spec return true end }
    end
    s.served = {}
    if opts.page then
        caps["levels.serve"], caps["assets.read"] = true, true
        local installed = { ["pwr_energy.pwr"] = string.pack("<I4", 0xAFCE01CE) .. string.rep("p", 0x40),
                            ["thmnrgico1.rfi"] = string.pack("<I4", 0x1D2D3DC6) .. string.rep("r", 0x40) }
        if opts.garbled then installed["pwr_energy.pwr"] = string.rep("x", 600) end
        env.levels = { read = function(member, package) assert(package == "Resource.rpk") return installed[member] end,
                       serve = function(member, bytes, package) s.served[member] = bytes return true end }
        s.cache = {}
        env.assets = { read = function(path)
                           if path:find("^cache/") then return s.cache[path] end
                           assert(path == "assets/energy-cells.rfi") return "cells" end,
                       write = function(path, bytes) assert(path:find("^cache/")) s.cache[path] = bytes s.writes = (s.writes or 0) + 1 return true end }
        env.tasks = { worker = function(module, input, fn)
            assert(module == "merge" and input.pwr:sub(1, 4) == string.pack("<I4", 0xAFCE01CE) and input.cells == "cells" and #input.nodes == 2)
            s.workers = (s.workers or 0) + 1
            fn({ pwr = "merged-pwr", sheet = "merged-sheet" }) return 1 end }
    end
    local loaded = {}
    env.require = function(name)
        if loaded[name] == nil then
            loaded[name] = assert(loadfile(root .. "/scripts/" .. name .. ".lua", "t", env))()
        end
        return loaded[name]
    end
    assert(loadfile(root .. "/scripts/main.lua", "t", env))()
    s.cast = function(power)
        s.handlers["power.cast"]({ power = power, number = power & 0xff, school = "energy", mode = "immediate" })
        s.last_power = power
    end
    s.run = function(seconds)
        local stop = s.now + seconds
        while s.now < stop - 1e-9 do
            s.now = s.now + 0.05
            local list = s.timers
            for _, t in ipairs(list) do
                if t.fn and s.now >= t.due - 1e-9 then
                    local fn = t.fn
                    if t.once then t.fn = nil else t.due = t.due + t.sec end
                    fn()
                end
            end
        end
    end
    s.last = function(topic)
        for i = #s.sent, 1, -1 do if s.sent[i].topic == topic then return s.sent[i].value end end
    end
    return s
end

local passed = 0
local function case(name, fn) fn() passed = passed + 1 print("ok  " .. name) end

case("Fire Breath pays, gestures, and sends a cone the way the body faces", function()
    local s = new{ facing = { 0, 0, 1 } }
    s.cast(0x402) s.run(0.5)
    local order = s.last("fire.ignite")
    assert(order and order.cone and order.cone.dir[3] == 1 and order.cone.length == 350 and order.health == 0.06)
    assert(s.spent[1] == 0.15 and s.gestures[1] == "thrust" and s.sounds[#s.sounds] == "firesizzlea03")
    assert(s.lights.breath, "flash") s.run(1) assert(not s.lights.breath, "flash faded")
end)

case("without a facing it breathes at the nearest foe fighting you", function()
    local s = new{ foes = { { handle = 5, position = { 300, 0, 0 }, awareness = { fights_player = true } },
                            { handle = 6, position = { 0, 0, -100 }, awareness = { fights_player = false } } } }
    s.cast(0x402) s.run(0.5)
    local dir = s.last("fire.ignite").cone.dir
    assert(dir[1] == 1 and dir[3] == 0)
end)

case("with nothing to aim at only a short ring around you burns", function()
    local s = new() s.cast(0x402) s.run(0.5)
    local order = s.last("fire.ignite")
    assert(order.sphere and order.sphere.radius == 120 and not order.cone)
end)

case("too little focus refuses, with the fail sound when there is no wheel", function()
    local s = new{ focus = 0.1 } s.cast(0x402) s.run(1)
    assert(#s.sent == 0 and #s.spent == 0 and s.sounds[1] == "thaumfail01")
    local t = new{ focus = 0.1, wheel = true } t.cast(0x402) t.run(1)
    assert(t.wheel[1] == "fail" and #t.sounds == 0)
end)

case("Iteration halves a repeated breath", function()
    local s = new{ iteration = true } s.cast(0x402) s.run(1) s.cast(0x402) s.run(1)
    assert(s.spent[1] == 0.15 and s.spent[2] == 0.075)
end)

case("Flaming Weapon burns for its time, a second cast puts it out, and it needs a weapon", function()
    local s = new() s.cast(0x403) s.run(0.2)
    assert(s.last("fire.weapon").seconds == 20 and s.spent[1] == 0.2 and s.lights.blade)
    s.run(21)
    assert(s.last("fire.weapon").seconds == 0 and not s.lights.blade and s.sounds[#s.sounds] == "firesizzlea04")
    s.cast(0x403) s.run(1) s.cast(0x403) s.run(0.2)
    assert(s.last("fire.weapon").seconds == 0 and #s.spent == 2, "put out early, no refund, no charge")
    local t = new{ weapons = { 0, 0 } } t.cast(0x403) t.run(1)
    assert(#t.sent == 0 and #t.spent == 0)
end)

case("with the runtime's fire effects the blade burns and the breath shows a jet", function()
    local s = new{ fx = true, facing = { 1, 0, 0 } }
    s.cast(0x403) s.run(0.2) assert(s.fx.blade == "weapon:right" and not s.lights.blade)
    s.cast(0x402) s.run(0.5) assert(s.jet and s.jet.length == 350)
end)

case("without the Fire mod it says so once", function()
    local s = new{ fire = false } s.cast(0x402) s.run(1) s.cast(0x402) s.run(1)
    local n = 0 for _, l in ipairs(s.logs) do if l:find("Fire mod") then n = n + 1 end end
    assert(n == 1)
end)

case("other powers are left alone", function()
    local s = new() s.cast(0x401) s.cast(0x20501) s.run(1)
    assert(#s.sent == 0 and #s.spent == 0)
end)

case("leaving the level puts the weapon out quietly", function()
    local s = new() s.cast(0x403) s.run(1)
    local sounds = #s.sounds
    s.handlers["runtime.phase"]({ phase = "loading" }) s.run(0.2)
    assert(s.last("fire.weapon").seconds == 0 and #s.sounds == sounds)
end)

case("the Energy page is built from the installed one once and served", function()
    local s = new{ page = true }
    s.handlers["runtime.phase"]({ phase = "menu" }) s.run(0.1)
    s.handlers["runtime.phase"]({ phase = "session" }) s.run(0.1)
    assert(s.workers == 1 and s.served["pwr_energy.pwr"] == "merged-pwr" and s.served["thmnrgico1.rfi"] == "merged-sheet")
    assert(s.cache["cache/pwr_energy.pwr"] == "merged-pwr" and s.cache["cache/thmnrgico1.rfi"] == "merged-sheet" and s.writes == 2)
end)

case("garbled installed bytes are reported with what arrived, and nothing is merged", function()
    local s = new{ page = true, garbled = true }
    s.handlers["runtime.phase"]({ phase = "menu" }) s.run(0.1)
    local said = false for _, l in ipairs(s.logs) do said = said or l:find("600 bytes %(7878787878787878%)") ~= nil end
    assert(said and not s.workers and next(s.served) == nil)
end)

case("without a way to read installed files the page is left alone, said once", function()
    local s = new()
    s.handlers["runtime.phase"]({ phase = "menu" }) s.run(0.1) s.handlers["runtime.phase"]({ phase = "session" }) s.run(0.1)
    local n = 0 for _, l in ipairs(s.logs) do if l:find("levels.read") then n = n + 1 end end
    assert(n == 1 and next(s.served) == nil)
end)

print(passed .. " passed")
