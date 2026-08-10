local run = function(func) func() end
local cloneref = cloneref or function(obj) return obj end

local playersService = cloneref(game:GetService('Players'))
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
local inputService = cloneref(game:GetService('UserInputService'))

local lplr = playersService.LocalPlayer
local vape = shared.BadVape
local entitylib = vape.Libraries.entity
local sessioninfo = vape.Libraries.sessioninfo
local bedwars = {}
local Knit

local function notif(...)
	return vape:CreateNotification(...)
end

local function waitForKnitClient()
	local deadline = os.clock() + 12
	local knitError
	repeat
		local success, result = pcall(function()
			return require(replicatedStorage.rbxts_include.node_modules['@easy-games'].knit.src).KnitClient
		end)
		if success and type(result) == 'table' then
			Knit = result
			break
		end
		knitError = result
		if os.clock() >= deadline then
			return false, knitError
		end
		task.wait()
	until Knit

	local startOk, startResult = pcall(function()
		if type(Knit.OnStart) == 'function' then
			local promise = Knit:OnStart()
			if promise and type(promise.timeout) == 'function' and type(promise.await) == 'function' then
				return select(1, promise:timeout(math.max(0, deadline - os.clock())):await())
			end
		end

		-- Compatibility for older FloodCraft snapshots that do not expose
		-- OnStart. Keep this fallback bounded; it must not block teleport setup.
		if type(debug) == 'table' and type(debug.getupvalue) == 'function'
			and type(Knit.Start) == 'function' then
			repeat
				local started = debug.getupvalue(Knit.Start, 1)
				if started then return true end
				if os.clock() >= deadline then return false end
				task.wait()
			until false
		end

		-- A few legacy builds only expose the controller table. Do not claim
		-- readiness until at least one controller has been registered.
		return type(Knit.Controllers) == 'table' and next(Knit.Controllers) ~= nil
	end)

	return startOk and startResult == true, startResult
end

local knitReady, knitError = waitForKnitClient()
if not knitReady then
	if shared.BadVapeDeveloper then
		warn('[BadVape] Lobby KnitClient did not finish startup: '..tostring(knitError))
	end
	return false
end

local initialized, initializationError = pcall(function()
	local Flamework = require(replicatedStorage['rbxts_include']['node_modules']['@flamework'].core.out).Flamework
	local Client = require(replicatedStorage.TS.remotes).default.Client

	bedwars = setmetatable({
		AchievementId = require(replicatedStorage.TS.achievement['achievement-id']).AchievementId,
		Client = Client,
		CrateItemMeta = debug.getupvalue(Flamework.resolveDependency('client/controllers/global/reward-crate/crate-controller@CrateController').onStart, 3),
		QueueMeta = require(replicatedStorage.TS.game['queue-meta']).QueueMeta,
		Store = require(lplr.PlayerScripts.TS.ui.store).ClientStore
	}, {
		__index = function(self, ind)
			rawset(self, ind, Knit.Controllers[ind])
			return rawget(self, ind)
		end
	})

	sessioninfo:AddItem('Kills')
	sessioninfo:AddItem('Beds')
	sessioninfo:AddItem('Wins')
	sessioninfo:AddItem('Games')

	vape:Clean(function()
		table.clear(bedwars)
	end)
end)
if not initialized then
	if shared.BadVapeDeveloper then
		warn('[BadVape] Lobby controller initialization failed: '..tostring(initializationError))
	end
	return false
end

for i, v in vape.Modules do
	if v.Category == 'Combat' or v.Category == 'Minigames' then
		vape:Remove(i)
	end
end

--[[
    Combat
]]

run(function()
    local Sprint
    local old
    
    Sprint = vape.Categories.Combat:CreateModule({
        Name = 'Sprint',
        Function = function(callback)
            if callback then
                old = bedwars.SprintController.stopSprinting
                bedwars.SprintController.stopSprinting = function(...)
                    local call = old(...)
                    bedwars.SprintController:startSprinting()
                    return call
                end
                Sprint:Clean(entitylib.Events.LocalAdded:Connect(function() bedwars.SprintController:stopSprinting() end))
                bedwars.SprintController:stopSprinting()
            else
                bedwars.SprintController.stopSprinting = old
                bedwars.SprintController:stopSprinting()
            end
        end,
        Tooltip = 'Sets your sprinting to true.'
    })
end)

--[[
    Utility
]]

run(function()
    local AutoQueue
    local QueueType
    local Leave
    
    local Categories = {}
    
    AutoQueue = vape.Categories.Utility:CreateModule({
        Name = 'Auto Queue',
        Function = function(call)
            if call then
                repeat
                    local partyData = bedwars.Store:getState().Party
                    if partyData.leader.userId == lplr.UserId then
                        if partyData.queueState == 3 and partyData.queueState ~= Categories[QueueType.Value] then
                            replicatedStorage['events-@easy-games/lobby:shared/event/lobby-events@getEvents.Events'].leaveQueue:FireServer()
                        elseif partyData.queueState < 2 then
                            replicatedStorage['events-@easy-games/lobby:shared/event/lobby-events@getEvents.Events'].joinQueue:FireServer({
                                queueType = Categories[QueueType.Value]
                            })
                            task.wait(1)
                        end
                    elseif Leave.Enabled then
                        replicatedStorage['events-@easy-games/lobby:shared/event/lobby-events@getEvents.Events'].leaveParty:FireServer()
                    end
                    task.wait(0.1)
                until not AutoQueue.Enabled
    
            else
                replicatedStorage['events-@easy-games/lobby:shared/event/lobby-events@getEvents.Events'].leaveQueue:FireServer()
            end
        end
    })
    
    local list = {}
    for i,v in bedwars.QueueMeta do
        if not v.disabled then
            Categories[v.title] = i
            table.insert(list, v.title)
        end
    end
    QueueType = AutoQueue:CreateDropdown({
        Name = 'Queue Type',
        List = list,
        Default = 'Duels (2v2)'
    })
    Leave = AutoQueue:CreateToggle({
        Name = 'Leave Party',
        Default = true
    })
end)

--[[
    Minigames
]]

run(function()
    local AutoGamble
    
    AutoGamble = vape.Categories.Minigames:CreateModule({
        Name = 'AutoGamble',
        Function = function(callback)
            if callback then
                AutoGamble:Clean(bedwars.Client:GetNamespace('RewardCrate'):Get('CrateOpened'):Connect(function(data)
                    if data.openingPlayer == lplr then
                        local tab = bedwars.CrateItemMeta[data.reward.itemType] or {displayName = data.reward.itemType or 'unknown'}
                        notif('AutoGamble', 'Won '..tab.displayName, 5)
                    end
                end))
    
                repeat
                    if not bedwars.CrateAltarController.activeCrates[1] then
                        for _, v in bedwars.Store:getState().Consumable.inventory do
                            if v.consumable:find('crate') then
                                bedwars.CrateAltarController:pickCrate(v.consumable, 1)
                                task.wait(1.2)
                                if bedwars.CrateAltarController.activeCrates[1] and bedwars.CrateAltarController.activeCrates[1][2] then
                                    bedwars.Client:GetNamespace('RewardCrate'):Get('OpenRewardCrate'):SendToServer({
                                        crateId = bedwars.CrateAltarController.activeCrates[1][2].attributes.crateId
                                    })
                                end
                                break
                            end
                        end
                    end
                    task.wait(1)
                until not AutoGamble.Enabled
            end
        end,
        Tooltip = 'Automatically opens lucky crates, piston inspired!'
    })
end)

run(function()
    local Claim = bedwars.Client:Get('ClaimAchievementRewards')
    
    vape.Categories.Minigames:CreateModule({
        Name = 'Infinite Rewards',
        Function = function(callback)
            if callback then
                for i in bedwars.AchievementId do
                    Claim:SendToServer({id = i:lower()})
                end
            end
        end,
        Tooltip = 'Automatically claims all rewards ingame.'
    })
end)
