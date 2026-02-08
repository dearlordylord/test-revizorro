# Test-Revizorro: Universal Test Marking Loop

**Copy this entire message to any LLM coding agent on any project (Python, Rust, Go, TypeScript, etc.)**

---

## What This Does

Builds Ralph-style system that marks all test cases for AI quality review.

**The Problem**: AI agents generate/modify tests with issues:
- Fake/mocked data
- Tests marked `.skip()` without reason
- Tests that don't test anything
- Other AI antipatterns

**Phase 1**: Mark all test cases with `// test-revizorro: scheduled`
**Phase 2**: Review marked tests for quality issues (see Phase 2 section below)

---

## Your Task

**PRIMARY GOAL**: Build working scripts for THIS project using the coding agent YOU have installed.

**NOT the goal**: Make scripts work with every possible coding agent. Just make it work HERE, NOW, with what's available.

**Adaptability is a side benefit**: Document your choices so others can learn from the patterns, but focus on making it WORK for this specific environment first.

Build custom version for THIS project by adapting these working examples:

### Example 1: Test List Generator (Vitest Project)

This is from a TypeScript/Vitest project. Adapt for your framework.

**File**: `.ralph-tests/generate-test-list.sh`

```bash
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
```

**Output**: `.ralph-tests/test-files.txt`

```
test/config/config.test.ts
test/domain/schemas.test.ts
test/huly/client.test.ts
test/huly/errors.test.ts
test/huly/operations/issues.test.ts
test/index.test.ts
test/mcp/error-mapping.test.ts
test/mcp/server.test.ts
test/placeholder.test.ts
```

One path per line. Clean. No logs mixed in (logs go to stderr).

---

### Example 2: Loop Structure

**Key function**: `build_test_prompt()` - what to tell the sub-agent

```bash
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

## On Completion

Output: "MARKED: N tests in $test_file" (where N is count)
EOF
}
```

**Loop pseudocode**:

```bash
# Read test files into array
mapfile -t test_files < test-files.txt

# For each file
for test_file in "${test_files[@]}"; do
    prompt=$(build_test_prompt "$test_file" $index $total)

    # Fresh session per file (Ralph principle)
    echo "$prompt" | claude --model sonnet > output

    # Check success
    if grep -q "MARKED:" output && git diff --name-only HEAD | grep -q "$test_file"; then
        # File modified + commit exists
        mark_complete
        index++  # ROTATE to next file
    else
        # Failure
        failure_count++
        if [ $failure_count -ge 3 ]; then
            # GUTTER: add guardrail, skip file
            add_guardrail
            index++
        else
            # Retry same file, fresh session
            continue
        fi
    fi
done
```

---

### Example 3: Setup Script

```bash
#!/usr/bin/env bash
set -euo pipefail

log() { echo "[SETUP] $1"; }

log "Initializing test-revizorro..."

# Make executable
chmod +x .ralph-tests/*.sh

# Generate test list
log "Generating test file list..."
./.ralph-tests/generate-test-list.sh

# Initialize state
mkdir -p .ralph-tests
cat > .ralph-tests/state.json <<'EOF'
{
  "current_index": 0,
  "failure_count": 0,
  "processed": []
}
EOF

# Create guardrails template
cat > .ralph-tests/guardrails.md <<'EOF'
# Guardrails

Learned patterns from failures. Read before each file.

## General Rules

- Read entire test file first
- Mark all active test cases
- Skip disabled tests
- Be idempotent
- Don't modify test logic

---

## Project-Specific Learnings

(Accumulates as files are processed)
EOF

log "✓ Setup complete"
log ""
log "Next steps:"
log "  1. Review: .ralph-tests/test-files.txt"
log "  2. Run: ./.ralph-tests/test-loop.sh"
```

---

## What You Need to Do

1. **Adapt `generate-test-list.sh`** for this project's framework
   - Run discovery: what test framework? what list command?
   - Update `detect_framework()` and `generate_list()` cases
   - Test it: does it generate clean test-files.txt?

2. **Create `test-loop.sh`** with:
   - `build_test_prompt()` function (adapt comment syntax for language)
   - Main loop (use example pseudocode)
   - State management (jq for state.json updates)
   - Success detection (check for "MARKED:" in output + file contains marker)
   - **CRITICAL**: Check coding agent CLI help to find correct flags
     - Example for Claude: `claude --help` shows `-p` (print mode) and `--permission-mode acceptEdits` needed
     - Without correct flags, agent may run interactively or skip file edits
     - Adjust invocation: `echo "$prompt" | <agent-cli> -p --permission-mode acceptEdits`
     - For other agents: check their docs for non-interactive + auto-permission flags

3. **Create `setup.sh`** using example above

4. **Test on ONE file first**:
   ```bash
   ./setup.sh
   # Modify test-loop.sh to process just first file
   ./test-loop.sh
   # Verify: file marked, committed
   ```

5. **Deploy full loop**

---

## Key Principles

✓ **Fresh context per file** (new claude invocation)
✓ **Mark test CASES** (each `it()`, `test()`, etc.)
✓ **Skip disabled tests** (already reviewed)
✓ **Idempotent** (skip already marked)
✓ **State in filesystem** (state.json, not chat)
✓ **Rotation** after success or 3 failures

---

## Expected File Structure After

```
.ralph-tests/
├── generate-test-list.sh    # Framework detection + list generation
├── test-loop.sh              # Ralph-style iteration loop
├── setup.sh                  # Initialization
├── test-files.txt            # One test path per line
├── state.json                # Current progress
└── guardrails.md             # Accumulated learnings
```

---

## Important: Test FILE vs Test CASE

- **Test FILE**: `test/api.test.ts` (what loop iterates)
- **Test CASE**: Each `it("should work", ...)` inside file (what agent marks)
- **Disabled test**: `.skip()`, `.todo()`, `@Ignore` (DON'T mark)

Agent marks individual test cases within each file.

---

# Phase 2: Parallel Test Review System

**Prerequisites**: Phase 1 complete (all test cases marked with `test-revizorro: scheduled`)

## What Phase 2 Does

Reviews each individual test case for AI-generated antipatterns using parallel agent pool.

**The Problem**: AI agents create tests with issues:
- **Fake passes**: Changed expectations to match wrong behavior
- **Convenient mocks**: Mocked data returns passing but useless values
- **No actual testing**: Test doesn't verify real behavior
- **Overly permissive**: Accepts any result as success

**Architecture**:
- **Controller**: Extracts test positions, manages agent pool, feeds work
- **Agent pool**: N parallel agents reviewing tests concurrently
- **Work unit**: Single test case (file path + line number)

## Phase 2 Steps

### 1. Extract Test Case Positions

Generate list of all marked test locations:

```bash
#!/usr/bin/env bash
# generate-review-list.sh
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
```

**Output format**: `.ralph-tests/review-list.txt`
```
test/config/config.test.ts:50
test/config/config.test.ts:69
test/domain/schemas.test.ts:45
...
```

One test case position per line.

### 2. Build Review Prompt

```bash
build_review_prompt() {
    local test_file=$1
    local test_line=$2
    local test_index=$3
    local total_tests=$4

    cat <<EOF
# TEST REVIEW - test-revizorro Phase 2 - [${test_index}/${total_tests}]

You are a fresh agent session. Your ONLY job: review ONE test case for AI antipatterns.

## Test Location
File: \`$test_file\`
Line: $test_line (marker comment line)

## Your Mission

Analyze this ONE test case for AI-generated quality issues.

## Steps

1. **Read test file**, find test case at line $test_line
   - The marker \`// test-revizorro: scheduled\` is at line $test_line
   - The actual test (it/test/describe) is on the NEXT line

2. **Read related application code**
   - Find what's being tested (imports, functions, classes)
   - Read source files to understand expected behavior

3. **Analyze for AI antipatterns**:

   **Fake Pass Indicators**:
   - Expectations changed to match wrong output (toBe(actualWrong) instead of toBe(expectedCorrect))
   - Mock setup returns convenient values that make test pass without testing real behavior
   - Assertions removed or weakened (expect anything, accept all results)
   - Test verifies implementation details, not behavior

   **Useless Mock Indicators**:
   - Mock returns hardcoded value unrelated to test scenario
   - Mock bypasses all logic being tested
   - Mock setup more complex than real implementation
   - Every external dependency mocked (nothing actually tested)

   **No Real Testing**:
   - Test only checks types/syntax (expect(result).toBeDefined())
   - Test passes with any value (expect(result).toBeTruthy())
   - No assertions or only trivial ones
   - Test duplicates another test exactly

4. **Make decision and update marker**:

   **If test is GOOD** (tests real behavior, proper assertions, realistic mocks):
   \`\`\`
      \`\`\`

   **If test is SUSPECT** (has antipatterns):
   \`\`\`
   // test-revizorro: suspect [Brief explanation: what's wrong and why]
   \`\`\`

   Keep "suspect" keyword immediately after "test-revizorro:" for greppability.

## Example Review

**File**: test/api.test.ts:42

**Before**:
\`\`\`typescript
// test-revizorro: scheduled
it('fetches user data', async () => {
  mockApi.getUser.mockResolvedValue({ id: 123, name: 'any' })
  const result = await fetchUser(456)
  expect(result).toBeDefined()
})
\`\`\`

**Issues found**:
- Mock returns hardcoded user for ID 456, but test passes ID 456 - wrong ID ignored
- Assertion only checks defined, not actual data correctness
- Test would pass with any result shape

**After**:
\`\`\`typescript
// test-revizorro: suspect [Mock ignores input ID (456), only checks result exists not correctness]
it('fetches user data', async () => {
  mockApi.getUser.mockResolvedValue({ id: 123, name: 'any' })
  const result = await fetchUser(456)
  expect(result).toBeDefined()
})
\`\`\`

## Critical Rules

- Review ONLY the one test at specified line
- Read application code to understand expected behavior
- Change ONLY the marker comment (scheduled → approved/suspect)
- Don't modify test logic
- Keep explanations brief (one line)
- Always include reasoning in suspect marker

## On Completion

Output: "REVIEWED: $test_file:$test_line - [approved|suspect]"
EOF
}
```

### 3. Controller with Agent Pool

**CRITICAL**: Parallel job control varies by shell version and system. Choose approach based on your environment.

#### Approach A: Manual PID Tracking (Most Compatible)

Works on bash 3.2+ (macOS default), Linux, BSD. No external dependencies.

```bash
#!/usr/bin/env bash
# review-loop.sh
set -euo pipefail

POOL_SIZE=\${POOL_SIZE:-10}  # Configurable parallel agents
REVIEW_LIST="\${REVIEW_LIST:-.ralph-tests/review-list.txt}"
AGENT_CLI="\${AGENT_CLI:-<coding-agent-cli>}"  # Discover from environment

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] \$1"; }

# IMPORTANT: Discover agent CLI flags from help
# Example for Claude: claude --help shows -p and --permission-mode acceptEdits
# Example for Cursor: cursor --help shows --non-interactive and --accept-all
# Check YOUR agent's help documentation and set correct flags below
AGENT_FLAGS="-p --permission-mode acceptEdits"  # Adapt for your agent

# Read review list (bash 3.2 compatible)
reviews=()
while IFS= read -r line; do
    reviews+=("\$line")
done < "\$REVIEW_LIST"
total=\${#reviews[@]}

log "Starting review pool (size: \$POOL_SIZE)"
log "Total test cases: \$total"

# Track PIDs manually (works on all bash versions)
declare -a pids

for ((idx=0; idx<total; idx++)); do
    review_item="\${reviews[\$idx]}"
    test_file=\$(echo "\$review_item" | cut -d: -f1)
    test_line=\$(echo "\$review_item" | cut -d: -f2)

    # Wait if pool is full - check actual running processes
    while true; do
        running=0
        if [ \${#pids[@]} -gt 0 ]; then
            for pid in "\${pids[@]}"; do
                if kill -0 "\$pid" 2>/dev/null; then
                    running=\$((running + 1))
                fi
            done
        fi

        if [ \$running -lt \$POOL_SIZE ]; then
            break
        fi
        sleep 0.5
    done

    log "[\$((idx + 1))/\$total] Spawning: \$test_file:\$test_line"

    # Run agent in background
    (
        prompt=\$(build_review_prompt "\$test_file" "\$test_line" \$((idx + 1)) \$total)
        output_file="/tmp/review_\$idx.log"
        echo "\$prompt" | \$AGENT_CLI \$AGENT_FLAGS > "\$output_file" 2>&1
        exit_code=\$?

        if [ \$exit_code -eq 0 ]; then
            log "✓ Completed: \$test_file:\$test_line"
        else
            log "✗ Failed: \$test_file:\$test_line (exit: \$exit_code)"
        fi
    ) &

    pids+=(\$!)
done

# Wait for all jobs
log "Waiting for all jobs to complete..."
wait

log "✓ All reviews complete"
```

**Why manual PID tracking?**
- `wait -n` (wait for next job) requires bash 4.3+ (not on macOS which ships bash 3.2)
- `kill -0 $pid` checks if process exists without killing it (POSIX standard, works everywhere)
- Array of PIDs works on bash 3.2+

#### Approach B: GNU Parallel (Best Performance, Requires Install)

```bash
#!/usr/bin/env bash
# review-loop.sh with GNU parallel
set -euo pipefail

POOL_SIZE=\${POOL_SIZE:-10}
REVIEW_LIST=".ralph-tests/review-list.txt"
AGENT_CLI="\${AGENT_CLI:-<coding-agent-cli>}"

# Check if parallel installed
if ! command -v parallel &> /dev/null; then
    echo "Error: GNU parallel not found. Install: brew install parallel (macOS) or apt install parallel (Linux)"
    exit 1
fi

# Run reviews in parallel
cat "\$REVIEW_LIST" | parallel -j \$POOL_SIZE --line-buffer '
    test_file=\$(echo {} | cut -d: -f1)
    test_line=\$(echo {} | cut -d: -f2)
    prompt=\$(build_review_prompt "\$test_file" "\$test_line" {#} {#})
    echo "\$prompt" | '\$AGENT_CLI' <agent-flags> > /tmp/review_{#}.log 2>&1
    echo "[\$(date)] Completed: \$test_file:\$test_line"
'
```

**Pros**: Best performance, built-in progress, retry logic
**Cons**: Requires external tool installation

#### Approach C: xargs -P (POSIX, Simpler than GNU Parallel)

```bash
#!/usr/bin/env bash
# review-loop.sh with xargs
set -euo pipefail

POOL_SIZE=\${POOL_SIZE:-10}
REVIEW_LIST=".ralph-tests/review-list.txt"

# Process each line with xargs parallel execution
cat "\$REVIEW_LIST" | xargs -P \$POOL_SIZE -I {} bash -c '
    test_file=\$(echo {} | cut -d: -f1)
    test_line=\$(echo {} | cut -d: -f2)
    # ... agent invocation
'
```

**Pros**: Available on most Unix systems
**Cons**: Limited control, harder to handle complex logic

#### Approach D: Fallback to Serial Execution (Always Works)

If parallel approaches fail or cause issues, fall back to simple sequential processing:

```bash
#!/usr/bin/env bash
# review-loop.sh - SERIAL FALLBACK
set -euo pipefail

REVIEW_LIST=".ralph-tests/review-list.txt"
AGENT_CLI="${AGENT_CLI:-claude}"
AGENT_FLAGS="-p --permission-mode acceptEdits"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

# Read review list
reviews=()
while IFS= read -r line; do
    reviews+=("$line")
done < "$REVIEW_LIST"
total=${#reviews[@]}

log "Starting SERIAL review (no parallelism)"
log "Total: $total test cases"

# Process sequentially - one at a time
for ((idx=0; idx<total; idx++)); do
    review_item="${reviews[$idx]}"
    test_file=$(echo "$review_item" | cut -d: -f1)
    test_line=$(echo "$review_item" | cut -d: -f2)

    log "[$((idx + 1))/$total] Processing: $test_file:$test_line"

    prompt=$(build_review_prompt "$test_file" "$test_line" $((idx + 1)) $total)
    output_file="/tmp/review_$idx.log"

    echo "$prompt" | $AGENT_CLI $AGENT_FLAGS > "$output_file" 2>&1

    if [ $? -eq 0 ]; then
        log "✓ Completed: $test_file:$test_line"
    else
        log "✗ Failed: $test_file:$test_line"
    fi
done

log "✓ All reviews complete"
```

**When to use serial fallback**:
- Parallel approaches causing shell errors
- System resource constraints (limited CPU/memory)
- Debugging (easier to trace issues)
- Simple projects (<50 tests where speed doesn't matter)

**Trade-off**: Slower (252 tests × 30s = ~2 hours) but guaranteed to work on any system.

## Agent CLI Flags Discovery

**PRIMARY GOAL**: Find the correct flags for the coding agent installed in THIS environment.

**Discovery process for THIS project**:
1. **Identify the agent**: What coding agent CLI is available?
   - Check environment: `which claude` / `which cursor` / `which aider`
   - Or ask: What agent CLI should I use? Where is it installed?

2. **Find the right flags**: Run `<agent-cli> --help`
   - Look for **non-interactive mode**: `-p`, `--print`, `--non-interactive`, `--batch`
   - Look for **auto-approve edits**: `--permission-mode acceptEdits`, `--accept-all`, `--yes`, `-y`

3. **Test it works**: `echo "test prompt" | <agent> <flags>`
   - Should complete immediately
   - Should output plain text (not formatted UI)
   - Should modify files when instructed

4. **Use those specific values** in your scripts

**Reference examples** (for learning, not copy-paste):
- **Claude**: `-p --permission-mode acceptEdits`
- **Cursor**: might be `--non-interactive --accept-all`
- **Aider**: might be `--yes --auto-commits`

Your flags will be specific to YOUR installed agent. Don't copy these examples blindly.

**What happens if flags are wrong**:
- Agent hangs waiting for user input
- Agent asks permission for every edit (blocks pipeline)
- Agent outputs formatted UI instead of plain text
- Nothing gets done

**Agent behavior note**: Don't create backup files (`.backup`, `.beforeedit`, `.backup-revizorro`, etc). Just edit files directly as instructed.

### 4. Setup Phase 2

```bash
#!/usr/bin/env bash
# setup-phase2.sh
set -euo pipefail

log() { echo "[SETUP-PHASE2] \$1"; }

log "Initializing Phase 2 (review system)..."

# Generate review list from scheduled markers
./.ralph-tests/generate-review-list.sh

# Initialize state
cat > .ralph-tests/review-state.json <<'EOF'
{
  "phase": 2,
  "current_index": 0,
  "total": 0,
  "completed": [],
  "approved": 0,
  "suspect": 0
}
EOF

log "✓ Phase 2 setup complete"
log ""
log "Next steps:"
log "  1. Review: .ralph-tests/review-list.txt (all test positions)"
log "  2. Set pool size: export POOL_SIZE=4"
log "  3. Run: ./.ralph-tests/review-loop.sh"
```

## Phase 2 Key Principles

✓ **One test case per agent** (not file, individual test)
✓ **Parallel execution** (N agents concurrently)
✓ **Read application code** (understand expected behavior)
✓ **Conservative marking** (approve only clearly good tests)
✓ **Brief explanations** (one-line suspect reason)
✓ **Greppable markers** (test-revizorro: suspect [explanation])

## Expected Results

After Phase 2:
```bash
# Count results
grep -r "test-revizorro: approved" test/ | wc -l      # Good tests
grep -r "test-revizorro: suspect" test/ | wc -l       # Problematic tests

# List all suspect tests with reasons
grep -r "test-revizorro: suspect" test/
```

Example output:
```
test/api.test.ts:42:  // test-revizorro: suspect [Mock ignores input, only checks defined]
test/db.test.ts:89:   // test-revizorro: suspect [Expectations changed to match wrong output]
```

## Troubleshooting Parallel Execution

### Problem: Too many processes spawned (pool not limiting)

**Symptom**: `ps aux | grep <agent>` shows 50+ processes instead of POOL_SIZE

**Causes**:
1. Using `wait -n` on bash 3.2 (doesn't work, silently fails)
2. PID tracking logic broken (not checking running processes correctly)

**Fix**:
- Use manual PID tracking with `kill -0` (Approach A above)
- Test pool control: `for i in {1..20}; do ps aux | grep <agent> | wc -l; sleep 1; done`
- Should see count stay around POOL_SIZE, not grow unbounded

### Problem: Agent hangs or waits for input

**Symptom**: Script spawns one agent and stops, no progress

**Causes**:
1. Missing non-interactive flag (agent waiting for user input)
2. Missing auto-approve flag (agent asking permission for edits)

**Fix**:
- Check agent help: `<agent-cli> --help | grep -i "non-interactive\|batch\|print"`
- Test manually: `echo "test prompt" | <agent> <flags>` should complete immediately
- Verify output is plain text, not formatted UI

### Problem: No files modified after reviews complete

**Symptom**: All agents complete but `git diff` shows no changes

**Causes**:
1. Agent not executing file edits (wrong permission flags)
2. Agent outputting response but not using tools

**Fix**:
- Check one agent output: `cat /tmp/review_0.log`
- Should see "REVIEWED: ..." and file should have marker changed
- If agent just responds with text, check permission flags

### Problem: Bash syntax errors (unbound variable, bad substitution)

**Symptom**: Script fails with "unbound variable" or "bad substitution"

**Causes**:
1. Bash 3.2 incompatibility (no `declare -A`, different array handling)
2. `mapfile` not available (bash 3.2 doesn't have it)

**Fix**:
- Use manual array population: `while IFS= read -r line; do array+=("$line"); done < file`
- Check bash version: `bash --version`
- Test on oldest bash version you support (macOS has bash 3.2)

## Adapting to Your Project

1. **Extract test positions**: Adapt grep patterns for your comment syntax
2. **Review criteria**: Add project-specific antipatterns
3. **Pool size**: Start with 4-8, monitor CPU/memory, adjust up to 10-20 if system handles it
4. **Agent CLI flags**: Discover from `<agent> --help`, test manually before automating
5. **Shell compatibility**: Test on oldest shell version your team uses (macOS, Linux, CI)
6. **Parallel approach**: Start with Approach A (manual PID tracking), switch to GNU parallel if performance needed

## Validation Checklist Before Full Run

Before processing all test cases:

1. ✓ **Test agent CLI manually**: `echo "mark test" | <agent> <flags>` completes and modifies file
2. ✓ **Test on 3 test cases**: `head -3 review-list.txt > test-list.txt && REVIEW_LIST=test-list.txt ./review-loop.sh`
3. ✓ **Verify pool control**: Monitor `ps aux | grep <agent>` count stays around POOL_SIZE
4. ✓ **Check file modifications**: `git diff` shows marker changes (scheduled → approved/suspect)
5. ✓ **Review quality**: Read 5 suspect findings - are they accurate? detailed enough?

Only after validation: run on full test suite.

---

## Important Reminders

**This prompt is the deliverable.** The example scripts shown are working examples from a TypeScript/Vitest project, but they are NOT copy-paste solutions. Your job:

1. **Discover THIS project's specifics**:
   - What test framework? (run detection)
   - What language/comment syntax? (TypeScript `//`, Python `#`, etc.)
   - What coding agent CLI? (check `--help`)
   - What shell version? (`bash --version`)

2. **Adapt the patterns**:
   - Phase 1: Marking loop (sequential, one file at a time)
   - Phase 2: Review loop (parallel, N test cases at once)
   - Job control: Choose approach based on shell version
   - Agent flags: Discover from help, test manually

3. **Test incrementally**:
   - Generate test list (verify clean output)
   - Mark ONE file (verify marker added)
   - Review 3 test cases (verify quality)
   - Run full system only after validation

**The goal**: Any coding agent, on any project, can use this prompt to build working test-revizorro infrastructure.

---

Start by running discovery on THIS codebase, then adapt the examples above.
