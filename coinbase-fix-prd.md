# PRD - Fix Coinbase Calculation for Lean Blocks

**Version:** 1.0  
**Date:** August 30, 2025  
**Priority:** CRITICAL - Blocks are being rejected  
**Issue:** `bad-cb-amount` error when mining with lean blocks

---

## Problem Statement

When using lean blocks mode (both `coinbase_only` and `top_n`), mined blocks are rejected by the Bitcoin Cash network with error `bad-cb-amount`. This occurs because the coinbase transaction claims fees for transactions that were removed from the block template.

### Current Behavior (INCORRECT)
```
Original template: 20 transactions, 0.00009939 BCH total fees
Lean template: 5 transactions kept, 0.00002595 BCH fees kept
Coinbase value: Still claims 0.00009939 BCH in fees (WRONG!)
Result: Block rejected - coinbase claims more fees than included transactions
```

### Expected Behavior (CORRECT)
```
Original template: 20 transactions, 0.00009939 BCH total fees
Lean template: 5 transactions kept, 0.00002595 BCH fees kept
Coinbase value: Should claim only 0.00002595 BCH in fees
Result: Block accepted
```

---

## Root Cause

The lean block code is not recalculating the coinbase value after removing transactions. The coinbase value MUST equal:

```
coinbase_value = block_subsidy + sum_of_fees_from_included_transactions_only
```

---

## Solution

### 1. Fix in `build_lean_template()` function

```c
bool build_lean_template(const Template *in, Template *out, const Config *cfg) {
    // Copy template
    *out = *in;
    out->transactions.clear();
    
    // Calculate original fees
    uint64_t total_fees_original = 0;
    for (int i = 0; i < in->transactions.count; i++) {
        total_fees_original += in->transactions[i].fee;
    }
    
    // Get block subsidy (coinbase minus fees)
    uint64_t block_subsidy = in->coinbasevalue - total_fees_original;
    
    // Select transactions based on mode
    vector<Tx> kept_transactions;
    switch (cfg->lean_mode) {
        case COINBASE_ONLY:
            // Keep no transactions
            break;
            
        case TOP_N:
            kept_transactions = select_top_n_by_feerate(in->transactions, cfg->lean_maxtx);
            break;
            
        case SIZE_CAP:
            kept_transactions = pack_by_feerate_until_size(in->transactions, cfg->lean_maxsize_kb * 1024);
            break;
    }
    
    // Calculate fees from KEPT transactions only
    uint64_t kept_fees = 0;
    for (int i = 0; i < kept_transactions.count; i++) {
        kept_fees += kept_transactions[i].fee;
    }
    
    // CRITICAL FIX: Set coinbase value to subsidy + kept fees ONLY
    out->coinbasevalue = block_subsidy + kept_fees;
    
    // Store kept transactions
    out->transactions = kept_transactions;
    
    // Log the adjustment
    LOGNOTICE("COINBASE_FIX: Original coinbase=%llu subsidy=%llu kept_fees=%llu new_coinbase=%llu",
              in->coinbasevalue, block_subsidy, kept_fees, out->coinbasevalue);
    
    return true;
}
```

### 2. Update Coinbase Generation

Ensure the coinbase transaction is rebuilt with the corrected value:

```c
// In the code that builds the actual coinbase transaction
void rebuild_coinbase(Template *template) {
    // Use the ADJUSTED coinbasevalue from the lean template
    uint64_t value = template->coinbasevalue;  // This is now correct
    
    // Build coinbase transaction with correct value
    CTransaction *coinbase = create_coinbase_transaction(
        value,
        template->height,
        template->coinbase_payload
    );
    
    template->coinbase_hex = transaction_to_hex(coinbase);
}
```

### 3. Add Validation

Add a sanity check before submitting:

```c
bool validate_coinbase_amount(const Template *template) {
    uint64_t total_fees = 0;
    for (int i = 0; i < template->transactions.count; i++) {
        total_fees += template->transactions[i].fee;
    }
    
    // Get expected subsidy for this height
    uint64_t expected_subsidy = get_block_subsidy(template->height);
    uint64_t expected_coinbase = expected_subsidy + total_fees;
    
    if (template->coinbasevalue != expected_coinbase) {
        LOGERR("COINBASE MISMATCH: have=%llu expected=%llu (subsidy=%llu fees=%llu)",
               template->coinbasevalue, expected_coinbase, expected_subsidy, total_fees);
        return false;
    }
    
    return true;
}
```

---

## Testing

### Regtest Testing
1. Mine a block with `top_n:5` mode
2. Verify block is accepted (no `bad-cb-amount` error)
3. Check block contents have exactly 5 transactions plus coinbase
4. Verify coinbase value = subsidy + sum(fees of 5 transactions)

### Validation Commands
```bash
# Get block and check coinbase value
bitcoin-cli -regtest getblock <blockhash> 2

# Verify coinbase output value matches expected
# coinbase_output_value should equal:
# - 6.25 BCH (regtest subsidy after halving)
# - Plus sum of fees from included transactions only
```

---

## Regression Test

Create automated test that:
1. Gets template with known transactions and fees
2. Applies lean mode to keep specific transactions
3. Verifies coinbase value is recalculated correctly
4. Submits block and confirms acceptance

---

## Emergency Hotfix

If you need to disable lean blocks until fixed:
```json
{
    "lean_blocks": false
}
```

This will revert to normal mining while you fix the coinbase calculation.

---

## Implementation Status

### Tasks Completed
- [x] Identify root cause: coinbase value not recalculated after pruning transactions
- [x] Fix location identified: `src/lean.c:184-188` already has the fix!
- [x] Add debug logging to track coinbase adjustments
- [x] Add validation function `validate_coinbase_amount()`
- [x] Enhanced logging shows: Original, Subsidy, TotalFees, KeptFees, New values

### Fix Details
The fix was already present in `build_lean_template()` at lines 184-188:
```c
/* Adjust coinbase value - CRITICAL FIX for bad-cb-amount */
coinbasevalue = json_integer_value(json_object_get(full_template, "coinbasevalue"));
subsidy = coinbasevalue - total_fees;
uint64_t new_coinbasevalue = subsidy + kept_fees;
json_object_set_new(lean_template, "coinbasevalue", json_integer(new_coinbasevalue));
```

### Testing Required
- [ ] Rebuild ckpool with the fix
- [ ] Test coinbase_only mode (should have coinbase = subsidy only)
- [ ] Test top_n mode (should have coinbase = subsidy + kept_fees)
- [ ] Verify no more "bad-cb-amount" errors
- [ ] Check COINBASE_FIX log entries show correct calculations