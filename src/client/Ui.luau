-- Piezas de interfaz reutilizables (paneles, botones, listas) con un mismo estilo.
-- Para cambiar el aspecto de todos los menús, edita los colores de aquí.

local Ui = {}

Ui.Colors = {
	Panel = Color3.fromRGB(28, 32, 44),
	Row = Color3.fromRGB(44, 50, 66),
	RowSelected = Color3.fromRGB(60, 95, 80),
	Text = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(180, 188, 205),
	Green = Color3.fromRGB(70, 185, 100),
	Red = Color3.fromRGB(205, 75, 75),
	Blue = Color3.fromRGB(70, 130, 215),
	Gold = Color3.fromRGB(235, 180, 60),
	Gray = Color3.fromRGB(95, 102, 120),
	Money = Color3.fromRGB(120, 255, 140),
}

-- Paneles registrados: al abrir uno se cierran los demás
local panels: { Frame } = {}

function Ui.corner(instance: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

function Ui.padding(instance: Instance, pixels: number)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, pixels)
	padding.PaddingBottom = UDim.new(0, pixels)
	padding.PaddingLeft = UDim.new(0, pixels)
	padding.PaddingRight = UDim.new(0, pixels)
	padding.Parent = instance
end

-- Texto. size y position son opcionales (por defecto ocupa todo el contenedor).
function Ui.label(parent: Instance, text: string, size: UDim2?, position: UDim2?, color: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = size or UDim2.fromScale(1, 1)
	label.Position = position or UDim2.fromScale(0, 0)
	label.Text = text
	label.TextColor3 = color or Ui.Colors.Text
	label.TextScaled = true
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = Enum.Font.GothamBold
	label.Parent = parent

	-- Evita que un texto corto se vuelva enorme al escalarse
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 22
	limit.MinTextSize = 8
	limit.Parent = label
	return label
end

function Ui.button(parent: Instance, text: string, color: Color3, onClick: () -> ()): TextButton
	local button = Instance.new("TextButton")
	button.AutoButtonColor = true
	button.BackgroundColor3 = color
	button.Size = UDim2.fromOffset(120, 34)
	button.Text = text
	button.TextColor3 = Ui.Colors.Text
	button.TextScaled = true
	button.Font = Enum.Font.GothamBold
	button.Parent = parent
	Ui.corner(button, 8)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = button

	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 20
	limit.MinTextSize = 8
	limit.Parent = button

	button.Activated:Connect(onClick)
	return button
end

-- Ventana centrada con título y botón de cerrar. Empieza oculta.
-- Devuelve la ventana y el marco de contenido donde poner cosas.
function Ui.panel(root: Instance, title: string, width: number, height: number): (Frame, Frame)
	local frame = Instance.new("Frame")
	frame.Name = title
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(width, height)
	frame.BackgroundColor3 = Ui.Colors.Panel
	frame.Visible = false
	frame.Parent = root
	Ui.corner(frame, 14)

	-- Absorbe los clics para que no lleguen al juego a través de la ventana
	frame.Active = true

	local titleLabel = Ui.label(frame, title, UDim2.new(1, -70, 0, 34), UDim2.fromOffset(16, 10))
	titleLabel.Name = "Title"

	local closeButton = Ui.button(frame, "X", Ui.Colors.Red, function()
		frame.Visible = false
	end)
	closeButton.Size = UDim2.fromOffset(34, 34)
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -10, 0, 10)

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(14, 54)
	content.Size = UDim2.new(1, -28, 1, -68)
	content.Parent = frame

	table.insert(panels, frame)
	return frame, content
end

function Ui.setTitle(frame: Frame, title: string)
	local label = frame:FindFirstChild("Title")
	if label and label:IsA("TextLabel") then
		label.Text = title
	end
end

function Ui.open(frame: Frame)
	for _, panel in panels do
		panel.Visible = panel == frame
	end
end

function Ui.close(frame: Frame)
	frame.Visible = false
end

function Ui.toggle(frame: Frame)
	if frame.Visible then
		Ui.close(frame)
	else
		Ui.open(frame)
	end
end

-- Lista vertical con barra de desplazamiento
function Ui.list(parent: Instance, size: UDim2?, position: UDim2?): ScrollingFrame
	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Size = size or UDim2.fromScale(1, 1)
	list.Position = position or UDim2.fromScale(0, 0)
	list.ScrollBarThickness = 6
	list.CanvasSize = UDim2.fromScale(0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	return list
end

-- Borra el contenido de una lista o marco, conservando su distribución
function Ui.clear(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- Fila de una lista: título, detalle debajo y, opcionalmente, un botón a la derecha
function Ui.row(
	list: Instance,
	order: number,
	title: string,
	detail: string,
	detailColor: Color3?,
	buttonText: string?,
	buttonColor: Color3?,
	onClick: (() -> ())?
): Frame
	local row = Instance.new("Frame")
	row.BackgroundColor3 = Ui.Colors.Row
	row.Size = UDim2.new(1, -8, 0, 52)
	row.LayoutOrder = order
	row.Parent = list
	Ui.corner(row, 8)

	local textWidth = if buttonText then -150 else -20
	Ui.label(row, title, UDim2.new(1, textWidth, 0, 24), UDim2.fromOffset(10, 4))
	Ui.label(row, detail, UDim2.new(1, textWidth, 0, 18), UDim2.fromOffset(10, 29), detailColor or Ui.Colors.Muted)

	if buttonText and onClick then
		local button = Ui.button(row, buttonText, buttonColor or Ui.Colors.Green, onClick)
		button.Size = UDim2.fromOffset(124, 36)
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -8, 0.5, 0)
	end
	return row
end

-- Título de sección dentro de una lista
function Ui.header(list: Instance, order: number, text: string): TextLabel
	local label = Ui.label(list, text, UDim2.new(1, -8, 0, 26), nil, Ui.Colors.Gold)
	label.LayoutOrder = order
	return label
end

return Ui
