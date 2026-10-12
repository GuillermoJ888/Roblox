-- Interfaz fija del jugador: dinero, botones de menú, barra de energía, avisos,
-- anuncios para todo el servidor y la cuenta atrás de la tormenta de mutaciones.
-- Se construye por código y se adapta al tamaño de la pantalla (PC, tablet y teléfono).
--
--   HudController.getRoot()                  -> marco del que cuelgan los demás menús
--   HudController.addMenuButton(texto, fn)   -> añade un botón bajo el dinero
--   HudController.notify(texto, tipo)        -> aviso corto
--   HudController.setHint(texto o nil)       -> consejo fijo en la parte baja de la pantalla

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)
local Ui = require(script.Parent.Parent.Ui)

local NOTIFICATION_DURATION = 3
local ANNOUNCE_DURATION = 5
-- La interfaz está diseñada para una pantalla de 800 px de alto y se escala a partir de ahí
local DESIGN_HEIGHT = 800

local NOTIFICATION_COLORS = {
	info = Color3.fromRGB(255, 255, 255),
	success = Color3.fromRGB(120, 255, 140),
	error = Color3.fromRGB(255, 110, 110),
}

local HudController = {}

local player = Players.LocalPlayer
local started = false

local root: Frame
local moneyFrame: Frame
local moneyLabel: TextLabel
local menuButtons: Frame
local staminaFrame: Frame
local staminaFill: Frame
local notificationList: Frame
local announceLabel: TextLabel
local rainLabel: TextLabel
local hintLabel: TextLabel

local notificationCount = 0
local announceToken = 0
local lastMoney: number? = nil

local function buildGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "HUD"
	gui.ResetOnSpawn = false

	-- Todo cuelga de un marco con escala: en pantallas pequeñas la interfaz encoge entera
	root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui

	local scale = Instance.new("UIScale")
	scale.Parent = root

	local function updateScale()
		local camera = Workspace.CurrentCamera
		if camera then
			scale.Scale = math.clamp(camera.ViewportSize.Y / DESIGN_HEIGHT, 0.6, 1.4)
			-- Con UIScale el marco se dibuja más pequeño o más grande; se compensa para que cubra la pantalla
			root.Size = UDim2.fromScale(1 / scale.Scale, 1 / scale.Scale)
		end
	end
	updateScale()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end

	-- Dinero: a la izquierda, a media altura (lejos del joystick y del botón de salto del teléfono)
	moneyFrame = Instance.new("Frame")
	moneyFrame.Name = "Money"
	moneyFrame.AnchorPoint = Vector2.new(0, 0.5)
	moneyFrame.Position = UDim2.new(0, 14, 0.36, 0)
	moneyFrame.Size = UDim2.fromOffset(210, 52)
	moneyFrame.BackgroundColor3 = Color3.fromRGB(20, 30, 20)
	moneyFrame.BackgroundTransparency = 0.25
	moneyFrame.Parent = root
	Ui.corner(moneyFrame, 14)

	moneyLabel = Instance.new("TextLabel")
	moneyLabel.BackgroundTransparency = 1
	moneyLabel.Position = UDim2.fromOffset(12, 6)
	moneyLabel.Size = UDim2.new(1, -24, 1, -12)
	moneyLabel.Text = "$..."
	moneyLabel.TextColor3 = Ui.Colors.Money
	moneyLabel.TextScaled = true
	moneyLabel.TextXAlignment = Enum.TextXAlignment.Left
	moneyLabel.Font = Enum.Font.FredokaOne
	moneyLabel.Parent = moneyFrame

	-- Botones de menú, en columna bajo el dinero
	menuButtons = Instance.new("Frame")
	menuButtons.Name = "MenuButtons"
	menuButtons.BackgroundTransparency = 1
	menuButtons.Position = UDim2.new(0, 14, 0.36, 36)
	menuButtons.Size = UDim2.fromOffset(170, 200)
	menuButtons.Parent = root

	local menuLayout = Instance.new("UIListLayout")
	menuLayout.Padding = UDim.new(0, 6)
	menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
	menuLayout.Parent = menuButtons

	-- Barra de energía: abajo en el centro, solo visible cuando no está llena
	staminaFrame = Instance.new("Frame")
	staminaFrame.Name = "Stamina"
	staminaFrame.AnchorPoint = Vector2.new(0.5, 1)
	staminaFrame.Position = UDim2.new(0.5, 0, 1, -70)
	staminaFrame.Size = UDim2.fromOffset(260, 16)
	staminaFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	staminaFrame.BackgroundTransparency = 0.25
	staminaFrame.Visible = false
	staminaFrame.Parent = root
	Ui.corner(staminaFrame, 8)

	staminaFill = Instance.new("Frame")
	staminaFill.Name = "Fill"
	staminaFill.Size = UDim2.fromScale(1, 1)
	staminaFill.BackgroundColor3 = Color3.fromRGB(90, 200, 255)
	staminaFill.BorderSizePixel = 0
	staminaFill.Parent = staminaFrame
	Ui.corner(staminaFill, 8)

	-- Consejo para quien empieza: justo encima de la barra de energía
	hintLabel = Instance.new("TextLabel")
	hintLabel.Name = "Hint"
	hintLabel.AnchorPoint = Vector2.new(0.5, 1)
	hintLabel.Position = UDim2.new(0.5, 0, 1, -100)
	hintLabel.Size = UDim2.fromOffset(560, 40)
	hintLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	hintLabel.BackgroundTransparency = 0.3
	hintLabel.TextColor3 = Color3.fromRGB(255, 235, 150)
	hintLabel.TextScaled = true
	hintLabel.Font = Enum.Font.GothamBold
	hintLabel.Visible = false
	hintLabel.Parent = root
	Ui.corner(hintLabel, 10)
	Ui.padding(hintLabel, 7)

	-- Anuncios para todo el servidor: grandes, arriba en el centro
	announceLabel = Instance.new("TextLabel")
	announceLabel.Name = "Announce"
	announceLabel.AnchorPoint = Vector2.new(0.5, 0)
	announceLabel.Position = UDim2.new(0.5, 0, 0, 14)
	announceLabel.Size = UDim2.fromOffset(700, 46)
	announceLabel.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	announceLabel.BackgroundTransparency = 0.25
	announceLabel.TextScaled = true
	announceLabel.Font = Enum.Font.FredokaOne
	announceLabel.TextStrokeTransparency = 0.4
	announceLabel.Visible = false
	announceLabel.Parent = root
	Ui.corner(announceLabel, 12)
	Ui.padding(announceLabel, 6)

	-- Cuenta atrás de la tormenta de mutaciones
	rainLabel = Instance.new("TextLabel")
	rainLabel.Name = "MutationRain"
	rainLabel.AnchorPoint = Vector2.new(1, 0)
	rainLabel.Position = UDim2.new(1, -14, 0.3, 0)
	rainLabel.Size = UDim2.fromOffset(290, 34)
	rainLabel.BackgroundColor3 = Color3.fromRGB(20, 45, 70)
	rainLabel.BackgroundTransparency = 0.2
	rainLabel.TextColor3 = Color3.fromRGB(150, 230, 255)
	rainLabel.TextScaled = true
	rainLabel.Font = Enum.Font.GothamBold
	rainLabel.Visible = false
	rainLabel.Parent = root
	Ui.corner(rainLabel, 10)
	Ui.padding(rainLabel, 6)

	-- Avisos cortos: bajo el anuncio, se apilan hacia abajo
	notificationList = Instance.new("Frame")
	notificationList.Name = "Notifications"
	notificationList.AnchorPoint = Vector2.new(0.5, 0)
	notificationList.Position = UDim2.new(0.5, 0, 0, 70)
	notificationList.Size = UDim2.fromOffset(460, 200)
	notificationList.BackgroundTransparency = 1
	notificationList.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = notificationList

	gui.Parent = player:WaitForChild("PlayerGui")
end

-- Número que sube desde el contador de dinero y se desvanece ("+$120")
local function showMoneyChange(difference: number)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(1, 8, 0, 0)
	label.Size = UDim2.fromOffset(150, 30)
	label.Text = (if difference > 0 then "+" else "-") .. Format.money(math.abs(difference))
	label.TextColor3 = if difference > 0 then Ui.Colors.Money else Color3.fromRGB(255, 120, 120)
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = Enum.Font.FredokaOne
	label.TextStrokeTransparency = 0.5
	label.Parent = moneyFrame

	local tween = TweenService:Create(label, TweenInfo.new(1), {
		Position = UDim2.new(1, 8, 0, -36),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	tween:Play()
	tween.Completed:Once(function()
		label:Destroy()
	end)
end

-- El dinero se lee del marcador que crea el servidor (leaderstats)
local function watchMoney()
	local leaderstats = player:WaitForChild("leaderstats")
	local money = leaderstats:WaitForChild("Dinero") :: IntValue

	local function update()
		local value = money.Value
		moneyLabel.Text = Format.money(value)
		if lastMoney and value ~= lastMoney then
			showMoneyChange(value - lastMoney)
			-- Pequeño "salto" del contador
			moneyFrame.Size = UDim2.fromOffset(226, 56)
			TweenService:Create(moneyFrame, TweenInfo.new(0.25), { Size = UDim2.fromOffset(210, 52) }):Play()
		end
		lastMoney = value
	end
	money.Changed:Connect(update)
	update()
end

-- Muestra un aviso durante unos segundos
function HudController.notify(text: string, kind: string?)
	if text == "" then
		return
	end
	notificationCount += 1

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromOffset(460, 34)
	label.LayoutOrder = notificationCount
	label.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	label.BackgroundTransparency = 0.3
	label.Text = text
	label.TextColor3 = NOTIFICATION_COLORS[kind or "info"] or NOTIFICATION_COLORS.info
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = notificationList
	Ui.corner(label, 10)
	Ui.padding(label, 6)

	task.delay(NOTIFICATION_DURATION, function()
		local fade = TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 })
		fade:Play()
		fade.Completed:Wait()
		label:Destroy()
	end)
end

-- Aviso grande, el mismo para todo el servidor
function HudController.announce(text: string, color: Color3)
	announceToken += 1
	local token = announceToken
	announceLabel.Text = text
	announceLabel.TextColor3 = color
	announceLabel.Visible = true
	task.delay(ANNOUNCE_DURATION, function()
		-- Si llegó otro anuncio mientras tanto, ese decide cuándo ocultarse
		if announceToken == token then
			announceLabel.Visible = false
		end
	end)
end

-- Consejo fijo (nil para quitarlo)
function HudController.setHint(text: string?)
	hintLabel.Visible = text ~= nil
	if text then
		hintLabel.Text = text
	end
end

-- fraction: energía de 0 (vacía) a 1 (llena). exhausted: true si se agotó y aún no puede correr.
function HudController.setStamina(fraction: number, exhausted: boolean)
	if not staminaFill then
		return
	end
	fraction = math.clamp(fraction, 0, 1)
	staminaFill.Size = UDim2.fromScale(fraction, 1)
	staminaFill.BackgroundColor3 = if exhausted then Color3.fromRGB(255, 110, 110) else Color3.fromRGB(90, 200, 255)
	staminaFrame.Visible = fraction < 1
end

function HudController.getRoot(): Frame
	return root
end

function HudController.addMenuButton(text: string, color: Color3, onClick: () -> ()): TextButton
	local button = Ui.button(menuButtons, text, color, onClick)
	button.Size = UDim2.fromOffset(170, 36)
	button.LayoutOrder = #menuButtons:GetChildren()
	return button
end

-- Hora del servidor. Sirve para cuentas atrás que deben coincidir en todos los jugadores.
function HudController.getServerTime(): number
	return Workspace:GetServerTimeNow()
end

function HudController.start()
	if started then
		return
	end
	started = true

	buildGui()
	task.spawn(watchMoney)

	Remotes.get("Notify").OnClientEvent:Connect(function(text, kind)
		if type(text) == "string" then
			HudController.notify(text, if type(kind) == "string" then kind else nil)
		end
	end)
	Remotes.get("Announce").OnClientEvent:Connect(function(text, color)
		if type(text) == "string" then
			HudController.announce(text, if typeof(color) == "Color3" then color else Color3.new(1, 1, 1))
		end
	end)

	-- Cuenta atrás de la tormenta de mutaciones
	task.spawn(function()
		while true do
			local endsAt = Workspace:GetAttribute("MutationRainEndsAt")
			local remaining = if type(endsAt) == "number" then endsAt - Workspace:GetServerTimeNow() else 0
			rainLabel.Visible = remaining > 0
			if remaining > 0 then
				rainLabel.Text = `Tormenta de mutaciones {Format.time(remaining)}`
			end
			task.wait(0.5)
		end
	end)
end

return HudController
