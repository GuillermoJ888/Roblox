-- Bases de los jugadores: asigna una al entrar, la libera al salir y controla
-- el bloqueo temporal de la puerta.
--
--   BaseService.getBase(player)    -> base del jugador (o nil)
--   BaseService.isLocked(base)     -> true mientras la puerta está bloqueada
--   BaseService.BaseAssigned / BaseService.BaseReleased -> avisos para otros sistemas

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config").GameConfig)
local MapBuilder = require(script.Parent.Parent.World.MapBuilder)

export type Base = {
	info: MapBuilder.BaseInfo,
	index: number,
	owner: Player?,
	lockedUntil: number, -- os.clock() hasta el que la puerta sigue bloqueada
	cooldownUntil: number, -- os.clock() a partir del cual se puede volver a bloquear
	guardUntil: number, -- os.clock() hasta el que un guardia mantiene la puerta cerrada
	doorGroup: string,
	ownerGroup: string,
}

local DOOR_OPEN_COLOR = Color3.fromRGB(90, 220, 120)
local DOOR_LOCKED_COLOR = Color3.fromRGB(255, 60, 60)
local STATUS_OPEN_COLOR = Color3.fromRGB(120, 255, 150)
local STATUS_LOCKED_COLOR = Color3.fromRGB(255, 110, 110)

local BaseService = {}

local bases: { Base } = {}
local baseByPlayer: { [Player]: Base } = {}
local characterConnections: { [Player]: { RBXScriptConnection } } = {}
local started = false

local assignedEvent = Instance.new("BindableEvent")
local releasedEvent = Instance.new("BindableEvent")
-- Los BindableEvent copian las tablas que se les pasan, así que solo se envían el jugador y el
-- número de base: quien escucha debe pedir la base con getBase o getBaseByIndex.
BaseService.BaseAssigned = assignedEvent.Event -- (player, baseIndex)
BaseService.BaseReleased = releasedEvent.Event -- (player, baseIndex)

-- ===== Colisiones: la puerta bloqueada frena a todos menos al dueño =====

local function registerGroup(name: string)
	if not PhysicsService:IsCollisionGroupRegistered(name) then
		PhysicsService:RegisterCollisionGroup(name)
	end
end

local function setCharacterGroup(character: Model, group: string)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = group
		end
	end
end

local function disconnectCharacter(player: Player)
	local connections = characterConnections[player]
	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
		characterConnections[player] = nil
	end
end

-- Mantiene al personaje del dueño en el grupo que atraviesa su propia puerta
local function trackCharacter(player: Player, base: Base)
	disconnectCharacter(player)
	local connections = {}
	characterConnections[player] = connections

	local function onCharacter(character: Model)
		setCharacterGroup(character, base.ownerGroup)
		table.insert(connections, character.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("BasePart") then
				descendant.CollisionGroup = base.ownerGroup
			end
		end))
	end

	table.insert(connections, player.CharacterAdded:Connect(onCharacter))
	if player.Character then
		onCharacter(player.Character)
	end
end

-- ===== Puerta =====

-- true mientras un guardia de seguridad vigila la puerta
function BaseService.isGuarded(base: Base): boolean
	return os.clock() < base.guardUntil
end

-- true si los demás no pueden entrar: por el bloqueo de la placa roja o por el guardia
function BaseService.isLocked(base: Base): boolean
	local now = os.clock()
	return now < base.lockedUntil or now < base.guardUntil
end

local function formatTime(seconds: number): string
	local total = math.max(math.ceil(seconds), 0)
	return string.format("%d:%02d", math.floor(total / 60), total % 60)
end

local function refreshBase(base: Base)
	local info = base.info
	local now = os.clock()
	local guarded = now < base.guardUntil
	local locked = guarded or now < base.lockedUntil

	info.door.CanCollide = locked
	info.door.Color = if locked then DOOR_LOCKED_COLOR else DOOR_OPEN_COLOR
	info.door.Transparency = if locked then 0.3 else 0.85

	if not base.owner then
		info.ownerLabel.Text = "Libre"
		info.statusLabel.Text = ""
		return
	end

	info.ownerLabel.Text = `Base de {base.owner.DisplayName}`
	if guarded then
		info.statusLabel.Text = `Guardia de seguridad {formatTime(base.guardUntil - now)}`
		info.statusLabel.TextColor3 = STATUS_LOCKED_COLOR
	elseif locked then
		info.statusLabel.Text = `Bloqueada {math.ceil(base.lockedUntil - now)} s`
		info.statusLabel.TextColor3 = STATUS_LOCKED_COLOR
	elseif now < base.cooldownUntil then
		info.statusLabel.Text = `Abierta - bloqueo en {math.ceil(base.cooldownUntil - now)} s`
		info.statusLabel.TextColor3 = STATUS_OPEN_COLOR
	else
		info.statusLabel.Text = "Abierta"
		info.statusLabel.TextColor3 = STATUS_OPEN_COLOR
	end
end

-- Bloquea la puerta si quien lo pide es el dueño y ya pasó la espera. Devuelve true si se bloqueó.
function BaseService.tryLock(player: Player): boolean
	local base = baseByPlayer[player]
	if not base then
		return false
	end
	local now = os.clock()
	if now < base.cooldownUntil then
		return false
	end
	base.lockedUntil = now + GameConfig.DoorLockDuration
	base.cooldownUntil = base.lockedUntil + GameConfig.DoorLockCooldown
	refreshBase(base)
	return true
end

-- ===== Asignación =====

local function assignBase(player: Player)
	if baseByPlayer[player] then
		return
	end

	local freeBase: Base? = nil
	for _, base in bases do
		if not base.owner then
			freeBase = base
			break
		end
	end
	if not freeBase then
		warn(`[BaseService] No hay bases libres para {player.Name}. Revisa el máximo de jugadores del juego.`)
		return
	end

	local base = freeBase :: Base
	base.owner = player
	baseByPlayer[player] = base
	player:SetAttribute("BaseIndex", base.index)
	player.RespawnLocation = base.info.spawn

	trackCharacter(player, base)
	-- Si su personaje ya apareció en otro sitio, lo llevamos a su base
	if player.Character then
		player.Character:PivotTo(base.info.spawn.CFrame + Vector3.new(0, 4, 0))
	end

	refreshBase(base)
	assignedEvent:Fire(player, base.index)
end

local function releaseBase(player: Player)
	local base = baseByPlayer[player]
	disconnectCharacter(player)
	if not base then
		return
	end

	baseByPlayer[player] = nil
	base.owner = nil
	base.lockedUntil = 0
	base.cooldownUntil = 0
	base.guardUntil = 0
	refreshBase(base)
	releasedEvent:Fire(player, base.index)
end

-- ===== API pública =====

-- Pone un guardia en la base del jugador durante esos segundos (0 lo retira)
function BaseService.setGuard(player: Player, seconds: number)
	local base = baseByPlayer[player]
	if base then
		base.guardUntil = if seconds > 0 then os.clock() + seconds else 0
		refreshBase(base)
	end
end

function BaseService.getBase(player: Player): Base?
	return baseByPlayer[player]
end

function BaseService.getBaseByIndex(index: number): Base?
	return bases[index]
end

function BaseService.getBases(): { Base }
	return bases
end

function BaseService.start(map: MapBuilder.MapInfo)
	if started then
		return
	end
	started = true

	for _, info in map.bases do
		local base: Base = {
			info = info,
			index = info.index,
			owner = nil,
			lockedUntil = 0,
			cooldownUntil = 0,
			guardUntil = 0,
			doorGroup = `BaseDoor{info.index}`,
			ownerGroup = `BaseOwner{info.index}`,
		}
		table.insert(bases, base)

		registerGroup(base.doorGroup)
		registerGroup(base.ownerGroup)
		PhysicsService:CollisionGroupSetCollidable(base.doorGroup, base.ownerGroup, false)
		info.door.CollisionGroup = base.doorGroup

		-- El dueño bloquea la puerta subiéndose a la placa roja
		info.lockPad.Touched:Connect(function(hit)
			local character = hit.Parent
			local player = character and Players:GetPlayerFromCharacter(character)
			if not player or player ~= base.owner then
				return
			end
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				BaseService.tryLock(player)
			end
		end)

		refreshBase(base)
	end

	Players.PlayerAdded:Connect(assignBase)
	Players.PlayerRemoving:Connect(releaseBase)
	for _, player in Players:GetPlayers() do
		assignBase(player)
	end

	-- Actualiza las cuentas atrás de los carteles y abre las puertas cuando toca
	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, base in bases do
				if base.owner then
					refreshBase(base)
				end
			end
		end
	end)
end

return BaseService
