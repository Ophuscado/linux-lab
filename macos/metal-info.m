// metal-info: what Metal says about this GPU, for comparison with Vulkan's limits under Honeykrisp:
// families, limits, memory, the GPU counter sets and their counters, and the timestamp clock.
// Build (macOS): clang -O2 -fobjc-arc -framework Metal -framework Foundation metal-info.m -o metal-info
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

int main(void) {
    @autoreleasepool {
        id<MTLDevice> d = MTLCreateSystemDefaultDevice();
        if (!d) { fprintf(stderr, "no Metal device\n"); return 1; }
        printf("name %s\narchitecture %s\n", d.name.UTF8String,
               [d respondsToSelector:@selector(architecture)] ? d.architecture.name.UTF8String : "?");
        printf("registryID %llu (not stable across boots)\nlowPower %d headless %d removable %d unifiedMemory %d\n",
               d.registryID, d.isLowPower, d.isHeadless, d.isRemovable, d.hasUnifiedMemory);
        struct { MTLGPUFamily f; const char *n; } fam[] = {
            {MTLGPUFamilyApple1, "Apple1"}, {MTLGPUFamilyApple2, "Apple2"}, {MTLGPUFamilyApple3, "Apple3"},
            {MTLGPUFamilyApple4, "Apple4"}, {MTLGPUFamilyApple5, "Apple5"}, {MTLGPUFamilyApple6, "Apple6"},
            {MTLGPUFamilyApple7, "Apple7"}, {MTLGPUFamilyApple8, "Apple8"}, {MTLGPUFamilyApple9, "Apple9"},
            {(MTLGPUFamily)1010, "Apple10"}, {MTLGPUFamilyMac2, "Mac2"}, {MTLGPUFamilyCommon3, "Common3"},
            {MTLGPUFamilyMetal3, "Metal3"}, {(MTLGPUFamily)5002, "Metal4"}};
        printf("families:");
        for (unsigned i = 0; i < sizeof fam / sizeof fam[0]; i++) if ([d supportsFamily:fam[i].f]) printf(" %s", fam[i].n);
        printf("\n");
        MTLSize t = d.maxThreadsPerThreadgroup;
        printf("maxThreadsPerThreadgroup %lux%lux%lu\nmaxThreadgroupMemoryLength %lu\nmaxBufferLength %lu\n",
               t.width, t.height, t.depth, d.maxThreadgroupMemoryLength, d.maxBufferLength);
        printf("recommendedMaxWorkingSetSize %llu\ncurrentAllocatedSize %lu\nmaxTransferRate %llu\n",
               d.recommendedMaxWorkingSetSize, d.currentAllocatedSize, d.maxTransferRate);
        printf("argumentBuffersSupport %lu readWriteTextureSupport %lu raytracing %d 32bitFloatFiltering %d "
               "32bitMSAA %d bcTextures %d dynamicLibraries %d functionPointers %d\n",
               (unsigned long)d.argumentBuffersSupport, (unsigned long)d.readWriteTextureSupport, d.supportsRaytracing,
               d.supports32BitFloatFiltering, d.supports32BitMSAA, d.supportsBCTextureCompression,
               d.supportsDynamicLibraries, d.supportsFunctionPointers);
        printf("sparseTileSizeInBytes %lu\nmaxArgumentBufferSamplerCount %lu\n",
               d.sparseTileSizeInBytes, d.maxArgumentBufferSamplerCount);
        printf("counter sampling: atStageBoundary %d atDrawBoundary %d atDispatchBoundary %d atBlitBoundary %d\n",
               [d supportsCounterSampling:MTLCounterSamplingPointAtStageBoundary],
               [d supportsCounterSampling:MTLCounterSamplingPointAtDrawBoundary],
               [d supportsCounterSampling:MTLCounterSamplingPointAtDispatchBoundary],
               [d supportsCounterSampling:MTLCounterSamplingPointAtBlitBoundary]);
        for (id<MTLCounterSet> cs in d.counterSets) {
            printf("counter set %s:", cs.name.UTF8String);
            for (id<MTLCounter> c in cs.counters) printf(" %s", c.name.UTF8String);
            printf("\n");
        }
        MTLTimestamp cpu0, gpu0, cpu1, gpu1;
        [d sampleTimestamps:&cpu0 gpuTimestamp:&gpu0];
        [NSThread sleepForTimeInterval:0.5];
        [d sampleTimestamps:&cpu1 gpuTimestamp:&gpu1];
        printf("timestamps: cpu %llu -> %llu, gpu %llu -> %llu (gpu ticks per cpu ns %.6f)\n", cpu0, cpu1, gpu0, gpu1,
               (double)(gpu1 - gpu0) / (double)(cpu1 - cpu0));
    }
    return 0;
}
