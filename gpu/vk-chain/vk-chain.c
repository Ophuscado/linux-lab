// vk-chain: the GPU cost of one compute launch, alone and in a dependent chain.
// An LLM's token is ~1500 small launches, each depending on the one before, so the time
// of one dependent launch sets the token rate. Records COUNT launches of a tiny shader in
// one command buffer, with a compute-to-compute memory barrier between them (chain) or
// none (free), submits, waits, and prints microseconds per launch (best of REPEAT).
// Usage: vk-chain [COUNT=1500] [ELEMENTS=4096] [REPEAT=20] [SHADER=add] [MODE ITERS]; SHADER.spv next to
// the binary; MODE and ITERS are the specialization constants of reduce.spv (0 barriers, 1 subgroup).
// VKCHAIN_ALT=1 alternates two pipelines of the same shader launch by launch, VKCHAIN_REBIND=1 binds
// the descriptor set and pushes the constants again before every launch: what ggml does per op.
#include <vulkan/vulkan.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <libgen.h>

#define CK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { fprintf(stderr, "%s: %d\n", #x, r_); exit(1); } } while (0)

static double now_us(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1e6 + t.tv_nsec / 1e3; }

int main(int argc, char **argv) {
    uint32_t count = argc > 1 ? atoi(argv[1]) : 1500, n = argc > 2 ? atoi(argv[2]) : 4096, rep = argc > 3 ? atoi(argv[3]) : 20;
    const char *shader = argc > 4 ? argv[4] : "add"; uint32_t spec[2] = { argc > 5 ? atoi(argv[5]) : 0, argc > 6 ? atoi(argv[6]) : 16 };
    char path[4096]; snprintf(path, sizeof path, "%s/%s.spv", dirname(strdup(argv[0])), shader);
    FILE *f = fopen(path, "rb"); if (!f) { perror(path); return 1; }
    fseek(f, 0, SEEK_END); long sz = ftell(f); rewind(f); uint32_t *spv = malloc(sz);
    if (fread(spv, 1, sz, f) != (size_t)sz) return 1; fclose(f);

    VkInstance inst; VkApplicationInfo ai = { VK_STRUCTURE_TYPE_APPLICATION_INFO, .apiVersion = VK_API_VERSION_1_2 };
#ifdef __APPLE__
    // MoltenVK is a portability driver: the loader lists it only when the instance asks for portability enumeration.
    const char *iext[] = { "VK_KHR_portability_enumeration" };
    CK(vkCreateInstance(&(VkInstanceCreateInfo){ VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .flags = 0x00000001 /* ENUMERATE_PORTABILITY */,
        .pApplicationInfo = &ai, .enabledExtensionCount = 1, .ppEnabledExtensionNames = iext }, NULL, &inst));
    const char *dext[] = { "VK_KHR_portability_subset" }; uint32_t ndext = 1;
#else
    CK(vkCreateInstance(&(VkInstanceCreateInfo){ VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &ai }, NULL, &inst));
    const char **dext = NULL; uint32_t ndext = 0;
#endif
    uint32_t nd = 1; VkPhysicalDevice pd; vkEnumeratePhysicalDevices(inst, &nd, &pd);
    if (!nd) { fprintf(stderr, "no Vulkan device\n"); return 1; }
    VkPhysicalDeviceProperties pp; vkGetPhysicalDeviceProperties(pd, &pp);
    uint32_t nq = 0; vkGetPhysicalDeviceQueueFamilyProperties(pd, &nq, NULL);
    VkQueueFamilyProperties qf[16]; if (nq > 16) nq = 16; vkGetPhysicalDeviceQueueFamilyProperties(pd, &nq, qf);
    uint32_t qi = 0; while (qi < nq && !(qf[qi].queueFlags & VK_QUEUE_COMPUTE_BIT)) qi++;
    float prio = 1; VkDevice dev;
    // 16-bit storage, for q8dot.spv's 16-bit reads of q8_0 blocks (as ggml reads them).
    VkPhysicalDevice16BitStorageFeatures s16 = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_16BIT_STORAGE_FEATURES, .storageBuffer16BitAccess = VK_TRUE };
    VkPhysicalDeviceFeatures2 f2 = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2, .pNext = &s16, .features = { .shaderInt16 = VK_TRUE } };
    CK(vkCreateDevice(pd, &(VkDeviceCreateInfo){ VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, .pNext = &f2, .queueCreateInfoCount = 1,
        .enabledExtensionCount = ndext, .ppEnabledExtensionNames = dext,
        .pQueueCreateInfos = &(VkDeviceQueueCreateInfo){ VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, .queueFamilyIndex = qi, .queueCount = 1, .pQueuePriorities = &prio } }, NULL, &dev));
    VkQueue q; vkGetDeviceQueue(dev, qi, 0, &q);

    VkBuffer buf; VkDeviceSize bytes = (VkDeviceSize)n * 4;
    CK(vkCreateBuffer(dev, &(VkBufferCreateInfo){ VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, .size = bytes, .usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT }, NULL, &buf));
    VkMemoryRequirements mr; vkGetBufferMemoryRequirements(dev, buf, &mr);
    VkPhysicalDeviceMemoryProperties mp; vkGetPhysicalDeviceMemoryProperties(pd, &mp);
    uint32_t mt = 0; while (mt < mp.memoryTypeCount && !((mr.memoryTypeBits >> mt & 1) && (mp.memoryTypes[mt].propertyFlags & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT))) mt++;
    VkDeviceMemory mem; CK(vkAllocateMemory(dev, &(VkMemoryAllocateInfo){ VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .allocationSize = mr.size, .memoryTypeIndex = mt }, NULL, &mem));
    CK(vkBindBufferMemory(dev, buf, mem, 0));

        // fat.spv has ggml's three buffers and 30 words of push constants; the others one buffer, one word.
    int fat = !strcmp(shader, "fat"); uint32_t nb = fat ? 3 : 1, pcs = fat ? 120 : 4;
    uint32_t pc[30] = { n, n, 1, 1, 1, 1, n, n, n, n, 1, 1, 1, 1, n, n, n, n, 1, 1, 1, 1, n, n, n, 0 };
    if (!fat) pc[0] = n;
    ((float *)pc)[26] = 1.0001f; ((float *)pc)[27] = 0; pc[28] = 0; pc[29] = 0;
    VkDescriptorSetLayout dsl; VkDescriptorSetLayoutBinding bs[3];
    for (uint32_t k = 0; k < nb; k++) bs[k] = (VkDescriptorSetLayoutBinding){ k, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT };
    CK(vkCreateDescriptorSetLayout(dev, &(VkDescriptorSetLayoutCreateInfo){ VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO, .bindingCount = nb, .pBindings = bs }, NULL, &dsl));
    VkPushConstantRange pcr = { VK_SHADER_STAGE_COMPUTE_BIT, 0, pcs }; VkPipelineLayout pl;
    CK(vkCreatePipelineLayout(dev, &(VkPipelineLayoutCreateInfo){ VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO, .setLayoutCount = 1, .pSetLayouts = &dsl, .pushConstantRangeCount = 1, .pPushConstantRanges = &pcr }, NULL, &pl));
    VkShaderModule sm; CK(vkCreateShaderModule(dev, &(VkShaderModuleCreateInfo){ VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO, .codeSize = sz, .pCode = spv }, NULL, &sm));
    int alt = getenv("VKCHAIN_ALT") && atoi(getenv("VKCHAIN_ALT")), rebind = getenv("VKCHAIN_REBIND") && atoi(getenv("VKCHAIN_REBIND"));
    uint32_t groups = getenv("VKCHAIN_GROUPS") ? atoi(getenv("VKCHAIN_GROUPS")) : 0;
    VkPipeline pipes[2];
    for (int k = 0; k < 2; k++) {
        // The second pipeline differs only in an unused specialization value, so it is a distinct object.
        uint32_t sp[3] = { spec[0], spec[1], (uint32_t)k };
        CK(vkCreateComputePipelines(dev, VK_NULL_HANDLE, 1, &(VkComputePipelineCreateInfo){ VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
            .stage = { VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_COMPUTE_BIT, .module = sm, .pName = "main",
                .pSpecializationInfo = &(VkSpecializationInfo){ 3, (VkSpecializationMapEntry[]){ { 0, 0, 4 }, { 1, 4, 4 }, { 7, 8, 4 } }, 12, sp } }, .layout = pl }, NULL, &pipes[k]));
    }
    VkPipeline pipe = pipes[0];
    VkDescriptorPool dp; VkDescriptorPoolSize ps = { VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 3 };
    CK(vkCreateDescriptorPool(dev, &(VkDescriptorPoolCreateInfo){ VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO, .maxSets = 1, .poolSizeCount = 1, .pPoolSizes = &ps }, NULL, &dp));
    VkDescriptorSet ds; CK(vkAllocateDescriptorSets(dev, &(VkDescriptorSetAllocateInfo){ VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO, .descriptorPool = dp, .descriptorSetCount = 1, .pSetLayouts = &dsl }, &ds));
    for (uint32_t k = 0; k < nb; k++)
        vkUpdateDescriptorSets(dev, 1, &(VkWriteDescriptorSet){ VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = ds, .dstBinding = k, .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .pBufferInfo = &(VkDescriptorBufferInfo){ buf, 0, bytes } }, 0, NULL);

    VkCommandPool cp; CK(vkCreateCommandPool(dev, &(VkCommandPoolCreateInfo){ VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO, .queueFamilyIndex = qi }, NULL, &cp));
    VkFence fence; CK(vkCreateFence(dev, &(VkFenceCreateInfo){ VK_STRUCTURE_TYPE_FENCE_CREATE_INFO }, NULL, &fence));
    printf("device %s, %u launches of %u floats, %s mode %u iters %u, alt %d rebind %d, best of %u\n", pp.deviceName, count, n, shader, spec[0], spec[1], alt, rebind, rep);
    for (int chain = 0; chain <= 1; chain++) {
        VkCommandBuffer cb; CK(vkAllocateCommandBuffers(dev, &(VkCommandBufferAllocateInfo){ VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, .commandPool = cp, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1 }, &cb));
        CK(vkBeginCommandBuffer(cb, &(VkCommandBufferBeginInfo){ VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO }));
        vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_COMPUTE, pipe);
        vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_COMPUTE, pl, 0, 1, &ds, 0, NULL);
        vkCmdPushConstants(cb, pl, VK_SHADER_STAGE_COMPUTE_BIT, 0, pcs, pc);
        VkMemoryBarrier mb = { VK_STRUCTURE_TYPE_MEMORY_BARRIER, .srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT, .dstAccessMask = VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT };
        for (uint32_t i = 0; i < count; i++) {
            if (alt) vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_COMPUTE, pipes[i & 1]);
            if (rebind) {
                vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_COMPUTE, pl, 0, 1, &ds, 0, NULL);
                vkCmdPushConstants(cb, pl, VK_SHADER_STAGE_COMPUTE_BIT, 0, pcs, pc);
            }
            vkCmdDispatch(cb, groups ? groups : (n + 255) / 256, 1, 1);
            if (chain && i + 1 < count) vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 1, &mb, 0, NULL, 0, NULL);
        }
        CK(vkEndCommandBuffer(cb));
        double best = 1e30;
        for (uint32_t r = 0; r < rep; r++) {
            double t0 = now_us();
            CK(vkQueueSubmit(q, 1, &(VkSubmitInfo){ VK_STRUCTURE_TYPE_SUBMIT_INFO, .commandBufferCount = 1, .pCommandBuffers = &cb }, fence));
            VkResult w = vkWaitForFences(dev, 1, &fence, VK_TRUE, 5000000000ull); // 5 s: a hung GPU must not hang the test
            if (w != VK_SUCCESS) { printf("%-6s GPU did not finish (%s)\n", chain ? "chain" : "free", w == VK_TIMEOUT ? "timeout" : "device lost or error"); return 2; }
            vkResetFences(dev, 1, &fence);
            double t = now_us() - t0; if (t < best) best = t;
        }
        printf("%-6s %8.2f us per launch (%.0f us for %u)\n", chain ? "chain" : "free", best / count, best, count);
        vkFreeCommandBuffers(dev, cp, 1, &cb);
    }
    vkDestroyDevice(dev, NULL); vkDestroyInstance(inst, NULL);
    return 0;
}
