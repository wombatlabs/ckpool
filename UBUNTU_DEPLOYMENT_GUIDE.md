# Ubuntu Server Deployment Guide - Lean Blocks Feature

## Quick Deployment Steps

### 1. Connect to Your Ubuntu Server
```bash
ssh user@your-server-ip
```

### 2. Clone and Checkout Feature Branch
```bash
cd ~
git clone https://github.com/yourusername/ckpool.git
cd ckpool
git checkout feat/lean-blocks-dual-submit
```

### 3. Run Installation Script
```bash
./install-ckpool-lean.sh
```

### 4. Configure Your Pool
```bash
# Edit the main config
nano ~/ckpool/ckpool.conf

# Set these values:
# - btcaddress: Your BCH address
# - auth/pass: Your bitcoind RPC credentials
```

### 5. Configure Bitcoin Cash Node
```bash
# Edit bitcoin.conf
sudo nano /etc/bitcoin/bitcoin.conf
```

Add these settings:
```ini
server=1
rpcuser=bchadmin
rpcpassword=YOUR_SECURE_PASSWORD
rpcallowip=127.0.0.1
rpcport=8332
zmqpubhashblock=tcp://0.0.0.0:28333
maxconnections=125
```

### 6. Start Services
```bash
# Start bitcoind
sudo systemctl start bitcoind

# Wait for sync (check progress)
bitcoin-cli getblockchaininfo

# Start pool in normal mode
sudo systemctl start ckpool

# OR start in lean mode for maximum speed
sudo systemctl start ckpool-lean
```

## Operating Lean Blocks

### Quick Mode Switching

**Enable Lean Mode (Empty Blocks):**
```bash
~/ckpool/switch-to-lean.sh
```

**Return to Normal Mode:**
```bash
~/ckpool/switch-to-normal.sh
```

### When to Use Each Mode

| Your Hashrate | Recommended Mode | Command |
|--------------|------------------|---------|
| 400+ PH burst | Lean (coinbase_only) | `~/ckpool/switch-to-lean.sh` |
| 100-400 PH | Lean or Normal | Depends on fees |
| < 100 PH | Normal | `~/ckpool/switch-to-normal.sh` |

### Monitor Performance
```bash
# Real-time monitoring
~/ckpool/monitor.sh

# Watch logs
tail -f ~/ckpool/logs/ckpool.log

# Check lean blocks
grep "LEAN_BLOCK" ~/ckpool/logs/ckpool.log | tail -20

# Check dual submissions
grep "DUAL_SUBMIT" ~/ckpool/logs/ckpool.log | tail -20
```

## Configuration Details

### Lean Mode Settings (ckpool-lean.conf)
```json
{
  "lean_blocks": true,           // Enable lean blocks
  "lean_mode": "coinbase_only",  // Empty blocks (maximum speed)
  "dual_submit": true,           // Submit to both nodes
  "aggressive_preflight": true   // Skip validation for speed
}
```

### Mode Options

**coinbase_only** (Recommended for bursts)
- Empty blocks only
- Fastest propagation
- Maximum block discovery rate
- Matches unknown miner strategy

**top_n** (Balance speed/fees)
```json
{
  "lean_mode": "top_n",
  "lean_maxtx": 5  // Include top 5 fee transactions
}
```

**size_cap** (Size limited)
```json
{
  "lean_mode": "size_cap",
  "lean_maxsize_kb": 100  // Max 100KB blocks
}
```

## Testing Before Production

### 1. Test Configuration
```bash
# Test config syntax
~/ckpool/ckpool -c ~/ckpool/ckpool-lean.conf -t

# Run in foreground to see output
~/ckpool/ckpool -c ~/ckpool/ckpool-lean.conf
```

### 2. Connect Test Miner
```bash
# From another machine
minerd -a sha256d -o stratum+tcp://your-server:3333 -u testworker -p x
```

### 3. Check Metrics
```bash
# Pool stats
~/ckpool/ckpmsg -s /tmp/ckpool/stratifier stats

# Worker info
~/ckpool/ckpmsg -s /tmp/ckpool/stratifier workers
```

## Production Checklist

- [ ] Bitcoin Cash node fully synced
- [ ] Both nodes configured (if using dual_submit)
- [ ] Pool config has correct BCH address
- [ ] RPC credentials match bitcoind
- [ ] Firewall allows port 3333 for miners
- [ ] Monitoring scripts tested
- [ ] Backup of configs created

## Systemd Commands

```bash
# Status
sudo systemctl status ckpool
sudo systemctl status ckpool-lean

# Start/Stop
sudo systemctl start ckpool-lean
sudo systemctl stop ckpool-lean

# Restart
sudo systemctl restart ckpool-lean

# View logs
sudo journalctl -u ckpool-lean -f

# Enable auto-start
sudo systemctl enable ckpool-lean
```

## Performance Tuning

### For Maximum Block Discovery
1. Use `coinbase_only` mode
2. Enable `dual_submit`
3. Enable `aggressive_preflight`
4. Ensure low latency to BCH network
5. Use fast NVMe storage

### Network Optimization
```bash
# Increase network buffers
sudo sysctl -w net.core.rmem_max=134217728
sudo sysctl -w net.core.wmem_max=134217728
sudo sysctl -w net.ipv4.tcp_rmem="4096 87380 134217728"
sudo sysctl -w net.ipv4.tcp_wmem="4096 65536 134217728"
```

## Troubleshooting

### Pool Won't Start
```bash
# Check for errors
sudo journalctl -u ckpool-lean -n 50

# Check if port is in use
sudo lsof -i :3333

# Check config syntax
~/ckpool/ckpool -c ~/ckpool/ckpool-lean.conf -t
```

### No Blocks Found
1. Check lean mode is enabled: `grep lean_blocks ~/ckpool/ckpool-lean.conf`
2. Verify bitcoind connection: `~/ckpool/ckpmsg -s /tmp/ckpool/generator getbest`
3. Check miner connections: `~/ckpool/ckpmsg -s /tmp/ckpool/connector stats`

### High Orphan Rate
1. Immediately switch to normal mode
2. Check node sync status
3. Review network latency
4. Consider disabling lean blocks temporarily

## Expected Results

With lean blocks enabled during high hashrate (400+ PH):
- **Block discovery**: +20-40% more blocks
- **Propagation**: 50-80% faster
- **Orphan rate**: Should stay < 2%
- **Revenue impact**: Higher block rewards offset fee loss

## Support Commands

```bash
# Get pool version
~/ckpool/ckpool -v

# Test connectivity to bitcoind
bitcoin-cli getblockcount

# Check pool health
~/ckpool/ckpmsg -s /tmp/ckpool/stratifier stats

# Emergency stop
sudo systemctl stop ckpool-lean
```

---

**Remember:** Lean blocks are most effective during high hashrate bursts. Monitor your results and adjust strategy based on network conditions.