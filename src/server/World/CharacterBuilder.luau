-- Crea el modelo visible de un personaje (fruta o verdura con cuerpo humano).
--
-- PLACEHOLDER: ahora es un avatar básico de Roblox con la piel del color de la fruta.
-- Para usar modelos propios, cambia buildRig para que clone tu modelo según character.id
-- (debe tener PrimaryPart y, si puede ser, una pieza llamada "Head" para el cartel).

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CharacterConfig = require(Shared.Config.CharacterConfig)
local Mutations = require(Shared.Config.Mutations)
local Rarities = require(Shared.Config.Rarities)
local Format = require(Shared.Util.Format)
local InfoBillboard = require(script.Parent.InfoBillboard)

local COLLISION_GROUP = "FruitNPC"
local SHIRT_COLOR = Color3.fromRGB(240, 240, 240)
local PANTS_COLOR = Color3.fromRGB(60, 80, 130)
local FROZEN_COLOR = Color3.fromRGB(170, 225, 255)
local RAINBOW_MUTATION_ID = "Rainbow"
local RAINBOW_TAG = "RainbowPart"
-- Distancia de la cabeza al borde inferior del cartel
local INFO_BOTTOM_OFFSET = 1.75

local CharacterBuilder = {}

local templates: { [string]: Model } = {}
local building: { [string]: boolean } = {}

-- Los personajes no chocan con los jugadores ni entre ellos.
-- playerGroups: grupos de colisión extra que usan los personajes de los jugadores.
function CharacterBuilder.init(playerGroups: { string })
	if not PhysicsService:IsCollisionGroupRegistered(COLLISION_GROUP) then
		PhysicsService:RegisterCollisionGroup(COLLISION_GROUP)
	end
	PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUP, "Default", false)
	PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUP, COLLISION_GROUP, false)
	for _, group in playerGroups do
		PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUP, group, false)
	end
end

local function prepareParts(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = COLLISION_GROUP
			descendant.CanCollide = false
			descendant.CanTouch = false
		elseif descendant:IsA("LuaSourceContainer") then
			-- Los scripts de animación y vida del avatar no hacen falta
			descendant:Destroy()
		end
	end
end

-- Avatar R15 con los colores del personaje. Devuelve nil si Roblox no pudo crearlo.
local function buildRig(character: CharacterConfig.Character): Model?
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = character.skinColor
	description.LeftArmColor = character.skinColor
	description.RightArmColor = character.skinColor
	description.TorsoColor = SHIRT_COLOR
	description.LeftLegColor = PANTS_COLOR
	description.RightLegColor = PANTS_COLOR
	if character.fruitHead then
		-- Cabeza grande mientras no haya un modelo de cabeza de fruta
		description.HeadScale = 1.5
	end

	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not result then
		warn(`[CharacterBuilder] No se pudo crear el avatar de {character.id}: {result}`)
		return nil
	end

	local rig = result :: Model
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	local root = rig:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		rig:Destroy()
		return nil
	end

	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	-- Son estatuas: sin esto el Humanoid gasta rendimiento calculando físicas
	pcall(function()
		(humanoid :: any).EvaluateStateMachine = false
	end)

	root.Anchored = true
	rig.PrimaryPart = root
	rig:SetAttribute("FootOffset", humanoid.HipHeight + root.Size.Y / 2)
	return rig
end

-- Modelo de emergencia con dos piezas, por si falla la creación del avatar
local function buildFallback(character: CharacterConfig.Character): Model
	local model = Instance.new("Model")

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(2.5, 4, 1.5)
	body.Color = character.skinColor
	body.Anchored = true
	body.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(2.5, 2.5, 2.5)
	head.Color = character.skinColor
	head.Anchored = true
	head.CFrame = body.CFrame * CFrame.new(0, 3.25, 0)
	head.Parent = model

	model.PrimaryPart = body
	model:SetAttribute("FootOffset", 2)
	return model
end

-- Plantilla de un personaje: se construye una sola vez y después se clona
local function getTemplate(character: CharacterConfig.Character): Model
	while building[character.id] do
		task.wait()
	end
	local template = templates[character.id]
	if template then
		return template
	end

	building[character.id] = true
	local model = buildRig(character) or buildFallback(character)
	model.Name = character.id
	prepareParts(model)
	templates[character.id] = model
	building[character.id] = nil
	return model
end

-- Construye todas las plantillas en segundo plano para que no haya esperas al aparecer
function CharacterBuilder.preload()
	for _, character in CharacterConfig.List do
		task.spawn(getTemplate, character)
	end
end

local function applyMutation(model: Model, mutation: Mutations.Mutation)
	-- Si se queda, vuelve a pintar el avatar con sus colores originales
	local bodyColors = model:FindFirstChildOfClass("BodyColors")
	if bodyColors then
		bodyColors:Destroy()
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= model.PrimaryPart then
			descendant.Color = mutation.color
			descendant.Material = mutation.material
			-- El cliente va cambiando el color de las piezas con esta etiqueta (RainbowController)
			if mutation.id == RAINBOW_MUTATION_ID then
				descendant:AddTag(RAINBOW_TAG)
			end
		end
	end

	-- Partículas del color de la mutación (REEMPLAZAR por un efecto propio de cada una)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "MutationEffect"
	emitter.Color = ColorSequence.new(mutation.color)
	emitter.LightEmission = 0.6
	emitter.Size = NumberSequence.new(0.4)
	emitter.Lifetime = NumberRange.new(1, 1.5)
	emitter.Speed = NumberRange.new(1, 2)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 6
	emitter.Parent = model.PrimaryPart
end

-- Cartel sobre la cabeza con mutación, nombre, rareza e ingreso.
-- En la banda muestra además el precio; en una base, el dinero acumulado (etiqueta "Pending").
local function addInfo(model: Model, character: CharacterConfig.Character, mutation: Mutations.Mutation?, onConveyor: boolean)
	local rarity = Rarities.ById[character.rarity]
	local multiplier = if mutation then mutation.multiplier else 1

	local lines: { InfoBillboard.Line } = {}
	if mutation then
		table.insert(lines, { text = mutation.name, color = mutation.color })
	end
	table.insert(lines, { text = character.name, color = Color3.new(1, 1, 1) })
	table.insert(lines, { text = rarity.name, color = rarity.color })
	table.insert(lines, {
		text = Format.money(character.incomePerSecond * multiplier) .. "/s",
		color = Color3.fromRGB(255, 225, 90),
	})
	if onConveyor then
		table.insert(lines, {
			text = Format.money(math.floor(character.price * multiplier)),
			color = Color3.fromRGB(120, 255, 130),
		})
	else
		table.insert(lines, { text = Format.money(0), color = Color3.fromRGB(120, 255, 130), name = "Pending" })
	end

	InfoBillboard.create(model, CharacterBuilder.getHead(model), lines, INFO_BOTTOM_OFFSET)
end

-- Pieza sobre la que flotan los carteles de un personaje
function CharacterBuilder.getHead(model: Model): Instance?
	return model:FindFirstChild("Head") or model.PrimaryPart
end

-- Crea el modelo de un personaje sin cartel (todavía sin Parent)
function CharacterBuilder.createBare(characterId: string, mutationId: string?): Model
	local character = CharacterConfig.ById[characterId]
	assert(character, `Personaje desconocido: {characterId}`)
	local mutation = if mutationId then Mutations.ById[mutationId] else nil

	local model = getTemplate(character):Clone()
	model:SetAttribute("CharacterId", character.id)
	model:SetAttribute("Mutation", mutationId)

	if mutation then
		applyMutation(model, mutation)
	end
	return model
end

-- Crea un ejemplar con su cartel, listo para colocar en el mundo (todavía sin Parent).
-- onConveyor: true para la banda (muestra precio), false para una base (muestra lo acumulado)
function CharacterBuilder.create(characterId: string, mutationId: string?, onConveyor: boolean): Model
	local model = CharacterBuilder.createBare(characterId, mutationId)
	local mutation = if mutationId then Mutations.ById[mutationId] else nil
	addInfo(model, CharacterConfig.ById[characterId], mutation, onConveyor)
	return model
end

-- Pone una mutación a un personaje que ya está en el mundo y rehace su cartel.
-- Pensado para personajes sin mutación (los que alcanza un rayo en la banda).
function CharacterBuilder.setMutation(model: Model, mutationId: string, onConveyor: boolean)
	local character = CharacterConfig.ById[model:GetAttribute("CharacterId")]
	local mutation = Mutations.ById[mutationId]
	if not character or not mutation then
		return
	end
	applyMutation(model, mutation)
	model:SetAttribute("Mutation", mutationId)
	local info = model:FindFirstChild("Info")
	if info then
		info:Destroy()
	end
	addInfo(model, character, mutation, onConveyor)
end

-- Aspecto de congelado: todo el cuerpo de hielo, con el color original apagado hacia azul
function CharacterBuilder.applyFrozen(model: Model)
	local bodyColors = model:FindFirstChildOfClass("BodyColors")
	if bodyColors then
		bodyColors:Destroy()
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= model.PrimaryPart then
			descendant:RemoveTag(RAINBOW_TAG) -- congelado no cambia de color
			descendant.Color = descendant.Color:Lerp(FROZEN_COLOR, 0.6)
			descendant.Material = Enum.Material.Ice
		end
	end
end

-- Animación de caminar por defecto de Roblox para avatares R15
local WALK_ANIMATION_ID = "rbxassetid://507777826"

-- Pone al personaje a caminar en el sitio. Devuelve la animación para poder pararla,
-- o nil si el modelo no es un avatar o la animación no cargó.
function CharacterBuilder.playWalk(model: Model): AnimationTrack?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local ok, track = pcall(function()
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end
		local animation = Instance.new("Animation")
		animation.AnimationId = WALK_ANIMATION_ID
		local loaded = (animator :: Animator):LoadAnimation(animation)
		loaded.Looped = true
		loaded:Play()
		return loaded
	end)
	return if ok then track else nil
end

-- Coloca el modelo con los pies en el punto indicado
function CharacterBuilder.placeAt(model: Model, feet: CFrame)
	local footOffset = model:GetAttribute("FootOffset") or 0
	model:PivotTo(feet * CFrame.new(0, footOffset, 0))
end

return CharacterBuilder
