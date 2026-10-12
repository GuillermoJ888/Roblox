-- Frutas colocadas en el piso 1 de cada base: las muestra, calcula el dinero que
-- generan cada segundo y lo entrega cuando el dueño pisa la placa verde.
--
--   PlacementService.addFruit(player, item)       -> ranura donde quedó, o nil si la base está llena
--   PlacementService.reserveSlot(player)          -> aparta una ranura para una fruta que viene de camino
--   PlacementService.placeReserved(player, ranura, item) -> coloca la fruta en la ranura apartada
--   PlacementService.removeFruit(player, ranura)  -> la fruta retirada (para congelar, vender o robar)
--   PlacementService.collect(player)              -> dinero recogido

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CharacterConfig = require(Shared.Config.CharacterConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Mutations = require(Shared.Config.Mutations)
local Format = require(Shared.Util.Format)

local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)
local Notifier = require(script.Parent.Notifier)
local CharacterBuilder = require(script.Parent.Parent.World.CharacterBuilder)

type Placed = {
	item: DataService.Item,
	model: Model,
	pendingLabel: TextLabel?,
	pending: number, -- dinero acumulado sin recoger
	income: number, -- dinero por segundo, con la mutación aplicada
}

local PlacementService = {}

-- Frutas visibles de cada jugador, por ranura ("1", "2"...)
local placedByPlayer: { [Player]: { [string]: Placed } } = {}
-- Ranuras apartadas para frutas compradas que aún van caminando hacia la base
local reservedByPlayer: { [Player]: { [string]: boolean } } = {}
local started = false

-- Los rebirths dan un extra permanente a todos los ingresos
local function getIncomeMultiplier(data: DataService.PlayerData): number
	return 1 + data.rebirths * GameConfig.RebirthIncomeBonus
end

local function getTotalPending(player: Player): number
	local total = 0
	local placed = placedByPlayer[player]
	if placed then
		for _, entry in placed do
			total += entry.pending
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

-- Primera ranura de frutas que no está ocupada ni apartada
local function findFreeSlot(player: Player, data: DataService.PlayerData): string?
	local reserved = reservedByPlayer[player]
	for slot = 1, GameConfig.FruitSlots do
		local key = tostring(slot)
		if data.fruits[key] == nil and not (reserved and reserved[key]) then
			return key
		end
	end
	return nil
end

-- Crea el modelo de una fruta sobre su casilla
local function showFruit(player: Player, slotKey: string, item: DataService.Item)
	local base = BaseService.getBase(player)
	local placed = placedByPlayer[player]
	local slot = base and base.info.fruitSlots[tonumber(slotKey) :: number]
	if not base or not placed or not slot or placed[slotKey] then
		return
	end

	local character = CharacterConfig.ById[item.id]
	local model = CharacterBuilder.create(item.id, item.mutation, false)
	-- Otro sistema pudo ocupar la ranura o el jugador pudo irse mientras se creaba el modelo
	if placedByPlayer[player] ~= placed or placed[slotKey] then
		model:Destroy()
		return
	end

	model:SetAttribute("Uid", item.uid)
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("Slot", slotKey)
	-- De pie sobre la casilla, mirando hacia la puerta
	CharacterBuilder.placeAt(model, slot.CFrame * CFrame.new(0, slot.Size.Y / 2, 0))
	model.Parent = base.info.model

	local info = model:FindFirstChild("Info")
	local pendingLabel = info and info:FindFirstChild("Pending")

	placed[slotKey] = {
		item = item,
		model = model,
		pendingLabel = if pendingLabel and pendingLabel:IsA("TextLabel") then pendingLabel else nil,
		pending = 0,
		income = character.incomePerSecond * Mutations.getMultiplier(item.mutation),
	}
end

-- Muestra todas las frutas guardadas cuando el jugador ya tiene base y datos
local function loadPlayer(player: Player)
	if placedByPlayer[player] then
		return
	end
	local data = DataService.waitForData(player)
	if not data or placedByPlayer[player] or not BaseService.getBase(player) then
		return
	end

	placedByPlayer[player] = {}
	reservedByPlayer[player] = {}
	for slotKey, item in data.fruits do
		task.spawn(showFruit, player, slotKey, item)
	end
	refreshCollectLabel(player)
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

	for _, entry in placed do
		entry.pending = 0
		if entry.pendingLabel then
			entry.pendingLabel.Text = Format.money(0)
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

	placedByPlayer[player] = nil
	reservedByPlayer[player] = nil
	for _, entry in placed do
		entry.model:Destroy()
	end

	local base = if baseIndex then BaseService.getBaseByIndex(baseIndex) else nil
	if base then
		base.info.collectLabel.Text = "Recolectar"
	end
end

-- Coloca una fruta nueva en la primera ranura libre. Devuelve la ranura, o nil si no cabe.
function PlacementService.addFruit(player: Player, item: DataService.Item): string?
	local data = DataService.getData(player)
	if not data or not placedByPlayer[player] then
		return nil
	end
	local slotKey = findFreeSlot(player, data)
	if not slotKey then
		return nil
	end
	data.fruits[slotKey] = item
	task.spawn(showFruit, player, slotKey, item)
	return slotKey
end

-- Aparta una ranura libre para una fruta que viene caminando. Devuelve la ranura, o nil si no hay.
function PlacementService.reserveSlot(player: Player): string?
	local data = DataService.getData(player)
	local reserved = reservedByPlayer[player]
	if not data or not reserved or not placedByPlayer[player] then
		return nil
	end
	local slotKey = findFreeSlot(player, data)
	if slotKey then
		reserved[slotKey] = true
	end
	return slotKey
end

function PlacementService.releaseReservation(player: Player, slotKey: string)
	local reserved = reservedByPlayer[player]
	if reserved then
		reserved[slotKey] = nil
	end
end

-- Coloca una fruta en la ranura que se había apartado. Devuelve false si ya no es posible.
function PlacementService.placeReserved(player: Player, slotKey: string, item: DataService.Item): boolean
	local data = DataService.getData(player)
	local reserved = reservedByPlayer[player]
	if not data or not reserved or not reserved[slotKey] or data.fruits[slotKey] ~= nil then
		return false
	end
	reserved[slotKey] = nil
	data.fruits[slotKey] = item
	task.spawn(showFruit, player, slotKey, item)
	return true
end

function PlacementService.hasFreeSlot(player: Player): boolean
	local data = DataService.getData(player)
	if not data or not placedByPlayer[player] then
		return false
	end
	return findFreeSlot(player, data) ~= nil
end

-- Retira una fruta de la base. Lo que tenía acumulado se entrega antes al dueño.
function PlacementService.removeFruit(player: Player, slotKey: string): DataService.Item?
	local data = DataService.getData(player)
	if not data or not data.fruits[slotKey] then
		return nil
	end
	local item = data.fruits[slotKey]
	data.fruits[slotKey] = nil

	local placed = placedByPlayer[player]
	local entry = placed and placed[slotKey]
	if placed and entry then
		if entry.pending >= 1 then
			DataService.addMoney(player, math.floor(entry.pending))
		end
		entry.model:Destroy()
		placed[slotKey] = nil
		refreshCollectLabel(player)
	end
	return item
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
				Notifier.send(player, `+{Format.money(amount)}`, "success")
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
					local multiplier = getIncomeMultiplier(data)
					for _, entry in placed do
						entry.pending += entry.income * multiplier
						if entry.pendingLabel then
							entry.pendingLabel.Text = Format.money(math.floor(entry.pending))
						end
					end
					refreshCollectLabel(player)
				end
			end
		end
	end)
end

return PlacementService
