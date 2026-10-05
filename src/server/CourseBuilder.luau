--!strict
-- Builds the course in Workspace from the CourseLayout specs. Moving parts get
-- tags and attributes here; Mechanics gives them their behaviour.

local Workspace = game:GetService("Workspace")

local CourseLayout = require(script.Parent.CourseLayout)

type Spec = CourseLayout.Spec

export type Course = {
	folder: Folder,
	checkpoints: { [number]: BasePart }, -- by stage index; 0 is the spawn
	startLine: BasePart,
}

local TEXT_FONT = Enum.Font.FredokaOne
local TEXT_COLOR = Color3.new(1, 1, 1)
local PAD_LABEL_DISTANCE = 150 -- studs; hides far-away checkpoint numbers
local KILL_COLOR = Color3.fromRGB(255, 50, 30)
local MAX_FORCE = 1e7

-- Attachment orientations: a constraint's axis is its attachments' X axis.
local UP_AXIS = CFrame.fromMatrix(Vector3.zero, Vector3.yAxis, Vector3.xAxis)

local CourseBuilder = {}

local function style(part: BasePart, spec: Spec)
	part.Name = spec.name
	part.Anchored = true
	part.Size = spec.size
	part.CFrame = spec.cframe
	part.Color = spec.color
	part.Material = spec.material
	part.Transparency = spec.transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function newTextLabel(text: string): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = TEXT_FONT
	label.TextScaled = true
	label.TextColor3 = TEXT_COLOR
	label.TextStrokeTransparency = 0.4
	label.Text = text
	return label
end

-- Text painted on the sign's front face, which faces players coming along the course.
local function addSignText(part: BasePart, text: string)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	newTextLabel(text).Parent = gui
	gui.Parent = part
end

-- A label floating above a checkpoint; billboards always face the camera.
local function addPadLabel(part: BasePart, text: string)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(8, 3) -- studs
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.MaxDistance = PAD_LABEL_DISTANCE
	gui.LightInfluence = 0
	newTextLabel(text).Parent = gui
	gui.Parent = part
end

-- A platform on a servo-driven PrismaticConstraint. Being physically simulated
-- (rather than teleported) is what lets it carry players standing on it.
local function buildMoving(spec: Spec, parent: Instance)
	local travel = assert(spec.travel, "moving platform needs travel")
	local trackAxis = CFrame.fromMatrix(Vector3.zero, travel.Unit, Vector3.yAxis)

	local rail = Instance.new("Part")
	rail.Name = spec.name .. "Rail"
	rail.Anchored = true
	rail.CanCollide = false
	rail.CanTouch = false
	rail.CanQuery = false
	rail.Transparency = 1
	rail.Size = Vector3.one
	rail.CFrame = spec.cframe
	rail.Parent = parent

	local platform = Instance.new("Part")
	style(platform, spec)
	platform.Anchored = false
	platform:SetAttribute("Travel", travel.Magnitude)
	platform:SetAttribute("Speed", spec.speed)
	platform:SetAttribute("Phase", spec.phase)
	platform:AddTag("MovingPlatform")

	local railAttachment = Instance.new("Attachment")
	railAttachment.CFrame = trackAxis
	railAttachment.Parent = rail

	local platformAttachment = Instance.new("Attachment")
	platformAttachment.CFrame = trackAxis
	platformAttachment.Parent = platform

	local slider = Instance.new("PrismaticConstraint")
	slider.Attachment0 = railAttachment
	slider.Attachment1 = platformAttachment
	slider.ActuatorType = Enum.ActuatorType.Servo
	slider.ServoMaxForce = MAX_FORCE
	slider.Speed = spec.speed or 6
	slider.LimitsEnabled = true
	slider.LowerLimit = 0
	slider.UpperLimit = travel.Magnitude
	slider.TargetPosition = 0
	slider.Parent = platform

	platform.Parent = parent
end

-- An anchored hub with lava arms turned by a motorised HingeConstraint.
local function buildSpinner(spec: Spec, parent: Instance)
	local hub = Instance.new("Part")
	style(hub, spec)
	hub.Parent = parent

	local armCount = spec.armCount or 1
	local hubPosition = spec.cframe.Position
	local armY = hubPosition.Y - spec.size.Y / 2 + (spec.armHeight or 1)
	local pivot = CFrame.new(hubPosition.X, armY, hubPosition.Z)

	local rotor: Part? = nil
	for i = 1, armCount do
		local arm = Instance.new("Part")
		arm.Name = "Arm" .. i
		arm.Size = Vector3.new(assert(spec.armLength, "spinner needs an arm length"), 1, 1)
		arm.CFrame = pivot * CFrame.Angles(0, (i - 1) * math.pi / armCount, 0)
		arm.Color = KILL_COLOR
		arm.Material = Enum.Material.Neon
		arm.CanCollide = false -- touching kills anyway; this avoids flinging players
		arm:AddTag("KillBrick")
		if rotor then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = rotor
			weld.Part1 = arm
			weld.Parent = arm
		else
			rotor = arm
			arm:AddTag("Spinner")
		end
		arm.Parent = parent
	end

	local hubAttachment = Instance.new("Attachment")
	hubAttachment.CFrame = CFrame.new(0, armY - hubPosition.Y, 0) * UP_AXIS
	hubAttachment.Parent = hub

	local rotorAttachment = Instance.new("Attachment")
	rotorAttachment.CFrame = UP_AXIS
	rotorAttachment.Parent = assert(rotor, "spinner needs at least one arm")

	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0 = hubAttachment
	hinge.Attachment1 = rotorAttachment
	hinge.ActuatorType = Enum.ActuatorType.Motor
	hinge.AngularVelocity = spec.speed or 1
	hinge.MotorMaxTorque = MAX_FORCE
	hinge.Parent = hub
end

function CourseBuilder.build(): Course
	local layout = CourseLayout.generate()

	local folder = Instance.new("Folder")
	folder.Name = "Course"

	local groups: { [string]: Folder } = {}
	local function groupFolder(name: string): Folder
		local existing = groups[name]
		if existing then
			return existing
		end
		local group = Instance.new("Folder")
		group.Name = name
		group.Parent = folder
		groups[name] = group
		return group
	end

	local checkpoints: { [number]: BasePart } = {}
	local startLine: BasePart? = nil

	for _, spec in layout.specs do
		local parent = groupFolder(spec.group)
		local kind = spec.kind

		if kind == "Moving" then
			buildMoving(spec, parent)
		elseif kind == "Spinner" then
			buildSpinner(spec, parent)
		else
			local part: BasePart
			if kind == "Spawn" then
				local spawn = Instance.new("SpawnLocation")
				spawn.Neutral = true
				spawn.Duration = 0 -- no spawn force field
				spawn.AllowTeamChangeOnTouch = false
				part = spawn
			elseif kind == "Truss" then
				part = Instance.new("TrussPart")
			else
				part = Instance.new("Part")
			end
			style(part, spec)

			if kind == "Spawn" or kind == "Checkpoint" then
				local index = assert(spec.index, "checkpoint needs an index")
				part:AddTag("Checkpoint")
				part:SetAttribute("Index", index)
				checkpoints[index] = part
				if spec.text then
					addPadLabel(part, spec.text)
				end
			elseif kind == "Kill" then
				part:AddTag("KillBrick")
			elseif kind == "Vanish" then
				part:AddTag("VanishPlatform")
				part:SetAttribute("VanishDelay", spec.vanishDelay)
			elseif kind == "Conveyor" then
				part:AddTag("Conveyor")
				part:SetAttribute("Velocity", spec.velocity)
			elseif kind == "Sign" then
				addSignText(part, spec.text or "")
			elseif kind == "Decor" then
				part.CanCollide = false
				part.CanTouch = false
				part.CanQuery = false
			elseif kind == "StartLine" then
				part.CanCollide = false
				part.CanQuery = false
				startLine = part
			end

			part.Parent = parent
		end
	end

	folder.Parent = Workspace

	return {
		folder = folder,
		checkpoints = checkpoints,
		startLine = assert(startLine, "the layout has no start line"),
	}
end

return CourseBuilder
