local entitylib = {
	isAlive = false,
	character = {},
	List = {},
	Connections = {},
	PlayerConnections = {},
	EntityThreads = {},
	Running = false,
	Events = setmetatable({}, {
		__index = function(self, ind)
			self[ind] = {
				Connections = {},
				Connect = function(rself, func)
					table.insert(rself.Connections, func)
					return {
						Disconnect = function()
							local rind = table.find(rself.Connections, func)
							if rind then
								table.remove(rself.Connections, rind)
							end
						end
					}
				end,
				Fire = function(rself, ...)
					for _, v in rself.Connections do
						task.spawn(v, ...)
					end
				end,
				Destroy = function(rself)
					table.clear(rself.Connections)
					table.clear(rself)
				end
			}

			return self[ind]
		end
	})
}

local cloneref = cloneref or function(obj)
	return obj
end
local playersService = cloneref(game:GetService('Players'))
local inputService = cloneref(game:GetService('UserInputService'))
local lplr = playersService.LocalPlayer
local gameCamera = workspace.CurrentCamera

local function getMousePosition()
	if inputService.TouchEnabled then
		return gameCamera.ViewportSize / 2
	end
	return inputService.GetMouseLocation(inputService)
end

local function sortDistance(a, b)
	return a.Magnitude < b.Magnitude
end

local function finiteNumber(value)
	return type(value) == 'number'
		and value == value
		and value > -math.huge
		and value < math.huge
end

local function finiteVector(value)
	return typeof(value) == 'Vector3'
		and finiteNumber(value.X)
		and finiteNumber(value.Y)
		and finiteNumber(value.Z)
end

local function normalizeRange(value)
	local range = tonumber(value)
	if not finiteNumber(range) then return math.huge end
	return math.max(range, 0)
end

local function normalizeLimit(value)
	local limit = tonumber(value)
	if not finiteNumber(limit) then return math.huge end
	return math.max(math.floor(limit), 0)
end

local function getLiveEntityPart(ent, partName)
	local part = ent and partName and ent[partName]
	if not part and ent then
		part = ent.RootPart or ent.HumanoidRootPart
	end
	if not part or not part.Parent then return nil end
	local success, isPart = pcall(part.IsA, part, 'BasePart')
	if not success or not isPart then return nil end
	local character = ent.Character
	if character and part ~= character and typeof(character) == 'Instance' then
		local descendantSuccess, isDescendant = pcall(part.IsDescendantOf, part, character)
		if not descendantSuccess or not isDescendant then return nil end
	end
	return part
end

local function entityIsVulnerable(ent)
	local success, vulnerable = pcall(entitylib.isVulnerable, ent)
	return success and vulnerable
end

local function entityIsTargetable(ent)
	-- Game adapters can expose friend/target state that is not represented by a
	-- Roblox signal (for example a GUI-maintained name list).  Give the adapter
	-- a chance to refresh those cached flags immediately before every query.
	if type(entitylib.refreshTargetState) == 'function' then
		pcall(entitylib.refreshTargetState, ent)
	end
	local success, targetable = pcall(entitylib.targetCheck, ent)
	if success and ent.Targetable ~= targetable then
		ent.Targetable = targetable
		entitylib.Events.EntityUpdated:Fire(ent)
	end
	return success and targetable == true
end

local function loopClean(tbl)
	for i, v in tbl do
		if type(v) == 'table' then
			loopClean(v)
		end
		tbl[i] = nil
	end
end

local function waitForChildOfType(obj, name, timeout, prop)
	local checktick = tick() + timeout
	local returned
	repeat
		returned = prop and obj[name] or obj:FindFirstChildOfClass(name)
		if returned or checktick < tick() then break end
		task.wait()
	until false
	return returned
end

entitylib.targetCheck = function(ent)
	if not ent then return false end
	if ent.TeamCheck then
		local success, result = pcall(ent.TeamCheck, ent)
		return success and result == true
	end
	if ent.NPC then return true end
	if not ent.Player or not lplr then return false end
	if not lplr.Team then return true end
	if not ent.Player.Team then return true end
	if ent.Player.Team ~= lplr.Team then return true end
	return #ent.Player.Team:GetPlayers() == #playersService:GetPlayers()
end

entitylib.getUpdateConnections = function(ent)
	local hum = ent.Humanoid
	local returned = {}
	if hum and hum.GetPropertyChangedSignal then
		table.insert(returned, hum:GetPropertyChangedSignal('Health'))
		table.insert(returned, hum:GetPropertyChangedSignal('MaxHealth'))
	end
	return returned
end

entitylib.isVulnerable = function(ent)
	local health = ent and tonumber(ent.Health)
	local character = ent and ent.Character
	if not health or health <= 0 or not character or not character.Parent then return false end
	local success, forceField = pcall(
		character.FindFirstChildWhichIsA,
		character,
		'ForceField'
	)
	return success and not forceField
end

entitylib.getEntityColor = function(ent)
	ent = ent and ent.Player
	return ent and ent.TeamColor and tostring(ent.TeamColor) ~= 'White' and ent.TeamColor.Color or nil
end

entitylib.IgnoreObject = RaycastParams.new()
-- Keep the filter mode explicit.  Relying on the engine default made the
-- result depend on the executor/Roblox build that created the params object.
entitylib.IgnoreObject.FilterType = Enum.RaycastFilterType.Exclude
entitylib.IgnoreObject.RespectCanCollide = true
entitylib.IgnoreObject.IgnoreWater = true
entitylib.Wallcheck = function(origin, position, ignoreobject)
	if not finiteVector(origin) or not finiteVector(position) then
		return nil
	end

	if typeof(ignoreobject) ~= 'Instance' then
		local ignorelist = {gameCamera, lplr.Character}
		for _, v in entitylib.List do
			if v.Targetable then
				table.insert(ignorelist, v.Character)
			end
		end

		if typeof(ignoreobject) == 'table' then
			for _, v in ignoreobject do
				table.insert(ignorelist, v)
			end
		end

		ignoreobject = entitylib.IgnoreObject
		ignoreobject.FilterDescendantsInstances = ignorelist
	end

	local delta = position - origin
	if delta.Magnitude <= 1e-5 then
		return nil
	end

	-- FloodCraft's sword controller checks more than one body height.  A single
	-- root-to-root ray can miss a wall that covers the torso/head while leaving
	-- the root ray clear (or report a false block when only the feet are hidden).
	-- Preserve the first hit for callers that use the return value, but accept
	-- the target when any of the sampled sight lines is clear, matching the
	-- native canSee contract.
	local firstHit = workspace.Raycast(workspace, origin, delta, ignoreobject)
	if not firstHit then
		return nil
	end
	local samples = {
		Vector3.zero,
		Vector3.new(0, 2.5, 0),
		Vector3.new(0, -2.5, 0)
	}
	for _, offset in samples do
		if not workspace.Raycast(workspace, origin + offset, delta, ignoreobject) then
			return nil
		end
	end
	return firstHit
end

entitylib.EntityMouse = function(entitysettings)
	if entitylib.isAlive then
		local mouseLocation, sortingTable = entitysettings.MouseOrigin or getMousePosition(), {}
		local range = normalizeRange(entitysettings.Range)
		for _, v in entitylib.List do
			if not entitysettings.Players and v.Player then continue end
			if not entitysettings.NPCs and v.NPC then continue end
			if not entityIsTargetable(v) then continue end
			local part = getLiveEntityPart(v, entitysettings.Part)
			if not part then continue end
			local position, vis = gameCamera.WorldToViewportPoint(gameCamera, part.Position)
			if not vis then continue end
			local mag = (mouseLocation - Vector2.new(position.x, position.y)).Magnitude
			if mag > range then continue end
			if entityIsVulnerable(v) then
				table.insert(sortingTable, {
					Entity = v,
					Magnitude = v.Target and -1 or mag
				})
			end
		end

		if #sortingTable > 1 then
			table.sort(sortingTable, entitysettings.Sort or sortDistance)
		end

		for _, v in sortingTable do
			local part = getLiveEntityPart(v.Entity, entitysettings.Part)
			if not part or not v.Entity.Targetable or not entityIsVulnerable(v.Entity) then continue end
			if entitysettings.Wallcheck then
				if not entitysettings.Origin
					or entitylib.Wallcheck(entitysettings.Origin, part.Position, entitysettings.Wallcheck) then continue end
			end
			table.clear(entitysettings)
			table.clear(sortingTable)
			return v.Entity
		end
		table.clear(sortingTable)
	end
	table.clear(entitysettings)
end

entitylib.EntityPosition = function(entitysettings)
	if entitylib.isAlive then
		local localRoot = entitylib.character and entitylib.character.HumanoidRootPart
		local localPosition, sortingTable = entitysettings.Origin or (localRoot and localRoot.Parent and localRoot.Position), {}
		if not finiteVector(localPosition) then
			table.clear(entitysettings)
			return
		end
		local range, customSort = normalizeRange(entitysettings.Range), entitysettings.Sort or entitysettings.Priority
		local rangeSquared = range * range
		for _, v in entitylib.List do
			if not entitysettings.Players and v.Player then continue end
			if not entitysettings.NPCs and v.NPC then continue end
			if not entityIsTargetable(v) then continue end
			local part = getLiveEntityPart(v, entitysettings.Part)
			if not part then continue end
			local delta = part.Position - localPosition
			local mag = delta:Dot(delta)
			if mag > rangeSquared then continue end
			if entityIsVulnerable(v) then
				table.insert(sortingTable, {
					Entity = v,
					Magnitude = v.Target and -1 or (customSort and math.sqrt(mag) or mag)
				})
			end
		end

		if #sortingTable > 1 then
			table.sort(sortingTable, entitysettings.Sort or sortDistance)
			if entitysettings.Priority then
				table.sort(sortingTable, entitysettings.Priority)
			end
		end

		for _, v in sortingTable do
			local part = getLiveEntityPart(v.Entity, entitysettings.Part)
			if not part or not v.Entity.Targetable or not entityIsVulnerable(v.Entity) then continue end
			if entitysettings.Wallcheck then
				if entitylib.Wallcheck(localPosition, part.Position, entitysettings.Wallcheck) then continue end
			end
			table.clear(entitysettings)
			table.clear(sortingTable)
			return v.Entity
		end
		table.clear(sortingTable)
	end
	table.clear(entitysettings)
end

entitylib.AllPosition = function(entitysettings)
	local returned = {}
	if entitylib.isAlive then
		local localRoot = entitylib.character and entitylib.character.HumanoidRootPart
		local localPosition, sortingTable = entitysettings.Origin or (localRoot and localRoot.Parent and localRoot.Position), {}
		if not finiteVector(localPosition) then
			table.clear(entitysettings)
			return returned
		end
		local range, customSort = normalizeRange(entitysettings.Range), entitysettings.Sort
		local limit = normalizeLimit(entitysettings.Limit)
		if limit <= 0 then
			table.clear(entitysettings)
			return returned
		end
		local rangeSquared = range * range
		for _, v in entitylib.List do
			if not entitysettings.Players and v.Player then continue end
			if not entitysettings.NPCs and v.NPC then continue end
			if not entityIsTargetable(v) then continue end
			local part = getLiveEntityPart(v, entitysettings.Part)
			if not part then continue end
			local delta = part.Position - localPosition
			local mag = delta:Dot(delta)
			if mag > rangeSquared then continue end
			if entityIsVulnerable(v) then
				table.insert(sortingTable, {Entity = v, Magnitude = v.Target and -1 or (customSort and math.sqrt(mag) or mag)})
			end
		end

		if #sortingTable > 1 then
			table.sort(sortingTable, entitysettings.Sort or sortDistance)
		end

		for _, v in sortingTable do
			local part = getLiveEntityPart(v.Entity, entitysettings.Part)
			if not part or not v.Entity.Targetable or not entityIsVulnerable(v.Entity) then continue end
			if entitysettings.Wallcheck then
				if entitylib.Wallcheck(localPosition, part.Position, entitysettings.Wallcheck) then continue end
			end
			table.insert(returned, v.Entity)
			if #returned >= limit then break end
		end
		table.clear(sortingTable)
	end
	table.clear(entitysettings)
	return returned
end

entitylib.getEntity = function(char)
	local localEntity = entitylib.character
	if localEntity and (localEntity.Player == char or localEntity.Character == char) then
		return localEntity
	end
	for i, v in entitylib.List do
		if v.Player == char or v.Character == char then
			return v, i
		end
	end
end

entitylib.addEntity = function(char, plr, teamfunc)
	if not char then return end
	-- CollectionService and CharacterAdded can both report the same instance
	-- during streaming.  Do not create duplicate records or leave two pending
	-- registration coroutines racing to publish one entity.
	if entitylib.getEntity(char) or entitylib.EntityThreads[char] then return end
	entitylib.EntityThreads[char] = task.spawn(function()
		local hum = waitForChildOfType(char, 'Humanoid', 10)
		local humrootpart = hum and waitForChildOfType(hum, 'RootPart', workspace.StreamingEnabled and 9e9 or 10, true)
		local head = char:WaitForChild('Head', 10) or humrootpart

		if hum and humrootpart then
			local entity = {
				Connections = {},
				Character = char,
				Health = hum.Health,
				Head = head,
				Humanoid = hum,
				HumanoidRootPart = humrootpart,
				HipHeight = hum.HipHeight + (humrootpart.Size.Y / 2) + (hum.RigType == Enum.HumanoidRigType.R6 and 2 or 0),
				MaxHealth = hum.MaxHealth,
				NPC = plr == nil,
				Player = plr,
				RootPart = humrootpart,
				TeamCheck = teamfunc
			}

			if plr == lplr then
				entitylib.character = entity
				entitylib.isAlive = true
				entitylib.Events.LocalAdded:Fire(entity)
			else
				entity.Targetable = entitylib.targetCheck(entity)
				table.insert(entity.Connections, hum.AnimationPlayed:Connect(function(track)
					entitylib.Events.AnimationPlayed:Fire(plr, track)
				end))

				for _, v in entitylib.getUpdateConnections(entity) do
					table.insert(entity.Connections, v:Connect(function()
						entity.Health = hum.Health
						entity.MaxHealth = hum.MaxHealth
						entitylib.Events.EntityUpdated:Fire(entity)
					end))
				end

				table.insert(entitylib.List, entity)
				entitylib.Events.EntityAdded:Fire(entity)
			end

			-- Character rigs can replace their root/head while the Character instance
			-- itself remains alive (streaming, respawn staging, and controller swaps).
			-- Keep the entity record pointed at live instances instead of leaving every
			-- consumer with a destroyed part.
			local refreshQueued = false
			local function refreshParts()
				if not char.Parent
					or (plr == lplr and (entitylib.character ~= entity or not entitylib.isAlive))
					or (plr ~= lplr and entitylib.getEntity(char) ~= entity) then return end
				local currentHum = char:FindFirstChildWhichIsA('Humanoid', true)
				if currentHum ~= hum then
					entitylib.removeEntity(char, plr == lplr)
					task.defer(entitylib.addEntity, char, plr, teamfunc)
					return
				end
				local currentRoot = (currentHum and currentHum.RootPart) or char:FindFirstChild('HumanoidRootPart', true)
				local currentHead = char:FindFirstChild('Head', true) or currentRoot
				if not currentRoot or not currentRoot.Parent then return end
				humrootpart = currentRoot
				head = currentHead or currentRoot
				entity.HumanoidRootPart = currentRoot
				entity.RootPart = currentRoot
				entity.Head = currentHead or currentRoot
				entity.HipHeight = hum.HipHeight + (currentRoot.Size.Y / 2) + (hum.RigType == Enum.HumanoidRigType.R6 and 2 or 0)
				entitylib.Events.EntityUpdated:Fire(entity)
			end
			local function queueRefresh()
				if refreshQueued then return end
				refreshQueued = true
				task.defer(function()
					refreshQueued = false
					refreshParts()
				end)
			end
			table.insert(entity.Connections, char.DescendantAdded:Connect(function(descendant)
				if descendant:IsA('Humanoid') or descendant:IsA('BasePart')
					or descendant.Name == 'Head' or descendant.Name == 'HumanoidRootPart' then
					queueRefresh()
				end
			end))
			table.insert(entity.Connections, char.DescendantRemoving:Connect(function(descendant)
				if descendant == humrootpart or descendant == head or descendant == hum then
					queueRefresh()
				end
			end))
			if hum.GetPropertyChangedSignal then
				table.insert(entity.Connections, hum:GetPropertyChangedSignal('RootPart'):Connect(queueRefresh))
			end
			if char.GetPropertyChangedSignal then
				local ok, signal = pcall(char.GetPropertyChangedSignal, char, 'PrimaryPart')
				if ok and signal then
					table.insert(entity.Connections, signal:Connect(queueRefresh))
				end
			end
		end
		entitylib.EntityThreads[char] = nil
	end)
end

entitylib.removeEntity = function(char, localcheck)
	-- A character can be removed while its registration coroutine is still
	-- waiting for a streamed Humanoid/root. Cancel it before the local-entity
	-- fast path so it cannot publish a ghost record after respawn.
	if char and entitylib.EntityThreads[char] then
		task.cancel(entitylib.EntityThreads[char])
		entitylib.EntityThreads[char] = nil
	end
	if localcheck then
		local current = entitylib.character
		-- Ignore a late CharacterRemoving signal for an old rig after a new
		-- character has already been registered.  Without the identity check it
		-- could mark the new local entity dead.  When the current record does
		-- match, always detach and replace it, even if isAlive was already false:
		-- Team changes call start()->stop()->refreshEntity(), and leaving the dead
		-- record in place makes addEntity() reject the replacement as a duplicate.
		if type(current) == 'table' and (not char or current.Character == char) then
			local wasAlive = entitylib.isAlive
			entitylib.isAlive = false
			local connections = current.Connections
			if type(connections) == 'table' then
				for _, v in connections do
					if v and v.Disconnect then
						v:Disconnect()
					end
				end
				table.clear(connections)
			end
			if wasAlive then
				entitylib.Events.LocalRemoved:Fire(current)
			end
			-- Do not leave a record that still matches char: addEntity() uses
			-- getEntity() as its duplicate guard.  A fresh table lets the next
			-- refresh/register operation publish the live local entity.
			if entitylib.character == current then
				entitylib.character = {}
			end
		end
		return
	end

	if char then
		local entity, ind = entitylib.getEntity(char)
		if entity and not ind and entity == entitylib.character then
			-- The local entity is intentionally not stored in List.  A caller that
			-- removes it by Character/Player still needs the same teardown path.
			entitylib.removeEntity(entity.Character, true)
			return
		end
		if ind then
			for _, v in entity.Connections do
				v:Disconnect()
			end
			table.clear(entity.Connections)
			table.remove(entitylib.List, ind)
			entitylib.Events.EntityRemoved:Fire(entity)
		end
	end
end

entitylib.refreshEntity = function(char, plr)
	-- Local characters are not stored in List, so the old removeEntity(char)
	-- call silently left the previous local record alive during a team/respawn
	-- refresh.  That leaked attribute connections and allowed two local records
	-- to race for entitylib.character.  Use the local cleanup path explicitly.
	entitylib.removeEntity(char, plr == lplr)
	entitylib.addEntity(char, plr)
end

entitylib.addPlayer = function(plr)
	if plr.Character then
		entitylib.refreshEntity(plr.Character, plr)
	end
	entitylib.PlayerConnections[plr] = {
		plr.CharacterAdded:Connect(function(char)
			entitylib.refreshEntity(char, plr)
		end),
		plr.CharacterRemoving:Connect(function(char)
			entitylib.removeEntity(char, plr == lplr)
		end),
		plr:GetPropertyChangedSignal('Team'):Connect(function()
			for _, v in entitylib.List do
				if v.Targetable ~= entitylib.targetCheck(v) then
					entitylib.refreshEntity(v.Character, v.Player)
				end
			end

			if plr == lplr then
				entitylib.start()
			else
				entitylib.refreshEntity(plr.Character, plr)
			end
		end)
	}
end

entitylib.removePlayer = function(plr)
	if entitylib.PlayerConnections[plr] then
		for _, v in entitylib.PlayerConnections[plr] do
			v:Disconnect()
		end
		table.clear(entitylib.PlayerConnections[plr])
		entitylib.PlayerConnections[plr] = nil
	end
	local character = plr and plr.Character
	if character then
		entitylib.removeEntity(character, plr == lplr)
	elseif plr == lplr and entitylib.character and entitylib.character.Character then
		-- PlayerRemoving can run after CharacterRemoving has detached Character.
		-- Still tear down the local record instead of leaving it marked alive.
		entitylib.removeEntity(entitylib.character.Character, true)
	end
	-- Keep the player-object lookup for records whose Character has already
	-- been detached before PlayerRemoving fires.
	entitylib.removeEntity(plr)
end

entitylib.start = function()
	if entitylib.Running then
		entitylib.stop()
	end
	table.insert(entitylib.Connections, playersService.PlayerAdded:Connect(function(v)
		entitylib.addPlayer(v)
	end))
	table.insert(entitylib.Connections, playersService.PlayerRemoving:Connect(function(v)
		entitylib.removePlayer(v)
	end))
	for _, v in playersService:GetPlayers() do
		entitylib.addPlayer(v)
	end
	table.insert(entitylib.Connections, workspace:GetPropertyChangedSignal('CurrentCamera'):Connect(function()
		gameCamera = workspace.CurrentCamera or workspace:FindFirstChildWhichIsA('Camera')
	end))
	entitylib.Running = true
end

entitylib.stop = function()
	for _, v in entitylib.Connections do
		v:Disconnect()
	end
	for _, v in entitylib.PlayerConnections do
		for _, v2 in v do
			v2:Disconnect()
		end
		table.clear(v)
	end
	entitylib.removeEntity(nil, true)
	local cloned = table.clone(entitylib.List)
	for _, v in cloned do
		entitylib.removeEntity(v.Character)
	end
	for _, v in entitylib.EntityThreads do
		task.cancel(v)
	end
	table.clear(entitylib.PlayerConnections)
	table.clear(entitylib.EntityThreads)
	table.clear(entitylib.Connections)
	table.clear(cloned)
	entitylib.Running = false
end

entitylib.kill = function()
	if entitylib.Running then
		entitylib.stop()
	end
	for _, v in entitylib.Events do
		v:Destroy()
	end
	entitylib.IgnoreObject:Destroy()
	loopClean(entitylib)
end

entitylib.refresh = function()
	local cloned = table.clone(entitylib.List)
	for _, v in cloned do
		entitylib.refreshEntity(v.Character, v.Player)
	end
	table.clear(cloned)
end

entitylib.start()

return entitylib
