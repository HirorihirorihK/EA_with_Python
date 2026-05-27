# TradingPanel 仕様書

## 1. 概要
`TradingPanel.mq5` は、指定マジックナンバーの `_Symbol` ポジションを管理する MQL5 Expert Advisor です。チャート上の操作パネルから主要な SL/TP 設定を変更し、ポジション保有時間、ブレークイーブン、ステップ式トレールストップ、総建値ラインを管理します。

## 2. 使用インジケータ
- Deviation Band 系の値表示用ハンドルを保持します。
- SuperTrend 関連のストップ管理・表示・コンボボックスは使用しません。

## 3. パラメータ設定
- `exit_time_interval`: 時間制限クローズまでの保有時間（時間）。パネル入力値は `UpdateInputValues()` 内で秒へ変換されます。
- `slippage`: 許容スリッページ。
- `magic_number`: 管理対象ポジションを識別するマジックナンバー。
- `take_profit_pips`: 初期 TP 幅。
- `default_sl`: 初期 SL 幅。
- `stop_offset_pips`: SL オフセット。
- `enable_breakeven`: `ManageStops()` のブレークイーブン処理を有効化する。
- `breakeven_pips`: ブレークイーブン判定に使う含み益幅。
- `stop_loss_offset_pips`: 建値から SL を置くマージン。
- `step_trigger_pips`: トレール更新を判定する利益ステップ。
- `step_move_pips`: 1 ステップごとに SL を有利方向へ動かす幅。
- `tp_edit_pips`: パネルから TP を増減する初期幅。
- `range_pips`: レンジ判定表示用設定。
- `isTradingTimeEnabled`, `TradeStartHour`, `TradeStartMin`, `TradeEndHour`, `TradeEndMin`: 取引時間制限。

## 4. エントリー/エグジット条件
- `CloseTimedPositions()` は、`timelimit_exit` が ON の場合のみ、ポジションの建値時刻に `exit_time_interval` を加算した時刻へ到達した対象マジックナンバーかつ `_Symbol` のポジションを成行でクローズします。この監視は取引時間フィルターとは独立して `OnTick()` と `OnTimer()` から実行します。
- `ApplyInitialStops()` は、EA 起動時および取引トランザクション検知時に、対象マジックナンバーかつ `_Symbol` の既存ポジションを走査し、未設定の SL/TP のみ `default_sl` / `take_profit_pips` から補完します。既に設定済みの SL/TP は上書きしません。
- `ManageStops(enable_breakeven)` は BUY/SELL 両方のポジションを 1 回の呼び出しで走査します。
- `enable_breakeven=true` の場合、含み益が `breakeven_pips` 未満の間はトレールへ移行しません。閾値到達後、SL を建値 +/- `stop_loss_offset_pips` に更新し、その後ステップ式トレールへ移行します。
- `enable_breakeven=false` の場合、建値移動は行わず、含み益が `step_trigger_pips` 以上になった時点でステップ式トレールを開始します。
- トレール SL は、含み益のステップ数に応じて建値から `step_move_pips` 単位で有利方向へ更新します。

## 5. リスク管理
- すべてのストップ管理および時間制限クローズ対象は `_Symbol` かつ `magic_number` が一致するポジションに限定します。
- 初期 SL/TP 補完は、BUY では建値から `default_sl` pips 下に SL、`take_profit_pips` pips 上に TP を置き、SELL では建値から `default_sl` pips 上に SL、`take_profit_pips` pips 下に TP を置きます。
- SL/TP 更新前に `SYMBOL_TRADE_STOPS_LEVEL` と `SYMBOL_TRADE_FREEZE_LEVEL` を確認します。これらのブローカー制約はポイント単位のため、判定には `SYMBOL_POINT` を使用します。
- `CTrade::PositionModify()` の戻り値を確認し、失敗時は retcode、`GetLastError()`、設定予定 SL をログ出力します。
- SL は BUY では上方向、SELL では下方向の改善時のみ更新します。

## 6. 内部構成
- `Experts/MyProject/TradingPanel.mq5`: `OnInit()`, `OnDeinit()`, `OnTimer()`, `OnTick()`, `OnChartEvent()`, `OnTradeTransaction()` のイベント入口と取引時間判定を保持します。
- `Include/MyLib/Panel/TradingPanelPanel.mqh`: `CTradingPanelPanel` として操作パネル、入力値検証、ボタン状態管理、TP 調整イベントの生成を担当します。
- `Include/MyLib/Common/TradingPanelSymbolUtils.mqh`: pips 換算と注文執行ポリシー取得の共通関数を提供します。
- `Include/MyLib/Trading/TradingPanelTradingManagers.mqh`: `CTradingPanelStopManager`, `CTradingPanelPositionManager`, `CTradingPanelBreakEvenLineManager` を定義し、SL/TP 管理、時間制限クローズ、ポジション集計、総建値ライン管理を担当します。

## 7. 変更履歴
- 2026-05-04: EA 起動時および取引トランザクション検知時に、対象 `_Symbol` と `magic_number` が一致する既存ポジションへ未設定の初期 SL/TP を補完する処理を追加。既存 SL/TP は上書きせず、stop/freeze level に近い候補はスキップしてログ出力する仕様を追加。
- 2026-05-03: 可読性・保守性向上のため、EA 本体をイベント入口中心へ整理し、パネル、ストップ管理、ポジション管理、総建値ライン管理、シンボル共通処理を `.mqh` のクラス/共通関数へ分割。
- 2026-05-03: EA 名を `TradingPanel` に変更。EA 本体、MyLib 配下の外部 `.mqh`、仕様書ファイル名と内部参照を `TradingPanel` 名へ統一。
- 2026-05-03: `ManageStops()` を `ManageStops(bool breakeven_enabled)` に変更。ブレークイーブン ON/OFF を引数で切り替え、BE ON 時は `breakeven_pips` 到達後にステップ式トレールへ移行する仕様へ変更。SuperTrend ベースのストップ管理・表示・コンボボックスを削除し、未使用の `check_expand_pips` を削除。
- 2026-05-03: `order_interval` を `exit_time_interval` に変更し、時間単位の入力へ変更。`UpdateInputValues()` で秒へ変換し、`timelimit_exit` ON 時のみ `entry_time + exit_time_interval` 到達で時間制限クローズする仕様へ変更。
- 2026-05-03: 時間制限クローズを取引時間フィルターから独立させ、`OnTimer()` でも監視するよう変更。時間制限クローズに `_Symbol` フィルターを追加。stop/freeze level 判定をポイント単位へ修正し、SL 更新失敗ログを共通化。
- 2026-05-03: 未使用の input、グローバル変数、未使用定数、未使用 DLL import、未使用パネル部品宣言を削除。

