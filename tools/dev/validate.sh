#!/usr/bin/env bash
# =============================================================================
# BrickForce AI — Project Validation Script (Phase 1 + Phase 2)
# =============================================================================
# Checks that the project structure and key files are in place.
# Usage: bash tools/dev/validate.sh
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'; BOLD='\033[1m'

PASS=0; FAIL=0; WARN=0

check_file() {
  local path="$1"
  if [ -f "$path" ]; then
    echo -e "${GREEN}[PASS]${NC} $path"
    PASS=$((PASS+1))
  else
    echo -e "${RED}[FAIL]${NC} $path (missing)"
    FAIL=$((FAIL+1))
  fi
}

check_dir() {
  local path="$1"
  if [ -d "$path" ]; then
    echo -e "${GREEN}[PASS]${NC} $path/"
    PASS=$((PASS+1))
  else
    echo -e "${YELLOW}[WARN]${NC} $path/ (missing)"
    WARN=$((WARN+1))
  fi
}

echo -e "${BOLD}=== BrickForce AI — Project Validation (Phase 1 + Phase 2) ===${NC}"
echo ""

echo "── Core Config ──"
check_file "project.godot"
check_file "replit.md"
check_file ".gitignore"

echo ""
echo "── Phase 1: Autoload Systems ──"
check_file "src/core/events/event_bus.gd"
check_file "src/core/logging/logger.gd"
check_file "src/core/pooling/object_pool.gd"
check_file "src/core/performance/performance_monitor.gd"
check_file "src/core/managers/game_manager.gd"
check_file "src/core/managers/scene_manager.gd"
check_file "src/core/managers/settings_manager.gd"
check_file "src/core/managers/input_manager.gd"
check_file "src/core/managers/time_manager.gd"
check_file "src/core/debug/debug_console.gd"
check_file "src/core/debug/dev_tools.gd"
check_file "src/core/systems/component_system.gd"
check_file "src/core/systems/component_base.gd"

echo ""
echo "── Phase 1: Economy ──"
check_file "src/economy/currency/currency_manager.gd"
check_file "src/economy/inventory/inventory_manager.gd"
check_file "src/economy/shop/shop_manager.gd"
check_file "src/economy/cosmetics/cosmetic_manager.gd"

echo ""
echo "── Phase 1: Save / Network ──"
check_file "src/save/save_manager.gd"
check_file "src/network/network_manager.gd"
check_file "src/network/api/api_manager.gd"
check_file "src/network/local_server/local_server.gd"
check_file "src/network/sync/state_sync.gd"

echo ""
echo "── Phase 1: Data Resources ──"
check_file "src/data/weapons/weapon_data.gd"
check_file "src/data/characters/character_data.gd"
check_file "src/data/items/item_data.gd"

echo ""
echo "── Phase 1: Audio / VFX ──"
check_file "src/audio/audio_manager.gd"
check_file "src/vfx/vfx_manager.gd"

echo ""
echo "── Phase 2: Movement ──"
check_file "src/gameplay/characters/movement/movement_component.gd"
check_file "src/gameplay/characters/movement/movement_config.gd"

echo ""
echo "── Phase 2: Camera ──"
check_file "src/gameplay/camera/third_person_camera.gd"
check_file "src/gameplay/camera/camera_config.gd"

echo ""
echo "── Phase 2: Weapons ──"
check_file "src/gameplay/weapons/base/weapon_base.gd"
check_file "src/gameplay/weapons/weapon_handler.gd"
check_file "src/gameplay/weapons/systems/recoil_system.gd"
check_file "src/gameplay/weapons/systems/spread_calculator.gd"
check_file "src/gameplay/weapons/systems/ballistics_system.gd"

echo ""
echo "── Phase 2: Health / Damage Pipeline ──"
check_file "src/gameplay/characters/health/health_component.gd"
check_file "src/gameplay/characters/health/armor_component.gd"
check_file "src/gameplay/characters/health/damage_processor.gd"
check_file "src/gameplay/characters/health/hit_zone.gd"

echo ""
echo "── Phase 2: Characters ──"
check_file "src/gameplay/characters/base/character_base.gd"
check_file "src/gameplay/characters/player/player_character.gd"
check_file "src/gameplay/characters/enemy/ai_character.gd"
check_file "src/gameplay/characters/animation/animation_controller.gd"

echo ""
echo "── Phase 2: Abilities ──"
check_file "src/gameplay/abilities/ability_base.gd"

echo ""
echo "── Phase 2: Interaction ──"
check_file "src/gameplay/interaction/interactable_base.gd"
check_file "src/gameplay/interaction/interaction_system.gd"
check_file "src/gameplay/interaction/interactable_pickup.gd"
check_file "src/gameplay/interaction/interactable_container.gd"

echo ""
echo "── Phase 2: Inventory ──"
check_file "src/gameplay/inventory/match_inventory.gd"

echo ""
echo "── Phase 2: Cover System ──"
check_file "src/gameplay/cover/cover_point.gd"
check_file "src/gameplay/cover/cover_system.gd"

echo ""
echo "── Phase 2: Match Systems ──"
check_file "src/gameplay/match/match_manager.gd"
check_file "src/gameplay/match/match_scoring.gd"
check_file "src/gameplay/match/player_match_state.gd"

echo ""
echo "── Phase 2: Squad Systems ──"
check_file "src/gameplay/squads/squad_manager.gd"

echo ""
echo "── Phase 2: AI State Machine ──"
check_file "src/ai/states/ai_state_machine.gd"
check_file "src/ai/states/ai_state_base.gd"
check_file "src/ai/states/concrete/state_idle.gd"
check_file "src/ai/states/concrete/state_patrol.gd"
check_file "src/ai/states/concrete/state_alert.gd"
check_file "src/ai/states/concrete/state_combat.gd"
check_file "src/ai/states/concrete/state_cover.gd"
check_file "src/ai/states/concrete/state_seek.gd"
check_file "src/ai/states/concrete/state_retreat.gd"
check_file "src/ai/states/concrete/state_revive.gd"
check_file "src/ai/states/concrete/state_dead.gd"

echo ""
echo "── Phase 2: AI Perception & Squad AI ──"
check_file "src/ai/perception/perception_system.gd"
check_file "src/ai/squad/squad_ai_commander.gd"

echo ""
echo "── Phase 2: World / Loot ──"
check_file "src/world/loot/loot_spawner.gd"
check_file "src/world/loot/loot_table_data.gd"
check_file "src/world/loot/loot_manager.gd"

echo ""
echo "── Phase 2: Network Replication ──"
check_file "src/network/replication/replication_component.gd"

echo ""
echo "── Phase 2: Input ──"
check_file "src/core/input/input_context.gd"
check_file "src/core/input/input_action_map.gd"

echo ""
echo "── Phase 2: Test Scenes ──"
check_file "scenes/test/test_character_movement.gd"
check_file "scenes/test/test_weapon_firing.gd"
check_file "scenes/test/test_ai_states.gd"
check_file "scenes/test/test_inventory_loot.gd"

echo ""
echo "── Key Directories ──"
check_dir "scenes/autoloads"
check_dir "scenes/gameplay"
check_dir "scenes/test"
check_dir "assets/audio"
check_dir "assets/textures"
check_dir "resources/weapons"
check_dir "resources/characters"
check_dir "addons"
check_dir "docs"

echo ""
echo -e "${BOLD}═══════════════════════════════════${NC}"
echo -e "${GREEN}PASS: $PASS${NC}  ${RED}FAIL: $FAIL${NC}  ${YELLOW}WARN: $WARN${NC}"
if [ $FAIL -eq 0 ]; then
  echo -e "${GREEN}${BOLD}All checks passed!${NC}"
else
  echo -e "${RED}${BOLD}$FAIL check(s) failed. Run: bash tools/setup.sh${NC}"
fi
echo ""
