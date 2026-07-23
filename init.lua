-- BadVape public runtime installer.
-- The manifest is an explicit allowlist; private game source is never part of it.

local forwardedLicense = ...
local httpService = game:GetService('HttpService')

local owner = '4fundsagent-source'
local repo = 'badvape-v2'
local branch = 'main'
local folder = shared.BadVapeFolder or 'badvape'
local diagnosticsPath = folder..'/badvape-debug.txt'

-- Keep one self-contained report in the workspace. It deliberately excludes
-- credentials, device identifiers, auth tokens, request headers and contents.
local diagnosticLines = {
	'BadVape diagnostics v1',
	'privacy=credentials, device identifiers, auth tokens, headers and file contents are not recorded',
}
local diagnosticStarted = type(os) == 'table' and type(os.clock) == 'function' and os.clock() or 0
local forwardedSecret = type(forwardedLicense) == 'table' and forwardedLicense.Key
forwardedSecret = type(forwardedSecret) == 'string' and forwardedSecret or nil

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

local function flushDiagnostics()
	pcall(function()
		if not isfolder(folder) then makefolder(folder) end
		writefile(diagnosticsPath, table.concat(diagnosticLines, '\n')..'\n')
	end)
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
	flushDiagnostics()
end
diagnostics.redact = diagnosticValue
shared.BadVapeDiagnostics = diagnostics
flushDiagnostics()

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
local releaseRefPath = folder..'/cache/public-release-ref.txt'
local runtimeRepairPath = folder..'/cache/runtime-repair-20260716-v1.txt'

shared.BadVapeFolder = folder

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
	credentialKind = forwardedSecret and (forwardedSecret:match('^BV%-%u%-') and 'license' or 'uid') or 'missing',
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
local capabilitySyn = type(capabilityEnvironment.syn) == 'table' and capabilityEnvironment.syn
	or type(syn) == 'table' and syn or nil
local capabilityFluxus = type(capabilityEnvironment.fluxus) == 'table' and capabilityEnvironment.fluxus
	or type(fluxus) == 'table' and fluxus or nil
local capabilityKrnl = type(capabilityEnvironment.krnl) == 'table' and capabilityEnvironment.krnl
	or type(krnl) == 'table' and krnl or nil
local capabilityCrypt = type(capabilityEnvironment.crypt) == 'table' and capabilityEnvironment.crypt
	or type(crypt) == 'table' and crypt or nil
local capabilityCrypto = type(capabilityEnvironment.crypto) == 'table' and capabilityEnvironment.crypto
	or type(crypto) == 'table' and crypto or nil
local requestDirect = type(capabilityEnvironment.request) == 'function'
	or type(capabilityEnvironment.http_request) == 'function'
	or type(request) == 'function'
	or type(http_request) == 'function'
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

local function safeIsFile(path)
	if isfile then
		return isfile(path)
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
	local osChunk, loadError = loadstring(osSource, folder..'/os.luau')
	if type(osChunk) ~= 'function' then
		diagnostics.record('runtime_compile_failed', {error = loadError or 'rejected', path = osPath})
		error(loadError or 'BadVape runtime rejected', 0)
	end
	local function traceError(value)
		if type(debug) == 'table' and type(debug.traceback) == 'function' then
			local ok, trace = pcall(debug.traceback, tostring(value), 2)
			if ok and type(trace) == 'string' then return trace end
		end
		return tostring(value)
	end
	local runtimeResult = table.pack(xpcall(function()
		return osChunk(forwardedLicense)
	end, traceError))
	if not runtimeResult[1] then
		diagnostics.record('runtime_execution_failed', {error = runtimeResult[2], path = osPath})
		error(runtimeResult[2], 0)
	end
	diagnostics.record('runtime_execution_complete', {path = osPath, resultType = typeof(runtimeResult[2])})
	return table.unpack(runtimeResult, 2, runtimeResult.n)
end

local localWorkspace = shared.BadVapeDeveloper == true and safeIsFile(folder..'/os.luau')
if not localWorkspace and safeIsFile(folder..'/profiles/commit.txt') then
	local markerOk, marker = pcall(readfile, folder..'/profiles/commit.txt')
	localWorkspace = markerOk
		and type(marker) == 'string'
		and marker:match('^%s*(.-)%s*$') == 'local'
end
if localWorkspace then
	diagnostics.record('installer_local_workspace', {folder = folder})
	return runCachedRuntime()
end
if shared.BadVapeDeveloper == true then
	shared.BadVapeDeveloper = nil
end

local releaseRef, releaseStrategy
for attempt = 1, 3 do
	local refOk, refBody = pcall(game.HttpGet, game,
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
	['libraries/prediction.lua'] = true,
	['libraries/string.lua'] = true,
	['profiles/features.json'] = true,
	['profiles/packages.json'] = true,
}

local gameDependencyPaths = {
	[6872274481] = {
		['libraries/cheatenginelib.lua'] = true,
	},
	[8444591321] = {
		['games/6872274481.lua'] = true,
		['libraries/cheatenginelib.lua'] = true,
	},
	[8560631822] = {
		['games/6872274481.lua'] = true,
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
	local ok, body = pcall(game.HttpGet, game, url, true)
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
local function contentMatches(entry, contents)
	if type(contents) ~= 'string' or #contents ~= entry.bytes then
		return false
	end
	if hashCandidate then
		local ok, digest = invokeHash(hashCandidate, hashOwner, hashMode, contents, hashUseOwner)
		return ok and validDigest(digest) and digest:lower() == entry.sha256
	end
	return true
end

function diagnostics.fileState(relativePath, entry, state)
	relativePath = relativePath:gsub('\\', '/')
	local path
	if relativePath:sub(1, #folder + 1) == folder..'/' then
		path = relativePath
	else
		relativePath = relativePath:gsub('^badvape/', '', 1)
		path = folder..'/'..relativePath
	end
	local exists = safeIsFile(path)
	local fields = {
		exists = exists,
		expectedBytes = entry and entry.bytes or 'unknown',
		expectedSha256 = entry and entry.sha256 or 'unknown',
		path = path,
		state = state or 'observed',
		validation = hashCandidate and 'sha256+size' or 'size-only',
	}
	if exists then
		local ok, contents = pcall(readfile, path)
		fields.readable = ok and type(contents) == 'string'
		if fields.readable then
			fields.bytes = #contents
			fields.matches = entry and contentMatches(entry, contents) or 'unknown'
			if hashCandidate then
				local hashOk, digest = invokeHash(hashCandidate, hashOwner, hashMode, contents, hashUseOwner)
				fields.sha256 = hashOk and validDigest(digest) and digest:lower() or 'hash-failed'
			end
		else
			fields.error = contents
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
		if requiredPaths[entry.path] then
			local localPath = folder..'/'..entry.path
			local seedProfile = seedProfilePaths[entry.path] == true
			local releaseProfile = releaseProfileOverridePaths[entry.path] == true
			local runtimeFile = entry.path:sub(1, 9) ~= 'profiles/'
			local reasons = {}
			if not safeIsFile(localPath) then table.insert(reasons, 'missing') end
			if seedProfile and not profileSeeded then table.insert(reasons, 'profile-seed') end
			if releaseProfile and forceProfileOverride then table.insert(reasons, 'profile-override') end
			if runtimeFile and forceRuntimeRepair then table.insert(reasons, 'runtime-repair') end
			local needsDownload = #reasons > 0
			if not needsDownload and not seedProfile then
				local ok, cached = pcall(readfile, localPath)
				needsDownload = not ok or not contentMatches(entry, cached)
				if needsDownload then table.insert(reasons, ok and 'content-mismatch' or 'read-failed') end
			end
			if not needsDownload and not seedProfile then
				local previous = previousIndex[entry.path]
				needsDownload = not hasPreviousIndex
					or not previous
					or previous.bytes ~= entry.bytes
					or previous.sha256 ~= entry.sha256
				if needsDownload then table.insert(reasons, 'index-mismatch') end
			end
			if needsDownload then
				table.insert(pending, {
					entry = entry,
					localPath = localPath,
					reason = table.concat(reasons, ','),
				})
				diagnostics.fileState(entry.path, entry, 'pending:'..table.concat(reasons, ','))
			else
				nextIndex[entry.path] = {bytes = entry.bytes, sha256 = entry.sha256}
				diagnostics.fileState(entry.path, entry, 'cached')
			end
		end
	end
	diagnostics.record('install_plan', {cached = requiredCount - #pending, pending = #pending})
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
		diagnostics.fileState(pendingFile.entry.path, pendingFile.entry, 'installed')
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
	diagnostics.record('installer_committed', {
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
