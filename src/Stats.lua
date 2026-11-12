--[[
	AOTR Suite :: Stats
	Reads the player currencies and keeps the session counters.

	Pumpkins are a first class currency here: they show up in the player
	stats block and in the drop list of the Discord webhook.
]]

return function(Ctx)
	local Util = Ctx.Util
	local Stats = {}

	local Players = game:GetService("Players")

	-- Currencies the game exposes, with the attribute / leaderstat names
	-- that are used for them.
	Stats.CURRENCIES = {
		{ key = "Gold", label = "Gold", names = { "Gold", "Coins", "Currency" } },
		{ key = "Gems", label = "Gems", names = { "Gems", "Gem", "Diamonds" } },
		{ key = "Canes", label = "Canes", names = { "Canes", "Cane", "Stick" } },
		{ key = "Pumpkins", label = "Pumpkins", names = { "Pumpkins", "Pumpkin" } },
		{ key = "XP", label = "XP", names = { "XP", "Experience", "Exp" } },
		{ key = "Level", label = "Level", names = { "Level", "Rank", "Lv" } },
	}

	------------------------------------------------------------------
	-- Value lookup
	------------------------------------------------------------------

	-- Roblox exposes typeof, the fallback keeps the module usable in a
	-- plain Lua environment.
	local function isInstance(value)
		if typeof then
			return typeof(value) == "Instance"
		end
		return type(value) == "Instance"
	end

	local function readFromStat(value)
		if type(value) == "number" then
			return value
		end
		if type(value) == "string" then
			local number = value:match("(%d+)")
			return tonumber(number)
		end
		if isInstance(value) then
			if value:IsA("NumberValue") or value:IsA("IntValue") or value:IsA("FloatValue") then
				return value.Value
			end
			if value:IsA("StringValue") then
				return tonumber((value.Value or ""):match("(%d+)"))
			end
		end
		return nil
	end

	-- Looks a currency up in leaderstats, in player attributes and in the
	-- replicated data folders the game keeps on the player.
	Stats.readCurrency = function(key)
		local player = Util.LocalPlayer or Players.LocalPlayer
		if not player then
			return nil
		end
		local definition = nil
		for _, entry in ipairs(Stats.CURRENCIES) do
			if entry.key == key then
				definition = entry
				break
			end
		end
		if not definition then
			return nil
		end

		local leaderstats = player:FindFirstChild("leaderstats")
		if leaderstats then
			for _, name in ipairs(definition.names) do
				local value = readFromStat(leaderstats:FindFirstChild(name))
				if value ~= nil then
					return value
				end
			end
		end

		local attributes = player:GetAttributes()
		for _, name in ipairs(definition.names) do
			local value = readFromStat(attributes[name])
			if value ~= nil then
				return value
			end
		end

		-- Some currencies only exist inside a replicated folder.
		for _, folderName in ipairs({ "Stats", "Currencies", "PlayerData", "Data" }) do
			local folder = player:FindFirstChild(folderName)
			if folder then
				for _, name in ipairs(definition.names) do
					local value = readFromStat(folder:FindFirstChild(name))
					if value ~= nil then
						return value
					end
				end
			end
		end

		return nil
	end

	------------------------------------------------------------------
	-- Session counters
	------------------------------------------------------------------

	Stats.session = {
		missions = 0,
		raids = 0,
		waves = 0,
		titansKilled = 0,
		bladesReloaded = 0,
		boostsBought = 0,
		achievementsClaimed = 0,
		questsClaimed = 0,
		startedAt = Util.now(),
	}

	Stats.reset = function()
		Stats.session.missions = 0
		Stats.session.raids = 0
		Stats.session.waves = 0
		Stats.session.titansKilled = 0
		Stats.session.bladesReloaded = 0
		Stats.session.boostsBought = 0
		Stats.session.achievementsClaimed = 0
		Stats.session.questsClaimed = 0
		Stats.session.startedAt = Util.now()
	end

	------------------------------------------------------------------
	-- Snapshot
	------------------------------------------------------------------

	Stats.snapshot = function()
		local snapshot = {}
		for _, entry in ipairs(Stats.CURRENCIES) do
			snapshot[entry.key] = Stats.readCurrency(entry.key)
		end
		snapshot.username = (Util.LocalPlayer and Util.LocalPlayer.Name) or "Unknown"
		snapshot.displayName = (Util.LocalPlayer and Util.LocalPlayer.DisplayName) or "Unknown"
		snapshot.session = Util.deepCopy(Stats.session)
		snapshot.sessionSeconds = Util.now() - Stats.session.startedAt
		return snapshot
	end

	return Stats
end
