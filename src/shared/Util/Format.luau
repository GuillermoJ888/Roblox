-- Texto para mostrar cantidades: 950 -> "950", 1.25 -> "1.25", 1250 -> "1.25K", 3400000 -> "3.4M"

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

function Format.number(value: number): string
	local amount = math.abs(value)
	local index = 1
	while amount >= 1000 and index < #SUFFIXES do
		amount /= 1000
		index += 1
	end

	-- Dos decimales como máximo, sin ceros sobrantes ("1.50" -> "1.5", "50.00" -> "50")
	local text = string.format("%.2f", math.floor(amount * 100) / 100)
	if string.find(text, "%.") then
		text = string.gsub(text, "%.?0+$", "")
	end

	return (if value < 0 then "-" else "") .. text .. SUFFIXES[index]
end

function Format.money(value: number): string
	return "$" .. Format.number(value)
end

-- Tiempo restante: 95 -> "1:35", 3725 -> "1:02:05"
function Format.time(seconds: number): string
	local total = math.max(math.ceil(seconds), 0)
	local hours = math.floor(total / 3600)
	local minutes = math.floor(total % 3600 / 60)
	local secs = total % 60
	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, secs)
	end
	return string.format("%d:%02d", minutes, secs)
end

return Format
