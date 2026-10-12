-- Cueva y banda transportadora: genera personajes con rareza y mutación al azar
-- y los mueve hasta el final de la banda. Si nadie los compra, desaparecen.
--
--   SpawnerService.getItem(uid)  -> personaje que sigue en la banda (o nil)
--   SpawnerService.take(uid)     -> lo saca de la banda y lo devuelve (para la compra)
--   SpawnerService.ItemSpawned   -> aviso cada vez que aparece uno

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CharacterConfig = require(Shared.Config.CharacterConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Mutations = require(Shared.Config.Mutations)
local CharacterBuilder = require(script.Parent.Parent.World.CharacterBuilder)
local MapBuilder = require(script.Parent.Parent.World.MapBuilder)

export type ConveyorItem = {
	uid: string,
	character: CharacterConfig.Character,
	mutation: Mutations.Mutation?,
	price: number, -- precio con la mutación aplicada
	model: Model,
	distance: number, -- studs recorridos sobre la banda
}

local SpawnerService = {}

-- true mientras dura una tormenta de mutaciones
SpawnerService.mutationRainActive = false

local items: { [string]: ConveyorItem } = {}
local rng = Random.new()
local started = false

local folder: Folder
local startPosition: Vector3
local direction: Vector3
local beltLength: number

local spawnedEvent = Instance.new("BindableEvent")
-- Solo se envía el uid (los BindableEvent copian las tablas): pide el personaje con getItem(uid)
SpawnerService.ItemSpawned = spawnedEvent.Event -- (uid)

local changedEvent = Instance.new("BindableEvent")
-- Se dispara cuando cambia la mutación (y el precio) de un personaje de la banda
SpawnerService.ItemChanged = changedEvent.Event -- (uid)

local function placeItem(item: ConveyorItem)
	local position = startPosition + direction * item.distance
	CharacterBuilder.placeAt(item.model, CFrame.lookAt(position, position + direction))
end

local function spawnItem()
	local character = CharacterConfig.pickRandom(rng)
	local mutation = Mutations.roll(rng, SpawnerService.mutationRainActive)
	local multiplier = if mutation then mutation.multiplier else 1

	local item: ConveyorItem = {
		uid = HttpService:GenerateGUID(false),
		character = character,
		mutation = mutation,
		price = math.floor(character.price * multiplier),
		model = CharacterBuilder.create(character.id, if mutation then mutation.id else nil, true),
		distance = 0,
	}
	item.model:SetAttribute("Uid", item.uid)
	item.model:SetAttribute("Price", item.price)

	items[item.uid] = item
	placeItem(item)
	item.model.Parent = folder
	spawnedEvent:Fire(item.uid)
end

function SpawnerService.getItem(uid: string): ConveyorItem?
	return items[uid]
end

-- Todos los personajes que van ahora mismo por la banda, por uid. Solo para leer.
function SpawnerService.getItems(): { [string]: ConveyorItem }
	return items
end

-- Pone una mutación a un personaje que va por la banda: cambian su aspecto y su precio
function SpawnerService.setMutation(uid: string, mutation: Mutations.Mutation): boolean
	local item = items[uid]
	if not item then
		return false
	end
	item.mutation = mutation
	item.price = math.floor(item.character.price * mutation.multiplier)
	CharacterBuilder.setMutation(item.model, mutation.id, true)
	item.model:SetAttribute("Price", item.price)
	changedEvent:Fire(uid)
	return true
end

-- Saca un personaje de la banda. Quien lo recibe decide qué hacer con el modelo.
function SpawnerService.take(uid: string): ConveyorItem?
	local item = items[uid]
	if item then
		items[uid] = nil
	end
	return item
end

function SpawnerService.start(map: MapBuilder.MapInfo)
	if started then
		return
	end
	started = true

	folder = Instance.new("Folder")
	folder.Name = "ConveyorItems"
	folder.Parent = map.folder

	startPosition = map.conveyorStart
	local path = map.conveyorEnd - map.conveyorStart
	direction = path.Unit
	beltLength = path.Magnitude

	CharacterBuilder.preload()

	-- Aparición periódica
	task.spawn(function()
		while true do
			local ok, message = pcall(spawnItem)
			if not ok then
				warn(`[SpawnerService] Error al generar un personaje: {message}`)
			end
			task.wait(GameConfig.SpawnInterval)
		end
	end)

	-- Movimiento por la banda
	RunService.Heartbeat:Connect(function(deltaTime)
		for uid, item in items do
			item.distance += GameConfig.ConveyorSpeed * deltaTime
			if item.distance >= beltLength then
				items[uid] = nil
				item.model:Destroy()
			else
				placeItem(item)
			end
		end
	end)
end

return SpawnerService
