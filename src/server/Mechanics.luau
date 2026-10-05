--!strict
-- Behaviour for the tagged course parts that CourseBuilder creates.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local MOVING_PAUSE = 1.5 -- seconds a moving platform waits at each end
local DEFAULT_VANISH_DELAY = 0.6
local REAPPEAR_DELAY = 3
local VANISHED_TRANSPARENCY = 0.9

local Mechanics = {}

-- The living humanoid of the player character that `hit` belongs to, if any.
local function touchingHumanoid(hit: BasePart): Humanoid?
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character or not Players:GetPlayerFromCharacter(character) then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

local function forEachTagged(tag: string, callback: (BasePart) -> ())
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:IsA("BasePart") then
			callback(instance)
		end
	end
end

-- Physics-driven parts are simulated by the server so every player sees them the same way.
local function simulateOnServer(part: BasePart)
	if part:CanSetNetworkOwnership() then
		part:SetNetworkOwner(nil)
	end
end

local function setUpKillBrick(part: BasePart)
	part.Touched:Connect(function(hit)
		local humanoid = touchingHumanoid(hit)
		if humanoid then
			humanoid.Health = 0
		end
	end)
end

local function setUpMovingPlatform(platform: BasePart)
	local slider = platform:FindFirstChildOfClass("PrismaticConstraint")
	local travel = platform:GetAttribute("Travel")
	local speed = platform:GetAttribute("Speed")
	local phase = platform:GetAttribute("Phase")
	if not slider or typeof(travel) ~= "number" or typeof(speed) ~= "number" then
		warn("[Mechanics] Moving platform is missing its setup: " .. platform:GetFullName())
		return
	end

	simulateOnServer(platform)
	local halfCycle = travel / speed + MOVING_PAUSE
	task.spawn(function()
		task.wait(halfCycle * (if typeof(phase) == "number" then phase else 0))
		local target = travel
		while platform.Parent do
			slider.TargetPosition = target
			task.wait(halfCycle)
			target = travel - target
		end
	end)
end

local function setUpVanishPlatform(part: BasePart)
	local delayAttribute = part:GetAttribute("VanishDelay")
	local vanishDelay = if typeof(delayAttribute) == "number" then delayAttribute else DEFAULT_VANISH_DELAY
	local visibleTransparency = part.Transparency
	local busy = false

	part.Touched:Connect(function(hit)
		if busy or not touchingHumanoid(hit) then
			return
		end
		busy = true
		TweenService:Create(part, TweenInfo.new(vanishDelay), { Transparency = 0.7 }):Play()
		task.wait(vanishDelay)
		part.CanCollide = false
		part.Transparency = VANISHED_TRANSPARENCY
		task.wait(REAPPEAR_DELAY)
		part.CanCollide = true
		part.Transparency = visibleTransparency
		busy = false
	end)
end

local function setUpConveyor(part: BasePart)
	-- An anchored part with a velocity moves whatever stands on it without moving itself.
	local velocity = part:GetAttribute("Velocity")
	if typeof(velocity) == "Vector3" then
		part.AssemblyLinearVelocity = velocity
	end
end

function Mechanics.start()
	forEachTagged("KillBrick", setUpKillBrick)
	forEachTagged("MovingPlatform", setUpMovingPlatform)
	forEachTagged("VanishPlatform", setUpVanishPlatform)
	forEachTagged("Spinner", simulateOnServer)
	forEachTagged("Conveyor", setUpConveyor)
end

return Mechanics
