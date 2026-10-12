-- NPC coco heladero, dueño de la heladería. Por ahora explica de qué trata el juego;
-- la venta de helados y el bono diario se añaden más adelante.
--
-- PLACEHOLDER: avatar básico marrón con la cabeza grande. Para usar un modelo propio,
-- cambia buildNpc para que clone tu modelo (necesita PrimaryPart y una pieza "Head").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config").GameConfig)
local MapBuilder = require(script.Parent.Parent.World.MapBuilder)

local COCONUT_COLOR = Color3.fromRGB(120, 75, 45)
local SHIRT_COLOR = Color3.fromRGB(95, 125, 85)
local PANTS_COLOR = Color3.fromRGB(60, 80, 130)
local LINE_DURATION = 4.5 -- segundos que se muestra cada frase

-- Frases de la explicación. {name} se cambia por el nombre del jugador.
local DIALOGUE = {
	"¡Hola, {name}! Soy {npc}, el dueño de esta heladería.",
	"De la cueva salen frutas por la banda. ¡Compra las que más te gusten!",
	"Ponlas en tu base y te darán dinero cada segundo.",
	"Sube una fruta al congelador del piso 2 y se convertirá en helado. ¡Vale mucho más!",
	"Tráeme tus helados y te los compro a buen precio.",
	"Pero cuidado: otros jugadores pueden robarte. ¡Bloquea tu puerta con la placa roja!",
}

local CoconutService = {}

local started = false

local function buildNpc(): Model
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = COCONUT_COLOR
	description.LeftArmColor = COCONUT_COLOR
	description.RightArmColor = COCONUT_COLOR
	description.TorsoColor = SHIRT_COLOR
	description.LeftLegColor = PANTS_COLOR
	description.RightLegColor = PANTS_COLOR
	description.HeadScale = 1.4

	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)

	if ok and result then
		local rig = result :: Model
		local humanoid = rig:FindFirstChildOfClass("Humanoid")
		local root = rig:FindFirstChild("HumanoidRootPart")
		if humanoid and root and root:IsA("BasePart") then
			humanoid.DisplayName = GameConfig.CoconutNpcName
			humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			root.Anchored = true
			rig.PrimaryPart = root
			rig:SetAttribute("FootOffset", humanoid.HipHeight + root.Size.Y / 2)
			return rig
		end
		rig:Destroy()
	else
		warn(`[CoconutService] No se pudo crear el avatar del coco: {result}`)
	end

	-- Modelo de emergencia: una bola marrón
	local model = Instance.new("Model")
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(5, 5, 5)
	head.Color = COCONUT_COLOR
	head.Anchored = true
	head.Parent = model
	model.PrimaryPart = head
	model:SetAttribute("FootOffset", 2.5)
	return model
end

local function buildSpeechBubble(npc: Model): (BillboardGui, TextLabel)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Speech"
	gui.Size = UDim2.fromScale(18, 5)
	gui.StudsOffset = Vector3.new(0, 5.5, 0)
	gui.MaxDistance = 80
	gui.Enabled = false
	gui.Adornee = (npc:FindFirstChild("Head") or npc.PrimaryPart) :: any

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.new(1, 1, 1)
	label.TextColor3 = Color3.fromRGB(40, 30, 20)
	label.TextScaled = true
	label.TextWrapped = true
	label.Font = Enum.Font.FredokaOne
	label.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.2, 0)
	corner.Parent = label

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.PaddingTop = UDim.new(0.08, 0)
	padding.PaddingBottom = UDim.new(0.08, 0)
	padding.Parent = label

	gui.Parent = npc
	return gui, label
end

function CoconutService.start(map: MapBuilder.MapInfo)
	if started then
		return
	end
	started = true

	local npc = buildNpc()
	npc.Name = GameConfig.CoconutNpcName
	local footOffset = npc:GetAttribute("FootOffset") or 0
	npc:PivotTo(map.coconutSpot * CFrame.new(0, footOffset, 0))
	npc.Parent = map.folder

	local bubble, label = buildSpeechBubble(npc)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Hablar"
	prompt.ObjectText = GameConfig.CoconutNpcName
	prompt.HoldDuration = 0
	-- Está detrás del mostrador: hace falta alcance y no exigir visión directa
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Parent = npc.PrimaryPart

	local talking = false
	prompt.Triggered:Connect(function(player)
		if talking then
			return
		end
		talking = true
		prompt.Enabled = false

		bubble.Enabled = true
		for _, line in DIALOGUE do
			line = string.gsub(line, "{name}", player.DisplayName)
			line = string.gsub(line, "{npc}", GameConfig.CoconutNpcName)
			label.Text = line
			task.wait(LINE_DURATION)
		end
		bubble.Enabled = false

		prompt.Enabled = true
		talking = false
	end)
end

return CoconutService
