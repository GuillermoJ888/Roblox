-- Menú de intercambio entre jugadores.
--   - Sin intercambio en curso: lista de jugadores a los que invitar.
--   - Con intercambio: a la izquierda lo que ofreces tú, a la derecha lo que ofrece el otro,
--     y abajo el estado, la cuenta atrás y los botones.
--
-- Aquí solo se muestra lo que dice el servidor y se piden acciones: él decide todo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Util.Format)

local HudController = require(script.Parent.HudController)
local InventoryController = require(script.Parent.InventoryController)
local ItemText = require(script.Parent.Parent.ItemText)
local Ui = require(script.Parent.Parent.Ui)

type OfferItem = { kind: string, slotKey: string, id: string, mutation: string?, uid: string }
type Offer = { money: number, items: { OfferItem } }
type State = {
	partnerName: string,
	partnerUserId: number,
	mine: Offer,
	theirs: Offer,
	mineAccepted: boolean,
	theirsAccepted: boolean,
	executeAt: number?,
}

local TradeController = {}

local player = Players.LocalPlayer
local started = false

local actionRemote: RemoteEvent
local panel: Frame
local body: Frame
local requestFrame: Frame
local requestLabel: TextLabel
local requestToken = 0

local state: State? = nil
local statusLabel: TextLabel? = nil

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

local function statusText(current: State): string
	if current.executeAt then
		local remaining = math.max(current.executeAt - HudController.getServerTime(), 0)
		return `Los dos aceptaron. Se intercambia en {math.ceil(remaining)} s (aún puedes cancelar)`
	end
	if current.mineAccepted then
		return `Aceptaste. Esperando a {current.partnerName}...`
	end
	if current.theirsAccepted then
		return `{current.partnerName} aceptó. Revisa la oferta y acepta si estás de acuerdo.`
	end
	return "Añade lo que ofreces. Cualquier cambio anula las aceptaciones."
end

-- ===== Sin intercambio: lista de jugadores =====

local function renderPlayerList()
	Ui.setTitle(panel, "Intercambio")
	local list = Ui.list(body)
	local order = 0
	for _, other in Players:GetPlayers() do
		if other ~= player then
			order += 1
			Ui.row(list, order, other.DisplayName, "Invítalo a intercambiar frutas, helados o dinero", nil, "Invitar", Ui.Colors.Blue, function()
				actionRemote:FireServer("Request", other.UserId)
			end)
		end
	end
	if order == 0 then
		Ui.header(list, 1, "No hay otros jugadores en el servidor.")
	end
end

-- ===== Con intercambio: las dos ofertas =====

local function renderColumn(parent: Frame, title: string, position: UDim2): ScrollingFrame
	local column = Instance.new("Frame")
	column.BackgroundTransparency = 1
	column.Size = UDim2.new(0.5, -6, 1, -120)
	column.Position = position
	column.Parent = parent

	Ui.label(column, title, UDim2.new(1, 0, 0, 26), nil, Ui.Colors.Gold)
	return Ui.list(column, UDim2.new(1, 0, 1, -32), UDim2.fromOffset(0, 32))
end

local function renderTrade(current: State)
	Ui.setTitle(panel, `Intercambio con {current.partnerName}`)

	local offered = {}
	for _, item in current.mine.items do
		offered[item.uid] = true
	end

	-- Izquierda: todo mi inventario; lo que está en la oferta se marca
	local mineList = renderColumn(body, "Tú ofreces (toca para añadir o quitar)", UDim2.fromScale(0, 0))
	local order = 1

	local moneyRow = Instance.new("Frame")
	moneyRow.BackgroundColor3 = Ui.Colors.Row
	moneyRow.Size = UDim2.new(1, -8, 0, 44)
	moneyRow.LayoutOrder = order
	moneyRow.Parent = mineList
	Ui.corner(moneyRow, 8)
	Ui.label(moneyRow, "Dinero:", UDim2.fromOffset(80, 28), UDim2.fromOffset(10, 8))

	local moneyBox = Instance.new("TextBox")
	moneyBox.BackgroundColor3 = Ui.Colors.Panel
	moneyBox.Position = UDim2.fromOffset(92, 6)
	moneyBox.Size = UDim2.new(1, -100, 0, 32)
	moneyBox.Text = tostring(current.mine.money)
	moneyBox.PlaceholderText = "0"
	moneyBox.TextColor3 = Ui.Colors.Money
	moneyBox.TextScaled = true
	moneyBox.ClearTextOnFocus = false
	moneyBox.Font = Enum.Font.GothamBold
	moneyBox.Parent = moneyRow
	Ui.corner(moneyBox, 6)
	moneyBox.FocusLost:Connect(function()
		-- Solo dígitos: se ignora cualquier otra cosa que se escriba
		local digits = string.gsub(moneyBox.Text, "%D", "")
		actionRemote:FireServer("SetMoney", tonumber(digits) or 0)
	end)

	local snapshot = InventoryController.get()
	for _, kind in { "iceCreams", "fruits" } do
		local container = (snapshot :: any)[kind]
		for _, slotKey in sortedSlots(container) do
			local item = container[slotKey]
			order += 1
			local inOffer = offered[item.uid] == true
			local row = Ui.row(
				mineList,
				order,
				ItemText.name(kind, item.id),
				ItemText.detail(item.id, item.mutation),
				ItemText.color(item.id),
				if inOffer then "Quitar" else "Ofrecer",
				if inOffer then Ui.Colors.Red else Ui.Colors.Green,
				function()
					actionRemote:FireServer("ToggleItem", kind, slotKey)
				end
			)
			if inOffer then
				row.BackgroundColor3 = Ui.Colors.RowSelected
			end
		end
	end

	-- Derecha: lo que ofrece el otro
	local theirsList = renderColumn(body, `{current.partnerName} ofrece`, UDim2.new(0.5, 6, 0, 0))
	local theirOrder = 1
	Ui.row(theirsList, theirOrder, `Dinero: {Format.money(current.theirs.money)}`, "", Ui.Colors.Money)
	for _, item in current.theirs.items do
		theirOrder += 1
		Ui.row(theirsList, theirOrder, ItemText.name(item.kind, item.id), ItemText.detail(item.id, item.mutation), ItemText.color(item.id))
	end
	if #current.theirs.items == 0 and current.theirs.money == 0 then
		Ui.header(theirsList, theirOrder + 1, "Todavía no ofrece nada.")
	end

	-- Abajo: resumen, estado y botones
	local summary = `Tú das: {Format.money(current.mine.money)} y {#current.mine.items} cosas   ·   Recibes: {Format.money(current.theirs.money)} y {#current.theirs.items} cosas`
	local summaryLabel = Ui.label(body, summary, UDim2.new(1, 0, 0, 24), UDim2.new(0, 0, 1, -112), Ui.Colors.Muted)
	summaryLabel.TextXAlignment = Enum.TextXAlignment.Center

	local status = Ui.label(body, statusText(current), UDim2.new(1, 0, 0, 28), UDim2.new(0, 0, 1, -84))
	status.TextXAlignment = Enum.TextXAlignment.Center
	status.TextColor3 = if current.executeAt then Ui.Colors.Gold else Ui.Colors.Text
	statusLabel = status

	local acceptButton
	if current.mineAccepted then
		acceptButton = Ui.button(body, "Quitar mi aceptación", Ui.Colors.Gray, function()
			actionRemote:FireServer("Unaccept")
		end)
	else
		acceptButton = Ui.button(body, "Aceptar", Ui.Colors.Green, function()
			actionRemote:FireServer("Accept")
		end)
	end
	acceptButton.Size = UDim2.new(0.5, -6, 0, 44)
	acceptButton.Position = UDim2.new(0, 0, 1, -46)

	local cancelButton = Ui.button(body, "Cancelar intercambio", Ui.Colors.Red, function()
		actionRemote:FireServer("Cancel")
	end)
	cancelButton.Size = UDim2.new(0.5, -6, 0, 44)
	cancelButton.Position = UDim2.new(0.5, 6, 1, -46)
end

local function render()
	Ui.clear(body)
	statusLabel = nil
	if state then
		renderTrade(state)
	else
		renderPlayerList()
	end
end

-- ===== Invitación recibida =====

local function showRequest(fromName: string, timeout: number)
	requestToken += 1
	local token = requestToken
	requestLabel.Text = `{fromName} quiere intercambiar contigo`
	requestFrame.Visible = true
	task.delay(timeout, function()
		if requestToken == token then
			requestFrame.Visible = false
		end
	end)
end

local function respond(accept: boolean)
	requestToken += 1
	requestFrame.Visible = false
	actionRemote:FireServer("Respond", accept)
end

local function buildRequestFrame(root: Frame)
	requestFrame = Instance.new("Frame")
	requestFrame.Name = "TradeRequest"
	requestFrame.AnchorPoint = Vector2.new(0.5, 0)
	requestFrame.Position = UDim2.new(0.5, 0, 0, 190)
	requestFrame.Size = UDim2.fromOffset(420, 100)
	requestFrame.BackgroundColor3 = Ui.Colors.Panel
	requestFrame.Visible = false
	requestFrame.Parent = root
	Ui.corner(requestFrame, 12)

	requestLabel = Ui.label(requestFrame, "", UDim2.new(1, -24, 0, 34), UDim2.fromOffset(12, 10))
	requestLabel.TextXAlignment = Enum.TextXAlignment.Center

	local accept = Ui.button(requestFrame, "Aceptar", Ui.Colors.Green, function()
		respond(true)
	end)
	accept.Size = UDim2.new(0.5, -18, 0, 38)
	accept.Position = UDim2.new(0, 12, 1, -48)

	local decline = Ui.button(requestFrame, "Rechazar", Ui.Colors.Red, function()
		respond(false)
	end)
	decline.Size = UDim2.new(0.5, -18, 0, 38)
	decline.Position = UDim2.new(0.5, 6, 1, -48)
end

function TradeController.start()
	if started then
		return
	end
	started = true

	actionRemote = Remotes.get("TradeAction")
	local root = HudController.getRoot()

	local content
	panel, content = Ui.panel(root, "Intercambio", 760, 560)
	body = content
	buildRequestFrame(root)

	HudController.addMenuButton("Intercambiar", Ui.Colors.Gold, function()
		Ui.toggle(panel)
		if panel.Visible then
			render()
		end
	end)

	Remotes.get("TradeUpdate").OnClientEvent:Connect(function(kind, data)
		if kind == "Request" and type(data) == "table" then
			showRequest(tostring(data.fromName), tonumber(data.timeout) or GameConfig.TradeRequestTimeout)
		elseif kind == "State" and type(data) == "table" then
			state = data
			Ui.open(panel)
			render()
		elseif kind == "Closed" then
			state = nil
			Ui.close(panel)
		end
	end)

	-- Mientras se elige qué ofrecer puede cambiar el inventario (llega un helado, te roban...)
	InventoryController.onChanged(function()
		if panel.Visible then
			render()
		end
	end)
	Players.PlayerAdded:Connect(function()
		if panel.Visible and not state then
			render()
		end
	end)
	Players.PlayerRemoving:Connect(function()
		if panel.Visible and not state then
			task.defer(render)
		end
	end)

	-- Cuenta atrás
	task.spawn(function()
		while true do
			task.wait(0.2)
			if state and state.executeAt and statusLabel and statusLabel.Parent then
				statusLabel.Text = statusText(state)
			end
		end
	end)
end

return TradeController
