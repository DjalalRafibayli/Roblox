--!strict
-- Turns the stage list in Config into plain part descriptions ("specs").
-- Nothing here creates Instances, so the whole course can be checked outside
-- Roblox (see tests/run.luau). CourseBuilder turns the specs into real parts.
--
-- The course runs along +Z. A cursor remembers the front edge (frontZ) and the
-- top height (top) of the last surface, and each obstacle is placed from it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

export type Kind =
	"Spawn"
	| "Checkpoint"
	| "Floor"
	| "Decor"
	| "Kill"
	| "Moving"
	| "Vanish"
	| "Spinner"
	| "Conveyor"
	| "Truss"
	| "Sign"
	| "StartLine"

export type Spec = {
	kind: Kind,
	name: string,
	group: string, -- folder the part goes in ("Lobby", "Stage01", ...)
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	transparency: number?,
	index: number?, -- Spawn/Checkpoint: the stage this checkpoint completes (0 = spawn)
	text: string?, -- Sign/Checkpoint: label
	travel: Vector3?, -- Moving: offset from the start to the end of the track
	speed: number?, -- Moving: studs per second; Spinner: radians per second
	phase: number?, -- Moving: start delay, in half-cycles
	velocity: Vector3?, -- Conveyor: belt velocity
	armCount: number?, -- Spinner
	armLength: number?, -- Spinner
	armHeight: number?, -- Spinner: arm centre above the floor
	vanishDelay: number?, -- Vanish: seconds between being stepped on and vanishing
}

-- A surface the player has to stand on, in the order they reach them.
export type Step = {
	center: Vector3, -- centre of the top face
	size: Vector3,
	stage: number,
	ride: boolean?, -- reached by riding the previous step (the same moving platform)
	climb: boolean?, -- reached by climbing a truss instead of jumping
}

export type Layout = {
	specs: { Spec },
	route: { Step },
}

type Placement = {
	gap: number, -- distance from the cursor to this surface's back edge
	rise: number?, -- height above the cursor's top
	x: number?, -- centre on the X axis
	climb: boolean?,
}

local THICKNESS = 1
local START_HEIGHT = 40
local LOBBY_SIZE = 32
local PAD_SIZE = Vector3.new(10, THICKNESS, 10)
local FINISH_SIZE = Vector3.new(24, THICKNESS, 24)
local PAD_GAP = 4
local LAVA_DEPTH = 16 -- how far below the start of its stage each lava sheet sits
local LAVA_WIDTH = 120
local LAVA_RUNOUT = 20 -- extra lava behind the lobby and past the finish

local LOBBY_COLOR = Color3.fromRGB(200, 205, 215)
local PAD_COLOR = Color3.fromRGB(240, 240, 240)
local SIGN_COLOR = Color3.fromRGB(35, 35, 45)
local KILL_COLOR = Color3.fromRGB(255, 50, 30)
local LAVA_COLOR = Color3.fromRGB(255, 110, 20)
local FINISH_COLOR = Color3.fromRGB(255, 200, 40)
local CONVEYOR_COLOR = Color3.fromRGB(60, 60, 70)
local TRUSS_COLOR = Color3.fromRGB(190, 190, 200)
local HUB_COLOR = Color3.fromRGB(70, 70, 80)
local WHITE = Color3.new(1, 1, 1)

local CourseLayout = {}

function CourseLayout.generate(): Layout
	local specs: { Spec } = {}
	local route: { Step } = {}

	local group = "Lobby"
	local stage = 0
	local color = LOBBY_COLOR
	local frontZ = 0
	local top = START_HEIGHT

	-- Adds a box with its top face at `topY`, centred on `x`, starting at `backZ`.
	local function box(kind: Kind, name: string, size: Vector3, x: number, topY: number, backZ: number): Spec
		local spec: Spec = {
			kind = kind,
			name = name,
			group = group,
			size = size,
			cframe = CFrame.new(x, topY - size.Y / 2, backZ + size.Z / 2),
			color = color,
			material = Enum.Material.SmoothPlastic,
		}
		table.insert(specs, spec)
		return spec
	end

	local function addStep(spec: Spec, offset: Vector3?, ride: boolean?, climb: boolean?)
		table.insert(route, {
			center = spec.cframe.Position + Vector3.new(0, spec.size.Y / 2, 0) + (offset or Vector3.zero),
			size = spec.size,
			stage = stage,
			ride = ride,
			climb = climb,
		})
	end

	-- Adds a surface to stand on and moves the cursor to its front edge.
	local function surface(kind: Kind, name: string, size: Vector3, placement: Placement): Spec
		top += placement.rise or 0
		local spec = box(kind, name, size, placement.x or 0, top, frontZ + placement.gap)
		frontZ += placement.gap + size.Z
		addStep(spec, nil, nil, placement.climb)
		return spec
	end

	-- Adds a flat beam covering the given X/Z range at the cursor's height.
	local function beam(name: string, minX: number, maxX: number, minZ: number, maxZ: number)
		local spec = box("Floor", name, Vector3.new(maxX - minX, THICKNESS, maxZ - minZ), (minX + maxX) / 2, top, minZ)
		addStep(spec)
		frontZ = maxZ
	end

	-- Adds a sign hanging above the cursor's front edge, facing the player.
	local function sign(name: string, text: string, height: number)
		local spec = box("Sign", name, Vector3.new(24, 6, 1), 0, top + height, frontZ - 1)
		spec.text = text
		spec.color = SIGN_COLOR
	end

	local function lava(fromZ: number, toZ: number, stageTop: number)
		local spec = box("Kill", "Lava", Vector3.new(LAVA_WIDTH, 2, toZ - fromZ), 0, stageTop - LAVA_DEPTH, fromZ)
		spec.color = LAVA_COLOR
		spec.material = Enum.Material.Neon
	end

	-- One builder per stage kind. `d` is the difficulty, 1 (NOOB) to 4 (LEGEND).
	local builders: { [Config.StageKind]: (d: number) -> () } = {
		-- Platforms to jump between: smaller, further apart and zig-zagging as d grows.
		Jumps = function(d)
			local width = 7 - d
			for i = 1, 4 + d do
				surface("Floor", "Jump" .. i, Vector3.new(width, THICKNESS, width), {
					gap = 3.5 + d,
					rise = if i % 2 == 0 then 1.5 else 0,
					x = if d >= 2 then (if i % 2 == 0 then 2 else -2) else 0,
				})
			end
		end,

		-- Safe tiles with longer and longer lava tiles between them.
		LavaHop = function(d)
			local killLength = 2 + d
			surface("Floor", "Safe0", Vector3.new(8, THICKNESS, 4), { gap = PAD_GAP })
			for i = 1, 3 + d do
				local tile = box("Kill", "LavaTile" .. i, Vector3.new(8, THICKNESS, killLength), 0, top, frontZ)
				tile.color = KILL_COLOR
				tile.material = Enum.Material.Neon
				surface("Floor", "Safe" .. i, Vector3.new(8, THICKNESS, 4), { gap = killLength })
			end
		end,

		-- Narrow beams in a zig-zag, thinner as d grows.
		Zigzag = function(d)
			local w = 2.6 - 0.3 * d
			local run = 12
			local side = 8
			local z = frontZ + 3
			beam("Beam1", -w / 2, w / 2, z, z + run)
			beam("Beam2", w / 2, side + w / 2, z + run - w, z + run)
			beam("Beam3", side - w / 2, side + w / 2, z + run, z + 2 * run)
			beam("Beam4", -w / 2, side - w / 2, z + 2 * run - w, z + 2 * run)
			beam("Beam5", -w / 2, w / 2, z + 2 * run, z + 3 * run)
		end,

		-- Platforms sliding forward along a track. Neighbours move in opposite
		-- phases, so one waits at its start while the previous one waits at its end.
		Moving = function(d)
			local size = if d <= 2 then 6 else 5
			local travel = 12 + 2 * d
			for i = 1, if d <= 2 then 2 else 3 do
				local platform = box("Moving", "Mover" .. i, Vector3.new(size, THICKNESS, size), 0, top, frontZ + 3)
				platform.travel = Vector3.new(0, 0, travel)
				platform.speed = 5 + d
				platform.phase = (i - 1) % 2
				platform.color = color:Lerp(WHITE, 0.35)
				addStep(platform)
				addStep(platform, Vector3.new(0, 0, travel), true)
				frontZ += 3 + size + travel
			end
		end,

		-- Glass platforms that vanish shortly after being stepped on.
		Vanish = function(d)
			local size = if d <= 2 then 5 else 4
			for i = 1, 4 + d do
				local platform = surface("Vanish", "Vanish" .. i, Vector3.new(size, THICKNESS, size), {
					gap = 3 + 0.75 * d,
					x = if i % 2 == 0 then 1.5 else -1.5,
				})
				platform.vanishDelay = 0.9 - 0.15 * d
				platform.material = Enum.Material.Glass
				platform.transparency = 0.2
			end
		end,

		-- A floor swept by a spinning lava bar (a cross of two bars from d = 3).
		Spinner = function(d)
			local floor = surface("Floor", "SpinnerFloor", Vector3.new(22, THICKNESS, 22), { gap = PAD_GAP })
			local center = floor.cframe.Position
			local hub = box("Spinner", "Spinner", Vector3.new(2, 4, 2), center.X, top + 4, center.Z - 1)
			hub.color = HUB_COLOR
			hub.material = Enum.Material.Metal
			hub.speed = 0.8 + 0.25 * d
			hub.armCount = if d >= 3 then 2 else 1
			hub.armLength = 20
			hub.armHeight = 1.25
		end,

		-- A belt pushing players back, with lava blocks to dodge.
		Conveyor = function(d)
			local length = 24 + 6 * d
			local belt = surface("Conveyor", "Conveyor", Vector3.new(8, THICKNESS, length), { gap = PAD_GAP })
			belt.velocity = Vector3.new(0, 0, -(4 + 1.5 * d))
			belt.color = CONVEYOR_COLOR
			belt.material = Enum.Material.DiamondPlate
			local backZ = frontZ - length
			local blocks = 1 + d
			for i = 1, blocks do
				local x = if i % 2 == 0 then 2.5 else -2.5
				local z = backZ + length * i / (blocks + 1) - 1
				local block = box("Kill", "Block" .. i, Vector3.new(3, 2, 2), x, top + 2, z)
				block.color = KILL_COLOR
				block.material = Enum.Material.Neon
			end
			-- Jumping off a moving belt is much harder, so the belt ends on solid ground.
			surface("Floor", "ConveyorExit", Vector3.new(8, THICKNESS, 4), { gap = 0 })
		end,

		-- A truss to climb up to the next platform.
		Truss = function(d)
			local height = 10 + 4 * d -- TrussPart sizes must be multiples of 2
			surface("Floor", "TrussBase", Vector3.new(8, THICKNESS, 8), { gap = PAD_GAP })
			local truss = box("Truss", "Truss", Vector3.new(2, height, 2), 0, top + height, frontZ - 2)
			truss.color = TRUSS_COLOR
			truss.material = Enum.Material.Metal
			surface("Floor", "TrussTop", Vector3.new(8, THICKNESS, 8), { gap = 0, rise = height, climb = true })
		end,
	}

	-- Lobby
	local lobby = box("Floor", "LobbyFloor", Vector3.new(LOBBY_SIZE, THICKNESS, LOBBY_SIZE), 0, top, -LOBBY_SIZE)
	addStep(lobby)
	local spawn = box("Spawn", "Spawn", Vector3.new(8, THICKNESS, 8), 0, top + 0.2, -LOBBY_SIZE / 2 - 4)
	spawn.index = 0
	spawn.color = PAD_COLOR
	local stripe = box("Decor", "StartStripe", Vector3.new(LOBBY_SIZE, 0.2, 2), 0, top + 0.1, -2)
	stripe.color = WHITE
	stripe.material = Enum.Material.Neon
	local startLine = box("StartLine", "StartLine", Vector3.new(LOBBY_SIZE, 12, 1), 0, top + 12, -1)
	startLine.transparency = 1
	sign("TitleSign", string.upper(Config.GameName), 22)
	lava(-LOBBY_SIZE - LAVA_RUNOUT, 0, top)

	-- Stages, each ending in a checkpoint pad
	local previousTier = 1
	for index, definition in Config.Stages do
		stage = index
		group = string.format("Stage%02d", index)
		local tier = Config.Tiers[definition.tier]
		color = tier.color

		if definition.tier ~= previousTier then
			sign("TierSign", tier.name .. " ZONE", 20)
			previousTier = definition.tier
		end

		local startZ = frontZ
		local startTop = top
		builders[definition.kind](definition.tier)

		local isFinish = index == #Config.Stages
		local pad = surface(
			"Checkpoint",
			if isFinish then "Finish" else "Checkpoint",
			if isFinish then FINISH_SIZE else PAD_SIZE,
			{ gap = PAD_GAP }
		)
		pad.index = index
		pad.text = if isFinish then "FINISH" else tostring(index)
		pad.color = if isFinish then FINISH_COLOR else PAD_COLOR
		if isFinish then
			sign("FinishSign", "YOU MADE IT!", 16)
		end

		-- Stages only climb, so lava below the stage's starting height catches every fall.
		lava(startZ, frontZ + (if isFinish then LAVA_RUNOUT else 0), startTop)
	end

	return { specs = specs, route = route }
end

return CourseLayout
