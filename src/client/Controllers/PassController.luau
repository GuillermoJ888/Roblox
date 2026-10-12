-- Menú "Mejoras": todo lo que se compra con Robux.
--   - Pases: se pagan una vez y son para siempre (ampliar la base, súper resorte, súper botas).
--   - Productos: se pueden comprar las veces que se quiera (tormenta, guardia, súper congelador).
-- También muestra en pantalla el tiempo que queda de las ventajas activas.
--
-- El botón pide la compra al servidor y Roblox muestra su propia ventana de pago.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PassConfig = require(Shared.Config.PassConfig)
local ProductConfig = require(Shared.Config.ProductConfig)
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Util.Format)

local HudController = require(script.Parent.HudController)
local Ui = require(script.Parent.Parent.Ui)

-- Ventajas con tiempo: atributo del jugador con la hora a la que caducan, y su nombre en pantalla
local TIMED_BOOSTS = {
	{ attribute = "GuardUntil", name = "Guardia" },
	{ attribute = "SuperFreezerUntil", name = "Súper congelador" },
}

local PassController = {}

local player = Players.LocalPlayer
local started = false
local passRemote: RemoteEvent
local productRemote: RemoteEvent
local panel: Frame
local list: ScrollingFrame
local boostLabels: { [string]: TextLabel } = {}

local function owns(passId: string): boolean
	return player:GetAttribute(PassConfig.attributeName(passId)) == true
end

local function render()
	if not panel.Visible then
		return
	end
	Ui.clear(list)
	local order = 1
	Ui.header(list, order, "Para siempre (se pagan una vez)")
	for _, pass in PassConfig.List do
		order += 1
		local hasIt = owns(pass.id)
		local locked = pass.requires ~= nil and not owns(pass.requires)
		local buttonText = if hasIt then "Comprado" elseif locked then "Bloqueado" else "Comprar"
		local buttonColor = if hasIt or locked then Ui.Colors.Gray else Ui.Colors.Green
		Ui.row(list, order, pass.name, pass.description, Ui.Colors.Muted, buttonText, buttonColor, function()
			if not hasIt then
				passRemote:FireServer("Buy", pass.id)
			end
		end)
	end

	order += 1
	Ui.header(list, order, "De un uso (puedes comprarlos más veces)")
	for _, product in ProductConfig.List do
		order += 1
		Ui.row(list, order, product.name, product.description, Ui.Colors.Muted, "Comprar", Ui.Colors.Gold, function()
			productRemote:FireServer("Buy", product.id)
		end)
	end
end

-- Etiquetas a la derecha de la pantalla con el tiempo que queda de cada ventaja activa
local function buildBoostLabels(root: Frame)
	local holder = Instance.new("Frame")
	holder.Name = "Boosts"
	holder.AnchorPoint = Vector2.new(1, 0)
	holder.Position = UDim2.new(1, -14, 0.3, 42)
	holder.Size = UDim2.fromOffset(290, 120)
	holder.BackgroundTransparency = 1
	holder.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = holder

	for order, boost in TIMED_BOOSTS do
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromOffset(290, 30)
		label.LayoutOrder = order
		label.BackgroundColor3 = Color3.fromRGB(45, 40, 20)
		label.BackgroundTransparency = 0.2
		label.TextColor3 = Color3.fromRGB(255, 225, 130)
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.Visible = false
		label.Parent = holder
		Ui.corner(label, 10)
		Ui.padding(label, 5)
		boostLabels[boost.attribute] = label
	end
end

function PassController.start()
	if started then
		return
	end
	started = true

	passRemote = Remotes.get("PassAction")
	productRemote = Remotes.get("ProductAction")
	local root = HudController.getRoot()

	local content
	panel, content = Ui.panel(root, "Mejoras", 600, 540)
	local note = Ui.label(content, "Compras con Robux. El pago lo gestiona Roblox.", UDim2.new(1, 0, 0, 26), nil, Ui.Colors.Muted)
	note.TextXAlignment = Enum.TextXAlignment.Center
	list = Ui.list(content, UDim2.new(1, 0, 1, -34), UDim2.fromOffset(0, 34))

	HudController.addMenuButton("Mejoras", Ui.Colors.Green, function()
		Ui.toggle(panel)
		render()
	end)

	for _, pass in PassConfig.List do
		player:GetAttributeChangedSignal(PassConfig.attributeName(pass.id)):Connect(render)
	end

	buildBoostLabels(root)
	task.spawn(function()
		while true do
			for _, boost in TIMED_BOOSTS do
				local label = boostLabels[boost.attribute]
				local expiresAt = player:GetAttribute(boost.attribute)
				local remaining = if type(expiresAt) == "number" then expiresAt - HudController.getServerTime() else 0
				label.Visible = remaining > 0
				if remaining > 0 then
					label.Text = `{boost.name} {Format.time(remaining)}`
				end
			end
			task.wait(1)
		end
	end)
end

return PassController
