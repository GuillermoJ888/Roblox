-- Rarezas de los personajes.
-- weight: probabilidad relativa de aparecer en la banda (no hace falta que sumen 100).
--   Ahora suman 100, así que cada peso es directamente su porcentaje.
--   Con un personaje cada 4 segundos salen unos 900 por hora: un Mítico cada 20 minutos
--   y un Secreto cada 2 horas, más o menos. Subir un peso hace esa rareza más común.
-- freezeTime: segundos que tarda el congelador en convertir la fruta en helado.
-- stormPoints: puntos que da una fruta de esta rareza al echarla a la máquina de tormentas.

local WeightedRandom = require(script.Parent.Parent.Util.WeightedRandom)

export type Rarity = {
	id: string,
	name: string,
	weight: number,
	color: Color3,
	freezeTime: number,
	stormPoints: number,
	order: number,
}

local Rarities = {}

Rarities.List = {
	{
		id = "Comun",
		name = "Común",
		weight = 70,
		color = Color3.fromRGB(200, 200, 200),
		freezeTime = 60,
		stormPoints = 1,
		order = 1,
	},
	{
		id = "Raro",
		name = "Raro",
		weight = 22,
		color = Color3.fromRGB(80, 160, 255),
		freezeTime = 120,
		stormPoints = 3,
		order = 2,
	},
	{
		id = "Epico",
		name = "Épico",
		weight = 6,
		color = Color3.fromRGB(170, 85, 255),
		freezeTime = 240,
		stormPoints = 10,
		order = 3,
	},
	{
		id = "Legendario",
		name = "Legendario",
		weight = 1.6,
		color = Color3.fromRGB(255, 190, 40),
		freezeTime = 420,
		stormPoints = 30,
		order = 4,
	},
	{
		id = "Mitico",
		name = "Mítico",
		weight = 0.35,
		color = Color3.fromRGB(255, 70, 90),
		freezeTime = 600,
		stormPoints = 100,
		order = 5,
	},
	{
		id = "Secreto",
		name = "Secreto",
		weight = 0.05,
		color = Color3.fromRGB(20, 20, 20),
		freezeTime = 900,
		stormPoints = 300,
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
