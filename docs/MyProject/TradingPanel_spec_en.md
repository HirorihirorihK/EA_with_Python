# TradingPanel Specification

## 1. Overview
`TradingPanel.mq5` is an MQL5 Expert Advisor that manages `_Symbol` positions for a configured magic number. It provides chart-panel controls for key SL/TP parameters and manages timed exits, break-even stops, step-based trailing stops, and aggregate break-even lines.

## 2. Indicators
- The EA keeps a Deviation Band related handle/value for display.
- SuperTrend-based stop management, display text, and timeframe combo boxes are not used.

## 3. Inputs
- `exit_time_interval`: Holding time in hours before timed close. The panel value is converted to seconds inside `UpdateInputValues()`.
- `slippage`: Allowed slippage.
- `magic_number`: Magic number used to identify managed positions.
- `take_profit_pips`: Initial TP distance.
- `default_sl`: Initial SL distance.
- `stop_offset_pips`: Stop-loss offset.
- `enable_breakeven`: Enables break-even handling in `ManageStops()`.
- `breakeven_pips`: Profit threshold for break-even activation.
- `stop_loss_offset_pips`: Margin from entry price for the break-even SL.
- `step_trigger_pips`: Profit interval used to calculate trailing steps.
- `step_move_pips`: SL movement per trailing step.
- `tp_edit_pips`: Default panel increment/decrement for TP edits.
- `range_pips`: Range display setting.
- `isTradingTimeEnabled`, `TradeStartHour`, `TradeStartMin`, `TradeEndHour`, `TradeEndMin`: Trading-time filter settings.

## 4. Entry and Exit Conditions
- `CloseTimedPositions()` closes matching `_Symbol` and magic-number positions only when `timelimit_exit` is ON and the current time has reached the position entry time plus `exit_time_interval`. The check runs from both `OnTick()` and `OnTimer()` independently of the trading-time filter.
- `ApplyInitialStops()` scans existing positions on EA startup and trade-transaction detection. For positions matching `_Symbol` and `magic_number`, it backfills only missing SL/TP values from `default_sl` / `take_profit_pips`. Existing SL/TP values are not overwritten.
- `ManageStops(enable_breakeven)` scans both BUY and SELL positions in a single call.
- When `enable_breakeven=true`, trailing does not start before profit reaches `breakeven_pips`. Once reached, the EA moves SL to entry +/- `stop_loss_offset_pips`, then switches to step-based trailing.
- When `enable_breakeven=false`, the EA skips the break-even move and starts step-based trailing once profit reaches `step_trigger_pips`.
- The trailing SL is calculated from the entry price using the number of completed profit steps and `step_move_pips`.

## 5. Risk Management
- Stop management and timed close are limited to positions matching `_Symbol` and `magic_number`.
- Initial SL/TP backfill places BUY SL `default_sl` pips below entry and TP `take_profit_pips` pips above entry. For SELL positions, SL is placed `default_sl` pips above entry and TP `take_profit_pips` pips below entry.
- Before each SL/TP update, the EA checks `SYMBOL_TRADE_STOPS_LEVEL` and `SYMBOL_TRADE_FREEZE_LEVEL`. These broker constraints are point-based, so the checks use `SYMBOL_POINT`.
- `CTrade::PositionModify()` return values are checked. On failure, the EA logs the retcode, `GetLastError()`, and the requested SL.
- SL updates are monotonic: BUY stops only move upward and SELL stops only move downward.

## 6. Internal Structure
- `Experts/MyProject/TradingPanel.mq5`: Keeps the event entry points, including `OnInit()`, `OnDeinit()`, `OnTimer()`, `OnTick()`, `OnChartEvent()`, `OnTradeTransaction()`, and trading-time checks.
- `Include/MyLib/Panel/TradingPanelPanel.mqh`: Defines `CTradingPanelPanel`, which owns the chart panel, input validation, button state updates, and TP adjustment actions.
- `Include/MyLib/Common/TradingPanelSymbolUtils.mqh`: Provides shared pip conversion and order filling policy helpers.
- `Include/MyLib/Trading/TradingPanelTradingManagers.mqh`: Defines `CTradingPanelStopManager`, `CTradingPanelPositionManager`, and `CTradingPanelBreakEvenLineManager` for SL/TP management, timed exits, position counting, and aggregate break-even line handling.

## 7. Changelog
- 2026-05-04: Added initial SL/TP backfill for existing positions matching `_Symbol` and `magic_number` on EA startup and trade-transaction detection. The EA now preserves existing SL/TP values, skips candidates that are too close to stop/freeze levels, and logs skipped or failed updates.
- 2026-05-03: Refactored the EA for readability and maintainability. The main `.mq5` now focuses on event entry points, while panel handling, stop management, position management, aggregate break-even lines, and symbol helpers are split into imported `.mqh` classes/helpers.
- 2026-05-03: Renamed the EA to `TradingPanel`. Updated the EA source, external `.mqh` files under MyLib, specification filenames, and internal references to use the `TradingPanel` name consistently.
- 2026-05-03: Changed `ManageStops()` to `ManageStops(bool breakeven_enabled)`. Added argument-based break-even ON/OFF behavior and switched to BE-gated step trailing when enabled. Removed SuperTrend-based stop management, display references, timeframe combo boxes, and unused `check_expand_pips`.
- 2026-05-03: Renamed `order_interval` to `exit_time_interval` and changed the input unit to hours. `UpdateInputValues()` now converts it to seconds, and timed close runs only when `timelimit_exit` is ON and `entry_time + exit_time_interval` has been reached.
- 2026-05-03: Made timed close independent from the trading-time filter and monitored it from `OnTimer()` as well. Added `_Symbol` filtering to timed close. Corrected stop/freeze level checks to point units and centralized SL modification failure logging.
- 2026-05-03: Removed unused inputs, globals, constants, DLL import, and unused panel component declarations.

