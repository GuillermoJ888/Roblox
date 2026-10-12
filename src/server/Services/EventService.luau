-- Avisos para todo el servidor que dependen de lo que sale por la banda.
-- Por ahora: el aviso cuando aparece un personaje Secreto.
-- (La tormenta de mutaciones tiene su propio sistema: StormService.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rarities = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config").Rarities)

local Notifier = require(script.Parent.Notifier)
local SpawnerService = require(script.Parent.SpawnerService)

local SECRET_RARITY_ID = "Secreto"
local SECRET_COLOR = Color3.fromRGB(255, 80, 200)

local EventService = {}

local started = false

function EventService.start()
	if started then
		return
	end
	started = true

	assert(Rarities.ById[SECRET_RARITY_ID], "Falta la rareza Secreto en Rarities")
	SpawnerService.ItemSpawned:Connect(function(uid)
		local item = SpawnerService.getItem(uid)
		if item and item.character.rarity == SECRET_RARITY_ID then
			Notifier.announce(`¡Apareció un SECRETO en la banda: {item.character.name}!`, SECRET_COLOR, "Secret")
		end
	end)
end

return EventService
