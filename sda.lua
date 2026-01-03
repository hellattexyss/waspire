--[[ 
    SIDE DASH ASSIST v2.1 - FIXED & OPTIMIZED
    ✅ Proper ESP cham fade in/out (purple -> target -> red -> original)
    ✅ Fixed range detection (4 studs default, 5 max)
    ✅ Live button size changer
    ✅ Live dash range changer
    ✅ No more "no target found" bugs
    PRODUCTION READY
]]

-- ═══════════════════════════════════════════════════════════════════════════════
-- SNIPPET 1 - CORE SETUP + PROPER ESP CHAM
-- ═══════════════════════════════════════════════════════════════════════════════

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
local WorkspaceService = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")
local Lighting = game:GetService("Lighting")
local CoreGui = game:FindService("CoreGui")

local LocalPlayer = PlayersService.LocalPlayer
local CurrentCamera = WorkspaceService.CurrentCamera
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")
local Humanoid = Character:FindFirstChildOfClass("Humanoid")

-- ESP/CHAM SYSTEM - PROPER FADE IN/OUT
local espConnections = {}
local Storage = Instance.new("Folder")
Storage.Parent = CoreGui
Storage.Name = "Highlight_Storage"

local function createPlayerCham(plr)
    if plr == LocalPlayer then return end
    
    local Highlight = Instance.new("Highlight")
    Highlight.Name = plr.Name
    Highlight.FillColor = Color3.fromRGB(175, 25, 255)
    Highlight.DepthMode = "AlwaysOnTop"
    Highlight.FillTransparency = 0.5
    Highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    Highlight.OutlineTransparency = 0
    Highlight.Parent = Storage
    
    local plrchar = plr.Character
    if plrchar then
        Highlight.Adornee = plrchar
    end

    espConnections[plr] = plr.CharacterAdded:Connect(function(char)
        Highlight.Adornee = char
    end)
end

PlayersService.PlayerAdded:Connect(createPlayerCham)
for i, v in next, PlayersService:GetPlayers() do
    if v ~= LocalPlayer then
        createPlayerCham(v)
    end
end

PlayersService.PlayerRemoving:Connect(function(plr)
    local plrname = plr.Name
    if Storage[plrname] then
        Storage[plrname]:Destroy()
    end
    if espConnections[plr] then
        espConnections[plr]:Disconnect()
    end
end)

local function isCharacterDisabled()
    if not (Humanoid and Humanoid.Parent) then return false end
    if Humanoid.Health <= 0 then return true end
    if Humanoid.PlatformStand then return true end
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

-- CONSTANTS (WILL BE UPDATED BY SETTINGS)
local MAX_TARGET_RANGE = 4
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
local DASH_COOLDOWN = 2.0

local isDashing = false
local sideAnimationTrack = nil
local straightAnimationTrack = nil
local lastButtonPressTime = -math.huge
local isAutoRotateDisabled = false
local autoRotateConnection = nil

-- RED CHAM SYSTEM - PROPER FADE IN/OUT
local chammedTarget = nil
local originalColors = {}
local chamTweens = {}

local function addRedCham(target)
    if not target or not target:IsA("Model") then return end
    if chammedTarget == target then return end
    
    if chammedTarget then
        removeRedCham()
    end
    
    chammedTarget = target
    originalColors = {}
    
    for _, part in pairs(target:GetDescendants()) do
        if part:IsA("BasePart") then
            originalColors[part] = part.Color
            
            if chamTweens[part] then
                pcall(function() chamTweens[part]:Cancel() end)
            end
            
            local tween = TweenService:Create(part, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Color = Color3.fromRGB(255, 0, 0)})
            chamTweens[part] = tween
            tween:Play()
        end
    end
end

function removeRedCham()
    if chammedTarget then
        for part, origColor in pairs(originalColors) do
            if part and part.Parent then
                if chamTweens[part] then
                    pcall(function() chamTweens[part]:Cancel() end)
                end
                
                local tween = TweenService:Create(part, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Color = origColor})
                chamTweens[part] = tween
                tween:Play()
            end
        end
        originalColors = {}
        chammedTarget = nil
    end
end

local dashSound = Instance.new("Sound")
dashSound.Name = "DashSFX"
dashSound.SoundId = "rbxassetid://3084314259"
dashSound.Volume = 2
dashSound.Looped = false
dashSound.Parent = WorkspaceService

local function setupAutoRotateProtection()
    if autoRotateConnection then pcall(function() autoRotateConnection:Disconnect() end) end
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

local function getAngleDifference(angle1, angle2)
    local difference = angle1 - angle2
    while math.pi < difference do difference = difference - 2 * math.pi end
    while difference < -math.pi do difference = difference + 2 * math.pi end
    return difference
end

local function easeInOutCubic(progress)
    return 1 - (1 - math.clamp(progress, 0, 1)) ^ 3
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

local loadSound = Instance.new("Sound")
loadSound.Name = "LoadSound"
loadSound.SoundId = "rbxassetid://115916891254154"
loadSound.Volume = 1
loadSound.Parent = WorkspaceService
loadSound:Play()

notify("Side Dash Assist v2.1", "Loading... Please wait!")
-- ═══════════════════════════════════════════════════════════════════════════════
-- SNIPPET 2 - DASH MECHANICS & FIXED TARGETING
-- ═══════════════════════════════════════════════════════════════════════════════

_G.dashKeybind = Enum.KeyCode.E
_G.dashRange = 4
_G.buttonSize = 110

local function getHumanoidAndAnimator()
    if not (Character and Character.Parent) then return nil, nil end
    local foundHumanoid = Character:FindFirstChildOfClass("Humanoid")
    if not foundHumanoid then return nil, nil end
    local animator = foundHumanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
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
    maxRange = maxRange or _G.dashRange
    local nearestTarget, nearestDistance = nil, math.huge
    if not HumanoidRootPart then return nil end
    local rootPosition = HumanoidRootPart.Position

    for _, player in pairs(PlayersService:GetPlayers()) do
        if player ~= LocalPlayer then
            local playerChar = player.Character
            if playerChar then
                local playerRoot = playerChar:FindFirstChild("HumanoidRootPart")
                local playerHumanoid = playerChar:FindFirstChild("Humanoid")
                
                if playerRoot and playerHumanoid and playerHumanoid.Health > 0 then
                    local distance = (playerRoot.Position - rootPosition).Magnitude
                    if distance <= maxRange and distance < nearestDistance then
                        nearestTarget = playerChar
                        nearestDistance = distance
                    end
                end
            end
        end
    end

    if not nearestTarget then
        for _, descendant in pairs(WorkspaceService:GetDescendants()) do
            if descendant:IsA("Model") and not PlayersService:GetPlayerFromCharacter(descendant) then
                local npcHumanoid = descendant:FindFirstChild("Humanoid")
                local npcRoot = descendant:FindFirstChild("HumanoidRootPart")
                
                if npcHumanoid and npcRoot and npcHumanoid.Health > 0 then
                    local distance = (npcRoot.Position - rootPosition).Magnitude
                    if distance <= maxRange and distance < nearestDistance then
                        nearestTarget = descendant
                        nearestDistance = distance
                    end
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

local function calculateDashDistance(gapSliderValue)
    return 1 + 11 * (math.clamp(gapSliderValue or 14, 0, 100) / 100)
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
                if (targetRoot.Position - HumanoidRootPart.Position).Magnitude > _G.dashRange then
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
    return findNearestTarget(_G.dashRange)
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

    local capturedTargetPos = targetRootPart.Position
    local isActive = true
    local heartbeatConnection

    heartbeatConnection = RunService.Heartbeat:Connect(function()
        if isActive and targetRootPart and targetRootPart.Parent and HumanoidRootPart and HumanoidRootPart.Parent then
            local directionToTarget = capturedTargetPos - HumanoidRootPart.Position
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
                    aimCharacterAtTarget(capturedTargetPos, 0.56)
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
    
    local timeSinceDash = tick() - lastButtonPressTime
    if timeSinceDash < DASH_COOLDOWN then
        return
    end
    
    isDashing = true
    addRedCham(targetCharacter)

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

        local function startDashEndSequence()
            if not hasCompletedCircle then
                hasCompletedCircle = true
                task.delay(CAMERA_FOLLOW_DELAY, function()
                    shouldEndDash = true
                    restoreAutoRotate()
                    lastButtonPressTime = tick()
                    removeRedCham()
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

            local currentTargetPosition = targetRoot.Position
            local playerGroundY = HumanoidRootPart.Position.Y

            local currentAngle = angleToTarget + directionMultiplier * dashAngleRad * easeInOutCubic(progress)
            local circleX = currentTargetPosition.X + clampedRadius * math.cos(currentAngle)
            local circleZ = currentTargetPosition.Z + clampedRadius * math.sin(currentAngle)
            local newPosition = Vector3.new(circleX, playerGroundY, circleZ)

            if targetRoot then
                currentTargetPosition = targetRoot.Position or currentTargetPosition
            end

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
        removeRedCham()
    end
end

InputService.InputBegan:Connect(function(inp, gp)
    if gp or isDashing or isCharacterDisabled() then return end
    if inp.UserInputType == Enum.UserInputType.Keyboard and inp.KeyCode == _G.dashKeybind then
        local target = getCurrentTarget()
        if target then
            performCircularDash(target)
        else
            notify("No Target", "❌ No player within " .. _G.dashRange .. " studs!")
        end
    end
end)
-- ═══════════════════════════════════════════════════════════════════════════════
-- SNIPPET 3 - GUI CREATION & STYLING
-- ═══════════════════════════════════════════════════════════════════════════════

local gui = Instance.new("ScreenGui")
gui.Name = "SideDashAssistGUI"
gui.ResetOnSpawn = false
gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

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

local cooldownLabel = Instance.new("TextLabel")
cooldownLabel.Name = "CooldownLabel"
cooldownLabel.Size = UDim2.new(0, 110, 0, 35)
cooldownLabel.Position = UDim2.new(0, 10, 1, -50)
cooldownLabel.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
cooldownLabel.BackgroundTransparency = 0.2
cooldownLabel.BorderSizePixel = 0
cooldownLabel.Text = "Ready!"
cooldownLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
cooldownLabel.TextSize = 13
cooldownLabel.Font = Enum.Font.GothamBold
cooldownLabel.Parent = gui
Instance.new("UICorner", cooldownLabel).CornerRadius = UDim.new(0, 8)

RunService.Heartbeat:Connect(function()
    if cooldownLabel and cooldownLabel.Parent then
        local timeSinceDash = tick() - lastButtonPressTime
        local cooldownRemaining = math.max(0, DASH_COOLDOWN - timeSinceDash)
        
        if cooldownRemaining <= 0.01 then
            cooldownLabel.Text = "Ready!"
            cooldownLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
        else
            cooldownLabel.Text = string.format("%.1fs", cooldownRemaining)
            
            if cooldownRemaining > 1.2 then
                cooldownLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
            elseif cooldownRemaining > 0.5 then
                cooldownLabel.TextColor3 = Color3.fromRGB(255, 255, 0)
            else
                cooldownLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
            end
        end
    end
end)

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 380, 0, 140)
mainFrame.Position = UDim2.new(0.5, -190, 0.12, 0)
mainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
mainFrame.BackgroundTransparency = 0
mainFrame.BorderSizePixel = 0
mainFrame.Visible = true
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
borderFrame.BackgroundTransparency = 0
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
versionLabel.Text = "v2.1"
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

local keybindsBtn = Instance.new("TextButton")
keybindsBtn.Size = UDim2.new(0, 36, 0, 36)
keybindsBtn.Position = UDim2.new(0, 56, 1, -46)
keybindsBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
keybindsBtn.Text = "🖱️"
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

local dashBtn = Instance.new("Frame")
dashBtn.Name = "DashButton_Final"
dashBtn.Size = UDim2.new(0, _G.buttonSize, 0, _G.buttonSize)
dashBtn.Position = UDim2.new(1, -130, 0.5, -55)
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
dashIcon.Size = UDim2.new(0, _G.buttonSize - 15, 0, _G.buttonSize - 15)
dashIcon.Position = UDim2.new(0.5, -(_G.buttonSize - 15) / 2, 0.5, -(_G.buttonSize - 15) / 2)
dashIcon.Image = "rbxassetid://12443244342"
dashIcon.Parent = dashBtn
-- ═══════════════════════════════════════════════════════════════════════════════
-- SNIPPET 4 - OVERLAYS & LIVE SETTINGS
-- ═══════════════════════════════════════════════════════════════════════════════

local settingsOverlay = Instance.new("Frame")
settingsOverlay.Name = "SettingsOverlay"
settingsOverlay.Size = UDim2.new(0, 280, 0, 320)
settingsOverlay.Position = UDim2.new(0, 30, 0.25, 0)
settingsOverlay.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
settingsOverlay.BackgroundTransparency = 0.1
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
keybindFrame.Size = UDim2.new(1, -32, 0, 85)
keybindFrame.Position = UDim2.new(0, 16, 0, 50)
keybindFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
keybindFrame.BorderSizePixel = 0
keybindFrame.Parent = settingsOverlay
Instance.new("UICorner", keybindFrame).CornerRadius = UDim.new(0, 14)

local keyTitle = Instance.new("TextLabel")
keyTitle.Size = UDim2.new(1, -20, 0, 25)
keyTitle.Position = UDim2.new(0, 10, 0, 8)
keyTitle.BackgroundTransparency = 1
keyTitle.Text = "Keybind Info"
keyTitle.TextColor3 = Color3.fromRGB(230, 230, 230)
keyTitle.TextSize = 17
keyTitle.Font = Enum.Font.GothamBold
keyTitle.TextXAlignment = Enum.TextXAlignment.Left
keyTitle.Parent = keybindFrame

local keyInfo1 = Instance.new("TextLabel")
keyInfo1.Size = UDim2.new(1, -20, 0, 20)
keyInfo1.Position = UDim2.new(0, 10, 0, 33)
keyInfo1.BackgroundTransparency = 1
keyInfo1.Text = "PC Dash Key: E"
keyInfo1.TextColor3 = Color3.fromRGB(205, 205, 205)
keyInfo1.TextSize = 14
keyInfo1.Font = Enum.Font.Gotham
keyInfo1.TextXAlignment = Enum.TextXAlignment.Left
keyInfo1.Parent = keybindFrame

local keyInfo2 = Instance.new("TextLabel")
keyInfo2.Size = UDim2.new(1, -20, 0, 20)
keyInfo2.Position = UDim2.new(0, 10, 0, 53)
keyInfo2.BackgroundTransparency = 1
keyInfo2.Text = "Mobile Button :)"
keyInfo2.TextColor3 = Color3.fromRGB(205, 205, 205)
keyInfo2.TextSize = 14
keyInfo2.Font = Enum.Font.Gotham
keyInfo2.TextXAlignment = Enum.TextXAlignment.Left
keyInfo2.Parent = keybindFrame

-- BUTTON SIZE SETTING
local buttonSizeLabel = Instance.new("TextLabel")
buttonSizeLabel.Size = UDim2.new(1, -32, 0, 20)
buttonSizeLabel.Position = UDim2.new(0, 16, 0, 145)
buttonSizeLabel.BackgroundTransparency = 1
buttonSizeLabel.Text = "Button Size"
buttonSizeLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
buttonSizeLabel.TextSize = 14
buttonSizeLabel.Font = Enum.Font.GothamBold
buttonSizeLabel.TextXAlignment = Enum.TextXAlignment.Left
buttonSizeLabel.Parent = settingsOverlay

local buttonSizeInput = Instance.new("TextBox")
buttonSizeInput.Size = UDim2.new(1, -32, 0, 28)
buttonSizeInput.Position = UDim2.new(0, 16, 0, 165)
buttonSizeInput.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
buttonSizeInput.TextColor3 = Color3.fromRGB(255, 255, 255)
buttonSizeInput.PlaceholderText = "50-180"
buttonSizeInput.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
buttonSizeInput.BorderSizePixel = 0
buttonSizeInput.Text = tostring(_G.buttonSize)
buttonSizeInput.TextSize = 13
buttonSizeInput.Font = Enum.Font.Gotham
buttonSizeInput.Parent = settingsOverlay
Instance.new("UICorner", buttonSizeInput).CornerRadius = UDim.new(0, 8)

buttonSizeInput.FocusLost:Connect(function(enterPressed)
    if enterPressed then
        local size = tonumber(buttonSizeInput.Text)
        if size and size >= 50 and size <= 180 then
            _G.buttonSize = size
            dashBtn.Size = UDim2.new(0, size, 0, size)
            dashIcon.Size = UDim2.new(0, size - 15, 0, size - 15)
            dashIcon.Position = UDim2.new(0.5, -(size - 15) / 2, 0.5, -(size - 15) / 2)
            notify("Button Size", "✅ Changed to " .. size)
            buttonSizeInput.Text = tostring(size)
        else
            notify("Error", "❌ Size must be 50-180")
            buttonSizeInput.Text = tostring(_G.buttonSize)
        end
    end
end)

-- DASH RANGE SETTING
local dashRangeLabel = Instance.new("TextLabel")
dashRangeLabel.Size = UDim2.new(1, -32, 0, 20)
dashRangeLabel.Position = UDim2.new(0, 16, 0, 200)
dashRangeLabel.BackgroundTransparency = 1
dashRangeLabel.Text = "Dash Range (Max 5)"
dashRangeLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
dashRangeLabel.TextSize = 14
dashRangeLabel.Font = Enum.Font.GothamBold
dashRangeLabel.TextXAlignment = Enum.TextXAlignment.Left
dashRangeLabel.Parent = settingsOverlay

local dashRangeInput = Instance.new("TextBox")
dashRangeInput.Size = UDim2.new(1, -32, 0, 28)
dashRangeInput.Position = UDim2.new(0, 16, 0, 220)
dashRangeInput.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
dashRangeInput.TextColor3 = Color3.fromRGB(255, 255, 255)
dashRangeInput.PlaceholderText = "0.1-5 studs"
dashRangeInput.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
dashRangeInput.BorderSizePixel = 0
dashRangeInput.Text = tostring(_G.dashRange)
dashRangeInput.TextSize = 13
dashRangeInput.Font = Enum.Font.Gotham
dashRangeInput.Parent = settingsOverlay
Instance.new("UICorner", dashRangeInput).CornerRadius = UDim.new(0, 8)

dashRangeInput.FocusLost:Connect(function(enterPressed)
    if enterPressed then
        local range = tonumber(dashRangeInput.Text)
        if range and range >= 0.1 and range <= 5 then
            _G.dashRange = range
            MAX_TARGET_RANGE = range
            notify("Dash Range", "✅ Changed to " .. range .. " studs")
            dashRangeInput.Text = tostring(range)
        else
            notify("Error", "❌ Range must be 0.1-5 studs")
            dashRangeInput.Text = tostring(_G.dashRange)
        end
    end
end)

local comingSoon = Instance.new("TextLabel")
comingSoon.Size = UDim2.new(1, 0, 0, 25)
comingSoon.Position = UDim2.new(0, 0, 0, 290)
comingSoon.BackgroundTransparency = 1
comingSoon.Text = "More coming soon..."
comingSoon.TextColor3 = Color3.fromRGB(255, 60, 60)
comingSoon.TextSize = 13
comingSoon.Font = Enum.Font.GothamBold
comingSoon.TextXAlignment = Enum.TextXAlignment.Center
comingSoon.Parent = settingsOverlay

-- KEYBINDS OVERLAY
local keybindsOverlay = Instance.new("Frame")
keybindsOverlay.Name = "KeybindsOverlay"
keybindsOverlay.Size = UDim2.new(0, 280, 0, 280)
keybindsOverlay.Position = UDim2.new(1, -310, 0.25, 0)
keybindsOverlay.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
keybindsOverlay.BackgroundTransparency = 0.1
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
keybindLabel.Position = UDim2.new(0, 16, 0, 50)
keybindLabel.BackgroundTransparency = 1
keybindLabel.Text = "Dash Keybind:"
keybindLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
keybindLabel.TextSize = 14
keybindLabel.Font = Enum.Font.GothamBold
keybindLabel.TextXAlignment = Enum.TextXAlignment.Left
keybindLabel.Parent = keybindsOverlay

local keybindTextbox = Instance.new("TextBox")
keybindTextbox.Size = UDim2.new(1, -32, 0, 32)
keybindTextbox.Position = UDim2.new(0, 16, 0, 75)
keybindTextbox.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
keybindTextbox.TextColor3 = Color3.fromRGB(255, 255, 255)
keybindTextbox.PlaceholderText = "Enter key (E, Q, R, etc)"
keybindTextbox.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
keybindTextbox.BorderSizePixel = 0
keybindTextbox.Text = "E"
keybindTextbox.TextSize = 14
keybindTextbox.Font = Enum.Font.Gotham
keybindTextbox.Parent = keybindsOverlay
Instance.new("UICorner", keybindTextbox).CornerRadius = UDim.new(0, 8)

local currentKeyLabel = Instance.new("TextLabel")
currentKeyLabel.Size = UDim2.new(1, -32, 0, 24)
currentKeyLabel.Position = UDim2.new(0, 16, 0, 115)
currentKeyLabel.BackgroundTransparency = 1
currentKeyLabel.Text = "Current Key: E"
currentKeyLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
currentKeyLabel.TextSize = 12
currentKeyLabel.Font = Enum.Font.Gotham
currentKeyLabel.TextXAlignment = Enum.TextXAlignment.Left
currentKeyLabel.Parent = keybindsOverlay

local keyInfoBox = Instance.new("Frame")
keyInfoBox.Size = UDim2.new(1, -32, 0, 95)
keyInfoBox.Position = UDim2.new(0, 16, 0, 145)
keyInfoBox.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
keyInfoBox.BorderSizePixel = 0
keyInfoBox.Parent = keybindsOverlay
Instance.new("UICorner", keyInfoBox).CornerRadius = UDim.new(0, 8)

local keyInfoText = Instance.new("TextLabel")
keyInfoText.Size = UDim2.new(1, -12, 1, -12)
keyInfoText.Position = UDim2.new(0, 6, 0, 6)
keyInfoText.BackgroundTransparency = 1
keyInfoText.Text = "Valid Keys:\nE, Q, R, X, C, V, F, G, Z, T, Y, U\n\nPress Enter to apply"
keyInfoText.TextColor3 = Color3.fromRGB(200, 200, 200)
keyInfoText.TextSize = 11
keyInfoText.Font = Enum.Font.Gotham
keyInfoText.TextXAlignment = Enum.TextXAlignment.Left
keyInfoText.TextYAlignment = Enum.TextYAlignment.Top
keyInfoText.TextWrapped = true
keyInfoText.Parent = keyInfoBox

local keyMap = {
    ["E"] = Enum.KeyCode.E, ["Q"] = Enum.KeyCode.Q, ["R"] = Enum.KeyCode.R,
    ["X"] = Enum.KeyCode.X, ["C"] = Enum.KeyCode.C, ["V"] = Enum.KeyCode.V,
    ["F"] = Enum.KeyCode.F, ["G"] = Enum.KeyCode.G, ["Z"] = Enum.KeyCode.Z,
    ["T"] = Enum.KeyCode.T, ["Y"] = Enum.KeyCode.Y, ["U"] = Enum.KeyCode.U,
}

local function notifyGui(text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "Side Dash Assist",
            Text = text,
            Duration = 2,
        })
    end)
end

keybindTextbox.FocusLost:Connect(function(enterPressed)
    if enterPressed then
        local inputKey = string.upper(keybindTextbox.Text or "")
        if keyMap[inputKey] then
            _G.dashKeybind = keyMap[inputKey]
            currentKeyLabel.Text = "Current Key: " .. inputKey
            notifyGui("✅ Keybind set to " .. inputKey)
            keybindTextbox.Text = ""
        else
            notifyGui("❌ Invalid Key! Use: E, Q, R, X, C, V, F, G, Z, T, Y, U")
        end
    end
end)

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
        notifyGui("GUI locked in place")
    else
        lockButton.Text = "🔓 Unlocked"
        notifyGui("GUI can be dragged")
    end
end)

dashBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dashClickSound:Play()
        local target = getCurrentTarget()
        if target then
            performCircularDash(target)
        else
            notifyGui("No Target", "❌ No player within " .. _G.dashRange .. " studs!")
        end
    end
end)

closeBtn.MouseButton1Click:Connect(function()
    uiClickSound:Play()
    mainFrame.Visible = false
    openButton.Visible = true
    lockButton.Visible = true
end)

minimizeBtn.MouseButton1Click:Connect(function()
    uiClickSound:Play()
    mainFrame.Visible = false
    openButton.Visible = true
    lockButton.Visible = true
end)

openButton.MouseButton1Click:Connect(function()
    uiClickSound:Play()
    openButton.Visible = false
    lockButton.Visible = false
    mainFrame.Visible = true
end)

settingsBtn.MouseButton1Click:Connect(function()
    uiClickSound:Play()
    settingsOverlay.Visible = not settingsOverlay.Visible
end)

settingsCloseBtn.MouseButton1Click:Connect(function()
    uiClickSound:Play()
    settingsOverlay.Visible = false
end)

keybindsBtn.MouseButton1Click:Connect(function()
    uiClickSound:Play()
    keybindsOverlay.Visible = not keybindsOverlay.Visible
end)

keybindsCloseBtn.MouseButton1Click:Connect(function()
    uiClickSound:Play()
    keybindsOverlay.Visible = false
end)

discordBtn.MouseButton1Click:Connect(function()
    uiClickSound:Play()
    if setclipboard then
        setclipboard("https://discord.gg/YFf3rdXbUf")
        notifyGui("Discord invite copied!")
    else
        notifyGui("Discord: discord.gg/YFf3rdXbUf")
    end
end)

ytBtn.MouseButton1Click:Connect(function()
    uiClickSound:Play()
    if setclipboard then
        setclipboard("https://youtube.com/@waspire")
        notifyGui("YouTube link copied!")
    else
        notifyGui("YouTube: @waspire")
    end
end)
