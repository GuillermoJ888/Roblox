-- Armas y mejoras de la tienda de Cocardo.
--
-- PARA AÑADIR UNA NUEVA: copia un bloque, cámbiale el id (único y sin espacios) y sus datos.
--
-- kind = "Weapon": un arma que aparece en el inventario.
--   damage, cooldown (segundos entre golpes), range (alcance en studs) y los colores de la hoja.
-- kind = "Upgrade": una mejora permanente que no ocupa sitio.
--   attribute y value: el servidor pone ese atributo en el jugador y el juego lo lee.
--   Si el jugador tiene además un pase de Robux con el mismo atributo, cuenta el valor mayor.

local GameConfig = require(script.Parent.GameConfig)

export type Tool = {
	id: string,
	name: string,
	kind: "Weapon" | "Upgrade",
	price: number,
	description: string,
	-- Solo armas
	damage: number?,
	cooldown: number?,
	range: number?,
	bladeColor: Color3?,
	bladeMaterial: Enum.Material?,
	-- Solo mejoras
	attribute: string?,
	value: number?,
}

local ToolConfig = {}

-- Arma que todos reciben gratis al aparecer
ToolConfig.DefaultWeaponId = "Espada"

ToolConfig.List = {
	{
		id = "Espada",
		name = "Espada",
		kind = "Weapon",
		price = 0,
		description = `{GameConfig.SwordDamage} de daño. La tienes desde el principio.`,
		damage = GameConfig.SwordDamage,
		cooldown = GameConfig.SwordCooldown,
		range = GameConfig.SwordRange,
		bladeColor = Color3.fromRGB(210, 215, 225),
		bladeMaterial = Enum.Material.Metal,
	},
	{
		id = "EspadaHielo",
		name = "Espada de Hielo",
		kind = "Weapon",
		price = 5000,
		description = "35 de daño. Afilada como un carámbano.",
		damage = 35,
		cooldown = 0.6,
		range = 7.5,
		bladeColor = Color3.fromRGB(170, 225, 255),
		bladeMaterial = Enum.Material.Ice,
	},
	{
		id = "MartilloCoco",
		name = "Martillo de Coco",
		kind = "Weapon",
		price = 50000,
		description = "60 de daño, pero golpea más lento.",
		damage = 60,
		cooldown = 1,
		range = 8,
		bladeColor = Color3.fromRGB(120, 75, 45),
		bladeMaterial = Enum.Material.Wood,
	},
	{
		id = "BotasVeloces",
		name = "Botas Veloces",
		kind = "Upgrade",
		price = 15000,
		description = "+4 de velocidad al caminar y al correr. (Las Súper botas de Mejoras dan +10.)",
		attribute = "SpeedBonus",
		value = 4,
	},
	{
		id = "Resorte",
		name = "Resorte",
		kind = "Upgrade",
		price = 20000,
		description = "Saltas un 30 % más alto. (El Súper resorte de Mejoras salta mucho más.)",
		attribute = "JumpMultiplier",
		value = 1.3,
	},
	{
		id = "BatidoEnergetico",
		name = "Batido Energético",
		kind = "Upgrade",
		price = 25000,
		description = "La energía para correr se recupera el doble de rápido.",
		attribute = "StaminaRegenMultiplier",
		value = 2,
	},
} :: { Tool }

ToolConfig.ById = {} :: { [string]: Tool }
for _, tool in ToolConfig.List do
	assert(not ToolConfig.ById[tool.id], `Id de herramienta repetido: {tool.id}`)
	ToolConfig.ById[tool.id] = tool
end

return ToolConfig
