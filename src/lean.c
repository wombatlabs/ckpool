/*
 * Copyright 2025 EloPool
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation; either version 3 of the License, or (at your option)
 * any later version.  See COPYING for more details.
 */

#include "config.h"

#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>

#include "ckpool.h"
#include "libckpool.h"
#include "bitcoin.h"
#include "lean.h"
#include "sha2.h"

static lean_stats_t lean_stats = {0};
static mutex_t stats_lock;

/* NOTE: Removed compare_tx_feerate function
 * We must NOT sort transactions to maintain dependency order.
 * Bitcoin Core already provides transactions in valid dependency order.
 * Sorting would break this order and cause "tx-ordering" errors. */

/* Check if transaction has unresolved dependencies */
static bool is_independent_tx(const lean_tx_t *tx, const lean_tx_t *selected, int n_selected)
{
	int i, j;
	
	if (!tx->depends || tx->n_depends == 0)
		return true;
	
	/* Check if all dependencies are in the selected set */
	for (i = 0; i < tx->n_depends; i++) {
		const char *dep_txid = json_string_value(json_array_get(tx->depends, i));
		bool found = false;
		
		for (j = 0; j < n_selected; j++) {
			if (selected[j].txid && !strcmp(selected[j].txid, dep_txid)) {
				found = true;
				break;
			}
		}
		
		if (!found)
			return false;
	}
	
	return true;
}

/* Validate coinbase amount matches included transactions */
bool validate_coinbase_amount(const json_t *template, uint64_t expected_subsidy)
{
	json_t *transactions;
	uint64_t total_fees = 0;
	uint64_t coinbasevalue;
	int i, n_txs;
	
	transactions = json_object_get(template, "transactions");
	if (!transactions || !json_is_array(transactions))
		return true; /* No transactions to validate */
	
	n_txs = json_array_size(transactions);
	for (i = 0; i < n_txs; i++) {
		json_t *tx = json_array_get(transactions, i);
		json_t *fee_val = json_object_get(tx, "fee");
		if (fee_val)
			total_fees += json_integer_value(fee_val);
	}
	
	coinbasevalue = json_integer_value(json_object_get(template, "coinbasevalue"));
	uint64_t expected_coinbase = expected_subsidy + total_fees;
	
	if (coinbasevalue != expected_coinbase) {
		LOGERR("COINBASE MISMATCH: have=%llu expected=%llu (subsidy=%llu fees=%llu)",
		       coinbasevalue, expected_coinbase, expected_subsidy, total_fees);
		return false;
	}
	
	LOGDEBUG("COINBASE VALID: value=%llu subsidy=%llu fees=%llu", 
	         coinbasevalue, expected_subsidy, total_fees);
	return true;
}

/* Build lean template from full template */
json_t *build_lean_template(ckpool_t *ckp, const json_t *full_template)
{
	json_t *lean_template, *transactions, *new_transactions;
	lean_tx_t *all_txs = NULL, *selected_txs = NULL;
	int n_txs, n_selected = 0, total_size = 0;
	uint64_t total_fees = 0, kept_fees = 0;
	uint64_t coinbasevalue, subsidy;
	int i;
	
	if (!ckp->lean_blocks) {
		LOGDEBUG("Lean blocks disabled, returning original template");
		return json_deep_copy(full_template);
	}
	
	/* Create a deep copy of the template */
	lean_template = json_deep_copy(full_template);
	if (!lean_template) {
		LOGERR("Failed to copy template for lean processing");
		return NULL;
	}
	
	transactions = json_object_get(full_template, "transactions");
	if (!transactions || !json_is_array(transactions)) {
		LOGDEBUG("No transactions in template");
		return lean_template;
	}
	
	n_txs = json_array_size(transactions);
	if (n_txs == 0) {
		LOGDEBUG("Empty transaction array in template");
		return lean_template;
	}
	
	/* Allocate arrays for transaction data */
	all_txs = ckzalloc(n_txs * sizeof(lean_tx_t));
	selected_txs = ckzalloc(n_txs * sizeof(lean_tx_t));
	
	/* Parse all transactions */
	for (i = 0; i < n_txs; i++) {
		json_t *tx_json = json_array_get(transactions, i);
		json_t *fee_val = json_object_get(tx_json, "fee");
		json_t *data_val = json_object_get(tx_json, "data");
		json_t *txid_val = json_object_get(tx_json, "txid");
		json_t *depends_val = json_object_get(tx_json, "depends");
		
		if (fee_val)
			all_txs[i].fee = json_integer_value(fee_val);
		
		if (data_val) {
			all_txs[i].data = (char *)json_string_value(data_val);
			all_txs[i].size = strlen(all_txs[i].data) / 2;
		}
		
		if (txid_val)
			all_txs[i].txid = (char *)json_string_value(txid_val);
		
		all_txs[i].json = tx_json;
		all_txs[i].depends = depends_val;
		if (depends_val && json_is_array(depends_val))
			all_txs[i].n_depends = json_array_size(depends_val);
		
		total_fees += all_txs[i].fee;
	}
	
	/* NOTE: Do NOT sort transactions - must maintain dependency order from bitcoind */
	/* Bitcoin Core provides transactions in valid dependency order already */
	
	/* Select transactions based on mode */
	switch (ckp->lean_mode) {
	case LEAN_MODE_COINBASE_ONLY:
		/* Keep no transactions - maximum speed like unknown miner */
		LOGNOTICE("LEAN: Coinbase-only mode - dropping all %d transactions (%.8f BCH fees)",
		          n_txs, total_fees / 100000000.0);
		n_selected = 0;
		break;
		
	case LEAN_MODE_TOP_N:
		/* Select first N transactions (maintains dependency order) */
		/* Transactions from bitcoind are already sorted by fee/priority */
		for (i = 0; i < n_txs && n_selected < ckp->lean_maxtx; i++) {
			selected_txs[n_selected] = all_txs[i];
			kept_fees += all_txs[i].fee;
			total_size += all_txs[i].size;
			n_selected++;
		}
		LOGNOTICE("LEAN: Top-%d mode - kept %d tx, %.8f BCH fees, %d bytes",
		          ckp->lean_maxtx, n_selected, kept_fees / 100000000.0, total_size);
		break;
		
	case LEAN_MODE_SIZE_CAP:
		/* Select transactions until size limit reached (maintains order) */
		for (i = 0; i < n_txs && total_size < ckp->lean_maxsize_kb * 1024; i++) {
			if (total_size + all_txs[i].size <= ckp->lean_maxsize_kb * 1024) {
				selected_txs[n_selected] = all_txs[i];
				kept_fees += all_txs[i].fee;
				total_size += all_txs[i].size;
				n_selected++;
			}
		}
		LOGNOTICE("LEAN: Size-cap mode - kept %d tx in %d bytes, %.8f BCH fees",
		          n_selected, total_size, kept_fees / 100000000.0);
		break;
	}
	
	/* Create new transaction array */
	new_transactions = json_array();
	for (i = 0; i < n_selected; i++) {
		json_array_append(new_transactions, selected_txs[i].json);
	}
	
	/* Update template with new transaction list */
	json_object_set_new(lean_template, "transactions", new_transactions);
	
	/* Adjust coinbase value - CRITICAL FIX for bad-cb-amount */
	coinbasevalue = json_integer_value(json_object_get(full_template, "coinbasevalue"));
	subsidy = coinbasevalue - total_fees;
	uint64_t new_coinbasevalue = subsidy + kept_fees;
	json_object_set_new(lean_template, "coinbasevalue", json_integer(new_coinbasevalue));
	
	/* Log the coinbase adjustment for debugging */
	LOGNOTICE("COINBASE_FIX: Original=%llu Subsidy=%llu TotalFees=%llu KeptFees=%llu New=%llu",
	          coinbasevalue, subsidy, total_fees, kept_fees, new_coinbasevalue);
	
	/* Log statistics */
	LOGNOTICE("LEAN: Dropped %.8f BCH in fees (%d transactions)",
	          (total_fees - kept_fees) / 100000000.0, n_txs - n_selected);
	
	log_lean_block(ckp, n_selected, n_txs - n_selected, kept_fees, 
	               total_fees - kept_fees, total_size);
	
	/* Clean up */
	free(all_txs);
	free(selected_txs);
	
	return lean_template;
}

/* Validate block template with preflight check */
bool lean_preflight_check(connsock_t *cs, const char *block_hex)
{
	json_t *req, *val, *res_val, *err_val;
	char *req_str;
	bool ret = false;
	int len;
	
	/* Build getblocktemplate proposal request */
	req = json_object();
	json_object_set_new(req, "mode", json_string("proposal"));
	json_object_set_new(req, "data", json_string(block_hex));
	
	len = strlen(block_hex) + 256;
	req_str = ckalloc(len);
	sprintf(req_str, "{\"method\": \"getblocktemplate\", \"params\": [{\"mode\": \"proposal\", \"data\": \"%s\"}]}\n", 
	        block_hex);
	
	/* Send request */
	val = json_rpc_call(cs, req_str);
	dealloc(req_str);
	json_decref(req);
	
	if (!val) {
		LOGWARNING("LEAN: Preflight check failed - no response");
		return false;
	}
	
	/* Check for error */
	err_val = json_object_get(val, "error");
	if (err_val && !json_is_null(err_val)) {
		const char *err_msg = json_string_value(json_object_get(err_val, "message"));
		LOGWARNING("LEAN: Preflight validation error: %s", err_msg ? err_msg : "unknown");
		goto out;
	}
	
	/* Check result - null means template is valid */
	res_val = json_object_get(val, "result");
	if (json_is_null(res_val)) {
		LOGDEBUG("LEAN: Preflight check passed");
		ret = true;
	} else {
		const char *reject = json_string_value(res_val);
		LOGWARNING("LEAN: Preflight rejected: %s", reject ? reject : "unknown reason");
	}
	
out:
	json_decref(val);
	return ret;
}

/* Calculate merkle root for transaction set */
void lean_calculate_merkle(const json_t *template, char *merkle_root)
{
	json_t *transactions;
	uchar merkle_bin[32];
	int n_txs;
	
	transactions = json_object_get(template, "transactions");
	n_txs = json_array_size(transactions);
	
	/* For now, use existing merkle from template if available */
	/* Full merkle calculation would be implemented here */
	const char *merkle_str = json_string_value(json_object_get(template, "merkleroot"));
	if (merkle_str) {
		strcpy(merkle_root, merkle_str);
	} else {
		/* Generate merkle root from transaction hashes */
		memset(merkle_bin, 0, 32);
		__bin2hex(merkle_root, merkle_bin, 32);
	}
}

/* Get lean block statistics */
void get_lean_stats(lean_stats_t *stats)
{
	mutex_lock(&stats_lock);
	memcpy(stats, &lean_stats, sizeof(lean_stats_t));
	mutex_unlock(&stats_lock);
}

/* Log lean block metrics */
void log_lean_block(ckpool_t *ckp, int kept_tx, int dropped_tx, 
                   uint64_t kept_fees, uint64_t dropped_fees, int block_size)
{
	time_t now = time(NULL);
	
	mutex_lock(&stats_lock);
	lean_stats.blocks_generated++;
	lean_stats.fees_kept_total += kept_fees;
	lean_stats.fees_dropped_total += dropped_fees;
	lean_stats.tx_kept_total += kept_tx;
	lean_stats.tx_dropped_total += dropped_tx;
	lean_stats.last_lean_block_time = now;
	
	/* Update average block size */
	if (lean_stats.blocks_generated == 1) {
		lean_stats.avg_block_size_kb = block_size / 1024.0;
	} else {
		lean_stats.avg_block_size_kb = 
		    (lean_stats.avg_block_size_kb * (lean_stats.blocks_generated - 1) + 
		     block_size / 1024.0) / lean_stats.blocks_generated;
	}
	mutex_unlock(&stats_lock);
	
	/* Log to file for monitoring */
	LOGWARNING("LEAN_BLOCK: mode=%s kept_tx=%d dropped_tx=%d size=%.2fKB "
	           "fees_kept=%.8f fees_dropped=%.8f total_lean_blocks=%lu",
	           ckp->lean_mode == LEAN_MODE_COINBASE_ONLY ? "coinbase_only" :
	           ckp->lean_mode == LEAN_MODE_TOP_N ? "top_n" : "size_cap",
	           kept_tx, dropped_tx, block_size / 1024.0,
	           kept_fees / 100000000.0, dropped_fees / 100000000.0,
	           lean_stats.blocks_generated);
}