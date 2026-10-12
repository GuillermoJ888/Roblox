-- Elige un elemento al azar de una lista según su peso.
-- Cuanto mayor es el peso de un elemento, más probable es que salga.

local WeightedRandom = {}

-- items: lista de elementos
-- getWeight: función que devuelve el peso de cada elemento
-- rng: generador opcional (Random.new()); si no se pasa, se crea uno
function WeightedRandom.pick<T>(items: { T }, getWeight: (T) -> number, rng: Random?): T?
	local total = 0
	for _, item in items do
		total += math.max(getWeight(item), 0)
	end
	if total <= 0 then
		return nil
	end

	local generator = rng or Random.new()
	local roll = generator:NextNumber() * total
	local accumulated = 0
	for _, item in items do
		accumulated += math.max(getWeight(item), 0)
		if roll < accumulated then
			return item
		end
	end

	-- Por errores de redondeo podría no entrar en el bucle; devolvemos el último
	return items[#items]
end

return WeightedRandom
