local AP = require("./lua-apclientpp")

-- Connection Info
local connected = false
local address = ""
local slot = ""
local password = ""
local console = ""

-- AP Info
local game_name = "Risk of Rain"
local items_handling = 7  -- full remote
local message_format = AP.RenderFormat.TEXT
---@type APClient
local ap = nil

-- Item and Location Handling
local itemsCollected = {}
local itemsBuffer = {}
local locationsMissing = {}
local skipItemSend = false
local mapGroup = {
    ["Desolate Forest"] =         {},
    ["Dried Lake"] =              {},
    ["Damp Caverns"] =            {},
    ["Sky Meadow"] =              {},
    ["Ancient Valley"] =          {},
    ["Sunken Tomb"] =             {},
    ["Sunken Tombs"] =            {},
    ["Magma Barracks"] =          {},
    ["Hive Cluster"] =            {},
    ["Temple of the Elders"] =    {}
}
local stageGroup = {0, 0, 0, 0, 0}

-- AP Data
local slotData = nil
local curPlayerSlot = nil
local pickupStepOverride = -1
local deathLink = false
local teleFrags = 0

-- 
local initialSetup = true
local pickupStep = 0

--------------------------------------------------
-- AP Client                                    --
--------------------------------------------------

function connect(server, slot, password)
    function on_socket_connected()
        log.info("Socket connected")
    end

    function on_socket_error(msg)
        log.info("Socket error: " .. msg)
    end

    function on_socket_disconnected()
        connected = false
        skipItemSend = true
        itemsCollected = {}
        log.info("Socket disconnected")
    end

    function on_room_info()
        log.info("Room info")
        ap:ConnectSlot(slot, password, items_handling, {"Lua-APClientPP"}, {0, 5, 0})
    end

    function on_slot_connected(data)
        log.info("Slot connected")
        connected = true
        slotData = data
        curPlayerSlot = ap:get_player_number()

        if data.grouping == 0 then
            locationsMissing = ap.missing_locations
        elseif data.grouping == 2 then
            for _, loc in ipairs(ap.missing_locations) do
                name = ap:get_locations_name(loc)
                map = string.match(name, "(.*):")
                table.insert(mapGroup[map], 1, loc)
            end
        end

        if pickupStepOverride == -1 then
            pickupStepOverride = data.itemPickupStep
        end

        if deathLink == true then
            ap:ConnectUpdate(nil, { "Lua-APClientPP", "DeathLink" })
        end
    end


    function on_slot_refused(reasons)
        log.info("Slot refused: " .. table.concat(reasons, ", "))
    end

    function on_items_received(items)
        if(skipItemSend) then
            return
        end
        log.info("Items: ")

        for _, item in ipairs(items) do 
            log.info(item.item)
            if initialSetup and (item.item == 250202 or item.item == 250203) then
            elseif item.item < 250300 then
                table.insert(itemsBuffer, 1, item)
            elseif item.item < 250400 then
                if item.item == 250302 then
                    table.insert(unlockedStages, 2)
                elseif item.item == 250303 then
                    table.insert(unlockedStages, 3)
                elseif item.item == 250304 then
                    table.insert(unlockedStages, 4)
                elseif item.item == 250305 then
                    table.insert(unlockedStages, 5)
                elseif item.item == 250306 then
                    table.insert(unlockedStages, progStage)
                    progStage = progStage + 1
                end
                if runStarted == true then
                    refreshOverride()
                end
            else
                table.insert(unlockedMaps, ap:get_item_name(item.item))
                if runStarted == true then
                    refreshOverride()
                end
            end
        end

        skipItemSend = false
        initialSetup = false
    end

    function on_location_info(items)
        log.info("Locations scouted:")
        for _, item in ipairs(items) do
            log.info(item.item) 
        end
    end

    function on_location_checked(locations)
        log.info("Locations checked:" .. table.concat(locations, ", "))
        log.info("Checked locations: " .. table.concat(ap.checked_locations, ", "))
    end

    function on_data_package_changed(data_package)
        log.info("Data package changed:")
        log.info(data_package)
    end

    function on_print(msg)
        log.info(msg)
        console = msg .. "\n"
    end

    function on_print_json(msg, extra)
        log.info(ap:render_json(msg, message_format))
        for key, value in pairs(extra) do
            -- log.info("  " .. key .. ": " .. tostring(value))
        end
    end

    function on_bounced(bounce)
        log.info("Bounced:")
        log.info(bounce)
    end

    function on_retrieved(map, keys, extra)
        log.info("Retrieved:")
        -- since lua tables won't contain nil values, we can use keys array
        for _, key in ipairs(keys) do
            log.info("  " .. key .. ": " .. tostring(map[key]))
        end
        -- extra will include extra fields from Get
        log.info("Extra:")
        for key, value in pairs(extra) do
            log.info("  " .. key .. ": " .. tostring(value))
        end
        -- both keys and extra are optional
    end

    function on_set_reply(message)
        log.info("Set Reply:")
        for key, value in pairs(message) do
            log.info("  " .. key .. ": " .. tostring(value))
            if key == "value" and type(value) == "table" then
                for subkey, subvalue in pairs(value) do
                    log.info("    " .. subkey .. ": " .. tostring(subvalue))
                end
            end
        end
    end

    
    local uuid = ""
    ap = AP(uuid, game_name, server);

    ap:set_socket_connected_handler(on_socket_connected)
    ap:set_socket_error_handler(on_socket_error)
    ap:set_socket_disconnected_handler(on_socket_disconnected)
    ap:set_room_info_handler(on_room_info)
    ap:set_slot_connected_handler(on_slot_connected)
    ap:set_slot_refused_handler(on_slot_refused)
    ap:set_items_received_handler(on_items_received)
    ap:set_location_info_handler(on_location_info)
    ap:set_location_checked_handler(on_location_checked)
    ap:set_data_package_changed_handler(on_data_package_changed)
    ap:set_print_handler(on_print)
    ap:set_print_json_handler(on_print_json)
    ap:set_bounced_handler(on_bounced)
    ap:set_retrieved_handler(on_retrieved)
    ap:set_set_reply_handler(on_set_reply)
end

--------------------------------------------------
-- Main                                         --
--------------------------------------------------

-- Connection Screen
gui.add_imgui(function()
    if ImGui.Begin("Connection") then
        con = "Connect"
        if connection then
            con = "Disconnect"
        end
        address = ImGui.InputText("Server Address", address, 100)
        slot = ImGui.InputText("slot", slot, 100)
        password = ImGui.InputText("password", password, 100)

        if ImGui.Button(con) then
            if not connected then
                log.info("Attempting connection with " .. address .. " " .. slot .. " " .. password)
                connect(address, slot, password)
            else
                ap = nil
                connected = false
            end
        end
    end
 
    ImGui.End()
end)

-- Game Loop
gm.pre_script_hook(gm.constants.__input_system_tick, function()
    if ap then
        ap:poll()

        player = getPlayer()
        if next(itemsBuffer) ~= nil and player ~= nil then
            local item = table.remove(itemsBuffer)
            print("Sending: " .. item.item)
            if item.item ~= 250006 then
                giveItem(item, player)
                table.insert(itemsCollected, item)
            else
                teleFrags = teleFrags + 1
                table.insert(itemQueue, "Teleporter Fragment")
            end
        end
    end
end)

-- New Run Check
gm.post_script_hook(gm.constants.init_player, function(self)
    print("Sending ".. #itemsCollected .. " items")
    if ap then
        for _, item in ipairs(itemsCollected) do
            print("Sending: " .. item.item)
            giveItem(item, self)
        end
    end
end)

-- Item Send
gm.post_script_hook(gm.constants.item_give, function(self, other, result, args)
    if ap then
        local actor = args[1].value
        if actor.object_index == gm.constants.oP then
            
        end
    end
end)

--------------------------------------------------
-- Functions                                    --
--------------------------------------------------

-- Item Handler
function giveItem(item, player)
    local class_item = gm.variable_global_get("class_item")
    local class_equipment = gm.variable_global_get("class_equipment")

    if item.item == nil then
        return
    end

    local itemSent = nil
    local rarity = nil
    local itemId = nil

    -- Items
    if item.item == 250001 then -- Common Item
        rarity = 0
    elseif item.item == 250002 then -- Uncommon Item
        rarity = 1
    elseif item.item == 250003 then -- Rare Item
        rarity = 2
    elseif item.item == 250004 then -- Boss Item
        rarity = 4
    elseif item.item == 250005 then -- Equipment
        equipment = nil
        repeat
            itemId = gm.irandom_range(0, #class_equipment - 1)
            equipment = class_equipment[itemId + 1]
        until equipment[7] == 3 and (equipment[11] == nil or gm.achievement_is_unlocked(equipment[11]))
        gm.instance_create_depth(player.x, player.y, 0, equipment[9])
    
    -- Fillers
    elseif item.item == 250101 then -- Money
        
    elseif item.item == 250102 then -- Experience
        

    -- Traps
    elseif item.item == 250201 then -- Time Warp
        
    elseif item.item == 250202 and runStarted then -- Combat
        
    elseif item.item == 250203 and runStarted then -- Meteor
        
    end

    if rarity ~= nil then
        repeat
            itemId = gm.irandom_range(0, #class_item - 1)
            itemSent = class_item[itemId + 1]
        until itemSent[7] == rarity and (itemSent[11] == nil or gm.achievement_is_unlocked(itemSent[11]))

        gm.item_give(player, itemId, 1)

        -- table.insert(itemQueue, itemSent[2])
    end
end

-- Find Player
function getPlayer()
    for i = 1, #gm.CInstance.instances_active do
        if gm.CInstance.instances_active[i].object_index == gm.constants.oP then
            return gm.CInstance.instances_active[i]
        end
    end
    return nil
end