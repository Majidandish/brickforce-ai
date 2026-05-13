#!/usr/bin/env bash
# =============================================================================
# BrickForce AI — Project Bootstrap Setup Script
# =============================================================================
# Purpose  : Initializes the full project environment from a clean clone.
# Usage    : bash tools/setup.sh [--clean] [--skip-hooks]
# =============================================================================

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# ── Flags ─────────────────────────────────────────────────────────────────────
CLEAN=false
SKIP_HOOKS=false
for arg in "$@"; do
  case $arg in
    --clean)      CLEAN=true ;;
    --skip-hooks) SKIP_HOOKS=true ;;
  esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────
log()     { echo -e "${BOLD}${BLUE}[SETUP]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

log "BrickForce AI — Project Setup"
log "Root: $ROOT_DIR"
echo ""

# ── 1. Verify Godot 4 ─────────────────────────────────────────────────────────
log "Checking Godot 4 installation..."
if command -v godot4 &>/dev/null; then
  GODOT_BIN="godot4"
elif command -v godot &>/dev/null; then
  GODOT_VER=$(godot --version 2>/dev/null | head -1)
  if [[ "$GODOT_VER" == 4* ]]; then
    GODOT_BIN="godot"
  else
    warn "Godot found but it appears to be version < 4. Skipping engine checks."
    GODOT_BIN=""
  fi
else
  warn "Godot 4 not found in PATH. Skipping engine validation."
  GODOT_BIN=""
fi
[ -n "$GODOT_BIN" ] && success "Godot binary: $GODOT_BIN"

# ── 2. Clean (optional) ───────────────────────────────────────────────────────
if [ "$CLEAN" = true ]; then
  log "Clean mode: removing generated caches..."
  rm -rf "$ROOT_DIR/.godot"
  rm -rf "$ROOT_DIR/build"
  success "Cache cleaned."
fi

# ── 3. Ensure directory tree ──────────────────────────────────────────────────
log "Verifying directory structure..."
DIRS=(
  "src/core/autoloads"
  "src/core/events"
  "src/core/managers"
  "src/core/systems"
  "src/core/pooling"
  "src/core/logging"
  "src/core/debug"
  "src/core/performance"
  "src/gameplay/characters/base"
  "src/gameplay/characters/player"
  "src/gameplay/characters/enemy"
  "src/gameplay/weapons/base"
  "src/gameplay/weapons/firearms"
  "src/gameplay/weapons/grenades"
  "src/gameplay/weapons/melee"
  "src/gameplay/items/base"
  "src/gameplay/items/consumables"
  "src/gameplay/items/equipment"
  "src/gameplay/abilities"
  "src/gameplay/squads"
  "src/gameplay/match"
  "src/ai/behaviors"
  "src/ai/states"
  "src/ai/perception"
  "src/ai/decision"
  "src/ai/squad"
  "src/ai/pathfinding"
  "src/network/client"
  "src/network/server"
  "src/network/api"
  "src/network/local_server"
  "src/network/sync"
  "src/ui/hud"
  "src/ui/menus"
  "src/ui/shop"
  "src/ui/inventory"
  "src/ui/settings"
  "src/ui/debug"
  "src/world/environment"
  "src/world/modular"
  "src/world/zones"
  "src/world/loot"
  "src/data/items"
  "src/data/weapons"
  "src/data/characters"
  "src/data/config"
  "src/data/missions"
  "src/economy/currency"
  "src/economy/shop"
  "src/economy/inventory"
  "src/economy/cosmetics"
  "src/save/profiles"
  "src/save/serializers"
  "src/vfx"
  "src/audio"
  "scenes/autoloads"
  "scenes/gameplay"
  "scenes/ui"
  "scenes/world"
  "scenes/characters"
  "scenes/weapons"
  "scenes/vfx"
  "assets/audio/sfx"
  "assets/audio/music"
  "assets/audio/ambient"
  "assets/textures"
  "assets/models"
  "assets/fonts"
  "assets/vfx"
  "resources/items"
  "resources/weapons"
  "resources/characters"
  "resources/missions"
  "resources/config"
  "addons"
  "tools/dev"
  "tools/build"
  "tools/ci"
  "docs/architecture"
  "docs/systems"
  "docs/api"
  "build"
)
for dir in "${DIRS[@]}"; do
  mkdir -p "$ROOT_DIR/$dir"
done
success "Directory structure verified."

# ── 4. Git hooks ──────────────────────────────────────────────────────────────
if [ "$SKIP_HOOKS" = false ] && [ -d "$ROOT_DIR/.git" ]; then
  log "Installing git hooks..."
  HOOK_DIR="$ROOT_DIR/.git/hooks"

  cat > "$HOOK_DIR/pre-commit" << 'HOOK'
#!/usr/bin/env bash
# BrickForce AI pre-commit hook — validates GDScript syntax
echo "[PRE-COMMIT] Checking GDScript files..."
CHANGED=$(git diff --cached --name-only --diff-filter=ACM | grep "\.gd$" || true)
if [ -n "$CHANGED" ] && command -v godot4 &>/dev/null; then
  for f in $CHANGED; do
    godot4 --headless --check-only --script "$f" 2>/dev/null || {
      echo "GDScript error in: $f"
      exit 1
    }
  done
fi
echo "[PRE-COMMIT] OK"
HOOK
  chmod +x "$HOOK_DIR/pre-commit"
  success "Git hooks installed."
fi

# ── 5. Generate .gdignore files ───────────────────────────────────────────────
log "Setting up .gdignore markers..."
touch "$ROOT_DIR/tools/.gdignore"
touch "$ROOT_DIR/docs/.gdignore"
success ".gdignore markers set."

# ── 6. Godot import (headless) ────────────────────────────────────────────────
if [ -n "$GODOT_BIN" ]; then
  log "Running headless Godot import (generates .godot/ cache)..."
  cd "$ROOT_DIR"
  timeout 60 "$GODOT_BIN" --headless --import --quit 2>/dev/null || true
  success "Godot import complete."
fi

# ── 7. Summary ────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}═══════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  BrickForce AI — Setup Complete!      ${NC}"
echo -e "${BOLD}${GREEN}═══════════════════════════════════════${NC}"
echo ""
echo -e "  Next steps:"
echo -e "  ${CYAN}1.${NC} Open Godot 4 → Import project.godot"
echo -e "  ${CYAN}2.${NC} Run: ${BOLD}bash tools/dev/validate.sh${NC}"
echo -e "  ${CYAN}3.${NC} Press F5 to launch (or use dedicated server mode)"
echo ""
