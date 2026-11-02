#!/usr/bin/env bash
# llama-compare.sh [NAME...]: on Linux, the same llama.cpp tests macos/collect.sh's llama step ran with Metal, so the two
# sit side by side: llama-bench pp512/pp2048/tg128, the 1-512 token batch curve, generation after 0-16k tokens of
# context (depth), speculative decoding on the code edit of macos/spec-req.py (none, ngram-mod 64 and 128, the MTP
# head where the model has one), test-backend-ops perf of FLASH_ATTN_EXT and SET_ROWS (once), and with STEPS=perf, a few tokens
# at 4k context through the per-op logger (llama-NAME-perf-d4096.txt); STEPS=sync, one token through ggml-vulkan's
# sync logger; STEPS=mmv (no model), the matrix-vector over its settings; STEPS=pp, prompt processing per op. Models and names from
# macos/models.txt (default: all present); the settings of gpu/llama-run.sh. Output: var/compare-<time>/, JSON as on
# macOS. Takes the GPU lock.
# provenance.json records pre-run artifacts and configuration using Python 3's standard library.
# rows.tsv records the model row overrides with Bash shell quoting.
# cmake.txt: the build's configuration (its CMakeCache.txt: build type, compilers, flags, GGML_*/LLAMA_* options).
# thermal.txt: fans, power and temperatures from the SMC, the NVMe's temperature and each CPU cluster's clock, at the
# start, before each model and at the end (no GPU clock: the Asahi driver exposes none).
# models.tsv: each model run, its bytes and the sha256 macos/models.sha256 gives it (not hashed again here;
# sha256sum -c macos/models.sha256 checks the files). gpu/bench-spread.py compares the bench step across runs.
#
# Environment: STEPS (default "bench batches depth spec ops"), THREADS (default 16), COMPARE_OUT (instead of var/), GPU_LOCK (the lock
# file, default ~/.cache/linux-lab-gpu.lock), MESA_SIDE (the side Mesas, default build/mesa-side), LLAMA_BIN (the binaries needed by STEPS; default src/llama.cpp-simd/build/bin, the
# honeykrisp series), LLM (models, default ~/Projects/_llm).
set -euo pipefail
case ${1:-} in -h|--help)
    sed -n '2,/^set -eu/p' "$0" | sed '$d; s/^# \?//'
    exit 0 ;;
esac
LAB=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
B=${LLAMA_BIN:-$LAB/src/llama.cpp-simd/build/bin}
LLM=${LLM:-$HOME/Projects/_llm}
OUT=${COMPARE_OUT:-$LAB/var}/compare-$(date +%Y%m%d-%H%M%S)
die() { printf '\nERR: %s\n' "$*" >&2; exit 1; }
requested_steps=${STEPS:-bench batches depth spec ops}
selected_steps=()
IFS=$' \t' read -r -a selected_steps <<< "${requested_steps//$'\n'/ }" || true
[[ ${#selected_steps[@]} -gt 0 ]] || die "no benchmark steps selected"
for step in "${selected_steps[@]}"; do
    case $step in
        mmv|mmid|pp|ops|bench|batches|depth|perf|sync|spec) ;;
        *) die "unknown benchmark step: $step" ;;
    esac
done
STEPS=" ${selected_steps[*]} "
on() { [[ $STEPS == *" $1 "* ]]; }
require_binary() {
    local binary=$1 step
    shift
    for step; do
        if on "$step"; then
            [[ -x $B/$binary ]] || die "no $binary in $B (step: $step)"
            return
        fi
    done
}
require_binary test-backend-ops mmv mmid ops pp
require_binary llama-bench bench batches depth perf sync pp
require_binary llama-server spec
mkdir -p "$(dirname "$OUT")"
OUT=$(mktemp -d "$OUT-XXXXXX")

for d in agxperf coopmat; do
    icd=$(compgen -G "${MESA_SIDE:-$LAB/build/mesa-side}/$d/share/vulkan/icd.d/asahi_icd.*.json" | head -n 1 || true)
    [[ -n $icd ]] && { export VK_DRIVER_FILES=$icd; echo "driver: $d" | tee "$OUT/driver.txt"; break; }
done
export AGX_CLUSTER_OFF=1 AGX_HOIST_LOADS=${AGX_HOIST_LOADS:-1} HK_PERFTEST=designedusccdmbarrier GGML_VK_DMMV_WG=large GGML_VK_MMV_SIMD=1
# The server's settings (llama-run.sh), so these numbers are its; each can be overridden from the environment.
export GGML_VK_WT_M=${GGML_VK_WT_M:-512,128,128,,32,32,,16,16,16} GGML_VK_MMV_ID_MAX=64 GGML_VK_MMV_ID_PER_EXPERT=2 GGML_VK_MMV_MAX_COLS=16 GGML_VK_SHADER_CORES=${GGML_VK_SHADER_CORES:-152}
export GGML_VK_MMID_SIZES=${GGML_VK_MMID_SIZES:-sm} GGML_VK_WT_S=${GGML_VK_WT_S:-256,128,32,,32,16} GGML_VK_MMID_S_MAX=${GGML_VK_MMID_S_MAX:-64}
# CPU threads: the 16 performance cores, as Metal's llama-bench uses by default on macOS (n_threads 16 in
# results/macos) and as llama-run.sh runs (-t 16); llama-bench's own default here is all 24, efficiency cores too.
export THREADS=${THREADS:-16}
# Rows per workgroup as llama-run.sh sets them; ROWS=N for every model instead.
rows() { [[ -n ${ROWS:-} ]] && { echo "$ROWS"; return; }; case $1 in qwen) echo 4 ;; gemma) echo 2 ;; *) echo 1 ;; esac; }

# A step that fails is noted and the run goes on to the next step and model (set -e would end the whole run at the
# first failing llama-bench, losing every model after it). Called as `on STEP && cmd || failed "NAME STEP"`: a step
# that is off ends the && early, and that is not a failure.
failed() { local rc=$?; on "${1##* }" || return 0; echo "$1: failed (rc $rc), see errors.txt" | tee -a "$OUT/failed.txt"; }
# The lock is opened for reading when it cannot be written (a confined run sees ~/.cache read-only), as flock needs
# only an open file; so every run shares the one lock.
lock_started=$SECONDS
lock=${GPU_LOCK:-$HOME/.cache/linux-lab-gpu.lock}
{ exec 9>>"$lock"; } 2>/dev/null || exec 9<"$lock"; flock 9
STEPS="$STEPS" python3 -I "$LAB/gpu/benchmark-provenance.py" "$LAB" "$B" "$OUT/provenance.json" "$((SECONDS - lock_started))"
if [[ -r $B/../CMakeCache.txt ]]; then
    grep -E '^(CMAKE_BUILD_TYPE|CMAKE_C_COMPILER|CMAKE_CXX_COMPILER|CMAKE_C_FLAGS|CMAKE_CXX_FLAGS|GGML_[A-Z0-9_]+|LLAMA_[A-Z0-9_]+):' \
        "$B/../CMakeCache.txt" >"$OUT/cmake.txt" || true
else
    echo "no CMakeCache.txt beside $B" >"$OUT/cmake.txt"
fi
# thermal LABEL: one line of the sensors as sysfs gives them (temperatures m°C, power uW, fans RPM, mV, mA, kHz).
thermal() {
    local h f line
    line="$1 $(date -u +%FT%TZ)"
    for h in /sys/class/hwmon/hwmon*; do
        case $(cat "$h/name" 2>/dev/null) in macsmc_hwmon | nvme) ;; *) continue ;; esac
        for f in "$h"/*_label; do
            [[ -r ${f%_label}_input ]] && line+=" $(tr ' ' _ <"$f")=$(cat "${f%_label}_input" 2>/dev/null)"
        done
    done
    for f in /sys/devices/system/cpu/cpufreq/policy*/scaling_cur_freq; do
        [[ -r $f ]] && line+=" $(basename "$(dirname "$f")")=$(cat "$f")"
    done
    echo "$line" >>"$OUT/thermal.txt"
}
thermal start
failed=0
s=
failure() { printf 'ERR: %s\n' "$*" | tee -a "$OUT/failed.txt" >&2; failed=1; }
run_json() {
    local target=$1 status
    shift
    if "$@" >"$target.tmp" 2>>"$OUT/errors.txt"; then
        # Exit status alone cannot distinguish an empty/truncated result from JSON.
        if ! python3 -I -c '
import json, sys
def invalid_constant(value):
    raise ValueError("non-JSON numeric constant")
with open(sys.argv[1], encoding="utf-8") as source:
    data = json.load(source, parse_constant=invalid_constant)
if not isinstance(data, list) or not data or not all(isinstance(row, dict) for row in data):
    raise ValueError("expected a nonempty array of benchmark result objects")
' "$target.tmp" 2>>"$OUT/errors.txt"; then
            failure "invalid benchmark JSON (see $target.tmp and $OUT/errors.txt)"
            return 1
        fi
        mv -- "$target.tmp" "$target" || { failure "cannot publish $target"; return 1; }
    else
        status=$?
        failure "benchmark failed (see $target.tmp and $OUT/errors.txt)"
        return "$status"
    fi
}
stop_server() {
    if [[ -n $s ]]; then
        kill "$s" 2>/dev/null || true
        wait "$s" 2>/dev/null || true
        s=
    fi
}
trap stop_server EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# STEPS=mmv: the one-token 4096x14336 matrix-vector (f16, q4_0, q8_0) over rows per workgroup, workgroup size and
# the Metal-layout shader, against the read bandwidth (610-655 GB/s) and Metal (f16 131 us, q4_0 37, q8_0 57.5).
if on mmv; then
    # LARGE: subgroups in a large group (patch 0009).
    # MMV_SWEEP="SIMD,WG,RM,LARGE,RMF16 ..." (RMF16: rows of an f16 group, patch 0010).
    point=0
    for pt in ${MMV_SWEEP:-1,large,4,4,1 1,large,4,4,2 1,large,4,4,4 1,large,4,4,8 1,large,4,4,16 1,large,4,8,8}; do
        point=$((point + 1))
        IFS=, read -r simd wg rm large rmf16 <<<"$pt"
        if ! GGML_VK_MMV_SIMD=$simd GGML_VK_DMMV_WG=$wg GGML_VK_RM_STDQ=$rm GGML_VK_RM_KQ=$rm GGML_VK_DMMV_LARGE=$large GGML_VK_RM_F16=${rmf16:-2} "$B/test-backend-ops" perf -b Vulkan0 -o MUL_MAT \
            -p 'type_a=(f16|q4_0|q8_0),type_b=f32,m=4096,n=1,k=14336,bs=\[1,1\],nr=\[1,1\],per=\[0,1,2,3\],k_v=0,o=1' 2>&1 |
            tee "$OUT/mmv-$point.log" |
            sed -nE "s/^ *MUL_MAT\(type_a=([a-z0-9_]+),.* ([0-9.]+) us\/run.*/simd $simd $wg rm $rm large $large rmf16 ${rmf16:-2} \1 \2 us/p" |
            tee "$OUT/mmv-$point.txt"; then
            failure "$pt: matrix-vector performance failed (see $OUT/mmv-$point.log)"
            exit 1
        fi
        [[ -s $OUT/mmv-$point.txt ]] || { failure "$pt: no matching timings (see $OUT/mmv-$point.log)"; exit 1; }
    done | tee "$OUT/mmv.txt"
fi
# STEPS=pp: prompt processing. The n=512 matmuls and MUL_MAT_ID, the cases results/macos's llama-ops-mul_mat*.txt
# timed on Metal, and per model one 512-token prompt through the per-op logger (llama-NAME-perf-pp512.txt).
# STEPS=mmid: MUL_MAT_ID (the experts' matmuls, 3.5-7.4x Metal's time at 32-512 tokens) over the tile sizes built
# for it (GGML_VK_MMID_SIZES, letters of "sml"; patch 0001).
if on mmid; then
    # MMID_SWEEP="SIZES[:WT_S] ...": a small tile reshaped through GGML_VK_WT_S serves MUL_MAT_ID alone when the
    # dense matmuls keep the medium one; each such point first runs the MUL_MAT_ID tests.
    point=0
    for pt in ${MMID_SWEEP:-m s sm l ml sml}; do
        point=$((point + 1))
        sz=${pt%%:*} wts=; [[ $pt == *:* ]] && wts=${pt#*:}
        if [[ -n $wts ]]; then
            if ! GGML_VK_MMID_SIZES=$sz GGML_VK_WT_S=$wts "$B/test-backend-ops" test -b Vulkan0 -o MUL_MAT_ID >"$OUT/mmid-tests.txt" 2>&1; then
                die "$pt: MUL_MAT_ID correctness failed (see $OUT/mmid-tests.txt)"
            fi
            echo "$pt tests $(grep -E 'tests passed' "$OUT/mmid-tests.txt" | tr -s ' ')"
        fi
        if ! env GGML_VK_MMID_SIZES="$sz" ${wts:+GGML_VK_WT_S=$wts} "$B/test-backend-ops" perf -b Vulkan0 -o MUL_MAT_ID -p 'type_a=(q8_0|q4_K|f16|mxfp4),' 2>&1 |
            tee "$OUT/mmid-$point.log" |
            sed -nE "s/^ *MUL_MAT_ID\((type_a=[^,]+),type_b=f32,n_mats=([0-9]+),n_used=([0-9]+),.*m=([0-9]+),n=([0-9]+),k=([0-9]+),.* ([0-9.]+) us\/run.*/$pt \1 e\2 u\3 m\4 n\5 k\6 \7/p" |
            tee "$OUT/mmid-$point.txt"; then
            failure "$pt: expert performance failed (see $OUT/mmid-$point.log)"
            exit 1
        fi
        [[ -s $OUT/mmid-$point.txt ]] || { failure "$pt: no matching timings (see $OUT/mmid-$point.log)"; exit 1; }
    done | tee "$OUT/mmid.txt"
fi
if on pp; then
    "$B/test-backend-ops" perf -b Vulkan0 -o MUL_MAT -p 'n=512,' >"$OUT/ops-MUL_MAT-n512.txt" 2>&1 ||
        failure "pp: MUL_MAT failed (see $OUT/ops-MUL_MAT-n512.txt)"
    "$B/test-backend-ops" perf -b Vulkan0 -o MUL_MAT_ID >"$OUT/ops-MUL_MAT_ID.txt" 2>&1 ||
        failure "pp: MUL_MAT_ID failed (see $OUT/ops-MUL_MAT_ID.txt)"
fi
if on ops; then
    for o in FLASH_ATTN_EXT SET_ROWS; do
        "$B/test-backend-ops" perf -b Vulkan0 -o $o >"$OUT/ops-$o.txt" 2>&1 ||
            failure "ops: $o failed (see $OUT/ops-$o.txt)"
    done
fi
want=" $* "
while IFS='|' read -r name file mtp; do
    [[ -z $name || $name == \#* ]] && continue
    [[ $# == 0 || $want == *" $name "* ]] || continue
    f=$LLM/$file; [[ -f $f ]] || { echo "$name: no $f, skipped"; continue; }
    mf=; [[ -n $mtp && -f $LLM/$mtp ]] && mf=$LLM/$mtp
    r=$(rows "$name"); export GGML_VK_RM_STDQ=$r GGML_VK_RM_KQ=$r
    printf '%q\t%q\n' "$name" "$r" >>"$OUT/rows.tsv"
    sha=$(awk -v p="$file" '$2 == p { print $1 }' "$LAB/macos/models.sha256" 2>/dev/null) || sha=
    printf '%s\t%s\t%s\t%s\n' "$name" "$file" "$(stat -c %s "$f")" "${sha:-not in macos/models.sha256}" >>"$OUT/models.tsv"
    thermal "$name"
    echo "== $name (rows $GGML_VK_RM_STDQ)"
    on bench && run_json "$OUT/llama-$name-bench.json" "$B/llama-bench" -m "$f" -t "$THREADS" -ngl 99 -fa 1 -ub 2048 -p 512,2048 -n 128 -r 3 -o json || failed "$name bench"
    on batches && run_json "$OUT/llama-$name-batches.json" "$B/llama-bench" -m "$f" -t "$THREADS" -ngl 99 -fa 1 -ub 8192 -b 8192 -p 1,2,4,8,9,12,16,24,32,48,64,128,512 -n 0 -r 2 -o json || failed "$name batches"
    on depth && run_json "$OUT/llama-$name-depth.json" "$B/llama-bench" -m "$f" -t "$THREADS" -ngl 99 -fa 1 -ub 2048 -p 0 -n 32 -d 0,1024,4096,16384 -r 2 -o json || failed "$name depth"
    if on perf; then
        GGML_VK_PERF_LOGGER=1 GGML_VK_PERF_LOGGER_FREQUENCY=1 "$B/llama-bench" -m "$f" -t "$THREADS" -ngl 99 -fa 1 -ub 2048 -p 0 -n 4 \
            -d 4096 -r 1 >"$OUT/llama-$name-perf-d4096.txt" 2>&1 ||
            failure "$name: generation profile failed (see $OUT/llama-$name-perf-d4096.txt)"
    fi
    # Where ggml-vulkan makes the GPU wait: one generated token with its sync logger (a "sync" line before each
    # barrier, then the node or fused nodes it records), and the count of each.
    if on sync; then
        if GGML_VK_SYNC_LOGGER=1 "$B/llama-bench" -m "$f" -t "$THREADS" -ngl 99 -fa 1 -ub 2048 -p 0 -n 1 -r 1 >"$OUT/llama-$name-sync.txt" 2>&1; then
            echo "$name: $(grep -c '^sync$' "$OUT/llama-$name-sync.txt") syncs, $(grep -cE '^[0-9]+ ' "$OUT/llama-$name-sync.txt") nodes (warm-up and the token)" | tee -a "$OUT/sync.txt"
        else
            failure "$name: sync profile failed (see $OUT/llama-$name-sync.txt)"
        fi
    fi
    if on pp; then
        GGML_VK_PERF_LOGGER=1 GGML_VK_PERF_LOGGER_FREQUENCY=1 "$B/llama-bench" -m "$f" -t "$THREADS" -ngl 99 -fa 1 -ub 2048 -p 512 -n 0 \
            -r 1 >"$OUT/llama-$name-perf-pp512.txt" 2>&1 ||
            failure "$name: prompt profile failed (see $OUT/llama-$name-perf-pp512.txt)"
    fi
    on spec || continue
    for c in "none|" "ngram-mod-64|--spec-type ngram-mod" \
        "ngram-mod-128|--spec-type ngram-mod --spec-ngram-mod-n-max 128 --spec-ngram-mod-n-min 96" \
        ${mf:+"mtp|--spec-type draft-mtp -md $mf -ngld 99"}; do
        if ! python3 -I -c 'import socket; s=socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.1", 8099))' >"$OUT/port-check.txt" 2>&1; then
            failure "$name: port 8099 unavailable (see $OUT/port-check.txt)"
            break
        fi
        server_log="$OUT/server-$name-${c%%|*}.log"
        # shellcheck disable=SC2086
        "$B/llama-server" -m "$f" -t "$THREADS" ${c#*|} -ngl all -fa on -np 1 -c 16384 -ub 8192 -b 8192 -ctk q8_0 -ctv q8_0 \
            --host 127.0.0.1 --port 8099 >"$server_log" 2>&1 &
        s=$!
        ready=0
        for ((i = 0; i < 600; i++)); do
            kill -0 "$s" 2>/dev/null || break
            if curl -sf --max-time 2 http://127.0.0.1:8099/health >/dev/null && kill -0 "$s" 2>/dev/null; then
                ready=1
                break
            fi
            sleep 1
        done
        if (( ! ready )); then
            failure "$name ${c%%|*}: server did not become ready (see $server_log)"
            stop_server
            break
        fi
        spec_log="$OUT/llama-$name-spec-${c%%|*}.txt"
        if ! python3 -I "$LAB/macos/spec-req.py" 8099 "$LAB/gpu/llama-run.sh" >"$spec_log" 2>&1; then
            failure "$name ${c%%|*}: request failed (see $spec_log)"
            stop_server
            break
        fi
        echo "$name ${c%%|*}: $(tail -n 1 "$spec_log")" | tee -a "$OUT/llama-spec.txt"
        stop_server
    done
done <"$LAB/macos/models.txt"
thermal end
echo "saved: $OUT"
(( failed == 0 )) || die "one or more steps failed (see $OUT/failed.txt)"
