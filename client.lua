local RSGCore = exports['rsg-core']:GetCoreObject()
local Hired = false
local HasParcel = false
local DeliveriesCount = 0
local Delivered = false
local ParcelDelivered = false
local ownsWagon = false
local activeOrder = false
local newDelivery = nil
local bossBlip = nil
local prop = nil
local isPropAttached = false
local parcelObject = nil
local isCarryingParcel = false
local lastMovementTime = 0
local detachmentDelay = 10000  -- 

local function loadAnimDict(dict)
    while (not HasAnimDictLoaded(dict)) do
        RequestAnimDict(dict)
        Wait(5)
    end
end

local spawnedPeds = {}

-- Ensure Config is defined
Config = Config or {}
Config.DistanceSpawn = Config.DistanceSpawn or 20.0  -- Default value if not set in config file

CreateThread(function()
	bossBlip = CreateBossBlip()
	
    while true do
        Wait(500)
        local playerCoords = GetEntityCoords(PlayerPedId())
        local bossCoords = vector3(Config.BossCoords.x, Config.BossCoords.y, Config.BossCoords.z)
        
        if bossCoords and Config.DistanceSpawn then
            local distance = #(playerCoords - bossCoords)
            
            if distance < Config.DistanceSpawn and not spawnedPeds["parcelBoss"] then
                local spawnedPed = NearPed(Config.BossModel, Config.BossCoords)
                if spawnedPed then
                    spawnedPeds["parcelBoss"] = { ped = spawnedPed }
                    SetupBossPed(spawnedPed)
                end
            elseif distance >= Config.DistanceSpawn and spawnedPeds["parcelBoss"] then
                if DoesEntityExist(spawnedPeds["parcelBoss"].ped) then
                    DeletePed(spawnedPeds["parcelBoss"].ped)
                end
                spawnedPeds["parcelBoss"] = nil
            end
        else
            print("Error: Boss coordinates or spawn distance not set in config")
            break  -- Exit the loop if critical config is missing
        end
    end
end)

function NearPed(model, coords)
    if not model or not coords then
        print("Error: Invalid model or coords for NearPed")
        return nil
    end

    local modelHash = GetHashKey(model)
    RequestModel(modelHash)
    local startTime = GetGameTimer()
    while not HasModelLoaded(modelHash) do
        Wait(50)
        if GetGameTimer() - startTime > 5000 then  -- 5 second timeout
            print("Error: Model failed to load in time: " .. model)
            return nil
        end
    end
    
    local ped = CreatePed(modelHash, coords.x, coords.y, coords.z - 1.0, coords.w or 0.0, false, false, 0, 0)
    if not DoesEntityExist(ped) then
        print("Error: Failed to create ped")
        return nil
    end

    Citizen.InvokeNative(0x283978A15512B2FE, ped, true) -- SetRandomOutfitVariation
    SetEntityCanBeDamaged(ped, false)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    
    return ped
end

-- Rest of your code remains the same

function SetupBossPed(ped)
    exports['rsg-target']:AddTargetEntity(ped, { 
        options = {
            { 
                type = "client",
                event = "randol_parceljob:client:startJob",
                icon = "fa-solid fa-box",
                label = "Start Work",
                canInteract = function()
                    return not Hired
                end,
            },
            { 
                type = "client",
                event = "randol_parceljob:client:finishWork",
                icon = "fa-solid fa-box",
                label = "Finish Work",
                canInteract = function()
                    return Hired
                end,
            },
        }, 
        distance = 1.5, 
    })
end

AddEventHandler("onResourceStop", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    for k,v in pairs(spawnedPeds) do
        DeletePed(v.spawnedPed)
    end
	
end)

AddEventHandler('onResourceStart', function(resource)
    if GetCurrentResourceName() == resource then
        PlayerJob = RSGCore.Functions.GetPlayerData().job
        
    end
end)

RegisterNetEvent('RSGCore:Client:OnPlayerLoaded', function()
    ClockInPed()
end)

RegisterNetEvent('RSGCore:Client:OnPlayerUnload', function()
    exports['rsg-target']:RemoveZone("deliverZone")
    RemoveBlip(JobBlip)
    ResetJobVariables()
    DeletePed(parcelBoss)
    
    -- Add this block to remove the boss blip
    if bossBlip then
        RemoveBlip(bossBlip)
        bossBlip = nil
    end
end)

AddEventHandler('onResourceStop', function(resourceName) 
    if GetCurrentResourceName() == resourceName then
        exports['rsg-target']:RemoveZone("deliverZone")
        RemoveBlip(JobBlip)
        ResetJobVariables()
        DeletePed(parcelBoss)
        
        -- Add this block to remove the boss blip
        if bossBlip then
            RemoveBlip(bossBlip)
            bossBlip = nil
        end
    end 
end)

function ResetJobVariables()
    Hired = false
    HasParcel = false
    DeliveriesCount = 0
    Delivered = false
    ParcelDelivered = false
    ownsWagon = false
    activeOrder = false
end

CreateThread(function()
    DecorRegister("parcel_job", 1)
end)

function PullOutWagon()
    local coords = Config.WagonSpawn
    RSGCore.Functions.SpawnVehicle(Config.Vehicle, function(parcelWagon)
        SetEntityHeading(parcelWagon, coords.w)
        SetVehicleOnGroundProperly(parcelWagon)
        SetVehicleDirtLevel(parcelWagon, 0)
        TaskWarpPedIntoVehicle(PlayerPedId(), parcelWagon, -1)
        exports['rsg-target']:AddTargetEntity(parcelWagon, {
            options = {
                {
                    icon = "fa-solid fa-box",
                    label = "Take parcel",
                    action = function(entity) TakeParcel() end,
                    canInteract = function() 
                        return Hired and activeOrder and not HasParcel
                    end,
                },
            },
            distance = 2.5
        })
    end, coords, true)
    Hired = true
    ownsWagon = true
    NextDelivery()
end

RegisterNetEvent('randol_parceljob:client:startJob', function()
    if not Hired then
        PullOutWagon()
    end
end)

function CreateBossBlip()
    local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, Config.BossCoords.x, Config.BossCoords.y, Config.BossCoords.z)
    SetBlipSprite(blip, Config.BlipSprite, 1)
    SetBlipScale(blip, Config.BlipScale)
    Citizen.InvokeNative(0x9CB1A1623062F402, blip, "Parcel Job")
    return blip
end

RegisterNetEvent('randol_parceljob:client:deliverParcel', function()
    if HasParcel and Hired and not ParcelDelivered then
        local player = PlayerPedId()

        TriggerServerEvent('randol_parceljob:server:Payment', DeliveriesCount)
        ParcelDelivered = true

        -- Play put down animation
        -- loadAnimDict("mech_pickup@plant@gold_currant")
        -- TaskPlayAnim(player, "mech_pickup@plant@gold_currant", "exit_lf", 8.0, -8.0, -1, 0, 0, false, false, false)
        prop = exports['carry']:dropEntity()

        RSGCore.Functions.Progressbar("deliver", "Delivering parcel", 7000, false, true, {
            disableMovement = true,
            disableCarMovement = true,
            disableMouse = false,
            disableCombat = true,
        }, {}, {}, {}, function()
            DeliveriesCount = DeliveriesCount + 1
            RemoveBlip(JobBlip)
            exports['rsg-target']:RemoveZone("deliverZone")
            HasParcel = false
            activeOrder = false
            ParcelDelivered = false
            
            if DoesEntityExist(prop) then
                DetachEntity(prop, 1, 1)
                DeleteObject(prop)
                prop = nil
            end
            isPropAttached = false

            ClearPedTasks(player)
            RSGCore.Functions.Notify("Parcel Delivered. Please wait for your next delivery!", "success") 
            SetTimeout(5000, function()    
                NextDelivery()
            end)
        end)
    else
        RSGCore.Functions.Notify("You need the parcel from the wagon.", "error") 
    end
end)

Citizen.CreateThread(function()
    while true do
        Wait(0)

        if isCarryingParcel then
            local playerPed = PlayerPedId()

            if IsPedSprinting(playerPed) or IsPedRunning(playerPed) or GetEntitySpeedVector(playerPed, true).y > 1.0 then
                lastMovementTime = GetGameTimer()
            end

            -- Detach parcel if player hasn't moved for 10 seconds
            if GetGameTimer() - lastMovementTime >= detachmentDelay then
                TriggerEvent('randol_parceljob:client:dropParcel')
                RSGCore.Functions.Notify("You've dropped the parcel due to inactivity.", "error")
            end

            -- Ensure animation is playing
            if not IsEntityPlayingAnim(playerPed, "mech_carry@package", "idle", 3) then
                TaskPlayAnim(playerPed, "mech_carry@package", "idle", 8.0, -8.0, -1, 31, 0, false, false, false)
            end
        end
    end
end)

RegisterNetEvent('randol_parceljob:client:dropParcel')
AddEventHandler('randol_parceljob:client:dropParcel', function()
    local playerPed = PlayerPedId()
    ClearPedTasks(playerPed)

    if parcelObject then
        DeleteEntity(parcelObject)
        parcelObject = nil
    end

    isCarryingParcel = false
    lastMovementTime = 0
end)

RegisterNetEvent('randol_parceljob:client:takeParcel')
AddEventHandler('randol_parceljob:client:takeParcel', function()
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)

    if not isCarryingParcel then
        local dict = "mech_carry_box"
        -- RequestAnimDict(dict)
        -- while not HasAnimDictLoaded(dict) do
        --     Citizen.Wait(100)
        -- end

        -- TaskPlayAnim(playerPed, dict, "idle", 8.0, -8.0, -1, 31, 0, false, false, false)

        -- local parcelCoords = GetOffsetFromEntityInWorldCoords(playerPed, 0.0, 0.0, 0.0)
        -- local object = CreateObject(GetHashKey(Config.ParcelProp), parcelCoords.x, parcelCoords.y, parcelCoords.z, true, false, false)

        -- AttachEntityToEntity(object, playerPed, GetPedBoneIndex(playerPed, 28422), 0.0, 0.6, -0.2, 0.0, 0.0, 0.0, true, true, false, true, 1, true)

        parcelObject = object
        isCarryingParcel = true
        lastMovementTime = GetGameTimer()
        exports['carry']:createAndPickupObject(Config.ParcelProp,coords)
        RSGCore.Functions.Notify("You've picked up a parcel. Deliver it to the marked location.", "success")
    end
end)





function NextDelivery()
    if not activeOrder then
        -- Remove existing blip and target zone if they exist
        if JobBlip then
            RemoveBlip(JobBlip)
        end
        exports['rsg-target']:RemoveZone("deliverZone")

        -- Clear existing GPS route
        ClearGpsMultiRoute()

        -- Select a random delivery location
        newDelivery = Config.JobLocs[math.random(1, #Config.JobLocs)]

        -- Create the blip for the new delivery location
        JobBlip = N_0x554d9d53f696d002(1664425300, newDelivery.x, newDelivery.y, newDelivery.z)
        SetBlipSprite(JobBlip, -44057202) -- Set an appropriate sprite
        SetBlipScale(JobBlip, 0.8)
        Citizen.InvokeNative(0x9CB1A1623062F402, JobBlip, "Next Customer") -- Set name

        -- Add an interactive target zone for delivery
        exports['rsg-target']:AddCircleZone("deliverZone", vector3(newDelivery.x, newDelivery.y, newDelivery.z), 1.3, {
            name = "deliverZone",
            debugPoly = false,
            useZ = true,
        }, {
            options = {
                {
                    type = "client",
                    event = "randol_parceljob:client:deliverParcel",
                    icon = "fa-solid fa-box",
                    label = "Deliver Parcel",
                },
            },
            distance = 1.5,
        })

        -- Start the GPS route
        StartGpsMultiRoute(GetHashKey("COLOR_RED"), true, true)
        AddPointToGpsMultiRoute(newDelivery.x, newDelivery.y, newDelivery.z)
        SetGpsMultiRouteRender(true)

        activeOrder = true
        RSGCore.Functions.Notify("You have a new delivery!", "success")
        
        -- Add a thread to check player's distance from the delivery point
        CreateThread(function()
            local notified = false
            while activeOrder do
                Wait(1000)  -- Check every second
                local playerPos = GetEntityCoords(PlayerPedId())
                local distance = #(playerPos - vector3(newDelivery.x, newDelivery.y, newDelivery.z))
                
                if distance < 30.0 and not notified then  -- Adjust this distance as needed
                    RSGCore.Functions.Notify("You've reached the delivery location. Take the parcel from your wagon.", "primary")
                    notified = true
                end

                if not activeOrder then
                    break
                end
            end
        end)
    end
end

function TakeParcel()
    local player = PlayerPedId()
    local pos = GetEntityCoords(player)

    if not IsPedInAnyVehicle(player, false) and not HasParcel then
        if newDelivery and #(pos - vector3(newDelivery.x, newDelivery.y, newDelivery.z)) < 30.0 then
            -- local dict = "mech_carry_box"
            -- local anim = "idle"
            local playerCoord = GetEntityCoords(player)
            local prop_name = Config.ParcelProp
            exports['carry']:createAndPickupObject(Config.ParcelProp,playerCoord)
            
            -- RequestAnimDict(dict)
            -- while not HasAnimDictLoaded(dict) do
            --     Wait(10)
            -- end
            
            -- -- Create the parcel object and attach it to the player
            -- local x, y, z = table.unpack(GetEntityCoords(player))
            -- prop = CreateObject(GetHashKey(prop_name), x, y, z + 0.2, true, true, true)
            -- AttachEntityToEntity(prop, player, GetPedBoneIndex(player, 60309), 0.2, 0.08, 0.2, -45.0, 290.0, 0.0, true, true, false, true, 1, true)
            
            -- -- Play the carrying animation
            -- TaskPlayAnim(player, dict, anim, 3.0, 3.0, -1, 63, 0, false, false, false)
            
            HasParcel = true
            RSGCore.Functions.Notify("You've taken a parcel. Deliver it to the marked location.", "success")
        else
            RSGCore.Functions.Notify("You're not close enough to the customer's house!", "error")
        end
    end
end




RegisterNetEvent('randol_parceljob:client:finishWork', function()
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local veh = RSGCore.Functions.GetClosestVehicle()
    local finishspot = vector3(Config.BossCoords.x, Config.BossCoords.y, Config.BossCoords.z)
    if #(pos - finishspot) < 10.0 then
        if Hired then
            if DecorExistOn((veh), "parcel_job") then
                RSGCore.Functions.DeleteVehicle(veh)
                RemoveBlip(JobBlip)
                ResetJobVariables()
                if DeliveriesCount > 0 then
                    RSGCore.Functions.Notify("You completed " .. DeliveriesCount .. " deliveries.", "success")
                else
                    RSGCore.Functions.Notify("You didn't complete any deliveries so you weren't paid.", "error")
                end
                DeliveriesCount = 0
            else
                RSGCore.Functions.Notify("You must return your work wagon to get paid.", "error")
            end
        end
    end
end)

function loadAnimDict(dict)
    while not HasAnimDictLoaded(dict) do
        RequestAnimDict(dict)
        Wait(0)
    end
end