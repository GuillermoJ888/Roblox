-- Compra de personajes. Todo se comprueba en el servidor: que el personaje siga disponible,
-- que el jugador esté cerca, que tenga espacio y que le alcance el dinero.
--
-- El personaje comprado camina hasta la base (DeliveryService). Mientras camina por fuera,
-- otro jugador puede comprarlo y se desvía hacia su base.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Format = require(Shared.Util.Format)

local DataService = require(script.Parent.DataService)
local DeliveryService = require(script.Parent.DeliveryService)
local Notifier = require(script.Parent.Notifier)
local PlacementService = require(script.Parent.PlacementService)
local SpawnerService = require(script.Parent.SpawnerService)

-- Margen sobre la distancia del botón: el personaje se mueve y hay retraso de red
local DISTANCE_TOLERANCE = 8

local PurchaseService = {}

local started = false

local function isCloseEnough(player: Player, model: Model): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	local distance = (root.Position - model:GetPivot().Position).Magnitude
	return distance <= GameConfig.BuyDistance + DISTANCE_TOLERANCE
end

local function tryPurchase(player: Player, uid: string)
	-- El personaje puede estar en la banda o caminando hacia la base de otro jugador
	local beltItem = SpawnerService.getItem(uid)
	local delivery = if beltItem then nil else DeliveryService.get(uid)
	if not beltItem and not delivery then
		return -- ya no está disponible
	end

	local model = if beltItem then beltItem.model else (delivery :: DeliveryService.Delivery).model
	local price = if beltItem then beltItem.price else (delivery :: DeliveryService.Delivery).price
	local name = if beltItem then beltItem.character.name else (delivery :: DeliveryService.Delivery).character.name

	if delivery then
		if delivery.owner == player then
			Notifier.send(player, `{name} ya es tuyo: va camino a tu base.`, "info")
			return
		end
		if not DeliveryService.canRetarget(uid) then
			return -- ya entró en la base de su dueño
		end
	end

	if not DataService.getData(player) then
		Notifier.send(player, "Tus datos aún se están cargando.", "error")
		return
	end
	if not isCloseEnough(player, model) then
		return
	end

	local slotKey = PlacementService.reserveSlot(player)
	if not slotKey then
		Notifier.send(player, "Tu base está llena.", "error", "Error")
		return
	end
	if not DataService.trySpend(player, price) then
		PlacementService.releaseReservation(player, slotKey)
		Notifier.send(player, `Te faltan {Format.money(price - DataService.getMoney(player))}.`, "error", "Error")
		return
	end

	-- A partir de aquí ya está pagado
	if beltItem then
		SpawnerService.take(uid)
		if DeliveryService.begin(beltItem, player, slotKey) then
			Notifier.send(player, `¡Compraste a {name}! Va caminando a tu base.`, "success", "Purchase")
		else
			-- No debería pasar (tener ranura implica tener base), pero nunca se cobra sin entregar
			beltItem.model:Destroy()
			PlacementService.releaseReservation(player, slotKey)
			DataService.addMoney(player, price)
			Notifier.send(player, "No se pudo completar la compra. Se te devolvió el dinero.", "error")
		end
		return
	end

	local previousOwner, previousSlot = DeliveryService.retarget(uid, player, slotKey)
	if not previousOwner or not previousSlot then
		PlacementService.releaseReservation(player, slotKey)
		DataService.addMoney(player, price)
		return
	end

	PlacementService.releaseReservation(previousOwner, previousSlot)
	if GameConfig.RefundOnSnipe and DataService.addMoney(previousOwner, price) then
		Notifier.send(previousOwner, `¡{player.DisplayName} te quitó a {name}! Recuperas {Format.money(price)}.`, "error")
	else
		Notifier.send(previousOwner, `¡{player.DisplayName} te quitó a {name}!`, "error")
	end
	Notifier.send(player, `¡Le quitaste {name} a {previousOwner.DisplayName}! Va caminando a tu base.`, "success", "Purchase")
end

function PurchaseService.start()
	if started then
		return
	end
	started = true

	-- Cada personaje que aparece en la banda recibe su botón de compra.
	-- El mismo botón sigue sirviendo mientras camina hacia una base.
	SpawnerService.ItemSpawned:Connect(function(uid)
		local item = SpawnerService.getItem(uid)
		if not item or not item.model.PrimaryPart then
			return
		end

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Comprar"
		prompt.ObjectText = `{item.character.name} - {Format.money(item.price)}`
		prompt.HoldDuration = 0.25
		prompt.MaxActivationDistance = GameConfig.BuyDistance
		prompt.RequiresLineOfSight = false
		prompt.Parent = item.model.PrimaryPart

		prompt.Triggered:Connect(function(player)
			tryPurchase(player, uid)
		end)
	end)

	-- Si un rayo le pone una mutación mientras va por la banda, cambia su precio
	SpawnerService.ItemChanged:Connect(function(uid)
		local item = SpawnerService.getItem(uid)
		local part = item and item.model.PrimaryPart
		local prompt = part and part:FindFirstChildOfClass("ProximityPrompt")
		if item and prompt then
			prompt.ObjectText = `{item.character.name} - {Format.money(item.price)}`
		end
	end)
end

return PurchaseService
