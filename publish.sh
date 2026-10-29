#!/usr/bin/env bash
# publish.sh: turn a patch series of src-patches/ into a branch of its fork, and push it.
#
#   ./publish.sh PROJECT/SERIES            build the branch in the local clone and show it (pushes nothing)
#   ./publish.sh PROJECT/SERIES --push     the same, then push the branch to the fork
#   ./publish.sh PROJECT/SERIES --push --tag NAME
#                                          and an annotated tag NAME on its tip, pushed too
#   ./publish.sh list                      every series, its base, branch and last publication
#
# A series is src-patches/PROJECT/SERIES/: NNNN-*.patch (git format-patch files, applied with git am in
# file-name order) and BASE, a shell file with UPSTREAM (where BASE comes from), BASE (the commit the
# series applies to), FORK (the repository it is published to), BRANCH and CLONE (the local working
# clone, relative to this folder, e.g. src/linux).
#
# The fork's branch is generated: it is BASE plus the series, nothing else. Commits are made with the
# committer date set to the author date and the author as committer, so the same series on the same base
# gives the same commit ids and a republish without changes pushes nothing. A changed series rewrites
# the branch; the push then replaces the branch only when its tip is what this script pushed last
# (recorded in SERIES/PUBLISHED), so commits added on the fork by other means are never overwritten:
# the script stops and shows them instead.
# After a push SERIES/PUBLISHED records the tip, and this repository gets a commit with that file.
set -euo pipefail
die() { echo "ERR: $*" >&2; exit 1; }
LAB=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
SP=$LAB/src-patches

if [[ ${1:-} == list ]]; then
    for b in "$SP"/*/*/BASE; do
        d=${b%/BASE}; s=${d#"$SP"/}
        (   # shellcheck disable=SC1090
            . "$b"
            n=$(compgen -G "$d/[0-9][0-9][0-9][0-9]-*.patch" | wc -l || true)
            p=$(cat "$d/PUBLISHED" 2>/dev/null || echo "not published")
            printf '%-24s %2s patches on %s -> %s %s; %s\n' "$s" "$n" "${BASE:0:12}" "${FORK:-(no fork)}" "$BRANCH" "$p"
        )
    done
    exit 0
fi

series=${1:?usage: $0 PROJECT/SERIES [--push [--tag NAME]] | list}; shift
push="" tag=""
while [[ $# -gt 0 ]]; do
    case $1 in
    --push) push=1 ;;
    --tag) tag=${2:?--tag needs a name}; shift ;;
    *) die "unknown option $1" ;;
    esac
    shift
done
[[ -z $tag || -n $push ]] || die "--tag goes with --push"
D=$SP/$series
[[ -f $D/BASE ]] || die "no series $series (no $D/BASE)"
UPSTREAM="" BASE="" FORK="" BRANCH="" CLONE=""
# shellcheck disable=SC1091
. "$D/BASE"
[[ -n $UPSTREAM && $BASE =~ ^[0-9a-f]{40}$ && -n $BRANCH && -n $CLONE ]] || die "$D/BASE needs UPSTREAM, BASE (a full commit id), BRANCH and CLONE"
mapfile -t patches < <(ls "$D"/[0-9][0-9][0-9][0-9]-*.patch 2>/dev/null)
((${#patches[@]})) || die "no NNNN-*.patch files in $D"
C=$LAB/$CLONE
[[ -d $C/.git || -f $C/.git ]] || die "no git clone at $C (clone $UPSTREAM there first)"
g() { git -C "$C" -c advice.detachedHead=false "$@"; }

# Remotes: upstream for the base, fork for the push. Existing remotes with these names are kept.
g remote get-url upstream >/dev/null 2>&1 || g remote add upstream "$UPSTREAM"
if [[ -n $FORK ]]; then g remote get-url fork >/dev/null 2>&1 || g remote add fork "$FORK"; fi
g cat-file -e "$BASE^{commit}" 2>/dev/null || g fetch upstream "$BASE" || die "cannot fetch $BASE from $UPSTREAM"

# The working clone must be clean: the branch is rebuilt in it.
[[ -z $(g status --porcelain --untracked-files=no) ]] || die "$C has uncommitted changes; commit or stash them first"
was=$(g symbolic-ref -q --short HEAD || g rev-parse HEAD)
work=publish/${BRANCH//\//-}
g checkout -q -B "$work" "$BASE"
if ! g -c user.name=publish -c user.email=publish@localhost am -q --committer-date-is-author-date "${patches[@]}"; then
    g am --abort || true; g checkout -q "$was"
    die "the series does not apply on ${BASE:0:12}; nothing changed"
fi
# Committer = author, so the ids do not depend on who runs this.
g -c core.hooksPath=/dev/null filter-branch -f --env-filter \
    'export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL" GIT_COMMITTER_DATE="$GIT_AUTHOR_DATE"' \
    "$BASE..$work" >/dev/null 2>&1 || die "could not set the committers"
g update-ref -d "refs/original/refs/heads/$work" 2>/dev/null || true
tip=$(g rev-parse "$work")
g checkout -q "$was"
g branch -f "$BRANCH" "$tip"
echo "$series: $BRANCH = ${BASE:0:12} + ${#patches[@]} patches, tip ${tip:0:12}"
g log --format='  %h %an  %s' "$BASE..$tip"

[[ -n $push ]] || { echo "built locally only; --push to publish to ${FORK:-(no fork)}"; exit 0; }
[[ -n $FORK ]] || die "$series has no FORK to push to"
remote=$(g ls-remote fork "refs/heads/$BRANCH" | cut -f1)
last=$(awk '{print $1}' "$D/PUBLISHED" 2>/dev/null || true)
if [[ $remote == "$tip" ]]; then
    echo "the fork's $BRANCH is already ${tip:0:12}"
    [[ -n $tag || $last != "$tip" ]] || exit 0
elif [[ -z $remote ]]; then
    g push fork "$tip:refs/heads/$BRANCH"
elif g fetch -q fork "refs/heads/$BRANCH" && [[ -z $last ]] && g diff --quiet "$remote" "$tip" &&
    [[ $(g rev-list --count "$BASE..$remote") == "${#patches[@]}" ]]; then
    # Published before this script (the same content and as many commits on BASE): adopt it, push nothing.
    echo "the fork's $BRANCH (${remote:0:12}) already has this series (same tree, ${#patches[@]} commits on ${BASE:0:12}); recorded, not pushed"
    tip=$remote
elif [[ -n $last && $remote == "$last" ]]; then
    g push --force-with-lease="refs/heads/$BRANCH:$remote" fork "$tip:refs/heads/$BRANCH"
else
    g fetch -q fork "refs/heads/$BRANCH" || true
    echo "ERR: the fork's $BRANCH (${remote:0:12}) is not what this script pushed last (${last:-nothing recorded}):" >&2
    g log --format='  %h %an %cs  %s' "$tip..$remote" 2>/dev/null | head -n 20 >&2 || true
    die "bring those commits into $D as patches (git format-patch), or record ${remote:0:12} in $D/PUBLISHED if they are the series already"
fi
if [[ -n $tag ]]; then
    g tag -a -f "$tag" -m "$series: ${#patches[@]} patches on ${BASE:0:12}" "$tip"
    g push fork "refs/tags/$tag"
fi
echo "$tip $(date -u +%FT%TZ) $BRANCH${tag:+ tag $tag}" >"$D/PUBLISHED"
git -C "$LAB" add "$D/PUBLISHED"
git -C "$LAB" commit -q -m "publish: $series at ${tip:0:12}${tag:+ ($tag)}" -- "$D/PUBLISHED" && echo "recorded in $(git -C "$LAB" log -1 --format=%h)"
