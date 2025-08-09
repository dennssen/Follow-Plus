--!strict

local Box = require("box")
type BoxType = typeof(Box)

local Util = require("util")

export type ArenaTeam<T = {}> = {
	previousActualScore: number,
	previousScore: number,
	score: number,
	scoreIncrease: boolean,
	previousRoundsWon: number,
	roundsWon: number,
	roundsWonIncrease: boolean,
	goal: {
		position: Vec3,
		rotation: Quat,
		box: BoxType,
	},
	players: { ReplayPlayer },
	data: T,
}

export type Arena<ArenaData = {}, HomeData = {}, AwayData = {}> = {
	__index: Arena<ArenaData, HomeData, AwayData>,
	type: string,

	frameIndex: number,
	frame: ReplayFrame,
	slotId: string,
	gamemode: ModuleStateSpectatorLuaApi,
	name: string,
	transform: Transform,
	box: BoxType,
	centerBox: BoxType,
	home: ArenaTeam<HomeData>,
	away: ArenaTeam<AwayData>,
	players: { ReplayPlayer },
	ball: ReplayBall,
	data: ArenaData,

	lastIsGameActive: boolean,
	isGameActive: boolean,
	isKickoff: boolean,
	isOvertime: boolean,
	isGracePeriod: boolean,

	gameTimeSeconds: number,
	lastGameTimeSeconds: number,
	actionTimerSeconds: number,
	bestOfAmount: number,
	matchLengthSeconds: number,
	mercyScoreDifference: number,

	gracePeriodStartTime: number,
	instantUpdate: boolean,

	new: (gamemode: ModuleStateSpectatorLuaApi, frameIndex: number) -> Arena<ArenaData, HomeData, AwayData>,
	getArenaBall: (self: Arena<ArenaData, HomeData, AwayData>) -> (),
	tick: (self: Arena<ArenaData, HomeData, AwayData>) -> (),
	onGameStart: (self: Arena<ArenaData, HomeData, AwayData>) -> (),
	onRoundStart: (self: Arena<ArenaData, HomeData, AwayData>) -> (),
	onRoundEnd: (self: Arena<ArenaData, HomeData, AwayData>) -> (),
	setTeams: (self: Arena<ArenaData, HomeData, AwayData>) -> (),

	-- Event overrides
	preTickHook: (self: Arena<ArenaData, HomeData, AwayData>) -> (),
	postTickHook: (self: Arena<ArenaData, HomeData, AwayData>) -> (),
	onGameStartHook: (self: Arena<ArenaData, HomeData, AwayData>) -> (),
	onRoundStartHook: (self: Arena<ArenaData, HomeData, AwayData>) -> (),
	onRoundEndHook: (
		self: Arena<ArenaData, HomeData, AwayData>,
		isRestart: boolean,
		isMercy: boolean,
		homeScore: number,
		awayScore: number
	) -> (),
	onGoalScoredHook: (self: Arena<ArenaData, HomeData, AwayData>, scoredTeamIndex: number) -> (),

	-- Overrides
	isPointOnHomeSide: (self: Arena<ArenaData, HomeData, AwayData>, point: Vec3) -> boolean,
	setupDimensions: (self: Arena<ArenaData, HomeData, AwayData>) -> (),
	getTeamRotation: (self: Arena<ArenaData, HomeData, AwayData>, teamIndex: number) -> Quat,

	GUIChangeDimensions: (self: Arena<ArenaData, HomeData, AwayData>) -> (), -- Debuging
}

local Arena: Arena = {} :: Arena
Arena.__index = Arena

function Arena.new(gamemode: ModuleStateSpectatorLuaApi, frameIndex: number): Arena
	local self: Arena = setmetatable({}, Arena) :: any

	self.frameIndex = frameIndex

	self.slotId = gamemode:getSlotId()
	self.gamemode = gamemode
	self.transform = gamemode.transform
	self.players = {}

	self.home = {
		previousActualScore = 0,
		previousScore = 0,
		score = 0,
		scoreIncrease = false,
		previousRoundsWon = 0,
		roundsWon = 0,
		roundsWonIncrease = false,
		goal = {
			position = Vec3.zeroVector,
			rotation = Quat.identity,
			box = Box.empty,
		},
		players = {},
		data = {},
	}

	self.away = {
		previousActualScore = 0,
		previousScore = 0,
		score = 0,
		scoreIncrease = false,
		previousRoundsWon = 0,
		roundsWon = 0,
		roundsWonIncrease = false,
		goal = {
			position = Vec3.zeroVector,
			rotation = Quat.identity,
			box = Box.empty,
		},
		players = {},
		data = {},
	}

	self.instantUpdate = false
	self.gracePeriodStartTime = 0
	self.isOvertime = false
	self.isKickoff = false
	self.isGracePeriod = false

	print(`made arena {self.slotId}`)

	return self
end

function Arena:getArenaBall()
	local balls = self.frame.balls
	local closestBallDistance = math.huge
	local clostestBall: ReplayBall = nil
	for i in balls do
		local ball = balls[i]

		if not self.box:checkPointIntersect(ball.transform.position) then
			continue
		end
		local distance = Util.getDist(self.transform.position, ball.transform.position)
		if distance < closestBallDistance and Util.getBallType(ball:toJson()) ~= 2 then
			closestBallDistance = distance
			clostestBall = ball
		end
	end
	return clostestBall
end

function Arena:tick()
	self.frame = Util.getReplayFrameFromIndex(self.frameIndex)
	self.ball = self:getArenaBall()

	if self.preTickHook then
		self:preTickHook()
	end

	local currentTime = os.clock()
	self.lastIsGameActive = self.isGameActive
	self.isGameActive = self.gamemode:getIsGameRunning()

	if self.instantUpdate then
		self.lastIsGameActive = self.isGameActive
	end

	if not self.isKickoff and not self.lastIsGameActive and self.isGameActive then
		self.isKickoff = true
	end

	local started = self.isGameActive and not self.lastIsGameActive

	if started and self.home.roundsWon == 0 and self.away.roundsWon == 0 then
		self:onGameStart()
	elseif started then
		self:onRoundStart()
	end

	local gameTimeComponent = self.gamemode:getGameTimeComponent()

	self.matchLengthSeconds = self.gamemode:getNumberConfigVariable("matchlengthseconds")
	self.mercyScoreDifference = self.gamemode:getNumberConfigVariable("mercyscoredifference")
	if gameTimeComponent then
		if self.gameTimeSeconds and self.isGameActive then
			self.lastGameTimeSeconds = self.gameTimeSeconds
		elseif self.matchLengthSeconds then
			self.lastGameTimeSeconds = self.matchLengthSeconds
		else
			self.lastGameTimeSeconds = 0
		end
		self.gameTimeSeconds = gameTimeComponent:getTimeSeconds()
		self.actionTimerSeconds = gameTimeComponent:getSecondaryTimeSeconds()
	else
		self.gameTimeSeconds = 0
		self.lastGameTimeSeconds = 0
		self.actionTimerSeconds = 0
	end

	local homeActualScore = self.gamemode:getTeamScore(Util.TeamIndex.HomeTeam)
	local awayActualScore = self.gamemode:getTeamScore(Util.TeamIndex.AwayTeam)

	if homeActualScore ~= self.home.previousActualScore then
		self.home.previousScore = self.home.score
		self.home.score = self.gamemode:getTeamScore(Util.TeamIndex.HomeTeam)
	end

	if awayActualScore ~= self.away.previousActualScore then
		self.away.previousScore = self.away.score
		self.away.score = self.gamemode:getTeamScore(Util.TeamIndex.AwayTeam)
	end

	if self.instantUpdate then
		self.home.previousActualScore = homeActualScore
		self.away.previousActualScore = awayActualScore
		self.lastGameTimeSeconds = self.gameTimeSeconds
	end

	self.home.scoreIncrease = self.home.previousActualScore ~= homeActualScore and homeActualScore ~= 0
	self.away.scoreIncrease = self.away.previousActualScore ~= awayActualScore and awayActualScore ~= 0

	self.home.previousActualScore = homeActualScore
	self.away.previousActualScore = awayActualScore

	if self.home.scoreIncrease or self.away.scoreIncrease then
		local scoredTeamIndex = self.home.scoreIncrease and Util.TeamIndex.HomeTeam or Util.TeamIndex.AwayTeam
		self.gracePeriodStartTime = currentTime
		self.isGracePeriod = true
		if self.onGoalScoredHook then
			self:onGoalScoredHook(scoredTeamIndex)
		end
	elseif not self.isGracePeriod and self.actionTimerSeconds > 0 and self.isGameActive then
		self.gracePeriodStartTime = currentTime
		self.isGracePeriod = true
	end

	if
		self.isGracePeriod
		and ((currentTime - self.gracePeriodStartTime > 6 and self.actionTimerSeconds == 0) or not self.isGameActive)
	then
		self.isGracePeriod = false
	end

	if self.gameTimeSeconds > self.lastGameTimeSeconds and not self.isOvertime then
		self.isOvertime = true
	end

	self.home.previousRoundsWon = self.home.roundsWon
	self.home.roundsWon = self.gamemode:getTeamRoundsWon(Util.TeamIndex.HomeTeam)
	self.away.previousRoundsWon = self.away.roundsWon
	self.away.roundsWon = self.gamemode:getTeamRoundsWon(Util.TeamIndex.AwayTeam)

	if self.instantUpdate then
		self.home.previousRoundsWon = self.home.roundsWon
		self.away.previousRoundsWon = self.away.roundsWon
	end

	self.home.roundsWonIncrease = self.home.roundsWon > self.home.previousRoundsWon
	self.away.roundsWonIncrease = self.away.roundsWon > self.away.previousRoundsWon

	if self.gamemode:getBoolConfigVariable("busebestof") then
		self.bestOfAmount = self.gamemode:getNumberConfigVariable("roundspermatch")
	else
		self.bestOfAmount = 1
	end

	if not self.isGameActive and self.lastIsGameActive then
		self:onRoundEnd()
	end

	self:setTeams()

	if self.instantUpdate then
		self.instantUpdate = false
	end

	if self.postTickHook then
		self:postTickHook()
	end
end

function Arena:onGameStart()
	print("game start")

	if self.onGameStartHook then
		self:onGameStartHook()
	end

	self:onRoundStart()
end

function Arena:onRoundStart()
	print("round start")
	self.isOvertime = false
	self.home.score = 0
	self.home.previousScore = 0
	self.away.score = 0
	self.away.previousScore = 0

	if self.onRoundStartHook then
		self:onRoundStartHook()
	end
end

function Arena:onRoundEnd()
	print("round end")
	local isRestart = not self.home.roundsWonIncrease and not self.away.roundsWonIncrease
	local endsWithAGoal = self.home.scoreIncrease or self.away.scoreIncrease
	local cachedHomeScore
	local cachedAwayScore

	if endsWithAGoal then
		cachedHomeScore = self.home.previousScore
		cachedAwayScore = self.away.previousScore
	else
		cachedHomeScore = self.home.score
		cachedAwayScore = self.away.score
	end

	local scoreDifference = math.abs(cachedHomeScore - cachedAwayScore)
	local isMercy = scoreDifference >= (self.mercyScoreDifference - 1) and endsWithAGoal

	print(`Home pre-score: {self.home.previousScore}`)
	print(`Away pre-score: {self.away.previousScore}`)
	print(`Game time: {self.gameTimeSeconds}`)
	print(`Action time: {self.actionTimerSeconds}`)
	print(`Ends with goal: {endsWithAGoal}`)
	print(`Is overtime: {self.isOvertime}`)
	print(`Is mercy: {isMercy}`)

	if not isRestart then
		if
			endsWithAGoal
			and (self.isOvertime or isMercy)
			and self.home.goal.box:checkPointIntersect(self.ball.transform.position)
		then
			print("Increased away score")
			cachedAwayScore += 1
		elseif
			endsWithAGoal
			and (self.isOvertime or isMercy)
			and self.away.goal.box:checkPointIntersect(self.ball.transform.position)
		then
			print("Increased home score")
			cachedHomeScore += 1
		end
	end

	print(`Home score: {cachedHomeScore}`)
	print(`Away score: {cachedAwayScore}`)

	if self.onRoundEndHook then
		self:onRoundEndHook(isRestart, isMercy, cachedHomeScore, cachedAwayScore)
	end
end

function Arena:setTeams()
	local tempHome = {}
	local tempAway = {}

	for _, player in self.frame.players do
		if player.teamIndex == Util.TeamIndex.NoTeam then
			continue
		end

		if not self.box:checkPointIntersect(player.root.position) then
			continue
		end

		if player.teamIndex == Util.TeamIndex.HomeTeam then
			table.insert(tempHome, player)
		elseif player.teamIndex == Util.TeamIndex.AwayTeam then
			table.insert(tempAway, player)
		end
	end

	self.home.players = tempHome
	self.away.players = tempAway

	local allPlayers = {}
	for _, player in self.home.players do
		table.insert(allPlayers, player)
	end
	for _, player in self.away.players do
		table.insert(allPlayers, player)
	end
	self.players = allPlayers
end

return Arena
