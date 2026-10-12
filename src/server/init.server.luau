-- Arranque del servidor: construye el mapa y enciende cada sistema en orden.

local Services = script:WaitForChild("Services")
local World = script:WaitForChild("World")

local MapBuilder = require(World.MapBuilder)
local CharacterBuilder = require(World.CharacterBuilder)
local DataService = require(Services.DataService)
local BaseService = require(Services.BaseService)
local SpawnerService = require(Services.SpawnerService)
local CoconutService = require(Services.CoconutService)
local PlacementService = require(Services.PlacementService)
local PurchaseService = require(Services.PurchaseService)
local DeliveryService = require(Services.DeliveryService)
local CombatService = require(Services.CombatService)
local FreezerService = require(Services.FreezerService)
local StealService = require(Services.StealService)
local TradeService = require(Services.TradeService)
local ShopService = require(Services.ShopService)
local InventoryService = require(Services.InventoryService)
local EventService = require(Services.EventService)
local StormService = require(Services.StormService)
local PassService = require(Services.PassService)
local BoostService = require(Services.BoostService)
local ProductService = require(Services.ProductService)

local map = MapBuilder.build()

DataService.start()
PassService.start()
BaseService.start(map)

-- Los personajes no deben chocar con ningún jugador, tampoco con los dueños de base
local ownerGroups = {}
for _, base in BaseService.getBases() do
	table.insert(ownerGroups, base.ownerGroup)
end
CharacterBuilder.init(ownerGroups)

-- Antes que PlacementService: así ya están escuchando cuando se cargan las bases
-- y cada fruta recibe sus botones (congelar, robar, vender) en cuanto aparece
FreezerService.start()
StealService.start()
ShopService.start()
PlacementService.start()
DeliveryService.start()
CombatService.start()
TradeService.start()
InventoryService.start()

-- Antes que la banda, para que el primer personaje ya tenga su botón de compra
-- y el aviso de Secreto no se pierda ninguno
PurchaseService.start()
EventService.start()
StormService.start(map)
BoostService.start()
ProductService.start()
SpawnerService.start(map)

CoconutService.start(map)
