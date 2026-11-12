--[[
	AOTR Suite :: Hub
	The user interface.

	The UI is built on Rayfield, which is vendored in vendor/source.lua.
	Every control writes straight into the shared config table, and the
	config tab persists the changes to disk.

	When another profile is selected the controls are refreshed in place
	through the Rayfield Set methods, so the window never has to be closed
	and opened again.
]]

return function(Ctx)
	local Util = Ctx.Util
	local Hub = {}

	local Rayfield = Ctx.Rayfield
	local Config = Ctx.Config

	local window = nil
	local profileDropdown = nil
	local statsParagraph = nil
	local saveTimer = 0
	local loopsStarted = false
	local newProfileName = ""
	local uiProvider = nil

	-- Every control that mirrors a config value, so it can be refreshed.
	local bindings = {}

	------------------------------------------------------------------
	-- Helpers
	------------------------------------------------------------------

	local function settings()
		return Config.Get()
	end

	local function notify(title, content, duration)
		local provider = uiProvider or Rayfield
		if not provider then
			return
		end
		provider:Notify({
			Title = title,
			Content = content,
			Duration = duration or 4,
		})
	end

	-- Schedules a save a moment after the last change, so dragging a
	-- slider does not write a hundred files.
	local function scheduleSave()
		saveTimer = Util.now()
	end

	local function register(element, name, kind, extra)
		table.insert(bindings, {
			element = element,
			name = name,
			kind = kind,
			extra = extra,
		})
		return element
	end

	local function createToggle(tab, name, default)
		local current = settings()[name]
		if current == nil then
			current = default or false
		end
		local element = tab:CreateToggle({
			Name = name,
			CurrentValue = current == true,
			Flag = "AOTR_" .. name,
			Callback = function(value)
				Config.Set(name, value == true)
				scheduleSave()
			end,
		})
		return register(element, name, "toggle")
	end

	local function createDropdown(tab, name, options, default)
		local current = settings()[name]
		if current == nil then
			current = default or options[1]
		end
		local element = tab:CreateDropdown({
			Name = name,
			Options = options,
			CurrentOption = { current },
			MultipleOptions = false,
			Flag = "AOTR_" .. name,
			Callback = function(option)
				local value = type(option) == "table" and option[1] or option
				Config.Set(name, value)
				scheduleSave()
			end,
		})
		return register(element, name, "dropdown")
	end

	local function createSlider(tab, name, range, increment, suffix, default)
		local current = settings()[name]
		if type(current) ~= "number" then
			current = default or range[1]
		end
		local element = tab:CreateSlider({
			Name = name,
			Range = range,
			Increment = increment,
			Suffix = suffix,
			CurrentValue = current,
			Flag = "AOTR_" .. name,
			Callback = function(value)
				Config.Set(name, value)
				scheduleSave()
			end,
		})
		return register(element, name, "slider", { min = range[1], max = range[2] })
	end

	local function createInput(tab, name, placeholder, default)
		local current = settings()[name]
		if type(current) ~= "string" then
			current = default or ""
		end
		local element = tab:CreateInput({
			Name = name,
			CurrentValue = current,
			PlaceholderText = placeholder,
			RemoveTextAfterFocusLost = false,
			Flag = "AOTR_" .. name,
			Callback = function(text)
				Config.Set(name, tostring(text or ""))
				scheduleSave()
			end,
		})
		return register(element, name, "input")
	end

	-- A list of strings that is edited as one comma separated line.
	local function createListInput(tab, name, placeholder)
		local current = settings()[name]
		if type(current) ~= "table" then
			current = {}
		end
		local element = tab:CreateInput({
			Name = name,
			CurrentValue = table.concat(current, ", "),
			PlaceholderText = placeholder,
			RemoveTextAfterFocusLost = false,
			Flag = "AOTR_" .. name,
			Callback = function(text)
				local list = {}
				for piece in string.gmatch(tostring(text or ""), "([^,]+)") do
					local trimmed = piece:match("^%s*(.-)%s*$")
					if trimmed ~= "" then
						table.insert(list, trimmed)
					end
				end
				Config.Set(name, list)
				scheduleSave()
			end,
		})
		return register(element, name, "list")
	end

	------------------------------------------------------------------
	-- Refresh
	------------------------------------------------------------------

	-- Pushes the values of the active profile back into the controls.
	Hub.refresh = function()
		local current = settings()
		for _, binding in ipairs(bindings) do
			local value = current[binding.name]
			pcall(function()
				if binding.kind == "toggle" then
					binding.element:Set(value == true)
				elseif binding.kind == "slider" then
					if type(value) == "number" then
						local minimum = binding.extra and binding.extra.min or value
						local maximum = binding.extra and binding.extra.max or value
						binding.element:Set(Util.clamp(value, minimum, maximum))
					end
				elseif binding.kind == "input" then
					binding.element:Set(tostring(value or ""))
				elseif binding.kind == "list" then
					if type(value) == "table" then
						binding.element:Set(table.concat(value, ", "))
					end
				elseif binding.kind == "dropdown" then
					if type(value) == "string" then
						binding.element:Set({ value })
					end
				end
			end)
		end
	end

	------------------------------------------------------------------
	-- Build
	------------------------------------------------------------------

	Hub.build = function()
		local windowSettings = {
			Name = "AOTR Suite | Attack on Titan: Revolution",
			LoadingTitle = "AOTR Suite",
			LoadingSubtitle = "Attack on Titan: Revolution",
			ConfigurationSaving = {
				Enabled = false,
			},
			KeySystem = false,
		}

		-- Rayfield loads its window from a Roblox asset, and a lot of
		-- executors block that call. When it fails the built in interface
		-- takes over so the suite is always visible.
		local created = nil
		if Rayfield then
			local ok, result = pcall(function()
				return Rayfield:CreateWindow(windowSettings)
			end)
			if ok and result then
				created = result
				uiProvider = Rayfield
			else
				Util.warn("Rayfield could not open a window:", tostring(result))
			end
		end

		if not created then
			Util.warn("using the built in interface")
			local Fallback = Ctx.FallbackUI
			created = Fallback:CreateWindow(windowSettings)
			uiProvider = Fallback
		end

		window = created

		--------------------------------------------------------------
		-- Tab: Auto Farm
		--------------------------------------------------------------
		local farm = window:CreateTab("Auto Farm", 0)
		farm:CreateSection("Farming")

		createToggle(farm, "AutoFarm", false)
		createDropdown(farm, "FarmMethod", { "Blade", "Hover", "Teleport" }, "Blade")
		createDropdown(farm, "TargetPriority", { "Closest", "Bosses First", "Crawlers & Abnormals", "Lowest HP" }, "Closest")
		createToggle(farm, "DisableHovering", false)
		createToggle(farm, "TeleportTitans", false)
		createSlider(farm, "HoverHeight", { 0, 600 }, 5, " studs", 265)
		createSlider(farm, "HoverSpeed", { 500, 8000 }, 100, "", 3000)
		createSlider(farm, "BehindNapeDistance", { 0, 20 }, 0.5, " studs", 2)
		createSlider(farm, "HitDistance", { 50, 2000 }, 50, " studs", 1000)

		farm:CreateSection("Combat")
		createSlider(farm, "MultiHit", { 1, 10 }, 1, " targets", 9)
		createSlider(farm, "BossDamage", { 0, 20 }, 1, " hits", 9)
		createToggle(farm, "DamageExtender", false)
		createSlider(farm, "DamageMultiplier", { 1, 50 }, 1, "x", 3)
		createToggle(farm, "InfiniteSpears", false)
		createToggle(farm, "AutoUseSkills", false)

		farm:CreateSection("Visuals")
		createToggle(farm, "TitanEsp", false)
		createToggle(farm, "NapeExtend", false)
		createToggle(farm, "NoTitanLag", true)
		createToggle(farm, "DisableRendering", true)

		--------------------------------------------------------------
		-- Tab: Reload & Refill
		--------------------------------------------------------------
		local reload = window:CreateTab("Reload & Refill", 0)
		reload:CreateSection("Reload")
		createToggle(reload, "AutoReload", false)
		createDropdown(reload, "ReloadStation", { "Safest", "Nearest" }, "Safest")
		createToggle(reload, "AutoRefill", false)

		reload:CreateSection("Safety")
		local safetyValue = settings().SafetyTime
		if type(safetyValue) ~= "number" then
			safetyValue = 30
		end
		local safetySlider = reload:CreateSlider({
			Name = "Safety Time",
			Range = { 30, 600 },
			Increment = 5,
			Suffix = " s",
			CurrentValue = math.max(30, safetyValue),
			Flag = "AOTR_SafetyTime",
			Callback = function(value)
				-- The mission timer never goes below 30 seconds.
				Config.Set("SafetyTime", math.max(30, value))
				scheduleSave()
			end,
		})
		register(safetySlider, "SafetyTime", "slider", { min = 30, max = 600 })

		reload:CreateParagraph({
			Name = "Minimum mission timer is 30 seconds.",
			Content = "The suite leaves a mission only after the real mission timer passed the value above.",
		})

		--------------------------------------------------------------
		-- Tab: Rewards
		--------------------------------------------------------------
		local rewards = window:CreateTab("Rewards", 0)
		rewards:CreateSection("Auto claim")
		createToggle(rewards, "ClaimAchievements", false)
		createToggle(rewards, "ClaimQuests", false)
		createToggle(rewards, "ClaimBattlePass", true)
		rewards:CreateParagraph({
			Name = "Auto Claim Daily Reward",
			Content = "Always active. There is no toggle for it.",
		})

		rewards:CreateSection("Boosts")
		createToggle(rewards, "BuyBoosts", false)
		createDropdown(rewards, "ItemtoBuyWith", Config.CURRENCIES, "Canes")
		createListInput(rewards, "Boosts", "2x Gold Boost [2h], 2x XP Boost [1h]")

		--------------------------------------------------------------
		-- Tab: Auto Start
		--------------------------------------------------------------
		local autoStart = window:CreateTab("Auto Start", 0)
		autoStart:CreateSection("Session")
		createToggle(autoStart, "AutoStart", false)
		createDropdown(autoStart, "AutoStartType", { "Missions", "Raids" }, "Missions")
		createDropdown(autoStart, "AutoStartMap", {
			"Shiganshina",
			"Trost",
			"Outskirts",
			"Giant Forest",
			"Utgard",
			"Docks",
			"Stohess",
			"Chapel",
		}, "Shiganshina")
		createDropdown(autoStart, "AutoStartObjective", { "Breach", "Skirmish", "Protect", "Clear" }, "Breach")

		local difficultyNames = {}
		for _, entry in ipairs(Config.DIFFICULTIES) do
			table.insert(difficultyNames, entry.name)
		end
		createDropdown(autoStart, "AutoStartDifficulty", difficultyNames, "Hardest (w/ Freedom)")

		autoStart:CreateSection("Modifiers")
		createListInput(autoStart, "AutoStartModifiers", "Nightmare, Oddball, Fog")
		createToggle(autoStart, "PlayBoostedMap", false)

		autoStart:CreateSection("Loop")
		createToggle(autoStart, "Kaitun", false)
		createToggle(autoStart, "AutoReturn", false)
		createSlider(autoStart, "ReturnAmount", { 1, 100 }, 1, " missions", 15)
		autoStart:CreateParagraph({
			Name = "Kaitun",
			Content = "Restarts a session right after the previous one ended. Wave features and the boost currency keep working inside a kaitun.",
		})

		--------------------------------------------------------------
		-- Tab: Waves
		--------------------------------------------------------------
		local waves = window:CreateTab("Waves", 0)
		waves:CreateSection("Wave mode")
		createToggle(waves, "TargetBoss", false)
		createToggle(waves, "WavesAutoSkip", false)
		createToggle(waves, "WavesRollBlessing", false)
		createToggle(waves, "WavesAutoUpgrade", false)
		createToggle(waves, "WavesBuyUpgrades", false)
		createToggle(waves, "WavesGetCrates", false)

		waves:CreateSection("End the run")
		createToggle(waves, "AutoWaveDie", false)
		createSlider(waves, "WaveToDieAt", { 0, 100 }, 1, "", 0)
		createListInput(waves, "WavesUpgradesToBuy", "Damage, Speed")

		--------------------------------------------------------------
		-- Tab: Progression
		--------------------------------------------------------------
		local progression = window:CreateTab("Progression", 0)
		progression:CreateSection("Prestige")
		createToggle(progression, "AutoPrestige", false)
		createSlider(progression, "PrestigeToStopAt", { 1, 50 }, 1, "", 5)

		progression:CreateSection("Skill tree")
		createToggle(progression, "AutoSkillTree", false)
		createDropdown(progression, "LeftPath", { "Skill Cooldown", "Damage", "Damage Reduction", "Health" }, "Skill Cooldown")
		createDropdown(progression, "MiddlePath", { "Skill Cooldown", "Damage", "Damage Reduction", "Health" }, "Damage")
		createDropdown(progression, "RightPath", { "Skill Cooldown", "Damage", "Damage Reduction", "Health" }, "Damage Reduction")
		createDropdown(progression, "PathPriority", { "Left", "Middle", "Right" }, "Middle")

		--------------------------------------------------------------
		-- Tab: Webhook
		--------------------------------------------------------------
		local webhook = window:CreateTab("Webhook & Stats", 0)
		webhook:CreateSection("Discord webhook")
		createToggle(webhook, "Webhook", false)
		createInput(webhook, "WebhookLink", "https://discord.com/api/webhooks/...", "")
		createToggle(webhook, "ShowUsername", true)
		createToggle(webhook, "SendSafetyUpdate", false)
		webhook:CreateButton({
			Name = "Send test webhook",
			Callback = function()
				if Ctx.Webhook.test() then
					notify("Webhook", "The test message was sent.")
				else
					notify("Webhook", "The message could not be sent, check the URL.", 5)
				end
			end,
		})

		webhook:CreateSection("Live stats")
		statsParagraph = webhook:CreateParagraph({
			Name = "Player Stats",
			Content = "waiting for data",
		})
		local function refreshStats()
			local snapshot = Ctx.Stats.snapshot()
			local lines = {}
			for _, entry in ipairs(Ctx.Stats.CURRENCIES) do
				local value = snapshot[entry.key]
				if type(value) == "number" then
					table.insert(lines, string.format("%s: %s", entry.label, Util.formatNumber(value)))
				end
			end
			table.insert(lines, "")
			table.insert(lines, string.format("Missions: %d", snapshot.session.missions))
			table.insert(lines, string.format("Raids: %d", snapshot.session.raids))
			table.insert(lines, string.format("Waves: %d", snapshot.session.waves))
			table.insert(lines, string.format("Titans killed: %d", snapshot.session.titansKilled))
			table.insert(lines, string.format("Reloads: %d", snapshot.session.bladesReloaded))
			table.insert(lines, string.format("Session: %s", Util.formatDuration(snapshot.sessionSeconds)))
			pcall(function()
				statsParagraph:Set({
					Title = "Player Stats",
					Content = table.concat(lines, "\n"),
				})
			end)
		end

		--------------------------------------------------------------
		-- Tab: Config
		--------------------------------------------------------------
		local configTab = window:CreateTab("Config", 0)
		configTab:CreateSection("Profile")

		local function profileNames()
			local names = {}
			for _, profile in ipairs(Config.listProfiles()) do
				table.insert(names, profile.name)
			end
			if #names == 0 then
				table.insert(names, Config.DEFAULT_PROFILE)
			end
			return names
		end

		profileDropdown = configTab:CreateDropdown({
			Name = "Config Profile",
			Options = profileNames(),
			CurrentOption = { Config.ActiveProfile },
			MultipleOptions = false,
			Flag = "AOTR_ConfigProfile",
			Callback = function(option)
				local name = type(option) == "table" and option[1] or option
				if name and name ~= Config.ActiveProfile then
					Config.Select(name)
					notify("Config", "Loaded profile: " .. name)
					-- The controls read from the config table, so they are
					-- refreshed to show the values of the new profile.
					Hub.refresh()
				end
			end,
		})

		configTab:CreateInput({
			Name = "New profile name",
			CurrentValue = "",
			PlaceholderText = "my farm config",
			RemoveTextAfterFocusLost = false,
			Flag = "AOTR_NewProfileName",
			Callback = function(text)
				newProfileName = tostring(text or "")
			end,
		})

		configTab:CreateButton({
			Name = "Create profile",
			Callback = function()
				local name = Util.sanitizeName(newProfileName)
				if name == "" or name == "default" then
					notify("Config", "Enter a name for the new profile.")
					return
				end
				Config.New(name)
				newProfileName = ""
				notify("Config", "Created profile: " .. name)
				profileDropdown:Refresh(profileNames())
			end,
		})

		configTab:CreateButton({
			Name = "Save config now",
			Callback = function()
				if Config.Save() then
					notify("Config", "Saved to " .. Config.profilePath(Config.ActiveProfile))
				else
					notify("Config", "The config could not be saved.", 5)
				end
			end,
		})

		configTab:CreateButton({
			Name = "Reload config from disk",
			Callback = function()
				if Config.loadProfile(Config.ActiveProfile) then
					notify("Config", "Reloaded profile: " .. Config.ActiveProfile)
					Hub.refresh()
				else
					notify("Config", "No file found for this profile.", 4)
				end
			end,
		})

		configTab:CreateButton({
			Name = "Delete profile",
			Callback = function()
				local name = Config.ActiveProfile
				Config.Delete(name)
				notify("Config", "Deleted profile: " .. name)
				profileDropdown:Refresh(profileNames())
				Hub.refresh()
			end,
		})

		configTab:CreateParagraph({
			Name = "Config folder",
			Content = Config.CONFIG_FOLDER,
		})

		--------------------------------------------------------------
		-- Tab: Misc
		--------------------------------------------------------------
		local misc = window:CreateTab("Misc", 0)
		misc:CreateSection("General")
		createToggle(misc, "AntiAFK", true)
		createToggle(misc, "ShadowBanCheck", false)
		misc:CreateButton({
			Name = "Check shadow ban now",
			Callback = function()
				local clean, flags = Ctx.ShadowBan.check()
				if clean then
					notify("Shadow ban", "No restriction flags were found.")
				else
					notify("Shadow ban", "Flags found: " .. table.concat(flags, ", "), 7)
				end
			end,
		})

		misc:CreateSection("Server")
		createInput(misc, "PrivateServerCode", "-", "-")
		createToggle(misc, "LeaveIfMorePlayers", false)
		createToggle(misc, "AutoSelectSlot", true)
		createDropdown(misc, "Slot", { "A", "B", "C", "D" }, "B")

		misc:CreateSection("Streak")
		createSlider(misc, "StreakAmount", { 0, 1000000 }, 1000, "", 0)
		createToggle(misc, "StreakDie", false)

		------------------------------------------------------------------
		-- Auto save and live stats
		------------------------------------------------------------------
		Config.onChanged(function()
			scheduleSave()
		end)

		if not loopsStarted then
			loopsStarted = true

			-- The config is written a moment after the last change, so
			-- dragging a slider does not write a hundred files.
			task.spawn(function()
				while true do
					task.wait(1)
					if saveTimer > 0 and Util.now() - saveTimer > 1.5 then
						saveTimer = 0
						Config.Save()
					end
				end
			end)

			task.spawn(function()
				while true do
					task.wait(2)
					pcall(refreshStats)
				end
			end)
		end

		return window
	end

	Hub.window = function()
		return window
	end

	-- Which interface library ended up being used, shown in the console.
	Hub.providerName = function()
		if uiProvider == Rayfield then
			return "Rayfield"
		end
		if uiProvider then
			return "built in"
		end
		return "none"
	end

	Hub.notify = notify

	return Hub
end
