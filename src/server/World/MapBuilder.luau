-- Construye el mapa con piezas básicas al iniciar el servidor: bases de dos pisos,
-- banda transportadora, cueva y heladería. Todo queda dentro de Workspace.Map.
--
-- TODO ES PLACEHOLDER: para cambiar el aspecto, edita los colores y tamaños de aquí
-- o sustituye las piezas por modelos propios manteniendo los mismos nombres.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config").GameConfig)

export type BaseInfo = {
	index: number,
	model: Model,
	origin: CFrame, -- centro de la base a nivel del suelo; el frente mira hacia -Z local
	size: Vector3, -- ancho, alto y fondo de la base
	freezerPath: { Vector3 }, -- puntos por los que sube una fruta del piso 1 al congelador
	color: Color3,
	door: Part,
	lockPad: Part,
	collectPad: Part,
	collectLabel: TextLabel,
	spawn: SpawnLocation,
	ownerLabel: TextLabel,
	statusLabel: TextLabel,
	fruitSlots: { Part }, -- piso 1
	freezerSlots: { Part }, -- piso 2
	iceCreamSlots: { Part }, -- piso 2
}

export type MapInfo = {
	folder: Folder,
	bases: { BaseInfo },
	conveyorStart: Vector3, -- donde aparecen los personajes (boca de la cueva)
	conveyorEnd: Vector3, -- donde desaparecen si nadie los compra
	coconutSpot: CFrame, -- donde se coloca el NPC coco heladero
}

-- ===== Medidas (en studs) =====
local BASE_WIDTH = 56
local BASE_DEPTH = 48
local FLOOR_HEIGHT = 14 -- altura a la que empieza la losa del piso 2
local FREEZER_ROOM_HEIGHT = 12 -- altura interior del piso 2 (la cámara frigorífica)
local WALL_HEIGHT = FLOOR_HEIGHT + 1 + FREEZER_ROOM_HEIGHT -- altura a la que terminan los muros
local DOOR_WIDTH = 12
local DOOR_HEIGHT = 10
local DOOR_X = -5 -- centro de la puerta respecto al centro de la base
local RAMP_WIDTH = 10

local BASE_SPACING = 84 -- distancia entre centros de bases vecinas
local BASE_FRONT_Z = 62 -- distancia de la banda al frente de las bases
local CONVEYOR_HALF_LENGTH = 170
local CONVEYOR_WIDTH = 10

local BASE_COLORS = {
	Color3.fromRGB(235, 80, 80),
	Color3.fromRGB(245, 160, 60),
	Color3.fromRGB(240, 215, 70),
	Color3.fromRGB(110, 200, 90),
	Color3.fromRGB(70, 190, 200),
	Color3.fromRGB(80, 130, 235),
	Color3.fromRGB(160, 100, 230),
	Color3.fromRGB(235, 120, 190),
}

local MARBLE_COLOR = Color3.fromRGB(242, 234, 222) -- suelo del piso 1
local STONE_COLOR = Color3.fromRGB(125, 120, 130) -- zócalo y escalón
local TRIM_COLOR = Color3.fromRGB(250, 246, 240) -- pilares, marcos y remates blancos
local WAFFLE_COLOR = Color3.fromRGB(215, 165, 100)
local WINDOW_SILL = 3 -- del suelo del piso 1 al borde inferior de sus ventanas
local WINDOW_TOP = 9 -- del suelo del piso 1 al borde superior de sus ventanas

-- Colores de la cámara frigorífica (piso 2)
local FREEZER_WALL_COLOR = Color3.fromRGB(190, 215, 235)
local FREEZER_FLOOR_COLOR = Color3.fromRGB(205, 222, 238)
local ICE_COLOR = Color3.fromRGB(170, 225, 255)
local SNOW_COLOR = Color3.fromRGB(245, 250, 255)
local COLD_LIGHT_COLOR = Color3.fromRGB(190, 230, 255)

local MapBuilder = {}

-- ===== Utilidades =====

local function makePart(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function makeFolder(parent: Instance, name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

-- Cartel flotante; su tamaño va en studs, así se ve más pequeño de lejos
local function makeBillboard(parent: Instance, width: number, height: number, offsetY: number): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(width, height)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.MaxDistance = 250
	gui.Parent = parent
	return gui
end

local function makeLabel(parent: Instance, text: string, position: UDim2, size: UDim2, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextStrokeTransparency = 0
	label.Parent = parent
	return label
end

-- Texto pintado en una cara de una pieza. A diferencia de un cartel flotante, queda fijo:
-- no gira con la cámara ni se corta contra los muros.
local function makeSurfaceText(part: BasePart, face: Enum.NormalId, text: string, color: Color3): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0 -- se lee igual de bien aunque el cuarto esté oscuro
	gui.Parent = part
	return makeLabel(gui, text, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), color)
end

-- Fila de casillas donde se colocan frutas o helados
local function makeSlots(parent: Instance, origin: CFrame, positions: { Vector3 }, size: number, color: Color3, material: Enum.Material?): { Part }
	local slots = {}
	for index, position in positions do
		local slot = makePart(
			parent,
			tostring(index),
			Vector3.new(size, 0.4, size),
			origin * CFrame.new(position),
			color,
			material
		)
		slot:SetAttribute("Slot", index)
		table.insert(slots, slot)
	end
	return slots
end

-- ===== Cámara frigorífica (decoración del piso 2) =====

-- Añade al piso 2 lo que lo hace parecer un congelador: mampara de cristal hacia la rampa,
-- cortina de tiras en la entrada, luces frías, nieve, carámbanos y niebla.
local function buildFreezerRoom(parent: Instance, origin: CFrame, index: number, slabWidth: number, rampEndZ: number)
	local folder = makeFolder(parent, "FreezerRoom")
	local halfW = BASE_WIDTH / 2
	local halfD = BASE_DEPTH / 2
	local floorTop = FLOOR_HEIGHT + 1
	local roomY = floorTop + FREEZER_ROOM_HEIGHT / 2
	local slabLeft = -halfW + 1
	local slabRight = slabLeft + slabWidth
	local slabCenterX = (slabLeft + slabRight) / 2
	local innerFront = -halfD + 1
	local innerBack = halfD - 1

	-- Mampara de cristal entre la cámara y el hueco de la rampa. Es solo decoración: se atraviesa.
	local glassLength = rampEndZ - innerFront
	local glass = makePart(folder, "Partition", Vector3.new(0.4, FREEZER_ROOM_HEIGHT, glassLength), origin * CFrame.new(slabRight - 0.2, roomY, (innerFront + rampEndZ) / 2), ICE_COLOR, Enum.Material.Glass)
	glass.Transparency = 0.55
	glass.CanCollide = false

	-- Entrada desde el descansillo: cortina de tiras de plástico que se atraviesa
	local entryWidth = innerBack - rampEndZ
	local stripCount = 5
	local stripWidth = entryWidth / stripCount
	local stripHeight = FREEZER_ROOM_HEIGHT - 2
	for strip = 1, stripCount do
		local z = rampEndZ + (strip - 0.5) * stripWidth
		local part = makePart(folder, "CurtainStrip", Vector3.new(0.1, stripHeight, stripWidth - 0.1), origin * CFrame.new(slabRight - 0.2, floorTop + stripHeight / 2, z), ICE_COLOR)
		part.Transparency = 0.5
		part.CanCollide = false
	end

	-- Cartel de temperatura sobre la entrada
	local thermometer = makePart(folder, "Thermometer", Vector3.new(0.3, 1.6, entryWidth), origin * CFrame.new(slabRight - 0.2, floorTop + FREEZER_ROOM_HEIGHT - 1, (rampEndZ + innerBack) / 2), Color3.fromRGB(20, 30, 45))
	thermometer.CanCollide = false
	-- Se lee desde la rampa y desde dentro de la cámara
	makeSurfaceText(thermometer, Enum.NormalId.Right, "-18 °C", ICE_COLOR)
	makeSurfaceText(thermometer, Enum.NormalId.Left, "-18 °C", ICE_COLOR)

	-- Luces frías en el techo
	for _, x in { slabCenterX - 11, slabCenterX + 11 } do
		local lamp = makePart(folder, "Lamp", Vector3.new(10, 0.3, 1), origin * CFrame.new(x, WALL_HEIGHT - 0.15, -2), COLD_LIGHT_COLOR, Enum.Material.Neon)
		local light = Instance.new("PointLight")
		light.Color = COLD_LIGHT_COLOR
		light.Range = 28
		light.Brightness = 1
		light.Parent = lamp
	end

	-- Nieve acumulada junto a los muros izquierdo y frontal
	makePart(folder, "SnowLeft", Vector3.new(1.5, 0.5, BASE_DEPTH - 8), origin * CFrame.new(slabLeft + 0.75, floorTop + 0.25, -3), SNOW_COLOR, Enum.Material.Snow)
	makePart(folder, "SnowFront", Vector3.new(slabWidth - 2, 0.5, 1.5), origin * CFrame.new(slabCenterX, floorTop + 0.25, innerFront + 0.75), SNOW_COLOR, Enum.Material.Snow)

	-- Carámbanos colgando del techo. La semilla es el número de base: siempre salen igual.
	local rng = Random.new(index)
	for _ = 1, 14 do
		local height = rng:NextNumber(1.2, 3.2)
		local x = rng:NextNumber(slabLeft + 1, slabRight - 2)
		local z = rng:NextNumber(innerFront + 1, innerBack - 6)
		local icicle = Instance.new("CornerWedgePart")
		icicle.Name = "Icicle"
		icicle.Anchored = true
		icicle.CanCollide = false
		icicle.Size = Vector3.new(0.7, height, 0.7)
		-- Se gira boca abajo para que la punta quede hacia el suelo
		icicle.CFrame = origin * CFrame.new(x, WALL_HEIGHT - height / 2, z) * CFrame.Angles(math.pi, rng:NextNumber(0, math.pi * 2), 0)
		icicle.Color = ICE_COLOR
		icicle.Material = Enum.Material.Ice
		icicle.Transparency = 0.2
		icicle.Parent = folder
	end

	-- Niebla fría a ras de suelo
	local mist = makePart(folder, "Mist", Vector3.new(slabWidth - 4, 0.2, BASE_DEPTH - 8), origin * CFrame.new(slabCenterX, floorTop + 0.2, -2), SNOW_COLOR)
	mist.Transparency = 1
	mist.CanCollide = false
	mist.CanQuery = false
	mist.CanTouch = false
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(225, 240, 255))
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.85),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Size = NumberSequence.new(3, 6)
	emitter.Lifetime = NumberRange.new(3, 5)
	emitter.Speed = NumberRange.new(0.3, 0.8)
	emitter.Rate = 5
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.SpreadAngle = Vector2.new(30, 30)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.Parent = mist
end

-- ===== Casillas de fruta bloqueadas y desbloqueadas =====

local SLOT_COLOR = Color3.fromRGB(245, 245, 245)
local LOCKED_SLOT_COLOR = Color3.fromRGB(70, 70, 80)

local function styleFruitSlot(part: Part, unlocked: boolean)
	part.Color = if unlocked then SLOT_COLOR else LOCKED_SLOT_COLOR
	part.Transparency = if unlocked then 0 else 0.6
end

-- ===== Decoración exterior de la base (no afecta al juego) =====

-- Cilindro de pie. Los cilindros de Roblox van tumbados (a lo largo de X), así que se giran.
local function makeCylinder(parent: Instance, name: string, diameter: number, height: number, cframe: CFrame, color: Color3): Part
	local part = makePart(parent, name, Vector3.new(height, diameter, diameter), cframe * CFrame.Angles(0, 0, math.pi / 2), color)
	part.Shape = Enum.PartType.Cylinder
	return part
end

local function makeBall(parent: Instance, name: string, diameter: number, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local part = makePart(parent, name, Vector3.new(diameter, diameter, diameter), cframe, color, material)
	part.Shape = Enum.PartType.Ball
	return part
end

-- Zócalo de piedra, pilares en las esquinas, franja entre pisos, marco y toldo de la puerta,
-- farolillos, jardineras y un helado gigante en el tejado. color: el color de la base.
local function decorateBase(parent: Instance, origin: CFrame, color: Color3)
	local folder = makeFolder(parent, "Decoration")
	local halfW = BASE_WIDTH / 2
	local halfD = BASE_DEPTH / 2
	local lowerTop = FLOOR_HEIGHT + 1
	local doorLeft = DOOR_X - DOOR_WIDTH / 2
	local doorRight = DOOR_X + DOOR_WIDTH / 2
	local doorTop = 1 + DOOR_HEIGHT

	-- Zócalo de piedra alrededor (en el frente deja libre la puerta)
	local plinthY = 1.6
	makePart(folder, "PlinthBack", Vector3.new(BASE_WIDTH + 0.6, 1.2, 0.3), origin * CFrame.new(0, plinthY, halfD + 0.15), STONE_COLOR, Enum.Material.Slate)
	for _, side in { -1, 1 } do
		makePart(folder, "PlinthSide", Vector3.new(0.3, 1.2, BASE_DEPTH + 0.6), origin * CFrame.new(side * (halfW + 0.15), plinthY, 0), STONE_COLOR, Enum.Material.Slate)
	end
	makePart(folder, "PlinthFrontLeft", Vector3.new(doorLeft + halfW, 1.2, 0.3), origin * CFrame.new((doorLeft - halfW) / 2, plinthY, -halfD - 0.15), STONE_COLOR, Enum.Material.Slate)
	makePart(folder, "PlinthFrontRight", Vector3.new(halfW - doorRight, 1.2, 0.3), origin * CFrame.new((doorRight + halfW) / 2, plinthY, -halfD - 0.15), STONE_COLOR, Enum.Material.Slate)

	-- Pilares en las cuatro esquinas: blancos en el piso 1, metálicos en el piso 2
	local lowerHeight = lowerTop - 1
	local upperHeight = WALL_HEIGHT - lowerTop
	for _, sideX in { -1, 1 } do
		for _, sideZ in { -1, 1 } do
			local x = sideX * (halfW + 0.2)
			local z = sideZ * (halfD + 0.2)
			makePart(folder, "Pillar", Vector3.new(2, lowerHeight, 2), origin * CFrame.new(x, 1 + lowerHeight / 2, z), TRIM_COLOR, Enum.Material.Concrete)
			makePart(folder, "PillarFreezer", Vector3.new(2, upperHeight, 2), origin * CFrame.new(x, lowerTop + upperHeight / 2, z), Color3.fromRGB(150, 175, 200), Enum.Material.Metal)
		end
	end

	-- Franja del color de la base entre los dos pisos
	for _, side in { -1, 1 } do
		makePart(folder, "BandFrontBack", Vector3.new(BASE_WIDTH + 0.8, 1, 0.4), origin * CFrame.new(0, lowerTop, side * (halfD + 0.2)), color)
		makePart(folder, "BandSide", Vector3.new(0.4, 1, BASE_DEPTH + 0.8), origin * CFrame.new(side * (halfW + 0.2), lowerTop, 0), color)
	end

	-- Marco blanco de la puerta y escalón de piedra
	for _, x in { doorLeft - 0.4, doorRight + 0.4 } do
		makePart(folder, "DoorPost", Vector3.new(0.8, DOOR_HEIGHT, 1.4), origin * CFrame.new(x, 1 + DOOR_HEIGHT / 2, -halfD + 0.5), TRIM_COLOR)
	end
	makePart(folder, "DoorBeam", Vector3.new(DOOR_WIDTH + 1.6, 0.8, 1.4), origin * CFrame.new(DOOR_X, doorTop + 0.4, -halfD + 0.5), TRIM_COLOR)
	makePart(folder, "DoorStep", Vector3.new(DOOR_WIDTH + 2, 0.5, 3), origin * CFrame.new(DOOR_X, 0.25, -halfD - 1.5), STONE_COLOR, Enum.Material.Slate)

	-- Toldo de rayas sobre la puerta, como el de una heladería
	local slatWidth = 2
	local slatCount = math.floor((DOOR_WIDTH + 2) / slatWidth)
	for slat = 1, slatCount do
		local x = DOOR_X + (slat - (slatCount + 1) / 2) * slatWidth
		local slatColor = if slat % 2 == 0 then TRIM_COLOR else color
		local part = makePart(folder, "Awning", Vector3.new(slatWidth, 0.3, 5), origin * CFrame.new(x, doorTop + 2.2, -halfD - 2.3) * CFrame.Angles(math.rad(-20), 0, 0), slatColor)
		part.CanCollide = false
	end

	-- Farolillos a los lados de la puerta
	for _, x in { doorLeft - 2.4, doorRight + 2.4 } do
		local lamp = makePart(folder, "Lamp", Vector3.new(0.8, 1.4, 0.8), origin * CFrame.new(x, 8.5, -halfD - 0.5), Color3.fromRGB(255, 225, 160), Enum.Material.Neon)
		lamp.CanCollide = false
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 220, 160)
		light.Range = 14
		light.Brightness = 0.8
		light.Parent = lamp
	end

	-- Jardineras bajo las ventanas, con arbustos y flores del color de la base
	for _, x in { -halfW + 5.5, doorRight + 14 } do
		makePart(folder, "Planter", Vector3.new(7, 1.6, 2.4), origin * CFrame.new(x, 0.8, -halfD - 1.6), Color3.fromRGB(125, 85, 55), Enum.Material.Wood)
		for _, offset in { -2, 0, 2 } do
			local bush = makeBall(folder, "Bush", 2.4, origin * CFrame.new(x + offset, 2.4, -halfD - 1.6), Color3.fromRGB(85, 160, 85), Enum.Material.Grass)
			bush.CanCollide = false
			local flower = makeBall(folder, "Flower", 0.7, origin * CFrame.new(x + offset, 3.6, -halfD - 1.9), color, Enum.Material.Neon)
			flower.CanCollide = false
		end
	end

	-- Helado gigante en una esquina del tejado
	local coneX = -halfW + 6
	local coneZ = -halfD + 6
	local roofTop = WALL_HEIGHT + 1.4
	makeCylinder(folder, "RoofCone", 3.4, 4, origin * CFrame.new(coneX, roofTop + 2, coneZ), WAFFLE_COLOR)
	makeBall(folder, "RoofScoop", 5, origin * CFrame.new(coneX, roofTop + 5.6, coneZ), color)
	makeBall(folder, "RoofScoopTop", 3.6, origin * CFrame.new(coneX, roofTop + 8.6, coneZ), TRIM_COLOR)
	makeBall(folder, "RoofCherry", 1.2, origin * CFrame.new(coneX, roofTop + 10.8, coneZ), Color3.fromRGB(220, 40, 60))
end

-- ===== Base de dos pisos =====

local function buildBase(parent: Instance, index: number, origin: CFrame, color: Color3): BaseInfo
	local model = Instance.new("Model")
	model.Name = `Base{index}`

	local structure = makeFolder(model, "Structure")
	local halfW = BASE_WIDTH / 2
	local halfD = BASE_DEPTH / 2
	-- Los muros se apoyan sobre el suelo del piso 1 y todo lo interior queda 1 stud hacia dentro,
	-- para que ninguna pieza asome por la cara exterior de los muros.
	-- Cada muro tiene dos tramos: el del piso 1 y el de la cámara frigorífica del piso 2.
	local lowerTop = FLOOR_HEIGHT + 1 -- altura del suelo del piso 2
	local lowerHeight = lowerTop - 1
	local lowerY = 1 + lowerHeight / 2
	local upperHeight = WALL_HEIGHT - lowerTop
	local upperY = lowerTop + upperHeight / 2
	local innerBack = halfD - 1
	local floor2Y = FLOOR_HEIGHT + 0.5 -- centro de la losa del piso 2
	local rampWidth = RAMP_WIDTH - 1
	local rampX = halfW - 1 - rampWidth / 2 -- la rampa va pegada al muro derecho
	local frontZ = -halfD + 0.5
	-- Cada base tiene su propio tono: los muros son una versión pastel de su color
	local wallColor = color:Lerp(Color3.new(1, 1, 1), 0.6)

	-- length: largo del muro. alongX: true si va de lado a lado, false si va de frente a fondo.
	local function makeWall(name: string, length: number, x: number, z: number, alongX: boolean)
		local lowerSize = if alongX then Vector3.new(length, lowerHeight, 1) else Vector3.new(1, lowerHeight, length)
		local upperSize = if alongX then Vector3.new(length, upperHeight, 1) else Vector3.new(1, upperHeight, length)
		makePart(structure, name, lowerSize, origin * CFrame.new(x, lowerY, z), wallColor, Enum.Material.Brick)
		makePart(structure, name .. "Freezer", upperSize, origin * CFrame.new(x, upperY, z), FREEZER_WALL_COLOR, Enum.Material.Metal)
	end

	-- Suelo del piso 1
	makePart(structure, "Floor1", Vector3.new(BASE_WIDTH, 1, BASE_DEPTH), origin * CFrame.new(0, 0.5, 0), MARBLE_COLOR, Enum.Material.Marble)

	-- Muros trasero y laterales
	makeWall("BackWall", BASE_WIDTH, 0, halfD - 0.5, true)
	makeWall("LeftWall", BASE_DEPTH, -halfW + 0.5, 0, false)
	makeWall("RightWall", BASE_DEPTH, halfW - 0.5, 0, false)

	-- Muro frontal: en el piso 1 deja el hueco de la puerta; en el piso 2 es corrido
	local doorLeft = DOOR_X - DOOR_WIDTH / 2
	local doorRight = DOOR_X + DOOR_WIDTH / 2
	-- Tramo del muro frontal con una ventana, para que desde la calle se vean las frutas.
	-- Va de fromX a toX y la ventana ocupa de windowFrom a windowTo.
	local function makeFrontWall(name: string, fromX: number, toX: number, windowFrom: number, windowTo: number)
		local function piece(suffix: string, x0: number, x1: number, y0: number, y1: number)
			if x1 - x0 > 0 and y1 - y0 > 0 then
				makePart(structure, name .. suffix, Vector3.new(x1 - x0, y1 - y0, 1), origin * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, frontZ), wallColor, Enum.Material.Brick)
			end
		end
		local sillY = 1 + WINDOW_SILL
		local topY = 1 + WINDOW_TOP
		piece("Left", fromX, windowFrom, 1, lowerTop)
		piece("Right", windowTo, toX, 1, lowerTop)
		piece("Below", windowFrom, windowTo, 1, sillY)
		piece("Above", windowFrom, windowTo, topY, lowerTop)

		local centerX = (windowFrom + windowTo) / 2
		local centerY = (sillY + topY) / 2
		local width = windowTo - windowFrom
		local height = topY - sillY
		local glass = makePart(structure, name .. "Glass", Vector3.new(width, height, 0.4), origin * CFrame.new(centerX, centerY, frontZ), Color3.fromRGB(200, 230, 255), Enum.Material.Glass)
		glass.Transparency = 0.55

		-- Marco blanco por fuera
		local frameZ = -halfD - 0.15
		makePart(structure, name .. "FrameTop", Vector3.new(width + 1, 0.5, 0.3), origin * CFrame.new(centerX, topY + 0.25, frameZ), TRIM_COLOR)
		makePart(structure, name .. "FrameBottom", Vector3.new(width + 1.6, 0.6, 0.8), origin * CFrame.new(centerX, sillY - 0.3, frameZ - 0.25), TRIM_COLOR)
		makePart(structure, name .. "FrameLeft", Vector3.new(0.5, height, 0.3), origin * CFrame.new(windowFrom - 0.25, centerY, frameZ), TRIM_COLOR)
		makePart(structure, name .. "FrameRight", Vector3.new(0.5, height, 0.3), origin * CFrame.new(windowTo + 0.25, centerY, frameZ), TRIM_COLOR)
	end
	-- Las ventanas evitan los rótulos de las placas, que cuelgan por dentro junto a la puerta
	makeFrontWall("FrontWallLeft", -halfW, doorLeft, -halfW + 2, -halfW + 9)
	makeFrontWall("FrontWallRight", doorRight, halfW, doorRight + 9, doorRight + 19)
	-- Frente del piso 2: dos ventanales para que desde la calle se vean los helados de la vitrina
	local sillHeight = 2.5 -- del suelo del piso 2 al borde inferior de la ventana
	local windowHeight = 6
	local topHeight = upperHeight - sillHeight - windowHeight
	local windowY = lowerTop + sillHeight + windowHeight / 2
	makePart(structure, "FrontFreezerSill", Vector3.new(BASE_WIDTH, sillHeight, 1), origin * CFrame.new(0, lowerTop + sillHeight / 2, frontZ), FREEZER_WALL_COLOR, Enum.Material.Metal)
	makePart(structure, "FrontFreezerTop", Vector3.new(BASE_WIDTH, topHeight, 1), origin * CFrame.new(0, WALL_HEIGHT - topHeight / 2, frontZ), FREEZER_WALL_COLOR, Enum.Material.Metal)
	-- Tramos de izquierda a derecha: muro, ventana, muro, ventana, muro (x inicial, x final, es ventana)
	local windowLayout = {
		{ -halfW, -halfW + 4, false },
		{ -halfW + 4, -halfW + 20, true },
		{ -halfW + 20, -halfW + 24, false },
		{ -halfW + 24, -halfW + 40, true },
		{ -halfW + 40, halfW, false },
	}
	for _, segment in windowLayout do
		local fromX, toX, isWindow = segment[1], segment[2], segment[3]
		local cframe = origin * CFrame.new((fromX + toX) / 2, windowY, frontZ)
		if isWindow then
			local pane = makePart(structure, "FreezerWindow", Vector3.new(toX - fromX, windowHeight, 0.4), cframe, ICE_COLOR, Enum.Material.Glass)
			pane.Transparency = 0.6
		else
			makePart(structure, "FrontFreezerPillar", Vector3.new(toX - fromX, windowHeight, 1), cframe, FREEZER_WALL_COLOR, Enum.Material.Metal)
		end
	end
	local doorTop = 1 + DOOR_HEIGHT
	local lintelHeight = lowerTop - doorTop
	-- El dintel lleva el color de la base, para distinguirla desde lejos
	makePart(structure, "Lintel", Vector3.new(DOOR_WIDTH, lintelHeight, 1), origin * CFrame.new(DOOR_X, doorTop + lintelHeight / 2, frontZ), color)

	-- Techo de la cámara, con nieve encima y un equipo de frío
	makePart(structure, "Roof", Vector3.new(BASE_WIDTH + 3, 1, BASE_DEPTH + 3), origin * CFrame.new(0, WALL_HEIGHT + 0.5, 0), FREEZER_WALL_COLOR, Enum.Material.Metal)
	-- Borde del alero en el color de la base
	makePart(structure, "RoofTrim", Vector3.new(BASE_WIDTH + 3.6, 0.6, BASE_DEPTH + 3.6), origin * CFrame.new(0, WALL_HEIGHT + 0.5, 0), color)
	decorateBase(structure, origin, color)
	makePart(structure, "RoofSnow", Vector3.new(BASE_WIDTH - 2, 0.4, BASE_DEPTH - 2), origin * CFrame.new(0, WALL_HEIGHT + 1.2, 0), SNOW_COLOR, Enum.Material.Snow)
	makePart(structure, "CoolingUnit", Vector3.new(8, 4, 6), origin * CFrame.new(10, WALL_HEIGHT + 3.4, 8), Color3.fromRGB(90, 100, 110), Enum.Material.Metal)
	makePart(structure, "CoolingUnitLight", Vector3.new(8.2, 0.5, 0.4), origin * CFrame.new(10, WALL_HEIGHT + 4.4, 5), ICE_COLOR, Enum.Material.Neon)

	-- Losa del piso 2 (deja libre el hueco de la rampa) y descansillo al final de la rampa
	local slabWidth = BASE_WIDTH - RAMP_WIDTH - 1
	makePart(structure, "Floor2", Vector3.new(slabWidth, 1, BASE_DEPTH - 2), origin * CFrame.new(-halfW + 1 + slabWidth / 2, floor2Y, 0), FREEZER_FLOOR_COLOR, Enum.Material.DiamondPlate)
	local rampStartZ = -halfD + 4
	local rampEndZ = halfD - 6
	makePart(structure, "Landing", Vector3.new(rampWidth, 1, innerBack - rampEndZ), origin * CFrame.new(rampX, floor2Y, (rampEndZ + innerBack) / 2), FREEZER_FLOOR_COLOR, Enum.Material.DiamondPlate)

	-- Rampa del piso 1 al piso 2
	local run = rampEndZ - rampStartZ
	local rise = FLOOR_HEIGHT
	local angle = math.atan2(rise, run)
	local rampLength = math.sqrt(run * run + rise * rise)
	local rampCenter = Vector3.new(rampX, 1 + rise / 2 - 0.5 * math.cos(angle), (rampStartZ + rampEndZ) / 2 + 0.5 * math.sin(angle))
	makePart(structure, "Ramp", Vector3.new(rampWidth, 1, rampLength), origin * CFrame.new(rampCenter) * CFrame.Angles(-angle, 0, 0), color)

	-- Puerta (BaseService controla si está bloqueada)
	local door = makePart(model, "Door", Vector3.new(DOOR_WIDTH, DOOR_HEIGHT, 0.6), origin * CFrame.new(DOOR_X, 1 + DOOR_HEIGHT / 2, frontZ), Color3.fromRGB(90, 220, 120), Enum.Material.ForceField)
	door.CanCollide = false
	door.CanTouch = false
	door.Transparency = 0.85

	-- Punto de aparición, justo detrás de la puerta
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Size = Vector3.new(6, 0.5, 6)
	spawn.CFrame = origin * CFrame.new(DOOR_X, 1.25, -halfD + 6)
	spawn.Color = color
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = model

	-- Placa para bloquear la puerta (el dueño se sube encima)
	local lockPad = makePart(model, "LockPad", Vector3.new(4, 0.3, 4), origin * CFrame.new(DOOR_X + 9, 1.15, -halfD + 5), Color3.fromRGB(255, 70, 70), Enum.Material.Neon)
	-- Rótulo fijo en el muro, encima de la placa y mirando hacia dentro de la base
	local lockSign = makePart(model, "LockSign", Vector3.new(8, 2, 0.2), origin * CFrame.new(DOOR_X + 9, 5, -halfD + 1.1), Color3.fromRGB(60, 20, 20))
	makeSurfaceText(lockSign, Enum.NormalId.Back, "Bloquear base", Color3.fromRGB(255, 150, 150))

	-- Placa para recoger el dinero acumulado (al otro lado de la entrada)
	local collectPad = makePart(model, "CollectPad", Vector3.new(4, 0.3, 4), origin * CFrame.new(DOOR_X - 9, 1.15, -halfD + 5), Color3.fromRGB(80, 230, 110), Enum.Material.Neon)
	local collectSign = makePart(model, "CollectSign", Vector3.new(8, 3.2, 0.2), origin * CFrame.new(DOOR_X - 9, 5.6, -halfD + 1.1), Color3.fromRGB(20, 55, 30))
	local collectLabel = makeSurfaceText(collectSign, Enum.NormalId.Back, "Recolectar", Color3.fromRGB(150, 255, 170))

	-- Cartel sobre la puerta: dueño y estado
	local signAnchor = makePart(model, "Sign", Vector3.new(1, 1, 1), origin * CFrame.new(DOOR_X, WALL_HEIGHT + 2, -halfD), color)
	signAnchor.Transparency = 1
	signAnchor.CanCollide = false
	signAnchor.CanQuery = false
	local signGui = makeBillboard(signAnchor, 18, 5, 1.5)
	local ownerLabel = makeLabel(signGui, "Libre", UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.6), Color3.new(1, 1, 1))
	local statusLabel = makeLabel(signGui, "", UDim2.fromScale(0, 0.6), UDim2.fromScale(1, 0.4), Color3.fromRGB(120, 255, 150))

	-- Piso 1: casillas de frutas en filas de 4. Se construyen todas las posibles; las que el
	-- dueño aún no ha desbloqueado se ven apagadas (ver MapBuilder.setFruitCapacity).
	local fruitPositions = {}
	local perRow = 4
	for slot = 1, GameConfig.MaxFruitSlots do
		local column = (slot - 1) % perRow
		local row = math.floor((slot - 1) / perRow)
		table.insert(fruitPositions, Vector3.new(-RAMP_WIDTH / 2 + (column - (perRow - 1) / 2) * 10, 1.2, -8 + row * 8))
	end
	local fruitSlots = makeSlots(makeFolder(model, "FruitSlots"), origin, fruitPositions, 5, SLOT_COLOR)
	for slot, part in fruitSlots do
		styleFruitSlot(part, slot <= GameConfig.FruitSlots)
	end

	-- Piso 2: decoración de cámara frigorífica
	buildFreezerRoom(structure, origin, index, slabWidth, rampEndZ)

	-- Piso 2: congelador al fondo (armario metálico con puertas de cristal) y sus ranuras delante
	local slotY = FLOOR_HEIGHT + 1.2
	local freezerX = -RAMP_WIDTH / 2
	local freezerZ = halfD - 3
	makePart(model, "Freezer", Vector3.new(34, 9, 4), origin * CFrame.new(freezerX, lowerTop + 4.5, freezerZ), Color3.fromRGB(225, 235, 245), Enum.Material.Metal)
	makePart(model, "FreezerLight", Vector3.new(34, 0.4, 0.4), origin * CFrame.new(freezerX, lowerTop + 8.6, freezerZ - 2.1), ICE_COLOR, Enum.Material.Neon)
	for slot = 1, GameConfig.FreezerSlots do
		local offset = (slot - (GameConfig.FreezerSlots + 1) / 2) * 10
		local glass = makePart(model, "FreezerDoor", Vector3.new(8, 7, 0.3), origin * CFrame.new(freezerX + offset, lowerTop + 4.2, freezerZ - 2.1), ICE_COLOR, Enum.Material.Glass)
		glass.Transparency = 0.35
		makePart(model, "FreezerHandle", Vector3.new(0.3, 3, 0.3), origin * CFrame.new(freezerX + offset + 3.2, lowerTop + 4.2, freezerZ - 2.4), Color3.fromRGB(120, 130, 140), Enum.Material.Metal)
	end
	-- Rótulo fijo sobre el armario, mirando hacia la entrada de la base
	local freezerSign = makePart(model, "FreezerSign", Vector3.new(16, 2.2, 0.3), origin * CFrame.new(freezerX, lowerTop + 10.4, freezerZ - 1.9), Color3.fromRGB(20, 30, 45))
	makeSurfaceText(freezerSign, Enum.NormalId.Front, "CONGELADOR", ICE_COLOR)

	local freezerPositions = {}
	for slot = 1, GameConfig.FreezerSlots do
		local offset = (slot - (GameConfig.FreezerSlots + 1) / 2) * 10
		table.insert(freezerPositions, Vector3.new(freezerX + offset, slotY, halfD - 10))
	end
	local freezerSlots = makeSlots(makeFolder(model, "FreezerSlots"), origin, freezerPositions, 5, Color3.fromRGB(150, 210, 255), Enum.Material.Ice)

	-- Piso 2: vitrina de helados, en fila junto al frente
	local iceCreamPositions = {}
	for slot = 1, GameConfig.IceCreamSlots do
		local offset = (slot - (GameConfig.IceCreamSlots + 1) / 2) * 7
		table.insert(iceCreamPositions, Vector3.new(-RAMP_WIDTH / 2 + offset, slotY, -halfD + 12))
	end
	local iceCreamSlots = makeSlots(makeFolder(model, "IceCreamSlots"), origin, iceCreamPositions, 4, Color3.fromRGB(255, 190, 220))

	model.Parent = parent

	return {
		index = index,
		model = model,
		origin = origin,
		size = Vector3.new(BASE_WIDTH, WALL_HEIGHT, BASE_DEPTH),
		freezerPath = {
			origin * Vector3.new(rampX, 1, rampStartZ), -- pie de la rampa
			origin * Vector3.new(rampX, lowerTop, rampEndZ), -- final de la rampa
			origin * Vector3.new(rampX, lowerTop, (rampEndZ + innerBack) / 2), -- descansillo
			origin * Vector3.new(halfW - RAMP_WIDTH - 3, lowerTop, (rampEndZ + innerBack) / 2), -- tras la cortina
			origin * Vector3.new(halfW - RAMP_WIDTH - 3, lowerTop, halfD - 10), -- pasillo frente al congelador
		},
		color = color,
		door = door,
		lockPad = lockPad,
		collectPad = collectPad,
		collectLabel = collectLabel,
		spawn = spawn,
		ownerLabel = ownerLabel,
		statusLabel = statusLabel,
		fruitSlots = fruitSlots,
		freezerSlots = freezerSlots,
		iceCreamSlots = iceCreamSlots,
	}
end

-- Marca cuántas casillas de fruta están desbloqueadas en una base: las demás se ven apagadas
function MapBuilder.setFruitCapacity(info: BaseInfo, capacity: number)
	for slot, part in info.fruitSlots do
		styleFruitSlot(part, slot <= capacity)
	end
end

-- ===== Banda transportadora y cueva =====

local function buildConveyor(parent: Instance)
	local folder = makeFolder(parent, "Conveyor")
	local length = CONVEYOR_HALF_LENGTH * 2

	makePart(folder, "Belt", Vector3.new(length, 1, CONVEYOR_WIDTH), CFrame.new(0, 0.5, 0), Color3.fromRGB(45, 45, 50), Enum.Material.Metal)
	for _, side in { -1, 1 } do
		makePart(folder, "Rail", Vector3.new(length, 0.4, 0.6), CFrame.new(0, 1.2, side * (CONVEYOR_WIDTH / 2 - 0.3)), Color3.fromRGB(250, 200, 60))
	end

	-- Cueva de la que salen los personajes (REEMPLAZAR por un modelo de cueva o carreta)
	local caveX = -CONVEYOR_HALF_LENGTH - 12
	local rock = Color3.fromRGB(95, 85, 80)
	makePart(folder, "CaveRock", Vector3.new(24, 22, 28), CFrame.new(caveX, 11, 0), rock, Enum.Material.Slate)
	makePart(folder, "CaveMouth", Vector3.new(0.5, 11, CONVEYOR_WIDTH + 2), CFrame.new(-CONVEYOR_HALF_LENGTH + 0.2, 6.5, 0), Color3.new(0, 0, 0))

	-- Final de la banda: los personajes que nadie compra desaparecen aquí
	makePart(folder, "EndBlock", Vector3.new(10, 12, 14), CFrame.new(CONVEYOR_HALF_LENGTH + 5, 6, 0), Color3.fromRGB(120, 40, 40), Enum.Material.Metal)
end

-- ===== Heladería del coco =====

local function buildIceCreamShop(parent: Instance): CFrame
	local folder = makeFolder(parent, "IceCreamShop")
	local centerX = CONVEYOR_HALF_LENGTH + 60
	local pink = Color3.fromRGB(255, 190, 215)
	local cream = Color3.fromRGB(255, 245, 225)

	makePart(folder, "Floor", Vector3.new(36, 1, 36), CFrame.new(centerX, 0.5, 0), cream)
	makePart(folder, "BackWall", Vector3.new(1, 16, 36), CFrame.new(centerX + 17.5, 8.5, 0), pink)
	for _, side in { -1, 1 } do
		makePart(folder, "SideWall", Vector3.new(20, 16, 1), CFrame.new(centerX + 8, 8.5, side * 17.5), pink)
		makePart(folder, "Pillar", Vector3.new(2, 16, 2), CFrame.new(centerX - 16, 8.5, side * 16), cream)
	end
	makePart(folder, "Roof", Vector3.new(38, 1, 38), CFrame.new(centerX, 17, 0), Color3.fromRGB(240, 110, 150))
	makePart(folder, "Counter", Vector3.new(4, 4, 20), CFrame.new(centerX, 3, 0), Color3.fromRGB(150, 220, 230))

	local sign = makePart(folder, "Sign", Vector3.new(1, 1, 1), CFrame.new(centerX - 16, 19, 0), pink)
	sign.Transparency = 1
	sign.CanCollide = false
	sign.CanQuery = false
	local gui = makeBillboard(sign, 24, 5, 2)
	makeLabel(gui, "Heladería", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Color3.fromRGB(255, 230, 240))

	-- El coco se coloca detrás del mostrador, mirando hacia la banda
	local spot = Vector3.new(centerX + 6, 1, 0)
	return CFrame.lookAt(spot, spot + Vector3.new(-1, 0, 0))
end

-- ===== Construcción completa =====

function MapBuilder.build(): MapInfo
	local old = Workspace:FindFirstChild("Map")
	if old then
		old:Destroy()
	end

	-- Los puntos de aparición sueltos (como el de la plantilla Baseplate) estorban en la banda.
	-- Solo se quitan durante la partida: el lugar guardado en Studio no cambia.
	for _, child in Workspace:GetChildren() do
		if child:IsA("SpawnLocation") then
			child:Destroy()
		end
	end

	local folder = Instance.new("Folder")
	folder.Name = "Map"

	buildConveyor(folder)
	local coconutSpot = buildIceCreamShop(folder)

	-- Bases en dos filas, una a cada lado de la banda, con la puerta mirando hacia ella
	local basesFolder = makeFolder(folder, "Bases")
	local bases = {}
	local total = GameConfig.MaxPlayers
	local perSide = math.ceil(total / 2)
	local centerZ = BASE_FRONT_Z + BASE_DEPTH / 2

	for index = 1, total do
		local column = (index - 1) % perSide
		local farSide = index > perSide
		local x = (column - (perSide - 1) / 2) * BASE_SPACING

		local origin
		if farSide then
			origin = CFrame.new(x, 0, -centerZ) * CFrame.Angles(0, math.pi, 0)
		else
			origin = CFrame.new(x, 0, centerZ)
		end

		local color = BASE_COLORS[(index - 1) % #BASE_COLORS + 1]
		table.insert(bases, buildBase(basesFolder, index, origin, color))
	end

	folder.Parent = Workspace

	return {
		folder = folder,
		bases = bases,
		conveyorStart = Vector3.new(-CONVEYOR_HALF_LENGTH + 2, 1, 0),
		conveyorEnd = Vector3.new(CONVEYOR_HALF_LENGTH, 1, 0),
		coconutSpot = coconutSpot,
	}
end

return MapBuilder
