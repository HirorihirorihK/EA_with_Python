# HIT-EA 仕様書（日本語）

## 1. 概要

- 本EAは、H4の確定足OHLCから外部Pythonで相場状態を判定し、H1の確定足OHLCからエントリー候補価格を生成する。
- MQL5側はPythonの出力ファイルを読み込み、H4相場状態、H1候補価格、M15確定足フィルタ、スプレッド、ブローカー距離制約を確認したうえでペンディング注文を発行する。
- バックテスト再現性のため、Pythonへ渡すOHLCは `OHLC_START_SHIFT = 1` により形成中バーを除外し、確定足だけを使用する。
- ライブ実行時の耐性として、外部プロセスの `running` ファイル、プロセスID、終了コード、タイムアウトを監視し、二重起動とCSV上書きを抑止する。

## 2. 使用インジケータ

- 標準インジケータおよびカスタムインジケータは未使用。
- OHLCは `CopyRates(_Symbol, timeframe, OHLC_START_SHIFT, HISTORY_BARS, rates)` で取得する。
- M15エントリー確認は、T2/T4では直近確定足と1本前の確定足のローソク足形状、平均レンジ、候補価格との距離から判定し、T1/T3では必要に応じてM15初動確認を行う。

## 3. パラメータ設定

### input

- `lot_size = 0.01`: 注文ロット。
- `spread_limit = 60`: 許容スプレッド（point）。
- `magic_number = 10001`: EA識別用マジックナンバー。
- `initial_order = 0`: 起動直後の初回H4/H1処理を実行するか。`1` で有効。
- `use_m15_entry_filter = true`: M15確定足によるエントリータイミング確認を使用するか。
- `m15_entry_zone_atr_multiplier = 1.50`: M15平均レンジに対する候補価格接近許容倍率。
- `use_m15_imbalance_confirmation = true`: T1/T3の順張り候補に対して、M15確定足の初動確認を追加するか。
- `m15_imbalance_avg_body_period = 20`: M15初動確認で使う平均実体計算期間。
- `m15_imbalance_sensitivity = 2.0`: M15初動確認で現在足実体が平均実体を上回る必要倍率。
- `m15_imbalance_min_avg_body_points = 1.0`: M15平均実体の最小値（point）。
- `use_m15_imbalance_debug_log = false`: M15初動確認の詳細ログを出すか。
- `input_entry_max_candidate_age_minutes = 120`: H1候補価格を新規発注に使用できる最大経過分数。古い候補でM15条件が後から整った場合の遅延エントリーを抑止する。
- `input_position_limit = 10`: 自EAの未約定注文 + ポジション数の実運用上限。内部上限 `POSITION_LIMIT` を超える指定は丸める。
- `use_split_entry_zone = false`: H1予測ゾーンを使った分割エントリーを有効化するか。
- `split_entry_count = 3`: 分割エントリー本数。1〜10に丸めて使用する。
- `split_lot_mode = SPLIT_LOT_TOTAL`: 分割ロット配分モード。`SPLIT_LOT_TOTAL` は総ロットをN分割、`SPLIT_LOT_FIXED` は各注文に固定ロットを使う。
- `split_total_lot_size = 0.09`: 総量分割モードの合計ロット。
- `split_fixed_lot_size = 0.01`: 固定ロットモードの1注文ロット。
- `cancel_old_split_pending_on_new_zone = true`: 新しいH1ゾーン読込時に、同じEAの古い分割pending注文を取消するか。
- `input_sltp_manager_enabled = false`: UI連動の `CSLTPManager` による既存ポジションSL管理を有効化するか。
- `input_sltp_show_panel = true`: チャート上にSLTP操作パネルを表示するか。
- `input_sltp_use_breakeven = false`: 通常ブレークイーブンを有効化するか。
- `input_sltp_breakeven_trigger_pips = 30.0`: 通常ブレークイーブンを開始する含み益pips。
- `input_sltp_breakeven_buffer_pips = 3.0`: 通常ブレークイーブン時に建値から利益方向へずらすpips。
- `input_sltp_use_elapsed_breakeven = false`: 保有時間ベースのブレークイーブンを有効化するか。
- `input_sltp_elapsed_breakeven_hours = 4.0`: 保有時間ベースのブレークイーブンを許可するまでの保有時間。
- `input_sltp_elapsed_breakeven_buffer_pips = 3.0`: 保有時間ベースのブレークイーブン時に建値から利益方向へずらすpips。
- `input_sltp_use_active_trailing = false`: アクティブトレーリングを有効化するか。
- `input_sltp_active_breakeven_pips = 30.0`: アクティブトレーリング開始pips。
- `input_sltp_active_stop_loss_offset_pips = 5.0`: 開始時に建値から固定する利益pips。
- `input_sltp_active_step_trigger_pips = 10.0`: SLを1段進めるために必要な追加利益pips。
- `input_sltp_active_step_move_pips = 5.0`: 1段ごとにSLを利益方向へ動かすpips。
- `input_sltp_use_tp_progress_stop = false`: TP進捗率に応じたSL固定を有効化するか。
- `input_sltp_tp_progress_trigger_percent = 70.0`: TP進捗率SLを開始する進捗率。
- `input_sltp_tp_progress_sl_lock_percent = 30.0`: 建値からTPまでの距離のうちSLで固定する割合。
- `input_sltp_use_high_volatility_limit = false`: 短時間急変時のSL引き締めを有効化するか。

### 主要定数

- `POSITION_LIMIT = 48`: 自EAの未約定注文 + ポジション数の上限。
- `ENTRY_H1_LIMIT = 2`: 未約定注文の有効期限（H1本数）。
- `CLOSE_H1_LIMIT = 12`: ポジションの時間制限クローズ（H1本数）。
- `HISTORY_BARS = 72`: Pythonへ渡すOHLC本数。
- `OHLC_START_SHIFT = 1`: 確定足からOHLCを取得するためのシフト。
- `M15_CONFIRM_BARS = 30`: M15平均レンジ計算に使う足数。
- `ENTRY_RETRY_SECONDS = 60`: エントリー判定リトライ間隔。
- `ENTRY_RETRY_LIMIT = 10`: H1候補価格に対する最大リトライ回数。
- `TARGET_SIZE = 13`: `target_prices.txt` から読み込む数値数。
- `TARGET_ZONE_SCHEMA_VERSION = 2`: `target_zones.txt` の形式バージョン。
- `PYTHON_TIMEOUT_SECONDS = 600`: Python完了待ちの監視上限。

### Python側エントリー候補ガード

- H1候補価格生成後、Python側で現在価格から遠すぎる `entry` を無効化する。
- 距離上限は戦略別に計算し、T1/T3のStop系は `max(H1 EATR * 1.50, 5.00)`、T2/T4のLimit系は `max(H1 EATR * 1.00, 5.00)` とする。上限を超えた戦略は `0.00,0.00,0.00` に補正する。
- このガードは、深い指値や遠いブレイク待ちがM15確認後に遅れて発注されることを抑えるための後処理である。

## 4. ファイル構成

- `Experts/MyProject/HIT-EA_refactor_ver6.mq5`: EAエントリーポイント。`OnInit`, `OnDeinit`, `OnTick`、input、グローバル状態、DLL importを保持する。
- `Include/MyLib/Common/HITRuntimeController.mqh`: ティック処理、H4/H1/M15更新制御、ステータス表示、スプレッド判定。
- `Include/MyLib/Signals/HITEntrySignal.mqh`: エントリー前提条件、注文タイプ別価格判定、M15フィルタ、リトライ状態更新。
- `Include/MyLib/Common/HITExternalProcess.mqh`: done/runningファイル、外部プロセスハンドル、PID復元、終了コード確認、タイムアウト復旧。
- `Include/MyLib/Signals/HITPythonSignalGateway.mqh`: OHLC CSV出力、Pythonバッチ起動、`trend_state.txt` / `target_prices.txt` / `target_zones.txt` 読込。
- `Include/MyLib/Trading/HITTradeManager.mqh`: 注文送信、執行ポリシー、有効期限設定、注文/ポジション数集計、期限切れ取消/クローズ。
- `Include/MyLib/Trading/SLTPManager.mqh`: 既存ポジションに対するブレークイーブン、時間経過BE、アクティブトレーリング、TP進捗SL、急変時SL引き締めを管理する。
- `Include/MyLib/Panel/SLTPManagerPanel.mqh`: `CSLTPManager` の各設定をチャート上で切り替え、数値入力を検証してEAへ反映する操作パネル。

## 5. Python連携ファイル

EAは `OnInit()` で `_Symbol` と `magic_number` から `HIT_<sanitized symbol>_<magic_number>` 形式の接頭辞を作り、MT5 `Files` 配下の連携ファイル名へ付与する。例: `HIT_GOLD_10001_ohlc_H4.csv`。batには同じ接頭辞を第1引数で渡し、bat側が `MT5_EA_FILE_PREFIX` としてPythonへ引き継ぐ。

手動実行などで接頭辞が指定されない場合、Pythonは従来どおり `ohlc_H4.csv` などの旧ファイル名を使う。

### H4トレンド判定

- MQL5出力: `<prefix>_ohlc_H4.csv`
- Python出力: `<prefix>_trend_state.txt`
- 完了フラグ: `<prefix>_process_done_trend.txt`
- 実行中フラグ: `<prefix>_process_running_trend.txt`
- 起動バッチ: `<TerminalDataPath>\MQL5\python_for_ea\bat\get_trend_reply.bat`

### H1エントリー価格生成

- MQL5出力: `<prefix>_ohlc_H1.csv`
- Python出力: `<prefix>_target_prices.txt`, `<prefix>_target_zones.txt`
- 完了フラグ: `<prefix>_process_done_entry.txt`
- 実行中フラグ: `<prefix>_process_running_entry.txt`
- 起動バッチ: `<TerminalDataPath>\MQL5\python_for_ea\bat\get_entry_reply.bat`

EAは `OnInit()` で `TerminalInfoString(TERMINAL_DATA_PATH)` から `MQL5\python_for_ea` を解決し、各batファイルの絶対パスを組み立てる。batファイルは自身の位置からPythonプロジェクトルートを解決するため、`C:\ea_py` には依存しない。

`target_prices.txt` は13行構成とする。

```text
1行目: res_chk
2-4行目: T1 Buy Stop  の entry/tp/sl
5-7行目: T2 Buy Limit の entry/tp/sl
8-10行目: T3 Sell Stop の entry/tp/sl
11-13行目: T4 Sell Limit の entry/tp/sl
```

`target_zones.txt` は分割エントリー用の7行構成とする。

```text
1行目: schema_version（2）
2行目: res_chk
3行目: candidate_id（H1確定足時刻由来）
4行目: T1 Buy Stop  の strategy, zone_low, zone_high, tp, sl
5行目: T2 Buy Limit の strategy, zone_low, zone_high, tp, sl
6行目: T3 Sell Stop の strategy, zone_low, zone_high, tp, sl
7行目: T4 Sell Limit の strategy, zone_low, zone_high, tp, sl
```

Pythonは `target_prices.txt` と `target_zones.txt` の両方を書き終えてから `process_done_entry.txt` を作成する。分割エントリーが無効な場合、EAは従来どおり `target_prices.txt` を使用する。

## 6. エントリー条件

新規エントリーは、以下をすべて満たす場合のみ行う。

- スプレッドが `spread_limit` 以下。
- H4トレンド判定結果が完了済みで、`trend_state.txt` を読み込める。
- H1候補価格生成が完了済みで、`target_prices.txt` を読み込める。
- `res_chk = 1`。
- H1候補価格が `ENTRY_H1_LIMIT` 内で期限切れではない。
- H1候補価格の読込から `input_entry_max_candidate_age_minutes` 分を超えていない。
- 対象注文タイプの `entry/tp/sl` がすべて `0.0` より大きい。
- H4 `market_state` に対して注文タイプが許可されている。
- 注文タイプごとの価格整合条件とブローカー最小距離制約を満たす。
- `use_m15_entry_filter = true` の場合、T2/T4はM15確定足の方向・反発・接近条件を満たす。T1/T3は `use_m15_imbalance_confirmation = true` の場合にM15初動確認を満たす。
- 自EAの注文 + ポジション数が `input_position_limit` 未満。
- 分割エントリー有効時は `target_zones.txt` の `res_chk = 1`、予測ゾーンの価格整合、分割ロットの `SYMBOL_VOLUME_MIN/MAX/STEP` 適合、同一 `candidate_id` + slot の重複注文/ポジション不存在を満たす。

### market_state と注文タイプ

- `0 MARKET_LOW_VOL_RANGE`: T2 Buy Limit / T4 Sell Limit を許可。
- `1 MARKET_HIGH_VOL_RANGE`: T2 Buy Limit / T4 Sell Limit を許可。
- `2 MARKET_LOW_VOL_UP`: T1 Buy Stop / T2 Buy Limit を許可。
- `3 MARKET_HIGH_VOL_UP`: T1 Buy Stop / T2 Buy Limit を許可。
- `4 MARKET_LOW_VOL_DOWN`: T3 Sell Stop / T4 Sell Limit を許可。
- `5 MARKET_HIGH_VOL_DOWN`: T3 Sell Stop / T4 Sell Limit を許可。
- `6 MARKET_TECHNICAL_ERROR_STOP`: 新規注文を停止。

### 注文タイプごとの価格整合条件

- T1 Buy Stop: `Ask < entry`, `tp > entry`, `sl < entry`
- T2 Buy Limit: `Ask > entry`, `tp > entry`, `sl < entry`
- T3 Sell Stop: `Bid > entry`, `tp < entry`, `sl > entry`
- T4 Sell Limit: `Bid < entry`, `tp < entry`, `sl > entry`

## 7. エグジット条件

- 未約定注文は、注文作成時刻から `ENTRY_H1_LIMIT * PeriodSeconds(PERIOD_H1)` 以上経過した場合に取消する。
- 保有ポジションは、建玉時刻から `CLOSE_H1_LIMIT * PeriodSeconds(PERIOD_H1)` 以上経過した場合にクローズする。
- 時間制限処理は `OnTick` の早い段階で実行し、Python完了待ちやスプレッド判定に依存させない。
- EA削除時は `OnDeinit()` で外部プロセス状態とSLTPパネルを解放し、`Comment("")` と `ChartRedraw(0)` によりチャート上のステータス表示を消去する。
- `input_sltp_manager_enabled` またはパネルの `Manager` がONの場合、時間制限処理後に `CSLTPManager::ManagePositions()` と `HighVolatilityLimit()` を実行する。これにより、Python結果待ちや新規注文停止中でも既存ポジションのSL保護を継続する。
- 通常ブレークイーブンとアクティブトレーリングは同時有効化しない。パネル上では片方をONにするともう片方をOFFにし、`CSLTPManager::ValidateSettings()` でも排他条件を検証する。

## 7.1 SLTP操作パネル

- パネルは `input_sltp_show_panel = true` の場合に作成され、チャート右上に表示される。
- パネル生成に失敗した場合はログへ出力し、EA本体はinputで反映済みのSLTP設定のまま継続する。
- `Manager` ボタンでSLTP管理全体のON/OFFを切り替える。OFFの場合、パネル値は保持するが `OnTick` でSL変更は行わない。
- `BreakEven`, `Elapsed BE`, `Active Trail`, `TP Progress`, `High Vol` ボタンで各機能を切り替える。
- 数値入力欄は `APPLY` 押下時に範囲検証される。範囲外または数値以外の場合は `MessageBox` とログで通知し、直前の有効値へ戻す。
- `APPLY` 成功時のみEA内部の `CSLTPManager` 設定へ反映する。反映後は `ValidateSettings()` を通し、失敗した場合はSLTP管理を停止してログへ理由を出力する。

## 8. リスク管理

- 注文/ポジション管理対象は `_Symbol` と `magic_number` が一致するものに限定する。
- `input_position_limit` は口座全体ではなく、自EA対象分のみを数える。内部の絶対上限は `POSITION_LIMIT` とする。
- 送信時は `SYMBOL_FILLING_MODE` を参照し、IOC、FOK、RETURNの順で利用可能な執行ポリシーを選択する。
- ペンディング注文には、ブローカーが対応する場合にサーバー側の期限を設定する。
- `OrderSend` の戻り値と `MqlTradeResult.retcode` を確認し、失敗時は `GetLastError()` またはretcodeをログへ出力する。
- 分割エントリーの注文コメントには `candidate_id` とslot番号を入れ、同一slotの二重発注を抑止する。
- `cancel_old_split_pending_on_new_zone = true` の場合、新しい有効 `candidate_id` を読んだ時は旧candidateの分割pending注文を取消し、`target_zones.txt` が無効または停止値の場合は既存の分割pending注文をすべて取消する。
- SLTP管理は `_Symbol` と `magic_number` が一致する既存ポジションのみを対象とし、TPは既存値を維持する。
- SL変更は既存SLより利益保護方向へ改善する場合だけ実行し、ブローカーのstop level / freeze levelを満たさない候補は送信しない。

## 9. 異常系の扱い

- `trend_state.txt` が存在しない、読み込めない、整数として厳格にパースできない、または `0..6` 以外の場合は `MARKET_TECHNICAL_ERROR_STOP` として扱う。
- `target_prices.txt` が存在しない、読み込めない、13行未満、またはいずれかの行が数値として厳格にパースできない場合は `res_chk = 0` として扱う。
- 分割エントリー有効時に `target_zones.txt` が存在しない、schema不一致、7行未満、`res_chk != 1`、またはいずれかの数値行を厳格にパースできない場合は新規注文を停止する。
- Pythonプロセスが異常終了した場合、終了コードをログへ出力し、次回トリガーで再実行できる状態に戻す。
- `running` ファイルだけが残っている場合は、PIDからプロセス復元を試みる。復元できずタイムアウト済みなら古いマーカーとして削除する。

## 10. 変更履歴

### 2026-05-30

- 同一Terminal内の複数EA/複数シンボルでPython連携ファイルが衝突しないよう、`HIT_<symbol>_<magic_number>` 接頭辞をMT5/Python双方のファイル名へ適用する仕様に更新した。
- T1/T3の順張り候補でも `use_m15_imbalance_confirmation = true` の場合はM15初動確認を必須とする仕様に更新した。
- `trend_state.txt`、`target_prices.txt`、`target_zones.txt` の数値読込を厳格化し、不正値は安全側の停止値として扱う仕様を追加した。
- `target_zones.txt` が無効または停止値の場合に、古い分割pending注文を全取消できる仕様を追加した。
- 現行コードに合わせて、`input_entry_max_candidate_age_minutes`、`ENTRY_H1_LIMIT`、SLTPバッファ、Python側距離ガードの既定値を修正した。

### 2026-05-27

- Python補助アプリの配置を `C:\ea_py` からMT5データフォルダ配下の `MQL5\python_for_ea` へ移行する仕様に変更した。
- EA側は `TerminalInfoString(TERMINAL_DATA_PATH)` からbatパスを組み立て、外部プロセスの作業ディレクトリはbatファイルの配置から導出するようにした。
- Python側は `MQL5\python_for_ea` の親にある `MQL5\Files` を既定の連携先として自動検出し、必要に応じて `MT5_FILES_DIR` または `MT5_DATA_PATH` で上書きできる仕様にした。

### 2026-05-24

- Python側で `target_zones.txt` を追加出力し、既存 `target_prices.txt` と両方を書き終えてから `process_done_entry.txt` を作成する仕様にした。
- EA側に `use_split_entry_zone`、`split_entry_count`、`split_lot_mode`、`split_total_lot_size`、`split_fixed_lot_size`、`input_position_limit` を追加した。
- 分割エントリー有効時は、H1予測ゾーンをN本に分割し、総ロット分割または固定ロットでpending注文を出せるようにした。
- `candidate_id` + slot番号で分割注文を識別し、同一slotの二重発注を抑止する仕様を追加した。

### 2026-05-13

- Python側にH1 EATRベースの候補距離ガードを追加し、現在価格から遠すぎる候補をMT5へ渡す前に無効化する仕様を追加。
- EA側に `input_entry_max_candidate_age_minutes` を追加し、M15確認が遅れて整った古いH1候補で新規発注しないようにした。
- エントリー見送りログへH1候補の経過秒数を追加し、遅延・M15未確認・価格不整合の原因を追跡しやすくした。

### 2026-05-05

- EA削除後にチャート左上のステータスコメントが残らないよう、`OnDeinit()` で `Comment("")` と `ChartRedraw(0)` を実行する終了処理を追加。
- `HIT-EA_refactor_ver5.mq5` に `CSLTPManager` と専用チャートパネル `SLTPManagerPanel.mqh` を接続し、UIからブレークイーブン、時間経過BE、アクティブトレーリング、TP進捗SL、急変時SL引き締めを操作できるようにした。
- SLTP管理を `OnTick` の時間制限処理直後に実行し、Python結果待ちやスプレッド判定に依存せず既存ポジション保護を継続する仕様を追加。
- SLTPパネル用inputと、通常ブレークイーブン/アクティブトレーリングの排他検証、`APPLY` 時の数値検証を追加。
- `HIT-EA_refactor_ver5.mq5` の関数群を用途別 `.mqh` に分割。
- `OnInit`, `OnDeinit`, `OnTick`、input、グローバル状態はEA本体に残し、動作ロジックは `Include/MyLib/` 配下へ移動。
- 現行コードに合わせて、`CreateProcessW` ベースのPythonプロセス監視、M15フィルタ、`market_state` 0..6、`spread_limit = 60` を仕様へ反映。

### 2026-05-02

- `res_chk=0` 時にエントリー送信を抑止する分岐を追加。
- 時間制限処理を、Python完了待ち・スプレッド制限より前に移動。
- `initial_order` の初回処理フラグをH4用・H1用に分離。
- OHLC取得を `CopyRates` 中心に変更し、確定足のみをPythonへ渡す仕様に変更。
