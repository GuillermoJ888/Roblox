-- Mutación Rainbow: va cambiando el color de las piezas que el servidor marca con la
-- etiqueta "RainbowPart". Se hace en el cliente porque es puro adorno: así no gasta red.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local RAINBOW_TAG = "RainbowPart"
local CYCLE_SECONDS = 3 -- lo que tarda en dar la vuelta completa de colores
local UPDATE_INTERVAL = 0.05

local RainbowController = {}

local started = false

function RainbowController.start()
	if started then
		return
	end
	started = true

	local elapsed = 0
	RunService.Heartbeat:Connect(function(deltaTime)
		elapsed += deltaTime
		if elapsed < UPDATE_INTERVAL then
			return
		end
		elapsed = 0

		local color = Color3.fromHSV((os.clock() / CYCLE_SECONDS) % 1, 0.85, 1)
		for _, part in CollectionService:GetTagged(RAINBOW_TAG) do
			if part:IsA("BasePart") then
				part.Color = color
			end
		end
	end)
end

return RainbowController
