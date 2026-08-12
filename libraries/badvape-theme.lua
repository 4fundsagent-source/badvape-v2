return function(vape, entitylib)
	if not vape then
		return
	end

	for _ = 1, 60 do
		if vape.Categories and vape.Categories.Render then
			break
		end
		task.wait()
	end

	if not vape.Categories or not vape.Categories.Render then
		return
	end

	if vape.Modules and vape.Modules.Theme then
		return
	end

	local cloneref = cloneref or function(object)
		return object
	end

	local lightingService = cloneref(game:GetService('Lighting'))
	local tweenService = cloneref(game:GetService('TweenService'))
	local collectionService = cloneref(game:GetService('CollectionService'))
	local playersService = cloneref(game:GetService('Players'))
	local localPlayer = playersService.LocalPlayer

	local Theme
	local Mode
	local RemoveClouds
	local CloudSize
	local CloudTransparency
	local newObjects = {}
	local oldObjects = {}
	local storeBlocks = {}
	local originalSettings = {}
	local preservedClouds = setmetatable({}, {__mode = 'k'})
	local preservedCloudParts = setmetatable({}, {__mode = 'k'})
	local timeConnection
	local currentCloud
	local characterConnection
	local cleanFunc
	local waterTask
	local waterGeneration = 0
	local waterRegion
	local terrainSettings = {}
	local mapReadySince = 0
	local rootStableSince = 0
	local waterWorlds
	local waterTeam
	local waterBounds
	local waterBoundsSampledAt = 0
	local waterBoundsSignature
	-- Keep the historical footprint.  Placement is map-derived below, but the
	-- plane itself stays 5000x5000 so smaller maps do not regress to the old
	-- 2048-stud area.
	local waterPlaneSize = 5000
	local restoreWorkspaceClouds
	local applyCloudRemovalState

	local function getEntityLibrary()
		return entitylib or vape.Libraries and vape.Libraries.entity
	end

	local function getRuntimeStore()
		local environments = {}
		if type(getgenv) == 'function' then
			local ok, environment = pcall(getgenv)
			if ok and type(environment) == 'table' then
				table.insert(environments, environment)
			end
		end
		if type(getfenv) == 'function' then
			local ok, environment = pcall(getfenv, 0)
			if ok and type(environment) == 'table' then
				table.insert(environments, environment)
			end
		end
		if type(_G) == 'table' then table.insert(environments, _G) end
		if type(shared) == 'table' then table.insert(environments, shared) end
		for _, environment in environments do
			local store = rawget(environment, 'BadVapeStore')
			if type(store) == 'table' then return store end
		end
	end

	local function cancelWaterTask()
		waterGeneration += 1
		if waterTask then
			pcall(task.cancel, waterTask)
			waterTask = nil
		end
	end

	local function clearWaterRegion()
		local region = waterRegion
		waterRegion = nil
		if not region then return end
		local terrain = workspace:FindFirstChildOfClass('Terrain')
		if terrain then
			-- Only clear the thin region created by Theme.  The previous cleanup
			-- called Terrain:Clear(), which erased the loaded map and left the
			-- player under/inside the skybox after a respawn.
			pcall(function()
				terrain:FillBlock(region.CFrame, region.Size, Enum.Material.Air)
			end)
		end
	end

	local function removeOldLightingObject(object)
		if table.find(newObjects, object) then
			return
		end

		if object:IsA('Sky')
			or object:IsA('Atmosphere')
			or object:IsA('BloomEffect')
			or object:IsA('DepthOfFieldEffect')
			or object:IsA('ColorCorrectionEffect')
			or object:IsA('SunRaysEffect')
			or object:IsA('Clouds') then
			if object.Parent then
				table.insert(oldObjects, object)
				object.Parent = game
			end
		end
	end

	local function cleanup()
		mapReadySince = 0
		rootStableSince = 0
		waterWorlds = nil
		waterTeam = nil
		waterBounds = nil
		waterBoundsSampledAt = 0
		waterBoundsSignature = nil
		for _, object in newObjects do
			if object and object.Parent then
				object:Destroy()
			end
		end
		table.clear(newObjects)

		for _, object in oldObjects do
			if object then
				object.Parent = lightingService
			end
		end
		table.clear(oldObjects)

		if timeConnection then
			timeConnection:Disconnect()
			timeConnection = nil
		end

		if characterConnection then
			characterConnection:Disconnect()
			characterConnection = nil
		end

		if currentCloud then
			currentCloud:Destroy()
			currentCloud = nil
		end

		if restoreWorkspaceClouds then restoreWorkspaceClouds() end

		if cleanFunc then
			cleanFunc()
			cleanFunc = nil
		end

		cancelWaterTask()
		clearWaterRegion()
		local terrain = workspace:FindFirstChildOfClass('Terrain')
		if terrain and terrainSettings.WaterColor then
			for property, value in terrainSettings do
				pcall(function()
					terrain[property] = value
				end)
			end
		end
		table.clear(terrainSettings)

		if originalSettings.Ambient then
			lightingService.Ambient = originalSettings.Ambient
			lightingService.Brightness = originalSettings.Brightness
			lightingService.ColorShift_Bottom = originalSettings.ColorShift_Bottom
			lightingService.ColorShift_Top = originalSettings.ColorShift_Top
			lightingService.EnvironmentDiffuseScale = originalSettings.EnvironmentDiffuseScale
			lightingService.EnvironmentSpecularScale = originalSettings.EnvironmentSpecularScale
			lightingService.GlobalShadows = originalSettings.GlobalShadows
			lightingService.OutdoorAmbient = originalSettings.OutdoorAmbient
			lightingService.ShadowSoftness = originalSettings.ShadowSoftness
			lightingService.Technology = originalSettings.Technology
			lightingService.ClockTime = originalSettings.ClockTime
			lightingService.GeographicLatitude = originalSettings.GeographicLatitude
			table.clear(originalSettings)
		end
	end

	local function removeWorkspaceClouds()
		if workspace:FindFirstChild('Clouds') then
			for _, object in workspace.Clouds:GetChildren() do
				if object:IsA('Part') then
					if not preservedCloudParts[object] then
						preservedCloudParts[object] = {
							Transparency = object.Transparency,
							LocalTransparencyModifier = object.LocalTransparencyModifier,
						}
					end
					object.Transparency = 1
				end
			end
		end

		for _, object in workspace:GetDescendants() do
			if object:IsA('Clouds') then
				if object ~= currentCloud and not preservedClouds[object] then
					preservedClouds[object] = {
						Parent = object.Parent,
						Enabled = object.Enabled,
						Cover = object.Cover,
						Density = object.Density,
						Color = object.Color,
					}
					pcall(function() object.Parent = game end)
				end
			end
		end
	end

	local function hideWorkspaceCloudParts()
		if workspace:FindFirstChild('Clouds') then
			for _, object in workspace.Clouds:GetChildren() do
				if object:IsA('Part') then
					if not preservedCloudParts[object] then
						preservedCloudParts[object] = {
							Transparency = object.Transparency,
							LocalTransparencyModifier = object.LocalTransparencyModifier,
						}
					end
					object.Transparency = 1
				end
			end
		end
	end

	restoreWorkspaceClouds = function()
		for object, state in preservedClouds do
			if object then
				pcall(function()
					object.Enabled = state.Enabled
					object.Cover = state.Cover
					object.Density = state.Density
					object.Color = state.Color
					object.Parent = state.Parent
				end)
			end
			preservedClouds[object] = nil
		end
		for object, state in preservedCloudParts do
			if object then
				pcall(function()
					object.Transparency = state.Transparency
					object.LocalTransparencyModifier = state.LocalTransparencyModifier
				end)
			end
			preservedCloudParts[object] = nil
		end
	end

	applyCloudRemovalState = function()
		if not Theme or not Theme.Enabled then return end
		if RemoveClouds and RemoveClouds.Enabled then
			removeWorkspaceClouds()
			hideWorkspaceCloudParts()
		else
			restoreWorkspaceClouds()
		end
	end

	-- Roblox's Clouds object exposes Cover (how much of the sky is filled),
	-- Density (opacity), and Color.  Keep the user-facing controls in the
	-- more intuitive size/transparency terms and apply them to the one cloud
	-- instance owned by Theme.  This also avoids the old weather coroutine
	-- repeatedly overwriting the user's values.
	local function applyCloudSettings()
		if not currentCloud or not currentCloud.Parent then return end
		local size = CloudSize and tonumber(CloudSize.Value) or 0.8
		local transparency = CloudTransparency and tonumber(CloudTransparency.Value) or 0.1
		-- Realistic clouds use the neutral white/gray game default.  The old
		-- color control silently fell back to hue 0.44 in the GUI and tinted
		-- clouds turquoise, even when no custom color was selected.
		local colorValue = Color3.new(1, 1, 1)
		pcall(function()
			currentCloud.Cover = math.clamp(size, 0, 1)
			currentCloud.Density = 1 - math.clamp(transparency, 0, 1)
			currentCloud.Color = colorValue
		end)
	end

	local function applyBlavish()
		if RemoveClouds and RemoveClouds.Enabled then
			removeWorkspaceClouds()
		end
		lightingService.ClockTime = 6.1

		local sky = Instance.new('Sky')
		sky.Parent = lightingService
		sky.SkyboxBk = 'rbxassetid://8139677359'
		sky.SkyboxDn = 'rbxassetid://8139677253'
		sky.SkyboxFt = 'rbxassetid://8139677111'
		sky.SkyboxLf = 'rbxassetid://8139676988'
		sky.SkyboxRt = 'rbxassetid://8139676842'
		sky.SkyboxUp = 'rbxassetid://8139676647'
		sky.SunTextureId = 'rbxassetid://6196665106'
		sky.MoonTextureId = 'rbxassetid://8139665943'
		sky.StarCount = 50
		sky.SunAngularSize = 0
		sky.MoonAngularSize = 0
		table.insert(newObjects, sky)

		local colorCorrection = Instance.new('ColorCorrectionEffect')
		colorCorrection.Parent = lightingService
		colorCorrection.Enabled = false
		colorCorrection.Brightness = 0
		colorCorrection.Contrast = 0.1
		colorCorrection.Saturation = 0
		colorCorrection.TintColor = Color3.fromHSV(0.80625, 1, 1)
		table.insert(newObjects, colorCorrection)

		local sunRays = Instance.new('SunRaysEffect')
		sunRays.Parent = lightingService
		sunRays.Enabled = false
		sunRays.Intensity = 0
		sunRays.Spread = 0
		table.insert(newObjects, sunRays)

		local bloom = Instance.new('BloomEffect')
		bloom.Parent = lightingService
		bloom.Enabled = false
		bloom.Intensity = 0
		bloom.Size = 0
		bloom.Threshold = 0
		table.insert(newObjects, bloom)

		local depthOfField = Instance.new('DepthOfFieldEffect')
		depthOfField.Parent = lightingService
		depthOfField.Enabled = false
		depthOfField.FarIntensity = 0
		depthOfField.FocusDistance = 0
		depthOfField.InFocusRadius = 0
		depthOfField.NearIntensity = 0
		table.insert(newObjects, depthOfField)

		local atmosphere = Instance.new('Atmosphere')
		atmosphere.Parent = lightingService
		atmosphere.Density = 0.1
		atmosphere.Offset = 0
		atmosphere.Color = Color3.fromHSV(0.59375, 1, 1)
		atmosphere.Decay = Color3.fromHSV(0.44, 1, 1)
		atmosphere.Glare = 0.1
		atmosphere.Haze = 0
		table.insert(newObjects, atmosphere)
	end

	local function applyRealistic()
		lightingService.Ambient = Color3.fromRGB(55, 55, 55)
		lightingService.Brightness = 2.5
		lightingService.ColorShift_Bottom = Color3.fromRGB(150, 100, 170)
		lightingService.ColorShift_Top = Color3.fromRGB(140, 120, 210)
		lightingService.EnvironmentDiffuseScale = 0.9
		lightingService.EnvironmentSpecularScale = 0.9
		lightingService.GlobalShadows = true
		lightingService.OutdoorAmbient = Color3.fromRGB(55, 55, 55)
		lightingService.ShadowSoftness = 0.15
		lightingService.Technology = Enum.Technology.ShadowMap
		lightingService.ClockTime = 6.47
		lightingService.GeographicLatitude = -7

		timeConnection = lightingService:GetPropertyChangedSignal('ClockTime'):Connect(function()
			if Theme.Enabled and lightingService.ClockTime ~= 6.47 then
				lightingService.ClockTime = 6.47
			end
		end)

		local atmosphere = Instance.new('Atmosphere', lightingService)
		atmosphere.Density = 0.35
		atmosphere.Offset = 0.3
		atmosphere.Color = Color3.fromRGB(185, 185, 185)
		atmosphere.Decay = Color3.fromRGB(95, 102, 115)
		atmosphere.Glare = 0
		atmosphere.Haze = 0
		table.insert(newObjects, atmosphere)

		local sky = Instance.new('Sky', lightingService)
		sky.MoonAngularSize = 0
		sky.MoonTextureId = ''
		sky.SkyboxBk = 'rbxassetid://158422743'
		sky.SkyboxDn = 'rbxassetid://158422584'
		sky.SkyboxFt = 'rbxassetid://158423013'
		sky.SkyboxLf = 'rbxassetid://158423239'
		sky.SkyboxRt = 'rbxassetid://158422849'
		sky.SkyboxUp = 'rbxassetid://158422277'
		sky.StarCount = 2800
		sky.SunAngularSize = 2
		sky.SunTextureId = ''
		table.insert(newObjects, sky)

		local bloom = Instance.new('BloomEffect', lightingService)
		bloom.Enabled = true
		bloom.Intensity = 0.4
		bloom.Size = 22
		bloom.Threshold = 2.2
		table.insert(newObjects, bloom)

		local depthOfField = Instance.new('DepthOfFieldEffect', lightingService)
		depthOfField.Enabled = false
		table.insert(newObjects, depthOfField)

		if RemoveClouds and RemoveClouds.Enabled then
			removeWorkspaceClouds()
		end

		local terrain = workspace:FindFirstChildOfClass('Terrain')
		if terrain then
			for _, property in {'WaterColor', 'WaterReflectance', 'WaterTransparency', 'WaterWaveSize', 'WaterWaveSpeed'} do
				if terrainSettings[property] == nil then
					pcall(function()
						terrainSettings[property] = terrain[property]
					end)
				end
			end
			local existingCloud = terrain:FindFirstChild('MadeCloud')
			if existingCloud then
				existingCloud:Destroy()
			end

			currentCloud = Instance.new('Clouds', terrain)
			currentCloud.Name = 'MadeCloud'
			currentCloud.Enabled = true
			applyCloudSettings()
		end

		if game.PlaceId ~= 6872265039 then
			pcall(function()
				storeBlocks, cleanFunc = (function(tags)
					local objects = {}
					local tagList = typeof(tags) == 'string' and {tags} or tags

					for _, tag in tagList do
						for _, object in collectionService:GetTagged(tag) do
							table.insert(objects, object)
						end

						Theme:Clean(collectionService:GetInstanceAddedSignal(tag):Connect(function(object)
							if Theme.Enabled then
								table.insert(objects, object)
							end
						end))

						Theme:Clean(collectionService:GetInstanceRemovedSignal(tag):Connect(function(object)
							for index, stored in objects do
								if stored == object then
									table.remove(objects, index)
									break
								end
							end
						end))
					end

					return objects, function()
						table.clear(objects)
					end
				end)('block')

				local function getRoot()
					local activeEntity = getEntityLibrary()
					return activeEntity and activeEntity.isAlive and activeEntity.character
						and activeEntity.character.RootPart or nil
				end

				local function getMapBounds(worlds)
					local bounds = {
						minX = math.huge,
						maxX = -math.huge,
						minZ = math.huge,
						maxZ = -math.huge,
						lowestSurfaceY = math.huge,
						count = 0,
					}

					for _, block in storeBlocks do
						if block and block.Parent and block:IsA('BasePart')
							and block:IsDescendantOf(worlds) then
							local position = block.Position
							local halfSize = block.Size * 0.5
							local cframe = block.CFrame
							-- Account for rotated map pieces instead of assuming every
							-- tagged block is axis-aligned.
							local extentX = math.abs(cframe.RightVector.X) * halfSize.X
								+ math.abs(cframe.UpVector.X) * halfSize.Y
								+ math.abs(cframe.LookVector.X) * halfSize.Z
							local extentY = math.abs(cframe.RightVector.Y) * halfSize.X
								+ math.abs(cframe.UpVector.Y) * halfSize.Y
								+ math.abs(cframe.LookVector.Y) * halfSize.Z
							local extentZ = math.abs(cframe.RightVector.Z) * halfSize.X
								+ math.abs(cframe.UpVector.Z) * halfSize.Y
								+ math.abs(cframe.LookVector.Z) * halfSize.Z

							bounds.minX = math.min(bounds.minX, position.X - extentX)
							bounds.maxX = math.max(bounds.maxX, position.X + extentX)
							bounds.minZ = math.min(bounds.minZ, position.Z - extentZ)
							bounds.maxZ = math.max(bounds.maxZ, position.Z + extentZ)
							-- The lowest top surface is the first safe level below
							-- the loaded islands.  The match-state gate keeps lobby
							-- skybox pieces out of this scan.
							bounds.lowestSurfaceY = math.min(
								bounds.lowestSurfaceY,
								position.Y + extentY
							)
							bounds.count += 1
						end
					end

					if bounds.count == 0 or bounds.minX == math.huge then
						return nil
					end

					bounds.spanX = bounds.maxX - bounds.minX
					bounds.spanZ = bounds.maxZ - bounds.minZ
					bounds.centerX = (bounds.minX + bounds.maxX) * 0.5
					bounds.centerZ = (bounds.minZ + bounds.maxZ) * 0.5
					bounds.signature = string.format(
						'%d:%d:%d:%d:%d:%d',
						bounds.count,
						math.floor(bounds.minX),
						math.floor(bounds.maxX),
						math.floor(bounds.minZ),
						math.floor(bounds.maxZ),
						math.floor(bounds.lowestSurfaceY)
					)
					return bounds
				end

				local function sampleMapBounds(worlds)
					local now = tick()
					if waterBounds and waterBoundsSampledAt > 0
						and now - waterBoundsSampledAt < 0.5 then
						return waterBounds
					end
					waterBounds = getMapBounds(worlds)
					waterBoundsSampledAt = now
					return waterBounds
				end

				local function mapReady(root)
					-- BedWars creates the lobby avatar and skybox map before it
					-- transitions the store into a live match.  Waiting for the
					-- authoritative match state prevents water from being placed at
					-- the temporary spawn position.
					local runtimeStore = getRuntimeStore()
					if not runtimeStore or tonumber(runtimeStore.matchState) ~= 1 then
						if waterRegion then clearWaterRegion() end
						waterWorlds = nil
						waterTeam = nil
						waterBounds = nil
						waterBoundsSampledAt = 0
						waterBoundsSignature = nil
						mapReadySince = 0
						rootStableSince = 0
						return false
					end
					if not root or not root.Parent then
						mapReadySince = 0
						return false
					end

					local mapRoot = workspace:FindFirstChild('Map')
					local worlds = mapRoot and mapRoot:FindFirstChild('Worlds')
					local team = localPlayer:GetAttribute('Team')
					if not worlds or #worlds:GetChildren() == 0 or team == nil
						or team == 0 or team == '0' or team == '' then
						if waterRegion then clearWaterRegion() end
						waterWorlds = nil
						waterTeam = nil
						waterBounds = nil
						waterBoundsSampledAt = 0
						waterBoundsSignature = nil
						mapReadySince = 0
						rootStableSince = 0
						return false
					end

					-- A new Worlds model or team is a real map transition.  A
					-- respawn is deliberately not part of this check, so ordinary
					-- CharacterAdded events never clear/refill the water plane.
					if waterWorlds ~= worlds or waterTeam ~= team then
						if waterRegion then clearWaterRegion() end
						waterWorlds = worlds
						waterTeam = team
						waterBounds = nil
						waterBoundsSampledAt = 0
						waterBoundsSignature = nil
						mapReadySince = 0
						rootStableSince = tick()
					elseif waterRegion then
						-- The plane is intentionally immutable after the first
						-- successful fill.  Respawns and transient character/store
						-- changes must not recreate it, but match/map transitions
						-- above have already invalidated the old region.
						return true
					end

					if rootStableSince == 0 then rootStableSince = tick() end

					local bounds = sampleMapBounds(worlds)
					if not bounds or bounds.count < 8
						or math.max(bounds.spanX, bounds.spanZ) < 64 then
						mapReadySince = 0
						return false
					end

					local now = tick()
					if waterBoundsSignature ~= bounds.signature then
						waterBoundsSignature = bounds.signature
						mapReadySince = now
					elseif mapReadySince == 0 then
						mapReadySince = now
					end
					return now - mapReadySince >= 1 and now - rootStableSince >= 0.75
				end

				local function findSafeWaterY(root, bounds)
					if not root or not bounds then return end
					-- Keep the terrain voxel below the lowest live map surface and
					-- below the current root even if the map has uneven islands.
					return math.min(bounds.lowestSurfaceY - 4, root.Position.Y - 16)
				end

				local function fillSafeWater(bounds, waterY)
					local terrain = workspace:FindFirstChildOfClass('Terrain')
					if not terrain or not bounds or not waterY then return end
					local region = {
						CFrame = CFrame.new(bounds.centerX, waterY, bounds.centerZ),
						-- Keep the historical thin water sheet.  Terrain rounds this
						-- to its voxel grid; a four-stud volume wastes memory without
						-- changing the visible surface.
						Size = Vector3.new(waterPlaneSize, 0.01, waterPlaneSize),
						TopY = waterY,
						SizeStuds = waterPlaneSize,
						Worlds = waterWorlds,
						Team = waterTeam,
					}
					local ok = pcall(function()
						terrain:FillBlock(region.CFrame, region.Size, Enum.Material.Water)
						terrain.WaterColor = Color3.fromRGB(0, 50, 60)
						terrain.WaterReflectance = 0.7
						terrain.WaterTransparency = 0.25
						terrain.WaterWaveSize = 0.13
						terrain.WaterWaveSpeed = 8
					end)
					if ok then waterRegion = region end
				end

				cancelWaterTask()
				local generation = waterGeneration
				waterTask = task.spawn(function()
					while Theme.Enabled and generation == waterGeneration and not waterRegion do
						local root = getRoot()
						local ready = root and mapReady(root)
						if root and ready and not waterRegion then
							local waterY = findSafeWaterY(root, waterBounds)
							if waterY then fillSafeWater(waterBounds, waterY) end
						end
						if not waterRegion then task.wait(0.25) end
					end
					if generation == waterGeneration then waterTask = nil end
				end)

				local activeEntity = getEntityLibrary()
				local humanoid = activeEntity and activeEntity.character and activeEntity.character.Humanoid
				if humanoid then
					humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
				end

				characterConnection = localPlayer.CharacterAdded:Connect(function(character)
					if not Theme.Enabled then return end
					local humanoid = character:WaitForChild('Humanoid', 10)
					if humanoid then
						humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
					end
				end)
			end)
		end

		if applyCloudRemovalState then applyCloudRemovalState() end
	end

	Theme = vape.Categories.Render:CreateModule({
		Name = 'Theme',
		Function = function(callback)
			if callback then
				originalSettings = {
					Ambient = lightingService.Ambient,
					Brightness = lightingService.Brightness,
					ColorShift_Bottom = lightingService.ColorShift_Bottom,
					ColorShift_Top = lightingService.ColorShift_Top,
					EnvironmentDiffuseScale = lightingService.EnvironmentDiffuseScale,
					EnvironmentSpecularScale = lightingService.EnvironmentSpecularScale,
					GlobalShadows = lightingService.GlobalShadows,
					OutdoorAmbient = lightingService.OutdoorAmbient,
					ShadowSoftness = lightingService.ShadowSoftness,
					Technology = lightingService.Technology,
					ClockTime = lightingService.ClockTime,
					GeographicLatitude = lightingService.GeographicLatitude,
				}

				for _, object in lightingService:GetChildren() do
					removeOldLightingObject(object)
				end

				if Mode.Value == 'Blavish' then
					applyBlavish()
				else
					applyRealistic()
				end
			else
				cleanup()
			end
		end,
		Tooltip = 'Applies BadVape atmospheric effects to the world',
	})

	Mode = Theme:CreateDropdown({
		Name = 'Mode',
		List = {'Realistic', 'Blavish'},
		Function = function()
			if Theme.Enabled then
				Theme:Toggle()
				Theme:Toggle()
			end
		end,
	})

	RemoveClouds = Theme:CreateToggle({
		Name = 'Remove Clouds',
		Function = function()
			if applyCloudRemovalState then applyCloudRemovalState() end
		end,
		Default = true,
	})

	CloudSize = Theme:CreateSlider({
		Name = 'Cloud size',
		Min = 0,
		Max = 1,
		Decimal = 100,
		Default = 0.8,
		Suffix = '',
		Function = applyCloudSettings,
	})

	CloudTransparency = Theme:CreateSlider({
		Name = 'Cloud transparency',
		Min = 0,
		Max = 1,
		Decimal = 100,
		Default = 0.1,
		Suffix = '',
		Function = applyCloudSettings,
	})

	vape.Libraries.badvapeTheme = Theme

	return Theme
end
