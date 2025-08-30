# EloPool (CKPool Fork) - High-Performance Bitcoin Cash Mining Pool

**EloPool** is an enhanced fork of CKPool optimized for Bitcoin Cash (BCH) mining with enterprise-grade features including multi-node ZMQ support, ASIC optimization, and high-performance architecture.

## 🚀 Key Features

### Core CKPool Features
- **Ultra-low overhead** massively scalable multi-process, multi-threaded architecture
- **Multiple deployment modes**: Pool, Solo, Proxy, Passthrough, Node
- **Seamless restarts** with socket handover for zero-downtime upgrades
- **ASICBoost support** for improved mining efficiency
- **Advanced vardiff** algorithm with stable high-difficulty handling

### EloPool Enhancements
- **Multi-Node ZMQ Support** 🆕
  - Connect to multiple BCH nodes simultaneously
  - Redundant block notifications (failover support)
  - Faster block detection (milliseconds vs polling)
  - Load distribution across nodes
- **Lean Blocks Mining** 🆕
  - Maximize block discovery rate over fee collection
  - Three configurable modes for different strategies
  - Ideal for high-hashrate burst mining
  - Proven strategy used by successful BCH miners
- **Bitcoin Cash Optimizations**
  - SegWit removed for BCH compatibility
  - Optimized for ASIC miners (500k+ difficulty)
  - Custom BCH coinbase signatures
- **Production-Ready Configuration**
  - Pre-configured for high-performance ASIC mining
  - Comprehensive logging and monitoring
  - SystemD service integration

## 📋 Requirements

- **Operating System**: Ubuntu 18.04+ or Debian 10+
- **Dependencies**: 
  - Build tools: `build-essential autoconf automake libtool`
  - Libraries: `libssl-dev libjansson-dev libzmq3-dev`
- **Bitcoin Cash Node**: One or more BCH full nodes with RPC and ZMQ enabled

## 🛠️ Installation

### Quick Install (Production)

```bash
# Clone the repository
git clone https://github.com/skaisser/ckpool.git
cd ckpool

# Run the installer
./install-ckpool.sh
```

### Development/Testing Install

```bash
# Clone the repository
git clone https://github.com/skaisser/ckpool.git
cd ckpool

# Build from current directory
./install-local.sh
```

## ⚙️ Configuration

### Basic Configuration (Single Node)

```json
{
    "btcd": [{
        "url": "127.0.0.1:8332",
        "auth": "rpcuser",
        "pass": "rpcpassword",
        "notify": true,
        "zmqnotify": "tcp://127.0.0.1:28333"
    }],
    "btcaddress": "YOUR_BCH_ADDRESS",
    "btcsig": "/[Solo]",
    "pooladdress": "YOUR_BCH_ADDRESS",
    "poolfee": 1,
    "blockpoll": 50,
    "update_interval": 15,
    "serverurl": ["0.0.0.0:3333"],
    "mindiff": 500000,
    "startdiff": 500000,
    "maxdiff": 1000000
}
```

### Multi-Node Configuration (Recommended)

```json
{
    "btcd": [
        {
            "url": "10.0.1.10:8332",
            "auth": "rpcuser",
            "pass": "rpcpassword",
            "notify": true,
            "zmqnotify": "tcp://10.0.1.10:28333"
        },
        {
            "url": "10.0.1.11:8332",
            "auth": "rpcuser",
            "pass": "rpcpassword",
            "notify": true,
            "zmqnotify": "tcp://10.0.1.11:28333"
        }
    ],
    "btcaddress": "YOUR_BCH_ADDRESS",
    "btcsig": "/EloPool/",
    "pooladdress": "YOUR_BCH_ADDRESS",
    "poolfee": 1,
    "mindiff": 500000,
    "startdiff": 500000,
    "maxdiff": 1000000,
    "asicboost": true,
    "version_mask": "1fffe000"
}
```

### Lean Blocks Configuration (Advanced)

Lean blocks is a mining strategy that prioritizes block discovery rate over transaction fee collection. This is particularly effective during high-hashrate bursts or when competing with other miners.

#### Configuration Options

```json
{
    "lean_blocks": true,           // Enable lean blocks feature (default: false)
    "lean_mode": "top_n",          // Mining mode: "coinbase_only", "top_n", or "size_cap"
    "lean_maxtx": 5,               // Max transactions to include (for top_n mode)
    "lean_maxsize_kb": 10          // Max block size in KB (for size_cap mode)
}
```

#### Available Modes

**1. Normal Mining (lean_blocks: false)**
- Traditional mining with all transactions included
- Maximizes fee collection
- Larger blocks, slower propagation
- Best for: Steady hashrate, low competition

**2. Coinbase-Only Mode**
```json
{
    "lean_blocks": true,
    "lean_mode": "coinbase_only"
}
```
- Empty blocks (only coinbase transaction)
- Zero transaction fees collected
- Fastest possible block propagation
- Best for: Maximum speed during hashrate spikes, competing with fast miners

**3. Top-N Mode**
```json
{
    "lean_blocks": true,
    "lean_mode": "top_n",
    "lean_maxtx": 5
}
```
- Includes only the top N highest-fee transactions
- Balances speed with some fee collection
- Maintains transaction ordering for dependencies
- Best for: General lean mining, good compromise between speed and fees

**4. Size-Cap Mode**
```json
{
    "lean_blocks": true,
    "lean_mode": "size_cap",
    "lean_maxsize_kb": 10
}
```
- Limits block size to specified KB
- Includes as many transactions as fit
- Predictable block size
- Best for: Network conditions where specific block sizes perform better

#### When to Use Lean Blocks

**Enable Lean Blocks When:**
- You have sudden hashrate spikes (e.g., 400+ PH/s bursts)
- Competing with miners using similar strategies
- Network latency is high to other miners
- Block propagation speed is critical
- You observe other miners finding many blocks quickly

**Use Normal Mode When:**
- Network fees are exceptionally high
- You have consistent, steady hashrate
- Less competition from other miners
- You want to maximize revenue per block

#### Decision Matrix

Use this table to choose the optimal mode based on your hashrate and current mempool fees:

| Hashrate     | Mempool Fees | Best Mode      | Configuration                    |
|--------------|--------------|----------------|-----------------------------------|
| < 100 PH     | Any          | Normal         | `"lean_blocks": false`            |
| 100-200 PH   | < 0.1 BCH    | Top_5          | `"lean_mode": "top_n", "lean_maxtx": 5` |
| 100-200 PH   | > 0.1 BCH    | Normal         | `"lean_blocks": false`            |
| 200-500 PH   | < 0.05 BCH   | Coinbase_only  | `"lean_mode": "coinbase_only"`   |
| 200-500 PH   | 0.05-0.5 BCH | Top_5          | `"lean_mode": "top_n", "lean_maxtx": 5` |
| 200-500 PH   | > 0.5 BCH    | Normal         | `"lean_blocks": false`            |
| 500+ PH      | < 0.1 BCH    | Coinbase_only  | `"lean_mode": "coinbase_only"`   |
| 500+ PH      | > 0.1 BCH    | Top_10         | `"lean_mode": "top_n", "lean_maxtx": 10` |

**Note:** These are guidelines based on typical BCH network conditions. Adjust based on your specific situation and competition.

#### Real-World Example

A successful BCH miner achieves 5+ blocks/hour using a strategy similar to top_n mode with ~10-20 transactions, sacrificing ~0.0006 BCH in fees per block to dramatically increase block discovery rate.

#### Testing Status

✅ **Fully Tested on Regtest:**
- Normal mode (full blocks) - Working perfectly
- Coinbase-only mode (empty blocks) - Working perfectly  
- Top-N mode (5 transactions) - Working perfectly
- Size-cap mode - Working perfectly
- No "bad-cb-amount" errors
- Successful block acceptance in all modes

⏳ **Pending Testnet Validation:**
- Currently syncing testnet nodes (ETA: ~2 hours)
- Node 1 (10.0.1.238): 14.68% synced
- Node 2 (10.0.0.61): 12.39% synced
- Will validate all lean modes on testnet
- Production deployment after testnet confirmation

## 🚦 BCH Node Setup

### Enable ZMQ in bitcoin.conf

```ini
# RPC Settings
rpcuser=yourusername
rpcpassword=yourpassword
rpcallowip=10.0.0.0/8
rpcbind=0.0.0.0

# ZMQ Settings (Required for fast block detection)
zmqpubhashblock=tcp://0.0.0.0:28333

# Mining Optimizations
maxmempool=2000
dbcache=4096
```

### Firewall Configuration

```bash
# On BCH nodes - allow ZMQ connections
sudo ufw allow 28333/tcp comment 'ZMQ block notifications'
sudo ufw allow from POOL_SERVER_IP to any port 8332 comment 'BCH RPC'

# On pool server - allow miner connections
sudo ufw allow 3333/tcp comment 'Stratum mining port'
```

## 🏃 Running the Pool

### Start the Pool

```bash
cd ~/ckpool
./start-ckpool.sh

# Or with systemd
sudo systemctl start ckpool
```

### Monitor Operations

```bash
# View logs
tail -f ~/ckpool/logs/ckpool.log

# Check statistics
./ckpmsg -s /tmp/ckpool/stratifier stats

# View connected workers
./ckpmsg -s /tmp/ckpool/stratifier users

# Monitor lean blocks performance (if enabled)
grep "LEAN_BLOCK" ~/ckpool/logs/ckpool.log | tail -20

# Check lean blocks statistics
grep "LEAN_BLOCK" ~/ckpool/logs/ckpool.log | awk '{
    for(i=1; i<=NF; i++) {
        if($i ~ /kept_tx=/) kept=substr($i,9)
        if($i ~ /fees_dropped=/) dropped=substr($i,14)
    }
    total+=dropped
} END { printf "Total fees sacrificed: %.8f BCH\n", total }'
```

### Stop the Pool

```bash
./stop-ckpool.sh

# Or with systemd
sudo systemctl stop ckpool
```

## 🔧 Troubleshooting

### ZMQ Connection Issues

1. **Check if ZMQ is enabled on BCH node:**
   ```bash
   bitcoin-cli getzmqnotifications
   ```

2. **Test ZMQ connectivity:**
   ```bash
   ./test-zmq-connection.sh
   ```

3. **Verify firewall rules:**
   ```bash
   sudo ufw status | grep 28333
   ```

### Performance Tuning

```bash
# Fix buffer size warnings
sudo ./tune-system.sh

# Increase system limits
ulimit -n 1048576
```

## 📊 API Commands

CKPool uses Unix sockets for administration:

```bash
# Pool statistics
./ckpmsg -s /tmp/ckpool/stratifier stats

# User information
./ckpmsg -s /tmp/ckpool/stratifier users

# Worker details
./ckpmsg -s /tmp/ckpool/stratifier workers

# Change log level
./ckpmsg -s /tmp/ckpool/pool loglevel=debug
```

## 🏗️ Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  BCH Node 1 │     │  BCH Node 2 │     │  BCH Node N │
│  RPC:8332   │     │  RPC:8332   │     │  RPC:8332   │
│  ZMQ:28333  │     │  ZMQ:28333  │     │  ZMQ:28333  │
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                   │
       └───────────────────┴───────────────────┘
                           │
                    ┌──────┴──────┐
                    │   CKPool    │
                    │  Generator  │ ← Block Templates
                    │  Stratifier │ ← Share Validation
                    │  Connector  │ ← Client Connections
                    └──────┬──────┘
                           │
                    ┌──────┴──────┐
                    │  Port 3333  │
                    └──────┬──────┘
                           │
         ┌─────────────────┼─────────────────┐
         │                 │                 │
    ┌────┴────┐      ┌────┴────┐      ┌────┴────┐
    │ ASIC 1  │      │ ASIC 2  │      │ ASIC N  │
    └─────────┘      └─────────┘      └─────────┘
```

## 🤝 Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Test thoroughly with BCH mainnet/testnet
4. Submit a pull request

## 📝 License

GNU Public License V3. See [COPYING](COPYING) for details.

## 🙏 Credits

- **Original CKPool**: Con Kolivas and the CKPool team
- **EloPool Fork**: Enhanced for Bitcoin Cash by the EloPool team
- **Multi-Node ZMQ**: Implemented for enterprise BCH mining operations

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/skaisser/ckpool/issues)
- **Documentation**: [Wiki](https://github.com/skaisser/ckpool/wiki)

---

*EloPool - Enterprise-grade Bitcoin Cash mining pool software*