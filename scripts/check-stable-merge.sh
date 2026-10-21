#!/bin/sh
# Re-create the linux-3.4.y stable merge from its inputs and check that it is the pinned
# STABLE_COMMIT: the same parents, and the same tree as git's own merge of them plus the
# resolutions documented in docs/stable-merge.md. Runs on the host (git 2.38 or newer,
# for merge-tree --write-tree), not in the build container. Needs about 100 MB.
set -eu
cd "$(dirname "$0")/.."
# shellcheck disable=SC1091
. scripts/source.env
top=$PWD
work=${1:-$top/out/stable-merge}
resolutions=$top/stable-merge/$STABLE_UPSTREAM_TAG-resolutions.patch
# Files whose conflicts are resolved by keeping the glass-omap-xrx13b side whole.
keep_google="drivers/usb/dwc3/core.c drivers/usb/dwc3/core.h drivers/usb/dwc3/ep0.c
drivers/usb/dwc3/gadget.c drivers/usb/dwc3/gadget.h"
expected_conflicts="drivers/usb/dwc3/core.c drivers/usb/dwc3/ep0.c drivers/usb/dwc3/gadget.c
net/netfilter/xt_socket.c sound/usb/card.c"

# A bare repository: no checkout, so the paths that differ only by case are no problem on macOS.
# Remove an old work directory only if this script made it.
if [ -e "$work" ]; then
    [ -f "$work/check-stable-merge" ] || { echo "error: $work exists and was not made by this script" >&2; exit 1; }
    rm -rf "$work"
fi
git init -q --bare "$work"
touch "$work/check-stable-merge"
# Ignore the user's and the system's git config: merge.conflictStyle, for example, changes the
# conflict markers that the resolutions patch expects.
g() { GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git -c merge.conflictStyle=merge -C "$work" "$@"; }
# Only history from 2014 on is needed: the merge base, v3.4.94, is from June 2014.
# The ref names are part of the conflict markers the resolutions patch expects.
g fetch -q --filter=blob:none --shallow-since=2014-04-01 "$REPO" \
    "refs/heads/$BRANCH:refs/heads/google/$BRANCH"
g fetch -q --no-tags --shallow-since=2014-04-01 "$STABLE_UPSTREAM_REPO" \
    "refs/tags/$STABLE_UPSTREAM_TAG:refs/tags/$STABLE_UPSTREAM_TAG"
# No --depth here: a shallow fetch would cut the merge commit off from its parents.
g fetch -q --filter=blob:none "$STABLE_REPO" "refs/heads/$STABLE_BRANCH:refs/heads/stable"

fail() { echo "error: $*" >&2; exit 1; }
upstream=$(g rev-parse "$STABLE_UPSTREAM_TAG^{commit}")
[ "$upstream" = "$STABLE_UPSTREAM_COMMIT" ] || fail "$STABLE_UPSTREAM_TAG is not at the pinned $STABLE_UPSTREAM_COMMIT"
[ "$(g rev-parse "google/$BRANCH")" = "$COMMIT" ] || fail "$BRANCH is not at the pinned $COMMIT"
[ "$(g rev-parse stable)" = "$STABLE_COMMIT" ] || fail "$STABLE_BRANCH is not at the pinned $STABLE_COMMIT"
[ "$(g merge-base --all "$COMMIT" "$upstream")" = "$STABLE_MERGE_BASE" ] ||
    fail "merge base is not $STABLE_MERGE_BASE"
[ "$(g rev-parse "$STABLE_COMMIT^1")" = "$COMMIT" ] || fail "first parent is not $COMMIT"
[ "$(g rev-parse "$STABLE_COMMIT^2")" = "$upstream" ] || fail "second parent is not $STABLE_UPSTREAM_TAG"
[ -z "$(g rev-parse -q --verify "$STABLE_COMMIT^3" || true)" ] || fail "more than two parents"

# git's own merge; exit status 1 means conflicts, which are expected.
status=0
g merge-tree --write-tree --name-only "google/$BRANCH" "$STABLE_UPSTREAM_TAG" > "$work/merge-tree.out" || status=$?
[ "$status" -eq 1 ] || fail "merge-tree exited with $status, expected 1 (conflicts)"
auto=$(head -n 1 "$work/merge-tree.out")
conflicts=$(sed -n '2,/^$/p' "$work/merge-tree.out" | sed '/^$/d' | sort | tr '\n' ' ')
want=$(echo "$expected_conflicts" | tr ' ' '\n' | sed '/^$/d' | sort | tr '\n' ' ')
[ "$conflicts" = "$want" ] || fail "conflicts are '$conflicts', expected '$want'"

# Apply the documented resolutions to git's result, in a scratch index.
GIT_INDEX_FILE=$work/resolve.index
export GIT_INDEX_FILE
g read-tree "$auto"
g apply --cached "$resolutions"
for f in $keep_google; do
    entry=$(g ls-tree "google/$BRANCH" -- "$f")
    [ -n "$entry" ] || fail "$f is not in $BRANCH"
    mode=${entry%% *}
    oid=$(echo "$entry" | awk '{print $3}')
    g update-index --cacheinfo "$mode,$oid,$f"
done
tree=$(g write-tree)
unset GIT_INDEX_FILE
pinned=$(g rev-parse "$STABLE_COMMIT^{tree}")
if [ "$tree" != "$pinned" ]; then
    g diff --stat "$tree" "$pinned" >&2
    fail "re-created tree $tree differs from $STABLE_COMMIT's tree $pinned"
fi
# Files git merged cleanly have no markers; check the hand-resolved ones.
for f in $expected_conflicts; do
    if g show "$tree:$f" | grep -q -E '^(<<<<<<<|=======|>>>>>>>)( |$)'; then
        fail "conflict markers left in $f"
    fi
done
echo "$STABLE_COMMIT = merge of $COMMIT and $STABLE_UPSTREAM_TAG ($upstream)"
echo "conflicts: $conflicts"
echo "tree $tree: git's merge plus the documented resolutions"
