-- Sky Islands BN Port - Proof of Concept
-- main.lua - Main implementation

local mod = game.mod_runtime[game.current_mod]
local storage = game.mod_storage[game.current_mod]

-- Constants
local WARP_SICKNESS_INTERVAL = TimeDuration.from_minutes(5)
local SICKNESS_STAGES = {
  { threshold = 1, message = "Your body shivers slightly as a warp pulse passes through it. Warp sickness won't set in for another 7 pulses.", intensity = 6 },
  { threshold = 2, message = "Your body shivers slightly as a warp pulse passes through it. Warp sickness won't set in for another 6 pulses.", intensity = 6 },
  { threshold = 3, message = "Your body shivers slightly as a warp pulse passes through it. Warp sickness won't set in for another 5 pulses.", intensity = 6 },
  { threshold = 4, message = "Your body shivers slightly as a warp pulse passes through it. Warp sickness won't set in for another 4 pulses.", intensity = 6 },
  { threshold = 5, message = "Your body shivers slightly as a warp pulse passes through it. Warp sickness won't set in for another 3 pulses.", intensity = 6 },
  { threshold = 6, message = "Your body shivers slightly as a warp pulse passes through it. Warp sickness won't set in for another 2 pulses.", intensity = 6 },
  { threshold = 7, message = "Your body shivers slightly as a warp pulse passes through it. Warp sickness won't set in for another 1 pulse.", intensity = 6 },
  { threshold = 8, message = "Goosebumps cover your skin as a warp pulse passes through you. You're only one warp pulse from your deadline.", intensity = 6 },
  { threshold = 9, message = "A warp pulse passing through you twists your blood inside your veins and your eyes pulse in pain. You've overstayed your welcome and need to get home.", intensity = 5 },
  { threshold = 10, message = "A warp pulse shudders through your head like a localized earthquake and your extremities surge with pain like they're peeling open. You need to get home as soon as possible.", intensity = 4 },
  { threshold = 11, message = "Another warp pulse rocks through you and your organs wrench themselves over. Existence is fracturing. You need to get home immediately.", intensity = 3 },
  { threshold = 12, message = "A sickening wet sound rips through you as another warp pulse hits. You can feel your whole body trying to pull itself apart, and if you wait any longer, it just might. If you want to live, you need to get home NOW!", intensity = 2 },
  { threshold = 13, message = "As the warp pulse hits, you realize there are no words to describe how much trouble you're in. Your body is crumbling to wet paste and your blood is twisting into a viny tangle. All you know is pain.\nYou're not just dying, you're dying horribly.\nIf escape is already near you may survive against all odds, but oblivion is only moments away.", intensity = 1 }
}

-- Initialize storage defaults (only for new games)
-- These will be overwritten by saved data on load
storage.home_location = storage.home_location or nil
storage.is_away_from_home = storage.is_away_from_home or false
storage.sickness_counter = storage.sickness_counter or 0
storage.raids_total = storage.raids_total or 0
storage.raids_won = storage.raids_won or 0
storage.raids_lost = storage.raids_lost or 0

-- Mission reward table (mission_name -> shard count)
-- HACK: We're using mission names instead of mission type IDs because BN's Lua bindings
-- don't expose mission_type.id. The mission_type class exists in Lua but its 'id' field
-- is not bound (see catalua_bindings_mission.cpp line 47 comment). We could use
-- mission:get_type() but can't access .id on it. Using names works but is fragile if
-- mission names change. Ideally BN should expose mission_type.id or add a method like
-- mission:get_type_id_str() to make this cleaner.
local MISSION_REWARDS = {
  -- MGOAL_KILL_MONSTER_SPEC missions
  ["RAID: Kill 10 Zombies"] = 1,
  ["RAID: Kill 50 Zombies"] = 3,
  ["RAID: Kill 100 Zombies"] = 5,
  ["RAID: Kill a Mi-Go"] = 3,
  ["RAID: Kill 3 Nether Creatures"] = 4,
  ["RAID: Kill 5 Birds"] = 1,
  ["RAID: Kill 5 Mammals"] = 1,

  -- MGOAL_KILL_MONSTERS (combat) missions
  ["RAID: Clear zombie cluster"] = 3,
  ["RAID: Clear zombie horde"] = 4,
  ["RAID: Clear evolved zombies"] = 4,
  ["RAID: Clear evolved horde"] = 5,
  ["RAID: Clear fearsome zombies"] = 5,
  ["RAID: Clear elite zombies"] = 8,
  ["RAID: Kill zombie lord"] = 10,
  ["RAID: Kill zombie superteam"] = 10,
  ["RAID: Kill zombie leader + swarm"] = 12,
  ["RAID: Kill horde lord"] = 12,
  ["RAID: Clear mi-go threat"] = 9,
  ["RAID: Kill mi-go overlord"] = 12,
}

-- Helper: Give mission reward
local function give_mission_reward(player, mission_type_id, count)
  if count and count > 0 then
    -- Give warp shards directly using add_item_with_id
    -- BN requires an itype_id userdata object (string_id<itype>)
    local shard_id = ItypeId.new("skyisland_warp_shard")
    player:add_item_with_id(shard_id, count)
    gapi.add_msg(string.format("You completed a mission and were rewarded with %d warp shard%s.", count, count > 1 and "s" or ""))
    gdebug.log_info(string.format("Awarded %d warp shards for mission %s", count, mission_type_id))
  end
end

-- Helper: Get player position in OMT coordinates
local function get_player_omt()
  local player = gapi.get_avatar()
  if not player then return nil end

  local pos_ms = player:get_pos_ms()
  local abs_ms = gapi.get_map():get_abs_ms(pos_ms)
  local omt, _ = coords.ms_to_omt(abs_ms)
  return omt
end

-- Helper: Teleport player to OMT coordinates with offset
local function teleport_to_omt(omt, offset_tiles)
  gdebug.log_info(string.format("Teleporting to OMT: %s, %s, %s", omt.x, omt.y, omt.z))
  gapi.place_player_overmap_at(omt)

  -- If offset specified, move player after teleport
  if offset_tiles then
    local player = gapi.get_avatar()
    if player then
      local current_pos = player:get_pos_ms()
      local new_pos = Tripoint.new(
        current_pos.x + offset_tiles.x,
        current_pos.y + offset_tiles.y,
        current_pos.z + offset_tiles.z
      )
      player:set_pos_ms(new_pos)
      gdebug.log_info(string.format("Applied offset: %d, %d, %d", offset_tiles.x, offset_tiles.y, offset_tiles.z))
    end
  end

  gapi.add_msg("You feel reality shift around you...")
end

-- Create extraction mission
mod.create_extraction_mission = function(center_omt)
  local player = gapi.get_avatar()
  if not player then return end

  -- Pick exit location 5-10 OMTs away from player spawn
  local exit_omt = Tripoint.new(
    center_omt.x + gapi.rng(-10, 10),
    center_omt.y + gapi.rng(-10, 10),
    center_omt.z
  )

  -- Store exit location for tracking
  storage.exit_location = { x = exit_omt.x, y = exit_omt.y, z = exit_omt.z }

  -- Create and assign mission using BN's mission API
  local player_id = player:getID()

  -- Create mission_type_id like we do TerId
  local mission_type = MissionTypeIdRaw.new("MISSION_REACH_EXTRACT")

  local new_mission = Mission.reserve_new(mission_type, player_id)
  if new_mission then
    new_mission:assign(player)
    gapi.add_msg("Mission: Reach the exit portal!")
    gdebug.log_info(string.format("Created extraction mission at: %d, %d, %d", exit_omt.x, exit_omt.y, exit_omt.z))
  else
    gdebug.log_error("Failed to create extraction mission!")
  end
end

-- Create treasure mission
mod.create_treasure_mission = function(center_omt)
  local player = gapi.get_avatar()
  if not player then return end

  -- Pick treasure location 5-10 OMTs away from player spawn
  local treasure_omt = Tripoint.new(
    center_omt.x + gapi.rng(-10, 10),
    center_omt.y + gapi.rng(-10, 10),
    center_omt.z
  )

  local player_id = player:getID()
  local mission_type = MissionTypeIdRaw.new("MISSION_BONUS_TREASURE")

  local new_mission = Mission.reserve_new(mission_type, player_id)
  if new_mission then
    new_mission:assign(player)
    gapi.add_msg("Bonus Mission: Find the warp shards!")
    gdebug.log_info(string.format("Created treasure mission at: %d, %d, %d", treasure_omt.x, treasure_omt.y, treasure_omt.z))
  else
    gdebug.log_error("Failed to create treasure mission!")
  end
end

-- Create slaughter mission
mod.create_slaughter_mission = function()
  local player = gapi.get_avatar()
  if not player then return end

  -- !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  -- !!! TEMPORARY DEBUG: FORCE KILL_MONSTERS MISSION FOR TESTING             !!!
  -- !!! REMOVE THIS BEFORE PRODUCTION - SEARCH FOR "TEMPORARY DEBUG"         !!!
  -- !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  local DEBUG_FORCE_KILL_MONSTERS = true

  if DEBUG_FORCE_KILL_MONSTERS then
    gdebug.log_info("!!! TEMPORARY DEBUG: Forcing MISSION_BONUS_KILL_LIGHT for testing !!!")
    local player_id = player:getID()
    local mission_type = MissionTypeIdRaw.new("MISSION_BONUS_KILL_LIGHT")
    local new_mission = Mission.reserve_new(mission_type, player_id)
    if new_mission then
      new_mission:assign(player)
      gapi.add_msg("DEBUG: Mission: Kill the warp-draining zombies!")
      gdebug.log_info("DEBUG: Created KILL_MONSTERS mission: MISSION_BONUS_KILL_LIGHT")
    else
      gdebug.log_error("DEBUG: Failed to create KILL_MONSTERS mission!")
    end
    return
  end
  -- !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

  -- Weighted pool of slaughter missions (matching CDDA weights)
  local slaughter_missions = {
    { id = "MISSION_SLAUGHTER_ZOMBIES_10", weight = 10, name = "Kill 10 Zombies" },
    { id = "MISSION_SLAUGHTER_ZOMBIES_50", weight = 20, name = "Kill 50 Zombies" },
    { id = "MISSION_SLAUGHTER_BIRD", weight = 5, name = "Kill 5 Birds" },
    { id = "MISSION_SLAUGHTER_MAMMAL", weight = 5, name = "Kill 5 Mammals" },
    -- TODO: Add harder missions when difficulty system is implemented
    -- MISSION_SLAUGHTER_ZOMBIES_100, MISSION_SLAUGHTER_MIGO, MISSION_SLAUGHTER_NETHER
  }

  -- Calculate total weight
  local total_weight = 0
  for _, mission in ipairs(slaughter_missions) do
    total_weight = total_weight + mission.weight
  end

  -- Select random mission based on weight
  local roll = gapi.rng(1, total_weight)
  local selected_mission = nil
  local current_weight = 0

  for _, mission in ipairs(slaughter_missions) do
    current_weight = current_weight + mission.weight
    if roll <= current_weight then
      selected_mission = mission
      break
    end
  end

  if not selected_mission then
    gdebug.log_error("Failed to select slaughter mission!")
    return
  end

  local player_id = player:getID()
  local mission_type = MissionTypeIdRaw.new(selected_mission.id)

  local new_mission = Mission.reserve_new(mission_type, player_id)
  if new_mission then
    new_mission:assign(player)
    gapi.add_msg(string.format("Mission: %s!", selected_mission.name))
    gdebug.log_info(string.format("Created slaughter mission: %s", selected_mission.name))
  else
    gdebug.log_error("Failed to create slaughter mission!")
  end
end

-- Warp sickness timer tick
mod.warp_sickness_tick = function()
  if not storage.is_away_from_home then
    return true  -- Keep hook active
  end

  -- Increment counter
  storage.sickness_counter = (storage.sickness_counter or 0) + 1

  gdebug.log_info(string.format("Warp sickness tick: %d", storage.sickness_counter))

  -- Find the appropriate stage message for this pulse count
  for i = #SICKNESS_STAGES, 1, -1 do
    local stage = SICKNESS_STAGES[i]
    if storage.sickness_counter == stage.threshold then
      gapi.add_msg(stage.message)

      -- Apply warp sickness effect (if we have such an effect defined)
      -- For PoC, just show messages

      -- At max stage, deal damage
      if storage.sickness_counter > 12 then
        local player = gapi.get_avatar()
        if player then
          -- Deal minor disintegration damage
          player:mod_pain(5)
          gapi.add_msg("Your body is coming apart!")
        end
      end
      break
    end
  end

  return true  -- Keep running
end

-- Use warp obelisk - start expedition
mod.use_warp_obelisk = function(who, item, pos)
  if storage.is_away_from_home then
    gapi.add_msg("You are already on an expedition!")
    return 0
  end

  -- Store home location as absolute MS coordinates (for resurrection) - only once
  if not storage.home_location then
    local player_pos_ms = who:get_pos_ms()
    local home_abs_ms = gapi.get_map():get_abs_ms(player_pos_ms)
    storage.home_location = { x = home_abs_ms.x, y = home_abs_ms.y, z = home_abs_ms.z }
    gdebug.log_info(string.format("Home location set to: %d, %d, %d", home_abs_ms.x, home_abs_ms.y, home_abs_ms.z))
  end

  -- Also get OMT for teleportation
  local home_omt = get_player_omt()
  if not home_omt then
    gapi.add_msg("ERROR: Could not determine position!")
    return 0
  end

  -- Show raid type menu
  local ui = UiList.new()
  ui:title(locale.gettext("Select Expedition Type"))
  ui:add(1, locale.gettext("Quick Raid (Test)"))
  ui:add(2, locale.gettext("Cancel"))

  local choice = ui:query()

  if choice == 1 then
    -- Start quick raid
    gapi.add_msg("Initiating warp sequence...")

    -- Teleport to random nearby location at ground level (z=0)
    -- Distance matches CDDA short raid: 5-30 OM tiles from home
    local distance = gapi.rng(5, 30)
    local angle = gapi.rng(0, 359) * (math.pi / 180)  -- Random angle in radians
    local dx = math.floor(distance * math.cos(angle))
    local dy = math.floor(distance * math.sin(angle))

    local dest_omt = Tripoint.new(
      home_omt.x + dx,
      home_omt.y + dy,
      0  -- Always teleport to ground level to avoid fall damage
    )

    teleport_to_omt(dest_omt)

    -- Set away status
    storage.is_away_from_home = true
    storage.sickness_counter = 0
    storage.raids_total = (storage.raids_total or 0) + 1

    -- Create extraction mission (mission's update_mapgen will spawn red room automatically)
    mod.create_extraction_mission(dest_omt)

    -- Create slaughter mission
    mod.create_slaughter_mission()

    -- Create treasure bonus mission (TODO: make this optional based on upgrades)
    mod.create_treasure_mission(dest_omt)

    -- Start sickness timer
    gapi.add_on_every_x_hook(WARP_SICKNESS_INTERVAL, function()
      return mod.warp_sickness_tick()
    end)

    gapi.add_msg("You arrive at the raid location!")
    gapi.add_msg("Find the red room exit portal to return home before warp sickness kills you.")

    return 1
  else
    gapi.add_msg("Warp cancelled.")
    return 0
  end
end

-- Use return obelisk - return home
mod.use_return_obelisk = function(who, item, pos)
  if not storage.is_away_from_home then
    gapi.add_msg("You are already home!")
    return 0
  end

  if not storage.home_location then
    gapi.add_msg("ERROR: Home location not set!")
    return 0
  end

  -- Confirmation dialog
  local confirm_ui = UiList.new()
  confirm_ui:title(string.format("Return home? Sickness: %d/12", storage.sickness_counter))
  confirm_ui:add(1, locale.gettext("Yes, return home"))
  confirm_ui:add(2, locale.gettext("No, stay"))
  local confirm = confirm_ui:query()

  if confirm == 1 then
    -- Convert stored abs_ms coordinates to OMT for teleportation
    local home_abs_ms = Tripoint.new(
      storage.home_location.x,
      storage.home_location.y,
      storage.home_location.z
    )
    local home_omt = coords.ms_to_omt(home_abs_ms)

    -- Offset 1 tile north (negative Y in map coordinates)
    teleport_to_omt(home_omt, Tripoint.new(0, -1, 0))

    -- Complete missions when returning home
    local player = gapi.get_avatar()
    if player then
      local missions = player:get_active_missions()

      for _, mission in ipairs(missions) do
        if mission:in_progress() and not mission:has_failed() then
          local mission_name = mission:name()

          -- Only process raid missions (prefixed with "RAID: ")
          if mission_name:sub(1, 6) == "RAID: " then
            -- Check mission type and handle appropriately
            if mission_name == "RAID: Reach the exit portal!" or mission_name == "RAID: Find the warp shards!" then
              -- GO_TO missions: Always complete (survival = success)
              mission:wrap_up()
              gdebug.log_info(string.format("Completed mission: %s (GO_TO mission)", mission_name))
              gapi.add_msg(string.format("Mission completed: %s", mission_name))
            else
              -- KILL missions: Check if goal was actually met
              local is_complete = mission:is_complete()

              if is_complete then
                -- Give reward before completing mission
                -- HACK: Using mission name to look up reward since BN doesn't expose mission_type.id
                local reward_count = MISSION_REWARDS[mission_name]
                if reward_count then
                  give_mission_reward(player, mission_name, reward_count)
                end

                mission:wrap_up()
                gdebug.log_info(string.format("Completed mission: %s", mission_name))
                gapi.add_msg(string.format("Mission completed: %s", mission_name))
              else
                mission:fail()
                gdebug.log_info(string.format("Failed mission: %s", mission_name))
                gapi.add_msg(string.format("Mission failed: %s", mission_name))
              end
            end
          end
        end
      end
    end

    -- Award material tokens for successful return
    -- Formula from CDDA: lengthofthisraid * 75 + 50
    -- Short raid: 50 tokens, Medium: 125 tokens, Long: 200 tokens
    -- TODO: When raid duration selection is implemented, calculate based on raid length
    local material_tokens = 50  -- Currently only short raids
    gapi.spawn_item_at(player:get_location(), "skyisland_material_token", material_tokens)
    gapi.add_msg(string.format("You've returned home safely! Earned %d material tokens.", material_tokens))

    -- Clear away status
    storage.is_away_from_home = false
    storage.sickness_counter = 0
    storage.raids_won = (storage.raids_won or 0) + 1

    gapi.add_msg(string.format(
      "Stats: %d/%d raids completed successfully",
      storage.raids_won,
      storage.raids_total
    ))

    return 1
  else
    gapi.add_msg("Cancelled.")
    return 0
  end
end

-- Game started hook - initialize for new games only
mod.on_game_started = function()
  -- Reset to defaults for new game
  storage.home_location = nil
  storage.is_away_from_home = false
  storage.sickness_counter = 0
  storage.raids_total = 0
  storage.raids_won = 0
  storage.raids_lost = 0

  gdebug.log_info("Sky Islands: New game started")
  gapi.add_msg("Sky Islands PoC loaded! Use warp remote to start.")
end

-- Game load hook - restore state (storage auto-loaded)
mod.on_game_load = function()
  gdebug.log_info("Sky Islands: Game loaded")
  gdebug.log_info(string.format("  Away from home: %s", tostring(storage.is_away_from_home)))
  gdebug.log_info(string.format("  Sickness counter: %d", storage.sickness_counter or 0))

  -- If we were away, restart the sickness timer
  if storage.is_away_from_home then
    gapi.add_msg("Resuming expedition... warp sickness timer restarted.")
    gapi.add_on_every_x_hook(WARP_SICKNESS_INTERVAL, function()
      return mod.warp_sickness_tick()
    end)
  end
end

-- Game save hook
mod.on_game_save = function()
  gdebug.log_info("Sky Islands: Game saving")
  gdebug.log_info(string.format("  Saving state: Away=%s, Sickness=%d",
    tostring(storage.is_away_from_home), storage.sickness_counter or 0))
end

-- Resurrection sickness tick - forcibly stabilize the player
mod.resurrection_sickness_tick = function()
  local player = gapi.get_avatar()
  if not player then return true end

  -- Check if player has resurrection sickness effect
  local res_sick_effect = EffectTypeId.new("skyisland_resurrection_sickness")
  if player:has_effect(res_sick_effect) then
    -- Get remaining duration before clearing
    local remaining_dur = player:get_effect_dur(res_sick_effect)

    -- Clear ALL effects (including broken limbs, poison, etc.)
    player:clear_effects()

    -- Forcibly heal all parts to 10 HP
    player:set_all_parts_hp_cur(10)

    -- Set pain to 10 if it's greater than 10
    if player:get_pain() > 10 then
      player:set_pain(10)
    end

    -- Re-apply resurrection sickness with remaining duration
    player:add_effect(res_sick_effect, remaining_dur)

    return true  -- Keep running while effect is active
  else
    return false  -- Stop running when effect expires
  end
end

-- Character death hook (early) - clear effects and heal before broken limbs lock in
mod.on_char_death = function()
  gdebug.log_info("Sky Islands: on_char_death fired")

  if storage.home_location then
    local player = gapi.get_avatar()
    if not player then return end

    -- Clear all effects (including broken limb effects) EARLY
    player:clear_effects()
    -- Heal everything to prevent broken limbs from locking in
    player:set_all_parts_hp_cur(10)

    gdebug.log_info("Sky Islands: Cleared effects and healed in on_char_death")
  end
end

-- Character death hook (late) - actual resurrection and teleportation
mod.on_character_death = function()
  gdebug.log_info("Sky Islands: on_character_death fired")
  gdebug.log_info(string.format("  home_location: %s", tostring(storage.home_location)))

  if storage.home_location then
    gdebug.log_info("Sky Islands: Resurrecting at home")
    gapi.add_msg("Using emergency warp to return home...")

    local player = gapi.get_avatar()
    if not player then return end

    -- Build home position from stored abs_ms coordinates
    local home_abs_ms = Tripoint.new(
      storage.home_location.x,
      storage.home_location.y,
      storage.home_location.z
    )

    -- Convert abs_ms to OMT for overmap placement
    local home_omt = coords.ms_to_omt(home_abs_ms)
    gapi.place_player_overmap_at(home_omt)

    -- Convert abs_ms to local_ms for exact positioning
    local local_pos = gapi.get_map():get_local_ms(home_abs_ms)
    gapi.place_player_local_at(local_pos)

    -- Fail all raid missions on death
    local missions = player:get_active_missions()
    for _, mission in ipairs(missions) do
      if mission:in_progress() and not mission:has_failed() then
        local mission_name = mission:name()
        -- Only fail raid missions (prefixed with "RAID: ")
        if mission_name:sub(1, 6) == "RAID: " then
          mission:fail()
          gdebug.log_info(string.format("Failed raid mission on death: %s", mission_name))
        end
      end
    end

    -- Mark raid as failed
    storage.is_away_from_home = false
    storage.sickness_counter = 0
    storage.raids_lost = (storage.raids_lost or 0) + 1

    -- Set HP immediately
    player:set_all_parts_hp_cur(10)

    -- Set pain to 10 for resurrection penalty
    player:set_pain(10)

    -- Apply resurrection sickness effect to stabilize over 10 seconds
    local res_sick_effect = EffectTypeId.new("skyisland_resurrection_sickness")
    player:add_effect(res_sick_effect, TimeDuration.from_seconds(10))

    -- Start resurrection stabilization tick (runs every second)
    gapi.add_on_every_x_hook(TimeDuration.from_seconds(1), function()
      return mod.resurrection_sickness_tick()
    end)

    gapi.add_msg("You respawn at home, badly wounded!")
    gdebug.log_info(string.format("Resurrected at home abs_ms: %d, %d, %d", home_abs_ms.x, home_abs_ms.y, home_abs_ms.z))
  end
end

gdebug.log_info("Sky Islands PoC main.lua loaded")
