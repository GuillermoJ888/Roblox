-- Guarda el resumen que envía el servidor con lo que tiene el jugador y muestra el
-- menú "Inventario": frutas, helados y lo que hay en el congelador con su tiempo.
--
--   InventoryController.get()            -> último resumen recibido
--   InventoryController.onChanged(fn)    -> aviso cada vez que cambia

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Economy = require(Shared.Economy)
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Util.Format)

local HudController = require(script.Parent.HudController)
local ItemText = require(script.Parent.Parent.ItemText)
local Ui = require(script.Parent.Parent.Ui)

export type Item = { id: string, mutation: string?, uid: string, readyAt: number? }

export type Snapshot = {
	fruits: { [string]: Item },
	iceCreams: { [string]: Item },
	freezer: { [string]: Item },
	tools: { string },
	lastDailyBonus: number,
}

local InventoryController = {}

local player = Players.LocalPlayer
local started = false

local snapshot: Snapshot = { fruits = {}, iceCreams = {}, freezer = {}, tools = {}, lastDailyBonus = 0 }
local received = false
local changedCallbacks: { () -> () } = {}

local panel: Frame
local list: ScrollingFrame
-- Etiquetas de tiempo del congelador, para actualizarlas cada segundo sin rehacer la lista
local timerLabels: { [TextLabel]: number } = {}

local function count(container: { [string]: any }): number
	local total = 0
	for _ in container do
		total += 1
	end
	return total
end

-- Ranuras ordenadas ("1", "2", "10"...) para que la lista no salte de sitio
local function sortedSlots(container: { [string]: any }): { string }
	local slots = {}
	for slotKey in container do
		table.insert(slots, slotKey)
	end
	table.sort(slots, function(a, b)
		return (tonumber(a) or 0) < (tonumber(b) or 0)
	end)
	return slots
end

local function getRebirths(): number
	local leaderstats = player:FindFirstChild("leaderstats")
	local rebirths = leaderstats and leaderstats:FindFirstChild("Rebirths")
	return if rebirths and rebirths:IsA("IntValue") then rebirths.Value else 0
end

local function freezerText(readyAt: number): string
	local remaining = readyAt - HudController.getServerTime()
	return if remaining > 0 then `Listo en {Format.time(remaining)}` else "¡Listo! Esperando sitio en la vitrina"
end

local function render()
	Ui.clear(list)
	table.clear(timerLabels)
	local multiplier = Economy.rebirthMultiplier(getRebirths())
	local order = 0

	local function addSection(title: string, kind: string, container: { [string]: Item }, maxSlots: number)
		order += 1
		Ui.header(list, order, `{title} ({count(container)}/{maxSlots})`)
		for _, slotKey in sortedSlots(container) do
			local item = container[slotKey]
			order += 1
			if kind == "freezer" then
				local row = Ui.row(list, order, ItemText.name(kind, item.id), ItemText.detail(item.id, item.mutation), ItemText.color(item.id))
				local timer = Ui.label(row, freezerText(item.readyAt or 0), UDim2.fromOffset(250, 20), UDim2.new(1, -260, 0.5, -10), Color3.fromRGB(170, 225, 255))
				timer.TextXAlignment = Enum.TextXAlignment.Right
				timerLabels[timer] = item.readyAt or 0
			else
				local income = Economy.income(kind, item.id, item.mutation) * multiplier
				local detail = `{ItemText.detail(item.id, item.mutation)} · {Format.money(income)}/s`
				Ui.row(list, order, ItemText.name(kind, item.id), detail, ItemText.color(item.id))
			end
		end
	end

	local fruitCapacity = GameConfig.FruitSlots + (player:GetAttribute("ExtraFruitSlots") or 0)
	addSection("Frutas", "fruits", snapshot.fruits, fruitCapacity)
	addSection("Helados", "iceCreams", snapshot.iceCreams, GameConfig.IceCreamSlots)
	addSection("Congelador", "freezer", snapshot.freezer, GameConfig.FreezerSlots)
end

-- Consejo para quien todavía no tiene nada
local function updateHint()
	local empty = count(snapshot.fruits) + count(snapshot.iceCreams) + count(snapshot.freezer) == 0
	if received and empty then
		HudController.setHint("Ve a la banda del centro y mantén E sobre una fruta para comprarla")
	else
		HudController.setHint(nil)
	end
end

function InventoryController.get(): Snapshot
	return snapshot
end

function InventoryController.onChanged(callback: () -> ())
	table.insert(changedCallbacks, callback)
end

function InventoryController.start()
	if started then
		return
	end
	started = true

	local content
	panel, content = Ui.panel(HudController.getRoot(), "Inventario", 520, 520)
	list = Ui.list(content)

	HudController.addMenuButton("Inventario", Ui.Colors.Blue, function()
		render()
		Ui.toggle(panel)
	end)

	Remotes.get("Inventory").OnClientEvent:Connect(function(newSnapshot)
		if type(newSnapshot) ~= "table" then
			return
		end
		snapshot = newSnapshot
		received = true
		updateHint()
		if panel.Visible then
			render()
		end
		for _, callback in changedCallbacks do
			task.spawn(callback)
		end
	end)

	-- Tiempos del congelador
	task.spawn(function()
		while true do
			task.wait(1)
			if panel.Visible then
				for label, readyAt in timerLabels do
					if label.Parent then
						label.Text = freezerText(readyAt)
					end
				end
			end
		end
	end)
end

return InventoryController
