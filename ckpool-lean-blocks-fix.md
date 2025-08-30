# PRD - CKPool Fork Lean Blocks Complete Fix

**Version:** 3.0 - CKPool Specific  
**Date:** August 30, 2025  
**Target:** CKPool Fork Implementation  
**Priority:** CRITICAL - Blocks being rejected

---

## Overview

This PRD provides specific fixes for the ckpool fork to properly implement lean blocks functionality. The implementation must handle configuration parsing, template modification, and coinbase generation correctly.

---

## 1. Configuration Parsing (ckpool.c)

### Add to config structure
```c
// In ckpool.h - add to struct ckpool
bool lean_blocks;           // Default: false
char *lean_mode;           // Default: "disabled"
int lean_maxtx;            // Default: 0
int lean_maxsize_kb;       // Default: 10
bool dual_submit;          // Default: false
bool aggressive_preflight; // Default: false
```

### Parse configuration
```c
// In ckpool.c - parse_config() function
static bool parse_config(ckpool_t *ckp)
{
    // ... existing code ...
    
    // Lean blocks configuration - DEFAULT TO FALSE
    json_t *lean_val = json_object_get(json_conf, "lean_blocks");
    if (lean_val && json_is_boolean(lean_val)) {
        ckp->lean_blocks = json_is_true(lean_val);
    } else {
        ckp->lean_blocks = false; // DEFAULT FALSE
    }
    
    if (ckp->lean_blocks) {
        // Only parse other lean options if enabled
        json_get_string(&ckp->lean_mode, json_conf, "lean_mode");
        if (!ckp->lean_mode) {
            ckp->lean_mode = strdup("top_n"); // Default mode
        }
        
        json_get_int(&ckp->lean_maxtx, json_conf, "lean_maxtx");
        if (ckp->lean_maxtx <= 0) {
            ckp->lean_maxtx = 5; // Default 5 transactions
        }
        
        json_get_int(&ckp->lean_maxsize_kb, json_conf, "lean_maxsize_kb");
        if (ckp->lean_maxsize_kb <= 0) {
            ckp->lean_maxsize_kb = 10; // Default 10KB
        }
        
        // Log configuration
        LOGNOTICE("Lean blocks enabled: mode=%s maxtx=%d maxsize=%dKB",
                  ckp->lean_mode, ckp->lean_maxtx, ckp->lean_maxsize_kb);
    } else {
        LOGNOTICE("Lean blocks disabled (normal mining mode)");
    }
    
    // ... rest of config parsing ...
}
```

---

## 2. Template Processing (bitcoin.c/generator.c)

### Find the parse_gbtbase() or similar function
```c
// In bitcoin.c - where getblocktemplate response is processed
static bool parse_gbtbase(connsock_t *cs, gbtbase_t *gbt, json_t *res_val)
{
    // ... existing parsing code ...
    
    // After parsing the template, apply lean mode if enabled
    if (ckp->lean_blocks) {
        apply_lean_mode_to_template(ckp, res_val, gbt);
    }
    
    // ... continue with normal processing ...
}

// New function to modify template for lean mode
static void apply_lean_mode_to_template(ckpool_t *ckp, json_t *template_json, gbtbase_t *gbt)
{
    json_t *transactions = json_object_get(template_json, "transactions");
    int64_t coinbasevalue = json_integer_value(json_object_get(template_json, "coinbasevalue"));
    
    // Calculate total fees in original template
    int64_t total_fees = 0;
    size_t n_txs = json_array_size(transactions);
    
    for (size_t i = 0; i < n_txs; i++) {
        json_t *tx = json_array_get(transactions, i);
        json_t *fee_val = json_object_get(tx, "fee");
        if (fee_val) {
            total_fees += json_integer_value(fee_val);
        }
    }
    
    // Calculate block subsidy
    int64_t subsidy = coinbasevalue - total_fees;
    
    // Create new transaction array
    json_t *new_transactions = json_array();
    int64_t kept_fees = 0;
    size_t kept_count = 0;
    
    if (strcmp(ckp->lean_mode, "coinbase_only") == 0) {
        // Keep no transactions
        kept_count = 0;
        kept_fees = 0;
    } else if (strcmp(ckp->lean_mode, "top_n") == 0) {
        // Keep first N transactions (DO NOT SORT - maintain dependency order)
        size_t max_keep = ckp->lean_maxtx;
        if (max_keep > n_txs) max_keep = n_txs;
        
        for (size_t i = 0; i < max_keep; i++) {
            json_t *tx = json_array_get(transactions, i);
            json_array_append_new(new_transactions, json_deep_copy(tx));
            
            json_t *fee_val = json_object_get(tx, "fee");
            if (fee_val) {
                kept_fees += json_integer_value(fee_val);
            }
            kept_count++;
        }
    }
    
    // CRITICAL: Calculate new coinbase value
    int64_t new_coinbasevalue = subsidy + kept_fees;
    
    // Update the template JSON
    json_object_set_new(template_json, "transactions", new_transactions);
    json_object_set_new(template_json, "coinbasevalue", json_integer(new_coinbasevalue));
    
    // ALSO update the gbtbase structure if it stores coinbasevalue
    gbt->coinbasevalue = new_coinbasevalue;
    
    // Calculate size for logging
    double size_kb = 0;
    for (size_t i = 0; i < kept_count; i++) {
        json_t *tx = json_array_get(new_transactions, i);
        const char *data = json_string_value(json_object_get(tx, "data"));
        if (data) {
            size_kb += strlen(data) / 2048.0; // hex to KB
        }
    }
    
    LOGNOTICE("LEAN_BLOCK: mode=%s kept_tx=%zu dropped_tx=%zu size=%.2fKB "
              "fees_kept=%.8f fees_dropped=%.8f coinbase_was=%lld coinbase_now=%lld",
              ckp->lean_mode, kept_count, n_txs - kept_count, size_kb,
              kept_fees / 100000000.0, (total_fees - kept_fees) / 100000000.0,
              coinbasevalue, new_coinbasevalue);
}
```

---

## 3. Coinbase Generation (stratifier.c)

### Find where coinbase is generated
```c
// In stratifier.c - look for gbt_coinbase() or similar
static void gbt_coinbase(ckpool_t *ckp, workbase_t *wb, json_t *coinbase_aux)
{
    // ... existing code ...
    
    // CRITICAL: Use the modified coinbasevalue from lean processing
    uint64_t coinbasevalue = wb->coinbasevalue; // This MUST be the adjusted value
    
    // Build coinbase with correct value
    // The coinbase outputs must total exactly coinbasevalue
    
    // ... rest of coinbase generation ...
    
    LOGDEBUG("Generated coinbase with value %llu", coinbasevalue);
}
```

---

## 4. Debugging Additions

Add these debug logs to track the issue:

```c
// In template processing
LOGWARNING("LEAN_DEBUG: Original coinbase=%lld, total_fees=%lld, subsidy=%lld",
           coinbasevalue, total_fees, subsidy);
LOGWARNING("LEAN_DEBUG: Kept %zu txs with fees=%lld, new_coinbase should be %lld",
           kept_count, kept_fees, subsidy + kept_fees);

// In coinbase generation
LOGWARNING("LEAN_DEBUG: Generating coinbase with value=%llu", wb->coinbasevalue);

// Before block submission
LOGWARNING("LEAN_DEBUG: Submitting block with %d transactions", wb->txn_count);
```

---

## 5. Configuration Examples

### Normal mining (default)
```json
{
    "btcd": [...],
    "lean_blocks": false
}
```

### Lean mining (top 5)
```json
{
    "btcd": [...],
    "lean_blocks": true,
    "lean_mode": "top_n",
    "lean_maxtx": 5
}
```

### Coinbase only
```json
{
    "btcd": [...],
    "lean_blocks": true,
    "lean_mode": "coinbase_only"
}
```

---

## 6. Critical Implementation Notes

1. **Default to false**: If `lean_blocks` is not in config, it MUST default to false
2. **Don't sort transactions**: Bitcoin Core provides them in dependency order
3. **Update coinbase value**: Both in JSON and internal structures
4. **Test normal mode**: Ensure normal mining still works when `lean_blocks: false`

---

## 7. Testing Steps

1. Start with `lean_blocks: false` - verify normal mining works
2. Enable `lean_blocks: true` with `top_n` mode
3. Check logs for "LEAN_DEBUG" messages
4. Verify submitted blocks have correct coinbase value
5. Test `coinbase_only` mode once `top_n` works

---

## 8. Expected Log Output

When working correctly:
```
LEAN_BLOCK: mode=top_n kept_tx=5 dropped_tx=15 size=2.50KB fees_kept=0.00002000 fees_dropped=0.00008000 coinbase_was=625002000 coinbase_now=625002000
BLOCK ACCEPTED!
```

If still broken, you'll see:
```
LEAN_DEBUG: Original coinbase=625010000, total_fees=10000, subsidy=625000000
LEAN_DEBUG: Kept 5 txs with fees=2000, new_coinbase should be 625002000
SUBMIT BLOCK RETURNED: bad-cb-amount
```

This will show exactly where the value mismatch occurs.