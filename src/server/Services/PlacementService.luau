-- Frutas (piso 1) y helados (vitrina del piso 2) colocados en cada base: los muestra, calcula
-- el dinero que generan cada segundo y lo entrega cuando el dueño pisa la placa verde.
--
-- kind es "fruits" o "iceCreams".
--   PlacementService.addItem(player, kind, item)        -> ranura donde quedó, o nil si no cabe
--   PlacementService.removeItem(player, kind, ranura)   -> lo retirado (para congelar, vender, robar...)
--   PlacementService.reserve(player, kind, ranura?)     -> aparta una ranura para algo que viene de camino
--   PlacementService.placeReserved(player, kind, ranura, item) -> lo coloca en la ranura apartada
--   PlacementService.collect(player)                    -> dinero recogido
--   PlacementService.onItemShown(función)               -> aviso cada vez que aparece un modelo en una base

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CharacterConfig = require(Shared.Config.CharacterConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Economy = require(Shared.Economy)
local Format = require(Shared.Util.Format)

local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)
local Notifier = require(script.Parent.Notifier)
local PassService = require(script.Parent.PassService)
local CharacterBuilder = require(script.Parent.Parent.World.CharacterBuilder)
local Effects = require(script.Parent.Parent.World.Effects)
local IceCreamBuilder = require(script.Parent.Parent.World.IceCreamBuilder)
local InfoBillboard = require(script.Parent.Parent.World.InfoBillboard)
local MapBuilder = require(script.Parent.Parent.World.MapBuilder)

-- Tipo de cosa colocada. Coincide con el nombre de su tabla en los datos del jugador.
export type Kind = "fruits" | "iceCreams"

type Placed = {
	item: DataService.Item,
	model: Model,
	pendingLabel: TextLabel?,
	pending: number, -- dinero acumulado sin recoger
	income: number, -- dinero por segundo, con la mutación aplicada
}

type ContainerDef = {
	maxSlots: number, -- casillas construidas en la base (no todas tienen por qué estar desbloqueadas)
	getSlots: (info: MapBuilder.BaseInfo) -> { Part },
	build: (item: DataService.Item) -> Model,
}

type ShownCallback = (player: Player, kind: Kind, slotKey: string, model: Model, item: DataService.Item) -> ()

local CONTAINERS: { [Kind]: ContainerDef } = {
	fruits = {
		maxSlots = GameConfig.MaxFruitSlots,
		getSlots = function(info)
			return info.fruitSlots
		end,
		build = function(item)
			return CharacterBuilder.create(item.id, item.mutation, false)
		end,
	},
	iceCreams = {
		maxSlots = GameConfig.IceCreamSlots,
		getSlots = function(info)
			return info.iceCreamSlots
		end,
		build = function(item)
			return IceCreamBuilder.create(item.id, item.mutation)
		end,
	},
}

local PlacementService = {}

-- Modelos visibles de cada jugador, por tipo y por ranura ("1", "2"...)
local placedByPlayer: { [Player]: { [Kind]: { [string]: Placed } } } = {}
-- Ranuras apartadas para cosas que aún no han llegado (compras caminando, robos en curso...)
local reservedByPlayer: { [Player]: { [Kind]: { [string]: boolean } } } = {}

local shownCallbacks: { ShownCallback } = {}
local loadedCallbacks: { (Player) -> () } = {}
local unloadingCallbacks: { (Player) -> () } = {}
local started = false

local function runCallbacks(callbacks: { (...any) -> () }, ...: any)
	for _, callback in callbacks do
		local ok, message = pcall(callback, ...)
		if not ok then
			warn(`[PlacementService] Error en un aviso: {message}`)
		end
	end
end

-- Casillas que este jugador puede usar. Las de fruta crecen con los pases de Robux.
local function getCapacity(player: Player, kind: Kind): number
	if kind == "fruits" then
		return math.min(GameConfig.FruitSlots + PassService.getExtraFruitSlots(player), GameConfig.MaxFruitSlots)
	end
	return CONTAINERS[kind].maxSlots
end

local function getContainer(data: DataService.PlayerData, kind: Kind): { [string]: DataService.Item }
	return (data :: any)[kind]
end

local function getTotalPending(player: Player): number
	local total = 0
	local placed = placedByPlayer[player]
	if placed then
		for _, entries in placed do
			for _, entry in entries do
				total += entry.pending
			end
		end
	end
	return math.floor(total)
end

local function refreshCollectLabel(player: Player)
	local base = BaseService.getBase(player)
	if base then
		base.info.collectLabel.Text = `Recolectar\n{Format.money(getTotalPending(player))}`
	end
end

local function isSlotFree(player: Player, data: DataService.PlayerData, kind: Kind, slotKey: string): boolean
	local reserved = reservedByPlayer[player]
	return getContainer(data, kind)[slotKey] == nil and not (reserved and reserved[kind][slotKey])
end

-- Primera ranura que no está ocupada ni apartada
local function findFreeSlot(player: Player, data: DataService.PlayerData, kind: Kind): string?
	for slot = 1, getCapacity(player, kind) do
		local key = tostring(slot)
		if isSlotFree(player, data, kind, key) then
			return key
		end
	end
	return nil
end

-- Crea el modelo de una fruta o un helado sobre su casilla
local function showItem(player: Player, kind: Kind, slotKey: string, item: DataService.Item)
	local base = BaseService.getBase(player)
	local placed = placedByPlayer[player]
	local definition = CONTAINERS[kind]
	local slot = base and definition.getSlots(base.info)[tonumber(slotKey) :: number]
	if not base or not placed or not slot or placed[kind][slotKey] then
		return
	end

	local model = definition.build(item)
	-- Mientras se creaba el modelo pudo irse el jugador, ocuparse la ranura o retirarse la fruta
	local data = DataService.getData(player)
	if placedByPlayer[player] ~= placed or placed[kind][slotKey] or not data or getContainer(data, kind)[slotKey] ~= item then
		model:Destroy()
		return
	end

	model:SetAttribute("Uid", item.uid)
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("Slot", slotKey)
	-- De pie sobre la casilla, mirando hacia la puerta
	CharacterBuilder.placeAt(model, slot.CFrame * CFrame.new(0, slot.Size.Y / 2, 0))
	model.Parent = base.info.model

	placed[kind][slotKey] = {
		item = item,
		model = model,
		pendingLabel = InfoBillboard.getLabel(model, "Pending"),
		pending = 0,
		income = Economy.income(kind, item.id, item.mutation),
	}
	Effects.burst(model.PrimaryPart, CharacterConfig.ById[item.id].skinColor)
	runCallbacks(shownCallbacks, player, kind, slotKey, model, item)
end

-- Muestra todo lo guardado cuando el jugador ya tiene base y datos
local function loadPlayer(player: Player)
	if placedByPlayer[player] then
		return
	end
	local data = DataService.waitForData(player)
	if not data or placedByPlayer[player] or not BaseService.getBase(player) then
		return
	end

	local base = BaseService.getBase(player)
	if base then
		MapBuilder.setFruitCapacity(base.info, getCapacity(player, "fruits"))
	end
	placedByPlayer[player] = { fruits = {}, iceCreams = {} }
	reservedByPlayer[player] = { fruits = {}, iceCreams = {} }
	for kind in CONTAINERS do
		for slotKey, item in getContainer(data, kind) do
			task.spawn(showItem, player, kind, slotKey, item)
		end
	end
	refreshCollectLabel(player)
	runCallbacks(loadedCallbacks, player)
end

-- Entrega al jugador el dinero acumulado. Devuelve la cantidad recogida.
function PlacementService.collect(player: Player): number
	local placed = placedByPlayer[player]
	local total = getTotalPending(player)
	if not placed or total <= 0 then
		return 0
	end
	if not DataService.addMoney(player, total) then
		return 0
	end

	for _, entries in placed do
		for _, entry in entries do
			entry.pending = 0
			if entry.pendingLabel then
				entry.pendingLabel.Text = Format.money(0)
			end
		end
	end
	refreshCollectLabel(player)
	return total
end

local function unloadPlayer(player: Player, baseIndex: number?)
	local placed = placedByPlayer[player]
	if not placed then
		return
	end
	-- Lo que no se recogió no se pierde (si sus datos siguen cargados)
	PlacementService.collect(player)
	runCallbacks(unloadingCallbacks, player)

	placedByPlayer[player] = nil
	reservedByPlayer[player] = nil
	for _, entries in placed do
		for _, entry in entries do
			entry.model:Destroy()
		end
	end

	local base = if baseIndex then BaseService.getBaseByIndex(baseIndex) else nil
	if base then
		base.info.collectLabel.Text = "Recolectar"
		-- La base queda libre: vuelve a mostrar solo las casillas básicas
		MapBuilder.setFruitCapacity(base.info, GameConfig.FruitSlots)
	end
end

-- Coloca algo nuevo en la primera ranura libre de su tipo. Devuelve la ranura, o nil si no cabe.
function PlacementService.addItem(player: Player, kind: Kind, item: DataService.Item): string?
	local data = DataService.getData(player)
	if not data or not placedByPlayer[player] then
		return nil
	end
	local slotKey = findFreeSlot(player, data, kind)
	if not slotKey then
		return nil
	end
	getContainer(data, kind)[slotKey] = item
	task.spawn(showItem, player, kind, slotKey, item)
	return slotKey
end

-- Retira algo de la base. Lo que tenía acumulado se entrega antes al dueño.
function PlacementService.removeItem(player: Player, kind: Kind, slotKey: string): DataService.Item?
	local data = DataService.getData(player)
	local container = if data then getContainer(data, kind) else nil
	if not container or not container[slotKey] then
		return nil
	end
	local item = container[slotKey]
	container[slotKey] = nil

	local placed = placedByPlayer[player]
	local entry = placed and placed[kind][slotKey]
	if placed and entry then
		if entry.pending >= 1 then
			DataService.addMoney(player, math.floor(entry.pending))
		end
		entry.model:Destroy()
		placed[kind][slotKey] = nil
		refreshCollectLabel(player)
	end
	return item
end

-- Número de ranuras libres (ni ocupadas ni apartadas)
function PlacementService.countFree(player: Player, kind: Kind): number
	local data = DataService.getData(player)
	if not data or not placedByPlayer[player] then
		return 0
	end
	local count = 0
	for slot = 1, getCapacity(player, kind) do
		if isSlotFree(player, data, kind, tostring(slot)) then
			count += 1
		end
	end
	return count
end

function PlacementService.hasFree(player: Player, kind: Kind): boolean
	return PlacementService.countFree(player, kind) > 0
end

-- Lo que hay guardado en una ranura (o nil)
function PlacementService.getItem(player: Player, kind: Kind, slotKey: string): DataService.Item?
	local data = DataService.getData(player)
	return if data then getContainer(data, kind)[slotKey] else nil
end

-- Modelo visible de lo que hay en una ranura (o nil si aún no se ha creado)
function PlacementService.getModel(player: Player, kind: Kind, slotKey: string): Model?
	local placed = placedByPlayer[player]
	local entry = placed and placed[kind][slotKey]
	return if entry then entry.model else nil
end

-- true cuando la base del jugador ya está lista para recibir cosas
function PlacementService.isLoaded(player: Player): boolean
	return placedByPlayer[player] ~= nil
end

-- Aparta una ranura libre. Si se indica slotKey, aparta justo esa (si está libre).
-- Devuelve la ranura apartada, o nil si no hay.
function PlacementService.reserve(player: Player, kind: Kind, slotKey: string?): string?
	local data = DataService.getData(player)
	local reserved = reservedByPlayer[player]
	if not data or not reserved or not placedByPlayer[player] then
		return nil
	end
	local chosen = slotKey
	if chosen then
		if not isSlotFree(player, data, kind, chosen) then
			return nil
		end
	else
		chosen = findFreeSlot(player, data, kind)
	end
	if chosen then
		reserved[kind][chosen] = true
	end
	return chosen
end

function PlacementService.release(player: Player, kind: Kind, slotKey: string)
	local reserved = reservedByPlayer[player]
	if reserved then
		reserved[kind][slotKey] = nil
	end
end

-- Coloca algo en la ranura que se había apartado. Devuelve false si ya no es posible.
function PlacementService.placeReserved(player: Player, kind: Kind, slotKey: string, item: DataService.Item): boolean
	local data = DataService.getData(player)
	local reserved = reservedByPlayer[player]
	if not data or not reserved or not reserved[kind][slotKey] or getContainer(data, kind)[slotKey] ~= nil then
		return false
	end
	reserved[kind][slotKey] = nil
	getContainer(data, kind)[slotKey] = item
	task.spawn(showItem, player, kind, slotKey, item)
	return true
end

-- Vacía la base del jugador: frutas y helados (lo usa el rebirth). Antes entrega lo acumulado.
function PlacementService.clearAll(player: Player)
	local data = DataService.getData(player)
	if not data then
		return
	end
	PlacementService.collect(player)
	for kind in CONTAINERS do
		for slot = 1, CONTAINERS[kind].maxSlots do
			PlacementService.removeItem(player, kind, tostring(slot))
		end
	end
end

-- Atajos para las frutas, que es lo que más se usa
function PlacementService.addFruit(player: Player, item: DataService.Item): string?
	return PlacementService.addItem(player, "fruits", item)
end

function PlacementService.removeFruit(player: Player, slotKey: string): DataService.Item?
	return PlacementService.removeItem(player, "fruits", slotKey)
end

function PlacementService.hasFreeSlot(player: Player): boolean
	return PlacementService.hasFree(player, "fruits")
end

function PlacementService.addIceCream(player: Player, item: DataService.Item): string?
	return PlacementService.addItem(player, "iceCreams", item)
end

function PlacementService.reserveSlot(player: Player): string?
	return PlacementService.reserve(player, "fruits")
end

function PlacementService.releaseReservation(player: Player, slotKey: string)
	PlacementService.release(player, "fruits", slotKey)
end

-- Registra una función que se llama cada vez que aparece un modelo en una base
-- (por ejemplo, para ponerle botones de acción)
function PlacementService.onItemShown(callback: ShownCallback)
	table.insert(shownCallbacks, callback)
end

-- Registra una función que se llama cuando la base de un jugador queda lista
function PlacementService.onPlayerLoaded(callback: (Player) -> ())
	table.insert(loadedCallbacks, callback)
end

-- Registra una función que se llama justo antes de vaciar la base de un jugador que se va
function PlacementService.onPlayerUnloading(callback: (Player) -> ())
	table.insert(unloadingCallbacks, callback)
end

function PlacementService.start()
	if started then
		return
	end
	started = true

	BaseService.BaseAssigned:Connect(function(player)
		loadPlayer(player)
	end)
	BaseService.BaseReleased:Connect(unloadPlayer)
	-- Al conseguir un pase de ampliación se encienden las casillas nuevas
	PassService.onChanged(function(player)
		local base = BaseService.getBase(player)
		if base and placedByPlayer[player] then
			MapBuilder.setFruitCapacity(base.info, getCapacity(player, "fruits"))
		end
	end)
	-- Antes del guardado final, lo acumulado pasa al dinero del jugador
	DataService.onPlayerLeaving(function(player)
		PlacementService.collect(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(loadPlayer, player)
	end

	-- El dueño recoge su dinero pisando la placa verde
	for _, base in BaseService.getBases() do
		local lastCollect = 0
		base.info.collectPad.Touched:Connect(function(hit)
			local character = hit.Parent
			local player = character and Players:GetPlayerFromCharacter(character)
			if not player or player ~= base.owner or os.clock() - lastCollect < 0.5 then
				return
			end
			lastCollect = os.clock()
			local amount = PlacementService.collect(player)
			if amount > 0 then
				Notifier.send(player, `+{Format.money(amount)}`, "success", "Collect")
			end
		end)
	end

	-- Ingresos: una vez por segundo
	task.spawn(function()
		while true do
			task.wait(1)
			for player, placed in placedByPlayer do
				local data = DataService.getData(player)
				if data then
					local multiplier = Economy.rebirthMultiplier(data.rebirths)
					for _, entries in placed do
						for _, entry in entries do
							entry.pending += entry.income * multiplier
							if entry.pendingLabel then
								entry.pendingLabel.Text = Format.money(math.floor(entry.pending))
							end
						end
					end
					refreshCollectLabel(player)
				end
			end
		end
	end)
end

return PlacementService
