# Codex用 MQL5 SL/TP管理ファイル作成指示

## 目的

`TradingPanelTradingManagers.mqh` を参考にして、他のEAでも再利用できる
SL/TP管理用の共通 `.mqh` ファイルを作成する。

作成ファイル名の例：

```text
SLTPManager.mqh
```

このファイルは、EA本体から `#include` して使用できる構成にする。

---

## 基本方針

- MQL5で実装する。
- `CTrade` を使用してポジションのSL/TPを更新する。
- 既存EAに依存しすぎない汎用的な設計にする。
- クラス化して、他EAから再利用しやすい構成にする。
- TPは原則として変更しない。
- SL更新のみを行う。
- エラー時は `Print()` で分かりやすくログを出力する。
- コンパイルエラーが出ないMQL5コードにする。

---

## 管理対象ポジション

以下の条件を満たすポジションのみ管理対象にする。

1. `POSITION_MAGIC` が指定された magic number と一致する
2. `POSITION_SYMBOL` が指定された symbol と一致する

実装では `PositionsTotal()` を使用して全ポジションを走査し、
条件に一致するポジションのみ処理する。

BUY / SELL の両方に対応する。

---

## BUY / SELL の基準価格

利益pipsやSL更新位置の計算では、BUY / SELL の方向を正しく扱う。

- BUYポジション
  - 現在価格は `Bid` を基準にする。
  - 利益方向は価格上昇方向。
- SELLポジション
  - 現在価格は `Ask` を基準にする。
  - 利益方向は価格下落方向。

---

## pips計算

pipsから価格差への変換関数を用意する。

例：

- 5桁・3桁銘柄では `Point * 10`
- 4桁・2桁銘柄では `Point`

ただし、XAUUSDなどの銘柄でも使えるように、
対象シンボルの以下の情報を使用して計算する。

```mql5
SYMBOL_DIGITS
SYMBOL_POINT
```

---

## SL更新時の安全条件

SLは不利な方向へ戻さない。

BUYの場合：

- 新しいSLが現在SLより上の場合のみ更新する。
- 現在SLが未設定の場合は更新可能。

SELLの場合：

- 新しいSLが現在SLより下の場合のみ更新する。
- 現在SLが未設定の場合は更新可能。

また、以下も考慮する。

- `SYMBOL_TRADE_STOPS_LEVEL`
- `SYMBOL_TRADE_FREEZE_LEVEL`
- `NormalizeDouble()`
- `PositionModify()` 失敗時のログ出力

---

# 機能要件

## 1. 通常ブレークイーブン機能

ブレークイーブン設定を実装する。

### パラメーター例

```mql5
bool use_breakeven;
double breakeven_trigger_pips;
double breakeven_offset_pips;
```

### 動作

- `use_breakeven == true` の場合のみ動作する。
- 現在利益が `breakeven_trigger_pips` 以上になったらSLを建値付近へ移動する。
- SLの移動先は以下とする。

BUYの場合：

```text
entry_price + breakeven_offset_pips
```

SELLの場合：

```text
entry_price - breakeven_offset_pips
```

---

## 2. アクティブ・ブレークイーブン兼トレーリング機能

ブレークイーブン到達後に、段階的にSLを更新する機能を実装する。

### パラメーター

```mql5
bool use_active_trailing;
double active_breakeven_pips;
double active_stop_loss_offset_pips;
double active_step_trigger_pips;
double active_step_move_pips;
```

### パラメーターの意味

#### `active_breakeven_pips`

建値移動を開始する利益幅をpipsで指定する。

#### `active_stop_loss_offset_pips`

確保する利益として、建値からずらす幅をpipsで指定する。

#### `active_step_trigger_pips`

トレーリングを1段進めるために必要な利益間隔をpipsで指定する。

#### `active_step_move_pips`

1段ごとにSLを移動する幅をpipsで指定する。

### 動作

- `use_active_trailing == true` の場合のみ動作する。
- 利益が `active_breakeven_pips` に到達したら、まずSLを建値付近へ移動する。
- その後、利益が `active_step_trigger_pips` 増えるごとに、SLを `active_step_move_pips` ずつ利益方向へ移動する。
- SLは不利な方向へ戻さない。

### 計算例

BUYの場合：

```text
entry_price = 100.000
active_breakeven_pips = 20
active_stop_loss_offset_pips = 2
active_step_trigger_pips = 10
active_step_move_pips = 5
```

利益が20pips到達：

```text
SL = entry_price + 2pips
```

利益が30pips到達：

```text
SL = entry_price + 7pips
```

利益が40pips到達：

```text
SL = entry_price + 12pips
```

SELLの場合は逆方向で計算する。

---

## 3. 通常ブレークイーブンとアクティブトレーリングの排他制御

以下の2つは同時にONにできない。

```mql5
use_breakeven
use_active_trailing
```

両方が `true` の場合は、初期化時にエラーとして扱う。

例：

```mql5
bool ValidateSettings()
```

を用意し、両方ONの場合は `false` を返して `Print()` でエラーを出す。

EA側では `ValidateSettings()` が `false` の場合、`INIT_FAILED` を返す想定にする。

---

## 4. TP到達率に応じたSL更新機能

建値とTPの距離に対する現在価格の到達割合に応じて、SLを更新する機能を実装する。

### パラメーター例

```mql5
bool use_tp_progress_stop;
double tp_progress_trigger_percent;
double tp_progress_sl_lock_percent;
```

### 動作

- `use_tp_progress_stop == true` の場合のみ動作する。
- TPが設定されているポジションのみ対象にする。
- エントリー価格からTPまでの距離を100%とする。
- 現在価格が `tp_progress_trigger_percent` に到達したら、SLを `tp_progress_sl_lock_percent` の位置へ移動する。
- 通常ブレークイーブン、アクティブトレーリングとは独立して動作する。
- ただし、SLは不利な方向へ戻さない。

### BUYの例

```text
entry_price = 100.000
take_profit = 110.000
tp_progress_trigger_percent = 50
tp_progress_sl_lock_percent = 20
```

現在価格が105.000に到達したら、SLを102.000へ移動する。

### SELLの例

```text
entry_price = 100.000
take_profit = 90.000
tp_progress_trigger_percent = 50
tp_progress_sl_lock_percent = 20
```

現在価格が95.000に到達したら、SLを98.000へ移動する。

---

## 5. 複数条件が同時に成立した場合

複数のSL更新候補がある場合は、最も有利なSLのみを採用する。

BUYの場合：

- 候補SLの中で最も高い価格を採用する。

SELLの場合：

- 候補SLの中で最も低い価格を採用する。

その上で、現在SLより有利な場合のみ `PositionModify()` を実行する。

---

# 想定するクラス構成

例：

```mql5
class CSLTPManager
{
private:
   ulong  m_magic;
   string m_symbol;

public:
   CSLTPManager();

   void SetMagicNumber(ulong magic);
   void SetSymbol(string symbol);

   bool ValidateSettings();
   void ManagePositions();

private:
   bool IsTargetPosition();
   double PipToPrice(double pips);
   double GetProfitPips(ENUM_POSITION_TYPE type, double open_price);
   bool ModifyStopLoss(ulong ticket, double new_sl, double current_tp);

   bool CalcBreakevenSL(...);
   bool CalcActiveTrailingSL(...);
   bool CalcTpProgressSL(...);
};
```

実際の引数や構成は、MQL5としてコンパイルしやすい形に調整してよい。

---

# EA側での使用例

作成した `.mqh` をEAから利用する簡単なサンプルも作成する。

```mql5
#include "SLTPManager.mqh"

input ulong MagicNumber = 123456;

CSLTPManager sltp_manager;

int OnInit()
{
   sltp_manager.SetMagicNumber(MagicNumber);
   sltp_manager.SetSymbol(_Symbol);

   if(!sltp_manager.ValidateSettings())
   {
      Print("SLTPManager settings are invalid.");
      return INIT_FAILED;
   }

   return INIT_SUCCEEDED;
}

void OnTick()
{
   sltp_manager.ManagePositions();
}
```

---

# 注意事項

- 既存ポジションのTPは変更しない。
- SL更新に失敗した場合は、以下をログ出力する。
  - ticket番号
  - symbol
  - magic number
  - エラーコード
- BUYとSELLの計算方向を間違えない。
- 現在SLより不利なSLには更新しない。
- TP未設定のポジションではTP到達率によるSL更新は行わない。
- `PositionModify()` 前に価格を `NormalizeDouble()` する。
- `SYMBOL_TRADE_STOPS_LEVEL` と `SYMBOL_TRADE_FREEZE_LEVEL` を考慮する。
- コンパイルエラーが出ないMQL5コードにする。

---

# 実装時の推奨判断

| 項目 | 方針 |
|---|---|
| `use_breakeven` と `use_active_trailing` が両方ON | `ValidateSettings()` で `false` を返す |
| EA初期化時に設定エラー | `INIT_FAILED` にする |
| TP到達率SLとブレークイーブンが同時成立 | より有利なSLを採用 |
| TP未設定時 | TP到達率SLはスキップ |
| SL未設定時 | 条件成立なら新規設定 |
| TP変更 | しない |
| 対象ポジション | magic number + symbol 一致のみ |
