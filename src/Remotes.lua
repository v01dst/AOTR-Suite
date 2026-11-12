--[[
	AOTR Suite :: Remotes
	Thin wrapper around the Attack on Titan: Revolution server API.

	The game exposes a single action dispatcher:

		ReplicatedStorage.Assets.Remotes.POST   (RemoteEvent)
		ReplicatedStorage.Assets.Remotes.GET    (RemoteEvent / RemoteFunction)

	`POST:FireServer(<Category>, <Action>, ...)` performs the action.
	Categories observed in the live game:
		S_Equipment / Equipment / Character / Attacks / Hitboxes
	]]

return function(Ctx)
	local Util = Ctx.Util
	local Remotes = {}

	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local postRemote = nil
	local getRemote = nil
	local resolvedAt = 0

	------------------------------------------------------------------
	-- Resolution
	------------------------------------------------------------------

	local function findRemote(name)
		local candidates = {
			ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Remotes"),
			ReplicatedStorage:FindFirstChild("Remotes"),
		}
		for _, container in ipairs(candidates) do
			if container then
				local direct = container:FindFirstChild(name)
				if direct then
					return direct
				end
			end
		end
		-- Deep fallback: the game occasionally nests the remotes deeper.
		return Util.findDeep(ReplicatedStorage, function(node)
			return node.Name == name and (node:IsA("RemoteEvent") or node:IsA("RemoteFunction"))
		end, 6)
	end

	Remotes.resolve = function(force)
		if not force and postRemote and (Util.now() - resolvedAt) < 30 then
			return postRemote, getRemote
		end
		postRemote = findRemote("POST")
		getRemote = findRemote("GET")
		resolvedAt = Util.now()
		return postRemote, getRemote
	end

	Remotes.post = function(...)
		local remote = Remotes.resolve()
		if not remote then
			return false
		end
		local args = table.pack(...)
		return pcall(function()
			remote:FireServer(table.unpack(args, 1, args.n))
		end)
	end

	Remotes.invoke = function(...)
		local remote = Remotes.resolve()
		if not remote then
			return nil
		end
		local args = table.pack(...)
		if remote:IsA("RemoteFunction") then
			local ok, result = pcall(function()
				return remote:InvokeServer(table.unpack(args, 1, args.n))
			end)
			if ok then
				return result
			end
			return nil
		end
		Remotes.post(table.unpack(args, 1, args.n))
		return nil
	end

	------------------------------------------------------------------
	-- Action learning
	------------------------------------------------------------------
	-- The game occasionally renames a category. Instead of hard failing we
	-- remember which spelling worked the last time and try it first.

	local learned = {}

	Remotes.remember = function(feature, action)
		learned[feature] = action
	end

	Remotes.recall = function(feature)
		return learned[feature]
	end

	-- Fires the first candidate signature that does not error.
	-- `candidates` is a list of tables, each table being the argument list.
	Remotes.postAny = function(feature, candidates)
		local remembered = learned[feature]
		if remembered then
			for index, candidate in ipairs(candidates) do
				if candidate[1] == remembered[1] then
					table.remove(candidates, index)
					table.insert(candidates, 1, remembered)
					break
				end
			end
		end
		for _, candidate in ipairs(candidates) do
			local ok = Remotes.post(table.unpack(candidate))
			if ok then
				learned[feature] = candidate
				return true, candidate
			end
		end
		return false
	end

	------------------------------------------------------------------
	-- High level actions used across the suite
	------------------------------------------------------------------

	Remotes.refill = function()
		Remotes.post("S_Equipment", "Refill")
		Remotes.post("Equipment", "Refill")
		Remotes.post("Character", "Refill")
		Remotes.post("Attacks", "Refill")
	end

	-- Registers a hitbox for a server side damage check.
	-- `damage` and `critical` mirror the arguments the game expects.
	Remotes.registerHitbox = function(part, damage, critical)
		if not part or not part.Parent then
			return false
		end
		Remotes.post("Hitboxes", "Register", part, damage or 500, critical or 100)
		return true
	end

	Remotes.slash = function()
		Remotes.post("Attacks", "Slash", true)
		Remotes.post("Attacks", "Slash_Release")
		Remotes.post("Attacks", "M1")
	end

	Remotes.fireSpears = function(position)
		if not position then
			return false
		end
		Remotes.post("S_Equipment", "Spears", "Fire", position)
		Remotes.post("Attacks", "Spears", position)
		return true
	end

	Remotes.getReady = function()
		return getRemote
	end

	return Remotes
end
