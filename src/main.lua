--[[
	AOTR Suite :: main
	Entry point.

	The interface is built first so there is always something on screen,
	every later step runs protected and reports into the diagnostics tab.
]]

return function(MOD)
	local Util = MOD.Util
	local RunService = game:GetService("RunService")
	local Players = game:GetService("Players")

	------------------------------------------------------------------
	-- Single instance guard
	------------------------------------------------------------------

	local genv = (getgenv and getgenv()) or _G
	if genv.AOTRSuite and genv.AOTRSuite.Running then
		Util.warn("AOTRSuite is already running.")
		return nil
	end

	------------------------------------------------------------------
	-- Context
	------------------------------------------------------------------
	-- The context is filled in step by step. Every module receives the
	-- same table by reference and only reads from it at runtime, so the
	-- order below does not have to be perfect.

	local Ctx = {
		Util = Util,
		Rayfield = MOD.Rayfield,
		state = {},
	}

	local function build(name)
		Ctx[name] = MOD[name](Ctx)
		return Ctx[name]
	end

	build("Config")
	build("Remotes")
	build("GameUI")
	build("Targets")
	build("Stats")
	build("Safety")
	build("Webhook")
	build("Farm")
	build("Combat")
	build("Reload")
	build("Claim")
	build("Boosts")
	build("AutoStart")
	build("Waves")
	build("ShadowBan")
	build("FallbackUI")
	build("Diagnostics")
	build("Hub")

	if type(Ctx.Rayfield) ~= "table" then
		Util.log("the Rayfield interface is not available, the built in interface is used")
	end

	local Config = Ctx.Config
	local GameUI = Ctx.GameUI
	local Stats = Ctx.Stats
	local Safety = Ctx.Safety
	local Webhook = Ctx.Webhook
	local Farm = Ctx.Farm
	local Combat = Ctx.Combat
	local Reload = Ctx.Reload
	local Claim = Ctx.Claim
	local Boosts = Ctx.Boosts
	local AutoStart = Ctx.AutoStart
	local Waves = Ctx.Waves
	local ShadowBan = Ctx.ShadowBan
	local Hub = Ctx.Hub
	local Diagnostics = Ctx.Diagnostics

	------------------------------------------------------------------
	-- Collect what we know before anything can fail
	------------------------------------------------------------------

	Diagnostics.set("executor", Diagnostics.detectExecutor())
	Diagnostics.set("gameId", game.GameId)
	Diagnostics.set("placeId", game.PlaceId)
	Diagnostics.set("player", Players.LocalPlayer and Players.LocalPlayer.Name or "?")

	------------------------------------------------------------------
	-- Boot, step by step, every step protected
	------------------------------------------------------------------

	local function step(name, fn)
		local ok, result = pcall(fn)
		if not ok then
			Diagnostics.error(name .. ": " .. tostring(result))
		end
		return ok, result
	end

	step("config", function()
		Config.AutoLoad()
		Diagnostics.set("profile", Config.ActiveProfile)
	end)

	-- The interface comes before the rest, so a window is visible even if
	-- something later goes wrong.
	local interfaceOk = step("interface", function()
		Hub.build()
		Diagnostics.set("interface", Hub.providerName())
	end)
	if not interfaceOk then
		-- Nothing worked, write the reason on the screen.
		pcall(function()
			Ctx.FallbackUI:Emergency("AOTR Suite could not open its interface:\n" .. tostring(Diagnostics.state.errors[1]))
		end)
	end

	step("remotes", function()
		local post, get = Ctx.Remotes.resolve(true)
		Diagnostics.set("postRemote", post ~= nil)
		Diagnostics.set("getRemote", get ~= nil)
	end)

	------------------------------------------------------------------
	-- Anti AFK
	------------------------------------------------------------------

	local antiAfkConnection = nil
	local function setupAntiAfK()
		if antiAfkConnection then
			antiAfkConnection:Disconnect()
			antiAfkConnection = nil
		end
		if not Config.Get().AntiAFK then
			return
		end
		local player = Players.LocalPlayer
		if not player then
			return
		end
		antiAfkConnection = player.Idled:Connect(function()
			Util.warn("idle detected, nudging the character")
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then
				root.CFrame = root.CFrame + Vector3.new(0, 0, 0.5)
			end
		end)
	end
	step("anti afk", setupAntiAfK)
	Config.onChanged(setupAntiAfK)

	------------------------------------------------------------------
	-- Session bookkeeping
	------------------------------------------------------------------

	local lastRewardsVisible = false
	local lastInMission = false
	local missionsSinceReturn = 0

	local function handleMissionEnd()
		local drops = Webhook.collectDrops()
		if Config.Get().Webhook and Config.Get().SendSafetyUpdate then
			Webhook.reportMission(drops)
		end
		Stats.session.missions = Stats.session.missions + 1
		missionsSinceReturn = missionsSinceReturn + 1
		Webhook.markBaseline()

		local settings = Config.Get()
		if settings.AutoReturn == true and missionsSinceReturn >= (settings.ReturnAmount or 15) then
			missionsSinceReturn = 0
			local leave = GameUI.leaveButton()
			if leave then
				Util.click(leave)
			end
		end
	end

	------------------------------------------------------------------
	-- Loops
	------------------------------------------------------------------

	-- Fast loop: movement, targeting and the safety timer.
	RunService.Heartbeat:Connect(function(deltaTime)
		local ok, err = pcall(function()
			Safety.update()
			Farm.update(deltaTime)
			Combat.update()
		end)
		if not ok then
			Diagnostics.error("heartbeat: " .. tostring(err))
		end
	end)

	-- Slow loop: everything that talks to the interface.
	task.spawn(function()
		while true do
			task.wait(1)
			pcall(Reload.update)
			pcall(Claim.update)
			pcall(Waves.update)
			pcall(ShadowBan.update)

			-- Mission end detection.
			local rewardsVisible = GameUI.rewardsVisible()
			if rewardsVisible and not lastRewardsVisible then
				handleMissionEnd()
			end
			lastRewardsVisible = rewardsVisible

			-- The drop list is the difference between the currencies at the
			-- start and at the end of the mission, so the baseline is taken
			-- when the mission starts.
			local inMission = Safety.inMission()
			if inMission and not lastInMission then
				Webhook.markBaseline()
			end
			lastInMission = inMission
		end
	end)

	-- Slower loop: the shop and the session automation.
	task.spawn(function()
		while true do
			task.wait(3)
			pcall(Boosts.update)
			pcall(AutoStart.update)
		end
	end)

	-- The nape extender runs a bit slower than the combat loop.
	task.spawn(function()
		while true do
			task.wait(0.5)
			pcall(Farm.extendNapes)
		end
	end)

	------------------------------------------------------------------
	-- Public handle
	------------------------------------------------------------------

	genv.AOTRSuite = {
		Running = true,
		Config = Config,
		Ctx = Ctx,
		Diagnostics = Diagnostics,
		Stop = function()
			RunService.Heartbeat:Disconnect()
			if antiAfkConnection then
				antiAfkConnection:Disconnect()
			end
			local window = Hub.window()
			if window then
				pcall(function()
					window:Destroy()
				end)
			end
			genv.AOTRSuite.Running = false
		end,
	}

	------------------------------------------------------------------
	-- Tell the user what happened, on the screen and in the console
	------------------------------------------------------------------

	local interface = Diagnostics.state.interface or "none"
	local post = Diagnostics.state.postRemote and "found" or "missing"
	local message = string.format(
		"interface: %s | POST remote: %s | profile: %s",
		interface,
		post,
		tostring(Diagnostics.state.profile or "default")
	)
	Diagnostics.publish("AOTR Suite loaded", message)

	return genv.AOTRSuite
end
