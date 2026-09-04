#!/usr/bin/env bash
# Pre-commit: gitleaks over the staged diff. Hard block on any finding.
set -u
REPO_ROOT="$(git rev-parse --show-toplevel)"
GITLEAKS="$(command -v gitleaks || echo "$HOME/.local/bin/gitleaks")"
if [ ! -x "$GITLEAKS" ]; then
    echo "pre-commit: gitleaks not found — refusing to commit without the secret scan." >&2
    exit 1
fi
if ! "$GITLEAKS" git --pre-commit --staged --no-banner --exit-code 1 "$REPO_ROOT" >&2; then
    echo "pre-commit: gitleaks found potential secrets in the staged diff — COMMIT BLOCKED." >&2
    exit 1
fi
