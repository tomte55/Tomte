-- Run from the AddOns folder: lua Tomte/tests/test_petscript.lua
local ns = {}
assert(loadfile("Tomte/Modules/Pets/Data.lua"))("Tomte", ns) -- ns.PETS_MAX_LEVEL
assert(loadfile("Tomte/Modules/Pets/Script.lua"))("Tomte", ns)

local failures = 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		print("ok   " .. name)
	else
		failures = failures + 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function eq(actual, expected, label)
	if actual ~= expected then
		error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end

-- A battle as plain tables, and the api the interpreter reads it through (Battle.lua gives the live one).
local MODS = { ["8:5"] = 1.5, ["8:3"] = 2 / 3 } -- Beast is strong vs Critter, weak vs Flying
local TYPES = { beast = 8, critter = 5, flying = 3 }
local QUALITIES = { rare = 4 }

local function Pet(name, species, extra)
	local p = { name = name, species = species, health = 1000, max = 1000, speed = 300, power = 300, level = 25,
		type = 8, quality = 3, played = false, auras = {},
		abilities = {
			{ id = 101, name = "Bite", type = 8, usable = true, cd = 0 },
			{ id = 102, name = "Roar", type = 8, usable = true, cd = 0 },
			{ id = 103, name = "Howl", type = 8, usable = true, cd = 0 },
		} }
	for k, v in pairs(extra or {}) do
		p[k] = v
	end
	return p
end

local function Battle()
	return {
		round = 1,
		rounds = { [1] = 1, [2] = 1 },
		canSwapOut = true, petSelect = false, canSkip = true, trap = { false, 1 },
		weather = nil,
		collected = { [900] = { 1, 3 } },
		[1] = { active = 1, pad = {}, pets = { Pet("Alpha", 900), Pet("Beta", 901), Pet("Gamma", 902) } },
		[2] = { active = 1, pad = {}, pets = { Pet("Foe", 500, { type = 5 }), Pet("Foe2", 501), Pet("Foe3", 502) } },
	}
end

local function API(b)
	local api = {}
	local function P(o, i)
		return b[o].pets[i]
	end
	function api:NumPets(o) return #b[o].pets end
	function api:Active(o) return b[o].active end
	function api:Health(o, i) return P(o, i).health end
	function api:MaxHealth(o, i) return P(o, i).max end
	function api:Speed(o, i) return P(o, i).speed end
	function api:Power(o, i) return P(o, i).power end
	function api:Level(o, i) return P(o, i).level end
	function api:Type(o, i) return P(o, i).type end
	function api:Quality(o, i) return P(o, i).quality end
	function api:Species(o, i) return P(o, i).species end
	function api:Name(o, i) return P(o, i).name end
	function api:Ability(o, i, s)
		local a = P(o, i).abilities[s]
		if a then
			return a.id, a.name, a.type, a.noHints
		end
	end
	function api:AbilityState(o, i, s)
		local a = P(o, i).abilities[s]
		return a.usable, a.cd, 0
	end
	function api:Auras(o, i) return P(o, i).auras end
	function api:PadAuras(o) return b[o].pad end
	function api:Weather()
		if b.weather then
			return b.weather.id, b.weather.name, b.weather.turns
		end
	end
	function api:Modifier(atk, def) return MODS[atk .. ":" .. def] or 1 end
	function api:CanSwapOut() return b.canSwapOut end
	function api:PetSelect() return b.petSelect end
	function api:CanSwapIn(i) return P(1, i).health > 0 end
	function api:CanSkip() return b.canSkip end
	function api:Trap() return b.trap[1], b.trap[2] end
	function api:Round(o)
		if o then
			return b.rounds[o]
		end
		return b.round
	end
	function api:Played(o, i) return P(o, i).played end
	function api:Collected(o, i)
		local c = b.collected[P(o, i).species]
		if c then
			return c[1], c[2], true
		end
		return 0, 3, true
	end
	function api:TypeOf(name) return TYPES[name] end
	function api:QualityOf(name) return QUALITIES[name] end
	return api
end

local function Build(code)
	local script, err = ns.PetScript_Build(code)
	if not script then
		error("build failed: " .. tostring(err), 2)
	end
	return script
end

-- "ability 2", "change 3", "skip", ... or "none".
local function Next(code, b)
	local action = ns.PetScript_Next(Build(code), API(b or Battle()))
	if not action then
		return "none"
	end
	if action.kind == "ability" then
		return "ability " .. action.slot
	elseif action.kind == "change" then
		return "change " .. action.pet
	elseif action.kind == "test" then
		return "test " .. tostring(action.text)
	end
	return action.kind
end

-- Cond: does the condition hold in battle b? (A use(#1) line guarded by it.)
local function Cond(cond, b)
	return Next("use(#1) [" .. cond .. "]", b) == "ability 1"
end

local function BuildError(code)
	local script, err = ns.PetScript_Build(code)
	return script == nil and err or nil
end

-- Building ------------------------------------------------------------------------------------------------------

test("build errors", function()
	eq(BuildError("jump(#1)") ~= nil, true, "unknown command")
	eq(BuildError("if [round=1]\nuse(#1)\nelse\nuse(#2)\nendif") ~= nil, true, "else")
	eq(BuildError("if [round=1]\nuse(#1)") ~= nil, true, "unpaired if")
	eq(BuildError("endif") ~= nil, true, "endif alone")
	eq(BuildError("use(#1) [round => 2]") ~= nil, true, "bad operator")
	eq(BuildError("use(#1) -- go") ~= nil, true, "end-of-line comment")
	eq(BuildError("use(#1) [self.bogus]") ~= nil, true, "unknown condition")
	eq(BuildError("use(#1) [!self.hp > 3]") ~= nil, true, "! on a comparison")
	eq(BuildError("use(#1) [self.dead = 3]") ~= nil, true, "value on yes/no")
	eq(BuildError("use(#1) [self.hp > lots]") ~= nil, true, "non-number value")
	eq(BuildError("use(#1) [hp > 3]") ~= nil, true, "owner required")
	eq(BuildError("use(#1) [self(#2).hp.low]") ~= nil, true, "no pet allowed")
	eq(BuildError("use(#1) [self.weather(Rain)]") ~= nil, true, "no owner allowed")
	eq(BuildError("use()") ~= nil, true, "use needs an ability")
end)

test("build error names the line", function()
	local err = BuildError("use(#1)\n\njump(#2)")
	eq(err:find("line 3", 1, true) ~= nil, true, err)
end)

test("comments, blank lines, a leading slash and ei", function()
	Build("-- hello\n\n/use(#1)\nif [round=1]\nuse(#2)\nei")
	eq(Next("-- use(#2)\n/use(#3)"), "ability 3")
end)

-- Choosing ------------------------------------------------------------------------------------------------------

test("first line that can act wins", function()
	eq(Next("use(#2)\nuse(#1)"), "ability 2")
end)

test("an ability on cooldown falls through", function()
	local b = Battle()
	b[1].pets[1].abilities[2].usable = false
	eq(Next("use(#2)\nuse(#1)", b), "ability 1")
end)

test("ability by name and by id", function()
	eq(Next("use(Howl)"), "ability 3")
	eq(Next("use(Whatever:102)"), "ability 2")
	eq(Next("use(102)"), "ability 2")
	eq(Next("use(Nope:999)\nuse(Nope)\nuse(#1)"), "ability 1")
end)

test("false condition skips the line", function()
	eq(Next("use(#2) [round=2]\nuse(#1)"), "ability 1")
end)

test("if block falls through when nothing inside acts", function()
	local b = Battle()
	b[1].pets[1].abilities[3].usable = false
	eq(Next("if [round=1]\nuse(#3)\nendif\nuse(#1)", b), "ability 1")
	eq(Next("if [round=2]\nuse(#2)\nendif\nuse(#1)"), "ability 1")
	eq(Next("if [round=1]\nuse(#2)\nendif\nuse(#1)"), "ability 2")
end)

test("nested if blocks", function()
	eq(Next("if [round=1]\nif [self.hp > 5]\nuse(#3)\nendif\nendif"), "ability 3")
	eq(Next("if [round=1]\nif [self.hp < 5]\nuse(#3)\nendif\nuse(#2)\nendif"), "ability 2")
end)

test("change to a pet", function()
	eq(Next("change(#2)"), "change 2")
	eq(Next("change(Gamma)"), "change 3")
	eq(Next("change(Beta:901)"), "change 2")
	eq(Next("change(#1)\nuse(#1)"), "ability 1") -- already active
end)

test("change(next) wraps and skips dead pets", function()
	local b = Battle()
	b[1].active = 3
	eq(Next("change(next)", b), "change 1")
	b[1].pets[1].health = 0
	eq(Next("change(next)", b), "change 2")
	b[1].pets[2].health = 0
	eq(Next("change(next)\nstandby", b), "skip")
end)

test("change needs a swap to be allowed", function()
	local b = Battle()
	b.canSwapOut = false
	eq(Next("change(#2)\nuse(#1)", b), "ability 1")
	b.petSelect = true
	eq(Next("change(#2)\nuse(#1)", b), "change 2") -- forced pick after a death
end)

test("a dead active pet: use fails, change picks", function()
	local b = Battle()
	b[1].pets[1].health = 0
	for _, a in ipairs(b[1].pets[1].abilities) do
		a.usable = false
	end
	b.canSwapOut, b.petSelect = false, true
	eq(Next("use(#1)\nchange(#2)", b), "change 2")
end)

test("standby, catch, quit, test", function()
	local b = Battle()
	eq(Next("standby", b), "skip")
	b.canSkip = false
	eq(Next("standby\nuse(#1)", b), "ability 1")
	eq(Next("catch\nuse(#1)", b), "ability 1")
	b.trap = { true, 0 }
	eq(Next("catch", b), "trap")
	eq(Next("quit"), "quit")
	eq(Next("test(hello)\nuse(#1)"), "test hello")
end)

test("nothing to do", function()
	local b = Battle()
	b.canSkip = false
	eq(Next("standby", b), "none")
end)

-- Conditions ----------------------------------------------------------------------------------------------------

test("health", function()
	local b = Battle()
	b[1].pets[1].health = 400
	b[2].pets[1].health = 900
	eq(Cond("self.hp = 400", b), true)
	eq(Cond("self.hp > 400", b), false)
	eq(Cond("self.hp >= 400 & self.hp <= 400", b), true)
	eq(Cond("self.hpp < 50", b), true)
	eq(Cond("enemy.hp.full", b), false)
	eq(Cond("self(#2).hp.full", b), true)
	eq(Cond("!self.hp.full", b), true)
	eq(Cond("self.hp.low", b), true)
	eq(Cond("self.hp.high", b), false)
	eq(Cond("self.hp.diff = -500", b), true)
	eq(Cond("self.hp.can_explode", b), true) -- 400 <= floor(1000 * 0.4)
	eq(Cond("enemy.hp.can_be_exploded", b), false)
	eq(Cond("self(#2).dead", b), false)
	b[1].pets[2].health = 0
	eq(Cond("self(#2).dead", b), true)
	eq(Cond("self(Beta).dead", b), true)
end)

test("auras on the pet and on the team pad", function()
	local b = Battle()
	b[2].pets[1].auras = { { id = 379, name = "Poisoned", turns = 2 } }
	b[1].pad = { { id = 590, name = "Shield", turns = 4 } }
	eq(Cond("enemy.aura(Poisoned:379).exists", b), true)
	eq(Cond("enemy.aura(Poisoned).exists", b), true)
	eq(Cond("enemy.aura(379).duration = 2", b), true)
	eq(Cond("self.aura(Shield).exists", b), true) -- found on the pad
	eq(Cond("self.aura(Shield).duration > 3", b), true)
	eq(Cond("!self.aura(Nope:1).exists", b), true)
	eq(Cond("self.aura(Nope:1).duration = 0", b), true)
end)

test("weather", function()
	local b = Battle()
	eq(Cond("weather(Rain)", b), false)
	b.weather = { id = 229, name = "Cleansing Rain", turns = 5 }
	eq(Cond("weather(Cleansing Rain:229)", b), true)
	eq(Cond("weather(Cleansing Rain).exists", b), true)
	eq(Cond("weather(229).duration >= 5", b), true)
	eq(Cond("weather(Sunny Day:403).duration = 0", b), true)
end)

test("abilities", function()
	local b = Battle()
	b[1].pets[1].abilities[2].usable = false
	b[1].pets[1].abilities[2].cd = 3
	eq(Cond("self.ability(Roar).usable", b), false)
	eq(Cond("self.ability(#2).duration = 3", b), true)
	eq(Cond("self.ability(Nope).duration > 99", b), true)
	eq(Cond("self.ability(Bite).strong", b), true) -- Beast vs the Critter foe
	eq(Cond("self.ability(Bite).weak", b), false)
	eq(Cond("self.ability(Bite).type = beast", b), true)
	eq(Cond("self.ability(Bite).type = 8", b), true)
	eq(Cond("enemy.ability(#1).usable", b), true)
	b[1].pets[1].abilities[1].noHints = true
	eq(Cond("self.ability(Bite).strong", b), false)
end)

test("stats, type, quality, identity", function()
	local b = Battle()
	b[2].pets[1].speed = 200
	eq(Cond("self.speed.fast", b), true)
	eq(Cond("self.speed.slow", b), false)
	eq(Cond("self.speed > 299", b), true)
	eq(Cond("self.power = 300 & self.level = 25 & self.level.max", b), true)
	eq(Cond("enemy.type = critter", b), true)
	eq(Cond("enemy.type ~ beast, critter", b), true)
	eq(Cond("enemy.type !~ beast, flying", b), true)
	eq(Cond("enemy.type != 5", b), false)
	eq(Cond("self.quality = rare", b), true) -- 0-based 3 = 4 Rare
	eq(Cond("self.quality >= 4", b), true)
	eq(Cond("enemy.id = 500", b), true)
	eq(Cond("enemy.is(Foe)", b), true)
	eq(Cond("enemy.is(500)", b), true)
	eq(Cond("self(#3).exists", b), true)
	eq(Cond("self(#4).exists", b), false)
	eq(Cond("self(#1).active & !self(#2).active", b), true)
end)

test("rounds and played", function()
	local b = Battle()
	b.round, b.rounds[1], b.rounds[2] = 4, 2, 4
	eq(Cond("round = 4", b), true)
	eq(Cond("round ~ 1, 4", b), true)
	eq(Cond("self.round = 2", b), true)
	eq(Cond("enemy.round < 3", b), false)
	b[1].pets[2].played = true
	eq(Cond("self(#2).played & !self(#3).played", b), true)
end)

test("collected", function()
	local b = Battle()
	eq(Cond("self.collected", b), true)
	eq(Cond("self.collected.count = 1", b), true)
	eq(Cond("self.collected.max = 3", b), true)
	eq(Cond("enemy.collected", b), false)
end)

test("trap", function()
	local b = Battle()
	eq(Cond("trap", b), false)
	b.trap = { false, 4 } -- too much health: trappable once lower
	eq(Cond("trap", b), true)
end)

test("a selector that matches nothing is false, not an error", function()
	local b = Battle()
	b[1].pets[3] = nil -- a two-pet team
	eq(Cond("self(#3).hp > 0", b), false)
	eq(Cond("self(#3).dead", b), false)
	eq(Cond("self(Nobody).hp.full", b), false)
	eq(Cond("self(#3).aura(Shield).exists", b), false)
	eq(Cond("self.ability(Nope).usable", b), false)
	eq(Cond("self.ability(Nope).strong", b), false)
	eq(Cond("self(#3).speed > 0", b), false)
	eq(Next("change(#3)\nuse(#2)", b), "ability 2")
end)

test("! on a pet that doesn't resolve", function()
	local b = Battle()
	b[1].pets[3] = nil
	eq(Cond("!self(#3).exists", b), true)
	eq(Cond("!self(#3).played", b), true)
	eq(Cond("!self(#3).dead", b), false) -- not nil-safe: false either way, as the spec decided
end)

-- A made-up script in the shape of real ones.
local SCRIPT = [[
-- Opening
standby [round=1]
change(#2) [round=2 & !self(#2).played]
if [self(#2).active]
    use(Roar:102) [!enemy.aura(Stunned:174).exists & self.round < 3]
    use(Howl:103) [enemy.hp.can_explode]
    use(Bite:101)
endif
change(Gamma:902) [self(#2).dead]
use(Bite:101) [self.ability(Bite).strong]
use(#1)
change(next)
]]

test("a full script plays turn by turn", function()
	local b = Battle()
	eq(Next(SCRIPT, b), "skip")
	b.round = 2
	eq(Next(SCRIPT, b), "change 2")
	b[1].active, b[1].pets[2].played, b.round, b.rounds[1] = 2, true, 3, 1
	eq(Next(SCRIPT, b), "ability 2")
	b[2].pets[1].auras = { { id = 174, name = "Stunned", turns = 1 } }
	eq(Next(SCRIPT, b), "ability 1")
	b[2].pets[1].health = 300
	eq(Next(SCRIPT, b), "ability 3")
	b[1].pets[2].health = 0
	for _, a in ipairs(b[1].pets[2].abilities) do
		a.usable = false
	end
	b.canSwapOut, b.petSelect = false, true
	eq(Next(SCRIPT, b), "change 3")
end)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
