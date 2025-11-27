--// CPS Network GUI (Updated)
if game.CoreGui:FindFirstChild("CPSNetworkGui") then
    game.CoreGui.CPSNetworkGui:Destroy()
end

local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

-- Create main GUI
local gui = Instance.new("ScreenGui")
gui.Name = "CPSNetworkGui"
gui.Parent = game.CoreGui
gui.ResetOnSpawn = false

-- Blur background
local blur = Instance.new("BlurEffect")
blur.Size = 0
blur.Parent = game.Lighting

-- Main frame
local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 380, 0, 200)
mainFrame.Position = UDim2.new(0.5, -190, 0.5, -100)
mainFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = gui
mainFrame.ClipsDescendants = true

-- Rounded borders
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 15)
corner.Parent = mainFrame

-- Red gradient
local gradient = Instance.new("UIGradient")
gradient.Color = ColorSequence.new{
    ColorSequenceKeypoint.new(0, Color3.fromRGB(10, 10, 10)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 50))
}
gradient.Rotation = 90
gradient.Parent = mainFrame

-- Title
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 40)
title.BackgroundTransparency = 1
title.Text = "CPS Network"
title.Font = Enum.Font.GothamBold
title.TextColor3 = Color3.fromRGB(255, 50, 50)
title.TextSize = 26
title.Parent = mainFrame

-- New description line
local topDesc = Instance.new("TextLabel")
topDesc.Size = UDim2.new(1, -20, 0, 20)
topDesc.Position = UDim2.new(0, 10, 0, 45)
topDesc.BackgroundTransparency = 1
topDesc.Text = "The script has switched loaders."
topDesc.Font = Enum.Font.GothamMedium
topDesc.TextColor3 = Color3.fromRGB(255, 90, 90)
topDesc.TextSize = 16
topDesc.TextWrapped = true
topDesc.Parent = mainFrame

-- Description text
local desc = Instance.new("TextLabel")
desc.Size = UDim2.new(1, -20, 0, 60)
desc.Position = UDim2.new(0, 10, 0, 68)
desc.BackgroundTransparency = 1
desc.Text = "Join the Discord server below to get the script!"
desc.Font = Enum.Font.Gotham
desc.TextColor3 = Color3.fromRGB(230, 230, 230)
desc.TextSize = 16
desc.TextWrapped = true
desc.Parent = mainFrame

-- Copy Button
local copyButton = Instance.new("TextButton")
copyButton.Size = UDim2.new(0, 200, 0, 40)
copyButton.Position = UDim2.new(0.5, -100, 1, -60)
copyButton.BackgroundColor3 = Color3.fromRGB(255, 0, 60)
copyButton.Text = "Click to Copy Link"
copyButton.Font = Enum.Font.GothamMedium
copyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
copyButton.TextSize = 18
copyButton.Parent = mainFrame

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(0, 10)
btnCorner.Parent = copyButton

-- Copy to clipboard function
local function copyLink()
    local link = "https://discord.gg/SXeJc3V67j"
    if setclipboard then
        setclipboard(link)
    elseif toclipboard then
        toclipboard(link)
    end
    copyButton.Text = "Copied!"
    TweenService:Create(copyButton, TweenInfo.new(0.25), {BackgroundColor3 = Color3.fromRGB(0, 200, 80)}):Play() 
    task.wait(1)
    TweenService:Create(copyButton, TweenInfo.new(0.25), {BackgroundColor3 = Color3.fromRGB(255, 0, 60)}):Play()
    copyButton.Text = "Click to Copy Link"
end

copyButton.MouseButton1Click:Connect(copyLink)

-- Discord invite link
local discordLink = "https://discord.gg/PA2sUXezDD"

-- Automatically copy Discord invite link on script execution
if setclipboard then
    setclipboard(discordLink)
elseif toclipboard then
    toclipboard(discordLink)
end

-- Roblox notification for outdated version (no button)
StarterGui:SetCore("SendNotification", {
    Title = "Outdated Version";
    Text = "Please join the discord server for the new script!";
    Duration = 8;
})

-- Fade in animation
gui.Enabled = false
mainFrame.BackgroundTransparency = 1
title.TextTransparency = 1
topDesc.TextTransparency = 1
desc.TextTransparency = 1
copyButton.BackgroundTransparency = 1
copyButton.TextTransparency = 1

task.wait(0.2)
gui.Enabled = true

TweenService:Create(mainFrame, TweenInfo.new(0.6), {BackgroundTransparency = 0}):Play()
TweenService:Create(title, TweenInfo.new(0.6), {TextTransparency = 0}):Play()
TweenService:Create(topDesc, TweenInfo.new(0.6), {TextTransparency = 0}):Play()
TweenService:Create(desc, TweenInfo.new(0.6), {TextTransparency = 0}):Play()
TweenService:Create(copyButton, TweenInfo.new(0.6), {BackgroundTransparency = 0, TextTransparency = 0}):Play()
TweenService:Create(blur, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = 20}):Play()
