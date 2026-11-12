--[[
	AOTR Suite :: Features / Reload
	Redesigned auto reload.

	When the blades break the player walks to a refill station and refills
	there instead of refilling on the spot. The station that is selected is
	the safest one, meaning the one that has the most distance to the
	nearest titan, unless the config asks for the nearest station.
]]

return function(Ctx)
	local Util = Ctx.Util
	local Reload = {}

	local Workspace = game:GetService("Workspace")

	local state = {
		lastReload = 0,
		atStation = false,
		station = nil,
		slashCounter = 0,
	}

	local STATION_KEYWORDS = {
		"refill",
		"supply",
		"supplies",
		"station",
		"gastank",
		"gas tank",
		"horse",
		"resupply",
		"depot",
	}

	------------------------------------------------------------------
	-- Blade state
	------------------------------------------------------------------

	-- Detects a broken blade using the character attributes first, then
	-- the HUD gauge and finally the amount of swings that happened.
	Reload.isBroken = function()
		local player = Util.LocalPlayer
		local character = player and player.Character
		if not character then
			return false
		end

		if character:GetAttribute("BladesBroken") == true
			or character:GetAttribute("Broken") == true
			or character:GetAttribute("BladeBroken") == true then
			return true
		end

		local durability = character:GetAttribute("Durability") or character:GetAttribute("BladeDurability")
		if type(durability) == "number" then
			return durability <= 2
		end

		local tool = character:FindFirstChildOfClass("Tool")
		if tool then
			local toolDurability = tool:GetAttribute("Durability") or tool:GetAttribute("Dur")
			if type(toolDurability) == "number" then
				return toolDurability <= 2
			end
		end

		local blades, maximum = Ctx.GameUI.blades()
		if blades and maximum and maximum > 0 then
			return blades <= 1
		end

		return false
	end

	------------------------------------------------------------------
	-- Stations
	------------------------------------------------------------------

	local function promptPosition(prompt)
		local parent = prompt.Parent
		if not parent then
			return nil
		end
		if parent:IsA("BasePart") then
			return parent.Position
		end
		if parent:IsA("Model") then
			return parent:GetPivot().Position
		end
		return nil
	end

	-- Collects every refill station that is currently loaded.
	Reload.stations = function()
		local stations = {}
		local player = Util.LocalPlayer
		local character = player and player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")

		for _, prompt in ipairs(Workspace:GetDescendants()) do
			if prompt:IsA("ProximityPrompt") then
				local haystack = string.lower(prompt.Name .. " " .. prompt.ActionText .. " " .. prompt.ObjectText)
				local matches = false
				for _, keyword in ipairs(STATION_KEYWORDS) do
					if string.find(haystack, keyword, 1, true) then
						matches = true
						break
					end
				end
				if matches then
					local position = promptPosition(prompt)
					if position then
						table.insert(stations, {
							prompt = prompt,
							position = position,
							distance = root and (position - root.Position).Magnitude or 9999,
						})
					end
				end
			end
		end

		-- Some maps use a plain part instead of a prompt.
		for _, part in ipairs(Workspace:GetDescendants()) do
			if part:IsA("BasePart") then
				local haystack = string.lower(part.Name)
				for _, keyword in ipairs({ "refill", "gastank", "supplystation" }) do
					if string.find(haystack, keyword, 1, true) then
						local position = part.Position
						table.insert(stations, {
							prompt = nil,
							position = position,
							distance = root and (position - root.Position).Magnitude or 9999,
						})
						break
					end
				end
			end
		end

		return stations
	end

	-- Scores a station by how safe it is. A station that is far away from
	-- every titan is the safe one.
	local function safetyScore(station)
		local nearestTitan = math.huge
		for _, entry in ipairs(Ctx.Targets.getTitans()) do
			if entry.nape and entry.nape.Parent then
				local distance = (entry.nape.Position - station.position).Magnitude
				if distance < nearestTitan then
					nearestTitan = distance
				end
			end
		end
		if nearestTitan == math.huge then
			nearestTitan = 500
		end
		return nearestTitan
	end

	-- Picks the station that should be used.
	Reload.pickStation = function(settings)
		local stations = Reload.stations()
		if #stations == 0 then
			return nil
		end
		local mode = settings.ReloadStation or "Safest"
		local best = stations[1]
		local bestScore
		if mode == "Nearest" then
			bestScore = best.distance
			for _, station in ipairs(stations) do
				if station.distance < bestScore then
					best = station
					bestScore = station.distance
				end
			end
		else
			bestScore = safetyScore(best)
			for _, station in ipairs(stations) do
				local score = safetyScore(station)
				if score > bestScore then
					best = station
					bestScore = score
				end
			end
		end
		return best
	end

	------------------------------------------------------------------
	-- Refill
	------------------------------------------------------------------

	local function triggerPrompt(prompt)
		if not prompt then
			return false
		end
		if type(fireproximityprompt) == "function" then
			local ok = pcall(fireproximityprompt, prompt)
			if ok then
				return true
			end
		end
		return false
	end

	local function moveTo(station)
		local player = Util.LocalPlayer
		local character = player and player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or not station then
			return false
		end
		local destination = station.position + Vector3.new(0, 3, 0)
		root.CFrame = CFrame.new(destination)
		return true
	end

	-- Performs the reload: walk to the station, trigger it, refill.
	Reload.perform = function(force)
		local settings = Ctx.Config.Get()
		local now = Util.now()
		if now - state.lastReload < 1 then
			return false
		end
		state.lastReload = now

		local station = Reload.pickStation(settings)
		if station then
			state.station = station
			moveTo(station)
			task.wait(0.15)
			triggerPrompt(station.prompt)
		end

		-- The server side refill works from anywhere and is the reliable
		-- part of the reload.
		Ctx.Remotes.refill()
		state.slashCounter = 0
		Ctx.Stats.session.bladesReloaded = Ctx.Stats.session.bladesReloaded + 1
		return true
	end

	------------------------------------------------------------------
	-- Auto refill of the supplies
	------------------------------------------------------------------

	-- Tops the gas and the blades up without leaving the fight.
	Reload.refillSupplies = function()
		local settings = Ctx.Config.Get()
		if settings.AutoRefill ~= true then
			return false
		end
		local now = Util.now()
		if now - (state.lastRefill or 0) < 2 then
			return false
		end
		state.lastRefill = now
		Ctx.Remotes.refill()
		return true
	end

	------------------------------------------------------------------
	-- Main update
	------------------------------------------------------------------

	Reload.update = function()
		local settings = Ctx.Config.Get()

		if settings.AutoRefill == true then
			Reload.refillSupplies()
		end

		if settings.AutoReload ~= true then
			return
		end

		-- Count the swings so the reload also triggers when the game does
		-- not report the durability.
		state.slashCounter = state.slashCounter + 1
		if not Reload.isBroken() and state.slashCounter < 40 then
			return
		end

		Reload.perform()
	end

	Reload.state = state

	return Reload
end
