#!/usr/bin/env bash
# llama-sweep.sh MODEL.gguf: find the mat-vec settings of llama.cpp's Vulkan backend that
# make token generation fastest on this GPU, into ~/llama-sweep-<kernel release>.txt.
#
# Why: generating a token is a few hundred matrix-times-vector products, and llama.cpp
# sizes those per GPU vendor (rows per work group, work-group size, integer or float
# arithmetic). The Asahi driver gets the generic defaults. The patch carried in
# this script only adds environment variables for those settings; nothing changes unless
# one is set. The sweep runs llama-bench once per setting, then checks the fastest one
# against the CPU with llama.cpp's own operator tests and prints where its time goes.
#
#   llama-sweep.sh MODEL.gguf   build, sweep, check, timings
#   llama-sweep.sh test         only the operator tests, with the environment as it is
#                               (for example under: mesa-side.sh run coopmat ...)
#
# Works in its own checkout, src/llama.cpp-sweep in the lab (~/src/llama.cpp-tune before 27 Oct), at the llama.cpp commit the first
# measurements were made with. Needs the packages llama-bench.sh installs.
#
# Environment: LLAMA_TUNE_SRC (checkout), THREADS, BENCH_LABEL (added to the file name).

set -euo pipefail

PIN=f2cc7282ce0042641df55e0e563b75e824e2b647
SRC=${LLAMA_TUNE_SRC:-$(cd "$(dirname "$(readlink -f "$0")")" && pwd)/../src/llama.cpp-sweep}
[[ -n ${LLAMA_TUNE_SRC:-} || -d $SRC || ! -d $HOME/src/llama.cpp-tune ]] || SRC=$HOME/src/llama.cpp-tune
BIN=$SRC/build/bin
OUT=$HOME/llama-sweep-$(uname -r)${BENCH_LABEL:+-$BENCH_LABEL}.txt
# Matrix products of the weight types that matter here, including the mixture-of-experts form.
TESTS=(test -b Vulkan0 -o 'MUL_MAT,MUL_MAT_ID' -p 'type_a=(f32|f16|q4_0|q8_0|mxfp4)' -j 4)

die() { printf '\nERR: %s\n' "$*" >&2; exit 1; }
sec() { printf '\n===== %s\n' "$*"; }

# The patch: environment overrides for the mat-vec settings, and one line on stderr that
# says which are in force.
write_patch() {
    cat <<'PATCH_END'
diff --git a/ggml/src/ggml-vulkan/ggml-vulkan.cpp b/ggml/src/ggml-vulkan/ggml-vulkan.cpp
index 80f4d3a..68673f4 100644
--- a/ggml/src/ggml-vulkan/ggml-vulkan.cpp
+++ b/ggml/src/ggml-vulkan/ggml-vulkan.cpp
@@ -2892,6 +2892,19 @@ void ggml_vk_load_shaders(vk_device& device, vk_pipeline requested) {
         }
         return is_rdna3_or_4 ? 4u : rows;
     };
+    // Tuning overrides, for GPUs that have no settings of their own above.
+    if (const char * env = getenv("GGML_VK_RM_STDQ")) {
+        rm_stdq = std::max(1, atoi(env));
+    }
+    if (const char * env = getenv("GGML_VK_RM_KQ")) {
+        rm_kq = std::max(1, atoi(env));
+    }
+    if (getenv("GGML_VK_RM_STDQ") || getenv("GGML_VK_RM_KQ") || getenv("GGML_VK_DMMV_WG") || getenv("GGML_VK_FORCE_INT_DOT")) {
+        const char * wg = getenv("GGML_VK_DMMV_WG");
+        // Straight to stderr: tools such as llama-bench drop log messages after start-up.
+        fprintf(stderr, "ggml_vulkan: tuning overrides: rm_stdq=%u rm_kq=%u dmmv_wg=%s int_dot=%d\n",
+                rm_stdq, rm_kq, wg ? wg : "default", (int)device->integer_dot_product);
+    }
     uint32_t rm_iq = 2 * rm_kq;
 
     const bool use_subgroups = device->subgroup_arithmetic;
@@ -4275,7 +4288,10 @@ vk_device ggml_vk_get_device(size_t idx) {
             device->coopmat_support = false;
         }
 
-        device->integer_dot_product = device->integer_dot_product && shader_integer_dot_product_props.integerDotProduct4x8BitPackedSignedAccelerated;
+        device->integer_dot_product = device->integer_dot_product &&
+            (shader_integer_dot_product_props.integerDotProduct4x8BitPackedSignedAccelerated ||
+             // Tuning override: try the integer path on a driver that does not call it accelerated.
+             getenv("GGML_VK_FORCE_INT_DOT") != nullptr);
 
         device->min_imported_host_pointer_alignment = external_memory_host_props.minImportedHostPointerAlignment;
 
@@ -5594,6 +5610,11 @@ static vk_pipeline ggml_vk_get_dequantize_mul_mat_vec(ggml_backend_vk_context *
         }
     }
 
+    // Tuning override: GGML_VK_DMMV_WG=large or =subgroup, for every matrix shape.
+    if (const char * env = getenv("GGML_VK_DMMV_WG")) {
+        dmmv_wg = (env[0] == 'l' || env[0] == 'L') ? DMMV_WG_SIZE_LARGE : DMMV_WG_SIZE_SUBGROUP;
+    }
+
     if (b_type == GGML_TYPE_Q8_1) {
         if (ctx->device->vendor_id == VK_VENDOR_ID_INTEL) {
             dmmv_wg = DMMV_WG_SIZE_SUBGROUP;
@@ -5682,6 +5703,11 @@ static vk_pipeline ggml_vk_get_dequantize_mul_mat_vec_id(ggml_backend_vk_context
         }
     }
 
+    // Tuning override: GGML_VK_DMMV_WG=large or =subgroup, for every matrix shape.
+    if (const char * env = getenv("GGML_VK_DMMV_WG")) {
+        dmmv_wg = (env[0] == 'l' || env[0] == 'L') ? DMMV_WG_SIZE_LARGE : DMMV_WG_SIZE_SUBGROUP;
+    }
+
     if (b_type == GGML_TYPE_Q8_1) {
         if (ctx->device->vendor_id == VK_VENDOR_ID_INTEL) {
             dmmv_wg = DMMV_WG_SIZE_SUBGROUP;
PATCH_END
}

prepare() {
    if [[ ! -d $SRC/.git ]]; then
        git init -q "$SRC"
        git -C "$SRC" remote add origin https://github.com/ggml-org/llama.cpp
    fi
    cd "$SRC"
    if [[ $(git rev-parse -q --verify HEAD 2>/dev/null) != "$PIN" ]]; then
        git fetch -q --depth 1 origin "$PIN"
        git checkout -q --detach FETCH_HEAD
    fi
    write_patch >"$SRC/tuning-overrides.patch"
    if git apply --check tuning-overrides.patch 2>/dev/null; then
        git apply tuning-overrides.patch
    elif ! git apply -R --check tuning-overrides.patch 2>/dev/null; then
        die "the tuning patch neither applies nor is applied in $SRC"
    fi
    if [[ ! -x $BIN/llama-bench || ! -x $BIN/test-backend-ops ||
        ggml/src/ggml-vulkan/ggml-vulkan.cpp -nt $BIN/llama-bench ]]; then
        echo "building llama.cpp with the tuning patch (log: $SRC/build.log)"
        if ! { cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DGGML_VULKAN=ON -DLLAMA_BUILD_TESTS=ON \
            -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_SERVER=OFF &&
            cmake --build build --target llama-bench test-backend-ops -j"$(nproc)"; } >build.log 2>&1; then
            grep -B2 -A12 -m1 -E 'CMake Error|error:' build.log || tail -n 25 build.log
            die "build failed; full log in $SRC/build.log"
        fi
    fi
}

# llama.cpp's own comparison of each operator against the CPU result.
optests() { # rest: environment assignments
    local log
    log=$(mktemp)
    # More rows per work group make much larger shaders; a first compile can take minutes.
    env "$@" timeout 1200 "$BIN/test-backend-ops" "${TESTS[@]}" >"$log" 2>&1 ||
        { [[ $? != 124 ]] || echo "stopped after 20 minutes without finishing"; }
    grep -E 'tuning overrides' "$log" | sort -u || true
    grep -E 'tests passed' "$log" || echo "no result line; the last lines were: $(tail -n 3 "$log")"
    echo "not supported by the backend: $(grep -c 'not supported' "$log" || true)"
    grep -E 'FAIL' "$log" | sed 's/\x1b\[[0-9;]*m//g' | head -n 20 || true
    rm -f "$log"
}

if [[ ${1:-} == test ]]; then
    prepare
    {
        sec "operator tests, environment as given"
        vulkaninfo --summary 2>&1 | grep -E 'deviceName|driverInfo' || true
        optests
    } 2>&1 | tee "$OUT"
    echo
    echo "Wrote $OUT. Attach it to the chat."
    exit 0
fi

MODEL=${1:-}
[[ -n $MODEL && -r $MODEL ]] || die "usage: $0 MODEL.gguf | $0 test"
MODEL=$(cd "$(dirname "$MODEL")" && pwd)/$(basename "$MODEL")
prepare

if [[ -z ${THREADS:-} ]]; then
    max=$(cat /sys/devices/system/cpu/cpu*/cpufreq/cpuinfo_max_freq 2>/dev/null | sort -n | tail -n 1) || true
    THREADS=$(grep -lx "${max:-none}" /sys/devices/system/cpu/cpu*/cpufreq/cpuinfo_max_freq 2>/dev/null | wc -l) || true
    [[ $THREADS -gt 0 ]] || THREADS=$(nproc)
fi

# label|environment. The default is one row per work group for the plain quantisations,
# two for the K ones, and the small work group. llama.cpp itself goes up to four rows on
# other GPUs; eight made shaders that took minutes to compile on a software driver.
CONFIGS=("default|")
for wg in subgroup large; do
    for rows in 1 2 4; do
        CONFIGS+=("rows=$rows wg=$wg|GGML_VK_RM_STDQ=$rows GGML_VK_RM_KQ=$rows GGML_VK_DMMV_WG=$wg")
    done
done
CONFIGS+=("integer dot|GGML_VK_FORCE_INT_DOT=1"
    "integer dot, always|GGML_VK_FORCE_INT_DOT=1 GGML_VK_FORCE_MMVQ=1")

best_tg=0
best_env=
best_label=default
{
    sec "system"
    uname -sr
    echo "llama.cpp $(git log -1 --format='%H %cd' --date=short) + tuning-overrides.patch"
    echo "model: $(basename "$MODEL") ($(du -h "$MODEL" | cut -f1))"
    vulkaninfo --summary 2>&1 | grep -E 'deviceName|driverInfo' || echo "no Vulkan device"

    sec "sweep: tokens per second, 512-token prompt and 128 generated, 3 runs each"
    printf '%-22s %-20s %-18s %s\n' setting prompt generation "overrides seen by llama.cpp"
    for cfg in "${CONFIGS[@]}"; do
        label=${cfg%%|*}
        read -r -a assign <<<"${cfg#*|}"
        out=$(env "${assign[@]}" "$BIN/llama-bench" -m "$MODEL" -ngl 99 -t "$THREADS" -p 512 -n 128 -r 3 2>&1) || true
        pp=$(awk -F'|' '/ pp512 / { gsub(/^ +| +$/, "", $(NF-1)); print $(NF-1) }' <<<"$out")
        tg=$(awk -F'|' '/ tg128 / { gsub(/^ +| +$/, "", $(NF-1)); print $(NF-1) }' <<<"$out")
        seen=$(grep -m 1 'tuning overrides' <<<"$out" | sed 's/.*overrides: //') || true
        printf '%-22s %-20s %-18s %s\n' "$label" "${pp:-failed}" "${tg:-failed}" "${seen:--}"
        if [[ -n $tg ]] && awk -v a="${tg%% *}" -v b="$best_tg" 'BEGIN { exit !(a > b) }'; then
            best_tg=${tg%% *}
            best_env=${cfg#*|}
            best_label=$label
        fi
    done
    echo
    echo "fastest generation: $best_label ($best_tg tokens/s)${best_env:+, with: $best_env}"

    sec "operator tests, default settings"
    optests
    if [[ -n $best_env ]]; then
        read -r -a assign <<<"$best_env"
        sec "operator tests, $best_label"
        optests "${assign[@]}"
    fi

    sec "vulkan timings, generating 64 tokens, $best_label"
    read -r -a assign <<<"$best_env"
    log=$(mktemp)
    env "${assign[@]}" GGML_VK_PERF_LOGGER=1 GGML_VK_PERF_LOGGER_FREQUENCY=1000000000 \
        "$BIN/llama-bench" -m "$MODEL" -ngl 99 -t "$THREADS" -r 1 --no-warmup -p 0 -n 64 >"$log" 2>&1 ||
        echo "llama-bench failed"
    awk 'match($0, / = [0-9.e+]+ us/) { print substr($0, RSTART + 3, RLENGTH - 6) "\t" $0 }' "$log" |
        sort -gr | cut -f2- | head -n 25 || true
    grep '^Total time' "$log" || echo "no timings in the output"
    rm -f "$log"
} 2>&1 | tee "$OUT"

echo
echo "Wrote $OUT. Attach it to the chat."
