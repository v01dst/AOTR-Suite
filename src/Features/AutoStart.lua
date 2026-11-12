--[[
	AOTR Suite :: Features / AutoStart
	Creates missions and raids on its own.

	Difficulties supported (from the in game ladder):
		Easy, Normal, Hard, Severe, Aberrant, Freedom
	plus the top tier "Hardest (w/ Freedom)" which needs Freedom unlocked.
]]

return function(Ctx)
	local Util = Ctx.Util
	local AutoStart = {}

	local state = {
		lastRun = 0,
		running = false,
		started = 0,
	}

	local MAP_SUFFIX = "_Missions"

	local function config()
		return Ctx.Config.Get()
	end

	------------------------------------------------------------------
	-- Difficulty
	------------------------------------------------------------------

	-- Returns the difficulty entry of the config.
	AutoStart.difficulty = function()
		local settings = config()
		local wanted = settings.AutoStartDifficulty or "Hardest (w/ Freedom)"
		for _, entry in ipairs(Ctx.Config.DIFFICULTIES) do
			if entry.name == wanted then
				return entry
			end
		end
		return Ctx.Config.DIFFICULTIES[#Ctx.Config.DIFFICULTIES]
	end

	-- Clicks the difficulty button inside the mission panel.
	local function selectDifficulty(root, name)
		local matches = Ctx.GameUI.findClickables(root, { name }, true)
		if #matches == 0 then
			return false
		end
		Util.click(matches[1])
		task.wait(0.2)
		return true
	end

	------------------------------------------------------------------
	-- Missions
	------------------------------------------------------------------

	local function openMissionMap()
		-- Interface.Missions.Prompt.Selection.Missions
		local prompt = Ctx.GameUI.find("Missions.Prompt.Selection.Missions")
		if prompt and Util.isVisible(prompt) then
			Util.click(prompt)
			task.wait(0.3)
			return true
		end
		return Ctx.GameUI.openMenu("Missions")
	end

	local function selectMap(mapName)
		-- Interface.Missions.Missions.Main.Maps.Maps.<Map>_Missions
		local maps = Ctx.GameUI.find("Missions.Missions.Main.Maps.Maps")
		if maps then
			local entry = maps:FindFirstChild(mapName .. MAP_SUFFIX) or maps:FindFirstChild(mapName)
			if entry then
				Util.click(entry)
				task.wait(0.25)
				return true
			end
		end
		return Ctx.GameUI.clickFirst(Ctx.GameUI.missions(), { mapName }, true)
	end

	local function createMission()
		-- Interface.Missions.Missions.Main.Info.Main.Buttons.Creation_Missions
		local button = Ctx.GameUI.find("Missions.Missions.Main.Info.Main.Buttons.Creation_Missions")
		if button and Util.isVisible(button) then
			Util.click(button)
			task.wait(0.3)
			return true
		end
		return Ctx.GameUI.clickFirst(Ctx.GameUI.missions(), { "Creation", "Create" }, true)
	end

	local function applyModifiers(modifiers)
		if type(modifiers) ~= "table" or #modifiers == 0 then
			return
		end
		-- Interface.Missions.Info.Main.Info.Modifiers.Modifiers_Buttons
		local opener = Ctx.GameUI.find("Missions.Info.Main.Info.Modifiers.Modifiers_Buttons")
		if opener and Util.isVisible(opener) then
			Util.click(opener)
			task.wait(0.3)
		else
			Ctx.GameUI.clickFirst(Ctx.GameUI.missions(), { "Modifiers" }, true)
			task.wait(0.3)
		end

		local options = Ctx.GameUI.find("Missions.Info.Main.Info.Modifiers.Options")
		if options then
			for _, modifier in ipairs(modifiers) do
				local option = options:FindFirstChild(modifier)
				if option and option:IsA("GuiObject") then
					Util.click(option)
					task.wait(0.12)
				end
			end
		end

		-- Interface.Missions.Info.Main.Info.Modifiers.Modifiers_Buttons.Modifiers_Return
		local closer = Ctx.GameUI.find("Missions.Info.Main.Info.Modifiers.Modifiers_Buttons.Modifiers_Return")
		if closer and Util.isVisible(closer) then
			Util.click(closer)
			task.wait(0.25)
		else
			Ctx.GameUI.clickFirst(Ctx.GameUI.missions(), { "Return", "Close" }, true)
		end
	end

	local function beginMission()
		-- Interface.Missions.Info.Main.Info.Main.Info_Buttons.Begin
		local begin = Ctx.GameUI.find("Missions.Info.Main.Info.Main.Info_Buttons.Begin")
		if begin and Util.isVisible(begin) then
			Util.click(begin)
			return true
		end
		return Ctx.GameUI.clickFirst(Ctx.GameUI.missions(), { "Begin", "Start" }, true)
	end

	AutoStart.startMission = function()
		local settings = config()
		if not openMissionMap() then
			return false
		end
		if settings.PlayBoostedMap == true then
			-- Prefer a map that carries a boost.
			local maps = Ctx.GameUI.find("Missions.Missions.Main.Maps.Maps")
			if maps then
				for _, child in ipairs(maps:GetChildren()) do
					if child:FindFirstChild("Boost") then
						Util.click(child)
						task.wait(0.25)
						break
					end
				end
			end
		else
			selectMap(settings.AutoStartMap or "Shiganshina")
		end

		if not createMission() then
			return false
		end

		local panel = Ctx.GameUI.missions() or Ctx.GameUI.interface()
		local difficulty = AutoStart.difficulty()
		selectDifficulty(panel, difficulty.name)
		applyModifiers(settings.AutoStartModifiers)

		if not beginMission() then
			return false
		end
		state.started = Util.now()
		return true
	end

	------------------------------------------------------------------
	-- Raids
	------------------------------------------------------------------

	AutoStart.startRaid = function()
		local settings = config()
		if not Ctx.GameUI.openMenu("Raids") then
			if not Ctx.GameUI.openMenu("Raid") then
				return false
			end
		end
		task.wait(0.3)
		local panel = Ctx.GameUI.interface()
		local difficulty = AutoStart.difficulty()
		selectDifficulty(panel, difficulty.name)
		if not Ctx.GameUI.clickFirst(panel, { "Begin", "Start", "Launch" }, true) then
			return false
		end
		state.started = Util.now()
		return true
	end

	------------------------------------------------------------------
	-- Main update
	------------------------------------------------------------------

	AutoStart.update = function()
		local settings = config()
		if settings.AutoStart ~= true then
			state.running = false
			return
		end

		-- Never start a new mission while one is running.
		if Ctx.Safety.inMission() then
			return
		end

		local now = Util.now()
		if now - state.lastRun < 4 then
			return
		end
		state.lastRun = now

		-- The lobby has the slot screen, that is the place to start from.
		if Ctx.GameUI.titleScreen() then
			if settings.AutoSelectSlot ~= false then
				Ctx.GameUI.selectSlot(settings.Slot or "B")
				task.wait(0.4)
			end
		end

		local ok
		if settings.AutoStartType == "Raids" then
			ok = AutoStart.startRaid()
		else
			ok = AutoStart.startMission()
		end

		if ok then
			state.running = true
			Ctx.Stats.session.missions = Ctx.Stats.session.missions + 1
			Util.log("auto started a", settings.AutoStartType or "Missions", "session")
		end
	end

	AutoStart.state = state

	return AutoStart
end
