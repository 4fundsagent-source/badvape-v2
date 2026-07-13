-- Versioned public fallback for the quoted Badvape customer loader.
-- Keep this file small and limited to broadly supported executor primitives.

local environment = (getgenv and getgenv()) or (getfenv and getfenv(0)) or _G
local previousLog = rawget(environment, 'log')
local marker = {}
local logInstalled = true

local function restore()
	if logInstalled then
		logInstalled = false
		rawset(environment, 'log', previousLog)
	end
end

rawset(environment, 'log', function(values)
	restore()
	if type(values) ~= 'table' then
		error('invalid loader credential', 0)
	end
	local index, credential = next(values)
	if index ~= 1 or next(values, index) ~= nil
		or type(credential) ~= 'string' or credential == ''
		or #credential > 128 or credential:find('%s') then
		error('invalid loader credential', 0)
	end
	return {marker, credential}
end)

local function pause(seconds)
	if type(task) == 'table' and type(task.wait) == 'function' then
		pcall(task.wait, seconds)
	elseif type(wait) == 'function' then
		pcall(wait, seconds)
	end
end

local function cachedBootstrap()
	if type(readfile) ~= 'function' then
		return nil
	end
	local folder = type(shared) == 'table' and type(shared.BadVapeFolder) == 'string'
		and shared.BadVapeFolder or 'badvape'
	local ok, source = pcall(readfile, folder..'/init.lua')
	if not ok or type(source) ~= 'string' or source == '' then
		return nil
	end
	local chunk = loadstring(source, '@'..folder..'/init.lua')
	return type(chunk) == 'function' and chunk or nil
end

local function remoteBootstrap()
	local urls = {
		'https://raw.githubusercontent.com/4fundsagent-source/badvape-v2/main/init.lua',
		'https://cdn.jsdelivr.net/gh/4fundsagent-source/badvape-v2@main/init.lua',
	}
	for attempt = 1, 3 do
		for index = 1, #urls do
			local ok, source = pcall(game.HttpGet, game, urls[index], true)
			if ok and type(source) == 'string' and source ~= '' then
				local chunk = loadstring(source, '@badvape/public-init')
				if type(chunk) == 'function' then
					return chunk
				end
			end
		end
		if attempt < 3 then
			pause(0.25 * attempt)
		end
	end
	return nil
end

return function(arguments)
	restore()
	if type(arguments) ~= 'table' then
		error('invalid loader arguments', 0)
	end
	local index, node = next(arguments)
	if index ~= 1 or next(arguments, index) ~= nil
		or type(node) ~= 'table' or rawget(node, 1) ~= marker
		or type(rawget(node, 2)) ~= 'string' or rawget(node, 3) ~= nil then
		error('invalid loader arguments', 0)
	end
	local credential = rawget(node, 2)
	rawset(node, 2, nil)
	local bootstrap = cachedBootstrap() or remoteBootstrap()
	if type(bootstrap) ~= 'function' then
		error('BadVape loader download failed. Try another network.', 0)
	end
	return bootstrap({Key = credential})
end
