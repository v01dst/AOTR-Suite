--[[
	AOTR Suite :: loader
	========================================================================

	الصق هذا الملف في الـ executor ونفّذه.

	يبحث عن السكربت بالترتيب:
		1. من أول رابط يعمل في قائمة urls
		2. من ملف AOTR.lua الموجود في مجلد الـ executor (workspace)

	Usage:
		loadstring(readfile("AOTR.lua"))()   -- when the file sits next to it
]]

local __AOTRLoader = (function()
--[[
	AOTR Suite :: Loader
	Loads the bundled script from a URL or from a local file.

	dist\loader.lua is generated from this module, so the loader stays
	testable and the shipped file stays a single pasteable chunk.
]]

return function(options)
	options = options or {}

	local GAME_ID = options.gameId or 4658598196
	local URLS = options.urls or {}
	local LOCAL_FILE = options.file or "AOTR.lua"
	local log = options.log or print

	local function report(...)
		local parts = {}
		for index = 1, select("#", ...) do
			parts[#parts + 1] = tostring((select(index, ...)))
		end
		log("[AOTR Loader] " .. table.concat(parts, " "))
	end

	local function fromUrl(url)
		if type(url) ~= "string" or url == "" then
			return nil
		end
		local ok, source = pcall(function()
			return game:HttpGet(url)
		end)
		if ok and type(source) == "string" and #source > 0 then
			return source
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
	-- Single instance guard
	------------------------------------------------------------------
	local genv = (getgenv and getgenv()) or _G
	if genv.AOTRSuite and genv.AOTRSuite.Running then
		report("the suite is already running, nothing to do")
		return { loaded = false, reason = "already running" }
	end

	if game.GameId ~= GAME_ID then
		report("warning: this script is built for Attack on Titan: Revolution")
		report("expected GameId " .. tostring(GAME_ID) .. ", got " .. tostring(game.GameId))
	end

	------------------------------------------------------------------
	-- Find the source
	------------------------------------------------------------------
	local source = nil
	local origin = nil

	for _, url in ipairs(URLS) do
		source = fromUrl(url)
		if source then
			origin = url
			break
		end
	end

	if not source then
		source = fromFile(LOCAL_FILE)
		if source then
			origin = "local file: " .. LOCAL_FILE
		end
	end

	if not source then
		report("no source found.")
		report("put the URL of your hosted AOTR.lua into the url list,")
		report("or place AOTR.lua in the executor folder as " .. LOCAL_FILE .. ".")
		return { loaded = false, reason = "no source" }
	end

	report("source: " .. tostring(origin) .. " (" .. tostring(#source) .. " bytes)")

	------------------------------------------------------------------
	-- Run
	------------------------------------------------------------------
	local chunk, compileError = loadstring(source, "@AOTR")
	if not chunk then
		report("compile failed: " .. tostring(compileError))
		return { loaded = false, reason = "compile error" }
	end

	local ok, runtimeError = pcall(chunk)
	if not ok then
		report("runtime error: " .. tostring(runtimeError))
		return { loaded = false, reason = "runtime error" }
	end

	report("done")
	return { loaded = true, source = source }
end

end)()

__AOTRLoader({
	urls = {
		-- "https://raw.githubusercontent.com/USER/REPO/main/AOTR.lua",
	},
	file = "AOTR.lua",
})
