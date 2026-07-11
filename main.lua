local forwardedLicense = ...
local license = {}
if type(forwardedLicense) == 'table' then
	for key, value in forwardedLicense do
		license[key] = value
	end
end
license.Key = type(license.Key) == 'string' and license.Key or nil
repeat task.wait() until game:IsLoaded()
if shared.vape then shared.vape:Uninject() end

local vape
local loadstring = function(...)
	local res, err = loadstring(...)
	if err and vape then
		vape:CreateNotification('BadVape', 'Failed to load : '..err, 30, 'alert')
	end
	return res
end
local queue_on_teleport = queue_on_teleport or function() end
local isfile = isfile or function(file)
	local suc, res = pcall(function()
		return readfile(file)
	end)
	return suc and res ~= nil and res ~= ''
end
local cloneref = cloneref or function(obj)
	return obj
end
local playersService = cloneref(game:GetService('Players'))
local httpService = cloneref(game:GetService('HttpService'))
local runtimeFolder = shared.BadVapeFolder or 'badvape'

local redirect = function() end

local function downloadFile(path, func)
	if not isfile(path) then
		if shared.VapeDeveloper then
			error('Missing local BadVape file: '..path)
		end

		local suc, res = pcall(function()
			return game:HttpGet('https://raw.githubusercontent.com/4fundsagent-source/badvape-v2/'..readfile('badvape/profiles/commit.txt')..'/'..select(1, path:gsub('badvape/', '')), true)
		end)
		if not suc or res == '404: Not Found' then
			error(tostring(res), 0)
		end
		if suc then
			if path:find('.lua') then
				res = '--This watermark is used to delete the file if its cached, remove it to make the file persist after vape updates.\n'..res
			end
			writefile(path, res)
		end
	end
	return (func or readfile)(path)
end

local function loadBadVapeTheme()
	if not vape or not vape.Categories or not vape.Categories.Render then
		return
	end

	if vape.Modules and vape.Modules.Theme then
		return
	end

	local suc, res = pcall(function()
		local themeChunk = loadstring(downloadFile('badvape/libraries/badvape-theme.lua'), 'badvape-theme')
		if not themeChunk then
			return
		end

		local themeLoader = themeChunk()
		if type(themeLoader) == 'function' then
			return themeLoader(vape, vape.Libraries and vape.Libraries.entity)
		end
	end)

	if not suc then
		vape:CreateNotification('BadVape', 'Theme failed to load : '..tostring(res), 10, 'alert')
	end
end

local function loadMaxPrediction()
	if not vape then
		return
	end

	vape.Libraries = vape.Libraries or {}
	shared.BadVapePredictionMode = 'max-devirtualized'
	vape.Libraries.calculatePosition = function(selfPosition, rootPart)
		return CFrame.lookAt(rootPart.Position, selfPosition).LookVector * math.max((selfPosition - rootPart.Position).Magnitude / 10, 0)
	end
end

local function finishLoading()
	vape.Init = nil
	vape:Load()
	task.spawn(function()
		repeat
			vape:Save()
			task.wait(10)
		until not vape.Loaded
	end)

	local teleportedServers
	vape:Clean(playersService.LocalPlayer.OnTeleport:Connect(function(state)
		if (not teleportedServers) and (not shared.VapeIndependent) then
			local teleportUid = tostring(license.Key or ''):lower()
			if #teleportUid >= 3 and #teleportUid <= 24 and teleportUid:match('^%l[%w_]+$') then
				teleportedServers = true
				local loaderUrl = httpService:JSONEncode('https://luvit.cc/badvape-api/loader')
				local encodedUid = httpService:JSONEncode(teleportUid)
				local teleportScript = 'shared.vapereload = true\n'
					..'shared.BadVapeFolder = '..httpService:JSONEncode(runtimeFolder)..'\n'
					..'loadstring(game:HttpGet('..loaderUrl..'))() { log { '..encodedUid..' } }'
				if shared.VapeDeveloper then
					teleportScript = 'shared.VapeDeveloper = true\n'..teleportScript
				end
				if shared.VapeCustomProfile then
					teleportScript = 'shared.VapeCustomProfile = '
						..httpService:JSONEncode(tostring(shared.VapeCustomProfile))..'\n'..teleportScript
				end
				queue_on_teleport(teleportScript)
			end
		end
	end))

	if not shared.vapereload then
		if not vape.Categories then return end
		if vape.Categories.Main.Options['GUI bind indicator'].Enabled then
			if vape.Place ~= 6872274481 then
				--task.spawn(redirect)
			end
			vape:CreateNotification('Finished Loading', (vape.VapeButton and 'Press the button in the top right' or 'Press '..table.concat(vape.Keybind, ' + '):upper())..' to open GUI', 5)
			task.delay(1, function()
				if shared.updated then
					vape:CreateNotification('BadVape', `Script has updated from {shared.updated} to {readfile('badvape/profiles/commit.txt')}`, 10, 'info')
				end
			end)
		end
	end
end

if not isfile('badvape/profiles/gui.txt') then
	writefile('badvape/profiles/gui.txt', 'new')
end
local gui = readfile('badvape/profiles/gui.txt')
if gui == 'rise' then
	gui = 'new'
	writefile('badvape/profiles/gui.txt', gui)
end

if not isfolder('badvape/assets/'..gui) then
	makefolder('badvape/assets/'..gui)
end
if not isfile('badvape/profiles/commit.txt') then
	writefile('badvape/profiles/commit.txt', 'main')
end

getgenv().used_init = true
vape = loadstring(downloadFile('badvape/guis/'..gui..'.lua'), 'gui')(license)
_G.vape = vape
shared.vape = vape
loadMaxPrediction()
loadBadVapeTheme()

if shared.maincat then
	redirect()
	playersService.LocalPlayer:Kick('Your local BadVape build is outdated.')
	return
end

if not shared.VapeIndependent then
	loadstring(downloadFile('badvape/games/universal.lua'), 'universal')(license)
	local function routesToProtectedBedwars(placeId)
		if placeId == 131823264266369 or placeId == 6872274481 then
			return true
		end

		local routePath = 'badvape/games/'..placeId..'.lua'
		if not isfile(routePath) then
			return false
		end

		local success, source = pcall(readfile, routePath)
		return success and type(source) == 'string' and (
			source:match('vape%.Place%s*=%s*6872274481') ~= nil
			or source:find('protected6872274481.lua', 1, true) ~= nil
		)
	end

	local gamePath = 'badvape/games/'..game.PlaceId..'.lua'
	local protectedGamePath
	if routesToProtectedBedwars(game.PlaceId) then
		vape.Place = 6872274481
		gamePath = 'badvape/games/protected6872274481.lua'
		protectedGamePath = gamePath
	end
	if protectedGamePath and not isfile(gamePath) and not shared.VapeDeveloper then
		pcall(downloadFile, gamePath)
	end
	if isfile(gamePath) then
		local gameChunk = loadstring(readfile(gamePath), tostring(game.PlaceId))
		if protectedGamePath then
			local gameOk, gameLoaded = false, false
			if gameChunk then
				gameOk, gameLoaded = pcall(gameChunk, license)
			end
			if not gameOk or gameLoaded ~= true then
				vape:CreateNotification('BadVape', 'Protected game module unavailable; loaded base modules only.', 8, 'warning')
			end
		elseif gameChunk then
			gameChunk(license)
		end
	else
		if protectedGamePath then
			vape:CreateNotification('BadVape', 'Protected game module missing; loaded base modules only.', 8, 'warning')
		end
		if not protectedGamePath and not shared.VapeDeveloper then
			local suc, res = pcall(function()
				return game:HttpGet('https://raw.githubusercontent.com/4fundsagent-source/badvape-v2/'..readfile('badvape/profiles/commit.txt')..'/games/'..game.PlaceId..'.lua', true)
			end)
			if suc and res ~= '404: Not Found' then
				loadstring(downloadFile('badvape/games/'..game.PlaceId..'.lua'), tostring(game.PlaceId))(license)
			end
		end
	end
	loadBadVapeTheme()
	finishLoading()
else
	loadBadVapeTheme()
	vape.Init = finishLoading
	return vape
end
