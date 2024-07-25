local RSGCore = exports['rsg-core']:GetCoreObject()

RegisterServerEvent('randol_parceljob:server:Payment', function(jobsDone)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    
    if not Player then return end

    jobsDone = tonumber(jobsDone)
    if not jobsDone or jobsDone <= 0 then
        -- If jobsDone is invalid or zero, don't process payment
        return
    end

    local payment = Config.Payment * jobsDone

    Player.Functions.AddMoney("cash", payment)
    TriggerClientEvent("RSGCore:Notify", src, "You received $"..payment.." for "..jobsDone.." deliveries.", "success")
end)