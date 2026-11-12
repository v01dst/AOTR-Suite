--[[
	AOTR Suite :: Config
	Schema + multi profile configuration store.

	Design notes
	------------
	* The schema is intentionally a superset of the classic `TekkitConfig`
	  table, so configs written for Tekkit Hub keep loading unchanged.
	* Profiles are stored one file per profile under a single folder:
	      AOTRSuite/configs/<profile>.json
	  and the active profile name lives in
	      AOTRSuite/active.txt
	  This fixes the "unorganized / duplicated config files" problem.
	* Every write goes through an atomic temp-file swap and a single flight
	  guard, which fixes the race condition on file loading.
]]

return function(Ctx)
	local Util = Ctx.Util
	local Config = {}

	------------------------------------------------------------------
	-- Schema
	------------------------------------------------------------------

	Config.ROOT_FOLDER = "AOTRSuite"
	Config.CONFIG_FOLDER = "AOTRSuite/configs"
	Config.ACTIVE_FILE = "AOTRSuite/active.txt"
	Config.DEFAULT_PROFILE = "default"

	Config.DEFAULTS = {
		-- ===== FARM =====
		AutoFarm = false,
		FarmMethod = "Blade", -- "Blade" | "Hover" | "Teleport"
		DisableHovering = false,
		TargetPriority = "Closest", -- "Closest" | "Bosses First" | "Crawlers & Abnormals" | "Lowest HP"
		HoverHeight = 265,
		HoverSpeed = 3000,
		BehindNapeDistance = 2,
		TeleportTitans = false,
		HitDistance = 1000,
		MultiHit = 9,
		BossDamage = 9,
		DamageExtender = false,
		DamageMultiplier = 3,
		InfiniteSpears = false,
		NapeExtend = false,
		TitanEsp = false,
		NoTitanLag = true,
		DisableRendering = true,
		AutoUseSkills = false,

		-- ===== RELOAD / REFILL =====
		AutoReload = false,
		AutoRefill = false,
		ReloadStation = "Safest", -- "Safest" | "Nearest"
		SafetyTime = 30, -- hard minimum is 30 seconds

		-- ===== CLAIMS =====
		ClaimAchievements = false,
		ClaimQuests = false,
		ClaimBattlePass = true,
		-- ClaimDailyReward has no toggle on purpose, it is always active.

		-- ===== BOOSTS =====
		BuyBoosts = false,
		ItemtoBuyWith = "Canes", -- "Canes" | "Gems" | "Pumpkins"
		Boosts = { "2x Gold Boost [2h]" },

		-- ===== AUTO START =====
		AutoStart = false,
		AutoStartType = "Missions", -- "Missions" | "Raids"
		AutoStartMap = "Shiganshina",
		AutoStartObjective = "Breach",
		AutoStartDifficulty = "Hardest (w/ Freedom)",
		AutoStartModifiers = {
			"No Skills",
			"No Talents",
			"Nightmare",
			"Oddball",
			"Injury Prone",
			"Chronic Injuries",
			"Fog",
			"Glass Cannon",
			"Time Trial",
		},
		PlayBoostedMap = false,
		AutoReturn = false,
		ReturnAmount = 15,
		Kaitun = false,

		-- ===== WAVES =====
		WaveToDieAt = 0,
		AutoWaveDie = false,
		WavesRollBlessing = false,
		WavesBuyUpgrades = false,
		WavesAutoUpgrade = false,
		WavesAutoSkip = false,
		WavesGetCrates = false,
		WavesUpgradesToBuy = {},
		TargetBoss = false,

		-- ===== PROGRESSION =====
		AutoPrestige = false,
		PrestigeToStopAt = 5,
		AutoSkillTree = false,
		LeftPath = "Skill Cooldown",
		MiddlePath = "Damage",
		RightPath = "Damage Reduction",
		PathPriority = "Middle",

		-- ===== WEBHOOK =====
		Webhook = false,
		WebhookLink = "",
		ShowUsername = true,
		SendSafetyUpdate = false,

		-- ===== MISC =====
		AntiAFK = true,
		ShadowBanCheck = false,
		PrivateServerCode = "-",
		LeaveIfMorePlayers = false,
		AutoSelectSlot = true,
		Slot = "B",
		StreakAmount = 0,
		StreakDie = false,

		-- ===== PROFILE =====
		ConfigProfile = Config.DEFAULT_PROFILE,
	}

	-- Difficulty ladder used by Auto Start. "Hardest (w/ Freedom)" is the
	-- top tier that is only selectable once Freedom is unlocked.
	Config.DIFFICULTIES = {
		{ name = "Easy", grade = 2 },
		{ name = "Normal", grade = 5 },
		{ name = "Hard", grade = 8 },
		{ name = "Severe", grade = 11 },
		{ name = "Aberrant", grade = 14 },
		{ name = "Freedom", grade = 15 },
		{ name = "Hardest (w/ Freedom)", grade = 15 },
	}

	Config.CURRENCIES = { "Canes", "Gems", "Pumpkins" }

	------------------------------------------------------------------
	-- Current state
	------------------------------------------------------------------

	Config.Data = Util.deepCopy(Config.DEFAULTS)
	Config.ActiveProfile = Config.DEFAULT_PROFILE

	------------------------------------------------------------------
	-- Filesystem helpers
	------------------------------------------------------------------

	local function ensureFolder(path)
		if not Util.hasMakeFolder then
			return
		end
		-- Walk the path and create every segment. Most executors create
		-- parents automatically, but a few do not.
		local parts = {}
		for segment in string.gmatch(path, "[^/\\]+") do
			parts[#parts + 1] = segment
		end
		local current = ""
		for _, segment in ipairs(parts) do
			current = current .. "/" .. segment
			pcall(makefolder, current)
		end
	end

	local function writeAtomic(path, content)
		if not Util.hasFileIO then
			return false
		end
		ensureFolder(Config.CONFIG_FOLDER)
		local temp = path .. ".tmp"
		local ok = pcall(function()
			writefile(temp, content)
		end)
		if not ok then
			return false
		end
		local data = Util.safe(readfile, temp)
		if data == nil then
			pcall(function()
				delfile(temp)
			end)
			return false
		end
		pcall(function()
			writefile(path, data)
		end)
		pcall(function()
			delfile(temp)
		end)
		return true
	end

	local function removeFile(path)
		if Util.hasDeleteFile then
			pcall(delfile, path)
		end
	end

	------------------------------------------------------------------
	-- Profile discovery
	------------------------------------------------------------------

	-- Profiles are compared by a normalised key, so "Farm One",
	-- "farm one" and "FarmOne" are the same profile and never end up as
	-- three separate files.
	local function profileKey(name)
		local key = string.lower(Util.sanitizeName(name))
		key = key:gsub("[%s%-]", "")
		return key
	end

	-- Lists profiles without duplicates. Files whose names only differ by
	-- case are treated as the same profile, which removes the duplicated
	-- config files that older versions produced.
	Config.listProfiles = function()
		local profiles = {}
		local seen = {}
		if not Util.hasFileIO then
			return profiles
		end
		ensureFolder(Config.CONFIG_FOLDER)
		local files = {}
		if Util.hasListFiles then
			local ok, list = pcall(listfiles, Config.CONFIG_FOLDER)
			if ok and type(list) == "table" then
				files = list
			end
		end
		if #files == 0 and Util.hasIsFile then
			-- Fall back to the known profiles we may have written before.
			for _, name in ipairs({ Config.DEFAULT_PROFILE, Config.ActiveProfile }) do
				local file = Config.CONFIG_FOLDER .. "/" .. Util.sanitizeName(name) .. ".json"
				if Util.safe(isfile, file) then
					table.insert(files, file)
				end
			end
		end
		for _, file in ipairs(files) do
			if type(file) == "string" and file:match("%.json$") then
				local base = file:match("([^/\\]+)%.json$")
				local key = profileKey(base)
				if key ~= "" and not seen[key] then
					seen[key] = true
					table.insert(profiles, { name = base, file = file, key = key })
				end
			end
		end
		table.sort(profiles, function(a, b)
			return a.key < b.key
		end)
		return profiles
	end

	Config.profilePath = function(name)
		return Config.CONFIG_FOLDER .. "/" .. Util.sanitizeName(name) .. ".json"
	end

	------------------------------------------------------------------
	-- Load / save with single flight guard
	------------------------------------------------------------------

	-- Any load that starts while another one is running is queued instead
	-- of racing it. Combined with the generation counter this removes the
	-- race condition on file loading entirely.
	local loadGeneration = 0
	local loadInProgress = false
	local loadWaiters = {}

	local function releaseLoad()
		loadInProgress = false
		local waiters = loadWaiters
		loadWaiters = {}
		for _, waiter in ipairs(waiters) do
			waiter()
		end
	end

	local function rawLoad(name)
		local file = Config.profilePath(name)
		if not Util.hasFileIO then
			return false
		end
		if Util.hasIsFile and not Util.safe(isfile, file) then
			return false
		end
		local raw = Util.safe(readfile, file)
		if type(raw) ~= "string" or raw == "" then
			return false
		end
		local decoded = Util.jsonDecode(raw)
		if type(decoded) ~= "table" then
			return false
		end
		Config.Data = Util.deepMerge(Config.DEFAULTS, decoded)
		Config.Data.ConfigProfile = Util.sanitizeName(name)
		Config.ActiveProfile = Config.Data.ConfigProfile
		return true
	end

	Config.loadProfile = function(name)
		name = Util.sanitizeName(name or Config.ActiveProfile)
		if loadInProgress then
			-- Queue behind the running load instead of starting a second one.
			local waiter
			waiter = function()
				Config.loadProfile(name)
			end
			table.insert(loadWaiters, waiter)
			return false
		end
		loadInProgress = true
		loadGeneration = loadGeneration + 1
		local generation = loadGeneration
		local ok = false
		ok = rawLoad(name)
		if generation ~= loadGeneration then
			-- A newer load superseded this one, drop the result.
			releaseLoad()
			return false
		end
		if ok then
			Config.writeActiveProfile(name)
			Config.notifyChanged()
		end
		releaseLoad()
		return ok
	end

	Config.writeActiveProfile = function(name)
		if not Util.hasFileIO then
			return
		end
		ensureFolder(Config.ROOT_FOLDER)
		writeAtomic(Config.ACTIVE_FILE, Util.sanitizeName(name))
	end

	Config.readActiveProfile = function()
		if not Util.hasFileIO then
			return nil
		end
		local raw = Util.safe(readfile, Config.ACTIVE_FILE)
		if type(raw) ~= "string" or raw == "" then
			return nil
		end
		return Util.sanitizeName(raw)
	end

	------------------------------------------------------------------
	-- Public API
	------------------------------------------------------------------

	Config.Save = function(name)
		name = Util.sanitizeName(name or Config.ActiveProfile)
		Config.Data.ConfigProfile = name
		Config.ActiveProfile = name
		if not Util.hasFileIO then
			return false
		end
		ensureFolder(Config.CONFIG_FOLDER)
		local ok = writeAtomic(Config.profilePath(name), Util.jsonEncode(Config.Data) or "")
		if ok then
			Config.writeActiveProfile(name)
			-- Remove any older duplicate that maps to the same profile key.
			local key = profileKey(name)
			for _, profile in ipairs(Config.listProfiles()) do
				if profile.key == key and profile.name ~= Util.sanitizeName(name) then
					removeFile(profile.file)
				end
			end
		end
		return ok
	end

	Config.New = function(name)
		name = Util.sanitizeName(name)
		Config.Data = Util.deepCopy(Config.DEFAULTS)
		Config.Data.ConfigProfile = name
		Config.ActiveProfile = name
		return Config.Save(name)
	end

	Config.Delete = function(name)
		name = Util.sanitizeName(name)
		removeFile(Config.profilePath(name))
		if profileKey(name) == profileKey(Config.ActiveProfile) then
			Config.ActiveProfile = Config.DEFAULT_PROFILE
			Config.Data = Util.deepCopy(Config.DEFAULTS)
			Config.writeActiveProfile(Config.DEFAULT_PROFILE)
		end
		return true
	end

	Config.Select = function(name)
		name = Util.sanitizeName(name)
		if not Config.loadProfile(name) then
			-- Selecting a profile that does not exist yet creates it.
			Config.New(name)
		end
		return Config.ActiveProfile
	end

	------------------------------------------------------------------
	-- Change notification (used by the Config tab to mark it dirty)
	------------------------------------------------------------------

	local changeListeners = {}

	Config.onChanged = function(callback)
		table.insert(changeListeners, callback)
	end

	Config.notifyChanged = function()
		for _, callback in ipairs(changeListeners) do
			pcall(callback)
		end
	end

	Config.Get = function()
		return Config.Data
	end

	-- Dotted path setter: Config.Set("Farm.HoverHeight", 300)
	Config.Set = function(path, value)
		local segments = {}
		for segment in string.gmatch(tostring(path), "[^%.]+") do
			table.insert(segments, segment)
		end
		if #segments == 0 then
			return
		end
		local node = Config.Data
		for index = 1, #segments - 1 do
			local key = segments[index]
			if type(node[key]) ~= "table" then
				node[key] = {}
			end
			node = node[key]
		end
		node[segments[#segments]] = value
		Config.notifyChanged()
	end

	------------------------------------------------------------------
	-- Boot: auto load
	------------------------------------------------------------------

	-- Auto Load Config:
	--   1. start from the defaults
	--   2. overlay a `TekkitConfig` table if the user exported one
	--   3. overlay the profile that was active last time
	Config.AutoLoad = function()
		Config.Data = Util.deepCopy(Config.DEFAULTS)

		local genv = (getgenv and getgenv()) or _G
		local tekkit = genv.TekkitConfig
		if type(tekkit) == "table" then
			Config.Data = Util.deepMerge(Config.Data, tekkit)
			Util.log("merged external TekkitConfig")
		end

		local active = Config.readActiveProfile()
		if active then
			if Config.loadProfile(active) then
				Util.log("auto loaded config profile:", active)
			end
		end

		if not Util.hasFileIO then
			Util.warn("executor has no file access, config persistence is disabled")
		end
		return Config.Data
	end

	return Config
end
