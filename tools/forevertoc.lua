-- Writes World of Warcraft: Forever's TOC from Tomte.toc and tools/forever_list.lua (rules in tools/forever_build.lua).
-- Run from the AddOns folder: lua Tomte/tools/forevertoc.lua
local ForeverToc = dofile("Tomte/tools/forever_build.lua")
local list = dofile("Tomte/tools/forever_list.lua")

local lines = {}
for line in io.lines("Tomte/Tomte.toc") do
	lines[#lines + 1] = (line:gsub("\r$", ""))
end
local out = ForeverToc.Build(lines, list)
local file = assert(io.open("Tomte/" .. list.name, "wb"))
file:write(table.concat(out, "\r\n") .. "\r\n")
file:close()
local files = 0
for _, line in ipairs(out) do
	if line:match("%.lua$") then
		files = files + 1
	end
end
print(("%s: %d files"):format(list.name, files))
