--// CLEANUP
pcall(function()
	local pg = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	for _, name in ipairs({"SettingsGUI_Only_V2_Merged", "DashSettingsGui_Merged", "CircularTweenUI_Merged"}) do
		local g = pg:FindFirstChild(name)
		if g then g:Destroy() end
	end
end)

task.wait(0.1)

--// SERVICES
local PlayersService = game:GetService("Players")
local RunService = game:GetService("RunService")
local InputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local WorkspaceService = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")

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

--// ANIMATIONS
local ANIMATION_IDS = {
	[10449761463] = {Left = 10480796021, Right = 10480793962, Straight = 10479335397},
	[13076380114] = {Left = 101843860692381, Right = 100087324592640, Straight = 110878031211717}
}
local gameId = game.PlaceId
local currentGameAnimations = ANIMATION_IDS[gameId] or ANIMATION_IDS[13076380114]
local leftAnimationId = currentGameAnimations.Left
local rightAnimationId = currentGameAnimations.Right
local straightAnimationId = currentGameAnimations.Straight

--// CONSTANTS
local MAX_TARGET_RANGE = 40
local MIN_DASH_DISTANCE = 1.2
local MAX_DASH_DISTANCE = 60
local MIN_TARGET_DISTANCE = 15
local TARGET_REACH_THRESHOLD = 10
local DASH_SPEED = 120
local DIRECTION_LERP_FACTOR = 0.7
local CAMERA_FOLLOW_DELAY = 0.7
local VELOCITY_PREDICTION_FACTOR = 0.5
local FOLLOW_EASING_POWER = 200
local CIRCLE_COMPLETION_THRESHOLD = 390 / 480
local BUTTON_PRESS_SOUND_ID = "rbxassetid://5852470908"

--// STATE
local isDashing = false
local sideAnimationTrack = nil
local lastButtonPressTime = -math.huge
local dashSound = Instance.new("Sound")
dashSound.Name = "DashSFX"
dashSound.SoundId = "rbxassetid://72014632956520"
dashSound.Volume = 2
dashSound.Looped = false
dashSound.Parent = WorkspaceService

local isAutoRotateDisabled = false
local autoRotateConnection = nil

local function setupAutoRotateProtection()
	if autoRotateConnection then pcall(function() autoRotateConnection:Disconnect() end) autoRotateConnection = nil end
	local targetHumanoid = Character:FindFirstChildOfClass("Humanoid")
	if targetHumanoid then
		autoRotateConnection = targetHumanoid:GetPropertyChangedSignal("AutoRotate"):Connect(function()
			if isAutoRotateDisabled then
				pcall(function() if targetHumanoid and targetHumanoid.AutoRotate then targetHumanoid.AutoRotate = false end end)
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

--// MATH HELPERS
local function getAngleDifference(angle1, angle2)
	local difference = angle1 - angle2
	while math.pi < difference do difference = difference - 2 * math.pi end
	while difference < -math.pi do difference = difference + 2 * math.pi end
	return difference
end

local function easeInOutCubic(progress)
	return 1 - (1 - math.clamp(progress, 0, 1)) ^ 3
end

--// NOTIFICATIONS
pcall(function()
	StarterGui:SetCore("SendNotification", {
		Title = "Side Dash Assist V1",
		Text = "Enjoy! Report bugs on discord server",
		Duration = 5
	})
end)

pcall(function()
	StarterGui:SetCore("SendNotification", {
		Title = "Keybinds Info",
		Text = "Side Dash Keybind: E",
		Duration = 5
	})
end)

pcall(function()
	if setclipboard then setclipboard("https://discord.gg/GEVGRzC4ZP") end
end)
--// ANIMATION & TARGETING
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
	pcall(function() if sideAnimationTrack and sideAnimationTrack.IsPlaying then sideAnimationTrack:Stop() end end)
	sideAnimationTrack = nil
	local targetHumanoid, animator = getHumanoidAndAnimator()
	if targetHumanoid and animator then
		local animationId = isLeftDirection and leftAnimationId or rightAnimationId
		local animationInstance = Instance.new("Animation")
		animationInstance.Name = "CircularSideAnim"
		animationInstance.AnimationId = "rbxassetid://" .. tostring(animationId)
		local success, loadedAnimation = pcall(function() return animator:LoadAnimation(animationInstance) end)
		if success and loadedAnimation then
			sideAnimationTrack = loadedAnimation
			loadedAnimation.Priority = Enum.AnimationPriority.Action
			pcall(function() loadedAnimation.Looped = false end)
			loadedAnimation:Play()
			pcall(function() dashSound:Stop() dashSound:Play() end)
			delay(0.45 + 0.15, function()
				pcall(function() if loadedAnimation and loadedAnimation.IsPlaying then loadedAnimation:Stop() end end)
				pcall(function() animationInstance:Destroy() end)
			end)
		else
			pcall(function() animationInstance:Destroy() end)
		end
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

--// SLIDER CALCS (HARDCODED DEFAULTS)
local function calculateDashDuration(speedSliderValue)
	local clampedValue = math.clamp(speedSliderValue or 49, 0, 100) / 100
	return 1.5 + (0.12 - 1.5) * clampedValue
end

local function calculateDashAngle(degreesSliderValue)
	return 90 + 990 * (math.clamp(degreesSliderValue or 32, 0, 100) / 100)
end

local function calculateDashDistance(gapSliderValue)
	return 1 + 11 * (math.clamp(gapSliderValue or 14, 0, 100) / 100)
end

--// HARDCODED SETTINGS
local settingsValues = {["Dash speed"] = 49, ["Dash Degrees"] = 32, ["Dash gap"] = 14}
local lockedTargetPlayer = nil
PlayersService.PlayerRemoving:Connect(function(removedPlayer) if lockedTargetPlayer == removedPlayer then lockedTargetPlayer = nil end end)

local function getCurrentTarget()
	if lockedTargetPlayer then
		if lockedTargetPlayer.Character and lockedTargetPlayer.Character.Parent then
			local targetCharacter = lockedTargetPlayer.Character
			local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")
			local targetHumanoid = targetCharacter:FindFirstChild("Humanoid")
			if targetRoot and targetHumanoid and targetHumanoid.Health > 0 and HumanoidRootPart then
				if (targetRoot.Position - HumanoidRootPart.Position).Magnitude > MAX_TARGET_RANGE then return nil else return targetCharacter end
			end
			lockedTargetPlayer = nil
		else
			lockedTargetPlayer = nil
		end
	end
	return findNearestTarget(MAX_TARGET_RANGE)
end

--// MOVEMENT & AIM
local function aimCharacterAtTarget(targetPosition, lerpFactor)
	lerpFactor = lerpFactor or 0.7
	pcall(function()
		local characterPosition = HumanoidRootPart.Position
		local characterLookVector = HumanoidRootPart.CFrame.LookVector
		local directionToTarget = targetPosition - characterPosition
		local horizontalDirection = Vector3.new(directionToTarget.X, 0, directionToTarget.Z)
		if horizontalDirection.Magnitude < 0.001 then horizontalDirection = Vector3.new(1, 0, 0) end
		local targetDirection = horizontalDirection.Unit
		local finalLookVector = Vector3.new(targetDirection.X, characterLookVector.Y, targetDirection.Z)
		if finalLookVector.Magnitude < 0.001 then finalLookVector = Vector3.new(targetDirection.X, characterLookVector.Y, targetDirection.Z + 0.0001) end
		local lerpedDirection = characterLookVector:Lerp(finalLookVector.Unit, lerpFactor)
		if lerpedDirection.Magnitude < 0.001 then lerpedDirection = Vector3.new(finalLookVector.Unit.X, characterLookVector.Y, finalLookVector.Unit.Z) end
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
	local straightAnimationTrack, straightAnimationInstance = nil, nil
	if straightAnimationId then
		local characterHumanoid, characterAnimator = getHumanoidAndAnimator()
		if characterHumanoid and characterAnimator then
			straightAnimationInstance = Instance.new("Animation")
			straightAnimationInstance.Name = "StraightDashAnim"
			straightAnimationInstance.AnimationId = "rbxassetid://" .. tostring(straightAnimationId)
			local success, loadedAnim = pcall(function() return characterAnimator:LoadAnimation(straightAnimationInstance) end)
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
	local hasReachedTarget, isActive = false, true
	local heartbeatConnection = nil
	heartbeatConnection = RunService.Heartbeat:Connect(function()
		if isActive and targetRootPart and targetRootPart.Parent and HumanoidRootPart and HumanoidRootPart.Parent then
			local targetPosition = targetRootPart.Position
			local directionToTarget = targetPosition - HumanoidRootPart.Position
			local horizontalDirection = Vector3.new(directionToTarget.X, 0, directionToTarget.Z)
			if horizontalDirection.Magnitude > TARGET_REACH_THRESHOLD then
				linearVelocity.VectorVelocity = horizontalDirection.Unit * dashSpeed
				pcall(function() if horizontalDirection.Magnitude > 0.001 then HumanoidRootPart.CFrame = CFrame.new(HumanoidRootPart.Position, HumanoidRootPart.Position + horizontalDirection.Unit) end end)
				pcall(function() aimCharacterAtTarget(targetPosition, 0.56) end)
			else
				hasReachedTarget = true
				isActive = false
				heartbeatConnection:Disconnect()
				pcall(function() linearVelocity:Destroy() attachment:Destroy() end)
				pcall(function() if straightAnimationTrack and straightAnimationTrack.IsPlaying then straightAnimationTrack:Stop() end if straightAnimationInstance then straightAnimationInstance:Destroy() end end)
			end
		else
			isActive = false
			heartbeatConnection:Disconnect()
			pcall(function() linearVelocity:Destroy() attachment:Destroy() end)
			pcall(function() if straightAnimationTrack and straightAnimationTrack.IsPlaying then straightAnimationTrack:Stop() end if straightAnimationInstance then straightAnimationInstance:Destroy() end end)
		end
	end)
	repeat task.wait() until hasReachedTarget or not (targetRootPart and targetRootPart.Parent and HumanoidRootPart and HumanoidRootPart.Parent)
end

local function smoothlyAimAtTarget(targetRootPart, duration)
	duration = duration or CAMERA_FOLLOW_DELAY
	if targetRootPart and targetRootPart.Parent then
		local startTime = tick()
		local aimTweenConnection = nil
		aimTweenConnection = RunService.Heartbeat:Connect(function()
			if targetRootPart and targetRootPart.Parent then
				local currentTime = tick()
				local progress = math.clamp((currentTime - startTime) / duration, 0, 1)
				local easedProgress = 1 - (1 - progress) ^ math.max(1, FOLLOW_EASING_POWER)
				local targetPosition = targetRootPart.Position
				local targetVelocity = Vector3.new(0, 0, 0)
				pcall(function() targetVelocity = targetRootPart:GetVelocity() or Vector3.new(0, 0, 0) end)
				local predictedPosition = targetPosition + Vector3.new(targetVelocity.X, 0, targetVelocity.Z) * VELOCITY_PREDICTION_FACTOR
				pcall(function()
					local characterPosition = HumanoidRootPart.Position
					local characterLookVector = HumanoidRootPart.CFrame.LookVector
					local directionToTarget = predictedPosition - characterPosition
					local horizontalDirection = Vector3.new(directionToTarget.X, 0, directionToTarget.Z)
					if horizontalDirection.Magnitude < 0.001 then horizontalDirection = Vector3.new(1, 0, 0) end
					local targetDirection = horizontalDirection.Unit
					local finalLookVector = characterLookVector:Lerp(Vector3.new(targetDirection.X, characterLookVector.Y, targetDirection.Z).Unit, easedProgress)
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

--// MAIN CIRCULAR DASH
local function performCircularDash(targetCharacter)
	if isDashing or not targetCharacter or not targetCharacter:FindFirstChild("HumanoidRootPart") or not HumanoidRootPart then return end
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
		if directionToTarget.Magnitude < 0.001 then directionToTarget = HumanoidRootPart.CFrame.LookVector end
		local isLeftDirection = characterRightVector:Dot(directionToTarget.Unit) < 0
		playSideAnimation(isLeftDirection)
		local directionMultiplier = isLeftDirection and 1 or -1
		local angleToTarget = math.atan2(characterPosition.Z - targetPosition.Z, characterPosition.X - targetPosition.X)
		local horizontalDistance = (Vector3.new(characterPosition.X, 0, characterPosition.Z) - Vector3.new(targetPosition.X, 0, targetPosition.Z)).Magnitude
		local clampedDistance = math.clamp(horizontalDistance, MIN_DASH_DISTANCE, MAX_DASH_DISTANCE)
		local startTime = tick()
		local movementConnection = nil
		local hasStartedAim, hasCompletedCircle, shouldEndDash, dashEnded = false, false, false, false
		
		local function startDashEndSequence()
			if not hasCompletedCircle then
				hasCompletedCircle = true
				task.delay(CAMERA_FOLLOW_DELAY, function()
					shouldEndDash = true
					restoreAutoRotate()
					lastButtonPressTime = tick()
					if dashEnded then isDashing = false end
				end)
			end
		end
		
		if m1ToggleEnabled then
			communicateWithServer({{Mobile = true, Goal = "LeftClick"}})
			task.delay(0.05, function() communicateWithServer({{Goal = "LeftClickRelease", Mobile = true}}) end)
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
			local currentAngle = angleToTarget + directionMultiplier * dashAngleRad * easeInOutCubic(progress)
			local currentTargetPosition = targetRoot.Position
			local targetY = currentTargetPosition.Y
			local circleX = currentTargetPosition.X + clampedRadius * math.cos(currentAngle)
			local circleZ = currentTargetPosition.Z + clampedRadius * math.sin(currentAngle)
			local newPosition = Vector3.new(circleX, targetY, circleZ)
			if targetRoot then currentTargetPosition = targetRoot.Position or currentTargetPosition end
			local angleToTargetPosition = math.atan2((currentTargetPosition - newPosition).Z, (currentTargetPosition - newPosition).X)
			local characterAngle = math.atan2(HumanoidRootPart.CFrame.LookVector.Z, HumanoidRootPart.CFrame.LookVector.X)
			local finalCharacterAngle = characterAngle + getAngleDifference(angleToTargetPosition, characterAngle) * DIRECTION_LERP_FACTOR
			pcall(function() HumanoidRootPart.CFrame = CFrame.new(newPosition, newPosition + Vector3.new(math.cos(finalCharacterAngle), 0, math.sin(finalCharacterAngle))) end)
			if not hasStartedAim and CIRCLE_COMPLETION_THRESHOLD <= easedProgress then
				hasStartedAim = true
				pcall(function() smoothlyAimAtTarget(targetRoot, CAMERA_FOLLOW_DELAY) end)
				startDashEndSequence()
			end
			if progress >= 1 then
				movementConnection:Disconnect()
				pcall(function() if sideAnimationTrack and sideAnimationTrack.IsPlaying then sideAnimationTrack:Stop() end sideAnimationTrack = nil end)
				if not hasStartedAim then
					hasStartedAim = true
					pcall(function() smoothlyAimAtTarget(targetRoot, CAMERA_FOLLOW_DELAY) end)
					startDashEndSequence()
				end
				dashEnded = true
				if shouldEndDash then isDashing = false end
			end
		end)
	else
		restoreAutoRotate()
		isDashing = false
	end
end

--// E KEY KEYBIND
InputService.InputBegan:Connect(function(inp, gp)
	if gp or isDashing or isCharacterDisabled() then return end
	if inp.UserInputType == Enum.UserInputType.Keyboard and inp.KeyCode == Enum.KeyCode.E then
		local target = getCurrentTarget()
		if target then performCircularDash(target) end
	end
end)
--// SETTINGS & HELPERS
local mainGui = Instance.new("ScreenGui")
mainGui.Name = "SettingsGUI_Only_V2_Merged"
mainGui.ResetOnSpawn = false
mainGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local clickSound = Instance.new("Sound")
clickSound.SoundId = "rbxassetid://6042053626"
clickSound.Volume = 0.7
clickSound.Parent = mainGui

local function makeFrameDraggable(frame)
	local isDragging = false
	local dragStartPosition = nil
	local frameStartPosition = nil
	frame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			isDragging = true
			dragStartPosition = input.Position
			frameStartPosition = frame.Position
			input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then isDragging = false end end)
		end
	end)
	InputService.InputChanged:Connect(function(input)
		if isDragging and (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement) then
			local delta = input.Position - dragStartPosition
			frame.Position = UDim2.new(frameStartPosition.X.Scale, frameStartPosition.X.Offset + delta.X, frameStartPosition.Y.Scale, frameStartPosition.Y.Offset + delta.Y)
		end
	end)
end

local function createToggleButton(buttonText, callback)
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0, 100, 0, 35)
	button.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
	button.Text = buttonText
	button.TextColor3 = Color3.fromRGB(0, 0, 0)
	button.Font = Enum.Font.Gotham
	button.TextSize = 14
	button.AutoButtonColor = false
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 8)
	local indicator = Instance.new("Frame")
	indicator.Size = UDim2.new(0, 15, 0, 15)
	indicator.Position = UDim2.new(1, -24, 0.5, -7)
	indicator.BackgroundColor3 = Color3.fromRGB(180, 180, 180)
	indicator.Parent = button
	Instance.new("UICorner", indicator).CornerRadius = UDim.new(1, 0)
	local isEnabled = false
	local function updateVisuals()
		indicator.BackgroundColor3 = isEnabled and Color3.fromRGB(0, 200, 0) or Color3.fromRGB(180, 180, 180)
		button.BackgroundColor3 = isEnabled and Color3.fromRGB(220, 220, 220) or Color3.fromRGB(245, 245, 245)
	end
	local function setState(newState, shouldCallback)
		isEnabled = newState and true or false
		updateVisuals()
		if shouldCallback and callback then pcall(function() callback(isEnabled) end) end
	end
	button.MouseButton1Click:Connect(function()
		pcall(function() clickSound:Play() end)
		setState(not isEnabled, true)
	end)
	return button, setState
end

--// SETTINGS FRAME (YOUR GUI)
local settingsFrame = Instance.new("Frame")
settingsFrame.Size = UDim2.new(0, 340, 0, 270)
settingsFrame.Position = UDim2.new(0.5, -170, 0.5, -135)
settingsFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
settingsFrame.BackgroundTransparency = 0.3
settingsFrame.BorderColor3 = Color3.fromRGB(0, 0, 0)
settingsFrame.BorderSizePixel = 2
settingsFrame.AnchorPoint = Vector2.new(0.5, 0.5)
settingsFrame.ClipsDescendants = true
settingsFrame.Parent = mainGui
Instance.new("UICorner", settingsFrame).CornerRadius = UDim.new(0, 12)
settingsFrame.Size = UDim2.new(0, 0, 0, 0)
TweenService:Create(settingsFrame, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0, 340, 0, 270)}):Play()

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, 0, 0, 35)
titleLabel.BackgroundColor3 = Color3.fromRGB(235, 235, 235)
titleLabel.Text = "Settings V2"
titleLabel.TextColor3 = Color3.fromRGB(0, 0, 0)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 18
titleLabel.Parent = settingsFrame
Instance.new("UICorner", titleLabel).CornerRadius = UDim.new(0, 12)

local minimizeButton = Instance.new("TextButton")
minimizeButton.Size = UDim2.new(0, 35, 0, 35)
minimizeButton.Position = UDim2.new(1, -40, 0, 0)
minimizeButton.BackgroundColor3 = Color3.fromRGB(200, 200, 200)
minimizeButton.Text = "-"
minimizeButton.Font = Enum.Font.GothamBold
minimizeButton.TextColor3 = Color3.fromRGB(0, 0, 0)
minimizeButton.TextSize = 20
minimizeButton.Parent = settingsFrame
Instance.new("UICorner", minimizeButton).CornerRadius = UDim.new(1, 0)
minimizeButton.AutoButtonColor = false

local toggleContainer = Instance.new("Frame")
toggleContainer.Size = UDim2.new(1, -20, 0, 90)
toggleContainer.Position = UDim2.new(0, 10, 0, 45)
toggleContainer.BackgroundTransparency = 1
toggleContainer.Parent = settingsFrame

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.new(0.5, -10, 0, 35)
gridLayout.CellPadding = UDim2.new(0, 10, 0, 10)
gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
gridLayout.VerticalAlignment = Enum.VerticalAlignment.Top
gridLayout.Parent = toggleContainer

local m1Button, setM1State = createToggleButton("M1", function(enabled) m1ToggleEnabled = enabled end)
m1Button.Parent = toggleContainer

local dashButton, setDashState = createToggleButton("Dash", function(enabled) dashToggleEnabled = enabled end)
dashButton.Parent = toggleContainer

local discordButton = Instance.new("TextButton")
discordButton.Size = UDim2.new(0, 100, 0, 35)
discordButton.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
discordButton.Text = "Discord"
discordButton.TextColor3 = Color3.fromRGB(0, 0, 0)
discordButton.Font = Enum.Font.GothamBold
discordButton.TextSize = 14
discordButton.AutoButtonColor = false
Instance.new("UICorner", discordButton).CornerRadius = UDim.new(0, 8)
discordButton.Parent = toggleContainer
discordButton.MouseButton1Click:Connect(function()
	pcall(function() clickSound:Play() end)
	local wasCopied = false
	pcall(function() if setclipboard then setclipboard("https://discord.gg/5x4xbPvuSc") wasCopied = true end end)
	if not wasCopied then pcall(function() LocalPlayer:SetAttribute("LastDiscordInvite", "https://discord.gg/5x4xbPvuSc") end) end
	local originalText = discordButton.Text
	discordButton.Text = wasCopied and "Copied" or "Stored"
	task.delay(0.9, function() pcall(function() discordButton.Text = originalText end) end)
end)

local playerListScrollingFrame = Instance.new("ScrollingFrame")
playerListScrollingFrame.Size = UDim2.new(1, -20, 0, 70)
playerListScrollingFrame.Position = UDim2.new(0, 10, 0, 145)
playerListScrollingFrame.BackgroundColor3 = Color3.fromRGB(220, 220, 220)
playerListScrollingFrame.ScrollBarThickness = 4
playerListScrollingFrame.Parent = settingsFrame
Instance.new("UICorner", playerListScrollingFrame).CornerRadius = UDim.new(0, 8)
local listLayout = Instance.new("UIListLayout")
listLayout.Parent = playerListScrollingFrame
listLayout.Padding = UDim.new(0, 4)

local function refreshPlayerList()
	for _, child in ipairs(playerListScrollingFrame:GetChildren()) do
		if child:IsA("TextButton") then child:Destroy() end
	end
	for _, player in ipairs(PlayersService:GetPlayers()) do
		if player ~= LocalPlayer then
			local playerButton = Instance.new("TextButton")
			playerButton.Size = UDim2.new(1, -10, 0, 26)
			playerButton.BackgroundColor3 = Color3.fromRGB(235, 235, 235)
			playerButton.TextColor3 = Color3.fromRGB(0, 0, 0)
			playerButton.TextXAlignment = Enum.TextXAlignment.Left
			playerButton.TextSize = 14
			playerButton.Font = Enum.Font.Gotham
			playerButton.Text = "   " .. player.Name
			playerButton.Parent = playerListScrollingFrame
			playerButton.MouseButton1Click:Connect(function()
				pcall(function() clickSound:Play() end)
				for _, otherButton in ipairs(playerListScrollingFrame:GetChildren()) do
					if otherButton:IsA("TextButton") then otherButton.BackgroundColor3 = Color3.fromRGB(235, 235, 235) end
				end
				if lockedTargetPlayer ~= player then
					lockedTargetPlayer = player
					playerButton.BackgroundColor3 = Color3.fromRGB(100, 200, 255)
				else
					lockedTargetPlayer = nil
					playerButton.BackgroundColor3 = Color3.fromRGB(235, 235, 235)
				end
			end)
			playerButton.MouseButton2Click:Connect(function()
				if lockedTargetPlayer == player then
					lockedTargetPlayer = nil
					playerButton.BackgroundColor3 = Color3.fromRGB(235, 235, 235)
				end
			end)
			Instance.new("UICorner", playerButton).CornerRadius = UDim.new(0, 6)
			if lockedTargetPlayer == player then playerButton.BackgroundColor3 = Color3.fromRGB(100, 200, 255) end
		end
	end
end

refreshPlayerList()

local refreshButton = Instance.new("TextButton")
refreshButton.Size = UDim2.new(0, 110, 0, 36)
refreshButton.Position = UDim2.new(1, -122, 1, -44)
refreshButton.BackgroundColor3 = Color3.fromRGB(90, 90, 90)
refreshButton.Text = "Refresh"
refreshButton.TextColor3 = Color3.fromRGB(255, 255, 255)
refreshButton.Font = Enum.Font.GothamBold
refreshButton.TextSize = 16
refreshButton.Parent = settingsFrame
Instance.new("UICorner", refreshButton).CornerRadius = UDim.new(0, 12)
refreshButton.AutoButtonColor = false
refreshButton.MouseButton1Click:Connect(function() pcall(function() clickSound:Play() end) refreshPlayerList() end)

local adjustButton = Instance.new("TextButton")
adjustButton.Size = UDim2.new(0, 110, 0, 36)
adjustButton.Position = UDim2.new(0, 12, 1, -44)
adjustButton.BackgroundColor3 = Color3.fromRGB(110, 110, 110)
adjustButton.Text = "Adjust"
adjustButton.TextColor3 = Color3.fromRGB(255, 255, 255)
adjustButton.Font = Enum.Font.GothamBold
adjustButton.TextSize = 16
adjustButton.Parent = settingsFrame
Instance.new("UICorner", adjustButton).CornerRadius = UDim.new(0, 12)
adjustButton.AutoButtonColor = false

local settingsToggleButton = Instance.new("TextButton")
settingsToggleButton.Size = UDim2.new(0, 60, 0, 35)
settingsToggleButton.Position = UDim2.new(0.5, -30, 0.5, -17)
settingsToggleButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
settingsToggleButton.Text = "Settings"
settingsToggleButton.TextColor3 = Color3.fromRGB(0, 0, 0)
settingsToggleButton.Font = Enum.Font.GothamBold
settingsToggleButton.TextSize = 14
settingsToggleButton.Visible = false
settingsToggleButton.Parent = mainGui
settingsToggleButton.BorderSizePixel = 2
settingsToggleButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
Instance.new("UICorner", settingsToggleButton).CornerRadius = UDim.new(0, 10)
settingsToggleButton.AutoButtonColor = false

local function addButtonPressEffect(button, callback)
	button.MouseButton1Click:Connect(function()
		button:TweenSize(button.Size - UDim2.new(0, 5, 0, 5), "Out", "Quad", 0.08, true, function()
			button:TweenSize(button.Size + UDim2.new(0, 5, 0, 5), "Out", "Quad", 0.08)
			if callback then callback() end
		end)
	end)
end

addButtonPressEffect(minimizeButton, function()
	pcall(function() clickSound:Play() end)
	TweenService:Create(settingsFrame, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Size = UDim2.new(0, 0, 0, 0)}):Play()
	task.wait(0.28)
	settingsFrame.Visible = false
	settingsToggleButton.Visible = true
end)

addButtonPressEffect(settingsToggleButton, function()
	pcall(function() clickSound:Play() end)
	settingsToggleButton.Visible = false
	settingsFrame.Visible = true
	settingsFrame.Size = UDim2.new(0, 0, 0, 0)
	TweenService:Create(settingsFrame, TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0, 340, 0, 270)}):Play()
end)

addButtonPressEffect(adjustButton, function()
	pcall(function() clickSound:Play() end)
end)

makeFrameDraggable(settingsFrame)
makeFrameDraggable(settingsToggleButton)

PlayersService.PlayerRemoving:Connect(function(removedPlayer) if lockedTargetPlayer == removedPlayer then lockedTargetPlayer = nil end refreshPlayerList() end)
PlayersService.PlayerAdded:Connect(refreshPlayerList)

--// YOUR SLEEK RED DASH BUTTON
local function createMobileDashButton()
	pcall(function() local existingGui = LocalPlayer.PlayerGui:FindFirstChild("CircularTweenUI_Merged") if existingGui then existingGui:Destroy() end end)
	local mobileGui = Instance.new("ScreenGui")
	mobileGui.Name = "CircularTweenUI_Merged"
	mobileGui.ResetOnSpawn = false
	mobileGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	
	local dashButton = Instance.new("ImageButton")
	dashButton.Name = "DashButton"
	dashButton.Size = UDim2.new(0, 110, 0, 110)
	dashButton.Position = UDim2.new(0.5, -55, 0.8, -55)
	dashButton.BackgroundTransparency = 1
	dashButton.BorderSizePixel = 0
	dashButton.Image = "rbxassetid://99317918824094"
	dashButton.Parent = mobileGui
	
	local buttonScale = Instance.new("UIScale", dashButton)
	buttonScale.Scale = 1
	
	local pressSound = Instance.new("Sound", dashButton)
	pressSound.SoundId = BUTTON_PRESS_SOUND_ID
	pressSound.Volume = 0.9
	
	local isButtonPressed = false
	local isBeingDragged = false
	local dragInput = nil
	local dragStartPosition = nil
	local buttonStartPosition = nil
	local dragThreshold = 8
	
	local function animateButtonScale(targetScale, duration)
		duration = duration or 0.06
		local success, tween = pcall(function() return TweenService:Create(buttonScale, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = targetScale}) end)
		if success and tween then tween:Play() end
	end
	
	local function handleInputBegin(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			isButtonPressed = true
			isBeingDragged = false
			dragStartPosition = input.Position
			buttonStartPosition = dashButton.Position
			dragInput = input
			animateButtonScale(0.92, 0.06)
			pcall(function() pressSound:Play() end)
		end
	end
	
	local function handleInputChange(input)
		if isButtonPressed and dragInput and input == dragInput then
			local delta = input.Position - dragStartPosition
			if not isBeingDragged and dragThreshold <= delta.Magnitude then
				isBeingDragged = true
				animateButtonScale(1, 0.06)
			end
			if isBeingDragged then
				local viewportWidth = CurrentCamera.ViewportSize.X
				local viewportHeight = CurrentCamera.ViewportSize.Y
				local newX = math.clamp(buttonStartPosition.X.Offset + delta.X, 0, viewportWidth - dashButton.AbsoluteSize.X)
				local newY = math.clamp(buttonStartPosition.Y.Offset + delta.Y, 0, viewportHeight - dashButton.AbsoluteSize.Y)
				dashButton.Position = UDim2.new(0, newX, 0, newY)
			end
		end
	end
	
	InputService.InputChanged:Connect(function(input) pcall(function() handleInputChange(input) end) end)
	InputService.InputEnded:Connect(function(input)
		if input == dragInput and isButtonPressed then
			if not isBeingDragged and tick() - lastButtonPressTime >= 2 then
				if not isCharacterDisabled() then
					local target = getCurrentTarget()
					if target then performCircularDash(target) end
				end
			end
			animateButtonScale(1, 0.06)
			dragInput = nil
			buttonStartPosition = nil
			dragStartPosition = nil
			isBeingDragged = false
			isButtonPressed = false
		end
	end)
	dashButton.InputBegan:Connect(function(input) pcall(function() handleInputBegin(input) end) end)
end

createMobileDashButton()

print("sub to wasp :)")
