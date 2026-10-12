-- Datos de cada jugador: los carga al entrar, los mantiene en memoria mientras juega
-- y los guarda en el DataStore (cada cierto tiempo, al salir y al cerrar el servidor).
--
-- Los demás sistemas NUNCA hablan con el DataStore: piden los datos aquí.
--   DataService.getData(player)            -> tabla de datos (o nil si aún no cargó)
--   DataService.addMoney(player, cantidad)
--   DataService.trySpend(player, cantidad) -> true si tenía dinero y se le descontó

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local CharacterConfig = require(Config.CharacterConfig)
local GameConfig = require(Config.GameConfig)
local Mutations = require(Config.Mutations)
local Rarities = require(Config.Rarities)

-- Cambiar este nombre crea un almacén nuevo y vacío (todos empezarían de cero)
local STORE_NAME = "PlayerData_v1"
local AUTOSAVE_INTERVAL = 90 -- segundos
-- En Studio un solo intento, para no esperar si el acceso a la API está desactivado
local MAX_ATTEMPTS = if RunService:IsStudio() then 1 else 4

-- Una fruta o un helado guardado
export type Item = {
	id: string, -- id del personaje en CharacterConfig
	mutation: string?, -- id de la mutación, o nil
	uid: string, -- identificador único de este ejemplar
}

-- Una fruta dentro del congelador
export type FreezerItem = Item & {
	startedAt: number, -- os.time() del momento en que se metió
	duration: number, -- segundos que tarda en convertirse en helado
}

-- Los contenedores usan el número de ranura como texto ("1", "2"...) porque
-- el DataStore no guarda bien las listas con huecos.
export type PlayerData = {
	version: number,
	money: number,
	rebirths: number,
	fruits: { [string]: Item }, -- piso 1
	iceCreams: { [string]: Item }, -- vitrina del piso 2
	freezer: { [string]: FreezerItem }, -- congelador del piso 2
	tools: { [string]: boolean }, -- herramientas compradas
	lastDailyBonus: number, -- os.time() del último bono diario
	boosts: { -- ventajas compradas con Robux: segundos que le quedan a cada una (solo se gastan conectado)
		guardSeconds: number,
		superFreezerSeconds: number,
	},
}

type Profile = {
	data: PlayerData,
	canSave: boolean, -- false si los datos no vienen del DataStore (no se deben sobrescribir)
}

local DataService = {}

local profiles: { [Player]: Profile } = {}
local leavingCallbacks: { (Player, PlayerData) -> () } = {}
local pendingSaves = 0
local started = false

local loadedEvent = Instance.new("BindableEvent")
-- Se dispara cuando los datos de un jugador ya están listos: DataService.PlayerLoaded:Connect(function(player) ... end)
DataService.PlayerLoaded = loadedEvent.Event

-- En un lugar sin publicar, GetDataStore da error: en ese caso se trabaja solo en memoria
local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn(`[DataService] DataStore no disponible, los datos NO se guardarán: {result}`)
	end
end

local function getKey(player: Player): string
	return `Player_{player.UserId}`
end

-- Ejecuta una operación del DataStore con reintentos (espera 2, 4, 8... segundos entre ellos)
local function retry(actionName: string, callback: () -> any): (boolean, any)
	local lastError
	for attempt = 1, MAX_ATTEMPTS do
		local ok, result = pcall(callback)
		if ok then
			return true, result
		end
		lastError = result
		warn(`[DataService] Fallo al {actionName} (intento {attempt}/{MAX_ATTEMPTS}): {result}`)
		if attempt < MAX_ATTEMPTS then
			task.wait(2 ^ attempt)
		end
	end
	return false, lastError
end

local function isValidAmount(amount: any): boolean
	return type(amount) == "number" and amount == amount and amount >= 0 and amount ~= math.huge
end

local function newUid(): string
	return HttpService:GenerateGUID(false)
end

-- ===== Limpieza de datos cargados =====
-- Lo que viene del DataStore puede ser de una versión vieja del juego (personajes
-- borrados, campos que faltan...). Aquí se reconstruye una tabla siempre válida.

local function sanitizeItem(raw: any): Item?
	if type(raw) ~= "table" or type(raw.id) ~= "string" then
		return nil
	end
	if not CharacterConfig.ById[raw.id] then
		warn(`[DataService] Se descarta un personaje que ya no existe: {raw.id}`)
		return nil
	end
	local mutation = raw.mutation
	if type(mutation) ~= "string" or not Mutations.ById[mutation] then
		mutation = nil
	end
	return {
		id = raw.id,
		mutation = mutation,
		uid = if type(raw.uid) == "string" then raw.uid else newUid(),
	}
end

local function sanitizeContainer(raw: any, maxSlots: number): { [string]: Item }
	local result = {}
	if type(raw) ~= "table" then
		return result
	end
	for slot = 1, maxSlots do
		local key = tostring(slot)
		local item = sanitizeItem(raw[key])
		if item then
			result[key] = item
		end
	end
	return result
end

local function sanitizeFreezer(raw: any): { [string]: FreezerItem }
	local result = {}
	if type(raw) ~= "table" then
		return result
	end
	for slot = 1, GameConfig.FreezerSlots do
		local key = tostring(slot)
		local rawItem = raw[key]
		local item = sanitizeItem(rawItem)
		if item then
			local rarity = Rarities.ById[CharacterConfig.ById[item.id].rarity]
			result[key] = {
				id = item.id,
				mutation = item.mutation,
				uid = item.uid,
				startedAt = if isValidAmount(rawItem.startedAt) then rawItem.startedAt else os.time(),
				duration = if isValidAmount(rawItem.duration) then rawItem.duration else rarity.freezeTime,
			}
		end
	end
	return result
end

local function sanitizeTools(raw: any): { [string]: boolean }
	local result = {}
	if type(raw) == "table" then
		for toolId, owned in raw do
			if type(toolId) == "string" and owned == true then
				result[toolId] = true
			end
		end
	end
	return result
end

-- Convierte lo que haya en el DataStore (o nil si es jugador nuevo) en datos completos
local function buildData(raw: any): PlayerData
	if type(raw) ~= "table" then
		raw = {}
	end
	local rawBoosts = if type(raw.boosts) == "table" then raw.boosts else {}
	return {
		version = 1,
		money = if isValidAmount(raw.money) then math.floor(raw.money) else GameConfig.StartingMoney,
		rebirths = if isValidAmount(raw.rebirths) then math.floor(raw.rebirths) else 0,
		fruits = sanitizeContainer(raw.fruits, GameConfig.MaxFruitSlots),
		iceCreams = sanitizeContainer(raw.iceCreams, GameConfig.IceCreamSlots),
		freezer = sanitizeFreezer(raw.freezer),
		tools = sanitizeTools(raw.tools),
		lastDailyBonus = if isValidAmount(raw.lastDailyBonus) then raw.lastDailyBonus else 0,
		boosts = {
			guardSeconds = if isValidAmount(rawBoosts.guardSeconds) then math.floor(rawBoosts.guardSeconds) else 0,
			superFreezerSeconds = if isValidAmount(rawBoosts.superFreezerSeconds) then math.floor(rawBoosts.superFreezerSeconds) else 0,
		},
	}
end

-- ===== Marcador (lista de jugadores) =====

local function updateLeaderstats(player: Player, data: PlayerData)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"

		local money = Instance.new("IntValue")
		money.Name = "Dinero"
		money.Parent = leaderstats

		local rebirths = Instance.new("IntValue")
		rebirths.Name = "Rebirths"
		rebirths.Parent = leaderstats

		leaderstats.Parent = player
	end
	(leaderstats :: any).Dinero.Value = data.money;
	(leaderstats :: any).Rebirths.Value = data.rebirths
end

-- ===== Cargar y guardar =====

local function saveProfile(player: Player, profile: Profile): boolean
	if not profile.canSave or not store then
		return false
	end
	local key = getKey(player)
	local ok = retry(`guardar los datos de {player.Name}`, function()
		(store :: DataStore):SetAsync(key, profile.data, { player.UserId })
	end)
	return ok
end

local function loadProfile(player: Player)
	if profiles[player] then
		return
	end

	local raw = nil
	local canSave = false

	if store then
		local key = getKey(player)
		local ok, result = retry(`cargar los datos de {player.Name}`, function()
			return (store :: DataStore):GetAsync(key)
		end)
		if ok then
			raw = result
			canSave = true
		elseif RunService:IsStudio() then
			warn("[DataService] Jugando con datos temporales: en Studio no se pudo leer el DataStore.")
		else
			-- Si no se pudo leer, no se deja jugar: al guardar se borraría su progreso real
			player:Kick("No se pudieron cargar tus datos. Vuelve a entrar en unos minutos.")
			return
		end
	end

	-- El jugador pudo irse mientras se cargaban los datos
	if not player:IsDescendantOf(Players) or profiles[player] then
		return
	end

	local profile: Profile = { data = buildData(raw), canSave = canSave }
	-- Dinero de prueba: solo dentro de Roblox Studio, nunca en el juego publicado
	if RunService:IsStudio() and GameConfig.StudioTestMoney > 0 then
		profile.data.money = math.max(profile.data.money, GameConfig.StudioTestMoney)
	end
	profiles[player] = profile
	updateLeaderstats(player, profile.data)
	player:SetAttribute("DataLoaded", true)
	loadedEvent:Fire(player)
end

local function releaseProfile(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end

	-- Otros sistemas ajustan los datos antes del guardado final (p. ej. devolver algo robado)
	for _, callback in leavingCallbacks do
		local ok, message = pcall(callback, player, profile.data)
		if not ok then
			warn(`[DataService] Error en un aviso de salida: {message}`)
		end
	end

	profiles[player] = nil
	pendingSaves += 1
	saveProfile(player, profile)
	pendingSaves -= 1
end

-- ===== API pública =====

-- Datos del jugador, o nil si todavía no han cargado
function DataService.getData(player: Player): PlayerData?
	local profile = profiles[player]
	return if profile then profile.data else nil
end

-- Espera a que carguen los datos. Devuelve nil si el jugador se va o pasa el tiempo límite.
function DataService.waitForData(player: Player, timeout: number?): PlayerData?
	local deadline = os.clock() + (timeout or 30)
	while not profiles[player] and player:IsDescendantOf(Players) and os.clock() < deadline do
		task.wait(0.1)
	end
	return DataService.getData(player)
end

function DataService.getMoney(player: Player): number
	local data = DataService.getData(player)
	return if data then data.money else 0
end

function DataService.setMoney(player: Player, amount: number): boolean
	local data = DataService.getData(player)
	if not data or not isValidAmount(amount) then
		return false
	end
	data.money = math.floor(amount)
	updateLeaderstats(player, data)
	return true
end

function DataService.addMoney(player: Player, amount: number): boolean
	local data = DataService.getData(player)
	if not data or not isValidAmount(amount) then
		return false
	end
	return DataService.setMoney(player, data.money + amount)
end

-- Descuenta dinero solo si tiene suficiente. Devuelve true si se pudo pagar.
function DataService.trySpend(player: Player, amount: number): boolean
	local data = DataService.getData(player)
	if not data or not isValidAmount(amount) or data.money < amount then
		return false
	end
	return DataService.setMoney(player, data.money - amount)
end

-- Actualiza el marcador tras cambiar los rebirths
function DataService.refreshLeaderstats(player: Player)
	local data = DataService.getData(player)
	if data then
		updateLeaderstats(player, data)
	end
end

-- Crea un ejemplar nuevo de un personaje, listo para meter en una ranura
function DataService.newItem(characterId: string, mutationId: string?): Item
	assert(CharacterConfig.ById[characterId], `Personaje desconocido: {characterId}`)
	return {
		id = characterId,
		mutation = if mutationId and Mutations.ById[mutationId] then mutationId else nil,
		uid = newUid(),
	}
end

-- Primera ranura libre de un contenedor (data.fruits, data.iceCreams o data.freezer), o nil si está lleno
function DataService.findFreeSlot(container: { [string]: any }, maxSlots: number): string?
	for slot = 1, maxSlots do
		local key = tostring(slot)
		if container[key] == nil then
			return key
		end
	end
	return nil
end

-- Registra una función que se llama justo antes del guardado final cuando un jugador sale
function DataService.onPlayerLeaving(callback: (Player, PlayerData) -> ())
	table.insert(leavingCallbacks, callback)
end

function DataService.start()
	if started then
		return
	end
	started = true

	Players.PlayerAdded:Connect(loadProfile)
	Players.PlayerRemoving:Connect(releaseProfile)
	for _, player in Players:GetPlayers() do
		task.spawn(loadProfile, player)
	end

	-- Guardado automático
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player, profile in profiles do
				task.spawn(saveProfile, player, profile)
			end
		end
	end)

	-- Al cerrar el servidor: guardar a todos y esperar a que terminen los guardados en curso
	game:BindToClose(function()
		for player in profiles do
			task.spawn(releaseProfile, player)
		end
		while pendingSaves > 0 do
			task.wait(0.1)
		end
	end)
end

return DataService
