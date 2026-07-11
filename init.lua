-- BadVape public runtime installer.
-- The manifest is an explicit allowlist; private game source is never part of it.

local forwardedLicense = ...
local httpService = game:GetService('HttpService')

local owner = '4fundsagent-source'
local repo = 'badvape-v2'
local branch = 'main'
local folder = shared.BadVapeFolder or 'badvape'
local baseUrl = 'https://raw.githubusercontent.com/'..owner..'/'..repo..'/'..branch..'/'
local manifestUrl = baseUrl..'public-manifest.json'
local revisionPath = folder..'/cache/public-revision.txt'
local fileIndexPath = folder..'/cache/public-file-index.txt'

shared.BadVapeFolder = folder

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
		error('missing cached BadVape runtime', 0)
	end
	local osChunk, loadError = loadstring(readfile(osPath), folder..'/os.luau')
	if type(osChunk) ~= 'function' then
		error(loadError or 'BadVape runtime rejected', 0)
	end
	return osChunk(forwardedLicense)
end

local localWorkspace = shared.VapeDeveloper == true
if not localWorkspace and safeIsFile(folder..'/profiles/commit.txt') then
	local markerOk, marker = pcall(readfile, folder..'/profiles/commit.txt')
	localWorkspace = markerOk
		and type(marker) == 'string'
		and marker:match('^%s*(.-)%s*$') == 'local'
end
if localWorkspace then
	return runCachedRuntime()
end

local publicGamePaths = {
	['games/11156779721.lua'] = true,
	['games/123804558118054.lua'] = true,
	['games/131465939650733.lua'] = true,
	['games/13246639586.lua'] = true,
	['games/135564683255158.lua'] = true,
	['games/139566161526375.lua'] = true,
	['games/142823291.lua'] = true,
	['games/155615604.lua'] = true,
	['games/5938036553.lua'] = true,
	['games/606849621.lua'] = true,
	['games/6872265039.lua'] = true,
	['games/77790193039862.lua'] = true,
	['games/80041634734121.lua'] = true,
	['games/8542259458.lua'] = true,
	['games/8542275097.lua'] = true,
	['games/8592115909.lua'] = true,
	['games/8768229691.lua'] = true,
	['games/893973440.lua'] = true,
	['games/8951451142.lua'] = true,
	['games/131823264266369.lua'] = true,
	['games/8444591321.lua'] = true,
	['games/8560631822.lua'] = true,
	['games/protected6872274481.lua'] = true,
	['games/universal.lua'] = true,
}
local publicLibraryPaths = {
	['libraries/badvape-theme.lua'] = true,
	['libraries/base64.lua'] = true,
	['libraries/cheatenginelib.lua'] = true,
	['libraries/drawing.lua'] = true,
	['libraries/entity.lua'] = true,
	['libraries/hash.lua'] = true,
	['libraries/prediction.lua'] = true,
	['libraries/string.lua'] = true,
	['libraries/vm.lua'] = true,
}

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
	if publicLibraryPaths[path] then
		return true
	end
	if path:match('^assets/new/[^/]+%.png$') or path:match('^assets/old/[^/]+%.png$') then
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
	if not ok or type(body) ~= 'string' or body == '' or body == '404: Not Found' then
		return nil
	end
	return body
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
		bytes = tonumber(bytes)
		if not path or not isPublicPath(path) or not bytes or #sha256 ~= 64 then
			return {}, false
		end
		index[path] = {bytes = bytes, sha256 = sha256}
	end
	return index, true
end

local function encodeFileIndex(manifest)
	local lines = {}
	for index, entry in ipairs(manifest.files) do
		lines[index] = entry.path..'\t'..entry.bytes..'\t'..entry.sha256
	end
	return table.concat(lines, '\n')..'\n'
end

ensureFolder(folder)
ensureFolder(folder..'/cache')
ensureFolder(folder..'/profiles')

local manifestBody = fetch(manifestUrl)
local manifest
if manifestBody then
	local ok, decoded = pcall(httpService.JSONDecode, httpService, manifestBody)
	if ok then
		manifest = validateManifest(decoded)
	end
end

if manifest then
	local previousIndex, hasPreviousIndex = readCachedFileIndex()
	local revisionChanged = readCachedRevision() ~= manifest.revision
	local pending = {}
	for _, entry in ipairs(manifest.files) do
		local localPath = folder..'/'..entry.path
		local needsDownload = not safeIsFile(localPath)
		if not needsDownload then
			local ok, cached = pcall(readfile, localPath)
			needsDownload = not ok or not contentMatches(entry, cached)
		end
		if not needsDownload and revisionChanged then
			local previous = previousIndex[entry.path]
			needsDownload = not hasPreviousIndex
				or not previous
				or previous.bytes ~= entry.bytes
				or previous.sha256 ~= entry.sha256
		end
		if needsDownload then
			table.insert(pending, {entry = entry, localPath = localPath})
		end
	end

	local downloaded = {}
	local function fetchPending(index)
		local pendingFile = pending[index]
		local contents = fetch(baseUrl..pendingFile.entry.path)
		if contentMatches(pendingFile.entry, contents) then
			downloaded[index] = contents
		else
			downloaded[index] = false
		end
	end

	if #pending > 1
		and type(task) == 'table'
		and type(task.spawn) == 'function'
		and type(task.wait) == 'function' then
		local nextIndex = 1
		local workers = math.min(6, #pending)
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
			error('failed to download public runtime file: '..pendingFile.entry.path, 0)
		end
	end
	-- All network work succeeded before any cached runtime file is replaced.
	for index, pendingFile in ipairs(pending) do
		ensureParent(pendingFile.localPath)
		writefile(pendingFile.localPath, downloaded[index])
	end
	writefile(fileIndexPath, encodeFileIndex(manifest))
	writefile(revisionPath, manifest.revision)
	-- Fallback downloads use this branch; user profile/config files remain untouched.
	writefile(folder..'/profiles/commit.txt', branch)
elseif not safeIsFile(folder..'/os.luau') then
	error(manifestBody and 'invalid public manifest' or 'failed to download public manifest', 0)
else
	warn('BadVape update check failed; using the cached public runtime.')
end

return runCachedRuntime()
