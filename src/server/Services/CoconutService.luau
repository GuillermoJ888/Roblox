-- NPC coco heladero, dueño de la heladería. Al hablarle se abre su menú (ShopService).
--
--   CoconutService.onInteract(función)  -> se llama con el jugador que le habla
--   CoconutService.isNear(player)       -> true si el jugador está lo bastante cerca para usar el menú
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

local CoconutService = {}

local started = false
local npcPosition: Vector3? = nil
local interactCallbacks: { (Player) -> () } = {}

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

-- Registra una función que se llama cuando un jugador le habla al coco
function CoconutService.onInteract(callback: (Player) -> ())
	table.insert(interactCallbacks, callback)
end

-- El menú solo funciona cerca del coco: así no se puede vender desde cualquier parte del mapa
function CoconutService.isNear(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not npcPosition or not root or not root:IsA("BasePart") then
		return false
	end
	return (root.Position - npcPosition).Magnitude <= GameConfig.ShopDistance
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
	npcPosition = map.coconutSpot.Position

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Hablar"
	prompt.ObjectText = GameConfig.CoconutNpcName
	prompt.HoldDuration = 0
	-- Está detrás del mostrador: hace falta alcance y no exigir visión directa
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Parent = npc.PrimaryPart

	prompt.Triggered:Connect(function(player)
		for _, callback in interactCallbacks do
			task.spawn(callback, player)
		end
	end)
end

return CoconutService
