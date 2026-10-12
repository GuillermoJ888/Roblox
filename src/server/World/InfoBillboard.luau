-- Cartel flotante con varias líneas de texto que se coloca sobre un personaje o un helado.

export type Line = {
	text: string,
	color: Color3,
	name: string?, -- nombre de la etiqueta, para poder buscarla después y cambiarle el texto
}

local LINE_HEIGHT = 0.9 -- alto de cada línea, en studs
local WIDTH = 8

local InfoBillboard = {}

-- adornee: pieza sobre la que flota. bottomOffset: distancia de esa pieza al borde inferior del cartel.
function InfoBillboard.create(model: Model, adornee: Instance?, lines: { Line }, bottomOffset: number): BillboardGui
	local height = LINE_HEIGHT * #lines

	local gui = Instance.new("BillboardGui")
	gui.Name = "Info"
	gui.Size = UDim2.fromScale(WIDTH, height)
	gui.StudsOffset = Vector3.new(0, bottomOffset + height / 2, 0)
	gui.MaxDistance = 90
	gui.Adornee = adornee :: any

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = gui

	for order, line in lines do
		local label = Instance.new("TextLabel")
		label.Name = line.name or `Line{order}`
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1 / #lines)
		label.LayoutOrder = order
		label.Text = line.text
		label.TextColor3 = line.color
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.TextStrokeTransparency = 0
		-- Los colores muy oscuros (rareza Secreto) no se leen con borde negro
		local brightness = line.color.R * 0.3 + line.color.G * 0.6 + line.color.B * 0.1
		label.TextStrokeColor3 = if brightness < 0.25 then Color3.new(1, 1, 1) else Color3.new(0, 0, 0)
		label.Parent = gui
	end

	gui.Parent = model
	return gui
end

-- Etiqueta de mutación que flota a un costado del personaje o del helado.
-- Va aparte del cartel principal para que se distinga de un vistazo desde lejos.
function InfoBillboard.addMutationBadge(model: Model, adornee: Instance?, name: string, multiplier: number, color: Color3): BillboardGui
	local old = model:FindFirstChild("MutationBadge")
	if old then
		old:Destroy()
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "MutationBadge"
	gui.Size = UDim2.fromScale(4.2, 1.9)
	-- El desplazamiento es respecto a la pantalla: queda siempre a la derecha del personaje
	gui.StudsOffset = Vector3.new(4, 0.5, 0)
	gui.MaxDistance = 90
	gui.Adornee = adornee :: any

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	label.BackgroundTransparency = 0.25
	label.Text = `{name}\nx{multiplier}`
	label.TextColor3 = color
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextStrokeTransparency = 0.3
	label.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.25, 0)
	corner.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = label

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.08, 0)
	padding.PaddingBottom = UDim.new(0.08, 0)
	padding.PaddingLeft = UDim.new(0.06, 0)
	padding.PaddingRight = UDim.new(0.06, 0)
	padding.Parent = label

	gui.Parent = model
	return gui
end

-- Etiqueta con ese nombre dentro del cartel de un modelo, o nil si no existe
function InfoBillboard.getLabel(model: Model, name: string): TextLabel?
	local gui = model:FindFirstChild("Info")
	local label = gui and gui:FindFirstChild(name)
	return if label and label:IsA("TextLabel") then label else nil
end

return InfoBillboard
