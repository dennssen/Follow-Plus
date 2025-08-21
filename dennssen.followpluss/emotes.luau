--!strict

local Util = require("util")

local lastAnimationCycle: number = os.clock()
local defaultEmoteIndex: number = 3

export type Emote = {
	__index: Emote,
	id: number,

	animation: { string },
	animationLength: number,
	animationIndex: number,
	animationFrame: string,

	new: (id: number, animation: { string }) -> Emote,
	nextFrame: (self: Emote) -> (),
}
local Emote: Emote = {} :: Emote
Emote.__index = Emote

function Emote.new(id: number, animation: { string }): Emote
	local self: Emote = setmetatable({}, Emote) :: any

	self.id = id
	self.animation = animation
	self.animationLength = #self.animation
	self.animationIndex = 1
	self.animationFrame = self.animation[self.animationIndex]

	return self :: Emote
end

function Emote:nextFrame()
	self.animationIndex = Util.clampAround(self.animationIndex + 1, 1, self.animationLength)
	self.animationFrame = self.animation[self.animationIndex]
end

export type Emotes = {
	emoteList: { Emote },
	selectedEmote: Emote,
	animationCycleSpeed: number,

	tick: (self: Emotes) -> (),
	getEmoteById: (self: Emotes, emoteId: number) -> Emote,
	setEmote: (self: Emotes, emoteId: Emote) -> (),
	selectEmoteGUI: (self: Emotes, lable: string) -> (),
}

local Emotes: Emotes = {} :: Emotes
Emotes.emoteList = {
	Emote.new(1, { "|   |" }),
	Emote.new(2, { "^-^", "^_-", "^-^", "^-^" }),
	Emote.new(3, { "o_o", "o_o.", "o_o;", "o_o.", "o_o" }),
	Emote.new(4, { "x_x", "X_X" }),
	Emote.new(5, { "0_0", "-_-", "<_<", ">_>", "0_0" }),
	Emote.new(6, { "+" }),
	Emote.new(7, { "-" }),
	Emote.new(8, { "->", "-->" }),
	Emote.new(9, { "<-", "<--" }),
	Emote.new(10, { "^", "^^" }),
	Emote.new(11, { "v", "vv", "VV", "V" }),
}
Emotes.animationCycleSpeed = 1

function Emotes:tick()
	local currentTime: number = os.clock()
	Util.debugPrint(currentTime)
	if currentTime > lastAnimationCycle + Emotes.animationCycleSpeed then
		for _, emote: Emote in Emotes.emoteList do
			emote:nextFrame()
		end
		lastAnimationCycle = currentTime
	end
end

function Emotes:getEmoteById(emoteId: number): Emote
	local _emote: Emote = self.emoteList[1]
	for _, emote: Emote in self.emoteList do
		if emote.id == emoteId then
			_emote = emote
			break
		end
	end

	return _emote
end

function Emotes:setEmote(emote: Emote)
	self.selectedEmote = emote
	camera:setEmote(self.selectedEmote.id)
end

function Emotes:selectEmoteGUI(lable: string)
	if Gui.beginCombo(lable, `{self.selectedEmote.animationFrame}###{self.selectedEmote.id}`) then
		for _, emote: Emote in self.emoteList do
			if Gui.selectable(`{emote.animationFrame}###{emote.id}`, self.selectedEmote.id == emote.id) then
				self:setEmote(emote)
			end
		end
		Gui.endCombo()
	end
end

Emotes.selectedEmote = Emotes:getEmoteById(defaultEmoteIndex)

return Emotes
