# SLTPManager Specification

## 1. Overview
`SLTPManager.mqh` provides a reusable MQL5 stop-loss manager for Expert Advisors. It scans all open positions, selects only positions matching a configured symbol and magic number, and updates SL values with `CTrade::PositionModify()` while preserving each position's existing TP.

## 2. Indicators
- No standard or custom indicators are used.
- The manager uses `SYMBOL_DIGITS`, `SYMBOL_POINT`, `SYMBOL_TRADE_STOPS_LEVEL`, `SYMBOL_TRADE_FREEZE_LEVEL`, and live bid/ask ticks from the configured symbol.

## 3. Inputs and Settings
The reusable class stores settings through setter methods rather than direct `input` declarations. `SLTPManagerSample.mq5` exposes the following example inputs:

- `input_magic_number`: Magic number used to select managed positions.
- `input_slippage_points`: Deviation in points passed to `CTrade`.
- `input_use_breakeven`: Enables the normal break-even mode.
- `input_breakeven_trigger_pips`: Profit threshold for normal break-even.
- `input_breakeven_buffer_pips`: Profit-side SL buffer from entry after normal break-even triggers.
- `input_use_elapsed_breakeven`: Enables elapsed-time break-even.
- `input_elapsed_breakeven_hours`: Holding time required before the time-based break-even move is allowed. Fractional hours are supported.
- `input_elapsed_breakeven_buffer_pips`: Profit-side SL buffer from entry after elapsed-time break-even triggers.
- `input_use_active_trailing`: Enables active break-even plus step trailing.
- `input_active_breakeven_pips`: Profit threshold for the first active break-even move.
- `input_active_stop_loss_offset_pips`: Locked profit offset from entry at activation.
- `input_active_step_trigger_pips`: Additional profit interval required for each trailing step.
- `input_active_step_move_pips`: SL movement added per completed trailing step.
- `input_use_tp_progress_stop`: Enables TP-progress-based SL locking.
- `input_tp_progress_trigger_percent`: Current price progress toward TP required before locking SL.
- `input_tp_progress_sl_lock_percent`: Entry-to-TP percentage where SL is moved after the trigger.

## 4. Entry and Exit Conditions
- The manager does not open or close positions.
- `ManagePositions()` scans `PositionsTotal()` and processes only positions where `POSITION_MAGIC` equals the configured magic number and `POSITION_SYMBOL` equals the configured symbol.
- BUY profit calculations use Bid and price increases as the favorable direction.
- SELL profit calculations use Ask and price decreases as the favorable direction.
- Normal break-even moves SL to entry plus/minus the configured buffer once profit reaches the trigger. BUY positions use entry + `input_breakeven_buffer_pips`, and SELL positions use entry - `input_breakeven_buffer_pips`.
- Elapsed-time break-even uses the position `POSITION_TIME` and the current tick time. When holding time is at least `input_elapsed_breakeven_hours` and the current rate has crossed the entry price, SL moves to entry plus/minus `input_elapsed_breakeven_buffer_pips`. BUY positions require Bid above entry, and SELL positions require Ask below entry.
- Active trailing first moves SL to the active offset once profit reaches `input_active_breakeven_pips`, then adds `input_active_step_move_pips` for every completed `input_active_step_trigger_pips`.
- TP-progress locking runs only when TP exists and the TP is in the correct profit direction.

## 5. Risk Management
- SL updates are monotonic: BUY stops only move upward and SELL stops only move downward.
- When multiple rules produce candidates on the same tick, BUY uses the highest candidate and SELL uses the lowest candidate.
- TP is never changed; the current TP is passed back unchanged during `PositionModify()`.
- Pip conversion follows the existing `AdjustPoint()` convention: `GOLD` / `XAUUSD` use `1 pip = 0.1`, 2/3-digit symbols use `0.01`, and 4/5-digit symbols use `0.0001`.
- Candidate SL prices are normalized with `NormalizeDouble()` using the symbol digits.
- Broker stop and freeze levels are checked with `SYMBOL_TRADE_STOPS_LEVEL`, `SYMBOL_TRADE_FREEZE_LEVEL`, and `SYMBOL_POINT` before modification.
- `ValidateSettings()` rejects simultaneous normal break-even and active trailing because those modes are mutually exclusive.
- Elapsed-time break-even can be enabled or disabled independently from normal break-even and active trailing. If multiple candidates are valid, the existing best-candidate selection rule is used.
- `ValidateSettings()` checks that elapsed-time break-even hours and buffer pips are non-negative.
- Failed SL modifications log ticket, symbol, magic number, trade retcode, `GetLastError()`, and requested SL.

## 6. Changelog
- 2026-05-05: Aligned pip conversion with the existing `AdjustPoint()` convention so `GOLD` / `XAUUSD` use `1 pip = 0.1`. A panel input of `2.0` pips now maps to a `0.2` price distance on `GOLD`.
- 2026-05-05: Added elapsed-time break-even settings `input_use_elapsed_breakeven`, `input_elapsed_breakeven_hours`, and `input_elapsed_breakeven_buffer_pips`, allowing an independent SL move to entry plus/minus buffer after the configured holding time when the current rate has crossed entry.
- 2026-05-05: Added the configurable normal break-even buffer `input_breakeven_buffer_pips` and clarified that SL moves to entry plus/minus the buffer after the trigger.
- 2026-05-05: Added reusable `CSLTPManager`, example EA `SLTPManagerSample.mq5`, normal break-even, active trailing, TP-progress SL locking, monotonic SL selection, broker stop/freeze checks, and validation for mutually exclusive modes.
