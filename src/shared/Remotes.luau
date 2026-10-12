-- RemoteEvents del juego (mensajes entre servidor y cliente).
-- El servidor los crea al arrancar; el cliente espera a que existan.
--
-- Para añadir uno nuevo, pon su nombre en la lista NAMES.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	"Notify", -- servidor -> cliente: (texto, tipo) con tipo "info" | "success" | "error"
}

local FOLDER_NAME = "Remotes"

local Remotes = {}

local folder: Instance

if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
	end
	for _, name in NAMES do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

function Remotes.get(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

return Remotes
