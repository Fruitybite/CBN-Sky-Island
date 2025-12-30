-- Sky Islands BN Port - Item Use Functions
-- Lua iuse handlers for various items

local iuse = {}

-- Helper: Check if furniture exists in adjacent tiles
local function has_adjacent_furniture(player, furniture_id)
  local map = gapi.get_map()
  local player_pos = player:get_pos_ms()

  -- Check all 8 adjacent tiles + current tile
  for dx = -1, 1 do
    for dy = -1, 1 do
      local check_pos = Tripoint.new(player_pos.x + dx, player_pos.y + dy, player_pos.z)
      local furn = map:get_furn_at(check_pos)
      if furn == furniture_id:int_id() then
        return true
      end
    end
  end
  return false
end

-- Imprint autodoc copyplate - converts inert to active when near autodoc
function iuse.imprint_autodoc(who, item, pos)
  local player = gapi.get_avatar()
  if not player then return 0 end

  -- Check for adjacent autodoc furniture
  if not has_adjacent_furniture(player, FurnId.new("f_autodoc")) then
    gapi.add_msg("You need to be standing next to a working Autodoc to imprint this copyplate.")
    return 0
  end

  -- Remove inert item and add active one
  local inert_plate = player:get_item_with_id(ItypeId.new("skyisland_autodoc_inert"), false)
  player:remove_item(inert_plate)
  local active_id = ItypeId.new("skyisland_autodoc_active")
  player:add_item_with_id(active_id, 1)

  gapi.add_msg("The copyplate hums and glows as it absorbs the Autodoc's schematics!")
  gapi.add_msg("You now have an activated Autodoc copyplate.")

  return 1  -- Consume the inert item
end

-- Imprint autodoc couch copyplate - converts inert to active when near couch
function iuse.imprint_autodoc_couch(who, item, pos)
  local player = gapi.get_avatar()
  if not player then return 0 end

  -- Check for adjacent autodoc couch furniture
  if not has_adjacent_furniture(player, FurnId.new("f_autodoc_couch")) then
    gapi.add_msg("You need to be standing next to a working Autodoc Couch to imprint this copyplate.")
    return 0
  end

  -- Remove inert item and add active one
  local inert_plate = player:get_item_with_id(ItypeId.new("skyisland_autodoc_couch_inert"), false)
  player:remove_item(inert_plate)
  local active_id = ItypeId.new("skyisland_autodoc_couch_active")
  player:add_item_with_id(active_id, 1)

  gapi.add_msg("The copyplate hums and glows as it absorbs the Autodoc Couch's schematics!")
  gapi.add_msg("You now have an activated Autodoc Couch copyplate.")

  return 1  -- Consume the inert item
end

return iuse
