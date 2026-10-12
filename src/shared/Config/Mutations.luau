-- Mutaciones: cambian el aspecto del personaje y multiplican su ingreso.
-- Un personaje solo puede tener UNA mutación (o ninguna).
-- weight: probabilidad relativa entre mutaciones, una vez decidido que sale mutado.
-- effect: nombre del efecto visual que aplicará el sistema de efectos (placeholder).

local WeightedRandom = require(script.Parent.Parent.Util.WeightedRandom)

export type Mutation = {
	id: string,
	name: string,
	multiplier: number,
	weight: number,
	color: Color3,
	material: Enum.Material,
	effect: string,
}

local Mutations = {}

-- Probabilidad de que un personaje salga con mutación (0 a 1)
Mutations.BaseChance = 0.15
-- Probabilidad durante el evento "Lluvia de mutaciones"
Mutations.EventChance = 0.5

Mutations.List = {
	{
		id = "Gold",
		name = "Gold",
		multiplier = 1.25,
		weight = 40,
		color = Color3.fromRGB(255, 200, 50),
		material = Enum.Material.Metal,
		effect = "Brillo",
	},
	{
		id = "Diamond",
		name = "Diamond",
		multiplier = 1.5,
		weight = 25,
		color = Color3.fromRGB(120, 230, 255),
		material = Enum.Material.Glass,
		effect = "Destellos",
	},
	{
		id = "Dulce",
		name = "Dulce",
		multiplier = 2,
		weight = 15,
		color = Color3.fromRGB(255, 170, 215),
		material = Enum.Material.SmoothPlastic,
		effect = "Azucar", -- partículas de azúcar
	},
	{
		id = "Escarchada",
		name = "Escarchada",
		multiplier = 3,
		weight = 10,
		color = Color3.fromRGB(200, 235, 255),
		material = Enum.Material.Ice,
		effect = "Hielo", -- efecto de hielo
	},
	{
		id = "Lava",
		name = "Lava",
		multiplier = 6,
		weight = 7,
		color = Color3.fromRGB(255, 90, 20),
		material = Enum.Material.Neon,
		effect = "Fuego",
	},
	{
		id = "Rainbow",
		name = "Rainbow",
		multiplier = 10,
		weight = 3,
		color = Color3.fromRGB(255, 255, 255),
		material = Enum.Material.Neon,
		effect = "Arcoiris", -- el color va cambiando
	},
} :: { Mutation }

-- Acceso rápido por id: Mutations.ById.Lava
Mutations.ById = {} :: { [string]: Mutation }
for _, mutation in Mutations.List do
	Mutations.ById[mutation.id] = mutation
end

-- Decide si sale mutación y cuál. Devuelve nil si el personaje sale normal.
-- eventActive: true mientras dura la "Lluvia de mutaciones"
function Mutations.roll(rng: Random?, eventActive: boolean?): Mutation?
	local generator = rng or Random.new()
	local chance = if eventActive then Mutations.EventChance else Mutations.BaseChance
	if generator:NextNumber() >= chance then
		return nil
	end
	return WeightedRandom.pick(Mutations.List, function(mutation)
		return mutation.weight
	end, generator)
end

-- Multiplicador de una mutación por id (1 si no tiene mutación)
function Mutations.getMultiplier(mutationId: string?): number
	local mutation = if mutationId then Mutations.ById[mutationId] else nil
	return if mutation then mutation.multiplier else 1
end

return Mutations
