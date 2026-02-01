#!/usr/bin/env bash
# Generate review list - extract test case positions
set -euo pipefail

OUTPUT_FILE=".ralph-tests/review-list.txt"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >&2; }

log "Extracting test case positions..."

# Find all files with scheduled markers
grep -rl "test-revizorro: scheduled" test/ 2>/dev/null | while read -r file; do
    # Get line numbers of scheduled markers
    grep -n "test-revizorro: scheduled" "$file" | cut -d: -f1 | while read -r line; do
        echo "$file:$line"
    done
done > "$OUTPUT_FILE"

COUNT=$(wc -l < "$OUTPUT_FILE")
log "Found $COUNT test cases to review"
log "Written to: $OUTPUT_FILE"
