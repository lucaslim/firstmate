#!/usr/bin/env bash
# Live repro for #6168 in a guarded fm-lab-* Herdr session.
# Usage: live-seeded-prune-repro.sh <worktree> <herdr.sh to exercise> <mode: relabel|rename>
set -u
ROOT=$1; IMPL=$2; MODE=$3
. "$ROOT/tests/herdr-test-safety.sh"
herdr_forget_inherited_pane
SESSION="fm-lab-prune6168-$$"
export HERDR_SESSION="$SESSION"
SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/fm-6168.XXXXXX")
cleanup() { herdr_safe_stop_and_delete "$SESSION"; rm -rf "$SCRATCH"; }
trap cleanup EXIT
fm_herdr_lab_prepare "$SESSION" || { echo "prepare failed"; exit 1; }
. "$ROOT/bin/fm-backend.sh"
fm_backend_source herdr || exit 1
. "$IMPL"   # override adapter functions with the implementation under test
fm_backend_herdr_server_ensure "$SESSION" || { echo "server_ensure failed"; exit 1; }
CWD="$SCRATCH/firstmate"; mkdir -p "$CWD"
OUT=$(fm_backend_herdr_cli "$SESSION" workspace create --cwd "$CWD" --label firstmate --no-focus)
WS=$(printf '%s' "$OUT" | jq -r '.result.workspace.workspace_id')
SEED=$(printf '%s' "$OUT" | jq -r '.result.tab.tab_id')
echo "created workspace=$WS seeded_tab=$SEED label_at_create=$(printf '%s' "$OUT" | jq -r '.result.tab.label')"
label() { fm_backend_herdr_cli "$SESSION" tab list --workspace "$WS" | jq -r --arg t "$SEED" '.result.tabs[]|select(.tab_id==$t)|.label'; }
for _ in $(seq 1 50); do L=$(label); [ "$L" != 1 ] && break; sleep 0.1; done
echo "seeded tab label after settle: '$(label)'"
if [ "$MODE" = rename ]; then
  fm_backend_herdr_cli "$SESSION" tab rename "$SEED" "my shell" >/dev/null
  echo "renamed seeded tab by hand -> '$(label)'"
fi
fm_backend_herdr_cli "$SESSION" tab create --workspace "$WS" --cwd "$CWD" --label fm-task --no-focus >/dev/null
echo "tabs before prune: $(fm_backend_herdr_cli "$SESSION" tab list --workspace "$WS" | jq -c '[.result.tabs[]|{tab_id,label}]')"
fm_backend_herdr_workspace_prune_seeded_default_tab "$SESSION" "$WS" "$SEED"; echo "prune rc=$?"
echo "tabs after prune:  $(fm_backend_herdr_cli "$SESSION" tab list --workspace "$WS" | jq -c '[.result.tabs[]|{tab_id,label}]')"
echo "RESULT tab_count=$(fm_backend_herdr_cli "$SESSION" tab list --workspace "$WS" | jq '.result.tabs|length')"
