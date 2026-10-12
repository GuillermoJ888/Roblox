-- Decide qué botones de acción (los de pulsar E) ve este jugador.
--
-- El servidor marca los botones con una etiqueta y les pone el atributo OwnerUserId:
--   "OwnerPrompt"  -> solo para el dueño de la base (congelar, sacar...)
--   "OthersPrompt" -> solo para los que NO son el dueño (robar)
-- Aquí se ocultan a quien no corresponde. Es solo comodidad visual: el servidor vuelve
-- a comprobar quién pulsa.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local OWNER_PROMPT_TAG = "OwnerPrompt"
local OTHERS_PROMPT_TAG = "OthersPrompt"

local PromptController = {}

local player = Players.LocalPlayer
local started = false

-- forOwner: true si el botón es para el dueño, false si es para los demás
local function watch(tag: string, forOwner: boolean)
	local function apply(instance: Instance)
		if not instance:IsA("ProximityPrompt") then
			return
		end
		local function update()
			local isOwner = instance:GetAttribute("OwnerUserId") == player.UserId
			instance.Enabled = isOwner == forOwner
		end
		-- El atributo puede llegar un instante después que el botón
		instance:GetAttributeChangedSignal("OwnerUserId"):Connect(update)
		update()
	end

	CollectionService:GetInstanceAddedSignal(tag):Connect(apply)
	for _, instance in CollectionService:GetTagged(tag) do
		apply(instance)
	end
end

function PromptController.start()
	if started then
		return
	end
	started = true

	watch(OWNER_PROMPT_TAG, true)
	watch(OTHERS_PROMPT_TAG, false)
end

return PromptController
