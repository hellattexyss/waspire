--// COMPLETE FIXED SNIPPET - TYPO FIXED - ALL WORKING

-- Cleanup old GUIs
pcall(function()
    local pg = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
    for _, name in ipairs({"SideDashAssistGUI"}) do
        local g = pg:FindFirstChild(name)
        if g then g:Destroy() end
    end
end)

task.wait(0.1)

-- Services
local PlayersService = game:GetService("Players")
local RunService = game:GetService("RunService")
local InputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local WorkspaceService = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")
local Lighting = game:GetService("Lighting")

local LocalPlayer = PlayersService.LocalPlayer
local CurrentCamera = WorkspaceService.CurrentCamera
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")
local Humanoid = Character:FindFirstChildOfClass("Humanoid")

local function isCharacterDisabled()
    if not (Humanoid and Humanoid.Parent) then return false end
    if Humanoid.Health <= 0 then return true end
    if Humanoid.PlatformStand then return true end
    local success, state = pcall(function() return Humanoid:GetState() end)
    if success and state == Enum.HumanoidStateType.Physics then return true end
    local ragdollValue = Character:FindFirstChild("Ragdoll")
    return ragdollValue and (ragdollValue:IsA("BoolValue") and ragdollValue.Value) and true or false
end

LocalPlayer.CharacterAdded:Connect(function(newCharacter)
    Character = newCharacter
    HumanoidRootPart = newCharacter:WaitForChild("HumanoidRootPart")
    Humanoid = newCharacter:FindFirstChildOfClass("Humanoid")
end)

-- Animations
local ANIMATION_IDS = {
    [10449761463] = {Left = 10480796021, Right = 10480793962, Straight = 10479335397},
    [13076380114] = {Left = 101843860692381, Right = 100087324592640, Straight = 110878031211717}
}
local gameId = game.PlaceId
local currentGameAnimations = ANIMATION_IDS[gameId] or ANIMATION_IDS[13076380114]
local leftAnimationId = currentGameAnimations.Left
local rightAnimationId = currentGameAnimations.Right
local straightAnimationId = currentGameAnimations.Straight

-- Constants
local MAX_TARGET_RANGE = 60
local MIN_DASH_DISTANCE = 1.2
local MAX_DASH_DISTANCE = 60
local MIN_TARGET_DISTANCE = 15
local TARGET_REACH_THRESHOLD = 10
local DASH_SPEED = 240
local DIRECTION_LERP_FACTOR = 0.7
local CAMERA_FOLLOW_DELAY = 0.7
local VELOCITY_PREDICTION_FACTOR = 0.5
local FOLLOW_EASING_POWER = 200
local CIRCLE_COMPLETION_THRESHOLD = 390 / 480
local DASH_GAP = 0.5
local DASH_DEGREE = 105

-- State
local isDashing = false
local sideAnimationTrack = nil
local straightAnimationTrack = nil
local lastButtonPressTime = -math.huge
local isAutoRotateDisabled = false
local autoRotateConnection = nil

-- COOLDOWN SYSTEM (2 seconds)
local DASH_COOLDOWN = 2
local lastDashTime = -math.huge

-- RED BUTTON SIZE STATE
local redButtonSize = 90

local function dashReady()
    return (tick() - lastDashTime) >= DASH_COOLDOWN
end

local function dashRemaining()
    local r = DASH_COOLDOWN - (tick() - lastDashTime)
    return math.max(0, r)
end

-- Dash SFX (non-button)
local dashSound = Instance.new("Sound")
dashSound.Name = "DashSFX"
dashSound.SoundId = "rbxassetid://3084314259"
dashSound.Volume = 2
dashSound.Looped = false
dashSound.Parent = WorkspaceService

-- EXECUTION SOUND
pcall(function()
    local executionSound = Instance.new("Sound")
    executionSound.SoundId = "rbxassetid://115916891254154"
    executionSound.Volume = 1
    executionSound.Parent = WorkspaceService
    task.defer(function()
        pcall(function() executionSound:Play() end)
        task.delay(2.5, function() pcall(function() executionSound:Destroy() end) end)
    end)
end)

local function setupAutoRotateProtection()
    if autoRotateConnection then
        pcall(function() autoRotateConnection:Disconnect() end)
        autoRotateConnection = nil
    end
    local targetHumanoid = Character:FindFirstChildOfClass("Humanoid")
    if targetHumanoid then
        autoRotateConnection = targetHumanoid:GetPropertyChangedSignal("AutoRotate"):Connect(function()
            if isAutoRotateDisabled then
                pcall(function()
                    if targetHumanoid and targetHumanoid.AutoRotate then
                        targetHumanoid.AutoRotate = false
                    end
                end)
            end
        end)
    end
end

setupAutoRotateProtection()
LocalPlayer.CharacterAdded:Connect(function(newCharacter)
    Character = newCharacter
    HumanoidRootPart = newCharacter:WaitForChild("HumanoidRootPart")
    Humanoid = newCharacter:FindFirstChildOfClass("Humanoid")
    task.wait(0.05)
    setupAutoRotateProtection()
end)

-- Math helpers
local function getAngleDifference(angle1, angle2)
    local difference = angle1 - angle2
    while math.pi < difference do difference = difference - 2 * math.pi end
    while difference < -math.pi do difference = difference + 2 * math.pi end
    return difference
end

local function easeInOutCubic(progress)
    return 1 - (1 - math.clamp(progress, 0, 1)) ^ 3
end

-- Blur effect
local blur = Instance.new("BlurEffect")
blur.Size = 0
blur.Parent = Lighting

-- Notifications
local function notify(title, text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = 3,
        })
    end)
end

notify("Side Dash Assist v2.0", "Loaded! Press E or click the red dash button")

-- ============ DASH LOGIC ============

local function getHumanoidAndAnimator()
    if not (Character and Character.Parent) then return nil, nil end
    local foundHumanoid = Character:FindFirstChildOfClass("Humanoid")
    if not foundHumanoid then return nil, nil end
    local animator = foundHumanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Name = "Animator"
        animator.Parent = foundHumanoid
    end
    return foundHumanoid, animator
end

local function playSideAnimation(isLeftDirection)
    pcall(function()
        if sideAnimationTrack and sideAnimationTrack.IsPlaying then
            sideAnimationTrack:Stop()
        end
    end)
    sideAnimationTrack = nil

    local targetHumanoid, animator = getHumanoidAndAnimator()
    if targetHumanoid and animator then
        local animationId = isLeftDirection and leftAnimationId or rightAnimationId
        local animationInstance = Instance.new("Animation")
        animationInstance.Name = "CircularSideAnim"
        animationInstance.AnimationId = "rbxassetid://" .. tostring(animationId)

        local success, loadedAnimation = pcall(function()
            return animator:LoadAnimation(animationInstance)
        end)
        if success and loadedAnimation then
            sideAnimationTrack = loadedAnimation
            loadedAnimation.Priority = Enum.AnimationPriority.Action
            pcall(function() loadedAnimation.Looped = false end)
            pcall(function() loadedAnimation:Play() end)
        end

        delay(0.7, function()
            pcall(function()
                if loadedAnimation and loadedAnimation.IsPlaying then
                    loadedAnimation:Stop()
                end
            end)
            pcall(function() animationInstance:Destroy() end)
        end)
    end
end

local function findNearestTarget(maxRange)
    maxRange = maxRange or MAX_TARGET_RANGE
    local nearestTarget, nearestDistance = nil, math.huge
    if not HumanoidRootPart then return nil end
    local rootPosition = HumanoidRootPart.Position

    for _, player in pairs(PlayersService:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character:FindFirstChild("Humanoid") then
            local playerHumanoid = player.Character:FindFirstChild("Humanoid")
            if playerHumanoid and playerHumanoid.Health > 0 then
                local distance = (player.Character.HumanoidRootPart.Position - rootPosition).Magnitude
                if distance < nearestDistance and distance <= maxRange then
                    nearestTarget = player.Character
                    nearestDistance = distance
                end
            end
        end
    end

    for _, descendant in pairs(WorkspaceService:GetDescendants()) do
        if descendant:IsA("Model") and descendant:FindFirstChild("Humanoid") and descendant:FindFirstChild("HumanoidRootPart") and not PlayersService:GetPlayerFromCharacter(descendant) then
            local npcHumanoid = descendant:FindFirstChild("Humanoid")
            if npcHumanoid and npcHumanoid.Health > 0 then
                local distance = (descendant.HumanoidRootPart.Position - rootPosition).Magnitude
                if distance < nearestDistance and distance <= maxRange then
                    nearestTarget = descendant
                    nearestDistance = distance
                end
            end
        end
    end

    return nearestTarget, nearestDistance
end

local function calculateDashDuration(speedSliderValue)
    local clampedValue = math.clamp(speedSliderValue or 49, 0, 100) / 100
    local baseMin = 1.0
    local baseMax = 0.10
    return baseMin + (baseMax - baseMin) * clampedValue
end

-- ============ DASH EXECUTION ============

-- Settings with DASH DISTANCE
local settingsValues = {["Dash speed"] = 49, ["Dash Degrees"] = 32, ["Dash distance"] = 20}
local lockedTargetPlayer = nil
local isSliding = false

PlayersService.PlayerRemoving:Connect(function(removedPlayer)
    if lockedTargetPlayer == removedPlayer then
        lockedTargetPlayer = nil
    end
end)

local function getCurrentTarget()
    if lockedTargetPlayer then
        if lockedTargetPlayer.Character and lockedTargetPlayer.Character.Parent then
            local targetCharacter = lockedTargetPlayer.Character
            local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")
            local targetHumanoid = targetCharacter:FindFirstChild("Humanoid")
            if targetRoot and targetHumanoid and targetHumanoid.Health > 0 and HumanoidRootPart then
                if (targetRoot.Position - HumanoidRootPart.Position).Magnitude <= MAX_TARGET_RANGE then
                    return nil
                else
                    return targetCharacter
                end
            end
            lockedTargetPlayer = nil
        else
            lockedTargetPlayer = nil
        end
    end
    return findNearestTarget(MAX_TARGET_RANGE)
end

local function aimCharacterAtTarget(targetPosition, lerpFactor)
    lerpFactor = lerpFactor or 0.7
    pcall(function()
        local characterPosition = HumanoidRootPart.Position
        local characterLookVector = HumanoidRootPart.CFrame.LookVector
        local directionToTarget = targetPosition - characterPosition
        local horizontalDirection = Vector3.new(directionToTarget.X, 0, directionToTarget.Z)
        if horizontalDirection.Magnitude < 0.001 then
            horizontalDirection = Vector3.new(1, 0, 0)
        end
        local targetDirection = horizontalDirection.Unit
        local finalLookVector = Vector3.new(targetDirection.X, characterLookVector.Y, targetDirection.Z)
        if finalLookVector.Magnitude < 0.001 then
            finalLookVector = Vector3.new(targetDirection.X, characterLookVector.Y, targetDirection.Z + 0.0001)
        end
        local lerpedDirection = characterLookVector:Lerp(finalLookVector.Unit, lerpFactor)
        if lerpedDirection.Magnitude < 0.001 then
            lerpedDirection = Vector3.new(finalLookVector.Unit.X, characterLookVector.Y, finalLookVector.Unit.Z)
        end
        HumanoidRootPart.CFrame = CFrame.new(characterPosition, characterPosition + lerpedDirection.Unit)
    end)
end

local function performDashMovement(targetRootPart, dashSpeed)
    dashSpeed = dashSpeed or DASH_SPEED
    local attachment = Instance.new("Attachment")
    attachment.Name = "DashAttach"
    attachment.Parent = HumanoidRootPart
    local linearVelocity = Instance.new("LinearVelocity")
    linearVelocity.Name = "DashLinearVelocity"
    linearVelocity.Attachment0 = attachment
    linearVelocity.MaxForce = math.huge
    linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
    linearVelocity.Parent = HumanoidRootPart

    local hasReachedTarget = false
    local isActive = true
    local heartbeatConnection
    heartbeatConnection = RunService.Heartbeat:Connect(function()
        if isActive and targetRootPart and targetRootPart.Parent and HumanoidRootPart and HumanoidRootPart.Parent then
            local targetPosition = targetRootPart.Position
            local directionToTarget = targetPosition - HumanoidRootPart.Position
            local horizontalDirection = Vector3.new(directionToTarget.X, 0, directionToTarget.Z)
            if horizontalDirection.Magnitude <= TARGET_REACH_THRESHOLD then
                linearVelocity.VectorVelocity = horizontalDirection.Unit * dashSpeed
                pcall(function()
                    if horizontalDirection.Magnitude > 0.001 then
                        HumanoidRootPart.CFrame = CFrame.new(HumanoidRootPart.Position, HumanoidRootPart.Position + horizontalDirection.Unit)
                    end
                end)
                pcall(function() aimCharacterAtTarget(targetPosition, 0.56) end)
            else
                hasReachedTarget = true
                isActive = false
                heartbeatConnection:Disconnect()
                pcall(function() linearVelocity:Destroy() end)
                pcall(function() attachment:Destroy() end)
            end
        else
            isActive = false
            heartbeatConnection:Disconnect()
            pcall(function() linearVelocity:Destroy() end)
            pcall(function() attachment:Destroy() end)
        end
    end)
end

local function smoothlyAimAtTarget(targetRootPart, duration)
    duration = duration or CAMERA_FOLLOW_DELAY
    if targetRootPart and targetRootPart.Parent then
        local startTime = tick()
        local aimTweenConnection
        aimTweenConnection = RunService.Heartbeat:Connect(function()
            if targetRootPart and targetRootPart.Parent then
                local currentTime = tick()
                local progress = math.clamp((currentTime - startTime) / duration, 0, 1)
                local easedProgress = 1 - (1 - progress) ^ math.max(1, FOLLOW_EASING_POWER)
                local targetPosition = targetRootPart.Position
                local targetVelocity = Vector3.new(0, 0, 0)
                pcall(function()
                    targetVelocity = targetRootPart:GetVelocity() or Vector3.new(0, 0, 0)
                end)
                local predictedPosition = targetPosition + Vector3.new(targetVelocity.X, 0, targetVelocity.Z) * VELOCITY_PREDICTION_FACTOR
                pcall(function()
                    local characterPosition = HumanoidRootPart.Position
                    local characterLookVector = HumanoidRootPart.CFrame.LookVector
                    local directionToTarget = predictedPosition - characterPosition
                    local horizontalDirection = Vector3.new(directionToTarget.X, 0, directionToTarget.Z)
                    if horizontalDirection.Magnitude < 0.001 then
                        horizontalDirection = Vector3.new(1, 0, 0)
                    end
                    local targetDirection = horizontalDirection.Unit
                    local finalLookVector = characterLookVector:Lerp(Vector3.new(targetDirection.X, characterLookVector.Y, targetDirection.Z).Unit, easedProgress)
                    HumanoidRootPart.CFrame = CFrame.new(characterPosition, characterPosition + finalLookVector)
                end)
                if progress >= 1 then
                    aimTweenConnection:Disconnect()
                end
            else
                aimTweenConnection:Disconnect()
            end
        end)
    end
end

local m1ToggleEnabled = false
local dashToggleEnabled = false

local function communicateWithServer(communicationData)
    pcall(function()
        local playerCharacter = LocalPlayer.Character
        if playerCharacter and playerCharacter:FindFirstChild("Communicate") then
            playerCharacter.Communicate:FireServer(unpack(communicationData))
        end
    end)
end

-- MAIN CIRCULAR DASH WITH DISTANCE CHECK
local function performCircularDash(targetCharacter)
    if isDashing or not targetCharacter or not targetCharacter:FindFirstChild("HumanoidRootPart") or not HumanoidRootPart then
        return
    end

    if not dashReady() then
        return
    end
    
    local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")
    if targetRoot then
        local distance = (targetRoot.Position - HumanoidRootPart.Position).Magnitude
        if distance > settingsValues["Dash distance"] then
            notify("Out of Range", "Target is " .. math.floor(distance) .. " studs away. Max: " .. settingsValues["Dash distance"] .. " studs")
            return
        end
    end
    
    lastDashTime = tick()

    isDashing = true
    local characterHumanoid = Character:FindFirstChildOfClass("Humanoid")
    local originalAutoRotate = characterHumanoid and characterHumanoid.AutoRotate
    if characterHumanoid then
        isAutoRotateDisabled = true
        pcall(function() characterHumanoid.AutoRotate = false end)
    end

    local function restoreAutoRotate()
        if characterHumanoid and originalAutoRotate ~= nil then
            isAutoRotateDisabled = false
            pcall(function() characterHumanoid.AutoRotate = originalAutoRotate end)
        end
    end

    local dashDuration = calculateDashDuration(settingsValues["Dash speed"])

-- Dynamic dash angle based on distance
local distance = (targetRoot.Position - HumanoidRootPart.Position).Magnitude
local dashAngle

if distance <= 8 then
    dashAngle = 190
else
    dashAngle = 110
end

local dashAngleRad = math.rad(dashAngle)
local dashDistance = DASH_GAP
    if MIN_TARGET_DISTANCE < (targetRoot.Position - HumanoidRootPart.Position).Magnitude then
        performDashMovement(targetRoot, DASH_SPEED)
    end

    if targetRoot and targetRoot.Parent and HumanoidRootPart and HumanoidRootPart.Parent then
        local snapshotTargetPosition = targetRoot.Position
        local characterPosition = HumanoidRootPart.Position
        local characterRightVector = HumanoidRootPart.CFrame.RightVector
        local directionToTarget = targetRoot.Position - HumanoidRootPart.Position
        if directionToTarget.Magnitude < 0.001 then
            directionToTarget = HumanoidRootPart.CFrame.LookVector
        end
        local isLeftDirection = characterRightVector:Dot(directionToTarget.Unit) < 0
        playSideAnimation(isLeftDirection)
        local directionMultiplier = isLeftDirection and 1 or -1
        local angleToTarget = math.atan2(characterPosition.Z - snapshotTargetPosition.Z, characterPosition.X - snapshotTargetPosition.X)
        local horizontalDistance = (Vector3.new(characterPosition.X, 0, characterPosition.Z) - Vector3.new(snapshotTargetPosition.X, 0, snapshotTargetPosition.Z)).Magnitude
        local clampedDistance = math.clamp(horizontalDistance, MIN_DASH_DISTANCE, MAX_DASH_DISTANCE)

        local startTime = tick()
        local movementConnection
        local hasStartedAim = false
        local hasCompletedCircle = false
        local shouldEndDash = false
        local dashEnded = false

        local function startDashEndSequence()
            if not hasCompletedCircle then
                hasCompletedCircle = true
                task.delay(CAMERA_FOLLOW_DELAY, function()
                    shouldEndDash = true
                    restoreAutoRotate()
                    lastButtonPressTime = tick()
                    if dashEnded then
                        isDashing = false
                    end
                end)
            end
        end

        if m1ToggleEnabled then
            communicateWithServer({Mobile = true, Goal = "LeftClick"})
            task.delay(0.05, function()
                communicateWithServer({Goal = "LeftClickRelease", Mobile = true})
            end)
        end

        if dashToggleEnabled then
            communicateWithServer({Dash = Enum.KeyCode.W, Key = Enum.KeyCode.Q, Goal = "KeyPress"})
        end

        movementConnection = RunService.Heartbeat:Connect(function()
            local currentTime = tick()
            local progress = math.clamp((currentTime - startTime) / dashDuration, 0, 1)
            local easedProgress = easeInOutCubic(progress)
            local aimProgress = math.clamp(progress / 1.5, 0, 1)
            local currentRadius = clampedDistance + (dashDistance - clampedDistance) * easeInOutCubic(aimProgress)
            local clampedRadius = math.clamp(currentRadius, MIN_DASH_DISTANCE, MAX_DASH_DISTANCE)
            local currentTargetPosition = snapshotTargetPosition
            local playerGroundY = HumanoidRootPart.Position.Y
            local currentAngle = angleToTarget + (directionMultiplier * dashAngleRad * easeInOutCubic(progress))
            local circleX = currentTargetPosition.X + clampedRadius * math.cos(currentAngle)
            local circleZ = currentTargetPosition.Z + clampedRadius * math.sin(currentAngle)
            local newPosition = Vector3.new(circleX, playerGroundY, circleZ)

            local angleToTargetPosition = math.atan2(currentTargetPosition.Z - newPosition.Z, currentTargetPosition.X - newPosition.X)
            local characterAngle = math.atan2(HumanoidRootPart.CFrame.LookVector.Z, HumanoidRootPart.CFrame.LookVector.X)
            local finalCharacterAngle = characterAngle + getAngleDifference(angleToTargetPosition, characterAngle) * DIRECTION_LERP_FACTOR
            pcall(function()
                HumanoidRootPart.CFrame = CFrame.new(newPosition, newPosition + Vector3.new(math.cos(finalCharacterAngle), 0, math.sin(finalCharacterAngle)))
            end)

            if not hasStartedAim and CIRCLE_COMPLETION_THRESHOLD <= easedProgress then
                hasStartedAim = true
                pcall(function() smoothlyAimAtTarget(targetRoot, CAMERA_FOLLOW_DELAY) end)
                startDashEndSequence()
            end

            if progress >= 1 then
                movementConnection:Disconnect()
                pcall(function()
                    if sideAnimationTrack and sideAnimationTrack.IsPlaying then
                        sideAnimationTrack:Stop()
                    end
                end)
                sideAnimationTrack = nil
                if not hasStartedAim then
                    hasStartedAim = true
                    pcall(function() smoothlyAimAtTarget(targetRoot, CAMERA_FOLLOW_DELAY) end)
                end
                startDashEndSequence()
            end
        end)

        dashEnded = true
        if shouldEndDash then
            isDashing = false
        end
    else
        restoreAutoRotate()
        isDashing = false
    end
end

-- E key
InputService.InputBegan:Connect(function(inp, gp)
    if gp or isDashing or isCharacterDisabled() then return end
    if inp.UserInputType == Enum.UserInputType.Keyboard and inp.KeyCode == Enum.KeyCode.E then
        local target = getCurrentTarget()
        if target then
            performCircularDash(target)
        else
            notify("No Target", "No enemies in range!")
        end
    end
end)

-- ============ GUI ============

local gui = Instance.new("ScreenGui")
gui.Name = "SideDashAssistGUI"
gui.ResetOnSpawn = false
gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

-- Sounds
local uiClickSound = Instance.new("Sound")
uiClickSound.Name = "UIClickSound"
uiClickSound.SoundId = "rbxassetid://6042053626"
uiClickSound.Volume = 0.7
uiClickSound.Parent = gui

local dashClickSound = Instance.new("Sound")
dashClickSound.Name = "DashClickSound"
dashClickSound.SoundId = "rbxassetid://9080070218"
dashClickSound.Volume = 1
dashClickSound.Parent = gui

local loadSound = Instance.new("Sound")
loadSound.Name = "LoadSound"
loadSound.SoundId = "rbxassetid://87437544236708"
loadSound.Volume = 1
loadSound.Parent = gui

-- Main frame
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 380, 0, 140)
mainFrame.Position = UDim2.new(0.5, -190, 0.12, 0)
mainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
mainFrame.BackgroundTransparency = 1
mainFrame.BorderSizePixel = 0
mainFrame.Visible = false
mainFrame.Parent = gui
mainFrame.Draggable = true

local mainCorner = Instance.new("UICorner", mainFrame)
mainCorner.CornerRadius = UDim.new(0, 20)

local mainBgGradient = Instance.new("UIGradient")
mainBgGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(25, 5, 5)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(15, 15, 15)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0))
})
mainBgGradient.Rotation = 90
mainBgGradient.Parent = mainFrame

local borderFrame = Instance.new("Frame")
borderFrame.Name = "BorderFrame"
borderFrame.Size = UDim2.new(1, 8, 1, 8)
borderFrame.Position = UDim2.new(0, -4, 0, -4)
borderFrame.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
borderFrame.BackgroundTransparency = 1
borderFrame.BorderSizePixel = 0
borderFrame.ZIndex = 0
borderFrame.Parent = mainFrame

local borderCorner = Instance.new("UICorner", borderFrame)
borderCorner.CornerRadius = UDim.new(0, 24)

local borderGradient = Instance.new("UIGradient")
borderGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(120, 0, 0)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(26, 26, 26))
})
borderGradient.Rotation = 45
borderGradient.Parent = borderFrame

local headerFrame = Instance.new("Frame")
headerFrame.Size = UDim2.new(1, 0, 0, 50)
headerFrame.BackgroundTransparency = 1
headerFrame.Parent = mainFrame

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(0, 190, 0, 30)
titleLabel.Position = UDim2.new(0, 20, 0, 10)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Side Dash Assist"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextSize = 23
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.TextStrokeTransparency = 0.7
titleLabel.Parent = headerFrame

local versionLabel = Instance.new("TextLabel")
versionLabel.Size = UDim2.new(0, 55, 0, 24)
versionLabel.Position = UDim2.new(0, 215, 0, 13)
versionLabel.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
versionLabel.BorderSizePixel = 0
versionLabel.Text = "v2.0"
versionLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
versionLabel.TextSize = 13
versionLabel.Font = Enum.Font.GothamBold
versionLabel.Parent = headerFrame
Instance.new("UICorner", versionLabel).CornerRadius = UDim.new(0, 8)

local authorLabel = Instance.new("TextLabel")
authorLabel.Size = UDim2.new(1, -40, 0, 17)
authorLabel.Position = UDim2.new(0, 20, 0, 32)
authorLabel.BackgroundTransparency = 1
authorLabel.Text = "by CPS Network"
authorLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
authorLabel.TextSize = 13
authorLabel.Font = Enum.Font.GothamMedium
authorLabel.TextXAlignment = Enum.TextXAlignment.Left
authorLabel.TextTransparency = 0.28
authorLabel.Parent = headerFrame

-- Close minimize
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 35, 0, 35)
closeBtn.Position = UDim2.new(1, -45, 0, 7)
closeBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Text = "X"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextColor3 = Color3.fromRGB(0, 0, 0)
closeBtn.TextSize = 19
closeBtn.BorderSizePixel = 0
closeBtn.Style = Enum.ButtonStyle.Custom
closeBtn.Parent = mainFrame
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 10)

local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Size = UDim2.new(0, 35, 0, 35)
minimizeBtn.Position = UDim2.new(1, -85, 0, 7)
minimizeBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
minimizeBtn.Text = "_"
minimizeBtn.Font = Enum.Font.GothamBold
minimizeBtn.TextColor3 = Color3.fromRGB(0, 0, 0)
minimizeBtn.TextSize = 22
minimizeBtn.BorderSizePixel = 0
minimizeBtn.Style = Enum.ButtonStyle.Custom
minimizeBtn.Parent = mainFrame
Instance.new("UICorner", minimizeBtn).CornerRadius = UDim.new(0, 10)

-- Settings button
local settingsBtn = Instance.new("TextButton")
settingsBtn.Size = UDim2.new(0, 36, 0, 36)
settingsBtn.Position = UDim2.new(0, 10, 1, -46)
settingsBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
settingsBtn.Text = "⚙️"
settingsBtn.Font = Enum.Font.GothamBold
settingsBtn.TextColor3 = Color3.fromRGB(0, 0, 0)
settingsBtn.TextSize = 19
settingsBtn.BorderSizePixel = 0
settingsBtn.Style = Enum.ButtonStyle.Custom
settingsBtn.Parent = mainFrame
Instance.new("UICorner", settingsBtn).CornerRadius = UDim.new(1, 0)

-- KEYBINDS BUTTON
local keybindsBtn = Instance.new("TextButton")
keybindsBtn.Size = UDim2.new(0, 36, 0, 36)
keybindsBtn.Position = UDim2.new(0, 55, 1, -46)
keybindsBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
keybindsBtn.Text = "⌨️"
keybindsBtn.Font = Enum.Font.GothamBold
keybindsBtn.TextColor3 = Color3.fromRGB(0, 0, 0)
keybindsBtn.TextSize = 19
keybindsBtn.BorderSizePixel = 0
keybindsBtn.Style = Enum.ButtonStyle.Custom
keybindsBtn.Parent = mainFrame
Instance.new("UICorner", keybindsBtn).CornerRadius = UDim.new(1, 0)

local discordBtn = Instance.new("TextButton")
discordBtn.Name = "DiscordButton"
discordBtn.Size = UDim2.new(0, 100, 0, 32)
discordBtn.Position = UDim2.new(1, -245, 1, -44)
discordBtn.BackgroundColor3 = Color3.fromRGB(88, 101, 242)
discordBtn.BorderSizePixel = 0
discordBtn.Text = "Discord"
discordBtn.Font = Enum.Font.GothamBold
discordBtn.TextSize = 14
discordBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
discordBtn.Style = Enum.ButtonStyle.Custom
discordBtn.Parent = mainFrame
Instance.new("UICorner", discordBtn).CornerRadius = UDim.new(0, 10)

local discordGradient = Instance.new("UIGradient", discordBtn)
discordGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 135, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 72, 220))
})
discordGradient.Rotation = 90

local ytBtn = Instance.new("TextButton")
ytBtn.Name = "YouTubeButton"
ytBtn.Size = UDim2.new(0, 100, 0, 32)
ytBtn.Position = UDim2.new(1, -130, 1, -44)
ytBtn.BackgroundColor3 = Color3.fromRGB(220, 0, 0)
ytBtn.BorderSizePixel = 0
ytBtn.Text = "YouTube"
ytBtn.Font = Enum.Font.GothamBold
ytBtn.TextSize = 14
ytBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ytBtn.Style = Enum.ButtonStyle.Custom
ytBtn.Parent = mainFrame
Instance.new("UICorner", ytBtn).CornerRadius = UDim.new(0, 10)

local ytGradient = Instance.new("UIGradient", ytBtn)
ytGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 0, 0))
})
ytGradient.Rotation = 90

-- SETTINGS OVERLAY
local settingsOverlay = Instance.new("Frame")
settingsOverlay.Name = "SettingsOverlay"
settingsOverlay.Size = UDim2.new(0, 320, 0, 400)
settingsOverlay.Position = UDim2.new(0, 20, 0.1, 0)
settingsOverlay.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
settingsOverlay.BackgroundTransparency = 0
settingsOverlay.BorderSizePixel = 0
settingsOverlay.Visible = false
settingsOverlay.Parent = gui
settingsOverlay.Draggable = false
Instance.new("UICorner", settingsOverlay).CornerRadius = UDim.new(0, 16)

local overlayGradient = Instance.new("UIGradient", settingsOverlay)
overlayGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(25, 5, 5)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(15, 15, 15)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0))
})
overlayGradient.Rotation = 90

local settingsTitle = Instance.new("TextLabel")
settingsTitle.Size = UDim2.new(1, -60, 0, 40)
settingsTitle.Position = UDim2.new(0, 16, 0, 8)
settingsTitle.BackgroundTransparency = 1
settingsTitle.Text = "Settings"
settingsTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
settingsTitle.TextSize = 20
settingsTitle.Font = Enum.Font.GothamBold
settingsTitle.TextXAlignment = Enum.TextXAlignment.Left
settingsTitle.Parent = settingsOverlay

local settingsCloseBtn = Instance.new("TextButton")
settingsCloseBtn.Size = UDim2.new(0, 30, 0, 30)
settingsCloseBtn.Position = UDim2.new(1, -40, 0, 8)
settingsCloseBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
settingsCloseBtn.Text = "X"
settingsCloseBtn.Font = Enum.Font.GothamBold
settingsCloseBtn.TextColor3 = Color3.fromRGB(0, 0, 0)
settingsCloseBtn.TextSize = 18
settingsCloseBtn.BorderSizePixel = 0
settingsCloseBtn.Style = Enum.ButtonStyle.Custom
settingsCloseBtn.Parent = settingsOverlay
Instance.new("UICorner", settingsCloseBtn).CornerRadius = UDim.new(0, 8)

-- DASH DISTANCE BUTTON
local dashDistanceLabel = Instance.new("TextLabel")
dashDistanceLabel.Size = UDim2.new(1, -32, 0, 25)
dashDistanceLabel.Position = UDim2.new(0, 16, 0, 55)
dashDistanceLabel.BackgroundTransparency = 1
dashDistanceLabel.Text = "Dash Distance:"
dashDistanceLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
dashDistanceLabel.TextSize = 13
dashDistanceLabel.Font = Enum.Font.Gotham
dashDistanceLabel.TextXAlignment = Enum.TextXAlignment.Left
dashDistanceLabel.Parent = settingsOverlay

local dashDistanceButton = Instance.new("TextButton")
dashDistanceButton.Size = UDim2.new(1, -32, 0, 45)
dashDistanceButton.Position = UDim2.new(0, 16, 0, 85)
dashDistanceButton.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
dashDistanceButton.BorderSizePixel = 0
dashDistanceButton.Text = settingsValues["Dash distance"] .. " studs (Click to increase)"
dashDistanceButton.TextColor3 = Color3.fromRGB(255, 255, 255)
dashDistanceButton.TextSize = 14
dashDistanceButton.Font = Enum.Font.GothamBold
dashDistanceButton.Style = Enum.ButtonStyle.Custom
dashDistanceButton.Parent = settingsOverlay
Instance.new("UICorner", dashDistanceButton).CornerRadius = UDim.new(0, 10)

dashDistanceButton.MouseButton1Click:Connect(function()
    uiClickSound:Play()
    if settingsValues["Dash distance"] < 30 then
        settingsValues["Dash distance"] = settingsValues["Dash distance"] + 5
        if settingsValues["Dash distance"] > 30 then
            settingsValues["Dash distance"] = 30
        end
    else
        settingsValues["Dash distance"] = 10
    end
    dashDistanceButton.Text = settingsValues["Dash distance"] .. " studs (Click to increase)"
end)

local infoFrame = Instance.new("Frame")
infoFrame.Size = UDim2.new(1, -32, 0, 200)
infoFrame.Position = UDim2.new(0, 16, 0, 150)
infoFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
infoFrame.BorderSizePixel = 0
infoFrame.Parent = settingsOverlay
Instance.new("UICorner", infoFrame).CornerRadius = UDim.new(0, 12)

local infoTitle = Instance.new("TextLabel")
infoTitle.Size = UDim2.new(1, -20, 0, 30)
infoTitle.Position = UDim2.new(0, 10, 0, 8)
infoTitle.BackgroundTransparency = 1
infoTitle.Text = "How it Works:"
infoTitle.TextColor3 = Color3.fromRGB(230, 230, 230)
infoTitle.TextSize = 14
infoTitle.Font = Enum.Font.GothamBold
infoTitle.TextXAlignment = Enum.TextXAlignment.Left
infoTitle.Parent = infoFrame

local infoText1 = Instance.new("TextLabel")
infoText1.Size = UDim2.new(1, -20, 0, 20)
infoText1.Position = UDim2.new(0, 10, 0, 40)
infoText1.BackgroundTransparency = 1
infoText1.Text = "• Select your target range above."
infoText1.TextColor3 = Color3.fromRGB(200, 200, 200)
infoText1.TextSize = 12
infoText1.Font = Enum.Font.Gotham
infoText1.TextXAlignment = Enum.TextXAlignment.Left
infoText1.Parent = infoFrame

local infoText2 = Instance.new("TextLabel")
infoText2.Size = UDim2.new(1, -20, 0, 20)
infoText2.Position = UDim2.new(0, 10, 0, 62)
infoText2.BackgroundTransparency = 1
infoText2.Text = "• 25 studs is suggested."
infoText2.TextColor3 = Color3.fromRGB(200, 200, 200)
infoText2.TextSize = 12
infoText2.Font = Enum.Font.Gotham
infoText2.TextXAlignment = Enum.TextXAlignment.Left
infoText2.Parent = infoFrame

local infoText3 = Instance.new("TextLabel")
infoText3.Size = UDim2.new(1, -20, 0, 20)
infoText3.Position = UDim2.new(0, 10, 0, 84)
infoText3.BackgroundTransparency = 1
infoText3.Text = "• Press E or the mobile button to dash."
infoText3.TextColor3 = Color3.fromRGB(200, 200, 200)
infoText3.TextSize = 12
infoText3.Font = Enum.Font.Gotham
infoText3.TextXAlignment = Enum.TextXAlignment.Left
infoText3.Parent = infoFrame

local infoText4 = Instance.new("TextLabel")
infoText4.Size = UDim2.new(1, -20, 0, 20)
infoText4.Position = UDim2.new(0, 10, 0, 106)
infoText4.BackgroundTransparency = 1
infoText4.Text = "• Added cooldown to the dash :)"
infoText4.TextColor3 = Color3.fromRGB(200, 200, 200)
infoText4.TextSize = 12
infoText4.Font = Enum.Font.Gotham
infoText4.TextXAlignment = Enum.TextXAlignment.Left
infoText4.Parent = infoFrame

local infoText5 = Instance.new("TextLabel")
infoText5.Size = UDim2.new(1, -20, 0, 20)
infoText5.Position = UDim2.new(0, 10, 0, 128)
infoText5.BackgroundTransparency = 1
infoText5.Text = "• Gap: 0.5 studs (distance from target)"
infoText5.TextColor3 = Color3.fromRGB(200, 200, 200)
infoText5.TextSize = 12
infoText5.Font = Enum.Font.Gotham
infoText5.TextXAlignment = Enum.TextXAlignment.Left
infoText5.Parent = infoFrame

local infoText6 = Instance.new("TextLabel")
infoText6.Size = UDim2.new(1, -20, 0, 20)
infoText6.Position = UDim2.new(0, 10, 0, 150)
infoText6.BackgroundTransparency = 1
infoText6.Text = "• Dash degree: 120 (smooth arc)"
infoText6.TextColor3 = Color3.fromRGB(200, 200, 200)
infoText6.TextSize = 12
infoText6.Font = Enum.Font.Gotham
infoText6.TextXAlignment = Enum.TextXAlignment.Left
infoText6.Parent = infoFrame

-- KEYBINDS OVERLAY
local keybindsOverlay = Instance.new("Frame")
keybindsOverlay.Name = "KeybindsOverlay"
keybindsOverlay.Size = UDim2.new(0, 320, 0, 400)
keybindsOverlay.Position = UDim2.new(0, 20, 0.1, 0)
keybindsOverlay.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
keybindsOverlay.BackgroundTransparency = 0
keybindsOverlay.BorderSizePixel = 0
keybindsOverlay.Visible = false
keybindsOverlay.Parent = gui
keybindsOverlay.Draggable = true
Instance.new("UICorner", keybindsOverlay).CornerRadius = UDim.new(0, 16)

local keybindsGradient = Instance.new("UIGradient", keybindsOverlay)
keybindsGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(25, 5, 5)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(15, 15, 15)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0))
})
keybindsGradient.Rotation = 90

local keybindsTitle = Instance.new("TextLabel")
keybindsTitle.Size = UDim2.new(1, -60, 0, 40)
keybindsTitle.Position = UDim2.new(0, 16, 0, 8)
keybindsTitle.BackgroundTransparency = 1
keybindsTitle.Text = "Keybinds"
keybindsTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
keybindsTitle.TextSize = 20
keybindsTitle.Font = Enum.Font.GothamBold
keybindsTitle.TextXAlignment = Enum.TextXAlignment.Left
keybindsTitle.Parent = keybindsOverlay

local keybindsCloseBtn = Instance.new("TextButton")
keybindsCloseBtn.Size = UDim2.new(0, 30, 0, 30)
keybindsCloseBtn.Position = UDim2.new(1, -40, 0, 8)
keybindsCloseBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
keybindsCloseBtn.Text = "X"
keybindsCloseBtn.Font = Enum.Font.GothamBold
keybindsCloseBtn.TextColor3 = Color3.fromRGB(0, 0, 0)
keybindsCloseBtn.TextSize = 18
keybindsCloseBtn.BorderSizePixel = 0
keybindsCloseBtn.Style = Enum.ButtonStyle.Custom
keybindsCloseBtn.Parent = keybindsOverlay
Instance.new("UICorner", keybindsCloseBtn).CornerRadius = UDim.new(0, 8)

-- Keybind selector for DASH KEY
local dashKeyLabel = Instance.new("TextLabel")
dashKeyLabel.Size = UDim2.new(1, -32, 0, 25)
dashKeyLabel.Position = UDim2.new(0, 16, 0, 60)
dashKeyLabel.BackgroundTransparency = 1
dashKeyLabel.Text = "Primary Dash Key:"
dashKeyLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
dashKeyLabel.TextSize = 13
dashKeyLabel.Font = Enum.Font.Gotham
dashKeyLabel.TextXAlignment = Enum.TextXAlignment.Left
dashKeyLabel.Parent = keybindsOverlay

local dashKeyButton = Instance.new("TextButton")
dashKeyButton.Size = UDim2.new(1, -32, 0, 40)
dashKeyButton.Position = UDim2.new(0, 16, 0, 90)
dashKeyButton.BackgroundColor3 = Color3.fromRGB(50, 100, 200)
dashKeyButton.BorderSizePixel = 0
dashKeyButton.Text = "E (Click to change)"
dashKeyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
dashKeyButton.TextSize = 13
dashKeyButton.Font = Enum.Font.GothamBold
dashKeyButton.Style = Enum.ButtonStyle.Custom
dashKeyButton.Parent = keybindsOverlay
Instance.new("UICorner", dashKeyButton).CornerRadius = UDim.new(0, 8)

local currentDashKey = Enum.KeyCode.E
local isWaitingForKey = false

dashKeyButton.MouseButton1Click:Connect(function()
    uiClickSound:Play()
    if not isWaitingForKey then
        isWaitingForKey = true
        dashKeyButton.Text = "Press any key..."
        dashKeyButton.BackgroundColor3 = Color3.fromRGB(255, 150, 0)
        
        local connection
        connection = InputService.InputBegan:Connect(function(input, gp)
            if gp then return end
            if input.UserInputType == Enum.UserInputType.Keyboard then
                currentDashKey = input.KeyCode
                dashKeyButton.Text = input.KeyCode.Name .. " (Click to change)"
                dashKeyButton.BackgroundColor3 = Color3.fromRGB(50, 200, 100)
                isWaitingForKey = false
                connection:Disconnect()
            end
        end)
        
        task.delay(5, function()
            if isWaitingForKey then
                isWaitingForKey = false
                dashKeyButton.Text = "E (Click to change)"
                dashKeyButton.BackgroundColor3 = Color3.fromRGB(50, 100, 200)
                pcall(function() connection:Disconnect() end)
            end
        end)
    end
end)

-- BUTTON SIZE CHANGER
local buttonSizeLabel = Instance.new("TextLabel")
buttonSizeLabel.Size = UDim2.new(1, -32, 0, 25)
buttonSizeLabel.Position = UDim2.new(0, 16, 0, 150)
buttonSizeLabel.BackgroundTransparency = 1
buttonSizeLabel.Text = "Red Button Size:"
buttonSizeLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
buttonSizeLabel.TextSize = 13
buttonSizeLabel.Font = Enum.Font.Gotham
buttonSizeLabel.TextXAlignment = Enum.TextXAlignment.Left
buttonSizeLabel.Parent = keybindsOverlay

local buttonSizeButton = Instance.new("TextButton")
buttonSizeButton.Size = UDim2.new(1, -32, 0, 40)
buttonSizeButton.Position = UDim2.new(0, 16, 0, 180)
buttonSizeButton.BackgroundColor3 = Color3.fromRGB(255, 120, 50)
buttonSizeButton.BorderSizePixel = 0
buttonSizeButton.Text = "Size: " .. redButtonSize .. " (Click to change)"
buttonSizeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
buttonSizeButton.TextSize = 13
buttonSizeButton.Font = Enum.Font.GothamBold
buttonSizeButton.Style = Enum.ButtonStyle.Custom
buttonSizeButton.Parent = keybindsOverlay
Instance.new("UICorner", buttonSizeButton).CornerRadius = UDim.new(0, 8)

-- Update keybind input
InputService.InputBegan:Connect(function(inp, gp)
    if gp or isDashing or isCharacterDisabled() then return end
    if inp.UserInputType == Enum.UserInputType.Keyboard and inp.KeyCode == currentDashKey then
        local target = getCurrentTarget()
        if target then
            performCircularDash(target)
        else
            notify("No Target", "No enemies in range!")
        end
    end
end)

-- Open lock buttons
local openButton = Instance.new("TextButton")
openButton.Name = "OpenGuiButton"
openButton.Size = UDim2.new(0, 90, 0, 34)
openButton.Position = UDim2.new(0, 10, 0.5, -17)
openButton.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
openButton.Text = "Open GUI"
openButton.TextColor3 = Color3.fromRGB(255, 255, 255)
openButton.TextSize = 15
openButton.Font = Enum.Font.GothamBold
openButton.BorderSizePixel = 0
openButton.Visible = false
openButton.Style = Enum.ButtonStyle.Custom
openButton.Parent = gui
openButton.Draggable = true
Instance.new("UICorner", openButton).CornerRadius = UDim.new(0, 10)

local dashButtonLocked = false
local lockButton = Instance.new("TextButton")
lockButton.Name = "LockButton"
lockButton.Size = UDim2.new(0, 90, 0, 34)
lockButton.Position = UDim2.new(0, 110, 0.5, -17)
lockButton.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
lockButton.Text = "🔓 Unlocked"
lockButton.TextColor3 = Color3.fromRGB(255, 255, 255)
lockButton.TextSize = 11
lockButton.Font = Enum.Font.GothamBold
lockButton.BorderSizePixel = 0
lockButton.Visible = false
lockButton.Style = Enum.ButtonStyle.Custom
lockButton.Parent = gui
lockButton.Draggable = true
Instance.new("UICorner", lockButton).CornerRadius = UDim.new(0, 10)

-- Red dash button - INITIALIZE WITH CORRECT SIZE
local dashBtn = Instance.new("Frame")
dashBtn.Name = "DashButtonFinal"
dashBtn.Size = UDim2.new(0, redButtonSize, 0, redButtonSize)
dashBtn.Position = UDim2.new(1, -125, 0.5, -(redButtonSize / 2))
dashBtn.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
dashBtn.BorderSizePixel = 0
dashBtn.Parent = gui
dashBtn.Active = true
dashBtn.Draggable = true
Instance.new("UICorner", dashBtn).CornerRadius = UDim.new(1, 0)

local dashGrad = Instance.new("UIGradient", dashBtn)
dashGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(220, 0, 0)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 0, 0))
})
dashGrad.Rotation = 45

local dashIcon = Instance.new("ImageLabel")
dashIcon.BackgroundTransparency = 1
dashIcon.Size = UDim2.new(0, redButtonSize - 15, 0, redButtonSize - 15)
dashIcon.Position = UDim2.new(0.5, -(redButtonSize - 15) / 2, 0.5, -(redButtonSize - 15) / 2)
dashIcon.Image = "rbxassetid://12443244342"
dashIcon.Parent = dashBtn

-- Notify helper
local function notifyGui(text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "Side Dash Assist",
            Text = text,
            Duration = 2,
        })
    end)
end

-- Logic
lockButton.MouseButton1Click:Connect(function()
    uiClickSound:Play()
    dashButtonLocked = not dashButtonLocked
    dashBtn.Draggable = not dashButtonLocked
    mainFrame.Draggable = not dashButtonLocked
    openButton.Draggable = not dashButtonLocked
    lockButton.Draggable = not dashButtonLocked
    if dashButtonLocked then
        lockButton.Text = "🔒 Locked"
        notifyGui("Dash button is now locked.")
    else
        lockButton.Text = "🔓 Unlocked"
        notifyGui("Dash button is now unlocked.")
    end
end)

dashBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dashClickSound:Play()
        local target = getCurrentTarget()
        if target then
            performCircularDash(target)
        else
            notifyGui("No target found!")
        end
    end
end)

closeBtn.MouseButton1Click:Connect(function()
    uiClickSound:Play()
    TweenService:Create(blur, TweenInfo.new(0.3), {Size = 0}):Play()
    TweenService:Create(mainFrame, TweenInfo.new(0.3), {BackgroundTransparency = 1}):Play()
    TweenService:Create(borderFrame, TweenInfo.new(0.3), {BackgroundTransparency = 1}):Play()
    task.wait(0.3)
    mainFrame.Visible = false
    openButton.Visible = true
    lockButton.Visible = true
end)

minimizeBtn.MouseButton1Click:Connect(function()
    uiClickSound:Play()
    TweenService:Create(blur, TweenInfo.new(0.3), {Size = 0}):Play()
    TweenService:Create(mainFrame, TweenInfo.new(0.3), {BackgroundTransparency = 1}):Play()
    TweenService:Create(borderFrame, TweenInfo.new(0.3), {BackgroundTransparency = 1}):Play()
    task.wait(0.3)
    mainFrame.Visible = false
    openButton.Visible = true
    lockButton.Visible = true
end)

openButton.MouseButton1Click:Connect(function()
    uiClickSound:Play()
    openButton.Visible = false
    lockButton.Visible = false
    mainFrame.Visible = true
    TweenService:Create(blur, TweenInfo.new(0.3), {Size = 12}):Play()
    TweenService:Create(mainFrame, TweenInfo.new(0.3), {BackgroundTransparency = 0}):Play()
    TweenService:Create(borderFrame, TweenInfo.new(0.3), {BackgroundTransparency = 0}):Play()
end)

settingsBtn.MouseButton1Click:Connect(function()
    uiClickSound:Play()
    if keybindsOverlay.Visible then
        keybindsOverlay.Visible = false
    end
    settingsOverlay.Visible = true
end)

keybindsBtn.MouseButton1Click:Connect(function()
    uiClickSound:Play()
    if settingsOverlay.Visible then
        settingsOverlay.Visible = false
    end
    keybindsOverlay.Visible = true
end)

settingsCloseBtn.MouseButton1Click:Connect(function()
    uiClickSound:Play()
    settingsOverlay.Visible = false
end)

keybindsCloseBtn.MouseButton1Click:Connect(function()
    uiClickSound:Play()
    keybindsOverlay.Visible = false
end)

discordBtn.MouseButton1Click:Connect(function()
    uiClickSound:Play()
    if setclipboard then
        setclipboard("https://discord.gg/YFf3rdXbUf")
        notifyGui("Discord invite copied to clipboard.")
    else
        notifyGui("Discord: https://discord.gg/YFf3rdXbUf")
    end
end)

ytBtn.MouseButton1Click:Connect(function()
    uiClickSound:Play()
    if setclipboard then
        setclipboard("https://youtube.com/@waspire")
        notifyGui("YouTube link copied to clipboard.")
    else
        notifyGui("YouTube: https://youtube.com/@waspire")
    end
end)

-- BUTTON SIZE CHANGER CLICK LOGIC - FIXED
buttonSizeButton.MouseButton1Click:Connect(function()
    uiClickSound:Play()
    redButtonSize = redButtonSize + 10
    if redButtonSize > 150 then
        redButtonSize = 70
    end
    buttonSizeButton.Text = "Size: " .. redButtonSize .. " (Click to change)"
    
    -- Update button size and position
    dashBtn.Size = UDim2.new(0, redButtonSize, 0, redButtonSize)
    dashBtn.Position = UDim2.new(1, -125, 0.5, -(redButtonSize / 2))
    
    -- Update icon size and position
    dashIcon.Size = UDim2.new(0, redButtonSize - 15, 0, redButtonSize - 15)
    dashIcon.Position = UDim2.new(0.5, -(redButtonSize - 15) / 2, 0.5, -(redButtonSize - 15) / 2)
end)

-- COOLDOWN NOTIFIER
local cooldownLabel = Instance.new("TextLabel")
cooldownLabel.Name = "CooldownLabel"
cooldownLabel.Size = UDim2.new(0, 150, 0, 50)
cooldownLabel.Position = UDim2.new(0, 10, 1, -60)
cooldownLabel.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
cooldownLabel.BackgroundTransparency = 0.3
cooldownLabel.BorderSizePixel = 0
cooldownLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
cooldownLabel.TextSize = 16
cooldownLabel.Font = Enum.Font.GothamBold
cooldownLabel.TextStrokeTransparency = 0.5
cooldownLabel.Parent = gui
Instance.new("UICorner", cooldownLabel).CornerRadius = UDim.new(0, 8)

local function updateCooldownLabel()
    local remaining = dashRemaining()
    
    if remaining > 0.05 then
        local displayTime = math.ceil(remaining * 10) / 10
        cooldownLabel.Text = string.format("%.1f", displayTime) .. "s"
        
        if displayTime > 1.2 then
            cooldownLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
        elseif displayTime > 0.5 then
            cooldownLabel.TextColor3 = Color3.fromRGB(255, 255, 0)
        else
            cooldownLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
        end
    else
        cooldownLabel.Text = "Ready!"
        cooldownLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
    end
end

RunService.RenderStepped:Connect(function()
    if gui and gui.Parent then
        updateCooldownLabel()
    end
end)

-- Initial show
mainFrame.Visible = true
TweenService:Create(blur, TweenInfo.new(0.3), {Size = 12}):Play()
TweenService:Create(mainFrame, TweenInfo.new(0.3), {BackgroundTransparency = 0}):Play()
TweenService:Create(borderFrame, TweenInfo.new(0.3), {BackgroundTransparency = 0}):Play()
task.delay(0.1, function()
    loadSound:Play()
end)

print("subscribe to Waspire")

--// END COMPLETE FIXED SNIPPET





