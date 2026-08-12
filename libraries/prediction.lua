--[[
	Prediction Library
	Source: https://devforum.roblox.com/t/predict-projectile-ballistics-including-gravity-and-motion/1842434
]]
local module = {}
local eps = 1e-9
local cloneref = cloneref or function(ref) return ref end
local tweenService = cloneref(game:GetService('TweenService'))
local function isZero(d)
	return (d > -eps and d < eps)
end

local function finiteScalar(value)
	return type(value) == 'number' and value == value and value > -math.huge and value < math.huge
end

local function appendRoot(roots, value)
	if not finiteScalar(value) then return end
	for _, existing in roots do
		if math.abs(existing - value) <= 1e-7 * math.max(1, math.abs(value), math.abs(existing)) then
			return
		end
	end
	table.insert(roots, value)
end

local tracer = Instance.new('Part')
tracer.Anchored = true
tracer.CanCollide = false
tracer.CanQuery = false
tracer.CanTouch = false
tracer.CastShadow = false

local function cuberoot(x)
	return (x > 0) and math.pow(x, (1 / 3)) or -math.pow(math.abs(x), (1 / 3))
end

local function solveQuadric(c0, c1, c2)
	local s0, s1
	if not finiteScalar(c0) or not finiteScalar(c1) or not finiteScalar(c2) then return end
	-- Treat the leading coefficient relative to the polynomial scale.  The
	-- interception coefficients can be very small when the target is close,
	-- and an absolute zero check there turns a valid quadratic into a bogus
	-- linear solve.
	local scale = math.max(math.abs(c0), math.abs(c1), math.abs(c2))
	if scale <= 0 then return end
	local leadingEpsilon = eps * scale
	if math.abs(c0) <= leadingEpsilon then
		if math.abs(c1) <= leadingEpsilon then return end
		return -c2 / c1
	end

	-- Use the stable quadratic formula.  Computing (-b +/- sqrt(D))/(2a)
	-- directly loses the smaller root when b and sqrt(D) nearly cancel; that
	-- is a common source of late/early aim errors on moving targets.
	local discriminant = c1 * c1 - 4 * c0 * c2
	local discriminantEpsilon = eps * math.max(c1 * c1, math.abs(4 * c0 * c2), eps * eps)
	if discriminant < 0 and discriminant > -discriminantEpsilon then
		discriminant = 0
	end
	if discriminant < 0 then return end

	if discriminant == 0 then
		s0 = -c1 / (2 * c0)
		return s0
	end

	local sqrtDiscriminant = math.sqrt(discriminant)
	local q = -0.5 * (c1 + (c1 >= 0 and sqrtDiscriminant or -sqrtDiscriminant))
	if math.abs(q) <= leadingEpsilon then
		-- This is only reachable for extreme underflow/cancellation.  The
		-- repeated-root expression is preferable to returning an invalid root.
		return -c1 / (2 * c0)
	end
	s0 = q / c0
	s1 = c2 / q
	return s0, s1
end

local function solveCubic(c0, c1, c2, c3)
	local s0, s1, s2
	if not finiteScalar(c0) or not finiteScalar(c1) or not finiteScalar(c2) or not finiteScalar(c3) then return end
	if isZero(c0) then
		return solveQuadric(c1, c2, c3)
	end

	-- Normalize before applying Cardano.  Interception coefficients can span
	-- several orders of magnitude when the target is far away or accelerating.
	local scale = math.max(math.abs(c0), math.abs(c1), math.abs(c2), math.abs(c3))
	if scale <= 0 then return end
	c0, c1, c2, c3 = c0 / scale, c1 / scale, c2 / scale, c3 / scale

	local num, sub
	local A, B, C
	local sq_A, p, q
	local cb_p, D

	A = c1 / c0
	B = c2 / c0
	C = c3 / c0

	sq_A = A * A
	p = (1 / 3) * (-(1 / 3) * sq_A + B)
	q = 0.5 * ((2 / 27) * A * sq_A - (1 / 3) * A * B + C)

	cb_p = p * p * p
	D = q * q + cb_p

	if isZero(D) then
		if isZero(q) then -- one triple solution
			s0 = 0
			num = 1
		else -- one single and one double solution
			local u = cuberoot(-q)
			s0 = 2 * u
			s1 = -u
			num = 2
		end
	elseif (D < 0) then -- Casus irreducibilis: three real solutions
		local cosine = -q / math.sqrt(-cb_p)
		local phi = (1 / 3) * math.acos(math.clamp(cosine, -1, 1))
		local t = 2 * math.sqrt(-p)

		s0 = t * math.cos(phi)
		s1 = -t * math.cos(phi + math.pi / 3)
		s2 = -t * math.cos(phi - math.pi / 3)
		num = 3
	else -- one real solution
		local sqrt_D = math.sqrt(D)
		local u = cuberoot(sqrt_D - q)
		local v = -cuberoot(sqrt_D + q)

		s0 = u + v
		num = 1
	end

	sub = (1 / 3) * A

	if (num > 0) then s0 = s0 - sub end
	if (num > 1) then s1 = s1 - sub end
	if (num > 2) then s2 = s2 - sub end

	return s0, s1, s2
end

function module.solveQuartic(c0, c1, c2, c3, c4)
	local s0, s1, s2, s3
	if not finiteScalar(c0) or not finiteScalar(c1) or not finiteScalar(c2)
		or not finiteScalar(c3) or not finiteScalar(c4) then return end
	local scale = math.max(math.abs(c0), math.abs(c1), math.abs(c2), math.abs(c3), math.abs(c4))
	if scale <= 0 then return end
	c0, c1, c2, c3, c4 = c0 / scale, c1 / scale, c2 / scale, c3 / scale, c4 / scale

	-- A zero leading coefficient is a lower-degree polynomial, not a reason to
	-- divide by zero.  This is common for zero-gravity and short-range shots.
	if isZero(c0) then
		if not isZero(c1) then
			local roots = {solveCubic(c1, c2, c3, c4)}
			local returned = {}
			for _, root in roots do appendRoot(returned, root) end
			return #returned > 0 and returned or nil
		elseif not isZero(c2) then
			local roots = {solveQuadric(c2, c3, c4)}
			local returned = {}
			for _, root in roots do appendRoot(returned, root) end
			return #returned > 0 and returned or nil
		elseif not isZero(c3) then
			return {-c4 / c3}
		end
		return
	end

	local coeffs = {}
	local z, u, v, sub
	local A, B, C, D
	local sq_A, p, q, r
	local num

	A = c1 / c0
	B = c2 / c0
	C = c3 / c0
	D = c4 / c0

	sq_A = A * A
	p = -0.375 * sq_A + B
	q = 0.125 * sq_A * A - 0.5 * A * B + C
	r = -(3 / 256) * sq_A * sq_A + 0.0625 * sq_A * B - 0.25 * A * C + D

	if isZero(r) then
		coeffs[3] = q
		coeffs[2] = p
		coeffs[1] = 0
		coeffs[0] = 1

		local results = {solveCubic(coeffs[0], coeffs[1], coeffs[2], coeffs[3])}
		num = #results
		s0, s1, s2 = results[1], results[2], results[3]
	else
		coeffs[3] = 0.5 * r * p - 0.125 * q * q
		coeffs[2] = -r
		coeffs[1] = -0.5 * p
		coeffs[0] = 1

		s0, s1, s2 = solveCubic(coeffs[0], coeffs[1], coeffs[2], coeffs[3])
		z = s0
		-- A resolvent cubic should always have at least one real root, but
		-- floating-point cancellation can still leave Cardano without a usable
		-- value.  Return no roots and let SolveIntercept use its bounded numeric
		-- fallback instead of throwing from the arithmetic below.
		if not finiteScalar(z) then return end

		u = z * z - r
		v = 2 * z - p

		if isZero(u) then
			u = 0
		elseif (u > 0) then
			u = math.sqrt(u)
		else
			return
		end
		if isZero(v) then
			v = 0
		elseif (v > 0) then
			v = math.sqrt(v)
		else
			return
		end

		coeffs[2] = z - u
		coeffs[1] = q < 0 and -v or v
		coeffs[0] = 1

		do
			local results = {solveQuadric(coeffs[0], coeffs[1], coeffs[2])}
			num = #results
			s0, s1 = results[1], results[2]
		end

		coeffs[2] = z + u
		coeffs[1] = q < 0 and v or -v
		coeffs[0] = 1

		if (num == 0) then
			local results = {solveQuadric(coeffs[0], coeffs[1], coeffs[2])}
			num = num + #results
			s0, s1 = results[1], results[2]
		end
		if (num == 1) then
			local results = {solveQuadric(coeffs[0], coeffs[1], coeffs[2])}
			num = num + #results
			s1, s2 = results[1], results[2]
		end
		if (num == 2) then
			local results = {solveQuadric(coeffs[0], coeffs[1], coeffs[2])}
			num = num + #results
			s2, s3 = results[1], results[2]
		end
	end

	sub = 0.25 * A

	if (num > 0) then s0 = s0 - sub end
	if (num > 1) then s1 = s1 - sub end
	if (num > 2) then s2 = s2 - sub end
	if (num > 3) then s3 = s3 - sub end

	local returned = {}
	for _, root in {s3, s2, s1, s0} do
		appendRoot(returned, root)
	end
	return #returned > 0 and returned or nil
end

function module.SpawnTracer(from, to, custom)
    local distance = (to - from).Magnitude
    if distance < 0.01 then return end

    local t = tracer:Clone()
    t.Color = custom.Color
    t.Size = vector.create(custom.Thick, custom.Thick, distance)
    t.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -distance / 2)
    t.Material = custom.Material
	t.Transparency = custom.Opacity or 0

   	if custom.Fade then
		tweenService:Create(t, TweenInfo.new(custom.Lifetime), {
			Transparency = 1
		}):Play()
	end
    return t
end

function module.SpawnArcTracer(origin, aimDirection, projectileSpeed, gravity, travelTime, steps, custom)
    steps = steps or 20
    local stepTime = travelTime / steps
    local g = Vector3.new(0, -gravity, 0)
    local velocity = aimDirection * projectileSpeed

    local prevPos = origin
    local model = Instance.new('Model')
    model.Parent = workspace.Terrain
	if custom.Material == Enum.Material.Glass then
		Instance.new('Highlight', model).Enabled = false
	end
    for i = 1, steps do
        local t = i * stepTime
        local nextPos = origin + velocity * t + 0.5 * g * t * t
        local l = module.SpawnTracer(prevPos, nextPos, custom)
        l.Parent = model
        prevPos = nextPos
    end
	task.delay(custom.Lifetime, model.Destroy, model)
end

local function finiteNumber(value)
	return type(value) == 'number' and value == value and value > -math.huge and value < math.huge
end

local function finiteVector(value)
	return typeof(value) == 'Vector3'
		and finiteNumber(value.X)
		and finiteNumber(value.Y)
		and finiteNumber(value.Z)
end

local function interceptResidual(relativePosition, relativeVelocity, halfRelativeAcceleration, speed, time)
	local offset = relativePosition + relativeVelocity * time + halfRelativeAcceleration * (time * time)
	return offset:Dot(offset) - (speed * speed * time * time)
end

-- Solves |r + v*t + 0.5*(at-ap)*t^2| = projectileSpeed*t.  The result uses
-- the same speed supplied by the caller, so the solved angle and transmitted
-- velocity cannot drift apart.
function module.SolveIntercept(origin, projectileSpeed, projectileAcceleration, targetPosition, targetVelocity, targetAcceleration, minimumTime, maximumTime)
	if not finiteVector(origin) or not finiteVector(projectileAcceleration)
		or not finiteVector(targetPosition) or not finiteVector(targetVelocity)
		or not finiteVector(targetAcceleration) or not finiteNumber(projectileSpeed)
		or projectileSpeed <= eps then return nil end

	minimumTime = tonumber(minimumTime)
	if not finiteScalar(minimumTime) or minimumTime < 0 then minimumTime = 0 end
	minimumTime = math.max(minimumTime, eps)
	maximumTime = tonumber(maximumTime) or 10
	if not finiteNumber(maximumTime) or maximumTime < minimumTime then return nil end

	local relativePosition = targetPosition - origin
	local halfRelativeAcceleration = (targetAcceleration - projectileAcceleration) * 0.5
	local bestTime
	local function residualTolerance(root)
		local scale = math.max(projectileSpeed * projectileSpeed * root * root, 1)
		return math.max(0.0025, scale * 1e-5)
	end
	local function acceptRoot(root)
		if not finiteNumber(root) or root < minimumTime or root > maximumTime then return end
		local residual = math.abs(interceptResidual(
			relativePosition,
			targetVelocity,
			halfRelativeAcceleration,
			projectileSpeed,
			root
		))
		if residual <= residualTolerance(root)
			and (not bestTime or root < bestTime) then
			bestTime = root
		end
	end

	local c4 = halfRelativeAcceleration:Dot(halfRelativeAcceleration)
	local c3 = 2 * targetVelocity:Dot(halfRelativeAcceleration)
	local c2 = targetVelocity:Dot(targetVelocity)
		+ 2 * relativePosition:Dot(halfRelativeAcceleration)
		- projectileSpeed * projectileSpeed
	local c1 = 2 * relativePosition:Dot(targetVelocity)
	local c0 = relativePosition:Dot(relativePosition)
	local coefficientScale = math.max(math.abs(c4), math.abs(c3), math.abs(c2), math.abs(c1), math.abs(c0))
	if coefficientScale <= 0 then return nil end
	local coefficientEpsilon = coefficientScale * 1e-12
	if math.abs(c4) > coefficientEpsilon then
		-- A closed-form quartic is an optimization, not a hard dependency.  A
		-- degenerate resolvent or executor math edge case must fall through to the
		-- bounded numerical search instead of aborting the caller's target query.
		local solved, roots = pcall(module.solveQuartic, c4, c3, c2, c1, c0)
		if solved and type(roots) == 'table' then
			for _, root in roots do
				acceptRoot(root)
			end
		end
	elseif math.abs(c2) > coefficientEpsilon then
		local root0, root1 = solveQuadric(c2, c1, c0)
		acceptRoot(root0)
		acceptRoot(root1)
	elseif math.abs(c1) > coefficientEpsilon then
		acceptRoot(-c0 / c1)
	end

	-- Numerical fallback covers near-degenerate quartics and floating-point
	-- roots rejected by the closed form at very short ranges.
	if not bestTime then
		local steps = 192
		local times, values = {}, {}
		for step = 0, steps do
			local time = minimumTime + ((maximumTime - minimumTime) * step / steps)
			times[step + 1] = time
			values[step + 1] = interceptResidual(
				relativePosition,
				targetVelocity,
				halfRelativeAcceleration,
				projectileSpeed,
				time
			)
		end
		local function refineSignChange(low, high, lowValue)
			for _ = 1, 32 do
				local middle = (low + high) * 0.5
				local middleValue = interceptResidual(relativePosition, targetVelocity, halfRelativeAcceleration, projectileSpeed, middle)
				if math.abs(middleValue) <= residualTolerance(middle) then return middle end
				if (lowValue <= 0) == (middleValue <= 0) then
					low, lowValue = middle, middleValue
				else
					high = middle
				end
			end
			return (low + high) * 0.5
		end
		local function refineTangent(low, high)
			for _ = 1, 32 do
				local left = low + (high - low) / 3
				local right = high - (high - low) / 3
				local leftValue = math.abs(interceptResidual(relativePosition, targetVelocity, halfRelativeAcceleration, projectileSpeed, left))
				local rightValue = math.abs(interceptResidual(relativePosition, targetVelocity, halfRelativeAcceleration, projectileSpeed, right))
				if leftValue <= rightValue then high = right else low = left end
			end
			return (low + high) * 0.5
		end
		for index = 1, #times do
			local value = values[index]
			if math.abs(value) <= residualTolerance(times[index]) then acceptRoot(times[index]) end
			if index > 1 then
				local previousValue = values[index - 1]
				if (previousValue < 0 and value > 0) or (previousValue > 0 and value < 0) then
					acceptRoot(refineSignChange(times[index - 1], times[index], previousValue))
				end
			end
			if index > 1 and index < #times then
				local previousAbs, nextAbs = math.abs(values[index - 1]), math.abs(values[index + 1])
				if math.abs(value) <= previousAbs and math.abs(value) <= nextAbs then
					acceptRoot(refineTangent(times[index - 1], times[index + 1]))
				end
			end
		end
	end
	if not bestTime then return nil end

	local displacement = relativePosition
		+ targetVelocity * bestTime
		+ halfRelativeAcceleration * (bestTime * bestTime)
	if displacement.Magnitude <= eps then return nil end
	local initialVelocity = displacement / bestTime
	return {
		AimPosition = origin + initialVelocity,
		FlightTime = bestTime,
		ImpactPosition = targetPosition
			+ targetVelocity * bestTime
			+ targetAcceleration * (0.5 * bestTime * bestTime),
		InitialVelocity = initialVelocity
	}
end

function module.SolveTrajectory(origin, projectileSpeed, gravity, targetPos, targetVelocity, playerGravity, playerHeight, playerJump, params)
	if typeof(origin) ~= 'Vector3' or typeof(targetPos) ~= 'Vector3'
		or typeof(targetVelocity) ~= 'Vector3' or not finiteScalar(projectileSpeed)
		or projectileSpeed <= eps then return end
	gravity = math.abs(tonumber(gravity) or 0)
	if not finiteScalar(gravity) then return end
	local numericHeight = tonumber(playerHeight)
	if numericHeight ~= nil and (not finiteScalar(numericHeight) or numericHeight < 0) then
		numericHeight = nil
	end

	local velocity = targetVelocity
	local grounded = false
	if numericHeight and numericHeight > 0 then
		local success, ray = pcall(workspace.Raycast, workspace, targetPos,
			Vector3.new(0, -numericHeight - 0.5, 0), params)
		grounded = success and ray ~= nil and velocity.Y <= 0.1
	end
	if grounded then
		-- A floor hit means the target is supported; its vertical velocity is
		-- zero, not the distance to the floor.  The old code injected that
		-- distance as a downward speed and systematically aimed low.
		velocity = Vector3.new(velocity.X, 0, velocity.Z)
	end

	local targetAcceleration = Vector3.zero
	-- Once the floor probe says the target is airborne, gravity still applies at
	-- the apex where Y velocity is zero.  The previous velocity/jump gate made
	-- that single frame look stationary and caused a systematic low shot.
	local targetGravity = tonumber(playerGravity)
	if not grounded and finiteScalar(targetGravity) and targetGravity > 0 then
		targetAcceleration = Vector3.new(0, -targetGravity, 0)
	end
	local solution = module.SolveIntercept(
		origin,
		projectileSpeed,
		Vector3.new(0, -gravity, 0),
		targetPos,
		velocity,
		targetAcceleration,
		0,
		10
	)
	if solution and solution.InitialVelocity.Magnitude > eps then
		return solution.AimPosition, solution.InitialVelocity.Unit, solution.FlightTime
	end
	return nil
end

return module
