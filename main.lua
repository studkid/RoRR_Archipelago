require("staticvars")
local AP = require("./lua-apclientpp")
mods["RoRRModdingToolkit-RoRR_Modding_Toolkit"].auto()

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
local skipItemCollectedAdd = false
local itemsBuffer = {}
local locationsMissing = {}
local skipItemSend = false
local mapGroup = {
    ["desolateForest"] =         {},
    ["driedLake"] =              {},
    ["dampCaverns"] =            {},
    ["skyMeadow"] =              {},
    ["ancientValley"] =          {},
    ["sunkenTombs"] =            {},
    ["magmaBarracks"] =          {},
    ["hiveCluster"] =            {},
    ["templeOfTheElders"] =      {}
}
local unlockedMaps = {}
local unlockedStages = {1, 6}
local progStage = 2
local mapOrder = {}

-- AP Data
local slotData = nil
local curPlayerSlot = nil
local pickupStepOverride = -1
local deathLink = false
local ringLink = false
local trapLink = false
local equipLink = false
local lastRingTime = 0
local warpToMostChecks = false
local teleFrags = 0
local expBuffer = 0
local maxEquip = 100
local bounceMsg = nil
local instanceID = os.time()

-- Game Data
local initialSetup = true
local pickupStep = 0
local canStep = true
local stageProg = 1
local curMap = nil
local playerInst = nil
local gameStarted = false
local deathLinkRec = false
local equipLinkRec = false
local lastGoldAmt = 0

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
        ap:ConnectSlot(slot, password, items_handling, {}, {0, 5, 0})
    end

    function on_slot_connected(data)
        log.info("Slot connected")
        connected = true
        slotData = data
        curPlayerSlot = ap:get_player_number()

        if data.grouping == 0 then
            locationsMissing = ap.missing_locations
        elseif data.grouping == 2 then
            resetMapArray()
            for _, loc in ipairs(ap.missing_locations) do
                name = ap:get_location_name(loc, ap:get_game())
                map = string.match(name, "(.*):"):gsub("%s", ""):gsub("^%u", string.lower)
                
                if map == "templeoftheElders" then
                    map = "templeOfTheElders"
                end

                if arrayContains(mapGroup[map], loc) == nil then
                    table.insert(mapGroup[map], 1, loc)
                end
            end
        end

        if pickupStepOverride == -1 then
            pickupStepOverride = data.itemPickupStep
        end

        ap:ConnectUpdate(nil, getApTags())

        -- Fill mapOrder
        local stageProgOrder = Array.wrap(gm.variable_global_get("stage_progression_order"))
        for i, maps in ipairs(stageProgOrder) do
            mapOrder[i] = List.wrap(maps)
        end
    end


    function on_slot_refused(reasons)
        log.info("Slot refused: " .. table.concat(reasons, ", "))
    end

    function on_items_received(items)
        if(skipItemSend) then
            return
        end
        -- log.info("Items: ")

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
                    log.info("progStage: " .. progStage)
                    progStage = progStage + 1
                end
            else
                local stageItem = ap:get_item_name(item.item, ap:get_game()):gsub("%s", ""):gsub("^%u", string.lower)

                -- Make this better please
                if stageItem == "templeoftheElders" then
                    stageItem = "templeOfTheElders"
                elseif stageItem == "riskofRain" then
                    stageItem = "riskOfRain"
                end

                table.insert(unlockedMaps, stageItem)
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
        -- log.info("Checked locations: " .. table.concat(ap.checked_locations, ", "))
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
        bounceMsg = bounce
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
        local con = "Connect"
        if connected then
            con = "Disconnect"
        end
        address = ImGui.InputText("Server Address", address, 100)
        slot = ImGui.InputText("Slot", slot, 100)
        password = ImGui.InputText("Password", password, 100)

        if ImGui.Button(con) then
            if not connected then
                log.info("Attempting connection with " .. address .. " " .. slot .. " " .. password)
                connect(address, slot, password)
            else
                ap = nil
                connected = false
                itemsCollected = {}
                skipItemSend = true
                unlockedStages = {1, 6}
                teleFrags = 0
            end
        end
        ImGui.End()
    end
    

    if ImGui.Begin("Tracker") and connected then
        ImGui.Text("Pickup Step: " .. pickupStep .. "/" .. pickupStepOverride)
        ImGui.Text("Teleporter Fragments: " .. teleFrags .. "/" .. slotData.requiredFrags)

        if slotData.grouping == 0 then
            ImGui.Text(map .. " " .. #ap.missing_locations .. "/" .. slotData.totalLocations)
        else
            for i, stage in ipairs(mapOrder) do
                if arrayContains(unlockedStages, i) then
                    ImGui.PushStyleColor(ImGuiCol.Text, 0xFFFFFF20)
                else
                    ImGui.PushStyleColor(ImGuiCol.Text, 0xEECCCCCC)
                end

                ImGui.Text("Stage " .. i)
                ImGui.PopStyleColor()

                for _, mapId in ipairs(stage) do
                    local map = Stage.wrap(mapId).identifier

                    if arrayContains(unlockedMaps, map) then
                        ImGui.PushStyleColor(ImGuiCol.Text, 0xFFFFFF20)
                    else
                        ImGui.PushStyleColor(ImGuiCol.Text, 0xEECCCCCC)
                    end

                    if mapGroup[map] then
                        ImGui.Text(map .. " " .. #mapGroup[map] .. "/" .. slotData.totalLocations)
                        ImGui.PopStyleColor();
                    else
                        ImGui.Text(map)
                    end
                    ImGui.PopStyleColor()
                end
            end
        end

        ImGui.End()
    end

    if ImGui.Begin("Settings") then
        pickupStepOverride = ImGui.InputInt("Pickup Step", pickupStepOverride)
        warpToMostChecks = ImGui.Checkbox("Always pick stage with most checks remaining", warpToMostChecks)
        maxEquip = ImGui.InputInt("Maximum Equipment on Run Start", maxEquip)
        deathLink = ImGui.Checkbox("Deathlink", deathLink)
        ringLink = ImGui.Checkbox("Ring Link", ringLink) 
        trapLink = ImGui.Checkbox("Trap Link", trapLink) 
        equipLink = ImGui.Checkbox("Equipment Link", equipLink) 
        if connected then
            if ImGui.Button("Update Tags") then
                ap:ConnectUpdate(nil, getApTags())
            end
        end

        ImGui.End()
    end
end)

-- Game Loop
gm.pre_script_hook(gm.constants.__input_system_tick, function()
    if not ap then return end
    ap:poll()

    player = getPlayer()
    if next(itemsBuffer) ~= nil and player ~= nil then
        local item = table.remove(itemsBuffer)
        log.info("Sending: " .. item.item)
        if item.item ~= 250006 then
            giveItem(item, player)
            if skipItemCollectedAdd then
                skipItemCollectedAdd = false
            else
                table.insert(itemsCollected, item)
            end
        else
            teleFrags = teleFrags + 1
            -- table.insert(itemQueue, "Teleporter Fragment")
        end
    end

    if expBuffer > 0 and player ~= nil then
        local director = gm._mod_game_getDirector()
        director.player_exp = expBuffer
        expBuffer = expBuffer - director.player_exp_required
    end

    -- Ignore bounce if run isn't started
    if not runStarted and bounceMsg ~= nil then
        bounceMsg = nil
    end
end)

-- onPlayerDeath
Callback.add("onDeath", "AP_deathCheck", function(actor, oob)
    if not deathLink then return end
    if actor.object_index ~= gm.constants.oP then return end

    if deathLinkRec then 
        deathLinkRec = false 
        return
    end

    if debug then log.info("Sending DeathLink") end
    ap:Bounce({
        time = os.time(),
        cause = slot .. deathMessages[math.random(#deathMessages)],
        source = instanceID,
    }, nil, nil, {"DeathLink"})
end)

-- onPlayerStep
Callback.add("onPlayerStep", "AP_onPlayerStep", function(player)
    if not ap then return end

    -- RingLink
    if ringLink then
        local teleInst = Instance.find(Instance.teleporters)

        local director = gm._mod_game_getDirector()
        local ohud = gm._mod_game_getHUD()
        local curGoldAmt = ohud.gold
        local goldDiff = 0

        if lastGoldAmt == 0 then
            lastGoldAmt = curGoldAmt
        else
            goldDiff = curGoldAmt - lastGoldAmt
            -- print("lastGoldAmt: " .. lastGoldAmt .. " curGoldAmt " .. curGoldAmt .. " goldDiff " .. goldDiff)
            lastGoldAmt = curGoldAmt
        end

        if goldDiff ~= 0 then
            -- log.info(goldDiff .. " " .. tag)
            ap:Bounce({
                time = os.time(),
                source = instanceID,
                amount = math.ceil(goldDiff / director.enemy_buff)
            }, nil, nil, {"RingLink"})
        end
    end

    -- Bounce Handler
    if bounceMsg then
        local tag = bounceMsg["tags"]
        if tag ~= nil then
            if debug then 
                log.info("data = {")
                for index, data in pairs(bounceMsg["data"]) do
                    log.info("  " .. index .. " = " .. tostring(data))
                end
                log.info("}") 
                log.info("tags = [\"" .. table.concat(tag, "\", \"") .. "\"]")
            end
            if arrayContains(tag, "DeathLink") then
                handleDeathLink(bounceMsg, player)
            elseif arrayContains(tag, "RingLink") then
                handleRingLink(bounceMsg)
            elseif arrayContains(tag, "TrapLink") then
                handleTrapLink(bounceMsg, player)
            elseif arrayContains(tag, "EquipLink") then
                handleEquipLink(bounceMsg, player)
            end
        end
        bounceMsg = nil
    end
end)

-- New Run Check 
Callback.add("onPlayerInit", "AP_newRunCheck", function(player)
    runStarted = true
    playerInst = player
    if ap then
        log.info("Sending ".. #itemsCollected .. " items")
        
        equipCount = 0
        for _, item in ipairs(itemsCollected) do
            -- log.info("Sending: " .. item.item)
            if item.item == 250005 then
                equipCount = equipCount + 1
            end

            giveItem(item, player)

        end
    end
end)

Callback.add("onGameStart", "AP_onGameStart", function()
    stageProg = 0
    gameStarted = true
end)

Callback.add("onGameEnd", "AP_onGameEnd", function()
    gameStarted = false
end)

-- Equipment Link
Callback.add("onEquipmentUse", "AP_EquipLink", function(player, equipment, embryo, direction)
    if not TrapLink and not ap then return end

    if equipLinkRec then
        equipLinkRec = false
        return
    end

    ap:Bounce({
        time = os.time(),
        source = instanceID,
        namespace = equipment.namespace,
        identifier = equipment.identifier,
        double = embryo
    }, nil, nil, {"EquipLink"})
end)

-- Location Checks
gm.post_script_hook(gm.constants.item_give, function(self, other, result, args)
    if ap and canStep then
        local actor = args[1].value
        if actor.object_index == gm.constants.oP then
            log.info(curMap)

            if slotData.grouping == 0 and #locationsMissing ~= 0 then
                locationsChecked = {}

                if pickupStep == pickupStepOverride then
                    table.insert(locationsChecked, ap.missing_locations[1])
                    ap:LocationChecks(locationsChecked)
                    gm.item_take(actor, args[2], 1, args[4])
                    pickupStep = 0
                else
                    pickupStep = pickupStep + 1
                end
            elseif curMap ~= "riskOfRain" and #mapGroup[curMap] ~= 0 then
                locationsChecked = {}
                map = curMap
                log.info(pickupStepOverride)
    
                if pickupStep == pickupStepOverride then
                    table.insert(locationsChecked, table.remove(mapGroup[curMap]))
                    ap:LocationChecks(locationsChecked)
                    gm.item_take(actor, args[2], 1, args[4])
                    pickupStep = 0
                else
                    pickupStep = pickupStep + 1
                end
            end
            log.info("Pickup Step: " .. pickupStep)
        end
    end
end)

-- Epic Teleporter Logic
gm.post_script_hook(gm.constants.stage_should_spawn_epic_teleporter, function(self, other, result, args)
    if not connected and not slotData.grouping == 0 then return end

    result.value = canEnterFinalStage()
end)

-- Stage Locking
gm.post_script_hook(gm.constants.stage_roll_next, function(self, other, result, args)
    local teleInst = Instance.find(Instance.teleporters)
    if teleInst:exists() then
        log.info(teleInst.active)
    end

    -- Why did I have this check for tele active state?  Was this some old carry over I don't need anymore??
    if not connected or slotData.grouping == 0 or teleInst.active == 7 then return end
    local nextStage = nil
    
    while nextStage == nil do 
        stageProg = math.fmod(stageProg, 5) + 1
        log.info("Stage Prog: " .. stageProg)

        if arrayContains(unlockedStages, stageProg) then
            local newProgression = {}
            for _, mapId in ipairs(mapOrder[stageProg]) do
                local map = Stage.wrap(mapId)
                if arrayContains(unlockedMaps, map.identifier) ~= nil then
                    table.insert(newProgression, mapId)
                end
            end
        
            if #newProgression > 0 then
                log.info(Stage.wrap(newProgression[1]).identifier)
                if #newProgression == 1 then 
                    nextStage = newProgression[1]
                elseif warpToMostChecks then
                    local lastMap = nil
                    for i, mapId in ipairs(newProgression) do
                        local map = Stage.wrap(mapId)
                        
                        if lastMap == nil then           
                        elseif #mapGroup[map.identifier] > #mapGroup[lastMap.identifier] then
                            nextStage = newProgression[i]
                        elseif #mapGroup[map.identifier] < #mapGroup[lastMap.identifier] then
                            nextStage = newProgression[i - 1]
                        else
                            nextStage = newProgression[math.random(#newProgression)]
                        end

                        lastMap = map
                    end
                else
                    nextStage = newProgression[math.random(#newProgression)]
                end
            else
                if slotData.strictStageProg == 1 then
                    stageProg = 0
                end
            end
        end
        log.info(nextStage)
    end

    curMap = Stage.wrap(nextStage).identifier
    -- log.info(curMap)
    result.value = nextStage
end)

-- Game Win Check
gm.post_script_hook(gm.constants.ending_find, function(self, other, result, args)
    log.info(args[1].value)
    if ap and args[1].value == "ror-won" then
        ap:StatusUpdate(30)
    end
end)

--------------------------------------------------
-- UI Additons                                  --
--------------------------------------------------

-- add_callback("onPlayerHUDDraw", 1, function(self, other, result, args)
--     cam = gm.view_get_camera(0)
--     gm.draw_text(100, 900, "Test")
--     -- log.info(gm.camera_get_view_height(cam))
-- end, false)

--------------------------------------------------
-- Functions                                    --
--------------------------------------------------

-- Checks array for value
function arrayContains(tab, val)
    for i, value in ipairs(tab) do
        if value == val then
            return i
        end
    end
    return nil
end

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
    elseif item.item == 250003 then -- Rare Itemsource
    elseif item.item == 250004 then -- Boss Item
        rarity = 4
    elseif item.item == 250005 then -- Equipment
        equipment = nil
        repeat
            itemId = gm.irandom_range(0, #class_equipment - 1)
            equipment = class_equipment[itemId + 1]
        until equipment[7] == 3 and (equipment[11] == nil or gm.achievement_is_unlocked(equipment[11]))
        if player.x == 0 and player.y == 0 then
            table.insert(itemsBuffer, item)
            skipItemCollectedAdd = true
        else
            gm.instance_create_depth(player.x, player.y, 0, equipment[9])
        end
    
    -- Fillers
    elseif item.item == 250101 then -- Money
        local director = gm._mod_game_getDirector()
        local ohud = gm._mod_game_getHUD()
        ohud.gold = ohud.gold + (100 * director.enemy_buff)
    elseif item.item == 250102 then -- Experience
        expBuffer = expBuffer + 1000

    -- Traps
    elseif item.item == 250201 then -- Time Warp
        
    elseif item.item == 250202 and runStarted then -- Combat
        
    elseif item.item == 250203 and runStarted then -- Meteor
        sendTrap("Meteor Trap", player, false)
    end

    if rarity ~= nil then
        repeat
            itemId = gm.irandom_range(0, #class_item - 1)
            itemSent = class_item[itemId + 1]
        until itemSent[7] == rarity and (itemSent[11] == nil or gm.achievement_is_unlocked(itemSent[11]))

        canStep = false
        -- log.info("Giving: " .. itemSent[2] .. " Id: " .. itemId)
        gm.item_give(player.object_index, itemId, 1)
        canStep = true
    end
end

function canEnterFinalStage()
    return slotData.requiredFrags <= teleFrags and (slotData.grouping == 0 or arrayContains(unlockedMaps, "riskOfRain") ~= nil) and (slotData.stageFiveTp == 0 or stageProg == 5)
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

-- DeathLink Handler
function handleDeathLink(msg, player)
    local cause = msg["data"]["cause"]
    local source = msg["data"]["source"]

    if source ~= instanceID and deathLink then
        deathLinkRec = true
        player:kill()
        if cause == nil then
            local death = source .. " died"
            log.info(death)
            -- table.insert(messageQueue, death)
        else
            log.info(cause)
            -- table.insert(sendMsgQueue, cause)
        end
    end
end


-- RingLink Handler
function handleRingLink(msg)
    local amount = msg["data"]["amount"]
    local source = msg["data"]["source"]
    if debug then log.info(source .. " sending " .. amount .. " gold") end

    if source ~= instanceID and ringLink then
        local director = gm._mod_game_getDirector()
        local ohud = gm._mod_game_getHUD()
        newGoldAmt = math.max(ohud.gold + (amount * director.enemy_buff), 0)
        if debug then log.info(newGoldAmt) end
        lastGoldAmt = newGoldAmt
        ohud.gold = newGoldAmt
    end
end

-- TrapLink Handler
function handleTrapLink(msg, player)
    local name = msg["data"]["trap_name"]
    local source = msg["data"]["source"]

    if source ~= slot and trapLink then
        if debug then log.info(source .. " recieving " .. name) end
        sendTrap("Meteor Trap", player, true)
    end
end

function sendTrap(trapName, player, linked)
    if trapName == "Meteor Trap" then
        equipLinkRec = true
        player:item_use_equipment(true, Equipment.find("ror", "glowingMeteorite").value, true)
        equipLinkRec = true
        player:item_use_equipment(true, Equipment.find("ror", "glowingMeteorite").value, true)
        equipLinkRec = true
        player:item_use_equipment(true, Equipment.find("ror", "glowingMeteorite").value, true)
        equipLinkRec = true
        player:item_use_equipment(true, Equipment.find("ror", "glowingMeteorite").value, true)
        equipLinkRec = true
        player:item_use_equipment(true, Equipment.find("ror", "glowingMeteorite").value, true)
    end

    if trapLink and not linked then
        ap:Bounce({
            time = os.time(),
            source = slot,
            trap_name = trapName
        }, nil, nil, {"TrapLink"})
    end
end

-- EquipLink Handler
function handleEquipLink(msg, player)
    local name = msg["data"]["trap_name"]
    local source = msg["data"]["source"]
    local namespace = msg["data"]["namespace"]
    local identifier = msg["data"]["identifier"]
    local double = msg["data"]["double"]

    if source ~= instanceID and equipLink then
        log.info("EquipLink Sending " .. identifier)
        equipment = Equipment.find(namespace, identifier).value
        direction, bool = player:get_equipment_use_direction()
        if equipment ~= nil then
            equipLinkRec = true
            player:item_use_equipment(true, equipment, true, direction)
        else
            log.info("EquipLink item not found: " .. identifier .. " from " .. namespace)
            log.info("If you're seeing this for a vanilla item, this is likely an error.  If this is a modded item let me know and I'll add it to the mapping!")
        end
    end
end

function getApTags()
    local tags = {  }

    if deathLink == true then
        table.insert(tags, "DeathLink")
    end

    if ringLink then
        table.insert(tags, "RingLink")
    end

    if trapLink then
        table.insert(tags, "TrapLink")
    end

    if equipLink then
        table.insert(tags, "EquipLink")
    end

    return tags
end

function resetMapArray()
    for _, i in ipairs(mapGroup) do
        i = {}
    end
end