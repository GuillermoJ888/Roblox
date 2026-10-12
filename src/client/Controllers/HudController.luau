-- Interfaz fija del jugador: dinero, barra de energía y avisos.
-- Se construye por código y se adapta al tamaño de la pantalla (PC, tablet y teléfono).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)

local NOTIFICATION_DURATION = 3
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

local moneyLabel: TextLabel
local staminaFrame: Frame
local staminaFill: Frame
local notificationList: Frame

local function addCorner(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function buildGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "HUD"
	gui.ResetOnSpawn = false

	-- Todo cuelga de un marco con escala: en pantallas pequeñas la interfaz encoge entera
	local root = Instance.new("Frame")
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
	local moneyFrame = Instance.new("Frame")
	moneyFrame.Name = "Money"
	moneyFrame.AnchorPoint = Vector2.new(0, 0.5)
	moneyFrame.Position = UDim2.new(0, 14, 0.4, 0)
	moneyFrame.Size = UDim2.fromOffset(210, 52)
	moneyFrame.BackgroundColor3 = Color3.fromRGB(20, 30, 20)
	moneyFrame.BackgroundTransparency = 0.25
	moneyFrame.Parent = root
	addCorner(moneyFrame, 14)

	moneyLabel = Instance.new("TextLabel")
	moneyLabel.BackgroundTransparency = 1
	moneyLabel.Position = UDim2.fromOffset(12, 6)
	moneyLabel.Size = UDim2.new(1, -24, 1, -12)
	moneyLabel.Text = "$..."
	moneyLabel.TextColor3 = Color3.fromRGB(120, 255, 140)
	moneyLabel.TextScaled = true
	moneyLabel.TextXAlignment = Enum.TextXAlignment.Left
	moneyLabel.Font = Enum.Font.FredokaOne
	moneyLabel.Parent = moneyFrame

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
	addCorner(staminaFrame, 8)

	staminaFill = Instance.new("Frame")
	staminaFill.Name = "Fill"
	staminaFill.Size = UDim2.fromScale(1, 1)
	staminaFill.BackgroundColor3 = Color3.fromRGB(90, 200, 255)
	staminaFill.BorderSizePixel = 0
	staminaFill.Parent = staminaFrame
	addCorner(staminaFill, 8)

	-- Avisos: arriba en el centro, se apilan hacia abajo
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

-- El dinero se lee del marcador que crea el servidor (leaderstats)
local function watchMoney()
	local leaderstats = player:WaitForChild("leaderstats")
	local money = leaderstats:WaitForChild("Dinero") :: IntValue

	local function update()
		moneyLabel.Text = Format.money(money.Value)
	end
	money.Changed:Connect(update)
	update()
end

local notificationCount = 0

-- Muestra un aviso durante unos segundos
function HudController.notify(text: string, kind: string?)
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
	addCorner(label, 10)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 5)
	padding.PaddingBottom = UDim.new(0, 5)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = label

	task.delay(NOTIFICATION_DURATION, function()
		local fade = TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 })
		fade:Play()
		fade.Completed:Wait()
		label:Destroy()
	end)
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
end

return HudController
