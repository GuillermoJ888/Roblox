-- Pases de juego: mejoras permanentes que se compran una sola vez con Robux.
--
-- CÓMO ACTIVAR UN PASE (hace falta tener el juego publicado):
--   1. En create.roblox.com abre tu juego -> Monetización -> Pases -> Crear un pase.
--   2. Ponle nombre, imagen y precio en Robux, y actívalo para la venta.
--   3. Copia el número de ID del pase y pégalo aquí en gamePassId.
--
-- Mientras gamePassId sea 0, el pase no se puede comprar en el juego publicado
-- (sale "Próximamente"). En Roblox Studio se concede gratis para poder probarlo.
--
-- Campos:
--   id               identificador interno (no lo cambies después)
--   gamePassId       número del pase en Roblox (0 = todavía no creado)
--   extraFruitSlots  casillas de fruta extra que da en la base
--   requires         id de otro pase que hay que tener antes (opcional)
--   attribute/value  mejora de movimiento: es la versión potente de una mejora que también
--                    se vende por dinero del juego en ToolConfig (cuenta el valor mayor)

export type Pass = {
	id: string,
	name: string,
	description: string,
	gamePassId: number,
	extraFruitSlots: number?,
	requires: string?,
	attribute: string?,
	value: number?,
}

local PassConfig = {}

PassConfig.List = {
	{
		id = "Slots1",
		name = "Base ampliada",
		description = "+4 casillas para frutas en tu base (12 en total).",
		gamePassId = 0,
		extraFruitSlots = 4,
	},
	{
		id = "Slots2",
		name = "Base gigante",
		description = "Otras +4 casillas para frutas (16 en total).",
		gamePassId = 0,
		extraFruitSlots = 4,
		requires = "Slots1",
	},
	{
		id = "SuperResorte",
		name = "Súper resorte",
		description = "Saltas más del doble de alto. La versión básica (Resorte) la vende Cocardo.",
		gamePassId = 0,
		attribute = "JumpMultiplier",
		value = 2.2,
	},
	{
		id = "SuperBotas",
		name = "Súper botas",
		description = "+10 de velocidad. La versión básica (Botas Veloces, +4) la vende Cocardo.",
		gamePassId = 0,
		attribute = "SpeedBonus",
		value = 10,
	},
} :: { Pass }

PassConfig.ById = {} :: { [string]: Pass }
for _, pass in PassConfig.List do
	assert(not PassConfig.ById[pass.id], `Id de pase repetido: {pass.id}`)
	PassConfig.ById[pass.id] = pass
end

-- Nombre del atributo que el servidor pone en el jugador cuando tiene el pase
function PassConfig.attributeName(passId: string): string
	return `Pass_{passId}`
end

return PassConfig
