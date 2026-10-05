--!strict
-- Formats run times for the HUD.

local TimeFormat = {}

-- "MM:SS.cc", or "H:MM:SS.cc" from an hour up. Rounds down, so a time never
-- looks faster than it was.
function TimeFormat.format(seconds: number): string
	if seconds ~= seconds or seconds == math.huge then
		return "--:--.--"
	end

	-- The small epsilon stops values like 12.34 (stored as 12.3399...) losing a centisecond.
	local totalCentiseconds = math.floor(math.max(seconds, 0) * 100 + 1e-6)
	local centiseconds = totalCentiseconds % 100
	local totalSeconds = totalCentiseconds // 100
	local hours = totalSeconds // 3600
	local minutes = (totalSeconds // 60) % 60
	local secs = totalSeconds % 60

	if hours > 0 then
		return string.format("%d:%02d:%02d.%02d", hours, minutes, secs, centiseconds)
	end
	return string.format("%02d:%02d.%02d", minutes, secs, centiseconds)
end

return TimeFormat
