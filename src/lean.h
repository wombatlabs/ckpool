/*
 * Copyright 2025 EloPool
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation; either version 3 of the License, or (at your option)
 * any later version.  See COPYING for more details.
 */

#ifndef LEAN_H
#define LEAN_H

#include "config.h"
#include "ckpool.h"
#include "bitcoin.h"

/* Transaction structure for lean block building */
typedef struct lean_tx {
	char *txid;
	char *data;
	int64_t fee;
	int size;
	json_t *json;
	json_t *depends;
	int n_depends;
} lean_tx_t;

/* Lean block statistics */
typedef struct lean_stats {
	uint64_t blocks_generated;
	uint64_t fees_dropped_total;
	uint64_t fees_kept_total;
	uint64_t tx_dropped_total;
	uint64_t tx_kept_total;
	time_t last_lean_block_time;
	double avg_block_size_kb;
} lean_stats_t;

/* Build a lean template from the full template */
json_t *build_lean_template(ckpool_t *ckp, const json_t *full_template);

/* Validate coinbase amount matches included transactions */
bool validate_coinbase_amount(const json_t *template, uint64_t expected_subsidy);

/* Validate template with preflight check */
bool lean_preflight_check(connsock_t *cs, const char *block_hex);

/* Calculate merkle root for pruned transaction set */
void lean_calculate_merkle(const json_t *template, char *merkle_root);

/* Get lean block statistics */
void get_lean_stats(lean_stats_t *stats);

/* Log lean block metrics */
void log_lean_block(ckpool_t *ckp, int kept_tx, int dropped_tx, 
                   uint64_t kept_fees, uint64_t dropped_fees, int block_size);

#endif /* LEAN_H */