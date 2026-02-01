#!/usr/bin/env bash
# Ralph-style test marking loop
set -euo pipefail

# Configuration
STATE_FILE=".ralph-tests/state.json"
TEST_LIST=".ralph-tests/test-files.txt"
GUARDRAILS=".ralph-tests/guardrails.md"
ERRORS_LOG=".ralph-tests/errors.log"
MAX_FAILURES_PER_TEST=3
CLAUDE_CLI="${CLAUDE_CLI:-claude}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Build prompt for marking tests in a single file
build_test_prompt() {
    local test_file=$1
    local test_index=$2
    local total_tests=$3

    cat <<EOF
# TEST MARKING - test-revizorro Phase 1 - [${test_index}/${total_tests}]

You are a fresh Claude session. Your ONLY job: mark all test cases in this ONE test file.

## Test File
\`$test_file\`

## Your Mission

Mark all individual test cases for future AI quality review.

## Steps

1. **Read the entire test file**
2. **Identify EVERY test case** (not the file, individual tests):
   - Vitest/Jest: Each \`it()\` or \`test()\` call
   - Pytest: Each function starting with \`test_\`
   - Rust: Each \`#[test]\` function
   - Go: Each function starting with \`Test\`
3. **Add comment ABOVE each test**:
   - TypeScript/JavaScript: \`// test-revizorro: scheduled\`
   - Python: \`# test-revizorro: scheduled\`
   - Rust/Go: \`// test-revizorro: scheduled\`
4. **Do NOT modify test logic** - ONLY add comments
5. **Skip already marked tests** (idempotent)
6. **Skip disabled tests** (\`.skip()\`, \`.todo()\`, \`@Ignore\`, etc.)
7. **Commit**: \`git commit -m "test-revizorro: mark tests in $test_file"\`

## Example (TypeScript/Vitest)

Before:
\`\`\`typescript
describe("API", () => {
  it("works", () => { expect(true).toBe(true); });
  it.skip("broken", () => { ... });  // disabled
  it("handles errors", () => { ... });
});
\`\`\`

After:
\`\`\`typescript
describe("API", () => {
  // test-revizorro: scheduled
  it("works", () => { expect(true).toBe(true); });

  it.skip("broken", () => { ... });  // NOT marked (disabled)

  // test-revizorro: scheduled
  it("handles errors", () => { ... });
});
\`\`\`

## Critical Rules

- Mark EVERY active test case
- Nested describe blocks: mark each it() inside
- Don't mark disabled tests (.skip, .todo) - already reviewed by humans
- Already marked: skip (idempotent)
- Don't modify test logic

## Guardrails

$(cat "$GUARDRAILS")

## On Completion

Output: "MARKED: N tests in $test_file" (where N is count)
EOF
}

# State management
get_state() {
    local key=$1
    jq -r ".$key" "$STATE_FILE"
}

update_state() {
    local key=$1
    local value=$2
    local tmp=$(mktemp)
    jq ".$key = $value" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

add_processed() {
    local test_file=$1
    local tmp=$(mktemp)
    jq ".processed += [\"$test_file\"]" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

add_guardrail() {
    local test_file=$1
    local reason=$2
    cat >> "$GUARDRAILS" <<EOF

---

## $test_file

**Status**: GUTTER (skipped after $MAX_FAILURES_PER_TEST failures)

**Reason**: $reason

EOF
}

# Check if test was successfully marked
check_success() {
    local test_file=$1
    local output=$2

    # Check for success signal in output
    if ! grep -q "MARKED:" "$output"; then
        return 1
    fi

    # Check if file was actually modified
    if ! git diff "$test_file" | grep -q "test-revizorro: scheduled"; then
        return 1
    fi

    return 0
}

# Main loop
main() {
    log "Starting test-revizorro marking loop"

    # Read test files
    if [ ! -f "$TEST_LIST" ]; then
        log "ERROR: $TEST_LIST not found. Run setup.sh first."
        exit 1
    fi

    local test_files=()
    while IFS= read -r line; do
        test_files+=("$line")
    done < "$TEST_LIST"
    local total_tests=${#test_files[@]}

    log "Found $total_tests test files to process"

    # Get current state
    local current_index=$(get_state "current_index")
    local failure_count=$(get_state "failure_count")

    # Process files starting from current index
    while [ $current_index -lt $total_tests ]; do
        local test_file="${test_files[$current_index]}"

        log "[$((current_index + 1))/$total_tests] Processing: $test_file"

        # Build prompt
        local prompt=$(build_test_prompt "$test_file" $((current_index + 1)) $total_tests)
        local output_file=$(mktemp)

        # Invoke fresh Claude session
        log "Spawning fresh agent session..."
        echo "$prompt" | $CLAUDE_CLI -p --model sonnet --permission-mode acceptEdits > "$output_file" 2>&1 || true

        # Check success
        if check_success "$test_file" "$output_file"; then
            log "✓ SUCCESS: $test_file marked"
            add_processed "$test_file"

            # Reset failure count, move to next file
            update_state "failure_count" 0
            current_index=$((current_index + 1))
            update_state "current_index" $current_index
            failure_count=0
        else
            log "✗ FAILURE: $test_file not marked"
            failure_count=$((failure_count + 1))
            update_state "failure_count" $failure_count

            # Log error
            echo "=== Failure #$failure_count for $test_file ===" >> "$ERRORS_LOG"
            cat "$output_file" >> "$ERRORS_LOG"
            echo "" >> "$ERRORS_LOG"

            if [ $failure_count -ge $MAX_FAILURES_PER_TEST ]; then
                log "⚠ GUTTER: $test_file failed $MAX_FAILURES_PER_TEST times, skipping"
                add_guardrail "$test_file" "Failed $MAX_FAILURES_PER_TEST times"

                # Move to next file, reset failure count
                current_index=$((current_index + 1))
                update_state "current_index" $current_index
                update_state "failure_count" 0
                failure_count=0
            else
                log "Retrying $test_file (attempt $((failure_count + 1))/$MAX_FAILURES_PER_TEST)..."
            fi
        fi

        rm -f "$output_file"
    done

    log "✓ All test files processed"
}

main
