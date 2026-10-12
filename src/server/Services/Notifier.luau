-- Envía avisos que el jugador ve en pantalla.
--   Notifier.send(player, texto, tipo, sonido)  -> aviso corto ("Te faltan $50", "+$120"...)
--   Notifier.announce(texto, color, sonido)     -> aviso grande para todo el servidor
--
-- sonido: nombre de una entrada de SoundConfig (opcional).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)

export type Kind = "info" | "success" | "error"

local Notifier = {}

local notifyRemote = Remotes.get("Notify")
local announceRemote = Remotes.get("Announce")

function Notifier.send(player: Player, text: string, kind: Kind?, sound: string?)
	notifyRemote:FireClient(player, text, kind or "info", sound)
end

function Notifier.sendAll(text: string, kind: Kind?, sound: string?)
	notifyRemote:FireAllClients(text, kind or "info", sound)
end

function Notifier.announce(text: string, color: Color3?, sound: string?)
	announceRemote:FireAllClients(text, color or Color3.new(1, 1, 1), sound or "Announce")
end

return Notifier
