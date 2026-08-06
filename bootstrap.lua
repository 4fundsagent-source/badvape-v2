--!nocheck
-- Compact public bootstrap with an executor-request fallback.

local credential = ...
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
		local status = ok and type(response) == 'table'
			and tonumber(response.StatusCode or response.Status) or nil
		local body = ok and type(response) == 'table'
			and (response.Body or response.body) or nil
		if (status == nil or status == 0 or status == 200 or status == 201)
			and type(body) == 'string'
			and body ~= ''
			and body ~= '404: Not Found' then
			return body
		end
	end
	return nil
end

local releaseRef = '73b6f5fd22615ecb0399a5435f458d1562417cfc'
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
if hasShared then shared.BadVapeReleaseRef = releaseRef end
local result = table.pack(pcall(bootstrap, {Key = credential}, {requestAdapters = adapters}))
if hasShared then shared.BadVapeReleaseRef = previousReleaseRef end
if not result[1] then error(result[2], 0) end
return table.unpack(result, 2, result.n)
