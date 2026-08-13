-- BadVape public runtime installer.
-- The manifest is an explicit allowlist; private game source is never part of it.

local forwardedLicense, installerTransport, requestedReleaseRef = ...
local httpService = game:GetService('HttpService')

-- The queued teleport entrypoint may run while the destination is still
-- mounting.  Keep this guard here as a second boundary for cached/direct
-- installer calls that do not pass through bootstrap.lua.
local floodCraftPlaces = {
	[6872265039] = true,
	[6872274481] = true,
	[8444591321] = true,
	[8560631822] = true,
}

local function floodCraftClientReady()
	local placeId = tonumber(game.PlaceId)
	if not floodCraftPlaces[placeId] then
		return true
	end

	local workspaceService = game:GetService('Workspace')
	local marker = workspaceService:FindFirstChild('ClientFlameReady')
	return marker ~= nil
		and (type(marker.IsA) ~= 'function' or marker:IsA('BoolValue'))
		and marker.Value == true
end

local function waitForDestinationReady()
	local apiAvailable = false
	pcall(function()
		apiAvailable = type(game) == 'userdata' or type(game) == 'table'
			and type(game.IsLoaded) == 'function'
			and type(game.GetService) == 'function'
	end)
	if not apiAvailable then return true end

	local clock = type(os) == 'table' and type(os.clock) == 'function'
		and os.clock or tick
	local deadline = clock() + 45
	while clock() < deadline do
		local ready = false
		pcall(function()
			local players = game:GetService('Players')
			local localPlayer = players.LocalPlayer
			ready = game:IsLoaded()
				and localPlayer ~= nil
				and localPlayer:FindFirstChild('PlayerGui') ~= nil
				and localPlayer:FindFirstChild('PlayerScripts') ~= nil
				and floodCraftClientReady()
		end)
		if ready then return true end
		if type(task) == 'table' and type(task.wait) == 'function' then
			task.wait()
		else
			break
		end
	end
	return false
end

if not waitForDestinationReady() then
	error('BadVape destination place did not finish loading', 0)
end

local owner = '4fundsagent-source'
local repo = 'badvape-v2'
local branch = 'main'
local folder = shared.BadVapeFolder or 'badvape'
local diagnosticsPath = folder..'/badvape-debug.txt'

-- Teleport reloads may pin the exact immutable release that was already
-- installed.  This is validated before any network selection and takes
-- precedence over branch/API resolution without weakening normal startup.
if requestedReleaseRef ~= nil then
	if type(requestedReleaseRef) ~= 'string'
		or not requestedReleaseRef:match('^[0-9a-f]+$')
		or #requestedReleaseRef ~= 40 then
		error('invalid BadVape release ref', 0)
	end
	branch = requestedReleaseRef
end

-- Keep one self-contained report in the workspace. It deliberately excludes
-- credentials, device identifiers, auth tokens, request headers and contents.
local diagnosticLines = {
	'BadVape diagnostics v1',
	'privacy=credentials, device identifiers, auth tokens, headers and file contents are not recorded',
}
local diagnosticStarted = type(os) == 'table' and type(os.clock) == 'function' and os.clock() or 0
local diagnosticDirty = true
local diagnosticLastFlush = diagnosticStarted
local diagnosticFlushCount = 0
local diagnosticFlushEvery = 12
local diagnosticFlushInterval = 0.75
local diagnosticCriticalEvents = {
	installer_start = true,
	installer_invalid_release_ref = true,
	pinned_cache_mismatch = true,
	manifest_invalid = true,
	install_download_set_failed = true,
	install_parent_failed = true,
	install_write_failed = true,
	install_verify_failed = true,
	profile_update_state_write_failed = true,
	installer_manifest_unavailable = true,
	installer_cache_fallback = true,
	installer_commit_deferred = true,
	installer_committed = true,
	runtime_missing = true,
	runtime_read_failed = true,
	runtime_compile_start = true,
	runtime_compile_failed = true,
	runtime_compile_complete = true,
	runtime_execution_start = true,
	runtime_execution_failed = true,
	runtime_execution_complete = true,
}
local forwardedSecret = type(forwardedLicense) == 'table' and forwardedLicense.Key
forwardedSecret = type(forwardedSecret) == 'string' and forwardedSecret or nil
local forwardedLuaProtMarker, forwardedLuaProtSecret
if forwardedSecret then
	forwardedLuaProtMarker, forwardedLuaProtSecret = forwardedSecret:match('^LP%-([BR])%-([a-f0-9]+)$')
end
if forwardedLuaProtSecret and #forwardedLuaProtSecret ~= 24 then
	forwardedLuaProtMarker, forwardedLuaProtSecret = nil, nil
end

local function replacePlain(value, needle, replacement)
	if type(value) ~= 'string' or type(needle) ~= 'string' or needle == '' then
		return value
	end
	local result, cursor = {}, 1
	while true do
		local first, last = value:find(needle, cursor, true)
		if not first then
			table.insert(result, value:sub(cursor))
			break
		end
		table.insert(result, value:sub(cursor, first - 1))
		table.insert(result, replacement)
		cursor = last + 1
	end
	return table.concat(result)
end

local function diagnosticValue(value)
	value = tostring(value)
	if forwardedSecret and forwardedSecret ~= '' then
		value = replacePlain(value, forwardedSecret, '<credential-redacted>')
	end
	if forwardedLuaProtSecret then
		value = replacePlain(value, forwardedLuaProtSecret, '<credential-redacted>')
	end
	value = value:gsub('BV%-%u%-[%w]+', '<license-redacted>')
	value = value:gsub("([\"']?[Kk][Ee][Yy][\"']?%s*[:=]%s*[\"']?)[^%s,;\"'}]+", '%1<redacted>')
	value = value:gsub("([\"']?[Uu][Ii][Dd][\"']?%s*[:=]%s*[\"']?)[^%s,;\"'}]+", '%1<redacted>')
	value = value:gsub("([\"']?[Hh][Ww][Ii][Dd][\"']?%s*[:=]%s*[\"']?)[^%s,;\"'}]+", '%1<redacted>')
	value = value:gsub("([\"']?[Aa]uthorization[\"']?%s*[:=]%s*[\"']?)[^,;\"'}]+", '%1<redacted>')
	value = value:gsub("([\"']?[Tt]oken[\"']?%s*[:=]%s*[\"']?)[^%s,;\"'}]+", '%1<redacted>')
	value = value:gsub("([\"']?[Ff]ingerprint[\"']?%s*[:=]%s*[\"']?)[^%s,;\"'}]+", '%1<redacted>')
	value = value:gsub('[\r\n\t%z]', ' '):gsub('%s+', ' ')
	return value:sub(1, 2000)
end

local function flushDiagnostics(force)
	if not force and not diagnosticDirty then return true end
	pcall(function()
		if not isfolder(folder) then makefolder(folder) end
		writefile(diagnosticsPath, table.concat(diagnosticLines, '\n')..'\n')
	end)
	diagnosticDirty = false
	diagnosticLastFlush = type(os) == 'table' and type(os.clock) == 'function' and os.clock() or diagnosticLastFlush
	diagnosticFlushCount += 1
	return true
end

local diagnostics = {path = diagnosticsPath}
function diagnostics.record(event, fields)
	local parts = {string.format('%04d', #diagnosticLines - 1), 'event='..diagnosticValue(event)}
	local elapsed = type(os) == 'table' and type(os.clock) == 'function' and os.clock() - diagnosticStarted or 0
	table.insert(parts, string.format('elapsed=%.3f', elapsed))
	local keys = {}
	for key in type(fields) == 'table' and fields or {} do
		table.insert(keys, tostring(key))
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		table.insert(parts, diagnosticValue(key)..'='..diagnosticValue(fields[key]))
	end
	table.insert(diagnosticLines, table.concat(parts, '\t'))
	diagnosticDirty = true
	local now = type(os) == 'table' and type(os.clock) == 'function' and os.clock() or diagnosticLastFlush
	local eventCount = #diagnosticLines - 2
	if diagnosticCriticalEvents[event]
		or eventCount % diagnosticFlushEvery == 0
		or now - diagnosticLastFlush >= diagnosticFlushInterval then
		flushDiagnostics(true)
	end
end
diagnostics.flush = function()
	return flushDiagnostics(true)
end
diagnostics.redact = diagnosticValue
shared.BadVapeDiagnostics = diagnostics
flushDiagnostics(true)

local pinnedReleaseRef
if shared.BadVapeReleaseRef ~= nil then
	if type(shared.BadVapeReleaseRef) ~= 'string'
		or not shared.BadVapeReleaseRef:match('^[0-9a-f]+$')
		or #shared.BadVapeReleaseRef ~= 40 then
		diagnostics.record('installer_invalid_release_ref')
		error('invalid BadVape release ref', 0)
	end
	pinnedReleaseRef = shared.BadVapeReleaseRef
	branch = pinnedReleaseRef
end
local revisionPath = folder..'/cache/public-revision.txt'
local fileIndexPath = folder..'/cache/public-file-index.txt'
local profileSeedPath = folder..'/cache/profile-seed-v1.txt'
local profileOverridePath = folder..'/cache/profile-reset-20260715-v1.txt'
local profileUpdateStatePath = folder..'/cache/profile-update-v1.json'
local profileUpdateRoot = folder..'/cache/profile-updates'
local releaseRefPath = folder..'/cache/public-release-ref.txt'
local runtimeRepairPath = folder..'/cache/runtime-repair-20260716-v1.txt'

shared.BadVapeFolder = folder
-- This flag is scoped to the current installer execution.  The game module
-- uses it only to yield during a cold/update registration pass; cached runs
-- stay on the fast path.
shared.BadVapeColdStart = false

local function identifyExecutor()
	local candidates = {identifyexecutor, getexecutorname}
	if type(getgenv) == 'function' then
		local ok, environment = pcall(getgenv)
		if ok and type(environment) == 'table' then
			table.insert(candidates, 1, environment.getexecutorname)
			table.insert(candidates, 1, environment.identifyexecutor)
		end
	end
	for _, candidate in ipairs(candidates) do
		if type(candidate) == 'function' then
			local ok, name = pcall(candidate)
			if ok and type(name) == 'string' and name ~= '' then return name end
		end
	end
	return 'unknown'
end

diagnostics.record('installer_start', {
	credentialKind = forwardedLuaProtSecret and 'luaprot'
		or (forwardedSecret and (forwardedSecret:match('^BV%-%u%-') and 'license' or 'uid') or 'missing'),
	executor = identifyExecutor(),
	folder = folder,
	gameId = game.GameId,
	pinned = pinnedReleaseRef ~= nil,
	placeId = game.PlaceId,
})
local capabilityEnvironment = {}
if type(getgenv) == 'function' then
	local ok, environment = pcall(getgenv)
	if ok and type(environment) == 'table' then capabilityEnvironment = environment end
end
local forwardedRequestAdapters = {}
if type(installerTransport) == 'table' and type(installerTransport.requestAdapters) == 'table' then
	for _, candidate in ipairs(installerTransport.requestAdapters) do
		if type(candidate) == 'function' then
			table.insert(forwardedRequestAdapters, candidate)
		end
	end
end
installerTransport = nil
local capabilitySyn = type(capabilityEnvironment.syn) == 'table' and capabilityEnvironment.syn
	or type(syn) == 'table' and syn or nil
local capabilityFluxus = type(capabilityEnvironment.fluxus) == 'table' and capabilityEnvironment.fluxus
	or type(fluxus) == 'table' and fluxus or nil
local capabilityKrnl = type(capabilityEnvironment.krnl) == 'table' and capabilityEnvironment.krnl
	or type(krnl) == 'table' and krnl or nil
local capabilityHttp = type(capabilityEnvironment.http) == 'table' and capabilityEnvironment.http
	or type(http) == 'table' and http or nil
local capabilityCrypt = type(capabilityEnvironment.crypt) == 'table' and capabilityEnvironment.crypt
	or type(crypt) == 'table' and crypt or nil
local capabilityCrypto = type(capabilityEnvironment.crypto) == 'table' and capabilityEnvironment.crypto
	or type(crypto) == 'table' and crypto or nil
local requestDirect = type(capabilityEnvironment.request) == 'function'
	or type(capabilityEnvironment.http_request) == 'function'
	or capabilityHttp and type(capabilityHttp.request) == 'function'
	or type(request) == 'function'
	or type(http_request) == 'function'
	or #forwardedRequestAdapters > 0
local requestSyn = capabilitySyn and type(capabilitySyn.request) == 'function' or false
local requestFluxus = capabilityFluxus and type(capabilityFluxus.request) == 'function' or false
local requestKrnl = capabilityKrnl and type(capabilityKrnl.request) == 'function' or false
diagnostics.record('executor_capabilities', {
	bit32 = type(bit32) == 'table',
	buffer = type(buffer) == 'table',
	cloneref = type(cloneref) == 'function',
	cryptHash = capabilityCrypt and type(capabilityCrypt.hash) == 'function' or false,
	cryptoHash = capabilityCrypto and type(capabilityCrypto.hash) == 'function' or false,
	debugTraceback = type(debug) == 'table' and type(debug.traceback) == 'function',
	delfile = type(delfile) == 'function',
	getcustomasset = type(getcustomasset) == 'function',
	getgenv = type(getgenv) == 'function',
	gethwid = type(capabilityEnvironment.gethwid) == 'function'
		or type(capabilityEnvironment.get_hwid) == 'function'
		or type(gethwid) == 'function'
		or type(get_hwid) == 'function',
	httpGet = type(game.HttpGet) == 'function',
	isfile = type(isfile) == 'function',
	isfolder = type(isfolder) == 'function',
	listfiles = type(listfiles) == 'function',
	loadstring = type(loadstring) == 'function',
	makefolder = type(makefolder) == 'function',
	readfile = type(readfile) == 'function',
	request = requestDirect or requestSyn or requestFluxus or requestKrnl,
	requestDirect = requestDirect,
	requestFluxus = requestFluxus,
	requestKrnl = requestKrnl,
	requestSyn = requestSyn,
	synCryptHash = capabilitySyn and type(capabilitySyn.crypt) == 'table'
		and type(capabilitySyn.crypt.hash) == 'function' or false,
	taskSpawn = type(task) == 'table' and type(task.spawn) == 'function',
	taskWait = type(task) == 'table' and type(task.wait) == 'function',
	writefile = type(writefile) == 'function',
})

local httpAdapters, seenHttpAdapters = {}, {}
local function addHttpAdapter(candidate)
	if type(candidate) == 'function' and not seenHttpAdapters[candidate] then
		seenHttpAdapters[candidate] = true
		table.insert(httpAdapters, candidate)
	end
end
for _, candidate in ipairs(forwardedRequestAdapters) do
	addHttpAdapter(candidate)
end
addHttpAdapter(capabilityHttp and capabilityHttp.request or nil)
addHttpAdapter(capabilityEnvironment.request)
addHttpAdapter(capabilityEnvironment.http_request)
addHttpAdapter(type(request) == 'function' and request or nil)
addHttpAdapter(type(http_request) == 'function' and http_request or nil)
addHttpAdapter(capabilitySyn and capabilitySyn.request or nil)
addHttpAdapter(capabilityFluxus and capabilityFluxus.request or nil)
addHttpAdapter(capabilityKrnl and capabilityKrnl.request or nil)

local function compatibleHttpGet(url, cache)
	local ok, body = pcall(game.HttpGet, game, url, cache)
	if ok and type(body) == 'string' and body ~= '' and body ~= '404: Not Found' then
		return body
	end
	local lastError = ok and 'empty response' or body
	for _, adapter in ipairs(httpAdapters) do
		local requestOk, response = pcall(adapter, {Url = url, Method = 'GET'})
		local responseType = requestOk and type(response) or nil
		local status = responseType == 'string' and 200
			or (responseType == 'table'
				and tonumber(response.StatusCode or response.Status
					or response.status_code or response.status) or nil)
		local responseBody = responseType == 'string' and response
			or (responseType == 'table' and (response.Body or response.body) or nil)
		if (status == nil or status == 0 or status == 200 or status == 201)
			and type(responseBody) == 'string'
			and responseBody ~= ''
			and responseBody ~= '404: Not Found' then
			return responseBody
		end
		lastError = requestOk and 'status '..tostring(status or 'unknown') or response
	end
	error(tostring(lastError or 'download failed'), 0)
end

local function safeIsFile(path)
	if isfile then
		local ok, result = pcall(isfile, path)
		if ok and result then
			return true
		end

		-- A few executors cache `isfile` results briefly after a write.  Read the
		-- file as a fallback so a successful atomic install is not reported as a
		-- missing runtime entrypoint on the same execution.
		local readOk, contents = pcall(readfile, path)
		return readOk and type(contents) == 'string' and contents ~= ''
	end
	local ok, value = pcall(readfile, path)
	return ok and type(value) == 'string'
end

local function ensureFolder(path)
	if not isfolder(path) then
		makefolder(path)
	end
end

local function ensureParent(path)
	local parts = path:split('/')
	local current = ''
	for index = 1, #parts - 1 do
		current = current..(index > 1 and '/' or '')..parts[index]
		ensureFolder(current)
	end
end

local function runCachedRuntime()
	-- Persist the complete installer state once before handing control to the
	-- runtime. Diagnostics are buffered during the file plan to avoid rewriting
	-- the whole report for every cache/hash event, but a runtime failure must
	-- still leave an immediately usable report on disk.
	flushDiagnostics(true)
	local osPath = folder..'/os.luau'
	if not safeIsFile(osPath) then
		diagnostics.record('runtime_missing', {path = osPath})
		error('missing cached BadVape runtime', 0)
	end
	local readOk, osSource = pcall(readfile, osPath)
	if not readOk or type(osSource) ~= 'string' or osSource == '' then
		diagnostics.record('runtime_read_failed', {error = osSource, path = osPath})
		error('failed to read cached BadVape runtime', 0)
	end
	diagnostics.record('runtime_compile_start', {bytes = #osSource, path = osPath})
	local compileResult = table.pack(pcall(loadstring, osSource, folder..'/os.luau'))
	if not compileResult[1] then
		diagnostics.record('runtime_compile_failed', {error = compileResult[2], path = osPath})
		error(compileResult[2] or 'BadVape runtime rejected', 0)
	end
	local osChunk, loadError = compileResult[2], compileResult[3]
	if type(osChunk) ~= 'function' then
		diagnostics.record('runtime_compile_failed', {error = loadError or 'rejected', path = osPath})
		error(loadError or 'BadVape runtime rejected', 0)
	end
	diagnostics.record('runtime_compile_complete', {path = osPath})
	local function traceError(value)
		if type(debug) == 'table' and type(debug.traceback) == 'function' then
			local ok, trace = pcall(debug.traceback, tostring(value), 2)
			if ok and type(trace) == 'string' then return trace end
		end
		return tostring(value)
	end
	diagnostics.record('runtime_execution_start', {path = osPath})
	local runtimeResult = table.pack(xpcall(function()
		return osChunk(forwardedLicense)
	end, traceError))
	if not runtimeResult[1] then
		diagnostics.record('runtime_execution_failed', {error = runtimeResult[2], path = osPath})
		flushDiagnostics(true)
		error(runtimeResult[2], 0)
	end
	diagnostics.record('runtime_execution_complete', {path = osPath, resultType = typeof(runtimeResult[2])})
	flushDiagnostics(true)
	return table.unpack(runtimeResult, 2, runtimeResult.n)
end

-- Only an explicit developer flag may select the local workspace.  Public
-- installs can retain `profiles/commit.txt=local` from older versions; that
-- marker is not an authorization signal and must not bypass manifest repair.
local localWorkspace = shared.BadVapeDeveloper == true and safeIsFile(folder..'/os.luau')
if localWorkspace then
	diagnostics.record('installer_local_workspace', {folder = folder})
	return runCachedRuntime()
end
if shared.BadVapeDeveloper == true then
	shared.BadVapeDeveloper = nil
end

local releaseRef, releaseStrategy
for attempt = 1, 3 do
	local refOk, refBody = pcall(compatibleHttpGet,
		'https://api.github.com/repos/'..owner..'/'..repo..'/commits/'..branch, true)
	if refOk and type(refBody) == 'string' then
		local decodeOk, refData = pcall(httpService.JSONDecode, httpService, refBody)
		if decodeOk and type(refData) == 'table'
			and type(refData.sha) == 'string'
			and refData.sha:match('^[0-9a-f]+$')
			and #refData.sha == 40
			and (not pinnedReleaseRef or refData.sha == pinnedReleaseRef) then
			releaseRef = refData.sha
			releaseStrategy = 'github_api'
			diagnostics.record('release_lookup_succeeded', {attempt = attempt, releaseRef = releaseRef})
			break
		end
		diagnostics.record('release_lookup_failed', {
			attempt = attempt,
			error = decodeOk and 'invalid commit response' or refData,
		})
	else
		diagnostics.record('release_lookup_failed', {attempt = attempt, error = refBody})
	end
	if attempt < 3 and type(task) == 'table' and type(task.wait) == 'function' then
		task.wait(0.25 * attempt)
	end
end
local cachedReleaseRef
if safeIsFile(releaseRefPath) then
	local ok, cachedRef = pcall(readfile, releaseRefPath)
	if ok and type(cachedRef) == 'string'
		and cachedRef:match('^[0-9a-f]+$') and #cachedRef == 40 then
		cachedReleaseRef = cachedRef
	end
end
diagnostics.record('release_cache_state', {cachedRef = cachedReleaseRef or 'none'})
if not releaseRef and pinnedReleaseRef and cachedReleaseRef == pinnedReleaseRef then
	releaseRef = cachedReleaseRef
	releaseStrategy = 'matching_pinned_cache'
end
if not releaseRef then
	if pinnedReleaseRef and safeIsFile(folder..'/os.luau')
		and cachedReleaseRef ~= pinnedReleaseRef then
		diagnostics.record('pinned_cache_mismatch', {
			cachedRef = cachedReleaseRef or 'none',
			requestedRef = pinnedReleaseRef,
		})
		error('pinned BadVape cache mismatch', 0)
	end
	-- GitHub's unauthenticated commit API can be rate-limited even while raw
	-- content remains healthy. Both fresh and existing installs must try the
	-- branch here; selecting an old cached ref would strand existing folders on
	-- a stale game module while clean folders update correctly.
	releaseRef = branch
	releaseStrategy = pinnedReleaseRef and 'pinned_direct' or 'branch_fallback'
end
diagnostics.record('release_selected', {releaseRef = releaseRef, strategy = releaseStrategy})
local baseUrls = {
	'https://raw.githubusercontent.com/'..owner..'/'..repo..'/'..releaseRef..'/',
	'https://cdn.jsdelivr.net/gh/'..owner..'/'..repo..'@'..releaseRef..'/',
}

local publicGamePaths = {
	['games/11156779721.lua'] = true,
	['games/123804558118054.lua'] = true,
	['games/129604661913557.lua'] = true,
	['games/131465939650733.lua'] = true,
	['games/13246639586.lua'] = true,
	['games/135564683255158.lua'] = true,
	['games/139566161526375.lua'] = true,
	['games/142823291.lua'] = true,
	['games/155615604.lua'] = true,
	['games/17625359962.lua'] = true,
	['games/18126510175.lua'] = true,
	['games/5938036553.lua'] = true,
	['games/606849621.lua'] = true,
	['games/6872265039.lua'] = true,
	['games/71874690745115.lua'] = true,
	['games/77790193039862.lua'] = true,
	['games/80041634734121.lua'] = true,
	['games/8542259458.lua'] = true,
	['games/8542275097.lua'] = true,
	['games/8592115909.lua'] = true,
	['games/8768229691.lua'] = true,
	['games/893973440.lua'] = true,
	['games/8951451142.lua'] = true,
	['games/6872274481.lua'] = true,
	['games/8444591321.lua'] = true,
	['games/8560631822.lua'] = true,
	['games/madebyirony.lua'] = true,
	['games/universal.lua'] = true,
	['games/117398147513099.lua'] = true,
	['games/133215910299950.lua'] = true,
}
local publicLibraryPaths = {
	['libraries/badvape-theme.lua'] = true,
	['libraries/base64.lua'] = true,
	['libraries/cheatenginelib.lua'] = true,
	['libraries/entity.lua'] = true,
	['libraries/hash.lua'] = true,
	['libraries/luaprot-bedwars.lua'] = true,
	['libraries/luaprot-rivals.lua'] = true,
	['libraries/prediction.lua'] = true,
	['libraries/string.lua'] = true,
	['libraries/vm.lua'] = true,
}
local seedProfilePaths = {
	['profiles/2619619496.gui.txt'] = true,
	['profiles/blatant6872265039.txt'] = true,
	['profiles/blatant6872274481.txt'] = true,
	['profiles/default6872265039.txt'] = true,
	['profiles/default6872274481.txt'] = true,
	['profiles/default117398147513099.txt'] = true,
	['profiles/default133215910299950.txt'] = true,
	['profiles/default17625359962.txt'] = true,
	['profiles/gui.txt'] = true,
}
local releaseProfileOverridePaths = {
	['profiles/2619619496.gui.txt'] = true,
	['profiles/blatant6872265039.txt'] = true,
	['profiles/blatant6872274481.txt'] = true,
	['profiles/default6872274481.txt'] = true,
}
local retiredRuntimePaths = {
	['games/131823264266369.lua'] = true,
	['games/protected6872274481.lua'] = true,
}

local commonInstallPaths = {
	['init.lua'] = true,
	['loader.lua'] = true,
	['main.lua'] = true,
	['os.luau'] = true,
	['reinstall.luau'] = true,
	['games/universal.lua'] = true,
	['libraries/badvape-theme.lua'] = true,
	['libraries/entity.lua'] = true,
	['libraries/hash.lua'] = true,
	['libraries/luaprot-bedwars.lua'] = true,
	['libraries/luaprot-rivals.lua'] = true,
	['libraries/prediction.lua'] = true,
	['libraries/string.lua'] = true,
	['profiles/features.json'] = true,
	['profiles/packages.json'] = true,
}

local gameDependencyPaths = {
	[6872274481] = {
		['games/madebyirony.lua'] = true,
		['libraries/cheatenginelib.lua'] = true,
	},
	[8444591321] = {
		['games/6872274481.lua'] = true,
		['games/madebyirony.lua'] = true,
		['libraries/cheatenginelib.lua'] = true,
	},
	[8560631822] = {
		['games/6872274481.lua'] = true,
		['games/madebyirony.lua'] = true,
		['libraries/cheatenginelib.lua'] = true,
	},
	[117398147513099] = {
		['games/17625359962.lua'] = true,
	},
	[133215910299950] = {
		['games/17625359962.lua'] = true,
	},
	[18126510175] = {
		['games/17625359962.lua'] = true,
	},
	[71874690745115] = {
		['games/17625359962.lua'] = true,
	},
	[129604661913557] = {
		['games/17625359962.lua'] = true,
	},
	[606849621] = {
		['libraries/vm.lua'] = true,
	},
}

local function selectedGuiPath()
	local gui = 'new'
	local guiPath = folder..'/profiles/gui.txt'
	if safeIsFile(guiPath) then
		local ok, value = pcall(readfile, guiPath)
		if ok and type(value) == 'string' then
			value = value:match('^%s*(.-)%s*$')
			if value == 'old' then
				gui = 'old'
			end
		end
	end
	return 'guis/'..gui..'.lua'
end

local function requiredPublicPaths(manifest)
	local available, required = {}, {}
	for _, entry in ipairs(manifest.files) do
		available[entry.path] = true
	end

	local function add(path)
		if available[path] then
			required[path] = true
		end
	end

	for path in commonInstallPaths do
		add(path)
	end
	for path in seedProfilePaths do
		add(path)
	end
	add(selectedGuiPath())

	local placeId = tonumber(game.PlaceId)
	local gamePath = placeId and 'games/'..placeId..'.lua' or nil
	if gamePath and publicGamePaths[gamePath] then
		add(gamePath)
	end
	for path in gameDependencyPaths[placeId] or {} do
		add(path)
	end
	return required
end

local function isPublicPath(path)
	if type(path) ~= 'string'
		or path == ''
		or path:sub(1, 1) == '/'
		or path:find('\\', 1, true)
		or path:find('//', 1, true)
		or not path:match('^[%w._/%-]+$') then
		return false
	end
	for part in path:gmatch('[^/]+') do
		if part == '.' or part == '..' then
			return false
		end
	end

	if path == 'init.lua'
		or path == 'bootstrap.lua'
		or path == 'loader.lua'
		or path == 'main.lua'
		or path == 'os.luau'
		or path == 'reinstall.luau'
		or path == 'guis/new.lua'
		or path == 'guis/old.lua'
		or path == 'profiles/features.json'
		or path == 'profiles/packages.json' then
		return true
	end
	if publicGamePaths[path] then
		return true
	end
	if seedProfilePaths[path] then
		return true
	end
	if publicLibraryPaths[path] then
		return true
	end
	return false
end

local function validateManifest(manifest)
	if type(manifest) ~= 'table'
		or manifest.schemaVersion ~= 1
		or type(manifest.revision) ~= 'string'
		or not manifest.revision:match('^sha256%-[0-9a-f]+$')
		or #manifest.revision ~= 71
		or type(manifest.files) ~= 'table'
		or #manifest.files == 0
		or #manifest.files > 512 then
		return nil
	end

	local seen = {}
	local hasEntrypoint = false
	local totalBytes = 0
	for _, entry in ipairs(manifest.files) do
		if type(entry) ~= 'table'
			or not isPublicPath(entry.path)
			or seen[entry.path]
			or type(entry.bytes) ~= 'number'
			or entry.bytes < 0
			or entry.bytes ~= math.floor(entry.bytes)
			or entry.bytes > 16 * 1024 * 1024
			or type(entry.sha256) ~= 'string'
			or #entry.sha256 ~= 64
			or not entry.sha256:match('^[0-9a-f]+$') then
			return nil
		end
		seen[entry.path] = true
		hasEntrypoint = hasEntrypoint or entry.path == 'os.luau'
		totalBytes += entry.bytes
	end
	if not hasEntrypoint or totalBytes > 32 * 1024 * 1024 then
		return nil
	end
	return manifest
end

local function fetch(url)
	local ok, body = pcall(compatibleHttpGet, url, true)
	if not ok then
		return nil, body
	end
	if type(body) ~= 'string' then
		return nil, 'response type '..typeof(body)
	end
	if body == '' then
		return nil, 'empty response'
	end
	if body == '404: Not Found' then
		return nil, '404 response'
	end
	return body
end

local function fetchPath(path, validator)
	for attempt = 1, 4 do
		for mirror, baseUrl in ipairs(baseUrls) do
			local contents, fetchError = fetch(baseUrl..path)
			local validatorOk, accepted = true, true
			if contents and validator then
				validatorOk, accepted = pcall(validator, contents)
			end
			if contents and validatorOk and accepted then
				diagnostics.record('download_succeeded', {
					attempt = attempt,
					bytes = #contents,
					mirror = mirror,
					path = path,
					releaseRef = releaseRef,
				})
				return contents
			end
			diagnostics.record('download_failed', {
				attempt = attempt,
				bytes = contents and #contents or 0,
				error = fetchError or (validatorOk and 'content validation rejected' or accepted),
				mirror = mirror,
				path = path,
				releaseRef = releaseRef,
			})
		end
		if attempt < 4 and type(task) == 'table' and type(task.wait) == 'function' then
			task.wait(0.25 * attempt)
		end
	end
	return nil
end

local sha256Calibration = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
local function validDigest(value)
	return type(value) == 'string' and #value == 64 and value:match('^[0-9a-fA-F]+$') ~= nil
end

-- Do not fall back to a size-only comparison.  An attacker can replace a
-- cached or downloaded file with a same-sized payload and pass that check.
-- Most executors expose SHA-256, but the installer must remain fail-closed on
-- runtimes that do not.  This compact implementation is only used to verify
-- release files; the larger public hash library is loaded later by the
-- runtime.  It deliberately uses the standard Luau bit32 primitive so the
-- result is identical to the native SHA-256 implementations above.
local sha256Constants = {
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local function pureSha256(message)
	if type(message) ~= 'string' or type(bit32) ~= 'table'
		or type(bit32.band) ~= 'function' or type(bit32.bxor) ~= 'function'
		or type(bit32.bnot) ~= 'function' or type(bit32.rrotate) ~= 'function'
		or type(bit32.rshift) ~= 'function' then
		return nil
	end
	local modulo = 4294967296
	local length = #message
	local bitLength = length * 8
	local lengthBytes = {}
	for index = 8, 1, -1 do
		lengthBytes[index] = string.char(bitLength % 256)
		bitLength = math.floor(bitLength / 256)
	end
	local padded = message .. string.char(0x80)
		.. string.rep('\0', (-length - 9) % 64)
		.. table.concat(lengthBytes)
	local hash = {
		0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
		0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
	}
	for offset = 1, #padded, 64 do
		local words = {}
		for index = 0, 15 do
			local position = offset + index * 4
			local a, b, c, d = string.byte(padded, position, position + 3)
			words[index] = ((a * 256 + b) * 256 + c) * 256 + d
		end
		for index = 16, 63 do
			local first = words[index - 15]
			local second = words[index - 2]
			local smallFirst = bit32.bxor(bit32.rrotate(first, 7), bit32.rrotate(first, 18), bit32.rshift(first, 3))
			local smallSecond = bit32.bxor(bit32.rrotate(second, 17), bit32.rrotate(second, 19), bit32.rshift(second, 10))
			words[index] = (words[index - 16] + smallFirst + words[index - 7] + smallSecond) % modulo
		end
		local a, b, c, d, e, f, g, h = table.unpack(hash)
		for index = 0, 63 do
			local bigSecond = bit32.bxor(bit32.rrotate(e, 6), bit32.rrotate(e, 11), bit32.rrotate(e, 25))
			local choose = bit32.bxor(bit32.band(e, f), bit32.band(bit32.bnot(e), g))
			local firstTemp = (h + bigSecond + choose + sha256Constants[index + 1] + words[index]) % modulo
			local bigFirst = bit32.bxor(bit32.rrotate(a, 2), bit32.rrotate(a, 13), bit32.rrotate(a, 22))
			local majority = bit32.bxor(bit32.band(a, b), bit32.band(a, c), bit32.band(b, c))
			local secondTemp = (bigFirst + majority) % modulo
			h, g, f, e, d, c, b, a = g, f, e, (d + firstTemp) % modulo, c, b, a, (firstTemp + secondTemp) % modulo
		end
		for index = 1, 8 do
			hash[index] = (hash[index] + ({a, b, c, d, e, f, g, h})[index]) % modulo
		end
	end
	local output = {}
	for index = 1, 8 do
		output[index] = string.format('%08x', hash[index])
	end
	return table.concat(output)
end

local function invokeHash(candidate, owner, mode, value, useOwner)
	if mode == 1 then
		if useOwner then
			return pcall(candidate, owner, value, 'sha256')
		end
		return pcall(candidate, value, 'sha256')
	elseif mode == 2 then
		if useOwner then
			return pcall(candidate, owner, 'sha256', value)
		end
		return pcall(candidate, 'sha256', value)
	end
	if useOwner then
		return pcall(candidate, owner, value)
	end
	return pcall(candidate, value)
end

local function findNativeSha256()
	local candidates = {
		{type(crypt) == 'table' and crypt.hash or nil, crypt},
		{type(crypto) == 'table' and crypto.hash or nil, crypto},
		{type(syn) == 'table' and type(syn.crypt) == 'table' and syn.crypt.hash or nil, type(syn) == 'table' and syn.crypt or nil},
		{sha256, nil},
		{pureSha256, nil},
	}
	for _, data in ipairs(candidates) do
		local candidate, owner = data[1], data[2]
		if type(candidate) == 'function' then
			for mode = 1, 3 do
				for ownerMode = 1, owner and 2 or 1 do
					local useOwner = ownerMode == 2
					local ok, digest = invokeHash(candidate, owner, mode, 'abc', useOwner)
					if ok and validDigest(digest) and digest:lower() == sha256Calibration then
						return candidate, owner, mode, useOwner
					end
				end
			end
		end
	end
	return nil
end

local hashCandidate, hashOwner, hashMode, hashUseOwner = findNativeSha256()
diagnostics.record('hash_capability', {
	available = hashCandidate ~= nil,
	mode = hashCandidate and hashMode or 'size-only',
	usesOwner = hashCandidate and hashUseOwner or false,
})
local function canonicalPublicContent(path, contents)
	if type(contents) ~= 'string' then return contents end
	local extension = type(path) == 'string' and path:match('%.([^.]+)$') or nil
	if extension == 'json' or extension == 'lua' or extension == 'luau' or extension == 'txt' then
		return contents:gsub('\r\n', '\n')
	end
	return contents
end
local function contentMatches(entry, contents)
	contents = canonicalPublicContent(entry and entry.path, contents)
	if type(contents) ~= 'string' or #contents ~= entry.bytes then
		return false
	end
	if hashCandidate then
		local ok, digest = invokeHash(hashCandidate, hashOwner, hashMode, contents, hashUseOwner)
		return ok and validDigest(digest) and digest:lower() == entry.sha256
	end
	-- Integrity is mandatory.  Without a verified digest the installer must
	-- refuse both fresh content and same-sized cache substitutions.
	return false
end

local function inspectFileContents(entry, readOk, contents)
	local observation = {
		readable = readOk and type(contents) == 'string',
	}
	if not observation.readable then
		observation.error = contents
		return observation
	end
	-- Canonicalize once and compute one digest.  The previous implementation
	-- called contentMatches (which hashes) and then hashed the same file again
	-- to populate diagnostics.  Large protected modules paid that cost twice
	-- during every installer scan.
	local canonicalContents = canonicalPublicContent(entry and entry.path, contents)
	observation.bytes = #contents
	if hashCandidate then
		local hashOk, digest = invokeHash(hashCandidate, hashOwner, hashMode, canonicalContents, hashUseOwner)
		observation.sha256 = hashOk and validDigest(digest) and digest:lower() or 'hash-failed'
	end
	if not entry then
		observation.matches = 'unknown'
	elseif type(canonicalContents) ~= 'string' or #canonicalContents ~= entry.bytes then
		observation.matches = false
	elseif not hashCandidate then
		-- Integrity is mandatory when no verified digest capability is present.
		observation.matches = false
	else
		observation.matches = observation.sha256 ~= 'hash-failed'
			and observation.sha256 == entry.sha256
	end
	return observation
end

local function inspectCachedFile(path, entry)
	local observation = {exists = safeIsFile(path)}
	if not observation.exists then return observation end
	local readOk, contents = pcall(readfile, path)
	local contentObservation = inspectFileContents(entry, readOk, contents)
	for key, value in contentObservation do observation[key] = value end
	return observation
end

function diagnostics.fileState(relativePath, entry, state, observed)
	relativePath = relativePath:gsub('\\', '/')
	local path
	if relativePath:sub(1, #folder + 1) == folder..'/' then
		path = relativePath
	else
		relativePath = relativePath:gsub('^badvape/', '', 1)
		path = folder..'/'..relativePath
	end
	local observation = type(observed) == 'table' and observed or inspectCachedFile(path, entry)
	local exists = observation.exists == true
	local fields = {
		exists = exists,
		expectedBytes = entry and entry.bytes or 'unknown',
		expectedSha256 = entry and entry.sha256 or 'unknown',
		path = path,
		state = state or 'observed',
		validation = hashCandidate and 'sha256+size' or 'unavailable',
	}
	if exists then
		fields.readable = observation.readable == true
		if fields.readable then
			fields.bytes = observation.bytes
			fields.matches = observation.matches
			if hashCandidate then fields.sha256 = observation.sha256 or 'hash-failed' end
		else
			fields.error = observation.error
		end
	end
	diagnostics.record('file_state', fields)
end

local function readCachedRevision()
	if not safeIsFile(revisionPath) then
		return nil
	end
	local ok, revision = pcall(readfile, revisionPath)
	return ok and revision or nil
end

local function readCachedFileIndex()
	local index = {}
	if not safeIsFile(fileIndexPath) then
		return index, false
	end
	local ok, contents = pcall(readfile, fileIndexPath)
	if not ok or type(contents) ~= 'string' then
		return index, false
	end
	for line in contents:gmatch('[^\r\n]+') do
		local path, bytes, sha256 = line:match('^([^\t]+)\t(%d+)\t([0-9a-f]+)$')
		path = path and path:gsub('\\', '/')
		bytes = tonumber(bytes)
		if not path
			or not (isPublicPath(path) or retiredRuntimePaths[path])
			or not bytes
			or #sha256 ~= 64 then
			return {}, false
		end
		index[path] = {bytes = bytes, sha256 = sha256}
	end
	return index, true
end

local function copyFileIndex(index)
	local copied = {}
	for path, entry in index do
		if isPublicPath(path) and safeIsFile(folder..'/'..path) then
			copied[path] = {bytes = entry.bytes, sha256 = entry.sha256}
		end
	end
	return copied
end

local function encodeFileIndex(index)
	local paths, lines = {}, {}
	for path in index do
		table.insert(paths, path)
	end
	table.sort(paths)
	for lineIndex, path in ipairs(paths) do
		local entry = index[path]
		lines[lineIndex] = path..'\t'..entry.bytes..'\t'..entry.sha256
	end
	return #lines > 0 and table.concat(lines, '\n')..'\n' or ''
end

-- Profile files are user data once the initial seed has been installed.  Keep
-- release changes in a separate, verified staging area so the runtime can ask
-- the user whether to apply them without touching GUI/theme settings.
local profileUpdateState
local function profileUpdatePathIsSafe(path)
	if type(path) ~= 'string' then return false end
	local name, place = path:match('^cache/profile%-updates/[0-9a-zA-Z%-]+/profiles/([%a_]+)(%d+)%.txt$')
	return (name == 'default' or name == 'blatant') and place ~= nil
end

local function readProfileUpdateState()
	if not safeIsFile(profileUpdateStatePath) then
		return nil
	end
	local ok, contents = pcall(readfile, profileUpdateStatePath)
	if not ok or type(contents) ~= 'string' or contents == '' then
		return nil
	end
	local decodedOk, decoded = pcall(httpService.JSONDecode, httpService, contents)
	if not decodedOk or type(decoded) ~= 'table'
		or decoded.schemaVersion ~= 1
		or type(decoded.revision) ~= 'string'
		or type(decoded.status) ~= 'string'
		or tonumber(decoded.placeId) == nil
		or (decoded.status ~= 'pending' and decoded.status ~= 'installed'
			and decoded.status ~= 'applied' and decoded.status ~= 'skipped')
		or type(decoded.profiles) ~= 'table' then
		return nil
	end
	local validProfiles = {}
	for _, item in decoded.profiles do
		local itemName, itemPlace
		if type(item) == 'table' and type(item.path) == 'string' then
			itemName, itemPlace = item.path:match('^profiles/([%a_]+)(%d+)%.txt$')
		end
		if type(item) == 'table'
			and (itemName == 'default' or itemName == 'blatant')
			and itemPlace ~= nil
			and type(item.stagedPath) == 'string'
			and profileUpdatePathIsSafe(item.stagedPath)
			and type(item.bytes) == 'number'
			and type(item.sha256) == 'string'
			and #item.sha256 == 64
			and item.sha256:match('^[0-9a-f]+$') then
			table.insert(validProfiles, item)
		end
	end
	if #validProfiles == 0 then
		return nil
	end
	decoded.profiles = validProfiles
	return decoded
end

local function writeProfileUpdateState(state)
	if type(state) ~= 'table' then
		return false
	end
	local ok, encoded = pcall(httpService.JSONEncode, httpService, state)
	if not ok or type(encoded) ~= 'string' then
		return false
	end
	local writeOk = pcall(writefile, profileUpdateStatePath, encoded)
	return writeOk
end

profileUpdateState = readProfileUpdateState()
local profileUpdateApi = {}
function profileUpdateApi.Get()
	return profileUpdateState
end
function profileUpdateApi.Mark(status)
	if type(profileUpdateState) ~= 'table'
		or (status ~= 'pending' and status ~= 'installed'
			and status ~= 'applied' and status ~= 'skipped') then
		return false
	end
	profileUpdateState.status = status
	profileUpdateState.updatedAt = os.time and os.time() or nil
	return writeProfileUpdateState(profileUpdateState)
end
function profileUpdateApi.ReadStaged(item)
	if type(item) ~= 'table' or not profileUpdatePathIsSafe(item.stagedPath) then
		return nil
	end
	local ok, contents = pcall(readfile, folder..'/'..item.stagedPath)
	return ok and type(contents) == 'string' and contents or nil
end
shared.BadVapeProfileUpdate = profileUpdateApi

local function neutralizeRetiredRuntimePath(path)
	if not retiredRuntimePaths[path] then
		return false
	end
	local localPath = folder..'/'..path
	if not safeIsFile(localPath) then
		return true
	end

	local deleted = false
	if type(delfile) == 'function' then
		local ok, result = pcall(delfile, localPath)
		deleted = ok and result ~= false and not safeIsFile(localPath)
	end
	if not deleted then
		ensureParent(localPath)
		writefile(localPath, 'return false\n')
	end
	return true
end

ensureFolder(folder)
ensureFolder(folder..'/cache')
ensureFolder(folder..'/profiles')

local manifestBody = fetchPath('public-manifest.json')
local manifest
if manifestBody then
	local ok, decoded = pcall(httpService.JSONDecode, httpService, manifestBody)
	if ok then
		manifest = validateManifest(decoded)
		if not manifest then
			diagnostics.record('manifest_invalid', {bytes = #manifestBody, reason = 'schema validation failed'})
		end
	else
		diagnostics.record('manifest_invalid', {bytes = #manifestBody, reason = decoded})
	end
end

if manifest then
	local previousIndex, hasPreviousIndex = readCachedFileIndex()
	local profileSeeded = safeIsFile(profileSeedPath)
	local forceProfileOverride = not safeIsFile(profileOverridePath)
	local forceRuntimeRepair = not safeIsFile(runtimeRepairPath)
	local requiredPaths = requiredPublicPaths(manifest)
	local nextIndex = copyFileIndex(previousIndex)
	local manifestPaths = {}
	local pending = {}
	local manifestEntries = {}
	local profilePlaceAliases = {
		[8444591321] = 6872274481,
		[8560631822] = 6872274481,
		[117398147513099] = 17625359962,
		[133215910299950] = 17625359962,
		[71874690745115] = 17625359962,
		[129604661913557] = 17625359962,
	}
	local currentProfilePlace = profilePlaceAliases[tonumber(game.PlaceId)] or tonumber(game.PlaceId)
	local profileUpdateForRevision = false
	local profileUpdateCompleted = false
	local requiredCount = 0
	for _ in requiredPaths do requiredCount += 1 end
	diagnostics.record('manifest_accepted', {
		cachedRevision = readCachedRevision() or 'none',
		files = #manifest.files,
		forceProfileOverride = forceProfileOverride,
		forceRuntimeRepair = forceRuntimeRepair,
		hasPreviousIndex = hasPreviousIndex,
		requiredFiles = requiredCount,
		revision = manifest.revision,
	})
	for _, entry in ipairs(manifest.files) do
		manifestPaths[entry.path] = true
		manifestEntries[entry.path] = entry
	end
	if profileUpdateState
		and profileUpdateState.revision == manifest.revision
		and tonumber(profileUpdateState.placeId) == currentProfilePlace then
		profileUpdateCompleted = profileUpdateState.status == 'installed'
			or profileUpdateState.status == 'applied'
			or profileUpdateState.status == 'skipped'
		if profileUpdateState.status == 'pending' then
			profileUpdateForRevision = true
			for _, item in ipairs(profileUpdateState.profiles) do
				local entry = manifestEntries[item.path]
				local stagedOk, staged = pcall(readfile, folder..'/'..item.stagedPath)
				if not entry
					or entry.bytes ~= item.bytes
					or entry.sha256 ~= item.sha256
					or not stagedOk
					or not contentMatches(entry, staged) then
					profileUpdateForRevision = false
					break
				end
			end
			if not profileUpdateForRevision then
				profileUpdateState = nil
			end
		end
	end
	for _, entry in ipairs(manifest.files) do
		if requiredPaths[entry.path] then
			local localPath = folder..'/'..entry.path
			local seedProfile = seedProfilePaths[entry.path] == true
			local releaseProfile = releaseProfileOverridePaths[entry.path] == true
			local runtimeFile = entry.path:sub(1, 9) ~= 'profiles/'
			local profileFile = not runtimeFile
			local profileKind, profilePlace = entry.path:match('^profiles/([%a_]+)(%d+)%.txt$')
			if profileKind ~= 'default' and profileKind ~= 'blatant' then
				profileKind = nil
			end
			profilePlace = tonumber(profilePlace)
			local reasons = {}
			-- Read/hash each cached file once. The previous path performed the
			-- validation here and then repeated the same read/hash inside
			-- diagnostics.fileState, which was especially expensive with the pure
			-- Luau SHA-256 fallback.
			local observation = inspectCachedFile(localPath, entry)
			local localExists = observation.exists == true
			if not localExists then table.insert(reasons, 'missing') end
			if seedProfile and not profileSeeded then table.insert(reasons, 'profile-seed') end
			if releaseProfile and forceProfileOverride then table.insert(reasons, 'profile-override') end
			if runtimeFile and forceRuntimeRepair then table.insert(reasons, 'runtime-repair') end
			local needsDownload = #reasons > 0
			local localMatchesRelease = observation.matches == true
			local shouldStageProfile = profileFile
				and profileKind ~= nil
				and profilePlace == currentProfilePlace
				and localExists
				and profileSeeded
				and not forceProfileOverride
				and not localMatchesRelease
				and not profileUpdateForRevision
				and not profileUpdateCompleted
			local previous = previousIndex[entry.path]
			local releaseChanged = hasPreviousIndex
				and previous ~= nil
				and (previous.bytes ~= entry.bytes or previous.sha256 ~= entry.sha256)
			if shouldStageProfile and not releaseChanged then
				shouldStageProfile = false
			end
			if not profileFile and not needsDownload then
				needsDownload = not observation.readable or observation.matches ~= true
				if needsDownload then
					table.insert(reasons, observation.readable and 'content-mismatch' or 'read-failed')
				end
			end
			if not profileFile and not needsDownload then
				needsDownload = not hasPreviousIndex
					or not previous
					or previous.bytes ~= entry.bytes
					or previous.sha256 ~= entry.sha256
				if needsDownload then table.insert(reasons, 'index-mismatch') end
			end
			if shouldStageProfile then
				local stagedRelativePath = 'cache/profile-updates/'..manifest.revision..'/'..entry.path
				table.insert(pending, {
					entry = entry,
					localPath = folder..'/'..stagedRelativePath,
					reason = 'profile-update',
					profileUpdate = true,
					stagedRelativePath = stagedRelativePath,
				})
				nextIndex[entry.path] = {bytes = entry.bytes, sha256 = entry.sha256}
				diagnostics.fileState(entry.path, entry, 'pending:profile-update', observation)
				continue
			end
			-- Existing profile files are user-owned.  A release hash mismatch is
			-- intentionally kept out of the normal install queue; it is either
			-- staged above (for the active game's profiles) or preserved here.
			if profileFile and localExists and not needsDownload then
				nextIndex[entry.path] = {bytes = entry.bytes, sha256 = entry.sha256}
				diagnostics.fileState(entry.path, entry, 'user-preserved', observation)
				continue
			end
			if needsDownload then
				table.insert(pending, {
					entry = entry,
					localPath = localPath,
					reason = table.concat(reasons, ','),
				})
				diagnostics.fileState(entry.path, entry, 'pending:'..table.concat(reasons, ','), observation)
			else
				nextIndex[entry.path] = {bytes = entry.bytes, sha256 = entry.sha256}
				diagnostics.fileState(entry.path, entry, 'cached', observation)
			end
		end
	end
	local coldRuntimeInstall = not hasPreviousIndex or not profileSeeded
	if not coldRuntimeInstall then
		for _, pendingFile in ipairs(pending) do
			if not pendingFile.profileUpdate then
				coldRuntimeInstall = true
				break
			end
		end
	end
	shared.BadVapeColdStart = coldRuntimeInstall
	diagnostics.record('install_plan', {
		cached = requiredCount - #pending,
		coldStart = coldRuntimeInstall,
		pending = #pending,
	})
	if forceProfileOverride then
		for path in releaseProfileOverridePaths do
			if not manifestPaths[path] then
				diagnostics.record('profile_override_manifest_missing', {path = path})
				error('profile override manifest missing required file: '..path, 0)
			end
		end
	end
	local retiredPending = {}
	for path in retiredRuntimePaths do
		if not manifestPaths[path] then
			table.insert(retiredPending, path)
		end
	end
	table.sort(retiredPending)

	local downloaded = {}
	local function fetchPending(index)
		local pendingFile = pending[index]
		local contents = fetchPath(pendingFile.entry.path, function(body)
			return contentMatches(pendingFile.entry, body)
		end)
		downloaded[index] = contents or false
	end

	if #pending > 1
		and type(task) == 'table'
		and type(task.spawn) == 'function'
		and type(task.wait) == 'function' then
		local nextIndex = 1
		local workers = math.min(3, #pending)
		local finishedWorkers = 0
		for _ = 1, workers do
			task.spawn(function()
				while true do
					local index = nextIndex
					nextIndex += 1
					if index > #pending then
						break
					end
					fetchPending(index)
				end
				finishedWorkers += 1
			end)
		end
		repeat
			task.wait()
		until finishedWorkers == workers
	else
		for index = 1, #pending do
			fetchPending(index)
		end
	end

	for index, pendingFile in ipairs(pending) do
		if type(downloaded[index]) ~= 'string' then
			diagnostics.record('install_download_set_failed', {
				path = pendingFile.entry.path,
				reason = pendingFile.reason,
			})
			if safeIsFile(folder..'/os.luau') then
				warn('BadVape update download failed; using the unchanged cached public runtime.')
				diagnostics.record('installer_cache_fallback', {
					path = pendingFile.entry.path,
					reason = 'atomic download set incomplete',
				})
				return runCachedRuntime()
			end
			error('failed to download public runtime file: '..pendingFile.entry.path, 0)
		end
	end
	-- All network work succeeded before any cached runtime file is replaced.
	local stagedProfiles = {}
	for index, pendingFile in ipairs(pending) do
		local parentOk, parentError = pcall(ensureParent, pendingFile.localPath)
		if not parentOk then
			diagnostics.record('install_parent_failed', {error = parentError, path = pendingFile.entry.path})
			error('failed to prepare public runtime path: '..pendingFile.entry.path, 0)
		end
		local writeOk, writeError = pcall(writefile, pendingFile.localPath, downloaded[index])
		if not writeOk then
			diagnostics.record('install_write_failed', {error = writeError, path = pendingFile.entry.path})
			error('failed to install public runtime file: '..pendingFile.entry.path, 0)
		end
		local readOk, installed = pcall(readfile, pendingFile.localPath)
		if not readOk or not contentMatches(pendingFile.entry, installed) then
			diagnostics.record('install_verify_failed', {
				bytes = readOk and type(installed) == 'string' and #installed or 0,
				error = readOk and 'content mismatch' or installed,
				path = pendingFile.entry.path,
			})
			error('failed to verify installed public runtime file: '..pendingFile.entry.path, 0)
		end
		nextIndex[pendingFile.entry.path] = {
			bytes = pendingFile.entry.bytes,
			sha256 = pendingFile.entry.sha256,
		}
		if pendingFile.profileUpdate then
			local profileName = pendingFile.entry.path:match('^profiles/([%a_]+)')
			table.insert(stagedProfiles, {
				name = profileName,
				path = pendingFile.entry.path,
				stagedPath = pendingFile.stagedRelativePath,
				bytes = pendingFile.entry.bytes,
				sha256 = pendingFile.entry.sha256,
			})
		end
		local installedObservation = inspectFileContents(pendingFile.entry, readOk, installed)
		installedObservation.exists = readOk and type(installed) == 'string'
		diagnostics.fileState(pendingFile.entry.path, pendingFile.entry, 'installed', installedObservation)
	end
	for _, path in ipairs(retiredPending) do
		local ok, result = pcall(neutralizeRetiredRuntimePath, path)
		diagnostics.record('retired_runtime_neutralized', {
			error = ok and 'none' or result,
			path = path,
			success = ok and result == true,
		})
		if not ok or result ~= true then
			error('failed to neutralize retired runtime file: '..path, 0)
		end
	end
	-- Persist the staged profile state before advancing the manifest index. If a
	-- profile-state write is interrupted, defer the commit markers so the next
	-- run can safely retry staging instead of believing it was already handled.
	local profileStateReady = true
	if #stagedProfiles > 0 then
		profileUpdateState = {
			schemaVersion = 1,
			revision = manifest.revision,
			placeId = currentProfilePlace,
			status = 'pending',
			profiles = stagedProfiles,
		}
		if not writeProfileUpdateState(profileUpdateState) then
			profileStateReady = false
			diagnostics.record('profile_update_state_write_failed', {revision = manifest.revision})
		else
			diagnostics.record('profile_update_staged', {
				count = #stagedProfiles,
				revision = manifest.revision,
			})
		end
	end
	if profileStateReady then
		writefile(fileIndexPath, encodeFileIndex(nextIndex))
		writefile(revisionPath, manifest.revision)
		if releaseRef:match('^[0-9a-f]+$') and #releaseRef == 40 then
			writefile(releaseRefPath, releaseRef)
		else
			-- A branch fallback means an older immutable ref is not a valid repair
			-- source. Main.lua intentionally treats this marker as the live branch.
			writefile(releaseRefPath, 'main')
		end
		writefile(profileSeedPath, manifest.revision)
		if forceProfileOverride then
			writefile(profileOverridePath, manifest.revision)
		end
		-- Fallback downloads use this branch; user profile/config files remain untouched.
		writefile(folder..'/profiles/commit.txt', branch)
		writefile(runtimeRepairPath, manifest.revision)
	else
		diagnostics.record('installer_commit_deferred', {revision = manifest.revision})
	end
	diagnostics.record('installer_committed', {
		committed = profileStateReady,
		installed = #pending,
		releaseRef = releaseRef,
		revision = manifest.revision,
		runtimeRepair = forceRuntimeRepair,
	})
elseif not safeIsFile(folder..'/os.luau') then
	diagnostics.record('installer_manifest_unavailable', {
		reason = manifestBody and 'invalid public manifest' or 'failed to download public manifest',
	})
	error(manifestBody and 'invalid public manifest' or 'failed to download public manifest', 0)
else
	warn('BadVape update check failed; using the cached public runtime.')
	diagnostics.record('installer_cache_fallback', {reason = 'manifest unavailable'})
end

return runCachedRuntime()
