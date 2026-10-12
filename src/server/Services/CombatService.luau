-- Vida de los jugadores, armas y mejoras compradas. El daño se calcula en el servidor:
-- el cliente solo avisa de que hizo clic con el arma equipada.
--
--   CombatService.refresh(player)  -> entrega las armas que le falten y aplica sus mejoras
--   CombatService.PlayerHit        -> aviso (atacante, víctima) cada vez que un golpe acierta
--
-- PLACEHOLDER: las armas son tres piezas básicas. Para usar modelos propios, cambia buildWeapon
-- (el modelo necesita una pieza llamada "Handle").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local PassConfig = require(Shared.Config.PassConfig)
local ToolConfig = require(Shared.Config.ToolConfig)

local DataService = require(script.Parent.DataService)
local PassService = require(script.Parent.PassService)

-- Animación de golpe con herramienta por defecto de Roblox para avatares R15
local SLASH_ANIMATION_ID = "rbxassetid://522635514"

local CombatService = {}

local started = false
local templates: { [string]: Tool } = {}
local lastAttack: { [Player]: number } = {}

local hitEvent = Instance.new("BindableEvent")
CombatService.PlayerHit = hitEvent.Event -- (atacante: Player, víctima: Player)

local function makePiece(name: string, size: Vector3, color: Color3, material: Enum.Material): Part
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

local function buildWeapon(definition: ToolConfig.Tool): Tool
	local tool = Instance.new("Tool")
	tool.Name = definition.name
	tool.ToolTip = `{definition.name} ({definition.damage} de daño)`
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("ToolId", definition.id)

	local handle = makePiece("Handle", Vector3.new(0.3, 1.2, 0.3), Color3.fromRGB(110, 70, 40), Enum.Material.Wood)
	handle.Parent = tool

	local guard = makePiece("Guard", Vector3.new(0.3, 0.25, 1.4), Color3.fromRGB(230, 190, 60), Enum.Material.Metal)
	weld(guard, handle, CFrame.new(0, 0.7, 0), tool)

	local bladeColor = definition.bladeColor or Color3.fromRGB(210, 215, 225)
	local bladeMaterial = definition.bladeMaterial or Enum.Material.Metal
	-- Las armas más fuertes tienen la hoja más ancha, para distinguirlas de un vistazo
	local width = 0.6 + ((definition.damage or 20) - 20) / 40
	local blade = makePiece("Blade", Vector3.new(0.15 + width / 6, 3.6, width), bladeColor, bladeMaterial)
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
local function attack(player: Player, tool: Tool, definition: ToolConfig.Tool)
	local character = player.Character
	if not character or tool.Parent ~= character then
		return -- el arma debe estar equipada
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return
	end

	-- La espera es por jugador, no por arma: cambiar de arma no permite golpear más rápido
	local now = os.clock()
	if now - (lastAttack[player] or 0) < (definition.cooldown or GameConfig.SwordCooldown) then
		return
	end
	lastAttack[player] = now

	playSlash(humanoid)

	local range = definition.range or GameConfig.SwordRange
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
		if distance > range then
			continue
		end
		-- Muy pegados cuenta siempre; si no, la víctima debe estar delante
		if distance > 2 and offset.Unit:Dot(root.CFrame.LookVector) < 0.3 then
			continue
		end

		otherHumanoid:TakeDamage(definition.damage or GameConfig.SwordDamage)
		hitEvent:Fire(player, other)
	end
end

local function ownsTool(data: DataService.PlayerData?, definition: ToolConfig.Tool): boolean
	if definition.id == ToolConfig.DefaultWeaponId then
		return true
	end
	return data ~= nil and data.tools[definition.id] == true
end

local function hasWeapon(player: Player, definition: ToolConfig.Tool): boolean
	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character
	return (backpack ~= nil and backpack:FindFirstChild(definition.name) ~= nil)
		or (character ~= nil and character:FindFirstChild(definition.name) ~= nil)
end

-- Entrega las armas que el jugador tiene compradas y aún no lleva, y aplica sus mejoras.
-- Se llama al aparecer y después de comprar algo en la tienda.
function CombatService.refresh(player: Player)
	local data = DataService.getData(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	-- Mejor valor de cada mejora de movimiento, entre lo comprado con dinero y los pases de Robux
	local upgrades: { [string]: number } = {}

	for _, definition in ToolConfig.List do
		local owned = ownsTool(data, definition)
		if definition.kind == "Upgrade" then
			if definition.attribute then
				local best = upgrades[definition.attribute] or 0
				upgrades[definition.attribute] = if owned then math.max(best, definition.value or 0) else best
			end
		elseif owned and backpack and player.Character and not hasWeapon(player, definition) then
			local template = templates[definition.id]
			if not template then
				template = buildWeapon(definition)
				templates[definition.id] = template
			end
			local weapon = template:Clone()
			weapon.Activated:Connect(function()
				attack(player, weapon, definition)
			end)
			weapon.Parent = backpack
		end
	end

	for _, pass in PassConfig.List do
		if pass.attribute then
			local best = upgrades[pass.attribute] or 0
			upgrades[pass.attribute] = if PassService.owns(player, pass.id) then math.max(best, pass.value or 0) else best
		end
	end
	for attribute, value in upgrades do
		player:SetAttribute(attribute, if value > 0 then value else nil)
	end
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.MaxHealth = GameConfig.PlayerMaxHealth
		humanoid.Health = GameConfig.PlayerMaxHealth
	end

	-- La mochila se vacía al reaparecer: se entregan las armas de nuevo cada vez.
	-- Primero el arma gratis, sin esperar a los datos; después las compradas.
	CombatService.refresh(player)
	if not DataService.getData(player) and DataService.waitForData(player) and player.Character == character then
		CombatService.refresh(player)
	end
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
	-- Las mejoras dependen de los datos: se aplican en cuanto cargan
	DataService.PlayerLoaded:Connect(function(player)
		CombatService.refresh(player)
	end)
	-- Al comprar un pase de mejora, se aplica al momento
	PassService.onChanged(function(player)
		CombatService.refresh(player)
	end)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return CombatService
