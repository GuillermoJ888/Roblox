-- Menú de Cocardo: vender frutas y helados, bono diario, tienda de herramientas y rebirth.
-- El cliente solo pide la acción; aquí se comprueba todo antes de dar o quitar nada.
--
-- Todas las acciones exigen estar cerca de Cocardo.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CharacterConfig = require(Shared.Config.CharacterConfig)
local GameConfig = require(Shared.Config.GameConfig)
local ToolConfig = require(Shared.Config.ToolConfig)
local Economy = require(Shared.Economy)
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Util.Format)

local CoconutService = require(script.Parent.CoconutService)
local CombatService = require(script.Parent.CombatService)
local DataService = require(script.Parent.DataService)
local DeliveryService = require(script.Parent.DeliveryService)
local FreezerService = require(script.Parent.FreezerService)
local Notifier = require(script.Parent.Notifier)
local PlacementService = require(script.Parent.PlacementService)
local StealService = require(script.Parent.StealService)
local TradeService = require(script.Parent.TradeService)
local Prompts = require(script.Parent.Parent.World.Prompts)

local ACTION_INTERVAL = 0.15 -- segundos mínimos entre acciones de un mismo jugador
local MAX_SLOTS = { fruits = GameConfig.MaxFruitSlots, iceCreams = GameConfig.IceCreamSlots }

local ShopService = {}

local started = false
local lastAction: { [Player]: number } = {}

local function isKind(value: any): boolean
	return value == "fruits" or value == "iceCreams"
end

-- Vende lo que hay en una ranura. Devuelve el dinero obtenido (0 si no había nada).
-- quick: true si se vende desde la propia base (paga menos que Cocardo).
local function sellSlot(player: Player, kind: PlacementService.Kind, slotKey: string, quick: boolean?): number
	local item = PlacementService.getItem(player, kind, slotKey)
	if not item then
		return 0
	end
	local price = if quick
		then Economy.quickSellPrice(kind, item.id, item.mutation)
		else Economy.sellPrice(kind, item.id, item.mutation)
	if not PlacementService.removeItem(player, kind, slotKey) then
		return 0
	end
	DataService.addMoney(player, price)
	return price
end

-- Venta rápida: el dueño vende algo de su base sin ir hasta Cocardo
local function quickSell(player: Player, kind: PlacementService.Kind, slotKey: string, uid: string)
	local item = PlacementService.getItem(player, kind, slotKey)
	if not item or item.uid ~= uid then
		return
	end
	-- Lo ofrecido en un intercambio no se puede vender a medias
	if TradeService.isTrading(player) then
		Notifier.send(player, "Termina o cancela el intercambio primero.", "error", "Error")
		return
	end
	local character = CharacterConfig.ById[item.id]
	local name = if kind == "iceCreams" then `el helado de {character.flavor}` else character.name
	local earned = sellSlot(player, kind, slotKey, true)
	if earned > 0 then
		Notifier.send(player, `Vendiste {name} por {Format.money(earned)}.`, "success", "Sell")
	end
end

local actions: { [string]: (player: Player, ...any) -> () } = {}

function actions.Sell(player: Player, kind: any, slotKey: any)
	if not isKind(kind) or type(slotKey) ~= "string" then
		return
	end
	local item = PlacementService.getItem(player, kind, slotKey)
	if not item then
		return
	end
	local character = CharacterConfig.ById[item.id]
	local name = if kind == "iceCreams" then `el helado de {character.flavor}` else character.name
	local earned = sellSlot(player, kind, slotKey)
	if earned > 0 then
		Notifier.send(player, `Vendiste {name} por {Format.money(earned)}.`, "success", "Sell")
	end
end

function actions.SellAll(player: Player, kind: any)
	if not isKind(kind) then
		return
	end
	local total = 0
	local count = 0
	for slot = 1, MAX_SLOTS[kind] do
		local earned = sellSlot(player, kind, tostring(slot))
		if earned > 0 then
			total += earned
			count += 1
		end
	end
	if count > 0 then
		local what = if kind == "iceCreams" then "helados" else "frutas"
		Notifier.send(player, `Vendiste {count} {what} por {Format.money(total)}.`, "success", "Sell")
	end
end

function actions.DailyBonus(player: Player)
	local data = DataService.getData(player)
	if not data then
		return
	end
	local remaining = data.lastDailyBonus + GameConfig.DailyBonusCooldown - os.time()
	if remaining > 0 then
		Notifier.send(player, `Tu próximo bono estará listo en {Format.time(remaining)}.`, "error", "Error")
		return
	end
	local amount = Economy.dailyBonus(data.rebirths)
	data.lastDailyBonus = os.time()
	DataService.addMoney(player, amount)
	Notifier.send(player, `¡Bono diario! +{Format.money(amount)}`, "success", "Collect")
end

function actions.BuyTool(player: Player, toolId: any)
	local data = DataService.getData(player)
	local tool = if type(toolId) == "string" then ToolConfig.ById[toolId] else nil
	if not data or not tool then
		return
	end
	if tool.id == ToolConfig.DefaultWeaponId or data.tools[tool.id] then
		Notifier.send(player, `Ya tienes {tool.name}.`, "info")
		return
	end
	if not DataService.trySpend(player, tool.price) then
		Notifier.send(player, `Te faltan {Format.money(tool.price - DataService.getMoney(player))}.`, "error", "Error")
		return
	end
	data.tools[tool.id] = true
	CombatService.refresh(player)
	Notifier.send(player, `¡Compraste {tool.name}!`, "success", "Purchase")
end

function actions.Rebirth(player: Player)
	local data = DataService.getData(player)
	if not data then
		return
	end
	if StealService.isInvolved(player) then
		Notifier.send(player, "No puedes hacer rebirth mientras hay un robo en curso.", "error", "Error")
		return
	end

	-- Lo acumulado en la base cuenta para llegar al precio
	PlacementService.collect(player)
	local cost = Economy.rebirthCost(data.rebirths)
	if data.money < cost then
		Notifier.send(player, `Te faltan {Format.money(cost - data.money)} para el rebirth.`, "error", "Error")
		return
	end

	-- Se reinicia el dinero y todos los personajes; las herramientas compradas se conservan
	DeliveryService.cancelFor(player)
	PlacementService.clearAll(player)
	FreezerService.clearAll(player)
	data.rebirths += 1
	DataService.setMoney(player, GameConfig.StartingMoney)
	DataService.refreshLeaderstats(player)

	local bonus = math.round((Economy.rebirthMultiplier(data.rebirths) - 1) * 100)
	Notifier.send(player, `¡Rebirth {data.rebirths}! Ahora ganas +{bonus} % en todo.`, "success")
	Notifier.announce(`{player.DisplayName} hizo su rebirth número {data.rebirths}`, Color3.fromRGB(255, 200, 80))
end

function ShopService.start()
	if started then
		return
	end
	started = true

	-- Cada fruta y helado de una base recibe el botón de venta rápida (tecla F, solo para el dueño).
	-- Va desplazado hacia abajo para no tapar el botón de congelar.
	PlacementService.onItemShown(function(owner, kind, slotKey, model, item)
		local price = Economy.quickSellPrice(kind, item.id, item.mutation)
		Prompts.addOwner(model, owner, {
			actionText = "Vender",
			objectText = Format.money(price),
			holdDuration = 1,
			keyCode = Enum.KeyCode.F,
			gamepadKeyCode = Enum.KeyCode.ButtonY,
			offset = Vector2.new(0, 80),
		}, function()
			quickSell(owner, kind, slotKey, item.uid)
		end)
	end)

	local openRemote = Remotes.get("OpenShop")
	CoconutService.onInteract(function(player)
		openRemote:FireClient(player)
	end)

	Remotes.get("ShopAction").OnServerEvent:Connect(function(player, action, ...)
		local handler = if type(action) == "string" then actions[action] else nil
		if not handler then
			return
		end
		local now = os.clock()
		if now - (lastAction[player] or 0) < ACTION_INTERVAL then
			return
		end
		lastAction[player] = now

		if not CoconutService.isNear(player) then
			Notifier.send(player, `Acércate a {GameConfig.CoconutNpcName} para hacer eso.`, "error", "Error")
			return
		end
		-- Lo ofrecido en un intercambio no se puede vender ni reiniciar a medias
		if TradeService.isTrading(player) then
			Notifier.send(player, "Termina o cancela el intercambio primero.", "error", "Error")
			return
		end

		local ok, message = pcall(handler, player, ...)
		if not ok then
			warn(`[ShopService] Error en la acción {action} de {player.Name}: {message}`)
		end
	end)

	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
	end)
end

return ShopService
