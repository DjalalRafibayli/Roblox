--!strict
-- The on-screen HUD: tier, checkpoint, run timer, best time and falls, the
-- restart button, and small celebrations for checkpoints and finishing.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local TimeFormat = require(ReplicatedStorage.Shared.TimeFormat)

local player = Players.LocalPlayer
local restartRun = ReplicatedStorage.Remotes.RestartRun
local runFinished = ReplicatedStorage.Remotes.RunFinished

local FONT = Enum.Font.FredokaOne
local TIMER_FONT = Enum.Font.RobotoMono
local WHITE = Color3.new(1, 1, 1)
local MUTED = Color3.fromRGB(190, 190, 200)
local GOLD = Color3.fromRGB(255, 200, 40)
local RESTART_TEXT = "RESTART RUN"
local CONFIRM_SECONDS = 3
local TOAST_SECONDS = 2.5

--------------------------------------------------------------------------------
-- Building the UI

local function addCorner(parent: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function addLabel(parent: Instance, name: string, size: UDim2, position: UDim2, font: Enum.Font): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextScaled = true
	label.TextColor3 = WHITE
	label.Text = ""
	label.Parent = parent
	return label
end

local gui = Instance.new("ScreenGui")
gui.Name = "Hud"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.Position = UDim2.new(0.5, 0, 0, 8)
panel.Size = UDim2.fromOffset(300, 110)
panel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
panel.BackgroundTransparency = 0.3
addCorner(panel, 12)
panel.Parent = gui

local tierBadge = addLabel(panel, "Tier", UDim2.fromOffset(96, 26), UDim2.fromOffset(10, 8), FONT)
tierBadge.BackgroundTransparency = 0
addCorner(tierBadge, 8)

local stageLabel = addLabel(panel, "Stage", UDim2.fromOffset(180, 26), UDim2.fromOffset(110, 8), FONT)
stageLabel.TextXAlignment = Enum.TextXAlignment.Right

local timerLabel = addLabel(panel, "Timer", UDim2.new(1, -20, 0, 40), UDim2.fromOffset(10, 38), TIMER_FONT)

local infoLabel = addLabel(panel, "Info", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 82), FONT)
infoLabel.TextColor3 = MUTED

local restartButton = Instance.new("TextButton")
restartButton.Name = "Restart"
restartButton.AnchorPoint = Vector2.new(0.5, 1)
restartButton.Position = UDim2.new(0.5, 0, 1, -12)
restartButton.Size = UDim2.fromOffset(220, 44)
restartButton.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
restartButton.Font = FONT
restartButton.TextScaled = true
restartButton.TextColor3 = WHITE
restartButton.Text = RESTART_TEXT
addCorner(restartButton, 10)
restartButton.Parent = gui

local toast = Instance.new("CanvasGroup")
toast.Name = "Toast"
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.fromScale(0.5, 0.22)
toast.Size = UDim2.new(0.8, 0, 0, 100)
toast.BackgroundTransparency = 1
toast.GroupTransparency = 1
toast.Parent = gui

local toastTitle = addLabel(toast, "Title", UDim2.new(1, 0, 0, 64), UDim2.new(), FONT)
local titleStroke = Instance.new("UIStroke")
titleStroke.Thickness = 3
titleStroke.Parent = toastTitle

local toastSubtitle = addLabel(toast, "Subtitle", UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 66), FONT)
local subtitleStroke = Instance.new("UIStroke")
subtitleStroke.Thickness = 2
subtitleStroke.Parent = toastSubtitle

gui.Parent = player:WaitForChild("PlayerGui")

--------------------------------------------------------------------------------
-- Effects

local toastToken = 0

local function showToast(title: string, subtitle: string?, color: Color3?)
	toastToken += 1
	local token = toastToken
	toastTitle.Text = title
	toastTitle.TextColor3 = color or WHITE
	toastSubtitle.Text = subtitle or ""
	toast.GroupTransparency = 0
	task.delay(TOAST_SECONDS, function()
		if token == toastToken then
			TweenService:Create(toast, TweenInfo.new(0.5), { GroupTransparency = 1 }):Play()
		end
	end)
end

local function confetti()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(20, 35)
	emitter.SpreadAngle = Vector2.new(60, 60)
	emitter.Lifetime = NumberRange.new(1.5, 2.5)
	emitter.Acceleration = Vector3.new(0, -30, 0)
	emitter.Size = NumberSequence.new(0.6)
	emitter.RotSpeed = NumberRange.new(-180, 180)
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(231, 76, 60)),
		ColorSequenceKeypoint.new(0.25, Color3.fromRGB(241, 196, 15)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(46, 204, 113)),
		ColorSequenceKeypoint.new(0.75, Color3.fromRGB(52, 152, 219)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(155, 89, 182)),
	})
	emitter.Parent = root
	emitter:Emit(150)
	task.delay(3, function()
		emitter:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- State

local leaderstats = player:WaitForChild("leaderstats")
local stageValue = leaderstats:WaitForChild("Stage") :: IntValue
local currentStage = stageValue.Value

-- Reached checkpoint pads glow in their tier's colour (only on this player's screen).
type PadLook = { color: Color3, material: Enum.Material }
local padLooks: { [Instance]: PadLook } = {}

local function paintPad(pad: Instance)
	local index = pad:GetAttribute("Index")
	if not pad:IsA("BasePart") or typeof(index) ~= "number" or index < 1 then
		return
	end
	local look = padLooks[pad]
	if not look then
		look = { color = pad.Color, material = pad.Material }
		padLooks[pad] = look
	end
	if index <= currentStage then
		pad.Color = Config.tierForStage(index).color
		pad.Material = Enum.Material.Neon
	else
		pad.Color = look.color
		pad.Material = look.material
	end
end

local function paintAllPads()
	for _, pad in CollectionService:GetTagged("Checkpoint") do
		paintPad(pad)
	end
end

local function refreshStage()
	-- The badge shows the tier of the stage being played, i.e. the next one.
	local tier = Config.tierForStage(currentStage + 1)
	tierBadge.Text = tier.name
	tierBadge.BackgroundColor3 = tier.color
	stageLabel.Text = if currentStage >= Config.StageCount
		then "FINISHED!"
		else string.format("CHECKPOINT %d / %d", currentStage, Config.StageCount)
end

local function refreshInfo()
	local best = player:GetAttribute("BestTime")
	local falls = player:GetAttribute("Falls")
	local parts = {
		"BEST " .. (if typeof(best) == "number" then TimeFormat.format(best) else "--:--.--"),
		"FALLS " .. tostring(if typeof(falls) == "number" then falls else 0),
	}
	if player:GetAttribute("SaveDisabled") then
		table.insert(parts, "NOT SAVING")
	end
	infoLabel.Text = table.concat(parts, "   ")
end

local function updateTimer()
	local runStart = player:GetAttribute("RunStart")
	local lastTime = player:GetAttribute("LastTime")
	if typeof(runStart) == "number" then
		timerLabel.Text = TimeFormat.format(Workspace:GetServerTimeNow() - runStart)
		timerLabel.TextColor3 = WHITE
	elseif typeof(lastTime) == "number" then
		timerLabel.Text = TimeFormat.format(lastTime)
		timerLabel.TextColor3 = GOLD
	elseif currentStage == 0 then
		timerLabel.Text = TimeFormat.format(0)
		timerLabel.TextColor3 = WHITE
	else
		timerLabel.Text = "--:--.--"
		timerLabel.TextColor3 = MUTED
	end
end

--------------------------------------------------------------------------------
-- Events

stageValue.Changed:Connect(function(stage: number)
	local previous = currentStage
	currentStage = stage
	refreshStage()
	paintAllPads()

	if stage == 0 and previous > 0 then
		showToast("RUN RESET", "Cross the start line to start the clock")
	elseif stage == previous + 1 and stage < Config.StageCount then
		local nextTier = Config.tierForStage(stage + 1)
		if nextTier ~= Config.tierForStage(stage) then
			showToast(nextTier.name .. " ZONE!", "Checkpoint " .. stage, nextTier.color)
		else
			showToast("CHECKPOINT " .. stage .. "!", nil, Config.tierForStage(stage).color)
		end
	end
end)

runFinished.OnClientEvent:Connect(function(elapsed: unknown, isBest: unknown)
	local subtitle = if typeof(elapsed) == "number"
		then TimeFormat.format(elapsed) .. (if isBest == true then "   NEW BEST!" else "")
		else "Press RESTART RUN to race the clock"
	showToast("YOU WIN!", subtitle, GOLD)
	confetti()
end)

local confirmUntil = 0
restartButton.Activated:Connect(function()
	-- Restarting wipes the player's checkpoint, so it takes a second tap to confirm.
	local now = os.clock()
	if now < confirmUntil then
		confirmUntil = 0
		restartButton.Text = RESTART_TEXT
		restartRun:FireServer()
		return
	end
	confirmUntil = now + CONFIRM_SECONDS
	restartButton.Text = "TAP AGAIN TO RESTART"
	task.delay(CONFIRM_SECONDS, function()
		if os.clock() >= confirmUntil then
			restartButton.Text = RESTART_TEXT
		end
	end)
end)

for _, attribute in { "BestTime", "Falls", "SaveDisabled" } do
	player:GetAttributeChangedSignal(attribute):Connect(refreshInfo)
end
CollectionService:GetInstanceAddedSignal("Checkpoint"):Connect(paintPad)
CollectionService:GetInstanceRemovedSignal("Checkpoint"):Connect(function(pad)
	padLooks[pad] = nil
end)
RunService.RenderStepped:Connect(updateTimer)

refreshStage()
refreshInfo()
paintAllPads()
if currentStage > 0 and currentStage < Config.StageCount then
	showToast("WELCOME BACK!", "Continuing from checkpoint " .. currentStage)
else
	showToast(string.upper(Config.GameName), "Reach the top. Don't touch the lava!")
end
