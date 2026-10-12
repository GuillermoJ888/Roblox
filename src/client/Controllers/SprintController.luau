-- Correr con Shift gastando energía. En teléfono y tablet aparece un botón "Correr"
-- en pantalla, y en mando se usa pulsar el stick izquierdo.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config").GameConfig)
local HudController = require(script.Parent.HudController)

local ACTION_NAME = "Sprint"

local SprintController = {}

local player = Players.LocalPlayer
local started = false

local sprintHeld = false
local stamina = GameConfig.StaminaMax
local exhausted = false -- se quedó sin energía y debe recuperar un mínimo antes de volver a correr
local lastSprintTime = 0

local function onSprintAction(_actionName: string, inputState: Enum.UserInputState)
	sprintHeld = inputState == Enum.UserInputState.Begin
	-- Pass: no bloquea otros usos de la misma tecla
	return Enum.ContextActionResult.Pass
end

local function update(deltaTime: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	-- Quien carga algo robado va más lento y no puede correr (lo marca el servidor)
	local carrying = player:GetAttribute("Carrying") == true
	local moving = humanoid.MoveDirection.Magnitude > 0.1
	local sprinting = sprintHeld and moving and not carrying and not exhausted and stamina > 0

	if sprinting then
		stamina = math.max(stamina - GameConfig.StaminaDrain * deltaTime, 0)
		lastSprintTime = os.clock()
		if stamina <= 0 then
			exhausted = true
		end
	elseif os.clock() - lastSprintTime >= GameConfig.StaminaRegenDelay then
		stamina = math.min(stamina + GameConfig.StaminaRegen * deltaTime, GameConfig.StaminaMax)
		if exhausted and stamina >= GameConfig.StaminaMinToSprint then
			exhausted = false
		end
	end

	local targetSpeed = GameConfig.WalkSpeed
	if carrying then
		targetSpeed = GameConfig.CarryWalkSpeed
	elseif sprinting then
		targetSpeed = GameConfig.SprintSpeed
	end
	-- Velocidad 0 significa que otro sistema lo inmovilizó: no se toca
	if humanoid.WalkSpeed ~= 0 and humanoid.WalkSpeed ~= targetSpeed then
		humanoid.WalkSpeed = targetSpeed
	end

	HudController.setStamina(stamina / GameConfig.StaminaMax, exhausted)
end

function SprintController.start()
	if started then
		return
	end
	started = true

	-- El tercer argumento (true) crea el botón táctil en teléfonos y tablets
	ContextActionService:BindAction(
		ACTION_NAME,
		onSprintAction,
		true,
		Enum.KeyCode.LeftShift,
		Enum.KeyCode.RightShift,
		Enum.KeyCode.ButtonL3
	)
	ContextActionService:SetTitle(ACTION_NAME, "Correr")

	RunService.Heartbeat:Connect(update)
end

return SprintController
