// metal-chain: vk-chain's measurements on Metal, so macOS and Asahi can be compared on the same Mac.
// Times COUNT launches in one command buffer: "chain" in a serial encoder (each launch waits on the one
// before, as Vulkan with a barrier), "barrier" in a concurrent encoder with a buffer memory barrier between
// launches (how llama.cpp's Metal backend orders them), "free" in a concurrent encoder without barriers.
// Prints microseconds per launch, best of REPEAT, for the same tests as vk-chain.sh run, groups, dot, clock.
// Build and run (macOS): clang -O2 -fobjc-arc -framework Metal -framework Foundation metal-chain.m -o metal-chain
//                        ./metal-chain
// Written on Linux and not compiled there: the first macOS run is its test.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <time.h>

static NSString *const kSource = @
"#include <metal_stdlib>\n"
"using namespace metal;\n"
"kernel void add(device float *x [[buffer(0)]], constant uint &n [[buffer(1)]], uint i [[thread_position_in_grid]]) {\n"
"    if (i < n) x[i] = x[i] * 1.0001f + 1.0f;\n"
"}\n"
"kernel void addk(device float *x [[buffer(0)]], constant uint &n [[buffer(1)]], uint i [[thread_position_in_grid]],\n"
"                 uint g [[threads_per_grid]]) {\n"
"    for (uint j = i; j < n; j += g) x[j] = x[j] * 1.0001f + 1.0f;\n"
"}\n"
"// The minimal matrix-vector: 2 rows per 128-thread threadgroup, f32, k columns; rows from float k on,\n"
"// the vector at float 0, the outputs after the rows.\n"
"kernel void dot(device float *x [[buffer(0)]], constant uint &n [[buffer(1)]], constant uint &k [[buffer(2)]],\n"
"                uint tg [[threadgroup_position_in_grid]], uint t [[thread_index_in_threadgroup]],\n"
"                uint sg [[simdgroup_index_in_threadgroup]], uint lane [[thread_index_in_simdgroup]]) {\n"
"    threadgroup float sh[2][4];\n"
"    uint m = n / k - 2, r0 = tg * 2;\n"
"    float acc[2] = { 0.0f, 0.0f };\n"
"    for (uint j = 0; j < 2; j++) {\n"
"        uint r = min(r0 + j, m - 1), a = (r + 1) * k;\n"
"        for (uint i = t; i < k; i += 128) acc[j] += x[a + i] * x[i];\n"
"        acc[j] = simd_sum(acc[j]);\n"
"    }\n"
"    if (lane == 0) { sh[0][sg] = acc[0]; sh[1][sg] = acc[1]; }\n"
"    threadgroup_barrier(mem_flags::mem_threadgroup);\n"
"    if (t < 2) x[(m + 1) * k + r0 + t] = sh[t][0] + sh[t][1] + sh[t][2] + sh[t][3];\n"
"}\n"
"// Read bandwidth, as read.comp: a grid-stride walk over float4s; nothing is written unless the sum hits an\n"
"// impossible value (keeps the loads alive).\n"
"kernel void rd(device float4 *v [[buffer(0)]], constant uint &n [[buffer(1)]], uint i [[thread_position_in_grid]],\n"
"               uint g [[threads_per_grid]]) {\n"
"    float4 s = float4(0.0f);\n"
"    for (uint k = i; k < n / 4; k += g) s += v[k];\n"
"    if (s.x == 1.2345e-37f) v[0] = s;\n"
"}\n"
"// One thread's dependent multiply-adds: 1 or 16 per loop step (mode), iters steps.\n"
"kernel void clockk(device float *x [[buffer(0)]], constant uint &mode [[buffer(1)]], constant uint &iters [[buffer(2)]],\n"
"                   uint i [[thread_position_in_grid]]) {\n"
"    if (i != 0) return;\n"
"    float v = x[0];\n"
"    // Coefficients known only at run time and strict math (see main): otherwise the compiler folds the\n"
"    // 16 affine steps into one, as the 27 Oct macOS 15 run showed (16 per step cost the same as 1).\n"
"    float e = 1.0f / float(iters);\n"
"    if (mode == 2) {\n"
"        for (uint it = 0; it < iters; it++) {\n"
"            v = fma(v, 1.0f - 1.0f * e, e); v = fma(v, 1.0f - 2.0f * e, e); v = fma(v, 1.0f - 3.0f * e, e); v = fma(v, 1.0f - 4.0f * e, e);\n"
"            v = fma(v, 1.0f - 5.0f * e, e); v = fma(v, 1.0f - 6.0f * e, e); v = fma(v, 1.0f - 7.0f * e, e); v = fma(v, 1.0f - 8.0f * e, e);\n"
"            v = fma(v, 1.0f - 9.0f * e, e); v = fma(v, 1.0f - 10.0f * e, e); v = fma(v, 1.0f - 11.0f * e, e); v = fma(v, 1.0f - 12.0f * e, e);\n"
"            v = fma(v, 1.0f - 13.0f * e, e); v = fma(v, 1.0f - 14.0f * e, e); v = fma(v, 1.0f - 15.0f * e, e); v = fma(v, 1.0f - 16.0f * e, e);\n"
"        }\n"
"    } else {\n"
"        for (uint it = 0; it < iters; it++) v = fma(v, 1.0f - 1.0f * e, e);\n"
"    }\n"
"    x[0] = v;\n"
"}\n";

enum mode { CHAIN, BARRIER, FREE };
static const char *mode_name[] = { "chain", "barrier", "free" };

static double now_us(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1e6 + t.tv_nsec / 1e3; }

// Best of rep: count launches of pso over grid threadgroups of tpg threads, with up to three uint constants.
static double run(id<MTLCommandQueue> q, id<MTLComputePipelineState> pso, id<MTLBuffer> buf, enum mode m,
                  uint32_t count, MTLSize grid, MTLSize tpg, const uint32_t *c, int nc, int rep) {
    double best = 1e30;
    for (int r = 0; r < rep; r++) {
        id<MTLCommandBuffer> cb = [q commandBuffer];
        id<MTLComputeCommandEncoder> e = [cb computeCommandEncoderWithDispatchType:
                                          m == CHAIN ? MTLDispatchTypeSerial : MTLDispatchTypeConcurrent];
        [e setComputePipelineState:pso];
        [e setBuffer:buf offset:0 atIndex:0];
        for (int i = 0; i < nc; i++) [e setBytes:&c[i] length:4 atIndex:1 + i];
        for (uint32_t i = 0; i < count; i++) {
            [e dispatchThreadgroups:grid threadsPerThreadgroup:tpg];
            if (m == BARRIER && i + 1 < count) [e memoryBarrierWithScope:MTLBarrierScopeBuffers];
        }
        [e endEncoding];
        double t0 = now_us();
        [cb commit];
        [cb waitUntilCompleted];
        double t = now_us() - t0;
        if (cb.status != MTLCommandBufferStatusCompleted) { printf("GPU error: %s\n", cb.error.description.UTF8String); exit(2); }
        if (t < best) best = t;
    }
    return best / count;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        if (!dev) { fprintf(stderr, "no Metal device\n"); return 1; }
        NSError *err = nil;
        id<MTLLibrary> lib = [dev newLibraryWithSource:kSource options:nil error:&err];
        if (!lib) { fprintf(stderr, "shader compile: %s\n", err.description.UTF8String); return 1; }
        // The clock test alone in strict math: fast math may reassociate its chain of multiply-adds. The
        // launch tests keep the default (fast) math, as llama.cpp's Metal kernels and the earlier runs.
        MTLCompileOptions *opt = [MTLCompileOptions new];
        if (@available(macOS 15.0, *)) {
            opt.mathMode = MTLMathModeSafe;
        } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            opt.fastMathEnabled = NO;
#pragma clang diagnostic pop
        }
        id<MTLLibrary> strict = [dev newLibraryWithSource:kSource options:opt error:&err];
        if (!strict) { fprintf(stderr, "shader compile (strict): %s\n", err.description.UTF8String); return 1; }
        id<MTLComputePipelineState> p_add = [dev newComputePipelineStateWithFunction:[lib newFunctionWithName:@"add"] error:&err];
        id<MTLComputePipelineState> p_addk = [dev newComputePipelineStateWithFunction:[lib newFunctionWithName:@"addk"] error:&err];
        id<MTLComputePipelineState> p_dot = [dev newComputePipelineStateWithFunction:[lib newFunctionWithName:@"dot"] error:&err];
        id<MTLComputePipelineState> p_clk = [dev newComputePipelineStateWithFunction:[strict newFunctionWithName:@"clockk"] error:&err];
        id<MTLComputePipelineState> p_rd = [dev newComputePipelineStateWithFunction:[lib newFunctionWithName:@"rd"] error:&err];
        if (!p_add || !p_addk || !p_dot || !p_clk || !p_rd) { fprintf(stderr, "pipeline: %s\n", err.description.UTF8String); return 1; }
        id<MTLCommandQueue> q = [dev newCommandQueue];
        id<MTLBuffer> buf = [dev newBufferWithLength:(4096u + 2) * 16384u * 4 options:MTLResourceStorageModePrivate];
        printf("device %s\n", dev.name.UTF8String);

        printf("== run: plain add, one float per thread, 256-thread threadgroups, 1500 launches\n");
        for (uint32_t n = 4096; n <= 16777216; n *= 16) {
            for (int m = 0; m < 3; m++) {
                uint32_t c[1] = { n };
                double us = run(q, p_add, buf, m, 1500, MTLSizeMake((n + 255) / 256, 1, 1), MTLSizeMake(256, 1, 1), c, 1, 10);
                printf("%8u KB %-7s %8.2f us per launch\n", n * 4 / 1024, mode_name[m], us);
            }
        }

        printf("== groups: the same add of 1 MB and 16 MB over 8 to 4096 threadgroups\n");
        uint32_t groups[] = { 8, 32, 76, 152, 304, 608, 1024, 4096 };
        for (uint32_t n = 262144; n <= 4194304; n *= 16)
            for (int g = 0; g < 8; g++) {
                uint32_t c[1] = { n };
                double us = run(q, p_addk, buf, CHAIN, 1500, MTLSizeMake(groups[g], 1, 1), MTLSizeMake(256, 1, 1), c, 1, 10);
                printf("%6u KB, %4u threadgroups: chain %8.2f us\n", n * 4 / 1024, groups[g], us);
            }

        printf("== dot: minimal f32 matrix-vector, 2 rows per 128-thread threadgroup\n");
        uint32_t shapes[][2] = { { 512, 2048 }, { 2048, 512 }, { 4096, 4096 } };
        for (int s = 0; s < 3; s++)
            for (int m = 0; m < 3; m++) {
                uint32_t c[2] = { (shapes[s][0] + 2) * shapes[s][1], shapes[s][1] };
                double us = run(q, p_dot, buf, m, 1500, MTLSizeMake(shapes[s][0] / 2, 1, 1), MTLSizeMake(128, 1, 1), c, 2, 10);
                printf("%ux%u f32 %-7s %8.2f us per launch\n", shapes[s][0], shapes[s][1], mode_name[m], us);
            }

        printf("== bw: read bandwidth, as vk-chain.sh bw: one float4 per thread, and 1216 threadgroups walking the buffer\n");
        id<MTLBuffer> big = [dev newBufferWithLength:1024u << 20 options:MTLResourceStorageModePrivate];
        uint32_t sizes_mb[] = { 1, 16, 64, 256, 1024 };
        for (int s = 0; s < 5; s++) {
            uint32_t mb = sizes_mb[s], n = mb * 262144u, c[1] = { n }, count = mb >= 256 ? 20 : 200;
            double a = run(q, p_rd, big, FREE, count, MTLSizeMake(n / 4 / 256, 1, 1), MTLSizeMake(256, 1, 1), c, 1, 5);
            double b = run(q, p_rd, big, FREE, count, MTLSizeMake(1216, 1, 1), MTLSizeMake(256, 1, 1), c, 1, 5);
            printf("%5u MB: one float4 each %8.1f GB/s (%.1f us)   1216 groups %8.1f GB/s (%.1f us)\n",
                   mb, n * 4 / (a * 1000), a, n * 4 / (b * 1000), b);
        }

        printf("== clock: one thread's dependent multiply-adds (16 per step against 1, 100k steps)\n");
        uint32_t c1[2] = { 1, 100000 }, c2[2] = { 2, 100000 };
        double a = run(q, p_clk, buf, CHAIN, 5, MTLSizeMake(1, 1, 1), MTLSizeMake(32, 1, 1), c1, 2, 5);
        double b = run(q, p_clk, buf, CHAIN, 5, MTLSizeMake(1, 1, 1), MTLSizeMake(32, 1, 1), c2, 2, 5);
        double ns = (b - a) * 1000 / (100000.0 * 15);
        printf("one dependent multiply-add %.2f ns (%.1f cycles at 1398 MHz); one loop step %.2f ns\n", ns, ns * 1.398, a / 100 - ns);
    }
    return 0;
}
