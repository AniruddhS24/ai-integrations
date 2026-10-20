#!/usr/bin/env bash
# Extract one AI plugin's default-branch history from temporalio/sdk-typescript.
# FROZEN AFTER THE FIRST IMPORT: paths, message rewriting, callback and the
# filter-repo version must stay identical to reproduce imported commit IDs.
#
# Environment: PLUGIN (required), SRC_REF (default: main), SRC_REPO (clone URL).
set -euo pipefail

PLUGIN="${PLUGIN:?set PLUGIN to the destination folder name}"
SRC_REF="${SRC_REF:-main}"
SRC_REPO="${SRC_REPO:-https://github.com/temporalio/sdk-typescript.git}"
FILTER_REPO_VERSION=2.47.0
REPO="$(git rev-parse --show-toplevel)"
EXTRA_PATHS=()
EXTRA_RENAMES=()

# Full main-branch path archaeology at 046dcef5e3d5d08710c4a07d805f17fea41e5ae5:
# ai-sdk moved from packages/ai-sdk and three tests moved from packages/test.
# Other plugins originated under contrib. Shared configuration copied when a
# package was created is not a previous location of that package.
case "$PLUGIN" in
  vercel-ai-sdk)
    SOURCE=contrib/ai-sdk
    EXTRA_PATHS=(--path packages/ai-sdk/ --path packages/test/src/activities/ai-sdk.ts
      --path packages/test/src/test-ai-sdk.ts --path packages/test/src/workflows/ai-sdk.ts)
    EXTRA_RENAMES=(--path-rename "packages/ai-sdk/:typescript/$PLUGIN/"
      --path-rename "packages/test/src/activities/ai-sdk.ts:typescript/$PLUGIN/src/__tests__/activities/ai-sdk.ts"
      --path-rename "packages/test/src/test-ai-sdk.ts:typescript/$PLUGIN/src/__tests__/test-ai-sdk.ts"
      --path-rename "packages/test/src/workflows/ai-sdk.ts:typescript/$PLUGIN/src/__tests__/workflows/ai-sdk.ts")
    ;;
  google-adk) SOURCE=contrib/google-adk-agents ;;
  langsmith) SOURCE=contrib/langsmith ;;
  openai-agents) SOURCE=contrib/openai-agents ;;
  strands-agents) SOURCE=contrib/strands ;;
  *) echo "error: no path archaeology recorded for PLUGIN=$PLUGIN" >&2; exit 2 ;;
esac

WORK="$(mktemp -d)"
echo "cloning $SRC_REPO into $WORK/src"
git clone --quiet --no-local --no-tags --single-branch --branch main "$SRC_REPO" "$WORK/src"
cd "$WORK/src"
SRC_SHA="$(git rev-parse --verify "$SRC_REF^{commit}")"
if ! git merge-base --is-ancestor "$SRC_SHA" refs/remotes/origin/main; then
  echo "error: SRC_REF=$SRC_REF is not reachable from upstream main; not a history-import input" >&2
  exit 2
fi
git reset --quiet --hard "$SRC_SHA"

cat > "$WORK/replace-message.txt" <<'RULE'
regex:(?<![\w/#])#(\d+)\b==>temporalio/sdk-typescript#\1
RULE
uvx --from "git-filter-repo==$FILTER_REPO_VERSION" git-filter-repo \
  --force --preserve-commit-hashes --prune-empty always \
  --path "$SOURCE/" ${EXTRA_PATHS[@]+"${EXTRA_PATHS[@]}"} \
  --path-rename "$SOURCE/:typescript/$PLUGIN/" ${EXTRA_RENAMES[@]+"${EXTRA_RENAMES[@]}"} \
  --replace-message "$WORK/replace-message.txt" \
  --commit-callback '
lines = commit.message.rstrip(b"\n").split(b"\n")
sep = b"\n" if len(lines) > 1 and re.match(rb"^[A-Za-z][A-Za-z-]*: ", lines[-1]) else b"\n\n"
commit.message = b"\n".join(lines) + sep + b"Migrated-From: temporalio/sdk-typescript@" + commit.original_id + b"\n"'

cat <<MSG
SRC_SHA=$SRC_SHA
FILTER_REPO=$FILTER_REPO_VERSION
WORK=$WORK/src
commits=$(git rev-list --count HEAD)
identities=$(git shortlog -sne HEAD | wc -l | tr -d ' ')
tags=$(git tag | wc -l | tr -d ' ')

In $REPO, fetch main from $WORK/src and merge with
  git merge --allow-unrelated-histories --no-ff
Record the merge in IMPORTS.md. Use history-import on the PR and
Create a merge commit, never squash or rebase.
MSG
