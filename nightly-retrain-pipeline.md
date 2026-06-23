# Nightly Retrain Pipeline — Design Document

**Created:** 2026-06-24 00:45 CEST  
**Status:** Draft  
**Author:** M.C.B.

## Overview

Automated nightly LoRA retraining pipeline on MortySmith (4×RX6600XT, ROCm 7.0) using Trading KG data, then deploy updated models across the cluster.

## Architecture

```
[Cron Trigger 02:00 CET]
       ↓
[MortySmith: Training Node]
   ├── Extract training data from trading_kg.json (ClawMachine → MortySmith)
   ├── LoRA fine-tuning (PyTorch 2.10+rocm7.0, 4×RX6600XT)
   ├── Merge adapter into base model
   ├── Convert to GGUF (Q4_K_M quantization)
   └── Import to Ollama
       ↓
[Distribute to Cluster]
   ├── MortySmith: ollama create (local)
   ├── ClawMachine: scp + ollama create
   └── AcerNitro: scp + ollama create (if model fits)
       ↓
[Health Check & Rollback]
   ├── Inference test (each node)
   ├── If fail: rollback to previous version
   └── Log results to memory/YYYY-MM-DD.md
```

## Models to Retrain

| Model | Base | LoRA Target | Deploy To |
|-------|------|-------------|-----------|
| mistral-trader | mistral:7b | Risk assessment | MortySmith, ClawMachine |
| qwen2.5-3b-trader | qwen2.5:3b | Pattern recognition | ClawMachine, AcerNitro |
| nemotron-mini-trader | nemotron-mini | Pattern recognition | MortySmith only (8.4GB) |

## Pipeline Steps

### 1. Data Extraction (ClawMachine)
```bash
# Export last 24h of trading decisions
python3 ACTIVE/trading-front/training/extract_training_data.py \
  --input ACTIVE/trading-front/trading_kg.json \
  --output /tmp/training_dpo_$(date +%Y%m%d).jsonl \
  --since "24h ago"
```

### 2. Transfer to MortySmith
```bash
scp /tmp/training_dpo_*.jsonl nodeadmin@192.168.0.124:/home/nodeadmin/training/data/
```

### 3. LoRA Training (MortySmith)
```bash
HSA_OVERRIDE_GFX_VERSION=10.3.0 python3 train_mistral7b_qlora.py \
  --data /home/nodeadmin/training/data/training_dpo_*.jsonl \
  --output /home/nodeadmin/training/output/mistral-7b-trader-$(date +%Y%m%d)/ \
  --epochs 3 \
  --lr 2e-4 \
  --lora-r 16 \
  --lora-alpha 32
```

### 4. Merge & Quantize (MortySmith)
```bash
# Merge LoRA adapter
python3 merge_adapter.py --base mistral:7b --adapter output/adapter/ --output output/merged/

# Convert to GGUF Q4_K_M
python3 convert_to_gguf.py --input output/merged/ --output output/mistral-trader-q4_k_m.gguf

# Import to Ollama
ollama create mistral-trader -f Modelfile
```

### 5. Distribute (MortySmith → Cluster)
```bash
# Export GGUF blob
BLOB=$(ollama show mistral-trader --modelfile | grep FROM | awk '{print $2}')

# To ClawMachine
scp /usr/share/ollama/.ollama/models/blobs/$BLOB nodeadmin@192.168.0.251:/tmp/
ssh nodeadmin@192.168.0.251 'ollama create mistral-trader -f Modelfile'

# To AcerNitro (if applicable)
scp /usr/share/ollama/.ollama/models/blobs/$BLOB pouwfrontend@192.168.0.115:/tmp/ -P 2200
ssh -p 2200 pouwfrontend@192.168.0.115 'ollama create mistral-trader -f Modelfile'
```

### 6. Health Check (All Nodes)
```bash
# Test inference on each node
for host in "192.168.0.124:11434" "192.168.0.251:11434" "192.168.0.115:11434"; do
  RESULT=$(curl -s --max-time 30 http://$host/api/generate \
    -d '{"model":"mistral-trader:latest","prompt":"BTC 65000 signal?","stream":false}')
  TOK_RATE=$(echo $RESULT | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'{d[\"eval_count\"]/d[\"eval_duration\"]*1e9:.1f}')")
  echo "$host: $TOK_RATE tok/s"
done
```

## Cron Schedule

```bash
# MortySmith crontab
0 2 * * * /home/nodeadmin/training/scripts/nightly-retrain.sh >> /home/nodeadmin/training/logs/retrain.log 2>&1
```

## Rollback Strategy

- Keep last 3 model versions in `/home/nodeadmin/training/output/`
- If health check fails: `ollama rm mistral-trader:latest && ollama create mistral-trader -f Modelfile.previous`
- Log all results to `memory/YYYY-MM-DD.md`

## Prerequisites

- [x] MortySmith ROCm 7.0 installed and working (38.1 tok/s)
- [x] PyTorch 2.10.0+rocm7.0 installed
- [x] Ollama 0.30.10 with ROCm backend (4 GPUs)
- [x] Training data extraction script exists
- [ ] Training automation script (nightly-retrain.sh)
- [ ] Model distribution script (distribute-models.sh)
- [ ] Health check + rollback script (health-check-models.sh)
- [ ] Cron job on MortySmith

## Next Steps

1. Create `nightly-retrain.sh` script
2. Create `distribute-models.sh` script
3. Create `health-check-models.sh` script
4. Set up cron on MortySmith
5. Test full pipeline end-to-end

---

*Last updated: 2026-06-24 00:45 CEST*