# The models of the runs

Every file `models.txt` names, where it came from, its size and sha256. Check a copy (`~/Projects/_llm`, or the
staged one on the exFAT disk) with:

    cd ~/Projects/_llm && sha256sum -c ~/Projects/linux-lab/macos/models.sha256

"Quant" is the file's own name for it; "header" is what its GGUF header says (`general.file_type`). The Unsloth
Dynamic (`UD-`) files mix types per tensor, so their header names only the base one.

| Name | File (under the models folder) | Quant / header | Bytes | Source | Matched how |
|---|---|---|---|---|---|
| llama2 | `Llama-2-7B/llama-2-7b.Q4_0.gguf` | Q4_0 / Q4_0 | 3825807040 | [TheBloke/Llama-2-7B-GGUF](https://huggingface.co/TheBloke/Llama-2-7B-GGUF/blob/main/llama-2-7b.Q4_0.gguf) | sha256 = Hugging Face's |
| gemma | `Gemma-4-26B-A4B-Instruct/UD-Q4_K_XL/model.gguf` | UD-Q4_K_XL / Q4_K_M | 17010980576 | [unsloth/gemma-4-26B-A4B-it-GGUF](https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF/blob/main/gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf) | sha256 = Hugging Face's |
| gemma, MTP | `Gemma-4-26B-A4B-Instruct/mtp-Q8_0.gguf` | Q8_0 / Q8_0 | 461766816 | [unsloth/gemma-4-26B-A4B-it-GGUF](https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF/blob/main/MTP/mtp-gemma-4-26B-A4B-it-Q8_0.gguf) | sha256 = Hugging Face's |
| qwen | `Qwen3-Coder-Next/UD-Q8_K_XL/model.gguf` | UD-Q8_K_XL / Q8_0 | 86348746848 | [unsloth/Qwen3-Coder-Next-GGUF](https://huggingface.co/unsloth/Qwen3-Coder-Next-GGUF/tree/main/UD-Q8_K_XL), 3 parts | merged parts, see below |
| gpt20 | `GPT-OSS-20B/UD-Q8_K_XL/model.gguf` | UD-Q8_K_XL / Q8_0 | 13195442368 | [unsloth/gpt-oss-20b-GGUF](https://huggingface.co/unsloth/gpt-oss-20b-GGUF/blob/main/gpt-oss-20b-UD-Q8_K_XL.gguf) | sha256 = Hugging Face's |
| gpt120 | `GPT-OSS-120B/UD-Q4_K_XL/model.gguf` | UD-Q4_K_XL / Q4_K_M | 63016311264 | [unsloth/gpt-oss-120b-GGUF](https://huggingface.co/unsloth/gpt-oss-120b-GGUF/tree/main/UD-Q4_K_XL), 2 parts | merged parts, see below |
| flash | `Qwen3.8-Flash-Next/UD-Q4_K_XL/model.gguf` | UD-Q4_K_XL / Q4_K_M | 111334654400 | [unsloth/Qwen3.8-Flash-Next-GGUF](https://huggingface.co/unsloth/Qwen3.8-Flash-Next-GGUF/tree/main/UD-Q4_K_XL), 4 parts | merged parts, see below |
| flash, MTP | `Qwen3.8-Flash-Next/mtp-Q4_K_M.gguf` | Q4_K_M / Q4_K_M | 2786204800 | [unsloth/Qwen3.8-Flash-Next-GGUF](https://huggingface.co/unsloth/Qwen3.8-Flash-Next-GGUF/blob/main/MTP/mtp-Qwen3.8-Flash-Next-Q4_K_M.gguf) | sha256 = Hugging Face's |

The sha256 of each file is in [`models.sha256`](models.sha256) (taken 1 Nov from the files the runs use).

"sha256 = Hugging Face's": the local file's sha256 is the one the Hugging Face API lists for that file (its LFS
oid), checked 1 Nov. "Merged parts": Hugging Face has these split in parts (`*-0000N-of-0000M.gguf`) and the local
file is one merged GGUF, so no published hash can match it. INFERRED from two checks, 1 Nov: its size is the parts'
sum less 128 bytes for each part after the first, and its last 4 MiB are byte for byte the last part's (a ranged
download). Its sha256 above is of the merged file.

`Llama 2`'s file is TheBloke's, not `ggml-org/Llama-2-7B-GGUF`'s (a different size and hash).
