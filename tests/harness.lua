-- Shared helpers for the plain-Lua unit tests. Load from the AddOns folder:
--   local H = dofile("Tomte/tests/harness.lua")
--   local test, eq = H.test, H.eq
--   ... tests ...
--   H.done()
local H = { failures = 0 }

-- WoW's xpcall passes extra arguments on to the function (xpcall(fn, handler, ...)); Lua 5.1's (CI) drops them.
-- The addon's code relies on WoW's behaviour, so the tests get it too.
if _VERSION == "Lua 5.1" then
	local xpcall51 = xpcall
	xpcall = function(fn, handler, ...)
		local n, args = select("#", ...), { ... }
		return xpcall51(function()
			return fn(unpack(args, 1, n))
		end, handler)
	end
end

function H.test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		print("ok   " .. name)
	else
		H.failures = H.failures + 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end

function H.eq(actual, expected, label)
	if actual ~= expected then
		error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end

function H.near(actual, expected, label)
	if math.abs(actual - expected) > 0.001 then
		error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end

-- Ends the run: exit code 1 when anything failed (CI runs each file under bash -e).
function H.done()
	if H.failures > 0 then
		print(H.failures .. " failed")
		os.exit(1)
	end
	print("all passed")
end

return H
