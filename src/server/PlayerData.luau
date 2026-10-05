--!strict
-- Loads and saves each player's progress with DataStoreService.
--
-- Only progress is stored (checkpoint, wins, best time), keyed by UserId. Nothing
-- typed by players is collected or saved.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

export type Data = {
	stage: number,
	wins: number,
	bestTime: number?,
}

local MAX_ATTEMPTS = 3

local PlayerData = {}

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[PlayerData] DataStores are unavailable, progress will not save: " .. tostring(result))
	end
end

local function keyFor(player: Player): string
	return "player_" .. player.UserId
end

-- Saved data could come from an older version of the game, so check every field.
local function sanitize(raw: any): Data
	local data: Data = { stage = 0, wins = 0, bestTime = nil }
	if type(raw) ~= "table" then
		return data
	end
	if type(raw.stage) == "number" then
		data.stage = math.clamp(math.floor(raw.stage), 0, Config.StageCount)
	end
	if type(raw.wins) == "number" then
		data.wins = math.max(math.floor(raw.wins), 0)
	end
	if type(raw.bestTime) == "number" and raw.bestTime > 0 and raw.bestTime < math.huge then
		data.bestTime = raw.bestTime
	end
	return data
end

-- Calls a DataStore request, retrying with backoff. Returns whether it succeeded and its result.
local function withRetries(action: string, player: Player, request: () -> any): (boolean, any)
	for attempt = 1, MAX_ATTEMPTS do
		local ok, result = pcall(request)
		if ok then
			return true, result
		end

		local message = tostring(result)
		warn(
			string.format(
				"[PlayerData] %s failed for %s (attempt %d/%d): %s",
				action,
				player.Name,
				attempt,
				MAX_ATTEMPTS,
				message
			)
		)
		if string.find(message, "StudioAccessToApisNotAllowed", 1, true) then
			-- Studio without "Enable Studio Access to API Services": every request will fail.
			store = nil
			return false, nil
		end
		if attempt < MAX_ATTEMPTS then
			task.wait(2 ^ attempt)
		end
	end
	return false, nil
end

-- Returns the player's data and whether it loaded. When loading fails the caller
-- must not save, or the defaults would overwrite the player's real progress.
function PlayerData.load(player: Player): (Data, boolean)
	local dataStore = store
	if not dataStore then
		return sanitize(nil), false
	end

	local loaded, raw = withRetries("Load", player, function()
		return (dataStore:GetAsync(keyFor(player)))
	end)
	return sanitize(raw), loaded
end

function PlayerData.save(player: Player, data: Data): boolean
	local dataStore = store
	if not dataStore then
		return false
	end

	local payload = { stage = data.stage, wins = data.wins, bestTime = data.bestTime }
	local saved = withRetries("Save", player, function()
		return dataStore:SetAsync(keyFor(player), payload, { player.UserId })
	end)
	return saved
end

return PlayerData
