--// Waspire Scripts GUI (Orange Branding)
if game.CoreGui:FindFirstChild("WaspireScriptsGui") then
    game.CoreGui.WaspireScriptsGui:Destroy()
end

local TweenService = game:GetService("TweenService")

-- Create main GUI
local gui = Instance.new("ScreenGui")
gui.Name = "WaspireScriptsGui"
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
mainFrame.BackgroundColor3 = Color3.fromRGB(35, 25, 0)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = gui
mainFrame.ClipsDescendants = true

-- Rounded borders
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 15)
corner.Parent = mainFrame

-- Orange gradient background
local gradient = Instance.new("UIGradient")
gradient.Color = ColorSequence.new{
    ColorSequenceKeypoint.new(0, Color3.fromRGB(35, 25, 0)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 160, 40))
}
gradient.Rotation = 90
gradient.Parent = mainFrame

-- Title (gradient text Waspire Scripts)
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 40)
title.BackgroundTransparency = 1
title.Text = "Waspire Scripts"
title.Font = Enum.Font.GothamBold
title.TextColor3 = Color3.fromRGB(255, 255, 255) -- fallback for gradient
title.TextSize = 26
title.Parent = mainFrame

local titleGradient = Instance.new("UIGradient")
titleGradient.Color = ColorSequence.new{
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 153, 51)),       -- Orange
    ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 63))        -- Yellow
}
titleGradient.Rotation = 0
titleGradient.Parent = title

-- New description line
local topDesc = Instance.new("TextLabel")
topDesc.Size = UDim2.new(1, -20, 0, 20)
topDesc.Position = UDim2.new(0, 10, 0, 45)
topDesc.BackgroundTransparency = 1
topDesc.Text = "The script has switched loaders."
topDesc.Font = Enum.Font.GothamMedium
topDesc.TextColor3 = Color3.fromRGB(255, 255, 255)
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
desc.TextColor3 = Color3.fromRGB(255, 255, 255)
desc.TextSize = 16
desc.TextWrapped = true
desc.Parent = mainFrame

-- Copy Button (gradient)
local copyButton = Instance.new("TextButton")
copyButton.Size = UDim2.new(0, 200, 0, 40)
copyButton.Position = UDim2.new(0.5, -100, 1, -60)
copyButton.BackgroundColor3 = Color3.fromRGB(255, 153, 51)
copyButton.Text = "Click to Copy Link"
copyButton.Font = Enum.Font.GothamMedium
copyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
copyButton.TextSize = 18
copyButton.Parent = mainFrame

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(0, 10)
btnCorner.Parent = copyButton

local buttonGradient = Instance.new("UIGradient")
buttonGradient.Color = ColorSequence.new{
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 153, 51)),       -- Orange
    ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 63))        -- Yellow
}
buttonGradient.Rotation = 90
buttonGradient.Parent = copyButton

-- Copy to clipboard function
local function copyLink()
    local link = "https://discord.gg/kD9nWVmZ"
    if setclipboard then
        setclipboard(link)
    elseif toclipboard then
        toclipboard(link)
    end
    copyButton.Text = "Copied!"
    TweenService:Create(copyButton, TweenInfo.new(0.25), {BackgroundColor3 = Color3.fromRGB(0,200,80)}):Play()
    task.wait(1)
    TweenService:Create(copyButton, TweenInfo.new(0.25), {BackgroundColor3 = Color3.fromRGB(255,153,51)}):Play()
    copyButton.Text = "Click to Copy Link"
end

copyButton.MouseButton1Click:Connect(copyLink)

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
