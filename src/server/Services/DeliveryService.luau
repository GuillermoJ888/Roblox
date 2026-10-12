-- Personajes ya comprados que van caminando desde la banda hasta la base de su dueño.
-- Mientras están fuera de la base, otro jugador puede comprarlos y desviarlos a la suya.
--
--   DeliveryService.begin(item, dueño, ranura)     -> empieza la caminata
--   DeliveryService.get(uid)                       -> entrega en curso (o nil)
--   DeliveryService.canRetarget(uid)               -> true mientras otro jugador aún puede comprarlo
--   DeliveryService.retarget(uid, dueño, ranura)   -> lo desvía; devuelve el dueño y la ranura anteriores

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CharacterConfig = require(Shared.Config.CharacterConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Format = require(Shared.Util.Format)

local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)
local Notifier = require(script.Parent.Notifier)
local PlacementService = require(script.Parent.PlacementService)
local SpawnerService = require(script.Parent.SpawnerService)
local CharacterBuilder = require(script.Parent.Parent.World.CharacterBuilder)

export type Delivery = {
	uid: string,
	model: Model,
	character: CharacterConfig.Character,
	mutationId: string?,
	price: number,
	owner: Player,
	slotKey: string,
	position: Vector3, -- posición actual de los pies
	waypoints: { Vector3 },
	nextIndex: number, -- punto del recorrido hacia el que camina
	insideIndex: number, -- punto a partir del cual ya está dentro de la base
	prompt: ProximityPrompt?,
	track: AnimationTrack?,
}

-- Distancias respecto a la puerta de los puntos por los que pasa
local OUTSIDE_DISTANCE = 8
local INSIDE_DISTANCE = 5

local DeliveryService = {}

local deliveries: { [string]: Delivery } = {}
local started = false

-- Puntos clave de una base: delante de la puerta, justo dentro y la casilla de destino
local function getBasePoints(base: BaseService.Base, slotKey: string): (Vector3, Vector3, Vector3)
	local info = base.info
	local outward = info.origin.LookVector -- del frente de la base hacia la banda
	local doorGround = Vector3.new(info.door.Position.X, 0, info.door.Position.Z)
	local outside = doorGround + outward * OUTSIDE_DISTANCE
	local inside = doorGround - outward * INSIDE_DISTANCE + Vector3.new(0, 1, 0)
	local slot = info.fruitSlots[tonumber(slotKey) :: number]
	local target = slot.Position + Vector3.new(0, slot.Size.Y / 2, 0)
	return outside, inside, target
end

local function updatePrompt(delivery: Delivery)
	if delivery.prompt then
		delivery.prompt.ObjectText =
			`{delivery.character.name} de {delivery.owner.DisplayName} - {Format.money(delivery.price)}`
	end
end

local function removeDelivery(delivery: Delivery)
	deliveries[delivery.uid] = nil
	if delivery.track then
		delivery.track:Stop()
	end
	delivery.model:Destroy()
end

-- El personaje llegó a su casilla: pasa a ser una fruta más de la base
local function complete(delivery: Delivery)
	local owner = delivery.owner
	removeDelivery(delivery)

	local item = DataService.newItem(delivery.character.id, delivery.mutationId)
	if not PlacementService.placeReserved(owner, "fruits", delivery.slotKey, item) then
		-- No debería pasar, pero nunca se cobra sin entregar
		if DataService.addMoney(owner, delivery.price) then
			Notifier.send(owner, "No se pudo colocar tu personaje. Se te devolvió el dinero.", "error")
		end
	end
end

local function step(delivery: Delivery, deltaTime: number)
	local remaining = GameConfig.DeliveryWalkSpeed * deltaTime
	local facing: Vector3? = nil

	while remaining > 0 do
		local target = delivery.waypoints[delivery.nextIndex]
		if not target then
			complete(delivery)
			return
		end

		local offset = target - delivery.position
		local distance = offset.Magnitude
		local flat = Vector3.new(offset.X, 0, offset.Z)
		if flat.Magnitude > 0.05 then
			facing = flat.Unit
		end

		if distance <= remaining then
			delivery.position = target
			remaining -= distance
			-- Al entrar en la base ya no se le puede comprar desde fuera
			if delivery.nextIndex == delivery.insideIndex and delivery.prompt then
				delivery.prompt.Enabled = false
			end
			delivery.nextIndex += 1
		else
			delivery.position += offset.Unit * remaining
			remaining = 0
		end
	end

	local lookDirection = facing or delivery.model:GetPivot().LookVector
	CharacterBuilder.placeAt(delivery.model, CFrame.lookAt(delivery.position, delivery.position + lookDirection))
end

-- Cancela las entregas en curso de un jugador (al salir o al hacer rebirth),
-- devolviéndole el dinero si sus datos siguen cargados
local function cancelFor(player: Player)
	for _, delivery in deliveries do
		if delivery.owner == player then
			DataService.addMoney(player, delivery.price)
			removeDelivery(delivery)
		end
	end
end

DeliveryService.cancelFor = cancelFor

function DeliveryService.get(uid: string): Delivery?
	return deliveries[uid]
end

-- Solo se puede desviar mientras sigue fuera de la base del dueño
function DeliveryService.canRetarget(uid: string): boolean
	local delivery = deliveries[uid]
	return delivery ~= nil and delivery.nextIndex <= delivery.insideIndex
end

-- Empieza la caminata de un personaje recién sacado de la banda (su modelo se reutiliza)
function DeliveryService.begin(item: SpawnerService.ConveyorItem, owner: Player, slotKey: string): boolean
	local base = BaseService.getBase(owner)
	if not base then
		return false
	end

	local model = item.model
	local footOffset = model:GetAttribute("FootOffset") or 0
	local outside, inside, target = getBasePoints(base, slotKey)

	local delivery: Delivery = {
		uid = item.uid,
		model = model,
		character = item.character,
		mutationId = if item.mutation then item.mutation.id else nil,
		price = item.price,
		owner = owner,
		slotKey = slotKey,
		position = model:GetPivot().Position - Vector3.new(0, footOffset, 0),
		waypoints = { outside, inside, target },
		nextIndex = 1,
		insideIndex = 2,
		prompt = if model.PrimaryPart then model.PrimaryPart:FindFirstChildOfClass("ProximityPrompt") else nil,
		track = CharacterBuilder.playWalk(model),
	}
	deliveries[item.uid] = delivery
	updatePrompt(delivery)
	return true
end

-- Desvía el personaje hacia la base de otro jugador. Devuelve el dueño y la ranura anteriores.
function DeliveryService.retarget(uid: string, newOwner: Player, slotKey: string): (Player?, string?)
	local delivery = deliveries[uid]
	local newBase = BaseService.getBase(newOwner)
	if not delivery or not newBase or not DeliveryService.canRetarget(uid) then
		return nil, nil
	end

	local previousOwner, previousSlot = delivery.owner, delivery.slotKey
	local outside, inside, target = getBasePoints(newBase, slotKey)
	local waypoints = { outside, inside, target }

	-- Si estaba cruzando la puerta del dueño anterior, primero sale por donde entró
	if delivery.nextIndex == delivery.insideIndex and delivery.nextIndex > 1 then
		table.insert(waypoints, 1, delivery.waypoints[delivery.nextIndex - 1])
	end

	delivery.owner = newOwner
	delivery.slotKey = slotKey
	delivery.waypoints = waypoints
	delivery.nextIndex = 1
	delivery.insideIndex = #waypoints - 1
	updatePrompt(delivery)
	return previousOwner, previousSlot
end

function DeliveryService.start()
	if started then
		return
	end
	started = true

	RunService.Heartbeat:Connect(function(deltaTime)
		for _, delivery in deliveries do
			step(delivery, deltaTime)
		end
	end)

	-- Se llama desde los dos sitios porque no se sabe cuál se ejecuta primero al salir
	DataService.onPlayerLeaving(cancelFor)
	Players.PlayerRemoving:Connect(cancelFor)
end

return DeliveryService
