-- Rarezas de los personajes.
-- weight: probabilidad relativa de aparecer en la banda (no hace falta que sumen 100).
-- freezeTime: segundos que tarda el congelador en convertir la fruta en helado.

local WeightedRandom = require(script.Parent.Parent.Util.WeightedRandom)

export type Rarity = {
	id: string,
	name: string,
	weight: number,
	color: Color3,
	freezeTime: number,
	order: number,
}

local Rarities = {}

Rarities.List = {
	{
		id = "Comun",
		name = "Común",
		weight = 55,
		color = Color3.fromRGB(200, 200, 200),
		freezeTime = 30,
		order = 1,
	},
	{
		id = "Raro",
		name = "Raro",
		weight = 25,
		color = Color3.fromRGB(80, 160, 255),
		freezeTime = 60,
		order = 2,
	},
	{
		id = "Epico",
		name = "Épico",
		weight = 12,
		color = Color3.fromRGB(170, 85, 255),
		freezeTime = 120,
		order = 3,
	},
	{
		id = "Legendario",
		name = "Legendario",
		weight = 5.5,
		color = Color3.fromRGB(255, 190, 40),
		freezeTime = 180,
		order = 4,
	},
	{
		id = "Mitico",
		name = "Mítico",
		weight = 2,
		color = Color3.fromRGB(255, 70, 90),
		freezeTime = 300,
		order = 5,
	},
	{
		id = "Secreto",
		name = "Secreto",
		weight = 0.5,
		color = Color3.fromRGB(20, 20, 20),
		freezeTime = 600,
		order = 6,
	},
} :: { Rarity }

-- Acceso rápido por id: Rarities.ById.Epico
Rarities.ById = {} :: { [string]: Rarity }
for _, rarity in Rarities.List do
	Rarities.ById[rarity.id] = rarity
end

-- Elige una rareza al azar según los pesos
function Rarities.pickRandom(rng: Random?): Rarity
	return WeightedRandom.pick(Rarities.List, function(rarity)
		return rarity.weight
	end, rng) :: Rarity
end

return Rarities
