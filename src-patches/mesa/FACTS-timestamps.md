# Facts for a Mesa report: Honeykrisp compute timestamps measure the work after them

For the operator to report in his own words (Asahi takes no AI-assisted material contributions; a report with these facts is his to write). Our local fix is `agxperf/0005`.

- Where: `src/asahi/vulkan/hk_query_pool.c`, `hk_CmdWriteTimestamp2`, unchanged from the coopmat series' base (795ae42a71) through Mesa of 25 Oct (e7371b0).
- What it does: a compute timestamp is stored as `timestamp.end` of the current CDM control stream, so it is written when that stream ends. The stream is split only at the next timestamp write. Dispatches recorded after the write therefore go into the same stream and finish before the timestamp is written.
- Effect: with a timestamp after every dispatch (ggml-vulkan's `GGML_VK_PERF_LOGGER`), timestamp i is the end of dispatch i+1, and each interval is booked to the dispatch before the one that ran in it. In llama.cpp prompts the cheap ops before large matmuls showed the matmuls' time (TOPK_MOE 170 ms, GLU 169 ms of a 0.9 s Qwen prompt; RMS_NORM_MUL 171 ms of a 0.6 s Llama 2 prompt) and the matmuls looked impossibly fast (q8_0 8192x512x2048 at 149 TFLOPS on a ~27 TFLOPS GPU).
- The spec: vkCmdWriteTimestamp2 with ALL_COMMANDS is written when all earlier commands have completed that stage, so later commands must not count.
- Fix tested here: end the compute stream right after setting its end timestamp (`if (!after_gfx) hk_cmd_buffer_end_compute(cmd);`), so the next dispatch starts a new stream. The redundant split before the write could then go. With it the per-op table sums to 9-11 % above the unlogged prompt time and puts the time on the matmuls (Mesa 795ae42a71 with agxperf, M2 Ultra; runs 6264 against 6289, 1 Nov).
- Cost: one extra CDM control stream per compute timestamp, only in command buffers that write timestamps.
