-- Efectos visuales cortos que crea el servidor (los ven todos los jugadores).

local Debris = game:GetService("Debris")

local Effects = {}

-- Estallido de partículas en una pieza
function Effects.burst(part: BasePart?, color: Color3, amount: number?)
	if not part then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Burst"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.7
	emitter.Size = NumberSequence.new(0.7, 0)
	emitter.Lifetime = NumberRange.new(0.5, 1)
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = part
	emitter:Emit(amount or 20)
	Debris:AddItem(emitter, 2)
end

return Effects
