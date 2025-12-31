--// COMPLETE SIDE DASH ASSIST v2.1 - FULL FIX (ONE SNIPPET)

-- Cleanup
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
local WorkspaceService = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")
local Lighting = game:GetService("Lighting")

local LocalPlayer = PlayersService.LocalPlayer
local CurrentCamera = WorkspaceService.CurrentCamera
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")
local Humanoid = Character:FindFirstChildOfClass("Humanoid")

_G.dashButtonSize = 90
_G.dashKeybind = Enum.KeyCode.E
_G.dashCooldown = 2.0
_G.dashDistance = 0.5

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

-- VALID ANIMATION IDS ONLY
local ANIMATION_IDS = {
    Left = 10480796021,
    Right = 10480793962,
    Straight = 10479335397
}

local leftAnimationId = ANIMATION_IDS.Left
local rightAnimationId = ANIMATION_IDS.Right
local straightAnimationId = ANIMATION_IDS.Straight

local BLOCKED_ANIMATION_ID = 10449761463
local MAX_TARGET_RANGE = 3.5  -- STRICT 3.5 STUDS
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

-- RED CHAM OVERLAY SYSTEM (OUTSIDE PLAYER)
local chamOverlays = {}
local doubleClickLocked = nil

local function createChamOverlay(player)
    if not player or not player.Character then return end
    if chamOverlays[player] then return end
    
    chamOverlays[player] = {}
    local char = player.Character
    
    for _, part in pairs(char:GetDescendants()) do
        if part:IsA("BasePart") and part ~= char:FindFirstChild("HumanoidRootPart") and part.Parent then
            local overlay = Instance.new("Part")
            overlay.Name = "ChamOverlay"
            overlay.Shape = Enum.PartType.Block
            overlay.CanCollide = false
            overlay.CanQuery = false
            overlay.CanTouch = false
            overlay.CFrame = part.CFrame
            overlay.Size = part.Size + Vector3.new(0.1, 0.1, 0.1)  -- SLIGHTLY LARGER (OUTSIDE)
            overlay.Color = Color3.fromRGB(255, 0, 0)
            overlay.Transparency = 0.75
            overlay.Material = Enum.Material.SmoothPlastic
            overlay.TopSurface = Enum.SurfaceType.Smooth
            overlay.BottomSurface = Enum.SurfaceType.Smooth
            overlay.Parent = char
            
            local weld = Instance.new("WeldConstraint")
            weld.Part0 = part
            weld.Part1 = overlay
            weld.Parent = overlay
            
            table.insert(chamOverlays[player], overlay)
        end
    end
end

local function removeChamOverlay(player)
    if not chamOverlays[player] then return end
    
    for _, overlay in pairs(chamOverlays[player]) do
        if overlay and overlay.Parent then
            pcall(function() overlay:Destroy() end)
        end
    end
    
    chamOverlays[player] = nil
end

local function findNearestTarget(maxRange)
    maxRange = maxRange or MAX_TARGET_RANGE
    local nearestTarget, nearestDistance = nil, math.huge
    if not HumanoidRootPart then return nil end
    local rootPosition = HumanoidRootPart.Position

    for _, player in pairs(PlayersService:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local targetRoot = player.Character:FindFirstChild("HumanoidRootPart")
            local targetHumanoid = player.Character:FindFirstChild("Humanoid")
            if targetRoot and targetHumanoid and targetHumanoid.Health > 0 then
                local distance = (targetRoot.Position - rootPosition).Magnitude
                if distance < nearestDistance and distance <= maxRange then
                    nearestTarget = player.Character
                    nearestDistance = distance
                end
            end
        end
    end

    return nearestTarget, nearestDistance
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

notify("Side Dash Assist v2.1", "Loaded successfully!")

-- ANIMATIONS & TARGETING
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
            pcall(function() loadedAnimation.Priority = Enum.AnimationPriority.Action end)
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

local function calculateDashDuration(speedSliderValue)
    local clampedValue = math.clamp(speedSliderValue or 49, 0, 100) / 100
    local baseMin = 1.0
    local baseMax = 0.10
    return baseMin + (baseMax - baseMin) * clampedValue
end

local function calculateDashDistance(_gapSliderValue)
    return _G.dashDistance
end

local settingsValues = {["Dash speed"] = 49, ["Dash Degrees"] = 32, ["Dash gap"] = 14}
local lockedTargetPlayer = nil

PlayersService.PlayerRemoving:Connect(function(removedPlayer)
    if lockedTargetPlayer == removedPlayer then
        lockedTargetPlayer = nil
    end
    if doubleClickLocked and PlayersService:GetPlayerFromCharacter(doubleClickLocked) == removedPlayer then
        doubleClickLocked = nil
    end
end)

local function getCurrentTarget()
    -- IF DOUBLE-CLICK LOCKED, USE THAT (WITH RANGE CHECK)
    if doubleClickLocked and doubleClickLocked.Parent then
        local targetRoot = doubleClickLocked:FindFirstChild("HumanoidRootPart")
        local targetHumanoid = doubleClickLocked:FindFirstChild("Humanoid")
        
        if targetRoot and targetHumanoid and targetHumanoid.Health > 0 and HumanoidRootPart then
            local distance = (targetRoot.Position - HumanoidRootPart.Position).Magnitude
            if distance <= MAX_TARGET_RANGE then
                return doubleClickLocked
            else
                notify("Out of Range", "Locked target is " .. string.format("%.1f", distance) .. " studs away (max: 3.5)!")
                return nil
            end
        else
            doubleClickLocked = nil
        end
    end
    
    -- AUTO-TARGET CLOSEST PLAYER
    return findNearestTarget(MAX_TARGET_RANGE)
end

local function aimCharacterAtTarget(targetPosition, lerpFactor)
    lerpFactor = lerpFactor or 0.7
    pcall(function()
        if not HumanoidRootPart or not HumanoidRootPart.Parent then return end
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
            lerpedDirection = Vector3.new(1, characterLookVector.Y, 0)
        end
        
        local newCFrame = CFrame.new(characterPosition, characterPosition + lerpedDirection.Unit)
        if newCFrame and newCFrame:IsA("CFrame") then
            HumanoidRootPart.CFrame = newCFrame
        end
    end)
end

local function isBlockedAnimationPlaying()
    if not Character or not Character.Parent then return false end
    local humanoid = Character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then return false end
    
    for _, track in pairs(animator:GetPlayingAnimationTracks()) do
        if track and track.IsPlaying and track.Animation then
            local animId = track.Animation.AnimationId
            if animId and string.find(animId, tostring(BLOCKED_ANIMATION_ID)) then
                return true
            end
        end
    end
    return false
end

-- DASH MOVEMENT (FIXED CFRAME)
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

local function performDashMovement(targetRootPart, dashSpeed)
    if not targetRootPart or not HumanoidRootPart then return end
    
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

    if straightAnimationId then
        local characterHumanoid, characterAnimator = getHumanoidAndAnimator()
        if characterHumanoid and characterAnimator then
            local straightAnimationInstance = Instance.new("Animation")
            straightAnimationInstance.Name = "StraightDashAnim"
            straightAnimationInstance.AnimationId = "rbxassetid://" .. tostring(straightAnimationId)
            local success, loadedAnim = pcall(function()
                return characterAnimator:LoadAnimation(straightAnimationInstance)
            end)
            if success and loadedAnim then
                pcall(function() loadedAnim.Priority = Enum.AnimationPriority.Movement end)
                pcall(function() loadedAnim.Looped = false end)
                pcall(function() loadedAnim:Play() end)
                straightAnimationTrack = loadedAnim
            end
        end
    end

    pcall(function()
        if dashSound then dashSound:Stop() dashSound:Play() end
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
                        local newPos = HumanoidRootPart.Position
                        local newLookat = newPos + horizontalDirection.Unit
                        local cf = CFrame.new(newPos, newLookat)
                        if cf then HumanoidRootPart.CFrame = cf end
                    end
                end)
                pcall(function() aimCharacterAtTarget(targetPosition, 0.56) end)
            else
                isActive = false
                heartbeatConnection:Disconnect()
                pcall(function() if linearVelocity and linearVelocity.Parent then linearVelocity:Destroy() end end)
                pcall(function() if attachment and attachment.Parent then attachment:Destroy() end end)
            end
        else
            isActive = false
            if heartbeatConnection then heartbeatConnection:Disconnect() end
            pcall(function() if linearVelocity and linearVelocity.Parent then linearVelocity:Destroy() end end)
            pcall(function() if attachment and attachment.Parent then attachment:Destroy() end end)
        end
    end)
end

local function smoothlyAimAtTarget(targetRootPart, duration)
    if not targetRootPart then return end
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
                    if HumanoidRootPart and HumanoidRootPart.Parent then
                        local characterPosition = HumanoidRootPart.Position
                        local characterLookVector = HumanoidRootPart.CFrame.LookVector
                        local directionToTarget = predictedPosition - characterPosition
                        local horizontalDirection = Vector3.new(directionToTarget.X, 0, directionToTarget.Z)
                        
                        if horizontalDirection.Magnitude < 0.001 then
                            horizontalDirection = Vector3.new(1, 0, 0)
                        end
                        
                        local targetDirection = horizontalDirection.Unit
                        local finalLookVector = characterLookVector:Lerp(Vector3.new(targetDirection.X, characterLookVector.Y, targetDirection.Z).Unit, easedProgress)
                        
                        local newCFrame = CFrame.new(characterPosition, characterPosition + finalLookVector)
                        if newCFrame then HumanoidRootPart.CFrame = newCFrame end
                    end
                end)
                if progress >= 1 then aimTweenConnection:Disconnect() end
            else
                aimTweenConnection:Disconnect()
            end
        end)
    end
end

local function performCircularDash(targetCharacter)
    if not targetCharacter or not targetCharacter:FindFirstChild("HumanoidRootPart") or not HumanoidRootPart then return end
    if isDashing or isCharacterDisabled() then return end
    
    if isBlockedAnimationPlaying() then
        notify("Blocked", "Cannot dash while animating")
        return
    end
    
    local currentTime = tick()
    local timeSinceLastDash = currentTime - lastButtonPressTime
    
    if timeSinceLastDash < _G.dashCooldown then
        return
    end
    
    -- STRICT 3.5 STUD RANGE CHECK BEFORE DASH
    local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")
    if not targetRoot then return end
    local distanceToTarget = (targetRoot.Position - HumanoidRootPart.Position).Magnitude
    if distanceToTarget > MAX_TARGET_RANGE then
        notify("Out of Range", "Target is " .. string.format("%.1f", distanceToTarget) .. " studs away (max: 3.5)!")
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
    local dashAngle = 120
    local dashAngleRad = math.rad(dashAngle)
    local dashDistance = math.clamp(calculateDashDistance(settingsValues["Dash gap"]), MIN_DASH_DISTANCE, MAX_DASH_DISTANCE)

    if MIN_TARGET_DISTANCE <= distanceToTarget then
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
            if not Character or not HumanoidRootPart then 
                movementConnection:Disconnect()
                return 
            end
            
            -- CONTINUOUS RANGE CHECK
            if targetRoot and targetRoot.Parent and HumanoidRootPart and HumanoidRootPart.Parent then
                local currentDistance = (targetRoot.Position - HumanoidRootPart.Position).Magnitude
                if currentDistance > MAX_TARGET_RANGE then
                    movementConnection:Disconnect()
                    notify("Out of Range", "Target left range during dash!")
                    isDashing = false
                    restoreAutoRotate()
                    return
                end
            end
            
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
                local cf = CFrame.new(newPosition, newPosition + Vector3.new(math.cos(finalCharacterAngle), 0, math.sin(finalCharacterAngle)))
                if cf then HumanoidRootPart.CFrame = cf end
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
        else
            notify("No Target", "No enemies in range! (Max: 3.5 studs)")
        end
    end
end)

-- GUI SETUP
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

local loadSound = Instance.new("Sound")
loadSound.Name = "LoadSound"
loadSound.SoundId = "rbxassetid://87437544236708"
loadSound.Volume = 1
loadSound.Parent = gui

-- COOLDOWN LABEL - BOTTOM LEFT
local cooldownLabel = Instance.new("TextLabel")
cooldownLabel.Name = "CooldownLabel"
cooldownLabel.Size = UDim2.new(0, 100, 0, 30)
cooldownLabel.Position = UDim2.new(0, 10, 1, -50)
cooldownLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
cooldownLabel.BackgroundTransparency = 0.3
cooldownLabel.BorderSizePixel = 0
cooldownLabel.Text = "Ready"
cooldownLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
cooldownLabel.TextSize = 11
cooldownLabel.Font = Enum.Font.GothamBold
cooldownLabel.Parent = gui
Instance.new("UICorner", cooldownLabel).CornerRadius = UDim.new(0, 8)

-- Main frame
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 380, 0, 140)
mainFrame.Position = UDim2.new(0.5, -190, 0.12, 0)
mainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
mainFrame.BackgroundTransparency = 0
mainFrame.BorderSizePixel = 0
mainFrame.Visible = false
mainFrame.Parent = gui

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
versionLabel.Text = "V2.1"
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
closeBtn.ZIndex = 100
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
minimizeBtn.ZIndex = 100
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
settingsBtn.ZIndex = 100
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
keybindsInfoBtn.ZIndex = 100
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
discordBtn.ZIndex = 100
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
ytBtn.ZIndex = 100
ytBtn.Parent = mainFrame
Instance.new("UICorner", ytBtn).CornerRadius = UDim.new(0, 10)
local ytGradient = Instance.new("UIGradient", ytBtn)
ytGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 0, 0))
})
ytGradient.Rotation = 90

-- Settings overlay WITH FULL CONTENT
local settingsOverlay = Instance.new("Frame")
settingsOverlay.Name = "SettingsOverlay"
settingsOverlay.Size = UDim2.new(0, 320, 0, 400)
settingsOverlay.Position = UDim2.new(0, 40, 0.2, 0)
settingsOverlay.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
settingsOverlay.BackgroundTransparency = 0
settingsOverlay.BorderSizePixel = 0
settingsOverlay.Visible = false
settingsOverlay.Parent = gui
settingsOverlay.ZIndex = 50
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
settingsCloseBtn.ZIndex = 100
settingsCloseBtn.Parent = settingsOverlay
Instance.new("UICorner", settingsCloseBtn).CornerRadius = UDim.new(0, 10)

-- BUTTON SIZE SECTION
local sizeLabel = Instance.new("TextLabel")
sizeLabel.Size = UDim2.new(1, -32, 0, 22)
sizeLabel.Position = UDim2.new(0, 16, 0, 55)
sizeLabel.BackgroundTransparency = 1
sizeLabel.Text = "Button Size (50-150):"
sizeLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
sizeLabel.TextSize = 14
sizeLabel.Font = Enum.Font.GothamBold
sizeLabel.TextXAlignment = Enum.TextXAlignment.Left
sizeLabel.Parent = settingsOverlay

local sizeTextbox = Instance.new("TextBox")
sizeTextbox.Size = UDim2.new(1, -32, 0, 35)
sizeTextbox.Position = UDim2.new(0, 16, 0, 80)
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

-- COOLDOWN SECTION
local cooldownLabel2 = Instance.new("TextLabel")
cooldownLabel2.Size = UDim2.new(1, -32, 0, 22)
cooldownLabel2.Position = UDim2.new(0, 16, 0, 130)
cooldownLabel2.BackgroundTransparency = 1
cooldownLabel2.Text = "Dash Cooldown (1-5s):"
cooldownLabel2.TextColor3 = Color3.fromRGB(230, 230, 230)
cooldownLabel2.TextSize = 14
cooldownLabel2.Font = Enum.Font.GothamBold
cooldownLabel2.TextXAlignment = Enum.TextXAlignment.Left
cooldownLabel2.Parent = settingsOverlay

local cooldownTextbox = Instance.new("TextBox")
cooldownTextbox.Size = UDim2.new(1, -32, 0, 35)
cooldownTextbox.Position = UDim2.new(0, 16, 0, 155)
cooldownTextbox.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
cooldownTextbox.TextColor3 = Color3.fromRGB(255, 255, 255)
cooldownTextbox.PlaceholderText = "2.0"
cooldownTextbox.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
cooldownTextbox.BorderSizePixel = 0
cooldownTextbox.Text = tostring(_G.dashCooldown)
cooldownTextbox.TextSize = 14
cooldownTextbox.Font = Enum.Font.Gotham
cooldownTextbox.Parent = settingsOverlay
Instance.new("UICorner", cooldownTextbox).CornerRadius = UDim.new(0, 8)

-- DISTANCE SECTION
local distanceLabel = Instance.new("TextLabel")
distanceLabel.Size = UDim2.new(1, -32, 0, 22)
distanceLabel.Position = UDim2.new(0, 16, 0, 205)
distanceLabel.BackgroundTransparency = 1
distanceLabel.Text = "Dash Distance Gap:"
distanceLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
distanceLabel.TextSize = 14
distanceLabel.Font = Enum.Font.GothamBold
distanceLabel.TextXAlignment = Enum.TextXAlignment.Left
distanceLabel.Parent = settingsOverlay

local distanceTextbox = Instance.new("TextBox")
distanceTextbox.Size = UDim2.new(1, -32, 0, 35)
distanceTextbox.Position = UDim2.new(0, 16, 0, 230)
distanceTextbox.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
distanceTextbox.TextColor3 = Color3.fromRGB(255, 255, 255)
distanceTextbox.PlaceholderText = "0.5"
distanceTextbox.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
distanceTextbox.BorderSizePixel = 0
distanceTextbox.Text = tostring(_G.dashDistance)
distanceTextbox.TextSize = 14
distanceTextbox.Font = Enum.Font.Gotham
distanceTextbox.Parent = settingsOverlay
Instance.new("UICorner", distanceTextbox).CornerRadius = UDim.new(0, 8)

-- INFO BOX
local infoBox = Instance.new("Frame")
infoBox.Size = UDim2.new(1, -32, 0, 85)
infoBox.Position = UDim2.new(0, 16, 0, 280)
infoBox.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
infoBox.BorderSizePixel = 0
infoBox.Parent = settingsOverlay
Instance.new("UICorner", infoBox).CornerRadius = UDim.new(0, 8)

local infoText = Instance.new("TextLabel")
infoText.Size = UDim2.new(1, -12, 1, -12)
infoText.Position = UDim2.new(0, 6, 0, 6)
infoText.BackgroundTransparency = 1
infoText.Text = "• Size: Button pixel size (px)\n• Cooldown: Wait time between dashes\n• Distance: Gap between you & target\n• Max Range: 3.5 studs (strict)"
infoText.TextColor3 = Color3.fromRGB(200, 200, 200)
infoText.TextSize = 12
infoText.Font = Enum.Font.Gotham
infoText.TextXAlignment = Enum.TextXAlignment.Left
infoText.TextYAlignment = Enum.TextYAlignment.Top
infoText.TextWrapped = true
infoText.Parent = infoBox

-- Keybinds overlay WITH FULL CONTENT
local keybindsOverlay = Instance.new("Frame")
keybindsOverlay.Name = "KeybindsOverlay"
keybindsOverlay.Size = UDim2.new(0, 340, 0, 420)
keybindsOverlay.Position = UDim2.new(0.5, -170, 0.3, 0)
keybindsOverlay.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
keybindsOverlay.BackgroundTransparency = 0
keybindsOverlay.BorderSizePixel = 0
keybindsOverlay.Visible = false
keybindsOverlay.Parent = gui
keybindsOverlay.ZIndex = 50
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
keybindsTitle.Text = "Keybinds & Info"
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
keybindsCloseBtn.ZIndex = 100
keybindsCloseBtn.Parent = keybindsOverlay
Instance.new("UICorner", keybindsCloseBtn).CornerRadius = UDim.new(0, 10)

-- DASH KEYBIND SECTION
local dashKeyLabel = Instance.new("TextLabel")
dashKeyLabel.Size = UDim2.new(1, -32, 0, 22)
dashKeyLabel.Position = UDim2.new(0, 16, 0, 55)
dashKeyLabel.BackgroundTransparency = 1
dashKeyLabel.Text = "Dash Keybind (PC):"
dashKeyLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
dashKeyLabel.TextSize = 14
dashKeyLabel.Font = Enum.Font.GothamBold
dashKeyLabel.TextXAlignment = Enum.TextXAlignment.Left
dashKeyLabel.Parent = keybindsOverlay

local dashKeyTextbox = Instance.new("TextBox")
dashKeyTextbox.Size = UDim2.new(1, -32, 0, 35)
dashKeyTextbox.Position = UDim2.new(0, 16, 0, 80)
dashKeyTextbox.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
dashKeyTextbox.TextColor3 = Color3.fromRGB(255, 255, 255)
dashKeyTextbox.PlaceholderText = "E, Q, R, X, C, V, F, G, Z, T, Y, U"
dashKeyTextbox.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
dashKeyTextbox.BorderSizePixel = 0
dashKeyTextbox.Text = "E"
dashKeyTextbox.TextSize = 14
dashKeyTextbox.Font = Enum.Font.Gotham
dashKeyTextbox.Parent = keybindsOverlay
Instance.new("UICorner", dashKeyTextbox).CornerRadius = UDim.new(0, 8)

-- TARGET LOCKING SECTION
local lockingLabel = Instance.new("TextLabel")
lockingLabel.Size = UDim2.new(1, -32, 0, 22)
lockingLabel.Position = UDim2.new(0, 16, 0, 130)
lockingLabel.BackgroundTransparency = 1
lockingLabel.Text = "Target Locking:"
lockingLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
lockingLabel.TextSize = 14
lockingLabel.Font = Enum.Font.GothamBold
lockingLabel.TextXAlignment = Enum.TextXAlignment.Left
lockingLabel.Parent = keybindsOverlay

local lockingInfoBox = Instance.new("Frame")
lockingInfoBox.Size = UDim2.new(1, -32, 0, 110)
lockingInfoBox.Position = UDim2.new(0, 16, 0, 155)
lockingInfoBox.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
lockingInfoBox.BorderSizePixel = 0
lockingInfoBox.Parent = keybindsOverlay
Instance.new("UICorner", lockingInfoBox).CornerRadius = UDim.new(0, 8)

local lockingInfoText = Instance.new("TextLabel")
lockingInfoText.Size = UDim2.new(1, -12, 1, -12)
lockingInfoText.Position = UDim2.new(0, 6, 0, 6)
lockingInfoText.BackgroundTransparency = 1
lockingInfoText.Text = "• Auto-targets CLOSEST enemy\n• Max range: 3.5 studs STRICT\n• Double-click player for RED CHAM lock\n• Red overlay = 75% transparent\n• Out of range = notification\n• Can't dash if target out of range"
lockingInfoText.TextColor3 = Color3.fromRGB(200, 200, 200)
lockingInfoText.TextSize = 12
lockingInfoText.Font = Enum.Font.Gotham
lockingInfoText.TextXAlignment = Enum.TextXAlignment.Left
lockingInfoText.TextYAlignment = Enum.TextYAlignment.Top
lockingInfoText.TextWrapped = true
lockingInfoText.Parent = lockingInfoBox

-- MOBILE SECTION
local mobileLabel = Instance.new("TextLabel")
mobileLabel.Size = UDim2.new(1, -32, 0, 22)
mobileLabel.Position = UDim2.new(0, 16, 0, 280)
mobileLabel.BackgroundTransparency = 1
mobileLabel.Text = "Mobile:"
mobileLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
mobileLabel.TextSize = 14
mobileLabel.Font = Enum.Font.GothamBold
mobileLabel.TextXAlignment = Enum.TextXAlignment.Left
mobileLabel.Parent = keybindsOverlay

local mobileInfoBox = Instance.new("Frame")
mobileInfoBox.Size = UDim2.new(1, -32, 0, 80)
mobileInfoBox.Position = UDim2.new(0, 16, 0, 305)
mobileInfoBox.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
mobileInfoBox.BorderSizePixel = 0
mobileInfoBox.Parent = keybindsOverlay
Instance.new("UICorner", mobileInfoBox).CornerRadius = UDim.new(0, 8)

local mobileInfoText = Instance.new("TextLabel")
mobileInfoText.Size = UDim2.new(1, -12, 1, -12)
mobileInfoText.Position = UDim2.new(0, 6, 0, 6)
mobileInfoText.BackgroundTransparency = 1
mobileInfoText.Text = "• Red dash button (right side)\n• Tap to dash at nearest target\n• Right-drag to reposition\n• Same 3.5 stud range limit"
mobileInfoText.TextColor3 = Color3.fromRGB(200, 200, 200)
mobileInfoText.TextSize = 12
mobileInfoText.Font = Enum.Font.Gotham
mobileInfoText.TextXAlignment = Enum.TextXAlignment.Left
mobileInfoText.TextYAlignment = Enum.TextYAlignment.Top
mobileInfoText.TextWrapped = true
mobileInfoText.Parent = mobileInfoBox

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
openButton.ZIndex = 100
openButton.Parent = gui
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
lockButton.ZIndex = 100
lockButton.Parent = gui
Instance.new("UICorner", lockButton).CornerRadius = UDim.new(0, 10)

local refreshBtn = Instance.new("TextButton")
refreshBtn.Name = "RefreshButton"
refreshBtn.Size = UDim2.new(0, 90, 0, 34)
refreshBtn.Position = UDim2.new(0, 210, 0.5, -17)
refreshBtn.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
refreshBtn.Text = "🔄 Refresh"
refreshBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
refreshBtn.TextSize = 13
refreshBtn.Font = Enum.Font.GothamBold
refreshBtn.BorderSizePixel = 0
refreshBtn.Visible = false
refreshBtn.Style = Enum.ButtonStyle.Custom
refreshBtn.ZIndex = 100
refreshBtn.Parent = gui
Instance.new("UICorner", refreshBtn).CornerRadius = UDim.new(0, 10)

local dashBtn = Instance.new("Frame")
dashBtn.Name = "DashButton_Final"
dashBtn.Size = UDim2.new(0, _G.dashButtonSize, 0, _G.dashButtonSize)
dashBtn.Position = UDim2.new(1, -(_G.dashButtonSize + 15), 0.5, -_G.dashButtonSize / 2)
dashBtn.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
dashBtn.BorderSizePixel = 0
dashBtn.Parent = gui
dashBtn.Active = true
dashBtn.ZIndex = 100
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
dashIcon.ZIndex = 101

-- BUTTON LOGIC
local lastClickTime = {}
local DOUBLE_CLICK_THRESHOLD = 0.25
local espButtons = {}

local function notifyGui(text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "Side Dash Assist",
            Text = text,
            Duration = 2,
        })
    end)
end

local function applyButtonSize(newSize)
    local sizeNum = tonumber(newSize)
    if not sizeNum or sizeNum < 50 or sizeNum > 150 then
        notifyGui("Size must be 50-150")
        return false
    end
    _G.dashButtonSize = sizeNum
    if dashBtn and dashBtn.Parent then
        dashBtn.Size = UDim2.new(0, sizeNum, 0, sizeNum)
        dashIcon.Size = UDim2.new(0, sizeNum - 15, 0, sizeNum - 15)
        dashIcon.Position = UDim2.new(0.5, -(sizeNum - 15) / 2, 0.5, -(sizeNum - 15) / 2)
        dashBtn.Position = UDim2.new(1, -(sizeNum + 15), 0.5, -sizeNum / 2)
    end
    notifyGui("Button size set to " .. sizeNum)
    return true
end

local function applyCooldown(newCooldown)
    local cooldownNum = tonumber(newCooldown)
    if not cooldownNum or cooldownNum < 1 or cooldownNum > 5 then
        notifyGui("Cooldown must be 1-5 seconds")
        return false
    end
    _G.dashCooldown = cooldownNum
    notifyGui("Cooldown set to " .. cooldownNum .. "s")
    return true
end

local function applyDistance(newDistance)
    local distanceNum = tonumber(newDistance)
    if not distanceNum or distanceNum < 0.1 or distanceNum > 20 then
        notifyGui("Distance must be 0.1-20")
        return false
    end
    _G.dashDistance = distanceNum
    notifyGui("Dash distance set to " .. distanceNum)
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
        notifyGui("Keybind set to " .. upperKey)
        return true
    else
        notifyGui("Invalid key. Use E/Q/R/X/C/V/F/G/Z/T/Y/U")
        return false
    end
end

local function onPlayerDoubleClick(player)
    if not lastClickTime[player] then
        lastClickTime[player] = tick()
        notifyGui("Click again to lock: " .. player.Name)
        return
    end
    
    local timeSinceLastClick = tick() - lastClickTime[player]
    if timeSinceLastClick < DOUBLE_CLICK_THRESHOLD then
        if doubleClickLocked == player.Character then
            doubleClickLocked = nil
            removeChamOverlay(player)
            notifyGui("Unlocked: " .. player.Name)
        else
            doubleClickLocked = player.Character
            createChamOverlay(player)
            notifyGui("Locked: " .. player.Name .. " (Red cham active)")
        end
        lastClickTime[player] = nil
    else
        lastClickTime[player] = tick()
    end
end

local function createESPButtonForPlayer(player)
    if espButtons[player] then return end
    
    local espBtn = Instance.new("TextButton")
    espBtn.Name = player.Name .. "_ESP"
    espBtn.Size = UDim2.new(0, 40, 0, 40)
    espBtn.BackgroundTransparency = 1
    espBtn.Text = ""
    espBtn.Parent = gui
    espBtn.ZIndex = 1
    
    espButtons[player] = {
        button = espBtn,
        lastScreenPos = Vector3.new(0, 0, 0)
    }
    
    local function updateESPButton()
        if not player or not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
            if espBtn and espBtn.Parent then
                espBtn:Destroy()
            end
            espButtons[player] = nil
            return
        end
        
        local hrp = player.Character.HumanoidRootPart
        local screenPos, onScreen = CurrentCamera:WorldToScreenPoint(hrp.Position)
        
        if onScreen then
            espBtn.Visible = true
            espBtn.Position = UDim2.new(0, screenPos.X - 20, 0, screenPos.Y - 20)
        else
            espBtn.Visible = false
        end
    end
    
    espBtn.MouseButton1Click:Connect(function()
        onPlayerDoubleClick(player)
    end)
    
    local renderLoop
    renderLoop = RunService.RenderStepped:Connect(function()
        if not espButtons[player] then
            renderLoop:Disconnect()
            return
        end
        updateESPButton()
    end)
end

-- Create ESP buttons for all players
for _, player in pairs(PlayersService:GetPlayers()) do
    if player ~= LocalPlayer then
        createESPButtonForPlayer(player)
    end
end

PlayersService.PlayerAdded:Connect(function(player)
    task.wait(0.1)
    createESPButtonForPlayer(player)
end)

PlayersService.PlayerRemoving:Connect(function(player)
    if espButtons[player] and espButtons[player].button and espButtons[player].button.Parent then
        espButtons[player].button:Destroy()
    end
    espButtons[player] = nil
    if doubleClickLocked == player.Character then
        doubleClickLocked = nil
    end
end)

-- COOLDOWN LABEL UPDATE
RunService.Heartbeat:Connect(function()
    if not cooldownLabel or not cooldownLabel.Parent then return end
    
    local timeSinceLastDash = tick() - lastButtonPressTime
    local cooldownRemaining = math.max(0, _G.dashCooldown - timeSinceLastDash)
    
    if cooldownRemaining <= 0 then
        cooldownLabel.Text = "Ready"
        cooldownLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
    else
        cooldownLabel.Text = string.format("%.2fs", cooldownRemaining)
        
        if cooldownRemaining >= 1.5 then
            cooldownLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
        elseif cooldownRemaining >= 0.5 then
            cooldownLabel.TextColor3 = Color3.fromRGB(255, 255, 0)
        else
            cooldownLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
        end
    end
end)

-- BUTTON CONNECTIONS
if lockButton then
    lockButton.MouseButton1Click:Connect(function()
        if uiClickSound then uiClickSound:Play() end
        dashButtonLocked = not dashButtonLocked
        
        if dashButtonLocked then
            lockButton.Text = "🔒 Locked"
            notifyGui("All elements locked")
        else
            lockButton.Text = "🔓 Unlocked"
            notifyGui("All elements unlocked")
        end
    end)
end

if refreshBtn then
    refreshBtn.MouseButton1Click:Connect(function()
        if uiClickSound then uiClickSound:Play() end
        if doubleClickLocked then
            removeChamOverlay(PlayersService:GetPlayerFromCharacter(doubleClickLocked))
        end
        doubleClickLocked = nil
        notifyGui("Target lock cleared")
    end)
end

if dashBtn then
    dashBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if dashClickSound then dashClickSound:Play() end
            local target = getCurrentTarget()
            if target then
                performCircularDash(target)
            else
                notifyGui("No target in range!")
            end
        end
    end)
end

if closeBtn then
    closeBtn.MouseButton1Click:Connect(function()
        if uiClickSound then uiClickSound:Play() end
        TweenService:Create(blur, TweenInfo.new(0.3), {Size = 0}):Play()
        TweenService:Create(mainFrame, TweenInfo.new(0.3), {BackgroundTransparency = 1}):Play()
        TweenService:Create(borderFrame, TweenInfo.new(0.3), {BackgroundTransparency = 1}):Play()
        task.wait(0.3)
        if mainFrame then mainFrame.Visible = false end
        if openButton then openButton.Visible = true end
        if lockButton then lockButton.Visible = true end
        if refreshBtn then refreshBtn.Visible = true end
    end)
end

if minimizeBtn then
    minimizeBtn.MouseButton1Click:Connect(function()
        if uiClickSound then uiClickSound:Play() end
        TweenService:Create(blur, TweenInfo.new(0.3), {Size = 0}):Play()
        TweenService:Create(mainFrame, TweenInfo.new(0.3), {BackgroundTransparency = 1}):Play()
        TweenService:Create(borderFrame, TweenInfo.new(0.3), {BackgroundTransparency = 1}):Play()
        task.wait(0.3)
        if mainFrame then mainFrame.Visible = false end
        if openButton then openButton.Visible = true end
        if lockButton then lockButton.Visible = true end
        if refreshBtn then refreshBtn.Visible = true end
    end)
end

if openButton then
    openButton.MouseButton1Click:Connect(function()
        if uiClickSound then uiClickSound:Play() end
        openButton.Visible = false
        if lockButton then lockButton.Visible = false end
        if refreshBtn then refreshBtn.Visible = false end
        if mainFrame then mainFrame.Visible = true end
        TweenService:Create(blur, TweenInfo.new(0.3), {Size = 12}):Play()
        TweenService:Create(mainFrame, TweenInfo.new(0.3), {BackgroundTransparency = 0}):Play()
        TweenService:Create(borderFrame, TweenInfo.new(0.3), {BackgroundTransparency = 0}):Play()
    end)
end

if settingsBtn then
    settingsBtn.MouseButton1Click:Connect(function()
        if uiClickSound then uiClickSound:Play() end
        if settingsOverlay then
            settingsOverlay.Visible = not settingsOverlay.Visible
        end
    end)
end

if settingsCloseBtn then
    settingsCloseBtn.MouseButton1Click:Connect(function()
        if uiClickSound then uiClickSound:Play() end
        if settingsOverlay then settingsOverlay.Visible = false end
    end)
end

if keybindsInfoBtn then
    keybindsInfoBtn.MouseButton1Click:Connect(function()
        if uiClickSound then uiClickSound:Play() end
        if keybindsOverlay then
            keybindsOverlay.Visible = not keybindsOverlay.Visible
        end
    end)
end

if keybindsCloseBtn then
    keybindsCloseBtn.MouseButton1Click:Connect(function()
        if uiClickSound then uiClickSound:Play() end
        if keybindsOverlay then keybindsOverlay.Visible = false end
    end)
end

if sizeTextbox then
    sizeTextbox.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            applyButtonSize(sizeTextbox.Text)
        end
    end)
end

if cooldownTextbox then
    cooldownTextbox.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            applyCooldown(cooldownTextbox.Text)
        end
    end)
end

if distanceTextbox then
    distanceTextbox.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            applyDistance(distanceTextbox.Text)
        end
    end)
end

if dashKeyTextbox then
    dashKeyTextbox.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            applyKeybind(dashKeyTextbox.Text)
        end
    end)
end

if discordBtn then
    discordBtn.MouseButton1Click:Connect(function()
        if uiClickSound then uiClickSound:Play() end
        if setclipboard then
            setclipboard("https://discord.gg/YFf3rdXbUf")
            notifyGui("Discord copied!")
        else
            notifyGui("Discord: discord.gg/YFf3rdXbUf")
        end
    end)
end

if ytBtn then
    ytBtn.MouseButton1Click:Connect(function()
        if uiClickSound then uiClickSound:Play() end
        if setclipboard then
            setclipboard("https://youtube.com/@waspire")
            notifyGui("YouTube copied!")
        else
            notifyGui("YouTube: youtube.com/@waspire")
        end
    end)
end

if mainFrame then mainFrame.Visible = true end
TweenService:Create(blur, TweenInfo.new(0.3), {Size = 12}):Play()
TweenService:Create(mainFrame, TweenInfo.new(0.3), {BackgroundTransparency = 0}):Play()
TweenService:Create(borderFrame, TweenInfo.new(0.3), {BackgroundTransparency = 0}):Play()

task.delay(0.1, function()
    if loadSound then loadSound:Play() end
end)

print("subscribe to waspire :)")
