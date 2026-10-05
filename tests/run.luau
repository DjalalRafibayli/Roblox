-- Run with `lune run tests/run` from the repository root.
--
-- Loads the modules that are pure data (Config, TimeFormat, CourseLayout) outside
-- Roblox and checks them, most importantly that every jump in the course can be made
-- by a default character.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

-- Default character: WalkSpeed 16, JumpHeight 7.2, gravity 196.2. A running jump
-- clears about 8.7 studs of open air on flat ground, and less when landing higher.
local WALK_SPEED = 16
local MAX_GAP = 8
local MAX_GAP_RISING = 7 -- when landing more than 1.5 studs higher
local MAX_RISE = 3

-- Modules are loaded with stand-ins for the Roblox globals they use. Module paths
-- (like `script.Parent.CourseLayout`) are faked as strings that `require` maps to files.
local cache = {}
local loadModule

local fakeGame = {
	GetService = function(_, name)
		assert(name == "ReplicatedStorage", "the tests only fake ReplicatedStorage")
		return { Shared = { Config = "shared/Config", TimeFormat = "shared/TimeFormat" } }
	end,
}

local function environmentFor(game)
	return {
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		Enum = roblox.Enum,
		Instance = roblox.Instance,
		UDim2 = roblox.UDim2,
		Vector3 = roblox.Vector3,
		game = game,
		require = loadModule,
		script = { Parent = { CourseLayout = "server/CourseLayout" } },
	}
end

function loadModule(path, game)
	if cache[path] == nil or game then
		local source = fs.readFile("src/" .. path .. ".luau")
		local environment = environmentFor(game or fakeGame)
		cache[path] = luau.load(source, { debugName = path, environment = environment })()
	end
	return cache[path]
end

local Config = loadModule("shared/Config")
local TimeFormat = loadModule("shared/TimeFormat")
local CourseLayout = loadModule("server/CourseLayout")

local failures = 0

local function test(name, callback)
	local ok, err = pcall(callback)
	if ok then
		print("PASS  " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. "\n      " .. tostring(err))
	end
end

local function expectEqual(actual, expected)
	if actual ~= expected then
		error(string.format("expected %s, got %s", tostring(expected), tostring(actual)), 2)
	end
end

-- Open-air distance between the top faces of two route steps.
local function gapBetween(a, b)
	local dx = math.max(0, math.abs(a.center.X - b.center.X) - (a.size.X + b.size.X) / 2)
	local dz = math.max(0, math.abs(a.center.Z - b.center.Z) - (a.size.Z + b.size.Z) / 2)
	return math.sqrt(dx * dx + dz * dz)
end

test("TimeFormat formats run times", function()
	expectEqual(TimeFormat.format(0), "00:00.00")
	expectEqual(TimeFormat.format(12.34), "00:12.34")
	expectEqual(TimeFormat.format(59.999), "00:59.99")
	expectEqual(TimeFormat.format(61.5), "01:01.50")
	expectEqual(TimeFormat.format(3725.07), "1:02:05.07")
	expectEqual(TimeFormat.format(-3), "00:00.00")
	expectEqual(TimeFormat.format(0 / 0), "--:--.--")
	expectEqual(TimeFormat.format(math.huge), "--:--.--")
end)

test("Config lists stages for every tier", function()
	expectEqual(Config.StageCount, #Config.Stages)
	for _, tier in Config.Tiers do
		assert(#tier.stages > 0, tier.name .. " has no stages")
	end
	for index, stage in Config.Stages do
		assert(Config.Tiers[stage.tier], "stage " .. index .. " has an unknown tier")
	end
	expectEqual(Config.tierForStage(0), Config.Tiers[1])
	expectEqual(Config.tierForStage(1), Config.Tiers[1])
	expectEqual(Config.tierForStage(Config.StageCount), Config.Tiers[#Config.Tiers])
	expectEqual(Config.tierForStage(Config.StageCount + 5), Config.Tiers[#Config.Tiers])
end)

local layout = CourseLayout.generate()

test("there is one checkpoint per stage, in order", function()
	local checkpoints = {}
	for _, spec in layout.specs do
		if spec.kind == "Spawn" or spec.kind == "Checkpoint" then
			assert(checkpoints[spec.index] == nil, "duplicate checkpoint " .. tostring(spec.index))
			checkpoints[spec.index] = spec
		end
	end
	for index = 0, Config.StageCount do
		assert(checkpoints[index], "missing checkpoint " .. index)
	end
	for index = 1, Config.StageCount do
		assert(
			checkpoints[index].cframe.Position.Z > checkpoints[index - 1].cframe.Position.Z,
			"checkpoint " .. index .. " is not further along than the one before"
		)
	end

	local finish = checkpoints[Config.StageCount]
	local lastStep = layout.route[#layout.route]
	expectEqual(lastStep.center.Z, finish.cframe.Position.Z)
end)

test("every jump on the route is possible", function()
	assert(#layout.route > Config.StageCount * 2, "the route is suspiciously short")
	for i = 2, #layout.route do
		local from, to = layout.route[i - 1], layout.route[i]
		if not (to.ride or to.climb) then
			local gap = gapBetween(from, to)
			local rise = to.center.Y - from.center.Y
			local limit = if rise > 1.5 then MAX_GAP_RISING else MAX_GAP
			local where = string.format("stage %d (route step %d)", to.stage, i)
			assert(rise <= MAX_RISE, string.format("%s: %.1f stud rise is too high", where, rise))
			assert(gap <= limit, string.format("%s: %.1f stud gap is too wide (max %.1f)", where, gap, limit))
		end
	end
end)

test("there is lava under every surface", function()
	local sheets = {}
	for _, spec in layout.specs do
		if spec.name == "Lava" then
			table.insert(sheets, spec)
		end
	end
	for i, step in layout.route do
		local covered = false
		for _, sheet in sheets do
			local position = sheet.cframe.Position
			if
				math.abs(step.center.X - position.X) <= sheet.size.X / 2
				and math.abs(step.center.Z - position.Z) <= sheet.size.Z / 2
				and position.Y + sheet.size.Y / 2 < step.center.Y
			then
				covered = true
				break
			end
		end
		assert(covered, string.format("stage %d (route step %d) has no lava below it", step.stage, i))
	end
end)

test("moving obstacles stay fair", function()
	for _, spec in layout.specs do
		local where = spec.group .. "/" .. spec.name
		if spec.kind == "Conveyor" then
			assert(spec.velocity.Magnitude <= WALK_SPEED * 0.75, where .. " belt is too fast to walk against")
		elseif spec.kind == "Moving" then
			assert(spec.speed <= WALK_SPEED * 0.75, where .. " moves too fast to catch")
		elseif spec.kind == "Vanish" then
			assert(spec.vanishDelay >= 0.25, where .. " vanishes too quickly")
		elseif spec.kind == "Spinner" then
			assert(spec.armCount >= 1 and spec.speed <= 2, where .. " spins too fast")
		elseif spec.kind == "Truss" then
			for _, axis in { "X", "Y", "Z" } do
				expectEqual(spec.size[axis] % 2, 0)
			end
		end
	end
end)

-- Runs the real builder against Lune's Roblox instance model, which rejects any
-- property or class name that doesn't exist in Roblox.
test("CourseBuilder builds the course from real instances", function()
	local game = roblox.Instance.new("DataModel")
	local CourseBuilder = loadModule("server/CourseBuilder", game)
	local course = CourseBuilder.build()

	expectEqual(course.folder.Parent, game:GetService("Workspace"))
	expectEqual(course.startLine.Name, "StartLine")
	for index = 0, Config.StageCount do
		local pad = course.checkpoints[index]
		assert(pad, "missing checkpoint part " .. index)
		expectEqual(pad:GetAttribute("Index"), index)
		assert(pad:HasTag("Checkpoint"), "checkpoint " .. index .. " is not tagged")
	end
	expectEqual(course.checkpoints[0].ClassName, "SpawnLocation")

	local counts = {}
	for _, instance in course.folder:GetDescendants() do
		for _, tag in instance:GetTags() do
			counts[tag] = (counts[tag] or 0) + 1
		end
		if instance:HasTag("MovingPlatform") then
			assert(instance:FindFirstChildOfClass("PrismaticConstraint"), instance.Name .. " has no slider")
			assert(not instance.Anchored, instance.Name .. " must be unanchored to carry players")
		end
		if instance:HasTag("Spinner") then
			assert(not instance.Anchored, instance.Name .. " must be unanchored to spin")
		end
	end
	for _, tag in { "KillBrick", "MovingPlatform", "VanishPlatform", "Spinner", "Conveyor" } do
		assert((counts[tag] or 0) > 0, "nothing is tagged " .. tag)
	end
end)

if failures > 0 then
	print(string.format("\n%d test(s) failed", failures))
	process.exit(1)
end
print("\nAll tests passed")
