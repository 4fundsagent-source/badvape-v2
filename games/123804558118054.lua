
local vape = shared.vape
local loadstring = function(...)
	local res, err = loadstring(...)
	if err and vape then
		vape:CreateNotification('BadVape', 'Failed to load : ' .. err, 30, 'alert')
	end
	return res
end
local isfile = isfile or function(file)
	local suc, res = pcall(function()
		return readfile(file)
	end)
	return suc and res ~= nil and res ~= '' 
end
local function downloadFile(path, func)
	if not isfile(path) then
		if shared.VapeDeveloper then
			error('Missing local BadVape file: '..path)
		end

		local suc, res = pcall(function()
			return game:HttpGet('https://raw.githubusercontent.com/4fundsagent-source/badvape-v2/'.. readfile('badvape/profiles/commit.txt').. '/'.. select(1, path:gsub('badvape/', '')), true)
		end)
		if not suc or res == '404: Not Found' then
			error(res)
		end
		if path:find('.lua') then
			res = '--This watermark is used to delete the file if its cached, remove it to make the file persist after vape updates.\n'.. res
		end
		writefile(path, res)
	end
	return (func or readfile)(path)
end

vape.Place = 5938036553
if isfile('badvape/games/' .. vape.Place .. '.lua') then
	loadstring(readfile('badvape/games/' .. vape.Place .. '.lua'), tostring(vape.Place))()
else
	if not shared.VapeDeveloper then
		local suc, res = pcall(function()
			return game:HttpGet('https://raw.githubusercontent.com/4fundsagent-source/badvape-v2/'.. readfile('badvape/profiles/commit.txt').. '/games/'.. vape.Place.. '.lua', true)
		end)
		if suc and res ~= '404: Not Found' then
			loadstring(downloadFile('badvape/games/' .. vape.Place .. '.lua'), tostring(vape.Place))()
		end
	end
end
