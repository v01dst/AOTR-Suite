--[[
	AOTR Suite :: GameUI
	Everything that touches the game's own interface.

	Verified layout of Attack on Titan: Revolution (place 13379208636 / 14916516914):

		PlayerGui.Interface
		  .Title_Screen
		    .Slots.A.Select_A
		    .Buttons.Play
		  .Warning.Prompt.Main.No
		  .Missions
		    .Prompt.Selection.Missions
		    .Missions.Main.Maps.Maps.<Map>_Missions
		    .Missions.Main.Info.Main.Buttons.Creation_Missions
		    .Info.Main.Info.Modifiers.Modifiers_Buttons
		    .Info.Main.Info.Modifiers.Options.<Modifier>
		    .Info.Main.Info.Main.Info_Buttons.Begin
		  .Rewards
		    .Main.Info.Main.Buttons.Retry
		    .Main.Info.Main.Buttons.Leave_2
		  .HUD.Main.Top["7"].Blades.Inner.Bar.Gradient
		  .HUD.Main.Top["7"].Gas.Inner.Bar.Gradient

	Paths change between game updates, so every lookup has a keyword based
	fallback that searches the interface tree instead of trusting a path.
]]

return function(Ctx)
	local Util = Ctx.Util
	local GameUI = {}

	local Players = game:GetService("Players")

	local function playerGui()
		local player = Util.LocalPlayer or Players.LocalPlayer
		if not player then
			return nil
		end
		return player:FindFirstChildOfClass("PlayerGui")
	end

	------------------------------------------------------------------
	-- Core lookups
	------------------------------------------------------------------

	GameUI.interface = function()
		local gui = playerGui()
		if not gui then
			return nil
		end
		return gui:FindFirstChild("Interface") or gui
	end

	GameUI.find = function(path)
		local root = GameUI.interface()
		if not root then
			return nil
		end
		local node = root
		for segment in string.gmatch(path, "[^%.]+") do
			node = node:FindFirstChild(segment)
			if not node then
				return nil
			end
		end
		return node
	end

	GameUI.missions = function()
		return GameUI.find("Missions")
	end

	GameUI.rewards = function()
		return GameUI.find("Rewards")
	end

	GameUI.hud = function()
		return GameUI.find("HUD")
	end

	GameUI.titleScreen = function()
		return GameUI.find("Title_Screen")
	end

	------------------------------------------------------------------
	-- Keyword driven search
	------------------------------------------------------------------

	local CLICKABLE = { "TextButton", "ImageButton" }

	local function labelOf(object)
		local text = ""
		if object:IsA("TextLabel") or object:IsA("TextButton") then
			text = object.Text or ""
		elseif object:IsA("ImageButton") or object:IsA("ImageLabel") then
			text = object.ImageLabel and object.ImageLabel.Text or ""
		end
		return (text .. " " .. object.Name):lower()
	end

	-- Finds clickable elements whose text or name contains any keyword.
	GameUI.findClickables = function(root, keywords, requireVisible)
		local results = {}
		root = root or GameUI.interface()
		if not root then
			return results
		end
		if type(keywords) == "string" then
			keywords = { keywords }
		end
		local lowered = {}
		for index, keyword in ipairs(keywords) do
			lowered[index] = string.lower(tostring(keyword))
		end
		local candidates = Util.findAllDeep(root, function(node)
			for _, class in ipairs(CLICKABLE) do
				if node:IsA(class) then
					return true
				end
			end
			return false
		end, 12)
		for _, node in ipairs(candidates) do
			local label = labelOf(node)
			for _, keyword in ipairs(lowered) do
				if keyword ~= "" and string.find(label, keyword, 1, true) then
					if not requireVisible or Util.isVisible(node) then
						table.insert(results, node)
					end
					break
				end
			end
		end
		return results
	end

	GameUI.clickFirst = function(root, keywords, requireVisible)
		local matches = GameUI.findClickables(root, keywords, requireVisible)
		if #matches == 0 then
			return false
		end
		return Util.click(matches[1])
	end

	-- Opens a top level menu of the interface by its name.
	GameUI.openMenu = function(name)
		local matches = GameUI.findClickables(GameUI.interface(), { name }, true)
		if #matches == 0 then
			return false
		end
		Util.click(matches[1])
		return true
	end

	------------------------------------------------------------------
	-- HUD readouts
	------------------------------------------------------------------

	-- Reads the number displayed on a HUD gauge. The gauge stores the
	-- value as text on the Gradient label, e.g. "12/60".
	GameUI.readGauge = function(path)
		local node = GameUI.find(path)
		if not node then
			return nil
		end
		local text = ""
		if node:IsA("TextLabel") or node:IsA("TextButton") then
			text = node.Text or ""
		else
			local label = node:FindFirstChildWhichIsA("TextLabel", true)
			text = label and label.Text or ""
		end
		local current, maximum = text:match("(%d+)%s*/%s*(%d+)")
		if current then
			return tonumber(current), tonumber(maximum)
		end
		local single = text:match("(%d+)")
		return tonumber(single), nil
	end

	GameUI.blades = function()
		return GameUI.readGauge('HUD.Main.Top["7"].Blades.Inner.Bar.Gradient')
	end

	GameUI.gas = function()
		return GameUI.readGauge('HUD.Main.Top["7"].Gas.Inner.Bar.Gradient')
	end

	-- Mission timer, the game keeps it somewhere in the HUD as mm:ss.
	GameUI.missionTimer = function()
		local hud = GameUI.hud()
		if not hud then
			return nil
		end
		local label = Util.findDeep(hud, function(node)
			if not (node:IsA("TextLabel") or node:IsA("TextButton")) then
				return false
			end
			local text = node.Text or ""
			return text:match("^%d+:%d+$") ~= nil
		end, 10)
		if not label then
			return nil
		end
		local minutes, seconds = label.Text:match("(%d+):(%d+)")
		if not minutes then
			return nil
		end
		return tonumber(minutes) * 60 + tonumber(seconds)
	end

	------------------------------------------------------------------
	-- Rewards screen
	------------------------------------------------------------------

	GameUI.rewardsVisible = function()
		local rewards = GameUI.rewards()
		if not rewards then
			return false
		end
		return rewards.Visible == true
	end

	GameUI.retryButton = function()
		local button = GameUI.find("Rewards.Main.Info.Main.Buttons.Retry")
		if button and Util.isVisible(button) then
			return button
		end
		local matches = GameUI.findClickables(GameUI.rewards(), { "Retry" }, true)
		return matches[1]
	end

	GameUI.leaveButton = function()
		local button = GameUI.find("Rewards.Main.Info.Main.Buttons.Leave_2")
		if button and Util.isVisible(button) then
			return button
		end
		local matches = GameUI.findClickables(GameUI.rewards(), { "Leave" }, true)
		return matches[1]
	end

	------------------------------------------------------------------
	-- Slot selection (lobby)
	------------------------------------------------------------------

	GameUI.selectSlot = function(slot)
		local screen = GameUI.titleScreen()
		if not screen then
			return false
		end
		local direct = screen:FindFirstChild("Slots")
			and screen.Slots:FindFirstChild(slot)
			and screen.Slots[slot]:FindFirstChild("Select_" .. slot)
		if direct then
			Util.click(direct)
			return true
		end
		return GameUI.clickFirst(screen, { "Select_" .. slot, slot }, true)
	end

	------------------------------------------------------------------
	-- Text scraping (used for drop lists)
	------------------------------------------------------------------

	-- Collects the visible text of a container, one entry per label.
	GameUI.collectText = function(root, filter)
		local output = {}
		root = root or GameUI.interface()
		if not root then
			return output
		end
		local labels = Util.findAllDeep(root, function(node)
			return node:IsA("TextLabel") or node:IsA("TextButton")
		end, 12)
		for _, label in ipairs(labels) do
			if Util.isVisible(label) then
				local text = (label.Text or ""):match("^%s*(.-)%s*$")
				if text and text ~= "" then
					if type(filter) == "function" then
						if filter(text, label) then
							table.insert(output, { text = text, node = label })
						end
					else
						table.insert(output, { text = text, node = label })
					end
				end
			end
		end
		return output
	end

	return GameUI
end
