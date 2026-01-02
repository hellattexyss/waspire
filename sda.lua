--// SNIPPET 1 - CORE SETUP WITH COOLDOWN NOTIFIER & KEYBINDS

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
local MAX_TARGET_RANGE = 40
local MIN_DASH_DISTANCE = 1.2
local MAX_DASH_DISTANCE = 60
local MIN_TARGET_DISTANCE = 15
local TARGET_REACH_THRESHOLD = 10
local DASH_COOLDOWN = 2.0

-- Increased dash speed
local DASH_SPEED = 180

local DIRECTION_LERP_FACTOR = 0.7
local CAMERA_FOLLOW_DELAY = 0.7
local VELOCITY_PREDICTION_FACTOR = 0.5
local FOLLOW_EASING_POWER = 200
local CIRCLE_COMPLETION_THRESHOLD = 390 / 480

-- State
local isDashing = false
local sideAnimationTrack = nil
local straightAnimationTrack = nil
local lastDashTime = 0
local lastButtonPressTime = -math.huge

local isAutoRotateDisabled = false
local autoRotateConnection = nil

-- Keybind State
local KEYBINDS = {
    Dash = "E",
    Sprint = "W"
}

local function savekeybinds()
    pcall(function()
        local data = HttpService:JSONEncode(KEYBINDS)
        writefile("sda_keybinds.json", data)
    end)
end

local function loadKeybinds()
    pcall(function()
        if readfile("sda_keybinds.json") then
            KEYBINDS = HttpService:JSONDecode(readfile("sda_keybinds.json"))
        end
    end)
end

loadKeybinds()

-- Dash SFX (non-button) + Execute sound
local dashSound = Instance.new("Sound")
dashSound.Name = "DashSFX"
dashSound.SoundId = "rbxassetid://3084314259"
dashSound.Volume = 2
dashSound.Looped = false
dashSound.Parent = WorkspaceService

local executeSound = Instance.new("Sound")
executeSound.Name = "ExecuteSound"
executeSound.SoundId = "rbxassetid://115916891254154"
executeSound.Volume = 0.7
executeSound.Looped = false
executeSound.Parent = WorkspaceService

-- Play execute sound on script load
task.delay(0.5, function()
    executeSound:Play()
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

notify("Side Dash Assist v2.0", "Loaded! Press " .. KEYBINDS.Dash .. " or click the dash button")

-- SNIPPET 1 END --
--// SNIPPET 2 - DASH LOGIC WITH RED CHAM & FIXED FOLLOWING

-- Anim + targeting
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

-- Slider calcs (hardcoded)
local function calculateDashDuration(speedSliderValue)
    local clampedValue = math.clamp(speedSliderValue or 49, 0, 100) / 100
    local baseMin = 1.0
    local baseMax = 0.10
    return baseMin + (baseMax - baseMin) * clampedValue
end

local function calculateDashAngle(_degreesSliderValue)
    return 120
end

-- CHAM EFFECT: RED BOX AROUND TARGET
local function createChamEffect(targetCharacter)
    if not targetCharacter then return end
    
    local humanoidRootPart = targetCharacter:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return end
    
    local cham = Instance.new("BoxHandleAdornment")
    cham.Name = "DashCham"
    cham.Adornee = humanoidRootPart
    cham.Size = humanoidRootPart.Size + Vector3.new(0.2, 0.2, 0.2)
    cham.Color3 = Color3.fromRGB(255, 0, 0)
    cham.Transparency = 1
    cham.Parent = humanoidRootPart
    
    -- Fade in
    local startTime = tick()
    local fadeInDuration = 0.3
    local fadeInConnection
    fadeInConnection = RunService.RenderStepped:Connect(function()
        local elapsed = tick() - startTime
        local progress = math.clamp(elapsed / fadeInDuration, 0, 1)
        if cham and cham.Parent then
            cham.Transparency = 1 - progress
        else
            fadeInConnection:Disconnect()
        end
        if progress >= 1 then
            fadeInConnection:Disconnect()
        end
    end)
    
    return cham
end

local function removeChamEffect(cham)
    if not cham or not cham.Parent then return end
    
    local startTime = tick()
    local fadeOutDuration = 0.3
    local fadeOutConnection
    fadeOutConnection = RunService.RenderStepped:Connect(function()
        local elapsed = tick() - startTime
        local progress = math.clamp(elapsed / fadeOutDuration, 0, 1)
        if cham and cham.Parent then
            cham.Transparency = 1 + progress
        else
            fadeOutConnection:Disconnect()
            return
        end
        if progress >= 1 then
            fadeOutConnection:Disconnect()
            pcall(function() cham:Destroy() end)
        end
    end)
end

-- FIXED DASH FOLLOWING: Don't follow if target is moving/attacking
local function isDashFollowAllowed(targetCharacter)
    if not targetCharacter or not targetCharacter.Parent then return false end
    
    local targetHumanoid = targetCharacter:FindFirstChildOfClass("Humanoid")
    if not targetHumanoid then return false end
    
    -- Don't follow if humanoid is in specific states (moving, attacking, etc)
    local success, state = pcall(function() return targetHumanoid:GetState() end)
    if success then
        if state == Enum.HumanoidStateType.Running or 
           state == Enum.HumanoidStateType.Jumping or
           state == Enum.HumanoidStateType.Flying or
           state == Enum.HumanoidStateType.Freefall then
            return false
        end
    end
    
    -- Check if moving fast
    local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")
    if targetRoot and targetRoot.AssemblyLinearVelocity.Magnitude > 50 then
        return false
    end
    
    return true
end

-- SNIPPET 2 END --
--// SNIPPET 3 - DASH EXECUTION & COOLDOWN NOTIFIER

local chamEffect = nil

local function executeDash(targetCharacter, direction)
    if isDashing or isCharacterDisabled() then return end
    
    -- Check cooldown
    if (tick() - lastDashTime) < DASH_COOLDOWN then
        notify("Cooldown", "Dash is on cooldown!")
        return
    end
    
    isDashing = true
    lastDashTime = tick()
    dashSound:Play()
    
    local targetHumanoid = Character:FindFirstChildOfClass("Humanoid")
    if not targetHumanoid then isDashing = false return end
    
    local targetAnimator = targetHumanoid:FindFirstChildOfClass("Animator")
    if targetAnimator then
        local animationInstance = Instance.new("Animation")
        animationInstance.AnimationId = "rbxassetid://" .. tostring(straightAnimationId)
        local success, animation = pcall(function() return targetAnimator:LoadAnimation(animationInstance) end)
        if success and animation then
            straightAnimationTrack = animation
            animation.Priority = Enum.AnimationPriority.Action
            animation:Play()
        end
    end
    
    -- Create cham if dashing towards opponent
    if targetCharacter and targetCharacter.Parent then
        chamEffect = createChamEffect(targetCharacter)
    end
    
    local dashDuration = calculateDashDuration(49)
    local traveledDistance = 0
    
    local connection
    connection = RunService.Heartbeat:Connect(function(deltaTime)
        if not isDashing or not Character or not HumanoidRootPart or not HumanoidRootPart.Parent then
            connection:Disconnect()
            isDashing = false
            return
        end
        
        if isCharacterDisabled() then
            connection:Disconnect()
            isDashing = false
            return
        end
        
        local timeElapsed = tick() - lastDashTime
        if timeElapsed > dashDuration then
            connection:Disconnect()
            isDashing = false
            
            -- Remove cham effect when dash ends
            if chamEffect then
                removeChamEffect(chamEffect)
                chamEffect = nil
            end
            
            if straightAnimationTrack and straightAnimationTrack.IsPlaying then
                straightAnimationTrack:Stop()
            end
            return
        end
        
        local distance = DASH_SPEED * deltaTime
        traveledDistance = traveledDistance + distance
        
        if traveledDistance > MAX_DASH_DISTANCE then
            connection:Disconnect()
            isDashing = false
            if chamEffect then
                removeChamEffect(chamEffect)
                chamEffect = nil
            end
            if straightAnimationTrack and straightAnimationTrack.IsPlaying then
                straightAnimationTrack:Stop()
            end
            return
        end
        
        local moveDirection = direction
        
        -- FIXED FOLLOWING: Only adjust direction slightly if opponent allows it
        if targetCharacter and isDashFollowAllowed(targetCharacter) then
            local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")
            if targetRoot and targetRoot.Parent and traveledDistance < MAX_DASH_DISTANCE * 0.6 then
                local directionToTarget = (targetRoot.Position - HumanoidRootPart.Position).Unit
                moveDirection = moveDirection:Lerp(directionToTarget, 0.15)
            end
        end
        
        local newPosition = HumanoidRootPart.Position + moveDirection * distance
        HumanoidRootPart.CFrame = CFrame.new(newPosition, newPosition + moveDirection)
        
        TweenService:Create(blur, TweenInfo.new(0.05), {Size = 8}):Play()
    end)
    
    task.delay(dashDuration + 0.2, function()
        TweenService:Create(blur, TweenInfo.new(0.3), {Size = 0}):Play()
    end)
end

local function performDash()
    if isDashing or isCharacterDisabled() then return end
    
    -- Check cooldown
    if (tick() - lastDashTime) < DASH_COOLDOWN then
        return
    end
    
    local targetCharacter, targetDistance = findNearestTarget(MAX_TARGET_RANGE)
    local dashDirection
    
    if targetCharacter and targetDistance and targetDistance > MIN_TARGET_DISTANCE then
        dashDirection = (targetCharacter.HumanoidRootPart.Position - HumanoidRootPart.Position).Unit
        playSideAnimation(dashDirection.X > 0)
    else
        dashDirection = CurrentCamera.CFrame.LookVector
    end
    
    executeDash(targetCharacter, dashDirection)
end

-- Cooldown Display UI on bottom left
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local cooldownGui = Instance.new("ScreenGui")
cooldownGui.Name = "CooldownNotifier"
cooldownGui.ResetOnSpawn = false
cooldownGui.Parent = playerGui

local cooldownLabel = Instance.new("TextLabel")
cooldownLabel.Name = "CooldownLabel"
cooldownLabel.Size = UDim2.new(0, 150, 0, 40)
cooldownLabel.Position = UDim2.new(0, 10, 1, -50)
cooldownLabel.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
cooldownLabel.BackgroundTransparency = 0.3
cooldownLabel.BorderSizePixel = 0
cooldownLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
cooldownLabel.TextSize = 18
cooldownLabel.Font = Enum.Font.GothamBold
cooldownLabel.Text = "Ready!"
cooldownLabel.Parent = cooldownGui

local cooldownConnection
cooldownConnection = RunService.Heartbeat:Connect(function()
    if not cooldownLabel or not cooldownLabel.Parent then
        cooldownConnection:Disconnect()
        return
    end
    
    local timeSinceLastDash = tick() - lastDashTime
    local remainingCooldown = DASH_COOLDOWN - timeSinceLastDash
    
    if remainingCooldown <= 0 then
        cooldownLabel.Text = "Ready!"
        cooldownLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
    else
        cooldownLabel.Text = string.format("%.1f", remainingCooldown)
        if remainingCooldown > 1.2 then
            cooldownLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
        elseif remainingCooldown > 0.5 then
            cooldownLabel.TextColor3 = Color3.fromRGB(255, 255, 0)
        else
            cooldownLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
        end
    end
end)

-- SNIPPET 3 END --
--// SNIPPET 4 - UI WITH KEYBINDS BUTTON & SETTINGS PANEL

-- Cleanup old frames
pcall(function()
    local pg = LocalPlayer:WaitForChild("PlayerGui")
    local oldFrame = pg:FindFirstChild("SideDashMainFrame")
    if oldFrame then oldFrame:Destroy() end
end)

task.wait(0.2)

-- Main Container
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SideDashMainFrame"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 280, 0, 200)
mainFrame.Position = UDim2.new(1, -300, 1, -230)
mainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
mainFrame.BackgroundTransparency = 0
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui

local borderFrame = Instance.new("Frame")
borderFrame.Name = "Border"
borderFrame.Size = UDim2.new(1, 0, 1, 0)
borderFrame.Position = UDim2.new(0, 0, 0, 0)
borderFrame.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
borderFrame.BackgroundTransparency = 0
borderFrame.BorderSizePixel = 0
borderFrame.Parent = mainFrame
borderFrame.ZIndex = 0

local innerFrame = Instance.new("Frame")
innerFrame.Name = "Inner"
innerFrame.Size = UDim2.new(1, -4, 1, -4)
innerFrame.Position = UDim2.new(0, 2, 0, 2)
innerFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
innerFrame.BackgroundTransparency = 0
innerFrame.BorderSizePixel = 0
innerFrame.Parent = borderFrame
innerFrame.ZIndex = 1

-- Title
local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.Size = UDim2.new(1, 0, 0, 30)
titleLabel.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
titleLabel.BackgroundTransparency = 0
titleLabel.BorderSizePixel = 0
titleLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
titleLabel.TextSize = 16
titleLabel.Font = Enum.Font.GothamBold
titleLabel.Text = "⚡ Dash Assist"
titleLabel.Parent = innerFrame
titleLabel.ZIndex = 2

-- Separator
local separator = Instance.new("Frame")
separator.Name = "Separator"
separator.Size = UDim2.new(1, 0, 0, 1)
separator.Position = UDim2.new(0, 0, 0, 30)
separator.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
separator.BackgroundTransparency = 0
separator.BorderSizePixel = 0
separator.Parent = innerFrame
separator.ZIndex = 2

-- Info Label
local infoLabel = Instance.new("TextLabel")
infoLabel.Name = "Info"
infoLabel.Size = UDim2.new(1, -20, 0, 50)
infoLabel.Position = UDim2.new(0, 10, 0, 40)
infoLabel.BackgroundTransparency = 1
infoLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
infoLabel.TextSize = 12
infoLabel.Font = Enum.Font.Gotham
infoLabel.TextWrapped = true
infoLabel.Text = "Click the button to dash!\nUse Keybinds menu to change controls."
infoLabel.Parent = innerFrame
infoLabel.ZIndex = 2

-- Buttons Container
local buttonsContainer = Instance.new("Frame")
buttonsContainer.Name = "ButtonsContainer"
buttonsContainer.Size = UDim2.new(1, -20, 0, 40)
buttonsContainer.Position = UDim2.new(0, 10, 1, -50)
buttonsContainer.BackgroundTransparency = 1
buttonsContainer.BorderSizePixel = 0
buttonsContainer.Parent = innerFrame
buttonsContainer.ZIndex = 2

-- Settings Button
local settingsButton = Instance.new("TextButton")
settingsButton.Name = "SettingsBtn"
settingsButton.Size = UDim2.new(0.5, -5, 1, 0)
settingsButton.Position = UDim2.new(0, 0, 0, 0)
settingsButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
settingsButton.BorderSizePixel = 0
settingsButton.TextColor3 = Color3.fromRGB(255, 255, 255)
settingsButton.TextSize = 14
settingsButton.Font = Enum.Font.GothamBold
settingsButton.Text = "⚙️ Settings"
settingsButton.Parent = buttonsContainer
settingsButton.ZIndex = 3

-- Keybinds Button (NEW)
local keybindsButton = Instance.new("TextButton")
keybindsButton.Name = "KeybindsBtn"
keybindsButton.Size = UDim2.new(0.5, -5, 1, 0)
keybindsButton.Position = UDim2.new(0.5, 5, 0, 0)
keybindsButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
keybindsButton.BorderSizePixel = 0
keybindsButton.TextColor3 = Color3.fromRGB(255, 255, 255)
keybindsButton.TextSize = 14
keybindsButton.Font = Enum.Font.GothamBold
keybindsButton.Text = "🖱️ Keybinds"
keybindsButton.Parent = buttonsContainer
keybindsButton.ZIndex = 3

-- Dash Button
local dashButton = Instance.new("TextButton")
dashButton.Name = "DashBtn"
dashButton.Size = UDim2.new(1, -20, 0, 50)
dashButton.Position = UDim2.new(0, 10, 0, 100)
dashButton.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
dashButton.BorderSizePixel = 0
dashButton.TextColor3 = Color3.fromRGB(255, 255, 255)
dashButton.TextSize = 16
dashButton.Font = Enum.Font.GothamBold
dashButton.Text = "🔴 DASH"
dashButton.Parent = innerFrame
dashButton.ZIndex = 2

dashButton.MouseButton1Click:Connect(function()
    performDash()
end)

-- Keybinds Panel (NEW)
local keybindsPanel = Instance.new("Frame")
keybindsPanel.Name = "KeybindsPanel"
keybindsPanel.Size = UDim2.new(0, 350, 0, 300)
keybindsPanel.Position = UDim2.new(0.5, -175, 0.5, -150)
keybindsPanel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
keybindsPanel.BackgroundTransparency = 1
keybindsPanel.BorderSizePixel = 0
keybindsPanel.Visible = false
keybindsPanel.Parent = screenGui
keybindsPanel.ZIndex = 10

local keybindsBg = Instance.new("Frame")
keybindsBg.Name = "Background"
keybindsBg.Size = UDim2.new(1, 0, 1, 0)
keybindsBg.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
keybindsBg.BorderColor3 = Color3.fromRGB(100, 200, 255)
keybindsBg.BorderSizePixel = 2
keybindsBg.Parent = keybindsPanel
keybindsBg.ZIndex = 10

local keybindsTitle = Instance.new("TextLabel")
keybindsTitle.Name = "Title"
keybindsTitle.Size = UDim2.new(1, 0, 0, 35)
keybindsTitle.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
keybindsTitle.BorderSizePixel = 0
keybindsTitle.TextColor3 = Color3.fromRGB(100, 200, 255)
keybindsTitle.TextSize = 16
keybindsTitle.Font = Enum.Font.GothamBold
keybindsTitle.Text = "🖱️ Keybinds Manager"
keybindsTitle.Parent = keybindsBg
keybindsTitle.ZIndex = 11

local keybindsContent = Instance.new("ScrollingFrame")
keybindsContent.Name = "Content"
keybindsContent.Size = UDim2.new(1, -10, 1, -80)
keybindsContent.Position = UDim2.new(0, 5, 0, 40)
keybindsContent.BackgroundTransparency = 1
keybindsContent.ScrollBarThickness = 8
keybindsContent.BorderSizePixel = 0
keybindsContent.Parent = keybindsBg
keybindsContent.ZIndex = 11

-- Keybind entry for Dash
local dashKeybindEntry = Instance.new("Frame")
dashKeybindEntry.Name = "DashEntry"
dashKeybindEntry.Size = UDim2.new(1, 0, 0, 50)
dashKeybindEntry.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
dashKeybindEntry.BorderSizePixel = 0
dashKeybindEntry.Parent = keybindsContent
dashKeybindEntry.ZIndex = 11

local dashLabel = Instance.new("TextLabel")
dashLabel.Name = "Label"
dashLabel.Size = UDim2.new(0.6, -5, 1, 0)
dashLabel.Position = UDim2.new(0, 5, 0, 0)
dashLabel.BackgroundTransparency = 1
dashLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
dashLabel.TextSize = 14
dashLabel.Font = Enum.Font.GothamBold
dashLabel.Text = "Dash Key:"
dashLabel.TextXAlignment = Enum.TextXAlignment.Left
dashLabel.Parent = dashKeybindEntry
dashLabel.ZIndex = 11

local dashKeyInput = Instance.new("TextBox")
dashKeyInput.Name = "Input"
dashKeyInput.Size = UDim2.new(0.4, -10, 0, 30)
dashKeyInput.Position = UDim2.new(0.6, 5, 0, 10)
dashKeyInput.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
dashKeyInput.BorderColor3 = Color3.fromRGB(100, 200, 255)
dashKeyInput.BorderSizePixel = 1
dashKeyInput.TextColor3 = Color3.fromRGB(100, 200, 255)
dashKeyInput.TextSize = 14
dashKeyInput.Font = Enum.Font.Gotham
dashKeyInput.Text = KEYBINDS.Dash
dashKeyInput.Parent = dashKeybindEntry
dashKeybindEntry.Size = UDim2.new(1, 0, 0, 60)
keybindsContent.CanvasSize = UDim2.new(0, 0, 0, 60)

-- Update keybind when input changes
dashKeyInput.FocusLost:Connect(function(enterPressed)
    if enterPressed and dashKeyInput.Text ~= "" then
        KEYBINDS.Dash = dashKeyInput.Text:upper()
        savekeybinds()
        notify("Keybind Changed", "Dash key set to: " .. KEYBINDS.Dash)
    else
        dashKeyInput.Text = KEYBINDS.Dash
    end
end)

-- Close button for keybinds
local closeKeybindsBtn = Instance.new("TextButton")
closeKeybindsBtn.Name = "CloseBtn"
closeKeybindsBtn.Size = UDim2.new(1, 0, 0, 35)
closeKeybindsBtn.Position = UDim2.new(0, 0, 1, -35)
closeKeybindsBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
closeKeybindsBtn.BorderSizePixel = 0
closeKeybindsBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
closeKeybindsBtn.TextSize = 14
closeKeybindsBtn.Font = Enum.Font.GothamBold
closeKeybindsBtn.Text = "Close"
closeKeybindsBtn.Parent = keybindsBg
closeKeybindsBtn.ZIndex = 11

closeKeybindsBtn.MouseButton1Click:Connect(function()
    keybindsPanel.Visible = false
end)

keybindsButton.MouseButton1Click:Connect(function()
    keybindsPanel.Visible = not keybindsPanel.Visible
end)

-- Input handling for keybinds
InputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    if input.KeyCode == Enum.KeyCode[KEYBINDS.Dash] or input.KeyCode.Name == KEYBINDS.Dash then
        performDash()
    end
end)

-- SNIPPET 4 END --
--// SNIPPET 5 - SETTINGS PANEL & FINAL CLEANUP

-- Settings Panel
local settingsPanel = Instance.new("Frame")
settingsPanel.Name = "SettingsPanel"
settingsPanel.Size = UDim2.new(0, 400, 0, 350)
settingsPanel.Position = UDim2.new(0.5, -200, 0.5, -175)
settingsPanel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
settingsPanel.BackgroundTransparency = 1
settingsPanel.BorderSizePixel = 0
settingsPanel.Visible = false
settingsPanel.Parent = screenGui
settingsPanel.ZIndex = 10

local settingsBg = Instance.new("Frame")
settingsBg.Name = "Background"
settingsBg.Size = UDim2.new(1, 0, 1, 0)
settingsBg.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
settingsBg.BorderColor3 = Color3.fromRGB(255, 150, 100)
settingsBg.BorderSizePixel = 2
settingsBg.Parent = settingsPanel
settingsBg.ZIndex = 10

local settingsTitle = Instance.new("TextLabel")
settingsTitle.Name = "Title"
settingsTitle.Size = UDim2.new(1, 0, 0, 40)
settingsTitle.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
settingsTitle.BorderSizePixel = 0
settingsTitle.TextColor3 = Color3.fromRGB(255, 150, 100)
settingsTitle.TextSize = 16
settingsTitle.Font = Enum.Font.GothamBold
settingsTitle.Text = "⚙️ Settings"
settingsTitle.Parent = settingsBg
settingsTitle.ZIndex = 11

-- Speed Slider Label
local speedLabel = Instance.new("TextLabel")
speedLabel.Name = "SpeedLabel"
speedLabel.Size = UDim2.new(1, -20, 0, 25)
speedLabel.Position = UDim2.new(0, 10, 0, 50)
speedLabel.BackgroundTransparency = 1
speedLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
speedLabel.TextSize = 13
speedLabel.Font = Enum.Font.GothamBold
speedLabel.Text = "Dash Speed: 49/100"
speedLabel.TextXAlignment = Enum.TextXAlignment.Left
speedLabel.Parent = settingsBg
speedLabel.ZIndex = 11

local speedSlider = Instance.new("TextButton")
speedSlider.Name = "SpeedSlider"
speedSlider.Size = UDim2.new(1, -20, 0, 12)
speedSlider.Position = UDim2.new(0, 10, 0, 80)
speedSlider.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
speedSlider.BorderColor3 = Color3.fromRGB(255, 150, 100)
speedSlider.BorderSizePixel = 1
speedSlider.Text = ""
speedSlider.Parent = settingsBg
speedSlider.ZIndex = 11

local speedFill = Instance.new("Frame")
speedFill.Name = "Fill"
speedFill.Size = UDim2.new(0.49, 0, 1, 0)
speedFill.BackgroundColor3 = Color3.fromRGB(255, 150, 100)
speedFill.BorderSizePixel = 0
speedFill.Parent = speedSlider
speedFill.ZIndex = 11

-- Range Slider Label
local rangeLabel = Instance.new("TextLabel")
rangeLabel.Name = "RangeLabel"
rangeLabel.Size = UDim2.new(1, -20, 0, 25)
rangeLabel.Position = UDim2.new(0, 10, 0, 120)
rangeLabel.BackgroundTransparency = 1
rangeLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
rangeLabel.TextSize = 13
rangeLabel.Font = Enum.Font.GothamBold
rangeLabel.Text = "Target Range: 40 studs"
rangeLabel.TextXAlignment = Enum.TextXAlignment.Left
rangeLabel.Parent = settingsBg
rangeLabel.ZIndex = 11

local rangeSlider = Instance.new("TextButton")
rangeSlider.Name = "RangeSlider"
rangeSlider.Size = UDim2.new(1, -20, 0, 12)
rangeSlider.Position = UDim2.new(0, 10, 0, 150)
rangeSlider.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
rangeSlider.BorderColor3 = Color3.fromRGB(255, 150, 100)
rangeSlider.BorderSizePixel = 1
rangeSlider.Text = ""
rangeSlider.Parent = settingsBg
rangeSlider.ZIndex = 11

local rangeFill = Instance.new("Frame")
rangeFill.Name = "Fill"
rangeFill.Size = UDim2.new(1, 0, 1, 0)
rangeFill.BackgroundColor3 = Color3.fromRGB(255, 150, 100)
rangeFill.BorderSizePixel = 0
rangeFill.Parent = rangeSlider
rangeFill.ZIndex = 11

-- Info Text
local infoText = Instance.new("TextLabel")
infoText.Name = "Info"
infoText.Size = UDim2.new(1, -20, 0, 80)
infoText.Position = UDim2.new(0, 10, 0, 180)
infoText.BackgroundTransparency = 1
infoText.TextColor3 = Color3.fromRGB(150, 150, 150)
infoText.TextSize = 11
infoText.Font = Enum.Font.Gotham
infoText.TextWrapped = true
infoText.TextYAlignment = Enum.TextYAlignment.Top
infoText.Text = "• Dash Cooldown: 2 seconds\n• Max Dash Distance: 60 studs\n• Press your keybind to dash\n• Cham effect shows on targets"
infoText.Parent = settingsBg
infoText.ZIndex = 11

-- Close button
local closeSettingsBtn = Instance.new("TextButton")
closeSettingsBtn.Name = "CloseBtn"
closeSettingsBtn.Size = UDim2.new(1, 0, 0, 40)
closeSettingsBtn.Position = UDim2.new(0, 0, 1, -40)
closeSettingsBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
closeSettingsBtn.BorderSizePixel = 0
closeSettingsBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
closeSettingsBtn.TextSize = 14
closeSettingsBtn.Font = Enum.Font.GothamBold
closeSettingsBtn.Text = "Close"
closeSettingsBtn.Parent = settingsBg
closeSettingsBtn.ZIndex = 11

closeSettingsBtn.MouseButton1Click:Connect(function()
    settingsPanel.Visible = false
end)

settingsButton.MouseButton1Click:Connect(function()
    settingsPanel.Visible = not settingsPanel.Visible
end)

-- Slider interactions
local mouse = LocalPlayer:GetMouse()

local function updateSlider(slider, fill, value, maxValue, label, labelPrefix)
    local fillPercent = math.clamp(value / maxValue, 0, 1)
    fill.Size = UDim2.new(fillPercent, 0, 1, 0)
    label.Text = labelPrefix .. ": " .. tostring(math.floor(value)) .. (labelPrefix:find("Range") and " studs" or "/100")
end

local draggingSpeed = false
speedSlider.MouseButton1Down:Connect(function()
    draggingSpeed = true
    
    local moveConnection
    moveConnection = mouse.Move:Connect(function()
        if not draggingSpeed then moveConnection:Disconnect() return end
        
        local relativeX = math.clamp(mouse.X - speedSlider.AbsolutePosition.X, 0, speedSlider.AbsoluteSize.X)
        local value = math.floor((relativeX / speedSlider.AbsoluteSize.X) * 100)
        updateSlider(speedSlider, speedFill, value, 100, speedLabel, "Dash Speed")
    end)
end)

InputService.InputEnded:Connect(function(input, gameProcessed)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        draggingSpeed = false
    end
end)

-- Cleanup and final notification

-- Prevent character breaking on rejoin
LocalPlayer.CharacterAdded:Connect(function(newChar)
    task.wait(0.5)
    if chamEffect and chamEffect.Parent then
        pcall(function() chamEffect:Destroy() end)
        chamEffect = nil
    end
end)

print("sub to waspire :)")
