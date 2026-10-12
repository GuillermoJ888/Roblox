-- Productos de desarrollador (compras con Robux que se pueden repetir): abre la ventana de
-- compra de Roblox y entrega lo comprado cuando Roblox confirma el pago.
--
-- Los pagos los gestiona Roblox: aquí nunca se toca dinero real. Roblox llama a
-- ProcessReceipt cuando un pago se ha cobrado, y solo entonces se entrega el efecto.
--
-- Para añadir un producto con un efecto que ya existe (otro paquete de minutos, por ejemplo)
-- basta con describirlo en ProductConfig. Un efecto nuevo se programa en EFFECTS.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ProductConfig = require(Shared.Config.ProductConfig)
local Remotes = require(Shared.Remotes)

local BoostService = require(script.Parent.BoostService)
local Notifier = require(script.Parent.Notifier)
local StormService = require(script.Parent.StormService)

-- Qué hace cada tipo de efecto (campo effect de ProductConfig). Devuelve true si se entregó.
-- Si devuelve false, el pago queda pendiente y Roblox lo reintenta más tarde.
local EFFECTS: { [string]: (player: Player, product: ProductConfig.Product) -> boolean } = {
	Storm = function(player)
		StormService.requestPaidStorm(player)
		return true
	end,
	Guard = function(player, product)
		return BoostService.addGuard(player, (product.minutes or 0) * 60)
	end,
	SuperFreezer = function(player, product)
		return BoostService.addSuperFreezer(player, (product.minutes or 0) * 60)
	end,
}

local ProductService = {}

local started = false
local lastAction: { [Player]: number } = {}

local function deliver(player: Player, product: ProductConfig.Product): boolean
	local effect = EFFECTS[product.effect]
	if not effect then
		warn(`[ProductService] El producto {product.id} no tiene efecto programado`)
		return false
	end
	local ok, result = pcall(effect, player, product)
	if not ok then
		warn(`[ProductService] Error al entregar {product.id} a {player.Name}: {result}`)
		return false
	end
	return result == true
end

-- Abre la ventana de compra de Roblox para ese producto
function ProductService.promptPurchase(player: Player, id: string)
	local product = ProductConfig.ById[id]
	if not product then
		return
	end
	if product.productId <= 0 then
		-- El producto aún no existe en Roblox. En Studio se concede gratis para poder probarlo.
		if RunService:IsStudio() then
			Notifier.send(player, "Compra de prueba (solo en Studio): el producto aún no tiene ID.", "info")
			deliver(player, product)
		else
			Notifier.send(player, "Próximamente.", "info")
		end
		return
	end
	MarketplaceService:PromptProductPurchase(player, product.productId)
end

function ProductService.start()
	if started then
		return
	end
	started = true

	-- Roblox llama a esta función cada vez que cobra un producto de este juego
	MarketplaceService.ProcessReceipt = function(receipt)
		local player = Players:GetPlayerByUserId(receipt.PlayerId)
		if not player then
			-- Se fue antes de recibirlo: Roblox volverá a intentarlo cuando entre de nuevo
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		for _, product in ProductConfig.List do
			if product.productId == receipt.ProductId then
				if deliver(player, product) then
					return Enum.ProductPurchaseDecision.PurchaseGranted
				end
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
		end
		warn(`[ProductService] Pago de un producto desconocido: {receipt.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	Remotes.get("ProductAction").OnServerEvent:Connect(function(player, action, id)
		if action ~= "Buy" or type(id) ~= "string" then
			return
		end
		local now = os.clock()
		if now - (lastAction[player] or 0) < 0.5 then
			return
		end
		lastAction[player] = now
		ProductService.promptPurchase(player, id)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
	end)
end

return ProductService
