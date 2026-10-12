-- Menú de la máquina de tormentas: muestra cuánto falta para llenarla y deja echarle
-- frutas y helados. Se abre al pulsar E en la máquina.
--
-- Aquí solo se muestra y se pide: el servidor decide si acepta cada fruta.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Economy = require(Shared.Economy)
local Remotes = require(Shared.Remotes)

local HudController = require(script.Parent.HudController)
local InventoryController = require(script.Parent.InventoryController)
local ItemText = require(script.Parent.Parent.ItemText)
local Ui = require(script.Parent.Parent.Ui)

local STORM_COLOR = Color3.fromRGB(190, 120, 255)

local StormController = {}

local started = false
local actionRemote: RemoteEvent
local panel: Frame
local statusLabel: TextLabel
local list: ScrollingFrame

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

local function statusText(): string
	local phase = Workspace:GetAttribute("StormPhase")
	if phase == "Storm" then
		return "¡Hay tormenta! Corre a la banda: los rayos están mutando frutas."
	elseif phase == "Cooldown" then
		return "La máquina se está recargando. Vuelve en unos minutos."
	end
	local points = Workspace:GetAttribute("StormPoints") or 0
	return `{points} / {GameConfig.StormGoal} puntos para provocar una tormenta`
end

local function render()
	if not panel.Visible then
		return
	end
	statusLabel.Text = statusText()
	Ui.clear(list)

	local snapshot = InventoryController.get()
	local order = 0
	for _, kind in { "fruits", "iceCreams" } do
		local container = (snapshot :: any)[kind]
		for _, slotKey in sortedSlots(container) do
			local item = container[slotKey]
			local points = Economy.stormPoints(kind, item.id)
			order += 1
			Ui.row(
				list,
				order,
				ItemText.name(kind, item.id),
				ItemText.detail(item.id, item.mutation),
				ItemText.color(item.id),
				`Echar (+{points})`,
				Ui.Colors.Blue,
				function()
					actionRemote:FireServer("Donate", kind, slotKey)
				end
			)
		end
	end

	if order == 0 then
		Ui.header(list, 1, "No tienes frutas ni helados para echar.")
	end
end

function StormController.start()
	if started then
		return
	end
	started = true

	actionRemote = Remotes.get("StormAction")

	local content
	panel, content = Ui.panel(HudController.getRoot(), "Máquina de tormentas", 560, 520)

	statusLabel = Ui.label(content, "", UDim2.new(1, 0, 0, 30), nil, STORM_COLOR)
	statusLabel.TextXAlignment = Enum.TextXAlignment.Center

	local help = Ui.label(
		content,
		"Lo que eches se gasta. Durante la tormenta, los rayos ponen mutaciones a las frutas que van por la banda.",
		UDim2.new(1, 0, 0, 40),
		UDim2.fromOffset(0, 34),
		Ui.Colors.Muted
	)
	help.TextXAlignment = Enum.TextXAlignment.Center

	list = Ui.list(content, UDim2.new(1, 0, 1, -84), UDim2.fromOffset(0, 84))

	Remotes.get("OpenStorm").OnClientEvent:Connect(function()
		Ui.open(panel)
		render()
	end)

	InventoryController.onChanged(render)
	Workspace:GetAttributeChangedSignal("StormPhase"):Connect(render)
	Workspace:GetAttributeChangedSignal("StormPoints"):Connect(function()
		if panel.Visible then
			statusLabel.Text = statusText()
		end
	end)
end

return StormController
