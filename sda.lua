--// SNIPPET 1 - CORE SETUP

pcall(function()
    local pg = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
    for _, name in ipairs({"SideDashAssistGUI"}) do
        local g = pg:FindFirstChild(name)
        if g then g:Destroy() end
    end
end)

task.wait(0.1)

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

-- CONFIG GLOBALS
_G.dashButtonSize = 90
_G.dashKeybind = Enum.KeyCode.E
_G.dashCooldown = 1.5
_G.dashDistance = 4

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

local ANIMATION_IDS = {
    [10449761463] = {Left = 10480796021, Right = 10480793962, Straight = 10479335397},
    [13076380114] = {Left = 101843860692381, Right = 100087324592640, Straight = 110878031211717}
}
local gameId = game.PlaceId
local currentGameAnimations = ANIMATION_IDS[gameId] or ANIMATION_IDS[13076380114]
local leftAnimationId = currentGameAnimations.Left
local rightAnimationId = currentGameAnimations.Right
local straightAnimationId = currentGameAnimations.Straight

local MAX_TARGET_RANGE = 40
local MIN_DASH_DISTANCE = 1.2
local MAX_DASH_DISTANCE = 60
local MIN_TARGET_DISTANCE = 15
local TARGET_REACH_THRESHOLD = 10
local DASH_SPEED = 180
local DIRECTION_LERP_FACTOR = 0.7
local CAMERA_FOLLOW_DELAY = 0.7
local VELOCITY_PREDICTION_FACTOR = 0.5
local FOLLOW_EASING_POWER = 200
local CIRCLE_COMPLETION_THRESHOLD = 390 / 480

local isDashing = false
local sideAnimationTrack = nil
local straightAnimationTrack = nil
local lastButtonPressTime = -math.huge

local isAutoRotateDisabled = false
local autoRotateConnection = nil

local dashSound = Instance.new("Sound")
dashSound.Name = "DashSFX"
dashSound.SoundId = "rbxassetid://3084314259"
dashSound.Volume = 2
dashSound.Looped = false
dashSound.Parent = WorkspaceService

-- FULL-BODY RED CHAM (NO ZINDEX)
local function applyRedChamEffectToPlayer(duration)
    duration = duration or 1.0
    for _, part in pairs(Character:GetDescendants()) do
        if part:IsA("BasePart") then
            local originalColor = part.Color
            TweenService:Create(part, TweenInfo.new(0.1), {Color = Color3.fromRGB(255, 0, 0)}):Play()
            task.delay(duration, function()
                if part and part.Parent then
                    TweenService:Create(part, TweenInfo.new(0.3), {Color = originalColor}):Play()
                end
            end)
        end
    end
end

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

local function getAngleDifference(a1, a2)
    local d = a1 - a2
    while math.pi < d do d -= 2 * math.pi end
    while d < -math.pi do d += 2 * math.pi end
    return d
end

local function easeInOutCubic(p)
    return 1 - (1 - math.clamp(p, 0, 1)) ^ 3
end

local blur = Instance.new("BlurEffect")
blur.Size = 0
blur.Parent = Lighting

local function notify(title, text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = 3,
        })
    end)
end

notify("Side Dash Assist v1.5", "Loaded! Press E or click the red dash button")
--// SNIPPET 2 - DASH LOGIC

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
            loadedAnimation:Play()
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

local function calculateDashAngle(_degreesSliderValue)
    return 120
end

-- uses global distance
local function calculateDashDistance(_gapSliderValue)
    return _G.dashDistance
end

local settingsValues = {["Dash speed"] = 49, ["Dash Degrees"] = 32, ["Dash gap"] = 14}
local lockedTargetPlayer = nil
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
                if (targetRoot.Position - HumanoidRootPart.Position).Magnitude > MAX_TARGET_RANGE then
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

    straightAnimationTrack = nil
    local straightAnimationInstance = nil

    if straightAnimationId then
        local characterHumanoid, characterAnimator = getHumanoidAndAnimator()
        if characterHumanoid and characterAnimator then
            straightAnimationInstance = Instance.new("Animation")
            straightAnimationInstance.Name = "StraightDashAnim"
            straightAnimationInstance.AnimationId = "rbxassetid://" .. tostring(straightAnimationId)
            local success, loadedAnim = pcall(function()
                return characterAnimator:LoadAnimation(straightAnimationInstance)
            end)
            if success and loadedAnim then
                loadedAnim.Priority = Enum.AnimationPriority.Movement
                pcall(function() loadedAnim.Looped = false end)
                pcall(function() loadedAnim:Play() end)
                straightAnimationTrack = loadedAnim
            else
                pcall(function() straightAnimationInstance:Destroy() end)
            end
        end
    end

    pcall(function()
        dashSound:Stop()
        dashSound:Play()
    end)

    local isActive = true
    local heartbeatConnection

    heartbeatConnection = RunService.Heartbeat:Connect(function()
        if isActive and targetRootPart and targetRootPart.Parent and HumanoidRootPart and HumanoidRootPart.Parent then
            local targetPosition = targetRootPart.Position
            local directionToTarget = targetPosition - HumanoidRootPart.Position
            local horizontalDirection = Vector3.new(directionToTarget.X, 0, directionToTarget.Z)
            if horizontalDirection.Magnitude > TARGET_REACH_THRESHOLD then
                linearVelocity.VectorVelocity = horizontalDirection.Unit * dashSpeed
                pcall(function()
                    if horizontalDirection.Magnitude > 0.001 then
                        HumanoidRootPart.CFrame = CFrame.new(
                            HumanoidRootPart.Position,
                            HumanoidRootPart.Position + horizontalDirection.Unit
                        )
                    end
                end)
                pcall(function()
                    aimCharacterAtTarget(targetPosition, 0.56)
                end)
            else
                isActive = false
                heartbeatConnection:Disconnect()
                pcall(function() linearVelocity:Destroy() attachment:Destroy() end)
            end
        else
            isActive = false
            heartbeatConnection:Disconnect()
            pcall(function() linearVelocity:Destroy() attachment:Destroy() end)
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
                    local finalLookVector =
                        characterLookVector:Lerp(Vector3.new(targetDirection.X, characterLookVector.Y, targetDirection.Z).Unit, easedProgress)
                    HumanoidRootPart.CFrame = CFrame.new(characterPosition, characterPosition + finalLookVector)
                end)
                if progress >= 1 then aimTweenConnection:Disconnect() end
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

local function performCircularDash(targetCharacter)
    if isDashing or not targetCharacter or not targetCharacter:FindFirstChild("HumanoidRootPart") or not HumanoidRootPart then return end
    
    local currentTime = tick()
    local timeSinceLastDash = currentTime - lastButtonPressTime
    if timeSinceLastDash < _G.dashCooldown then
        local remainingMs = math.ceil((_G.dashCooldown - timeSinceLastDash) * 1000)
        notify("Cooldown", "Wait " .. remainingMs .. "ms before next dash")
        return
    end
    
    isDashing = true
    lastButtonPressTime = currentTime

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
    local dashAngle = calculateDashAngle(settingsValues["Dash Degrees"])
    local dashAngleRad = math.rad(dashAngle)
    local dashDistance = math.clamp(calculateDashDistance(settingsValues["Dash gap"]), MIN_DASH_DISTANCE, MAX_DASH_DISTANCE)
    local targetRoot = targetCharacter.HumanoidRootPart

    -- full body cham for dash duration
    applyRedChamEffectToPlayer(dashDuration + CAMERA_FOLLOW_DELAY)

    if MIN_TARGET_DISTANCE <= (targetRoot.Position - HumanoidRootPart.Position).Magnitude then
        performDashMovement(targetRoot, DASH_SPEED)
    end

    if targetRoot and targetRoot.Parent and HumanoidRootPart and HumanoidRootPart.Parent then
        local targetPosition = targetRoot.Position
        local characterPosition = HumanoidRootPart.Position
        local characterRightVector = HumanoidRootPart.CFrame.RightVector
        local directionToTarget = targetRoot.Position - HumanoidRootPart.Position
        if directionToTarget.Magnitude < 0.001 then
            directionToTarget = HumanoidRootPart.CFrame.LookVector
        end

        local isLeftDirection = characterRightVector:Dot(directionToTarget.Unit) < 0
        playSideAnimation(isLeftDirection)

        local directionMultiplier = isLeftDirection and 1 or -1
        local angleToTarget = math.atan2(characterPosition.Z - targetPosition.Z, characterPosition.X - targetPosition.X)
        local horizontalDistance = (Vector3.new(characterPosition.X, 0, characterPosition.Z) - Vector3.new(targetPosition.X, 0, targetPosition.Z)).Magnitude
        local clampedDistance = math.clamp(horizontalDistance, MIN_DASH_DISTANCE, MAX_DASH_DISTANCE)

        local startTime = tick()
        local movementConnection
        local hasStartedAim = false
        local hasCompletedCircle = false
        local shouldEndDash = false
        local dashEnded = false
        
        local capturedTargetPosition = targetPosition

        local function startDashEndSequence()
            if not hasCompletedCircle then
                hasCompletedCircle = true
                task.delay(CAMERA_FOLLOW_DELAY, function()
                    shouldEndDash = true
                    restoreAutoRotate()
                    if dashEnded then
                        isDashing = false
                    end
                end)
            end
        end

        if m1ToggleEnabled then
            communicateWithServer({{Mobile = true, Goal = "LeftClick"}})
            task.delay(0.05, function()
                communicateWithServer({{Goal = "LeftClickRelease", Mobile = true}})
            end)
        end

        if dashToggleEnabled then
            communicateWithServer({{Dash = Enum.KeyCode.W, Key = Enum.KeyCode.Q, Goal = "KeyPress"}})
        end

        movementConnection = RunService.Heartbeat:Connect(function()
            local currentTime = tick()
            local progress = math.clamp((currentTime - startTime) / dashDuration, 0, 1)
            local easedProgress = easeInOutCubic(progress)
            local aimProgress = math.clamp(progress * 1.5, 0, 1)
            local currentRadius = clampedDistance + (dashDistance - clampedDistance) * easeInOutCubic(aimProgress)
            local clampedRadius = math.clamp(currentRadius, MIN_DASH_DISTANCE, MAX_DASH_DISTANCE)

            local currentTargetPosition = capturedTargetPosition
            local playerGroundY = HumanoidRootPart.Position.Y

            local currentAngle = angleToTarget + directionMultiplier * dashAngleRad * easeInOutCubic(progress)
            local circleX = currentTargetPosition.X + clampedRadius * math.cos(currentAngle)
            local circleZ = currentTargetPosition.Z + clampedRadius * math.sin(currentAngle)
            local newPosition = Vector3.new(circleX, playerGroundY, circleZ)

            local angleToTargetPosition = math.atan2((currentTargetPosition - newPosition).Z, (currentTargetPosition - newPosition).X)
            local characterAngle = math.atan2(HumanoidRootPart.CFrame.LookVector.Z, HumanoidRootPart.CFrame.LookVector.X)
            local finalCharacterAngle = characterAngle + getAngleDifference(angleToTargetPosition, characterAngle) * DIRECTION_LERP_FACTOR

            pcall(function()
                HumanoidRootPart.CFrame = CFrame.new(
                    newPosition,
                    newPosition + Vector3.new(math.cos(finalCharacterAngle), 0, math.sin(finalCharacterAngle))
                )
            end)

            if not hasStartedAim and CIRCLE_COMPLETION_THRESHOLD <= easedProgress then
                hasStartedAim = true
                pcall(function()
                    smoothlyAimAtTarget(targetRoot, CAMERA_FOLLOW_DELAY)
                end)
                startDashEndSequence()
            end

            if progress >= 1 then
                movementConnection:Disconnect()
                pcall(function()
                    if sideAnimationTrack and sideAnimationTrack.IsPlaying then
                        sideAnimationTrack:Stop()
                    end
                    sideAnimationTrack = nil
                end)

                if not hasStartedAim then
                    hasStartedAim = true
                    pcall(function()
                        smoothlyAimAtTarget(targetRoot, CAMERA_FOLLOW_DELAY)
                    end)
                    startDashEndSequence()
                end

                dashEnded = true
                if shouldEndDash then
                    isDashing = false
                end
            end
        end)
    else
        restoreAutoRotate()
        isDashing = false
    end
end

InputService.InputBegan:Connect(function(inp, gp)
    if gp or isDashing or isCharacterDisabled() then return end
    if inp.UserInputType == Enum.UserInputType.Keyboard and inp.KeyCode == _G.dashKeybind then
        local target = getCurrentTarget()
        if target then
            performCircularDash(target)
        end
    end
end)
--// SNIPPET 3 - GUI + RED BUTTON

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
versionLabel.Text = "v1.5"
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

-- Close / minimize
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

-- Settings / social
local settingsBtn = Instance.new("TextButton")
settingsBtn.Size = UDim2.new(0, 36, 0, 36)
settingsBtn.Position = UDim2.new(0, 10, 1, -46)
settingsBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
settingsBtn.Text = "⚙"
settingsBtn.Font = Enum.Font.GothamBold
settingsBtn.TextColor3 = Color3.fromRGB(0, 0, 0)
settingsBtn.TextSize = 19
settingsBtn.BorderSizePixel = 0
settingsBtn.Style = Enum.ButtonStyle.Custom
settingsBtn.Parent = mainFrame
Instance.new("UICorner", settingsBtn).CornerRadius = UDim.new(1, 0)

local keybindsInfoBtn = Instance.new("TextButton")
keybindsInfoBtn.Size = UDim2.new(0, 36, 0, 36)
keybindsInfoBtn.Position = UDim2.new(0, 56, 1, -46)
keybindsInfoBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
keybindsInfoBtn.Text = "🖱️"
keybindsInfoBtn.Font = Enum.Font.GothamBold
keybindsInfoBtn.TextColor3 = Color3.fromRGB(0, 0, 0)
keybindsInfoBtn.TextSize = 19
keybindsInfoBtn.BorderSizePixel = 0
keybindsInfoBtn.Style = Enum.ButtonStyle.Custom
keybindsInfoBtn.Parent = mainFrame
Instance.new("UICorner", keybindsInfoBtn).CornerRadius = UDim.new(1, 0)

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

-- Settings overlay (with size + distance)
local settingsOverlay = Instance.new("Frame")
settingsOverlay.Name = "SettingsOverlay"
settingsOverlay.Size = UDim2.new(0, 300, 0, 240)
settingsOverlay.Position = UDim2.new(0, 40, 0.2, 0)
settingsOverlay.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
settingsOverlay.BackgroundTransparency = 1
settingsOverlay.BorderSizePixel = 0
settingsOverlay.Visible = false
settingsOverlay.Parent = gui
settingsOverlay.Draggable = true
Instance.new("UICorner", settingsOverlay).CornerRadius = UDim.new(0, 19)
local overlayGradient = Instance.new("UIGradient", settingsOverlay)
overlayGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(25, 5, 5)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(15, 15, 15)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0))
})
overlayGradient.Rotation = 90

local settingsTitle = Instance.new("TextLabel")
settingsTitle.Size = UDim2.new(1, -60, 0, 40)
settingsTitle.Position = UDim2.new(0, 16, 0, 5)
settingsTitle.BackgroundTransparency = 1
settingsTitle.Text = "Settings"
settingsTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
settingsTitle.TextSize = 21
settingsTitle.Font = Enum.Font.GothamBold
settingsTitle.TextXAlignment = Enum.TextXAlignment.Left
settingsTitle.Parent = settingsOverlay

local settingsCloseBtn = Instance.new("TextButton")
settingsCloseBtn.Size = UDim2.new(0, 35, 0, 35)
settingsCloseBtn.Position = UDim2.new(1, -45, 0, 6)
settingsCloseBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
settingsCloseBtn.Text = "X"
settingsCloseBtn.Font = Enum.Font.GothamBold
settingsCloseBtn.TextColor3 = Color3.fromRGB(0, 0, 0)
settingsCloseBtn.TextSize = 19
settingsCloseBtn.BorderSizePixel = 0
settingsCloseBtn.Style = Enum.ButtonStyle.Custom
settingsCloseBtn.Parent = settingsOverlay
Instance.new("UICorner", settingsCloseBtn).CornerRadius = UDim.new(0, 10)

local keybindFrame = Instance.new("Frame")
keybindFrame.Size = UDim2.new(1, -32, 0, 110)
keybindFrame.Position = UDim2.new(0, 16, 0, 60)
keybindFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
keybindFrame.BorderSizePixel = 0
keybindFrame.Parent = settingsOverlay
Instance.new("UICorner", keybindFrame).CornerRadius = UDim.new(0, 14)

local keyTitle = Instance.new("TextLabel")
keyTitle.Size = UDim2.new(1, -20, 0, 30)
keyTitle.Position = UDim2.new(0, 10, 0, 8)
keyTitle.BackgroundTransparency = 1
keyTitle.Text = "Keybind Info"
keyTitle.TextColor3 = Color3.fromRGB(230, 230, 230)
keyTitle.TextSize = 18
keyTitle.Font = Enum.Font.GothamBold
keyTitle.TextXAlignment = Enum.TextXAlignment.Left
keyTitle.Parent = keybindFrame

local keyInfo1 = Instance.new("TextLabel")
keyInfo1.Size = UDim2.new(1, -20, 0, 24)
keyInfo1.Position = UDim2.new(0, 10, 0, 40)
keyInfo1.BackgroundTransparency = 1
keyInfo1.Text = "PC Dash Key: E"
keyInfo1.TextColor3 = Color3.fromRGB(205, 205, 205)
keyInfo1.TextSize = 15
keyInfo1.Font = Enum.Font.Gotham
keyInfo1.TextXAlignment = Enum.TextXAlignment.Left
keyInfo1.Parent = keybindFrame

local keyInfo2 = Instance.new("TextLabel")
keyInfo2.Size = UDim2.new(1, -20, 0, 24)
keyInfo2.Position = UDim2.new(0, 10, 0, 66)
keyInfo2.BackgroundTransparency = 1
keyInfo2.Text = "Mobile Button :)"
keyInfo2.TextColor3 = Color3.fromRGB(205, 205, 205)
keyInfo2.TextSize = 15
keyInfo2.Font = Enum.Font.Gotham
keyInfo2.TextXAlignment = Enum.TextXAlignment.Left
keyInfo2.Parent = keybindFrame

-- SIZE TEXTBOX
local sizeLabel = Instance.new("TextLabel")
sizeLabel.Size = UDim2.new(1, -32, 0, 22)
sizeLabel.Position = UDim2.new(0, 16, 0, 180)
sizeLabel.BackgroundTransparency = 1
sizeLabel.Text = "Button Size (50-150):"
sizeLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
sizeLabel.TextSize = 14
sizeLabel.Font = Enum.Font.GothamBold
sizeLabel.TextXAlignment = Enum.TextXAlignment.Left
sizeLabel.Parent = settingsOverlay

local sizeTextbox = Instance.new("TextBox")
sizeTextbox.Size = UDim2.new(0, 80, 0, 26)
sizeTextbox.Position = UDim2.new(0, 190, 0, 177)
sizeTextbox.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
sizeTextbox.TextColor3 = Color3.fromRGB(255, 255, 255)
sizeTextbox.PlaceholderText = "90"
sizeTextbox.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
sizeTextbox.BorderSizePixel = 0
sizeTextbox.Text = tostring(_G.dashButtonSize)
sizeTextbox.TextSize = 14
sizeTextbox.Font = Enum.Font.Gotham
sizeTextbox.Parent = settingsOverlay
Instance.new("UICorner", sizeTextbox).CornerRadius = UDim.new(0, 8)

-- DASH DISTANCE TEXTBOX
local distanceLabel = Instance.new("TextLabel")
distanceLabel.Size = UDim2.new(1, -32, 0, 22)
distanceLabel.Position = UDim2.new(0, 16, 0, 208)
distanceLabel.BackgroundTransparency = 1
distanceLabel.Text = "Dash Distance (1-60):"
distanceLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
distanceLabel.TextSize = 14
distanceLabel.Font = Enum.Font.GothamBold
distanceLabel.TextXAlignment = Enum.TextXAlignment.Left
distanceLabel.Parent = settingsOverlay

local distanceTextbox = Instance.new("TextBox")
distanceTextbox.Size = UDim2.new(0, 80, 0, 26)
distanceTextbox.Position = UDim2.new(0, 190, 0, 205)
distanceTextbox.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
distanceTextbox.TextColor3 = Color3.fromRGB(255, 255, 255)
distanceTextbox.PlaceholderText = "4"
distanceTextbox.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
distanceTextbox.BorderSizePixel = 0
distanceTextbox.Text = tostring(_G.dashDistance)
distanceTextbox.TextSize = 14
distanceTextbox.Font = Enum.Font.Gotham
distanceTextbox.Parent = settingsOverlay
Instance.new("UICorner", distanceTextbox).CornerRadius = UDim.new(0, 8)

-- Open / lock buttons
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
lockButton.TextSize = 13
lockButton.Font = Enum.Font.GothamBold
lockButton.BorderSizePixel = 0
lockButton.Visible = false
lockButton.Style = Enum.ButtonStyle.Custom
lockButton.Parent = gui
lockButton.Draggable = true
Instance.new("UICorner", lockButton).CornerRadius = UDim.new(0, 10)

-- Red dash button (size controlled by _G.dashButtonSize)
local dashBtn = Instance.new("Frame")
dashBtn.Name = "DashButton_Final"
dashBtn.Size = UDim2.new(0, _G.dashButtonSize, 0, _G.dashButtonSize)
dashBtn.Position = UDim2.new(1, -(_G.dashButtonSize + 15), 0.5, -_G.dashButtonSize / 2)
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
dashIcon.Size = UDim2.new(0, _G.dashButtonSize - 15, 0, _G.dashButtonSize - 15)
dashIcon.Position = UDim2.new(0.5, -(_G.dashButtonSize - 15) / 2, 0.5, -(_G.dashButtonSize - 15) / 2)
dashIcon.Image = "rbxassetid://12443244342"
dashIcon.Parent = dashBtn
--// SNIPPET 4 - KEYBINDS + LOGIC

-- Keybind overlay (change keybind)
local keybindsOverlay = Instance.new("Frame")
keybindsOverlay.Name = "KeybindsOverlay"
keybindsOverlay.Size = UDim2.new(0, 220, 0, 220)
keybindsOverlay.Position = UDim2.new(0.5, -110, 0.3, 0)
keybindsOverlay.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
keybindsOverlay.BackgroundTransparency = 1
keybindsOverlay.BorderSizePixel = 0
keybindsOverlay.Visible = false
keybindsOverlay.Parent = gui
keybindsOverlay.Draggable = true
Instance.new("UICorner", keybindsOverlay).CornerRadius = UDim.new(0, 19)
local keybindsGradient = Instance.new("UIGradient", keybindsOverlay)
keybindsGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(25, 5, 5)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(15, 15, 15)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0))
})
keybindsGradient.Rotation = 90

local keybindsTitle = Instance.new("TextLabel")
keybindsTitle.Size = UDim2.new(1, -60, 0, 40)
keybindsTitle.Position = UDim2.new(0, 16, 0, 5)
keybindsTitle.BackgroundTransparency = 1
keybindsTitle.Text = "Keybinds"
keybindsTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
keybindsTitle.TextSize = 21
keybindsTitle.Font = Enum.Font.GothamBold
keybindsTitle.TextXAlignment = Enum.TextXAlignment.Left
keybindsTitle.Parent = keybindsOverlay

local keybindsCloseBtn = Instance.new("TextButton")
keybindsCloseBtn.Size = UDim2.new(0, 35, 0, 35)
keybindsCloseBtn.Position = UDim2.new(1, -45, 0, 6)
keybindsCloseBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
keybindsCloseBtn.Text = "X"
keybindsCloseBtn.Font = Enum.Font.GothamBold
keybindsCloseBtn.TextColor3 = Color3.fromRGB(0, 0, 0)
keybindsCloseBtn.TextSize = 19
keybindsCloseBtn.BorderSizePixel = 0
keybindsCloseBtn.Style = Enum.ButtonStyle.Custom
keybindsCloseBtn.Parent = keybindsOverlay
Instance.new("UICorner", keybindsCloseBtn).CornerRadius = UDim.new(0, 10)

local keybindLabel = Instance.new("TextLabel")
keybindLabel.Size = UDim2.new(1, -32, 0, 25)
keybindLabel.Position = UDim2.new(0, 16, 0, 55)
keybindLabel.BackgroundTransparency = 1
keybindLabel.Text = "Dash Keybind:"
keybindLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
keybindLabel.TextSize = 15
keybindLabel.Font = Enum.Font.GothamBold
keybindLabel.TextXAlignment = Enum.TextXAlignment.Left
keybindLabel.Parent = keybindsOverlay

local keybindTextbox = Instance.new("TextBox")
keybindTextbox.Size = UDim2.new(1, -32, 0, 30)
keybindTextbox.Position = UDim2.new(0, 16, 0, 80)
keybindTextbox.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
keybindTextbox.TextColor3 = Color3.fromRGB(255, 255, 255)
keybindTextbox.PlaceholderText = "E, Q, R..."
keybindTextbox.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
keybindTextbox.BorderSizePixel = 0
keybindTextbox.Text = "E"
keybindTextbox.TextSize = 14
keybindTextbox.Font = Enum.Font.Gotham
keybindTextbox.Parent = keybindsOverlay
Instance.new("UICorner", keybindTextbox).CornerRadius = UDim.new(0, 8)

local keyInfo1KB = Instance.new("TextLabel")
keyInfo1KB.Size = UDim2.new(1, -32, 0, 24)
keyInfo1KB.Position = UDim2.new(0, 16, 0, 120)
keyInfo1KB.BackgroundTransparency = 1
keyInfo1KB.Text = "Current key: E"
keyInfo1KB.TextColor3 = Color3.fromRGB(205, 205, 205)
keyInfo1KB.TextSize = 15
keyInfo1KB.Font = Enum.Font.Gotham
keyInfo1KB.TextXAlignment = Enum.TextXAlignment.Left
keyInfo1KB.Parent = keybindsOverlay

local keyInfo2KB = Instance.new("TextLabel")
keyInfo2KB.Size = UDim2.new(1, -32, 0, 24)
keyInfo2KB.Position = UDim2.new(0, 16, 0, 146)
keyInfo2KB.BackgroundTransparency = 1
keyInfo2KB.Text = "Mobile: red dash button"
keyInfo2KB.TextColor3 = Color3.fromRGB(205, 205, 205)
keyInfo2KB.TextSize = 15
keyInfo2KB.Font = Enum.Font.Gotham
keyInfo2KB.TextXAlignment = Enum.TextXAlignment.Left
keyInfo2KB.Parent = keybindsOverlay

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

-- APPLY FUNCTIONS (size / distance / keybind)
local function applyButtonSize(newSize)
    local sizeNum = tonumber(newSize)
    if not sizeNum or sizeNum < 50 or sizeNum > 150 then
        notifyGui("Size must be 50-150")
        return false
    end
    _G.dashButtonSize = sizeNum
    dashBtn.Size = UDim2.new(0, sizeNum, 0, sizeNum)
    dashIcon.Size = UDim2.new(0, sizeNum - 15, 0, sizeNum - 15)
    dashIcon.Position = UDim2.new(0.5, -(sizeNum - 15) / 2, 0.5, -(sizeNum - 15) / 2)
    dashBtn.Position = UDim2.new(1, -(sizeNum + 15), 0.5, -sizeNum / 2)
    notifyGui("Button size set to " .. sizeNum)
    return true
end

local function applyDashDistance(newDistance)
    local distNum = tonumber(newDistance)
    if not distNum or distNum < 1 or distNum > 60 then
        notifyGui("Distance must be 1-60")
        return false
    end
    _G.dashDistance = distNum
    notifyGui("Dash distance set to " .. distNum)
    return true
end

local function applyKeybind(keyName)
    local keyMap = {
        ["E"] = Enum.KeyCode.E, ["Q"] = Enum.KeyCode.Q, ["R"] = Enum.KeyCode.R,
        ["X"] = Enum.KeyCode.X, ["C"] = Enum.KeyCode.C, ["V"] = Enum.KeyCode.V,
        ["F"] = Enum.KeyCode.F, ["G"] = Enum.KeyCode.G, ["Z"] = Enum.KeyCode.Z,
        ["T"] = Enum.KeyCode.T, ["Y"] = Enum.KeyCode.Y, ["U"] = Enum.KeyCode.U,
    }
    local upperKey = string.upper(keyName or "")
    local keycode = keyMap[upperKey]
    if keycode then
        _G.dashKeybind = keycode
        keyInfo1KB.Text = "Current key: " .. upperKey
        notifyGui("Keybind set to " .. upperKey)
        return true
    else
        notifyGui("Invalid key. Use E/Q/R/X/C/V/F/G/Z/T/Y/U")
        return false
    end
end

-- Logic: lock / open / settings / keybinds / inputs

lockButton.MouseButton1Click:Connect(function()
    uiClickSound:Play()
    dashButtonLocked = not dashButtonLocked
    dashBtn.Draggable = not dashButtonLocked
    mainFrame.Draggable = not dashButtonLocked
    openButton.Draggable = not dashButtonLocked
    lockButton.Draggable = not dashButtonLocked
    settingsOverlay.Draggable = not dashButtonLocked
    keybindsOverlay.Draggable = not dashButtonLocked

    if dashButtonLocked then
        lockButton.Text = "🔒 Locked"
        notifyGui("Dash button & GUI locked.")
    else
        lockButton.Text = "🔓 Unlocked"
        notifyGui("Dash button & GUI unlocked.")
    end
end)

dashBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
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
    settingsOverlay.Visible = true
    TweenService:Create(settingsOverlay, TweenInfo.new(0.25), {BackgroundTransparency = 0}):Play()
end)

settingsCloseBtn.MouseButton1Click:Connect(function()
    uiClickSound:Play()
    local t = TweenService:Create(settingsOverlay, TweenInfo.new(0.25), {BackgroundTransparency = 1})
    t:Play()
    t.Completed:Connect(function()
        settingsOverlay.Visible = false
    end)
end)

keybindsInfoBtn.MouseButton1Click:Connect(function()
    uiClickSound:Play()
    keybindsOverlay.Visible = true
end)

keybindsCloseBtn.MouseButton1Click:Connect(function()
    uiClickSound:Play()
    keybindsOverlay.Visible = false
end)

sizeTextbox.FocusLost:Connect(function(enterPressed)
    if enterPressed then
        applyButtonSize(sizeTextbox.Text)
    end
end)

distanceTextbox.FocusLost:Connect(function(enterPressed)
    if enterPressed then
        applyDashDistance(distanceTextbox.Text)
    end
end)

keybindTextbox.FocusLost:Connect(function(enterPressed)
    if enterPressed then
        applyKeybind(keybindTextbox.Text)
    end
end)

discordBtn.MouseButton1Click:Connect(function()
    uiClickSound:Play()
    if setclipboard then
        setclipboard("https://discord.gg/YFf3rdXbUf")
        notifyGui("Discord invite copied.")
    else
        notifyGui("Discord: https://discord.gg/YFf3rdXbUf")
    end
end)

ytBtn.MouseButton1Click:Connect(function()
    uiClickSound:Play()
    if setclipboard then
        setclipboard("https://youtube.com/@waspire")
        notifyGui("YouTube link copied.")
    else
        notifyGui("YouTube: https://youtube.com/@waspire")
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

print("subscribe to Waspire :)")
