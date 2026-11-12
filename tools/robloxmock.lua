--[[
	AOTR Suite :: Roblox mock
	A small but complete enough mock of the Roblox api, so the real bundle
	can be executed outside of the game.

	With this the test harness runs dist\AOTR.mod.lua exactly the way the
	executor runs it, which is the only way to catch the errors that only
	show up inside Roblox.
]]

return function()
	local mock = {}

	------------------------------------------------------------------
	-- Data types
	------------------------------------------------------------------

	local UDim = {}
	UDim.__index = UDim
	function UDim.new(scale, offset)
		return setmetatable({ Scale = scale, Offset = offset }, UDim)
	end

	local UDim2 = {}
	UDim2.__index = UDim2
	function UDim2.new(xScale, xOffset, yScale, yOffset)
		return setmetatable({
			X = UDim.new(xScale, xOffset),
			Y = UDim.new(yScale, yOffset),
		}, UDim2)
	end
	function UDim2.fromOffset(x, y)
		return UDim2.new(0, x, 0, y)
	end
	function UDim2.fromScale(x, y)
		return UDim2.new(x, 0, y, 0)
	end

	local Vector2 = {}
	Vector2.__index = Vector2
	function Vector2.new(x, y)
		return setmetatable({ X = x or 0, Y = y or 0 }, Vector2)
	end

	local Vector3 = {}
	Vector3.__index = Vector3
	function Vector3.new(x, y, z)
		return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3)
	end
	Vector3.zero = Vector3.new(0, 0, 0)

	local CFrame = {}
	CFrame.__index = CFrame
	function CFrame.new(x, y, z)
		if type(x) == "table" then
			return setmetatable({ Position = x }, CFrame)
		end
		return setmetatable({ Position = Vector3.new(x, y, z) }, CFrame)
	end
	function CFrame.getPivot()
		return CFrame.new(0, 0, 0)
	end
	function CFrame:Lerp(other, alpha)
		return other
	end
	function CFrame.__mul(_, other)
		return other
	end

	local Color3 = {}
	Color3.__index = Color3
	function Color3.new(r, g, b)
		return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3)
	end
	function Color3.fromRGB(r, g, b)
		return Color3.new(r / 255, g / 255, b / 255)
	end

	------------------------------------------------------------------
	-- Enum
	------------------------------------------------------------------

	local Enum = {
		TextXAlignment = { Left = 1, Center = 2, Right = 3 },
		TextYAlignment = { Top = 1, Center = 2, Bottom = 3 },
		TextTruncate = { None = 0, AtEnd = 1, Split = 2 },
		SortOrder = { LayoutOrder = 1, Name = 2 },
		AutomaticSize = { None = 0, X = 1, Y = 2, XY = 3 },
		UserInputType = { MouseButton1 = 1, MouseMovement = 2, Keyboard = 3 },
		ZIndexBehavior = { Global = 0, Sibling = 1 },
		FillDirection = { Horizontal = 1, Vertical = 2 },
	}

	------------------------------------------------------------------
	-- Instances
	------------------------------------------------------------------

	local HIERARCHY = {
		GuiObject = { "Frame", "TextLabel", "TextButton", "ImageLabel", "ImageButton", "TextBox", "ScrollingFrame", "ViewportFrame" },
		Frame = { "ScrollingFrame" },
		LayerCollector = { "ScreenGui", "SurfaceGui" },
		UIComponent = { "UICorner", "UIStroke", "UIPadding", "UIListLayout", "UIGridLayout", "UIScale", "UIDragDetector" },
	}

	local function classParents(className)
		local parents = {}
		for parent, children in pairs(HIERARCHY) do
			for _, child in ipairs(children) do
				if child == className then
					table.insert(parents, parent)
				end
			end
		end
		return parents
	end

	local Instance = {}
	local instanceMethods = {}

	local function newSignal()
		local signal = { connections = {} }
		function signal:Connect(callback)
			table.insert(self.connections, callback)
			return { Disconnect = function() end }
		end
		function signal:Once(callback)
			return self:Connect(callback)
		end
		function signal:Fire(...)
			for _, callback in ipairs(self.connections) do
				pcall(callback, ...)
			end
		end
		return signal
	end

	local function newInstance(className, name)
		local instance = {
			ClassName = className,
			Name = name or className,
			Parent = nil,
			Attributes = {},
			Visible = true,
			Text = "",
			TextSize = 14,
			Size = UDim2.new(0, 0, 0, 0),
			Position = UDim2.new(0, 0, 0, 0),
			AnchorPoint = Vector2.new(0, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			TextColor3 = Color3.new(1, 1, 1),
			AbsolutePosition = Vector2.new(0, 0),
			AbsoluteSize = Vector2.new(100, 30),
			LayoutOrder = 0,
			Enabled = true,
			Active = true,
			Selected = false,
			Selectable = true,
			ZIndex = 1,
			LayoutOrder = 0,
			Image = "",
			ImageLabel = nil,
			PlaceholderText = "",
			PlaceholderColor3 = Color3.new(0.5, 0.5, 0.5),
			ClearTextOnFocus = true,
			DisplayOrder = 0,
			ResetOnSpawn = false,
			IgnoreGuiInset = false,
			AutomaticSize = Enum.AutomaticSize.None,
			CanvasSize = UDim2.new(0, 0, 0, 0),
			ScrollBarThickness = 0,
			ScrollBarImageColor3 = Color3.new(1, 1, 1),
			CornerRadius = UDim.new(0, 0),
			Thickness = 1,
			Transparency = 0,
			PaddingTop = UDim.new(0, 0),
			PaddingBottom = UDim.new(0, 0),
			PaddingLeft = UDim.new(0, 0),
			PaddingRight = UDim.new(0, 0),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Health = 100,
			Value = 0,
			Offset = Vector2.new(0, 0),
			Position = Vector2.new(0, 0),
		}
		instance.Children = {}
		instance.MouseButton1Click = newSignal()
		instance.FocusLost = newSignal()
		instance.Changed = newSignal()
		instance.Destroying = newSignal()
		instance.AncestryChanged = newSignal()
		instance.GetPropertyChangedSignal = function(_, name)
			return newSignal()
		end

		local meta = {
			__index = function(self, key)
				local method = instanceMethods[key]
				if method then
					return method
				end
				if key == "Parent" then
					return rawget(self, "_parent")
				end
				return rawget(self, key)
			end,
			-- Setting the parent adds the instance to the parent, that is
			-- how Roblox behaves and the code relies on it.
			__newindex = function(self, key, value)
				if key == "Parent" then
					local previous = rawget(self, "_parent")
					if previous == value then
						return
					end
					if previous then
						for index, item in ipairs(previous.Children) do
							if item == self then
								table.remove(previous.Children, index)
								break
							end
						end
					end
					rawset(self, "_parent", value)
					if value then
						table.insert(value.Children, self)
					end
					return
				end
				rawset(self, key, value)
			end,
			__type = function()
				return "Instance"
			end,
		}
		setmetatable(instance, meta)

		instance.__typename = "Instance"

		return instance
	end
	instanceMethods.IsA = function(self, class)
		if class == self.ClassName then
			return true
		end
		for _, parent in ipairs(classParents(self.ClassName)) do
			if parent == class then
				return true
			end
		end
		return false
	end
	instanceMethods.AddChild = function(self, child)
		-- The parent assignment keeps the children list in sync.
		child.Parent = self
		return child
	end
	instanceMethods.RemoveChild = function(self, child)
		child.Parent = nil
		return child
	end
	instanceMethods.GetChildren = function(self)
		return self.Children
	end
	instanceMethods.GetDescendants = function(self)
		local result = {}
		local seen = {}
		local function walk(node, depth)
			if depth > 40 or seen[node] then
				return
			end
			seen[node] = true
			for _, child in ipairs(node.Children) do
				table.insert(result, child)
				walk(child, depth + 1)
			end
		end
		walk(self, 0)
		return result
	end
	instanceMethods.FindFirstChild = function(self, name, recursive)
		for _, child in ipairs(self.Children) do
			if child.Name == name then
				return child
			end
			if recursive then
				local found = child:FindFirstChild(name, true)
				if found then
					return found
				end
			end
		end
		return nil
	end
	instanceMethods.FindFirstChildOfClass = function(self, class)
		for _, child in ipairs(self.Children) do
			if child.ClassName == class then
				return child
			end
		end
		return nil
	end
	instanceMethods.FindFirstChildWhichIsA = function(self, class, recursive)
		for _, child in ipairs(self.Children) do
			if child:IsA(class) then
				return child
			end
			if recursive then
				local found = child:FindFirstChildWhichIsA(class, true)
				if found then
					return found
				end
			end
		end
		return nil
	end
	instanceMethods.FindFirstAncestorOfClass = function(self, class)
		local parent = self.Parent
		while parent do
			if parent:IsA(class) then
				return parent
			end
			parent = parent.Parent
		end
		return nil
	end
	instanceMethods.GetAttribute = function(self, name)
		return self.Attributes[name]
	end
	instanceMethods.SetAttribute = function(self, name, value)
		self.Attributes[name] = value
	end
	instanceMethods.GetAttributes = function(self)
		return self.Attributes
	end
	instanceMethods.Destroy = function(self)
		if self.Parent then
			self.Parent:RemoveChild(self)
		end
	end
	instanceMethods.ClearAllChildren = function(self)
		self.Children = {}
	end
	instanceMethods.Clone = function(self)
		local copy = newInstance(self.ClassName)
		copy.Name = self.Name
		for key, value in pairs(self) do
			if type(value) ~= "table" or key == "Children" or key == "Attributes" then
				copy[key] = value
			end
		end
		copy.Children = {}
		return copy
	end
	instanceMethods.GetPivot = function(self)
		return CFrame.new(self.Position)
	end
	instanceMethods.WaitForChild = function(self, name, timeout)
		return self:FindFirstChild(name, true)
	end
	instanceMethods.PivotTo = function(self, cframe)
		self.Position = cframe
	end

	Instance.new = function(className, parent)
		return newInstance(className, parent)
	end

	------------------------------------------------------------------
	-- Services
	------------------------------------------------------------------

	local services = {}

	local function service(name)
		if services[name] then
			return services[name]
		end
		local instance = newInstance(name)
		services[name] = instance
		return instance
	end

	local players = service("Players")
	local localPlayer = newInstance("Player")
	localPlayer.Name = "Tester"
	localPlayer.DisplayName = "Tester"
	localPlayer.Character = newInstance("Model")
	localPlayer.Character:AddChild(newInstance("BasePart", "HumanoidRootPart"))
	localPlayer.Idled = newSignal()
	localPlayer.CharacterAdded = newSignal()
	players.LocalPlayer = localPlayer
	players.GetPlayerFromCharacter = function(_, character)
		if character == localPlayer.Character then
			return localPlayer
		end
		return nil
	end
	players.GetPlayers = function()
		return { localPlayer }
	end

	local coreGui = service("CoreGui")
	local starterGui = service("StarterGui")
	starterGui.SetCore = function() end

	local httpService = service("HttpService")
	local runService = service("RunService")
	runService.Heartbeat = newSignal()
	runService.RenderStepped = newSignal()
	runService.Stepped = newSignal()

	local tweenService = service("TweenService")
	tweenService.Create = function(_, _, _)
		return { Play = function() end, Cancel = function() end }
	end

	local userInput = service("UserInputService")
	userInput.InputBegan = newSignal()
	userInput.InputChanged = newSignal()
	userInput.InputEnded = newSignal()
	userInput.GetMouseLocation = function()
		return Vector2.new(0, 0)
	end

	local vim = service("VirtualInputManager")
	vim.SendMouseButtonEvent = function() end
	vim.SendKeyEvent = function() end

	------------------------------------------------------------------
	-- Globals
	------------------------------------------------------------------

	mock.game = {
		GameId = 4658598196,
		PlaceId = 14916516914,
		JobId = "mock",
		GetService = function(_, name)
			return service(name)
		end,
		FindFirstChild = function(_, name)
			return coreGui:FindFirstChild(name)
		end,
		-- A lot of executors block this, the interface has to survive it.
		GetObjects = function()
			return {}
		end,
		HttpGet = function()
			return ""
		end,
	}

	mock.Instance = Instance
	mock.Enum = Enum
	mock.UDim = UDim
	mock.UDim2 = UDim2
	mock.Vector2 = Vector2
	mock.Vector3 = Vector3
	mock.CFrame = CFrame
	mock.Color3 = Color3
	mock.Workspace = service("Workspace")
	mock.CoreGui = coreGui
	mock.StarterGui = starterGui
	mock.ReplicatedStorage = service("ReplicatedStorage")
	mock.services = services
	mock.newSignal = newSignal

	------------------------------------------------------------------
	-- Task
	------------------------------------------------------------------
	-- The spawned functions are queued instead of being run right away,
	-- so the test can decide when they run. A wait stops the loops after
	-- a while, that is enough to catch an error in the first iterations.

	mock.spawned = {}
	mock.waits = 0

	mock.task = {
		wait = function()
			mock.waits = mock.waits + 1
			if mock.waits > 40 then
				error("__mock_stop__", 0)
			end
		end,
		spawn = function(callback, ...)
			local arguments = { ... }
			table.insert(mock.spawned, function()
				callback(table.unpack(arguments))
			end)
		end,
		delay = function(_, callback, ...)
			local arguments = { ... }
			table.insert(mock.spawned, function()
				callback(table.unpack(arguments))
			end)
		end,
		cancel = function() end,
	}

	-- Runs the queued functions once, the endless loops stop on their own.
	mock.runSpawned = function()
		local problems = {}
		for _, callback in ipairs(mock.spawned) do
			local ok, err = pcall(callback)
			if not ok and tostring(err) ~= "__mock_stop__" then
				table.insert(problems, tostring(err))
			end
		end
		return problems
	end

	return mock
end
