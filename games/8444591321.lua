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

local compileOk, chunk = pcall(loadstring, source, tostring(vape.Place))
if not compileOk or type(chunk) ~= 'function' then
	return false
end

-- Developer-only route diagnostics: the canonical source historically caught
-- its own bootstrap errors and returned nil, which made this alias look like
-- a successful game-module load while leaving the GUI-only runtime active.
-- Keep the alias behavior unchanged on success, but expose a thrown error or
-- an incomplete fresh BedWars state during source testing.
local runtimeEnvironment = (type(getgenv) == 'function' and getgenv()) or _G
local previousBedwars = type(runtimeEnvironment) == 'table'
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
	warn('[BadVape route] canonical BedWars source failed: '..tostring(result))
	return false
end
if result == false then
	return false
end
local currentBedwars = type(runtimeEnvironment) == 'table'
	and runtimeEnvironment.BadVapeBedwars or nil
if type(currentBedwars) ~= 'table' or currentBedwars == previousBedwars then
	warn('[BadVape route] canonical BedWars source returned without fresh BedWars state')
	return false
end
return result
