-- Intercambio entre dos jugadores, sin estafas:
--   1. Uno invita y el otro acepta la invitación.
--   2. Cada uno pone frutas, helados o dinero. Los dos ven siempre la oferta completa.
--   3. El intercambio no avanza hasta que LOS DOS pulsan "Aceptar".
--   4. Entonces corre una cuenta atrás (GameConfig.TradeCancelWindow) en la que cualquiera puede cancelar.
--   5. Si alguien cambia algo de la oferta, se anulan las dos aceptaciones y la cuenta atrás.
--   6. Al terminar la cuenta, el servidor vuelve a comprobar todo y hace el cambio completo de una vez.
--      O se hace entero, o no se hace nada.
--
-- El cliente solo pide cosas; todo se valida aquí.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local Notifier = require(script.Parent.Notifier)
local PlacementService = require(script.Parent.PlacementService)

type OfferedItem = { kind: PlacementService.Kind, slotKey: string, uid: string }

type Offer = {
	money: number,
	items: { [string]: OfferedItem }, -- por uid
}

type Session = {
	players: { Player },
	offers: { [Player]: Offer },
	accepted: { [Player]: boolean },
	executeAt: number?, -- hora del servidor a la que se ejecuta, si los dos aceptaron
}

type Request = { from: Player, expires: number }

local KINDS: { PlacementService.Kind } = { "fruits", "iceCreams" }
local MAX_OFFERED_ITEMS = 14
local ACTION_INTERVAL = 0.1 -- segundos mínimos entre acciones de un mismo jugador

local TradeService = {}

local updateRemote = Remotes.get("TradeUpdate")
local sessionByPlayer: { [Player]: Session } = {}
local requestByTarget: { [Player]: Request } = {}
local lastAction: { [Player]: number } = {}
local lastRequest: { [Player]: number } = {}
local started = false

local function getOther(session: Session, player: Player): Player
	return if session.players[1] == player then session.players[2] else session.players[1]
end

local function isReady(player: Player): boolean
	return player.Parent ~= nil and DataService.getData(player) ~= nil and PlacementService.isLoaded(player)
end

-- Quita de la oferta lo que el jugador ya no tiene y devuelve la lista para mostrar
local function serializeOffer(player: Player, offer: Offer): { [string]: any }
	local items = {}
	for uid, offered in offer.items do
		local item = PlacementService.getItem(player, offered.kind, offered.slotKey)
		if item and item.uid == uid then
			table.insert(items, {
				kind = offered.kind,
				slotKey = offered.slotKey,
				id = item.id,
				mutation = item.mutation,
				uid = uid,
			})
		else
			offer.items[uid] = nil
		end
	end
	table.sort(items, function(a, b)
		return a.uid < b.uid
	end)
	return { money = offer.money, items = items }
end

local function sendState(session: Session)
	for _, player in session.players do
		local other = getOther(session, player)
		updateRemote:FireClient(player, "State", {
			partnerName = other.DisplayName,
			partnerUserId = other.UserId,
			mine = serializeOffer(player, session.offers[player]),
			theirs = serializeOffer(other, session.offers[other]),
			mineAccepted = session.accepted[player],
			theirsAccepted = session.accepted[other],
			executeAt = session.executeAt,
		})
	end
end

local function close(session: Session, text: string, kind: Notifier.Kind, sound: string?)
	for _, player in session.players do
		if sessionByPlayer[player] == session then
			sessionByPlayer[player] = nil
		end
		if player.Parent then
			updateRemote:FireClient(player, "Closed")
			Notifier.send(player, text, kind, sound)
		end
	end
end

-- Cualquier cambio en la oferta anula las aceptaciones y la cuenta atrás
local function resetAccepted(session: Session)
	for _, player in session.players do
		session.accepted[player] = false
	end
	session.executeAt = nil
end

local function isOfferEmpty(offer: Offer): boolean
	return offer.money <= 0 and next(offer.items) == nil
end

local function countByKind(offer: Offer): { [string]: number }
	local counts = { fruits = 0, iceCreams = 0 }
	for _, offered in offer.items do
		counts[offered.kind] += 1
	end
	return counts
end

-- Comprueba que el intercambio se puede hacer entero. Devuelve nil si todo está bien,
-- o el motivo por el que no se puede.
local function validate(session: Session): string?
	for _, player in session.players do
		if not isReady(player) then
			return "Uno de los jugadores ya no está disponible."
		end
		local offer = session.offers[player]
		if offer.money > DataService.getMoney(player) then
			return `{player.DisplayName} ya no tiene el dinero que ofreció.`
		end
		for uid, offered in offer.items do
			local item = PlacementService.getItem(player, offered.kind, offered.slotKey)
			if not item or item.uid ~= uid then
				return `{player.DisplayName} ya no tiene algo de lo que ofreció.`
			end
		end
	end

	-- Cada uno necesita sitio para lo que recibe (lo que entrega deja hueco)
	for _, player in session.players do
		local giving = countByKind(session.offers[player])
		local receiving = countByKind(session.offers[getOther(session, player)])
		for _, kind in KINDS do
			if PlacementService.countFree(player, kind) + giving[kind] < receiving[kind] then
				local place = if kind == "iceCreams" then "la vitrina de helados" else "la base"
				return `{player.DisplayName} no tiene sitio en {place}.`
			end
		end
	end
	return nil
end

local function execute(session: Session)
	local problem = validate(session)
	if problem then
		close(session, `Intercambio cancelado: {problem}`, "error", "Error")
		return
	end

	-- Primero se retira todo de los dos lados; así queda hueco para lo que llega
	local taken: { [Player]: { { kind: PlacementService.Kind, item: DataService.Item } } } = {}
	for _, player in session.players do
		local list = {}
		for _, offered in session.offers[player].items do
			local item = PlacementService.removeItem(player, offered.kind, offered.slotKey)
			if item then
				table.insert(list, { kind = offered.kind, item = item })
			end
		end
		taken[player] = list
	end

	for _, player in session.players do
		local other = getOther(session, player)
		local money = session.offers[player].money
		if money > 0 and DataService.trySpend(player, money) then
			DataService.addMoney(other, money)
		end
		for _, entry in taken[player] do
			if not PlacementService.addItem(other, entry.kind, entry.item) then
				-- No debería pasar (se comprobó el sitio): antes que perderlo, vuelve con su dueño
				warn(`[TradeService] Sin sitio para entregar a {other.Name}; se devuelve a {player.Name}`)
				PlacementService.addItem(player, entry.kind, entry.item)
			end
		end
	end

	close(session, "¡Intercambio completado!", "success", "Trade")
end

-- ===== Acciones que pide el cliente =====

local actions: { [string]: (player: Player, ...any) -> () } = {}

function actions.Request(player: Player, targetUserId: any)
	if type(targetUserId) ~= "number" then
		return
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or target == player then
		return
	end
	if os.clock() - (lastRequest[player] or 0) < 2 then
		return
	end
	lastRequest[player] = os.clock()

	if sessionByPlayer[player] then
		Notifier.send(player, "Ya estás en un intercambio.", "error")
		return
	end
	if not isReady(player) or not isReady(target) then
		Notifier.send(player, "Ese jugador todavía no está listo.", "error")
		return
	end
	if sessionByPlayer[target] then
		Notifier.send(player, `{target.DisplayName} está en otro intercambio.`, "error")
		return
	end

	requestByTarget[target] = { from = player, expires = os.clock() + GameConfig.TradeRequestTimeout }
	updateRemote:FireClient(target, "Request", {
		fromName = player.DisplayName,
		fromUserId = player.UserId,
		timeout = GameConfig.TradeRequestTimeout,
	})
	Notifier.send(player, `Invitación enviada a {target.DisplayName}.`, "info")
end

function actions.Respond(player: Player, accept: any)
	local request = requestByTarget[player]
	requestByTarget[player] = nil
	if not request or os.clock() > request.expires then
		return
	end
	local from = request.from
	if not from.Parent then
		return
	end
	if accept ~= true then
		Notifier.send(from, `{player.DisplayName} rechazó el intercambio.`, "info")
		return
	end
	if sessionByPlayer[player] or sessionByPlayer[from] or not isReady(player) or not isReady(from) then
		Notifier.send(player, "El intercambio ya no está disponible.", "error")
		return
	end

	local session: Session = {
		players = { from, player },
		offers = {
			[from] = { money = 0, items = {} },
			[player] = { money = 0, items = {} },
		},
		accepted = { [from] = false, [player] = false },
		executeAt = nil,
	}
	sessionByPlayer[from] = session
	sessionByPlayer[player] = session
	sendState(session)
end

function actions.SetMoney(player: Player, amount: any)
	local session = sessionByPlayer[player]
	if not session or type(amount) ~= "number" or amount ~= amount or amount < 0 then
		return
	end
	-- Nunca se puede ofrecer más de lo que se tiene
	session.offers[player].money = math.floor(math.min(amount, DataService.getMoney(player)))
	resetAccepted(session)
	sendState(session)
end

function actions.ToggleItem(player: Player, kind: any, slotKey: any)
	local session = sessionByPlayer[player]
	if not session or type(slotKey) ~= "string" or (kind ~= "fruits" and kind ~= "iceCreams") then
		return
	end
	local item = PlacementService.getItem(player, kind, slotKey)
	if not item then
		return
	end

	local offer = session.offers[player]
	if offer.items[item.uid] then
		offer.items[item.uid] = nil
	else
		local count = 0
		for _ in offer.items do
			count += 1
		end
		if count >= MAX_OFFERED_ITEMS then
			return
		end
		offer.items[item.uid] = { kind = kind, slotKey = slotKey, uid = item.uid }
	end
	resetAccepted(session)
	sendState(session)
end

function actions.Accept(player: Player)
	local session = sessionByPlayer[player]
	if not session or session.accepted[player] then
		return
	end
	local other = getOther(session, player)
	if isOfferEmpty(session.offers[player]) and isOfferEmpty(session.offers[other]) then
		Notifier.send(player, "Nadie ha ofrecido nada todavía.", "error")
		return
	end

	session.accepted[player] = true
	if session.accepted[other] then
		session.executeAt = Workspace:GetServerTimeNow() + GameConfig.TradeCancelWindow
	end
	sendState(session)
end

function actions.Unaccept(player: Player)
	local session = sessionByPlayer[player]
	if session then
		resetAccepted(session)
		sendState(session)
	end
end

function actions.Cancel(player: Player)
	local session = sessionByPlayer[player]
	if session then
		close(session, `{player.DisplayName} canceló el intercambio.`, "info")
	end
end

-- ===== API para otros sistemas =====

function TradeService.isTrading(player: Player): boolean
	return sessionByPlayer[player] ~= nil
end

function TradeService.cancelFor(player: Player, reason: string)
	local session = sessionByPlayer[player]
	if session then
		close(session, reason, "info")
	end
end

function TradeService.start()
	if started then
		return
	end
	started = true

	Remotes.get("TradeAction").OnServerEvent:Connect(function(player, action, ...)
		local handler = if type(action) == "string" then actions[action] else nil
		if not handler then
			return
		end
		local now = os.clock()
		if now - (lastAction[player] or 0) < ACTION_INTERVAL then
			return
		end
		lastAction[player] = now

		local ok, message = pcall(handler, player, ...)
		if not ok then
			warn(`[TradeService] Error en la acción {action} de {player.Name}: {message}`)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		TradeService.cancelFor(player, `{player.DisplayName} salió del juego: intercambio cancelado.`)
		requestByTarget[player] = nil
		lastAction[player] = nil
		lastRequest[player] = nil
	end)

	-- Cuenta atrás de los intercambios aceptados
	task.spawn(function()
		while true do
			task.wait(0.2)
			local now = Workspace:GetServerTimeNow()
			for _, session in sessionByPlayer do
				-- Cada intercambio aparece dos veces (una por jugador): al ejecutarse se cierra y ya no repite
				if session.executeAt and now >= session.executeAt and sessionByPlayer[session.players[1]] == session then
					session.executeAt = nil
					execute(session)
				end
			end
		end
	end)
end

return TradeService
