#!/usr/bin/env python3
"""Apply vk-mmv-cols.patch's change to a llama.cpp tree whatever its age: the matrix-vector path's column limit
(mul_mat_vec_max_cols, 8) becomes 16 pipelines with a runtime cut, GGML_VK_MMV_MAX_COLS (default 8). Finds the
constant wherever the tree defines it (ggml-vulkan-types.h upstream, ggml-vulkan.cpp in older trees); idempotent.
Usage: vk-mmv-cols.py LLAMA_CPP_DIR"""
import pathlib, sys

d = pathlib.Path(sys.argv[1]) / "ggml/src/ggml-vulkan"
old = "static constexpr uint32_t mul_mat_vec_max_cols = 8;"
new = '''// Pipelines exist for up to this many columns (compiled when first used); ggml_vk_mmv_max_cols() is the cut used.
static constexpr uint32_t mul_mat_vec_max_cols = 16;
// Tuning: GGML_VK_MMV_MAX_COLS, the most columns a MUL_MAT takes the matrix-vector path for (default 8, at most 16).
static inline uint32_t ggml_vk_mmv_max_cols() {
    static const uint32_t v = [] {
        const char * e = getenv("GGML_VK_MMV_MAX_COLS");
        const unsigned long n = e ? strtoul(e, nullptr, 10) : 8ul;
        return (uint32_t)(n < 1 ? 1 : n > mul_mat_vec_max_cols ? mul_mat_vec_max_cols : n);
    }();
    return v;
}'''
uses = [("dst->ne[0] == 1 && dst->ne[1] > mul_mat_vec_max_cols &&", "dst->ne[0] == 1 && dst->ne[1] > ggml_vk_mmv_max_cols() &&"),
        ("dst->ne[1] <= mul_mat_vec_max_cols && src1->ne[2] * src1->ne[3] == 1", "dst->ne[1] <= ggml_vk_mmv_max_cols() && src1->ne[2] * src1->ne[3] == 1"),
        ("node->op == GGML_OP_MUL_MAT && n <= mul_mat_vec_max_cols", "node->op == GGML_OP_MUL_MAT && n <= ggml_vk_mmv_max_cols()")]
files = [f for f in d.glob("ggml-vulkan*.*") if f.suffix in (".cpp", ".h")]
if any("ggml_vk_mmv_max_cols" in f.read_text() for f in files):
    print("vk-mmv-cols: already in"); sys.exit(0)
defs = [f for f in files if old in f.read_text()]
if len(defs) != 1:
    sys.exit(f"vk-mmv-cols: the constant is in {len(defs)} files, expected 1")
t = defs[0].read_text()
t = t.replace(old, new)
if "#include <cstdlib>" not in t:
    t = "#include <cstdlib>\n" + t
defs[0].write_text(t)
cpp = d / "ggml-vulkan.cpp"; t = cpp.read_text(); done = 0
for a, b in uses:
    if a in t:
        t = t.replace(a, b); done += 1
# Any other use that still compares a column count against the constant would keep the old cut silently.
rest = [l.strip() for l in t.splitlines() if "mul_mat_vec_max_cols" in l and "<= mul_mat_vec_max_cols)" not in l
        and "i < mul_mat_vec_max_cols" not in l and "[mul_mat_vec_max_cols]" not in l]
cpp.write_text(t)
print(f"vk-mmv-cols: constant in {defs[0].name}, {done} of {len(uses)} cuts moved; other uses: {rest or 'none'}")
