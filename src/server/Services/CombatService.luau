-- Vida de los jugadores y espada por defecto. El daño se calcula en el servidor:
-- el cliente solo avisa de que hizo clic con la espada equipada.
--
--   CombatService.PlayerHit -> aviso (atacante, víctima) cada vez que un golpe acierta
--
-- PLACEHOLDER: la espada son tres piezas básicas. Para usar un modelo propio, cambia buildSword
-- (necesita una pieza llamada "Handle").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config").GameConfig)

local SWORD_NAME = "Espada"
-- Animación de golpe con herramienta por defecto de Roblox para avatares R15
local SLASH_ANIMATION_ID = "rbxassetid://522635514"

local CombatService = {}

local started = false
local swordTemplate: Tool? = nil
local lastAttack: { [Player]: number } = {}

local hitEvent = Instance.new("BindableEvent")
CombatService.PlayerHit = hitEvent.Event -- (atacante: Player, víctima: Player)

local function makeSwordPart(name: string, size: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function weld(part: Part, handle: Part, offset: CFrame, tool: Tool)
	part.CFrame = handle.CFrame * offset
	local constraint = Instance.new("WeldConstraint")
	constraint.Part0 = handle
	constraint.Part1 = part
	constraint.Parent = part
	part.Parent = tool
end

local function buildSword(): Tool
	local tool = Instance.new("Tool")
	tool.Name = SWORD_NAME
	tool.ToolTip = `Espada ({GameConfig.SwordDamage} de daño)`
	tool.CanBeDropped = false
	tool.RequiresHandle = true

	local handle = makeSwordPart("Handle", Vector3.new(0.3, 1.2, 0.3), Color3.fromRGB(110, 70, 40), Enum.Material.Wood)
	handle.Parent = tool

	local guard = makeSwordPart("Guard", Vector3.new(0.3, 0.25, 1.4), Color3.fromRGB(230, 190, 60), Enum.Material.Metal)
	weld(guard, handle, CFrame.new(0, 0.7, 0), tool)

	local blade = makeSwordPart("Blade", Vector3.new(0.15, 3.6, 0.6), Color3.fromRGB(210, 215, 225), Enum.Material.Metal)
	weld(blade, handle, CFrame.new(0, 2.6, 0), tool)

	return tool
end

local function playSlash(humanoid: Humanoid)
	pcall(function()
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			return
		end
		local animation = Instance.new("Animation")
		animation.AnimationId = SLASH_ANIMATION_ID
		animator:LoadAnimation(animation):Play()
	end)
end

-- Golpea a los jugadores que estén cerca y delante del atacante
local function attack(player: Player, tool: Tool)
	local character = player.Character
	if not character or tool.Parent ~= character then
		return -- la espada debe estar equipada
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return
	end

	local now = os.clock()
	if now - (lastAttack[player] or 0) < GameConfig.SwordCooldown then
		return
	end
	lastAttack[player] = now

	playSlash(humanoid)

	for _, other in Players:GetPlayers() do
		if other == player then
			continue
		end
		local otherCharacter = other.Character
		local otherHumanoid = otherCharacter and otherCharacter:FindFirstChildOfClass("Humanoid")
		local otherRoot = otherCharacter and otherCharacter:FindFirstChild("HumanoidRootPart")
		if not otherHumanoid or otherHumanoid.Health <= 0 or not otherRoot or not otherRoot:IsA("BasePart") then
			continue
		end

		local offset = otherRoot.Position - root.Position
		local distance = offset.Magnitude
		if distance > GameConfig.SwordRange then
			continue
		end
		-- Muy pegados cuenta siempre; si no, la víctima debe estar delante
		if distance > 2 and offset.Unit:Dot(root.CFrame.LookVector) < 0.3 then
			continue
		end

		otherHumanoid:TakeDamage(GameConfig.SwordDamage)
		hitEvent:Fire(player, other)
	end
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.MaxHealth = GameConfig.PlayerMaxHealth
		humanoid.Health = GameConfig.PlayerMaxHealth
	end

	-- La mochila se vacía al reaparecer: se entrega una espada nueva cada vez
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack or backpack:FindFirstChild(SWORD_NAME) or character:FindFirstChild(SWORD_NAME) then
		return
	end
	if not swordTemplate then
		swordTemplate = buildSword()
	end
	local sword = (swordTemplate :: Tool):Clone()
	sword.Activated:Connect(function()
		attack(player, sword)
	end)
	sword.Parent = backpack
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

function CombatService.start()
	if started then
		return
	end
	started = true

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		lastAttack[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return CombatService
