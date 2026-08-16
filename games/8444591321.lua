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

-- Cache the compiled protected artifact for warm reloads/teleports.  The
-- release/ref and source edge bytes invalidate the entry when the deployed
-- artifact changes without hashing the full ciphertext on every run.
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

-- Keep the route's normal return/exception behavior unchanged.  The fresh
-- BedWars-state check is useful only in the isolated developer harness; doing
-- it for every caller breaks ordinary redirect contracts that intentionally
-- use a tiny canonical stub (and can also call a missing `warn`).
local runtimeEnvironment = (type(getgenv) == 'function' and getgenv()) or _G
local developerRouteCheck = type(shared) == 'table' and shared.BadVapeDeveloper == true
local previousBedwars = developerRouteCheck and type(runtimeEnvironment) == 'table'
	and runtimeEnvironment.BadVapeBedwars or nil
local ok, result = xpcall(function()
	return chunk(license)
end, function(err)
		if type(debug) == 'table' and type(debug.traceback) == 'function' then
			return debug.traceback(tostring(err), 2)
		end
		return tostring(err)
	end)
if not ok then
	if type(warn) == 'function' then
		warn('[BadVape route] canonical BedWars source failed: '..tostring(result))
	end
	return false
end
if result == false then
	return false
end
local currentBedwars = type(runtimeEnvironment) == 'table'
	and runtimeEnvironment.BadVapeBedwars or nil
if developerRouteCheck and (type(currentBedwars) ~= 'table' or currentBedwars == previousBedwars) then
	if type(warn) == 'function' then
		warn('[BadVape route] canonical BedWars source returned without fresh BedWars state')
	end
	return false
end
return result
