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
**Phase 2 Complete** — Production Gameplay Foundations generated.

---

### Phase 1 Systems (Infrastructure)
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
| AIStateBase | src/ai/states/ai_state_base.gd | ✅ |
| PerceptionSystem | src/ai/perception/perception_system.gd | ✅ |
| SquadAICommander | src/ai/squad/squad_ai_commander.gd | ✅ |
| WeaponData (Resource) | src/data/weapons/weapon_data.gd | ✅ |
| CharacterData (Resource) | src/data/characters/character_data.gd | ✅ |
| ItemData (Resource) | src/data/items/item_data.gd | ✅ |
| LootSpawner | src/world/loot/loot_spawner.gd | ✅ |

---

### Phase 2 Systems (Production Gameplay Foundations)
| System | File | Notes |
|--------|------|-------|
| **Movement** | | |
| MovementComponent | src/gameplay/characters/movement/movement_component.gd | ✅ FSM: Idle/Walk/Sprint/Crouch/Prone/Slide/Air/Vault |
| MovementConfig | src/gameplay/characters/movement/movement_config.gd | ✅ Data resource — one .tres per archetype |
| **Camera** | | |
| ThirdPersonCamera | src/gameplay/camera/third_person_camera.gd | ✅ Spring-arm collision, ADS blend, shake trauma |
| CameraConfig | src/gameplay/camera/camera_config.gd | ✅ Data resource |
| **Weapons** | | |
| WeaponHandler | src/gameplay/weapons/weapon_handler.gd | ✅ 5 slots, switching queue, replication state |
| RecoilSystem | src/gameplay/weapons/systems/recoil_system.gd | ✅ Visual + accuracy, progressive buildup, patterns |
| SpreadCalculator | src/gameplay/weapons/systems/spread_calculator.gd | ✅ Pure static: stance/movement/ADS modifiers |
| BallisticsSystem | src/gameplay/weapons/systems/ballistics_system.gd | ✅ Hitscan, pellets, penetration, falloff, VFX |
| **Health / Damage** | | |
| HealthComponent | src/gameplay/characters/health/health_component.gd | ✅ Regen, overshield, down/revive lifecycle |
| ArmorComponent | src/gameplay/characters/health/armor_component.gd | ✅ 3 tiers, durability, helmet/vest slots |
| DamageProcessor | src/gameplay/characters/health/damage_processor.gd | ✅ Full pipeline: resist→armor→status→health |
| HitZone | src/gameplay/characters/health/hit_zone.gd | ✅ 7 body parts, static builder, physics layer |
| **Interaction** | | |
| InteractableBase | src/gameplay/interaction/interactable_base.gd | ✅ Instant/Hold/Toggle, one-shot, conditions |
| InteractionSystem | src/gameplay/interaction/interaction_system.gd | ✅ Overlap scan, scoring, prompt bus |
| InteractablePickup | src/gameplay/interaction/interactable_pickup.gd | ✅ Bobbing, auto-pickup, static spawn helper |
| InteractableContainer | src/gameplay/interaction/interactable_container.gd | ✅ Loot scatter on open, one-shot |
| **Inventory** | | |
| MatchInventory | src/gameplay/inventory/match_inventory.gd | ✅ Grid+ammo pools, quick slots, backpack tiers |
| **Loot** | | |
| LootTableData | src/world/loot/loot_table_data.gd | ✅ Weighted roll, guaranteed items, tiers |
| LootManager (Autoload) | src/world/loot/loot_manager.gd | ✅ Table registry, airdrop timer, scatter spawn |
| **Cover** | | |
| CoverPoint | src/gameplay/cover/cover_point.gd | ✅ Peek directions, scoring, max users |
| CoverSystem (Autoload) | src/gameplay/cover/cover_system.gd | ✅ Spatial query, claim/release, debug stats |
| **AI States (Concrete)** | | |
| StateIdle | src/ai/states/concrete/state_idle.gd | ✅ Look-around, perception check |
| StatePatrol | src/ai/states/concrete/state_patrol.gd | ✅ Ordered waypoints + random wander |
| StateAlert | src/ai/states/concrete/state_alert.gd | ✅ Investigate, timeout → Seek |
| StateCombat | src/ai/states/concrete/state_combat.gd | ✅ Strafe, reposition, health transitions |
| StateCover | src/ai/states/concrete/state_cover.gd | ✅ Find/claim cover, peek/fire pattern |
| StateSeek | src/ai/states/concrete/state_seek.gd | ✅ Fan sweep, timeout → Patrol |
| StateRetreat | src/ai/states/concrete/state_retreat.gd | ✅ Threat-away vector, health recovery |
| StateRevive | src/ai/states/concrete/state_revive.gd | ✅ Navigate to ally, interruptible |
| StateDead | src/ai/states/concrete/state_dead.gd | ✅ Terminal, timed cleanup |
| **Animation** | | |
| AnimationController | src/gameplay/characters/animation/animation_controller.gd | ✅ 3-layer blend tree bridge, breathing sway |
| **Match** | | |
| MatchScoring (Autoload) | src/gameplay/match/match_scoring.gd | ✅ Kill/assist/damage/survival/placement XP |
| PlayerMatchState | src/gameplay/match/player_match_state.gd | ✅ Stats container, XP reward computation |
| **Network** | | |
| ReplicationComponent | src/network/replication/replication_component.gd | ✅ Snapshot buffer, interpolation scaffold |
| **Input** | | |
| InputContext | src/core/input/input_context.gd | ✅ Stack-based, action allow/block list |
| InputActionMap | src/core/input/input_action_map.gd | ✅ Rebindable KBM + gamepad map |
| **Tests** | | |
| test_character_movement | scenes/test/test_character_movement.gd | ✅ |
| test_weapon_firing | scenes/test/test_weapon_firing.gd | ✅ |
| test_ai_states | scenes/test/test_ai_states.gd | ✅ |
| test_inventory_loot | scenes/test/test_inventory_loot.gd | ✅ |

---

## Quick Start
```bash
# 1. Validate project structure
bash tools/dev/validate.sh

# 2. Full bootstrap (installs git hooks, runs Godot import)
bash tools/setup.sh

# 3. Run automated tests (requires Godot binary)
bash tools/dev/run_tests.sh

# 4. Scaffold a new weapon
bash tools/dev/create_weapon.sh ak47 "Assault Rifle"

# 5. Scaffold a new character
bash tools/dev/create_character.sh ghost_operative ally
```

## Architecture
See `docs/architecture/ARCHITECTURE.md` for the complete system diagram.

## Phase 3 — Next Steps
- **World Building**: SafeZone shrink system, modular map tiles, destructibles
- **Concrete Weapons**: AR, SMG, Sniper, Shotgun, Pistol with WeaponData .tres files
- **Concrete Abilities**: Heal, Revive, Flash, Smoke, Shield resources
- **HUD Layer**: Minimal production HUD (health, ammo, minimap, kill feed)
- **Parachute / Drop-in**: Match spawn sequence
- **Zone/Phase System**: Safe zone phases with MatchManager integration
- **AI NavMesh**: Bake navigation mesh for maps, wire NavigationAgent3D

## User Preferences
- Godot 4.x + GDScript as primary language
- AAA production-grade code quality — no prototypes
- Modular, data-driven, future multiplayer-compatible architecture
- All systems communicate through EventBus (decoupled)
- ObjectPool for all high-frequency runtime spawning
- Full documentation on every system
