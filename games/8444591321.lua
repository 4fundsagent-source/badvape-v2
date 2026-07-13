local license = ...
local vape = shared and shared.vape
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

return chunk(license)
