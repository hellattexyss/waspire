--// SERVICES & INIT
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local char = player.Character or player.CharacterAdded:Wait()
local root = char:WaitForChild("HumanoidRootPart")
local hum = char:WaitForChild("Humanoid")

--// CHARACTER RESPAWN HANDLER
player.CharacterAdded:Connect(function(newChar)
	char = newChar
	root = newChar:WaitForChild("HumanoidRootPart")
	hum = newChar:WaitForChild("Humanoid")
end)

--// HARDCODED SETTINGS
local RANGE = 40
local minGap = 1.2
local maxGap = 60
local targetDist = 15
local straightSpeed = 120
local BASE_CD = 0.45
local TOTAL_TIME = 0.45
local speedMult = 0.8
local HARDCODED_DASH_COOLDOWN = 2.5

local dashRange = 40
local minDist = 4
local maxDist = 5

--// ANIMATION IDS (MULTIPLACE)
local animIds = {
	[10449761463] = {Left = 10480796021, Right = 10480793962, Straight = 10479335397},
	[13076380114] = {Left = 101843860692381, Right = 100087324592640, Straight = 110878031211717},
}

local gameAnims = animIds[game.PlaceId] or animIds[13076380114]
local leftId, rightId, straightId = gameAnims.Left, gameAnims.Right, gameAnims.Straight

--// AUDIO & STATE
local dashSfx = Instance.new("Sound")
dashSfx.Name = "DashSFX"
dashSfx.SoundId = "rbxassetid://72014632956520"
dashSfx.Volume = 2
dashSfx.Looped = false
dashSfx.Parent = Workspace

local dashing = false
local lastDashTime = 0
local animTrack = nil
local selectedPlr = nil
local dashButtonLocked = false
local autoRotateHook = nil
local shouldDisableRot = false

--// UI BLUR
local blur = Instance.new("BlurEffect")
blur.Size = 0
blur.Parent = Lighting

--// NOTIFICATIONS
pcall(function()
	StarterGui:SetCore("SendNotification", {
		Title = "Side Dash Assist v1.0";
		Text = "Loaded successfully! Press E to dash.";
		Duration = 5;
	})
end)
--// GUI CREATION - MERGED WITH DASH BUTTON

local gui = Instance.new("ScreenGui")
gui.Name = "SideDashAssistGUI"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

--// SOUNDS
local uiClickSound = Instance.new("Sound")
uiClickSound.Name = "UIClickSound"
uiClickSound.SoundId = "rbxassetid://5991592592"
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

--// MAIN WINDOW FRAME
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
versionLabel.Text = "v1.0"
versionLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
versionLabel.TextSize = 13
versionLabel.Font = Enum.Font.GothamBold
versionLabel.Parent = headerFrame

local versionCorner = Instance.new("UICorner", versionLabel)
versionCorner.CornerRadius = UDim.new(0, 8)

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

--// CLOSE BUTTON
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 35, 0, 35)
closeBtn.Position = UDim2.new(1, -45, 0, 7)
closeBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Text = "X"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextColor3 = Color3.fromRGB(0, 0, 0)
closeBtn.TextSize = 19
closeBtn.BorderSizePixel = 0
closeBtn.Parent = mainFrame

local closeBtnCorner = Instance.new("UICorner", closeBtn)
closeBtnCorner.CornerRadius = UDim.new(0, 10)

--// MINIMIZE BUTTON
local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Size = UDim2.new(0, 35, 0, 35)
minimizeBtn.Position = UDim2.new(1, -85, 0, 7)
minimizeBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
minimizeBtn.Text = "_"
minimizeBtn.Font = Enum.Font.GothamBold
minimizeBtn.TextColor3 = Color3.fromRGB(0, 0, 0)
minimizeBtn.TextSize = 22
minimizeBtn.BorderSizePixel = 0
minimizeBtn.Parent = mainFrame

local minimizeCorner = Instance.new("UICorner", minimizeBtn)
minimizeCorner.CornerRadius = UDim.new(0, 10)

--// SETTINGS BUTTON
local settingsBtn = Instance.new("TextButton")
settingsBtn.Size = UDim2.new(0, 36, 0, 36)
settingsBtn.Position = UDim2.new(0, 10, 1, -46)
settingsBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
settingsBtn.Text = "⚙"
settingsBtn.Font = Enum.Font.GothamBold
settingsBtn.TextColor3 = Color3.fromRGB(0, 0, 0)
settingsBtn.TextSize = 19
settingsBtn.BorderSizePixel = 0
settingsBtn.RichText = false
settingsBtn.Style = Enum.ButtonStyle.Custom
settingsBtn.Parent = mainFrame

local settingsBtnCorner = Instance.new("UICorner", settingsBtn)
settingsBtnCorner.CornerRadius = UDim.new(1, 0)

--// DISCORD BUTTON (WHITE TEXT)
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
discordBtn.RichText = false
discordBtn.Style = Enum.ButtonStyle.Custom
discordBtn.Parent = mainFrame

local discordCorner = Instance.new("UICorner", discordBtn)
discordCorner.CornerRadius = UDim.new(0, 10)

local discordGradient = Instance.new("UIGradient", discordBtn)
discordGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 135, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 72, 220))
})
discordGradient.Rotation = 90

--// YOUTUBE BUTTON (WHITE TEXT)
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
ytBtn.RichText = false
ytBtn.Style = Enum.ButtonStyle.Custom
ytBtn.Parent = mainFrame

local ytCorner = Instance.new("UICorner", ytBtn)
ytCorner.CornerRadius = UDim.new(0, 10)

local ytGradient = Instance.new("UIGradient", ytBtn)
ytGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 0, 0))
})
ytGradient.Rotation = 90

--// SETTINGS OVERLAY
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

local overlayCorner = Instance.new("UICorner", settingsOverlay)
overlayCorner.CornerRadius = UDim.new(0, 19)

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

local settingsCloseCorner = Instance.new("UICorner", settingsCloseBtn)
settingsCloseCorner.CornerRadius = UDim.new(0, 10)

local comingSoon = Instance.new("TextLabel")
comingSoon.Size = UDim2.new(1, 0, 0, 50)
comingSoon.Position = UDim2.new(0, 0, 0, 50)
comingSoon.BackgroundTransparency = 1
comingSoon.Text = "COMING SOON!..."
comingSoon.TextColor3 = Color3.fromRGB(255, 60, 60)
comingSoon.TextSize = 24
comingSoon.Font = Enum.Font.GothamBold
comingSoon.TextXAlignment = Enum.TextXAlignment.Center
comingSoon.Parent = settingsOverlay

--// KEYBINDS FRAME
local keybindFrame = Instance.new("Frame")
keybindFrame.Size = UDim2.new(1, -32, 0, 110)
keybindFrame.Position = UDim2.new(0, 16, 0, 110)
keybindFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
keybindFrame.BorderSizePixel = 0
keybindFrame.Parent = settingsOverlay

local keybindCorner = Instance.new("UICorner", keybindFrame)
keybindCorner.CornerRadius = UDim.new(0, 14)

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
keyInfo1.Text = "PC Keybind: E"
keyInfo1.TextColor3 = Color3.fromRGB(205, 205, 205)
keyInfo1.TextSize = 15
keyInfo1.Font = Enum.Font.Gotham
keyInfo1.TextXAlignment = Enum.TextXAlignment.Left
keyInfo1.Parent = keybindFrame

--// OPEN GUI BUTTON
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

local openCorner = Instance.new("UICorner", openButton)
openCorner.CornerRadius = UDim.new(0, 10)

--// LOCK BUTTON
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

local lockCorner = Instance.new("UICorner", lockButton)
lockCorner.CornerRadius = UDim.new(0, 10)

--// NOTIFY FUNCTION
local function notify(text)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = "Side Dash Assist";
			Text = text;
			Duration = 2;
		})
	end)
end

--// DASH BUTTON (LARGE RED CIRCLE RIGHT SIDE)
local dashBtn = Instance.new("ImageButton")
dashBtn.Name = "DashButton_Final"
dashBtn.Size = UDim2.new(0, 110, 0, 110)
dashBtn.Position = UDim2.new(1, -125, 0.5, -55)
dashBtn.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
dashBtn.BorderSizePixel = 0
dashBtn.BackgroundTransparency = 0
dashBtn.AutoButtonColor = false
dashBtn.Parent = gui
dashBtn.Draggable = true
dashBtn.Active = true

local round = Instance.new("UICorner", dashBtn)
round.CornerRadius = UDim.new(1, 0)

local grad = Instance.new("UIGradient", dashBtn)
grad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(220, 0, 0)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 0, 0))
})
grad.Rotation = 45
grad.Parent = dashBtn

local bigIcon = Instance.new("ImageLabel")
bigIcon.BackgroundTransparency = 1
bigIcon.Size = UDim2.new(0, 95, 0, 95)
bigIcon.Position = UDim2.new(0.5, -47.5, 0.5, -47.5)
bigIcon.Image = "rbxassetid://12443244342"
bigIcon.Parent = dashBtn

--// LOCK FUNCTIONALITY
lockButton.MouseButton1Click:Connect(function()
	uiClickSound:Play()
	dashButtonLocked = not dashButtonLocked
	dashBtn.Draggable = not dashButtonLocked
	mainFrame.Draggable = not dashButtonLocked
	openButton.Draggable = not dashButtonLocked
	lockButton.Draggable = not dashButtonLocked

	if dashButtonLocked then
		lockButton.Text = "🔒 Locked"
		notify("Dash button & GUI locked in place.")
	else
		lockButton.Text = "🔓 Unlocked"
		notify("Dash button & GUI can be dragged again.")
	end
end)

--// DASH BUTTON CLICK
dashBtn.MouseButton1Click:Connect(function()
	dashClickSound:Play()
	local target = getCurrentTarget()
	if target then
		circularDash(target)
	end
end)

--// WINDOW BUTTON CONNECTIONS
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

--// SOCIAL BUTTONS
discordBtn.MouseButton1Click:Connect(function()
	uiClickSound:Play()
	if setclipboard then
		setclipboard("https://discord.gg/YFf3rdXbUf")
		notify("Discord invite link copied to clipboard.")
	else
		notify("Discord: https://discord.gg/YFf3rdXbUf")
	end
end)

ytBtn.MouseButton1Click:Connect(function()
	uiClickSound:Play()
	if setclipboard then
		setclipboard("https://youtube.com/@waspire")
		notify("YouTube link copied to clipboard.")
	else
		notify("YouTube: https://youtube.com/@waspire")
	end
end)

--// INITIAL SHOW
mainFrame.Visible = true
TweenService:Create(blur, TweenInfo.new(0.3), {Size = 12}):Play()
TweenService:Create(mainFrame, TweenInfo.new(0.3), {BackgroundTransparency = 0}):Play()
TweenService:Create(borderFrame, TweenInfo.new(0.3), {BackgroundTransparency = 0}):Play()

task.delay(0.1, function()
	loadSound:Play()

	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = "Side Dash Assist v1.0";
			Text = "Join the discord server for more updates!";
			Duration = 5;
		})
	end)

	pcall(function()
		if setclipboard then
			setclipboard("https://discord.gg/YFf3rdXbUf")
		end
	end)

	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = "Created by CPS Network";
			Text = "PC Keybinds: E";
			Duration = 5;
		})
	end)
end)
--// GUI CREATION - MERGED WITH DASH BUTTON

local gui = Instance.new("ScreenGui")
gui.Name = "SideDashAssistGUI"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

--// SOUNDS
local uiClickSound = Instance.new("Sound")
uiClickSound.Name = "UIClickSound"
uiClickSound.SoundId = "rbxassetid://5991592592"
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

--// MAIN WINDOW FRAME
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
versionLabel.Text = "v1.0"
versionLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
versionLabel.TextSize = 13
versionLabel.Font = Enum.Font.GothamBold
versionLabel.Parent = headerFrame

local versionCorner = Instance.new("UICorner", versionLabel)
versionCorner.CornerRadius = UDim.new(0, 8)

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

--// CLOSE BUTTON
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 35, 0, 35)
closeBtn.Position = UDim2.new(1, -45, 0, 7)
closeBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Text = "X"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextColor3 = Color3.fromRGB(0, 0, 0)
closeBtn.TextSize = 19
closeBtn.BorderSizePixel = 0
closeBtn.Parent = mainFrame

local closeBtnCorner = Instance.new("UICorner", closeBtn)
closeBtnCorner.CornerRadius = UDim.new(0, 10)

--// MINIMIZE BUTTON
local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Size = UDim2.new(0, 35, 0, 35)
minimizeBtn.Position = UDim2.new(1, -85, 0, 7)
minimizeBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
minimizeBtn.Text = "_"
minimizeBtn.Font = Enum.Font.GothamBold
minimizeBtn.TextColor3 = Color3.fromRGB(0, 0, 0)
minimizeBtn.TextSize = 22
minimizeBtn.BorderSizePixel = 0
minimizeBtn.Parent = mainFrame

local minimizeCorner = Instance.new("UICorner", minimizeBtn)
minimizeCorner.CornerRadius = UDim.new(0, 10)

--// SETTINGS BUTTON
local settingsBtn = Instance.new("TextButton")
settingsBtn.Size = UDim2.new(0, 36, 0, 36)
settingsBtn.Position = UDim2.new(0, 10, 1, -46)
settingsBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
settingsBtn.Text = "⚙"
settingsBtn.Font = Enum.Font.GothamBold
settingsBtn.TextColor3 = Color3.fromRGB(0, 0, 0)
settingsBtn.TextSize = 19
settingsBtn.BorderSizePixel = 0
settingsBtn.RichText = false
settingsBtn.Style = Enum.ButtonStyle.Custom
settingsBtn.Parent = mainFrame

local settingsBtnCorner = Instance.new("UICorner", settingsBtn)
settingsBtnCorner.CornerRadius = UDim.new(1, 0)

--// DISCORD BUTTON (WHITE TEXT)
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
discordBtn.RichText = false
discordBtn.Style = Enum.ButtonStyle.Custom
discordBtn.Parent = mainFrame

local discordCorner = Instance.new("UICorner", discordBtn)
discordCorner.CornerRadius = UDim.new(0, 10)

local discordGradient = Instance.new("UIGradient", discordBtn)
discordGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 135, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 72, 220))
})
discordGradient.Rotation = 90

--// YOUTUBE BUTTON (WHITE TEXT)
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
ytBtn.RichText = false
ytBtn.Style = Enum.ButtonStyle.Custom
ytBtn.Parent = mainFrame

local ytCorner = Instance.new("UICorner", ytBtn)
ytCorner.CornerRadius = UDim.new(0, 10)

local ytGradient = Instance.new("UIGradient", ytBtn)
ytGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 0, 0))
})
ytGradient.Rotation = 90

--// SETTINGS OVERLAY
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

local overlayCorner = Instance.new("UICorner", settingsOverlay)
overlayCorner.CornerRadius = UDim.new(0, 19)

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

local settingsCloseCorner = Instance.new("UICorner", settingsCloseBtn)
settingsCloseCorner.CornerRadius = UDim.new(0, 10)

local comingSoon = Instance.new("TextLabel")
comingSoon.Size = UDim2.new(1, 0, 0, 50)
comingSoon.Position = UDim2.new(0, 0, 0, 50)
comingSoon.BackgroundTransparency = 1
comingSoon.Text = "COMING SOON!..."
comingSoon.TextColor3 = Color3.fromRGB(255, 60, 60)
comingSoon.TextSize = 24
comingSoon.Font = Enum.Font.GothamBold
comingSoon.TextXAlignment = Enum.TextXAlignment.Center
comingSoon.Parent = settingsOverlay

--// KEYBINDS FRAME
local keybindFrame = Instance.new("Frame")
keybindFrame.Size = UDim2.new(1, -32, 0, 110)
keybindFrame.Position = UDim2.new(0, 16, 0, 110)
keybindFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
keybindFrame.BorderSizePixel = 0
keybindFrame.Parent = settingsOverlay

local keybindCorner = Instance.new("UICorner", keybindFrame)
keybindCorner.CornerRadius = UDim.new(0, 14)

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
keyInfo1.Text = "PC Keybind: E"
keyInfo1.TextColor3 = Color3.fromRGB(205, 205, 205)
keyInfo1.TextSize = 15
keyInfo1.Font = Enum.Font.Gotham
keyInfo1.TextXAlignment = Enum.TextXAlignment.Left
keyInfo1.Parent = keybindFrame

--// OPEN GUI BUTTON
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

local openCorner = Instance.new("UICorner", openButton)
openCorner.CornerRadius = UDim.new(0, 10)

--// LOCK BUTTON
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

local lockCorner = Instance.new("UICorner", lockButton)
lockCorner.CornerRadius = UDim.new(0, 10)

--// NOTIFY FUNCTION
local function notify(text)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = "Side Dash Assist";
			Text = text;
			Duration = 2;
		})
	end)
end

--// DASH BUTTON (LARGE RED CIRCLE RIGHT SIDE)
local dashBtn = Instance.new("ImageButton")
dashBtn.Name = "DashButton_Final"
dashBtn.Size = UDim2.new(0, 110, 0, 110)
dashBtn.Position = UDim2.new(1, -125, 0.5, -55)
dashBtn.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
dashBtn.BorderSizePixel = 0
dashBtn.BackgroundTransparency = 0
dashBtn.AutoButtonColor = false
dashBtn.Parent = gui
dashBtn.Draggable = true
dashBtn.Active = true

local round = Instance.new("UICorner", dashBtn)
round.CornerRadius = UDim.new(1, 0)

local grad = Instance.new("UIGradient", dashBtn)
grad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(220, 0, 0)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 0, 0))
})
grad.Rotation = 45
grad.Parent = dashBtn

local bigIcon = Instance.new("ImageLabel")
bigIcon.BackgroundTransparency = 1
bigIcon.Size = UDim2.new(0, 95, 0, 95)
bigIcon.Position = UDim2.new(0.5, -47.5, 0.5, -47.5)
bigIcon.Image = "rbxassetid://12443244342"
bigIcon.Parent = dashBtn

--// LOCK FUNCTIONALITY
lockButton.MouseButton1Click:Connect(function()
	uiClickSound:Play()
	dashButtonLocked = not dashButtonLocked
	dashBtn.Draggable = not dashButtonLocked
	mainFrame.Draggable = not dashButtonLocked
	openButton.Draggable = not dashButtonLocked
	lockButton.Draggable = not dashButtonLocked

	if dashButtonLocked then
		lockButton.Text = "🔒 Locked"
		notify("Dash button & GUI locked in place.")
	else
		lockButton.Text = "🔓 Unlocked"
		notify("Dash button & GUI can be dragged again.")
	end
end)

--// DASH BUTTON CLICK
dashBtn.MouseButton1Click:Connect(function()
	dashClickSound:Play()
	local target = getCurrentTarget()
	if target then
		circularDash(target)
	end
end)

--// WINDOW BUTTON CONNECTIONS
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

--// SOCIAL BUTTONS
discordBtn.MouseButton1Click:Connect(function()
	uiClickSound:Play()
	if setclipboard then
		setclipboard("https://discord.gg/YFf3rdXbUf")
		notify("Discord invite link copied to clipboard.")
	else
		notify("Discord: https://discord.gg/YFf3rdXbUf")
	end
end)

ytBtn.MouseButton1Click:Connect(function()
	uiClickSound:Play()
	if setclipboard then
		setclipboard("https://youtube.com/@waspire")
		notify("YouTube link copied to clipboard.")
	else
		notify("YouTube: https://youtube.com/@waspire")
	end
end)

--// INITIAL SHOW
mainFrame.Visible = true
TweenService:Create(blur, TweenInfo.new(0.3), {Size = 12}):Play()
TweenService:Create(mainFrame, TweenInfo.new(0.3), {BackgroundTransparency = 0}):Play()
TweenService:Create(borderFrame, TweenInfo.new(0.3), {BackgroundTransparency = 0}):Play()

task.delay(0.1, function()
	loadSound:Play()

	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = "Side Dash Assist v1.0";
			Text = "Join the discord server for more updates!";
			Duration = 5;
		})
	end)

	pcall(function()
		if setclipboard then
			setclipboard("https://discord.gg/YFf3rdXbUf")
		end
	end)

	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = "Created by CPS Network";
			Text = "PC Keybinds: E";
			Duration = 5;
		})
	end)
end)
