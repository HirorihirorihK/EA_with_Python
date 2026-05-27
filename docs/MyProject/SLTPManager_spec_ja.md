# SLTPManager 仕様書

## 1. 概要
`SLTPManager.mqh` は、複数EAから再利用できる MQL5 用ストップロス管理ライブラリです。全ポジションを走査し、指定されたシンボルとマジックナンバーに一致するポジションのみを対象に、既存TPを維持したまま `CTrade::PositionModify()` で SL を更新します。

## 2. 使用インジケータ
- 標準・カスタムインジケータは使用しません。
- 対象シンボルの `SYMBOL_DIGITS`, `SYMBOL_POINT`, `SYMBOL_TRADE_STOPS_LEVEL`, `SYMBOL_TRADE_FREEZE_LEVEL` と Bid/Ask tick を使用します。

## 3. パラメータ設定
共通クラス自体は `input` を持たず、setter 経由で設定値を保持します。利用例の `SLTPManagerSample.mq5` では以下の input を定義しています。

- `input_magic_number`: 管理対象ポジションを識別するマジックナンバー。
- `input_slippage_points`: `CTrade` に設定する許容偏差ポイント。
- `input_use_breakeven`: 通常ブレークイーブンを有効化します。
- `input_breakeven_trigger_pips`: 通常ブレークイーブンを開始する含み益幅。
- `input_breakeven_buffer_pips`: 通常ブレークイーブン時に建値から利益方向へ SL をずらすバッファー幅。
- `input_use_elapsed_breakeven`: 保有時間ベースのブレークイーブンを有効化します。
- `input_elapsed_breakeven_hours`: 建値超過時のSL移動を許可するまでの保有時間。小数指定も可能です。
- `input_elapsed_breakeven_buffer_pips`: 保有時間ベースのブレークイーブン時に建値から利益方向へ SL をずらすバッファー幅。
- `input_use_active_trailing`: アクティブ・ブレークイーブン兼トレーリングを有効化します。
- `input_active_breakeven_pips`: 最初の建値移動を開始する含み益幅。
- `input_active_stop_loss_offset_pips`: 起動時に建値から確保する利益幅。
- `input_active_step_trigger_pips`: トレーリングを1段進めるために必要な追加利益幅。
- `input_active_step_move_pips`: 1段ごとに SL を有利方向へ動かす幅。
- `input_use_tp_progress_stop`: TP到達率に応じた SL 更新を有効化します。
- `input_tp_progress_trigger_percent`: TP到達率SLを起動する現在価格のTP到達率。
- `input_tp_progress_sl_lock_percent`: 起動後に SL を移動する建値からTPまでの割合。

## 4. エントリー/エグジット条件
- このライブラリは新規エントリーや決済を行いません。
- `ManagePositions()` は `PositionsTotal()` で全ポジションを走査し、`POSITION_MAGIC` と `POSITION_SYMBOL` が設定値に一致するポジションのみ処理します。
- BUY の利益計算は Bid を基準にし、価格上昇方向を利益方向とします。
- SELL の利益計算は Ask を基準にし、価格下落方向を利益方向とします。
- 通常ブレークイーブンは、含み益が指定pipsへ到達した時点で SL を建値 +/- バッファーへ移動します。BUY は建値 + `input_breakeven_buffer_pips`、SELL は建値 - `input_breakeven_buffer_pips` へ設定します。
- 保有時間ベースのブレークイーブンは、ポジションの `POSITION_TIME` から現在tick時刻までが `input_elapsed_breakeven_hours` 以上で、かつ現在レートが建値を超えている場合に SL を建値 +/- `input_elapsed_breakeven_buffer_pips` へ移動します。BUY は Bid が建値を上回る場合、SELL は Ask が建値を下回る場合のみ対象です。
- アクティブトレーリングは、`input_active_breakeven_pips` 到達時に SL を建値付近へ移動し、その後 `input_active_step_trigger_pips` ごとに `input_active_step_move_pips` 分だけ SL を更新します。
- TP到達率SLは、TPが設定され、かつTPが利益方向にあるポジションのみ対象にします。

## 5. リスク管理
- SL は BUY では上方向、SELL では下方向の改善時のみ更新します。
- 複数条件が同時に成立した場合、BUY は最も高いSL候補、SELL は最も低いSL候補を採用します。
- TP は変更せず、`PositionModify()` 実行時も現在TPをそのまま渡します。
- pips換算は既存の `AdjustPoint()` 仕様に合わせ、`GOLD` / `XAUUSD` は `1 pip = 0.1`、2/3桁シンボルは `0.01`、4/5桁シンボルは `0.0001` として扱います。
- SL候補は `NormalizeDouble()` により対象シンボルの桁数へ正規化します。
- 更新前に `SYMBOL_TRADE_STOPS_LEVEL`, `SYMBOL_TRADE_FREEZE_LEVEL`, `SYMBOL_POINT` を使ってブローカー制約を確認します。
- `ValidateSettings()` は通常ブレークイーブンとアクティブトレーリングの同時ONを設定エラーとして拒否します。
- 保有時間ベースのブレークイーブンは通常ブレークイーブンやアクティブトレーリングとは独立してON/OFFでき、同時成立時は既存の最良SL候補選択に従います。
- `ValidateSettings()` は保有時間ベースのブレークイーブンについて、保有時間とバッファーpipsが負値でないことを検証します。
- SL更新失敗時は ticket、symbol、magic number、trade retcode、`GetLastError()`、要求SLをログ出力します。

## 6. 変更履歴
- 2026-05-05: pips換算を既存の `AdjustPoint()` 仕様に合わせ、`GOLD` / `XAUUSD` は `1 pip = 0.1` として扱うように変更。パネルで入力した `2.0` pips が `GOLD` で `0.2` の価格幅として反映される。
- 2026-05-05: 保有時間ベースのブレークイーブン設定 `input_use_elapsed_breakeven`, `input_elapsed_breakeven_hours`, `input_elapsed_breakeven_buffer_pips` を追加し、指定時間経過後に現在レートが建値を超えていればSLを建値 +/− バッファーへ移動する独立機能を追加。
- 2026-05-05: 通常ブレークイーブンに任意pipsのバッファー設定 `input_breakeven_buffer_pips` を追加し、SLを建値 +/− バッファーへ移動する仕様として明確化。
- 2026-05-05: 再利用可能な `CSLTPManager`、利用例EA `SLTPManagerSample.mq5`、通常ブレークイーブン、アクティブトレーリング、TP到達率SL、単調なSL候補選択、stop/freeze level 検証、排他設定の検証を追加。
