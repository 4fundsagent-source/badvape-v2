local function getRuntimeFolder()
	if shared.BadVapeFolder then
		return shared.BadVapeFolder
	end

	if debug and debug.info then
		local success, source = pcall(debug.info, 1, 's')
		if success and type(source) == 'string' then
			source = source:gsub('\\', '/')
			local sourceFolder = source:match('^@?(.+)/os%.luau$') or source:match('["\']([^"\']+)/os%.luau["\']')
			if sourceFolder and sourceFolder ~= '' then
				return sourceFolder
			end
		end
	end

	return 'badvape'
end

local function resolveRuntimeEnvironment()
	if type(getgenv) == 'function' then
		local ok, environment = pcall(getgenv)
		if ok and type(environment) == 'table' then
			return environment
		end
	end
	if type(getfenv) == 'function' then
		local ok, environment = pcall(getfenv, 0)
		if ok and type(environment) == 'table' then
			return environment
		end
	end
	if type(_G) == 'table' then
		return _G
	end
	return {}
end

local folder = getRuntimeFolder()
local runtimeEnvironment = resolveRuntimeEnvironment()
local previousRuntimeRestore = shared.BadVapeRestoreRuntimeEnvironment
if type(previousRuntimeRestore) == 'function' then
	pcall(previousRuntimeRestore)
end
shared.BadVapeFolder = folder
local protect = newcclosure or function(callback)
	return callback
end
local cloneref = cloneref or function(object)
	return object
end

local game = cloneref(game)
local playersService = cloneref(game:GetService('Players'))
local httpService = cloneref(game:GetService('HttpService'))

local function safeIsFile(path)
	if isfile then
		return isfile(path)
	end

	local success, result = pcall(function()
		return readfile(path)
	end)
	return success and result ~= nil and result ~= ''
end

local function ensureFolder(path)
	if not isfolder(path) then
		makefolder(path)
	end
end

for _, path in {
	folder,
	folder..'/profiles',
	folder..'/assets',
	folder..'/assets/new',
	folder..'/assets/old',
	folder..'/assets/wurst',
	folder..'/guis',
	folder..'/libraries',
	folder..'/games',
	folder..'/cache',
} do
	ensureFolder(path)
end

-- Remove files left by older releases after the retired Rise UI was removed.
if delfile and safeIsFile(folder..'/guis/rise.lua') then
	pcall(delfile, folder..'/guis/rise.lua')
end
if delfolder and isfolder(folder..'/assets/rise') then
	pcall(delfolder, folder..'/assets/rise')
end

if not safeIsFile(folder..'/profiles/commit.txt') then
	writefile(folder..'/profiles/commit.txt', 'local')
end

if not safeIsFile(folder..'/profiles/gui.txt') then
	writefile(folder..'/profiles/gui.txt', 'new')
end

local forwardedLicense = ...
local license = type(forwardedLicense) == 'table' and forwardedLicense or {}
license.Key = type(license.Key) == 'string' and license.Key or nil
license.Commit = license.Commit or 'local'

local builtInProfileNames = {'default', 'blatant'}
local function ensureBuiltInProfiles(profiles)
	local changed = type(profiles) ~= 'table'
	profiles = type(profiles) == 'table' and profiles or {}
	local existing = {}

	for _, profile in profiles do
		if type(profile) == 'table' and type(profile.Name) == 'string' then
			existing[profile.Name] = true
		end
	end

	for _, name in builtInProfileNames do
		if not existing[name] then
			table.insert(profiles, {Name = name, Bind = {}})
			changed = true
		end
	end

	return profiles, changed
end

local function repairBuiltInProfileList(path)
	if not safeIsFile(path) then
		return false
	end

	local success, data = pcall(function()
		return httpService:JSONDecode(readfile(path))
	end)
	if not success or type(data) ~= 'table' then
		return false
	end

	local changed
	data.Profiles, changed = ensureBuiltInProfiles(data.Profiles)
	if type(data.Profile) ~= 'string' or data.Profile == '' then
		data.Profile = 'default'
		changed = true
	end
	if changed then
		writefile(path, httpService:JSONEncode(data))
	end
	return changed
end

local guiColorMarker = folder..'/profiles/.badvape-color'
local badVapeGuiTheme = {
	Hue = 0.5979853272438049,
	Sat = 0.2949999965667727,
	Value = 0.8387499550819432,
	Rainbow = false,
	CustomColor = true,
}

local function applyBadVapeGuiTheme(path)
	local data = {
		Categories = {},
		Keybind = {'RightShift'},
		Profile = 'default',
		Profiles = {
			{Name = 'default', Bind = {}},
			{Name = 'blatant', Bind = {}},
		},
	}

	if safeIsFile(path) then
		local success, decoded = pcall(function()
			return httpService:JSONDecode(readfile(path))
		end)

		if success and type(decoded) == 'table' then
			data = decoded
		end
	end

	data.Categories = type(data.Categories) == 'table' and data.Categories or {}
	data.Categories.Main = type(data.Categories.Main) == 'table' and data.Categories.Main or {}
	data.Categories.Main.Options = type(data.Categories.Main.Options) == 'table' and data.Categories.Main.Options or {}
	data.Categories.Main.Options['GUI Theme'] = badVapeGuiTheme
	data.Keybind = type(data.Keybind) == 'table' and data.Keybind or {'RightShift'}
	data.Profile = type(data.Profile) == 'string' and data.Profile or 'default'
	data.Profiles = ensureBuiltInProfiles(data.Profiles)

	writefile(path, httpService:JSONEncode(data))
end

local function applyBadVapeGuiThemeOnce()
	if safeIsFile(guiColorMarker) then
		return
	end

	if listfiles then
		for _, path in listfiles(folder..'/profiles') do
			local normalized = path:gsub('\\', '/')
			if normalized:find('%.gui%.txt$') then
				pcall(applyBadVapeGuiTheme, normalized)
			end
		end
	end

	pcall(applyBadVapeGuiTheme, folder..'/profiles/'..tostring(game.GameId)..'.gui.txt')
	writefile(guiColorMarker, '1')
end

applyBadVapeGuiThemeOnce()
pcall(repairBuiltInProfileList, folder..'/profiles/2619619496.gui.txt')

if shared.BadVapeDeveloper == nil then
	local commitOk, commit = pcall(readfile, folder..'/profiles/commit.txt')
	shared.BadVapeDeveloper = commitOk and commit == 'local'
end
shared.BadVapeReload = shared.BadVapeReload or false

-- BadVape keeps a virtual `badvape` root so developer/canary installs can use a
-- distinct physical folder. Do not rewrite another client's roots.
local redirectRoots = {'badvape'}
local function ownsRuntimePath(path)
	if type(path) ~= 'string' then
		return false
	end
	path = path:gsub('\\', '/')
	if path == folder or path:sub(1, #folder + 1) == folder..'/' then
		return true
	end
	for _, root in redirectRoots do
		if path == root or path:sub(1, #root + 1) == root..'/' then
			return true
		end
	end
	return false
end

local function redirectPath(path)
	if type(path) ~= 'string' then
		return path
	end

	local originalPath = path
	path = path:gsub('\\', '/')
	if path == folder or path:sub(1, #folder + 1) == folder..'/' then
		return path
	end
	for _, root in redirectRoots do
		if path == root then
			return folder
		end
		if path:sub(1, #root + 1) == root..'/' then
			return folder..path:sub(#root + 1)
		end
	end

	return originalPath
end

local environmentHooks = {}
local runtimeCleanups = {}
local restoreRuntimeEnvironment
local function installEnvironmentHook(name, original, wrapped)
	environmentHooks[name] = {Original = original, Wrapped = wrapped}
	runtimeEnvironment[name] = wrapped
end

restoreRuntimeEnvironment = function()
	for name, hook in environmentHooks do
		if runtimeEnvironment[name] == hook.Wrapped then
			runtimeEnvironment[name] = hook.Original
		end
	end
	for index = #runtimeCleanups, 1, -1 do
		pcall(runtimeCleanups[index])
	end
	table.clear(environmentHooks)
	table.clear(runtimeCleanups)
	if shared.BadVapeRestoreRuntimeEnvironment == restoreRuntimeEnvironment then
		shared.BadVapeRestoreRuntimeEnvironment = nil
	end
end
shared.BadVapeRestoreRuntimeEnvironment = restoreRuntimeEnvironment

local oldReadfile = readfile
local wrappedReadfile = protect(function(path)
	return oldReadfile(redirectPath(path))
end)
installEnvironmentHook('readfile', oldReadfile, wrappedReadfile)

local oldWritefile = writefile
local wrappedWritefile = protect(function(path, content)
	if not ownsRuntimePath(path) then
		return oldWritefile(path, content)
	end
	local redirected = redirectPath(path)
	local parts = redirected:split('/')
	local current = ''

	for index = 1, #parts - 1 do
		current = current..(index > 1 and '/' or '')..parts[index]
		ensureFolder(current)
	end

	return oldWritefile(redirected, content)
end)
installEnvironmentHook('writefile', oldWritefile, wrappedWritefile)

local oldIsfile = isfile
if oldIsfile then
	local wrappedIsfile = protect(function(path)
		return oldIsfile(redirectPath(path))
	end)
	installEnvironmentHook('isfile', oldIsfile, wrappedIsfile)
end

local oldIsfolder = isfolder
if oldIsfolder then
	local wrappedIsfolder = protect(function(path)
		return oldIsfolder(redirectPath(path))
	end)
	installEnvironmentHook('isfolder', oldIsfolder, wrappedIsfolder)
end

local oldMakefolder = makefolder
if oldMakefolder then
	local wrappedMakefolder = protect(function(path)
		return oldMakefolder(redirectPath(path))
	end)
	installEnvironmentHook('makefolder', oldMakefolder, wrappedMakefolder)
end

local oldListfiles = listfiles
if oldListfiles then
	local wrappedListfiles = protect(function(path)
		local files = oldListfiles(redirectPath(path))
		if not ownsRuntimePath(path) then
			return files
		end
		local normalized = {}

		for index, file in files do
			normalized[index] = file:gsub('\\', '/')
		end

		return normalized
	end)
	installEnvironmentHook('listfiles', oldListfiles, wrappedListfiles)
end

local oldDelfile = delfile
if oldDelfile then
	local wrappedDelfile = protect(function(path)
		return oldDelfile(redirectPath(path))
	end)
	installEnvironmentHook('delfile', oldDelfile, wrappedDelfile)
end

local function urlToLocalPath(url)
	local path = url:match('raw%.githubusercontent%.com/[^/]+/badvape%-v2/[^/]+/(.+)')

	if path then
		return folder..'/'..path
	end

	return nil
end

if shared.BadVapeDeveloper and getrawmetatable and setreadonly and getnamecallmethod then
	local gameMetatable = getrawmetatable(game)
	local oldNamecall = gameMetatable.__namecall
	local wrappedNamecall

	setreadonly(gameMetatable, false)
	wrappedNamecall = protect(function(self, ...)
		local method = getnamecallmethod()
		local args = {...}

		if method == 'HttpGet' or method == 'HttpGetAsync' then
			local url = args[1] or ''
			local localPath = urlToLocalPath(url)

			if localPath then
				if safeIsFile(localPath) then
					return readfile(localPath)
				end

				error('Missing local BadVape file: '..localPath)
			end
		end

		return oldNamecall(self, ...)
	end)
	gameMetatable.__namecall = wrappedNamecall
	setreadonly(gameMetatable, true)
	table.insert(runtimeCleanups, function()
		local currentMetatable = getrawmetatable(game)
		if currentMetatable.__namecall == wrappedNamecall then
			setreadonly(currentMetatable, false)
			currentMetatable.__namecall = oldNamecall
			setreadonly(currentMetatable, true)
		end
	end)
end

repeat
	task.wait()
until game:IsLoaded()

local function waitForLocalPlayer()
	local localPlayer
	repeat
		task.wait()
		localPlayer = playersService.LocalPlayer
	until localPlayer and localPlayer:FindFirstChild('PlayerGui')
	return localPlayer
end

local localPlayer = waitForLocalPlayer()

local mainPath = folder..'/main.lua'
if not safeIsFile(mainPath) then
	restoreRuntimeEnvironment()
	error('Missing local BadVape entrypoint', 0)
end
local mainChunk, mainLoadError = loadstring(readfile(mainPath), 'badvape/main.lua')
if not mainChunk then
	restoreRuntimeEnvironment()
	error('BadVape entrypoint rejected: '..tostring(mainLoadError), 0)
end

local mainOk, mainResult = pcall(mainChunk, license)
if not mainOk then
	restoreRuntimeEnvironment()
	error('BadVape entrypoint failed: '..tostring(mainResult), 0)
end
return mainResult
