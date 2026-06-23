# MortySmith Ollama Performance Research

**Date:** 2026-06-23
**Status:** Investigation Complete

## Problem
Mistral-trader (Q4_K_M, 4.1GB) runs at only **3.2 tok/s** on MortySmith (4× RX 6600 XT) vs **18 tok/s** on ClawMachine (2× RX 6600 XT).

## Root Cause

**Ollama v0.30.10 falls back to Vulkan backend** because all 4 GPUs on MortySmith report `gfx1032` (instead of `gfx1030`). Ollama drops them as unsupported for ROCm.

Evidence from logs:
```
dropping ROCm device — no rocblas support for gfx target
library=Vulkan
--split-mode none --main-gpu 0
```

### Why ClawMachine Works
- ClawMachine Ollama v0.20.5 uses **ROCm backend** (`libggml-hip.so`)
- GPUs report correctly as `gfx1030`
- Model split across 2 GPUs → 18 tok/s

### Why MortySmith Doesn't
- MortySmith GPUs report `gfx1032` (different BIOS/firmware per manufacturer)
- Ollama v0.30.10 doesn't recognize `gfx1032` as supported
- Falls back to **Vulkan** (single GPU, no splitting) → 3.2 tok/s

### GPU Manufacturers
| GPU | Manufacturer | Reported arch |
|-----|-------------|---------------|
| card1 | MSI | gfx1032 |
| card2 | ASUS | gfx1032 |
| card3 | XFX | gfx1032 |
| card4 | Sapphire | gfx1032 |

## Attempted Fixes

| Fix | Result |
|-----|--------|
| OLLAMA_SPLIT_MODE=layer | Ignored (Ollama forces `--split-mode none`) |
| OLLAMA_NUM_GPU=4 | Ignored |
| OLLAMA_VULKAN=1 | 2 GPUs detected, still 3.2 tok/s |
| HSA_OVERRIDE_GFX_VERSION=10.3.0 | v0.30.10: Vulkan fallback; v0.20.5: CPU-only |
| Ollama v0.20.5 binary | No GPU detection at all (CPU only) |
| ROCm libs from ClawMachine | v0.20.5 doesn't load them |
| Direct PCIe x16 (all 4 GPUs) | PCIe is fine, not the bottleneck |

## Conclusion

MortySmith is **not suitable for inference** with current Ollama versions. The `gfx1032` architecture detection prevents ROCm backend usage.

## Recommendations

1. **MortySmith → Training Only** (4× RX 6600 XT = 32GB VRAM for LoRA fine-tuning)
2. **Keep inference on ClawMachine** (2× RX 6600 XT, ROCm works, 18-73 tok/s)
3. **nemotron-mini-trader → AcerNitro** (NVIDIA RTX 4050, CUDA-native)
4. ## Current Status (2026-06-23 23:30 CEST)

**llama.cpp on MortySmith: CPU-only works, HIP build has symbol conflicts**
- CPU-only llama.cpp: ✅ Works (version 9775)
- HIP/ROCm build: ✅ Compiles (with patches for hipStreamWaitEvent and solve_tri.cu stub)
- HIP build runtime: ❌ `free(): invalid pointer` crash due to bfloat16 duplicate symbols in `libggml-hip.so`
- `--allow-multiple-definition` linker flag causes memory corruption at runtime
- **Next step:** Fix bfloat16 duplicate symbols (mark as `__attribute__((weak))` or deduplicate source files)

**Key Patches Applied:**
1. `ggml/src/ggml-cuda/vendors/hip.h`: `cudaStreamWaitEvent` macro → inline function with default flags=0
2. `ggml/src/ggml-cuda/solve_tri.cu`: Replaced with stub (hipblasStrsmBatched API incompatibility)
3. `CMAKE_SHARED_LINKER_FLAGS`: `--allow-multiple-definition` (causes runtime crash)

**Hardware Root Cause:** MortySmith's 4× RX 6600 XT GPUs report `gfx1032` (different manufacturers: MSI, ASUS, XFX, Sapphire). ClawMachine's 2× RX 6600 XT report `gfx1030`. ROCm/Ollama doesn't support `gfx1032` natively.

**Software Root Cause:** `amdgpu_get_auth` fails on 3 of 4 GPUs (headless mining rig), preventing HIP runtime initialization.

**GRUB `amdgpu.dc=0`:** Breaks module loading entirely – DO NOT USE on MortySmith.

## Current MoE Panel Distribution

| Model | Host | Backend | Speed |
|-------|------|---------|-------|
| nemotron-mini-trader | AcerNitro (RTX 4050) | CUDA | 9 tok/s |
| mistral:7b | ClawMachine (2×RX6600XT) | ROCm | 18 tok/s |
| qwen2.5-3b-trader | ClawMachine | ROCm | 33 tok/s |
| mistral:7b (sentiment) | ClawMachine | ROCm | 18 tok/s |
| qwen2.5:3b (risk) | ClawMachine | ROCm | 73 tok/s |