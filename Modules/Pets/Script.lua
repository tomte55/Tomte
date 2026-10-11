local addonName, ns = ...

-- Pet Battles: an interpreter for the Pet Battle Scripts language (the scripts Xu-Fu's Pet Guides ships with its
-- strategies). Written for Tomte from the language as Pet Battle Scripts (axc450/pbs, MIT; formerly
-- tdBattlePetScript) defines it in its source; no code is taken from it. Pure: the battle is read through an `api`
-- object (Battle.lua has the live one, tests/test_petscript.lua a fake one).
--
-- Each call to PetScript_Next reads the whole script from the top and returns the first action whose line's
-- conditions hold and that can be done right now (an ability on cooldown, a swap that isn't allowed and so on fall
-- through to the next line). It never acts: the caller does the action on a key press, so the same call is also the
-- preview shown on the Next move button.
--
-- Lines: `action [cond & cond]`, `if [cond]` ... `endif` (or `ei`), `-- comment`, an optional leading `/`.
-- Actions: use(x) / ability(x), change(x | next), standby, catch, quit, test(text).
-- A condition: [!]api [op value]; api = [self|ally|enemy[(pet)].]name[(arg)][.minor]. Operators by condition type:
-- yes/no (! allowed, no value), compare (= == != > < >= <= ~ !~) and equality (= == != ~ !~). `~` takes a list.
-- Ids are written Name:123 (the name is only a label). A pet or ability that doesn't resolve makes its condition false.
--
-- api methods (owner 1 = you, 2 = the enemy; pet index 1-3; ability slot 1-3):
--   NumPets(o) Active(o) Health(o,i) MaxHealth(o,i) Speed(o,i) Power(o,i) Level(o,i) Type(o,i) Quality(o,i) (0-based)
--   Species(o,i) Name(o,i) Ability(o,i,s) -> id, name, type, noHints  AbilityState(o,i,s) -> usable, cd, lockdown
--   Auras(o,i), PadAuras(o) -> { { id, name, turns } }  Weather() -> id, name, turns  Modifier(atk, def)
--   CanSwapOut() PetSelect() CanSwapIn(i) CanSkip() Trap() -> usable, err  Round(o|nil) Played(o,i)
--   Collected(o,i) -> owned, max, obtainable  TypeOf(name) QualityOf(name) -> number (localized names, lowercase)

local ALLY, ENEMY = 1, 2
local OWNERS = { self = ALLY, ally = ALLY, enemy = ENEMY }
local TRAP_TOO_HEALTHY = 4 -- C_PetBattles.IsTrapAvailable's error: the pet has too much health

local function Trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- "Name:123" -> 123; a bare number -> that number; otherwise nil.
local function ID(x)
	if type(x) ~= "string" then
		return nil
	end
	return tonumber(x:match(":(%d+)$") or "") or tonumber(x)
end

-- Resolving pets and abilities ---------------------------------------------------------------------------------

local function PetIndex(api, owner, sel)
	local n = api:NumPets(owner) or 0
	if not sel then
		local active = api:Active(owner)
		return active and active >= 1 and active <= n and active or nil
	end
	local slot = sel:match("^#(%d+)$")
	if slot then
		slot = tonumber(slot)
		return slot >= 1 and slot <= n and slot or nil
	end
	local id = ID(sel)
	local function Match(i)
		return api:Name(owner, i) == sel or (id ~= nil and api:Species(owner, i) == id)
	end
	local active = api:Active(owner)
	if active and active >= 1 and active <= n and Match(active) then
		return active
	end
	for i = 1, n do
		if Match(i) then
			return i
		end
	end
	return nil
end

-- The slot of ability x on that pet: by #n, id or name; the first usable match, else the one coming off cooldown
-- soonest.
local function AbilitySlot(api, owner, pet, x)
	if not (pet and x) then
		return nil
	end
	local slot = x:match("^#(%d+)$")
	if slot then
		slot = tonumber(slot)
		return slot >= 1 and slot <= 3 and slot or nil
	end
	local id = ID(x)
	local best, bestWait
	for s = 1, 3 do
		local aid, name = api:Ability(owner, pet, s)
		if aid and (aid == id or name == x) then
			local usable, cd, lockdown = api:AbilityState(owner, pet, s)
			if usable then
				return s
			end
			local wait = math.max(cd or 0, lockdown or 0)
			if not bestWait or wait < bestWait then
				best, bestWait = s, wait
			end
		end
	end
	return best
end

local function FindAura(api, owner, pet, x)
	local id = ID(x)
	local function Search(list)
		for _, a in ipairs(list or {}) do
			if a.id == id or a.name == x then
				return a
			end
		end
	end
	return Search(api:Auras(owner, pet)) or Search(api:PadAuras(owner))
end

local function Opponent(owner)
	return owner == ALLY and ENEMY or ALLY
end

local function Hpp(api, owner, pet)
	local max = api:MaxHealth(owner, pet)
	return max and max > 0 and api:Health(owner, pet) / max * 100 or 0
end

local function AbilityModifier(api, owner, pet, slot)
	local _, _, atkType, noHints = api:Ability(owner, pet, slot)
	if not atkType or noHints then
		return 1
	end
	local opp = Opponent(owner)
	local enemyPet = api:Active(opp)
	return enemyPet and api:Modifier(atkType, api:Type(opp, enemyPet)) or 1
end

-- Conditions ---------------------------------------------------------------------------------------------------

-- Each: type ("bool" | "compare" | "equal"), owner ("required" | "none" | "optional"), pet (a (pet) is allowed),
-- arg ("required" | nil = not allowed), value ("type" | "quality" | nil = numbers), nilPet (value when the pet doesn't
-- resolve; default false for every operator), nilSafe (a yes/no condition that is false, not skipped, for a pet that
-- doesn't resolve, so `!` applies), fn(api, owner, pet, arg) -> value.
-- `pet` reaches fn resolved (nil only when nilPet says how to handle it); `arg` is the raw text.
local C = {}

local function Def(names, spec)
	spec.owner = spec.owner or "required"
	if spec.pet == nil then
		spec.pet = true
	end
	for name in names:gmatch("[^ ]+") do
		C[name] = spec
	end
end

Def("dead", { type = "bool", fn = function(api, o, p)
	return api:Health(o, p) == 0
end })
Def("hp", { type = "compare", fn = function(api, o, p)
	return api:Health(o, p)
end })
Def("hp.full", { type = "bool", fn = function(api, o, p)
	return api:Health(o, p) == api:MaxHealth(o, p)
end })
-- Low enough to die to the enemy pet's explosion (Pet Battle Scripts' 40% of the exploding pet's max health).
Def("hp.can_explode hp.can_be_exploded", { type = "bool", nilSafe = true, fn = function(api, o, p)
	local opp = Opponent(o)
	local oppPet = api:Active(opp)
	return oppPet ~= nil and api:Health(o, p) <= math.floor(api:MaxHealth(opp, oppPet) * 0.4)
end })
Def("hp.low", { type = "bool", pet = false, fn = function(api, o, p)
	local opp = Opponent(o)
	local oppPet = api:Active(opp)
	return oppPet ~= nil and api:Health(o, p) < api:Health(opp, oppPet)
end })
Def("hp.high", { type = "bool", pet = false, fn = function(api, o, p)
	local opp = Opponent(o)
	local oppPet = api:Active(opp)
	return oppPet ~= nil and api:Health(o, p) > api:Health(opp, oppPet)
end })
Def("hpp", { type = "compare", fn = function(api, o, p)
	return Hpp(api, o, p)
end })
Def("hp.diff", { type = "compare", fn = function(api, o, p)
	local opp = Opponent(o)
	local oppPet = api:Active(opp)
	return oppPet and api:Health(o, p) - api:Health(opp, oppPet)
end })
Def("hpp.diff", { type = "compare", fn = function(api, o, p)
	local opp = Opponent(o)
	local oppPet = api:Active(opp)
	return oppPet and Hpp(api, o, p) - Hpp(api, opp, oppPet)
end })
Def("aura.exists", { type = "bool", arg = "required", fn = function(api, o, p, x)
	return FindAura(api, o, p, x) ~= nil
end })
Def("aura.duration", { type = "compare", arg = "required", nilPet = 0, fn = function(api, o, p, x)
	local a = FindAura(api, o, p, x)
	return a and a.turns or 0
end })
Def("weather weather.exists", { type = "bool", owner = "none", pet = false, arg = "required",
	fn = function(api, _, _, x)
		local id, name = api:Weather()
		return id ~= nil and (id == ID(x) or name == x)
	end })
Def("weather.duration", { type = "compare", owner = "none", pet = false, arg = "required",
	fn = function(api, _, _, x)
		local id, name, turns = api:Weather()
		return (id ~= nil and (id == ID(x) or name == x)) and turns or 0
	end })
-- Abilities: fn gets the resolved slot as its 4th argument (nil when it doesn't resolve).
Def("ability.usable", { type = "bool", arg = "required", ability = true, fn = function(api, o, p, s)
	return s ~= nil and api:AbilityState(o, p, s) and true or false
end })
Def("ability.duration", { type = "compare", arg = "required", ability = true, nilPet = math.huge,
	fn = function(api, o, p, s)
		if not s then
			return math.huge
		end
		local _, cd, lockdown = api:AbilityState(o, p, s)
		return math.max(cd or 0, lockdown or 0)
	end })
Def("ability.strong", { type = "bool", arg = "required", ability = true, fn = function(api, o, p, s)
	return s ~= nil and AbilityModifier(api, o, p, s) > 1
end })
Def("ability.weak", { type = "bool", arg = "required", ability = true, fn = function(api, o, p, s)
	return s ~= nil and AbilityModifier(api, o, p, s) < 1
end })
Def("ability.type", { type = "equal", arg = "required", ability = true, value = "type", fn = function(api, o, p, s)
	if s then
		local _, _, t = api:Ability(o, p, s)
		return t
	end
end })
Def("speed", { type = "compare", fn = function(api, o, p)
	return api:Speed(o, p)
end })
Def("power", { type = "compare", fn = function(api, o, p)
	return api:Power(o, p)
end })
Def("level", { type = "compare", fn = function(api, o, p)
	return api:Level(o, p)
end })
Def("level.max", { type = "bool", nilSafe = true, fn = function(api, o, p)
	return api:Level(o, p) == ns.PETS_MAX_LEVEL -- Data.lua
end })
Def("speed.fast", { type = "bool", pet = false, fn = function(api, o, p)
	local opp = Opponent(o)
	local oppPet = api:Active(opp)
	return oppPet ~= nil and api:Speed(o, p) > api:Speed(opp, oppPet)
end })
Def("speed.slow", { type = "bool", pet = false, fn = function(api, o, p)
	local opp = Opponent(o)
	local oppPet = api:Active(opp)
	return oppPet ~= nil and api:Speed(o, p) < api:Speed(opp, oppPet)
end })
Def("type", { type = "equal", value = "type", fn = function(api, o, p)
	return api:Type(o, p)
end })
Def("quality", { type = "compare", value = "quality", fn = function(api, o, p)
	return (api:Quality(o, p) or 0) + 1
end })
Def("id", { type = "equal", nilPet = 0, fn = function(api, o, p)
	return api:Species(o, p)
end })
Def("is", { type = "bool", nilSafe = true, arg = "required", fn = function(api, o, p, x)
	return api:Name(o, p) == x or api:Species(o, p) == ID(x)
end })
Def("exists", { type = "bool", nilSafe = true, fn = function()
	return true
end })
Def("active", { type = "bool", fn = function(api, o, p)
	return api:Active(o) == p
end })
Def("played", { type = "bool", nilSafe = true, fn = function(api, o, p)
	return api:Played(o, p) and true or false
end })
Def("collected", { type = "bool", fn = function(api, o, p)
	local owned = api:Collected(o, p)
	return (owned or 0) > 0
end })
Def("collected.count", { type = "compare", nilPet = 0, fn = function(api, o, p)
	local owned, _, obtainable = api:Collected(o, p)
	return obtainable and owned or 0
end })
Def("collected.max", { type = "compare", nilPet = 0, fn = function(api, o, p)
	local _, max, obtainable = api:Collected(o, p)
	return obtainable and max or 0
end })
Def("trap", { type = "bool", owner = "none", pet = false, fn = function(api)
	local usable, err = api:Trap()
	return usable and true or err == TRAP_TOO_HEALTHY
end })
Def("round", { type = "compare", owner = "optional", pet = false, fn = function(api, o)
	return api:Round(o)
end })

local OPS = {
	compare = { ["="] = true, ["=="] = true, ["!="] = true, [">"] = true, ["<"] = true, [">="] = true, ["<="] = true,
		["~"] = true, ["!~"] = true },
	equal = { ["="] = true, ["=="] = true, ["!="] = true, ["~"] = true, ["!~"] = true },
}

local function Compare(op, a, b)
	if op == "=" or op == "==" then
		return a == b
	elseif op == "!=" then
		return a ~= b
	end
	if type(a) ~= "number" or type(b) ~= "number" then
		return false
	end
	if op == ">" then
		return a > b
	elseif op == "<" then
		return a < b
	elseif op == ">=" then
		return a >= b
	elseif op == "<=" then
		return a <= b
	end
	return false
end

-- A value as written: a number, or a lowercase name resolved through the api when the condition runs (family and
-- quality names are localized, so they can't be checked while building).
local function ParseValue(text, kind)
	local n = ID(text)
	if n then
		return n
	end
	if kind == "type" or kind == "quality" then
		return { name = text:lower() }
	end
	return nil
end

local function ResolveValue(api, v, kind)
	if type(v) ~= "table" then
		return v
	end
	if kind == "type" then
		return api:TypeOf(v.name)
	end
	return api:QualityOf(v.name)
end

-- Splits "a.b(c.d).e" on dots outside parentheses.
local function Segments(text)
	local out, depth, start = {}, 0, 1
	for i = 1, #text do
		local ch = text:sub(i, i)
		if ch == "(" then
			depth = depth + 1
		elseif ch == ")" then
			depth = math.max(depth - 1, 0)
		elseif ch == "." and depth == 0 then
			out[#out + 1] = text:sub(start, i - 1)
			start = i + 1
		end
	end
	out[#out + 1] = text:sub(start)
	return out
end

local function Call(seg)
	local name, arg = seg:match("^([^()]+)%((.*)%)$")
	if name then
		return Trim(name), arg
	end
	return Trim(seg), nil
end

-- One condition's text -> a parsed condition, or nil and why.
local function ParseCondition(text)
	local neg, api, op, value = text:match("^(!?)([^!=<>~]+)%s*([!=<>~]*)%s*(.*)$")
	if not api then
		return nil, "can't read condition `" .. text .. "`"
	end
	local segs = Segments(Trim(api))
	local cond = { neg = neg == "!", op = op ~= "" and op or nil, text = text }
	local first, sel = Call(segs[1])
	local i = 1
	if OWNERS[first] then
		cond.owner, cond.sel, i = OWNERS[first], sel, 2
	end
	local cmd, arg = Call(segs[i] or "")
	local minor = segs[i + 1] and Trim(segs[i + 1]) or nil
	local name = minor and (cmd .. "." .. minor) or cmd
	local spec = C[name]
	if not spec and minor then -- extra segments are ignored, as Pet Battle Scripts does
		spec, name = C[cmd], cmd
	end
	if not spec then
		return nil, "unknown condition `" .. Trim(api) .. "`"
	end
	cond.spec, cond.arg = spec, arg
	if spec.owner == "required" and not cond.owner then
		return nil, "`" .. name .. "` needs self or enemy"
	elseif spec.owner == "none" and cond.owner then
		return nil, "`" .. name .. "` takes no self or enemy"
	end
	if cond.sel and not spec.pet then
		return nil, "`" .. name .. "` takes no pet"
	end
	if spec.arg == "required" and not arg then
		return nil, "`" .. name .. "` needs (...)"
	elseif not spec.arg and arg then
		return nil, "`" .. name .. "` takes no (...)"
	end
	if spec.type == "bool" then
		if cond.op or value ~= "" then
			return nil, "`" .. name .. "` is yes/no and takes no value"
		end
	else
		if cond.neg then
			return nil, "`!` only goes on yes/no conditions"
		end
		if not (cond.op and OPS[spec.type][cond.op]) then
			return nil, "bad operator in `" .. text .. "`"
		end
		value = Trim(value)
		if cond.op == "~" or cond.op == "!~" then
			cond.list = {}
			for item in value:gmatch("[^,]+") do
				local v = ParseValue(Trim(item), spec.value)
				if v == nil then
					return nil, "bad value `" .. item .. "`"
				end
				cond.list[#cond.list + 1] = v
			end
		else
			cond.value = ParseValue(value, spec.value)
			if cond.value == nil then
				return nil, "bad value `" .. value .. "`"
			end
		end
	end
	return cond
end

local function Test(api, cond)
	local spec = cond.spec
	local owner = cond.owner
	local pet
	if spec.owner ~= "none" and owner then
		pet = PetIndex(api, owner, cond.sel)
		if not pet then
			-- A pet that doesn't resolve: false, except for the yes/no conditions Pet Battle Scripts reads safely
			-- (exists, played, is, ...), which are false and take their `!` as usual.
			if spec.type == "bool" and not spec.nilSafe then
				return false
			elseif spec.type ~= "bool" and spec.nilPet == nil then
				return false
			end
		end
	end
	local result
	if pet or spec.owner == "none" or not owner then
		local arg = cond.arg
		if spec.ability then
			arg = AbilitySlot(api, owner, pet, arg)
		end
		result = spec.fn(api, owner, pet, arg)
	elseif spec.type == "bool" then
		result = false
	else
		result = spec.nilPet
	end
	if spec.type == "bool" then
		result = result and true or false
		if cond.neg then
			return not result
		end
		return result
	end
	if result == nil then
		return false
	end
	if cond.list then
		local found = false
		for _, v in ipairs(cond.list) do
			if result == ResolveValue(api, v, spec.value) then
				found = true
			end
		end
		if cond.op == "~" then
			return found
		end
		return not found
	end
	return Compare(cond.op, result, ResolveValue(api, cond.value, spec.value))
end

local function AllHold(api, conds)
	for _, cond in ipairs(conds) do
		if not Test(api, cond) then
			return false
		end
	end
	return true
end

-- Actions ------------------------------------------------------------------------------------------------------

local ACTIONS = { use = "use", ability = "use", change = "change", standby = "standby", catch = "catch", quit = "quit",
	test = "test" }
local NEEDS_ARG = { use = true, change = true }

local function ParseAction(text)
	local cmd, arg = text:match("^([^()]-)%s*%((.+)%)$")
	if not cmd then
		cmd = text
	end
	local kind = ACTIONS[cmd]
	if not kind then
		return nil, "unknown command `" .. text .. "`"
	end
	if NEEDS_ARG[kind] and not arg then
		return nil, "`" .. cmd .. "` needs (...)"
	end
	return { kind = kind, arg = arg }
end

local function NextPet(api)
	local n = api:NumPets(ALLY) or 0
	local active = api:Active(ALLY)
	if not active or n == 0 then
		return nil
	end
	local i = active
	repeat
		i = i % n + 1
		if i ~= active and api:Health(ALLY, i) ~= 0 and api:CanSwapIn(i) then
			return i
		end
	until i == active
	return nil
end

local function TryAction(api, action)
	local kind = action.kind
	if kind == "use" then
		local active = PetIndex(api, ALLY, nil)
		local slot = AbilitySlot(api, ALLY, active, action.arg)
		if slot and api:AbilityState(ALLY, active, slot) then
			return { kind = "ability", slot = slot }
		end
	elseif kind == "change" then
		local active = api:Active(ALLY)
		local target
		if action.arg == "next" then
			target = NextPet(api)
		else
			target = PetIndex(api, ALLY, action.arg)
		end
		if target and target ~= active and (api:CanSwapOut() or api:PetSelect()) and api:CanSwapIn(target) then
			return { kind = "change", pet = target }
		end
	elseif kind == "standby" then
		if api:CanSkip() then
			return { kind = "skip" }
		end
	elseif kind == "catch" then
		if api:Trap() then
			return { kind = "trap" }
		end
	elseif kind == "quit" then
		return { kind = "quit" }
	elseif kind == "test" then
		return { kind = "test", text = action.arg }
	end
	return nil
end

-- Building and running -----------------------------------------------------------------------------------------

-- code -> script, or nil and "line N: why".
function ns.PetScript_Build(code)
	if type(code) ~= "string" then
		return nil, "no script"
	end
	local root = { items = {} }
	local stack = { root }
	local lineNo = 0
	for raw in (code .. "\n"):gmatch("([^\n]*)\n") do
		lineNo = lineNo + 1
		local line = Trim(raw:gsub("\r", ""))
		local function Fail(why)
			return nil, ("line %d: %s"):format(lineNo, why)
		end
		if line ~= "" and not line:find("^%-%-") then
			line = line:gsub("^/", "")
			local actionText, condText
			if line:find("[", 1, true) then
				actionText, condText = line:match("^([^%[]-)%s*%[([^%]]+)%]$")
				if not actionText then
					return Fail("can't read `" .. line .. "`")
				end
			else
				actionText = line
			end
			actionText = Trim(actionText)
			local conds = {}
			for part in (condText or ""):gmatch("[^&]+") do
				part = Trim(part)
				if part ~= "" then
					local cond, err = ParseCondition(part)
					if not cond then
						return Fail(err)
					end
					conds[#conds + 1] = cond
				end
			end
			local top = stack[#stack]
			if actionText == "if" then
				local block = { items = {} }
				top.items[#top.items + 1] = { conds = conds, block = block }
				stack[#stack + 1] = block
			elseif actionText == "endif" or actionText == "ei" then
				if #stack == 1 then
					return Fail("endif without if")
				end
				stack[#stack] = nil
			else
				local action, err = ParseAction(actionText)
				if not action then
					return Fail(err)
				end
				top.items[#top.items + 1] = { conds = conds, action = action }
			end
		end
	end
	if #stack > 1 then
		return nil, "an if has no endif"
	end
	return root
end

local function Walk(api, block)
	for _, item in ipairs(block.items) do
		if AllHold(api, item.conds) then
			local result
			if item.block then
				result = Walk(api, item.block)
			else
				result = TryAction(api, item.action)
			end
			if result then
				return result
			end
		end
	end
	return nil
end

-- The action the script picks right now, or nil when no line can act.
function ns.PetScript_Next(script, api)
	return Walk(api, script)
end
