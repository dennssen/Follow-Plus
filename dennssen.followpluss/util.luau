--!strict

local Util = {}

Util.TeamIndex = {
	NoTeam = -1,
	HomeTeam = 0,
	AwayTeam = 1,
}

function Util.getDist(point1: Vec3, point2: Vec3): number
	local x: number = math.abs(point1.x - point2.x) ^ 2
	local y: number = math.abs(point1.y - point2.y) ^ 2
	local z: number = (point1.z - point2.z) ^ 2
	return math.sqrt(x + y + z)
end

function Util.getReplayFrameFromIndex(index: number): ReplayFrame
	index = math.clamp(index, 0, #Replay.listLoaded())
	local replay = Replay.getByIndex(index)
	if replay then
		return replay:getCurrentFrame(true)
	else
		-- 0 = live game
		return getGameData()
	end
end

function Util.getBallType(json: string): number
	local typeVal = string.match(json, '"type"%s*:%s*([%d]+)')
	local ballType: number? = tonumber(typeVal)

	if ballType then
		return ballType
	else
		return 0
	end
end

function Util.extractPrimaryPlayerColor(playerJson: string): { r: number, g: number, b: number }
	local r: number? = tonumber(playerJson:match('"primary"%s*:%s*{.-"r"%s*:%s*(%d+)'))
	local g: number? = tonumber(playerJson:match('"primary"%s*:%s*{.-"g"%s*:%s*(%d+)'))
	local b: number? = tonumber(playerJson:match('"primary"%s*:%s*{.-"b"%s*:%s*(%d+)'))

	if r == nil or g == nil or b == nil then
		return { r = 0, b = 0, g = 0 }
	end

	return { r = r / 255, g = g / 255, b = b / 255 }
end

function Util.getDictSize(dict): number
	local i = 0

	if dict == nil then
		return i
	end

	for _, _ in dict do
		i += 1
	end

	return i
end

function Util.getDictIndex(dict, index: number)
	local i = 0
	local dictSize = Util.getDictSize(dict)
	local dictItem = nil

	if index < 0 or index > dictSize then
		return dictItem
	end

	for _, item in dict do
		if i == index then
			dictItem = item
			break
		end

		i += 1
	end

	return dictItem
end

function Util.deepStructureCopy(structureTable, normalTable): boolean
	local adjusted = false
	if typeof(structureTable) == "table" then
		for structureKey, structureValue in structureTable do
			if normalTable[structureKey] == nil then
				adjusted = true
				normalTable[structureKey] = structureValue
			elseif typeof(normalTable[structureKey]) ~= typeof(structureValue) then
				adjusted = true
				normalTable[structureKey] = structureValue
			elseif typeof(structureValue) == "table" then
				if Util.deepStructureCopy(structureValue, normalTable[structureKey]) then
					adjusted = true
				end
			end
		end
	end

	return adjusted
end

function Util.deepStructureClean(structureTable, normalTable): boolean
	local adjusted = false
	if typeof(normalTable) == "table" then
		for normalKey, normalValue in normalTable do
			if structureTable[normalKey] == nil then
				adjusted = true
				normalTable[normalKey] = nil
			elseif typeof(normalValue) == "table" then
				if Util.deepStructureClean(structureTable[normalKey], normalValue) then
					adjusted = true
				end
			end
		end
	end

	return adjusted
end

function Util.initializeConfig(defaultConfig: { [any]: any })
	local saveToConfig = false

	if Util.deepStructureCopy(defaultConfig, config) then
		saveToConfig = true
	end

	if Util.deepStructureClean(defaultConfig, config) then
		saveToConfig = true
	end

	if saveToConfig then
		saveConfig()
	end
end

function Util.isBetweenVector(n: Vec3, min: Vec3, max: Vec3, up: Vec3): boolean
	local nHeight = n:dot(up)
	local minHeight = min:dot(up)
	local maxHeight = max:dot(up)

	return nHeight >= minHeight and nHeight <= maxHeight
end

function Util.isBetween(n: number, min: number, max: number): boolean
	if n > min and n < max then
		return true
	else
		return false
	end
end

function Util.getForward(positionA: Vec3, positionB: Vec3): Vec3
	local forward: Vec3 = Vec3.new((positionB.x - positionA.x), (positionB.y - positionA.y), positionB.z - positionA.z)
		:normalize()
	return forward
end

function Util.findPlayerInTable(table: { ReplayPlayer }, player: ReplayPlayer): number?
	local index = nil
	for i, tablePlayer: ReplayPlayer in table do
		if tablePlayer.playerId == player.playerId then
			index = i
		end
	end
	return index
end

function Util.getClosestBall(targetPosition: Vec3, frameData: ReplayFrame): ReplayBall
	local balls = frameData.balls
	local closestBallDistance = math.huge
	local clostestBall: ReplayBall = nil
	for i in balls do
		local ball = balls[i]
		local distance = Util.getDist(targetPosition, ball.transform.position)
		if distance < closestBallDistance then
			closestBallDistance = distance
			clostestBall = ball
		end
	end
	return clostestBall
end

function Util.debugPrint(s: any)
	if Input.getKeyDown(Input.Key.N) then
		print(s)
	end
end

function Util.multispacing(amount: number)
	for i = 1, amount, 1 do
		Gui.sameLine()
		Gui.spacing()
	end
end

function Util.getKey(value, table): string
	local key = ""
	for k, v in pairs(table) do
		if v == value then
			key = k
		end
	end
	return key
end

-- clamps every axis in the vector to be between max and min
function Util.vec3Clamp(vec: Vec3, min: number, max: number): Vec3
	local axises = { x = vec.x, y = vec.y, z = vec.z }

	for axis, value in pairs(axises) do
		if value < min then
			axises[axis] = min
		elseif value > max then
			axises[axis] = max
		end
	end

	vec.x = axises.x
	vec.y = axises.y
	vec.z = axises.z

	return vec
end

function Util.vec3ClampLength(vec: Vec3, maxLength: number): Vec3
	if vec:length() > maxLength then
		vec = vec:normalize() * maxLength
	end

	return vec
end

function Util.quatFromVec3(vec: Vec3): Quat
	return Quat.fromEuler(vec.x, vec.y, vec.z)
end

return Util
