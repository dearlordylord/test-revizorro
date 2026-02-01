#!/usr/bin/env bash
# Generate test file list - framework-agnostic
set -euo pipefail

OUTPUT_FILE=".ralph-tests/test-files.txt"
mkdir -p .ralph-tests

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >&2
}

# Detect test framework
detect_framework() {
    if [ -f "package.json" ]; then
        if grep -q '"vitest"' package.json; then
            echo "vitest"
        elif grep -q '"jest"' package.json; then
            echo "jest"
        fi
    elif [ -f "pytest.ini" ] || [ -f "pyproject.toml" ]; then
        echo "pytest"
    elif [ -f "Cargo.toml" ]; then
        echo "cargo"
    elif [ -f "go.mod" ]; then
        echo "go"
    else
        echo "unknown"
    fi
}

# Generate list based on framework
generate_list() {
    local framework=$1

    case "$framework" in
        vitest)
            log "Detected: Vitest"
            npx vitest list 2>/dev/null | awk -F ' > ' '{print $1}' | sort -u
            ;;
        jest)
            log "Detected: Jest"
            npx jest --listTests 2>/dev/null | sort -u
            ;;
        pytest)
            log "Detected: Pytest"
            pytest --collect-only -q 2>/dev/null | grep '::' | cut -d: -f1 | sort -u
            ;;
        cargo)
            log "Detected: Cargo"
            find . -name '*_test.rs' -o -name 'tests/*.rs' | sort -u
            ;;
        go)
            log "Detected: Go"
            go list -f '{{.Dir}}/{{range .TestGoFiles}}{{.}} {{end}}' ./... 2>/dev/null | \
                tr ' ' '\n' | grep '_test.go$' | sort -u
            ;;
        *)
            log "Unknown - using glob patterns"
            find . -type f \( \
                -name "*.test.ts" -o -name "*.test.js" -o \
                -name "*.spec.ts" -o -name "*.spec.js" -o \
                -name "*_test.py" -o -name "test_*.py" -o \
                -name "*_test.go" \
            \) | grep -v node_modules | sort -u
            ;;
    esac
}

# Main
log "Detecting test framework..."
FRAMEWORK=$(detect_framework)

log "Generating test file list..."
generate_list "$FRAMEWORK" > "$OUTPUT_FILE"

COUNT=$(wc -l < "$OUTPUT_FILE")
log "Found $COUNT test files"
log "Written to: $OUTPUT_FILE"

exit 0
