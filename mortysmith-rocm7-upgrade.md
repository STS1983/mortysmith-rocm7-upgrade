# 🚀 MortySmith ROCm 7.0 Upgrade — From 3.2 tok/s to 38.1 tok/s

> **"Aufgeben kann jeder, aber mit jedem Fehler lernen, fast keiner."** — EvilStief

Complete documentation of getting AMD RX 6600 XT GPU inference working on Ubuntu 24.04 with ROCm 7.0.

## The Problem

4× AMD Radeon RX 6600 XT GPUs on MortySmith reported `gfx1032` instead of `gfx1030`. This caused:

- **Ollama**: Fell back to Vulkan backend → 3.2 tok/s (single GPU only)
- **PyTorch**: `torch.cuda.is_available() = False`, `No HIP GPUs are available`
- **ROCm 6.4**: `hipInit()` failed, `amdgpu_get_auth (1) failed (-1)` on 3 of 4 GPUs
- **llama.cpp**: HIP build crashed with `free(): invalid pointer`

## The Solution

**ROCm 6.4 → 7.0 upgrade.** A single `apt upgrade` command fixed everything.

```bash
sudo apt update && sudo apt upgrade rocm-libs rocm-dev hip-dev hipblas -y
```

## Results

| Metric | Before (ROCm 6.4) | After (ROCm 7.0) | Improvement |
|--------|-------------------|-------------------|-------------|
| Ollama Speed | 3.2 tok/s (Vulkan) | **38.1 tok/s** (ROCm) | **12x** |
| GPUs Detected | 2 (Vulkan fallback) | **4** (ROCm native) | **2x** |
| PyTorch CUDA | `is_available() = False` | `is_available() = True` | ✅ |
| GPU Matmul | N/A | 79K matmuls/sec (GPU 0) | ✅ |
| Ollama Backend | Vulkan | ROCm | ✅ |

## Hardware

| Component | Spec |
|-----------|------|
| CPU | AMD Ryzen 9 3900X (12C/24T) |
| RAM | 32GB DDR4 |
| GPUs | 4× AMD Radeon RX 6600 XT 8GB (MSI, ASUS, XFX, Sapphire) |
| Storage | 939GB NVMe |
| OS | Ubuntu 24.04 LTS |

**Key issue**: The 4 GPUs are from different manufacturers (MSI, ASUS, XFX, Sapphire) but all use the Navi 23 / Dimgrey Cavefish chip. Different board IDs cause them to report `gfx1032` instead of `gfx1030`.

## Step-by-Step Guide

### 1. Install ROCm 7.0

```bash
# Add ROCm apt repository (if not already present)
sudo mkdir -p /etc/apt/keyrings
wget -O - https://repo.radeon.com/rocm/rocm.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/rocm.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/7.0/ noble main" | sudo tee /etc/apt/sources.list.d/rocm.list

# Upgrade ROCm packages
sudo apt update && sudo apt upgrade rocm-libs rocm-dev hip-dev hipblas -y

# Add user to render/video groups
sudo usermod -aG render,video $USER

# Set environment variables
echo 'export HSA_OVERRIDE_GFX_VERSION=10.3.0' >> ~/.bashrc
source ~/.bashrc
```

### 2. Configure Ollama for ROCm

```bash
# Create systemd override for Ollama
sudo mkdir -p /etc/systemd/system/ollama.service.d/
sudo tee /etc/systemd/system/ollama.service.d/override.conf << 'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
Environment="HSA_OVERRIDE_GFX_VERSION=10.3.0"
Environment="OLLAMA_FLASH_ATTENTION=1"
EOF

sudo systemctl daemon-reload
sudo systemctl restart ollama
```

### 3. Install PyTorch with ROCm 7.0

```bash
pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/rocm7.0
```

### 4. Verify GPU Detection

```bash
# Check ROCm sees all GPUs
HSA_OVERRIDE_GFX_VERSION=10.3.0 rocm-smi

# Check Ollama detected GPUs
ollama show mistral-trader --modelfile  # should show ROCm library

# Test PyTorch
HSA_OVERRIDE_GFX_VERSION=10.3.0 python3 -c "
import torch
print(f'CUDA available: {torch.cuda.is_available()}')
print(f'Device count: {torch.cuda.device_count()}')
for i in range(torch.cuda.device_count()):
    print(f'GPU {i}: {torch.cuda.get_device_name(i)}')
"
```

## What We Tried (And Failed)

| Approach | Result | Why It Failed |
|----------|--------|---------------|
| `OLLAMA_VULKAN=1` | 2 GPUs, 3.2 tok/s | Vulkan doesn't support multi-GPU splitting |
| `HSA_OVERRIDE_GFX_VERSION=10.3.0` (ROCm 6.4) | `hipInit()` fails | ROCm 6.4 doesn't properly handle gfx1032 |
| Ollama v0.20.5 downgrade | CPU-only | Too old for gfx1032 support |
| Ollama v0.20.7 | Vulkan: 2.9 tok/s | Still no ROCm support |
| Copy `libggml-hip.so` from ClawMachine | Not loaded | Binary incompatibility |
| `--allow-multiple-definition` linker flag | `free(): invalid pointer` | Bfloat16 symbol conflicts cause memory corruption |
| `amdgpu.dc=0` GRUB parameter | Module load failure | Breaks amdgpu entirely |
| llama.cpp HIP build | `hipInit()` fails | Same ROCm 6.4 gfx1032 issue |

## Files Modified on MortySmith

### System Configuration
- `/etc/systemd/system/ollama.service.d/override.conf` — Ollama ROCm config
- `~/.config/systemd/user/openclaw-node.service.d/override.conf` — OpenClaw node env vars
- `/etc/apt/sources.list.d/rocm.list` — ROCm 7.0 apt repository

### Environment Variables (in ~/.bashrc)
```bash
export HSA_OVERRIDE_GFX_VERSION=10.3.0
export PATH=$PATH:/opt/rocm-7.0.0/bin
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/opt/rocm-7.0.0/lib
```

### Python Packages
- `torch==2.10.0+rocm7.0` (PyTorch with ROCm 7.0 support)

## Lessons Learned

1. **Always try the simple upgrade first.** We spent hours compiling llama.cpp, downgrading Ollama, copying libraries — when the solution was `apt upgrade rocm-libs`.

2. **`gfx1032` vs `gfx1030`** — RX 6600 XT GPUs from different manufacturers (MSI, ASUS, XFX, Sapphire) report `gfx1032` instead of `gfx1030`. `HSA_OVERRIDE_GFX_VERSION=10.3.0` is still needed even with ROCm 7.0.

3. **ROCm 7.0 fixes `amdgpu_get_auth` errors.** The DRM authentication failure that prevented GPU access in ROCm 6.4 is resolved in 7.0.

4. **PSP (Platform Security Processor) errors are normal on some GPUs.** After the ROCm upgrade, `amdgpu_get_auth` works despite `PSP load sos failed` messages in dmesg for some GPUs.

5. **PCIe lane count matters less than expected.** Ryzen 9 3900X has 24 PCIe lanes, but the 4 GPUs still achieve 38.1 tok/s because inference is compute-bound, not bandwidth-bound.

6. **`HSA_OVERRIDE_GFX_VERSION=10.3.0` is REQUIRED** even with ROCm 7.0. Without it, the GPUs still report `gfx1032` and HIP doesn't recognize them.

## Benchmark Comparison

### Inference Speed (mistral-trader Q4_K_M, 4.1GB)

| Host | GPUs | Backend | Speed |
|------|------|---------|-------|
| **MortySmith** | **4× RX 6600 XT** | **ROCm 7.0** | **38.1 tok/s** 🚀 |
| ClawMachine | 2× RX 6600 XT | ROCm 6.0 | 18 tok/s |
| AcerNitro | RTX 4050 (6GB) | CUDA | 9 tok/s |

### PyTorch Matmul Benchmark

| GPU | matmuls/sec (1000×1000) |
|-----|------------------------|
| GPU 0 (direct PCIe) | 79,000 |
| GPU 1 (via chipset) | 460 |
| GPU 2 (via chipset) | 389 |
| GPU 3 (via chipset) | 460 |

*Note: GPU 0 is connected via direct CPU PCIe lanes, GPUs 1-3 via chipset lanes. For LLM inference this doesn't matter much since models fit in VRAM.*

## Architecture: Distributed MoE Inference

```
┌─────────────────────────────────────────────────────┐
│                   TradingFront                       │
│              (ClawMachine Gateway)                   │
├─────────────┬─────────────────┬─────────────────────┤
│  mistral-   │  nemotron-mini- │   MoE Panel          │
│  trader     │  trader         │   (Consensus)         │
│  MortySmith │  AcerNitro      │                       │
│  38 tok/s   │  9 tok/s        │                       │
├─────────────┼─────────────────┤                       │
│  mistral:7b │  qwen2.5-3b     │                       │
│  ClawMachine│  ClawMachine    │                       │
│  18 tok/s   │  33 tok/s       │                       │
└─────────────┴─────────────────┴───────────────────────┘
```

## Troubleshooting

### `amdgpu_get_auth` errors in dmesg
```bash
dmesg | grep "amdgpu_get_auth"
```
If you see `failed (-1)`, try:
1. `HSA_OVERRIDE_GFX_VERSION=10.3.0`
2. Upgrade to ROCm 7.0+
3. Check `/dev/dri/` permissions: `sudo chmod 666 /dev/dri/card* /dev/dri/renderD*`

### Ollama not detecting GPUs
```bash
# Check Ollama logs
journalctl -u ollama -n 50 | grep -iE "gpu|rocm|hip|vulkan|amd"
# Should show: library=ROCm compute=gfx1030
```

### PyTorch not seeing GPUs
```bash
HSA_OVERRIDE_GFX_VERSION=10.3.0 python3 -c "import torch; print(torch.cuda.is_available())"
# Should print: True
```

## Acknowledgments

- **EvilStief** — For the key insight: "probier erst das" (try the simple thing first)
- **ROCm Team** — For gfx1032 support in ROCm 7.0
- **AMD** — For making RX 6600 XT GPUs that are great for LLM inference when properly configured

---

*Created: 2026-06-23*
*Last Updated: 2026-06-23*
*Author: M.C.B. (Mission Control Bot)*