--!nocheck
-- Compact public bootstrap with an executor-request fallback.

local credential, requestedReleaseRef = ...
if type(credential) ~= 'string'
	or #credential < 1
	or #credential > 128
	or credential:find('%s') then
	error('invalid BadVape credential', 0)
end

local environments, seenEnvironments = {}, {}
local function addEnvironment(candidate)
	if type(candidate) == 'table' and not seenEnvironments[candidate] then
		seenEnvironments[candidate] = true
		table.insert(environments, candidate)
	end
end
if type(getfenv) == 'function' then
	local ok, environment = pcall(getfenv, 0)
	if ok then addEnvironment(environment) end
end
if type(getgenv) == 'function' then
	local ok, environment = pcall(getgenv)
	if ok then addEnvironment(environment) end
end
addEnvironment(type(_G) == 'table' and _G or nil)

-- Queue-on-teleport can execute before the destination place has mounted its
-- client tree. Do not fetch or run the installer until Roblox has finished
-- loading, the local player's basic script containers exist, and FloodCraft's
-- own client bootstrap has published its readiness marker.
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
	if not apiAvailable then
		-- Keep the standalone bootstrap harness compatible; Roblox always exposes
		-- these methods, so production execution still takes the strict path.
		return true
	end

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

local adapters, seenAdapters = {}, {}
local function addAdapter(candidate)
	if type(candidate) == 'function' and not seenAdapters[candidate] then
		seenAdapters[candidate] = true
		table.insert(adapters, candidate)
	end
end
for _, environment in ipairs(environments) do
	local httpLibrary = rawget(environment, 'http')
	addAdapter(type(httpLibrary) == 'table' and rawget(httpLibrary, 'request') or nil)
	addAdapter(rawget(environment, 'request'))
	addAdapter(rawget(environment, 'http_request'))
	for _, namespace in ipairs({'syn', 'fluxus', 'krnl'}) do
		local library = rawget(environment, namespace)
		addAdapter(type(library) == 'table' and rawget(library, 'request') or nil)
	end
end

local function fetch(url)
	if type(game) == 'userdata' or type(game) == 'table' then
		local ok, body = pcall(game.HttpGet, game, url, true)
		if ok and type(body) == 'string' and body ~= '' and body ~= '404: Not Found' then
			return body
		end
	end
	for _, adapter in ipairs(adapters) do
		local ok, response = pcall(adapter, {Url = url, Method = 'GET'})
		local responseType = ok and type(response) or nil
		local status = responseType == 'string' and 200
			or (responseType == 'table'
				and tonumber(response.StatusCode or response.Status
					or response.status_code or response.status) or nil)
		local body = responseType == 'string' and response
			or (responseType == 'table' and (response.Body or response.body) or nil)
		if (status == nil or status == 0 or status == 200 or status == 201)
			and type(body) == 'string'
			and body ~= ''
			and body ~= '404: Not Found' then
			return body
		end
	end
	return nil
end

-- Keep the bootstrap and installer on one reviewed immutable snapshot.  The
-- ref is advanced together with the public runtime release.
local releaseRef = '88135d5d6d6b9e6b7fcccc23db31c7919322020d'
if requestedReleaseRef ~= nil then
	if type(requestedReleaseRef) ~= 'string'
		or not requestedReleaseRef:match('^[0-9a-f]+$')
		or #requestedReleaseRef ~= 40 then
		error('invalid BadVape release ref', 0)
	end
	releaseRef = requestedReleaseRef
end
local bootstrap, compileError
for _, url in ipairs({
	'https://raw.githubusercontent.com/4fundsagent-source/badvape-v2/'..releaseRef..'/init.lua',
	'https://cdn.jsdelivr.net/gh/4fundsagent-source/badvape-v2@'..releaseRef..'/init.lua',
}) do
	local source = fetch(url)
	if source then
		bootstrap, compileError = loadstring(source, '@badvape/public-init')
		if type(bootstrap) == 'function' then break end
	end
end
if type(bootstrap) ~= 'function' then
	error(compileError or 'BadVape bootstrap download failed', 0)
end

local hasShared = type(shared) == 'table'
local previousReleaseRef = hasShared and shared.BadVapeReleaseRef or nil
if hasShared then
	shared.BadVapeReleaseRef = releaseRef
end
local result = table.pack(pcall(bootstrap, {Key = credential}, {requestAdapters = adapters}, releaseRef))
if hasShared then shared.BadVapeReleaseRef = previousReleaseRef end
if not result[1] then error(result[2], 0) end
return table.unpack(result, 2, result.n)
