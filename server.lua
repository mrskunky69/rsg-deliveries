local RSGCore = exports['rsg-core']:GetCoreObject()

RegisterServerEvent('randol_parceljob:server:Payment')
AddEventHandler('randol_parceljob:server:Payment', function(jobsDone)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player then
        print("Player not found for source: " .. tostring(src))
        return
    end

    jobsDone = tonumber(jobsDone)
    if not jobsDone or jobsDone <= 0 then
        TriggerClientEvent("RSGCore:Notify", src, "not enough jobs", "error")
        return
    end

    local payment = Config.Payment * jobsDone
    local bonusAmount = 20  -- Cash bonus amount

    -- Add payment and bonus to the player
    local successPayment = Player.Functions.AddMoney("cash", payment, "Completed parcel job payment")
    local successBonus = Player.Functions.AddMoney("cash", bonusAmount, "Completed parcel job bonus")

    if successPayment and successBonus then
        TriggerClientEvent("RSGCore:Notify", src, "You received $" .. payment .. " for " .. jobsDone .. " deliveries and a $20 bonus.", "success")
    else
        TriggerClientEvent("RSGCore:Notify", src, "Payment failed. Please contact support.", "error")
    end
end)
