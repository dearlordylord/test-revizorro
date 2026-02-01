# Test-Revizorro

Automated quality review system for AI-generated test code.

## Usage

Copy `PROMPT.md` to your coding agent to build project-specific scripts.

You can delete the project-specific scripts folder when you're done reviewing your tests.

## Problem

AI coding agents generate tests with quality issues:
- Fake/mocked data instead of real assertions
- Tests marked `.skip()` without reason
- Tests that don't actually test anything
- Other AI antipatterns

## Solution

Two-phase marking and review system:

**Phase 1**: Mark all test cases with `// test-revizorro: scheduled`
- Automatically finds all test cases in codebase
- Adds comment markers for tracking
- Prepares tests for review

**Phase 2**: Review each marked test for quality issues
- Parallel processing using your coding agent CLI
- Agent examines test code against quality criteria
- Marks tests as `approved` or `suspect` with findings
- Review output logged for manual inspection

## How It Works

Uses bash scripts + your installed coding agent (Claude, Cursor, Aider, etc) to:
1. Extract test positions from codebase
2. Generate review prompts with context
3. Execute reviews in parallel (configurable pool size)
4. Track state between runs (resume capability)
5. Output findings for manual review

## Key Design Principles

- **Project-specific**: Adapt patterns, grep expressions, and review criteria to your project.
- **Agent-agnostic**: Works with your installed coding agent. Discover CLI flags from `--help`, configure for your environment.
- **Resumable**: State tracking allows interruption and continuation.
- **Parallel**: Configurable worker pool for speed.

## Output

After Phase 2, check test files for markers:
- `// test-revizorro: approved` - Passed review
- `// test-revizorro: suspect | [finding details]` - Requires attention

Review suspect findings manually. Agent identifies issues but human makes final call.
