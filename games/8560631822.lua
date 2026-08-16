local license = ...
local vape = shared and shared.BadVape
if type(vape) ~= 'table' then
	return false
end

vape.Place = 6872274481
local path = 'badvape/games/6872274481.lua'
local source

local cachedOk, cached = pcall(readfile, path)
if cachedOk and type(cached) == 'string' and cached ~= '' then
	source = cached
end

if not source and shared and type(shared.BadVapeDownloadFile) == 'function' then
	local downloadOk, downloaded = pcall(shared.BadVapeDownloadFile, path)
	if downloadOk and type(downloaded) == 'string' and downloaded ~= '' then
		source = downloaded
	end
end

if type(source) ~= 'string' or source == '404: Not Found' or type(loadstring) ~= 'function' then
	return false
end

local routeCache, routeCacheKey, chunk
if type(shared) == 'table' and shared.BadVapeProtectedRouteCacheDisabled ~= true then
	routeCache = shared.BadVapeProtectedRouteChunkCache
	if type(routeCache) ~= 'table' then
		routeCache = {}
		shared.BadVapeProtectedRouteChunkCache = routeCache
	end
	local releaseRef = type(shared.BadVapeReleaseRef) == 'string'
		and shared.BadVapeReleaseRef or 'main'
	routeCacheKey = path..':'..releaseRef..':'..tostring(#source)
		..':'..source:sub(1, 32)..':'..source:sub(-32)
	local cachedChunk = routeCache[routeCacheKey]
	if type(cachedChunk) == 'function' then chunk = cachedChunk end
end
if type(chunk) ~= 'function' then
	local compileOk, compiled = pcall(loadstring, source, tostring(vape.Place))
	if not compileOk or type(compiled) ~= 'function' then
		return false
	end
	chunk = compiled
	if routeCache then
		for key in routeCache do
			if key ~= routeCacheKey then routeCache[key] = nil end
		end
		routeCache[routeCacheKey] = chunk
	end
end

return chunk(license)
