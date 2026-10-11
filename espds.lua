--[[
    UNIVERSAL MULTI-HACK HUB
    Объединяет:
    - KILASIK's Multi-Target Fling (Выбор целей, сохранение позиции)
    - Procedural Fly & Infinite Jump (Анимации R15/R6, управление скоростью)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

---------------------------------------------------------------------
-- Настройки полета и прыжка
---------------------------------------------------------------------
local InfiniteJumpEnabled = false
local FlyKey = Enum.KeyCode.F
local MenuKey = Enum.KeyCode.RightShift
local FlySpeed = 60
local MinSpeed, MaxSpeed = 10, 300
local AnimSmooth = 9 

local flying = false
local attachment, linearVelocity, alignOrientation, flyConnection
local flyJoints

---------------------------------------------------------------------
-- Настройки Fling
---------------------------------------------------------------------
local SelectedTargets = {}
local PlayerCheckboxes = {}
local FlingActive = false
getgenv().OldPos = nil
getgenv().FPDH = workspace.FallenPartsDestroyHeight

---------------------------------------------------------------------
-- Функции анимаций и полета
---------------------------------------------------------------------
local function getCharacterParts()
	local character = player.Character
	if not character then return nil, nil end
	return character:FindFirstChildOfClass("Humanoid"), character:FindFirstChild("HumanoidRootPart")
end

UserInputService.JumpRequest:Connect(function()
	if InfiniteJumpEnabled and not flying then
		local humanoid = getCharacterParts()
		if humanoid then humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end
	end
end)

local POSES = {
	Hover = { raP = 0.2, raS = 0.35, laP = 0.2, laS = 0.35, raE = 0.25, laE = 0.25, rlP = 0.25, rlS = 0.06, llP = -0.1, llS = 0.06, rlK = 0.4, llK = 0.15, neck = 0, waist = 0 },
	Super = { raP = 2.95, raS = 0.08, laP = -0.15, laS = 0.12, raE = 0.05, laE = 0.1, rlP = -0.12, rlS = 0.03, llP = 0, llS = 0.03, rlK = 0.15, llK = 0.05, neck = 0.9, waist = 0.15 },
	Back = { raP = 0.9, raS = 0.3, laP = 0.9, laS = 0.3, raE = 0.4, laE = 0.4, rlP = 0.5, rlS = 0.05, llP = 0.35, llS = 0.05, rlK = 0.6, llK = 0.5, neck = 0.1, waist = -0.15 },
	Ascend = { raP = 2.9, raS = 0.25, laP = 2.9, laS = 0.25, raE = 0.05, laE = 0.05, rlP = 0, rlS = 0.04, llP = 0.05, llS = 0.04, rlK = 0.1, llK = 0.2, neck = 0.25, waist = 0 },
	Descend = { raP = 0.6, raS = 1.2, laP = 0.6, laS = 1.2, raE = 0.3, laE = 0.3, rlP = 0.35, rlS = 0.15, llP = 0.1, llS = 0.15, rlK = 0.5, llK = 0.5, neck = -0.2, waist = -0.1 },
}

local function blendPoses(list)
	local result, total = {}, 0
	for _, item in ipairs(list) do total += item[2] end
	if total <= 0 then return table.clone(POSES.Hover) end
	for _, item in ipairs(list) do
		local pose, w = item[1], item[2] / total
		if w > 0 then
			for k, v in pairs(pose) do result[k] = (result[k] or 0) + v * w end
		end
	end
	return result
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

local function limbCFrame(rig, side, pitch, spread)
	if rig == "R15" then return CFrame.Angles(pitch, 0, side * spread) else return CFrame.Angles(-spread, 0, side * pitch) end
end

local function applyPose(j, p)
	local rig = j.rig
	if j.RightArm then j.RightArm.Transform = limbCFrame(rig, 1, p.raP, p.raS) end
	if j.LeftArm then j.LeftArm.Transform = limbCFrame(rig, -1, p.laP, p.laS) end
	if j.RightLeg then j.RightLeg.Transform = limbCFrame(rig, 1, p.rlP, p.rlS) end
	if j.LeftLeg then j.LeftLeg.Transform = limbCFrame(rig, -1, p.llP, p.llS) end
	if j.RightElbow then j.RightElbow.Transform = CFrame.Angles(p.raE, 0, 0) end
	if j.LeftElbow then j.LeftElbow.Transform = CFrame.Angles(p.laE, 0, 0) end
	if j.RightKnee then j.RightKnee.Transform = CFrame.Angles(-p.rlK, 0, 0) end
	if j.LeftKnee then j.LeftKnee.Transform = CFrame.Angles(-p.llK, 0, 0) end
	if j.Waist then j.Waist.Transform = CFrame.Angles(p.waist, 0, 0) end
	if j.Neck then j.Neck.Transform = rig == "R15" and CFrame.Angles(p.neck, 0, 0) or CFrame.Angles(-p.neck, 0, 0) end
	for _, motor in pairs(j.Neutral) do if motor then motor.Transform = CFrame.identity end end
end

local function resetJoints(j)
	if not j then return end
	for key, motor in pairs(j) do
		if key == "Neutral" then
			for _, m in pairs(motor) do if m and m.Parent then m.Transform = CFrame.identity end end
		elseif typeof(motor) == "Instance" and motor.Parent then motor.Transform = CFrame.identity end
	end
end

local updateMenuUI 

local function stopFly()
	flying = false
	if flyConnection then flyConnection:Disconnect() flyConnection = nil end
	if linearVelocity then linearVelocity:Destroy() linearVelocity = nil end
	if alignOrientation then alignOrientation:Destroy() alignOrientation = nil end
	if attachment then attachment:Destroy() attachment = nil end
	resetJoints(flyJoints)
	flyJoints = nil
	local humanoid = getCharacterParts()
	if humanoid then humanoid.PlatformStand = false humanoid:ChangeState(Enum.HumanoidStateType.Freefall) end
	if updateMenuUI then updateMenuUI() end
end

local function startFly()
	local humanoid, root = getCharacterParts()
	if not humanoid or not root then return end
	flying = true
	humanoid.PlatformStand = true
	flyJoints = getJoints(player.Character)
	local animator = humanoid:FindFirstChildOfClass("Animator")

	attachment = Instance.new("Attachment", root)
	linearVelocity = Instance.new("LinearVelocity", root)
	linearVelocity.Attachment0 = attachment
	linearVelocity.MaxForce = math.huge
	linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.VectorVelocity = Vector3.zero

	alignOrientation = Instance.new("AlignOrientation", root)
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.Attachment0 = attachment
	alignOrientation.RigidityEnabled = true

	local currentRotation = root.CFrame.Rotation
	local currentPose = {}
	for k in pairs(POSES.Hover) do currentPose[k] = 0 end
	local t = 0

	flyConnection = RunService.Stepped:Connect(function(_, dt)
		if not root.Parent then stopFly() return end
		t += dt
		local alpha = 1 - math.exp(-AnimSmooth * dt)
		if animator then for _, track in ipairs(animator:GetPlayingAnimationTracks()) do track:Stop(0) end end

		local camCF = camera.CFrame
		local camLook = camCF.LookVector
		local flatLook = Vector3.new(camLook.X, 0, camLook.Z)
		if flatLook.Magnitude < 1e-3 then flatLook = Vector3.new(camCF.UpVector.X, 0, camCF.UpVector.Z) end
		flatLook = flatLook.Unit
		local flatRight = Vector3.new(-flatLook.Z, 0, flatLook.X)

		local inF, inR, inU = 0, 0, 0
		if not UserInputService:GetFocusedTextBox() then
			if UserInputService:IsKeyDown(Enum.KeyCode.W) then inF += 1 end
			if UserInputService:IsKeyDown(Enum.KeyCode.S) then inF -= 1 end
			if UserInputService:IsKeyDown(Enum.KeyCode.D) then inR += 1 end
			if UserInputService:IsKeyDown(Enum.KeyCode.A) then inR -= 1 end
			if UserInputService:IsKeyDown(Enum.KeyCode.Space) then inU += 1 end
			if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then inU -= 1 end
		end

		if inF == 0 and inR == 0 then
			local md = humanoid.MoveDirection
			if md.Magnitude > 0.05 then inF = md:Dot(flatLook) inR = md:Dot(flatRight) end
		end

		local direction = camLook * inF + camCF.RightVector * inR + Vector3.yAxis * inU
		local moving = direction.Magnitude > 0.01
		if moving then
			linearVelocity.VectorVelocity = direction.Unit * FlySpeed
		else
			linearVelocity.VectorVelocity = Vector3.new(0, math.sin(t * 2) * 1.5, 0)
		end

		local wF, wB = math.max(0, inF), math.max(0, -inF)
		local wU, wD = math.max(0, inU), math.max(0, -inU)
		local wS = math.abs(inR) * 0.6
		local wH = moving and 0 or 1
		local total = wF + wB + wU + wD + wS + wH
		if total <= 0 then wH, total = 1, 1 end
		local wFn, wBn, wDn, wHn = wF / total, wB / total, wD / total, wH / total

		local camPitch = math.asin(math.clamp(camLook.Y, -1, 1))
		local superPitch = math.clamp(-(math.rad(80) - camPitch), -math.rad(165), -math.rad(15))
		local bodyPitch = wFn * superPitch + wBn * math.rad(15) + wDn * math.rad(-8) + math.sin(t * 1.3) * 0.03 * wHn
		local targetRot = CFrame.lookAt(Vector3.zero, flatLook) * CFrame.Angles(bodyPitch, 0, 0) * CFrame.Angles(0, inR * math.rad(35) * wFn, -inR * math.rad(20) * (1 - wFn) + math.sin(t * 0.9) * 0.03 * wHn)
		currentRotation = currentRotation:Lerp(targetRot, alpha)
		alignOrientation.CFrame = currentRotation

		if flyJoints then
			local target = blendPoses({{ POSES.Hover, wH + wS }, { POSES.Super, wF }, { POSES.Back, wB }, { POSES.Ascend, wU }, { POSES.Descend, wD }})
			for k, v in pairs(target) do currentPose[k] += (v - currentPose[k]) * alpha end
			local p = table.clone(currentPose)
			p.raS += math.sin(t * 2) * 0.07 * wHn
			p.laS += math.sin(t * 2) * 0.07 * wHn
			p.rlP += math.sin(t * 1.6) * 0.12 * wHn
			p.llP -= math.sin(t * 1.6) * 0.12 * wHn
			p.rlP += math.sin(t * 9) * 0.1 * wFn
			p.llP -= math.sin(t * 9) * 0.1 * wFn
			applyPose(flyJoints, p)
		end
	end)
	if updateMenuUI then updateMenuUI() end
end

local function toggleFly() if flying then stopFly() else startFly() end end

---------------------------------------------------------------------
-- Функции Fling
---------------------------------------------------------------------
local function Message(Title, Text, Time)
    game:GetService("StarterGui"):SetCore("SendNotification", {Title = Title, Text = Text, Duration = Time or 5})
end

local function SkidFling(TargetPlayer)
    local Character = player.Character
    local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
    local RootPart = Humanoid and Humanoid.RootPart
    local TCharacter = TargetPlayer.Character
    if not TCharacter then return end
    
    local THumanoid, TRootPart, THead, Accessory, Handle
    if TCharacter:FindFirstChildOfClass("Humanoid") then THumanoid = TCharacter:FindFirstChildOfClass("Humanoid") end
    if THumanoid and THumanoid.RootPart then TRootPart = THumanoid.RootPart end
    if TCharacter:FindFirstChild("Head") then THead = TCharacter.Head end
    if TCharacter:FindFirstChildOfClass("Accessory") then Accessory = TCharacter:FindFirstChildOfClass("Accessory") end
    if Accessory and Accessory:FindFirstChild("Handle") then Handle = Accessory.Handle end
    
    if Character and Humanoid and RootPart then
        if RootPart.Velocity.Magnitude < 50 then getgenv().OldPos = RootPart.CFrame end
        if THumanoid and THumanoid.Sit then return Message("Ошибка", TargetPlayer.Name .. " сидит", 2) end
        
        if THead then workspace.CurrentCamera.CameraSubject = THead
        elseif Handle then workspace.CurrentCamera.CameraSubject = Handle
        elseif THumanoid and TRootPart then workspace.CurrentCamera.CameraSubject = THumanoid end
        
        if not TCharacter:FindFirstChildWhichIsA("BasePart") then return end
        
        local FPos = function(BasePart, Pos, Ang)
            RootPart.CFrame = CFrame.new(BasePart.Position) * Pos * Ang
            Character:SetPrimaryPartCFrame(CFrame.new(BasePart.Position) * Pos * Ang)
            RootPart.Velocity = Vector3.new(9e7, 9e7 * 10, 9e7)
            RootPart.RotVelocity = Vector3.new(9e8, 9e8, 9e8)
        end
        
        local SFBasePart = function(BasePart)
            local TimeToWait, Time, Angle = 2, tick(), 0
            repeat
                if RootPart and THumanoid then
                    if BasePart.Velocity.Magnitude < 50 then
                        Angle = Angle + 100
                        FPos(BasePart, CFrame.new(0, 1.5, 0) + THumanoid.MoveDirection * BasePart.Velocity.Magnitude / 1.25, CFrame.Angles(math.rad(Angle),0 ,0))
                        task.wait()
                        FPos(BasePart, CFrame.new(0, -1.5, 0) + THumanoid.MoveDirection * BasePart.Velocity.Magnitude / 1.25, CFrame.Angles(math.rad(Angle), 0, 0))
                        task.wait()
                        FPos(BasePart, CFrame.new(0, 1.5, 0) + THumanoid.MoveDirection * BasePart.Velocity.Magnitude / 1.25, CFrame.Angles(math.rad(Angle),0 ,0))
                        task.wait()
                        FPos(BasePart, CFrame.new(0, -1.5, 0) + THumanoid.MoveDirection * BasePart.Velocity.Magnitude / 1.25, CFrame.Angles(math.rad(Angle), 0, 0))
                        task.wait()
                        FPos(BasePart, CFrame.new(0, 1.5, 0) + THumanoid.MoveDirection, CFrame.Angles(math.rad(Angle),0 ,0))
                        task.wait()
                        FPos(BasePart, CFrame.new(0, -1.5, 0) + THumanoid.MoveDirection, CFrame.Angles(math.rad(Angle), 0, 0))
                        task.wait()
                    else
                        FPos(BasePart, CFrame.new(0, 1.5, THumanoid.WalkSpeed), CFrame.Angles(math.rad(90), 0, 0))
                        task.wait()
                        FPos(BasePart, CFrame.new(0, -1.5, -THumanoid.WalkSpeed), CFrame.Angles(0, 0, 0))
                        task.wait()
                        FPos(BasePart, CFrame.new(0, 1.5, THumanoid.WalkSpeed), CFrame.Angles(math.rad(90), 0, 0))
                        task.wait()
                        FPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(math.rad(90), 0, 0))
                        task.wait()
                        FPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(0, 0, 0))
                        task.wait()
                        FPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(math.rad(90), 0, 0))
                        task.wait()
                        FPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(0, 0, 0))
                        task.wait()
                    end
                end
            until Time + TimeToWait < tick() or not FlingActive
        end
        
        workspace.FallenPartsDestroyHeight = 0/0
        local BV = Instance.new("BodyVelocity")
        BV.Parent = RootPart
        BV.Velocity = Vector3.new(0, 0, 0)
        BV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
        
        if TRootPart then SFBasePart(TRootPart)
        elseif THead then SFBasePart(THead)
        elseif Handle then SFBasePart(Handle)
        else return Message("Ошибка", TargetPlayer.Name .. " нет подходящих частей тела", 2) end
        
        BV:Destroy()
        Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
        workspace.CurrentCamera.CameraSubject = Humanoid
        
        if getgenv().OldPos then
            repeat
                RootPart.CFrame = getgenv().OldPos * CFrame.new(0, .5, 0)
                Character:SetPrimaryPartCFrame(getgenv().OldPos * CFrame.new(0, .5, 0))
                Humanoid:ChangeState("GettingUp")
                for _, part in pairs(Character:GetChildren()) do
                    if part:IsA("BasePart") then part.Velocity, part.RotVelocity = Vector3.new(), Vector3.new() end
                end
                task.wait()
            until (RootPart.Position - getgenv().OldPos.p).Magnitude < 25
            workspace.FallenPartsDestroyHeight = getgenv().FPDH
        end
    else
        return Message("Ошибка", "Ваш персонаж не готов", 2)
    end
end

---------------------------------------------------------------------
-- Создание единого UI
---------------------------------------------------------------------
local Theme = {
	Bg = Color3.fromRGB(16, 16, 22), Panel = Color3.fromRGB(26, 26, 36),
	PanelHover = Color3.fromRGB(34, 34, 48), Stroke = Color3.fromRGB(80, 80, 110),
	Text = Color3.fromRGB(240, 240, 250), SubText = Color3.fromRGB(145, 145, 168),
	Accent1 = Color3.fromRGB(130, 90, 255), Accent2 = Color3.fromRGB(60, 185, 255),
	Off = Color3.fromRGB(52, 52, 68), On = Color3.fromRGB(70, 220, 130),
	Red = Color3.fromRGB(220, 70, 70)
}

local function tween(obj, time, props, style)
	local tw = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out), props)
	tw:Play() return tw
end

local function corner(obj, radius) Instance.new("UICorner", obj).CornerRadius = UDim.new(0, radius) end
local function stroke(obj, color, thick, trans) local s = Instance.new("UIStroke", obj) s.Color = color s.Thickness = thick s.Transparency = trans s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border return s end
local function gradient(obj) local g = Instance.new("UIGradient", obj) g.Color = ColorSequence.new(Theme.Accent1, Theme.Accent2) return g end
local function makeLabel(p, t, s, f, c) local l = Instance.new("TextLabel", p) l.BackgroundTransparency = 1 l.Text = t l.TextSize = s l.Font = f l.TextColor3 = c l.TextXAlignment = Enum.TextXAlignment.Left return l end

local MENU_WIDTH, HEADER_HEIGHT, FULL_HEIGHT = 320, 52, 480

local gui = Instance.new("ScreenGui")
gui.Name = "UniversalHub"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
if CoreGui:FindFirstChild("UniversalHub") then CoreGui.UniversalHub:Destroy() end
gui.Parent = CoreGui

local container = Instance.new("Frame", gui)
container.Size = UDim2.fromOffset(MENU_WIDTH, FULL_HEIGHT)
container.Position = UDim2.new(0, 50, 0.5, -FULL_HEIGHT / 2)
container.BackgroundTransparency = 1

local uiScale = Instance.new("UIScale", container)
uiScale.Scale = 0.85

local shadow = Instance.new("Frame", container)
shadow.Size = UDim2.new(1, 16, 1, 16)
shadow.Position = UDim2.fromOffset(-8, -4)
shadow.BackgroundColor3 = Color3.new(0, 0, 0)
shadow.BackgroundTransparency = 1
shadow.ZIndex = 0
corner(shadow, 18)

local border = Instance.new("Frame", container)
border.Size = UDim2.new(1, 2, 1, 2)
border.Position = UDim2.fromOffset(-1, -1)
border.BackgroundColor3 = Color3.new(1, 1, 1)
border.BackgroundTransparency = 1
border.ZIndex = 1
corner(border, 13)
local borderGradient = gradient(border)

local main = Instance.new("CanvasGroup", container)
main.Size = UDim2.fromScale(1, 1)
main.BackgroundColor3 = Theme.Bg
main.GroupTransparency = 1
main.ZIndex = 2
corner(main, 12)

local header = Instance.new("Frame", main)
header.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
header.BackgroundTransparency = 1

local icon = Instance.new("Frame", header)
icon.Size = UDim2.fromOffset(32, 32)
icon.Position = UDim2.new(0, 12, 0.5, -16)
icon.BackgroundColor3 = Color3.new(1, 1, 1)
corner(icon, 9)
gradient(icon).Rotation = 45

local iconText = makeLabel(icon, "★", 20, Enum.Font.GothamBold, Color3.new(1, 1, 1))
iconText.Size = UDim2.fromScale(1, 1)
iconText.TextXAlignment = Enum.TextXAlignment.Center

local title = makeLabel(header, "Universal Hub", 16, Enum.Font.GothamBold, Theme.Text)
title.Position = UDim2.fromOffset(54, 9)
title.Size = UDim2.new(1, -120, 0, 18)

local subtitle = makeLabel(header, "Меню управления", 12, Enum.Font.Gotham, Theme.SubText)
subtitle.Position = UDim2.fromOffset(54, 27)
subtitle.Size = UDim2.new(1, -120, 0, 14)

local minimizeBtn = Instance.new("TextButton", header)
minimizeBtn.Size = UDim2.fromOffset(28, 28)
minimizeBtn.AnchorPoint = Vector2.new(1, 0.5)
minimizeBtn.Position = UDim2.new(1, -12, 0.5, 0)
minimizeBtn.BackgroundColor3 = Theme.Panel
minimizeBtn.AutoButtonColor = false
minimizeBtn.Text = "−"
minimizeBtn.TextColor3 = Theme.Text
minimizeBtn.Font = Enum.Font.GothamBold
minimizeBtn.TextSize = 18
corner(minimizeBtn, 8)

local divider = Instance.new("Frame", main)
divider.Position = UDim2.fromOffset(12, HEADER_HEIGHT)
divider.Size = UDim2.new(1, -24, 0, 1)
divider.BackgroundColor3 = Color3.new(1, 1, 1)
divider.BorderSizePixel = 0
local dividerGradient = gradient(divider)
dividerGradient.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.3), NumberSequenceKeypoint.new(1, 1)})

local content = Instance.new("ScrollingFrame", main)
content.Position = UDim2.fromOffset(12, HEADER_HEIGHT + 8)
content.Size = UDim2.new(1, -24, 1, -(HEADER_HEIGHT + 16))
content.BackgroundTransparency = 1
content.ScrollBarThickness = 4
content.CanvasSize = UDim2.new(0,0,0, 600)

local listLayout = Instance.new("UIListLayout", content)
listLayout.Padding = UDim.new(0, 8)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder

-- Toggle UI Builder
local function createToggleRow(parent, text, keyText, order)
	local row = Instance.new("TextButton", parent)
	row.Size = UDim2.new(1, -8, 0, 44)
	row.BackgroundColor3 = Theme.Panel
	row.AutoButtonColor = false
	row.Text = ""
	row.LayoutOrder = order
	corner(row, 10)
	stroke(row, Theme.Stroke, 1, 0.65)

	local lbl = makeLabel(row, text, 14, Enum.Font.GothamMedium, Theme.Text)
	lbl.Position = UDim2.fromOffset(14, 0)
	lbl.Size = UDim2.new(1, -120, 1, 0)

	if keyText then
		local badge = makeLabel(row, keyText, 12, Enum.Font.GothamBold, Theme.SubText)
		badge.Size = UDim2.fromOffset(24, 20)
		badge.AnchorPoint = Vector2.new(1, 0.5)
		badge.Position = UDim2.new(1, -68, 0.5, 0)
		badge.BackgroundTransparency = 0
		badge.BackgroundColor3 = Theme.Bg
		badge.TextXAlignment = Enum.TextXAlignment.Center
		corner(badge, 5)
		stroke(badge, Theme.Stroke, 1, 0.4)
	end

	local track = Instance.new("Frame", row)
	track.Size = UDim2.fromOffset(44, 24)
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.Position = UDim2.new(1, -14, 0.5, 0)
	track.BackgroundColor3 = Theme.Off
	corner(track, 12)

	local fill = Instance.new("Frame", track)
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.BackgroundTransparency = 1
	corner(fill, 12)
	gradient(fill)

	local knob = Instance.new("Frame", track)
	knob.Size = UDim2.fromOffset(18, 18)
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.Position = UDim2.new(0, 3, 0.5, 0)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.ZIndex = 2
	corner(knob, 9)

	local state
	local function setToggle(newState)
		if newState == state then return end
		state = newState
		tween(fill, 0.25, { BackgroundTransparency = newState and 0 or 1 })
		tween(knob, 0.35, { Position = newState and UDim2.new(1, -21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0) }, Enum.EasingStyle.Back)
	end

	row.MouseEnter:Connect(function() tween(row, 0.15, { BackgroundColor3 = Theme.PanelHover }) end)
	row.MouseLeave:Connect(function() tween(row, 0.15, { BackgroundColor3 = Theme.Panel }) end)

	return row, setToggle
end

-- Секция Передвижения
local sectionMove = makeLabel(content, "ПЕРЕДВИЖЕНИЕ", 12, Enum.Font.GothamBold, Theme.SubText)
sectionMove.LayoutOrder = 1
sectionMove.Size = UDim2.new(1, 0, 0, 20)

local jumpRow, setJumpToggle = createToggleRow(content, "Бесконечный прыжок", nil, 2)
local flyRow, setFlyToggle = createToggleRow(content, "Полёт", "F", 3)

local speedCard = Instance.new("Frame", content)
speedCard.Size = UDim2.new(1, -8, 0, 66)
speedCard.BackgroundColor3 = Theme.Panel
speedCard.LayoutOrder = 4
corner(speedCard, 10)
stroke(speedCard, Theme.Stroke, 1, 0.65)

local speedTitle = makeLabel(speedCard, "Скорость полёта", 14, Enum.Font.GothamMedium, Theme.Text)
speedTitle.Position = UDim2.fromOffset(14, 8)
speedTitle.Size = UDim2.new(1, -90, 0, 20)
local speedValue = makeLabel(speedCard, "", 15, Enum.Font.GothamBold, Color3.new(1, 1, 1))
speedValue.Position = UDim2.new(1, -74, 0, 8)
speedValue.Size = UDim2.fromOffset(60, 20)
speedValue.TextXAlignment = Enum.TextXAlignment.Right
gradient(speedValue)

local sTrack = Instance.new("Frame", speedCard)
sTrack.Position = UDim2.fromOffset(14, 42)
sTrack.Size = UDim2.new(1, -28, 0, 6)
sTrack.BackgroundColor3 = Theme.Off
corner(sTrack, 3)

local sFill = Instance.new("Frame", sTrack)
sFill.Size = UDim2.fromScale(0, 1)
sFill.BackgroundColor3 = Color3.new(1, 1, 1)
corner(sFill, 3)
gradient(sFill)

local sKnob = Instance.new("Frame", sTrack)
sKnob.Size = UDim2.fromOffset(16, 16)
sKnob.AnchorPoint = Vector2.new(0.5, 0.5)
sKnob.Position = UDim2.fromScale(0, 0.5)
sKnob.BackgroundColor3 = Color3.new(1, 1, 1)
sKnob.ZIndex = 3
corner(sKnob, 8)
stroke(sKnob, Theme.Accent1, 2, 0)

local sHitArea = Instance.new("TextButton", sTrack)
sHitArea.Size = UDim2.new(1, 16, 0, 26)
sHitArea.Position = UDim2.new(0, -8, 0.5, -13)
sHitArea.BackgroundTransparency = 1
sHitArea.Text = ""
sHitArea.ZIndex = 4

-- Секция Fling
local sectionFling = makeLabel(content, "FLING ИГРОКОВ", 12, Enum.Font.GothamBold, Theme.SubText)
sectionFling.LayoutOrder = 5
sectionFling.Size = UDim2.new(1, 0, 0, 20)
sectionFling.Position = UDim2.new(0,0,0,10)

local FlingStatus = makeLabel(content, "Выберите цели", 13, Enum.Font.Gotham, Theme.Text)
FlingStatus.LayoutOrder = 6
FlingStatus.Size = UDim2.new(1, 0, 0, 15)

local PlayerListFrame = Instance.new("Frame", content)
PlayerListFrame.Size = UDim2.new(1, -8, 0, 150)
PlayerListFrame.BackgroundColor3 = Theme.Panel
PlayerListFrame.LayoutOrder = 7
corner(PlayerListFrame, 10)
stroke(PlayerListFrame, Theme.Stroke, 1, 0.65)

local PlayerScrollFrame = Instance.new("ScrollingFrame", PlayerListFrame)
PlayerScrollFrame.Size = UDim2.new(1, -10, 1, -10)
PlayerScrollFrame.Position = UDim2.new(0, 5, 0, 5)
PlayerScrollFrame.BackgroundTransparency = 1
PlayerScrollFrame.BorderSizePixel = 0
PlayerScrollFrame.ScrollBarThickness = 4

local ActionButtons = Instance.new("Frame", content)
ActionButtons.Size = UDim2.new(1, -8, 0, 80)
ActionButtons.BackgroundTransparency = 1
ActionButtons.LayoutOrder = 8

local function makeBtn(p, txt, col, pos, size)
    local b = Instance.new("TextButton", p)
    b.Size = size b.Position = pos
    b.BackgroundColor3 = col
    b.Text = txt
    b.TextColor3 = Color3.new(1,1,1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    corner(b, 8)
    return b
end

local BtnStart = makeBtn(ActionButtons, "START FLING", Theme.On, UDim2.new(0,0,0,0), UDim2.new(0.48, 0, 0, 35))
BtnStart.TextColor3 = Color3.new(0,0,0)
local BtnStop = makeBtn(ActionButtons, "STOP FLING", Theme.Red, UDim2.new(0.52,0,0,0), UDim2.new(0.48, 0, 0, 35))
local BtnSelAll = makeBtn(ActionButtons, "ВЫДЕЛИТЬ ВСЕХ", Theme.Panel, UDim2.new(0,0,0,45), UDim2.new(0.48, 0, 0, 30))
local BtnDeselAll = makeBtn(ActionButtons, "СНЯТЬ ВСЕХ", Theme.Panel, UDim2.new(0.52,0,0,45), UDim2.new(0.48, 0, 0, 30))

---------------------------------------------------------------------
-- Логика UI
---------------------------------------------------------------------
local function refreshSpeed()
	local a = (FlySpeed - MinSpeed) / (MaxSpeed - MinSpeed)
	tween(sFill, 0.08, { Size = UDim2.fromScale(a, 1) })
	tween(sKnob, 0.08, { Position = UDim2.fromScale(a, 0.5) })
	speedValue.Text = tostring(FlySpeed)
end
local function setSpeed(v) FlySpeed = math.clamp(math.floor(v + 0.5), MinSpeed, MaxSpeed) refreshSpeed() end
local sliding = false
local function setSpeedFromX(x) setSpeed(MinSpeed + (MaxSpeed - MinSpeed) * math.clamp((x - sTrack.AbsolutePosition.X) / sTrack.AbsoluteSize.X, 0, 1)) end

sHitArea.InputBegan:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
		sliding = true setSpeedFromX(i.Position.X) tween(sKnob, 0.15, { Size = UDim2.fromOffset(20, 20) })
	end
end)
UserInputService.InputEnded:Connect(function(i)
	if sliding and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then
		sliding = false tween(sKnob, 0.2, { Size = UDim2.fromOffset(16, 16) }, Enum.EasingStyle.Back)
	end
end)

updateMenuUI = function()
	setJumpToggle(InfiniteJumpEnabled)
	setFlyToggle(flying)
	subtitle.Text = flying and "В полёте" or "Меню управления"
end

jumpRow.MouseButton1Click:Connect(function() InfiniteJumpEnabled = not InfiniteJumpEnabled updateMenuUI() end)
flyRow.MouseButton1Click:Connect(toggleFly)

local minimized = false
minimizeBtn.MouseButton1Click:Connect(function()
	minimized = not minimized
	minimizeBtn.Text = minimized and "+" or "−"
	tween(container, 0.35, { Size = UDim2.fromOffset(MENU_WIDTH, minimized and HEADER_HEIGHT or FULL_HEIGHT) })
	tween(divider, 0.2, { BackgroundTransparency = minimized and 1 or 0 })
end)

local menuVisible = false
local function setMenuVisible(v)
	menuVisible = v
	if v then
		container.Visible = true
		tween(uiScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
		tween(main, 0.3, { GroupTransparency = 0 })
		tween(border, 0.3, { BackgroundTransparency = 0.3 })
		tween(shadow, 0.3, { BackgroundTransparency = 0.6 })
	else
		tween(uiScale, 0.2, { Scale = 0.85 })
		tween(main, 0.2, { GroupTransparency = 1 })
		tween(border, 0.2, { BackgroundTransparency = 1 })
		tween(shadow, 0.2, { BackgroundTransparency = 1 })
		task.delay(0.2, function() if not menuVisible then container.Visible = false end end)
	end
end

-- Перетаскивание
local dragging, dragStart, startPos = false, nil, nil
header.InputBegan:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
		dragging = true dragStart = i.Position startPos = container.Position
		i.Changed:Connect(function() if i.UserInputState == Enum.UserInputState.End then dragging = false end end)
	end
end)
UserInputService.InputChanged:Connect(function(i)
	if sliding then setSpeedFromX(i.Position.X)
	elseif dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
		local delta = i.Position - dragStart
		container.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
	end
end)

RunService.RenderStepped:Connect(function(dt) borderGradient.Rotation = (borderGradient.Rotation + dt * 45) % 360 end)

-- Логика списка игроков (Fling)
local function CountSelectedTargets() local c=0 for _ in pairs(SelectedTargets) do c=c+1 end return c end
local function UpdateFlingStatus()
    local count = CountSelectedTargets()
    if FlingActive then FlingStatus.Text = "Flinging: " .. count .. " целей" FlingStatus.TextColor3 = Theme.Red
    else FlingStatus.Text = "Выбрано: " .. count .. " целей" FlingStatus.TextColor3 = Theme.Text end
end

local function RefreshPlayerList()
    for _, child in pairs(PlayerScrollFrame:GetChildren()) do if not child:IsA("UIListLayout") then child:Destroy() end end
    PlayerCheckboxes = {}
    local PListLayout = Instance.new("UIListLayout", PlayerScrollFrame)
    PListLayout.Padding = UDim.new(0, 4)
    
    local PlayerList = Players:GetPlayers()
    table.sort(PlayerList, function(a, b) return a.Name:lower() < b.Name:lower() end)
    
    local ySize = 0
    for _, p in ipairs(PlayerList) do
        if p ~= player then
            local Entry = Instance.new("Frame", PlayerScrollFrame)
            Entry.Size = UDim2.new(1, -10, 0, 26)
            Entry.BackgroundColor3 = Theme.Bg
            corner(Entry, 6)
            
            local Checkbox = Instance.new("TextButton", Entry)
            Checkbox.Size = UDim2.new(0, 20, 0, 20)
            Checkbox.Position = UDim2.new(0, 5, 0.5, -10)
            Checkbox.BackgroundColor3 = Theme.Off
            Checkbox.Text = ""
            corner(Checkbox, 4)
            
            local Checkmark = makeLabel(Checkbox, "✓", 14, Enum.Font.GothamBold, Theme.On)
            Checkmark.Size = UDim2.fromScale(1,1) Checkmark.TextXAlignment = Enum.TextXAlignment.Center
            Checkmark.Visible = SelectedTargets[p.Name] ~= nil
            
            local NLabel = makeLabel(Entry, p.Name, 13, Enum.Font.Gotham, Theme.Text)
            NLabel.Size = UDim2.new(1, -35, 1, 0)
            NLabel.Position = UDim2.new(0, 30, 0, 0)
            
            local ClickArea = Instance.new("TextButton", Entry)
            ClickArea.Size = UDim2.fromScale(1,1) ClickArea.BackgroundTransparency = 1 ClickArea.Text = "" ClickArea.ZIndex = 2
            
            ClickArea.MouseButton1Click:Connect(function()
                if SelectedTargets[p.Name] then SelectedTargets[p.Name] = nil Checkmark.Visible = false
                else SelectedTargets[p.Name] = p Checkmark.Visible = true end
                UpdateFlingStatus()
            end)
            
            PlayerCheckboxes[p.Name] = { Entry = Entry, Checkmark = Checkmark }
            ySize = ySize + 30
        end
    end
    PlayerScrollFrame.CanvasSize = UDim2.new(0, 0, 0, ySize + 5)
end

local function ToggleAllPlayers(sel)
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player then
            local chk = PlayerCheckboxes[p.Name]
            if chk then
                if sel then SelectedTargets[p.Name] = p chk.Checkmark.Visible = true
                else SelectedTargets[p.Name] = nil chk.Checkmark.Visible = false end
            end
        end
    end
    UpdateFlingStatus()
end

local function StartFling()
    if FlingActive then return end
    if CountSelectedTargets() == 0 then
        FlingStatus.Text = "Нет выбранных целей!"
        task.wait(1) UpdateFlingStatus() return
    end
    FlingActive = true UpdateFlingStatus()
    Message("Fling", "Запущен разброс целей", 2)
    spawn(function()
        while FlingActive do
            local validTargets = {}
            for name, p in pairs(SelectedTargets) do
                if p and p.Parent then validTargets[name] = p
                else SelectedTargets[name] = nil if PlayerCheckboxes[name] then PlayerCheckboxes[name].Checkmark.Visible = false end end
            end
            for _, p in pairs(validTargets) do
                if FlingActive then SkidFling(p) task.wait(0.1) else break end
            end
            UpdateFlingStatus() task.wait(0.5)
        end
    end)
end

local function StopFling()
    if not FlingActive then return end
    FlingActive = false UpdateFlingStatus()
    Message("Fling", "Разброс остановлен", 2)
end

BtnStart.MouseButton1Click:Connect(StartFling)
BtnStop.MouseButton1Click:Connect(StopFling)
BtnSelAll.MouseButton1Click:Connect(function() ToggleAllPlayers(true) end)
BtnDeselAll.MouseButton1Click:Connect(function() ToggleAllPlayers(false) end)

Players.PlayerAdded:Connect(RefreshPlayerList)
Players.PlayerRemoving:Connect(function(p)
    if SelectedTargets[p.Name] then SelectedTargets[p.Name] = nil end
    RefreshPlayerList() UpdateFlingStatus()
end)

---------------------------------------------------------------------
-- Инициализация и Хоткеи
---------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(i, gp)
	if gp then return end
	if i.KeyCode == FlyKey then toggleFly()
	elseif i.KeyCode == MenuKey then setMenuVisible(not menuVisible) end
end)

player.CharacterAdded:Connect(function() stopFly() end)

refreshSpeed()
updateMenuUI()
RefreshPlayerList()
UpdateFlingStatus()
setMenuVisible(true)

Message("Успех", "Universal Hub успешно загружен!", 3)
