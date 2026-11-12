--[[
	AOTR Suite :: FallbackUI
	A small built in interface that only uses Instance.new.

	Rayfield loads its window from a Roblox asset through
	game:GetObjects("rbxassetid://..."). A lot of mobile executors block
	that call, which is why the script showed nothing on them. This module
	implements the subset of the Rayfield API that the hub uses, so the
	same code works on every executor.

	Supported:
		Rayfield:CreateWindow(settings)
		Rayfield:Notify({Title, Content, Duration})
		window:CreateTab(name, icon)
		tab:CreateSection(name)
		tab:CreateToggle / CreateDropdown / CreateSlider / CreateInput
		tab:CreateButton / CreateParagraph
		element:Set(value) / dropdown:Refresh(options)
]]

return function(Ctx)
	local Util = Ctx.Util
	local Fallback = {}

	-- The colours are built through a helper so the module can also be
	-- loaded outside of Roblox, for example in the test harness.
	local function rgb(red, green, blue)
		if Color3 and Color3.fromRGB then
			return Color3.fromRGB(red, green, blue)
		end
		return { R = red / 255, G = green / 255, B = blue / 255 }
	end

	local THEME = {
		background = rgb(18, 18, 22),
		surface = rgb(28, 28, 34),
		surfaceAlt = rgb(36, 36, 44),
		accent = rgb(120, 170, 255),
		accentSoft = rgb(46, 66, 104),
		text = rgb(235, 235, 240),
		muted = rgb(150, 150, 160),
		border = rgb(52, 52, 62),
	}

	local function new(className, properties)
		local instance = Instance.new(className)
		for key, value in pairs(properties or {}) do
			instance[key] = value
		end
		return instance
	end

	local function corner(parent, radius)
		local c = new("UICorner", { CornerRadius = UDim.new(0, radius or 6) })
		c.Parent = parent
		return c
	end

	local function stroke(parent, color, thickness)
		local s = new("UIStroke", {
			Color = color or THEME.border,
			Thickness = thickness or 1,
			Transparency = 0.6,
		})
		s.Parent = parent
		return s
	end

	local function padding(parent, top, bottom, left, right)
		local p = new("UIPadding", {
			PaddingTop = UDim.new(0, top or 6),
			PaddingBottom = UDim.new(0, bottom or 6),
			PaddingLeft = UDim.new(0, left or 8),
			PaddingRight = UDim.new(0, right or 8),
		})
		p.Parent = parent
		return p
	end

	------------------------------------------------------------------
	-- Notify
	------------------------------------------------------------------

	local notifications = nil

	local function ensureNotifications()
		if notifications then
			return notifications
		end
		local gui = Util.getGuiHost()
		notifications = new("ScreenGui", {
			Name = "AOTRNotifications",
			ResetOnSpawn = false,
			DisplayOrder = 1000,
			IgnoreGuiInset = false,
		})
		notifications.Parent = gui
		return notifications
	end

	Fallback.Notify = function(_, data)
		data = data or {}
		local gui = ensureNotifications()
		local holder = new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 40),
			Position = UDim2.new(0, 0, 0, 60),
		})
		holder.Parent = gui

		local card = new("TextLabel", {
			BackgroundColor3 = THEME.surface,
			Text = tostring(data.Title or "") .. "\n" .. tostring(data.Content or ""),
			TextColor3 = THEME.text,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(0, 320, 0, 54),
			Position = UDim2.new(1, -330, 0, 4),
			TextWrapped = true,
		})
		card.Parent = holder
		corner(card, 6)
		stroke(card)

		task.spawn(function()
			task.wait((tonumber(data.Duration) or 4) * 1000 / 1000)
			task.wait(math.max(0, (tonumber(data.Duration) or 4) - 1))
			local tween = game:GetService("TweenService"):Create(
				card,
				TweenInfo.new(0.3),
				{ Position = UDim2.new(1, -300, 0, 4), TextTransparency = 1, BackgroundTransparency = 1 }
			)
			tween:Play()
			task.wait(0.35)
			holder:Destroy()
		end)
	end

	------------------------------------------------------------------
	-- Window
	------------------------------------------------------------------

	Fallback.CreateWindow = function(_, settings)
		settings = settings or {}

		local gui = Util.getGuiHost()
		local screen = new("ScreenGui", {
			Name = "AOTRSuiteUI",
			ResetOnSpawn = false,
			DisplayOrder = 999,
			IgnoreGuiInset = false,
		})
		screen.Parent = gui

		local main = new("Frame", {
			BackgroundColor3 = THEME.background,
			Size = UDim2.fromOffset(660, 430),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Active = true,
		})
		main.Parent = screen
		corner(main, 8)
		stroke(main, THEME.border, 1)

		-- Drag the window around.
		do
			local ok, detector = pcall(function()
				return new("UIDragDetector")
			end)
			if ok and detector then
				detector.Parent = main
			else
				main.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 then
						local dragging, startInput, startPos = true, input.Position, main.Position
						local connection
						connection = game:GetService("UserInputService").InputChanged:Connect(function(move)
							if dragging and move then
								local delta = move.Position - startInput.Position
								main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
							end
						end)
						game:GetService("UserInputService").InputEnded:Connect(function()
							dragging = false
							if connection then
								connection:Disconnect()
							end
						end)
					end
				end)
			end
		end

		-- Title bar
		local title = new("TextLabel", {
			BackgroundTransparency = 1,
			Text = tostring(settings.Name or "AOTR Suite"),
			TextColor3 = THEME.text,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -60, 0, 34),
			Position = UDim2.fromOffset(14, 4),
		})
		title.Parent = main

		local close = new("TextButton", {
			BackgroundColor3 = THEME.surfaceAlt,
			Text = "X",
			TextColor3 = THEME.muted,
			TextSize = 14,
			Size = UDim2.fromOffset(26, 22),
			Position = UDim2.new(1, -34, 0, 6),
		})
		close.Parent = main
		corner(close, 5)
		close.MouseButton1Click:Connect(function()
			screen:Destroy()
		end)

		-- Sidebar
		local sidebar = new("Frame", {
			BackgroundColor3 = THEME.surface,
			Size = UDim2.fromOffset(150, -38),
			Position = UDim2.fromOffset(0, 36),
			BorderSizePixel = 0,
		})
		sidebar.Parent = main
		corner(sidebar, 0)

		local sidebarList = new("UIListLayout", {
			Padding = UDim.new(0, 2),
			SortOrder = Enum.SortOrder.LayoutOrder,
		})
		sidebarList.Parent = sidebar
		padding(sidebar, 6, 6, 6, 6)

		-- Content area
		local content = new("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -150, 1, -36),
			Position = UDim2.fromOffset(150, 36),
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = THEME.accent,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
		})
		content.Parent = main
		local contentLayout = new("UIListLayout", {
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		})
		contentLayout.Parent = content
		padding(content, 8, 8, 10, 10)

		------------------------------------------------------------------
		-- Tab handling
		------------------------------------------------------------------
		local tabs = {}
		local activeTab = nil

		local function showTab(tab)
			if activeTab then
				activeTab.page.Visible = false
				activeTab.button.BackgroundColor3 = THEME.surface
				activeTab.button.TextColor3 = THEME.muted
			end
			activeTab = tab
			tab.page.Visible = true
			tab.button.BackgroundColor3 = THEME.accentSoft
			tab.button.TextColor3 = THEME.text
		end

		local window = {}

		window.Destroy = function()
			pcall(function()
				screen:Destroy()
			end)
		end

		window.CreateTab = function(_, name)
			local button = new("TextButton", {
				BackgroundColor3 = THEME.surface,
				Text = tostring(name),
				TextColor3 = THEME.muted,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, -4, 0, 30),
				AutoButtonColor = false,
			})
			button.Parent = sidebar
			corner(button, 5)

			local page = new("Frame", {
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = UDim2.new(1, -20, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Visible = false,
			})
			page.Parent = content
			local pageLayout = new("UIListLayout", {
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			})
			pageLayout.Parent = page

			local tab = { name = name, page = page, button = button }

			button.MouseButton1Click:Connect(function()
				showTab(tab)
			end)

			table.insert(tabs, tab)
			if not activeTab then
				showTab(tab)
			end
			return tab
		end

		------------------------------------------------------------------
		-- Controls
		------------------------------------------------------------------

		local function row(parent, height)
			local frame = new("Frame", {
				BackgroundColor3 = THEME.surface,
				Size = UDim2.new(1, -4, 0, height or 32),
			})
			frame.Parent = parent
			corner(frame, 6)
			return frame
		end

		local function label(parent, text, width)
			local textLabel = new("TextLabel", {
				BackgroundTransparency = 1,
				Text = tostring(text),
				TextColor3 = THEME.text,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Size = UDim2.new(1, -(width or 90), 1, 0),
				Position = UDim2.fromOffset(12, 0),
			})
			textLabel.Parent = parent
			return textLabel
		end

		-- The original tab creator is kept, makeTab extends it with the
		-- controls and the new creator below points at makeTab.
		local createTab = window.CreateTab

		-- Sections and controls are created through the tab object.
		local function makeTab(name)
			local tabObject = createTab(window, name)

			-- The rows keep the order they were created in, the section
			-- headers stay above the controls that belong to them.
			local layoutOrder = 0
			local function nextOrder()
				layoutOrder = layoutOrder + 1
				return layoutOrder
			end

			tabObject.CreateSection = function(_, sectionName)
				local sectionLabel = new("TextLabel", {
					BackgroundTransparency = 1,
					Text = tostring(sectionName),
					TextColor3 = THEME.accent,
					TextSize = 12,
					TextXAlignment = Enum.TextXAlignment.Left,
					Size = UDim2.new(1, -8, 0, 18),
				})
				sectionLabel.Parent = tabObject.page
				sectionLabel.LayoutOrder = nextOrder()
				return sectionLabel
			end

			tabObject.CreateToggle = function(_, toggleSettings)
				toggleSettings = toggleSettings or {}
				local frame = row(tabObject.page, 30)
				frame.LayoutOrder = nextOrder()

				local box = new("TextButton", {
					BackgroundColor3 = THEME.surfaceAlt,
					Text = "",
					Size = UDim2.fromOffset(20, 20),
					Position = UDim2.fromOffset(10, 5),
				})
				box.Parent = frame
				corner(box, 4)
				stroke(box)

				local text = label(frame, toggleSettings.Name or "", 44)
				text.Position = UDim2.fromOffset(38, 0)

				local state = { value = toggleSettings.CurrentValue == true }
				local function paint()
					box.BackgroundColor3 = state.value and THEME.accent or THEME.surfaceAlt
				end
				paint()

				local function setValue(newValue, silent)
					state.value = newValue == true
					paint()
					if not silent and toggleSettings.Callback then
						toggleSettings.Callback(state.value)
					end
				end

				box.MouseButton1Click:Connect(function()
					setValue(not state.value)
				end)
				text.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 then
						setValue(not state.value)
					end
				end)

				return {
					Set = function(_, newValue)
						setValue(newValue, true)
					end,
				}
			end

			tabObject.CreateDropdown = function(_, dropdownSettings)
				dropdownSettings = dropdownSettings or {}
				local frame = row(tabObject.page, 30)
				frame.LayoutOrder = nextOrder()

				local options = dropdownSettings.Options or {}
				local current = dropdownSettings.CurrentOption
				if type(current) == "table" then
					current = current[1]
				end
				current = current or options[1]

				local text = label(frame, dropdownSettings.Name or "", 150)
				local value = new("TextButton", {
					BackgroundColor3 = THEME.surfaceAlt,
					Text = tostring(current),
					TextColor3 = THEME.text,
					TextSize = 12,
					Size = UDim2.fromOffset(150, 20),
					Position = UDim2.new(1, -160, 0, 5),
				})
				value.Parent = frame
				corner(value, 4)
				stroke(value)

				local function select(option, silent)
					current = option
					value.Text = tostring(option)
					if not silent and dropdownSettings.Callback then
						dropdownSettings.Callback(option)
					end
				end

				value.MouseButton1Click:Connect(function()
					-- Cycle to the next option, the list is small.
					local index = 1
					for position, option in ipairs(options) do
						if option == current then
							index = position
							break
						end
					end
					local nextIndex = (index % #options) + 1
					select(options[nextIndex])
				end)

				return {
					Set = function(_, newOption)
						local option = newOption
						if type(option) == "table" then
							option = option[1]
						end
						select(option, true)
					end,
					Refresh = function(_, newOptions)
						options = newOptions or options
						if #options > 0 then
							select(options[1], true)
						end
					end,
				}
			end

			tabObject.CreateSlider = function(_, sliderSettings)
				sliderSettings = sliderSettings or {}
				local range = sliderSettings.Range or { 0, 100 }
				local increment = sliderSettings.Increment or 1
				local frame = row(tabObject.page, 30)
				frame.LayoutOrder = nextOrder()

				local text = label(frame, sliderSettings.Name or "", 120)
				local value = sliderSettings.CurrentValue or range[1]

				local valueLabel = new("TextLabel", {
					BackgroundTransparency = 1,
					Text = tostring(value) .. tostring(sliderSettings.Suffix or ""),
					TextColor3 = THEME.accent,
					TextSize = 12,
					Size = UDim2.fromOffset(70, 0),
					Position = UDim2.new(1, -190, 0, 0),
				})
				valueLabel.Parent = frame

				local function makeButton(textValue, xOffset)
					local button = new("TextButton", {
						BackgroundColor3 = THEME.surfaceAlt,
						Text = textValue,
						TextColor3 = THEME.text,
						TextSize = 13,
						Size = UDim2.fromOffset(24, 20),
						Position = UDim2.new(1, xOffset, 0, 5),
					})
					button.Parent = frame
					corner(button, 4)
					stroke(button)
					return button
				end

				local minus = makeButton("-", -100)
				local plus = makeButton("+", -30)

				local function setValue(newValue, silent)
					value = Util.clamp(newValue, range[1], range[2])
					valueLabel.Text = tostring(value) .. tostring(sliderSettings.Suffix or "")
					if not silent and sliderSettings.Callback then
						sliderSettings.Callback(value)
					end
				end

				minus.MouseButton1Click:Connect(function()
					setValue(value - increment)
				end)
				plus.MouseButton1Click:Connect(function()
					setValue(value + increment)
				end)

				return {
					Set = function(_, newValue)
						setValue(newValue, true)
					end,
				}
			end

			tabObject.CreateInput = function(_, inputSettings)
				inputSettings = inputSettings or {}
				local frame = row(tabObject.page, 30)
				frame.LayoutOrder = nextOrder()

				local text = label(frame, inputSettings.Name or "", 150)

				local box = new("TextBox", {
					BackgroundColor3 = THEME.surfaceAlt,
					Text = tostring(inputSettings.CurrentValue or ""),
					PlaceholderText = tostring(inputSettings.PlaceholderText or ""),
					PlaceholderColor3 = THEME.muted,
					TextColor3 = THEME.text,
					TextSize = 12,
					ClearTextOnFocus = false,
					Size = UDim2.fromOffset(150, 20),
					Position = UDim2.new(1, -160, 0, 5),
				})
				box.Parent = frame
				corner(box, 4)
				stroke(box)

				box.FocusLost:Connect(function()
					if inputSettings.Callback then
						inputSettings.Callback(box.Text)
					end
				end)

				return {
					Set = function(_, newText)
						box.Text = tostring(newText or "")
					end,
				}
			end

			tabObject.CreateButton = function(_, buttonSettings)
				buttonSettings = buttonSettings or {}
				local frame = new("TextButton", {
					BackgroundColor3 = THEME.accentSoft,
					Text = tostring(buttonSettings.Name or "Button"),
					TextColor3 = THEME.text,
					TextSize = 13,
					Size = UDim2.new(1, -8, 0, 28),
					AutoButtonColor = false,
				})
				frame.Parent = tabObject.page
				frame.LayoutOrder = nextOrder()
				corner(frame, 5)
				frame.MouseButton1Click:Connect(function()
					if buttonSettings.Callback then
						buttonSettings.Callback()
					end
				end)
				return frame
			end

			tabObject.CreateParagraph = function(_, paragraphSettings)
				paragraphSettings = paragraphSettings or {}
				local frame = new("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, -8, 0, 40),
					AutomaticSize = Enum.AutomaticSize.Y,
				})
				frame.Parent = tabObject.page
				frame.LayoutOrder = nextOrder()

				local title = new("TextLabel", {
					BackgroundTransparency = 1,
					Text = tostring(paragraphSettings.Name or ""),
					TextColor3 = THEME.text,
					TextSize = 12,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextWrapped = true,
					Size = UDim2.new(1, -8, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
				})
				title.Parent = frame

				local body = new("TextLabel", {
					BackgroundTransparency = 1,
					Text = tostring(paragraphSettings.Content or ""),
					TextColor3 = THEME.muted,
					TextSize = 11,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextWrapped = true,
					Size = UDim2.new(1, -8, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Position = UDim2.fromOffset(0, 16),
				})
				body.Parent = frame

				return {
					Set = function(_, newSettings)
						newSettings = newSettings or {}
						title.Text = tostring(newSettings.Title or title.Text)
						body.Text = tostring(newSettings.Content or body.Text)
					end,
				}
			end

			return tabObject
		end

		window.CreateTab = function(_, name)
			return makeTab(name)
		end

		return window
	end

	------------------------------------------------------------------
	-- Last resort
	------------------------------------------------------------------
	-- If even the built in interface cannot be created, at least the
	-- error is written on the screen.

	Fallback.Emergency = function(_, text)
		local ok, host = pcall(function()
			return (gethui and gethui()) or game:GetService("CoreGui")
		end)
		if not ok or not host then
			host = game:GetService("CoreGui")
		end
		pcall(function()
			if host:IsA("ScreenGui") then
				host = host.Parent or game:GetService("CoreGui")
			end
		end)
		pcall(function()
			local gui = new("ScreenGui", {
				Name = "AOTREmergency",
				ResetOnSpawn = false,
				DisplayOrder = 10000,
			})
			gui.Parent = host

			local label = new("TextLabel", {
				BackgroundColor3 = Color3.fromRGB(40, 20, 20),
				Text = tostring(text),
				TextColor3 = Color3.fromRGB(255, 180, 180),
				TextSize = 14,
				TextWrapped = true,
				Size = UDim2.new(0, 460, 0, 150),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
			})
			label.Parent = gui
			corner(label, 8)
		end)
	end

	return Fallback
end
