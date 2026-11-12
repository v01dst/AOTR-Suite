--[[
	AOTR Suite :: Features / Waves
	Wave mode helpers.

	Supports
		TargetBoss             - prioritise the boss titan of the wave
		WavesUpgrades          - upgrade the gear every wave
		AutoBuyUpgradesWaves   - buy the upgrades from the wave shop
		AutoWaveDie / WaveToDieAt - end the run on a given wave
		WavesAutoSkip          - vote to skip the wave
		WavesRollBlessing      - reroll the blessing
		WavesGetCrates         - open the wave crates

	All of it is written so it keeps working during a kaitun, where the
	mission restarts constantly: the wave state is rebuilt every frame from
	the interface instead of being cached across sessions.
]]

return function(Ctx)
	local Util = Ctx.Util
	local Waves = {}

	local state = {
		currentWave = 0,
		lastWave = 0,
		died = false,
		lastAction = 0,
	}

	------------------------------------------------------------------
	-- Wave detection
	------------------------------------------------------------------

	-- Reads the wave counter from the interface.
	Waves.currentWave = function()
		local hud = Ctx.GameUI.hud()
		if not hud then
			return state.currentWave
		end
		local label = Util.findDeep(hud, function(node)
			if not (node:IsA("TextLabel") or node:IsA("TextButton")) then
				return false
			end
			return string.find(string.lower(node.Text or ""), "wave", 1, true) ~= nil
		end, 10)
		if not label then
			return state.currentWave
		end
		local wave = label.Text:match("(%d+)")
		if wave then
			state.currentWave = tonumber(wave) or state.currentWave
		end
		return state.currentWave
	end

	------------------------------------------------------------------
	-- Buttons
	------------------------------------------------------------------

	local function clickAny(keywords)
		local root = Ctx.GameUI.interface()
		local matches = Ctx.GameUI.findClickables(root, keywords, true)
		for _, button in ipairs(matches) do
			if button.Active then
				Util.click(button)
				return true
			end
		end
		return false
	end

	------------------------------------------------------------------
	-- Actions
	------------------------------------------------------------------

	-- Votes to skip the current wave.
	Waves.skip = function()
		return clickAny({ "Skip", "Vote Skip", "Proceed" })
	end

	-- Rerolls the current blessing.
	Waves.rollBlessing = function()
		return clickAny({ "Reroll", "Roll", "Blessing" })
	end

	-- Upgrades the gear between waves.
	Waves.upgrade = function()
		return clickAny({ "Upgrade", "Upgrade Gear", "Improve" })
	end

	-- Opens the wave crates.
	Waves.getCrates = function()
		return clickAny({ "Crate", "Open Chest", "Open Crate" })
	end

	-- Buys the upgrades that are listed in the config.
	Waves.buyUpgrades = function()
		local settings = Ctx.Config.Get()
		local list = settings.WavesUpgradesToBuy
		if type(list) == "string" then
			list = { list }
		end
		if type(list) ~= "table" or #list == 0 then
			return false
		end
		local bought = false
		for _, upgrade in ipairs(list) do
			if type(upgrade) == "string" and upgrade ~= "" then
				if clickAny({ upgrade }) then
					bought = true
					task.wait(0.15)
				end
			end
		end
		return bought
	end

	------------------------------------------------------------------
	-- Dying on a wave
	------------------------------------------------------------------

	-- Ends the run on the configured wave. The character walks into a
	-- titan so the server applies the death.
	Waves.die = function()
		local player = Util.LocalPlayer
		local character = player and player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then
			return false
		end
		if clickAny({ "Die", "Give Up", "Surrender" }) then
			state.died = true
			return true
		end
		local titans = Ctx.Targets.getTitans()
		if #titans > 0 and titans[1].nape then
			root.CFrame = CFrame.new(titans[1].nape.Position)
			state.died = true
			return true
		end
		return false
	end

	------------------------------------------------------------------
	-- Boss targeting
	------------------------------------------------------------------

	-- When TargetBoss is on, the farm prefers the boss of the wave.
	Waves.applyTargetBoss = function()
		local settings = Ctx.Config.Get()
		if settings.TargetBoss ~= true then
			return false
		end
		if settings.TargetPriority ~= "Bosses First" then
			settings.TargetPriority = "Bosses First"
		end
		return true
	end

	------------------------------------------------------------------
	-- Main update
	------------------------------------------------------------------

	Waves.update = function()
		local settings = Ctx.Config.Get()

		if not Ctx.Safety.inMission() then
			-- A new session starts, the wave counter restarts as well.
			if state.currentWave ~= 0 then
				state.currentWave = 0
				state.lastWave = 0
				state.died = false
			end
			return
		end

		Waves.currentWave()
		Waves.applyTargetBoss()

		local now = Util.now()
		if now - state.lastAction < 0.6 then
			return
		end
		state.lastAction = now

		if settings.WavesAutoSkip == true then
			Waves.skip()
		end
		if settings.WavesRollBlessing == true then
			Waves.rollBlessing()
		end
		if settings.WavesAutoUpgrade == true then
			Waves.upgrade()
		end
		if settings.WavesBuyUpgrades == true then
			Waves.buyUpgrades()
		end
		if settings.WavesGetCrates == true then
			Waves.getCrates()
		end

		-- Auto die at a given wave.
		local dieAt = settings.WaveToDieAt or 0
		if settings.AutoWaveDie == true and dieAt > 0 and state.currentWave >= dieAt and not state.died then
			Waves.die()
		end
	end

	Waves.state = state

	return Waves
end
