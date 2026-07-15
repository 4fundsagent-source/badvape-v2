local forwardedLicense = ...
local function resolveRuntimeEnvironment()
	if type(getgenv) == 'function' then
		local ok, environment = pcall(getgenv)
		if ok and type(environment) == 'table' then
			return environment
		end
	end
	if type(getfenv) == 'function' then
		local ok, environment = pcall(getfenv, 0)
		if ok and type(environment) == 'table' then
			return environment
		end
	end
	if type(_G) == 'table' then
		return _G
	end
	return {}
end
local runtimeEnvironment = resolveRuntimeEnvironment()
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
local function addTeleportQueueCandidate(list, seen, candidate)
	if type(candidate) == 'function' and not seen[candidate] then
		seen[candidate] = true
		table.insert(list, candidate)
	end
end
local function teleportQueueCandidates()
	local list, seen = {}, {}
	local environmentSyn = type(runtimeEnvironment.syn) == 'table' and runtimeEnvironment.syn or nil
	local environmentFluxus = type(runtimeEnvironment.fluxus) == 'table' and runtimeEnvironment.fluxus or nil
	addTeleportQueueCandidate(list, seen, runtimeEnvironment.queue_on_teleport)
	addTeleportQueueCandidate(list, seen, runtimeEnvironment.queueonteleport)
	addTeleportQueueCandidate(list, seen, environmentSyn and environmentSyn.queue_on_teleport)
	addTeleportQueueCandidate(list, seen, environmentSyn and environmentSyn.queueonteleport)
	addTeleportQueueCandidate(list, seen, environmentFluxus and environmentFluxus.queue_on_teleport)
	addTeleportQueueCandidate(list, seen, environmentFluxus and environmentFluxus.queueonteleport)
	addTeleportQueueCandidate(list, seen, queue_on_teleport)
	addTeleportQueueCandidate(list, seen, queueonteleport)
	addTeleportQueueCandidate(list, seen, type(syn) == 'table' and syn.queue_on_teleport)
	addTeleportQueueCandidate(list, seen, type(syn) == 'table' and syn.queueonteleport)
	addTeleportQueueCandidate(list, seen, type(fluxus) == 'table' and fluxus.queue_on_teleport)
	addTeleportQueueCandidate(list, seen, type(fluxus) == 'table' and fluxus.queueonteleport)
	return list
end
local teleportQueueParts = {}
local teleportQueueFlushed = false
shared.BadVapeTeleportQueueParts = teleportQueueParts
local function flushTeleportQueue()
	if teleportQueueFlushed then return true end
	local names = {}
	for name in teleportQueueParts do table.insert(names, name) end
	table.sort(names)
	local scripts = {}
	for _, name in names do table.insert(scripts, teleportQueueParts[name]) end
	if #scripts == 0 then return false end
	local source = table.concat(scripts, '\n')
	for _, queueTeleport in teleportQueueCandidates() do
		local ok, result = pcall(queueTeleport, source)
		if ok and result ~= false then
			teleportQueueFlushed = true
			return true
		end
	end
	return false
end
shared.BadVapeQueueTeleport = function(name, source)
	if type(name) ~= 'string' or name == '' or type(source) ~= 'string' or source == '' then return false end
	if teleportQueueFlushed then return false end
	teleportQueueParts[name] = source
	return true
end
shared.BadVapeFlushTeleportQueue = flushTeleportQueue
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

local function readCachedFile(path)
	local ok, value = pcall(readfile, path)
	return ok and type(value) == 'string' and value ~= '' and value or nil
end

local function installedReleaseRef()
	local value = readCachedFile('badvape/cache/public-release-ref.txt')
	return value and #value == 40 and value:match('^[0-9a-f]+$') and value or 'main'
end

local function downloadFile(path, func)
	local contents = readCachedFile(path)
	if not contents then
		if shared.VapeDeveloper then
			error('Missing local BadVape file: '..path)
		end

		local relative = path:gsub('^badvape/', '', 1)
		local releaseRef = installedReleaseRef()
		local urls = {
			'https://raw.githubusercontent.com/4fundsagent-source/badvape-v2/'..releaseRef..'/'..relative,
			'https://cdn.jsdelivr.net/gh/4fundsagent-source/badvape-v2@'..releaseRef..'/'..relative,
		}
		local lastError = 'download failed'
		for _, url in urls do
			local ok, response = pcall(function()
				return game:HttpGet(url)
			end)
			if ok and type(response) == 'string' and response ~= '' and response ~= '404: Not Found' then
				local wrote, writeError = pcall(writefile, path, response)
				if not wrote then
					error(tostring(writeError), 0)
				end
				contents = response
				break
			end
			lastError = response
		end
		if not contents then
			error(tostring(lastError), 0)
		end
	end
	return func and func(path) or contents
end

local ownedDownloadFile
ownedDownloadFile = function(path)
	if type(path) ~= 'string'
		or not path:match('^badvape/[%w%._/%-]+$')
		or path:find('..', 1, true) then
		return nil
	end
	local ok, result = pcall(downloadFile, path)
	return ok and result or nil
end
shared.BadVapeDownloadFile = ownedDownloadFile

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

	if not shared.VapeIndependent then
		local teleportUid = tostring(license.Key or ''):lower()
		local function currentExecutorName()
			local environment = type(runtimeEnvironment) == 'table' and runtimeEnvironment or {}
			local identifiers, seen = {}, {}
			local function addIdentifier(candidate)
				if type(candidate) == 'function' and not seen[candidate] then
					seen[candidate] = true
					table.insert(identifiers, candidate)
				end
			end
			addIdentifier(environment.identifyexecutor)
			addIdentifier(environment.getexecutorname)
			addIdentifier(identifyexecutor)
			addIdentifier(getexecutorname)
			for _, identify in identifiers do
				local success, name = pcall(identify)
				if success and type(name) == 'string' and name ~= '' then
					return name
				end
			end
			return ''
		end
		if #teleportUid >= 1 and #teleportUid <= 24 and teleportUid:match('^%l[%w_]*$') then
			local encodedUid = httpService:JSONEncode(teleportUid)
			local encodedFolder = httpService:JSONEncode(runtimeFolder)
			local teleportScript
			if shared.VapeDeveloper then
				teleportScript = 'shared.vapereload = true\n'
					..'shared.VapeDeveloper = true\n'
					..'shared.BadVapeFolder = '..encodedFolder..'\n'
					..'local badVapeLoader, badVapeLoadError = loadstring(readfile(shared.BadVapeFolder.."/loader.lua"), "@badvape/loader.lua")\n'
					..'if type(badVapeLoader) ~= "function" then error(badVapeLoadError or "BadVape local loader rejected", 0) end\n'
					..'return badVapeLoader({Key = '..encodedUid..'})'
			else
				local loaderUrl = httpService:JSONEncode('https://luvit.cc/badvape-api/loader')
				teleportScript = 'shared.vapereload = true\n'
					..'shared.BadVapeFolder = '..encodedFolder..'\n'
					..'loadstring(game:HttpGet('..loaderUrl..'))() { log { '..encodedUid..' } }'
			end
			if shared.VapeCustomProfile then
				teleportScript = 'shared.VapeCustomProfile = '
					..httpService:JSONEncode(tostring(shared.VapeCustomProfile))..'\n'..teleportScript
			end
			if currentExecutorName():lower():find('potassium', 1, true) then
				teleportScript = 'task.wait(12)\n'..teleportScript
			end
			shared.BadVapeQueueTeleport('99-loader', teleportScript)
			local queueAttempted = false
			vape:Clean(playersService.LocalPlayer.OnTeleport:Connect(function()
				if queueAttempted then return end
				queueAttempted = true
				task.defer(function()
					if not shared.BadVapeFlushTeleportQueue() then
						queueAttempted = false
						vape:CreateNotification('BadVape', 'Your executor could not queue the teleport reload.', 8, 'warning')
					end
				end)
			end))
			if #teleportQueueCandidates() == 0 then
				vape:CreateNotification('BadVape', 'This executor does not support queue on teleport.', 8, 'warning')
			end
		elseif license.Key then
			vape:CreateNotification('BadVape', 'Automatic teleport reload needs your UID. Run /setuid, then use /getscript.', 10, 'warning')
		end
	end

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

runtimeEnvironment.used_init = true
vape = loadstring(downloadFile('badvape/guis/'..gui..'.lua'), 'gui')(license)
vape.Place = game.PlaceId
_G.vape = vape
shared.vape = vape
local previousUninject = vape.Uninject
if type(previousUninject) == 'function' then
	vape.Uninject = function(self, ...)
		if shared.BadVapeDownloadFile == ownedDownloadFile then
			shared.BadVapeDownloadFile = nil
		end
		return previousUninject(self, ...)
	end
end
loadMaxPrediction()
loadBadVapeTheme()

if shared.maincat then
	redirect()
	playersService.LocalPlayer:Kick('Your local BadVape build is outdated.')
	return
end

local function loadGameModule(placeId)
	vape.Place = placeId
	local gamePath = 'badvape/games/'..placeId..'.lua'
	local gameSource = readCachedFile(gamePath)
		or shared.BadVapeDownloadFile(gamePath)
	if type(gameSource) ~= 'string' or gameSource == '404: Not Found' then
		return false
	end

	local gameChunk = loadstring(gameSource, tostring(placeId))
	if type(gameChunk) ~= 'function' then
		return false
	end
	local ok, loaded = pcall(gameChunk, license)
	if not ok or loaded == false then
		vape:CreateNotification('BadVape', 'Game module unavailable; loaded base modules only.', 8, 'warning')
		return false
	end
	return true
end

if not shared.VapeIndependent then
	loadstring(downloadFile('badvape/games/universal.lua'), 'universal')(license)
	loadGameModule(game.PlaceId)
	loadBadVapeTheme()
	finishLoading()
else
	loadBadVapeTheme()
	vape.Init = finishLoading
	return vape
end
