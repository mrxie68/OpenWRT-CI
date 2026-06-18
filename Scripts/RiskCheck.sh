#!/bin/bash
set -euo pipefail

STATE_DIR="$GITHUB_WORKSPACE/BuildState"
STATE_FILE="$STATE_DIR/${WRT_SOURCE//\//_}-${WRT_BRANCH}.hash"
REPORT="$GITHUB_WORKSPACE/risk-report.txt"
CURRENT_HASH="$(git rev-parse --short=12 HEAD)"
PREVIOUS_HASH=""

mkdir -p "$STATE_DIR"

if [ -f "$STATE_FILE" ]; then
    PREVIOUS_HASH="$(tr -d '[:space:]' < "$STATE_FILE" || true)"
fi

if [ -n "$PREVIOUS_HASH" ] && ! git cat-file -e "$PREVIOUS_HASH^{commit}" 2>/dev/null; then
    git fetch --deepen=1000 origin "$WRT_BRANCH" || true
fi

{
    echo "OpenWrt upstream risk report"
    echo "Source: $WRT_SOURCE"
    echo "Branch: $WRT_BRANCH"
    echo "Config: $WRT_CONFIG"
    echo "Current: $CURRENT_HASH"
    echo "Previous: ${PREVIOUS_HASH:-none}"
    echo
} > "$REPORT"

if [ -z "$PREVIOUS_HASH" ]; then
    {
        echo "Risk: UNKNOWN"
        echo "Reason: no previous upstream hash was recorded."
        echo "Action: treat the first build after this change as a baseline; review upstream commits manually if flashing a main router."
    } >> "$REPORT"
    echo "RISK_LEVEL=unknown" >> "$GITHUB_ENV"
    echo "RISK_SUMMARY=No previous upstream hash recorded" >> "$GITHUB_ENV"
    exit 0
fi

if ! git cat-file -e "$PREVIOUS_HASH^{commit}" 2>/dev/null; then
    {
        echo "Risk: HIGH"
        echo "Reason: previous upstream hash is not reachable from the current branch history. The upstream branch may have been force-pushed or rewritten."
        echo "Action: do not flash full WiFi NSS firmware until this run is reviewed. Rebaseline only after a known-good boot."
        echo
        echo "Recent commits:"
        git log --oneline --date=short --pretty=format:'%h %ad %s' -30 || true
        echo
        echo
        echo "Recent critical-path commits:"
        git log --oneline --date=short --pretty=format:'%h %ad %s' -30 -- \
            package/qca-nss \
            package/kernel/mac80211 \
            target/linux/qualcommax \
            'target/linux/*/base-files/lib/upgrade' \
            'target/linux/*/image' || true
    } >> "$REPORT"
    echo "RISK_LEVEL=high" >> "$GITHUB_ENV"
    echo "RISK_SUMMARY=Previous upstream hash is not reachable" >> "$GITHUB_ENV"
    exit 0
fi

if [ "$PREVIOUS_HASH" = "$CURRENT_HASH" ]; then
    {
        echo "Risk: LOW"
        echo "Reason: upstream hash is unchanged."
    } >> "$REPORT"
    echo "RISK_LEVEL=low" >> "$GITHUB_ENV"
    echo "RISK_SUMMARY=Upstream hash unchanged" >> "$GITHUB_ENV"
    exit 0
fi

CHANGED_FILES="$(git diff --name-only "$PREVIOUS_HASH" "$CURRENT_HASH" || true)"
RISK_LEVEL="low"
RISK_SUMMARY="Upstream changed outside watched risk paths"

CRITICAL_PATTERN='^(package/qca-nss/|package/kernel/mac80211/|target/linux/qualcommax/|target/linux/.*/base-files/lib/upgrade/|target/linux/.*/image/)'
CONFIG_PATTERN='^(config/|include/target.mk|include/kernel|target/linux/.*/config-)'

CRITICAL_FILES="$(printf '%s\n' "$CHANGED_FILES" | grep -E "$CRITICAL_PATTERN" || true)"
CONFIG_FILES="$(printf '%s\n' "$CHANGED_FILES" | grep -E "$CONFIG_PATTERN" || true)"

if [ -n "$CRITICAL_FILES" ]; then
    RISK_LEVEL="high"
    RISK_SUMMARY="Critical NSS/WiFi/target/upgrade paths changed"
elif [ -n "$CONFIG_FILES" ]; then
    RISK_LEVEL="medium"
    RISK_SUMMARY="Build or target config paths changed"
fi

{
    echo "Risk: ${RISK_LEVEL^^}"
    echo "Reason: $RISK_SUMMARY"
    echo
    echo "Commits:"
    git log --oneline --date=short --pretty=format:'%h %ad %s' "$PREVIOUS_HASH..$CURRENT_HASH" || true
    echo
    echo
    echo "Changed files:"
    printf '%s\n' "$CHANGED_FILES"
    echo
    if [ -n "$CRITICAL_FILES" ]; then
        echo "Critical changed files:"
        printf '%s\n' "$CRITICAL_FILES"
        echo
    fi
    if [ -n "$CONFIG_FILES" ]; then
        echo "Config changed files:"
        printf '%s\n' "$CONFIG_FILES"
        echo
    fi
} >> "$REPORT"

echo "RISK_LEVEL=$RISK_LEVEL" >> "$GITHUB_ENV"
echo "RISK_SUMMARY=$RISK_SUMMARY" >> "$GITHUB_ENV"
