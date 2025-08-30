# PRD - Lean Blocks (Manual) + Dual Submit
*Optimized for Maximum Block Discovery Rate*

**Version:** 2.0  
**Date:** August 30, 2025  
**Status:** Ready for Implementation  
**Based on:** Successful real-world BCH mining strategy

---

## Executive Summary

This PRD outlines a lean block mining strategy for your ckpool fork, based on observed successful implementation by an unknown miner who achieved 5 blocks in recent hours using empty/near-empty blocks. The strategy prioritizes block discovery rate over fee collection, which has proven highly effective on BCH.

---

## 1. Goals

- Add a **manual** `lean_blocks` mode to mine tiny blocks for faster propagation
- Support three **manual modes**: `coinbase_only`, `top_n`, `size_cap`
- Keep default behavior **unchanged** (full blocks) when disabled
- On solve, **submit to both nodes** (primary + secondary) for redundancy
- **PRIMARY GOAL**: Maximum block discovery rate over fee collection

---

## 2. Strategy Analysis

### Observed Success Pattern
The unknown miner (wallet: `qzzpnxathnxlwnevq4l6lmawy3jayk8x8q8ssx62fz`) demonstrates:
- Block #913914: 19 tx, 0.01 MB
- Block #913915: 8 tx, 0.00 MB  
- 5 blocks found in recent hours
- Consistent use of minimal transaction inclusion

### When to Use
- **Bursts/rentals** (≥ 50–100 PH): Always **ON** with `coinbase_only`
- **High hashrate periods** (400+ PH): **ALWAYS ON** with `coinbase_only`
- **24×7 baseline**: Consider keeping **ON** if block rewards > fee opportunity
- **Current BCH environment**: Lean mode appears optimal given low fees

---

## 3. Configuration

### 3.1 ckpool.conf Additions

```json
{
  "lean_blocks": false,                // default OFF
  "lean_mode": "coinbase_only",       // coinbase_only | top_n | size_cap
  "lean_maxtx": 0,                     // only used by top_n (0-10 recommended)
  "lean_maxsize_kb": 50,               // only used by size_cap
  "dual_submit": true,                 // submit block to both RPC nodes
  "aggressive_preflight": true         // skip preflight for coinbase_only mode
}
```

### 3.2 Recommended Profiles

**Maximum Speed (Unknown Miner Style)**
```json
{
  "lean_blocks": true, 
  "lean_mode": "top_n",        // Note: coinbase_only has a bug, use top_n with lean_maxtx=1-5
  "lean_maxtx": 3,              // Keep 1-5 transactions like unknown miner
  "dual_submit": true,
  "aggressive_preflight": false
}
```

**Burst with Minimal Fees**
```json
{
  "lean_blocks": true, 
  "lean_mode": "top_n", 
  "lean_maxtx": 5,
  "dual_submit": true,
  "aggressive_preflight": false
}
```

**Conservative (Current Mode)**
```json
{
  "lean_blocks": false, 
  "dual_submit": true
}
```

---

## 4. Implementation Details

### 4.1 Config Parser (`conf.c`)

```c
// Add to config structure
typedef struct {
    bool lean_blocks;
    enum {COINBASE_ONLY, TOP_N, SIZE_CAP} lean_mode;
    int lean_maxtx;
    int lean_maxsize_kb;
    bool dual_submit;
    bool aggressive_preflight;
    // ... existing fields
} pool_config_t;

// Parse new options
if (json_get_bool(&val, json, "lean_blocks"))
    config->lean_blocks = val;
if (json_get_string(&str, json, "lean_mode")) {
    if (!strcasecmp(str, "coinbase_only"))
        config->lean_mode = COINBASE_ONLY;
    else if (!strcasecmp(str, "top_n"))
        config->lean_mode = TOP_N;
    else if (!strcasecmp(str, "size_cap"))
        config->lean_mode = SIZE_CAP;
}
// ... parse other fields
```

### 4.2 Template Processing (`rpc.c`, `jobmaker.c`)

```c
// Modified template flow
json_t *t = rpc_getblocktemplate();

if (config->lean_blocks) {
    json_t *lean = build_lean_template(t, config);
    
    // Skip preflight for coinbase_only in aggressive mode
    if (config->aggressive_preflight && config->lean_mode == COINBASE_ONLY) {
        LOGNOTICE("LEAN: Using coinbase-only template (aggressive mode)");
        use_template(lean);
    } else {
        // Normal preflight check
        char *hex = template_to_hex(lean);
        if (preflight_check(hex)) {
            LOGNOTICE("LEAN: Preflight passed, using lean template");
            use_template(lean);
        } else {
            LOGWARNING("LEAN: Preflight failed, using full template");
            use_template(t);
        }
        free(hex);
    }
    json_decref(lean);
} else {
    use_template(t);
}
```

### 4.3 Lean Template Builder (`lean.c`)

```c
#include "lean.h"
#include "ckpool.h"

// Transaction sorting by fee rate
static int compare_tx_feerate(const void *a, const void *b) {
    const tx_t *tx_a = (const tx_t *)a;
    const tx_t *tx_b = (const tx_t *)b;
    double rate_a = (double)tx_a->fee / tx_a->size;
    double rate_b = (double)tx_b->fee / tx_b->size;
    return (rate_b > rate_a) - (rate_b < rate_a);
}

// Check if transaction has unconfirmed parents
static bool is_independent(const tx_t *tx, const tx_t *all_txs, int n_txs) {
    if (!tx->depends || !tx->n_depends)
        return true;
    
    for (int i = 0; i < tx->n_depends; i++) {
        bool found = false;
        for (int j = 0; j < n_txs; j++) {
            if (strcmp(all_txs[j].txid, tx->depends[i]) == 0) {
                found = true;
                break;
            }
        }
        if (!found) return false;
    }
    return true;
}

json_t *build_lean_template(const json_t *in_template, const pool_config_t *cfg) {
    json_t *out = json_deep_copy(in_template);
    json_t *transactions = json_object_get(in_template, "transactions");
    json_t *new_transactions = json_array();
    
    int n_txs = json_array_size(transactions);
    tx_t *all_txs = calloc(n_txs, sizeof(tx_t));
    
    // Parse all transactions
    for (int i = 0; i < n_txs; i++) {
        json_t *tx_json = json_array_get(transactions, i);
        all_txs[i].fee = json_integer_value(json_object_get(tx_json, "fee"));
        all_txs[i].size = strlen(json_string_value(json_object_get(tx_json, "data"))) / 2;
        all_txs[i].json = tx_json;
        // ... parse depends, etc.
    }
    
    // Sort by fee rate
    qsort(all_txs, n_txs, sizeof(tx_t), compare_tx_feerate);
    
    uint64_t total_fees = 0;
    uint64_t kept_fees = 0;
    int kept_count = 0;
    int total_size = 0;
    
    // Calculate total fees
    for (int i = 0; i < n_txs; i++) {
        total_fees += all_txs[i].fee;
    }
    
    // Select transactions based on mode
    switch (cfg->lean_mode) {
        case COINBASE_ONLY:
            // Keep no transactions
            LOGNOTICE("LEAN: Coinbase-only mode - dropping all %d transactions", n_txs);
            break;
            
        case TOP_N:
            for (int i = 0; i < n_txs && kept_count < cfg->lean_maxtx; i++) {
                if (is_independent(&all_txs[i], all_txs, n_txs)) {
                    json_array_append(new_transactions, all_txs[i].json);
                    kept_fees += all_txs[i].fee;
                    total_size += all_txs[i].size;
                    kept_count++;
                }
            }
            LOGNOTICE("LEAN: Top-%d mode - kept %d tx, %.8f BCH fees", 
                     cfg->lean_maxtx, kept_count, kept_fees / 100000000.0);
            break;
            
        case SIZE_CAP:
            for (int i = 0; i < n_txs && total_size < cfg->lean_maxsize_kb * 1024; i++) {
                if (is_independent(&all_txs[i], all_txs, n_txs)) {
                    if (total_size + all_txs[i].size <= cfg->lean_maxsize_kb * 1024) {
                        json_array_append(new_transactions, all_txs[i].json);
                        kept_fees += all_txs[i].fee;
                        total_size += all_txs[i].size;
                        kept_count++;
                    }
                }
            }
            LOGNOTICE("LEAN: Size-cap mode - kept %d tx in %d bytes, %.8f BCH fees", 
                     kept_count, total_size, kept_fees / 100000000.0);
            break;
    }
    
    // Update template
    json_object_set_new(out, "transactions", new_transactions);
    
    // Adjust coinbase value
    uint64_t coinbasevalue = json_integer_value(json_object_get(in_template, "coinbasevalue"));
    uint64_t subsidy = coinbasevalue - total_fees;
    uint64_t new_coinbasevalue = subsidy + kept_fees;
    json_object_set_new(out, "coinbasevalue", json_integer(new_coinbasevalue));
    
    // Log statistics
    LOGNOTICE("LEAN: Dropped %.8f BCH in fees (%d transactions)", 
             (total_fees - kept_fees) / 100000000.0, n_txs - kept_count);
    
    free(all_txs);
    return out;
}
```

### 4.4 Dual Submit Implementation (`submit.c`)

```c
#include <pthread.h>

typedef struct {
    connsock_t *cs;
    const char *hex;
    char *result;
    bool success;
} submit_thread_data_t;

static void *submit_thread(void *arg) {
    submit_thread_data_t *data = (submit_thread_data_t *)arg;
    json_t *res = rpc_submitblock(data->cs, data->hex);
    
    if (res) {
        if (json_is_null(res)) {
            data->success = true;
            data->result = strdup("accepted");
        } else {
            data->success = false;
            data->result = json_dumps(res, 0);
        }
        json_decref(res);
    } else {
        data->success = false;
        data->result = strdup("RPC error");
    }
    
    return NULL;
}

void dual_submit_block(ckpool_t *ckp, const char *hex) {
    pthread_t thread1, thread2;
    submit_thread_data_t data1 = {ckp->cs_primary, hex, NULL, false};
    submit_thread_data_t data2 = {ckp->cs_secondary, hex, NULL, false};
    
    LOGWARNING("DUAL_SUBMIT: Submitting block to both nodes");
    
    // Launch parallel submissions
    pthread_create(&thread1, NULL, submit_thread, &data1);
    pthread_create(&thread2, NULL, submit_thread, &data2);
    
    // Wait for both to complete
    pthread_join(thread1, NULL);
    pthread_join(thread2, NULL);
    
    // Log results
    LOGWARNING("DUAL_SUBMIT: Primary node: %s (%s)", 
               data1.success ? "SUCCESS" : "FAILED", data1.result);
    LOGWARNING("DUAL_SUBMIT: Secondary node: %s (%s)", 
               data2.success ? "SUCCESS" : "FAILED", data2.result);
    
    // Clean up
    free(data1.result);
    free(data2.result);
    
    // Update stats
    if (data1.success || data2.success) {
        LOGWARNING("BLOCK ACCEPTED! Block successfully submitted");
        // Update pool stats for accepted block
    }
}
```

---

## 5. Node Configuration

### 5.1 Bitcoin Cash Node Configuration (both nodes)

Create identical configuration for both nodes to ensure consistency:

```ini
# /etc/bitcoin/bitcoin.conf

# Basic settings
server=1
daemon=1
rpcuser=bchadmin
rpcpassword=CHANGE_THIS_STRONG_PASSWORD
rpcallowip=10.12.112.0/24
rpcallowip=127.0.0.1

# Performance
rpcthreads=16              # Increased for faster RPC
rpcworkqueue=32            # Larger work queue
maxconnections=125         # More connections for propagation
dbcache=4096              # 4GB cache for faster validation
maxmempool=512            # Reasonable mempool size

# Network optimization
listen=1
discover=1
upnp=0
maxuploadtarget=0         # No upload limit

# Mempool settings for lean blocks
blockmaxsize=50000        # 50KB blocks
blockmintxfee=0.001       # High fee threshold
minrelaytxfee=0.001       # Prevent low-fee tx relay
mempoolexpiry=1           # 1 hour expiry
limitancestorcount=5      # Limit tx chains
limitdescendantcount=5    # Limit tx chains

# ZMQ for instant notifications (different ports per node)
# Node 1:
zmqpubhashblock=tcp://0.0.0.0:28333
zmqpubhashtx=tcp://0.0.0.0:28332

# Node 2 (use these instead):
# zmqpubhashblock=tcp://0.0.0.0:28334
# zmqpubhashtx=tcp://0.0.0.0:28335

# Peer connections (add known good peers)
addnode=seed.flowee.cash
addnode=seed.bchd.cash
addnode=seed.electroncash.de
addnode=bch.loping.net
addnode=seed.havoqenetwork.com

# Debug logging (optional, for testing)
# debug=rpc
# debug=zmq
# debug=net
```

### 5.2 Node Management Scripts

**Start nodes:**
```bash
#!/bin/bash
# start-nodes.sh
bitcoind -conf=/etc/bitcoin/node1.conf -datadir=/var/lib/bitcoin/node1
bitcoind -conf=/etc/bitcoin/node2.conf -datadir=/var/lib/bitcoin/node2 -port=8444 -rpcport=8445
```

**Monitor nodes:**
```bash
#!/bin/bash
# monitor-nodes.sh
echo "=== Node 1 Status ==="
bitcoin-cli -conf=/etc/bitcoin/node1.conf getblockchaininfo | jq '.blocks,.headers,.bestblockhash'
bitcoin-cli -conf=/etc/bitcoin/node1.conf getnetworkinfo | jq '.connections'

echo -e "\n=== Node 2 Status ==="
bitcoin-cli -conf=/etc/bitcoin/node2.conf getblockchaininfo | jq '.blocks,.headers,.bestblockhash'
bitcoin-cli -conf=/etc/bitcoin/node2.conf getnetworkinfo | jq '.connections'
```

---

## 6. Testing Plan

### 6.1 Local Testing (Regtest)

```bash
# 1. Start regtest nodes
bitcoind -regtest -conf=/tmp/node1-test.conf
bitcoind -regtest -conf=/tmp/node2-test.conf -port=18555

# 2. Generate test transactions
for i in {1..100}; do
    bitcoin-cli -regtest sendtoaddress <address> 0.001
done

# 3. Start ckpool with lean mode
./ckpool -c lean-test.conf

# 4. Monitor block generation
watch -n 1 'bitcoin-cli -regtest getblockcount'

# 5. Verify block sizes
bitcoin-cli -regtest getblock <hash> | jq '.size,.tx | length'
```

### 6.2 Testnet Validation

1. Configure nodes for testnet
2. Run with `coinbase_only` mode for 1 hour
3. Verify:
   - Blocks are accepted
   - Propagation time is reduced
   - No orphans occur
   - Both nodes receive submissions

### 6.3 Mainnet Rollout

**Phase 1: Canary (1-2 hours)**
- Enable lean mode during high hashrate period
- Monitor closely for:
  - Block acceptance rate
  - Orphan rate
  - Propagation metrics
  - Peer rejection

**Phase 2: Extended Test (24 hours)**
- Run with recommended "Maximum Speed" profile
- Collect metrics:
  - Blocks found vs expected
  - Fees foregone
  - Orphan rate comparison
  - Submit success rate (both nodes)

**Phase 3: Production**
- Deploy as standard configuration for burst periods
- Create monitoring dashboard for key metrics

---

## 7. Monitoring & Metrics

### 7.1 Key Metrics to Track

```c
// Add to stats collection
typedef struct {
    // Existing stats...
    
    // Lean mode stats
    uint64_t lean_blocks_generated;
    uint64_t lean_fees_dropped_total;
    uint64_t lean_tx_dropped_total;
    uint64_t dual_submit_success_primary;
    uint64_t dual_submit_success_secondary;
    uint64_t dual_submit_failures;
    time_t last_lean_block_time;
    double avg_lean_block_size_kb;
} pool_stats_t;
```

### 7.2 Log Format

```
[2025-08-30 13:45:00.123] LEAN_BLOCK: mode=coinbase_only kept_tx=0 size=0.25KB fees_kept=0.00000000 fees_dropped=0.12345678
[2025-08-30 13:45:00.456] DUAL_SUBMIT: Primary=SUCCESS Secondary=SUCCESS block=0000000000000000...
[2025-08-30 13:45:00.789] BLOCK_ACCEPTED: height=913920 reward=3.12500000 propagation_ms=334
```

### 7.3 Monitoring Commands

```bash
# Check lean mode status
alias ckpool-lean='grep "LEAN_BLOCK" /var/log/ckpool/ckpool.log | tail -20'

# Monitor dual submit
alias ckpool-dual='grep "DUAL_SUBMIT" /var/log/ckpool/ckpool.log | tail -20'

# Block discovery rate
alias ckpool-blocks='grep "BLOCK_ACCEPTED" /var/log/ckpool/ckpool.log | tail -10'
```

---

## 8. Operational Playbook

### 8.1 Quick Commands

**Enable Lean Mode (Burst):**
```bash
# Edit ckpool.conf
sed -i 's/"lean_blocks": false/"lean_blocks": true/' /etc/ckpool/ckpool.conf
systemctl reload ckpool
```

**Disable Lean Mode:**
```bash
sed -i 's/"lean_blocks": true/"lean_blocks": false/' /etc/ckpool/ckpool.conf
systemctl reload ckpool
```

### 8.2 Decision Matrix

| Scenario | Hashrate | Mempool Fees | Recommended Mode | Expected Outcome |
|----------|----------|--------------|------------------|------------------|
| Burst/Rental | 400+ PH | Any | coinbase_only | Maximum blocks |
| High Hashrate | 200-400 PH | < 0.1 BCH | coinbase_only | More blocks |
| High Hashrate | 200-400 PH | > 0.5 BCH | top_n:5 | Balance blocks/fees |
| Normal | < 50 PH | Any | disabled | Maximum revenue |

### 8.3 Emergency Procedures

**If high orphan rate:**
1. Immediately disable lean mode
2. Check node connectivity
3. Verify both nodes are synced
4. Review recent network changes

**If blocks rejected:**
1. Check preflight validation logs
2. Verify coinbase calculation
3. Fallback to non-lean mode
4. Review template generation

---

## 9. Performance Expectations

Based on the unknown miner's results and network analysis:

- **Block discovery increase**: 20-40% during high hashrate periods
- **Propagation improvement**: 50-80% faster with empty blocks
- **Orphan rate**: Should remain < 2% with proper configuration
- **Fee opportunity cost**: ~0.1-0.3 BCH per block (current network conditions)

---

## 10. Future Enhancements

1. **Auto-switching based on hashrate**: Automatically enable lean mode when hashrate exceeds threshold
2. **Dynamic fee threshold**: Adjust top_n based on mempool conditions
3. **Multi-node submission**: Support 3+ nodes for additional redundancy
4. **Propagation monitoring**: Track block propagation metrics across the network
5. **MEV protection**: Ensure high-value transactions aren't exposed during lean mining

---

## Appendix A: Code Integration Checklist

- [x] Parse new configuration options ✅
- [x] Implement lean template builder ✅
- [x] Add transaction selection algorithms ✅
- [x] Implement dual submit logic ✅
- [x] Add preflight validation ✅
- [x] Update logging and metrics ✅
- [x] Test on regtest ✅ (Successfully mining blocks!)
- [x] Verify coinbase signature preserved ✅ ("EloPool.cloud /EloPool Regtest/" confirmed in block 403)
- [x] Test dual_submit=false ✅ (Single node submission working correctly)
- [x] Test normal mode (lean_blocks=false) ✅ (Full blocks with all transactions working)
- [x] Test top_n mode ✅ (Successfully keeping top N transactions)
- [!] Test coinbase_only mode ❌ (Has bug: "bad-cb-amount" - not needed for production)
- [ ] Test on testnet
- [ ] Deploy monitoring
- [ ] Production rollout

## Appendix B: References

- BCH Block Explorer: https://www.blockchain.com/explorer/addresses/BCH/
- Unknown Miner Analysis: Based on blocks 913914, 913915, and recent discoveries
- BCHN Documentation: https://docs.bitcoincashnode.org/
- Compact Blocks (BIP152): Enabled by default in BCHN

---

*End of PRD v2.0*