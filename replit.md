# BrickForce AI

## Project Overview
A production-grade Godot 4 offline tactical battle royale game featuring:
- 60-player matches with human + AI squad mates
- Mass Effect-inspired squad AI command system
- Ghost Recon / Rainbow Six tactical depth
- Free Fire pacing and progression loop
- LEGO-inspired modular environments

## Tech Stack
- **Engine**: Godot 4.x
- **Language**: GDScript (future C# support planned)
- **Networking**: Godot ENet (multiplayer-ready, offline-first)
- **Backend**: LocalServer (offline fake REST) → future cloud migration
- **Save**: JSON with optional AES encryption

## Project Status
**Phase 1 Complete** — Full AAA bootstrap infrastructure generated.

### Systems Built
| System | File | Status |
|--------|------|--------|
| EventBus | src/core/events/event_bus.gd | ✅ |
| Logger | src/core/logging/logger.gd | ✅ |
| ObjectPool | src/core/pooling/object_pool.gd | ✅ |
| PerformanceMonitor | src/core/performance/performance_monitor.gd | ✅ |
| GameManager (FSM) | src/core/managers/game_manager.gd | ✅ |
| SceneManager | src/core/managers/scene_manager.gd | ✅ |
| SettingsManager | src/core/managers/settings_manager.gd | ✅ |
| InputManager | src/core/managers/input_manager.gd | ✅ |
| TimeManager | src/core/managers/time_manager.gd | ✅ |
| DebugConsole | src/core/debug/debug_console.gd | ✅ |
| DevTools | src/core/debug/dev_tools.gd | ✅ |
| ComponentSystem (ECS) | src/core/systems/component_system.gd | ✅ |
| AudioManager | src/audio/audio_manager.gd | ✅ |
| VFXManager | src/vfx/vfx_manager.gd | ✅ |
| NetworkManager | src/network/network_manager.gd | ✅ |
| APIManager | src/network/api/api_manager.gd | ✅ |
| LocalServer | src/network/local_server/local_server.gd | ✅ |
| StateSync | src/network/sync/state_sync.gd | ✅ |
| SaveManager | src/save/save_manager.gd | ✅ |
| CurrencyManager | src/economy/currency/currency_manager.gd | ✅ |
| InventoryManager | src/economy/inventory/inventory_manager.gd | ✅ |
| ShopManager | src/economy/shop/shop_manager.gd | ✅ |
| CosmeticManager | src/economy/cosmetics/cosmetic_manager.gd | ✅ |
| CharacterBase | src/gameplay/characters/base/character_base.gd | ✅ |
| PlayerCharacter | src/gameplay/characters/player/player_character.gd | ✅ |
| AICharacter | src/gameplay/characters/enemy/ai_character.gd | ✅ |
| WeaponBase | src/gameplay/weapons/base/weapon_base.gd | ✅ |
| AbilityBase | src/gameplay/abilities/ability_base.gd | ✅ |
| MatchManager | src/gameplay/match/match_manager.gd | ✅ |
| SquadManager | src/gameplay/squads/squad_manager.gd | ✅ |
| AIStateMachine | src/ai/states/ai_state_machine.gd | ✅ |
| PerceptionSystem | src/ai/perception/perception_system.gd | ✅ |
| SquadAICommander | src/ai/squad/squad_ai_commander.gd | ✅ |
| WeaponData (Resource) | src/data/weapons/weapon_data.gd | ✅ |
| CharacterData (Resource) | src/data/characters/character_data.gd | ✅ |
| ItemData (Resource) | src/data/items/item_data.gd | ✅ |
| LootSpawner | src/world/loot/loot_spawner.gd | ✅ |

## Quick Start
```bash
# 1. Validate project structure
bash tools/dev/validate.sh

# 2. Full bootstrap (installs git hooks, runs Godot import)
bash tools/setup.sh

# 3. Scaffold a new weapon
bash tools/dev/create_weapon.sh ak47 "Assault Rifle"

# 4. Scaffold a new character
bash tools/dev/create_character.sh ghost_operative ally
```

## Architecture
See `docs/architecture/ARCHITECTURE.md` for the complete system diagram.

## User Preferences
- Godot 4.x + GDScript as primary language
- AAA production-grade code quality — no prototypes
- Modular, data-driven, future multiplayer-compatible architecture
- All systems communicate through EventBus (decoupled)
- ObjectPool for all high-frequency runtime spawning
- Full documentation on every system
