--[[
	AOTR Suite :: test harness
	Runs the pure logic parts of the suite outside of Roblox.

	Usage:
		tools\luau\luau.exe tools\test.lua
]]

--------------------------------------------------------------------------------
-- Mock environment
--------------------------------------------------------------------------------

local failures = 0
local checks = 0

local function check(name, condition, detail)
	checks = checks + 1
	if condition then
		print(("  ok   %s"):format(name))
	else
		failures = failures + 1
		print(("  FAIL %s%s"):format(name, detail and (" -> " .. tostring(detail)) or ""))
	end
end

local function section(title)
	print("")
	print("== " .. title .. " ==")
end

-- Minimal JSON encoder and decoder, enough for the config files.
local function jsonEncode(value)
	local kind = type(value)
	if kind == "number" or kind == "boolean" then
		return tostring(value)
	elseif kind == "string" then
		-- The parentheses matter, gsub returns the string and the count.
		return (string.format("%q", value):gsub("\\\n", "\\n"))
	elseif kind == "table" then
		local isArray = #value > 0
		local parts = {}
		if isArray then
			for _, item in ipairs(value) do
				table.insert(parts, jsonEncode(item))
			end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local keys = {}
		for key in pairs(value) do
			table.insert(keys, key)
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
		for _, key in ipairs(keys) do
			table.insert(parts, string.format("%q:%s", tostring(key), jsonEncode(value[key])))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "null"
end

local function jsonDecode(text)
	-- Note: the "^" anchor of a Lua pattern is relative to the start of
	-- the whole string, not to the init position, so the parser walks the
	-- text with explicit indexes instead of patterns with an anchor.
	local function skipWhitespace(position)
		while position <= #text and text:sub(position, position):match("%s") do
			position = position + 1
		end
		return position
	end
	local function parseValue(position)
		local char = text:sub(position, position)
		if char == "{" then
			local result = {}
			position = position + 1
			while true do
				position = skipWhitespace(position)
				if text:sub(position, position) == "}" then
					return result, position + 1
				end
				local startPos, endPos, key = text:find('"([^"]*)"', position)
				if not key or startPos ~= position then
					error("bad json key at " .. position)
				end
				position = skipWhitespace(endPos + 1)
				if text:sub(position, position) ~= ":" then
					error("bad json at " .. position)
				end
				position = skipWhitespace(position + 1)
				local value
				value, position = parseValue(position)
				result[key] = value
				position = skipWhitespace(position)
				local separator = text:sub(position, position)
				if separator == "," then
					position = position + 1
				elseif separator ~= "}" then
					error("bad json separator at " .. position)
				end
			end
		elseif char == "[" then
			local result = {}
			position = position + 1
			while true do
				position = skipWhitespace(position)
				if text:sub(position, position) == "]" then
					return result, position + 1
				end
				local value
				value, position = parseValue(position)
				table.insert(result, value)
				position = skipWhitespace(position)
				local separator = text:sub(position, position)
				if separator == "," then
					position = position + 1
				elseif separator ~= "]" then
					error("bad json separator at " .. position)
				end
			end
		elseif char == '"' then
			local startPos, endPos, value = text:find('"([^"]*)"', position)
			if not value or startPos ~= position then
				error("bad json string at " .. position)
			end
			return value, endPos + 1
		elseif text:sub(position, position + 3) == "true" then
			return true, position + 4
		elseif text:sub(position, position + 4) == "false" then
			return false, position + 5
		elseif text:sub(position, position + 3) == "null" then
			return nil, position + 4
		else
			-- No anchor here, "^" is relative to the start of the whole
			-- string and not to the init position.
			local startPos, endPos = text:find("-?%d+%.?%d*[eE]?[-+]?%d*", position)
			if not startPos or startPos ~= position then
				error("bad json value at " .. position .. " char=[" .. text:sub(position, position + 8) .. "] len=" .. #text)
			end
			return tonumber(text:sub(startPos, endPos)), endPos + 1
		end
	end
	local position = skipWhitespace(1)
	local value
	value = parseValue(position)
	return value
end

-- Fake instances
local function newInstance(className, name)
	local instance = {
		ClassName = className,
		Name = name or className,
		Parent = nil,
		Children = {},
		Attributes = {},
	}
	instance.__typename = "Instance"
	function instance:IsA(class)
		return class == self.ClassName
	end
	function instance:FindFirstChild(childName, recursive)
		for _, child in ipairs(self.Children) do
			if child.Name == childName then
				return child
			end
			if recursive then
				local found = child:FindFirstChild(childName, true)
				if found then
					return found
				end
			end
		end
		return nil
	end
	function instance:FindFirstChildOfClass(class)
		for _, child in ipairs(self.Children) do
			if child.ClassName == class then
				return child
			end
		end
		return nil
	end
	function instance:GetChildren()
		return self.Children
	end
	function instance:GetDescendants()
		local result = {}
		for _, child in ipairs(self.Children) do
			table.insert(result, child)
			for _, nested in ipairs(child:GetDescendants()) do
				table.insert(result, nested)
			end
		end
		return result
	end
	function instance:GetAttribute(key)
		return self.Attributes[key]
	end
	function instance:SetAttribute(key, value)
		self.Attributes[key] = value
	end
	function instance:GetAttributes()
		return self.Attributes
	end
	function instance:AddChild(child)
		child.Parent = self
		table.insert(self.Children, child)
		return child
	end
	return instance
end

-- Fake filesystem
local files = {}
local folders = {}

local function normalize(path)
	return (path:gsub("\\", "/"))
end

local filesApi = {
	writefile = function(path, content)
		files[normalize(path)] = content
	end,
	readfile = function(path)
		local key = normalize(path)
		local content = files[key]
		if content == nil then
			error("file not found: " .. key)
		end
		return content
	end,
	isfile = function(path)
		return files[normalize(path)] ~= nil
	end,
	delfile = function(path)
		files[normalize(path)] = nil
	end,
	makefolder = function(path)
		folders[normalize(path)] = true
	end,
	isfolder = function(path)
		return folders[normalize(path)] == true
	end,
	listfiles = function(path)
		local prefix = normalize(path) .. "/"
		local result = {}
		for key in pairs(files) do
			if key:sub(1, #prefix) == prefix then
				table.insert(result, key)
			end
		end
		table.sort(result)
		return result
	end,
}

local genv = {}

local mockWorkspace = newInstance("Workspace", "Workspace")
local mockPlayer = newInstance("Player", "Tester")
mockPlayer.Name = "Tester"
mockPlayer.DisplayName = "Tester"
mockPlayer.Character = newInstance("Model", "Character")
local mockRoot = newInstance("BasePart", "HumanoidRootPart")
mockPlayer.Character:AddChild(mockRoot)

local mockPlayers = newInstance("Players", "Players")
mockPlayers.LocalPlayer = mockPlayer
mockPlayers.GetPropertyChangedSignal = function()
	return { Wait = function() end }
end

local mockHttp = newInstance("HttpService", "HttpService")
mockHttp.JSONEncode = function(_, value)
	return jsonEncode(value)
end
mockHttp.JSONDecode = function(_, text)
	return jsonDecode(text)
end

local mockRun = newInstance("RunService", "RunService")
mockRun.Heartbeat = { Connect = function() return { Disconnect = function() end } end }
mockRun.RenderStepped = { Connect = function() return { Disconnect = function() end } end }
mockRun.Stepped = { Connect = function() return { Disconnect = function() end } end }

local mockVim = newInstance("VirtualInputManager", "VirtualInputManager")
mockVim.SendMouseButtonEvent = function() end
mockVim.SendKeyEvent = function() end

local services = {
	Players = mockPlayers,
	Workspace = mockWorkspace,
	HttpService = mockHttp,
	RunService = mockRun,
	VirtualInputManager = mockVim,
	TweenService = newInstance("TweenService", "TweenService"),
	UserInputService = newInstance("UserInputService", "UserInputService"),
	ReplicatedStorage = newInstance("ReplicatedStorage", "ReplicatedStorage"),
}

local mockGame = {
	GetService = function(_, name)
		return services[name] or newInstance(name, name)
	end,
	HttpGet = function()
		return ""
	end,
}

-- Globals
getgenv = function()
	return genv
end
writefile = filesApi.writefile
readfile = filesApi.readfile
isfile = filesApi.isfile
delfile = filesApi.delfile
makefolder = filesApi.makefolder
isfolder = filesApi.isfolder
listfiles = filesApi.listfiles
game = mockGame
workspace = mockWorkspace
task = {
	wait = function() end,
	spawn = function(fn)
		fn()
	end,
	delay = function(_, fn)
		fn()
	end,
	cancel = function() end,
}
warn = function(...) end
-- Roblox exposes typeof, the mock implements it the same way.
typeof = function(value)
	if type(value) == "table" then
		local tag = rawget(value, "__typename")
		if tag then
			return tag
		end
	end
	return type(value)
end

--------------------------------------------------------------------------------
-- Module loading
--------------------------------------------------------------------------------
-- The standalone Luau CLI has no io library, so the modules are pulled in
-- with require. The environment of the returned factory is switched to the
-- test environment so the mocks are visible inside the module.

local function loadModule(relativePath)
	local factory = require((relativePath:gsub("%.lua$", "")))
	setfenv(factory, getfenv(0))
	return factory
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

section("Util")
local ctx = { state = {} }
ctx.Util = loadModule("../src/Util.lua")(ctx)
local Util = ctx.Util

check("formatNumber 1500", Util.formatNumber(1500) == "1.5K", Util.formatNumber(1500))
check("formatNumber 2500000", Util.formatNumber(2500000) == "2.50M", Util.formatNumber(2500000))
check("formatDuration 95", Util.formatDuration(95) == "01:35", Util.formatDuration(95))
check("formatDuration 3725", Util.formatDuration(3725) == "01:02:05", Util.formatDuration(3725))
check("sanitizeName strips", Util.sanitizeName("my farm/config!") == "my farmconfig", Util.sanitizeName("my farm/config!"))
check("sanitizeName empty", Util.sanitizeName("") == "default")
check("clamp high", Util.clamp(50, 1, 10) == 10)
check("clamp low", Util.clamp(-5, 1, 10) == 1)

local merged = Util.deepMerge({ a = 1, nested = { x = 1, y = 2 } }, { nested = { y = 9 } })
check("deepMerge keeps siblings", merged.nested.x == 1 and merged.nested.y == 9)
check("deepMerge keeps base", merged.a == 1)

section("Config")
local Config = loadModule("../src/Config.lua")(ctx)
ctx.Config = Config

genv.TekkitConfig = { AutoFarm = true, HoverHeight = 999, Extra = { A = 1 } }
Config.AutoLoad()
check("auto load merges TekkitConfig", Config.Get().AutoFarm == true)
check("auto load keeps Tekkit values", Config.Get().HoverHeight == 999)
check("auto load keeps defaults", Config.Get().AutoFarm == true and Config.Get().TargetPriority == "Closest")
check("external table is merged, not replaced", type(Config.Get().Extra) == "table")

Config.Set("HoverHeight", 300)
check("Set writes a dotted path", Config.Get().HoverHeight == 300)
Config.Set("Farm.NotThere", 5)
check("Set creates missing tables", Config.Get().Farm.NotThere == 5)

Config.New("farm one")
Config.Set("HoverHeight", 123)
check("save succeeds", Config.Save() == true)
check("file exists on disk", filesApi.isfile("AOTRSuite/configs/farm one.json") == true)

Config.Set("HoverHeight", 456)
check("load restores the value", Config.loadProfile("farm one") == true and Config.Get().HoverHeight == 123)
check("active profile is written", filesApi.readfile("AOTRSuite/active.txt") == "farm one")

-- Duplicated files that only differ in case or spacing are collapsed.
filesApi.writefile("AOTRSuite/configs/FarmOne.json", "{}")
filesApi.writefile("AOTRSuite/configs/second.json", "{}")
local profiles = Config.listProfiles()
local names = {}
for _, profile in ipairs(profiles) do
	names[profile.name] = true
end
local count = 0
for _ in pairs(names) do
	count = count + 1
end
check("duplicate profiles are collapsed", count == 2, "count=" .. count)

-- Saving removes the case variant duplicate.
Config.Set("HoverHeight", 321)
Config.Save("farm one")
check("duplicate file removed on save", filesApi.isfile("AOTRSuite/configs/FarmOne.json") == false)
check("the other profile survives", filesApi.isfile("AOTRSuite/configs/second.json") == true)

-- A concurrent load must not corrupt the state.
Config.Set("HoverHeight", 1)
Config.loadProfile("farm one")
local first = Config.Get().HoverHeight
Config.loadProfile("farm one")
check("repeated loads stay consistent", Config.Get().HoverHeight == first and first == 321, tostring(Config.Get().HoverHeight))

check("safety timer minimum is 30", (function()
	local Safety = loadModule("../src/Safety.lua")({ Util = Util, Config = Config, GameUI = {}, Targets = {} })
	Config.Set("SafetyTime", 5)
	local ok = Safety.timerAmount() == 30
	Config.Set("SafetyTime", 120)
	ok = ok and Safety.timerAmount() == 120
	return ok
end)())

section("Targets")
local Targets = loadModule("../src/Targets.lua")(ctx)
ctx.Targets = Targets

local function makeTitan(name, distance, options)
	options = options or {}
	local model = newInstance("Model", name)
	local hitboxes = newInstance("Folder", "Hitboxes")
	local hit = newInstance("Folder", "Hit")
	local nape = newInstance("BasePart", "Nape")
	hit:AddChild(nape)
	hitboxes:AddChild(hit)
	model:AddChild(hitboxes)
	local humanoid = newInstance("Humanoid", "Humanoid")
	humanoid.Health = options.hp or 100
	model:AddChild(humanoid)
	if options.immune then
		model:SetAttribute("Immune", true)
	end
	if options.protecting then
		model:SetAttribute("ProtectingBoats", true)
	end
	-- The titan has to live in the world, otherwise it counts as removed.
	model.Parent = mockWorkspace
	return {
		model = model,
		nape = nape,
		humanoid = humanoid,
		dist = distance,
		isBoss = options.boss or false,
		isCrawler = false,
		isAbnormal = false,
		isArmored = options.armored or false,
		isImmune = options.immune or false,
		isProtectingBoats = options.protecting or false,
	}
end

local list = {
	makeTitan("Normal", 100),
	makeTitan("Boss", 500, { boss = true }),
	makeTitan("Armored", 50, { armored = true, protecting = true }),
	makeTitan("Immune", 20, { immune = true, boss = true }),
}

local sorted = Targets.sort({ table.unpack(list) }, "Closest")
check("sort by distance puts the closest first", sorted[1].model.Name == "Immune", sorted[1].model.Name)
check("sort by distance keeps the order", sorted[2].model.Name == "Armored" and sorted[3].model.Name == "Normal", sorted[3].model.Name)

local picked = Targets.pick({ table.unpack(list) }, "Closest")
check("immune titan is never picked", picked ~= nil and picked.model.Name ~= "Immune", picked and picked.model.Name)
check("armored titan protecting the boats is skipped", picked ~= nil and picked.model.Name ~= "Armored", picked and picked.model.Name)
check("a valid titan is picked", picked ~= nil and picked.model.Name == "Normal", picked and picked.model.Name)

local pickedBoss = Targets.pick({ table.unpack(list) }, "Bosses First")
check("boss priority skips the immune boss", pickedBoss and pickedBoss.model.Name == "Boss", pickedBoss and pickedBoss.model.Name)

section("Stats")
local Stats = loadModule("../src/Stats.lua")(ctx)
ctx.Stats = Stats
local leaderstats = newInstance("Folder", "leaderstats")
local pumpkins = newInstance("IntValue", "Pumpkins")
pumpkins.Value = 4200
local gems = newInstance("IntValue", "Gems")
gems.Value = 15
leaderstats:AddChild(pumpkins)
leaderstats:AddChild(gems)
mockPlayer:AddChild(leaderstats)

check("reads Pumpkins", Stats.readCurrency("Pumpkins") == 4200, tostring(Stats.readCurrency("Pumpkins")))
check("reads Gems", Stats.readCurrency("Gems") == 15)
local snapshot = Stats.snapshot()
check("snapshot carries Pumpkins", snapshot.Pumpkins == 4200)

section("Remotes")
local Remotes = loadModule("../src/Remotes.lua")(ctx)
ctx.Remotes = Remotes
local postRemote = newInstance("RemoteEvent", "POST")
postRemote.FireServer = function() end
local remotesFolder = newInstance("Folder", "Remotes")
remotesFolder:AddChild(postRemote)
services.ReplicatedStorage:AddChild(remotesFolder)

local resolvedPost = Remotes.resolve(true)
check("resolves the POST remote", resolvedPost == postRemote)
check("post does not error", Remotes.post("Attacks", "M1") == true)
check("refill does not error", pcall(Remotes.refill) == true)

--------------------------------------------------------------------------------
-- Loader
--------------------------------------------------------------------------------

section("Loader")
local Loader = loadModule("../src/Loader")

local lines = {}
local function quiet(...)
	for index = 1, select("#", ...) do
		table.insert(lines, tostring((select(index, ...))))
	end
end

-- A stand in for the real script, it has to look like one because the
-- loader rejects anything that is not the script.
local function fakeSource(flag)
	return "-- AOTR Suite\n-- " .. string.rep("x", 120) .. "\n" .. flag .. " = true\n"
end

-- The loader fetches over http first.
mockGame.HttpGet = function(_, url)
	if url == "https://example.test/aotr.lua" then
		return fakeSource("loadedFromUrl")
	end
	error("404")
end
local urlResult = Loader({ urls = { "https://example.test/aotr.lua" }, file = "missing.lua", log = quiet })
check("loader runs the source it fetched", urlResult.loaded == true and loadedFromUrl == true, tostring(urlResult.reason))
check("loader reports the origin", urlResult.source ~= nil)

-- Then it falls back to the local file.
loadedFromUrl = nil
filesApi.writefile("AOTR.lua", fakeSource("loadedFromFile"))
local fileResult = Loader({ urls = { "https://example.test/missing.lua" }, file = "AOTR.lua", log = quiet })
check("loader falls back to the local file", fileResult.loaded == true and loadedFromFile == true, tostring(fileResult.reason))

-- Without any source it gives up instead of throwing.
local emptyResult = Loader({ urls = {}, file = "does-not-exist.lua", log = quiet })
check("loader reports a missing source", emptyResult.loaded == false and emptyResult.reason == "no source")

-- A page that is not the script is rejected instead of being compiled.
filesApi.writefile("AOTR.lua", "<html><body>404 not found</body></html>")
local htmlResult = Loader({ urls = {}, file = "AOTR.lua", log = quiet })
check("loader rejects a page that is not the script", htmlResult.loaded == false and htmlResult.reason == "no source")

-- When game:HttpGet is patched the executor http client is used instead.
local requestedUrl = nil
request = function(options)
	requestedUrl = options and options.Url
	return { Body = fakeSource("loadedFromRequest"), StatusCode = 200 }
end
loadedFromRequest = nil
local requestResult = Loader({ urls = { "https://example.test/patched.lua" }, file = "missing.lua", log = quiet })
check("loader falls back to the executor http client", requestResult.loaded == true and loadedFromRequest == true, tostring(requestResult.reason))
check("the executor http client got the url", requestedUrl == "https://example.test/patched.lua", tostring(requestedUrl))
request = nil

-- A broken source is reported and does not crash the loader.
filesApi.writefile("AOTR.lua", "-- AOTR Suite\n" .. string.rep("x", 120) .. "\nthis is not lua ===")
local brokenResult = Loader({ urls = {}, file = "AOTR.lua", log = quiet })
check("loader survives a broken source", brokenResult.loaded == false, tostring(brokenResult.reason))

-- The double execution guard.
genv.AOTRSuite = { Running = true }
local guardResult = Loader({ urls = {}, file = "AOTR.lua", log = quiet })
check("loader refuses to run twice", guardResult.loaded == false and guardResult.reason == "already running")
genv.AOTRSuite = nil

--------------------------------------------------------------------------------
-- Diagnostics
--------------------------------------------------------------------------------

section("Diagnostics")
local Diagnostics = loadModule("../src/Diagnostics")({ Util = ctx.Util })
ctx.Diagnostics = Diagnostics

Diagnostics.set("executor", "Xeno")
Diagnostics.set("gameId", 4658598196)
Diagnostics.set("postRemote", true)
Diagnostics.error("something went wrong")
local report = Diagnostics.report()
check("report names the executor", report:find("Xeno", 1, true) ~= nil)
check("report names the game id", report:find("4658598196", 1, true) ~= nil)
check("report shows the remote state", report:find("POST remote: found", 1, true) ~= nil)
check("report lists the errors", report:find("something went wrong", 1, true) ~= nil)
check("errors are counted", #Diagnostics.state.errors == 1)

--------------------------------------------------------------------------------
-- The wiring of main.lua
--------------------------------------------------------------------------------

section("Wiring")
-- main.lua builds every module and puts it into the context. A module
-- that is referenced but never built is a factory function instead of a
-- table, which only fails at runtime inside the game.
local MODULES = {
	"Util",
	"Config",
	"Remotes",
	"GameUI",
	"Targets",
	"Stats",
	"Safety",
	"Webhook",
	"Features/Farm",
	"Features/Combat",
	"Features/Reload",
	"Features/Claim",
	"Features/Boosts",
	"Features/AutoStart",
	"Features/Waves",
	"Features/ShadowBan",
	"FallbackUI",
	"Diagnostics",
	"Hub",
}

local registry = {}
for _, name in ipairs(MODULES) do
	registry[name] = loadModule("../src/" .. name)
end

local wiringCtx = { state = {} }
wiringCtx.Util = registry.Util(wiringCtx)
wiringCtx.Rayfield = {}
for _, name in ipairs(MODULES) do
	if name ~= "Util" then
		wiringCtx[name] = registry[name](wiringCtx)
	end
end

for _, name in ipairs(MODULES) do
	local value = wiringCtx[name]
	check(name .. " is a table, not a factory", type(value) == "table", type(value))
end

check("the context holds the built utilities", type(wiringCtx.Util.deepCopy) == "function")
check("the context holds the built config", type(wiringCtx.Config.Get) == "function")
check("the context holds the built remotes", type(wiringCtx.Remotes.post) == "function")
check("the context holds the built interface", type(wiringCtx.Hub.build) == "function")
check("the context holds the built diagnostics", type(wiringCtx.Diagnostics.report) == "function")

-- The utilities have to work when they are reached through the context.
local merged = wiringCtx.Util.deepMerge({ a = 1 }, { b = 2 })
check("the context utilities merge tables", merged.a == 1 and merged.b == 2)

--------------------------------------------------------------------------------
-- Result
--------------------------------------------------------------------------------

print("")
if failures > 0 then
	print(("%d of %d checks failed."):format(failures, checks))
	error("test run failed", 0)
end
print(("all %d checks passed."):format(checks))




