-- Productos: compras con Robux que se pueden repetir todas las veces que se quiera.
-- (Los pases, en cambio, se compran una sola vez: ver PassConfig.)
--
-- CÓMO ACTIVAR UN PRODUCTO (hace falta tener el juego publicado):
--   1. En create.roblox.com abre tu juego -> Monetización -> Productos de desarrollador -> Crear.
--   2. Ponle nombre, imagen y precio en Robux.
--   3. Copia el número de ID del producto y pégalo aquí en productId.
--
-- Mientras productId sea 0, no se puede comprar en el juego publicado (sale "Próximamente").
-- En Roblox Studio se concede gratis para poder probarlo.
--
-- Campos:
--   effect   qué hace: "Storm" (tormenta al instante), "Guard" (guardia) o "SuperFreezer"
--   minutes  minutos que da (solo Guard y SuperFreezer). El tiempo solo se gasta mientras
--            el jugador está conectado.
--
-- EL PRECIO SE PONE EN ROBLOX, no aquí. Para que compense comprar más tiempo, cada paquete
-- grande debe salir más barato por minuto. suggestedRobux es solo una propuesta orientativa
-- para cuando los crees; el juego no lo usa.

export type Product = {
	id: string,
	name: string,
	description: string,
	productId: number,
	effect: "Storm" | "Guard" | "SuperFreezer",
	minutes: number?,
	suggestedRobux: number?,
}

local PRODUCTS: { Product } = {
	{
		id = "StormNow",
		name = "Tormenta al instante",
		description = "Provoca una tormenta de mutaciones ahora mismo, para todo el servidor.",
		productId = 0,
		effect = "Storm",
		suggestedRobux = 49,
	},
	-- Guardia de seguridad: cuanto más tiempo, más barato sale cada minuto
	{
		id = "Guard10",
		name = "Guardia de seguridad (10 min)",
		description = "Un guardia vigila tu puerta: nadie más puede entrar. Solo cuenta mientras juegas.",
		productId = 0,
		effect = "Guard",
		minutes = 10,
		suggestedRobux = 20, -- 2 por minuto
	},
	{
		id = "Guard30",
		name = "Guardia de seguridad (30 min)",
		description = "Triple de tiempo y más barato por minuto.",
		productId = 0,
		effect = "Guard",
		minutes = 30,
		suggestedRobux = 49, -- 1,63 por minuto (18 % menos)
	},
	{
		id = "Guard60",
		name = "Guardia de seguridad (60 min)",
		description = "La mejor oferta: una hora entera al menor precio por minuto.",
		productId = 0,
		effect = "Guard",
		minutes = 60,
		suggestedRobux = 79, -- 1,32 por minuto (34 % menos)
	},
	-- Súper congelador: cuanto más tiempo, más barato sale cada minuto
	{
		id = "SuperFreezer10",
		name = "Súper congelador (10 min)",
		description = "Lo que metas al congelador se hace helado el doble de rápido.",
		productId = 0,
		effect = "SuperFreezer",
		minutes = 10,
		suggestedRobux = 25, -- 2,5 por minuto
	},
	{
		id = "SuperFreezer30",
		name = "Súper congelador (30 min)",
		description = "Triple de tiempo y más barato por minuto.",
		productId = 0,
		effect = "SuperFreezer",
		minutes = 30,
		suggestedRobux = 59, -- unos 2 por minuto (20 % menos)
	},
	{
		id = "SuperFreezer60",
		name = "Súper congelador (60 min)",
		description = "La mejor oferta: una hora entera al menor precio por minuto.",
		productId = 0,
		effect = "SuperFreezer",
		minutes = 60,
		suggestedRobux = 99, -- 1,65 por minuto (34 % menos)
	},
}

local ProductConfig = {}

ProductConfig.List = PRODUCTS

ProductConfig.ById = {} :: { [string]: Product }
for _, product in PRODUCTS do
	assert(not ProductConfig.ById[product.id], `Id de producto repetido: {product.id}`)
	ProductConfig.ById[product.id] = product
end

return ProductConfig
