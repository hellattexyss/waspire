-- ═══════════════════════════════════════════════════════════════════════════════
-- SNIPPET 1 - CORE SETUP + FIXED CHAM & RANGE SYSTEM
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

-- BLUR EFFECT
local blur = Instance.new("BlurEffect")
blur.Size = 0
blur.Parent = Lighting

local function applyBlur(enabled)
    local targetSize = enabled and 20 or 0
    TweenService:Create(blur, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = targetSize}):Play()
end

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

-- CONSTANTS (PROPERLY EXPOSED FOR UPDATES)
local MAX_TARGET_RANGE = 30
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
local lastCooldownNotificationTime = 0

-- FULL BODY RED CHAM SYSTEM WITH TRANSPARENCY
local chammedTarget = nil
local originalColors = {}
local originalTransparencies = {}
local chamTweens = {}

local function addFullBodyRedCham(target)
    if not target or not target:IsA("Model") then return end
    if chammedTarget == target then return end
    
    if chammedTarget then
        removeFullBodyRedCham()
    end
    
    chammedTarget = target
    originalColors = {}
    originalTransparencies = {}
    
    -- INSTANT RED ON DASH START - FULL BODY WITH 80% TRANSPARENCY
    for _, part in pairs(target:GetDescendants()) do
        if part:IsA("BasePart") then
            originalColors[part] = part.Color
            originalTransparencies[part] = part.Transparency
            
            if chamTweens[part] then
                pcall(function() chamTweens[part]:Cancel() end)
            end
            
            local tween = TweenService:Create(
                part, 
                TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), 
                {Color = Color3.fromRGB(255, 0, 0), Transparency = 0.2}
            )
            chamTweens[part] = tween
            tween:Play()
        end
    end
    
    -- YELLOW TRANSITION AT HALF COOLDOWN (1.0s later)
    task.delay(1.0, function()
        if chammedTarget == target then
            for _, part in pairs(target:GetDescendants()) do
                if part:IsA("BasePart") and originalColors[part] then
                    if chamTweens[part] then
                        pcall(function() chamTweens[part]:Cancel() end)
                    end
                    
                    local tween = TweenService:Create(
                        part, 
                        TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), 
                        {Color = Color3.fromRGB(255, 255, 0), Transparency = 0.2}
                    )
                    chamTweens[part] = tween
                    tween:Play()
                end
            end
        end
    end)
    
    -- GREEN TRANSITION WHEN FULLY READY (2.0s later)
    task.delay(2.0, function()
        if chammedTarget == target then
            for _, part in pairs(target:GetDescendants()) do
                if part:IsA("BasePart") and originalColors[part] then
                    if chamTweens[part] then
                        pcall(function() chamTweens[part]:Cancel() end)
                    end
                    
                    local tween = TweenService:Create(
                        part, 
                        TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), 
                        {Color = Color3.fromRGB(0, 255, 0), Transparency = 0.2}
                    )
                    chamTweens[part] = tween
                    tween:Play()
                end
            end
        end
    end)
end

function removeFullBodyRedCham()
    if chammedTarget then
        for part, origColor in pairs(originalColors) do
            if part and part.Parent then
                if chamTweens[part] then
                    pcall(function() chamTweens[part]:Cancel() end)
                end
                
                local origTrans = originalTransparencies[part] or 0
                local tween = TweenService:Create(
                    part, 
                    TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), 
                    {Color = origColor, Transparency = origTrans}
                )
                chamTweens[part] = tween
                tween:Play()
            end
        end
        originalColors = {}
        originalTransparencies = {}
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

local function notify(title, text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = 3,
        })
    end)
end

local function notifyCooldownInstant(text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "Cooldown",
            Text = text,
            Duration = 1,
        })
    end)
end

local loadSound = Instance.new("Sound")
loadSound.Name = "LoadSound"
loadSound.SoundId = "rbxassetid://115916891254154"
loadSound.Volume = 1
loadSound.Parent = WorkspaceService
loadSound:Play()

notify("Side Dash Assist v2.3", "Loading... Please wait!")

print("✅ SNIPPET 1 LOADED - FULL BODY RED CHAM SYSTEM READY")
print("✅ Range: 30 default, 50 max studs")
print("✅ Instant cooldown notifications")
