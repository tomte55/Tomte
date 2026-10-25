-- Forever TOC: builds World of Warcraft: Forever's TOC from Tomte.toc, so both load in the same order and a new
-- retail file never sneaks in. Pure (no I/O; unit-tested in tests/test_forevertoc.lua). The list of what Forever
-- loads is tools/forever_list.lua; tools/forevertoc.lua writes the file.
-- See docs/superpowers/specs/2026-10-25-tomte-forever-design.md.

local M = {}

local function StartsWithAny(path, prefixes)
	for _, prefix in ipairs(prefixes or {}) do
		if path:sub(1, #prefix) == prefix then
			return true
		end
	end
	return false
end

local function IsFile(line)
	return line:match("^[%w_/\\]+%.lua$") or line:match("^[%w_/\\]+%.xml$")
end

-- retailLines: Tomte.toc's lines (no line ends). list: { interface, keep, drop, extra } (tools/forever_list.lua).
function M.Build(retailLines, list)
	local extraAfter = {}
	for _, extra in ipairs(list.extra or {}) do
		extraAfter[extra.after] = extra.files
	end
	local out = {}
	for _, line in ipairs(retailLines) do
		if line:match("^## Interface:") then
			out[#out + 1] = "## Interface: " .. list.interface
		elseif line:match("^## Version:") then
			out[#out + 1] = line
			out[#out + 1] = "## X-Tomte-Flavor: forever"
		elseif IsFile(line) then
			local path = line:gsub("\\", "/")
			if StartsWithAny(path, list.keep) and not StartsWithAny(path, list.drop) then
				out[#out + 1] = line
				for _, file in ipairs(extraAfter[path] or {}) do
					out[#out + 1] = file
				end
			end
		else
			out[#out + 1] = line
		end
	end
	return out
end

return M
