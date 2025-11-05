-- Sky Islands BN Port - Warp Sickness System
-- Handles warp sickness progression and effects

local warp_sickness = {}

-- Warp sickness timing
local WARP_SICKNESS_INTERVAL = TimeDuration.from_minutes(5)

-- Warp sickness progression stages
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

-- Warp sickness timer tick
function warp_sickness.tick(storage)
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

-- Start warp sickness timer
function warp_sickness.start_timer(storage)
  gapi.add_on_every_x_hook(WARP_SICKNESS_INTERVAL, function()
    return warp_sickness.tick(storage)
  end)
end

-- Resurrection sickness tick - forcibly stabilize the player
function warp_sickness.resurrection_tick()
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

-- Apply resurrection sickness after death
function warp_sickness.apply_resurrection_sickness()
  local player = gapi.get_avatar()
  if not player then return end

  -- Set HP immediately
  player:set_all_parts_hp_cur(10)

  -- Set pain to 10 for resurrection penalty
  player:set_pain(10)

  -- Apply resurrection sickness effect to stabilize over 10 seconds
  local res_sick_effect = EffectTypeId.new("skyisland_resurrection_sickness")
  player:add_effect(res_sick_effect, TimeDuration.from_seconds(10))

  -- Start resurrection stabilization tick (runs every second)
  gapi.add_on_every_x_hook(TimeDuration.from_seconds(1), function()
    return warp_sickness.resurrection_tick()
  end)
end

return warp_sickness
