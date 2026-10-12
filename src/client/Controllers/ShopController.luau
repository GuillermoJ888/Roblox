-- Menú de Cocardo. Se abre al hablarle y tiene cinco pestañas:
-- Hablar (explica el juego), Vender, Bono diario, Tienda y Rebirth.
--
-- Aquí solo se muestran cosas y se piden acciones: el servidor decide si se hacen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local ToolConfig = require(Shared.Config.ToolConfig)
local Economy = require(Shared.Economy)
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Util.Format)

local HudController = require(script.Parent.HudController)
local InventoryController = require(script.Parent.InventoryController)
local ItemText = require(script.Parent.Parent.ItemText)
local Ui = require(script.Parent.Parent.Ui)

-- Lo que cuenta Cocardo en la pestaña "Hablar"
local DIALOGUE = {
	`¡Hola! Soy {GameConfig.CoconutNpcName}, el dueño de esta heladería.`,
	"De la cueva salen frutas por la banda. Mantén E sobre una para comprarla: irá caminando hasta tu base.",
	"En tu base te dan dinero cada segundo. Pisa la placa verde de la entrada para recogerlo.",
	"Mantén E sobre una de tus frutas para mandarla al congelador del piso 2. Al rato se convierte en helado, ¡y da el triple!",
	"Tráeme tus helados y te los compro a buen precio. También vendo armas y mejoras.",
	"Cuidado: otros jugadores pueden robarte. Bloquea tu puerta con la placa roja y golpea a los ladrones para recuperar lo tuyo.",
	"Cuando tengas mucho dinero, haz un rebirth: empiezas de cero, pero ganas más para siempre.",
}

local TABS = { "Hablar", "Vender", "Bono", "Tienda", "Rebirth" }

local ShopController = {}

local player = Players.LocalPlayer
local started = false

local shopRemote: RemoteEvent
local panel: Frame
local body: Frame
local tabButtons: { [string]: TextButton } = {}
local currentTab = "Hablar"
local dialogueIndex = 1
local bonusLabel: TextLabel? = nil

local function getStat(name: string): number
	local leaderstats = player:FindFirstChild("leaderstats")
	local value = leaderstats and leaderstats:FindFirstChild(name)
	return if value and value:IsA("IntValue") then value.Value else 0
end

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

local function bonusText(): (string, boolean)
	local snapshot = InventoryController.get()
	local remaining = snapshot.lastDailyBonus + GameConfig.DailyBonusCooldown - HudController.getServerTime()
	if remaining > 0 then
		return `Tu próximo bono estará listo en {Format.time(remaining)}.`, false
	end
	return "¡Tu bono diario está listo!", true
end

-- ===== Contenido de cada pestaña =====

local renderers: { [string]: () -> () } = {}

function renderers.Hablar()
	local text = Ui.label(body, DIALOGUE[dialogueIndex], UDim2.new(1, 0, 1, -60))
	text.TextXAlignment = Enum.TextXAlignment.Center

	local isLast = dialogueIndex >= #DIALOGUE
	local nextButton = Ui.button(body, if isLast then "Volver a empezar" else "Siguiente", Ui.Colors.Blue, function()
		dialogueIndex = if isLast then 1 else dialogueIndex + 1
		ShopController.render()
	end)
	nextButton.Size = UDim2.fromOffset(200, 40)
	nextButton.AnchorPoint = Vector2.new(0.5, 1)
	nextButton.Position = UDim2.new(0.5, 0, 1, 0)
end

function renderers.Vender()
	local snapshot = InventoryController.get()
	local list = Ui.list(body)
	local order = 0

	local function addSection(title: string, kind: string, container: { [string]: InventoryController.Item })
		local slots = sortedSlots(container)
		if #slots == 0 then
			return
		end
		order += 1
		Ui.header(list, order, title)

		local total = 0
		for _, slotKey in slots do
			local item = container[slotKey]
			local price = Economy.sellPrice(kind, item.id, item.mutation)
			total += price
			order += 1
			Ui.row(
				list,
				order,
				ItemText.name(kind, item.id),
				`{ItemText.detail(item.id, item.mutation)} · {Format.money(price)}`,
				ItemText.color(item.id),
				"Vender",
				Ui.Colors.Green,
				function()
					shopRemote:FireServer("Sell", kind, slotKey)
				end
			)
		end

		if #slots > 1 then
			order += 1
			local sellAll = Ui.button(list, `Vender todo ({Format.money(total)})`, Ui.Colors.Gold, function()
				shopRemote:FireServer("SellAll", kind)
			end)
			sellAll.Size = UDim2.new(1, -8, 0, 38)
			sellAll.LayoutOrder = order
		end
	end

	addSection("Helados", "iceCreams", snapshot.iceCreams)
	addSection("Frutas (se venden a mitad de precio)", "fruits", snapshot.fruits)

	if order == 0 then
		order += 1
		Ui.header(list, order, "No tienes nada que vender todavía.")
	end
end

function renderers.Bono()
	local amount = Economy.dailyBonus(getStat("Rebirths"))
	local title = Ui.label(body, `Bono diario: {Format.money(amount)}`, UDim2.new(1, 0, 0, 40), nil, Ui.Colors.Money)
	title.TextXAlignment = Enum.TextXAlignment.Center

	local text = bonusText()
	local status = Ui.label(body, text, UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 60))
	status.TextXAlignment = Enum.TextXAlignment.Center
	bonusLabel = status

	local claim = Ui.button(body, "Reclamar", Ui.Colors.Green, function()
		shopRemote:FireServer("DailyBonus")
	end)
	claim.Size = UDim2.fromOffset(220, 46)
	claim.AnchorPoint = Vector2.new(0.5, 0)
	claim.Position = UDim2.new(0.5, 0, 0, 120)
end

function renderers.Tienda()
	local owned = {}
	for _, toolId in InventoryController.get().tools do
		owned[toolId] = true
	end

	local list = Ui.list(body)
	for order, tool in ToolConfig.List do
		local hasIt = owned[tool.id] or tool.id == ToolConfig.DefaultWeaponId
		Ui.row(
			list,
			order,
			tool.name,
			tool.description,
			Ui.Colors.Muted,
			if hasIt then "Comprado" else Format.money(tool.price),
			if hasIt then Ui.Colors.Gray else Ui.Colors.Green,
			function()
				if not hasIt then
					shopRemote:FireServer("BuyTool", tool.id)
				end
			end
		)
	end
end

function renderers.Rebirth()
	local rebirths = getStat("Rebirths")
	local cost = Economy.rebirthCost(rebirths)
	local currentBonus = math.round((Economy.rebirthMultiplier(rebirths) - 1) * 100)
	local nextBonus = math.round((Economy.rebirthMultiplier(rebirths + 1) - 1) * 100)

	local lines = {
		`Rebirths: {rebirths}  ·  Bono actual: +{currentBonus} %`,
		`El siguiente cuesta {Format.money(cost)} y sube tu bono a +{nextBonus} %.`,
		"Pierdes el dinero, las frutas, los helados y lo que haya en el congelador.",
		"Conservas las armas y mejoras compradas.",
	}
	for index, line in lines do
		local label = Ui.label(body, line, UDim2.new(1, 0, 0, 34), UDim2.fromOffset(0, (index - 1) * 42))
		label.TextXAlignment = Enum.TextXAlignment.Center
		if index >= 3 then
			label.TextColor3 = Ui.Colors.Muted
		end
	end

	local canAfford = getStat("Dinero") >= cost
	local button = Ui.button(body, "Hacer rebirth", if canAfford then Ui.Colors.Gold else Ui.Colors.Gray, function()
		shopRemote:FireServer("Rebirth")
	end)
	button.Size = UDim2.fromOffset(240, 46)
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Position = UDim2.new(0.5, 0, 0, 190)
end

-- Vuelve a dibujar la pestaña abierta
function ShopController.render()
	if not panel.Visible then
		return
	end
	Ui.clear(body)
	bonusLabel = nil
	for name, button in tabButtons do
		button.BackgroundColor3 = if name == currentTab then Ui.Colors.Blue else Ui.Colors.Gray
	end
	renderers[currentTab]()
end

function ShopController.start()
	if started then
		return
	end
	started = true

	shopRemote = Remotes.get("ShopAction")

	local content
	panel, content = Ui.panel(HudController.getRoot(), GameConfig.CoconutNpcName, 620, 520)

	-- Fila de pestañas
	local tabBar = Instance.new("Frame")
	tabBar.BackgroundTransparency = 1
	tabBar.Size = UDim2.new(1, 0, 0, 38)
	tabBar.Parent = content

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabBar

	for order, name in TABS do
		local button = Ui.button(tabBar, name, Ui.Colors.Gray, function()
			currentTab = name
			ShopController.render()
		end)
		button.Size = UDim2.fromOffset(112, 38)
		button.LayoutOrder = order
		tabButtons[name] = button
	end

	body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(0, 50)
	body.Size = UDim2.new(1, 0, 1, -50)
	body.Parent = content

	-- El servidor avisa cuando el jugador le habla a Cocardo
	Remotes.get("OpenShop").OnClientEvent:Connect(function()
		Ui.open(panel)
		ShopController.render()
	end)

	-- Lo que se vende, se compra o se gana cambia lo que hay que mostrar
	InventoryController.onChanged(ShopController.render)
	task.spawn(function()
		local leaderstats = player:WaitForChild("leaderstats")
		for _, name in { "Dinero", "Rebirths" } do
			local value = leaderstats:WaitForChild(name) :: IntValue
			value.Changed:Connect(function()
				-- El dinero cambia a menudo: solo afecta a la pestaña de rebirth
				if currentTab == "Rebirth" or name == "Rebirths" then
					ShopController.render()
				end
			end)
		end
	end)

	-- Cuenta atrás del bono diario
	task.spawn(function()
		while true do
			task.wait(1)
			if panel.Visible and bonusLabel and bonusLabel.Parent then
				bonusLabel.Text = bonusText()
			end
		end
	end)
end

return ShopController
