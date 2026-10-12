-- Textos para mostrar frutas y helados en los menús.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CharacterConfig = require(Shared.Config.CharacterConfig)
local Mutations = require(Shared.Config.Mutations)
local Rarities = require(Shared.Config.Rarities)

local ItemText = {}

-- kind: "fruits", "iceCreams" o "freezer"
function ItemText.name(kind: string, characterId: string): string
	local character = CharacterConfig.ById[characterId]
	if not character then
		return "?"
	end
	if kind == "iceCreams" then
		return `Helado de {character.flavor}`
	end
	return character.name
end

-- "Raro" o "Raro · Gold"
function ItemText.detail(characterId: string, mutationId: string?): string
	local character = CharacterConfig.ById[characterId]
	if not character then
		return ""
	end
	local text = Rarities.ById[character.rarity].name
	local mutation = if mutationId then Mutations.ById[mutationId] else nil
	if mutation then
		text ..= ` · {mutation.name}`
	end
	return text
end

function ItemText.color(characterId: string): Color3
	local character = CharacterConfig.ById[characterId]
	if not character then
		return Color3.new(1, 1, 1)
	end
	local color = Rarities.ById[character.rarity].color
	-- El color de Secreto es casi negro: sobre fondo oscuro no se leería
	local brightness = color.R * 0.3 + color.G * 0.6 + color.B * 0.1
	return if brightness < 0.25 then Color3.fromRGB(255, 80, 200) else color
end

return ItemText
