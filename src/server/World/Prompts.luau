-- Botones de acción (los de pulsar una tecla cerca de algo) que solo ve y usa el dueño de una base.
--
-- El cliente oculta a los demás los botones con la etiqueta "OwnerPrompt" (ver PromptController),
-- pero el servidor nunca se fía del cliente: aquí se vuelve a comprobar quién pulsa y desde dónde.

local PROMPT_DISTANCE = 10
-- Margen sobre la distancia del botón, por el retraso de red
local DISTANCE_TOLERANCE = 6
local OWNER_PROMPT_TAG = "OwnerPrompt"

export type Options = {
	actionText: string,
	objectText: string,
	holdDuration: number?,
	-- Tecla del teclado. Si un modelo tiene dos botones, cada uno necesita una tecla distinta.
	keyCode: Enum.KeyCode?,
	gamepadKeyCode: Enum.KeyCode?,
	-- Desplazamiento en pantalla (píxeles), para que dos botones del mismo modelo no se tapen
	offset: Vector2?,
}

local Prompts = {}

Prompts.Distance = PROMPT_DISTANCE

local function isNear(player: Player, model: Model): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	return (root.Position - model:GetPivot().Position).Magnitude <= PROMPT_DISTANCE + DISTANCE_TOLERANCE
end

-- Añade al modelo un botón que solo funciona para su dueño
function Prompts.addOwner(model: Model, owner: Player, options: Options, onTriggered: () -> ()): ProximityPrompt?
	local part = model.PrimaryPart
	if not part then
		return nil
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = options.actionText
	prompt.ObjectText = options.objectText
	prompt.HoldDuration = options.holdDuration or 0.5
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	if options.keyCode then
		prompt.KeyboardKeyCode = options.keyCode
	end
	if options.gamepadKeyCode then
		prompt.GamepadKeyCode = options.gamepadKeyCode
	end
	if options.offset then
		prompt.UIOffset = options.offset
	end
	prompt:SetAttribute("OwnerUserId", owner.UserId)
	prompt:AddTag(OWNER_PROMPT_TAG)
	prompt.Parent = part

	prompt.Triggered:Connect(function(player)
		if player == owner and isNear(player, model) then
			onTriggered()
		end
	end)
	return prompt
end

return Prompts
