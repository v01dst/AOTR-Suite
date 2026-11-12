--[[
	AOTR Suite :: Webhook
	Discord reporting.

	Two blocks are sent:
		Player Stats  - includes Pumpkins next to the other currencies
		Drops         - includes Pumpkins next to the other rewards

	"Time Taken" reports the real mission duration that the Safety module
	measured, not the wall clock time of the script.
]]

return function(Ctx)
	local Util = Ctx.Util
	local Webhook = {}

	local previousSnapshot = nil

	------------------------------------------------------------------
	-- Helpers
	------------------------------------------------------------------

	local function config()
		return Ctx.Config.Get()
	end

	Webhook.enabled = function()
		local settings = config()
		return settings.Webhook == true
		and type(settings.WebhookLink) == "string"
		and settings.WebhookLink:match("^https?://") ~= nil
	end

	------------------------------------------------------------------
	-- Drops
	------------------------------------------------------------------

	-- The drop list is built from two sources:
	--   1. the currency delta between the start and the end of a mission
	--   2. the text of the rewards screen
	local function currencyDrops()
		local drops = {}
		if not previousSnapshot then
			return drops
		end
		local current = Ctx.Stats.snapshot()
		for _, entry in ipairs(Ctx.Stats.CURRENCIES) do
			local before = previousSnapshot[entry.key]
			local after = current[entry.key]
			if type(before) == "number" and type(after) == "number" then
				local delta = after - before
				if delta > 0 then
					table.insert(drops, {
						name = entry.label,
						amount = delta,
						text = string.format("+%s %s", Util.formatNumber(delta), entry.label),
					})
				end
			end
		end
		return drops
	end

	local REWARD_SCRAP_PATTERN = "^[%+%-]?[%d%.]+%s+%a"

	-- Scrapes the rewards screen for item names that are not currencies.
	local function screenDrops()
		local drops = {}
		local rewards = Ctx.GameUI.rewards()
		if not rewards or not rewards.Visible then
			return drops
		end
		local entries = Ctx.GameUI.collectText(rewards, function(text)
			return text:match(REWARD_SCRAP_PATTERN) ~= nil
				and not text:match("^[%d%.]+%s+[Ss]econds?$")
		end)
		local seen = {}
		for _, entry in ipairs(entries) do
			local key = string.lower(entry.text)
			if not seen[key] then
				seen[key] = true
				table.insert(drops, {
					name = entry.text,
					amount = nil,
					text = entry.text,
				})
			end
		end
		return drops
	end

	Webhook.collectDrops = function()
		local drops = currencyDrops()
		for _, drop in ipairs(screenDrops()) do
			table.insert(drops, drop)
		end
		return drops
	end

	Webhook.markBaseline = function()
		previousSnapshot = Ctx.Stats.snapshot()
	end

	------------------------------------------------------------------
	-- Embed
	------------------------------------------------------------------

	local function statsFields(snapshot, duration)
		local settings = config()
		local fields = {}

		if settings.ShowUsername ~= false then
			table.insert(fields, {
				name = "Player",
				value = string.format("%s (%s)", snapshot.displayName, snapshot.username),
				inline = true,
			})
		end

		table.insert(fields, {
			name = "Time Taken",
			value = Util.formatDuration(duration),
			inline = true,
		})

		local currencies = {}
		for _, entry in ipairs(Ctx.Stats.CURRENCIES) do
			local value = snapshot[entry.key]
			if type(value) == "number" then
				table.insert(currencies, string.format("%s: %s", entry.label, Util.formatNumber(value)))
			end
		end
		if #currencies > 0 then
			table.insert(fields, {
				name = "Player Stats",
				value = table.concat(currencies, "\n"),
				inline = false,
			})
		end

		local session = snapshot.session
		table.insert(fields, {
			name = "Session",
			value = table.concat({
				string.format("Missions: %d", session.missions),
				string.format("Raids: %d", session.raids),
				string.format("Waves: %d", session.waves),
				string.format("Titans: %d", session.titansKilled),
				string.format("Reloads: %d", session.bladesReloaded),
			}, "\n"),
			inline = false,
		})

		return fields
	end

	local function dropFields(drops)
		local lines = {}
		for _, drop in ipairs(drops) do
			table.insert(lines, drop.text)
		end
		if #lines == 0 then
			return {}
		end
		return {
			{
				name = "Drops",
				value = table.concat(lines, "\n"),
				inline = false,
			},
		}
	end

	Webhook.buildPayload = function(title, duration, drops)
		local snapshot = Ctx.Stats.snapshot()
		local fields = statsFields(snapshot, duration)
		local extra = dropFields(drops or {})
		for _, field in ipairs(extra) do
			table.insert(fields, field)
		end
		return {
			embeds = {
				{
					title = title or "Attack on Titan: Revolution",
					color = 11141375,
					timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
					fields = fields,
					footer = { text = "AOTR Suite" },
				},
			},
		}
	end

	------------------------------------------------------------------
	-- Sending
	------------------------------------------------------------------

	Webhook.send = function(title, duration, drops)
		if not Webhook.enabled() then
			return false
		end
		local payload = Webhook.buildPayload(title, duration, drops)
		local body = Util.jsonEncode(payload)
		if not body then
			return false
		end
		local response = Util.httpRequest({
			Url = config().WebhookLink,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = body,
		})
		if not response then
			Util.warn("webhook request failed")
			return false
		end
		return true
	end

	-- Sends the end of mission report with the real mission duration.
	Webhook.reportMission = function(drops)
		local duration = Ctx.Safety.lastDuration()
		if duration <= 0 then
			duration = Ctx.Safety.elapsed()
		end
		return Webhook.send("Mission Report", duration, drops)
	end

	Webhook.test = function()
		return Webhook.send("Webhook Test", 0, {})
	end

	return Webhook
end
