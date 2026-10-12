-- Doble salto con giro en el aire. Funciona igual en PC, teléfono y mando,
-- porque escucha la petición de salto de Roblox y no una tecla concreta.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config").GameConfig)

-- Tiempo mínimo entre el primer salto y el segundo
local MIN_DELAY = 0.2
-- Mientras el botón sigue pulsado, Roblox repite la petición de salto en cada fotograma.
-- Un hueco mayor que este entre dos peticiones significa que se soltó y se volvió a pulsar.
local NEW_PRESS_GAP = 0.1

local JumpController = {}

local player = Players.LocalPlayer
local started = false

local usedDoubleJump = false
local lastJumpTime = 0
local lastRequestTime = 0
local spinning = false

-- Giro completo sobre sí mismo. Como el jugador controla la física de su personaje,
-- los demás jugadores también lo ven.
local function spin(humanoid: Humanoid, root: BasePart)
	if spinning then
		return
	end
	spinning = true
	humanoid.AutoRotate = false

	local duration = GameConfig.DoubleJumpSpinTime
	local turned = 0
	local fullTurn = math.pi * 2
	while turned < fullTurn and humanoid.Parent and humanoid.Health > 0 do
		local deltaTime = RunService.Heartbeat:Wait()
		local angle = math.min(fullTurn * deltaTime / duration, fullTurn - turned)
		turned += angle
		root.CFrame *= CFrame.Angles(0, angle, 0)
	end

	if humanoid.Parent then
		humanoid.AutoRotate = true
	end
	spinning = false
end

local function onJumpRequest()
	-- Mantener pulsado el botón no debe gastar el segundo salto
	local now = os.clock()
	local isNewPress = now - lastRequestTime > NEW_PRESS_GAP
	lastRequestTime = now
	if not isNewPress then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return
	end
	-- Quien carga algo robado no puede hacer el doble salto
	if usedDoubleJump or player:GetAttribute("Carrying") == true then
		return
	end

	local state = humanoid:GetState()
	local inAir = state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping
	if not inAir or now - lastJumpTime < MIN_DELAY then
		return
	end

	usedDoubleJump = true
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	task.spawn(spin, humanoid, root)
end

local function onCharacterAdded(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	usedDoubleJump = false
	spinning = false

	humanoid.StateChanged:Connect(function(_, newState)
		if newState == Enum.HumanoidStateType.Jumping then
			lastJumpTime = os.clock()
		elseif
			newState == Enum.HumanoidStateType.Landed
			or newState == Enum.HumanoidStateType.Running
			or newState == Enum.HumanoidStateType.Swimming
			or newState == Enum.HumanoidStateType.Climbing
			or newState == Enum.HumanoidStateType.Seated
		then
			usedDoubleJump = false
		end
	end)
end

function JumpController.start()
	if started then
		return
	end
	started = true

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end
	UserInputService.JumpRequest:Connect(onJumpRequest)
end

return JumpController
