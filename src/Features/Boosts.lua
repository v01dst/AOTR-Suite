--[[
	AOTR Suite :: Features / Boosts
	Boost purchase with a selectable currency.

	Supported currencies: Canes, Gems and Pumpkins.
	The currency is picked in the shop panel, the boosts are then bought one
	by one. A remote fallback is used for the parts of the shop that do not
	expose a button.
]]

return function(Ctx)
	local Util = Ctx.Util
	local Boosts = {}

	local state = {
		lastRun = 0,
		bought = 0,
		currency = nil,
	}

	local function config()
		return Ctx.Config.Get()
	end

	------------------------------------------------------------------
	-- Shop panel
	------------------------------------------------------------------

	local function openShop()
		local matches = Ctx.GameUI.findClickables(Ctx.GameUI.interface(), { "Shop", "Store", "Boosts" }, true)
		if #matches == 0 then
			return nil
		end
		Util.click(matches[1])
		task.wait(0.35)
		return Ctx.GameUI.interface()
	end

	------------------------------------------------------------------
	-- Currency
	------------------------------------------------------------------

	-- Selects the currency the boosts are paid with.
	Boosts.selectCurrency = function(root, currency)
		local options = Ctx.GameUI.findClickables(root, { currency }, true)
		for _, option in ipairs(options) do
			-- A currency entry is a button that either holds the currency
			-- name or sits next to it.
			Util.click(option)
			state.currency = currency
			task.wait(0.2)
			return true
		end
		return false
	end

	------------------------------------------------------------------
	-- Buying
	------------------------------------------------------------------

	-- Buys a single boost by name.
	Boosts.buy = function(root, boostName)
		local entries = Ctx.GameUI.findClickables(root, { boostName }, true)
		for _, entry in ipairs(entries) do
			-- The buy button usually sits inside the entry.
			local buy = entry:FindFirstChild("Buy", true)
			if not buy then
				buy = Ctx.GameUI.findClickables(entry, { "Buy", "Purchase" }, true)[1]
			end
			if buy and Util.isVisible(buy) then
				if Util.click(buy) then
					state.bought = state.bought + 1
					Ctx.Stats.session.boostsBought = Ctx.Stats.session.boostsBought + 1
					task.wait(0.25)
					return true
				end
			end
			-- Some layouts make the whole entry the button.
			if entry:IsA("TextButton") or entry:IsA("ImageButton") then
				if Util.click(entry) then
					state.bought = state.bought + 1
					Ctx.Stats.session.boostsBought = Ctx.Stats.session.boostsBought + 1
					task.wait(0.25)
					return true
				end
			end
		end
		return false
	end

	------------------------------------------------------------------
	-- Remote fallback
	------------------------------------------------------------------

	Boosts.remoteBuy = function(boostName, currency)
		Ctx.Remotes.postAny("buy_boost", {
			{ "Boosts", "Purchase", boostName, currency },
			{ "S_Equipment", "Boost", boostName, currency },
			{ "Shop", "Buy", boostName, currency },
		})
	end

	------------------------------------------------------------------
	-- Main update
	------------------------------------------------------------------

	Boosts.update = function()
		local settings = config()
		if settings.BuyBoosts ~= true then
			return
		end
		local now = Util.now()
		if now - state.lastRun < 5 then
			return
		end
		state.lastRun = now

		local currency = settings.ItemtoBuyWith or "Canes"
		local root = openShop()
		if not root then
			return
		end

		Boosts.selectCurrency(root, currency)

		local list = settings.Boosts
		if type(list) == "string" then
			list = { list }
		end
		if type(list) ~= "table" then
			return
		end
		for _, boost in ipairs(list) do
			if type(boost) == "string" and boost ~= "" then
				if not Boosts.buy(root, boost) then
					Boosts.remoteBuy(boost, currency)
				end
			end
		end
	end

	Boosts.state = state

	return Boosts
end
