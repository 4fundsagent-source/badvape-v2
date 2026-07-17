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
local restoreRuntimeEnvironment = type(shared.BadVapeRestoreRuntimeEnvironment) == 'function'
	and shared.BadVapeRestoreRuntimeEnvironment or function() end
local license = {}
if type(forwardedLicense) == 'table' then
	for key, value in forwardedLicense do
		license[key] = value
	end
end
license.Key = type(license.Key) == 'string' and license.Key or nil
local diagnostics = type(shared.BadVapeDiagnostics) == 'table' and shared.BadVapeDiagnostics or nil
local diagnosticsPath = diagnostics and diagnostics.path
	or (shared.BadVapeFolder or 'badvape')..'/badvape-debug.txt'
local function recordDiagnostic(event, fields)
	if diagnostics and type(diagnostics.record) == 'function' then
		pcall(diagnostics.record, event, fields)
	end
end
recordDiagnostic('main_start', {
	credentialKind = license.Key and (license.Key:match('^BV%-%u%-') and 'license' or 'uid') or 'missing',
	placeId = game.PlaceId,
})
repeat task.wait() until game:IsLoaded()
local staleVape = shared.BadVape
if type(staleVape) == 'table' and type(staleVape.Uninject) == 'function' then
	pcall(staleVape.Uninject, staleVape)
end
if shared.BadVape == staleVape then
	shared.BadVape = nil
end

local vape
local nativeLoadstring = loadstring
local loadstring = function(source, chunkName)
	local res, err = nativeLoadstring(source, chunkName)
	if err and vape then
		vape:CreateNotification('BadVape', 'Failed to compile '..tostring(chunkName)..' : '..tostring(err), 30, 'alert')
	end
	return res, err
end
local function runSource(source, chunkName, ...)
	if type(source) ~= 'string' or source == '' then
		local detail = tostring(chunkName)..' source unavailable'
		recordDiagnostic('source_unavailable', {chunk = chunkName})
		return false, detail
	end
	recordDiagnostic('source_compile_start', {bytes = #source, chunk = chunkName})
	local chunk, compileError = loadstring(source, chunkName)
	if type(chunk) ~= 'function' then
		local detail = tostring(chunkName)..' compile failed: '..tostring(compileError or 'rejected')
		recordDiagnostic('source_compile_failed', {chunk = chunkName, error = compileError or 'rejected'})
		return false, detail
	end
	local arguments = table.pack(...)
	local function traceError(value)
		if type(debug) == 'table' and type(debug.traceback) == 'function' then
			local traceOk, trace = pcall(debug.traceback, tostring(value), 2)
			if traceOk and type(trace) == 'string' then return trace end
		end
		return tostring(value)
	end
	local result = table.pack(xpcall(function()
		return chunk(table.unpack(arguments, 1, arguments.n))
	end, traceError))
	if not result[1] then
		local detail = tostring(chunkName)..' runtime failed: '..tostring(result[2])
		recordDiagnostic('source_runtime_failed', {chunk = chunkName, error = result[2]})
		return false, detail
	end
	local protectedFailure = type(shared.BadVapeProtectedFailure) == 'table'
		and shared.BadVapeProtectedFailure or nil
	recordDiagnostic('source_execution_complete', {
		chunk = chunkName,
		protectedCorrelation = protectedFailure and protectedFailure.correlationId or 'none',
		protectedDetail = protectedFailure and protectedFailure.detail or 'none',
		protectedStage = protectedFailure and protectedFailure.stage or 'none',
		resultFalse = result[2] == false,
		resultType = typeof(result[2]),
	})
	return true, result[2]
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
	local value = readCachedFile(runtimeFolder..'/cache/public-release-ref.txt')
	return value and #value == 40 and value:match('^[0-9a-f]+$') and value or 'main'
end

local function downloadFile(path, func)
	local contents = readCachedFile(path)
	if contents then
		recordDiagnostic('runtime_file_cache_hit', {bytes = #contents, path = path})
	end
	if not contents then
		recordDiagnostic('runtime_file_cache_miss', {path = path})
		if shared.BadVapeDeveloper then
			recordDiagnostic('runtime_file_missing_local', {path = path})
			error('Missing local BadVape file: '..path)
		end

		local relative = path:gsub('^badvape/', '', 1)
		local releaseRef = installedReleaseRef()
		local urls = {
			'https://raw.githubusercontent.com/4fundsagent-source/badvape-v2/'..releaseRef..'/'..relative,
			'https://cdn.jsdelivr.net/gh/4fundsagent-source/badvape-v2@'..releaseRef..'/'..relative,
		}
		local lastError = 'download failed'
		for mirror, url in urls do
			local ok, response = pcall(function()
				return game:HttpGet(url)
			end)
			if ok and type(response) == 'string' and response ~= '' and response ~= '404: Not Found' then
				local wrote, writeError = pcall(writefile, path, response)
				if not wrote then
					recordDiagnostic('runtime_file_write_failed', {error = writeError, path = path})
					error(tostring(writeError), 0)
				end
				contents = response
				recordDiagnostic('runtime_file_downloaded', {
					bytes = #response,
					mirror = mirror,
					path = path,
					releaseRef = releaseRef,
				})
				break
			end
			lastError = response
			recordDiagnostic('runtime_file_download_failed', {
				error = response,
				mirror = mirror,
				path = path,
				releaseRef = releaseRef,
			})
		end
		if not contents then
			recordDiagnostic('runtime_file_unavailable', {error = lastError, path = path, releaseRef = releaseRef})
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
		recordDiagnostic('runtime_file_path_rejected', {path = path})
		return nil
	end
	local ok, result = pcall(downloadFile, path)
	if not ok then
		recordDiagnostic('runtime_file_request_failed', {error = result, path = path})
	end
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
		local targetPosition = rootPart and rootPart.Position
		if typeof(selfPosition) ~= 'Vector3' or typeof(targetPosition) ~= 'Vector3' then
			return Vector3.zero
		end
		return CFrame.lookAt(targetPosition, selfPosition).LookVector * math.max((selfPosition - targetPosition).Magnitude / 10, 0)
	end
end

local function finishLoading()
	vape.Init = nil
	local loaded, loadError = pcall(vape.Load, vape)
	if not loaded then
		error('BadVape GUI load failed: '..tostring(loadError), 0)
	end
	task.spawn(function()
		repeat
			pcall(vape.Save, vape)
			task.wait(10)
		until not vape.Loaded
	end)

	if not shared.BadVapeIndependent then
		local teleportUid = tostring(license.Key or ''):lower()
		if #teleportUid >= 1 and #teleportUid <= 24 and teleportUid:match('^%l[%w_]*$') then
			local encodedUid = httpService:JSONEncode(teleportUid)
			local encodedFolder = httpService:JSONEncode(runtimeFolder)
			local teleportScript
			if shared.BadVapeDeveloper then
				teleportScript = 'shared.BadVapeReload = true\n'
					..'shared.BadVapeDeveloper = true\n'
					..'shared.BadVapeFolder = '..encodedFolder..'\n'
					..'local badVapeLoader, badVapeLoadError = loadstring(readfile(shared.BadVapeFolder.."/loader.lua"), "@badvape/loader.lua")\n'
					..'if type(badVapeLoader) ~= "function" then error(badVapeLoadError or "BadVape local loader rejected", 0) end\n'
					..'return badVapeLoader({Key = '..encodedUid..'})'
			else
				local loaderUrl = httpService:JSONEncode('https://luvit.cc/badvape-api/loader')
				teleportScript = 'shared.BadVapeReload = true\n'
					..'shared.BadVapeFolder = '..encodedFolder..'\n'
					..'loadstring(game:HttpGet('..loaderUrl..'))() { log { '..encodedUid..' } }'
			end
			if shared.BadVapeCustomProfile then
				teleportScript = 'shared.BadVapeCustomProfile = '
					..httpService:JSONEncode(tostring(shared.BadVapeCustomProfile))..'\n'..teleportScript
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

	if not shared.BadVapeReload then
		if not vape.Categories then return end
		if vape.Categories.Main.Options['GUI bind indicator'].Enabled then
			if vape.Place ~= 6872274481 then
				--task.spawn(redirect)
			end
			vape:CreateNotification('Finished Loading', (vape.VapeButton and 'Press the button in the top right' or 'Press '..table.concat(vape.Keybind, ' + '):upper())..' to open GUI', 5)
			task.delay(1, function()
				if shared.BadVapeUpdated then
					vape:CreateNotification('BadVape', `Script has updated from {shared.BadVapeUpdated} to {readfile('badvape/profiles/commit.txt')}`, 10, 'info')
				end
			end)
		end
	end
end

if not isfile('badvape/profiles/gui.txt') then
	writefile('badvape/profiles/gui.txt', 'new')
end
local gui = readCachedFile('badvape/profiles/gui.txt') or 'new'
if gui == 'rise' then
	gui = 'new'
	writefile('badvape/profiles/gui.txt', gui)
end
if gui ~= 'new' and gui ~= 'old' then
	gui = 'new'
	writefile('badvape/profiles/gui.txt', gui)
end
if not isfile('badvape/profiles/commit.txt') then
	writefile('badvape/profiles/commit.txt', 'main')
end

pcall(function()
	runtimeEnvironment.BadVapeUsedInit = true
end)

local function loadGuiCandidate(name)
	local path = 'badvape/guis/'..name..'.lua'
	if not isfolder('badvape/assets/'..name) then
		makefolder('badvape/assets/'..name)
	end
	local sourceOk, source = pcall(downloadFile, path)
	if not sourceOk then
		return nil, path..' download failed: '..tostring(source)
	end
	local success, result = runSource(source, path, license)
	if not success then return nil, result end
	if type(result) ~= 'table' or type(result.Load) ~= 'function'
		or type(result.Save) ~= 'function' or type(result.CreateNotification) ~= 'function' then
		return nil, path..' returned an invalid GUI object'
	end
	return result
end

local guiError
vape, guiError = loadGuiCandidate(gui)
local guiFallbackReason
if not vape and gui ~= 'old' then
	guiFallbackReason = guiError
	local fallbackError
	vape, fallbackError = loadGuiCandidate('old')
	if vape then
		gui = 'old'
		pcall(writefile, 'badvape/profiles/gui.txt', gui)
	else
		guiError = tostring(guiError)..' | '..tostring(fallbackError)
	end
end
if not vape then
	error('BadVape GUI unavailable: '..tostring(guiError), 0)
end

if not isfolder('badvape/assets/'..gui) then
	makefolder('badvape/assets/'..gui)
end
vape.Place = game.PlaceId
_G.BadVape = vape
shared.BadVape = vape
local previousUninject = vape.Uninject
if type(previousUninject) == 'function' then
	vape.Uninject = function(self, ...)
		if shared.BadVapeDownloadFile == ownedDownloadFile then
			shared.BadVapeDownloadFile = nil
		end
		local results = table.pack(pcall(previousUninject, self, ...))
		restoreRuntimeEnvironment()
		if not results[1] then
			error(results[2], 0)
		end
		return table.unpack(results, 2, results.n)
	end
end
loadMaxPrediction()
loadBadVapeTheme()
if guiFallbackReason then
	vape:CreateNotification('BadVape', 'The selected GUI failed, so compatibility mode was loaded: '..tostring(guiFallbackReason), 12, 'warning')
end

local function loadGameModule(placeId)
	vape.Place = placeId
	local gamePath = 'badvape/games/'..placeId..'.lua'
	if diagnostics and type(diagnostics.fileState) == 'function' then
		pcall(diagnostics.fileState, gamePath, nil, 'game-module-load')
	end
	local gameSource = readCachedFile(gamePath)
		or shared.BadVapeDownloadFile(gamePath)
	if type(gameSource) ~= 'string' or gameSource == '404: Not Found' then
		recordDiagnostic('game_module_source_unavailable', {path = gamePath, placeId = placeId})
		vape:CreateNotification(
			'BadVape',
			'Game module file unavailable; loaded base modules only. Send '..diagnosticsPath..' to support.',
			15,
			'warning'
		)
		return false
	end

	shared.BadVapeProtectedFailure = nil
	local ok, loaded = runSource(gameSource, tostring(placeId), license)
	if not ok or loaded == false then
		local protectedFailure = type(shared.BadVapeProtectedFailure) == 'table'
			and shared.BadVapeProtectedFailure or nil
		local detail = not ok and tostring(loaded) or 'module returned false'
		if protectedFailure then
			detail = 'stage='..tostring(protectedFailure.stage or 'unknown')
				..(protectedFailure.status and ' status='..tostring(protectedFailure.status) or '')
				..(protectedFailure.correlationId and ' reference='..tostring(protectedFailure.correlationId) or '')
				..(protectedFailure.detail and ' '..tostring(protectedFailure.detail) or '')
		end
		recordDiagnostic('game_module_failed', {
			correlationId = protectedFailure and protectedFailure.correlationId or 'none',
			detail = detail,
			path = gamePath,
			placeId = placeId,
			stage = protectedFailure and protectedFailure.stage or (ok and 'module-returned-false' or 'runtime-error'),
			status = protectedFailure and protectedFailure.status or 'none',
		})
		vape:CreateNotification(
			'BadVape',
			'Game module unavailable; loaded base modules only. '..detail:sub(1, 260)
				..' Send '..diagnosticsPath..' to support.',
			15,
			'warning'
		)
		return false
	end
	recordDiagnostic('game_module_loaded', {bytes = #gameSource, path = gamePath, placeId = placeId})
	return true
end

if not shared.BadVapeIndependent then
	local universalPath = 'badvape/games/universal.lua'
	local universalSourceOk, universalSource = pcall(downloadFile, universalPath)
	local universalOk, universalError = false, universalSource
	if universalSourceOk then
		universalOk, universalError = runSource(universalSource, universalPath, license)
	end
	if not universalOk then
		recordDiagnostic('base_modules_failed', {error = universalError, path = universalPath})
		vape:CreateNotification('BadVape', 'Base modules failed to load: '..tostring(universalError):sub(1, 240), 12, 'alert')
	else
		recordDiagnostic('base_modules_loaded', {path = universalPath})
	end
	loadGameModule(game.PlaceId)
	loadBadVapeTheme()
	recordDiagnostic('main_finish_loading', {placeId = game.PlaceId})
	finishLoading()
else
	loadBadVapeTheme()
	vape.Init = finishLoading
	return vape
end
