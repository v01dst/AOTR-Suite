--[[
	AOTR Suite :: Features / Farm
	Auto farm with the redesigned Blade and Hover methods plus the
	Teleport method.

	Methods
		Blade    - sits right behind the nape, the safe way to farm
		Hover    - flies above the titan at HoverHeight
		Teleport - warps straight onto the nape

	The chosen target is published on Ctx.state.target so the combat and
	reload modules can work on the same titan.
]]

return function(Ctx)
	local Util = Ctx.Util
	local Farm = {}

	local state = {
		target = nil,
		lastTargetId = nil,
		smoothed = nil,
		killCooldown = 0,
	}

	------------------------------------------------------------------
	-- Movement helpers
	------------------------------------------------------------------

	local function characterParts()
		local player = Util.LocalPlayer
		local character = player and player.Character
		if not character then
			return nil, nil, nil
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		return character, root, humanoid
	end

	-- Position the player wants to be in for the current method.
	local function desiredPosition(method, entry, settings)
		local nape = entry.nape
		if method == "Teleport" then
			return nape.CFrame * CFrame.new(0, 2, -(settings.BehindNapeDistance or 2))
		end
		if method == "Hover" then
			local height = settings.HoverHeight or 265
			return CFrame.new(nape.Position.X, nape.Position.Y + height, nape.Position.Z)
		end
		-- Blade, behind the nape on the neck axis.
		local distance = settings.BehindNapeDistance or 2
		return nape.CFrame * CFrame.new(0, 0, -distance)
	end

	------------------------------------------------------------------
	-- Target management
	------------------------------------------------------------------

	Farm.currentTarget = function()
		return state.target
	end

	Farm.clearTarget = function()
		if state.target and state.target.model then
			Ctx.Targets.markDead(state.target.model)
		end
		state.target = nil
		state.lastTargetId = nil
	end

	local function acquireTarget(settings)
		local list = Ctx.Targets.getTitans()
		local entry = Ctx.Targets.pick(list, settings.TargetPriority)
		if entry and state.lastTargetId == entry.model and not Ctx.Targets.isAlive(entry) then
			entry = nil
		end
		if entry then
			state.target = entry
			state.lastTargetId = entry.model
		end
		return entry
	end

	------------------------------------------------------------------
	-- Main update
	------------------------------------------------------------------

	Farm.update = function(deltaTime)
		local settings = Ctx.Config.Get()
		if settings.AutoFarm ~= true then
			if state.target then
				Farm.clearTarget()
			end
			return
		end

		local character, root, humanoid = characterParts()
		if not root or not humanoid or humanoid.Health <= 0 then
			return
		end

		local entry = state.target
		if not entry or not Ctx.Targets.isAlive(entry) then
			entry = acquireTarget(settings)
		end
		if not entry then
			return
		end

		local method = settings.FarmMethod or "Blade"
		local target = desiredPosition(method, entry, settings)

		if method == "Teleport" or settings.TeleportTitans == true then
			-- Instant warp, no interpolation.
			root.CFrame = target
		else
			-- Smooth flight towards the target position.
			local speed = settings.HoverSpeed or 3000
			local alpha = Util.clamp((speed / 60) * (deltaTime or 0.016) / math.max(1, (root.Position - target.Position).Magnitude), 0, 1)
			if alpha <= 0 then
				alpha = 1
			end
			root.CFrame = root.CFrame:Lerp(target, alpha)
		end

		if settings.DisableHovering ~= true then
			-- Keep the player in the air, this stops the game from
			-- dropping the character onto the titan.
			root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
		end

		Ctx.state.target = entry
	end

	------------------------------------------------------------------
	-- Nape extender
	------------------------------------------------------------------

	-- Grows the nape hitbox so the swings connect more reliably.
	Farm.extendNapes = function()
		local settings = Ctx.Config.Get()
		if settings.NapeExtend ~= true then
			return
		end
		for _, entry in ipairs(Ctx.Targets.getTitans()) do
			local nape = entry.nape
			if nape and nape.Parent then
				local weld = nape:FindFirstChild("Nape")
				if weld and weld:IsA("Weld") then
					weld.Destroy()
				end
				nape.CanCollide = false
				nape.Transparency = math.min(nape.Transparency, 0.85)
				local size = nape.Size
				if size.X < 12 or size.Y < 12 then
					nape.Size = Vector3.new(math.max(size.X, 12), math.max(size.Y, 12), math.max(size.Z, 12))
				end
			end
		end
	end

	Farm.state = state

	return Farm
end
