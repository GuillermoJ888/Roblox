-- RemoteEvents del juego (mensajes entre servidor y cliente).
-- El servidor los crea al arrancar; el cliente espera a que existan.
--
-- Para añadir uno nuevo, pon su nombre en la lista NAMES.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	-- servidor -> cliente
	"Notify", -- (texto, tipo, sonido?) aviso corto. tipo: "info" | "success" | "error"
	"Announce", -- (texto, color, sonido?) aviso grande para todos
	"Inventory", -- (resumen) lo que tiene el jugador: frutas, helados, congelador, herramientas
	"OpenShop", -- () abre el menú de Cocardo
	"OpenStorm", -- () abre el menú de la máquina de tormentas
	"TradeUpdate", -- (tipo, datos) estado del intercambio

	-- cliente -> servidor (el servidor valida todo lo que llega)
	"ShopAction", -- (acción, ...) vender, bono diario, comprar herramienta, rebirth
	"TradeAction", -- (acción, ...) pedir, aceptar, ofrecer, confirmar, cancelar
	"StormAction", -- ("Donate", tipo, ranura) echar una fruta o un helado a la máquina de tormentas
	"PassAction", -- ("Buy", idDelPase) pedir la ventana de compra de un pase de Robux
	"ProductAction", -- ("Buy", idDelProducto) pedir la ventana de compra de un producto de Robux
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
