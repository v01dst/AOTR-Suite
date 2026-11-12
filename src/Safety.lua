--[[
	AOTR Suite :: Safety
	Mission safety timer.

	Rules implemented:
		* The minimum mission timer is 30 seconds, it can never go below.
		* The timer follows the real in game mission timer when the HUD
		  exposes it, and falls back to a wall clock measurement otherwise.
		* The value reported as "Time Taken" is the real mission duration,
		  not the time the script happened to be running.
]]

return function(Ctx)
	local Util = Ctx.Util
	local Safety = {}

	local MINIMUM_TIMER = 30

	local state = {
		inMission = false,
		startedAt = 0,
		lastDuration = 0,
		lastHudValue = nil,
		rewardsSeen = false,
	}

	------------------------------------------------------------------
	-- Timer amount
	------------------------------------------------------------------

	-- The configured timer, clamped to the hard minimum of 30 seconds.
	Safety.timerAmount = function()
		local configured = 30
		local ok, value = pcall(function()
			return Ctx.Config.Get().SafetyTime
		end)
		if ok and type(value) == "number" then
			configured = value
		end
		return math.max(MINIMUM_TIMER, configured)
	end

	Safety.MINIMUM = MINIMUM_TIMER

	------------------------------------------------------------------
	-- Mission lifecycle
	------------------------------------------------------------------

	local function hudTimer()
		local ok, value = pcall(function()
			return Ctx.GameUI.missionTimer()
		end)
		if ok then
			return value
		end
		return nil
	end

	-- Updates the internal state. Call this every frame.
	Safety.update = function()
		local rewardsVisible = false
		local ok, visible = pcall(function()
			return Ctx.GameUI.rewardsVisible()
		end)
		if ok then
			rewardsVisible = visible == true
		end

		local timer = hudTimer()

		if rewardsVisible then
			if state.inMission then
				state.lastDuration = Safety.elapsed()
				state.inMission = false
				state.startedAt = 0
			end
			state.rewardsSeen = true
			return
		end

		state.rewardsSeen = false

		-- A mission is running when the HUD shows a timer or the player
		-- is inside a map with titans around.
		local running = timer ~= nil
		if not running then
			local okT, titans = pcall(function()
				return Ctx.Targets.getTitans()
			end)
			if okT and titans and #titans > 0 then
				running = true
			end
		end

		if running and not state.inMission then
			state.inMission = true
			state.startedAt = Util.now()
		elseif not running and state.inMission and timer == nil then
			-- The HUD timer vanished without a rewards screen, the player
			-- probably left the map.
			state.inMission = false
			state.startedAt = 0
		end

		state.lastHudValue = timer
	end

	-- Real elapsed mission time in seconds.
	Safety.elapsed = function()
		if state.lastHudValue ~= nil then
			-- The HUD countdown counts down, so the elapsed time is the
			-- mission length minus the remaining time. When the HUD shows
			-- an elapsed counter we detect that by comparing two samples.
			local remaining = state.lastHudValue
			local elapsed = state.trackedElapsed or 0
			if state.lastSampleRemaining ~= nil then
				local delta = state.lastSampleRemaining - remaining
				if delta > 0 and delta < 10 then
					elapsed = (state.trackedElapsed or 0) + delta
					state.trackedElapsed = elapsed
				end
			end
			state.lastSampleRemaining = remaining
			if elapsed > 0 then
				return elapsed
			end
		end
		if state.inMission and state.startedAt > 0 then
			return Util.now() - state.startedAt
		end
		return state.lastDuration
	end

	Safety.inMission = function()
		return state.inMission
	end

	Safety.lastDuration = function()
		return state.lastDuration
	end

	-- True when the safety timer allows leaving the mission.
	Safety.canLeave = function()
		if not state.inMission then
			return true
		end
		return Safety.elapsed() >= Safety.timerAmount()
	end

	-- Seconds left before leaving is allowed.
	Safety.remaining = function()
		if not state.inMission then
			return 0
		end
		return math.max(0, Safety.timerAmount() - Safety.elapsed())
	end

	Safety.reset = function()
		state.inMission = false
		state.startedAt = 0
		state.lastDuration = 0
		state.trackedElapsed = 0
		state.lastSampleRemaining = nil
		state.lastHudValue = nil
		state.rewardsSeen = false
	end

	return Safety
end
