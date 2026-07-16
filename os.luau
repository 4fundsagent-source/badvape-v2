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

shared.catdata = nil
if shared.VapeDeveloper == nil then
	local commitOk, commit = pcall(readfile, folder..'/profiles/commit.txt')
	shared.VapeDeveloper = commitOk and commit == 'local'
end
shared.vapereload = shared.vapereload or false

local redirectRoots = {'catrewrite', 'badrewrite', 'badvape'}
local function redirectPath(path)
	if type(path) ~= 'string' then
		return path
	end

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

	return path
end

local oldReadfile = readfile
runtimeEnvironment.readfile = protect(function(path)
	return oldReadfile(redirectPath(path))
end)

local oldWritefile = writefile
runtimeEnvironment.writefile = protect(function(path, content)
	local redirected = redirectPath(path)
	local parts = redirected:split('/')
	local current = ''

	for index = 1, #parts - 1 do
		current = current..(index > 1 and '/' or '')..parts[index]
		ensureFolder(current)
	end

	return oldWritefile(redirected, content)
end)

local oldIsfile = isfile
if oldIsfile then
	runtimeEnvironment.isfile = protect(function(path)
		return oldIsfile(redirectPath(path))
	end)
end

local oldIsfolder = isfolder
if oldIsfolder then
	runtimeEnvironment.isfolder = protect(function(path)
		return oldIsfolder(redirectPath(path))
	end)
end

local oldMakefolder = makefolder
if oldMakefolder then
	runtimeEnvironment.makefolder = protect(function(path)
		return oldMakefolder(redirectPath(path))
	end)
end

local oldListfiles = listfiles
if oldListfiles then
	runtimeEnvironment.listfiles = protect(function(path)
		local files = oldListfiles(redirectPath(path))
		local normalized = {}

		for index, file in files do
			normalized[index] = file:gsub('\\', '/')
		end

		return normalized
	end)
end

local oldDelfile = delfile
if oldDelfile then
	runtimeEnvironment.delfile = protect(function(path)
		return oldDelfile(redirectPath(path))
	end)
end

local assetIdMap = {
	['add.png'] = 'rbxassetid://14368300605',
	['alert.png'] = 'rbxassetid://14368301329',
	['allowedicon.png'] = 'rbxassetid://14368302000',
	['allowedtab.png'] = 'rbxassetid://14368302875',
	['arrowmodule.png'] = 'rbxassetid://14473354880',
	['back.png'] = 'rbxassetid://14368303894',
	['bind.png'] = 'rbxassetid://14368304734',
	['bindbkg.png'] = 'rbxassetid://14368305655',
	['blatanticon.png'] = 'rbxassetid://14368306745',
	['blockedicon.png'] = 'rbxassetid://14385669108',
	['blockedtab.png'] = 'rbxassetid://14385672881',
	['blur.png'] = 'rbxassetid://14898786664',
	['blurnotif.png'] = 'rbxassetid://16738720137',
	['close.png'] = 'rbxassetid://14368309446',
	['closemini.png'] = 'rbxassetid://14368310467',
	['colorpreview.png'] = 'rbxassetid://14368311578',
	['combaticon.png'] = 'rbxassetid://14368312652',
	['customsettings.png'] = 'rbxassetid://14403726449',
	['dots.png'] = 'rbxassetid://14368314459',
	['edit.png'] = 'rbxassetid://14368315443',
	['expandicon.png'] = 'rbxassetid://14368353032',
	['expandright.png'] = 'rbxassetid://14368316544',
	['expandup.png'] = 'rbxassetid://14368317595',
	['friendstab.png'] = 'rbxassetid://14397462778',
	['guisettings.png'] = 'rbxassetid://14368318994',
	['guislider.png'] = 'rbxassetid://14368320020',
	['guisliderrain.png'] = 'rbxassetid://14368321228',
	['guiv4.png'] = 'rbxassetid://14368322199',
	['guivape.png'] = 'rbxassetid://14657521312',
	['info.png'] = 'rbxassetid://14368324807',
	['inventoryicon.png'] = 'rbxassetid://14928011633',
	['legit.png'] = 'rbxassetid://14425650534',
	['legittab.png'] = 'rbxassetid://14426740825',
	['miniicon.png'] = 'rbxassetid://14368326029',
	['notification.png'] = 'rbxassetid://16738721069',
	['overlaysicon.png'] = 'rbxassetid://14368339581',
	['overlaystab.png'] = 'rbxassetid://14397380433',
	['pin.png'] = 'rbxassetid://14368342301',
	['profilesicon.png'] = 'rbxassetid://14397465323',
	['radaricon.png'] = 'rbxassetid://14368343291',
	['rainbow_1.png'] = 'rbxassetid://14368344374',
	['rainbow_2.png'] = 'rbxassetid://14368345149',
	['rainbow_3.png'] = 'rbxassetid://14368345840',
	['rainbow_4.png'] = 'rbxassetid://14368346696',
	['range.png'] = 'rbxassetid://14368347435',
	['rangearrow.png'] = 'rbxassetid://14368348640',
	['rendericon.png'] = 'rbxassetid://14368350193',
	['rendertab.png'] = 'rbxassetid://14397373458',
	['search.png'] = 'rbxassetid://14425646684',
	['targetinfoicon.png'] = 'rbxassetid://14368354234',
	['targetnpc1.png'] = 'rbxassetid://14497400332',
	['targetnpc2.png'] = 'rbxassetid://14497402744',
	['targetplayers1.png'] = 'rbxassetid://14497396015',
	['targetplayers2.png'] = 'rbxassetid://14497397862',
	['targetstab.png'] = 'rbxassetid://14497393895',
	['textguiicon.png'] = 'rbxassetid://14368355456',
	['textv4.png'] = 'rbxassetid://14368357095',
	['textvape.png'] = 'rbxassetid://14368358200',
	['utilityicon.png'] = 'rbxassetid://14368359107',
	['vape.png'] = 'rbxassetid://14373395239',
	['warning.png'] = 'rbxassetid://14368361552',
	['worldicon.png'] = 'rbxassetid://14368362492',
}

local oldGetcustomasset = getcustomasset
if oldGetcustomasset then
	runtimeEnvironment.getcustomasset = protect(function(path)
		if type(path) == 'string' then
			local filename = path:match('[^/\\]+%.%w+$')
			if filename and assetIdMap[filename] then
				return assetIdMap[filename]
			end
		end

		return oldGetcustomasset(redirectPath(path))
	end)
end

local function urlToLocalPath(url)
	local path = url:match('raw%.githubusercontent%.com/[^/]+/CatV6/[^/]+/(.+)')
		or url:match('raw%.githubusercontent%.com/[^/]+/badvape%-v2/[^/]+/(.+)')

	if path then
		return folder..'/'..path
	end

	return nil
end

if shared.VapeDeveloper and getrawmetatable and setreadonly and getnamecallmethod then
	local gameMetatable = getrawmetatable(game)
	local oldNamecall = gameMetatable.__namecall

	setreadonly(gameMetatable, false)
	gameMetatable.__namecall = protect(function(self, ...)
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
	setreadonly(gameMetatable, true)
end

repeat
	task.wait()
until game:IsLoaded()

local localPlayer = playersService.LocalPlayer
repeat
	task.wait()
until localPlayer and localPlayer:FindFirstChild('PlayerGui')

local mainPath = folder..'/main.lua'
if not safeIsFile(mainPath) then
	error('Missing local BadVape entrypoint', 0)
end
local mainChunk, mainLoadError = loadstring(readfile(mainPath), 'badvape/main.lua')
if not mainChunk then
	error('BadVape entrypoint rejected: '..tostring(mainLoadError), 0)
end

local mainOk, mainResult = pcall(mainChunk, license)
if not mainOk then
	error('BadVape entrypoint failed: '..tostring(mainResult), 0)
end
return mainResult
