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

	local function getEntityLibrary()
		return entitylib or vape.Libraries and vape.Libraries.entity
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

		local terrain = workspace:FindFirstChildOfClass('Terrain')
		if terrain then
			terrain:Clear()
		end

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

				local activeEntity = getEntityLibrary()
				if activeEntity and activeEntity.isAlive and activeEntity.character and activeEntity.character.RootPart then
					local root = activeEntity.character.RootPart
					local terrain = workspace:FindFirstChildOfClass('Terrain')
					local waterPosition = 0

					if terrain then
						local attempts = 0
						while #storeBlocks == 0 and attempts < 50 do
							task.wait(0.1)
							attempts += 1
						end

						if #storeBlocks > 0 then
							local lowestPosition = math.huge
							for _, block in storeBlocks do
								if block and block.Position then
									local ray = workspace:Raycast(block.Position + Vector3.new(0, 800, 0), Vector3.new(0, -1000, 0))
									if ray and ray.Position.Y <= lowestPosition then
										lowestPosition = ray.Position.Y
									end
								end
							end

							if lowestPosition < math.huge then
								waterPosition = lowestPosition
							end
						end

						terrain:FillBlock(
							CFrame.new(root.Position.X, waterPosition, root.Position.Z),
							Vector3.new(5000, 0.01, 5000),
							Enum.Material.Water
						)

						terrain.WaterColor = Color3.fromRGB(0, 50, 60)
						terrain.WaterReflectance = 0.7
						terrain.WaterTransparency = 0.25
						terrain.WaterWaveSize = 0.13
						terrain.WaterWaveSpeed = 8
					end

					local humanoid = activeEntity.character.Humanoid
					if humanoid then
						humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
					end

					characterConnection = localPlayer.CharacterAdded:Connect(function(character)
						if not Theme.Enabled then
							return
						end

						local humanoid = character:WaitForChild('Humanoid')
						if humanoid then
							humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
						end
					end)
				end
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
