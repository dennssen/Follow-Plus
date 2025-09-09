--!strict

local Util = {}

Util.TeamIndex = {
	NoTeam = -1,
	HomeTeam = 0,
	AwayTeam = 1,
}

function Util.safeSendMessage(camera: SpectatorCamera, message: any)
	if camera then
		sendMessage(camera, message)
	end
end

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

function Util.linearColorToVec3(color: LinearColor): Vec3
	return Vec3.new(color.R, color.G, color.B)
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

function Util.getDictKey(value, table): string
	local key = ""
	for k, v in pairs(table) do
		if v == value then
			key = k
		end
	end
	return key
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

function Util.stringToVec3(string: string): Vec3
	local x, y, z = string.match(string, "%{ ([%d.-]+), ([%d.-]+), ([%d.-]+) %}")
	if not x or not y or not z then
		return Vec3.zeroVector
	end

	local nx, ny, nz = tonumber(x), tonumber(y), tonumber(z)

	if not nx or not ny or not nz then
		return Vec3.zeroVector
	end

	local vec = Vec3.new(nx, ny, nz)
	return vec
end

function Util.isBetween(n: number, min: number, max: number): boolean
	if n > min and n < max then
		return true
	else
		return false
	end
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

function Util.isBallHeld(ball: ReplayBall, ballRadius: number, players: { ReplayPlayer }): ReplayPlayer?
	local closestPlayerDistance = math.huge
	local closestPlayer: ReplayPlayer = nil

	for _, player in players do
		local root = player.root
		local headPosition = player.head.position
		local leftHandPosition = root.rotation:rotateVector(player.leftHand.position) + root.position
		local rightHandPosition = root.rotation:rotateVector(player.rightHand.position) + root.position

		local headDistance = Util.getDist(ball.transform.position, headPosition)
		local leftHandDistance = Util.getDist(ball.transform.position, leftHandPosition)
		local rightHandDistance = Util.getDist(ball.transform.position, rightHandPosition)

		local minimumDistance = math.min(headDistance, leftHandDistance, rightHandDistance)

		if minimumDistance < closestPlayerDistance then
			closestPlayerDistance = minimumDistance
			closestPlayer = player
		end
	end

	if closestPlayerDistance < ballRadius + 10 then
		return closestPlayer
	else
		return nil
	end
end

function Util.getClosestPlayerToBall(ball: ReplayBall, players: { ReplayPlayer }): ReplayPlayer
	local closestPlayerDistance = math.huge
	local closestPlayer: ReplayPlayer = nil

	for _, player in players do
		local root = player.root
		local headPosition = player.head.position
		local leftHandPosition = root.rotation:rotateVector(player.leftHand.position) + root.position
		local rightHandPosition = root.rotation:rotateVector(player.rightHand.position) + root.position

		local rootDistance = Util.getDist(ball.transform.position, root.position)
		local headDistance = Util.getDist(ball.transform.position, headPosition)
		local leftHandDistance = Util.getDist(ball.transform.position, leftHandPosition)
		local rightHandDistance = Util.getDist(ball.transform.position, rightHandPosition)

		local minimumDistance = math.min(rootDistance, headDistance, leftHandDistance, rightHandDistance)

		if minimumDistance < closestPlayerDistance then
			closestPlayerDistance = minimumDistance
			closestPlayer = player
		end
	end

	return closestPlayer
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

function Util.negateVec3(vec: Vec3): Vec3 -- annoying error workaround
	vec.x = -vec.x
	vec.y = -vec.y
	vec.z = -vec.z
	return vec
end

function Util.getForward(positionA: Vec3, positionB: Vec3): Vec3
	local forward: Vec3 = (positionB - positionA):normalize()
	return forward
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

function Util.clampMagnitude3(vec: Vec3, maxMagnitude: number): Vec3
	if vec:length() > maxMagnitude then
		return vec:normalize() * maxMagnitude
	else
		return vec
	end
end

function Util.angleBetweenVec3s(a: Vec3, b: Vec3, axis: Vec3): number
	a = a:normalize()
	b = b:normalize()
	axis = axis:normalize()

	local dot = math.max(-1, math.min(1, a:dot(b)))
	local unsignedAngle = math.acos(dot)

	local cross = a:cross(b)

	local sign = cross:dot(axis)

	if sign >= 0 then
		return unsignedAngle
	else
		return -unsignedAngle
	end
end

function Util.isBetweenVector(n: Vec3, min: Vec3, max: Vec3, up: Vec3): boolean
	local nHeight = n:dot(up)
	local minHeight = min:dot(up)
	local maxHeight = max:dot(up)

	return nHeight >= minHeight and nHeight <= maxHeight
end

function Util.clampMagnitude2(vec: Vec2, maxMagnitude: number): Vec2
	if vec:length() > maxMagnitude then
		return vec:normalize() * maxMagnitude
	else
		return vec
	end
end

function Util.rotateVec2(vec: Vec2, rads: number): Vec2
	return Vec2.new(
		(vec.x * math.cos(rads)) + (vec.y * math.sin(rads)),
		(-vec.x * math.sin(rads)) + (vec.y * math.cos(rads))
	)
end

function Util.isBetweenVec2(v1: Vec2, v2: Vec2, point: Vec2)
	return v1.x < point.x and v2.x > point.x and v1.y < point.y and v2.y > point.y
end

function Util.quatFromVec3(vec: Vec3): Quat
	return Quat.fromEuler(vec.x, vec.y, vec.z)
end

function Util.QuatToAngleAxis(quat: Quat): { angle: number, axis: Vec3 }
	local angle = 2 * math.acos(quat.w)

	if angle == 0 or angle == 180 then
		return { angle = angle, axis = Vec3.upVector }
	end

	local axis = Vec3.new(quat.x / math.sin(angle / 2), quat.y / math.sin(angle / 2), quat.z / math.sin(angle / 2))

	return { angle = angle, axis = axis }
end

function Util.lookAt(cameraPosition: Vec3, point: Vec3, up: Vec3)
	up = up:normalize()
	local forward = Util.getForward(cameraPosition, point)
	return Quat.fromXZ(forward, up)
end

function Util.dateTimeDeltaSeconds(past: DateTime, future: DateTime): number
	local ticksPast = (past.ticks / 10000000) - 62167219200
	local ticksFuture = (future.ticks / 10000000) - 62167219200

	return os.difftime(ticksFuture, ticksPast)
end

function Util.lerp(a: number, b: number, t: number): number
	if a == nil then
		return b
	end
	if b == nil then
		return a
	end
	return a * (1.0 - t) + b * t
end

function Util.clampAround(n: number, min: number, max: number): number
	if n < min then
		return max
	elseif n > max then
		return min
	else
		return n
	end
end

return Util
