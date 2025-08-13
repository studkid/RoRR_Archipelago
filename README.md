# Archipelago for Risk of Rain Returns
This mod adds support for Risk of Rain Returns for Archipelago.  
This mod does nothing on it's own and a full detailed setup guide can be found [here](https://github.com/studkid/Archipelago/blob/main/worlds/ror1/docs/setup_RoRR_en.md)

# How does this work
This is written assuming a basic understanding of how Archipelago works; you can find more information on it at their site at https://archipelago.gg/.

## Checks
All item pickups count as an item check.  When picking up an item, it will be removed and a location will be sent out.  With the `item_pickup_step` yaml option (and ingame setting), you can set an interval for how many items you want to pickup normally before one is sent to the multiworld.  Total number of checks can be set in the yaml settings.

Checks can also be grouped either based on map or universally.
### Universal grouping
All locations can be obtained anywhere in numbered order.

### Map Grouping
Locations are split between each individual map.  You must be on that specific map to send out it's given check.

In addition to this, all maps and stages will require the given item to be sent to you.  The rules for when you can access these stages are as follows
- You will need both the map and numbered stage (or the corresponding number of progressive stages if enabled) to enter.
   - You can disable the stage item requirement by disabling `require_stage` in the yaml
- With `strict_stage_prog` enabled, you can additionally set a requirement on if you need to have a prior stage and access to one of those maps to enter a later stage map.  
   - For example, to get to Ancient Valley, you need `Stage 2` and either `Sky Meadow` or `Damp Caverns` in addition to `Stage 3` and `Ancient Valley`.

In the settings, you can enable an option that will prioritize maps that have the most checks in them (currently defaulted to disabled until further testing is done with it).

## Goal
Goal is set to release after defeating Providence at Risk of Rain.  The divine teleporter's spawn conditions can be tweaked in the yaml to make it so goaling isn't possible instantly.
- On map grouping mode, `Risk of Rain` is required to enter the final stage.
- If `stage_five_tp` is enabled, the divine teleporter is set to spawn exclusively on a stage 5 map (which would be Temple of the Elders without mods).
   - This is recommended for map mode, otherwise you will be able to goal the instant `Risk of Rain` is sent unless you have teleporter fragments enabled.
- You can enable "Teleporter Fragments" to be shuffled into the pool and set a certain percentage that needs to be found before the divine teleporter can spawn.

**Note, currently the teleporter will not dynamically update to a divine teleporter, so once you get your goal items, you will need to do at least one more stage for it to spawn.**

# Does this support the Providence Trials
No, and I have no plans on adding support for it for the time being.

# Does this support multiplayer
Not currently, but it's planned once a bit more polishing is done.

# Does this work with other mods?
This is currently untested.  However, most item and survivor mods should work.  Stage mods may work still with universal grouping mode, but would at best do nothing on map grouping mode.

# Archipelago YAML Settings
Currently, this implementation works off of the Risk of Rain 1 apworld, which you can download from its [Github](https://github.com/studkid/RoR_Archipelago/releases).
Traps are not currently implemented yet, so it's recommended to turn them off.

# How to connect to an Archipelago Server
- Open up the ImGUI window (default keybind is `insert`)
- Type in server address, slot, and password (if applicable) into the "Connection" window, then press "Connect"
- If the tracker window is updated to show your current progress you should be connected

Currently there is not any ingame UI to relay server information, so it's recommended to have a text client open for this reason.

# Known issues
- Temporary items (notably ones created by drifter) are counted as an item check
- Disconnecting and reconnecting can cause the tracker to display more checks than are actually there.  Also leads to the game removing items in an attempt to send already checked locations out.