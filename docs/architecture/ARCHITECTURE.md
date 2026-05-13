# BrickForce AI — System Architecture

## Vision
A scalable indie-AAA offline tactical battle royale with:
- 60-player matches (AI + human squad)
- Modular LEGO-inspired environments
- Mass Effect-quality squad AI
- Ghost Recon / Rainbow Six tactical depth
- Free Fire pacing and loop

---

## Tech Stack
| Layer | Technology |
|-------|-----------|
| Engine | Godot 4.x |
| Language | GDScript (+ future C# for performance-critical paths) |
| Networking | ENet (Godot built-in) — future WebSocket/Relay |
| Save | JSON + optional AES encryption |
| Backend | LocalServer (offline) → migrates to cloud REST |
| CI/CD | Shell scripts → future GitHub Actions |

---

## Folder Structure
```
brickforce-ai/
├── project.godot          ← Godot project config + autoload registry
├── src/
│   ├── core/              ← Engine-level systems (always loaded)
│   │   ├── events/        ← EventBus (decoupled signal bus)
│   │   ├── logging/       ← Logger (levelled structured logging)
│   │   ├── managers/      ← GameManager, SceneManager, SettingsManager…
│   │   ├── pooling/       ← ObjectPool (bullet/VFX recycling)
│   │   ├── performance/   ← PerformanceMonitor
│   │   ├── debug/         ← DebugConsole, DevTools overlay
│   │   └── systems/       ← ComponentSystem (ECS-inspired)
│   ├── gameplay/
│   │   ├── characters/    ← CharacterBase → PlayerCharacter / AICharacter
│   │   ├── weapons/       ← WeaponBase → RifleWeapon / ShotgunWeapon…
│   │   ├── items/         ← ItemBase → HealItem / ArmorItem…
│   │   ├── abilities/     ← AbilityBase → active/passive skills
│   │   ├── squads/        ← SquadManager (formation + roles)
│   │   └── match/         ← MatchManager (lifecycle + zone)
│   ├── ai/
│   │   ├── states/        ← HFSM: AIStateMachine + state nodes
│   │   ├── perception/    ← Sight / sound / memory system
│   │   ├── squad/         ← SquadAICommander (Mass Effect-style)
│   │   ├── behaviors/     ← BehaviorTree primitives
│   │   ├── decision/      ← Utility AI scoring
│   │   └── pathfinding/   ← NavigationAgent3D wrappers
│   ├── network/
│   │   ├── network_manager.gd   ← LOCAL / LAN / ONLINE mode switch
│   │   ├── api/           ← APIManager (routes to local or remote)
│   │   ├── local_server/  ← LocalServer (offline fake REST)
│   │   └── sync/          ← StateSync (snapshot replication)
│   ├── economy/
│   │   ├── currency/      ← CurrencyManager (gold/gems/BP)
│   │   ├── inventory/     ← InventoryManager (persistent items)
│   │   ├── shop/          ← ShopManager (catalogue + purchase)
│   │   └── cosmetics/     ← CosmeticManager (skins + loadouts)
│   ├── save/              ← SaveManager (slots + versioning)
│   ├── audio/             ← AudioManager (pooled SFX + music)
│   ├── vfx/               ← VFXManager (pooled particles + decals)
│   ├── ui/                ← HUD, menus, shop, inventory UI
│   ├── world/             ← Zones, loot spawners, modular tiles
│   └── data/              ← Resource definitions (items/weapons/chars)
├── scenes/                ← PackedScene files (.tscn)
├── assets/                ← Raw media (audio, textures, models)
├── resources/             ← Configured .tres data files
├── addons/                ← Godot plugins
├── tools/                 ← Shell scripts (setup, codegen, validate)
└── docs/                  ← Architecture, API, system docs
```

---

## Core Architecture Principles

### 1. EventBus (Decoupled Communication)
All cross-system communication flows through `EventBus` signals.
No direct node references between unrelated systems.
```
WeaponBase  → EventBus.weapon_fired → AudioManager, VFXManager, MatchManager
CharacterBase → EventBus.player_died → MatchManager, UIManager, APIManager
```

### 2. Autoload Singletons
All global managers are Autoloads loaded in dependency order:
```
Logger (first) → EventBus → ObjectPool → GameManager → All others
```

### 3. Data-Driven Resources
All item/weapon/character stats live in `.tres` Resource files.
Code reads from `weapon_data.damage` — never hardcoded.
New content = new .tres file, zero code changes.

### 4. ECS-Inspired Components
Complex entities compose behaviours via `ComponentSystem`:
```
entity_id → [HealthComponent, StaminaComponent, StealthComponent, ...]
```

### 5. Network Transparency
`NetworkManager.mode` switches between LOCAL / LAN / ONLINE.
`APIManager.backend` switches between LOCAL / REMOTE.
All callers are unchanged when switching backends.

### 6. ObjectPool
All high-frequency short-lived objects (bullets, VFX, damage numbers)
use `ObjectPool.acquire()` / `ObjectPool.release()`.

---

## AI Architecture

```
SquadAICommander
  ├── Threat assessment (aggregated from all members' PerceptionSystems)
  ├── Role assignment (leader / assault / flanker / support / sniper)
  ├── Command dispatch (→ each AICharacter via receive_ai_command())
  └── Formation management (wedge / line / column / diamond)

AICharacter
  ├── AIStateMachine (HFSM)
  │   └── States: Idle, Patrol, Alert, Seek, Combat, Cover, Flanking,
  │              Retreat, Revive, Suppress, Dead, Berserk
  ├── PerceptionSystem (sight cones, sound, memory decay)
  └── NavigationAgent3D (Godot NavMesh)
```

---

## Match Lifecycle

```
COUNTDOWN → DROP_PHASE → LANDING → EARLY_GAME
  ↓ zone_timer expires
MID_GAME → LATE_GAME → FINAL_CIRCLE
  ↓ alive_count ≤ 1
ENDING → RESULTS_SCREEN → MAIN_MENU
```

---

## Network Migration Plan

| Phase | Mode | Backend |
|-------|------|---------|
| Now (offline) | LOCAL | LocalServer |
| LAN co-op | LAN (ENet) | LocalServer |
| Online beta | ONLINE (ENet) | Self-hosted REST |
| Live-service | ONLINE (WebSocket) | Cloud (GCP/AWS) |

Switching: `NetworkManager.set_mode(ONLINE, "server_url")`

---

## Performance Targets
| Metric | Target |
|--------|--------|
| FPS (60 AI agents) | ≥ 60 FPS |
| AI perception tick | ≤ 2ms total |
| Zone damage tick | ≤ 0.1ms |
| Save (JSON) | ≤ 50ms |
| Scene load | ≤ 3s |
| Memory (active match) | ≤ 1.5 GB |

---

## Adding New Content

### New Weapon
```bash
bash tools/dev/create_weapon.sh desert_eagle Pistol
```
Configure `resources/weapons/desert_eagle.tres` → drop into loot tables.

### New Character
```bash
bash tools/dev/create_character.sh ghost_operative ally
```
Configure `resources/characters/ghost_operative.tres` → add to spawn tables.

### New Item
1. Create `resources/items/<id>.tres` extending `ItemData`
2. Add to `LootSpawner.loot_table` in the relevant zone scene
3. No code changes required.
