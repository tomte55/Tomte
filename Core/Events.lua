local addonName, ns = ...

-- One event frame per module, shared by its files. Each file is an owner: it attaches handlers once (On, at file
-- load) and says when it wants an event (Watch / Unwatch, from its Start/Stop). The frame registers an event while
-- any owner watches it and calls only the watching owners' handlers, in attach order (TOC order across files).
-- The first watcher's unit filter applies to every owner of that event: don't mix filtered and plain watches of one event.
-- A handler that errors is reported (ns.errorHandler) and the next ones still run.
-- Unit-tested with a CreateFrame stub (tests/test_eventbus.lua).

function ns.NewEvents()
	local frame = CreateFrame("Frame")
	local handlers = {} -- [event] = { { owner = owner, fn = fn }, ... }
	local watchers = {} -- [event] = { [owner] = true }
	local bus = { frame = frame }

	frame:SetScript("OnEvent", function(_, event, ...)
		local list, watching = handlers[event], watchers[event]
		if not list or not watching then
			return
		end
		for i = 1, #list do
			local h = list[i]
			if watching[h.owner] then
				-- One handler's error goes to BugSack and the others still run. ns.errorHandler is looked up per
				-- call: Core.lua sets it after this file loads.
				xpcall(h.fn, ns.errorHandler, bus, ...)
			end
		end
	end)

	function bus:On(owner, event, fn)
		handlers[event] = handlers[event] or {}
		table.insert(handlers[event], { owner = owner, fn = fn })
	end

	local function Count(event)
		local n = 0
		for _ in pairs(watchers[event] or {}) do
			n = n + 1
		end
		return n
	end

	function bus:Watch(owner, event, unit1, unit2)
		if Count(event) == 0 then
			if unit1 then
				frame:RegisterUnitEvent(event, unit1, unit2)
			else
				frame:RegisterEvent(event)
			end
		end
		watchers[event] = watchers[event] or {}
		watchers[event][owner] = true
	end

	-- For events this client may not have: false when the frame refused it.
	function bus:TryWatch(owner, event)
		local ok = pcall(bus.Watch, bus, owner, event)
		if not ok and watchers[event] then
			watchers[event][owner] = nil
		end
		return ok
	end

	function bus:Unwatch(owner, event)
		local watching = watchers[event]
		if not watching or not watching[owner] then
			return
		end
		watching[owner] = nil
		if Count(event) == 0 then
			frame:UnregisterEvent(event)
		end
	end

	function bus:UnwatchAll(owner)
		for event in pairs(watchers) do
			bus:Unwatch(owner, event)
		end
	end

	function bus:Watching(owner, event)
		return watchers[event] ~= nil and watchers[event][owner] == true
	end

	return bus
end
