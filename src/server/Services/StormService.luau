-- Tormenta de mutaciones y la máquina que la provoca.
--
-- LA MÁQUINA: está junto a la banda, en el centro del mapa. Los jugadores le echan frutas
-- y helados; cada uno da puntos según su rareza. Al llegar a la meta empieza la tormenta.
-- Si nadie la llena, cae una tormenta sola cada cierto tiempo.
--
-- LA TORMENTA: se oscurece el cielo, llueve y cada pocos segundos cae un rayo sobre un
-- personaje sin mutación de los que van por la banda y le pone una. Los que salen de la cueva
-- también tienen más probabilidad de venir mutados. Lo que ya está dentro de una base no cambia.
--
-- Todos los números están en GameConfig (bloque "Tormenta de mutaciones").

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CharacterConfig = require(Shared.Config.CharacterConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Mutations = require(Shared.Config.Mutations)
local SoundConfig = require(Shared.Config.SoundConfig)
local Economy = require(Shared.Economy)
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Util.Format)

local Notifier = require(script.Parent.Notifier)
local PlacementService = require(script.Parent.PlacementService)
local SpawnerService = require(script.Parent.SpawnerService)
local TradeService = require(script.Parent.TradeService)
local Effects = require(script.Parent.Parent.World.Effects)
local MapBuilder = require(script.Parent.Parent.World.MapBuilder)

-- "Charging": acepta frutas. "Storm": hay tormenta. "Cooldown": descansa tras una tormenta.
type Phase = "Charging" | "Storm" | "Cooldown"

local MACHINE_OFFSET = Vector3.new(0, 0, 24) -- respecto al centro de la banda
local TANK_HEIGHT = 10 -- alto del depósito de cristal
local STORM_COLOR = Color3.fromRGB(190, 120, 255)
local BOLT_COLOR = Color3.fromRGB(210, 225, 255)
local ACTION_INTERVAL = 0.15 -- segundos mínimos entre acciones de un mismo jugador

local StormService = {}

local started = false
local rng = Random.new()

local phase: string = "Charging" -- uno de los valores de Phase
local phaseEndsAt = 0 -- os.clock() al que termina la tormenta o el descanso
local nextNaturalStormAt = math.huge -- os.clock() al que cae una tormenta sola
local points = 0
local contributions: { [Player]: number } = {}
local lastAction: { [Player]: number } = {}
-- Tormentas pagadas que esperan a que termine la actual (un pago nunca se pierde)
local queuedStorms = 0

local machinePosition: Vector3
local fillPart: Part
local titleLabel: TextLabel
local progressLabel: TextLabel
local rainEmitter: ParticleEmitter

-- Valores normales de la iluminación, para volver a ellos al acabar la tormenta
local normalBrightness = Lighting.Brightness
local normalOutdoorAmbient = Lighting.OutdoorAmbient

-- ===== Construcción =====

local function makePart(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function makeLabel(parent: Instance, position: UDim2, size: UDim2, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.TextColor3 = color
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextStrokeTransparency = 0
	label.Parent = parent
	return label
end

-- PLACEHOLDER: la máquina son piezas básicas. Para usar un modelo propio, sustituye esta
-- función conservando fillPart (lo que sube al llenarse), los dos textos y el botón.
local function buildMachine(map: MapBuilder.MapInfo)
	machinePosition = (map.conveyorStart + map.conveyorEnd) / 2 + MACHINE_OFFSET
	machinePosition = Vector3.new(machinePosition.X, 0, machinePosition.Z)
	local at = machinePosition

	local model = Instance.new("Model")
	model.Name = "StormMachine"

	local metal = Color3.fromRGB(70, 75, 90)
	local base = makePart(model, "Base", Vector3.new(10, 3, 10), at + Vector3.new(0, 1.5, 0), metal, Enum.Material.Metal)

	local tank = makePart(model, "Tank", Vector3.new(7, TANK_HEIGHT, 7), at + Vector3.new(0, 3 + TANK_HEIGHT / 2, 0), Color3.fromRGB(200, 220, 255), Enum.Material.Glass)
	tank.Transparency = 0.65

	-- Lo que sube dentro del depósito a medida que se llena
	fillPart = makePart(model, "Fill", Vector3.new(6, 0.2, 6), at + Vector3.new(0, 3.1, 0), STORM_COLOR, Enum.Material.Neon)
	fillPart.CanCollide = false

	local capY = 3 + TANK_HEIGHT + 0.5
	makePart(model, "Cap", Vector3.new(8, 1, 8), at + Vector3.new(0, capY, 0), metal, Enum.Material.Metal)
	makePart(model, "Rod", Vector3.new(0.6, 6, 0.6), at + Vector3.new(0, capY + 3.5, 0), metal, Enum.Material.Metal)

	local orb = makePart(model, "Orb", Vector3.new(2.6, 2.6, 2.6), at + Vector3.new(0, capY + 7.5, 0), STORM_COLOR, Enum.Material.Neon)
	orb.Shape = Enum.PartType.Ball
	orb.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = STORM_COLOR
	light.Range = 20
	light.Parent = orb

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(20, 5)
	gui.StudsOffset = Vector3.new(0, 4.5, 0)
	gui.MaxDistance = 220
	gui.Parent = orb
	titleLabel = makeLabel(gui, UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.5), STORM_COLOR)
	titleLabel.Text = "MÁQUINA DE TORMENTAS"
	progressLabel = makeLabel(gui, UDim2.fromScale(0, 0.5), UDim2.fromScale(1, 0.5), Color3.new(1, 1, 1))

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Echar frutas"
	prompt.ObjectText = "Máquina de tormentas"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = base
	local openRemote = Remotes.get("OpenStorm")
	prompt.Triggered:Connect(function(player)
		openRemote:FireClient(player)
	end)

	-- Nube invisible sobre la banda de la que cae la lluvia
	local beltLength = (map.conveyorEnd - map.conveyorStart).Magnitude
	local cloud = makePart(model, "Cloud", Vector3.new(beltLength, 1, 90), at - MACHINE_OFFSET + Vector3.new(0, 75, 0), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	cloud.Transparency = 1
	cloud.CanCollide = false
	cloud.CanQuery = false
	cloud.CanTouch = false

	rainEmitter = Instance.new("ParticleEmitter")
	rainEmitter.Name = "Rain"
	rainEmitter.Enabled = false
	rainEmitter.Color = ColorSequence.new(Color3.fromRGB(190, 215, 255))
	rainEmitter.Transparency = NumberSequence.new(0.4)
	rainEmitter.Size = NumberSequence.new(0.25)
	rainEmitter.Lifetime = NumberRange.new(0.9)
	rainEmitter.Speed = NumberRange.new(85)
	rainEmitter.Rate = 500
	rainEmitter.EmissionDirection = Enum.NormalId.Bottom
	-- Estira las partículas en la dirección de caída para que parezcan gotas
	pcall(function()
		rainEmitter.Orientation = Enum.ParticleOrientation.VelocityParallel
		rainEmitter.Squash = NumberSequence.new(3)
	end)
	rainEmitter.Parent = cloud

	model.Parent = map.folder
end

-- ===== Estado visible =====

local function refresh()
	local goal = GameConfig.StormGoal
	local fraction = if phase == "Storm" then 1 else math.clamp(points / goal, 0, 1)
	local height = math.max(fraction * (TANK_HEIGHT - 0.4), 0.2)
	fillPart.Size = Vector3.new(6, height, 6)
	fillPart.Position = machinePosition + Vector3.new(0, 3.1 + height / 2, 0)

	local now = os.clock()
	if phase == "Storm" then
		progressLabel.Text = `¡TORMENTA! {Format.time(phaseEndsAt - now)}`
	elseif phase == "Cooldown" then
		progressLabel.Text = `Recargando... {Format.time(phaseEndsAt - now)}`
	else
		progressLabel.Text = `{points} / {goal} puntos`
	end

	-- El menú del cliente lee estos atributos
	Workspace:SetAttribute("StormPhase", phase)
	Workspace:SetAttribute("StormPoints", points)
end

-- ===== La tormenta =====

local function setStormLighting(active: boolean)
	TweenService:Create(Lighting, TweenInfo.new(3), {
		Brightness = if active then math.min(normalBrightness, 0.7) else normalBrightness,
		OutdoorAmbient = if active then Color3.fromRGB(70, 65, 105) else normalOutdoorAmbient,
	}):Play()
end

-- Rayo que cae sobre un personaje de la banda sin mutación y le pone una
local function strike()
	local candidates = {}
	for uid, item in SpawnerService.getItems() do
		if not item.mutation then
			table.insert(candidates, uid)
		end
	end
	if #candidates == 0 then
		return
	end

	local uid = candidates[rng:NextInteger(1, #candidates)]
	local item = SpawnerService.getItem(uid)
	if not item then
		return
	end
	local mutation = Mutations.pickRandom(rng)
	if not SpawnerService.setMutation(uid, mutation) then
		return
	end

	-- El rayo: una barra brillante desde el cielo hasta el personaje, que dura un instante
	local target = item.model:GetPivot().Position
	local origin = target + Vector3.new(rng:NextNumber(-12, 12), 80, rng:NextNumber(-12, 12))
	local bolt = Instance.new("Part")
	bolt.Name = "Lightning"
	bolt.Anchored = true
	bolt.CanCollide = false
	bolt.CanQuery = false
	bolt.CanTouch = false
	bolt.Material = Enum.Material.Neon
	bolt.Color = BOLT_COLOR
	bolt.Size = Vector3.new(0.6, 0.6, (origin - target).Magnitude)
	bolt.CFrame = CFrame.lookAt((origin + target) / 2, target)
	local flash = Instance.new("PointLight")
	flash.Color = BOLT_COLOR
	flash.Brightness = 6
	flash.Range = 45
	flash.Parent = bolt
	bolt.Parent = Workspace
	Debris:AddItem(bolt, 0.18)

	Effects.burst(item.model.PrimaryPart, mutation.color, 35)

	-- Trueno: suena desde el personaje alcanzado (si hay un sonido configurado)
	if SoundConfig.Thunder ~= "" and item.model.PrimaryPart then
		local sound = Instance.new("Sound")
		sound.SoundId = SoundConfig.Thunder
		sound.RollOffMaxDistance = 250
		sound.Parent = item.model.PrimaryPart
		sound:Play()
		Debris:AddItem(sound, 5)
	end
end

local function scheduleNaturalStorm(delay: number?)
	local interval = delay or GameConfig.StormNaturalInterval
	nextNaturalStormAt = if interval > 0 then os.clock() + interval else math.huge
end

local startStorm: (announcement: string) -> ()

local function endStorm()
	SpawnerService.mutationRainActive = false
	Workspace:SetAttribute("MutationRainEndsAt", nil)
	rainEmitter.Enabled = false
	setStormLighting(false)

	phase = "Cooldown"
	phaseEndsAt = os.clock() + GameConfig.StormCooldown
	points = 0
	table.clear(contributions)
	scheduleNaturalStorm()
	refresh()
	Notifier.announce("La tormenta de mutaciones terminó.", Color3.new(1, 1, 1))

	-- Si alguien pagó otra tormenta mientras duraba esta, empieza enseguida (sin descanso)
	if queuedStorms > 0 then
		queuedStorms -= 1
		task.delay(5, function()
			startStorm("¡OTRA TORMENTA DE MUTACIONES! Alguien la tenía reservada.")
		end)
	end
end

-- announcement: texto del aviso grande con el que empieza
function startStorm(announcement: string)
	if phase == "Storm" then
		return
	end
	phase = "Storm"
	phaseEndsAt = os.clock() + GameConfig.StormDuration
	nextNaturalStormAt = math.huge

	SpawnerService.mutationRainActive = true
	Workspace:SetAttribute("MutationRainEndsAt", Workspace:GetServerTimeNow() + GameConfig.StormDuration)
	rainEmitter.Enabled = true
	setStormLighting(true)
	refresh()
	Notifier.announce(announcement, STORM_COLOR, "Storm")

	task.spawn(function()
		while phase == "Storm" and os.clock() < phaseEndsAt do
			local ok, message = pcall(strike)
			if not ok then
				warn(`[StormService] Error al lanzar un rayo: {message}`)
			end
			task.wait(GameConfig.StormStrikeInterval)
		end
		endStorm()
	end)
end

-- Quien más puntos puso se lleva el crédito en el aviso
local function getTopDonor(): Player?
	local best: Player? = nil
	local bestPoints = 0
	for player, amount in contributions do
		if player.Parent and amount > bestPoints then
			best = player
			bestPoints = amount
		end
	end
	return best
end

-- ===== Echar frutas a la máquina =====

local function isNearMachine(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	return (root.Position - machinePosition).Magnitude <= GameConfig.StormMachineDistance
end

local function donate(player: Player, kind: any, slotKey: any)
	if (kind ~= "fruits" and kind ~= "iceCreams") or type(slotKey) ~= "string" then
		return
	end
	if not isNearMachine(player) then
		Notifier.send(player, "Acércate a la máquina de tormentas.", "error", "Error")
		return
	end
	if phase == "Storm" then
		Notifier.send(player, "Ya hay una tormenta en marcha.", "error", "Error")
		return
	end
	if phase == "Cooldown" then
		Notifier.send(player, `La máquina se está recargando: {Format.time(phaseEndsAt - os.clock())}.`, "error", "Error")
		return
	end
	-- Lo ofrecido en un intercambio no se puede gastar a medias
	if TradeService.isTrading(player) then
		Notifier.send(player, "Termina o cancela el intercambio primero.", "error", "Error")
		return
	end

	local item = PlacementService.getItem(player, kind, slotKey)
	if not item then
		return
	end
	local earned = Economy.stormPoints(kind, item.id)
	-- Al retirarlo, el dueño recibe lo que tuviera acumulado
	if not PlacementService.removeItem(player, kind, slotKey) then
		return
	end

	points += earned
	contributions[player] = (contributions[player] or 0) + earned
	Effects.burst(fillPart, STORM_COLOR, 25)

	local character = CharacterConfig.ById[item.id]
	local name = if kind == "iceCreams" then `el helado de {character.flavor}` else character.name
	Notifier.send(player, `Echaste {name} a la máquina: +{earned} puntos.`, "success")

	if points >= GameConfig.StormGoal then
		local top = getTopDonor()
		local credit = if top then ` Gracias a {top.DisplayName}.` else ""
		startStorm(`¡TORMENTA DE MUTACIONES! Los rayos mutan a las frutas de la banda.{credit}`)
	else
		refresh()
	end
end

-- Tormenta comprada con Robux: empieza ya, sin llenar la máquina ni esperar el descanso.
-- Si ya hay una en marcha, queda en cola y empieza al terminar esa.
function StormService.requestPaidStorm(player: Player)
	if phase == "Storm" then
		queuedStorms += 1
		Notifier.send(player, "Ya hay una tormenta: la tuya empezará en cuanto termine.", "info")
	else
		startStorm(`¡TORMENTA DE MUTACIONES! Regalo de {player.DisplayName}.`)
	end
end

function StormService.start(map: MapBuilder.MapInfo)
	if started then
		return
	end
	started = true

	buildMachine(map)
	refresh()

	-- En Studio la primera tormenta sola llega enseguida, para poder probarla
	if RunService:IsStudio() and GameConfig.StudioFirstStormDelay > 0 then
		scheduleNaturalStorm(GameConfig.StudioFirstStormDelay)
	else
		scheduleNaturalStorm()
	end

	Remotes.get("StormAction").OnServerEvent:Connect(function(player, action, ...)
		if action ~= "Donate" then
			return
		end
		local now = os.clock()
		if now - (lastAction[player] or 0) < ACTION_INTERVAL then
			return
		end
		lastAction[player] = now

		local ok, message = pcall(donate, player, ...)
		if not ok then
			warn(`[StormService] Error al echar algo a la máquina ({player.Name}): {message}`)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		contributions[player] = nil
		lastAction[player] = nil
	end)

	-- Reloj: cuentas atrás, fin del descanso y tormentas solas
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			if phase == "Cooldown" and now >= phaseEndsAt then
				phase = "Charging"
			end
			if phase == "Charging" and now >= nextNaturalStormAt then
				startStorm("¡TORMENTA DE MUTACIONES! Los rayos mutan a las frutas de la banda.")
			else
				refresh()
			end
		end
	end)
end

return StormService
