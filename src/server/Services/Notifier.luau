-- Envía avisos cortos que el jugador ve en pantalla ("No tienes suficiente dinero", "+$50"...).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)

export type Kind = "info" | "success" | "error"

local Notifier = {}

local notifyRemote = Remotes.get("Notify")

function Notifier.send(player: Player, text: string, kind: Kind?)
	notifyRemote:FireClient(player, text, kind or "info")
end

function Notifier.sendAll(text: string, kind: Kind?)
	notifyRemote:FireAllClients(text, kind or "info")
end

return Notifier
