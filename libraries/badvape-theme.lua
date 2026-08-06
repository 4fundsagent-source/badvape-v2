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
	local newObjects = {}
	local oldObjects = {}
	local storeBlocks = {}
	local originalSettings = {}
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
	local waterCharacter
	-- Keep the client-side terrain operation bounded.  A 5000x5000 plane
	-- allocates several times more voxels than a BedWars map needs and was
	-- especially costly when the old movement invalidation refilled it.
	local waterPlaneSize = 2048

	local function getEntityLibrary()
		return entitylib or vape.Libraries and vape.Libraries.entity
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
		waterCharacter = nil
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
					object.Transparency = 1
				end
			end
		end

		for _, object in workspace:GetDescendants() do
			if object:IsA('Clouds') then
				object:Destroy()
			end
		end
	end

	local function hideWorkspaceCloudParts()
		if workspace:FindFirstChild('Clouds') then
			for _, object in workspace.Clouds:GetChildren() do
				if object:IsA('Part') then
					object.Transparency = 1
				end
			end
		end
	end

	local function applyBlavish()
		removeWorkspaceClouds()
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

		removeWorkspaceClouds()

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
			currentCloud.Density = 0.9
			currentCloud.Cover = 0.8
			currentCloud.Color = Color3.new(1.1, 1.1, 1.1)

			task.spawn(function()
				local weatherStates = {
					{Density = 0.6, Cover = 0.8},
					{Density = 0.7, Cover = 0.9},
					{Density = 0.6, Cover = 1},
				}

				while Theme.Enabled and currentCloud do
					task.wait(math.random(15, 20))
					if not Theme.Enabled or not currentCloud then
						break
					end

					tweenService:Create(currentCloud, TweenInfo.new(10), weatherStates[math.random(1, #weatherStates)]):Play()
				end
			end)
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

				local function mapReady(root)
					-- Do not sample the lobby/skybox. BedWars can publish a Map object
					-- before the player is teleported into the live Worlds model, so
					-- require a non-zero team and nearby replicated map geometry for a
					-- short stable window before creating any terrain water.  Do not use
					-- player movement as an invalidation signal: the old implementation
					-- cleared and refilled a 5000x5000 terrain region every ~24 studs.
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
						waterCharacter = nil
						mapReadySince = 0
						rootStableSince = 0
						return false
					end

					-- A new Worlds model, team, or character represents a real map
					-- transition.  Only those transitions are allowed to invalidate the
					-- water plane; walking, jumping, and ordinary knockback are not.
					local character = root.Parent
					if waterWorlds ~= worlds or waterTeam ~= team or waterCharacter ~= character then
						if waterRegion then
							clearWaterRegion()
						end
						waterWorlds = worlds
						waterTeam = team
						waterCharacter = character
						mapReadySince = 0
						rootStableSince = tick()
					end

					-- Once the first plane is installed, the map has already been
					-- validated.  Avoid rescanning every tagged block on a timer.
					if waterRegion then
						return true
					end
					if rootStableSince == 0 then rootStableSince = tick() end
					local nearby = false
					for _, block in storeBlocks do
						if block and block.Parent and block:IsA('BasePart')
							and block:IsDescendantOf(worlds)
							and (Vector3.new(block.Position.X, 0, block.Position.Z)
								- Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude <= 350
							and math.abs(block.Position.Y - root.Position.Y) <= 300 then
							nearby = true
							break
						end
					end
					if not nearby then
						mapReadySince = 0
						return false
					end
					if mapReadySince == 0 then mapReadySince = tick() end
					return tick() - mapReadySince >= 1 and tick() - rootStableSince >= 0.75
				end

				local function findSafeWaterY(root, ready)
					if not root or (not ready and not mapReady(root)) then return end
					local rootPosition = root.Position
					local mapRoot = workspace:FindFirstChild('Map')
					local worlds = mapRoot and mapRoot:FindFirstChild('Worlds')
					local lowest = math.huge
					for _, block in storeBlocks do
						if block and block.Parent and block:IsA('BasePart')
							and worlds and block:IsDescendantOf(worlds) then
							local position = block.Position
							-- Ignore geometry far from the live character and never accept
							-- a surface above the current character.
							if math.abs(position.X - rootPosition.X) > 350
								or math.abs(position.Z - rootPosition.Z) > 350 then
								continue
							end
							-- Ignore lobby/skybox geometry and never accept a surface
							-- which is at or above the current character.
							if position.Y < rootPosition.Y - 4 then
								lowest = math.min(lowest, position.Y)
							end
						end
					end
					if lowest == math.huge then return end
					-- Keep a generous vertical gap below the player even if a stale
					-- lobby block was present during the initial load.  Terrain voxels
					-- are four studs tall, so the top of the fill is kept at least 16
					-- studs below the current root.
					local safeY = math.min(lowest - 4, rootPosition.Y - 16)
					return safeY <= rootPosition.Y - 16 and safeY or nil
				end

				local function fillSafeWater(root, waterY)
					local terrain = workspace:FindFirstChildOfClass('Terrain')
					if not terrain or not root or not waterY then return end
					if waterY >= root.Position.Y - 16 then return end
					local region = {
						CFrame = CFrame.new(root.Position.X, waterY - 2, root.Position.Z),
						Size = Vector3.new(waterPlaneSize, 4, waterPlaneSize),
						TopY = waterY,
						Worlds = waterWorlds,
						Team = waterTeam,
						Character = waterCharacter,
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
					while Theme.Enabled and generation == waterGeneration do
						local root = getRoot()
						local ready = root and mapReady(root)
						-- The water plane is a visual backdrop, not a player-following
						-- object.  Never clear/refill it because the player walked outside
						-- its bounds: doing so turns ordinary movement into a large terrain
						-- allocation and was the source of the Realistic-mode hitch/crash.
						if root and ready and not waterRegion then
							local waterY = findSafeWaterY(root, true)
							if waterY then fillSafeWater(root, waterY) end
						end
						task.wait(waterRegion and 2 or 0.25)
					end
				end)

				local activeEntity = getEntityLibrary()
				local humanoid = activeEntity and activeEntity.character and activeEntity.character.Humanoid
				if humanoid then
					humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
				end

				characterConnection = localPlayer.CharacterAdded:Connect(function(character)
					if not Theme.Enabled then return end
					mapReadySince = 0
					rootStableSince = 0
					-- Leave the existing plane in place during a respawn.  The next
					-- valid root is tracked as a character transition by mapReady and
					-- clears it once, instead of doing duplicate 5000x5000 fills here.
					waterCharacter = nil
					local humanoid = character:WaitForChild('Humanoid', 10)
					if humanoid then
						humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
					end
					-- The first character is often the lobby avatar.  The monitor above
					-- recalculates after the server teleports the new avatar to its base.
				end)
			end)
		end

		if RemoveClouds.Enabled then
			hideWorkspaceCloudParts()
		end
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
			if Theme.Enabled then
				Theme:Toggle()
				Theme:Toggle()
			end
		end,
		Default = true,
	})

	vape.Libraries.badvapeTheme = Theme

	return Theme
end
