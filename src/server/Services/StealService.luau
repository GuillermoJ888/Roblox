-- Robo de frutas y helados. Un jugador mantiene E sobre algo de una base ajena que no esté
-- bloqueada, lo carga sobre la cabeza y debe llevarlo hasta su propia base.
-- Si lo golpean, muere o se va, lo robado vuelve con su dueño.
--
-- Mientras dura el robo, la casilla del dueño y la del ladrón quedan apartadas, para que
-- lo robado siempre tenga un sitio al que volver o en el que quedarse.
--
--   StealService.isInvolved(player)  -> true si está robando o le están robando ahora mismo
--   StealService.cancelFor(player)   -> si está cargando algo, lo devuelve a su dueño

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CharacterConfig = require(Shared.Config.CharacterConfig)
local GameConfig = require(Shared.Config.GameConfig)

local BaseService = require(script.Parent.BaseService)
local CombatService = require(script.Parent.CombatService)
local DataService = require(script.Parent.DataService)
local Notifier = require(script.Parent.Notifier)
local PlacementService = require(script.Parent.PlacementService)
local CharacterBuilder = require(script.Parent.Parent.World.CharacterBuilder)
local IceCreamBuilder = require(script.Parent.Parent.World.IceCreamBuilder)
local InfoBillboard = require(script.Parent.Parent.World.InfoBillboard)

type Carry = {
	thief: Player,
	victim: Player,
	kind: PlacementService.Kind,
	item: DataService.Item,
	victimSlot: string, -- casilla apartada en la base del dueño, por si hay que devolverlo
	thiefSlot: string, -- casilla apartada en la base del ladrón, para cuando llegue
	model: Model?,
	connections: { RBXScriptConnection },
}

-- El cliente solo muestra estos botones a quien NO es el dueño (ver PromptController)
local OTHERS_PROMPT_TAG = "OthersPrompt"
local PROMPT_DISTANCE = 10
-- Margen sobre la distancia del botón, por el retraso de red
local DISTANCE_TOLERANCE = 6
local CARRY_SCALE = 0.6 -- lo robado se lleva en pequeño
local CARRY_HEIGHT = 4.5 -- altura sobre el centro del ladrón

local StealService = {}

-- Robos en curso, por ladrón (cada jugador solo puede cargar una cosa)
local carries: { [Player]: Carry } = {}
local lastSteal: { [Player]: number } = {}
local started = false

local function describe(kind: PlacementService.Kind, item: DataService.Item): string
	local character = CharacterConfig.ById[item.id]
	return if kind == "iceCreams" then `el helado de {character.flavor}` else character.name
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Versión pequeña y sin físicas del modelo, para llevarla soldada al ladrón
local function buildCarryModel(carry: Carry): Model
	local item = carry.item
	local model = if carry.kind == "iceCreams"
		then IceCreamBuilder.create(item.id, item.mutation)
		else CharacterBuilder.createBare(item.id, item.mutation)

	-- Dos Humanoid en el mismo cuerpo se estorban: el del modelo cargado se quita
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Destroy()
	end
	local info = model:FindFirstChild("Info")
	if info then
		info:Destroy()
	end
	pcall(function()
		model:ScaleTo(CARRY_SCALE)
	end)

	local root = model.PrimaryPart :: BasePart
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			if descendant ~= root then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = descendant
				weld.Parent = descendant
			end
		elseif descendant:IsA("ProximityPrompt") then
			descendant:Destroy()
		end
	end

	InfoBillboard.create(model, root, {
		{ text = "ROBADO", color = Color3.fromRGB(255, 110, 110) },
		{ text = `a {carry.victim.DisplayName}`, color = Color3.new(1, 1, 1) },
	}, 3)
	return model
end

local function attachCarryModel(carry: Carry)
	local model = buildCarryModel(carry)
	local thiefRoot = getRoot(carry.thief)
	local root = model.PrimaryPart
	-- Mientras se creaba el modelo pudo terminar el robo
	if carries[carry.thief] ~= carry or not thiefRoot or not root then
		model:Destroy()
		return
	end

	model:PivotTo(thiefRoot.CFrame * CFrame.new(0, CARRY_HEIGHT, 0))
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
		end
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = thiefRoot
	weld.Part1 = root
	weld.Parent = root

	carry.model = model
	model.Parent = carry.thief.Character
end

-- Termina el robo sin decidir a quién va lo robado (eso lo hace quien llama)
local function endCarry(carry: Carry)
	if carries[carry.thief] == carry then
		carries[carry.thief] = nil
	end
	carry.thief:SetAttribute("Carrying", nil)
	for _, connection in carry.connections do
		connection:Disconnect()
	end
	if carry.model then
		carry.model:Destroy()
		carry.model = nil
	end
end

-- Lo robado vuelve a la casilla de su dueño
local function returnToOwner(thief: Player, thiefMessage: string)
	local carry = carries[thief]
	if not carry then
		return
	end
	endCarry(carry)
	PlacementService.release(thief, carry.kind, carry.thiefSlot)

	local name = describe(carry.kind, carry.item)
	local victim = carry.victim
	if not PlacementService.placeReserved(victim, carry.kind, carry.victimSlot, carry.item) then
		-- La casilla apartada ya no sirve: se intenta en cualquier otra
		PlacementService.release(victim, carry.kind, carry.victimSlot)
		PlacementService.addItem(victim, carry.kind, carry.item)
	end
	if victim.Parent then
		Notifier.send(victim, `¡Recuperaste {name}!`, "success")
	end
	if thief.Parent then
		Notifier.send(thief, thiefMessage, "error", "Error")
	end
end

-- El ladrón llegó a su base: lo robado pasa a ser suyo
local function deliver(thief: Player)
	local carry = carries[thief]
	if not carry then
		return
	end
	endCarry(carry)
	PlacementService.release(carry.victim, carry.kind, carry.victimSlot)

	local name = describe(carry.kind, carry.item)
	if PlacementService.placeReserved(thief, carry.kind, carry.thiefSlot, carry.item) then
		Notifier.send(thief, `¡Robo completado! Ahora {name} es tuyo.`, "success", "Steal")
		if carry.victim.Parent then
			Notifier.send(carry.victim, `{thief.DisplayName} se llevó {name}.`, "error", "Steal")
		end
	else
		-- No debería pasar (la casilla estaba apartada): antes que perderlo, vuelve con su dueño
		PlacementService.release(thief, carry.kind, carry.thiefSlot)
		PlacementService.addItem(carry.victim, carry.kind, carry.item)
		Notifier.send(thief, "No había sitio en tu base. Lo robado volvió con su dueño.", "error")
	end
end

local function trySteal(thief: Player, victim: Player, kind: PlacementService.Kind, slotKey: string, uid: string)
	if thief == victim or not victim.Parent then
		return
	end
	local item = PlacementService.getItem(victim, kind, slotKey)
	local model = PlacementService.getModel(victim, kind, slotKey)
	if not item or item.uid ~= uid or not model then
		return -- ya no está ahí
	end

	local thiefRoot = getRoot(thief)
	local character = thief.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not thiefRoot or not humanoid or humanoid.Health <= 0 then
		return
	end
	if (thiefRoot.Position - model:GetPivot().Position).Magnitude > PROMPT_DISTANCE + DISTANCE_TOLERANCE then
		return
	end

	if carries[thief] then
		Notifier.send(thief, "Ya estás cargando algo. Llévalo a tu base primero.", "error", "Error")
		return
	end
	local remaining = GameConfig.StealCooldown - (os.clock() - (lastSteal[thief] or -math.huge))
	if remaining > 0 then
		Notifier.send(thief, `Espera {math.ceil(remaining)} s para volver a robar.`, "error", "Error")
		return
	end

	local victimBase = BaseService.getBase(victim)
	if not victimBase or BaseService.isLocked(victimBase) then
		Notifier.send(thief, "Esta base está bloqueada.", "error", "Error")
		return
	end
	if not PlacementService.isLoaded(thief) then
		return
	end

	local thiefSlot = PlacementService.reserve(thief, kind)
	if not thiefSlot then
		local place = if kind == "iceCreams" then "Tu vitrina de helados" else "Tu base"
		Notifier.send(thief, `{place} está llena: no tienes dónde ponerlo.`, "error", "Error")
		return
	end

	-- A partir de aquí el robo empieza. Al retirarlo, el dueño recibe lo que tuviera acumulado.
	local removed = PlacementService.removeItem(victim, kind, slotKey)
	if not removed then
		PlacementService.release(thief, kind, thiefSlot)
		return
	end
	-- La casilla del dueño queda apartada por si lo recupera
	PlacementService.reserve(victim, kind, slotKey)

	local carry: Carry = {
		thief = thief,
		victim = victim,
		kind = kind,
		item = removed,
		victimSlot = slotKey,
		thiefSlot = thiefSlot,
		model = nil,
		connections = {},
	}
	carries[thief] = carry
	lastSteal[thief] = os.clock()
	thief:SetAttribute("Carrying", true)

	table.insert(carry.connections, humanoid.Died:Connect(function()
		returnToOwner(thief, "Te derrotaron: lo robado volvió con su dueño.")
	end))
	table.insert(carry.connections, thief.CharacterRemoving:Connect(function()
		returnToOwner(thief, "Lo robado volvió con su dueño.")
	end))

	task.spawn(attachCarryModel, carry)

	local name = describe(kind, removed)
	Notifier.send(thief, `¡Tienes {name}! Llévalo a tu base sin que te golpeen.`, "success", "Steal")
	Notifier.send(victim, `¡{thief.DisplayName} te está robando {name}! Golpéalo para recuperarlo.`, "error", "Steal")
end

-- true si el jugador está dentro del terreno de su propia base
local function isInOwnBase(player: Player): boolean
	local base = BaseService.getBase(player)
	local root = getRoot(player)
	if not base or not root then
		return false
	end
	local localPosition = base.info.origin:PointToObjectSpace(root.Position)
	local size = base.info.size
	return math.abs(localPosition.X) <= size.X / 2 and math.abs(localPosition.Z) <= size.Z / 2
end

function StealService.isInvolved(player: Player): boolean
	if carries[player] then
		return true
	end
	for _, carry in carries do
		if carry.victim == player then
			return true
		end
	end
	return false
end

function StealService.cancelFor(player: Player)
	returnToOwner(player, "Lo robado volvió con su dueño.")
end

function StealService.start()
	if started then
		return
	end
	started = true

	-- Todo lo que hay en una base recibe el botón de robar (solo lo ven los que no son el dueño)
	PlacementService.onItemShown(function(owner, kind, slotKey, model, item)
		local part = model.PrimaryPart
		if not part then
			return
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "StealPrompt"
		prompt.ActionText = "Robar"
		prompt.ObjectText = describe(kind, item)
		prompt.HoldDuration = GameConfig.StealHoldDuration
		prompt.MaxActivationDistance = PROMPT_DISTANCE
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("OwnerUserId", owner.UserId)
		prompt:AddTag(OTHERS_PROMPT_TAG)
		prompt.Parent = part

		prompt.Triggered:Connect(function(player)
			trySteal(player, owner, kind, slotKey, item.uid)
		end)
	end)

	-- Un golpe con cualquier arma hace soltar lo robado
	CombatService.PlayerHit:Connect(function(attacker, target)
		if carries[target] then
			returnToOwner(target, `¡{attacker.DisplayName} te golpeó! Lo robado volvió con su dueño.`)
		end
	end)

	-- Antes del guardado final de quien se va
	DataService.onPlayerLeaving(function(player, data)
		-- Si era ladrón, lo que cargaba vuelve con su dueño
		returnToOwner(player, "")
		-- Si era víctima, lo que le estaban robando vuelve directamente a sus datos
		for _, carry in carries do
			if carry.victim == player then
				endCarry(carry)
				PlacementService.release(carry.thief, carry.kind, carry.thiefSlot)
				local container = (data :: any)[carry.kind]
				local maxSlots = if carry.kind == "iceCreams" then GameConfig.IceCreamSlots else GameConfig.MaxFruitSlots
				local slotKey = if container[carry.victimSlot] == nil
					then carry.victimSlot
					else DataService.findFreeSlot(container, maxSlots)
				if slotKey then
					container[slotKey] = carry.item
				end
				Notifier.send(carry.thief, "El dueño se fue del juego y se llevó lo que le robabas.", "error")
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		returnToOwner(player, "")
		lastSteal[player] = nil
	end)

	-- Comprueba si algún ladrón ya llegó a su base
	task.spawn(function()
		while true do
			task.wait(0.2)
			for thief in carries do
				if isInOwnBase(thief) then
					deliver(thief)
				end
			end
		end
	end)
end

return StealService
