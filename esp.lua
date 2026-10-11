--[[
    UNIVERSAL MULTI-HACK HUB (NEON UI EDITION)
    Включает:
    - KILASIK's Multi-Target Fling
    - Procedural Fly & Infinite Jump 
    - Spider-Man Wall Climb 
    - Safe Trolling (Орбита, Шапка, Преследование)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

---------------------------------------------------------------------
-- НАСТРОЙКИ UI
---------------------------------------------------------------------
local CONFIG = {
	Title = "Universal Hub",
	Subtitle = "Скрипт-меню  •  v2.5",
	ToggleKey = Enum.KeyCode.RightShift,
	Width = 560,
	Height = 370,
	Transparency = 0.35,
}
 
local THEME = {
	Window = Color3.fromRGB(24, 24, 38), Panel = Color3.fromRGB(30, 30, 48),
	Element = Color3.fromRGB(44, 44, 68), Off = Color3.fromRGB(70, 70, 96),
	Text = Color3.fromRGB(242, 242, 255), SubText = Color3.fromRGB(155, 155, 185),
	Accent1 = Color3.fromRGB(155, 100, 255), Accent2 = Color3.fromRGB(70, 200, 255),
	Close = Color3.fromRGB(235, 75, 100), White = Color3.new(1, 1, 1),
    Green = Color3.fromRGB(70, 220, 130)
}
 
local FONT_BOLD, FONT_MEDIUM, FONT_REGULAR = Enum.Font.GothamBold, Enum.Font.GothamMedium, Enum.Font.Gotham

---------------------------------------------------------------------
-- ПЕРЕМЕННЫЕ МЕХАНИК
---------------------------------------------------------------------
-- Передвижение
local InfiniteJumpEnabled, WallClimbEnabled, isClimbing = false, false, false
local FlySpeed = 60
local flying = false
local flyAttachment, flyVelocity, flyAlign, flyConnection, flyJoints
local climbNormal, climbAttachment, climbVelocity, climbAlign, climbTrack
local climbTrackCache, climbCooldownUntil = {}, 0
local ClimbSpeedWalk = 24
local CLIMB_HOLD_DIST = 1.2
local CLIMB_ANIM_FALLBACK = {R15 = "rbxassetid://507765644", R6 = "rbxassetid://180436334"}

-- Fling
local SelectedTargets = {}
local PlayerCheckboxes = {}
local FlingActive = false
getgenv().OldPos = nil
getgenv().FPDH = workspace.FallenPartsDestroyHeight

-- Троллинг
local TrollTarget = nil
local TrollMode = "None"
local trollConnection

---------------------------------------------------------------------
-- БАЗОВЫЕ ФУНКЦИИ ПЕРСОНАЖА
---------------------------------------------------------------------
local function getCharacterParts()
	local char = player.Character
	if not char then return nil, nil end
	return char:FindFirstChildOfClass("Humanoid"), char:FindFirstChild("HumanoidRootPart")
end

local function getJoints(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		local function m(p, j) local pt = character:FindFirstChild(p) return pt and pt:FindFirstChild(j) end
		return { rig = "R15", RightArm = m("RightUpperArm", "RightShoulder"), LeftArm = m("LeftUpperArm", "LeftShoulder"), RightLeg = m("RightUpperLeg", "RightHip"), LeftLeg = m("LeftUpperLeg", "LeftHip"), RightElbow = m("RightLowerArm", "RightElbow"), LeftElbow = m("LeftLowerArm", "LeftElbow"), RightKnee = m("RightLowerLeg", "RightKnee"), LeftKnee = m("LeftLowerLeg", "LeftKnee"), Neck = m("Head", "Neck"), Waist = m("UpperTorso", "Waist"), Neutral = { m("RightHand", "RightWrist"), m("LeftHand", "LeftWrist"), m("RightFoot", "RightAnkle"), m("LeftFoot", "LeftAnkle"), m("LowerTorso", "Root") } }
	else
		local torso, root = character:FindFirstChild("Torso"), character:FindFirstChild("HumanoidRootPart")
		if not torso then return nil end
		return { rig = "R6", RightArm = torso:FindFirstChild("Right Shoulder"), LeftArm = torso:FindFirstChild("Left Shoulder"), RightLeg = torso:FindFirstChild("Right Hip"), LeftLeg = torso:FindFirstChild("Left Hip"), Neck = torso:FindFirstChild("Neck"), Neutral = { root and root:FindFirstChild("RootJoint") } }
	end
end

local function resetJoints(j)
	if not j then return end
	for key, motor in pairs(j) do
		if key == "Neutral" then
			for _, m in pairs(motor) do if m and m.Parent then m.Transform = CFrame.identity end end
		elseif typeof(motor) == "Instance" and motor.Parent then motor.Transform = CFrame.identity end
	end
end

---------------------------------------------------------------------
-- ПОМОЩНИКИ UI
---------------------------------------------------------------------
local function create(className, props)
	local instance = Instance.new(className)
	if instance:IsA("GuiObject") then instance.BorderSizePixel = 0 end
	local parent = props.Parent
	props.Parent = nil
	for key, value in pairs(props) do instance[key] = value end
	instance.Parent = parent return instance
end
 
local function tween(object, duration, goal, style, direction)
	local animation = TweenService:Create(object, TweenInfo.new(duration, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out), goal)
	animation:Play() return animation
end
 
local function corner(parent, pixels) return create("UICorner", { CornerRadius = UDim.new(0, pixels or 8), Parent = parent }) end
local function round(parent) return create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = parent }) end
local function stroke(parent, transparency, thickness, color) return create("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = color or THEME.White, Transparency = transparency or 0.9, Thickness = thickness or 1, Parent = parent }) end
 
local animatedGradients = {}
local function accent(parent, rotation, animated)
	local gradient = create("UIGradient", { Color = ColorSequence.new(THEME.Accent1, THEME.Accent2), Rotation = rotation or 0, Parent = parent })
	if animated then table.insert(animatedGradients, gradient) end
	return gradient
end
 
local function newLabel(props)
	props.BackgroundTransparency = 1 props.Font = props.Font or FONT_MEDIUM props.TextSize = props.TextSize or 14 props.TextColor3 = props.TextColor3 or THEME.Text props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return create("TextLabel", props)
end
 
local function isPress(input) return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch end
local function isMove(input) return input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch end

---------------------------------------------------------------------
-- СОЗДАНИЕ UI ОКНА
---------------------------------------------------------------------
if CoreGui:FindFirstChild("TransparentMenu") then CoreGui.TransparentMenu:Destroy() end
local gui = create("ScreenGui", { Name = "TransparentMenu", ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 50, Parent = CoreGui })
local holder = create("Frame", { Name = "Holder", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(CONFIG.Width, CONFIG.Height), BackgroundTransparency = 1, Parent = gui })
local fitScale = create("UIScale", { Parent = holder })
local window = create("Frame", { Name = "Window", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = holder })
local popScale = create("UIScale", { Scale = 0, Parent = window })

local glowLayers = {}
for index, layer in ipairs({ { 3, 0.78 }, { 8, 0.9 }, { 15, 0.96 } }) do
	local glow = create("Frame", { Name = "Glow" .. index, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 0, Parent = window })
	corner(glow, 14) accent(stroke(glow, layer[2], layer[1]), 45, true) table.insert(glowLayers, glow)
end
 
local main = create("Frame", { Name = "Main", Size = UDim2.fromScale(1, 1), BackgroundColor3 = THEME.Window, BackgroundTransparency = CONFIG.Transparency, ClipsDescendants = true, Active = true, ZIndex = 1, Parent = window })
corner(main, 14) accent(stroke(main, 0.15, 1.5), 45, true)
create("UIGradient", { Rotation = 90, Color = ColorSequence.new(THEME.White, Color3.fromRGB(150, 150, 175)), Transparency = NumberSequence.new(0, 0.3), Parent = main })

-- ВЕРХНЯЯ ПАНЕЛЬ
local topBar = create("Frame", { Name = "TopBar", Size = UDim2.new(1, 0, 0, 48), BackgroundTransparency = 1, Parent = main })
local logo = create("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), Size = UDim2.fromOffset(28, 28), BackgroundColor3 = THEME.White, Parent = topBar })
corner(logo, 8) accent(logo, 45)
create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(10, 10), Rotation = 45, BackgroundColor3 = THEME.White, Parent = logo })
newLabel({ Position = UDim2.fromOffset(52, 8), Size = UDim2.new(1, -140, 0, 18), Text = CONFIG.Title, Font = FONT_BOLD, TextSize = 16, Parent = topBar })
newLabel({ Position = UDim2.fromOffset(52, 26), Size = UDim2.new(1, -140, 0, 14), Text = CONFIG.Subtitle, Font = FONT_REGULAR, TextSize = 11, TextColor3 = THEME.SubText, Parent = topBar })

local function windowButton(symbol, offsetX, hoverColor)
	local button = create("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, offsetX, 0.5, 0), Size = UDim2.fromOffset(28, 28), BackgroundColor3 = THEME.Element, BackgroundTransparency = 0.5, AutoButtonColor = false, Text = symbol, Font = FONT_BOLD, TextSize = 18, TextColor3 = THEME.SubText, Parent = topBar })
	corner(button, 8)
	button.MouseEnter:Connect(function() tween(button, 0.2, { BackgroundColor3 = hoverColor, BackgroundTransparency = 0.15, TextColor3 = THEME.White }) end)
	button.MouseLeave:Connect(function() tween(button, 0.2, { BackgroundColor3 = THEME.Element, BackgroundTransparency = 0.5, TextColor3 = THEME.SubText }) end)
	return button
end
local closeButton = windowButton("×", -12, THEME.Close)
local minimizeButton = windowButton("–", -46, THEME.Accent1)

local divider = create("Frame", { Position = UDim2.fromOffset(0, 48), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = THEME.White, Parent = main })
create("UIGradient", { Color = ColorSequence.new(THEME.Accent1, THEME.Accent2), Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 1)}), Parent = divider })

-- БОКОВАЯ ПАНЕЛЬ И ПРОФИЛЬ
local sidebar = create("Frame", { Name = "Sidebar", Position = UDim2.fromOffset(10, 58), Size = UDim2.new(0, 150, 1, -68), BackgroundColor3 = THEME.Panel, BackgroundTransparency = 0.5, Parent = main })
corner(sidebar, 10) stroke(sidebar, 0.93)
local tabList = create("Frame", { Size = UDim2.new(1, 0, 1, -60), BackgroundTransparency = 1, Parent = sidebar })
create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tabList })
create("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = tabList })

local profile = create("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -8), Size = UDim2.new(1, -16, 0, 44), BackgroundColor3 = THEME.Element, BackgroundTransparency = 0.5, Parent = sidebar })
corner(profile, 8)
local avatar = create("ImageLabel", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 7, 0.5, 0), Size = UDim2.fromOffset(30, 30), BackgroundColor3 = THEME.Off, BackgroundTransparency = 0.3, Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=48&h=48"):format(player.UserId), Parent = profile })
round(avatar) accent(stroke(avatar, 0.3, 1.5), 45)
newLabel({ Position = UDim2.fromOffset(44, 7), Size = UDim2.new(1, -50, 0, 16), Text = player.DisplayName, Font = FONT_BOLD, TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd, Parent = profile })
newLabel({ Position = UDim2.fromOffset(44, 23), Size = UDim2.new(1, -50, 0, 14), Text = "@" .. player.Name, Font = FONT_REGULAR, TextSize = 11, TextColor3 = THEME.SubText, TextTruncate = Enum.TextTruncate.AtEnd, Parent = profile })

-- ВКЛАДКИ
local content = create("Frame", { Name = "Content", Position = UDim2.fromOffset(170, 58), Size = UDim2.new(1, -180, 1, -68), BackgroundTransparency = 1, Parent = main })
local pageTitle = newLabel({ Size = UDim2.new(1, 0, 0, 24), Text = "", Font = FONT_BOLD, TextSize = 18, Parent = content })
local pageHolder = create("Frame", { Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 1, -32), BackgroundTransparency = 1, ClipsDescendants = true, Parent = content })
 
local tabs, selectedTab, layoutOrder = {}, nil, 0
local function nextOrder() layoutOrder = layoutOrder + 1 return layoutOrder end
 
local function selectTab(tab)
	if selectedTab == tab then return end
	selectedTab = tab
	for _, other in ipairs(tabs) do
		local active = other == tab
		other.Page.Visible = active
		tween(other.Button, 0.25, { BackgroundTransparency = active and 0.45 or 1 })
		tween(other.Indicator, 0.3, { Size = UDim2.fromOffset(3, active and 18 or 0) })
		tween(other.Label, 0.25, { TextColor3 = active and THEME.Text or THEME.SubText, Position = UDim2.fromOffset(active and 18 or 14, 0) })
	end
	pageTitle.Text = tab.Name
	tab.Page.Position = UDim2.fromOffset(0, 14)
	tween(tab.Page, 0.35, { Position = UDim2.fromOffset(0, 0) })
end
 
local function createTab(name)
	local button = create("TextButton", { Name = name, Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = THEME.Element, BackgroundTransparency = 1, AutoButtonColor = false, Text = "", LayoutOrder = nextOrder(), Parent = tabList })
	corner(button, 8)
	local indicator = create("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(3, 0), BackgroundColor3 = THEME.White, Parent = button })
	round(indicator) accent(indicator, 90)
	local label = newLabel({ Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -18, 1, 0), Text = name, TextSize = 13, TextColor3 = THEME.SubText, Parent = button })
	local page = create("ScrollingFrame", { Name = name, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 3, ScrollBarImageColor3 = THEME.Accent1, ScrollBarImageTransparency = 0.3, VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar, Visible = false, Parent = pageHolder })
	create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page })
	create("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 6), Parent = page })
	local tab = { Name = name, Button = button, Indicator = indicator, Label = label, Page = page }
	table.insert(tabs, tab)
	button.MouseEnter:Connect(function() if selectedTab ~= tab then tween(button, 0.2, { BackgroundTransparency = 0.75 }) end end)
	button.MouseLeave:Connect(function() if selectedTab ~= tab then tween(button, 0.2, { BackgroundTransparency = 1 }) end end)
	button.MouseButton1Click:Connect(function() selectTab(tab) end)
	return page
end

-- УВЕДОМЛЕНИЯ
local function notify(title, message)
	local toast = create("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 320, 1, -24), Size = UDim2.fromOffset(260, 60), BackgroundColor3 = THEME.Window, BackgroundTransparency = 0.25, Parent = gui })
	corner(toast, 10) accent(stroke(toast, 0.35, 1.2), 45)
	local bar = create("Frame", { Position = UDim2.fromOffset(12, 12), Size = UDim2.new(0, 3, 1, -24), BackgroundColor3 = THEME.White, Parent = toast })
	round(bar) accent(bar, 90)
	newLabel({ Position = UDim2.fromOffset(24, 11), Size = UDim2.new(1, -34, 0, 18), Text = title, Font = FONT_BOLD, Parent = toast })
	newLabel({ Position = UDim2.fromOffset(24, 31), Size = UDim2.new(1, -34, 0, 16), Text = message, Font = FONT_REGULAR, TextSize = 12, TextColor3 = THEME.SubText, Parent = toast })
	tween(toast, 0.6, { Position = UDim2.new(1, -24, 1, -24) })
	task.delay(4, function()
		local hide = tween(toast, 0.5, { Position = UDim2.new(1, 320, 1, -24) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		hide.Completed:Wait() toast:Destroy()
	end)
end

---------------------------------------------------------------------
-- КОМПОНЕНТЫ С ФУНКЦИЯМИ
---------------------------------------------------------------------
local function baseRow(page, height, className)
	local row = create(className or "Frame", { Size = UDim2.new(1, 0, 0, height), BackgroundColor3 = THEME.Element, BackgroundTransparency = 0.55, LayoutOrder = nextOrder(), Parent = page })
	if className == "TextButton" then row.AutoButtonColor = false row.Text = "" end
	corner(row, 8) stroke(row, 0.92) return row
end
 
local function hover(obj, normal, hovered)
	obj.MouseEnter:Connect(function() tween(obj, 0.2, { BackgroundTransparency = hovered }) end)
	obj.MouseLeave:Connect(function() tween(obj, 0.2, { BackgroundTransparency = normal }) end)
end
 
local function ripple(button, x)
	local relative = (x - button.AbsolutePosition.X) / math.max(button.AbsoluteSize.X, 1)
	local size = button.AbsoluteSize.X * 2
	local circle = create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(relative, 0.5), Size = UDim2.fromOffset(0, 0), BackgroundColor3 = THEME.White, BackgroundTransparency = 0.8, ZIndex = 0, Parent = button })
	round(circle) tween(circle, 0.6, { Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
	task.delay(0.6, function() circle:Destroy() end)
end
 
local function addSection(page, title)
	return newLabel({ Size = UDim2.new(1, 0, 0, 18), Text = title, Font = FONT_BOLD, TextSize = 11, TextColor3 = THEME.SubText, LayoutOrder = nextOrder(), Parent = page })
end

local function addButton(page, title, callback)
	local button = baseRow(page, 38, "TextButton")
	button.ClipsDescendants = true
	newLabel({ Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -40, 1, 0), Text = title, Parent = button })
	hover(button, 0.55, 0.35)
	button.InputBegan:Connect(function(input) if isPress(input) then ripple(button, input.Position.X) if callback then callback() end end end)
	return button
end
 
local function addToggle(page, title, enabled, callback)
	local row = baseRow(page, 38, "TextButton")
	newLabel({ Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -70, 1, 0), Text = title, Parent = row })
	local track = create("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(38, 20), BackgroundColor3 = THEME.Off, BackgroundTransparency = 0.2, Parent = row })
	round(track)
	local fill = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = THEME.White, BackgroundTransparency = 1, Parent = track })
	round(fill) accent(fill)
	local knob = create("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = THEME.White, ZIndex = 2, Parent = track })
	round(knob)
 
	local state = enabled == true
	local function render(dur)
		tween(fill, dur, { BackgroundTransparency = state and 0 or 1 })
		tween(knob, dur, { Position = state and UDim2.new(1, -17, 0.5, 0) or UDim2.new(0, 3, 0.5, 0) })
	end
	render(0)
 
	hover(row, 0.55, 0.35)
	row.MouseButton1Click:Connect(function()
		state = not state render(0.25)
        if callback then callback(state) end
	end)
	return row
end

local function addInput(page, title, placeholder, callback)
	local row = baseRow(page, 40)
	newLabel({ Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.45, -12, 1, 0), Text = title, Parent = row })
	local box = create("TextBox", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.new(0.55, -8, 0, 26), BackgroundColor3 = THEME.Panel, BackgroundTransparency = 0.3, ClearTextOnFocus = false, ClipsDescendants = true, Text = "", PlaceholderText = placeholder, PlaceholderColor3 = THEME.SubText, TextColor3 = THEME.Text, Font = FONT_MEDIUM, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
	corner(box, 6)
	create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = box })
	local boxStroke = stroke(box, 0.9)
	box.Focused:Connect(function() tween(boxStroke, 0.2, { Color = THEME.Accent2, Transparency = 0.2 }) end)
	box.FocusLost:Connect(function() tween(boxStroke, 0.2, { Color = THEME.White, Transparency = 0.9 }) if callback then callback(box.Text) end end)
	return row
end
 
local function addSlider(page, title, minValue, maxValue, startValue, callback)
	local row = baseRow(page, 54)
	row.Active = true
	newLabel({ Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -90, 0, 18), Text = title, Parent = row })
	local valueLabel = newLabel({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8), Size = UDim2.fromOffset(70, 18), Text = "", Font = FONT_BOLD, TextColor3 = THEME.Accent2, TextXAlignment = Enum.TextXAlignment.Right, Parent = row })
	local bar = create("Frame", { Position = UDim2.fromOffset(12, 36), Size = UDim2.new(1, -24, 0, 6), BackgroundColor3 = THEME.Off, BackgroundTransparency = 0.3, Parent = row })
	round(bar)
	local fill = create("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = THEME.White, Parent = bar })
	round(fill) accent(fill)
	local knob = create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = THEME.White, ZIndex = 2, Parent = bar })
	round(knob) stroke(knob, 0.1, 2, THEME.Accent1)
 
	local function setPercent(percent, duration)
		percent = math.clamp(percent, 0, 1)
        local val = math.floor(minValue + (maxValue - minValue) * percent + 0.5)
		valueLabel.Text = tostring(val)
		tween(fill, duration, { Size = UDim2.fromScale(percent, 1) })
		tween(knob, duration, { Position = UDim2.fromScale(percent, 0.5) })
        if callback then callback(val) end
	end
	setPercent((startValue - minValue) / (maxValue - minValue), 0)
 
	local sliding = false
	local function slideTo(x) setPercent((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0.08) end
	row.InputBegan:Connect(function(input) if isPress(input) then sliding = true slideTo(input.Position.X) end end)
	UserInputService.InputChanged:Connect(function(input) if sliding and isMove(input) then slideTo(input.Position.X) end end)
	UserInputService.InputEnded:Connect(function(input) if isPress(input) then sliding = false end end)
	return row
end

---------------------------------------------------------------------
-- ЛОГИКА СКРИПТОВ (FLY, CLIMB, FLING, TROLLING)
---------------------------------------------------------------------

-- ЛОГИКА ТРОЛЛИНГА
local function getTargetByName(str)
    if not str or str == "" then return nil end
    str = str:lower()
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= player and (p.Name:lower():sub(1, #str) == str or p.DisplayName:lower():sub(1, #str) == str) then
            return p
        end
    end
    return nil
end

local function startTrolling()
    if trollConnection then trollConnection:Disconnect() trollConnection = nil end
    local humanoid, root = getCharacterParts()
    if not humanoid or not root then return end

    if TrollMode == "None" or not TrollTarget then
        humanoid.PlatformStand = false
        return
    end

    humanoid.PlatformStand = true
    local t = 0
    trollConnection = RunService.Heartbeat:Connect(function(dt)
        t = t + dt
        if not TrollTarget or not TrollTarget.Character then return end
        local tRoot = TrollTarget.Character:FindFirstChild("HumanoidRootPart")
        local tHead = TrollTarget.Character:FindFirstChild("Head") or tRoot
        if not tRoot then return end

        if TrollMode == "Orbit" then
            local speed = 8
            local radius = 6
            local angle = t * speed
            root.Velocity = Vector3.zero
            root.CFrame = tRoot.CFrame * CFrame.new(math.cos(angle) * radius, math.sin(t*3)*2, math.sin(angle) * radius)
        elseif TrollMode == "Head" then
            root.Velocity = Vector3.zero
            root.CFrame = tHead.CFrame * CFrame.new(0, 1.5, 0)
        elseif TrollMode == "Follow" then
            root.Velocity = Vector3.zero
            root.CFrame = tRoot.CFrame * CFrame.new(0, 0, 4)
        end
    end)
end

-- ЛОГИКА ЛАЗАНИЯ
local function stopClimb(launchVelocity)
	if not isClimbing then return end
	isClimbing = false
	if climbVelocity then climbVelocity:Destroy() climbVelocity = nil end
	if climbAlign then climbAlign:Destroy() climbAlign = nil end
	if climbAttachment then climbAttachment:Destroy() climbAttachment = nil end
	if climbTrack then climbTrack:Stop(0.2) climbTrack = nil end
	climbCooldownUntil = os.clock() + 0.35
	local humanoid, root = getCharacterParts()
	if humanoid and TrollMode == "None" then humanoid.PlatformStand = false humanoid:ChangeState(Enum.HumanoidStateType.Freefall) end
	if root and launchVelocity then root.AssemblyLinearVelocity = launchVelocity end
end

local function startClimb(hit)
	local humanoid, root = getCharacterParts()
	if not humanoid or not root or flying or TrollMode ~= "None" then return end
	isClimbing = true
	climbNormal = hit.Normal
	humanoid.PlatformStand = true

	climbAttachment = Instance.new("Attachment", root)
	climbVelocity = Instance.new("LinearVelocity", root)
	climbVelocity.Attachment0 = climbAttachment
	climbVelocity.MaxForce = math.huge
	climbVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	climbVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	climbVelocity.VectorVelocity = Vector3.zero

	climbAlign = Instance.new("AlignOrientation", root)
	climbAlign.Mode = Enum.OrientationAlignmentMode.OneAttachment
	climbAlign.Attachment0 = climbAttachment
	climbAlign.MaxTorque = math.huge
	climbAlign.Responsiveness = 30
	climbAlign.CFrame = CFrame.lookAt(Vector3.zero, -Vector3.new(climbNormal.X, 0, climbNormal.Z).Unit)

	if climbTrackCache.humanoid ~= humanoid then
		climbTrackCache = { humanoid = humanoid }
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			local anim = Instance.new("Animation")
			anim.AnimationId = humanoid.RigType == Enum.HumanoidRigType.R15 and CLIMB_ANIM_FALLBACK.R15 or CLIMB_ANIM_FALLBACK.R6
			pcall(function() climbTrackCache.track = animator:LoadAnimation(anim) end)
		end
	end
	climbTrack = climbTrackCache.track
	if climbTrack then climbTrack.Priority = Enum.AnimationPriority.Action climbTrack.Looped = true climbTrack:Play(0.15) climbTrack:AdjustSpeed(0) end
end

local function toggleWallClimb(state)
	WallClimbEnabled = state
	if not state then stopClimb() end
    notify("Человек-паук", state and "Лазание включено" or "Лазание выключено")
end

-- ЛОГИКА ПОЛЕТА
local function stopFly()
	flying = false
	if flyConnection then flyConnection:Disconnect() flyConnection = nil end
	if flyVelocity then flyVelocity:Destroy() flyVelocity = nil end
	if flyAlign then flyAlign:Destroy() flyAlign = nil end
	if flyAttachment then flyAttachment:Destroy() flyAttachment = nil end
	resetJoints(flyJoints) flyJoints = nil
	local humanoid = getCharacterParts()
	if humanoid and TrollMode == "None" then humanoid.PlatformStand = false humanoid:ChangeState(Enum.HumanoidStateType.Freefall) end
end

local POSES = { Hover = { raP = 0.2, raS = 0.35, laP = 0.2, laS = 0.35, raE = 0.25, laE = 0.25, rlP = 0.25, rlS = 0.06, llP = -0.1, llS = 0.06, rlK = 0.4, llK = 0.15, neck = 0, waist = 0 }, Super = { raP = 2.95, raS = 0.08, laP = -0.15, laS = 0.12, raE = 0.05, laE = 0.1, rlP = -0.12, rlS = 0.03, llP = 0, llS = 0.03, rlK = 0.15, llK = 0.05, neck = 0.9, waist = 0.15 }, Back = { raP = 0.9, raS = 0.3, laP = 0.9, laS = 0.3, raE = 0.4, laE = 0.4, rlP = 0.5, rlS = 0.05, llP = 0.35, llS = 0.05, rlK = 0.6, llK = 0.5, neck = 0.1, waist = -0.15 }, Ascend = { raP = 2.9, raS = 0.25, laP = 2.9, laS = 0.25, raE = 0.05, laE = 0.05, rlP = 0, rlS = 0.04, llP = 0.05, llS = 0.04, rlK = 0.1, llK = 0.2, neck = 0.25, waist = 0 }, Descend = { raP = 0.6, raS = 1.2, laP = 0.6, laS = 1.2, raE = 0.3, laE = 0.3, rlP = 0.35, rlS = 0.15, llP = 0.1, llS = 0.15, rlK = 0.5, llK = 0.5, neck = -0.2, waist = -0.1 } }
local function applyPose(j, p)
	local rig = j.rig local function limb(s, pt, sp) return rig == "R15" and CFrame.Angles(pt, 0, s * sp) or CFrame.Angles(-sp, 0, s * pt) end
	if j.RightArm then j.RightArm.Transform = limb(1, p.raP, p.raS) end if j.LeftArm then j.LeftArm.Transform = limb(-1, p.laP, p.laS) end
	if j.RightLeg then j.RightLeg.Transform = limb(1, p.rlP, p.rlS) end if j.LeftLeg then j.LeftLeg.Transform = limb(-1, p.llP, p.llS) end
	if j.RightElbow then j.RightElbow.Transform = CFrame.Angles(p.raE, 0, 0) end if j.LeftElbow then j.LeftElbow.Transform = CFrame.Angles(p.laE, 0, 0) end
	if j.RightKnee then j.RightKnee.Transform = CFrame.Angles(-p.rlK, 0, 0) end if j.LeftKnee then j.LeftKnee.Transform = CFrame.Angles(-p.llK, 0, 0) end
	if j.Waist then j.Waist.Transform = CFrame.Angles(p.waist, 0, 0) end if j.Neck then j.Neck.Transform = rig == "R15" and CFrame.Angles(p.neck, 0, 0) or CFrame.Angles(-p.neck, 0, 0) end
	for _, m in pairs(j.Neutral) do if m then m.Transform = CFrame.identity end end
end

local function toggleFly(state)
	if not state then stopFly() notify("Полет", "Выключен") return end
	local humanoid, root = getCharacterParts()
	if not humanoid or not root or TrollMode ~= "None" then return end
	if isClimbing then stopClimb() end
	flying = true
	humanoid.PlatformStand = true
	flyJoints = getJoints(player.Character)
	
	flyAttachment = Instance.new("Attachment", root)
	flyVelocity = Instance.new("LinearVelocity", root) flyVelocity.Attachment0 = flyAttachment flyVelocity.MaxForce = math.huge flyVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector flyVelocity.RelativeTo = Enum.ActuatorRelativeTo.World flyVelocity.VectorVelocity = Vector3.zero
	flyAlign = Instance.new("AlignOrientation", root) flyAlign.Mode = Enum.OrientationAlignmentMode.OneAttachment flyAlign.Attachment0 = flyAttachment flyAlign.RigidityEnabled = true
	
	local currentRotation = root.CFrame.Rotation local currentPose = {} for k in pairs(POSES.Hover) do currentPose[k] = 0 end local t = 0
    notify("Полет", "Успешно активирован")
	
	flyConnection = RunService.Stepped:Connect(function(_, dt)
		if not root.Parent then stopFly() return end
		t += dt local alpha = 1 - math.exp(-9 * dt)
		local animator = humanoid:FindFirstChildOfClass("Animator") if animator then for _, track in ipairs(animator:GetPlayingAnimationTracks()) do track:Stop(0) end end
		local camCF = camera.CFrame local camLook = camCF.LookVector local flatLook = Vector3.new(camLook.X, 0, camLook.Z)
		if flatLook.Magnitude < 1e-3 then flatLook = Vector3.new(camCF.UpVector.X, 0, camCF.UpVector.Z) end flatLook = flatLook.Unit
		local flatRight = Vector3.new(-flatLook.Z, 0, flatLook.X)
		local inF, inR, inU = 0, 0, 0
		if not UserInputService:GetFocusedTextBox() then
			if UserInputService:IsKeyDown(Enum.KeyCode.W) then inF += 1 end if UserInputService:IsKeyDown(Enum.KeyCode.S) then inF -= 1 end
			if UserInputService:IsKeyDown(Enum.KeyCode.D) then inR += 1 end if UserInputService:IsKeyDown(Enum.KeyCode.A) then inR -= 1 end
			if UserInputService:IsKeyDown(Enum.KeyCode.Space) then inU += 1 end if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then inU -= 1 end
		end
		if inF == 0 and inR == 0 then local md = humanoid.MoveDirection if md.Magnitude > 0.05 then inF = md:Dot(flatLook) inR = md:Dot(flatRight) end end
		
		local direction = camLook * inF + camCF.RightVector * inR + Vector3.yAxis * inU
		local moving = direction.Magnitude > 0.01
		flyVelocity.VectorVelocity = moving and direction.Unit * FlySpeed or Vector3.new(0, math.sin(t * 2) * 1.5, 0)
		
		local wF, wB, wU, wD, wS = math.max(0, inF), math.max(0, -inF), math.max(0, inU), math.max(0, -inU), math.abs(inR) * 0.6
		local wH = moving and 0 or 1 local total = wF + wB + wU + wD + wS + wH if total <= 0 then wH, total = 1, 1 end
		local wFn, wBn, wDn, wHn = wF / total, wB / total, wD / total, wH / total
		local camPitch = math.asin(math.clamp(camLook.Y, -1, 1))
		local superPitch = math.clamp(-(math.rad(80) - camPitch), -math.rad(165), -math.rad(15))
		local bodyPitch = wFn * superPitch + wBn * math.rad(15) + wDn * math.rad(-8) + math.sin(t * 1.3) * 0.03 * wHn
		currentRotation = currentRotation:Lerp(CFrame.lookAt(Vector3.zero, flatLook) * CFrame.Angles(bodyPitch, 0, 0) * CFrame.Angles(0, inR * math.rad(35) * wFn, -inR * math.rad(20) * (1 - wFn) + math.sin(t * 0.9) * 0.03 * wHn), alpha)
		flyAlign.CFrame = currentRotation
		if flyJoints then
			local result = {} local tot = (wH+wS)+wF+wB+wU+wD
			for k,v in pairs(POSES.Hover) do result[k] = (v*(wH+wS) + POSES.Super[k]*wF + POSES.Back[k]*wB + POSES.Ascend[k]*wU + POSES.Descend[k]*wD) / math.max(tot,1) end
			for k, v in pairs(result) do currentPose[k] += (v - currentPose[k]) * alpha end
			local p = table.clone(currentPose)
			p.raS += math.sin(t * 2) * 0.07 * wHn p.laS += math.sin(t * 2) * 0.07 * wHn
			p.rlP += math.sin(t * 1.6) * 0.12 * wHn p.llP -= math.sin(t * 1.6) * 0.12 * wHn
			p.rlP += math.sin(t * 9) * 0.1 * wFn p.llP -= math.sin(t * 9) * 0.1 * wFn
			applyPose(flyJoints, p)
		end
	end)
end

-- ЛОГИКА ФЛИНГА
local function SkidFling(TargetPlayer)
    local Character = player.Character
    local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
    local RootPart = Humanoid and Humanoid.RootPart
    local TCharacter = TargetPlayer.Character
    if not TCharacter then return end
    
    local THumanoid = TCharacter:FindFirstChildOfClass("Humanoid")
    local TRootPart = THumanoid and THumanoid.RootPart
    local THead = TCharacter:FindFirstChild("Head")
    local Accessory = TCharacter:FindFirstChildOfClass("Accessory")
    local Handle = Accessory and Accessory:FindFirstChild("Handle")
    
    if Character and Humanoid and RootPart then
        if RootPart.Velocity.Magnitude < 50 then getgenv().OldPos = RootPart.CFrame end
        if THumanoid and THumanoid.Sit then return end
        
        if THead then workspace.CurrentCamera.CameraSubject = THead
        elseif Handle then workspace.CurrentCamera.CameraSubject = Handle
        elseif THumanoid and TRootPart then workspace.CurrentCamera.CameraSubject = THumanoid end
        
        if not TCharacter:FindFirstChildWhichIsA("BasePart") then return end
        
        local function FPos(BasePart, Pos, Ang)
            RootPart.CFrame = CFrame.new(BasePart.Position) * Pos * Ang
            Character:SetPrimaryPartCFrame(CFrame.new(BasePart.Position) * Pos * Ang)
            RootPart.Velocity = Vector3.new(9e7, 9e7 * 10, 9e7)
            RootPart.RotVelocity = Vector3.new(9e8, 9e8, 9e8)
        end
        
        local function SFBasePart(BasePart)
            local TimeToWait, Time, Angle = 2, tick(), 0
            repeat
                if RootPart and THumanoid then
                    if BasePart.Velocity.Magnitude < 50 then
                        Angle = Angle + 100
                        FPos(BasePart, CFrame.new(0, 1.5, 0) + THumanoid.MoveDirection * BasePart.Velocity.Magnitude / 1.25, CFrame.Angles(math.rad(Angle),0 ,0)) task.wait()
                        FPos(BasePart, CFrame.new(0, -1.5, 0) + THumanoid.MoveDirection * BasePart.Velocity.Magnitude / 1.25, CFrame.Angles(math.rad(Angle), 0, 0)) task.wait()
                        FPos(BasePart, CFrame.new(0, 1.5, 0) + THumanoid.MoveDirection, CFrame.Angles(math.rad(Angle),0 ,0)) task.wait()
                        FPos(BasePart, CFrame.new(0, -1.5, 0) + THumanoid.MoveDirection, CFrame.Angles(math.rad(Angle), 0, 0)) task.wait()
                    else
                        FPos(BasePart, CFrame.new(0, 1.5, THumanoid.WalkSpeed), CFrame.Angles(math.rad(90), 0, 0)) task.wait()
                        FPos(BasePart, CFrame.new(0, -1.5, -THumanoid.WalkSpeed), CFrame.Angles(0, 0, 0)) task.wait()
                        FPos(BasePart, CFrame.new(0, 1.5, THumanoid.WalkSpeed), CFrame.Angles(math.rad(90), 0, 0)) task.wait()
                        FPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(math.rad(90), 0, 0)) task.wait()
                        FPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(0, 0, 0)) task.wait()
                    end
                end
            until Time + TimeToWait < tick() or not FlingActive
        end
        
        workspace.FallenPartsDestroyHeight = 0/0
        local BV = Instance.new("BodyVelocity", RootPart) BV.Velocity = Vector3.zero BV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
        
        if TRootPart then SFBasePart(TRootPart) elseif THead then SFBasePart(THead) elseif Handle then SFBasePart(Handle) end
        
        BV:Destroy()
        Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
        workspace.CurrentCamera.CameraSubject = Humanoid
        
        if getgenv().OldPos then
            repeat
                RootPart.CFrame = getgenv().OldPos * CFrame.new(0, .5, 0)
                Character:SetPrimaryPartCFrame(getgenv().OldPos * CFrame.new(0, .5, 0))
                Humanoid:ChangeState("GettingUp")
                for _, part in pairs(Character:GetChildren()) do if part:IsA("BasePart") then part.Velocity = Vector3.zero part.RotVelocity = Vector3.zero end end
                task.wait()
            until (RootPart.Position - getgenv().OldPos.p).Magnitude < 25
            workspace.FallenPartsDestroyHeight = getgenv().FPDH
        end
    end
end

-- ОБРАБОТКА ПРЫЖКОВ И ПЕРЕМЕЩЕНИЙ
UserInputService.JumpRequest:Connect(function()
	if isClimbing and climbNormal then stopClimb(climbNormal * 45 + Vector3.yAxis * 40)
	elseif InfiniteJumpEnabled and not flying and not isClimbing and TrollMode == "None" then
		local humanoid = getCharacterParts() if humanoid then humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end
	end
end)

RunService.Heartbeat:Connect(function()
	if not WallClimbEnabled and not isClimbing then return end
	local character = player.Character
	local humanoid, root = getCharacterParts()
	if not WallClimbEnabled or not humanoid or not root or humanoid.Health <= 0 or humanoid.Sit or TrollMode ~= "None" then stopClimb() return end
	local params = RaycastParams.new() params.FilterType = Enum.RaycastFilterType.Exclude params.FilterDescendantsInstances = { character } params.IgnoreWater = true
	if not isClimbing then
		if os.clock() < climbCooldownUntil then return end
		local md = humanoid.MoveDirection local flatDir = Vector3.new(md.X, 0, md.Z) if flatDir.Magnitude < 0.1 then return end flatDir = flatDir.Unit
		local hit = workspace:Raycast(root.Position, flatDir * 2.2, params)
		if isClimbable(hit) and flatDir:Dot(-hit.Normal) > 0.5 then startClimb(hit) end
		return
	end
	local right = (-climbNormal):Cross(Vector3.yAxis) if right.Magnitude < 1e-3 then stopClimb() return end right = right.Unit
	local inU, inR = 0, 0
	if not UserInputService:GetFocusedTextBox() then
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then inU += 1 end if UserInputService:IsKeyDown(Enum.KeyCode.S) then inU -= 1 end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then inR += 1 end if UserInputService:IsKeyDown(Enum.KeyCode.A) then inR -= 1 end
	end
	if inU == 0 and inR == 0 then local md = humanoid.MoveDirection if md.Magnitude > 0.05 then inU = md:Dot(-climbNormal) inR = md:Dot(right) end end
	local hit = workspace:Raycast(root.Position, -climbNormal * 3.5, params)
	if not isClimbable(hit) then if inU > 0 then stopClimb(Vector3.yAxis * 40 - climbNormal * 18) else stopClimb() end return end
	local blended = climbNormal + hit.Normal climbNormal = blended.Magnitude > 0.01 and blended.Unit or hit.Normal
	if inU < 0 and workspace:Raycast(root.Position, Vector3.new(0, -3.2, 0), params) then stopClimb() return end
	local move = Vector3.yAxis * inU + right * inR if move.Magnitude > 1 then move = move.Unit end
	local boost = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and 2 or 1
	local dist = (root.Position - hit.Position):Dot(climbNormal)
	climbVelocity.VectorVelocity = move * ClimbSpeedWalk * boost + climbNormal * (CLIMB_HOLD_DIST - dist) * 12
	local facing = Vector3.new(-climbNormal.X, 0, -climbNormal.Z) if facing.Magnitude > 1e-3 then climbAlign.CFrame = CFrame.lookAt(Vector3.zero, facing.Unit) end
	if climbTrack then climbTrack:AdjustSpeed(move.Magnitude > 0.05 and ClimbSpeedWalk * boost / 12 or 0) end
end)

---------------------------------------------------------------------
-- НАСТРОЙКА ВКЛАДОК И ВНЕШНЕГО ВИДА
---------------------------------------------------------------------

-- ВКЛАДКА 1: ИГРОК
local pPlayer = createTab("Игрок")
addSection(pPlayer, "ПЕРЕДВИЖЕНИЕ")
addToggle(pPlayer, "Бесконечный прыжок", false, function(s) InfiniteJumpEnabled = s end)
addToggle(pPlayer, "Полет", false, toggleFly)
addToggle(pPlayer, "Человек-паук (Стены)", false, toggleWallClimb)
addSection(pPlayer, "НАСТРОЙКА СКОРОСТИ")
addSlider(pPlayer, "Скорость полета", 10, 300, 60, function(v) FlySpeed = v end)

-- ВКЛАДКА 2: ФЛИНГ
local pFling = createTab("Флинг")
addSection(pFling, "УПРАВЛЕНИЕ")
addButton(pFling, "▶ ЗАПУСТИТЬ FLING", function()
    local c=0 for _ in pairs(SelectedTargets) do c=c+1 end
    if c==0 then notify("Ошибка", "Сначала выбери игроков!") return end
    if FlingActive then return end FlingActive = true notify("Fling", "Запущен разброс " .. c .. " целей")
    spawn(function()
        while FlingActive do
            local valid = {} for n, p in pairs(SelectedTargets) do if p and p.Parent then valid[n]=p else SelectedTargets[n]=nil end end
            for _, p in pairs(valid) do if FlingActive then SkidFling(p) task.wait(0.1) else break end end task.wait(0.5)
        end
    end)
end)
addButton(pFling, "⏹ ОСТАНОВИТЬ FLING", function() FlingActive = false notify("Fling", "Остановлен") end)
addSection(pFling, "СПИСОК ИГРОКОВ")

local plyListRow = create("Frame", {Size = UDim2.new(1, 0, 0, 180), BackgroundColor3 = THEME.Panel, BackgroundTransparency = 0.5, LayoutOrder = nextOrder(), Parent = pFling})
corner(plyListRow, 8) stroke(plyListRow, 0.8)
local plyScroll = create("ScrollingFrame", {Size = UDim2.new(1, -10, 1, -10), Position = UDim2.fromOffset(5,5), BackgroundTransparency = 1, ScrollBarThickness = 4, CanvasSize = UDim2.new(0,0,0,0), Parent = plyListRow})
local plyListLayout = create("UIListLayout", {Padding = UDim.new(0, 4), Parent = plyScroll})

local function RefreshPlayerList()
    for _, c in pairs(plyScroll:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end
    PlayerCheckboxes = {}
    local plrs = Players:GetPlayers() table.sort(plrs, function(a,b) return a.Name:lower() < b.Name:lower() end)
    local ySize = 0
    for _, p in ipairs(plrs) do
        if p ~= player then
            local entry = create("TextButton", {Size = UDim2.new(1, -10, 0, 30), BackgroundColor3 = THEME.Element, Text = "", AutoButtonColor = false, Parent = plyScroll})
            corner(entry, 6)
            local chkBox = create("Frame", {Size = UDim2.fromOffset(20, 20), Position = UDim2.new(0, 5, 0.5, -10), BackgroundColor3 = THEME.Off, Parent = entry})
            corner(chkBox, 4)
            local chkMark = newLabel({Size = UDim2.fromScale(1,1), Text = "✓", Font = FONT_BOLD, TextColor3 = THEME.Green, TextXAlignment = Enum.TextXAlignment.Center, Visible = SelectedTargets[p.Name] ~= nil, Parent = chkBox})
            newLabel({Size = UDim2.new(1, -35, 1, 0), Position = UDim2.fromOffset(30, 0), Text = p.Name, Parent = entry})
            
            entry.MouseButton1Click:Connect(function()
                if SelectedTargets[p.Name] then SelectedTargets[p.Name] = nil chkMark.Visible = false
                else SelectedTargets[p.Name] = p chkMark.Visible = true end
            end)
            PlayerCheckboxes[p.Name] = chkMark
            ySize += 34
        end
    end
    plyScroll.CanvasSize = UDim2.new(0,0,0,ySize)
end
Players.PlayerAdded:Connect(RefreshPlayerList)
Players.PlayerRemoving:Connect(function(p) if SelectedTargets[p.Name] then SelectedTargets[p.Name] = nil end RefreshPlayerList() end)
RefreshPlayerList()

addButton(pFling, "☑ ВЫДЕЛИТЬ ВСЕХ", function() for _, p in ipairs(Players:GetPlayers()) do if p~=player then SelectedTargets[p.Name]=p if PlayerCheckboxes[p.Name] then PlayerCheckboxes[p.Name].Visible=true end end end end)
addButton(pFling, "☐ СНЯТЬ ВЫДЕЛЕНИЕ", function() SelectedTargets={} for _, mark in pairs(PlayerCheckboxes) do mark.Visible=false end end)

-- ВКЛАДКА 3: ТРОЛЛИНГ
local pTroll = createTab("Троллинг")
addSection(pTroll, "ПОИСК ЦЕЛИ")

addInput(pTroll, "Имя цели", "Введи начало ника...", function(txt)
    TrollTarget = getTargetByName(txt)
    if TrollTarget then
        notify("Троллинг", "Цель найдена: " .. TrollTarget.DisplayName)
        startTrolling()
    else
        notify("Ошибка", "Игрок не найден")
        TrollMode = "None"
        startTrolling()
    end
end)

addSection(pTroll, "РЕЖИМЫ (Только один)")

addButton(pTroll, "🪐 Безумная Орбита", function()
    if not TrollTarget then notify("Ошибка", "Сначала выбери цель!") return end
    TrollMode = "Orbit" startTrolling() notify("Троллинг", "Режим: Орбита")
end)

addButton(pTroll, "🎩 Сесть на голову (Шапка)", function()
    if not TrollTarget then notify("Ошибка", "Сначала выбери цель!") return end
    TrollMode = "Head" startTrolling() notify("Троллинг", "Режим: Шапка")
end)

addButton(pTroll, "🚶 Преследование спины", function()
    if not TrollTarget then notify("Ошибка", "Сначала выбери цель!") return end
    TrollMode = "Follow" startTrolling() notify("Троллинг", "Режим: Преследование")
end)

addSection(pTroll, "ОТКЛЮЧЕНИЕ")
addButton(pTroll, "🛑 ОСТАНОВИТЬ ТРОЛЛИНГ", function()
    TrollMode = "None" TrollTarget = nil startTrolling() notify("Троллинг", "Остановлен")
end)

player.CharacterAdded:Connect(function() 
    TrollMode = "None" TrollTarget = nil startTrolling() 
end)

selectTab(tabs[1])

---------------------------------------------------------------------
-- УПРАВЛЕНИЕ ОКНОМ (ВКЛ/ВЫКЛ, ДРАГ, АНИМАЦИИ)
---------------------------------------------------------------------
local menuVisible = true
local function setMenuVisible(v)
	if menuVisible == v then return end
	menuVisible = v
	if v then holder.Visible = true tween(popScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	else tween(popScale, 0.3, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In).Completed:Connect(function(s) if s == Enum.PlaybackState.Completed and not menuVisible then holder.Visible = false end end) end
end
 
local minimized = false
minimizeButton.MouseButton1Click:Connect(function()
	minimized = not minimized
	local goal = minimized and UDim2.new(1, 0, 0, 48) or UDim2.fromScale(1, 1)
	
	tween(main, 0.4, { Size = goal }) 
	for _, glow in ipairs(glowLayers) do 
		tween(glow, 0.4, { Size = goal }) 
	end
	
	if minimized then
		sidebar.Visible = false content.Visible = false divider.Visible = false
	else
		sidebar.Visible = true content.Visible = true divider.Visible = true
	end
end)
 
closeButton.MouseButton1Click:Connect(function()
	setMenuVisible(false) closeButton.BackgroundColor3 = THEME.Element closeButton.BackgroundTransparency = 0.5 closeButton.TextColor3 = THEME.SubText
end)
 
UserInputService.InputBegan:Connect(function(input, gp)
	if not gp and input.KeyCode == CONFIG.ToggleKey then setMenuVisible(not menuVisible) end
end)
 
local openButton = create("TextButton", { Name = "OpenButton", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), Size = UDim2.fromOffset(44, 44), BackgroundColor3 = THEME.Window, BackgroundTransparency = 0.3, AutoButtonColor = false, Text = "", Parent = gui })
round(openButton) accent(stroke(openButton, 0.2, 1.5), 45, true)
local openScale = create("UIScale", { Parent = openButton })
for i = -1, 1 do round(create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, i * 6), Size = UDim2.fromOffset(18, 2), BackgroundColor3 = THEME.White, Parent = openButton })) end
openButton.MouseEnter:Connect(function() tween(openScale, 0.2, { Scale = 1.08 }) end)
openButton.MouseLeave:Connect(function() tween(openScale, 0.2, { Scale = 1 }) end)
openButton.MouseButton1Click:Connect(function() setMenuVisible(not menuVisible) end)
 
local dragging, dragStart, startPosition = false, nil, nil
topBar.InputBegan:Connect(function(input) if isPress(input) then dragging = true dragStart = input.Position startPosition = holder.Position end end)
UserInputService.InputChanged:Connect(function(input) if dragging and isMove(input) then local delta = input.Position - dragStart tween(holder, 0.08, { Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X, startPosition.Y.Scale, startPosition.Y.Offset + delta.Y) }, Enum.EasingStyle.Sine) end end)
UserInputService.InputEnded:Connect(function(input) if isPress(input) then dragging = false end end)
 
local function fitToScreen() local vp = camera.ViewportSize fitScale.Scale = math.max(math.min((vp.X - 140) / CONFIG.Width, (vp.Y - 60) / CONFIG.Height, 1), 0.45) end
fitToScreen() camera:GetPropertyChangedSignal("ViewportSize"):Connect(fitToScreen)
 
RunService.RenderStepped:Connect(function(dt) for _, gradient in ipairs(animatedGradients) do gradient.Rotation = (gradient.Rotation + dt * 40) % 360 end end)
 
tween(popScale, 0.6, { Scale = 1 }, Enum.EasingStyle.Back)
notify("Universal Hub", "Скрипт загружен! [Скрыть/Показать на RightShift]")
