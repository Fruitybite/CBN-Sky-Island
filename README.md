# Sky Islands - Cataclysm: Bright Nights Port

A port of the Sky Islands mod from Cataclysm: Dark Days Ahead to Cataclysm: Bright Nights.

This is NOT CURRENTLY COMPATIBLE with BN Nightly; you need two C++ patches, only one of which I have polished enough to PR. If you insist on trying the mod out in its broken, incomplete state, you need to build [my working branch](https://github.com/graysonchao/Cataclysm-BN/tree/feat/mgoal_kill_monsters) from source.

## Features

### ✅ Implemented
- **Teleportation System**: Warp obelisk to start expeditions, return obelisk to get back home
- **Mission System**: Three mission types per expedition (extraction, slaughter, treasure)
- **Warp Sickness**: Escalating penalties every 5 minutes while away (13 stages from mild disorientation to instant death)
- **Material Token Economy**: Earn 50 tokens per successful return, convert to resources at infinity nodes
- **Infinity Nodes**: Three deployable furniture types that convert tokens to raw materials
  - Infinity tree: logs, planks, sticks, wooden beams
  - Infinity stone: rocks, clay, sand, soil, bricks, cement
  - Infinity ore: scrap metal, steel, pipes, wire, nails, frames
- **Death Protection**: Die during a raid? Respawn at home (but lose the raid rewards)
- **State Persistence**: All progress saves correctly across game sessions

### 🚧 In Progress
- **Heart of the Island**: Central upgrade hub (planned)
- **Progress Gates**: Automatic rank-ups at 10 and 20 successful raids (planned)
- **Rank-up Missions**: Craft "Proof of Determination" to unlock new recipes (planned)

## Known Issues

### Scenario Selection
When creating a character, the game may default to "Evacuee" instead of "Sky Island Warper". You must manually select "Sky Island Warper" from the scenario list.

This is a Bright Nights engine issue affecting multiple mods. **Workaround**: Manually select the scenario before starting.

## Development Status

This is an active work-in-progress port. The core gameplay loop is functional, but many features from the CDDA version are still being ported.

**Ported from**: [CDDA Sky Islands](https://github.com/TGWeaver/CDDA-Sky-Islands) by TGWeaver

## Troubleshooting

### Mod won't load
- Check `debug.log` for Lua errors
- Verify you're running a recent Cataclysm-BN build with Lua mod support

### Warp sickness not progressing
- Ensure you successfully started an expedition (check messages)
- Wait 5+ minutes of game time
- Check `debug.log` for "Warp sickness tick" messages

### State not persisting
- Check `debug.log` for save/load messages
- Verify raids_total increments correctly when starting expeditions
