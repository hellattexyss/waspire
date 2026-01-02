--// SNIPPET 1 - CORE SETUP + COOLDOWN INIT + EXECUTION SOUND (FIXED)

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

-- FIXED: Using VALID animation IDs with fallback
local ANIMATION_IDS = {
    LeftSide = 10480796021,
    RightSide = 10480793962,
    Straight = 10479335397
}

local leftAnimationId = ANIMATION_IDS.LeftSide
local rightAnimationId = ANIMATION_IDS.RightSide
local straightAnimationId = ANIMATION_IDS.Straight

-- Constants
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

-- COOLDOWN SYSTEM (2 seconds)
local DASH_COOLDOWN = 2
local lastDashTime = 0

-- STATE
local isDashing = false
local sideAnimationTrack = nil
local straightAnimationTrack = nil
local lastButtonPressTime = -math.huge
local isAutoRotateDisabled = false
local autoRotateConnection = nil

-- CHAMS FOR OPPONENT
local chammedTargets = {}

-- Dash SFX (non-button)
local dashSound = Instance.new("Sound")
dashSound.Name = "DashSFX"
dashSound.SoundId = "rbxassetid://3084314259"
dashSound.Volume = 2
dashSound.Looped = false
dashSound.Parent = WorkspaceService

-- EXECUTION SOUND
local executionSound = Instance.new("Sound")
executionSound.Name = "ExecutionSFX"
executionSound.SoundId = "rbxassetid://115916891254154"
executionSound.Volume = 1
executionSound.Looped = false
executionSound.Parent = WorkspaceService

task.wait(0.05)
pcall(function() 
    executionSound:Play() 
    game:GetService("Debris"):AddItem(executionSound, 2)
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

--// END SNIPPET 1 - CORE SETUP + COOLDOWN INIT + EXECUTION SOUND (FIXED)
--// SNIPPET 2 - DASH LOGIC + OPPONENT CHAMS + FIXED FOLLOW BUG

-- Anim + targeting (FIXED: Better error handling)
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

-- Slider calcs
local function calculateDashDuration(speedSliderValue)
    local clampedValue = math.clamp(speedSliderValue or 49, 0, 100) / 100
    local baseMin = 1.0
    local baseMax = 0.10
    return baseMin + (baseMax - baseMin) * clampedValue
end

local function calculateDashAngle(_degreesSliderValue)
    return 120
end

-- CHAM SYSTEM FOR OPPONENTS
local function createCham(targetPart)
    if not targetPart or not targetPart.Parent then return nil end
    
    local cham = Instance.new("BoxHandleAdornment")
    cham.Name = "OpponentCham"
    cham.Size = targetPart.Size + Vector3.new(0.1, 0.1, 0.1)
    cham.Adornee = targetPart
    cham.Color3 = Color3.fromRGB(255, 0, 0)
    cham.Transparency = 0
    cham.Parent = targetPart
    return cham
end

local function fadeChamIn(targetModel, duration)
    if not targetModel or not targetModel.Parent then return end
    
    local startTime = tick()
    local chamConnection
    chamConnection = RunService.RenderStepped:Connect(function()
        if not (targetModel and targetModel.Parent) then
            if chamConnection then chamConnection:Disconnect() end
            return
        end
        
        local elapsed = tick() - startTime
        local progress = math.clamp(elapsed / duration, 0, 1)
        
        for _, part in pairs(targetModel:GetDescendants()) do
            if part:IsA("BasePart") then
                local cham = part:FindFirstChild("OpponentCham")
                if cham and cham:IsA("BoxHandleAdornment") then
                    cham.Transparency = 1 - progress
                end
            end
        end
        
        if progress >= 1 then
            chamConnection:Disconnect()
        end
    end)
end

local function fadeChamOut(targetModel, duration)
    if not targetModel or not targetModel.Parent then return end
    
    local startTime = tick()
    local chamConnection
    chamConnection = RunService.RenderStepped:Connect(function()
        if not (targetModel and targetModel.Parent) then
            if chamConnection then chamConnection:Disconnect() end
            return
        end
        
        local elapsed = tick() - startTime
        local progress = math.clamp(elapsed / duration, 0, 1)
        
        for _, part in pairs(targetModel:GetDescendants()) do
            if part:IsA("BasePart") then
                local cham = part:FindFirstChild("OpponentCham")
                if cham and cham:IsA("BoxHandleAdornment") then
                    cham.Transparency = progress
                end
            end
        end
        
        if progress >= 1 then
            for _, part in pairs(targetModel:GetDescendants()) do
                if part:IsA("BasePart") then
                    local cham = part:FindFirstChild("OpponentCham")
                    if cham then pcall(function() cham:Destroy() end) end
                end
            end
            chamConnection:Disconnect()
        end
    end)
end

--// END SNIPPET 2 - DASH LOGIC + OPPONENT CHAMS + FIXED FOLLOW BUG
--// SNIPPET 3 - DASH EXECUTION WITH FIXED FOLLOW + COOLDOWN

local function performDash(targetCharacter, speedSliderValue)
    if isCharacterDisabled() then return end
    
    -- COOLDOWN CHECK
    local currentTime = tick()
    if currentTime - lastDashTime < DASH_COOLDOWN then
        notify("Cooldown", "Dash on cooldown!")
        return
    end
    lastDashTime = currentTime
    
    isDashing = true
    isAutoRotateDisabled = true
    
    if Humanoid then
        pcall(function() Humanoid.AutoRotate = false end)
    end
    
    local dashDuration = calculateDashDuration(speedSliderValue)
    local targetHumanoid, animator = getHumanoidAndAnimator()
    local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
    local startPosition = HumanoidRootPart.Position
    local targetPosition = targetRoot and targetRoot.Position or (HumanoidRootPart.Position + HumanoidRootPart.CFrame.LookVector * 30)
    
    -- CHAM SYSTEM
    if targetRoot then
        chammedTargets[targetCharacter] = true
        for _, part in pairs(targetCharacter:GetDescendants()) do
            if part:IsA("BasePart") and not part:FindFirstChild("OpponentCham") then
                createCham(part)
            end
        end
        fadeChamIn(targetCharacter, 0.3)
    end
    
    pcall(function() dashSound:Play() end)
    
    -- Blur effect
    local blurTween = TweenService:Create(blur, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = 30})
    pcall(function() blurTween:Play() end)
    
    local startTime = tick()
    local dashDirection = (targetPosition - startPosition).Unit
    local targetDistance = (targetPosition - startPosition).Magnitude
    local actualDistance = math.clamp(targetDistance, MIN_DASH_DISTANCE, MAX_DASH_DISTANCE)
    
    -- FIXED: Snapshot opponent position at dash START, don't follow during dash
    local snapshotTargetPos = targetRoot and targetRoot.Position or targetPosition
    
    while isDashing and tick() - startTime < dashDuration and (Character and Character.Parent) do
        if isCharacterDisabled() then break end
        
        local elapsed = tick() - startTime
        local progress = math.clamp(elapsed / dashDuration, 0, 1)
        local easedProgress = easeInOutCubic(progress)
        
        local currentPosition = startPosition:Lerp(snapshotTargetPos, easedProgress * (actualDistance / targetDistance))
        
        if HumanoidRootPart then
            HumanoidRootPart.CFrame = CFrame.new(currentPosition, currentPosition + dashDirection)
            HumanoidRootPart.Velocity = Vector3.new(0, 0, 0)
        end
        
        RunService.RenderStepped:Wait()
    end
    
    isDashing = false
    isAutoRotateDisabled = false
    
    if Humanoid then
        pcall(function() Humanoid.AutoRotate = true end)
    end
    
    -- Fade out blur
    local blurTweenOut = TweenService:Create(blur, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Size = 0})
    pcall(function() blurTweenOut:Play() end)
    
    -- CHAM FADE OUT
    if targetCharacter and chammedTargets[targetCharacter] then
        fadeChamOut(targetCharacter, 0.3)
        chammedTargets[targetCharacter] = nil
    end
end

--// END SNIPPET 3 - DASH EXECUTION WITH FIXED FOLLOW + COOLDOWN
--// SNIPPET 4 - GUI WITH COOLDOWN NOTIFIER + KEYBINDS SETTINGS

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SideDashAssistGUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndex = 50
ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

-- COOLDOWN NOTIFIER (Bottom Left)
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
cooldownLabel.Parent = ScreenGui

local cornerCooldown = Instance.new("UICorner")
cornerCooldown.CornerRadius = UDim.new(0, 8)
cornerCooldown.Parent = cooldownLabel

-- COOLDOWN LIVE UPDATE
local cooldownConnection
local function updateCooldown()
    if cooldownConnection then pcall(function() cooldownConnection:Disconnect() end) end
    
    cooldownConnection = RunService.Heartbeat:Connect(function()
        if not ScreenGui or not ScreenGui.Parent then return end
        
        local timeSinceDash = tick() - lastDashTime
        local remainingCooldown = DASH_COOLDOWN - timeSinceDash
        
        if remainingCooldown > 0 then
            local displayTime = math.ceil(remainingCooldown * 10) / 10
            cooldownLabel.Text = string.format("%.1f", displayTime) .. "s"
            
            if displayTime > 1.2 then
                cooldownLabel.TextColor3 = Color3.fromRGB(255, 0, 0) -- RED
            elseif displayTime > 0.5 then
                cooldownLabel.TextColor3 = Color3.fromRGB(255, 255, 0) -- YELLOW
            else
                cooldownLabel.TextColor3 = Color3.fromRGB(0, 255, 0) -- GREEN
            end
        else
            cooldownLabel.Text = "Ready!"
            cooldownLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
        end
    end)
end

updateCooldown()

-- MAIN BUTTON (DASH)
local dashButton = Instance.new("TextButton")
dashButton.Name = "DashButton"
dashButton.Size = UDim2.new(0, 60, 0, 60)
dashButton.Position = UDim2.new(1, -80, 1, -80)
dashButton.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
dashButton.TextColor3 = Color3.fromRGB(255, 255, 255)
dashButton.TextSize = 24
dashButton.Font = Enum.Font.GothamBold
dashButton.Text = "💨"
dashButton.BorderSizePixel = 0
dashButton.Parent = ScreenGui

local cornerDash = Instance.new("UICorner")
cornerDash.CornerRadius = UDim.new(0, 10)
cornerDash.Parent = dashButton

-- SETTINGS BUTTON
local settingsButton = Instance.new("TextButton")
settingsButton.Name = "SettingsButton"
settingsButton.Size = UDim2.new(0, 60, 0, 60)
settingsButton.Position = UDim2.new(1, -150, 1, -80)
settingsButton.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
settingsButton.TextColor3 = Color3.fromRGB(255, 255, 255)
settingsButton.TextSize = 24
settingsButton.Font = Enum.Font.GothamBold
settingsButton.Text = "⚙️"
settingsButton.BorderSizePixel = 0
settingsButton.Parent = ScreenGui

local cornerSettings = Instance.new("UICorner")
cornerSettings.CornerRadius = UDim.new(0, 10)
cornerSettings.Parent = settingsButton

-- KEYBINDS BUTTON (NEW)
local keybindsButton = Instance.new("TextButton")
keybindsButton.Name = "KeybindsButton"
keybindsButton.Size = UDim2.new(0, 60, 0, 60)
keybindsButton.Position = UDim2.new(1, -220, 1, -80)
keybindsButton.BackgroundColor3 = Color3.fromRGB(70, 130, 180)
keybindsButton.TextColor3 = Color3.fromRGB(255, 255, 255)
keybindsButton.TextSize = 24
keybindsButton.Font = Enum.Font.GothamBold
keybindsButton.Text = "🖱️"
keybindsButton.BorderSizePixel = 0
keybindsButton.Parent = ScreenGui

local cornerKeybinds = Instance.new("UICorner")
cornerKeybinds.CornerRadius = UDim.new(0, 10)
cornerKeybinds.Parent = keybindsButton

-- KEYBINDS PANEL (NEW)
local keybindsPanel = Instance.new("Frame")
keybindsPanel.Name = "KeybindsPanel"
keybindsPanel.Size = UDim2.new(0, 350, 0, 300)
keybindsPanel.Position = UDim2.new(1, -400, 1, -360)
keybindsPanel.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
keybindsPanel.BorderSizePixel = 0
keybindsPanel.Visible = false
keybindsPanel.Parent = ScreenGui

local cornerPanel = Instance.new("UICorner")
cornerPanel.CornerRadius = UDim.new(0, 12)
cornerPanel.Parent = keybindsPanel

local panelTitle = Instance.new("TextLabel")
panelTitle.Name = "Title"
panelTitle.Size = UDim2.new(1, 0, 0, 40)
panelTitle.Position = UDim2.new(0, 0, 0, 0)
panelTitle.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
panelTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
panelTitle.TextSize = 18
panelTitle.Font = Enum.Font.GothamBold
panelTitle.Text = "Keybinds Settings"
panelTitle.BorderSizePixel = 0
panelTitle.Parent = keybindsPanel

local cornerPanelTitle = Instance.new("UICorner")
cornerPanelTitle.CornerRadius = UDim.new(0, 10)
cornerPanelTitle.Parent = panelTitle

-- KEYBIND INPUT
local keybindLabel = Instance.new("TextLabel")
keybindLabel.Name = "Label"
keybindLabel.Size = UDim2.new(0, 100, 0, 30)
keybindLabel.Position = UDim2.new(0, 15, 0, 50)
keybindLabel.BackgroundTransparency = 1
keybindLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
keybindLabel.TextSize = 14
keybindLabel.Font = Enum.Font.Gotham
keybindLabel.Text = "Dash Key:"
keybindLabel.Parent = keybindsPanel

local keybindInput = Instance.new("TextBox")
keybindInput.Name = "Input"
keybindInput.Size = UDim2.new(0, 120, 0, 30)
keybindInput.Position = UDim2.new(0, 120, 0, 50)
keybindInput.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
keybindInput.TextColor3 = Color3.fromRGB(255, 255, 255)
keybindInput.TextSize = 14
keybindInput.Font = Enum.Font.Gotham
keybindInput.PlaceholderText = "E"
keybindInput.Text = "E"
keybindInput.BorderSizePixel = 1
keybindInput.BorderColor3 = Color3.fromRGB(70, 130, 180)
keybindInput.Parent = keybindsPanel

local saveKeyButton = Instance.new("TextButton")
saveKeyButton.Name = "SaveButton"
saveKeyButton.Size = UDim2.new(0, 80, 0, 30)
saveKeyButton.Position = UDim2.new(0, 250, 0, 50)
saveKeyButton.BackgroundColor3 = Color3.fromRGB(70, 130, 180)
saveKeyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
saveKeyButton.TextSize = 12
saveKeyButton.Font = Enum.Font.GothamBold
saveKeyButton.Text = "Save"
saveKeyButton.BorderSizePixel = 0
saveKeyButton.Parent = keybindsPanel

local cornerSaveBtn = Instance.new("UICorner")
cornerSaveBtn.CornerRadius = UDim.new(0, 6)
cornerSaveBtn.Parent = saveKeyButton

-- CURRENT KEYBIND INFO
local currentKeybindInfo = Instance.new("TextLabel")
currentKeybindInfo.Name = "CurrentKeybindInfo"
currentKeybindInfo.Size = UDim2.new(1, -30, 0, 100)
currentKeybindInfo.Position = UDim2.new(0, 15, 0, 100)
currentKeybindInfo.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
currentKeybindInfo.TextColor3 = Color3.fromRGB(150, 200, 255)
currentKeybindInfo.TextSize = 12
currentKeybindInfo.Font = Enum.Font.Gotham
currentKeybindInfo.TextWrapped = true
currentKeybindInfo.TextXAlignment = Enum.TextXAlignment.Left
currentKeybindInfo.Text = "Current Dash Key: E\n\nPress 'Save' to apply new keybind."
currentKeybindInfo.BorderSizePixel = 0
currentKeybindInfo.Parent = keybindsPanel

local cornerInfoBox = Instance.new("UICorner")
cornerInfoBox.CornerRadius = UDim.new(0, 6)
cornerInfoBox.Parent = currentKeybindInfo

-- KEYBIND SYSTEM
local CURRENT_DASH_KEY = "E"

local function isValidKeybind(keyName)
    if #keyName < 1 or #keyName > 3 then return false end
    local validKeys = {
        A=true, B=true, C=true, D=true, E=true, F=true, G=true, H=true, I=true, J=true, 
        K=true, L=true, M=true, N=true, O=true, P=true, Q=true, R=true, S=true, T=true,
        U=true, V=true, W=true, X=true, Y=true, Z=true,
        Zero=true, One=true, Two=true, Three=true, Four=true, Five=true, Six=true, Seven=true, Eight=true, Nine=true,
        F1=true, F2=true, F3=true, F4=true, F5=true, F6=true, F7=true, F8=true, F9=true, F10=true, F11=true, F12=true,
        Space=true, Tab=true, Backspace=true, Return=true, Escape=true, Shift=true, Ctrl=true, Alt=true,
        LeftShift=true, RightShift=true, LeftCtrl=true, RightCtrl=true, LeftAlt=true, RightAlt=true
    }
    return validKeys[keyName] ~= nil
end

saveKeyButton.MouseButton1Click:Connect(function()
    local newKey = keybindInput.Text:upper()
    if isValidKeybind(newKey) then
        CURRENT_DASH_KEY = newKey
        currentKeybindInfo.Text = "Current Dash Key: " .. CURRENT_DASH_KEY .. "\n\n✓ Keybind updated successfully!"
        currentKeybindInfo.TextColor3 = Color3.fromRGB(0, 255, 100)
        notify("Keybind Changed", "Dash key set to: " .. CURRENT_DASH_KEY)
        task.wait(2)
        currentKeybindInfo.TextColor3 = Color3.fromRGB(150, 200, 255)
        currentKeybindInfo.Text = "Current Dash Key: " .. CURRENT_DASH_KEY .. "\n\nPress 'Save' to apply new keybind."
    else
        currentKeybindInfo.Text = "Current Dash Key: " .. CURRENT_DASH_KEY .. "\n\n❌ Invalid keybind! Use letters or F-keys."
        currentKeybindInfo.TextColor3 = Color3.fromRGB(255, 100, 100)
        task.wait(2)
        currentKeybindInfo.TextColor3 = Color3.fromRGB(150, 200, 255)
        currentKeybindInfo.Text = "Current Dash Key: " .. CURRENT_DASH_KEY .. "\n\nPress 'Save' to apply new keybind."
    end
end)

-- TOGGLE KEYBINDS PANEL
keybindsButton.MouseButton1Click:Connect(function()
    keybindsPanel.Visible = not keybindsPanel.Visible
    if settingsPanel and settingsPanel.Visible then
        settingsPanel.Visible = false
    end
end)

-- DASH BUTTON CLICK
dashButton.MouseButton1Click:Connect(function()
    local target = findNearestTarget(MAX_TARGET_RANGE)
    performDash(target, 49)
end)

--// END SNIPPET 4 - GUI WITH COOLDOWN NOTIFIER + KEYBINDS SETTINGS
--// SNIPPET 5 - INPUT HANDLING + SETTINGS PANEL + FINALIZATION (FIXED)

-- SETTINGS PANEL (from original)
local settingsPanel = Instance.new("Frame")
settingsPanel.Name = "SettingsPanel"
settingsPanel.Size = UDim2.new(0, 350, 0, 400)
settingsPanel.Position = UDim2.new(1, -400, 1, -460)
settingsPanel.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
settingsPanel.BorderSizePixel = 0
settingsPanel.Visible = false
settingsPanel.Parent = ScreenGui

local cornerSettingsPanel = Instance.new("UICorner")
cornerSettingsPanel.CornerRadius = UDim.new(0, 12)
cornerSettingsPanel.Parent = settingsPanel

local settingsPanelTitle = Instance.new("TextLabel")
settingsPanelTitle.Name = "Title"
settingsPanelTitle.Size = UDim2.new(1, 0, 0, 40)
settingsPanelTitle.Position = UDim2.new(0, 0, 0, 0)
settingsPanelTitle.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
settingsPanelTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
settingsPanelTitle.TextSize = 18
settingsPanelTitle.Font = Enum.Font.GothamBold
settingsPanelTitle.Text = "Dash Settings"
settingsPanelTitle.BorderSizePixel = 0
settingsPanelTitle.Parent = settingsPanel

local cornerSettingsPanelTitle = Instance.new("UICorner")
cornerSettingsPanelTitle.CornerRadius = UDim.new(0, 10)
cornerSettingsPanelTitle.Parent = settingsPanelTitle

-- SPEED SLIDER
local speedLabel = Instance.new("TextLabel")
speedLabel.Name = "SpeedLabel"
speedLabel.Size = UDim2.new(0, 100, 0, 25)
speedLabel.Position = UDim2.new(0, 15, 0, 55)
speedLabel.BackgroundTransparency = 1
speedLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
speedLabel.TextSize = 13
speedLabel.Font = Enum.Font.Gotham
speedLabel.Text = "Dash Speed:"
speedLabel.Parent = settingsPanel

local speedSlider = Instance.new("Frame")
speedSlider.Name = "SpeedSlider"
speedSlider.Size = UDim2.new(0, 250, 0, 10)
speedSlider.Position = UDim2.new(0, 15, 0, 85)
speedSlider.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
speedSlider.BorderSizePixel = 0
speedSlider.Parent = settingsPanel

local cornerSpeedSlider = Instance.new("UICorner")
cornerSpeedSlider.CornerRadius = UDim.new(0, 5)
cornerSpeedSlider.Parent = speedSlider

local speedSliderFill = Instance.new("Frame")
speedSliderFill.Name = "Fill"
speedSliderFill.Size = UDim2.new(0.49, 0, 1, 0)
speedSliderFill.Position = UDim2.new(0, 0, 0, 0)
speedSliderFill.BackgroundColor3 = Color3.fromRGB(100, 150, 255)
speedSliderFill.BorderSizePixel = 0
speedSliderFill.Parent = speedSlider

local cornerSpeedSliderFill = Instance.new("UICorner")
cornerSpeedSliderFill.CornerRadius = UDim.new(0, 5)
cornerSpeedSliderFill.Parent = speedSliderFill

local speedSliderValue = Instance.new("TextLabel")
speedSliderValue.Name = "Value"
speedSliderValue.Size = UDim2.new(0, 60, 0, 20)
speedSliderValue.Position = UDim2.new(0, 270, 0, 75)
speedSliderValue.BackgroundTransparency = 1
speedSliderValue.TextColor3 = Color3.fromRGB(100, 150, 255)
speedSliderValue.TextSize = 12
speedSliderValue.Font = Enum.Font.GothamBold
speedSliderValue.Text = "49"
speedSliderValue.Parent = settingsPanel

local speedSliderCurrentValue = 49

local function updateSpeedSlider(value)
    speedSliderCurrentValue = math.clamp(value, 0, 100)
    speedSliderFill.Size = UDim2.new(speedSliderCurrentValue / 100, 0, 1, 0)
    speedSliderValue.Text = tostring(math.floor(speedSliderCurrentValue))
end

speedSlider.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        local mousePos = InputService:GetMouseLocation()
        local relativeX = mousePos.X - speedSlider.AbsolutePosition.X
        local percentage = math.clamp(relativeX / speedSlider.AbsoluteSize.X, 0, 1)
        updateSpeedSlider(percentage * 100)
    end
end)

InputService.InputChanged:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
        if speedSlider:IsDescendantOf(LocalPlayer:FindFirstChild("PlayerGui") or ScreenGui) then
            local mousePos = InputService:GetMouseLocation()
            if mousePos.X >= speedSlider.AbsolutePosition.X and mousePos.X <= speedSlider.AbsolutePosition.X + speedSlider.AbsoluteSize.X then
                if mousePos.Y >= speedSlider.AbsolutePosition.Y and mousePos.Y <= speedSlider.AbsolutePosition.Y + speedSlider.AbsoluteSize.Y then
                    local relativeX = mousePos.X - speedSlider.AbsolutePosition.X
                    local percentage = math.clamp(relativeX / speedSlider.AbsoluteSize.X, 0, 1)
                    updateSpeedSlider(percentage * 100)
                end
            end
        end
    end
end)

-- TOGGLE SETTINGS PANEL
settingsButton.MouseButton1Click:Connect(function()
    settingsPanel.Visible = not settingsPanel.Visible
    if keybindsPanel.Visible then
        keybindsPanel.Visible = false
    end
end)

keybindsButton.MouseButton1Click:Connect(function()
    keybindsPanel.Visible = not keybindsPanel.Visible
    if settingsPanel.Visible then
        settingsPanel.Visible = false
    end
end)

-- INPUT HANDLING (Keybind + Button Detection)
InputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    -- DYNAMIC KEYBIND DETECTION
    local inputName = input.Name:upper()
    
    if inputName == CURRENT_DASH_KEY or inputName == CURRENT_DASH_KEY:upper() then
        local target = findNearestTarget(MAX_TARGET_RANGE)
        performDash(target, speedSliderCurrentValue)
    end
end)

-- CLEANUP ON DISCONNECT
LocalPlayer.Destroying:Connect(function()
    if cooldownConnection then
        pcall(function() cooldownConnection:Disconnect() end)
    end
end)

game:GetService("Debris"):AddItem(ScreenGui, math.huge)

task.wait(0.5)
notify("Side Dash Assist v2.0", "subscribe to waspire :)")

--// END SNIPPET 5 - INPUT HANDLING + SETTINGS PANEL + FINALIZATION (FIXED)
