--[[
	AOTR Suite :: Features / Combat
	Swings, spears, multi hit and the damage extender.

	Server API used:
		POST("Attacks", "Slash", true)
		POST("Attacks", "Slash_Release")
		POST("Attacks", "M1")
		POST("Hitboxes", "Register", <BasePart>, <damage>, <crit>)
		POST("S_Equipment", "Spears", "Fire", <Vector3>)
		POST("Attacks", "Spears", <Vector3>)
]]

return function(Ctx)
	local Util = Ctx.Util
	local Combat = {}

	local state = {
		lastSlash = 0,
		lastSpear = 0,
		slashCount = 0,
	}

	local BASE_DAMAGE = 500
	local BASE_CRIT = 100

	------------------------------------------------------------------
	-- Damage
	------------------------------------------------------------------

	-- The damage extender scales the damage value that is registered on
	-- the hitbox. 1 means untouched, higher values hit harder.
	Combat.damageScale = function(settings)
		if settings.DamageExtender ~= true then
			return 1
		end
		return Util.clamp(settings.DamageMultiplier or 1, 1, 50)
	end

	local function damageArguments(settings)
		local scale = Combat.damageScale(settings)
		if scale > 1 then
			return math.floor(BASE_DAMAGE * scale), math.floor(BASE_CRIT * scale)
		end
		return BASE_DAMAGE, BASE_CRIT
	end

	------------------------------------------------------------------
	-- Target gathering
	------------------------------------------------------------------

	-- Builds the list of hitboxes a single swing should touch.
	Combat.targetsFor = function(primary, settings)
		local list = {}
		if not primary or not primary.nape then
			return list
		end
		table.insert(list, primary)

		local limit = Util.clamp(settings.MultiHit or 1, 1, 10)
		if limit > 1 then
			local radius = settings.HitDistance or 1000
			for _, entry in ipairs(Ctx.Targets.neighbours(primary, radius, limit - 1)) do
				table.insert(list, entry)
			end
		end
		return list
	end

	------------------------------------------------------------------
	-- Slash
	------------------------------------------------------------------

	Combat.slash = function(primary, settings)
		local now = Util.now()
		if now - state.lastSlash < 0.12 then
			return false
		end
		state.lastSlash = now
		state.slashCount = state.slashCount + 1

		local damage, crit = damageArguments(settings)

		for _, entry in ipairs(Combat.targetsFor(primary, settings)) do
			if entry.nape and entry.nape.Parent then
				-- Immune titans are skipped, the server would ignore the
				-- damage anyway and the swing would be wasted.
				if not entry.isImmune then
					Ctx.Remotes.registerHitbox(entry.nape, damage, crit)
					-- A boss gets the extra hits that the config asks for.
					if entry.isBoss then
						local extra = Util.clamp(settings.BossDamage or 0, 0, 20)
						for _ = 1, extra do
							Ctx.Remotes.registerHitbox(entry.nape, damage, crit)
						end
					end
				end
			end
		end

		Ctx.Remotes.slash()
		Util.pressMouse()
		return true
	end

	------------------------------------------------------------------
	-- Spears
	------------------------------------------------------------------

	-- Fires the thunder spears. When infinite spears is on the ammo is
	-- topped up before every burst so the spear never runs dry.
	Combat.spears = function(primary, settings)
		local now = Util.now()
		if now - state.lastSpear < 0.4 then
			return false
		end
		state.lastSpear = now

		local damage, crit = damageArguments(settings)

		for _, entry in ipairs(Combat.targetsFor(primary, settings)) do
			if entry.nape and entry.nape.Parent and not entry.isImmune then
				Ctx.Remotes.fireSpears(entry.nape.Position)
				Ctx.Remotes.registerHitbox(entry.nape, damage, crit)
			end
		end

		if settings.InfiniteSpears == true then
			-- Keep the spear ammo topped up.
			Ctx.Remotes.refill()
		end
		return true
	end

	------------------------------------------------------------------
	-- Boss mechanics
	------------------------------------------------------------------

	-- The Armored Titan has plated limbs that have to be unlocked before
	-- the nape can be hit.
	Combat.registerBossLimbs = function(entry)
		if not entry or not entry.model then
			return
		end
		local limbs = { "Leg_L", "Leg_R", "Knee_L", "Knee_R", "Ankle_L", "Ankle_R", "Arm_L", "Arm_R" }
		for _, name in ipairs(limbs) do
			local part = entry.model:FindFirstChild(name, true)
			if part and part:IsA("BasePart") then
				Ctx.Remotes.registerHitbox(part, BASE_DAMAGE, BASE_CRIT)
			end
		end
	end

	------------------------------------------------------------------
	-- Main update
	------------------------------------------------------------------

	Combat.update = function()
		local settings = Ctx.Config.Get()
		if settings.AutoFarm ~= true then
			return
		end

		local primary = Ctx.state.target
		if not primary then
			return
		end
		if not Ctx.Targets.isAlive(primary) then
			Ctx.state.target = nil
			return
		end

		-- Spear burst first, it removes the cheap titans quickly.
		Combat.spears(primary, settings)

		if settings.AutoUseSkills == true then
			Combat.useSkills()
		end

		if primary.isBoss then
			Combat.registerBossLimbs(primary)
		end

		Combat.slash(primary, settings)
	end

	------------------------------------------------------------------
	-- Skills
	------------------------------------------------------------------

	-- Casts the equipped hotbar skill when it is off cooldown.
	Combat.useSkills = function()
		local player = Util.LocalPlayer
		local character = player and player.Character
		if not character then
			return false
		end
		local backpack = player:FindFirstChildOfClass("Backpack")
		if not backpack then
			return false
		end
		local cast = false
		for _, tool in ipairs(backpack:GetChildren()) do
			if tool:IsA("Tool") then
				local slot = tool:FindFirstChild("abilitySlot")
				local cooldown = tool:FindFirstChild("Cooldown") or tool:FindFirstChild("cooldown")
				local ready = true
				if cooldown and cooldown:IsA("NumberValue") then
					ready = cooldown.Value <= 0
				end
				if slot and ready then
					local event = tool:FindFirstChild("localEvent")
					if event and event:IsA("BindableEvent") then
						pcall(function()
							event:Fire()
						end)
						cast = true
					end
				end
			end
		end
		return cast
	end

	Combat.state = state

	return Combat
end
