# HIT-EA Specification (English)

## 1. Overview

- This EA sends confirmed H4 OHLC data to an external Python process for market-state analysis and confirmed H1 OHLC data for entry candidate generation.
- The MQL5 side reads Python output files and places pending orders only after checking the H4 market state, H1 candidate prices, M15 confirmation filter, spread, and broker distance constraints.
- For backtest reproducibility, OHLC export uses `OHLC_START_SHIFT = 1`, so the forming bar is excluded and only closed bars are passed to Python.
- For live resilience, the EA tracks external-process running files, process IDs, exit codes, and timeouts to prevent duplicate launches and CSV overwrites.

## 2. Indicators

- No standard or custom indicators are used.
- OHLC data is retrieved with `CopyRates(_Symbol, timeframe, OHLC_START_SHIFT, HISTORY_BARS, rates)`.
- M15 entry confirmation uses candle shape, average range, and distance to the candidate price for T2/T4. For T1/T3 it uses M15 impulse confirmation when that option is enabled.

## 3. Parameters

### input

- `lot_size = 0.01`: Order volume.
- `spread_limit = 60`: Maximum allowed spread in points.
- `magic_number = 10001`: Magic number used to identify this EA's orders and positions.
- `initial_order = 0`: Enables initial H4/H1 processing on startup when set to `1`.
- `input_position_limit = 10`: Practical limit for this EA's pending orders plus positions. Values above the internal `POSITION_LIMIT` are clamped.
- `use_split_entry_zone = false`: Enables split entries based on H1 predicted zones.
- `split_entry_count = 3`: Number of split entry orders, clamped to 1..10.
- `split_lot_mode = SPLIT_LOT_TOTAL`: Split lot mode. `SPLIT_LOT_TOTAL` divides the total lot across slots, and `SPLIT_LOT_FIXED` uses a fixed lot per order.
- `split_total_lot_size = 0.09`: Total lot used by total-split mode.
- `split_fixed_lot_size = 0.01`: Per-order lot used by fixed-split mode.
- `cancel_old_split_pending_on_new_zone = true`: Cancels older split pending orders when a new H1 zone set is loaded.
- `use_m15_entry_filter = true`: Enables M15 closed-bar entry timing confirmation.
- `m15_entry_zone_atr_multiplier = 1.50`: Allowed proximity multiplier based on the M15 average range.
- `use_m15_imbalance_confirmation = true`: Adds M15 impulse confirmation for T1/T3 trend-following candidates.
- `m15_imbalance_avg_body_period = 20`: Average-body period used by M15 impulse confirmation.
- `m15_imbalance_sensitivity = 2.0`: Required multiple of the average body for M15 impulse confirmation.
- `m15_imbalance_min_avg_body_points = 1.0`: Minimum M15 average body in points.
- `use_m15_imbalance_debug_log = false`: Enables detailed M15 impulse-confirmation logs.
- `input_entry_max_candidate_age_minutes = 120`: Maximum age, in minutes, for using an H1 candidate for new execution. This blocks delayed entries when M15 confirmation appears too late.
- `input_sltp_manager_enabled = false`: Enables UI-driven existing-position SL management through `CSLTPManager`.
- `input_sltp_show_panel = true`: Shows the SLTP control panel on the chart.
- `input_sltp_use_breakeven = false`: Enables normal break-even.
- `input_sltp_breakeven_trigger_pips = 30.0`: Profit threshold for normal break-even.
- `input_sltp_breakeven_buffer_pips = 3.0`: Profit-side entry buffer used by normal break-even.
- `input_sltp_use_elapsed_breakeven = false`: Enables elapsed-time break-even.
- `input_sltp_elapsed_breakeven_hours = 4.0`: Holding time required before elapsed-time break-even is allowed.
- `input_sltp_elapsed_breakeven_buffer_pips = 3.0`: Profit-side entry buffer used by elapsed-time break-even.
- `input_sltp_use_active_trailing = false`: Enables active step trailing.
- `input_sltp_active_breakeven_pips = 30.0`: Profit threshold that starts active trailing.
- `input_sltp_active_stop_loss_offset_pips = 5.0`: Initial locked profit offset from entry.
- `input_sltp_active_step_trigger_pips = 10.0`: Additional profit interval required for each SL step.
- `input_sltp_active_step_move_pips = 5.0`: SL movement added per completed step.
- `input_sltp_use_tp_progress_stop = false`: Enables TP-progress-based SL locking.
- `input_sltp_tp_progress_trigger_percent = 70.0`: TP progress required before the SL lock is applied.
- `input_sltp_tp_progress_sl_lock_percent = 30.0`: Entry-to-TP distance percentage locked by SL.
- `input_sltp_use_high_volatility_limit = false`: Enables short-term high-volatility SL tightening.

### Main Constants

- `POSITION_LIMIT = 48`: Maximum number of this EA's pending orders plus positions.
- `ENTRY_H1_LIMIT = 2`: Pending-order lifetime in H1 bars.
- `CLOSE_H1_LIMIT = 12`: Position lifetime in H1 bars.
- `HISTORY_BARS = 72`: Number of OHLC bars exported to Python.
- `OHLC_START_SHIFT = 1`: Shift used to export closed bars only.
- `M15_CONFIRM_BARS = 30`: Number of M15 bars used for average-range calculation.
- `ENTRY_RETRY_SECONDS = 60`: Retry interval for entry checks.
- `ENTRY_RETRY_LIMIT = 10`: Maximum retry count for one H1 candidate set.
- `TARGET_SIZE = 13`: Number of numeric values expected in `target_prices.txt`.
- `TARGET_ZONE_SCHEMA_VERSION = 2`: Schema version used by `target_zones.txt`.
- `PYTHON_TIMEOUT_SECONDS = 600`: External Python wait threshold.

### Python Entry-Candidate Guard

- After H1 candidate generation, Python invalidates any `entry` that is too far from the current price.
- The maximum distance is strategy-specific: T1/T3 Stop candidates use `max(H1 EATR * 1.50, 5.00)`, and T2/T4 Limit candidates use `max(H1 EATR * 1.00, 5.00)`. A strategy beyond its limit is rewritten to `0.00,0.00,0.00`.
- This post-filter is intended to reduce delayed entries from deep limit orders or distant breakout waits after M15 confirmation arrives late.

## 4. File Layout

- `Experts/MyProject/HIT-EA_refactor_ver6.mq5`: EA entry point. Keeps `OnInit`, `OnDeinit`, `OnTick`, inputs, global state, and DLL imports.
- `Include/MyLib/Common/HITRuntimeController.mqh`: Tick flow, H4/H1/M15 update control, status comments, and spread checks.
- `Include/MyLib/Signals/HITEntrySignal.mqh`: Entry preconditions, order-type price validation, M15 filter, and retry-state updates.
- `Include/MyLib/Common/HITExternalProcess.mqh`: done/running files, external process handles, PID recovery, exit-code checks, and timeout recovery.
- `Include/MyLib/Signals/HITPythonSignalGateway.mqh`: OHLC CSV export, Python batch launch, and `trend_state.txt` / `target_prices.txt` / `target_zones.txt` loading.
- `Include/MyLib/Trading/HITTradeManager.mqh`: Order sending, filling policy, pending-order expiration, order/position counting, expired order cancellation, and expired position closing.
- `Include/MyLib/Trading/SLTPManager.mqh`: Existing-position break-even, elapsed-time break-even, active trailing, TP-progress SL, and high-volatility SL management.
- `Include/MyLib/Panel/SLTPManagerPanel.mqh`: Chart panel that toggles `CSLTPManager` features, validates numeric inputs, and applies settings to the EA.

## 5. Python Integration Files

During `OnInit()`, the EA builds a `HIT_<sanitized symbol>_<magic_number>` prefix from `_Symbol` and `magic_number`, then applies it to all MT5 `Files` linkage names. Example: `HIT_GOLD_10001_ohlc_H4.csv`. The same prefix is passed to the batch file as the first argument, and the batch file exposes it to Python as `MT5_EA_FILE_PREFIX`. The EA also passes the symbol's `SYMBOL_DIGITS` as the second argument, exposed to Python as `MT5_PRICE_DIGITS`.

When no prefix is provided, such as manual Python execution, Python keeps using the legacy names like `ohlc_H4.csv`.

### H4 Trend Analysis

- MQL5 output: `<prefix>_ohlc_H4.csv`
- Python output: `<prefix>_trend_state.txt`
- Done marker: `<prefix>_process_done_trend.txt`
- Running marker: `<prefix>_process_running_trend.txt`
- Batch file: `<TerminalDataPath>\MQL5\python_for_ea\bat\get_trend_reply.bat`

### H1 Entry Candidate Generation

- MQL5 output: `<prefix>_ohlc_H1.csv`
- Python output: `<prefix>_target_prices.txt`, `<prefix>_target_zones.txt`
- Done marker: `<prefix>_process_done_entry.txt`
- Running marker: `<prefix>_process_running_entry.txt`
- Batch file: `<TerminalDataPath>\MQL5\python_for_ea\bat\get_entry_reply.bat`

During `OnInit()`, the EA resolves `MQL5\python_for_ea` from `TerminalInfoString(TERMINAL_DATA_PATH)` and builds absolute batch-file paths. Each batch file resolves the Python project root from its own location, so runtime execution no longer depends on `C:\ea_py`.

`target_prices.txt` must contain 13 lines:

```text
Line 1: res_chk
Lines 2-4:   T1 Buy Stop entry/tp/sl
Lines 5-7:   T2 Buy Limit entry/tp/sl
Lines 8-10:  T3 Sell Stop entry/tp/sl
Lines 11-13: T4 Sell Limit entry/tp/sl
```

`target_zones.txt` must contain 7 lines for split entries:

```text
Line 1: schema_version (2)
Line 2: res_chk
Line 3: candidate_id derived from the closed H1 bar time
Line 4: T1 Buy Stop strategy, zone_low, zone_high, tp, sl
Line 5: T2 Buy Limit strategy, zone_low, zone_high, tp, sl
Line 6: T3 Sell Stop strategy, zone_low, zone_high, tp, sl
Line 7: T4 Sell Limit strategy, zone_low, zone_high, tp, sl
```

Python creates `process_done_entry.txt` only after both `target_prices.txt` and `target_zones.txt` have been written. Prices in `target_zones.txt` are formatted with `MT5_PRICE_DIGITS`; manual runs without this value use a conservative 5 decimal places. When split entries are disabled, the EA keeps using the legacy 13-line `target_prices.txt` path.

## 6. Entry Conditions

New entries are allowed only when all conditions below are satisfied:

- Spread is less than or equal to `spread_limit`.
- H4 trend analysis is complete and `trend_state.txt` can be loaded.
- H1 entry candidate generation is complete and `target_prices.txt` can be loaded.
- `res_chk = 1`.
- The H1 candidate set has not expired under `ENTRY_H1_LIMIT`, measured from the closed H1 bar time that produced the candidate.
- The H1 candidate set has not exceeded `input_entry_max_candidate_age_minutes`, measured from the closed H1 bar time that produced the candidate.
- The selected order type has valid `entry/tp/sl` values greater than `0.0`.
- The order type is allowed by the H4 `market_state`.
- The order-type price relationship and broker minimum distance rules are satisfied.
- When `use_m15_entry_filter = true`, T2/T4 satisfy the M15 direction, rejection, and proximity checks. T1/T3 satisfy M15 impulse confirmation when `use_m15_imbalance_confirmation = true`.
- This EA's pending orders plus positions are below `input_position_limit`.
- When split entries are enabled, `target_zones.txt` has `res_chk = 1`, the predicted zone prices are valid, split lots fit `SYMBOL_VOLUME_MIN/MAX/STEP`, and no duplicate order or position exists for the same `candidate_id` + slot.

### market_state and Allowed Order Types

- `0 MARKET_LOW_VOL_RANGE`: Allows T2 Buy Limit / T4 Sell Limit.
- `1 MARKET_HIGH_VOL_RANGE`: Allows T2 Buy Limit / T4 Sell Limit.
- `2 MARKET_LOW_VOL_UP`: Allows T1 Buy Stop / T2 Buy Limit.
- `3 MARKET_HIGH_VOL_UP`: Allows T1 Buy Stop / T2 Buy Limit.
- `4 MARKET_LOW_VOL_DOWN`: Allows T3 Sell Stop / T4 Sell Limit.
- `5 MARKET_HIGH_VOL_DOWN`: Allows T3 Sell Stop / T4 Sell Limit.
- `6 MARKET_TECHNICAL_ERROR_STOP`: Blocks new entries.

### Order-Type Price Rules

- T1 Buy Stop: `Ask < entry`, `tp > entry`, `sl < entry`
- T2 Buy Limit: `Ask > entry`, `tp > entry`, `sl < entry`
- T3 Sell Stop: `Bid > entry`, `tp < entry`, `sl > entry`
- T4 Sell Limit: `Bid < entry`, `tp < entry`, `sl > entry`

## 7. Exit Conditions

- Pending orders are cancelled after `ENTRY_H1_LIMIT * PeriodSeconds(PERIOD_H1)` has elapsed from setup time.
- Positions are closed after `CLOSE_H1_LIMIT * PeriodSeconds(PERIOD_H1)` has elapsed from entry time.
- Time-limit handling runs early in `OnTick` and is independent of Python readiness or spread checks.
- On EA removal, `OnDeinit()` releases external-process state and the SLTP panel, then clears the chart status text with `Comment("")` and `ChartRedraw(0)`.
- When `input_sltp_manager_enabled` or the panel `Manager` toggle is ON, the EA runs `CSLTPManager::ManagePositions()` and `HighVolatilityLimit()` after time-limit handling. Existing-position SL protection therefore continues while Python results are pending or new entries are skipped.
- Normal break-even and active trailing are mutually exclusive. The panel turns one mode off when the other is enabled, and `CSLTPManager::ValidateSettings()` also validates the exclusion.

## 7.1 SLTP Control Panel

- The panel is created when `input_sltp_show_panel = true` and appears near the chart's upper-right area.
- If panel creation fails, the EA logs the failure and continues with the already-applied input-based SLTP settings.
- The `Manager` button toggles all SLTP management. When OFF, panel values remain stored but `OnTick` does not modify SL values.
- The `BreakEven`, `Elapsed BE`, `Active Trail`, `TP Progress`, and `High Vol` buttons toggle each `CSLTPManager` feature.
- Numeric fields are validated when `APPLY` is pressed. Invalid or out-of-range values show a `MessageBox`, are logged, and revert to the previous valid value.
- Settings are copied into `CSLTPManager` only after `APPLY` succeeds. The EA then calls `ValidateSettings()`; if validation fails, SLTP management is stopped and the reason is logged.

## 8. Risk Management

- Managed orders and positions are limited to matching `_Symbol` and `magic_number`.
- `input_position_limit` counts only this EA's orders and positions, not the full account. The hard internal limit is `POSITION_LIMIT`.
- The EA selects the filling policy from `SYMBOL_FILLING_MODE`, preferring IOC, then FOK, then RETURN.
- Before sending either single or split orders, the EA verifies the requested lot against `SYMBOL_VOLUME_MIN/MAX/STEP`.
- Pending orders receive server-side expiration when the broker supports it.
- `OrderSend` return values and `MqlTradeResult.retcode` are checked. Failures are logged with `GetLastError()` or the retcode.
- Split-entry order comments include `candidate_id` and slot number to prevent duplicate slot execution.
- When `cancel_old_split_pending_on_new_zone = true`, a new valid `candidate_id` cancels older split pending orders, and an invalid or stopped `target_zones.txt` cancels all existing split pending orders for this EA/symbol/magic.
- SLTP management only targets existing positions matching `_Symbol` and `magic_number`, and it preserves each position's current TP.
- SL changes are sent only when the candidate improves protection relative to the current SL and satisfies broker stop-level and freeze-level constraints.
- `HighVolatilityLimit()` evaluates BUY positions with Bid and SELL positions with Ask, and treats GOLD/XAUUSD suffix symbols as 1 pip = 0.1.

## 9. Error Handling

- If `trend_state.txt` is missing, unreadable, not strictly parseable as an integer, or outside `0..6`, the EA uses `MARKET_TECHNICAL_ERROR_STOP`.
- If `target_prices.txt` is missing, unreadable, shorter than 13 lines, or contains a non-strict numeric line, the EA uses `res_chk = 0`.
- When split entries are enabled, missing `target_zones.txt`, schema mismatch, fewer than 7 lines, `res_chk != 1`, or non-strict numeric values stop new split orders.
- If a Python process exits with a non-zero code, the code is logged and the next trigger may retry.
- If a Python process remains active beyond `PYTHON_TIMEOUT_SECONDS`, the EA runs `taskkill /T /F` against the cmd/bat process tree, clears done/running files, and allows the next trigger to retry.
- If only a stale running marker remains, the EA attempts PID recovery. If recovery fails and the marker is timed out, it removes the stale marker.

## 10. Changelog

### 2026-05-30

- Added the `HIT_<symbol>_<magic_number>` linkage-file prefix contract on both the MT5 and Python sides to avoid collisions across multiple EAs or symbols in the same terminal.
- Updated T1/T3 trend-following candidates so `use_m15_imbalance_confirmation = true` requires M15 impulse confirmation.
- Added strict numeric parsing requirements for `trend_state.txt`, `target_prices.txt`, and `target_zones.txt`, with invalid content handled as a safe stop state.
- Added stale split-pending cancellation behavior when `target_zones.txt` is invalid or stopped.
- Synchronized current defaults for `input_entry_max_candidate_age_minutes`, `ENTRY_H1_LIMIT`, SLTP buffers, and the Python entry-distance guard.
- Added process-tree termination and retry recovery for Python timeouts.
- Changed H1 candidate freshness checks to use the closed H1 bar time restored from `candidate_id`, instead of the Python result load time.
- Added `MT5_PRICE_DIGITS` so Python formats `target_zones.txt` prices with the active symbol's decimal precision.
- Added single-order lot validation, OHLC CSV NaN/inf and consistency checks, Ask-based SELL high-volatility SL evaluation, and GOLD/XAUUSD suffix handling.

### 2026-05-27

- Moved the Python helper application specification from `C:\ea_py` to `MQL5\python_for_ea` under the MT5 data folder.
- Updated the EA startup path model so batch paths are built from `TerminalInfoString(TERMINAL_DATA_PATH)`, and the external process working directory is derived from the batch-file location.
- Updated Python path discovery so the default MT5 linkage is the adjacent `MQL5\Files` directory, with `MT5_FILES_DIR` or `MT5_DATA_PATH` available for explicit overrides.

### 2026-05-24

- Added Python-side `target_zones.txt` output and made `process_done_entry.txt` appear only after both `target_prices.txt` and `target_zones.txt` are written.
- Added `use_split_entry_zone`, `split_entry_count`, `split_lot_mode`, `split_total_lot_size`, `split_fixed_lot_size`, and `input_position_limit`.
- Added split-zone pending order placement with total-lot or fixed-lot sizing.
- Added `candidate_id` + slot identification to prevent duplicate split orders.

### 2026-05-13

- Added a Python-side H1 EATR distance guard that invalidates candidates too far from the current price before they are passed to MT5.
- Added `input_entry_max_candidate_age_minutes` on the EA side so stale H1 candidates are not executed when M15 confirmation arrives late.
- Added H1 candidate age to entry skip logs to make delayed entries, M15 rejection, and price mismatch easier to diagnose.

### 2026-05-05

- Added `Comment("")` and `ChartRedraw(0)` to `OnDeinit()` so the chart status comment is removed when the EA is deleted.
- Connected `CSLTPManager` and the dedicated chart panel `SLTPManagerPanel.mqh` to `HIT-EA_refactor_ver5.mq5`, allowing UI control of break-even, elapsed-time break-even, active trailing, TP-progress SL, and high-volatility SL tightening.
- Added SLTP management immediately after time-limit handling in `OnTick`, so existing-position protection continues independently of Python readiness and spread checks.
- Added SLTP panel inputs, mutual exclusion for normal break-even versus active trailing, and numeric validation on `APPLY`.
- Split the function implementations from `HIT-EA_refactor_ver5.mq5` into purpose-specific `.mqh` files.
- Kept `OnInit`, `OnDeinit`, `OnTick`, inputs, and global state in the EA source while moving behavior functions under `Include/MyLib/`.
- Updated the specification to match the current `CreateProcessW` Python process tracking, M15 filter, `market_state` range `0..6`, and `spread_limit = 60`.

### 2026-05-02

- Added entry suppression when `res_chk = 0`.
- Moved time-limit handling before Python readiness and spread checks.
- Split startup flags for H4 and H1 initial processing.
- Switched OHLC retrieval to `CopyRates` and exported closed bars only.
