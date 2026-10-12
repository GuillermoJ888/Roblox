-- Envía a cada jugador un resumen de lo que tiene (frutas, helados, congelador, herramientas)
-- para que sus menús lo muestren. Solo se envía cuando algo cambia.
--
-- Se revisa una vez por segundo comparando con el último resumen enviado. Así ningún otro
-- sistema tiene que acordarse de avisar cada vez que modifica los datos.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)
local DataService = require(script.Parent.DataService)

local InventoryService = {}

local inventoryRemote = Remotes.get("Inventory")
local lastSent: { [Player]: string } = {}
local started = false

local function copyItems(container: { [string]: DataService.Item }): { [string]: any }
	local result = {}
	for slotKey, item in container do
		result[slotKey] = { id = item.id, mutation = item.mutation, uid = item.uid }
	end
	return result
end

local function buildSnapshot(data: DataService.PlayerData): { [string]: any }
	local freezer = {}
	for slotKey, item in data.freezer do
		freezer[slotKey] = {
			id = item.id,
			mutation = item.mutation,
			uid = item.uid,
			readyAt = item.startedAt + item.duration, -- hora (os.time) a la que termina
		}
	end

	local tools = {}
	for toolId in data.tools do
		table.insert(tools, toolId)
	end
	table.sort(tools)

	return {
		fruits = copyItems(data.fruits),
		iceCreams = copyItems(data.iceCreams),
		freezer = freezer,
		tools = tools,
		lastDailyBonus = data.lastDailyBonus,
	}
end

local function update(player: Player)
	local data = DataService.getData(player)
	if not data then
		return
	end
	local snapshot = buildSnapshot(data)
	local signature = HttpService:JSONEncode(snapshot)
	if lastSent[player] ~= signature then
		lastSent[player] = signature
		inventoryRemote:FireClient(player, snapshot)
	end
end

function InventoryService.start()
	if started then
		return
	end
	started = true

	Players.PlayerRemoving:Connect(function(player)
		lastSent[player] = nil
	end)

	task.spawn(function()
		while true do
			for _, player in Players:GetPlayers() do
				update(player)
			end
			task.wait(1)
		end
	end)
end

return InventoryService
