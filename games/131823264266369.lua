local license = ...
local id = 131823264266369
if game.PlaceId ~= id then
	return
end

local function exists(path)
	if isfile then
		return isfile(path)
	end

	local success, result = pcall(function()
		return readfile(path)
	end)
	return success and result ~= nil and result ~= ''
end

local p = 'badvape/games/protected6872274481.lua'
if not exists(p) and exists('newbadvape/games/protected6872274481.lua') then
	p = 'newbadvape/games/protected6872274481.lua'
end

if not exists(p) then
	return
end

local chunk = loadstring(readfile(p), tostring(game.PlaceId))
if not chunk then
	return
end

pcall(chunk, license)
