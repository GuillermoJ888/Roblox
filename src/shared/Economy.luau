-- Cálculos de dinero que usan tanto el servidor (para cobrar y pagar) como el cliente
-- (para mostrar los precios). Tenerlos en un solo sitio evita que no coincidan.

local CharacterConfig = require(script.Parent.Config.CharacterConfig)
local GameConfig = require(script.Parent.Config.GameConfig)
local Mutations = require(script.Parent.Config.Mutations)
local Rarities = require(script.Parent.Config.Rarities)

local Economy = {}

-- Precio de un personaje con su mutación (lo que cuesta en la banda)
function Economy.price(characterId: string, mutationId: string?): number
	local character = CharacterConfig.ById[characterId]
	return math.floor(character.price * Mutations.getMultiplier(mutationId))
end

-- Lo que paga Cocardo. kind: "fruits" o "iceCreams".
function Economy.sellPrice(kind: string, characterId: string, mutationId: string?): number
	local price = Economy.price(characterId, mutationId)
	if kind == "iceCreams" then
		return math.floor(price * GameConfig.IceCreamSellMultiplier)
	end
	return math.floor(price * GameConfig.FruitSellFraction)
end

-- Lo que se cobra al vender desde la propia base, sin ir hasta Cocardo
function Economy.quickSellPrice(kind: string, characterId: string, mutationId: string?): number
	return math.floor(Economy.sellPrice(kind, characterId, mutationId) * GameConfig.QuickSellFraction)
end

-- Dinero por segundo sin contar rebirths. kind: "fruits" o "iceCreams".
function Economy.income(kind: string, characterId: string, mutationId: string?): number
	local character = CharacterConfig.ById[characterId]
	local income = character.incomePerSecond * Mutations.getMultiplier(mutationId)
	if kind == "iceCreams" then
		income *= GameConfig.IceCreamIncomeMultiplier
	end
	return income
end

-- Puntos que da algo al echarlo a la máquina de tormentas. kind: "fruits" o "iceCreams".
function Economy.stormPoints(kind: string, characterId: string): number
	local character = CharacterConfig.ById[characterId]
	local points = Rarities.ById[character.rarity].stormPoints
	if kind == "iceCreams" then
		points *= GameConfig.StormIceCreamMultiplier
	end
	return points
end

-- Multiplicador de ingresos que dan los rebirths
function Economy.rebirthMultiplier(rebirths: number): number
	return 1 + rebirths * GameConfig.RebirthIncomeBonus
end

-- Dinero necesario para el siguiente rebirth
function Economy.rebirthCost(rebirths: number): number
	return math.floor(GameConfig.RebirthBaseCost * GameConfig.RebirthCostGrowth ^ rebirths)
end

-- El bono diario crece con los rebirths, para que siga valiendo la pena
function Economy.dailyBonus(rebirths: number): number
	return math.floor(GameConfig.DailyBonus * Economy.rebirthMultiplier(rebirths))
end

return Economy
