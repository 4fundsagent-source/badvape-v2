local vape = shared.vape
vape.Place = 6872274481

local path = 'badvape/games/protected6872274481.lua'
if isfile(path) then
	local chunk = loadstring(readfile(path), tostring(game.PlaceId))
	if chunk then
		return chunk()
	end
end

return false
