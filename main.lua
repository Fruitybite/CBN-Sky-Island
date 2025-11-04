-- Sky Islands BN Port - Proof of Concept
-- main.lua - Main implementation

local mod = game.mod_runtime[game.current_mod]
local storage = game.mod_storage[game.current_mod]

-- Constants
local WARP_SICKNESS_INTERVAL = TimeDuration.from_minutes(5)
local SICKNESS_STAGES = {
  { threshold = 7, message = "You feel slightly disoriented from the warp.", intensity = 6 },
  { threshold = 8, message = "The warp sickness is getting worse!", intensity = 5 },
  { threshold = 9, message = "You feel very ill from prolonged warping.", intensity = 4 },
  { threshold = 10, message = "Your body is struggling to maintain cohesion!", intensity = 3 },
  { threshold = 11, message = "WARNING: Disintegration imminent!", intensity = 2 },
  { threshold = 12, message = "YOU ARE DISINTEGRATING!", intensity = 1 }
}

-- Initialize storage defaults (only for new games)
-- These will be overwritten by saved data on load
storage.home_location = storage.home_location or nil
storage.is_away_from_home = storage.is_away_from_home or false
storage.sickness_counter = storage.sickness_counter or 0
storage.raids_total = storage.raids_total or 0
storage.raids_won = storage.raids_won or 0
storage.raids_lost = storage.raids_lost or 0

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

-- Create slaughter mission
mod.create_slaughter_mission = function()
  local player = gapi.get_avatar()
  if not player then return end

  local player_id = player:getID()
  local mission_type = MissionTypeIdRaw.new("MISSION_SLAUGHTER_ZOMBIES_10")

  local new_mission = Mission.reserve_new(mission_type, player_id)
  if new_mission then
    new_mission:assign(player)
    gapi.add_msg("Mission: Kill 10 Zombies!")
    gdebug.log_info("Created slaughter mission: Kill 10 Zombies")
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

  -- Check sickness stages
  for _, stage in ipairs(SICKNESS_STAGES) do
    if storage.sickness_counter >= stage.threshold then
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
    local dest_omt = Tripoint.new(
      home_omt.x + gapi.rng(-5, 5),
      home_omt.y + gapi.rng(-5, 5),
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
      local invalid_npc = CharacterId.new()

      for _, mission in ipairs(missions) do
        if mission:in_progress() and not mission:has_failed() then
          local mission_name = mission:name()

          -- Only process raid missions (prefixed with "RAID: ")
          if mission_name:sub(1, 6) == "RAID: " then
            -- Always complete extraction mission (survival = success)
            -- For other missions, check if goal was actually met
            if mission_name == "RAID: Reach the exit portal!" then
              mission:wrap_up()
              gdebug.log_info("Completed extraction mission (survived)")
              gapi.add_msg("Mission completed: Extraction")
            elseif mission:is_complete(invalid_npc) then
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

    -- Clear away status
    storage.is_away_from_home = false
    storage.sickness_counter = 0
    storage.raids_won = (storage.raids_won or 0) + 1

    gapi.add_msg("You return home safely!")
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
