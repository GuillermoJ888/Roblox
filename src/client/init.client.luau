-- Arranque del cliente: enciende la interfaz y los controles del jugador.

local Controllers = script:WaitForChild("Controllers")

local HudController = require(Controllers.HudController)
local SprintController = require(Controllers.SprintController)
local JumpController = require(Controllers.JumpController)

HudController.start()
SprintController.start()
JumpController.start()
