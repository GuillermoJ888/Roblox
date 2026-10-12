-- Ventajas con tiempo limitado que se compran con Robux:
--   - Guardia de seguridad: la puerta de la base queda cerrada para los demás.
--   - Súper congelador: lo que se meta al congelador tarda menos.
--
-- De cada una se guardan los SEGUNDOS QUE QUEDAN, dentro de los datos del jugador.
-- El tiempo solo se gasta mientras el jugador está conectado: al salir se pausa y al
-- volver sigue donde lo dejó. (Mientras está fuera su base no existe, así que no hace falta.)
--
--   BoostService.addGuard(player, segundos)         -> suma tiempo de guardia
--   BoostService.addSuperFreezer(player, segundos)  -> suma tiempo de súper congelador
--   BoostService.getFreezeSpeed(player)             -> 2 si tiene el súper congelador activo, 1 si no

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Format = require(Shared.Util.Format)

local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)
local Notifier = require(script.Parent.Notifier)

local GUARD_NAME = "Guardia"

local BoostService = {}

local started = false
local guardTemplate: Model? = nil
local guardByBase: { [number]: Model } = {}

-- Publica en el jugador la hora a la que caduca cada ventaja (para la cuenta atrás de su
-- pantalla) y aplica la guardia a su base. Se llama al entrar y cada vez que compra tiempo.
local function apply(player: Player)
	local data = DataService.getData(player)
	if not data then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local guardLeft = data.boosts.guardSeconds
	local freezerLeft = data.boosts.superFreezerSeconds
	player:SetAttribute("GuardUntil", if guardLeft > 0 then now + guardLeft else nil)
	player:SetAttribute("SuperFreezerUntil", if freezerLeft > 0 then now + freezerLeft else nil)

	if BaseService.getBase(player) then
		BaseService.setGuard(player, guardLeft)
	end
end

function BoostService.addGuard(player: Player, seconds: number): boolean
	local data = DataService.getData(player)
	if not data then
		return false
	end
	-- Comprar otra vez mientras sigue activa suma tiempo
	data.boosts.guardSeconds += seconds
	apply(player)
	Notifier.send(
		player,
		`¡Guardia contratado! Te quedan {Format.time(data.boosts.guardSeconds)} de vigilancia.`,
		"success",
		"Purchase"
	)
	return true
end

function BoostService.addSuperFreezer(player: Player, seconds: number): boolean
	local data = DataService.getData(player)
	if not data then
		return false
	end
	data.boosts.superFreezerSeconds += seconds
	apply(player)
	Notifier.send(
		player,
		`¡Súper congelador! Te quedan {Format.time(data.boosts.superFreezerSeconds)}. Lo que metas ahora tarda la mitad.`,
		"success",
		"Purchase"
	)
	return true
end

-- Velocidad a la que congela este jugador (1 = normal)
function BoostService.getFreezeSpeed(player: Player): number
	local data = DataService.getData(player)
	if data and data.boosts.superFreezerSeconds > 0 then
		return GameConfig.SuperFreezerSpeed
	end
	return 1
end

-- ===== El guardia que se ve junto a la puerta =====

-- PLACEHOLDER: avatar básico con uniforme azul. Para usar un modelo propio, cambia esta función
-- (el modelo necesita PrimaryPart y el atributo FootOffset con la altura de su centro).
local function buildGuardTemplate(): Model?
	local description = Instance.new("HumanoidDescription")
	local uniform = Color3.fromRGB(30, 45, 95)
	description.HeadColor = Color3.fromRGB(224, 172, 105)
	description.LeftArmColor = uniform
	description.RightArmColor = uniform
	description.TorsoColor = uniform
	description.LeftLegColor = Color3.fromRGB(25, 25, 40)
	description.RightLegColor = Color3.fromRGB(25, 25, 40)
	description.HeightScale = 1.1
	description.WidthScale = 1.15

	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not result then
		warn(`[BoostService] No se pudo crear el avatar del guardia: {result}`)
		return nil
	end

	local rig = result :: Model
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	local root = rig:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		rig:Destroy()
		return nil
	end
	humanoid.DisplayName = GUARD_NAME
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	root.Anchored = true
	rig.Name = GUARD_NAME
	rig.PrimaryPart = root
	rig:SetAttribute("FootOffset", humanoid.HipHeight + root.Size.Y / 2)
	return rig
end

-- Muestra u oculta el guardia de cada base según tenga la vigilancia activa
local function refreshGuards()
	for _, base in BaseService.getBases() do
		local active = BaseService.isGuarded(base)
		local guard = guardByBase[base.index]

		if active and not guard and guardTemplate then
			guard = guardTemplate:Clone()
			-- De pie fuera, a un lado de la puerta y mirando hacia la calle
			local door = base.info.door
			local feet = door.CFrame * CFrame.new(door.Size.X / 2 + 2.5, -door.Position.Y, -3)
			local footOffset = guard:GetAttribute("FootOffset") or 0
			guard:PivotTo(feet * CFrame.new(0, footOffset, 0))
			guard.Parent = base.info.model
			guardByBase[base.index] = guard
		elseif not active and guard then
			guard:Destroy()
			guardByBase[base.index] = nil
		end
	end
end

-- Gasta un segundo de cada ventaja activa de los jugadores conectados
local function spendSecond()
	for _, player in Players:GetPlayers() do
		local data = DataService.getData(player)
		if data then
			local boosts = data.boosts
			if boosts.guardSeconds > 0 then
				boosts.guardSeconds = math.max(boosts.guardSeconds - 1, 0)
				if boosts.guardSeconds == 0 then
					player:SetAttribute("GuardUntil", nil)
					BaseService.setGuard(player, 0)
					Notifier.send(player, "Tu guardia de seguridad terminó su turno.", "info")
				end
			end
			if boosts.superFreezerSeconds > 0 then
				boosts.superFreezerSeconds = math.max(boosts.superFreezerSeconds - 1, 0)
				if boosts.superFreezerSeconds == 0 then
					player:SetAttribute("SuperFreezerUntil", nil)
					Notifier.send(player, "Se acabó el súper congelador.", "info")
				end
			end
		end
	end
end

function BoostService.start()
	if started then
		return
	end
	started = true

	DataService.PlayerLoaded:Connect(apply)
	BaseService.BaseAssigned:Connect(function(player)
		apply(player)
	end)
	for _, player in Players:GetPlayers() do
		apply(player)
	end

	task.spawn(function()
		guardTemplate = buildGuardTemplate()
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			spendSecond()
			refreshGuards()
		end
	end)
end

return BoostService
