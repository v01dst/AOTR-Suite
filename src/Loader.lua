--[[
	AOTR Suite :: Loader
	Loads the bundled script from a URL or from a local file.

	The loader draws its own small window on the screen, because some
	executors swallow print output and patch the notification api. The
	window lists every attempt so a failed download is visible instead of
	silent.
]]

return function(options)
	options = options or {}

	local GAME_ID = options.gameId or 4658598196
	local URLS = options.urls or {}
	local LOCAL_FILE = options.file or "AOTR.lua"
	local log = options.log or print
	local MARKER = options.marker or "AOTR Suite"

	------------------------------------------------------------------
	-- Output
	------------------------------------------------------------------

	local status = "starting"
	local details = {}

	local function report(...)
		local parts = {}
		for index = 1, select("#", ...) do
			parts[#parts + 1] = tostring((select(index, ...)))
		end
		log("[AOTR Loader] " .. table.concat(parts, " "))
	end

	------------------------------------------------------------------
	-- On screen window
	------------------------------------------------------------------

	local gui = nil
	local statusLabel = nil
	local detailsLabel = nil

	local function paint()
		if not statusLabel then
			return
		end
		pcall(function()
			statusLabel.Text = status
			detailsLabel.Text = table.concat(details, "\n")
		end)
	end

	local function note(line)
		table.insert(details, line)
		paint()
	end

	local function buildGui()
		if gui then
			return
		end
		local ok, host = pcall(function()
			return (gethui and gethui()) or game:GetService("CoreGui")
		end)
		if not ok or not host then
			host = game:GetService("CoreGui")
		end
		-- A ScreenGui cannot hold another ScreenGui.
		pcall(function()
			if host:IsA("ScreenGui") then
				host = host.Parent or game:GetService("CoreGui")
			end
		end)

		local created = pcall(function()
			gui = Instance.new("ScreenGui")
			gui.Name = "AOTRLoaderUI"
			gui.ResetOnSpawn = false
			gui.DisplayOrder = 9999
			gui.IgnoreGuiInset = false
			gui.Parent = host

			local frame = Instance.new("Frame")
			frame.Size = UDim2.fromOffset(430, 190)
			frame.Position = UDim2.fromScale(0.5, 0.5)
			frame.AnchorPoint = Vector2.new(0.5, 0.5)
			frame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
			frame.BorderSizePixel = 0
			frame.Parent = gui
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 8)
			corner.Parent = frame
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(52, 52, 62)
			stroke.Thickness = 1
			stroke.Parent = frame

			local title = Instance.new("TextLabel")
			title.BackgroundTransparency = 1
			title.Text = "AOTR Loader"
			title.TextColor3 = Color3.fromRGB(235, 235, 240)
			title.TextSize = 15
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.Size = UDim2.new(1, -24, 0, 24)
			title.Position = UDim2.fromOffset(12, 8)
			title.Parent = frame

			statusLabel = Instance.new("TextLabel")
			statusLabel.BackgroundTransparency = 1
			statusLabel.Text = "starting"
			statusLabel.TextColor3 = Color3.fromRGB(120, 170, 255)
			statusLabel.TextSize = 13
			statusLabel.TextXAlignment = Enum.TextXAlignment.Left
			statusLabel.Size = UDim2.new(1, -24, 0, 20)
			statusLabel.Position = UDim2.fromOffset(12, 34)
			statusLabel.Parent = frame

			detailsLabel = Instance.new("TextLabel")
			detailsLabel.BackgroundTransparency = 1
			detailsLabel.Text = ""
			detailsLabel.TextColor3 = Color3.fromRGB(150, 150, 160)
			detailsLabel.TextSize = 11
			detailsLabel.TextXAlignment = Enum.TextXAlignment.Left
			detailsLabel.TextYAlignment = Enum.TextYAlignment.Top
			detailsLabel.TextWrapped = true
			detailsLabel.Size = UDim2.new(1, -24, 1, -62)
			detailsLabel.Position = UDim2.fromOffset(12, 58)
			detailsLabel.Parent = frame
		end)
		if not created then
			gui = nil
			statusLabel = nil
		end
	end

	local function setStatus(text)
		status = text
		paint()
	end

	------------------------------------------------------------------
	-- Executor detection
	------------------------------------------------------------------

	local function detectExecutor()
		local names = {}
		local function push(name)
			table.insert(names, name)
		end
		pcall(function()
			if syn then
				push("Synapse")
			end
		end)
		pcall(function()
			if fluxus then
				push("Fluxus")
			end
		end)
		pcall(function()
			if krnl then
				push("Krnl")
			end
		end)
		pcall(function()
			if delta then
				push("Delta")
			end
		end)
		pcall(function()
			if getexecutorname then
				local ok, name = pcall(getexecutorname)
				if ok and type(name) == "string" then
					push(name)
				end
			end
		end)
		pcall(function()
			if identifier then
				local ok, name = pcall(identifier)
				if ok and type(name) == "string" then
					push(name)
				end
			end
		end)
		if #names == 0 then
			return "unknown"
		end
		return table.concat(names, ", ")
	end

	------------------------------------------------------------------
	-- Download attempts
	------------------------------------------------------------------

	-- A source that is not the script is useless, the marker is checked
	-- so a html error page is not compiled.
	local function looksValid(source)
		if type(source) ~= "string" or #source < 100 then
			return false
		end
		return string.find(source, MARKER, 1, true) ~= nil
	end

	local function tryGameHttpGet(url)
		local ok, result = pcall(function()
			return game:HttpGet(url)
		end)
		if ok and type(result) == "string" and #result > 0 then
			return result, "game:HttpGet"
		end
		local ok2, result2 = pcall(function()
			return game.HttpGet(game, url)
		end)
		if ok2 and type(result2) == "string" and #result2 > 0 then
			return result2, "game.HttpGet"
		end
		return nil, "game:HttpGet"
	end

	-- Every known name of the executor http client.
	local function requestClients()
		local clients = {}
		local function push(name, fn)
			if type(fn) == "function" then
				table.insert(clients, { name = name, fn = fn })
			end
		end
		pcall(function()
			push("syn.request", syn and syn.request)
		end)
		pcall(function()
			push("fluxus.request", fluxus and fluxus.request)
		end)
		pcall(function()
			push("http.request", http and http.request)
		end)
		pcall(function()
			push("krnl.request", krnl and krnl.request)
		end)
		pcall(function()
			push("delta.request", delta and delta.request)
		end)
		pcall(function()
			push("http_request", http_request)
		end)
		pcall(function()
			push("request", request)
		end)
		pcall(function()
			push("httpRequest", httpRequest)
		end)
		return clients
	end

	local function tryRequest(client, url)
		local ok, response = pcall(client.fn, {
			Url = url,
			Method = "GET",
		})
		if not ok or type(response) ~= "table" then
			return nil
		end
		local body = response.Body or response.body or response.Text or response.text
		if type(body) == "string" and #body > 0 then
			return body
		end
		return nil
	end

	local function fromFile(path)
		if type(readfile) ~= "function" then
			return nil
		end
		local ok, source = pcall(readfile, path)
		if ok and type(source) == "string" and #source > 0 then
			return source
		end
		return nil
	end

	------------------------------------------------------------------
	-- Run
	------------------------------------------------------------------

	buildGui()
	setStatus("looking for the script")
	note("executor: " .. tostring(options.executor or detectExecutor()))

	local genv = (getgenv and getgenv()) or _G
	if genv.AOTRSuite and genv.AOTRSuite.Running then
		setStatus("already running")
		note("the suite is already running")
		report("the suite is already running, nothing to do")
		return { loaded = false, reason = "already running" }
	end

	if game.GameId ~= GAME_ID then
		note("warning: expected GameId " .. tostring(GAME_ID) .. ", got " .. tostring(game.GameId))
	end

	local source = nil
	local origin = nil

	for _, url in ipairs(URLS) do
		setStatus("downloading")
		local body, how = tryGameHttpGet(url)
		if body and looksValid(body) then
			source = body
			origin = url .. " (" .. how .. ")"
			break
		end
		note("failed: " .. tostring(how) .. " -> " .. tostring(body and ("unexpected content, " .. #body .. " bytes") or "no response"))

		for _, client in ipairs(requestClients()) do
			local result = tryRequest(client, url)
			if result and looksValid(result) then
				source = result
				origin = url .. " (" .. client.name .. ")"
				break
			end
			if result then
				note("failed: " .. client.name .. " -> unexpected content, " .. tostring(#result) .. " bytes")
			else
				note("failed: " .. client.name .. " -> no response")
			end
		end
		if source then
			break
		end
	end

	-- The local file is the fallback, it also works without a network.
	if not source then
		local file = fromFile(LOCAL_FILE)
		if file and looksValid(file) then
			source = file
			origin = "local file: " .. LOCAL_FILE
		elseif file then
			note("the local file is not the script, " .. tostring(#file) .. " bytes")
		else
			note("no local file: " .. LOCAL_FILE)
		end
	end

	if not source then
		setStatus("no source found")
		note("tried " .. tostring(#URLS) .. " url(s) and the local file")
		note("put AOTR.lua next to the loader, or fix the url")
		report("no source found")
		return { loaded = false, reason = "no source" }
	end

	setStatus("loaded " .. tostring(#source) .. " bytes")
	note("source: " .. tostring(origin))
	report("source: " .. tostring(origin) .. " (" .. tostring(#source) .. " bytes)")

	-- Cache the script so the next run works without a network.
	if type(writefile) == "function" and LOCAL_FILE ~= "" then
		pcall(function()
			writefile(LOCAL_FILE, source)
		end)
	end

	setStatus("starting the suite")
	local chunk, compileError = loadstring(source, "@AOTR")
	if not chunk then
		setStatus("compile failed")
		note("compile error: " .. tostring(compileError))
		report("compile failed: " .. tostring(compileError))
		return { loaded = false, reason = "compile error" }
	end

	local ok, runtimeError = pcall(chunk)
	if not ok then
		setStatus("runtime error")
		note("runtime error: " .. tostring(runtimeError))
		report("runtime error: " .. tostring(runtimeError))
		return { loaded = false, reason = "runtime error" }
	end

	setStatus("the suite is running")
	note("done")
	report("done")

	-- Hand the window over to the suite, it shows its own interface.
	task.spawn(function()
		task.wait(2)
		pcall(function()
			if gui then
				gui:Destroy()
			end
		end)
	end)

	return { loaded = true, source = source }
end
