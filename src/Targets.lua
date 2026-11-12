--[[
	AOTR Suite :: Targets
	Titan discovery, hitbox resolution and classification.

	Fixes implemented here (from the v0276 changelog):
		* Raid bosses that are immune to damage are never registered as a
		  hitbox, so the suite stops wasting attacks on them.
		* The Armored Titan is skipped while it is protecting the boats.
		* Normal titans inside a Colossal Raid are found as well, which is
		  what made spears fail to kill them.
		* Targeting no longer sticks to a dead or removed titan.
]]

return function(Ctx)
	local Util = Ctx.Util
	local Targets = {}

	local Workspace = game:GetService("Workspace")

	local napeCache = setmetatable({}, { __mode = "k" })
	local deadCache = setmetatable({}, { __mode = "k" })

	local SEARCH_FOLDERS = {
		"Titans",
		"Enemies",
		"Boss",
		"Bosses",
		"Raid",
		"RaidTitans",
		"Spawns",
		"Entities",
		"Living",
		"Targets",
	}

	------------------------------------------------------------------
	-- Nape resolution
	------------------------------------------------------------------

	Targets.findNape = function(titan)
		if not titan or not titan.Parent then
			return nil
		end
		local cached = napeCache[titan]
		if cached and cached.Parent and cached:IsDescendantOf(titan) then
			return cached
		end

		local hitboxes = titan:FindFirstChild("Hitboxes")
		local nape = nil
		if hitboxes then
			local hit = hitboxes:FindFirstChild("Hit")
			nape = (hit and hit:FindFirstChild("Nape")) or hitboxes:FindFirstChild("Nape")
		end
		if not nape then
			for _, part in ipairs(titan:GetDescendants()) do
				if part:IsA("BasePart") then
					local name = string.lower(part.Name)
					if name == "nape" or name == "weakpoint" or name == "core" or name == "neck" then
						nape = part
						break
					end
				end
			end
		end
		if nape and nape:IsA("BasePart") then
			napeCache[titan] = nape
			return nape
		end
		return nil
	end

	------------------------------------------------------------------
	-- Classification
	------------------------------------------------------------------

	local IMMUNE_ATTRIBUTES = {
		"Immune",
		"Invulnerable",
		"DamageImmune",
		"CannotBeDamaged",
		"Undodgeable",
	}

	local function attributeIsTrue(model, names)
		for _, name in ipairs(names) do
			if model:GetAttribute(name) == true then
				return true
			end
		end
		return false
	end

	-- A titan is untouchable when the server marked it immune, either
	-- through an attribute or through a boolean child.
	Targets.isImmune = function(model)
		if not model then
			return false
		end
		if attributeIsTrue(model, IMMUNE_ATTRIBUTES) then
			return true
		end
		local flag = Util.findDeep(model, function(node)
			if not node:IsA("BoolValue") then
				return false
			end
			local name = string.lower(node.Name)
			return node.Value == true and (string.find(name, "immun", 1, true) or string.find(name, "invulner", 1, true))
		end, 6)
		return flag ~= nil
	end

	-- The Armored Titan has to be left alone while it shields the boats.
	Targets.isProtectingBoats = function(model)
		if not model then
			return false
		end
		if attributeIsTrue(model, { "ProtectingBoats", "Protecting", "DefendingBoats", "EscortingBoats" }) then
			return true
		end
		for _, name in ipairs({ "ProtectingBoats", "Protecting", "DefendingBoats" }) do
			local value = model:FindFirstChild(name)
			if value and value:IsA("BoolValue") and value.Value == true then
				return true
			end
		end
		return false
	end

	local function cleanName(model)
		if not model then
			return "Titan"
		end
		for _, attribute in ipairs({ "Title", "TitanType", "Type", "Variant", "BossName", "Class" }) do
			local value = model:GetAttribute(attribute)
			if type(value) == "string" and value ~= "" and not value:match("%x+%-%x+") and #value < 24 then
				return value
			end
		end
		local raw = tostring(model.Name)
		if raw:match("%x+%-%x+") or #raw >= 24 then
			if model:FindFirstChild("Abnormal") or model:GetAttribute("Abnormal") == true then
				return "Abnormal Titan"
			elseif model:FindFirstChild("Crawler") or model:GetAttribute("Crawler") == true then
				return "Crawler Titan"
			elseif model:FindFirstChild("Shifter") or model:GetAttribute("Shifter") == true then
				return "Titan Shifter"
			elseif model:FindFirstChild("Boss") or model:GetAttribute("Boss") == true or string.find(string.lower(raw), "colossal", 1, true) then
				return "Boss Titan"
			end
			return "Titan"
		end
		return raw
	end

	------------------------------------------------------------------
	-- Liveness
	------------------------------------------------------------------

	Targets.isAlive = function(entry)
		if not entry or not entry.model or not entry.model.Parent then
			return false
		end
		if deadCache[entry.model] then
			return false
		end
		local humanoid = entry.humanoid
		if humanoid and humanoid.Health <= 0 then
			deadCache[entry.model] = true
			return false
		end
		local nape = entry.nape
		if nape and nape.Parent and type(nape.Transparency) == "number" and nape.Transparency >= 1 and not nape.Anchored then
			-- A removed hitbox means the titan is gone.
			deadCache[entry.model] = true
			return false
		end
		return true
	end

	Targets.markDead = function(model)
		deadCache[model] = true
		napeCache[model] = nil
	end

	------------------------------------------------------------------
	-- Discovery
	------------------------------------------------------------------

	local function collectFolders()
		local folders = {}
		local seen = {}
		local function push(folder)
			if folder and not seen[folder] then
				seen[folder] = true
				table.insert(folders, folder)
			end
		end
		for _, name in ipairs(SEARCH_FOLDERS) do
			push(Workspace:FindFirstChild(name))
		end
		local map = Workspace:FindFirstChild("Map")
		if map then
			for _, child in ipairs(map:GetChildren()) do
				push(child)
			end
		end
		return folders
	end

	-- Titans that live inside a raid are sometimes parented to a nested
	-- model instead of a top level folder, so the raid container is
	-- searched one level deeper.
	local function collectRaidTitans()
		local found = {}
		local seen = {}
		local containers = {
			Workspace:FindFirstChild("Raid"),
			Workspace:FindFirstChild("RaidTitans"),
			Workspace:FindFirstChild("ColossalRaid"),
			Workspace:FindFirstChild("Colossal"),
		}
		for _, container in ipairs(containers) do
			if container then
				for _, child in ipairs(container:GetDescendants()) do
					if child:IsA("Model") and not seen[child] then
						seen[child] = true
						table.insert(found, child)
					end
				end
			end
		end
		return found
	end

	-- The workspace scan is the expensive part, it is cached for a short
	-- time so the heartbeat loop does not walk the world every frame.
	local SCAN_INTERVAL = 0.25
	local scanCache = {}
	local scanTime = 0

	Targets.scan = function(force)
		local now = Util.now()
		if not force and now - scanTime < SCAN_INTERVAL then
			return scanCache
		end
		scanTime = now

		local models = {}
		local seen = {}
		for _, folder in ipairs(collectFolders()) do
			for _, child in ipairs(folder:GetChildren()) do
				if child:IsA("Model") and not seen[child] then
					seen[child] = true
					table.insert(models, child)
				end
			end
		end
		for _, child in ipairs(collectRaidTitans()) do
			if not seen[child] then
				seen[child] = true
				table.insert(models, child)
			end
		end
		scanCache = models
		return scanCache
	end

	Targets.getTitans = function()
		local list = {}
		local player = Util.LocalPlayer
		local character = player and player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")

		for _, model in ipairs(Targets.scan()) do
			if model ~= character then
				local humanoid = model:FindFirstChildOfClass("Humanoid")
				local nape = Targets.findNape(model)
				if nape then
					local name = cleanName(model)
					local lower = string.lower(name .. " " .. model.Name)
					local isBoss = string.find(lower, "boss", 1, true)
						or string.find(lower, "colossal", 1, true)
						or string.find(lower, "armored", 1, true)
						or string.find(lower, "female", 1, true)
						or string.find(lower, "beast", 1, true)
						or string.find(lower, "shifter", 1, true)
						or model:GetAttribute("Boss") == true
					local isCrawler = string.find(lower, "crawler", 1, true) or model:GetAttribute("Crawler") == true
					local isAbnormal = string.find(lower, "abnormal", 1, true) or model:GetAttribute("Abnormal") == true
					local isArmored = string.find(lower, "armored", 1, true) or model:GetAttribute("Armored") == true
					local distance = root and (nape.Position - root.Position).Magnitude or 9999

					table.insert(list, {
						model = model,
						name = name,
						humanoid = humanoid,
						nape = nape,
						dist = distance,
						hp = humanoid and humanoid.Health or 100,
						isBoss = isBoss,
						isCrawler = isCrawler,
						isAbnormal = isAbnormal,
						isArmored = isArmored,
						isImmune = Targets.isImmune(model),
						isProtectingBoats = Targets.isProtectingBoats(model),
					})
				end
			end
		end

		return list
	end

	------------------------------------------------------------------
	-- Sorting
	------------------------------------------------------------------

	Targets.sort = function(list, priority)
		priority = priority or "Closest"
		table.sort(list, function(a, b)
			if priority == "Bosses First" then
				if a.isBoss ~= b.isBoss then
					return a.isBoss
				end
				return a.dist < b.dist
			elseif priority == "Crawlers & Abnormals" then
				local threatA = a.isCrawler or a.isAbnormal or a.isBoss
				local threatB = b.isCrawler or b.isAbnormal or b.isBoss
				if threatA ~= threatB then
					return threatA
				end
				return a.dist < b.dist
			elseif priority == "Lowest HP" then
				if math.abs(a.hp - b.hp) > 50 then
					return a.hp < b.hp
				end
				return a.dist < b.dist
			end
			return a.dist < b.dist
		end)
		return list
	end

	-- Picks the next target, honouring the immunity and the boat rule.
	Targets.pick = function(list, priority)
		priority = priority or "Closest"
		Targets.sort(list, priority)
		for _, entry in ipairs(list) do
			local usable = Targets.isAlive(entry)
			if usable and entry.isImmune then
				-- Immune raid bosses must not be hit at all.
				usable = false
			end
			if usable and entry.isArmored and entry.isProtectingBoats then
				-- The armored titan is busy shielding the boats.
				usable = false
			end
			if usable then
				return entry
			end
		end
		return nil
	end

	-- Collects the extra targets that can be hit with the same swing.
	Targets.neighbours = function(primary, radius, limit)
		local result = {}
		if not primary then
			return result
		end
		local player = Util.LocalPlayer
		local character = player and player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		for _, entry in ipairs(Targets.getTitans()) do
			if entry ~= primary and Targets.isAlive(entry) and not entry.isImmune then
				local toPrimary = (entry.nape.Position - primary.nape.Position).Magnitude
				local toPlayer = root and (entry.nape.Position - root.Position).Magnitude or toPrimary
				if toPrimary <= radius or toPlayer <= radius then
					table.insert(result, entry)
					if #result >= (limit or 4) then
						break
					end
				end
			end
		end
		return result
	end

	return Targets
end
