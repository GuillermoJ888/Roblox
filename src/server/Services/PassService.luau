-- Pases de juego (compras permanentes con Robux): comprueba cuáles tiene cada jugador,
-- abre la ventana de compra de Roblox y aplica sus efectos.
--
-- Los pagos los gestiona Roblox: aquí nunca se toca dinero real, solo se pregunta
-- "¿este jugador tiene el pase?" y se pide a Roblox que muestre su ventana de compra.
--
--   PassService.owns(player, idDelPase)      -> true si lo tiene
--   PassService.getExtraFruitSlots(player)   -> casillas de fruta extra por sus pases
--   PassService.onChanged(función)           -> aviso cuando un jugador consigue un pase

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PassConfig = require(Shared.Config.PassConfig)
local Remotes = require(Shared.Remotes)

local Notifier = require(script.Parent.Notifier)

local PassService = {}

local started = false
local ownedByPlayer: { [Player]: { [string]: boolean } } = {}
local changedCallbacks: { (Player) -> () } = {}
local lastAction: { [Player]: number } = {}

function PassService.owns(player: Player, passId: string): boolean
	local owned = ownedByPlayer[player]
	return owned ~= nil and owned[passId] == true
end

function PassService.getExtraFruitSlots(player: Player): number
	local total = 0
	for _, pass in PassConfig.List do
		if PassService.owns(player, pass.id) then
			total += pass.extraFruitSlots or 0
		end
	end
	return total
end

function PassService.onChanged(callback: (Player) -> ())
	table.insert(changedCallbacks, callback)
end

-- Publica en el jugador lo que tiene, para que su interfaz lo muestre
local function publish(player: Player)
	for _, pass in PassConfig.List do
		player:SetAttribute(PassConfig.attributeName(pass.id), PassService.owns(player, pass.id) or nil)
	end
	player:SetAttribute("ExtraFruitSlots", PassService.getExtraFruitSlots(player))
end

local function grant(player: Player, pass: PassConfig.Pass)
	local owned = ownedByPlayer[player]
	if not owned or owned[pass.id] then
		return
	end
	owned[pass.id] = true
	publish(player)
	for _, callback in changedCallbacks do
		task.spawn(callback, player)
	end
	Notifier.send(player, `¡Tienes {pass.name}! {pass.description}`, "success", "Purchase")
end

-- Pregunta a Roblox qué pases tiene el jugador al entrar
local function loadPlayer(player: Player)
	if ownedByPlayer[player] then
		return
	end
	local owned = {}
	ownedByPlayer[player] = owned
	publish(player)

	for _, pass in PassConfig.List do
		if pass.gamePassId > 0 then
			local ok, result = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.gamePassId)
			end)
			if ok and result then
				owned[pass.id] = true
			elseif not ok then
				warn(`[PassService] No se pudo comprobar el pase {pass.id} de {player.Name}: {result}`)
			end
		end
	end

	if ownedByPlayer[player] == owned and next(owned) then
		publish(player)
		for _, callback in changedCallbacks do
			task.spawn(callback, player)
		end
	end
end

-- Abre la ventana de compra de Roblox para ese pase
function PassService.promptPurchase(player: Player, passId: string)
	local pass = PassConfig.ById[passId]
	if not pass or not ownedByPlayer[player] then
		return
	end
	if PassService.owns(player, pass.id) then
		Notifier.send(player, `Ya tienes {pass.name}.`, "info")
		return
	end
	if pass.requires and not PassService.owns(player, pass.requires) then
		local required = PassConfig.ById[pass.requires]
		Notifier.send(player, `Primero necesitas {if required then required.name else pass.requires}.`, "error", "Error")
		return
	end

	if pass.gamePassId <= 0 then
		-- El pase aún no existe en Roblox. En Studio se concede gratis para poder probarlo.
		if RunService:IsStudio() then
			Notifier.send(player, "Compra de prueba (solo en Studio): el pase aún no tiene ID.", "info")
			grant(player, pass)
		else
			Notifier.send(player, "Próximamente.", "info")
		end
		return
	end

	MarketplaceService:PromptGamePassPurchase(player, pass.gamePassId)
end

function PassService.start()
	if started then
		return
	end
	started = true

	Players.PlayerAdded:Connect(loadPlayer)
	Players.PlayerRemoving:Connect(function(player)
		ownedByPlayer[player] = nil
		lastAction[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(loadPlayer, player)
	end

	-- Roblox avisa cuando termina una compra hecha dentro del juego
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
		if not wasPurchased then
			return
		end
		for _, pass in PassConfig.List do
			if pass.gamePassId == gamePassId then
				grant(player, pass)
			end
		end
	end)

	Remotes.get("PassAction").OnServerEvent:Connect(function(player, action, passId)
		if action ~= "Buy" or type(passId) ~= "string" then
			return
		end
		local now = os.clock()
		if now - (lastAction[player] or 0) < 0.5 then
			return
		end
		lastAction[player] = now
		PassService.promptPurchase(player, passId)
	end)
end

return PassService
