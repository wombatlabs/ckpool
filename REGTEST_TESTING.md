# Regtest Testing Guide for EloPool Lean Blocks

## Overview
This guide explains how to test the lean blocks feature using Bitcoin Cash regtest mode with your existing nodes.

## Node Configuration

### Node 1 (10.0.0.61)
- **Config**: `~/bch/bitcoin.conf`
- **CLI**: `bch-cli`
- **Process**: `/usr/local/bin/bitcoind-bch`
- **Data Dir**: `/pooldb/blockchain/bch`

### Node 2 (10.0.1.238)
- **Config**: `~/.bitcoin/bitcoin.conf`
- **CLI**: `bitcoin-cli`
- **Process**: `/usr/local/bin/bitcoind`

## Setting Up Regtest Mode

### Step 1: Stop Current Mainnet Nodes

**On Node 1 (10.0.0.61):**
```bash
bch-cli stop
```

**On Node 2 (10.0.1.238):**
```bash
bitcoin-cli stop
```

### Step 2: Create Regtest Configuration

**On Node 1 (10.0.0.61):**
```bash
# Create regtest config
cat > ~/bch/bitcoin-regtest.conf << 'EOF'
# Regtest mode
regtest=1
daemon=1

# RPC settings
rpcuser=skaisser
rpcpassword=Leprechal22
rpcport=18332
rpcallowip=10.0.0.0/8
rpcbind=0.0.0.0

# Mining settings
blockmaxsize=32000000
blockmintxfee=0.00001

# ZMQ notifications (for pool)
zmqpubhashblock=tcp://0.0.0.0:28333
zmqpubrawblock=tcp://0.0.0.0:28334

# Network
listen=1
server=1
port=18444
addnode=10.0.1.238:18444

# Logging
debug=rpc
debug=zmq
EOF

# Start in regtest mode
/usr/local/bin/bitcoind-bch -conf=~/bch/bitcoin-regtest.conf -datadir=/tmp/bch-regtest
```

**On Node 2 (10.0.1.238):**
```bash
# Create regtest config
cat > ~/.bitcoin/bitcoin-regtest.conf << 'EOF'
# Regtest mode
regtest=1
daemon=1

# RPC settings
rpcuser=skaisser
rpcpassword=Leprechal22
rpcport=18332
rpcallowip=10.0.0.0/8
rpcbind=0.0.0.0

# Mining settings
blockmaxsize=32000000
blockmintxfee=0.00001

# ZMQ notifications (for pool)
zmqpubhashblock=tcp://0.0.0.0:28333
zmqpubrawblock=tcp://0.0.0.0:28334

# Network
listen=1
server=1
port=18444
addnode=10.0.0.61:18444

# Logging
debug=rpc
debug=zmq
EOF

# Start in regtest mode
/usr/local/bin/bitcoind -conf=~/.bitcoin/bitcoin-regtest.conf -datadir=/tmp/bch-regtest2
```

### Step 3: Create Pool Configuration for Regtest

**On Pool Server (10.0.0.144):**
```bash
cat > ~/ckpool/configs/ckpool-regtest.conf << 'EOF'
{
    "btcd": [
        {
            "url": "10.0.0.61:18332",
            "auth": "skaisser",
            "pass": "Leprechal22",
            "zmqnotify": "tcp://10.0.0.61:28333"
        },
        {
            "url": "10.0.1.238:18332",
            "auth": "skaisser",
            "pass": "Leprechal22",
            "zmqnotify": "tcp://10.0.1.238:28333"
        }
    ],
    "btcaddress": "bchreg:qp3wjpa3tjkj84rn8v5ry2mchgzavckj3qg9wvj0ym",
    "btcsig": "/EloPool Regtest/",
    "pooladdress": "bchreg:qp3wjpa3tjkj84rn8v5ry2mchgzavckj3qg9wvj0ym",
    "poolfee": 0,
    "blockpoll": 1,
    "update_interval": 1,
    "serverurl": [
        "0.0.0.0:3333"
    ],
    "logdir": "logs",
    "mindiff": 0.001,
    "startdiff": 0.001,
    "maxdiff": 1,
    "lean_blocks": true,
    "lean_mode": "top_n",
    "lean_maxtx": 5,
    "lean_maxsize_kb": 10,
    "dual_submit": true,
    "aggressive_preflight": true
}
EOF
```

## Testing Procedure

### Step 1: Initialize Regtest Chain

**On Node 1 (10.0.0.61):**
```bash
# Generate initial blocks
bch-cli -conf=~/bch/bitcoin-regtest.conf -regtest generate 101

# Check balance (should have mature coins)
bch-cli -conf=~/bch/bitcoin-regtest.conf -regtest getbalance
```

### Step 2: Create Test Transactions

Create a script to generate transactions:

```bash
cat > ~/generate-test-txs.sh << 'EOF'
#!/bin/bash

# Configuration
NODE1_CLI="bch-cli -conf=~/bch/bitcoin-regtest.conf -regtest"
NUM_TXS=${1:-20}

echo "Generating $NUM_TXS test transactions..."

# Get a new address for each transaction
for i in $(seq 1 $NUM_TXS); do
    ADDR=$($NODE1_CLI getnewaddress)
    AMOUNT=$(echo "scale=8; 0.001 + $i * 0.0001" | bc)
    TXID=$($NODE1_CLI sendtoaddress $ADDR $AMOUNT)
    echo "TX $i: $TXID (${AMOUNT} BCH)"
done

echo "Mempool size:"
$NODE1_CLI getmempoolinfo
EOF

chmod +x ~/generate-test-txs.sh
```

### Step 3: Start Pool with Regtest Config

**On Pool Server (10.0.0.144):**
```bash
# Stop current pool
pkill -f ckpool

# Start with regtest config
cd ~/ckpool
./ckpool -c configs/ckpool-regtest.conf
```

### Step 4: Test Lean Blocks Behavior

#### Test 1: Empty Blocks (coinbase_only)
```bash
# Update config for empty blocks
sed -i 's/"lean_mode": "top_n"/"lean_mode": "coinbase_only"/' ~/ckpool/configs/ckpool-regtest.conf

# Restart pool
pkill -f ckpool && sleep 2
./ckpool -c configs/ckpool-regtest.conf

# Generate transactions on Node 1
ssh 10.0.0.61 "~/generate-test-txs.sh 50"

# Mine a block (on Node 1)
ssh 10.0.0.61 "bch-cli -conf=~/bch/bitcoin-regtest.conf -regtest generate 1"

# Check logs for LEAN_BLOCK entries
grep "LEAN_BLOCK" logs/ckpool.log | tail -5
```

#### Test 2: Top-N Transactions
```bash
# Update config for top-5 transactions
sed -i 's/"lean_mode": "coinbase_only"/"lean_mode": "top_n"/' ~/ckpool/configs/ckpool-regtest.conf

# Restart pool
pkill -f ckpool && sleep 2
./ckpool -c configs/ckpool-regtest.conf

# Generate varied fee transactions
ssh 10.0.0.61 << 'EOF'
NODE1_CLI="bch-cli -conf=~/bch/bitcoin-regtest.conf -regtest"
# High fee txs
for i in {1..3}; do
    ADDR=$($NODE1_CLI getnewaddress)
    $NODE1_CLI settxfee 0.001
    $NODE1_CLI sendtoaddress $ADDR 0.1
done
# Low fee txs
for i in {1..10}; do
    ADDR=$($NODE1_CLI getnewaddress)
    $NODE1_CLI settxfee 0.00001
    $NODE1_CLI sendtoaddress $ADDR 0.1
done
$NODE1_CLI getmempoolinfo
EOF

# Check pool template
grep "Top-.*mode - kept" logs/ckpool.log | tail -5
```

#### Test 3: Size-Capped Blocks
```bash
# Update config for size cap (10KB)
sed -i 's/"lean_mode": "top_n"/"lean_mode": "size_cap"/' ~/ckpool/configs/ckpool-regtest.conf

# Restart pool
pkill -f ckpool && sleep 2
./ckpool -c configs/ckpool-regtest.conf

# Generate large transactions
ssh 10.0.0.61 << 'EOF'
NODE1_CLI="bch-cli -conf=~/bch/bitcoin-regtest.conf -regtest"
# Create multi-output transactions (larger size)
for i in {1..5}; do
    OUTPUTS=""
    for j in {1..20}; do
        ADDR=$($NODE1_CLI getnewaddress)
        OUTPUTS="$OUTPUTS \"$ADDR\":0.001,"
    done
    OUTPUTS=${OUTPUTS%,}  # Remove trailing comma
    $NODE1_CLI sendmany "" "{$OUTPUTS}"
done
$NODE1_CLI getmempoolinfo
EOF

# Check size-based pruning
grep "Size-cap.*mode" logs/ckpool.log | tail -5
```

### Step 5: Test Dual Submit

```bash
# Monitor both nodes for block submissions
# Terminal 1 (Node 1):
ssh 10.0.0.61 "tail -f /tmp/bch-regtest/debug.log | grep -E 'AcceptBlock|submitblock'"

# Terminal 2 (Node 2):
ssh 10.0.1.238 "tail -f /tmp/bch-regtest2/debug.log | grep -E 'AcceptBlock|submitblock'"

# Terminal 3 (Pool):
tail -f ~/ckpool/logs/ckpool.log | grep -E "DUAL_SUBMIT|Submitted block"
```

### Step 6: Simulate Mining

Use CPU miner to actually mine blocks:

```bash
# Install minerd if not available
if ! command -v minerd &> /dev/null; then
    cd /tmp
    wget https://github.com/pooler/cpuminer/releases/download/v2.5.1/pooler-cpuminer-2.5.1-linux-x86_64.tar.gz
    tar xzf pooler-cpuminer-2.5.1-linux-x86_64.tar.gz
    sudo cp minerd /usr/local/bin/
fi

# Start mining (very low difficulty in regtest)
minerd -a sha256d -o stratum+tcp://10.0.0.144:3333 -u testworker -p x --no-longpoll
```

## Monitoring and Validation

### Check Lean Blocks Statistics
```bash
# On pool server
cd ~/ckpool

# Overall stats
grep "LEAN_BLOCK" logs/ckpool.log | wc -l  # Total lean blocks
grep "LEAN_BLOCK" logs/ckpool.log | tail -10  # Recent lean blocks

# Analyze pruning effectiveness
grep "LEAN_BLOCK" logs/ckpool.log | awk '{
    for(i=1; i<=NF; i++) {
        if($i ~ /kept_tx=/) {kept=substr($i,9)}
        if($i ~ /dropped_tx=/) {dropped=substr($i,12)}
        if($i ~ /fees_kept=/) {fkept=substr($i,11)}
        if($i ~ /fees_dropped=/) {fdropped=substr($i,14)}
    }
    total_tx = kept + dropped
    if(total_tx > 0) {
        pct = (dropped/total_tx)*100
        printf "Kept: %d, Dropped: %d (%.1f%%), Fees kept: %.8f, Fees lost: %.8f\n", 
               kept, dropped, pct, fkept, fdropped
    }
}'
```

### Verify Dual Submit
```bash
# Check if both nodes received blocks
ssh 10.0.0.61 "bch-cli -conf=~/bch/bitcoin-regtest.conf -regtest getblockcount"
ssh 10.0.1.238 "bitcoin-cli -conf=~/.bitcoin/bitcoin-regtest.conf -regtest getblockcount"

# Check for dual submit in logs
grep "DUAL_SUBMIT" logs/ckpool.log | tail -10
```

## Reverting to Mainnet

After testing, return to mainnet:

```bash
# Stop regtest nodes
ssh 10.0.0.61 "bch-cli -conf=~/bch/bitcoin-regtest.conf -regtest stop"
ssh 10.0.1.238 "bitcoin-cli -conf=~/.bitcoin/bitcoin-regtest.conf -regtest stop"

# Clean regtest data
ssh 10.0.0.61 "rm -rf /tmp/bch-regtest"
ssh 10.0.1.238 "rm -rf /tmp/bch-regtest2"

# Restart mainnet nodes
ssh 10.0.0.61 "/usr/local/bin/bitcoind-bch -daemon -datadir=/pooldb/blockchain/bch"
ssh 10.0.1.238 "/usr/local/bin/bitcoind -daemon"

# Restart pool with mainnet config
pkill -f ckpool
cd ~/ckpool
./start-lean.sh  # or ./start-normal.sh
```

## Expected Results

### Coinbase-Only Mode
- Blocks contain only coinbase transaction
- Zero fees collected
- Fastest block template generation
- Logs show: "kept_tx=0 dropped_tx=X"

### Top-N Mode
- Blocks contain top N highest-fee transactions
- Most valuable fees preserved
- Logs show: "Top-N mode - kept X tx"

### Size-Cap Mode
- Blocks limited to specified size
- Includes transactions until size limit
- Logs show: "Size-cap mode - X bytes"

### Dual Submit
- Both nodes receive block submissions
- Second node may show "duplicate" (normal)
- Provides redundancy for block propagation

## Troubleshooting

### Node Connection Issues
```bash
# Test RPC connectivity
curl --user skaisser:Leprechal22 --data-binary '{"jsonrpc":"1.0","id":"test","method":"getblockcount","params":[]}' -H 'content-type:text/plain;' http://10.0.0.61:18332/
```

### ZMQ Not Working
```bash
# Check if ZMQ port is listening
nc -zv 10.0.0.61 28333
nc -zv 10.0.1.238 28333
```

### Pool Not Getting Work
```bash
# Check generator process
tail -f logs/ckpool.log | grep generator
```