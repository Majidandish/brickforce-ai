#!/usr/bin/env bash
# =============================================================================
# BrickForce AI — Automated Test Runner
# =============================================================================
# Runs all test scene scripts via Godot's headless mode.
# Requires: GODOT_BIN environment variable pointing to Godot 4 binary.
# Usage: bash tools/dev/run_tests.sh [test_filter]
# Example: bash tools/dev/run_tests.sh movement
# =============================================================================

set -euo pipefail
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

GODOT_BIN="${GODOT_BIN:-godot4}"
TEST_DIR="scenes/test"
FILTER="${1:-}"
PASS=0; FAIL=0; SKIP=0

echo -e "${BOLD}=== BrickForce AI — Test Runner ===${NC}"
echo -e "Godot binary: $GODOT_BIN"
echo -e "Test directory: $TEST_DIR"
[ -n "$FILTER" ] && echo -e "Filter: $FILTER"
echo ""

if ! command -v "$GODOT_BIN" &> /dev/null; then
  echo -e "${YELLOW}[SKIP]${NC} Godot binary '$GODOT_BIN' not found."
  echo -e "Set GODOT_BIN=/path/to/godot4 to enable headless test execution."
  echo ""
  echo -e "${BOLD}Available test scripts:${NC}"
  for f in "$TEST_DIR"/test_*.gd; do
    echo -e "  ${YELLOW}○${NC} $f"
  done
  exit 0
fi

for test_script in "$TEST_DIR"/test_*.gd; do
  test_name=$(basename "$test_script" .gd)
  if [ -n "$FILTER" ] && [[ "$test_name" != *"$FILTER"* ]]; then
    SKIP=$((SKIP+1))
    continue
  fi

  echo -e "${BOLD}Running: $test_name${NC}"
  output=$("$GODOT_BIN" --headless --no-header -s "$test_script" --quit 2>&1)
  exit_code=$?

  echo "$output" | grep -E "^\[PASS\]|\[FAIL\]" | while read -r line; do
    if [[ "$line" == "[PASS]"* ]]; then
      echo -e "  ${GREEN}${line}${NC}"
    else
      echo -e "  ${RED}${line}${NC}"
    fi
  done

  if echo "$output" | grep -q "ALL.*PASSED\|0/.*FAIL"; then
    echo -e "${GREEN}[OK]${NC} $test_name"
    PASS=$((PASS+1))
  else
    echo -e "${RED}[FAIL]${NC} $test_name"
    FAIL=$((FAIL+1))
  fi
  echo ""
done

echo -e "${BOLD}═══════════════════════════════════════${NC}"
echo -e "${GREEN}PASS: $PASS${NC}  ${RED}FAIL: $FAIL${NC}  ${YELLOW}SKIP: $SKIP${NC}"
if [ $FAIL -eq 0 ]; then
  echo -e "${GREEN}${BOLD}All tests passed!${NC}"
else
  echo -e "${RED}${BOLD}$FAIL test suite(s) failed.${NC}"
  exit 1
fi
