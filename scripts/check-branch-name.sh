#!/usr/bin/env bash
# Enforce branch names: feat/*, fix/*, revert-<pr>-*, or main.
set -euo pipefail

BRANCH="${1:-}"
if [[ -z "${BRANCH}" ]]; then
  BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
fi

if [[ -z "${BRANCH}" || "${BRANCH}" == "HEAD" ]]; then
  echo "Unable to determine branch name" >&2
  exit 1
fi

# Strip remote prefix if present (e.g. origin/feat/foo)
BRANCH="${BRANCH#origin/}"

if [[ "${BRANCH}" == "main" ]]; then
  echo "Branch name OK: ${BRANCH}"
  exit 0
fi

# feat/..., fix/..., or GitHub revert branches (revert-<pr>-<original-branch>)
if [[ "${BRANCH}" =~ ^(feat|fix)/.+ ]] \
  || [[ "${BRANCH}" =~ ^revert-[0-9]+-.+ ]]; then
  echo "Branch name OK: ${BRANCH}"
  exit 0
fi

echo "Invalid branch name: '${BRANCH}'" >&2
echo "Allowed: main, feat/<name>, fix/<name>, revert-<pr>-<name>" >&2
exit 1
