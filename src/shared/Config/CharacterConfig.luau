-- Catálogo de personajes (frutas y verduras con cuerpo humano).
--
-- PARA AÑADIR UN PERSONAJE NUEVO: copia un bloque de la lista, cámbiale el id
-- (debe ser único y sin espacios) y ajusta sus datos. No hay que tocar nada más.
--
-- Campos:
--   id              identificador interno único (es lo que se guarda en el DataStore: no lo cambies después)
--   name            nombre que ve el jugador
--   kind            "Fruta" o "Verdura"
--   rarity          id de la rareza (ver Rarities.luau)
--   incomePerSecond dinero por segundo sin mutación
--   price           precio en la banda transportadora, sin mutación
--   flavor          sabor del helado que produce en el congelador
--   imageId         imagen placeholder para Decal/BillboardGui. REEMPLAZAR por "rbxassetid://NUMERO"
--   skinColor       color de piel del cuerpo humano (el color de la fruta)
--   fruitHead       true = la cabeza completa es la fruta; false = cabeza humana con el color de la fruta
--   headDetail      detalle de la cabeza (pelo, palito, hojas...) para cuando haya modelos 3D

local Rarities = require(script.Parent.Rarities)
local WeightedRandom = require(script.Parent.Parent.Util.WeightedRandom)

export type Character = {
	id: string,
	name: string,
	kind: "Fruta" | "Verdura",
	rarity: string,
	incomePerSecond: number,
	price: number,
	flavor: string,
	imageId: string,
	skinColor: Color3,
	fruitHead: boolean,
	headDetail: string,
}

-- Imagen que se usa mientras no haya imágenes propias
local PLACEHOLDER_IMAGE = "rbxassetid://0"

local CharacterConfig = {}

CharacterConfig.List = {
	-- ===== COMÚN =====
	{
		id = "FresitaTralala",
		name = "Fresita Tralala",
		kind = "Fruta",
		rarity = "Comun",
		incomePerSecond = 1,
		price = 50,
		flavor = "Fresa",
		imageId = PLACEHOLDER_IMAGE,
		skinColor = Color3.fromRGB(230, 50, 70),
		fruitHead = false,
		headDetail = "Pelo rojo con hojitas verdes",
	},
	{
		id = "BananicoCremoso",
		name = "Banánico Cremoso",
		kind = "Fruta",
		rarity = "Comun",
		incomePerSecond = 2,
		price = 110,
		flavor = "Plátano",
		imageId = PLACEHOLDER_IMAGE,
		skinColor = Color3.fromRGB(250, 220, 80),
		fruitHead = false,
		headDetail = "Pelo de cáscara de plátano",
	},
	{
		id = "ZanahorioGelido",
		name = "Zanahorio Gélido",
		kind = "Verdura",
		rarity = "Comun",
		incomePerSecond = 3,
		price = 180,
		flavor = "Zanahoria",
		imageId = PLACEHOLDER_IMAGE,
		skinColor = Color3.fromRGB(240, 130, 40),
		fruitHead = false,
		headDetail = "Hojas verdes de punta",
	},

	-- ===== RARO =====
	{
		id = "SandioSandini",
		name = "Sandío Sandini",
		kind = "Fruta",
		rarity = "Raro",
		incomePerSecond = 8,
		price = 650,
		flavor = "Sandía",
		imageId = PLACEHOLDER_IMAGE,
		skinColor = Color3.fromRGB(240, 80, 100),
		fruitHead = true,
		headDetail = "Cabeza de sandía con rayas verdes",
	},
	{
		id = "CerecitaBombon",
		name = "Cerecita Bombón",
		kind = "Fruta",
		rarity = "Raro",
		incomePerSecond = 10,
		price = 900,
		flavor = "Cereza",
		imageId = PLACEHOLDER_IMAGE,
		skinColor = Color3.fromRGB(170, 20, 40),
		fruitHead = false,
		headDetail = "Palito de cereza con una hoja",
	},
	{
		id = "BrocolinoMusculino",
		name = "Brocolino Musculino",
		kind = "Verdura",
		rarity = "Raro",
		incomePerSecond = 12,
		price = 1200,
		flavor = "Brócoli",
		imageId = PLACEHOLDER_IMAGE,
		skinColor = Color3.fromRGB(110, 180, 70),
		fruitHead = false,
		headDetail = "Pelo de brócoli",
	},

	-- ===== ÉPICO =====
	{
		id = "MangoliaTropicana",
		name = "Mangolia Tropicana",
		kind = "Fruta",
		rarity = "Epico",
		incomePerSecond = 40,
		price = 5000,
		flavor = "Mango",
		imageId = PLACEHOLDER_IMAGE,
		skinColor = Color3.fromRGB(255, 170, 50),
		fruitHead = false,
		headDetail = "Pelo degradado de naranja a rojo",
	},
	{
		id = "UvaldoRacimon",
		name = "Uvaldo Racimón",
		kind = "Fruta",
		rarity = "Epico",
		incomePerSecond = 55,
		price = 8000,
		flavor = "Uva",
		imageId = PLACEHOLDER_IMAGE,
		skinColor = Color3.fromRGB(130, 70, 190),
		fruitHead = false,
		headDetail = "Pelo de racimo de uvas",
	},

	-- ===== LEGENDARIO =====
	{
		id = "PinardoCoronado",
		name = "Piñardo Coronado",
		kind = "Fruta",
		rarity = "Legendario",
		incomePerSecond = 200,
		price = 40000,
		flavor = "Piña",
		imageId = PLACEHOLDER_IMAGE,
		skinColor = Color3.fromRGB(230, 180, 50),
		fruitHead = true,
		headDetail = "Cabeza de piña con corona de hojas",
	},
	{
		id = "LimonelaChispitas",
		name = "Limonela Chispitas",
		kind = "Fruta",
		rarity = "Legendario",
		incomePerSecond = 260,
		price = 60000,
		flavor = "Limón",
		imageId = PLACEHOLDER_IMAGE,
		skinColor = Color3.fromRGB(190, 230, 60),
		fruitHead = false,
		headDetail = "Pelo corto verde lima",
	},

	-- ===== MÍTICO =====
	{
		id = "DonPlatanoSupremo",
		name = "Don Plátano Supremo",
		kind = "Fruta",
		rarity = "Mitico",
		incomePerSecond = 1200,
		price = 400000,
		flavor = "Plátano dorado",
		imageId = PLACEHOLDER_IMAGE,
		skinColor = Color3.fromRGB(255, 225, 60),
		fruitHead = true,
		headDetail = "Cabeza completa de plátano",
	},

	-- ===== SECRETO =====
	{
		id = "PitahayaGalactica",
		name = "Pitahaya Galáctica",
		kind = "Fruta",
		rarity = "Secreto",
		incomePerSecond = 10000,
		price = 5000000,
		flavor = "Pitahaya estelar",
		imageId = PLACEHOLDER_IMAGE,
		skinColor = Color3.fromRGB(235, 50, 150),
		fruitHead = false,
		headDetail = "Pelo rosa con puntas verdes y brillos",
	},
} :: { Character }

-- Acceso rápido por id y agrupado por rareza
CharacterConfig.ById = {} :: { [string]: Character }
CharacterConfig.ByRarity = {} :: { [string]: { Character } }

for _, character in CharacterConfig.List do
	assert(Rarities.ById[character.rarity], `Rareza desconocida "{character.rarity}" en {character.id}`)
	assert(not CharacterConfig.ById[character.id], `Id de personaje repetido: {character.id}`)

	CharacterConfig.ById[character.id] = character

	local group = CharacterConfig.ByRarity[character.rarity]
	if not group then
		group = {}
		CharacterConfig.ByRarity[character.rarity] = group
	end
	table.insert(group, character)
end

function CharacterConfig.get(id: string): Character?
	return CharacterConfig.ById[id]
end

-- Elige un personaje al azar: primero la rareza (según su peso) y luego uno de esa rareza.
-- Solo se sortean rarezas que tengan al menos un personaje.
function CharacterConfig.pickRandom(rng: Random?): Character
	local generator = rng or Random.new()

	local available = {}
	for _, rarity in Rarities.List do
		if CharacterConfig.ByRarity[rarity.id] then
			table.insert(available, rarity)
		end
	end

	local rarity = WeightedRandom.pick(available, function(item)
		return item.weight
	end, generator) :: Rarities.Rarity

	local group = CharacterConfig.ByRarity[rarity.id]
	return group[generator:NextInteger(1, #group)]
end

return CharacterConfig
