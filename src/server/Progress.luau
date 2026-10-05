--!strict
-- Player progress: loading and saving, checkpoints, respawning at the last
-- checkpoint, and the run timer.
--
-- A "run" starts when a player crosses the start line from the lobby and ends at
-- the finish. Players who come back mid-course keep their checkpoint, but the
-- clock only runs after they restart from the lobby.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local CourseBuilder = require(script.Parent.CourseBuilder)
local PlayerData = require(script.Parent.PlayerData)

local restartRun = ReplicatedStorage.Remotes.RestartRun
local runFinished = ReplicatedStorage.Remotes.RunFinished

-- How far (in studs, beyond the pad's own size) a character may be from a pad it
-- touched. Real touches are always close; this ignores faked far-away touches.
local TOUCH_TOLERANCE = 12
local SHUTDOWN_TIMEOUT = 25

type Session = {
	data: PlayerData.Data,
	canSave: boolean,
	dirty: boolean,
	runStart: number?,
	falls: number,
	lastRestart: number,
	stageValue: IntValue,
	winsValue: IntValue,
}

local Progress = {}

local sessions: { [Player]: Session } = {}
local pendingSaves = 0
local course: CourseBuilder.Course

local function serverTime(): number
	return Workspace:GetServerTimeNow()
end

-- The player (and character) that a touching part belongs to.
local function playerFromHit(hit: BasePart): (Player?, Model?)
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return nil, nil
	end
	return Players:GetPlayerFromCharacter(character), character
end

local function save(player: Player, session: Session)
	if not session.canSave or not session.dirty then
		return
	end
	session.dirty = false
	pendingSaves += 1
	local saved = PlayerData.save(player, session.data)
	pendingSaves -= 1
	if not saved then
		session.dirty = true
	end
end

local function setStage(session: Session, stage: number)
	session.data.stage = stage
	session.stageValue.Value = stage
	session.dirty = true
end

-- Starts (or, with nil, cancels) the run clock and resets the run's counters.
local function setRunStart(player: Player, session: Session, runStart: number?)
	session.runStart = runStart
	session.falls = 0
	player:SetAttribute("RunStart", runStart)
	player:SetAttribute("Falls", 0)
	player:SetAttribute("LastTime", nil)
end

local function spawnPlayer(player: Player, session: Session)
	if sessions[player] ~= session then
		return
	end
	local loaded, err = pcall(player.LoadCharacterAsync, player)
	if not loaded then
		warn("[Progress] Could not spawn " .. player.Name .. ": " .. tostring(err))
		return
	end

	local character = player.Character
	if sessions[player] ~= session or not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return
	end

	-- Stand the character on its checkpoint, facing along the course (+Z).
	local pad = course.checkpoints[session.data.stage] or course.checkpoints[0]
	local legHeight = if humanoid.RigType == Enum.HumanoidRigType.R6 then 2 else humanoid.HipHeight
	local position = pad.Position + Vector3.yAxis * (pad.Size.Y / 2 + legHeight + root.Size.Y / 2 + 0.5)
	character:PivotTo(CFrame.lookAt(position, position + Vector3.zAxis))

	humanoid.Died:Once(function()
		if player.Character ~= character then
			return
		end
		session.falls += 1
		player:SetAttribute("Falls", session.falls)
		task.delay(Config.RespawnDelay, function()
			if player.Character == character then
				spawnPlayer(player, session)
			end
		end)
	end)
end

local function finishRun(player: Player, session: Session)
	session.data.wins += 1
	session.winsValue.Value = session.data.wins
	session.dirty = true

	local runStart = session.runStart
	if not runStart then
		-- Progress carried over from an earlier visit, so the clock wasn't running.
		runFinished:FireClient(player, nil, false)
		return
	end

	local elapsed = serverTime() - runStart
	local best = session.data.bestTime
	local isBest = best == nil or elapsed < best
	if isBest then
		session.data.bestTime = elapsed
		player:SetAttribute("BestTime", elapsed)
	end
	session.runStart = nil
	player:SetAttribute("RunStart", nil)
	player:SetAttribute("LastTime", elapsed)
	runFinished:FireClient(player, elapsed, isBest)
end

local function onCheckpointTouched(index: number, pad: BasePart, hit: BasePart)
	local player, character = playerFromHit(hit)
	if not player or not character then
		return
	end
	local session = sessions[player]
	if not session or index ~= session.data.stage + 1 then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return
	end
	if (root.Position - pad.Position).Magnitude > pad.Size.Magnitude / 2 + TOUCH_TOLERANCE then
		return
	end

	setStage(session, index)
	if index == Config.StageCount then
		finishRun(player, session)
	end
end

local function onStartLineTouched(hit: BasePart)
	local player = playerFromHit(hit)
	if not player then
		return
	end
	local session = sessions[player]
	if not session or session.data.stage ~= 0 or session.runStart then
		return
	end
	setRunStart(player, session, serverTime())
end

local function onRestartRequested(player: Player)
	local session = sessions[player]
	local now = os.clock()
	if not session or now - session.lastRestart < Config.RestartCooldown then
		return
	end
	session.lastRestart = now
	setRunStart(player, session, nil)
	setStage(session, 0)
	spawnPlayer(player, session)
end

local function onPlayerAdded(player: Player)
	local data, loaded = PlayerData.load(player)
	if player.Parent ~= Players then
		return -- left while loading
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local stageValue = Instance.new("IntValue")
	stageValue.Name = "Stage"
	stageValue.Value = data.stage
	stageValue.Parent = leaderstats

	local winsValue = Instance.new("IntValue")
	winsValue.Name = "Wins"
	winsValue.Value = data.wins
	winsValue.Parent = leaderstats

	leaderstats.Parent = player

	local session: Session = {
		data = data,
		canSave = loaded,
		dirty = false,
		runStart = nil,
		falls = 0,
		lastRestart = 0,
		stageValue = stageValue,
		winsValue = winsValue,
	}
	sessions[player] = session

	player:SetAttribute("BestTime", data.bestTime)
	player:SetAttribute("Falls", 0)
	if not loaded then
		player:SetAttribute("SaveDisabled", true)
	end
	spawnPlayer(player, session)
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	sessions[player] = nil
	save(player, session)
end

function Progress.start(builtCourse: CourseBuilder.Course)
	course = builtCourse
	-- Characters are spawned by spawnPlayer, so they appear on the right checkpoint.
	Players.CharacterAutoLoads = false

	for index, pad in course.checkpoints do
		if index > 0 then
			pad.Touched:Connect(function(hit)
				onCheckpointTouched(index, pad, hit)
			end)
		end
	end
	course.startLine.Touched:Connect(onStartLineTouched)
	restartRun.OnServerEvent:Connect(onRestartRequested)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	task.spawn(function()
		while true do
			task.wait(Config.AutosaveInterval)
			for player, session in sessions do
				task.spawn(save, player, session)
			end
		end
	end)

	game:BindToClose(function()
		for player, session in sessions do
			task.spawn(save, player, session)
		end
		local deadline = os.clock() + SHUTDOWN_TIMEOUT
		while pendingSaves > 0 and os.clock() < deadline do
			task.wait()
		end
	end)
end

return Progress
