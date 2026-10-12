-- Arranque del cliente: enciende la interfaz y los controles del jugador.

local Controllers = script:WaitForChild("Controllers")

local HudController = require(Controllers.HudController)
local SoundController = require(Controllers.SoundController)
local SprintController = require(Controllers.SprintController)
local JumpController = require(Controllers.JumpController)
local PromptController = require(Controllers.PromptController)
local RainbowController = require(Controllers.RainbowController)
local InventoryController = require(Controllers.InventoryController)
local ShopController = require(Controllers.ShopController)
local TradeController = require(Controllers.TradeController)
local StormController = require(Controllers.StormController)
local PassController = require(Controllers.PassController)

-- La interfaz base va primero: los demás menús se cuelgan de ella
HudController.start()
SoundController.start()
SprintController.start()
JumpController.start()
PromptController.start()
RainbowController.start()
InventoryController.start()
ShopController.start()
TradeController.start()
StormController.start()
PassController.start()
