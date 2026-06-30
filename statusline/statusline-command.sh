#!/bin/bash
input=$(cat)

MODEL=$(echo "$input" | jq -r '.model.display_name')
EFFORT=$(echo "$input" | jq -r '.effort.level // empty')
DIR=$(echo "$input" | jq -r '.workspace.current_dir')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
DURATION_MS=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
RATE_5H=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
RATE_7D=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

BLUE='\033[1m\033[34m'; CYAN='\033[1m\033[36m'; PURPLE='\033[1m\033[95m'; YELLOW='\033[33m'; RESET='\033[0m'
SOFT_GREEN='\033[38;5;114m'; SOFT_YELLOW='\033[38;5;179m'; SOFT_RED='\033[38;5;167m'

# Pick bar color based on context usage
if [ "$PCT" -ge 90 ]; then BAR_COLOR="$SOFT_RED"
elif [ "$PCT" -ge 70 ]; then BAR_COLOR="$SOFT_YELLOW"
else BAR_COLOR="$SOFT_GREEN"; fi

FILLED=$((PCT / 10)); EMPTY=$((10 - FILLED))
printf -v FILL "%${FILLED}s"; printf -v PAD "%${EMPTY}s"
BAR="${FILL// /█}${PAD// /░}"

MINS=$((DURATION_MS / 60000)); SECS=$(((DURATION_MS % 60000) / 1000))

BRANCH=""
git rev-parse --git-dir > /dev/null 2>&1 && BRANCH=" |  $(git branch --show-current 2>/dev/null)"

COST_FMT=$(printf '$%.2f' "$COST")

MODEL_STR="$MODEL"
[ -n "$EFFORT" ] && MODEL_STR="$MODEL $EFFORT"

RATE_STR=""
if [ -n "$RATE_5H" ]; then
  R5H=$(printf '%.0f' "$RATE_5H")
  if [ "$R5H" -ge 90 ]; then C5H="$SOFT_RED"
  elif [ "$R5H" -ge 70 ]; then C5H="$SOFT_YELLOW"
  else C5H="$SOFT_GREEN"; fi
  RATE_STR="${RATE_STR} | ${C5H}5h: ${R5H}%${RESET}"
fi
if [ -n "$RATE_7D" ]; then
  R7D=$(printf '%.0f' "$RATE_7D")
  if [ "$R7D" -ge 90 ]; then C7D="$SOFT_RED"
  elif [ "$R7D" -ge 70 ]; then C7D="$SOFT_YELLOW"
  else C7D="$SOFT_GREEN"; fi
  RATE_STR="${RATE_STR} | ${C7D}7d: ${R7D}%${RESET}"
fi

echo -e "${BLUE}[$MODEL_STR]${RESET} ${CYAN}${DIR##*/}${RESET}${PURPLE}$BRANCH${RESET} | ${BAR_COLOR}${BAR} ${PCT}%${RESET} | ${YELLOW}${COST_FMT}${RESET} | ⏱️ ${MINS}m ${SECS}s${RATE_STR}"
