--[[
	AOTR Suite :: Features / Claim
	Auto claim for achievements, quests, battle pass quests and the daily
	reward.

	The daily reward has no toggle on purpose, it is always active.
	Everything is driven through the game interface by keyword, which keeps
	working when the game moves its panels around. A remote fallback exists
	for the parts that are not exposed as a button.
]]

return function(Ctx)
	local Util = Ctx.Util
	local Claim = {}

	local state = {
		lastRun = 0,
		achievements = 0,
		quests = 0,
		battlePass = 0,
		daily = 0,
	}

	------------------------------------------------------------------
	-- Helpers
	------------------------------------------------------------------

	local function config()
		return Ctx.Config.Get()
	end

	-- Opens a panel of the interface by keyword and returns its root.
	local function openPanel(keywords)
		local matches = Ctx.GameUI.findClickables(Ctx.GameUI.interface(), keywords, true)
		if #matches == 0 then
			return nil
		end
		Util.click(matches[1])
		task.wait(0.35)
		-- The opened panel is the deepest visible frame that contains the
		-- word we searched for.
		local root = nil
		for _, node in ipairs(Ctx.GameUI.findClickables(Ctx.GameUI.interface(), keywords, true)) do
			local ancestor = node
			while ancestor and ancestor:IsA("GuiObject") do
				if ancestor.Name:lower():find("panel", 1, true) or ancestor.Name:lower():find("menu", 1, true) then
					root = ancestor
					break
				end
				ancestor = ancestor.Parent
			end
			if root then
				break
			end
		end
		return root or Ctx.GameUI.interface()
	end

	-- Clicks every enabled claim button inside a root.
	local function claimButtons(root, keywords)
		local count = 0
		local buttons = Ctx.GameUI.findClickables(root, keywords, true)
		for _, button in ipairs(buttons) do
			if button:IsA("GuiObject") and button.Active and button.Selectable ~= false then
				if Util.click(button) then
					count = count + 1
					task.wait(0.12)
				end
			end
		end
		return count
	end

	------------------------------------------------------------------
	-- Achievements
	------------------------------------------------------------------

	Claim.achievements = function()
		local root = openPanel({ "Achievements", "Achievement" })
		if not root then
			return 0
		end
		local count = claimButtons(root, { "Claim" })
		-- Some layouts need the dedicated "Claim All" button.
		if count == 0 then
			count = claimButtons(root, { "Claim All" })
		end
		state.achievements = state.achievements + count
		if count > 0 then
			Ctx.Stats.session.achievementsClaimed = Ctx.Stats.session.achievementsClaimed + count
		end
		return count
	end

	------------------------------------------------------------------
	-- Quests (including the battle pass)
	------------------------------------------------------------------

	Claim.quests = function()
		local root = openPanel({ "Quests", "Quest" })
		if not root then
			return 0
		end
		local count = claimButtons(root, { "Claim" })
		count = count + claimButtons(root, { "Claim All" })
		state.quests = state.quests + count
		if count > 0 then
			Ctx.Stats.session.questsClaimed = Ctx.Stats.session.questsClaimed + count
		end
		return count
	end

	-- The battle pass quests live in their own tab of the quest panel.
	Claim.battlePass = function()
		local root = openPanel({ "Quests", "Quest" })
		if not root then
			return 0
		end
		local tabs = Ctx.GameUI.findClickables(root, { "Battle Pass", "BattlePass", "Season" }, true)
		for _, tab in ipairs(tabs) do
			Util.click(tab)
			task.wait(0.3)
			break
		end
		local count = claimButtons(root, { "Claim" })
		count = count + claimButtons(root, { "Claim All" })
		state.battlePass = state.battlePass + count
		return count
	end

	------------------------------------------------------------------
	-- Daily reward, always active
	------------------------------------------------------------------

	Claim.dailyReward = function()
		local root = openPanel({ "Daily Reward", "DailyRewards", "Daily", "Login Reward" })
		if not root then
			return 0
		end
		local count = claimButtons(root, { "Claim" })
		count = count + claimButtons(root, { "Collect", "Redeem" })
		state.daily = state.daily + count
		return count
	end

	------------------------------------------------------------------
	-- Remote fallback
	------------------------------------------------------------------

	-- Some claim actions are only reachable through the server. The
	-- signature that works is remembered for the rest of the session.
	local function remoteFallback()
		Ctx.Remotes.postAny("claim_achievement", {
			{ "Achievements", "Claim" },
			{ "Achievement", "Claim" },
			{ "Quests", "Claim" },
		})
	end

	------------------------------------------------------------------
	-- Main update
	------------------------------------------------------------------

	Claim.update = function()
		local settings = config()
		local now = Util.now()
		if now - state.lastRun < 3 then
			return
		end
		state.lastRun = now

		-- The daily reward is always claimed, there is no toggle for it.
		Claim.dailyReward()

		if settings.ClaimAchievements == true then
			if Claim.achievements() == 0 then
				remoteFallback()
			end
		end

		if settings.ClaimQuests == true then
			Claim.quests()
			if settings.ClaimBattlePass ~= false then
				Claim.battlePass()
			end
		end
	end

	Claim.state = state

	return Claim
end
