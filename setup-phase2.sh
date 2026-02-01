#!/usr/bin/env bash
# Setup Phase 2 - review system initialization
set -euo pipefail

log() { echo "[SETUP-PHASE2] $1"; }

log "Initializing Phase 2 (review system)..."

# Make scripts executable
chmod +x .ralph-tests/generate-review-list.sh
chmod +x .ralph-tests/review-loop.sh

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
log "  2. Set pool size: export POOL_SIZE=2"
log "  3. Run: ./.ralph-tests/review-loop.sh"
