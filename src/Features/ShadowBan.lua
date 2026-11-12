--[[
	AOTR Suite :: Features / ShadowBan
	Detects the silent ban that Roblox applies to flagged accounts.

	Detection is based on three independent signals:
		1. player attributes that mention a ban or a restriction
		2. boolean children of the player with a matching name
		3. the server refusing to answer the read remote
]]

return function(Ctx)
	local Util = Ctx.Util
	local ShadowBan = {}

	local state = {
		lastCheck = 0,
		clean = true,
		flags = {},
	}

	local BAN_ATTRIBUTES = { "ban", "flag", "cheat", "restrict", "shadowban", "muted" }

	------------------------------------------------------------------
	-- Signals
	------------------------------------------------------------------

	local function attributeFlags()
		local flags = {}
		local player = Util.LocalPlayer
		if not player then
			return flags
		end
		for name, value in pairs(player:GetAttributes()) do
			local lower = string.lower(tostring(name))
			for _, keyword in ipairs(BAN_ATTRIBUTES) do
				if string.find(lower, keyword, 1, true) and value == true then
					table.insert(flags, tostring(name))
					break
				end
			end
		end
		return flags
	end

	local function childFlags()
		local flags = {}
		local player = Util.LocalPlayer
		if not player then
			return flags
		end
		for _, child in ipairs(player:GetDescendants()) do
			if child:IsA("BoolValue") and child.Value == true then
				local lower = string.lower(child.Name)
				for _, keyword in ipairs(BAN_ATTRIBUTES) do
					if string.find(lower, keyword, 1, true) then
						table.insert(flags, child.Name)
						break
					end
				end
			end
		end
		return flags
	end

	-- The server stops answering when the account is flagged.
	local function serverResponds()
		local remote = Ctx.Remotes.getReady()
		if not remote then
			return true
		end
		local ok = pcall(function()
			if remote:IsA("RemoteFunction") then
				remote:InvokeServer("Ping")
			else
				remote:FireServer("Ping")
			end
		end)
		return ok
	end

	------------------------------------------------------------------
	-- Check
	------------------------------------------------------------------

	ShadowBan.check = function()
		local flags = {}
		for _, flag in ipairs(attributeFlags()) do
			table.insert(flags, flag)
		end
		for _, flag in ipairs(childFlags()) do
			table.insert(flags, flag)
		end

		-- The server stops answering the read remote once the account is
		-- flagged, that is the third independent signal.
		if not serverResponds() then
			table.insert(flags, "ServerUnresponsive")
		end

		state.flags = flags
		state.clean = #flags == 0
		state.lastCheck = Util.now()
		return state.clean, flags
	end

	ShadowBan.isClean = function()
		return state.clean
	end

	ShadowBan.flags = function()
		return state.flags
	end

	-- Runs the check and stops the farm when the account is flagged.
	ShadowBan.update = function()
		local settings = Ctx.Config.Get()
		if settings.ShadowBanCheck ~= true then
			return
		end
		local now = Util.now()
		if now - state.lastCheck < 10 then
			return
		end
		local clean, flags = ShadowBan.check()
		if not clean then
			Util.warn("shadow ban detected:", table.concat(flags, ", "))
			settings.AutoFarm = false
			settings.AutoStart = false
			Ctx.Config.notifyChanged()
		end
	end

	ShadowBan.state = state

	return ShadowBan
end
