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

# Create errors log
touch .ralph-tests/errors.log

log "✓ Setup complete"
log ""
log "Next steps:"
log "  1. Review: .ralph-tests/test-files.txt"
log "  2. Run: ./.ralph-tests/test-loop.sh"
