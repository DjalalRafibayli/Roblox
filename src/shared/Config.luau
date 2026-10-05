--!strict
-- Settings shared by the server and the client. To change the course, edit the
-- tiers below: each tier is a difficulty level and lists its stages in order.

export type StageKind = "Jumps" | "LavaHop" | "Zigzag" | "Moving" | "Vanish" | "Spinner" | "Conveyor" | "Truss"

export type Tier = {
	name: string,
	color: Color3,
	stages: { StageKind },
}

export type Stage = {
	kind: StageKind,
	tier: number, -- index into Tiers; also the stage's difficulty (1 = easiest)
}

local Tiers: { Tier } = {
	{
		name = "NOOB",
		color = Color3.fromRGB(46, 204, 113),
		stages = { "Jumps", "Zigzag", "LavaHop", "Moving", "Truss", "Conveyor" },
	},
	{
		name = "ROOKIE",
		color = Color3.fromRGB(52, 152, 219),
		stages = { "Jumps", "Vanish", "Spinner", "LavaHop", "Zigzag", "Moving" },
	},
	{
		name = "PRO",
		color = Color3.fromRGB(155, 89, 182),
		stages = { "Spinner", "Jumps", "Conveyor", "Vanish", "Truss", "Moving" },
	},
	{
		name = "LEGEND",
		color = Color3.fromRGB(241, 196, 15),
		stages = { "Vanish", "Spinner", "Zigzag", "LavaHop", "Conveyor", "Jumps" },
	},
}

local Stages: { Stage } = {}
for tierIndex, tier in Tiers do
	for _, kind: StageKind in tier.stages do
		table.insert(Stages, { kind = kind, tier = tierIndex })
	end
end

local Config = {
	GameName = "Noob to Pro Obby",
	Tiers = Tiers,
	Stages = Stages,
	StageCount = #Stages,

	RespawnDelay = 1.5, -- seconds between falling and respawning
	RestartCooldown = 2, -- seconds between accepted "restart run" requests
	AutosaveInterval = 120, -- seconds
	DataStoreName = "NoobToProObby_v1",
}

-- The tier a stage belongs to. Stage 0 (the lobby) and anything past the end
-- are clamped to the first and last stage.
function Config.tierForStage(stage: number): Tier
	local index = math.clamp(stage, 1, #Stages)
	return Tiers[Stages[index].tier]
end

return Config
