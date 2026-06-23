# MortySmith ROCm 7.0 Upgrade — Quick Setup Script

#!/bin/bash
# mortysmith-rocm7-setup.sh — Setup ROCm 7.0 on MortySmith (4× RX 6600 XT)
# Run as: bash mortysmith-rocm7-setup.sh
# Tested on: Ubuntu 24.04 LTS, 2026-06-23

set -e

echo "🚀 MortySmith ROCm 7.0 Setup"
echo "================================"

# 1. Add ROCm 7.0 repository
echo ""
echo "📦 Adding ROCm 7.0 apt repository..."
sudo mkdir -p /etc/apt/keyrings
wget -q -O - https://repo.radeon.com/rocm/rocm.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/rocm.gpg 2>/dev/null || {
    echo "⚠️  GPG key import failed. Trying alternative method..."
    curl -fsSL https://repo.radeon.com/rocm/rocm.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/rocm.gpg
}

echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/7.0/ noble main" | sudo tee /etc/apt/sources.list.d/rocm.list > /dev/null

# 2. Upgrade ROCm packages
echo ""
echo "⬆️  Upgrading ROCm packages (6.4 → 7.0)..."
sudo apt update
sudo apt upgrade rocm-libs rocm-dev hip-dev hipblas -y

# 3. Add user to render/video groups
echo ""
echo "👤 Adding user to render/video groups..."
sudo usermod -aG render,video $USER

# 4. Set environment variables
echo ""
echo "🔧 Setting environment variables..."
if ! grep -q "HSA_OVERRIDE_GFX_VERSION" ~/.bashrc; then
    echo 'export HSA_OVERRIDE_GFX_VERSION=10.3.0' >> ~/.bashrc
    echo "   Added HSA_OVERRIDE_GFX_VERSION to ~/.bashrc"
else
    echo "   HSA_OVERRIDE_GFX_VERSION already in ~/.bashrc"
fi

if ! grep -q "/opt/rocm-7.0.0/bin" ~/.bashrc; then
    echo 'export PATH=$PATH:/opt/rocm-7.0.0/bin' >> ~/.bashrc
    echo 'export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/opt/rocm-7.0.0/lib' >> ~/.bashrc
    echo "   Added ROCm paths to ~/.bashrc"
else
    echo "   ROCm paths already in ~/.bashrc"
fi

# 5. Configure Ollama for ROCm
echo ""
echo "🦙 Configuring Ollama for ROCm..."
sudo mkdir -p /etc/systemd/system/ollama.service.d/
sudo tee /etc/systemd/system/ollama.service.d/override.conf > /dev/null << 'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
Environment="HSA_OVERRIDE_GFX_VERSION=10.3.0"
Environment="OLLAMA_FLASH_ATTENTION=1"
EOF

sudo systemctl daemon-reload
sudo systemctl restart ollama

# 6. Wait for Ollama to start
echo ""
echo "⏳ Waiting for Ollama to detect GPUs..."
sleep 10

# 7. Verify GPU detection
echo ""
echo "✅ Verification:"
echo "================================"

export HSA_OVERRIDE_GFX_VERSION=10.3.0
export PATH=$PATH:/opt/rocm-7.0.0/bin

echo ""
echo "ROCm SMI:"
rocm-smi --showid 2>/dev/null | head -10 || echo "⚠️  rocm-smi not found"

echo ""
echo "Ollama GPU Detection:"
journalctl -u ollama -n 30 --no-pager 2>/dev/null | grep -iE "gpu|rocm|hip|vulkan|amd|library|compute" | tail -10

echo ""
echo "PyTorch GPU Test:"
python3 -c "
import torch
print(f'  PyTorch: {torch.__version__}')
print(f'  CUDA available: {torch.cuda.is_available()}')
print(f'  Device count: {torch.cuda.device_count()}')
if torch.cuda.is_available():
    for i in range(torch.cuda.device_count()):
        print(f'  GPU {i}: {torch.cuda.get_device_name(i)}')
" 2>&1 || echo "⚠️  PyTorch not installed. Install with: pip3 install torch --index-url https://download.pytorch.org/whl/rocm7.0"

echo ""
echo "🎉 Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Install PyTorch: pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/rocm7.0"
echo "  2. Import your model: ollama create <model-name> -f Modelfile"
echo "  3. Test inference: ollama run <model-name>"
echo ""
echo "Expected: 38+ tok/s on mistral-trader Q4_K_M"