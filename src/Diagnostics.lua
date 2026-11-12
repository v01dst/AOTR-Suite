--[[
	AOTR Suite :: Diagnostics
	Collects what happened during the boot so the user can see it.

	Some executors swallow print output, so the report is shown inside the
	interface, written to a log file and pushed to the screen as a toast.
]]

return function(Ctx)
	local Util = Ctx.Util
	local Diagnostics = {}

	Diagnostics.state = {
		source = nil,
		loader = nil,
		interface = nil,
		remotes = false,
		postRemote = false,
		getRemote = false,
		gameId = nil,
		placeId = nil,
		player = nil,
		executor = nil,
		startedAt = Util.now(),
		errors = {},
	}

	Diagnostics.set = function(key, value)
		Diagnostics.state[key] = value
		return value
	end

	Diagnostics.error = function(message)
		table.insert(Diagnostics.state.errors, tostring(message))
		Util.warn(message)
		return message
	end

	------------------------------------------------------------------
	-- Executor detection
	------------------------------------------------------------------

	Diagnostics.detectExecutor = function()
		local names = {}
		if syn then
			table.insert(names, "Synapse")
		end
		if fluxus then
			table.insert(names, "Fluxus")
		end
		if krnl then
			table.insert(names, "Krnl")
		end
		if delta then
			table.insert(names, "Delta")
		end
		if getexecutorname then
			local ok, name = pcall(getexecutorname)
			if ok and type(name) == "string" then
				table.insert(names, name)
			end
		end
		if identifier then
			local ok, name = pcall(identifier)
			if ok and type(name) == "string" then
				table.insert(names, name)
			end
		end
		return table.concat(names, ", ")
	end

	------------------------------------------------------------------
	-- Report
	------------------------------------------------------------------

	Diagnostics.report = function()
		local state = Diagnostics.state
		local lines = {}
		local function add(label, value)
			table.insert(lines, string.format("%s: %s", label, tostring(value)))
		end

		add("executor", state.executor ~= "" and state.executor or "unknown")
		add("game id", state.gameId or "?")
		add("place id", state.placeId or "?")
		add("player", state.player or "?")
		add("source", state.source or "?")
		add("interface", state.interface or "?")
		add("POST remote", state.postRemote and "found" or "missing")
		add("GET remote", state.getRemote and "found" or "missing")
		add("config profile", state.profile or "?")
		add("uptime", Util.formatDuration(Util.now() - state.startedAt))

		if #state.errors > 0 then
			table.insert(lines, "")
			table.insert(lines, "errors:")
			for _, message in ipairs(state.errors) do
				table.insert(lines, "- " .. message)
			end
		end

		return table.concat(lines, "\n")
	end

	------------------------------------------------------------------
	-- Output channels
	------------------------------------------------------------------

	-- The toast is the most visible channel, it shows up on the screen
	-- even when the console stays empty.
	Diagnostics.toast = function(title, content, duration)
		pcall(function()
			game:GetService("StarterGui"):SetCore("SendNotification", {
				Title = tostring(title),
				Text = tostring(content),
				Duration = duration or 6,
			})
		end)
	end

	-- Writes the report next to the executor files when it is possible.
	Diagnostics.writeLog = function()
		if type(writefile) ~= "function" then
			return false
		end
		local ok = pcall(function()
			writefile("AOTR_boot_log.txt", Diagnostics.report())
		end)
		return ok
	end

	-- Prints and shows the report in every channel at once.
	Diagnostics.publish = function(title, content)
		Util.log(title)
		Util.log(content)
		Diagnostics.toast(title, content, 8)
		Diagnostics.writeLog()
	end

	return Diagnostics
end
