-- Reproduce los sonidos del juego. Los IDs están en SoundConfig; mientras una entrada
-- esté vacía, ese sonido simplemente no suena.
--
--   SoundController.play("Purchase")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SoundConfig = require(Shared.Config.SoundConfig)
local Remotes = require(Shared.Remotes)

local SoundController = {}

local started = false
local sounds: { [string]: Sound } = {}

function SoundController.play(name: string)
	local id = (SoundConfig :: { [string]: string })[name]
	if not id or id == "" then
		return
	end
	local sound = sounds[name]
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = id
		sound.Volume = 0.6
		sound.Parent = SoundService
		sounds[name] = sound
	end
	sound:Play()
end

function SoundController.start()
	if started then
		return
	end
	started = true

	-- El servidor indica qué sonido acompaña a cada aviso (tercer dato del mensaje)
	Remotes.get("Notify").OnClientEvent:Connect(function(_, _, sound)
		if type(sound) == "string" then
			SoundController.play(sound)
		end
	end)
	Remotes.get("Announce").OnClientEvent:Connect(function(_, _, sound)
		if type(sound) == "string" then
			SoundController.play(sound)
		end
	end)
end

return SoundController
