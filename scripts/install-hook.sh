#!/usr/bin/env bash
# Install the pre-commit secret scan. Hooks don't survive clones — run once after cloning.
set -eu
REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOK="$REPO_ROOT/.git/hooks/pre-commit"
printf '#!/usr/bin/env bash\nexec "$(git rev-parse --show-toplevel)/scripts/pre-commit-hook.sh"\n' > "$HOOK"
chmod +x "$HOOK" "$REPO_ROOT/scripts/pre-commit-hook.sh"
echo "pre-commit hook installed -> $HOOK"
