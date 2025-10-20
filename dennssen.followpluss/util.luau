--!strict

local Util = {}

--- TeamIndex constants
--- @param NoTeam -- player with no team
--- @param HomeTeam -- player on home team
--- @param AwayTeam -- player on away team
Util.TeamIndex = {
	NoTeam = -1,
	HomeTeam = 0,
	AwayTeam = 1,
}

--- Toggle debug printing
--- Avoid calling the property directly. Instead let `Util.debugPrintToggle()` handle the logic.
Util.printToggle = false

--- Sends the `message` if the `camera` exists
--- @param camera -- the SpectatorCamera to message
--- @param message -- the message to send to the camera
function Util.safeSendMessage(camera: SpectatorCamera, message: any)
	if camera then
		sendMessage(camera, message)
	end
end

--- Get the distance between 2 points
--- @param a -- the first point
--- @param b -- then second point
--- @return the distance between `a` and `b` in centimeters
function Util.getDist(a: Vec3, b: Vec3): number
	local x: number = math.abs(a.x - b.x) ^ 2
	local y: number = math.abs(a.y - b.y) ^ 2
	local z: number = (a.z - b.z) ^ 2
	return math.sqrt(x + y + z)
end

--- Get the `ReplayFrame` using a `number`
--- @param index the replay index
--- @return replay number `index`'s replay frame | 0 returns live frame
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

--- Gets the `ReplayBall` type using it's JSON data
--- @param json the `ReplayBall`'s JSON
--- @return the type of the `ReplayBall` as a number. A type of 2 is a HeartBall
function Util.getBallType(json: string): number
	local typeVal = string.match(json, '"type"%s*:%s*([%d]+)')
	local ballType: number? = tonumber(typeVal)

	if ballType then
		return ballType
	else
		return 0
	end
end

--- Converts `LinearColor` to `Vec3` | **This will remove the Alpha value**
function Util.linearColorToVec3(color: LinearColor): Vec3
	return Vec3.new(color.R, color.G, color.B)
end

--- Gets a players primary color using it's JSON data
--- @param playerJson the `ReplayPlayer`'s json data
--- @return a table with r, g and b properties
function Util.extractPrimaryPlayerColor(playerJson: string): { r: number, g: number, b: number }
	local r: number? = tonumber(playerJson:match('"primary"%s*:%s*{.-"r"%s*:%s*(%d+)'))
	local g: number? = tonumber(playerJson:match('"primary"%s*:%s*{.-"g"%s*:%s*(%d+)'))
	local b: number? = tonumber(playerJson:match('"primary"%s*:%s*{.-"b"%s*:%s*(%d+)'))

	if r == nil or g == nil or b == nil then
		return { r = 0, b = 0, g = 0 }
	end

	return { r = r / 255, g = g / 255, b = b / 255 }
end

--- @return the size of the dict
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

--- @return the element of the dict at `index`
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

--- @return the name of the key to the value `value` in `table`
function Util.getDictKey(value, table): string
	local key = ""
	for k, v in pairs(table) do
		if v == value then
			key = k
		end
	end
	return key
end

--- Finds and adds missing keys from `structureTable` in `normalTable`
--- @param structureTable the table that contains all wanted keys and their default values
--- @param normalTable the table that should mimic the structure of `structureTable`
--- @return true if the `normalTable` was modified to fit the structure of `structureTable`
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

--- Finds and removes unwanted keys in `normalTable` not found in `structureTable`
--- @param structureTable the table that contains all wanted keys and their default values
--- @param normalTable the table that should mimic the structure of `structureTable`
--- @return true if the `normalTable` was modified to fit the structure of `structureTable`
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

--- Initializes and saves the config by removing/adding keys and values (not) in `defaultConfig` and saving if any changes were necessary
--- @param defaultConfig the table with the default keys and values you want your config to have
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

--- Converts a `tostring(vec3)` back to a Vec3
--- @param string the vector as a string
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

--- @return true if `n` is bigger than `min` and less then `max`
function Util.isBetween(n: number, min: number, max: number): boolean
	if n > min and n < max then
		return true
	else
		return false
	end
end

--- @return the index of the player within the table
--- @return nil if the player is not in the table
function Util.findPlayerInTable(table: { ReplayPlayer }, player: ReplayPlayer): number?
	local index = nil
	for i, tablePlayer: ReplayPlayer in table do
		if tablePlayer.playerId == player.playerId then
			index = i
		end
	end
	return index
end

--- @return the closest ball relative to `targetPosition`
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

--[=[
Checks if a player is withing a reasonable distance of the ball with their hands or head

*Note: the radius of a normal driftball is 17*

@return the player holding the ball
@return `nil` if no player is holding the ball
]=]
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

--- @return the closest player in the table `players` to the `ball`
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

--- Prints `s` once when the key **N** is pressed down
function Util.debugPrint(s: any)
	if Input.getKeyDown(Input.Key.N) then
		print(s)
	end
end

function Util.debugPrintToggle(s: any)
	if Input.getKeyDown(Input.Key.N) then
		Util.printToggle = not Util.printToggle
	end

	if Util.printToggle then
		print(s)
	end
end

--- Adds `Gui.spacing()` x number of times
--- @param amount the amount of spacing to be added
function Util.multispacing(amount: number)
	for i = 1, amount, 1 do
		Gui.sameLine()
		Gui.spacing()
	end
end

--- Avoids the annoying errors in vscode
--- @return the negated Vec3 (-vec3)
function Util.negateVec3(vec: Vec3): Vec3
	vec.x = -vec.x
	vec.y = -vec.y
	vec.z = -vec.z
	return vec
end

--- @param a start position
--- @param b end position
--- @return the normalized forward vector from a to b
function Util.getForward(a: Vec3, b: Vec3): Vec3
	local forward: Vec3 = (b - a):normalize()
	return forward
end

--- @param vec the vector to be clamped
--- @param min the min value on all axis
--- @param max the max value on all axis
--- @return the clamped vec3 on all axis
function Util.vec3ClampAxis(vec: Vec3, min: number, max: number): Vec3
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

--- @param vec the vector to be clamped
--- @param min the min vector length
--- @param max the max vector length
--- @return the vec3 clamped in length
function Util.clampLength3(vec: Vec3, min: number, max: number): Vec3
	if vec:length() > max then
		return vec:normalize() * max
	elseif vec:length() < min then
		return vec:normalize() * min
	else
		return vec
	end
end

--- @param a the first vector
--- @param b the second vector
--- @param axis the axis for the angle to be calculated on
--- @return the angle in radians between `a` and `b` on `axis`
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

--- Checks if a vector is above `min` and below `max`
--- @return true if n is above `min` and below `max` according to `up`
function Util.isBetweenVector(n: Vec3, min: Vec3, max: Vec3, up: Vec3): boolean
	up = up:normalize()
	local nHeight = n:dot(up)
	local minHeight = min:dot(up)
	local maxHeight = max:dot(up)

	return nHeight >= minHeight and nHeight <= maxHeight
end

--- @param vec the vector to be clamped
--- @param min the min vector length
--- @param max the max vector length
--- @return the vec2 clamped in length
function Util.clampLength2(vec: Vec2, min: number, max: number): Vec2
	if vec:length() > max then
		return vec:normalize() * max
	elseif vec:length() < min then
		return vec:normalize() * min
	else
		return vec
	end
end

--- @return the rotated `vec` by radians `rads`
function Util.rotateVec2(vec: Vec2, rads: number): Vec2
	return Vec2.new(
		(vec.x * math.cos(rads)) + (vec.y * math.sin(rads)),
		(-vec.x * math.sin(rads)) + (vec.y * math.cos(rads))
	)
end

--- @return true if `v1` < `point` > `v2`
function Util.isBetweenVec2(v1: Vec2, v2: Vec2, point: Vec2)
	return v1.x < point.x and v2.x > point.x and v1.y < point.y and v2.y > point.y
end

--- @return a quat with euler degrees `(vec.x, vec.y, vec.z)`
function Util.quatFromVec3(vec: Vec3): Quat
	return Quat.fromEuler(vec.x, vec.y, vec.z)
end

--- @return `angle` the rotation angle in degrees. The value is in range [0, 360].
--- @return `axis` the axis of rotation as a normalized `Vec3`. If the quaternion represents no rotation, the axis defaults to `Vec3.upVector`.
function Util.QuatToAngleAxis(quat: Quat): { angle: number, axis: Vec3 }
	local angle = 2 * math.acos(quat.w)

	if angle == 0 or angle == 180 then
		return { angle = angle, axis = Vec3.upVector }
	end

	local axis = Vec3.new(quat.x / math.sin(angle / 2), quat.y / math.sin(angle / 2), quat.z / math.sin(angle / 2))

	return { angle = angle, axis = axis:normalize() }
end

--- lookAt returns the Quat that looks at `to`, unlike `camera:lookAt` that automatically rotates the camera
--- @param from where to look from
--- @param to the point to look at
--- @param up the upwards direction of the quat
--- @return a Quat that looks towards `to` from the position of `from` with an upwards direction of `up`
function Util.lookAt(from: Vec3, to: Vec3, up: Vec3): Quat
	up = up:normalize()
	local forward = Util.getForward(from, to)
	return Quat.fromXZ(forward, up)
end

--- @return the amount of seconds between `past` and `future`
function Util.dateTimeDeltaSeconds(past: DateTime, future: DateTime): number
	local ticksPast = (past.ticks / 10000000) - 62167219200
	local ticksFuture = (future.ticks / 10000000) - 62167219200

	return os.difftime(ticksFuture, ticksPast)
end

--- Linearly interpolate between a and b by 0 <= t <= 1
function Util.lerp(a: number, b: number, t: number): number
	if a == nil then
		return b
	end
	if b == nil then
		return a
	end
	return a * (1.0 - t) + b * t
end

--- @return `max` if `n` < `min`
--- @return `min` if `n` > `max`
--- @return otherwise returns `n`
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
