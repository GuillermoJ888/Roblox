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

local map = MapBuilder.build()

DataService.start()
BaseService.start(map)

-- Los personajes no deben chocar con ningún jugador, tampoco con los dueños de base
local ownerGroups = {}
for _, base in BaseService.getBases() do
	table.insert(ownerGroups, base.ownerGroup)
end
CharacterBuilder.init(ownerGroups)

PlacementService.start()
DeliveryService.start()
CombatService.start()
-- Antes que la banda, para que el primer personaje ya tenga su botón de compra
PurchaseService.start()
SpawnerService.start(map)
CoconutService.start(map)
