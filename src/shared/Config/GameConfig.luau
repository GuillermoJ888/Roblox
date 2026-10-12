-- Números generales del juego. Cambia aquí los valores para ajustar la economía.

local GameConfig = {}

-- ===== Jugador =====
GameConfig.StartingMoney = 500
-- SOLO PARA PROBAR: dinero mínimo con el que se entra al pulsar Probar en Roblox Studio.
-- No afecta al juego publicado. Ponlo en 0 para probar la economía real.
GameConfig.StudioTestMoney = 100000
GameConfig.MaxPlayers = 8 -- una base por jugador
GameConfig.PlayerMaxHealth = 120

-- ===== Movimiento =====
GameConfig.WalkSpeed = 16
GameConfig.SprintSpeed = 26 -- velocidad al correr con Shift
GameConfig.StaminaMax = 100
GameConfig.StaminaDrain = 25 -- energía que gasta correr, por segundo
GameConfig.StaminaRegen = 15 -- energía que se recupera, por segundo
GameConfig.StaminaRegenDelay = 1 -- segundos sin correr antes de empezar a recuperar
GameConfig.StaminaMinToSprint = 20 -- tras agotarse, energía necesaria para volver a correr
GameConfig.DoubleJumpSpinTime = 0.4 -- segundos que dura el giro del doble salto

-- ===== Combate =====
GameConfig.SwordDamage = 20
GameConfig.SwordCooldown = 0.6 -- segundos entre golpes
GameConfig.SwordRange = 7 -- alcance del golpe, en studs

-- ===== Base =====
-- Piso 1: frutas. Piso 2: congelador y helados.
GameConfig.FruitSlots = 8 -- casillas de fruta con las que empieza todo el mundo
-- Casillas que se construyen en cada base. Las que pasan de FruitSlots se desbloquean
-- con pases de Robux (ver PassConfig). Debe ser múltiplo de 4.
GameConfig.MaxFruitSlots = 16
GameConfig.FreezerSlots = 3
GameConfig.FreezerWalkSpeed = 10 -- velocidad a la que la fruta sube caminando al congelador
GameConfig.IceCreamSlots = 6
GameConfig.DoorLockDuration = 60 -- segundos que la puerta queda bloqueada
GameConfig.DoorLockCooldown = 60 -- espera antes de poder bloquearla otra vez

-- ===== Banda transportadora =====
GameConfig.SpawnInterval = 4 -- segundos entre personajes
GameConfig.ConveyorSpeed = 8 -- studs por segundo
GameConfig.BuyDistance = 14 -- distancia máxima para comprar un personaje de la banda
GameConfig.DeliveryWalkSpeed = 7 -- velocidad a la que el personaje comprado camina hasta la base
-- Si otro jugador compra tu personaje mientras camina: true = te devuelven el dinero, false = lo pierdes
GameConfig.RefundOnSnipe = true

-- ===== Helados =====
GameConfig.IceCreamIncomeMultiplier = 3 -- ingreso del helado = ingreso de la fruta (con mutación) x 3
GameConfig.IceCreamSellMultiplier = 3 -- venta al coco = precio de la fruta x mutación x 3

-- ===== Coco heladero =====
GameConfig.CoconutNpcName = "Cocardo"
GameConfig.FruitSellFraction = 0.5 -- vender una fruta devuelve la mitad de su precio
GameConfig.ShopDistance = 40 -- distancia máxima a Cocardo para usar su menú
-- Vender desde tu propia base (tecla F) es más cómodo, pero paga solo esta parte de lo que da Cocardo
GameConfig.QuickSellFraction = 0.8
GameConfig.DailyBonus = 500
GameConfig.DailyBonusCooldown = 24 * 60 * 60 -- segundos

-- ===== Robo =====
GameConfig.StealHoldDuration = 3 -- segundos manteniendo E para robar
GameConfig.StealCooldown = 10 -- espera entre intentos de robo
GameConfig.CarryWalkSpeed = 10 -- velocidad al cargar algo robado (la normal es 16)

-- ===== Compras con Robux (ver ProductConfig y PassConfig) =====
-- Los minutos que da cada compra están en ProductConfig. El tiempo comprado solo se gasta
-- mientras el jugador está conectado.
GameConfig.SuperFreezerSpeed = 2 -- cuántas veces más rápido congela el súper congelador

-- ===== Intercambio entre jugadores =====
-- Segundos para cancelar después de que los dos aceptan. Si alguien cambia la oferta, se reinicia.
GameConfig.TradeCancelWindow = 6
GameConfig.TradeRequestTimeout = 20 -- segundos que dura una invitación sin responder

-- ===== Rebirth =====
GameConfig.RebirthBaseCost = 1000000
GameConfig.RebirthCostGrowth = 3 -- cada rebirth cuesta x3 más que el anterior
GameConfig.RebirthIncomeBonus = 0.5 -- +50 % de ingresos por cada rebirth

-- ===== Tormenta de mutaciones =====
-- Durante la tormenta caen rayos sobre los personajes que van por la banda y los mutan.
-- Los que ya están dentro de una base no cambian.
GameConfig.StormDuration = 2 * 60 -- segundos que dura
GameConfig.StormStrikeInterval = 3 -- segundos entre rayos
-- La tormenta se provoca llenando la máquina con frutas (los puntos por rareza están en Rarities)
GameConfig.StormGoal = 60 -- puntos necesarios
GameConfig.StormIceCreamMultiplier = 2 -- un helado vale el doble que su fruta
GameConfig.StormCooldown = 3 * 60 -- tras una tormenta, la máquina no acepta frutas durante este tiempo
GameConfig.StormMachineDistance = 30 -- distancia máxima a la máquina para echarle frutas
-- Si nadie llena la máquina, cae una tormenta sola cada este tiempo (0 = nunca)
GameConfig.StormNaturalInterval = 15 * 60
-- SOLO PARA PROBAR: en Roblox Studio la primera tormenta sola llega a los pocos segundos.
-- No afecta al juego publicado. Ponlo en 0 para desactivarlo.
GameConfig.StudioFirstStormDelay = 90

return GameConfig
