-- Números generales del juego. Cambia aquí los valores para ajustar la economía.

local GameConfig = {}

-- ===== Jugador =====
GameConfig.StartingMoney = 100
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
GameConfig.FruitSlots = 8
GameConfig.FreezerSlots = 3
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
GameConfig.DailyBonus = 500
GameConfig.DailyBonusCooldown = 24 * 60 * 60 -- segundos

-- ===== Robo =====
GameConfig.StealHoldDuration = 3 -- segundos manteniendo E para robar
GameConfig.StealCooldown = 10 -- espera entre intentos de robo
GameConfig.CarryWalkSpeed = 10 -- velocidad al cargar algo robado (la normal es 16)

-- ===== Intercambio entre jugadores (etapa 10, aún sin programar) =====
-- Segundos para cancelar después de que los dos aceptan. Si alguien cambia la oferta, se reinicia.
GameConfig.TradeCancelWindow = 6

-- ===== Rebirth =====
GameConfig.RebirthBaseCost = 1000000
GameConfig.RebirthCostGrowth = 3 -- cada rebirth cuesta x3 más que el anterior
GameConfig.RebirthIncomeBonus = 0.5 -- +50 % de ingresos por cada rebirth

-- ===== Evento "Lluvia de mutaciones" =====
GameConfig.MutationRainInterval = 10 * 60 -- cada 10 minutos
GameConfig.MutationRainDuration = 2 * 60 -- dura 2 minutos

return GameConfig
