#!/bin/bash
# status with no pool mounted, as after a boot before 'start': every row's line and the links, exit 0.
# (19 Oct: getfattr on the unmounted pool failed the pipeline in pool_branches and set -e ended status silently.)
set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d /var/tmp/status-nopool.XXXX); mkdir -p "$T/m/state"
echo "domain,port,dev,byid,serial,model,size,fstype,label,used,avail,row,slot,name" >"$T/plan.csv"
out=$(MIG_HOME=$T/m MIG_PLAN=$T/plan.csv MIG_DMESG=/dev/null bash "$REPO/migrate-row.sh" status 2>&1); rc=$?
rows=$(grep -c '^row [ABCD]:' <<<"$out"); links=$(grep -c '^links:' <<<"$out"); nomount=$(grep -c '^    not mounted' <<<"$out")
echo "exit $rc, row lines $rows, links $links, pool not mounted $nomount"
[[ $rc == 0 && $rows == 4 && $links == 1 && $nomount == 1 ]] && echo PASS || { echo FAIL; echo "$out" | tail -n 5; exit 1; }
