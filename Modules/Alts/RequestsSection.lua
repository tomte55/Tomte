local addonName, ns = ...

-- Friend crafting: the "Craft requests" section at the top of the Crafting list tab (ListTab.lua draws it first).
-- One row per request, yours and your friends', with what happens next in words and the buttons that move it on:
-- Accept / Decline for a friend's new ask, Cancel for your open ones, Clear once it's over. The requests and their
-- messages are Friends.lua's.

local ROW_H = 40
local HEADER_H = 28
local BUTTON_W = 74

local UI = ns.UI

local header
local rows = {}

local function Who(req)
	return req.friend and req.friend:match("^[^#]+") or "?"
end

-- What a request is waiting for, in words.
local function StateText(req)
	local friend, s = Who(req), req.state
	if req.mine then
		if s == "waiting" then
			return ("Waiting for %s to come online"):format(friend), "textMuted"
		elseif s == "sent" then
			return ("Sent to %s"):format(friend), "textMuted"
		elseif s == "delivered" then
			return ("%s has it"):format(friend), "text"
		elseif s == "accepted" then
			return ("%s accepted%s"):format(friend, req.mats and not req.matsSent and ": mail the materials" or ""), "success"
		elseif s == "made" then
			return ("%s made it: it comes by mail"):format(friend), "success"
		end
	else
		if s == "delivered" then
			return ("%s asks %s%s"):format(req.asker or friend, req.crafter or "you",
				req.mats and " and mails the materials" or ", with your materials"), "warning"
		elseif s == "accepted" then
			return "You accepted: it's on your crafting list", "success"
		elseif s == "made" then
			return ("Made: mail it to %s"):format(req.asker or friend), "success"
		end
	end
	if s == "done" then
		return "Done", "textMuted"
	elseif s == "declined" then
		return "Declined" .. (req.note and (": " .. req.note) or ""), "danger"
	end
	return "Cancelled", "textMuted"
end

local function Buttons(row, req)
	local open = ns.AltsFriends_Open(req)
	local first, second
	if not open then
		first = { "Clear", function()
			ns.AltsFriends_Clear(req.id)
		end }
	elseif not req.mine and req.state == "delivered" then
		first = { "Accept", function()
			UI.Sound("confirm")
			ns.AltsFriends_Answer(req.id, "accepted")
		end }
		second = { "Decline", function()
			ns.AltsFriends_Answer(req.id, "declined")
		end }
	elseif not req.mine then
		-- Accepted or made: Done when it reached them some other way (traded, an enchant, a craft that binds), or Decline.
		first = { "Done", function()
			ns.AltsFriends_Answer(req.id, "done")
		end }
		second = { "Decline", function()
			ns.AltsFriends_Answer(req.id, "declined")
		end }
	else
		first = { CANCEL, function()
			ns.Confirm_Show(("Cancel the request for %s?"):format(ns.AltsFriends_RecipeName(req)), function()
				ns.AltsFriends_Answer(req.id, "cancel")
			end)
		end }
	end
	for i, spec in ipairs({ first or false, second or false }) do
		local b = row.buttons[i]
		b:SetShown(spec ~= false)
		if spec then
			b.label:SetText(spec[1])
			b:SetScript("OnClick", spec[2])
		end
	end
end

local function CreateRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(ROW_H)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(UI.Color("surface"))
	row.bg:SetAlpha(0.35)
	row.buttons = {}
	for i = 1, 2 do
		local b = UI.Button(row, BUTTON_W, "")
		b:SetHeight(20)
		b:SetPoint("RIGHT", i == 1 and -6 or -(12 + BUTTON_W), 0)
		row.buttons[i] = b
	end
	row.title = UI.Text(row, 13, "text")
	row.title:SetPoint("TOPLEFT", 8, -5)
	row.title:SetPoint("RIGHT", -(18 + 2 * BUTTON_W), 0)
	row.title:SetWordWrap(false)
	row.sub = UI.Text(row, 11, "textMuted")
	row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
	row.sub:SetPoint("RIGHT", -(18 + 2 * BUTTON_W), 0)
	row.sub:SetWordWrap(false)
	return row
end

-- Draws the section at y in parent, width wide. Returns the y below it (y unchanged with no requests).
function ns.AltsRequests_Draw(parent, y, width)
	for _, row in ipairs(rows) do
		row:Hide()
	end
	if header then
		header:Hide()
	end
	local list = ns.AltsFriends_Requests()
	if #list == 0 then
		return y
	end
	header = header or UI.Text(parent, 14, "heading")
	header:SetText("Craft requests")
	header:ClearAllPoints()
	header:SetPoint("TOPLEFT", 2, -(y + 6))
	header:Show()
	y = y + HEADER_H
	for i, req in ipairs(list) do
		local row = rows[i] or CreateRow(parent)
		rows[i] = row
		row.bg:SetColorTexture(UI.Color("surface")) -- a theme switch reaches it
		local amount = (req.amount or 1) > 1 and (" x" .. req.amount) or ""
		row.title:SetText(ns.AltsFriends_RecipeName(req) .. amount)
		local text, role = StateText(req)
		row.sub:SetText(text)
		UI.SetTextRole(row.sub, role)
		Buttons(row, req)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -y)
		row:SetWidth(width)
		row:Show()
		y = y + ROW_H + 4
	end
	return y + 8
end
