-- The Energy school's fire: Fire Breath (an instant gout of flame in front of you) and Flaming Weapon
-- (your weapon burns for a while and sets alight whoever it strikes). They sit on the game's own
-- Energy page beside Shock. The game's dispatch casts only its own Energy powers; the runtime hands
-- these to us (RUNTIME-REQUESTS.md). Burning itself belongs to the Fire mod: these powers only ask it.
local config = require("config")

local breath, weapon = config.breath, config.weapon
local OURS = { [breath.power] = "breath", [weapon.power] = "weapon" }
local last_power = nil          -- for Iteration when the runtime does not report the game's last cast
local weapon_until, weapon_timer, crackle_at = 0, nil, 0
local warned = {}

local function warn_once(what, text)
    if not warned[what] then
        warned[what] = true
        log.info(text)
    end
end

local function sound(which)
    if ui and ui.sound and api.has_capability("ui.sound") then
        pcall(ui.sound, config.sounds[which], config.sounds.volume)
    end
end

local function wheel(power, accepted)
    return powers.wheel and (pcall(powers.wheel, power, accepted and "cast" or "fail")) or false
end

local function refuse(name, why)
    log.info(name .. " not cast: " .. why)
    if not wheel(config[name].power, false) then
        sound("fail")
    end
end

local function tell_fire(topic, value)
    local sent = addons and addons.send and addons.send(config.fire, topic, value)
    if not sent then
        warn_once("fire", "the Fire mod (" .. config.fire .. ") is not taking messages: enable it for these powers to burn")
    end
    return sent
end

-- The game's cost rules: Iteration halves a repeated instant cast; the caller checks focus.
local function cost_of(name, caster)
    local cost = config[name].focus
    local repeated
    if caster and caster.last_power ~= nil then
        repeated = caster.last_power == config[name].power
    else
        repeated = last_power == config[name].power
    end
    if repeated and caster and caster.techniques and caster.techniques.iteration then
        cost = cost * config.iteration
    end
    return cost
end

local function pay(power, cost, gesture)
    if powers.spend_focus and api.has_capability("powers.focus") then
        pcall(powers.spend_focus, cost)
    end
    wheel(power, true)
    if powers.gesture then
        pcall(powers.gesture, gesture)
    end
end

-- Fire Breath ---------------------------------------------------------------------------------------

local function flatten(dx, dz)
    local n = math.sqrt(dx * dx + dz * dz)
    if n < 1 then
        return nil
    end
    return { dx / n, 0, dz / n }
end

-- Where the breath goes: the way the body faces where the runtime reports it (requested), otherwise at
-- the nearest foe fighting you (you face what you fight), otherwise nowhere in particular.
local function aim(me)
    if me.facing then
        return flatten(me.facing[1], me.facing[3])
    end
    if not (characters.awareness and api.has_capability("characters.awareness")) then
        return nil
    end
    local ok, view = pcall(characters.awareness)
    if not ok or not view then
        return nil
    end
    local best, nearest = nil, breath.length * 1.5
    for _, row in ipairs(view.characters) do
        local mind = row.awareness
        if not row.is_player and not row.dead and mind and mind.fights_player and row.position then
            local dx, dz = row.position[1] - me.position[1], row.position[3] - me.position[3]
            local d = math.sqrt(dx * dx + dz * dz)
            if d < nearest then
                best, nearest = flatten(dx, dz), d
            end
        end
    end
    return best
end

local function me_row()
    if not api.has_capability("characters.read") then
        return nil
    end
    local ok, view = pcall(characters.snapshot)
    if ok and view then
        for _, row in ipairs(view.characters) do
            if row.is_player and row.position then
                return row
            end
        end
    end
    return nil
end

local flash_timer = nil

local function flash(strength)
    local f = breath.flash
    pcall(lights.set, "breath", { color = f.color, range = f.range, intensity = f.intensity * strength,
                                  follow = { forward = f.forward, up = f.up, smoothing = 0 } })
end

-- The gout's light fades out over `fade` seconds (no fire jet without the runtime's effect).
local function fade_flash(started)
    local t = (timers.now() - started) / breath.flash.fade
    if t >= 1 then
        pcall(lights.remove, "breath")
        if flash_timer then
            timers.cancel(flash_timer)
            flash_timer = nil
        end
        return
    end
    flash(1 - t)
end

local function show_jet()
    if effects and effects.spawn_fire_jet and api.has_capability("effects.fire") then
        pcall(effects.spawn_fire_jet, { from = "head", length = breath.jet.length, spread = breath.jet.spread,
                                        life = breath.jet.life })
    end
end

local function show_flash()
    if not (lights and lights.set and api.has_capability("world.lights")) then
        return
    end
    flash(1)
    local started = timers.now()
    if flash_timer then
        timers.cancel(flash_timer)
    end
    flash_timer = timers.every(0.05, function() fade_flash(started) end)
end

local function breathe()
    local me = me_row()
    if not me then
        return
    end
    local dir = aim(me)
    local order = { seconds = breath.seconds, health = breath.health, balance = breath.balance }
    if dir then
        -- From the body centre and level, so it reaches bodies and props in front at any height.
        order.cone = { origin = { me.position[1], me.position[2], me.position[3] }, dir = dir,
                       length = breath.length, angle = breath.angle }
    else
        order.sphere = { center = me.position, radius = breath.near }
    end
    tell_fire("fire.ignite", order)
    timers.after(0, show_jet)
    timers.after(0, show_flash)
    sound("cast")
end

local function cast_breath(caster)
    local cost = cost_of("breath", caster)
    if caster and caster.focus < cost then
        return refuse("breath", "not enough focus")
    end
    pay(breath.power, cost, config.gestures.breath)
    timers.after(breath.windup, breathe)
end

-- Flaming Weapon ------------------------------------------------------------------------------------

local function holds_weapon()
    if not (inventory and inventory.snapshot and api.has_capability("inventory.read")) then
        return true   -- unknown never blocks a cast
    end
    local ok, view = pcall(inventory.snapshot)
    if not ok or not view or not view.weapons then
        return true
    end
    for _, slot in ipairs(view.weapons) do
        if slot.item_id and slot.item_id ~= 0 then
            return true
        end
    end
    return false
end

local function blade_light(on)
    if not (lights and lights.set and api.has_capability("world.lights")) then
        return
    end
    if not on then
        pcall(lights.remove, "blade")
        return
    end
    local g = weapon.glow
    pcall(lights.set, "blade", { color = g.color, range = g.range, intensity = g.intensity * (0.8 + 0.4 * math.random()),
                                 follow = { forward = g.forward, right = g.right, up = g.up, smoothing = 0.05 },
                                 glow = { size = g.size, color = { 1, 0.5, 0.15 } } })
end

local function blade_fx(on)
    if effects and effects.attach_fire and api.has_capability("effects.fire") then
        if on then
            pcall(effects.attach_fire, "blade", "weapon:right", { size = 0.35 })
        else
            pcall(effects.remove_fire, "blade")
        end
        return true
    end
    return false
end

local function weapon_out(quiet)
    weapon_until = 0
    if weapon_timer then
        timers.cancel(weapon_timer)
        weapon_timer = nil
    end
    tell_fire("fire.weapon", { seconds = 0 })
    timers.after(0, function() if not blade_fx(false) then blade_light(false) end end)
    if not quiet then
        sound("out")
    end
end

-- While it burns: the glow flickers (where there are no real flames) and it crackles now and then.
local function weapon_tick()
    local now = timers.now()
    if now >= weapon_until then
        return weapon_out(false)
    end
    if not (effects and effects.attach_fire and api.has_capability("effects.fire")) then
        blade_light(true)
    end
    if now >= crackle_at then
        crackle_at = now + weapon.crackle
        timers.after(0, function() sound("crackle") end)
    end
end

local function cast_weapon(caster)
    if timers.now() < weapon_until then
        return weapon_out(false)   -- cast again: the flames go out early, nothing is given back
    end
    local cost = cost_of("weapon", caster)
    if caster and caster.focus < cost then
        return refuse("weapon", "not enough focus")
    end
    if not holds_weapon() then
        return refuse("weapon", "no weapon in hand")
    end
    pay(weapon.power, cost, config.gestures.weapon)
    weapon_until = timers.now() + weapon.seconds
    crackle_at = timers.now() + weapon.crackle
    tell_fire("fire.weapon", { seconds = weapon.seconds })
    timers.after(0, function() if not blade_fx(true) then blade_light(true) end end)
    sound("start")
    weapon_timer = timers.every(0.15, weapon_tick)
end

-- Casting ---------------------------------------------------------------------------------------------

if api.has_capability("powers.cast") then
    events.on("power.cast", function(event)
        local name = OURS[event.power & 0x3FFFF]
        if not name then
            return
        end
        local caster = powers.caster and powers.caster() or nil
        if name == "breath" then
            cast_breath(caster)
        else
            cast_weapon(caster)
        end
        last_power = config[name].power
    end)
else
    log.info("Fire Breath and Flaming Weapon cannot be cast: this runtime has no powers.cast")
end

-- A level change or the menu puts the weapon out with everything else that burns.
events.on("runtime.phase", function()
    if weapon_timer or weapon_until > 0 then
        weapon_out(true)
    end
    if flash_timer then
        timers.cancel(flash_timer)
        flash_timer = nil
    end
end)
