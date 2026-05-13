#!/usr/bin/env bash
# =============================================================================
# BrickForce AI — Project Validation Script
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

echo -e "${BOLD}=== BrickForce AI — Project Validation ===${NC}"
echo ""

echo "── Core Config ──"
check_file "project.godot"
check_file "replit.md"
check_file ".gitignore"

echo ""
echo "── Autoload Systems ──"
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

echo ""
echo "── Economy ──"
check_file "src/economy/currency/currency_manager.gd"
check_file "src/economy/inventory/inventory_manager.gd"
check_file "src/economy/shop/shop_manager.gd"
check_file "src/economy/cosmetics/cosmetic_manager.gd"

echo ""
echo "── Save / Network ──"
check_file "src/save/save_manager.gd"
check_file "src/network/network_manager.gd"
check_file "src/network/api/api_manager.gd"
check_file "src/network/local_server/local_server.gd"
check_file "src/network/sync/state_sync.gd"

echo ""
echo "── Gameplay ──"
check_file "src/gameplay/characters/base/character_base.gd"
check_file "src/gameplay/characters/player/player_character.gd"
check_file "src/gameplay/characters/enemy/ai_character.gd"
check_file "src/gameplay/weapons/base/weapon_base.gd"
check_file "src/gameplay/match/match_manager.gd"
check_file "src/gameplay/squads/squad_manager.gd"
check_file "src/gameplay/abilities/ability_base.gd"

echo ""
echo "── AI ──"
check_file "src/ai/states/ai_state_machine.gd"
check_file "src/ai/states/ai_state_base.gd"
check_file "src/ai/perception/perception_system.gd"
check_file "src/ai/squad/squad_ai_commander.gd"

echo ""
echo "── Data Resources ──"
check_file "src/data/weapons/weapon_data.gd"
check_file "src/data/characters/character_data.gd"
check_file "src/data/items/item_data.gd"

echo ""
echo "── Audio / VFX ──"
check_file "src/audio/audio_manager.gd"
check_file "src/vfx/vfx_manager.gd"

echo ""
echo "── Systems ──"
check_file "src/core/systems/component_system.gd"
check_file "src/core/systems/component_base.gd"

echo ""
echo "── World ──"
check_file "src/world/loot/loot_spawner.gd"

echo ""
echo "── Key Directories ──"
check_dir "scenes/autoloads"
check_dir "scenes/gameplay"
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
