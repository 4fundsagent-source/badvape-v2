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
local queueTeleport = queue_on_teleport
    or queueonteleport
    or (type(syn) == 'table' and syn.queue_on_teleport)
    or (type(fluxus) == 'table' and fluxus.queue_on_teleport)
    or (type(getgenv) == 'function' and getgenv().queue_on_teleport)
local teleportQueueParts = shared.BadVapeTeleportQueueParts or {}
shared.BadVapeTeleportQueueParts = teleportQueueParts
local function refreshTeleportQueue()
    if type(queueTeleport) ~= 'function' then return false end
    local names = {}
    for name in teleportQueueParts do table.insert(names, name) end
    table.sort(names)
    local scripts = {}
    for _, name in names do table.insert(scripts, teleportQueueParts[name]) end
    return pcall(queueTeleport, table.concat(scripts, '\n'))
end
shared.BadVapeQueueTeleport = function(name, source)
    if type(name) ~= 'string' or type(source) ~= 'string' then return false end
    teleportQueueParts[name] = source
    return refreshTeleportQueue()
end
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
		if #teleportUid >= 3 and #teleportUid <= 24 and teleportUid:match('^%l[%w_]+$') then
				local loaderUrl = httpService:JSONEncode('https://luvit.cc/badvape-api/loader')
				local encodedUid = httpService:JSONEncode(teleportUid)
				local teleportScript = 'shared.vapereload = true\n'
					..'shared.BadVapeFolder = '..httpService:JSONEncode(runtimeFolder)..'\n'
					..'loadstring(game:HttpGet('..loaderUrl..'))() { log { '..encodedUid..' } }'
				if shared.VapeCustomProfile then
					teleportScript = 'shared.VapeCustomProfile = '
						..httpService:JSONEncode(tostring(shared.VapeCustomProfile))..'\n'..teleportScript
				end
			shared.BadVapeQueueTeleport('00-loader', teleportScript)
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

getgenv().used_init = true
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
