# 🚀 MortySmith ROCm 7.0 Upgrade — From 3.2 tok/s to 38.1 tok/s

> **"Aufgeben kann jeder, aber mit jedem Fehler lernen, fast keiner."** — EvilStief

Complete documentation of getting **4× AMD Radeon RX 6600 XT** GPU inference working on Ubuntu 24.04 with **ROCm 7.0**.

## The Problem

RX 6600 XT GPUs from different manufacturers (MSI, ASUS, XFX, Sapphire) report `gfx1032` instead of `gfx1030`. With ROCm 6.4, this caused:

- Ollama: Vulkan fallback → **3.2 tok/s** (single GPU)
- PyTorch: `torch.cuda.is_available() = False`
- llama.cpp: `hipInit()` failure

## The Solution

```bash
sudo apt upgrade rocm-libs rocm-dev hip-dev hipblas -y
```

**One command. 12x performance improvement.**

## Results

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Inference Speed | 3.2 tok/s | **38.1 tok/s** | **12x** |
| GPUs Detected | 2 (Vulkan) | **4 (ROCm)** | **2x** |
| PyTorch CUDA | ❌ | ✅ | — |
| Backend | Vulkan | ROCm | — |

## Quick Start

```bash
# 1. Add ROCm 7.0 repo and upgrade
bash mortysmith-rocm7-setup.sh

# 2. Install PyTorch with ROCm 7.0
pip3 install torch --index-url https://download.pytorch.org/whl/rocm7.0

# 3. Test
HSA_OVERRIDE_GFX_VERSION=10.3.0 python3 -c "import torch; print(torch.cuda.is_available())"
# Should print: True
```

## Documentation

| File | Description |
|------|-------------|
| [mortysmith-rocm7-upgrade.md](mortysmith-rocm7-upgrade.md) | Full documentation with troubleshooting |
| [mortysmith-rocm7-setup.sh](mortysmith-rocm7-setup.sh) | Automated setup script |
| [mortysmith-ollama-performance.md](mortysmith-ollama-performance.md) | Performance research and debugging log |

## Hardware

| Component | Spec |
|-----------|------|
| CPU | AMD Ryzen 9 3900X (12C/24T) |
| RAM | 32GB DDR4 |
| GPUs | 4× AMD RX 6600 XT 8GB (MSI, ASUS, XFX, Sapphire) |
| Storage | 939GB NVMe |
| OS | Ubuntu 24.04 LTS |

## Lessons Learned

1. **Try the simple upgrade first** — We spent hours on complex fixes when `apt upgrade` solved everything
2. **`HSA_OVERRIDE_GFX_VERSION=10.3.0`** is still needed even with ROCm 7.0
3. **ROCm 7.0 fixes `amdgpu_get_auth` errors** that prevented GPU access in 6.4
4. **PCIe lanes matter less than expected** — Inference is compute-bound, not bandwidth-bound

## Star History

If this helped you get AMD GPUs working, ⭐ star the repo!

---

*Created: 2026-06-23* | *Author: M.C.B.*
