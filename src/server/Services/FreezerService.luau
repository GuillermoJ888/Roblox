-- Congelador del piso 2: el dueño manda una fruta, que sube caminando; corre un temporizador
-- según su rareza y al terminar se convierte en un helado que pasa a la vitrina.
--
-- El tiempo se guarda como la hora en que se metió la fruta, así que sigue contando
-- aunque el jugador se desconecte.
--
--   FreezerService.freeze(player, ranuraDeFruta)       -> manda esa fruta al congelador
--   FreezerService.unfreeze(player, ranuraCongelador)  -> la saca antes de tiempo (vuelve a ser fruta)
--   FreezerService.clearAll(player)                    -> vacía el congelador (rebirth)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CharacterConfig = require(Shared.Config.CharacterConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Mutations = require(Shared.Config.Mutations)
local Rarities = require(Shared.Config.Rarities)
local Format = require(Shared.Util.Format)

local BaseService = require(script.Parent.BaseService)
local BoostService = require(script.Parent.BoostService)
local DataService = require(script.Parent.DataService)
local Notifier = require(script.Parent.Notifier)
local PlacementService = require(script.Parent.PlacementService)
local CharacterBuilder = require(script.Parent.Parent.World.CharacterBuilder)
local Effects = require(script.Parent.Parent.World.Effects)
local InfoBillboard = require(script.Parent.Parent.World.InfoBillboard)
local Prompts = require(script.Parent.Parent.World.Prompts)

type Frozen = {
	item: DataService.FreezerItem,
	model: Model?, -- nil mientras se está creando
	timerLabel: TextLabel?,
	warnedFull: boolean, -- ya se avisó de que está listo pero no cabe en la vitrina
}

local ICE_TEXT_COLOR = Color3.fromRGB(170, 225, 255)
local READY_TEXT_COLOR = Color3.fromRGB(120, 255, 140)

local FreezerService = {}

-- Frutas en el congelador de cada jugador, por ranura ("1", "2", "3")
local frozenByPlayer: { [Player]: { [string]: Frozen } } = {}
local started = false

local function getRemaining(item: DataService.FreezerItem): number
	-- min: por si el reloj del servidor que la guardó iba adelantado
	return math.min(item.startedAt + item.duration - os.time(), item.duration)
end

-- Mueve el modelo caminando por los puntos indicados. Devuelve false si se interrumpió
-- (isValid dejó de cumplirse: la fruta salió del congelador o el jugador se fue).
local function walkAlong(model: Model, from: Vector3, waypoints: { Vector3 }, isValid: () -> boolean): boolean
	local track = CharacterBuilder.playWalk(model)
	local position = from
	local completed = true

	for _, target in waypoints do
		while true do
			local deltaTime = RunService.Heartbeat:Wait()
			if not isValid() then
				completed = false
				break
			end
			local offset = target - position
			local step = GameConfig.FreezerWalkSpeed * deltaTime
			if offset.Magnitude <= step then
				position = target
				break
			end
			position += offset.Unit * step

			local flat = Vector3.new(offset.X, 0, offset.Z)
			local look = if flat.Magnitude > 0.05 then flat.Unit else model:GetPivot().LookVector
			CharacterBuilder.placeAt(model, CFrame.lookAt(position, position + look))
		end
		if not completed then
			break
		end
	end

	if track then
		track:Stop()
	end
	return completed
end

-- Crea el modelo sobre su ranura del congelador.
-- walkFrom: si se indica, la fruta sube caminando desde ese punto del piso 1 antes de congelarse.
local function showFrozen(player: Player, slotKey: string, entry: Frozen, walkFrom: Vector3?)
	local base = BaseService.getBase(player)
	local slot = base and base.info.freezerSlots[tonumber(slotKey) :: number]
	if not base or not slot then
		return
	end

	local function isCurrent(): boolean
		local frozen = frozenByPlayer[player]
		return frozen ~= nil and frozen[slotKey] == entry
	end

	local item = entry.item
	local character = CharacterConfig.ById[item.id]
	local model = CharacterBuilder.createBare(item.id, item.mutation)
	-- Mientras se creaba el modelo pudo salir del congelador o irse el jugador
	if not isCurrent() then
		model:Destroy()
		return
	end
	entry.model = model
	model:SetAttribute("Uid", item.uid)
	model:SetAttribute("OwnerUserId", player.UserId)

	local slotFeet = slot.CFrame * CFrame.new(0, slot.Size.Y / 2, 0)

	if walkFrom then
		CharacterBuilder.placeAt(model, CFrame.new(walkFrom))
		model.Parent = base.info.model

		local waypoints = table.clone(base.info.freezerPath)
		table.insert(waypoints, slotFeet.Position)
		if not walkAlong(model, walkFrom, waypoints, isCurrent) then
			return -- quien la retiró del congelador ya destruyó el modelo
		end
	end

	CharacterBuilder.placeAt(model, slotFeet)
	CharacterBuilder.applyFrozen(model)
	Effects.burst(model.PrimaryPart, ICE_TEXT_COLOR)
	InfoBillboard.create(model, CharacterBuilder.getHead(model), {
		{ text = character.name, color = Color3.new(1, 1, 1) },
		{ text = "Congelando", color = ICE_TEXT_COLOR, name = "Status" },
		{ text = Format.time(getRemaining(item)), color = ICE_TEXT_COLOR, name = "Timer" },
	}, 1.75)
	local mutation = if item.mutation then Mutations.ById[item.mutation] else nil
	if mutation then
		InfoBillboard.addMutationBadge(model, model.PrimaryPart, mutation.name, mutation.multiplier, mutation.color)
	end
	model.Parent = base.info.model
	entry.timerLabel = InfoBillboard.getLabel(model, "Timer")

	Prompts.addOwner(model, player, { actionText = "Sacar", objectText = character.name }, function()
		FreezerService.unfreeze(player, slotKey)
	end)
end

local function addFrozen(player: Player, slotKey: string, item: DataService.FreezerItem, walkFrom: Vector3?)
	local frozen = frozenByPlayer[player]
	if not frozen then
		return
	end
	local entry: Frozen = { item = item, model = nil, timerLabel = nil, warnedFull = false }
	frozen[slotKey] = entry
	task.spawn(showFrozen, player, slotKey, entry, walkFrom)
end

local function removeFrozen(player: Player, slotKey: string)
	local data = DataService.getData(player)
	if data then
		data.freezer[slotKey] = nil
	end
	local frozen = frozenByPlayer[player]
	local entry = frozen and frozen[slotKey]
	if frozen and entry then
		frozen[slotKey] = nil
		if entry.model then
			entry.model:Destroy()
		end
	end
end

-- Manda al congelador la fruta de esa ranura del piso 1
function FreezerService.freeze(player: Player, fruitSlotKey: string): boolean
	local data = DataService.getData(player)
	local fruit = PlacementService.getItem(player, "fruits", fruitSlotKey)
	local base = BaseService.getBase(player)
	if not data or not fruit or not base or not frozenByPlayer[player] then
		return false
	end

	local freezerSlot = DataService.findFreeSlot(data.freezer, GameConfig.FreezerSlots)
	if not freezerSlot then
		Notifier.send(player, "El congelador está lleno.", "error", "Error")
		return false
	end

	local character = CharacterConfig.ById[fruit.id]
	-- Con el súper congelador activo en este momento, tarda menos
	local duration = math.ceil(Rarities.ById[character.rarity].freezeTime / BoostService.getFreezeSpeed(player))

	-- Punto del piso 1 desde el que empieza a caminar
	local fruitSlot = base.info.fruitSlots[tonumber(fruitSlotKey) :: number]
	local walkFrom = if fruitSlot then fruitSlot.Position + Vector3.new(0, fruitSlot.Size.Y / 2, 0) else nil

	-- Al retirarla se le entrega al dueño lo que tuviera acumulado
	local item = PlacementService.removeFruit(player, fruitSlotKey)
	if not item then
		return false
	end

	local freezerItem: DataService.FreezerItem = {
		id = item.id,
		mutation = item.mutation,
		uid = item.uid,
		startedAt = os.time(),
		duration = duration,
	}
	data.freezer[freezerSlot] = freezerItem
	addFrozen(player, freezerSlot, freezerItem, walkFrom)

	Notifier.send(player, `{character.name} va al congelador. Helado listo en {Format.time(duration)}.`, "info")
	return true
end

-- Saca una fruta del congelador antes de tiempo. Vuelve al piso 1 y pierde lo que llevaba congelado.
function FreezerService.unfreeze(player: Player, freezerSlotKey: string): boolean
	local data = DataService.getData(player)
	local item = if data then data.freezer[freezerSlotKey] else nil
	if not data or not item then
		return false
	end
	if not PlacementService.hasFreeSlot(player) then
		Notifier.send(player, "No tienes espacio libre para frutas en el piso 1.", "error", "Error")
		return false
	end

	removeFrozen(player, freezerSlotKey)
	if not PlacementService.addFruit(player, { id = item.id, mutation = item.mutation, uid = item.uid }) then
		-- No debería pasar (se acaba de comprobar el espacio): se devuelve al congelador
		data.freezer[freezerSlotKey] = item
		addFrozen(player, freezerSlotKey, item)
		return false
	end

	Notifier.send(player, `Sacaste a {CharacterConfig.ById[item.id].name} del congelador.`, "info")
	return true
end

-- Vacía el congelador del jugador (lo usa el rebirth)
function FreezerService.clearAll(player: Player)
	for slot = 1, GameConfig.FreezerSlots do
		removeFrozen(player, tostring(slot))
	end
end

-- Revisa el congelador de un jugador: actualiza los contadores y convierte lo que ya terminó
local function tick(player: Player, frozen: { [string]: Frozen })
	for slotKey, entry in frozen do
		local item = entry.item
		local remaining = getRemaining(item)

		if remaining > 0 then
			if entry.timerLabel then
				entry.timerLabel.Text = Format.time(remaining)
			end
			continue
		end

		local character = CharacterConfig.ById[item.id]
		local iceCream: DataService.Item = { id = item.id, mutation = item.mutation, uid = item.uid }
		if PlacementService.addIceCream(player, iceCream) then
			removeFrozen(player, slotKey)
			Notifier.send(player, `¡Tu helado de {character.flavor} está listo!`, "success", "IceCreamReady")
		else
			-- Sin sitio en la vitrina: espera en el congelador hasta que haya hueco
			if entry.timerLabel then
				entry.timerLabel.Text = "¡Listo! Vitrina llena"
				entry.timerLabel.TextColor3 = READY_TEXT_COLOR
			end
			if not entry.warnedFull then
				entry.warnedFull = true
				Notifier.send(player, `Helado de {character.flavor} listo, pero tu vitrina está llena.`, "error", "Error")
			end
		end
	end
end

local function loadPlayer(player: Player)
	local data = DataService.getData(player)
	if not data or frozenByPlayer[player] then
		return
	end
	frozenByPlayer[player] = {}
	for slotKey, item in data.freezer do
		addFrozen(player, slotKey, item)
	end
end

local function unloadPlayer(player: Player)
	local frozen = frozenByPlayer[player]
	if not frozen then
		return
	end
	frozenByPlayer[player] = nil
	for _, entry in frozen do
		if entry.model then
			entry.model:Destroy()
		end
	end
end

function FreezerService.start()
	if started then
		return
	end
	started = true

	PlacementService.onPlayerLoaded(loadPlayer)
	PlacementService.onPlayerUnloading(unloadPlayer)
	for _, player in Players:GetPlayers() do
		if PlacementService.isLoaded(player) then
			loadPlayer(player)
		end
	end

	-- Cada fruta del piso 1 recibe el botón para mandarla al congelador
	PlacementService.onItemShown(function(player, kind, slotKey, model, item)
		if kind ~= "fruits" then
			return
		end
		Prompts.addOwner(model, player, { actionText = "Congelar", objectText = CharacterConfig.ById[item.id].name }, function()
			FreezerService.freeze(player, slotKey)
		end)
	end)

	-- Temporizadores: una vez por segundo
	task.spawn(function()
		while true do
			task.wait(1)
			for player, frozen in frozenByPlayer do
				local ok, message = pcall(tick, player, frozen)
				if not ok then
					warn(`[FreezerService] Error al revisar el congelador de {player.Name}: {message}`)
				end
			end
		end
	end)
end

return FreezerService
