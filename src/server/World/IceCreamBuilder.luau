-- Crea el modelo visible de un helado: un cono con dos bolas del color de la fruta.
--
-- PLACEHOLDER: son piezas básicas. Para usar un modelo propio, cambia buildShape para que
-- clone tu modelo (necesita PrimaryPart y el atributo FootOffset con la altura de su centro).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CharacterConfig = require(Shared.Config.CharacterConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Mutations = require(Shared.Config.Mutations)
local Rarities = require(Shared.Config.Rarities)
local Format = require(Shared.Util.Format)
local InfoBillboard = require(script.Parent.InfoBillboard)

local CONE_COLOR = Color3.fromRGB(215, 165, 100)

local IceCreamBuilder = {}

local function makePiece(model: Model, name: string, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

-- Cilindro de pie. Los cilindros de Roblox van tumbados (a lo largo de X), así que se giran.
local function makeCylinder(model: Model, name: string, diameter: number, height: number, centerY: number, color: Color3)
	local part = makePiece(model, name, color, Enum.Material.SmoothPlastic)
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(height, diameter, diameter)
	part.CFrame = CFrame.new(0, centerY, 0) * CFrame.Angles(0, 0, math.pi / 2)
end

local function makeScoop(model: Model, name: string, diameter: number, centerY: number, color: Color3, material: Enum.Material): Part
	local part = makePiece(model, name, color, material)
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(diameter, diameter, diameter)
	part.CFrame = CFrame.new(0, centerY, 0)
	return part
end

-- Las alturas se miden desde el suelo (y = 0)
local function buildShape(flavorColor: Color3, mutation: Mutations.Mutation?): Model
	local model = Instance.new("Model")

	-- Pieza invisible en la base: sirve de punto de referencia para colocar el helado
	local root = makePiece(model, "Root", Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	root.Size = Vector3.new(1, 1, 1)
	root.Transparency = 1
	root.CanQuery = false
	root.CFrame = CFrame.new(0, 0.5, 0)
	model.PrimaryPart = root
	model:SetAttribute("FootOffset", 0.5)

	makeCylinder(model, "ConeBottom", 1.1, 1.4, 0.7, CONE_COLOR)
	makeCylinder(model, "ConeTop", 1.9, 1, 1.9, CONE_COLOR)

	-- Con mutación, las bolas toman su color y material
	local scoopColor = if mutation then mutation.color else flavorColor
	local scoopMaterial = if mutation then mutation.material else Enum.Material.SmoothPlastic
	local bottom = makeScoop(model, "ScoopBottom", 2.6, 3.3, scoopColor, scoopMaterial)
	local top = makeScoop(model, "ScoopTop", 2, 4.9, scoopColor:Lerp(Color3.new(1, 1, 1), 0.3), scoopMaterial)
	-- El cliente va cambiando el color de las piezas con esta etiqueta (RainbowController)
	if mutation and mutation.id == "Rainbow" then
		bottom:AddTag("RainbowPart")
		top:AddTag("RainbowPart")
	end

	if mutation then
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
		emitter.Parent = top
	end

	return model
end

-- Dinero por segundo que da el helado de un personaje, con su mutación (sin contar rebirths)
function IceCreamBuilder.getIncome(characterId: string, mutationId: string?): number
	local character = CharacterConfig.ById[characterId]
	return character.incomePerSecond * Mutations.getMultiplier(mutationId) * GameConfig.IceCreamIncomeMultiplier
end

-- Crea un helado listo para colocar en el mundo (todavía sin Parent)
function IceCreamBuilder.create(characterId: string, mutationId: string?): Model
	local character = CharacterConfig.ById[characterId]
	assert(character, `Personaje desconocido: {characterId}`)
	local mutation = if mutationId then Mutations.ById[mutationId] else nil
	local rarity = Rarities.ById[character.rarity]

	local model = buildShape(character.skinColor, mutation)
	model.Name = `Helado{character.id}`
	model:SetAttribute("CharacterId", character.id)
	model:SetAttribute("Mutation", mutationId)

	local lines: { InfoBillboard.Line } = {}
	table.insert(lines, { text = `Helado de {character.flavor}`, color = Color3.new(1, 1, 1) })
	table.insert(lines, { text = rarity.name, color = rarity.color })
	table.insert(lines, {
		text = Format.money(IceCreamBuilder.getIncome(characterId, mutationId)) .. "/s",
		color = Color3.fromRGB(255, 225, 90),
	})
	table.insert(lines, { text = Format.money(0), color = Color3.fromRGB(120, 255, 130), name = "Pending" })

	-- El cartel flota sobre la bola de arriba
	InfoBillboard.create(model, model:FindFirstChild("ScoopTop"), lines, 1.5)
	-- La mutación va en una etiqueta al costado
	if mutation then
		InfoBillboard.addMutationBadge(model, model:FindFirstChild("ScoopBottom"), mutation.name, mutation.multiplier, mutation.color)
	end
	return model
end

return IceCreamBuilder
