--[[
	AOTR Suite :: Util
	Low level helpers shared by every module.

	Nothing in here knows about Attack on Titan: Revolution specifically.
	It only knows how to talk to Roblox, the executor, and the filesystem.
]]

return function(Ctx)
	local Util = {}

	local Players = game:GetService("Players")
	local HttpService = game:GetService("HttpService")
	local RunService = game:GetService("RunService")
	local VirtualInputManager = game:GetService("VirtualInputManager")

	------------------------------------------------------------------
	-- Executor capability detection
	------------------------------------------------------------------

	Util.requestFunc = (syn and syn.request)
		or (fluxus and fluxus.request)
		or (http and http.request)
		or (krnl and krnl.request)
		or (delta and delta.request)
		or http_request
		or request

	Util.hasFileIO = (type(writefile) == "function" and type(readfile) == "function")
	Util.hasMakeFolder = type(makefolder) == "function"
	Util.hasIsFile = type(isfile) == "function"
	Util.hasListFiles = type(listfiles) == "function"
	Util.hasDeleteFile = type(delfile) == "function"

	-- The host of a ScreenGui. Some executors return a ScreenGui from
	-- gethui, and a ScreenGui cannot parent another ScreenGui, so in that
	-- case the parent of that ScreenGui is used instead.
	Util.getGuiHost = function()
		local ok, host = pcall(function()
			return (gethui and gethui()) or game:GetService("CoreGui")
		end)
		if ok and host and typeof == nil then
			-- typeof is missing, the host is used as it is.
			return host
		end
		if ok and host then
			local isScreen = false
			pcall(function()
				isScreen = host:IsA("ScreenGui")
			end)
			if isScreen then
				return host.Parent or game:GetService("CoreGui")
			end
			return host
		end
		return game:GetService("CoreGui")
	end

	------------------------------------------------------------------
	-- Logging
	------------------------------------------------------------------

	local LOG_PREFIX = "[AOTR] "

	Util.log = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[#parts + 1] = tostring((select(i, ...)))
		end
		print(LOG_PREFIX .. table.concat(parts, " "))
	end

	Util.warn = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[#parts + 1] = tostring((select(i, ...)))
		end
		warn(LOG_PREFIX .. table.concat(parts, " "))
	end

	------------------------------------------------------------------
	-- Misc helpers
	------------------------------------------------------------------

	Util.clamp = function(value, low, high)
		if type(value) ~= "number" then
			return low
		end
		if value < low then
			return low
		end
		if value > high then
			return high
		end
		return value
	end

	-- pcall that returns (ok, result...) and never throws
	Util.try = function(fn, ...)
		if type(fn) ~= "function" then
			return false
		end
		local packed = table.pack(pcall(fn, ...))
		return table.unpack(packed, 1, packed.n)
	end

	-- pcall that swallows errors and returns the result (or nil)
	Util.safe = function(fn, ...)
		local ok, result = pcall(fn, ...)
		if ok then
			return result
		end
		return nil
	end

	Util.now = function()
		return os.clock()
	end

	Util.deepCopy = function(value)
		if type(value) ~= "table" then
			return value
		end
		local copy = {}
		for key, item in pairs(value) do
			copy[key] = Util.deepCopy(item)
		end
		return copy
	end

	-- Recursive merge: `override` wins, tables are merged key by key.
	Util.deepMerge = function(base, override)
		if type(override) ~= "table" then
			if override ~= nil then
				return override
			end
			return base
		end
		if type(base) ~= "table" then
			return Util.deepCopy(override)
		end
		local result = Util.deepCopy(base)
		for key, item in pairs(override) do
			if type(item) == "table" and type(result[key]) == "table" then
				result[key] = Util.deepMerge(result[key], item)
			else
				result[key] = Util.deepCopy(item)
			end
		end
		return result
	end

	Util.formatNumber = function(value)
		if type(value) ~= "number" then
			return tostring(value)
		end
		local absolute = math.abs(value)
		if absolute >= 1e12 then
			return string.format("%.2fT", value / 1e12)
		elseif absolute >= 1e9 then
			return string.format("%.2fB", value / 1e9)
		elseif absolute >= 1e6 then
			return string.format("%.2fM", value / 1e6)
		elseif absolute >= 1e3 then
			return string.format("%.1fK", value / 1e3)
		end
		return string.format("%d", value)
	end

	Util.formatDuration = function(seconds)
		if type(seconds) ~= "number" or seconds < 0 then
			return "00:00"
		end
		local total = math.floor(seconds)
		local hours = math.floor(total / 3600)
		local minutes = math.floor((total % 3600) / 60)
		local secs = total % 60
		if hours > 0 then
			return string.format("%02d:%02d:%02d", hours, minutes, secs)
		end
		return string.format("%02d:%02d", minutes, secs)
	end

	-- File-system safe profile name.
	Util.sanitizeName = function(name)
		name = tostring(name or "")
		name = name:gsub("[^%w%-_%. ]", "")
		name = name:gsub("^%s+", ""):gsub("%s+$", "")
		if #name == 0 then
			return "default"
		end
		if #name > 48 then
			name = name:sub(1, 48)
		end
		return name
	end

	------------------------------------------------------------------
	-- Instance traversal
	------------------------------------------------------------------

	Util.waitFor = function(parent, name, timeout)
		if not parent then
			return nil
		end
		local found = parent:FindFirstChild(name)
		if found then
			return found
		end
		if timeout == nil then
			return nil
		end
		local ok, result = pcall(function()
			return parent:WaitForChild(name, timeout)
		end)
		if ok then
			return result
		end
		return nil
	end

	-- Depth limited deep search for the first matching descendant.
	Util.findDeep = function(root, predicate, maxDepth)
		maxDepth = maxDepth or 8
		if not root then
			return nil
		end
		local queue = { { root, 0 } }
		while #queue > 0 do
			local entry = table.remove(queue, 1)
			local node, depth = entry[1], entry[2]
			if node and depth <= maxDepth then
				if predicate(node) then
					return node
				end
				for _, child in ipairs(node:GetChildren()) do
					table.insert(queue, { child, depth + 1 })
				end
			end
		end
		return nil
	end

	Util.findAllDeep = function(root, predicate, maxDepth)
		maxDepth = maxDepth or 8
		local results = {}
		if not root then
			return results
		end
		local queue = { { root, 0 } }
		while #queue > 0 do
			local entry = table.remove(queue, 1)
			local node, depth = entry[1], entry[2]
			if node and depth <= maxDepth then
				if predicate(node) then
					table.insert(results, node)
				end
				for _, child in ipairs(node:GetChildren()) do
					table.insert(queue, { child, depth + 1 })
				end
			end
		end
		return results
	end

	-- True when the instance and every GuiObject ancestor is visible.
	Util.isVisible = function(object)
		if not object or not object:IsA("GuiObject") then
			return false
		end
		local current = object
		while current and current:IsA("GuiObject") do
			if not current.Visible then
				return false
			end
			current = current.Parent
		end
		local screen = object:FindFirstAncestorOfClass("ScreenGui")
		if screen and not screen.Enabled then
			return false
		end
		return object.AbsoluteSize.X > 0 and object.AbsoluteSize.Y > 0
	end

	------------------------------------------------------------------
	-- Input simulation
	------------------------------------------------------------------

	-- VirtualInputManager clicks are offset because Roblox reports the
	-- viewport in a different space than the mouse. 58-65 works for the
	-- standard 16:9 and 16:10 Roblox window chrome.
	Util.CLICK_Y_OFFSET = 58

	Util.click = function(object, yOffset)
		if not object or not object:IsA("GuiObject") then
			return false
		end
		local x = object.AbsolutePosition.X + (object.AbsoluteSize.X / 2)
		local y = object.AbsolutePosition.Y + (object.AbsoluteSize.Y / 2) + (yOffset or Util.CLICK_Y_OFFSET)
		pcall(function()
			VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 1)
		end)
		task.wait(0.04)
		pcall(function()
			VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 1)
		end)
		return true
	end

	Util.pressKey = function(keyCode, holdTime)
		holdTime = holdTime or 0.05
		pcall(function()
			VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
		end)
		task.wait(holdTime)
		pcall(function()
			VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
		end)
	end

	-- Sends a left mouse click at the current mouse position. The game
	-- listens to the mouse for the blade swings, so the attack has to be
	-- simulated as well.
	Util.pressMouse = function()
		pcall(function()
			VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
		end)
		task.wait(0.01)
		pcall(function()
			VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
		end)
	end

	------------------------------------------------------------------
	-- HTTP
	------------------------------------------------------------------

	Util.httpRequest = function(options)
		if not Util.requestFunc then
			return nil
		end
		local ok, response = pcall(Util.requestFunc, options)
		if not ok or type(response) ~= "table" then
			return nil
		end
		return response
	end

	Util.jsonEncode = function(value)
		local ok, encoded = pcall(function()
			return HttpService:JSONEncode(value)
		end)
		if ok then
			return encoded
		end
		return nil
	end

	Util.jsonDecode = function(text)
		local ok, decoded = pcall(function()
			return HttpService:JSONDecode(text)
		end)
		if ok then
			return decoded
		end
		return nil
	end

	------------------------------------------------------------------
	-- Services exposed for convenience
	------------------------------------------------------------------

	Util.Players = Players
	Util.RunService = RunService
	Util.LocalPlayer = Players.LocalPlayer

	-- Re-acquire the local player after a respawn / rejoin.
	Util.refreshLocalPlayer = function()
		Util.LocalPlayer = Players.LocalPlayer
		return Util.LocalPlayer
	end

	-- Small helper: run a function on a cadence and never overlap calls.
	Util.createLooper = function(interval, fn)
		local running = false
		return function()
			if running then
				return
			end
			running = true
			task.spawn(function()
				while true do
					local ok, err = pcall(fn)
					if not ok then
						Util.warn("loop error:", err)
					end
					task.wait(interval)
				end
			end)
		end
	end

	return Util
end
