-- Sonidos del juego. TODOS ESTÁN VACÍOS: el juego funciona en silencio hasta que pongas los IDs.
--
-- CÓMO PONER UN SONIDO:
--   1. Busca un audio en la Creator Store de Roblox (o sube el tuyo) y copia su número de ID.
--   2. Pégalo aquí entre las comillas, con el prefijo: "rbxassetid://1234567890"
--
-- El juego ya llama a cada sonido en el momento adecuado; solo falta el ID.

local SoundConfig = {
	Purchase = "", -- al comprar un personaje
	Collect = "", -- al recoger dinero
	Sell = "", -- al vender algo a Cocardo
	IceCreamReady = "", -- cuando un helado sale del congelador
	Steal = "", -- cuando robas o te roban
	Error = "", -- acción que no se pudo hacer
	Announce = "", -- aviso para todo el servidor (rebirth, fin de la tormenta)
	Secret = "", -- aparece un personaje Secreto
	Trade = "", -- intercambio completado
	Storm = "", -- empieza una tormenta de mutaciones
	Thunder = "", -- cae un rayo sobre un personaje de la banda
}

return SoundConfig
