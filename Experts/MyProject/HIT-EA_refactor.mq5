//+------------------------------------------------------------------+
//|                                                       HIT_EA.mq5 |
//|                               Copyright 2026,  nanpin-martin.com |
//|                                    https://www.nanpin-martin.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, nanpin-martin.com"
#property link      "https://nanpin-martin.com/"
#property version   "1.01"

//+------------------------------------------------------------------+
//| バッチファイル実行用の設定
//+------------------------------------------------------------------+

#import "Shell32.dll"
int ShellExecuteW(int hwnd, string lpOperation, string lpFile, string lpParameters, string lpDirectory, int nShowCmd);
#import

// バッチファイルのパス
string get_trend_reply_bat = "C:\\ea_py\\get_trend_reply.bat"; // H4: trend
string get_entry_reply_bat = "C:\\ea_py\\get_entry_reply.bat"; // H1: entry

// プロセス完了ファイルの設定
string done_trend_file = "process_done_trend.txt";
string done_entry_file = "process_done_entry.txt";

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| インプットの設定
//+------------------------------------------------------------------+

//--- 入力パラメータ
input double lot_size      = 0.01;  // ロット数
input double spread_limit  = 60;    // 許容スプレッド(point)
input int    magic_number  = 10001; // マジックナンバー
input int    initial_order = 0;     // 起動時の注文(0:なし, 1:あり)
ulong  slippage      = 10;          // スリッページ

//--- 主要な定数・設定
#define POSITION_LIMIT        48
#define ENTRY_H1_LIMIT        1         // H1本数（=1時間）
#define CLOSE_H1_LIMIT        12        // H1本数（=12時間）
#define HISTORY_BARS          72
#define OHLC_START_SHIFT       1         // 1: 確定足のみをPythonへ渡す
// ANALYZE_TIMEFRAME は削除（H4/H1 両方使うため定数ではなく直接指定）
#define TARGET_SIZE           13
#define DEFAULT_TARGET_PRICE  0.0

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| EAの状態をまとめる構造体
//+------------------------------------------------------------------+

struct EAState
  {
   int               trend_state;           // ★追加：トレンドを格納する変数
   int               res_chk;               // GPTの回答が正しく取得できたか
   double            en_price[5];           // エントリー基準価格
   double            tp_price[5];           // 利益確定価格
   double            sl_price[5];           // ロスカット基準価格
   bool              load_trend_flg;        // ★変更：トレンドを更新するタイミングか
   bool              load_target_flg;       // ★変更：ターゲット価格を更新するタイミングか
   int               chk_cnt;               // エントリー判定の試行回数
   datetime          last_trend_update;     // ★追加：前回トレンドを更新した時刻
   datetime          last_target_update;    // ★変更：前回ターゲット価格を更新した時刻
   datetime          last_chk;
  };

EAState g_ea;  // EA全体の状態をここで管理

// initial_order 用の初回処理フラグ
// H4トレンド処理とH1エントリー処理で別々に管理し、初回起動時の再実行ループを防ぐ。
bool g_init_trend_pending = false;
bool g_init_entry_pending = false;

// H4/H1のバー更新状態
int  g_pre_bars_H4   = 0;
int  g_pre_bars_H1   = 0;
bool g_bars_H1_check = false;

// ティックごとの価格情報
struct TickContext
  {
   double            ask;
   double            bid;
   double            spread;
   double            spread_points;
   int               digits;
  };

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 起動時の処理
//+------------------------------------------------------------------+
/**
 * @brief EA起動時の初期化処理を行います。
 *
 * Python連携用のdoneファイルを作成し、`initial_order` が有効な場合は
 * H4トレンド判定とH1エントリー価格生成をそれぞれ初回実行対象にします。
 * H4/H1の初回フラグを分けることで、起動直後にH4処理だけが繰り返される状態を防ぎます。
 */
void OnInit()
// プロセス完了ファイル("process_done_trend.txt" または "process_done_entry.txt")を作成
  {
   CreateDoneFile(done_trend_file);
   CreateDoneFile(done_entry_file);

   // initial_order=1 の場合でも、H4/H1を別々に1回だけ初回実行する。
   g_init_trend_pending = (initial_order == 1);
   g_init_entry_pending = (initial_order == 1);
  }

//+------------------------------------------------------------------+
//| ティック毎の処理
//+------------------------------------------------------------------+
/**
 * @brief ティック受信ごとにEA全体の処理を制御します。
 *
 * 処理順序は、ティック情報取得、期限切れ注文/ポジション管理、H4トレンド更新、
 * H1エントリー価格更新、ステータス表示、新規注文判定の順です。
 * 時間制限処理はPython完了待ちやスプレッド判定より前に実行します。
 */
void OnTick()
  {
   TickContext ctx;
   if(!GetTickContext(ctx))
      return;

   // 期限切れ注文・ポジションは、Python待ちやスプレッド制限に関係なく先に処理する。
   ManageExpiredTrades();

   // H4新バーまたは初回起動時に、トレンド判定用Pythonを起動する。
   ProcessTrendUpdate(g_ea);

   // トレンド判定が完了していない場合、新規注文側の処理だけをスキップする。
   if(!IsTrendResultReady())
      return;

   RefreshTrendState(g_ea);

   // H1新バーまたは初回起動時に、エントリー価格生成用Pythonを起動する。
   ProcessEntryUpdate(g_ea);

   UpdateStatusComment(ctx);

   // ここから下は新規注文に関する処理。
   if(!IsSpreadAllowed(ctx))
      return;

   if(!IsEntryResultReady())
      return;

   RefreshTargetPrices(g_ea);
   ProcessEntryDecisionIfNeeded(g_ea, ctx);
  }

//+------------------------------------------------------------------+
//| ティック情報を取得する関数
//+------------------------------------------------------------------+
/**
 * @brief 現在のAsk/Bid/スプレッド情報を取得してTickContextへ格納します。
 *
 * @param ctx 取得したティック情報を格納する構造体参照。
 * @return 取得成功時はtrue、ティック情報を取得できない場合はfalse。
 */
bool GetTickContext(TickContext &ctx)
  {
   MqlTick last_tick;
   if(!SymbolInfoTick(_Symbol, last_tick))
      return false;

   ctx.ask           = last_tick.ask;
   ctx.bid           = last_tick.bid;
   ctx.spread_points = MathRound((ctx.ask - ctx.bid) / Point());
   ctx.spread        = ctx.spread_points * Point();
   ctx.digits        = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   return true;
  }

//+------------------------------------------------------------------+
//| 期限切れ注文・期限切れポジションを処理する関数
//+------------------------------------------------------------------+
/**
 * @brief 期限切れの未約定注文と保有ポジションを処理します。
 *
 * 未約定注文はENTRY_H1_LIMIT、保有ポジションはCLOSE_H1_LIMITを基準に判定します。
 * 新規注文条件とは独立して、OnTickの早い段階で実行される想定です。
 */
void ManageExpiredTrades()
  {
   if(OrdersTotal() > 0)
      CancelExpiredOrders();

   if(PositionsTotal() > 0)
      CloseExpiredPositions();
  }

//+------------------------------------------------------------------+
//| H4更新検知とトレンド判定Python起動を処理する関数
//+------------------------------------------------------------------+
/**
 * @brief H4新バーまたは初回起動を検知し、トレンド判定Pythonを起動します。
 *
 * @param state EA全体の状態。トレンド更新開始フラグを更新します。
 *
 * Python処理中はdoneファイルが存在しないため、CSVの上書きと二重起動を抑止します。
 */
void ProcessTrendUpdate(EAState &state)
  {
   int current_bars_H4 = iBars(NULL, PERIOD_H4);
   if(g_pre_bars_H4 == 0)
      g_pre_bars_H4 = current_bars_H4;

   int  bars_H4_change = current_bars_H4 - g_pre_bars_H4;
   bool trend_trigger  = (bars_H4_change > 0 || g_init_trend_pending);

   if(!trend_trigger)
      return;

   if(RecordOHLCAndExecuteBatch_Trend(state))
     {
      g_init_trend_pending = false;
      g_pre_bars_H4        = current_bars_H4;
     }
  }

//+------------------------------------------------------------------+
//| トレンド判定Pythonの完了状態を返す関数
//+------------------------------------------------------------------+
/**
 * @brief H4トレンド判定Pythonの完了状態を確認します。
 *
 * @return `process_done_trend.txt` が存在する場合はtrue、未完了の場合はfalse。
 */
bool IsTrendResultReady()
  {
   return CheckDoneFile(done_trend_file);
  }

//+------------------------------------------------------------------+
//| トレンド判定結果をEA状態へ反映する関数
//+------------------------------------------------------------------+
/**
 * @brief 完了済みのH4トレンド判定結果をEA状態へ反映します。
 *
 * @param state EA全体の状態。`trend_state` と最終更新時刻が更新されます。
 */
void RefreshTrendState(EAState &state)
  {
   GetTrendState(state);
  }

//+------------------------------------------------------------------+
//| H1更新検知とエントリー価格生成Python起動を処理する関数
//+------------------------------------------------------------------+
/**
 * @brief H1新バーまたは初回起動を検知し、エントリー価格生成Pythonを起動します。
 *
 * @param state EA全体の状態。ターゲット価格更新開始フラグや判定リトライ状態を更新します。
 *
 * Python処理中はdoneファイルが存在しないため、H1 CSVの上書きと二重起動を抑止します。
 */
void ProcessEntryUpdate(EAState &state)
  {
   int current_bars_H1 = iBars(NULL, PERIOD_H1);
   if(g_pre_bars_H1 == 0)
      g_pre_bars_H1 = current_bars_H1;

   int  bars_H1_change = current_bars_H1 - g_pre_bars_H1;
   bool entry_trigger  = (bars_H1_change > 0 || g_init_entry_pending);

   if(!entry_trigger)
      return;

   if(RecordOHLCAndExecuteBatch_Entry(state))
     {
      g_init_entry_pending = false;
      g_bars_H1_check      = true;
      state.chk_cnt        = 0;
      state.last_chk       = 0;
      g_pre_bars_H1        = current_bars_H1;
     }
  }

//+------------------------------------------------------------------+
//| チャートコメント文字列を作成する関数
//+------------------------------------------------------------------+
/**
 * @brief チャート左上に表示するステータスメッセージを組み立てます。
 *
 * @param ctx 現在のAsk/Bid/スプレッド情報。
 * @return Comment()へ渡す表示用文字列。
 */
string BuildStatusMessage(TickContext &ctx)
  {
   string message = StringFormat(
                       " \nAsk: %." + IntegerToString(ctx.digits) + "f"
                       "\nBid: %." + IntegerToString(ctx.digits) + "f"
                       "\nSpread: %." + IntegerToString(ctx.digits) + "f"
                       "\nSpread Points: %.0f"
                       "\n\nLast Trend Update:\n %s"
                       "\n\nTrend State: %d"
                       "\n\nLast Target Update:\n %s"
                       "\n\nMy Used Count: %d / %d"
                       "\n\n[T1 Buy Stop ] en: %." + IntegerToString(ctx.digits) + "f  tp: %." + IntegerToString(ctx.digits) + "f  sl: %." + IntegerToString(ctx.digits) + "f"
                       "\n[T2 Buy Limit] en: %." + IntegerToString(ctx.digits) + "f  tp: %." + IntegerToString(ctx.digits) + "f  sl: %." + IntegerToString(ctx.digits) + "f"
                       "\n[T3 Sell Stop] en: %." + IntegerToString(ctx.digits) + "f  tp: %." + IntegerToString(ctx.digits) + "f  sl: %." + IntegerToString(ctx.digits) + "f"
                       "\n[T4 SellLimit] en: %." + IntegerToString(ctx.digits) + "f  tp: %." + IntegerToString(ctx.digits) + "f  sl: %." + IntegerToString(ctx.digits) + "f\n",
                       ctx.ask, ctx.bid, ctx.spread, ctx.spread_points,
                       TimeToString(g_ea.last_trend_update, TIME_DATE | TIME_MINUTES),
                       g_ea.trend_state,
                       TimeToString(g_ea.last_target_update, TIME_DATE | TIME_MINUTES),
                       CountMyUsed(), POSITION_LIMIT,
                       g_ea.en_price[1], g_ea.tp_price[1], g_ea.sl_price[1],
                       g_ea.en_price[2], g_ea.tp_price[2], g_ea.sl_price[2],
                       g_ea.en_price[3], g_ea.tp_price[3], g_ea.sl_price[3],
                       g_ea.en_price[4], g_ea.tp_price[4], g_ea.sl_price[4]
                    );
   return message;
  }

//+------------------------------------------------------------------+
//| チャートコメントを更新する関数
//+------------------------------------------------------------------+
/**
 * @brief チャート上のステータスコメントを更新します。
 *
 * @param ctx 現在のAsk/Bid/スプレッド情報。
 */
void UpdateStatusComment(TickContext &ctx)
  {
   Comment(BuildStatusMessage(ctx));
  }

//+------------------------------------------------------------------+
//| スプレッドが許容範囲内か判定する関数
//+------------------------------------------------------------------+
/**
 * @brief 現在スプレッドが入力パラメータの許容範囲内か判定します。
 *
 * @param ctx 現在のスプレッド情報。
 * @return 許容範囲内ならtrue、超過している場合はfalse。
 */
bool IsSpreadAllowed(TickContext &ctx)
  {
   return (ctx.spread <= spread_limit * Point());
  }

//+------------------------------------------------------------------+
//| エントリー価格生成Pythonの完了状態を返す関数
//+------------------------------------------------------------------+
/**
 * @brief H1エントリー価格生成Pythonの完了状態を確認します。
 *
 * @return `process_done_entry.txt` が存在する場合はtrue、未完了の場合はfalse。
 */
bool IsEntryResultReady()
  {
   return CheckDoneFile(done_entry_file);
  }

//+------------------------------------------------------------------+
//| ターゲット価格をEA状態へ反映する関数
//+------------------------------------------------------------------+
/**
 * @brief 完了済みのH1エントリー価格生成結果をEA状態へ反映します。
 *
 * @param state EA全体の状態。`res_chk` と各注文タイプのen/tp/slが更新されます。
 */
void RefreshTargetPrices(EAState &state)
  {
   GetTargetPrices(state);
  }

//+------------------------------------------------------------------+
//| エントリー判定が必要な場合のみ注文処理を実行する関数
//+------------------------------------------------------------------+
/**
 * @brief エントリー判定タイミングに到達している場合のみ注文処理を実行します。
 *
 * @param state EA全体の状態。
 * @param ctx 現在のAsk/Bid/スプレッド情報。
 *
 * 判定前チェック、許可注文の送信、リトライ状態更新をまとめて制御します。
 */
void ProcessEntryDecisionIfNeeded(EAState &state, TickContext &ctx)
  {
   if(!ShouldRunEntryDecision(state))
      return;

   g_bars_H1_check = false;
   state.last_chk  = TimeCurrent();

   if(!ValidateEntryPreconditions(state))
      return;

   int sent_success = SendAllowedEntryOrders(state, ctx);
   UpdateEntryRetryState(state, sent_success);
  }

//+------------------------------------------------------------------+
//| エントリー判定を実行するタイミングか判定する関数
//+------------------------------------------------------------------+
/**
 * @brief エントリー判定を実行するタイミングか確認します。
 *
 * @param state EA全体の状態。前回判定時刻を参照します。
 * @return H1更新後、かつ前回判定から60秒以上経過していればtrue。
 */
bool ShouldRunEntryDecision(EAState &state)
  {
   return (g_bars_H1_check && TimeCurrent() - state.last_chk >= 60);
  }

//+------------------------------------------------------------------+
//| エントリー判定前の共通チェックを行う関数
//+------------------------------------------------------------------+
/**
 * @brief 新規注文前の共通条件を検証します。
 *
 * @param state EA全体の状態。
 * @return 注文判定を続行できる場合はtrue、停止すべき場合はfalse。
 *
 * `res_chk`、`trend_state`、対象EAの注文/ポジション数上限を確認します。
 */
bool ValidateEntryPreconditions(EAState &state)
  {
   if(state.res_chk != 1)
     {
      Print("[Entry Skip] target_prices invalid. res_chk=", state.res_chk);
      state.chk_cnt = 0;
      return false;
     }

   if(state.trend_state == 0)
     {
      Print("[Entry Skip] trend_state=0 (range). No entry orders are sent.");
      state.chk_cnt = 0;
      return false;
     }

   if(state.trend_state != 1 && state.trend_state != 2)
     {
      Print("[Entry Skip] invalid trend_state=", state.trend_state);
      state.chk_cnt = 0;
      return false;
     }

   int used = CountMyUsed();
   if(used >= POSITION_LIMIT)
     {
      Print("Position limit exceeded: used=", used, " limit=", POSITION_LIMIT);
      return false;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| 許可された注文タイプだけを順番に送信する関数
//+------------------------------------------------------------------+
/**
 * @brief H4トレンド方向で許可された注文タイプだけを順番に送信します。
 *
 * @param state EA全体の状態。各注文タイプのen/tp/slを参照します。
 * @param ctx 現在のAsk/Bid/スプレッド情報。
 * @return 送信成功した注文数。
 */
int SendAllowedEntryOrders(EAState &state, TickContext &ctx)
  {
   int sent_success = 0;

   for(int t = 1; t <= 4; t++)
     {
      int used = CountMyUsed();
      if(used >= POSITION_LIMIT)
        {
         Print("Position limit reached while sending. used=", used, " limit=", POSITION_LIMIT);
         break;
        }

      if(!IsOrderTypeAllowedByTrend(t, state.trend_state))
        {
         Print("[Skip] orderType=", t, " not allowed by trend_state=", state.trend_state);
         continue;
        }

      if(TrySendEntryOrder(t, state, ctx))
         sent_success++;
     }

   return sent_success;
  }

//+------------------------------------------------------------------+
//| 注文タイプ1件分の価格検証と注文送信を行う関数
//+------------------------------------------------------------------+
/**
 * @brief 注文タイプ1件分の価格検証と注文送信を行います。
 *
 * @param orderType 注文タイプ。1=Buy Stop、2=Buy Limit、3=Sell Stop、4=Sell Limit。
 * @param state EA全体の状態。対象注文タイプのen/tp/slを参照します。
 * @param ctx 現在のAsk/Bid情報。
 * @return 注文送信に成功した場合はtrue、それ以外はfalse。
 */
bool TrySendEntryOrder(const int orderType, EAState &state, TickContext &ctx)
  {
   string entry_type = EntryTypeName(orderType);
   double cur_price  = CurrentPriceForOrderType(orderType, ctx);

   double en = state.en_price[orderType];
   double tp = state.tp_price[orderType];
   double sl = state.sl_price[orderType];

   if(!HasValidTargetPrices(en, tp, sl))
     {
      Print("[Skip] invalid target prices. orderType=", orderType,
            " en=", en, " tp=", tp, " sl=", sl);
      return false;
     }

   bool ok = IsTargetPriceOrderConditionMatched(orderType, ctx, en, tp, sl);
   if(!ok)
     {
      Print("[No ", entry_type, "] cur=", cur_price, " en=", en, " tp=", tp, " sl=", sl);
      return false;
     }

   Print("[", entry_type, " Order Try at ", cur_price, "] en=", en, " tp=", tp, " sl=", sl);

   if(SendOrder(orderType, en, tp, sl))
     {
      Print("[", entry_type, " Order Sent] ticket ok. en=", en, " tp=", tp, " sl=", sl);
      return true;
     }

   Print("[", entry_type, " Order Failed] en=", en, " tp=", tp, " sl=", sl);
   return false;
  }

//+------------------------------------------------------------------+
//| 注文タイプ名を返す関数
//+------------------------------------------------------------------+
/**
 * @brief 注文タイプ番号に対応する表示名を返します。
 *
 * @param orderType 注文タイプ番号。
 * @return 注文タイプの表示名。不正値の場合は"Unknown"。
 */
string EntryTypeName(const int orderType)
  {
   switch(orderType)
     {
      case 1:
         return "Buy Stop";
      case 2:
         return "Buy Limit";
      case 3:
         return "Sell Stop";
      case 4:
         return "Sell Limit";
      default:
         return "Unknown";
     }
  }

//+------------------------------------------------------------------+
//| 注文タイプに応じた現在価格を返す関数
//+------------------------------------------------------------------+
/**
 * @brief 注文タイプに応じて価格比較に使う現在価格を返します。
 *
 * @param orderType 注文タイプ番号。
 * @param ctx 現在のAsk/Bid情報。
 * @return 買い系注文ではAsk、売り系注文ではBid。
 */
double CurrentPriceForOrderType(const int orderType, TickContext &ctx)
  {
   if(orderType == 1 || orderType == 2)
      return ctx.ask;

   return ctx.bid;
  }

//+------------------------------------------------------------------+
//| 注文タイプごとの価格整合条件を判定する関数
//+------------------------------------------------------------------+
/**
 * @brief 注文タイプごとの現在価格・エントリー・TP・SLの大小関係を検証します。
 *
 * @param orderType 注文タイプ番号。
 * @param ctx 現在のAsk/Bid情報。
 * @param en エントリー価格。
 * @param tp 利確価格。
 * @param sl 損切価格。
 * @return 注文タイプの価格条件を満たす場合はtrue。
 */
bool IsTargetPriceOrderConditionMatched(const int orderType, TickContext &ctx, const double en, const double tp, const double sl)
  {
   switch(orderType)
     {
      case 1: // Buy Stop
         return (ctx.ask < en && tp > en && sl < en);

      case 2: // Buy Limit
         return (ctx.ask > en && tp > en && sl < en);

      case 3: // Sell Stop
         return (ctx.bid > en && tp < en && sl > en);

      case 4: // Sell Limit
         return (ctx.bid < en && tp < en && sl > en);

      default:
         return false;
     }
  }

//+------------------------------------------------------------------+
//| 注文送信結果に応じてリトライ状態を更新する関数
//+------------------------------------------------------------------+
/**
 * @brief 注文送信結果に応じてエントリー判定のリトライ状態を更新します。
 *
 * @param state EA全体の状態。`chk_cnt` を更新します。
 * @param sent_success 今回送信に成功した注文数。
 *
 * 注文が1件も送信されなかった場合、最大10回まで60秒間隔で再判定します。
 */
void UpdateEntryRetryState(EAState &state, const int sent_success)
  {
   if(sent_success > 0)
     {
      state.chk_cnt = 0;
      return;
     }

   state.chk_cnt += 1;
   Print("[Retry] no order sent. chk_cnt=", state.chk_cnt, "/10");

   if(state.chk_cnt < 10)
     {
      g_bars_H1_check = true;  // 60秒後に再度エントリー判定を実行する
      return;
     }

   Print("[Retry End] reached max tries. reset chk_cnt.");
   state.chk_cnt = 0;
  }

//+------------------------------------------------------------------+
//| "process_done.txt"を作成する関数
//+------------------------------------------------------------------+
/**
 * @brief 指定したdoneファイルを作成します。
 *
 * @param name 作成するファイル名。MT5のMQL5\Files配下を基準に扱います。
 */
void CreateDoneFile(const string name)
  {
   if(!FileIsExist(name))
     {
      int h = FileOpen(name, FILE_WRITE|FILE_TXT);
      if(h != INVALID_HANDLE)
         FileClose(h);
      else
         Print("Failed to create file: ", name, " err=", GetLastError());
     }
  }

//+------------------------------------------------------------------+
//| "process_done.txt"を削除する関数
//+------------------------------------------------------------------+
/**
 * @brief 指定したdoneファイルを削除します。
 *
 * @param name 削除するファイル名。存在しない場合は何もしません。
 */
void DeleteDoneFile(const string name)
  {
   if(FileIsExist(name))
      FileDelete(name);
  }


//+------------------------------------------------------------------+
//| "process_done.txt"の存在を確認し、存在する場合はtrueを返す関数
//+------------------------------------------------------------------+
/**
 * @brief 指定したdoneファイルの存在有無を確認します。
 *
 * @param name 確認するファイル名。
 * @return ファイルが存在する場合はtrue、存在しない場合はfalse。
 */
bool CheckDoneFile(const string name)
  {
   return FileIsExist(name);
  }

//+------------------------------------------------------------------+
//| 最新のOHLCデータを取得する関数
//+------------------------------------------------------------------+
/**
 * @brief 指定時間足のOHLCデータを取得します。
 *
 * @param times 取得したバー時刻を格納する配列。
 * @param open_prices 取得したOpen価格を格納する配列。
 * @param high_prices 取得したHigh価格を格納する配列。
 * @param low_prices 取得したLow価格を格納する配列。
 * @param close_prices 取得したClose価格を格納する配列。
 * @param tf 取得対象の時間足。
 * @param bars_count 取得するバー本数。
 * @return 取得に成功した場合はtrue、失敗した場合はfalse。
 *
 * `OHLC_START_SHIFT=1` のため、形成中のバーではなく確定足から取得します。
 */
bool GetLatestOHLC(datetime &times[], double &open_prices[], double &high_prices[], double &low_prices[], double &close_prices[], ENUM_TIMEFRAMES tf, int bars_count)
  {
   ArrayResize(times, 0);
   ArrayResize(open_prices, 0);
   ArrayResize(high_prices, 0);
   ArrayResize(low_prices, 0);
   ArrayResize(close_prices, 0);

   if(bars_count < 2)
      return false;

// OHLCデータを取得
// CopyTime と CopyRates を別々に呼ばず、MqlRates の time/open/high/low/close を同一配列から取得する。
// OHLC_START_SHIFT=1 のため、形成中の0本目ではなく確定足からPythonへ渡す。
   MqlRates rates[];
   int copied = CopyRates(_Symbol, tf, OHLC_START_SHIFT, bars_count, rates);
   if(copied <= 0)
     {
      Print(__FUNCTION__, ": Failed to copy rates data (bars=", bars_count, ") err=", GetLastError());
      return false;
     }

   ArrayResize(times, copied);
   ArrayResize(open_prices, copied);
   ArrayResize(high_prices, copied);
   ArrayResize(low_prices, copied);
   ArrayResize(close_prices, copied);

// 必要なデータを配列に格納
   for(int i = 0; i < copied; i++)
     {
      times[i]        = rates[i].time;
      open_prices[i]  = rates[i].open;
      high_prices[i]  = rates[i].high;
      low_prices[i]   = rates[i].low;
      close_prices[i] = rates[i].close;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| "ohlc.csv"を出力する関数
//+------------------------------------------------------------------+
/**
 * @brief OHLC配列をPython入力用CSVとして出力します。
 *
 * @param filename 出力するCSVファイル名。
 * @param times バー時刻配列。
 * @param open_prices Open価格配列。
 * @param high_prices High価格配列。
 * @param low_prices Low価格配列。
 * @param close_prices Close価格配列。
 */
void RecordOHLC(const string filename, const datetime &times[], const double &open_prices[], const double &high_prices[], const double &low_prices[], const double &close_prices[])
  {
// 出力先ファイル名
//  string filename = "ohlc.csv";

// ファイルを "書き込みモード" でオープン (テキスト/ANSI)
   int fileHandle = FileOpen(filename, FILE_WRITE | FILE_TXT | FILE_ANSI);

// ファイルが開けたかチェック
   if(fileHandle == INVALID_HANDLE)
     {
      Print(__FUNCTION__, " : Failed to open file: ", GetLastError());
      return;
     }

// 配列サイズを取得 (times, open, high, low, close の要素数は同じ前提)
   int size = ArraySize(times);

// ヘッダー行を追加
   FileWrite(fileHandle, "Time,Open,High,Low,Close");

// 小数点の桁数を取得
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

// フォーマット文字列を動的に生成
   string formatString = StringFormat("%%s,%%.%df,%%.%df,%%.%df,%%.%df", digits, digits, digits, digits);

// 1行ずつ "時刻, Open, High, Low, Close" の形式で書き込み
   for(int i = 0; i < size; i++)
     {
      // 時間をフォーマット
      string timeStr = TimeToString(times[i], TIME_DATE | TIME_MINUTES);

      // 1行分の文字列を生成 (小数点以下の桁数を `digits` に調整)
      string line = StringFormat(formatString,
                                 timeStr, open_prices[i], high_prices[i], low_prices[i], close_prices[i]);

      // ファイルに書き込み (改行付き)
      FileWrite(fileHandle, line);
     }

// 書き込み終了後、ファイルを閉じる
   FileClose(fileHandle);
  }

//+------------------------------------------------------------------+
//| バッチファイル（Pythonスクリプト）を実行する関数
//+------------------------------------------------------------------+
/**
 * @brief H4トレンド判定用バッチファイルを起動します。
 *
 * @return 起動に成功した場合はtrue、Python実行中または起動失敗時はfalse。
 *
 * 起動直前に`process_done_trend.txt`を削除し、ShellExecuteW失敗時はdoneファイルを戻します。
 */
bool ExecuteBatchTrend()
  {
   if(!CheckDoneFile(done_trend_file))
     {
      Print("Trend batch is still running. Skip execute.");
      return false;
     }

   DeleteDoneFile(done_trend_file);
   int ret = ShellExecuteW(0, "open", get_trend_reply_bat, "", "", 1);
   if(ret <= 32)
     {
      Print("ShellExecuteW trend failed. ret=", ret, " file=", get_trend_reply_bat);
      CreateDoneFile(done_trend_file);
      return false;
     }

   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
/**
 * @brief H1エントリー価格生成用バッチファイルを起動します。
 *
 * @return 起動に成功した場合はtrue、Python実行中または起動失敗時はfalse。
 *
 * 起動直前に`process_done_entry.txt`を削除し、ShellExecuteW失敗時はdoneファイルを戻します。
 */
bool ExecuteBatchEntry()
  {
   if(!CheckDoneFile(done_entry_file))
     {
      Print("Entry batch is still running. Skip execute.");
      return false;
     }

   DeleteDoneFile(done_entry_file);
   int ret = ShellExecuteW(0, "open", get_entry_reply_bat, "", "", 1);
   if(ret <= 32)
     {
      Print("ShellExecuteW entry failed. ret=", ret, " file=", get_entry_reply_bat);
      CreateDoneFile(done_entry_file);
      return false;
     }

   return true;
  }


//+------------------------------------------------------------------+
//| "ohlc.csv"を出力後、バッチファイルの実行する関数
//+------------------------------------------------------------------+
/**
 * @brief H4 OHLCをCSV出力し、トレンド判定Pythonを起動します。
 *
 * @param state EA全体の状態。トレンド読込待ちフラグを更新します。
 * @return CSV出力とバッチ起動が開始できた場合はtrue。
 */
bool RecordOHLCAndExecuteBatch_Trend(EAState &state)
  {
   if(!CheckDoneFile(done_trend_file))
     {
      Print("Trend Python is still running. Skip H4 CSV update.");
      return false;
     }

   datetime times[];
   double open_prices[], high_prices[], low_prices[], close_prices[];

   if(!GetLatestOHLC(times, open_prices, high_prices, low_prices, close_prices,
                     PERIOD_H4, HISTORY_BARS))
     { Print("GetLatestOHLC(H4) failed."); return false; }

   RecordOHLC("ohlc_H4.csv", times, open_prices, high_prices, low_prices, close_prices);

   if(!ExecuteBatchTrend())
      return false;

   state.load_trend_flg = true;
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
/**
 * @brief H1 OHLCをCSV出力し、エントリー価格生成Pythonを起動します。
 *
 * @param state EA全体の状態。ターゲット価格読込待ちフラグを更新します。
 * @return CSV出力とバッチ起動が開始できた場合はtrue。
 */
bool RecordOHLCAndExecuteBatch_Entry(EAState &state)
  {
   if(!CheckDoneFile(done_entry_file))
     {
      Print("Entry Python is still running. Skip H1 CSV update.");
      return false;
     }

   datetime times[];
   double open_prices[], high_prices[], low_prices[], close_prices[];

   if(!GetLatestOHLC(times, open_prices, high_prices, low_prices, close_prices,
                     PERIOD_H1, HISTORY_BARS))
     { Print("GetLatestOHLC(H1) failed."); return false; }

   RecordOHLC("ohlc_H1.csv", times, open_prices, high_prices, low_prices, close_prices);

   if(!ExecuteBatchEntry())
      return false;

   state.load_target_flg = true;
   return true;
  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
/**
 * @brief Pythonが出力したトレンド判定結果を必要なタイミングで読み込みます。
 *
 * @param state EA全体の状態。`trend_state` と更新フラグを更新します。
 * @return 現状は常にtrue。
 */
bool GetTrendState(EAState &state)
  {
   bool ProcessDone = CheckDoneFile(done_trend_file);
   if(ProcessDone && g_ea.load_trend_flg)
     {
      int trend_state;
      LoadTrendState(trend_state);
      state.trend_state = trend_state;
      Print("trend_state: ", state.trend_state);
      g_ea.load_trend_flg = false;
      g_ea.last_trend_update = TimeLocal();
     }
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
/**
 * @brief `trend_state.txt` からH4トレンド判定値を読み込みます。
 *
 * @param trend_state 読み込んだ値を格納する参照。0=RANGE、1=UP、2=DOWN。
 *
 * ファイル未存在、読込失敗、異常値の場合は安全側として0を設定します。
 */
void LoadTrendState(int &trend_state)
  {
   string filename = "trend_state.txt";
   trend_state = 0;

   if(FileIsExist(filename))
     {
      int filehandle = FileOpen(filename, FILE_READ | FILE_TXT);
      if(filehandle != INVALID_HANDLE)
        {
         string line = FileReadString(filehandle);
         int value = (int)StringToInteger(line);
         if(value == 0 || value == 1 || value == 2)
            trend_state = value;
         else
            Print("Invalid trend_state value: ", line, ". Use 0.");
         FileClose(filehandle);
        }
      else
        { Print("Failed to open trend_state.txt"); trend_state = 0; }
     }
   else
     { Print("trend_state.txt not found"); trend_state = 0; }
  }

//+------------------------------------------------------------------+
//| ターゲット価格を取得する関数
//+------------------------------------------------------------------+
/**
 * @brief Pythonが出力したエントリー価格群を必要なタイミングで読み込みます。
 *
 * @param state EA全体の状態。`res_chk` と4タイプ分のen/tp/slを更新します。
 * @return 現状は常にtrue。
 */
bool GetTargetPrices(EAState &state)
  {
   bool ProcessDone = CheckDoneFile(done_entry_file);  // ←変更
   if(ProcessDone && g_ea.load_target_flg)              // ←変更
     {
      double target_prices[];
      LoadTargetPrices(target_prices);

      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

      // 先頭は res_chk
      state.res_chk = (int)target_prices[0];

      // ★ 1..4 の (en,tp,sl) を読む：合計12個
      for(int t=1; t<=4; t++)
        {
         int base = 1 + (t-1)*3; // 1,4,7,10
         state.en_price[t] = NormalizeDouble(target_prices[base + 0], digits);
         state.tp_price[t] = NormalizeDouble(target_prices[base + 1], digits);
         state.sl_price[t] = NormalizeDouble(target_prices[base + 2], digits);
        }

      // ログ（任意）
      Print("target_prices: res=", state.res_chk,
            " | T1 en=", state.en_price[1], " tp=", state.tp_price[1], " sl=", state.sl_price[1],
            " | T2 en=", state.en_price[2], " tp=", state.tp_price[2], " sl=", state.sl_price[2],
            " | T3 en=", state.en_price[3], " tp=", state.tp_price[3], " sl=", state.sl_price[3],
            " | T4 en=", state.en_price[4], " tp=", state.tp_price[4], " sl=", state.sl_price[4]);

      g_ea.load_target_flg = false;                    // ←変更
      g_ea.last_target_update = TimeLocal();           // ←変更
     }
   return true;
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| "target_prices.txt"を読み込む関数
//+------------------------------------------------------------------+
/**
 * @brief `target_prices.txt` から13個の数値を読み込みます。
 *
 * @param target_prices 読み込んだ数値を格納する配列。先頭がres_chk、以降は4タイプ分のen/tp/sl。
 *
 * 行数不足の場合は`res_chk=0`として、ターゲット価格を無効扱いにします。
 */
void LoadTargetPrices(double &target_prices[])
  {
   ArrayResize(target_prices, TARGET_SIZE);
   for(int i = 0; i < TARGET_SIZE; i++)
      target_prices[i] = DEFAULT_TARGET_PRICE;

   string filename = "target_prices.txt";

   if(FileIsExist(filename))
     {
      int filehandle = FileOpen(filename, FILE_READ | FILE_TXT);
      if(filehandle != INVALID_HANDLE)
        {
         int i = 0;
         while(!FileIsEnding(filehandle) && i < TARGET_SIZE)
           {
            string line = FileReadString(filehandle);
            target_prices[i] = StringToDouble(line);
            i++;
           }
         FileClose(filehandle);

         if(i < TARGET_SIZE)
           {
            Print("target_prices.txt line count is short. loaded=", i, " required=", TARGET_SIZE);
            target_prices[0] = 0; // 不完全なファイルは無効扱い
           }
        }
      else
        {
         Print("Failed to open file. Error code: ", GetLastError());
        }
     }
   else
     {
      Print("File does not exist: ", filename);
     }
  }

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| エントリー注文を送信する関数 (1:buy-stop, 2:buy-limit, 3:sell-stop, 4:sell-limit)
//+------------------------------------------------------------------+
/**
 * @brief 指定された注文タイプでペンディング注文を送信します。
 *
 * @param orderType 注文タイプ。1=Buy Stop、2=Buy Limit、3=Sell Stop、4=Sell Limit。
 * @param price エントリー価格。
 * @param tp 利確価格。
 * @param sl 損切価格。
 * @return 注文が正常に受理された場合はtrue、それ以外はfalse。
 */
bool SendOrder(int orderType, double price, double tp, double sl)
  {
   MqlTradeRequest request  = {};
   MqlTradeResult result    = {};

   request.magic            = magic_number;
   request.symbol           = _Symbol;
   request.volume           = lot_size;
   request.deviation        = slippage;
   request.type_filling     = GetOrderFillingPolicy(_Symbol);
   request.price            = NormalizeDouble(price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   request.tp               = NormalizeDouble(tp, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   request.sl               = NormalizeDouble(sl, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   request.comment          = RequestComment(orderType);

   string orderTypeStr      = "";

// 指値または逆指値注文
   request.action = TRADE_ACTION_PENDING;

   switch(orderType)
     {
      case 1: // 順張り買い (buy-stop)
         request.type   = ORDER_TYPE_BUY_STOP;
         orderTypeStr   = "buy-stop";
         break;

      case 2: // 逆張り買い (buy-limit)
         request.type   = ORDER_TYPE_BUY_LIMIT;
         orderTypeStr   = "buy-limit";
         break;

      case 3: // 順張り売り (sell-stop)
         request.type   = ORDER_TYPE_SELL_STOP;
         orderTypeStr   = "sell-stop";
         break;

      case 4: // 逆張り売り (sell-limit)
         request.type   = ORDER_TYPE_SELL_LIMIT;
         orderTypeStr   = "sell-limit";
         break;

      default: // 不正なorderType
         Print(__FUNCTION__, ": invalid orderType=", orderType);
         return false;
     }

// 注文送信
   if(!OrderSend(request, result))
     {
      Print(__FUNCTION__, ": OrderSend failed. err=", GetLastError());
      return false;
     }

// 注文成功確認
   if(result.retcode == TRADE_RETCODE_PLACED ||
      result.retcode == TRADE_RETCODE_DONE ||
      result.retcode == TRADE_RETCODE_DONE_PARTIAL)
     {
      Print(request.comment + " - " + orderTypeStr + " order success (ticket=", result.order, ")");
      return true;
     }
   else
     {
      Print(__FUNCTION__, ": OrderSend retcode=", result.retcode);
      return false;
     }
  }

//+------------------------------------------------------------------+
//| 注文の執行ポリシーを取得する関数
//+------------------------------------------------------------------+
/**
 * @brief シンボルに対応する注文執行ポリシーを取得します。
 *
 * @param symbol 対象シンボル。
 * @return 利用可能な執行ポリシー。IOC、FOK、RETURNの順で選択します。
 */
ENUM_ORDER_TYPE_FILLING GetOrderFillingPolicy(string symbol)
  {
   long fill_mode = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   if((fill_mode & SYMBOL_FILLING_IOC) != 0)
      return ORDER_FILLING_IOC;
   if((fill_mode & SYMBOL_FILLING_FOK) != 0)
      return ORDER_FILLING_FOK;
   return ORDER_FILLING_RETURN;
  }

//+------------------------------------------------------------------+
//| 注文コメント(ローカル時刻)を生成する関数（先頭に orderType を付与）
//+------------------------------------------------------------------+
/**
 * @brief 注文コメント文字列を生成します。
 *
 * @param orderType 注文タイプ番号。
 * @return 注文タイプとPCローカル時刻を含むコメント文字列。
 */
string RequestComment(int orderType)
  {
   datetime localTime = TimeLocal();
   string timeStr     = TimeToString(localTime, TIME_DATE|TIME_MINUTES);

// 先頭に 1,2,3,4 を付ける（例: "1 | PC Time: 2026.02.14 19:05"）
   return IntegerToString(orderType) + " | PC Time: " + timeStr;
  }

//+------------------------------------------------------------------+
//| H4トレンド方向に対して許可された注文タイプか判定する関数
//+------------------------------------------------------------------+
/**
 * @brief H4トレンド方向に対して指定注文タイプが許可されるか判定します。
 *
 * @param orderType 注文タイプ番号。
 * @param trend_state H4トレンド判定。0=RANGE、1=UP、2=DOWN。
 * @return 許可される注文タイプならtrue。レンジまたは異常値ではfalse。
 */
bool IsOrderTypeAllowedByTrend(const int orderType, const int trend_state)
  {
   if(trend_state == 1)
      return (orderType == 1 || orderType == 2); // UP: Buy Stop / Buy Limit のみ

   if(trend_state == 2)
      return (orderType == 3 || orderType == 4); // DOWN: Sell Stop / Sell Limit のみ

   return false; // RANGEまたは異常値は新規注文しない
  }

//+------------------------------------------------------------------+
//| target_prices.txt の価格が有効か判定する関数
//+------------------------------------------------------------------+
/**
 * @brief エントリー価格、利確価格、損切価格が有効値か判定します。
 *
 * @param en エントリー価格。
 * @param tp 利確価格。
 * @param sl 損切価格。
 * @return すべて0より大きい場合はtrue。
 */
bool HasValidTargetPrices(const double en, const double tp, const double sl)
  {
   return (en > 0.0 && tp > 0.0 && sl > 0.0);
  }

//+------------------------------------------------------------------+
//| 自EAの未約定注文数を数える関数
//+------------------------------------------------------------------+
/**
 * @brief このEAが管理対象とする未約定注文数を数えます。
 *
 * @return `_Symbol` と `magic_number` が一致する未約定注文数。
 */
int CountMyPendingOrders()
  {
   int count = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;

      if(!OrderSelect(ticket))
         continue;

      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;

      if((int)OrderGetInteger(ORDER_MAGIC) != magic_number)
         continue;

      count++;
     }

   return count;
  }

//+------------------------------------------------------------------+
//| 自EAのポジション数を数える関数
//+------------------------------------------------------------------+
/**
 * @brief このEAが管理対象とする保有ポジション数を数えます。
 *
 * @return `_Symbol` と `magic_number` が一致するポジション数。
 */
int CountMyPositions()
  {
   int count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      string symbol = PositionGetSymbol(i);
      if(symbol == "")
         continue;

      if(symbol != _Symbol)
         continue;

      if((int)PositionGetInteger(POSITION_MAGIC) != magic_number)
         continue;

      count++;
     }

   return count;
  }

//+------------------------------------------------------------------+
//| 自EAの注文＋ポジション数を数える関数
//+------------------------------------------------------------------+
/**
 * @brief このEAが使用中の注文数とポジション数の合計を返します。
 *
 * @return 未約定注文数 + 保有ポジション数。
 */
int CountMyUsed()
  {
   return CountMyPendingOrders() + CountMyPositions();
  }


//+------------------------------------------------------------------+
//| 時間が経過したエントリー注文をキャンセルする関数
//+------------------------------------------------------------------+
/**
 * @brief H1経過本数が上限を超えた未約定注文をキャンセルします。
 *
 * @return 1件以上キャンセルに成功した場合はtrue。
 *
 * 対象は`_Symbol` と `magic_number` が一致する未約定注文のみです。
 */
bool CancelExpiredOrders()
  {
   bool result = false;

// 未決済注文の数を取得
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket)) // 注文を選択
        {
         if(OrderGetString(ORDER_SYMBOL) != _Symbol)
            continue;
         if(OrderGetInteger(ORDER_MAGIC) != magic_number)
            continue;

         datetime open_time = (datetime)OrderGetInteger(ORDER_TIME_SETUP);

         int open_shift = GetBarShiftByTime(open_time, PERIOD_H1, -1); // H1
         if(open_shift < 0)
            continue; // 時刻解決できないなら触らない

         if(open_shift >= ENTRY_H1_LIMIT)   // H1本数（=1本 ≒ 1時間）
           {
            MqlTradeRequest request = {};
            MqlTradeResult trade_result = {};
            request.action=TRADE_ACTION_REMOVE;                   // 取引操作タイプ
            request.order = ticket;                         // 注文チケット
            if(!OrderSend(request, trade_result))      // 削除リクエスト送信
              {
               Print("Failed to delete order. Ticket: ", ticket, " Error: ", GetLastError());
              }
            else
              {
               if(trade_result.retcode == TRADE_RETCODE_DONE)
                 {
                  Print("Order canceled successfully due to a time limit. Ticket: ", ticket);
                  result = true; // 削除成功フラグ
                 }
               else
                 {
                  Print("Order cancellation failed. Ticket: ", ticket, " Retcode: ", trade_result.retcode);
                 }
              }
           }
        }
     }
   return result;
  }

//+------------------------------------------------------------------+
//| 時間が経過したポジションをクローズする関数
//+------------------------------------------------------------------+
/**
 * @brief H1経過本数が上限を超えた保有ポジションをクローズします。
 *
 * @return 1件以上クローズに成功した場合はtrue。
 *
 * 対象は`_Symbol` と `magic_number` が一致するポジションのみです。
 */
bool CloseExpiredPositions()
  {
   bool result = false;

// ポジションを逆順でループ
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      string position_symbol = PositionGetSymbol(i);
      if(position_symbol!="")
        {
         // Magic Number とシンボルでフィルタリング
         if(position_symbol != _Symbol)
            continue;
         if(PositionGetInteger(POSITION_MAGIC) == magic_number)
           {
            // ポジションのエントリー時刻を取得
            datetime entry_time = (datetime)PositionGetInteger(POSITION_TIME);

            int entry_shift = GetBarShiftByTime(entry_time, PERIOD_H1, -1);
            if(entry_shift < 0)
               continue;

            if(entry_shift >= CLOSE_H1_LIMIT)  // H1本数（=12本 ≒ 12時間）
              {
               MqlTradeRequest request = {};
               MqlTradeResult trade_result = {};

               // ポジションタイプに応じてリクエストを設定
               int position_type = (int)PositionGetInteger(POSITION_TYPE);
               request.action = TRADE_ACTION_DEAL;
               request.position = PositionGetInteger(POSITION_TICKET); // ポジションのチケット番号
               request.symbol = position_symbol;   // シンボル
               request.volume = PositionGetDouble(POSITION_VOLUME);   // ポジションサイズ
               request.price = (position_type == POSITION_TYPE_BUY)
                               ? SymbolInfoDouble(position_symbol, SYMBOL_BID) // BUYの場合はBIDでクローズ
                               : SymbolInfoDouble(position_symbol, SYMBOL_ASK); // SELLの場合はASKでクローズ
               request.deviation = slippage;
               request.type = (position_type == POSITION_TYPE_BUY)
                              ? ORDER_TYPE_SELL // BUYポジションをSELLでクローズ
                              : ORDER_TYPE_BUY; // SELLポジションをBUYでクローズ
               request.type_filling = GetOrderFillingPolicy(position_symbol); // 注文執行ポリシー
               request.magic = magic_number;

               // 注文送信
               if(!OrderSend(request, trade_result))
                 {
                  Print("Failed to close position. Ticket: ", request.position, " Error: ", GetLastError());
                  continue;
                 }

               // 結果の確認
               if(trade_result.retcode == TRADE_RETCODE_DONE || trade_result.retcode == TRADE_RETCODE_DONE_PARTIAL)
                 {
                  Print("Position closed successfully due to a time limit. Ticket: ", request.position);
                  result = true; // 少なくとも1つ成功した場合
                 }
               else
                 {
                  Print("Failed to close position. Ticket: ", request.position, " Retcode: ", trade_result.retcode);
                 }
              }
           }
        }
      else
        {
         Print("Failed to select position at index ", i, ". Error: ", GetLastError());
        }
     }
   return result;
  }


//+------------------------------------------------------------------+
//| 指定された時間に最も近いバーのインデックスを返す関数
//+------------------------------------------------------------------+
/**
 * @brief 指定時刻に最も近いバーシフトを取得します。
 *
 * @param time 判定対象の時刻。
 * @param tf 判定対象の時間足。
 * @param default_shift 取得失敗時に返す値。
 * @return 取得できたバーシフト。失敗時はdefault_shift。
 *
 * `iBarShift(..., false)` を使い、厳密一致ではなく近傍バーで解決します。
 */
int GetBarShiftByTime(datetime time, ENUM_TIMEFRAMES tf, int default_shift = -1)
  {
   if(time <= 0)
      return default_shift;
   int shift = iBarShift(_Symbol, tf, time, false); // 近傍バーで解決する
   if(shift < 0)
      return default_shift;
   return shift;
  }
//+------------------------------------------------------------------+
