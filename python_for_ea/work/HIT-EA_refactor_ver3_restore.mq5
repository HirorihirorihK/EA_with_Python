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

// Windowsプロセス起動・終了確認用
#define CREATE_NO_WINDOW                  0x08000000
#define PROCESS_QUERY_LIMITED_INFORMATION 0x00001000
#define SYNCHRONIZE                       0x00100000
#define WAIT_OBJECT_0                     0
#define WAIT_TIMEOUT                      258
#define STILL_ACTIVE                      259

struct STARTUPINFO_W
  {
   uint              cb;
   string            lpReserved;
   string            lpDesktop;
   string            lpTitle;
   uint              dwX;
   uint              dwY;
   uint              dwXSize;
   uint              dwYSize;
   uint              dwXCountChars;
   uint              dwYCountChars;
   uint              dwFillAttribute;
   uint              dwFlags;
   ushort            wShowWindow;
   ushort            cbReserved2;
   long              lpReserved2;
   long              hStdInput;
   long              hStdOutput;
   long              hStdError;
  };

struct PROCESS_INFORMATION
  {
   long              hProcess;
   long              hThread;
   uint              dwProcessId;
   uint              dwThreadId;
  };

#import "kernel32.dll"
int  CreateProcessW(string lpApplicationName, string lpCommandLine, long lpProcessAttributes, long lpThreadAttributes, int bInheritHandles, uint dwCreationFlags, long lpEnvironment, string lpCurrentDirectory, STARTUPINFO_W &lpStartupInfo, PROCESS_INFORMATION &lpProcessInformation);
int  WaitForSingleObject(long hHandle, uint dwMilliseconds);
int  GetExitCodeProcess(long hProcess, uint &lpExitCode);
int  CloseHandle(long hObject);
long OpenProcess(uint dwDesiredAccess, int bInheritHandle, uint dwProcessId);
#import

// バッチファイルのパス
string get_trend_reply_bat = "C:\\ea_py\\bat\\get_trend_reply.bat"; // H4: trend
string get_entry_reply_bat = "C:\\ea_py\\bat\\get_entry_reply.bat"; // H1: entry

// プロセス完了ファイルの設定
string done_trend_file = "process_done_trend.txt";
string done_entry_file = "process_done_entry.txt";

// Python出力ファイル
string trend_state_file = "trend_state.txt";
string target_prices_file = "target_prices.txt";

// Python実行中を判定するための管理ファイル
string running_trend_file = "process_running_trend.txt";
string running_entry_file = "process_running_entry.txt";

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| インプットの設定
//+------------------------------------------------------------------+

//--- 入力パラメータ
input double lot_size      = 0.01;  // ロット数
input double spread_limit  = 60;    // 許容スプレッド(point)
input int    magic_number  = 10001; // マジックナンバー
input int    initial_order = 0;     // 起動時の注文(0:なし, 1:あり)
input bool   use_m15_entry_filter = true;  // M15確定足で発注タイミングを確認
input double m15_entry_zone_atr_multiplier = 1.50; // M15平均レンジ何本分まで候補価格への接近を許可
ulong  slippage      = 10;          // スリッページ

//--- 主要な定数・設定
#define POSITION_LIMIT        48
#define ENTRY_H1_LIMIT        2         // H1本数（=2時間）
#define CLOSE_H1_LIMIT        12        // H1本数（=12時間）
#define HISTORY_BARS          72
#define OHLC_START_SHIFT       1         // 1: 確定足のみをPythonへ渡す
#define M15_CONFIRM_BARS       20
#define M15_MIN_ENTRY_ZONE_POINTS 10
#define M15_MIN_BODY_RATIO     0.25
#define M15_REJECTION_WICK_RATIO 0.35
#define ENTRY_RETRY_SECONDS    60
#define ENTRY_RETRY_LIMIT      10
// ANALYZE_TIMEFRAME は削除（H4/H1 両方使うため定数ではなく直接指定）
#define TARGET_SIZE           13
#define DEFAULT_TARGET_PRICE  0.0
#define PYTHON_TIMEOUT_SECONDS 600       // Python完了待ちの上限（秒）

#define MARKET_LOW_VOL_RANGE       0
#define MARKET_HIGH_VOL_RANGE      1
#define MARKET_LOW_VOL_UP          2
#define MARKET_HIGH_VOL_UP         3
#define MARKET_LOW_VOL_DOWN        4
#define MARKET_HIGH_VOL_DOWN       5
#define MARKET_ABNORMAL_VOL_STOP   6

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| EAの状態をまとめる構造体
//+------------------------------------------------------------------+

struct EAState
  {
   int               trend_state;           // H4 market_state（0..6）を格納する変数
   int               res_chk;               // GPTの回答が正しく取得できたか
   double            en_price[5];           // エントリー基準価格
   double            tp_price[5];           // 利益確定価格
   double            sl_price[5];           // ロスカット基準価格
   bool              load_trend_flg;        // ★変更：トレンドを更新するタイミングか
   bool              load_target_flg;       // ★変更：ターゲット価格を更新するタイミングか
   int               chk_cnt;               // エントリー判定の試行回数
   datetime          last_trend_update;     // ★追加：前回トレンドを更新した時刻
   datetime          last_target_update;    // ★変更：前回ターゲット価格を更新した時刻
   datetime          target_loaded_at;      // H1候補価格をEAへ読み込んだサーバー時刻
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
int  g_pre_bars_M15  = 0;
bool g_bars_H1_check = false;
bool g_bars_M15_check = false;

// ティックごとの価格情報
struct TickContext
  {
   double            ask;
   double            bid;
   double            spread;
   double            spread_points;
   int               digits;
  };

// 外部Pythonプロセスの状態
struct ExternalProcessState
  {
   long              handle;
   uint              process_id;
   bool              active;
   bool              exit_code_ready;
   uint              exit_code;
   datetime          started_at;
  };

ExternalProcessState g_trend_process;
ExternalProcessState g_entry_process;

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 起動時の処理
//+------------------------------------------------------------------+
/**
 * @brief EA起動時の初期化処理を行います。
 *
 * Python連携用のdone/runningファイル状態を確認し、`initial_order` が有効な場合は
 * H4トレンド判定とH1エントリー価格生成をそれぞれ初回実行対象にします。
 * H4/H1の初回フラグを分けることで、起動直後にH4処理だけが繰り返される状態を防ぎます。
 */
void OnInit()
// プロセス完了ファイルと実行中ファイルの状態を初期化
  {
   PrepareDoneFileOnInit(done_trend_file, running_trend_file, "trend");
   PrepareDoneFileOnInit(done_entry_file, running_entry_file, "entry");

   // initial_order=1 の場合でも、H4/H1を別々に1回だけ初回実行する。
   g_init_trend_pending = (initial_order == 1);
   g_init_entry_pending = (initial_order == 1);
  }

//+------------------------------------------------------------------+
//| 終了時の処理
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ResetExternalProcessState(g_trend_process);
   ResetExternalProcessState(g_entry_process);
  }

//+------------------------------------------------------------------+
//| ティック毎の処理
//+------------------------------------------------------------------+
/**
 * @brief ティック受信ごとにEA全体の処理を制御します。
 *
 * 処理順序は、ティック情報取得、期限切れ注文/ポジション管理、H4トレンド更新、
 * H1エントリー価格更新、M15エントリータイミング更新、ステータス表示、新規注文判定の順です。
 * 時間制限処理はPython完了待ちやスプレッド判定より前に実行します。
 */
void OnTick()
  {
   TickContext ctx;
   if(!GetTickContext(ctx))
      return;

   // 期限切れ注文・ポジションは、Python待ちやスプレッド制限に関係なく先に処理する。
   ManageExpiredTrades();

   // 外部Pythonがdoneを返さない場合に、一定時間で待機状態を解除して再実行対象にする。
   RecoverTimedOutPythonProcesses();

   // H4新バーまたは初回起動時に、トレンド判定用Pythonを起動する。
   ProcessTrendUpdate(g_ea);

   // トレンド判定が完了していない場合、新規注文側の処理だけをスキップする。
   if(!IsTrendResultReady())
      return;

   RefreshTrendState(g_ea);

   // H1新バーまたは初回起動時に、エントリー価格生成用Pythonを起動する。
   ProcessEntryUpdate(g_ea);

   // M15確定足ごとに、H1候補価格を発注してよいタイミングか再判定する。
   ProcessM15EntryTimingUpdate();

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
 * 未約定注文はENTRY_H1_LIMIT時間、保有ポジションはCLOSE_H1_LIMIT時間を基準に判定します。
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
   return IsProcessResultReady(done_trend_file, running_trend_file, trend_state_file, "trend", g_trend_process);
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
//| M15更新検知とエントリータイミング判定トリガーを処理する関数
//+------------------------------------------------------------------+
/**
 * @brief M15新バーを検知し、H1候補価格の発注判定を実行できる状態にします。
 *
 * M15は方向判定を上書きする足ではなく、H4/H1で決めた候補価格を発注する
 * タイミング確認として使います。初回は直近の確定M15足で一度だけ判定可能にします。
 */
void ProcessM15EntryTimingUpdate()
  {
   int current_bars_M15 = iBars(NULL, PERIOD_M15);
   if(current_bars_M15 <= 0)
      return;

   if(g_pre_bars_M15 == 0)
     {
      g_pre_bars_M15 = current_bars_M15;
      g_bars_M15_check = true;
      return;
     }

   int bars_M15_change = current_bars_M15 - g_pre_bars_M15;
   if(bars_M15_change <= 0)
      return;

   g_bars_M15_check = true;
   g_pre_bars_M15 = current_bars_M15;
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
                        "\n\nMarket State: %d (%s)"
                       "\n\nLast Target Update:\n %s"
                       "\n\nMy Used Count: %d / %d"
                       "\n\n[T1 Buy Stop ] en: %." + IntegerToString(ctx.digits) + "f  tp: %." + IntegerToString(ctx.digits) + "f  sl: %." + IntegerToString(ctx.digits) + "f"
                       "\n[T2 Buy Limit] en: %." + IntegerToString(ctx.digits) + "f  tp: %." + IntegerToString(ctx.digits) + "f  sl: %." + IntegerToString(ctx.digits) + "f"
                       "\n[T3 Sell Stop] en: %." + IntegerToString(ctx.digits) + "f  tp: %." + IntegerToString(ctx.digits) + "f  sl: %." + IntegerToString(ctx.digits) + "f"
                       "\n[T4 SellLimit] en: %." + IntegerToString(ctx.digits) + "f  tp: %." + IntegerToString(ctx.digits) + "f  sl: %." + IntegerToString(ctx.digits) + "f\n",
                       ctx.ask, ctx.bid, ctx.spread, ctx.spread_points,
                       TimeToString(g_ea.last_trend_update, TIME_DATE | TIME_MINUTES),
                        g_ea.trend_state, MarketStateName(g_ea.trend_state),
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
//| market_stateの表示名を返す関数
//+------------------------------------------------------------------+
/**
 * @brief H4 market_stateの人間可読名を返します。
 *
 * @param market_state Pythonが出力したH4環境分類（0..6）。
 * @return 表示用ラベル。
 */
string MarketStateName(const int market_state)
  {
   switch(market_state)
     {
      case MARKET_LOW_VOL_RANGE:
         return "LOW_VOL_RANGE";
      case MARKET_HIGH_VOL_RANGE:
         return "HIGH_VOL_RANGE";
      case MARKET_LOW_VOL_UP:
         return "LOW_VOL_UP";
      case MARKET_HIGH_VOL_UP:
         return "HIGH_VOL_UP";
      case MARKET_LOW_VOL_DOWN:
         return "LOW_VOL_DOWN";
      case MARKET_HIGH_VOL_DOWN:
         return "HIGH_VOL_DOWN";
      case MARKET_ABNORMAL_VOL_STOP:
         return "ABNORMAL_VOL_STOP";
      default:
         return "UNKNOWN";
     }
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
   return IsProcessResultReady(done_entry_file, running_entry_file, target_prices_file, "entry", g_entry_process);
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
   g_bars_M15_check = false;
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
 * @return H1候補が有効で、M15確定足が更新され、前回判定から一定秒数以上経過していればtrue。
 */
bool ShouldRunEntryDecision(EAState &state)
  {
   return (g_bars_H1_check && g_bars_M15_check && TimeCurrent() - state.last_chk >= ENTRY_RETRY_SECONDS);
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
 * `res_chk`、market_state、対象EAの注文/ポジション数上限を確認します。
 */
bool ValidateEntryPreconditions(EAState &state)
  {
   if(state.res_chk != 1)
     {
      Print("[Entry Skip] target_prices invalid. res_chk=", state.res_chk);
      state.chk_cnt = 0;
      return false;
     }

   if(state.trend_state == MARKET_ABNORMAL_VOL_STOP)
     {
      Print("[Entry Skip] market_state=6 (abnormal volatility). No new entry orders are sent.");
      state.chk_cnt = 0;
      return false;
     }

   if(state.trend_state < MARKET_LOW_VOL_RANGE || state.trend_state > MARKET_ABNORMAL_VOL_STOP)
     {
      Print("[Entry Skip] invalid market_state=", state.trend_state);
      state.chk_cnt = 0;
      return false;
     }

   if(IsTargetCandidateExpired(state))
     {
      Print("[Entry Skip] H1 target candidate expired. loaded_at=",
            TimeToString(state.target_loaded_at, TIME_DATE | TIME_SECONDS));
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
//| H1候補価格の有効期限を判定する関数
//+------------------------------------------------------------------+
/**
 * @brief H1候補価格がENTRY_H1_LIMIT時間を超えて古くなっていないか判定します。
 *
 * @param state EA全体の状態。H1候補価格の読込時刻を参照します。
 * @return 候補価格が期限切れの場合はtrue。
 */
bool IsTargetCandidateExpired(EAState &state)
  {
   if(state.target_loaded_at <= 0)
      return false;

   int expiration_seconds = ENTRY_H1_LIMIT * PeriodSeconds(PERIOD_H1);
   if(expiration_seconds <= 0)
      return false;

   return (TimeCurrent() - state.target_loaded_at >= expiration_seconds);
  }

//+------------------------------------------------------------------+
//| 許可された注文タイプだけを順番に送信する関数
//+------------------------------------------------------------------+
/**
 * @brief H4 market_stateで許可された注文タイプだけを順番に送信します。
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
          Print("[Skip] orderType=", t, " not allowed by market_state=", state.trend_state,
                " (", MarketStateName(state.trend_state), ")");
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

   if(!IsM15EntryTimingConfirmed(orderType, ctx, en))
     {
      Print("[No ", entry_type, "] M15 timing not confirmed. cur=", cur_price, " en=", en);
      return false;
     }

   if(!MeetsTradeDistanceRules(orderType, ctx, en, tp, sl))
      return false;

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
//| M15確定足によるエントリータイミング確認
//+------------------------------------------------------------------+
/**
 * @brief H1候補価格に対してM15の発注タイミングが整っているか判定します。
 *
 * @param orderType 注文タイプ番号。
 * @param ctx 現在のAsk/Bid情報。
 * @param en H1で決めたエントリー候補価格。
 * @return M15確認条件を満たす場合はtrue。
 *
 * H4/H1の方向判断は維持し、M15では「候補価格に近い」「直近確定足が
 * 順張り/反転の根拠を持つ」ことだけを確認します。
 */
bool IsM15EntryTimingConfirmed(const int orderType, TickContext &ctx, const double en)
  {
   if(!use_m15_entry_filter)
      return true;

   if(IsTrendStopOrderType(orderType))
      return true;

   MqlRates rates[];
   int copied = CopyRates(_Symbol, PERIOD_M15, OHLC_START_SHIFT, M15_CONFIRM_BARS, rates);
   if(copied < 3)
     {
      Print("[M15 Filter] insufficient M15 bars. copied=", copied);
      return false;
     }

   int last_index = copied - 1;
   int prev_index = copied - 2;

   double avg_range = AverageM15Range(rates, copied);
   double min_zone = M15_MIN_ENTRY_ZONE_POINTS * Point();
   double entry_zone = avg_range * m15_entry_zone_atr_multiplier;
   if(entry_zone < min_zone)
      entry_zone = min_zone;

   double cur_price = CurrentPriceForOrderType(orderType, ctx);
   if(MathAbs(cur_price - en) > entry_zone)
     {
      Print("[M15 Filter] ", EntryTypeName(orderType), " is not near entry zone. cur=",
            cur_price, " en=", en, " zone=", entry_zone);
      return false;
     }

   return IsM15SignalAligned(orderType, rates[prev_index], rates[last_index], en, entry_zone);
  }

//+------------------------------------------------------------------+
//| 順張りStop注文タイプか判定する関数
//+------------------------------------------------------------------+
/**
 * @brief M15反転確認を待たずH1候補で発注する順張りStop注文か判定します。
 *
 * @param orderType 注文タイプ番号。
 * @return Buy Stop または Sell Stop の場合はtrue。
 */
bool IsTrendStopOrderType(const int orderType)
  {
   return (orderType == 1 || orderType == 3);
  }

//+------------------------------------------------------------------+
//| M15平均レンジを計算する関数
//+------------------------------------------------------------------+
/**
 * @brief M15確定足の平均レンジを計算します。
 *
 * @param rates M15のMqlRates配列。
 * @param count 使用する本数。
 * @return 平均レンジ。算出不能な場合は最小ゾーン幅を返します。
 */
double AverageM15Range(const MqlRates &rates[], const int count)
  {
   double total_range = 0.0;
   int used = 0;

   for(int i = 0; i < count; i++)
     {
      double range = rates[i].high - rates[i].low;
      if(range <= 0.0)
         continue;

      total_range += range;
      used++;
     }

   if(used <= 0)
      return M15_MIN_ENTRY_ZONE_POINTS * Point();

   return total_range / used;
  }

//+------------------------------------------------------------------+
//| 注文タイプごとのM15シグナル方向を判定する関数
//+------------------------------------------------------------------+
/**
 * @brief 注文タイプごとにM15確定足の勢い・反転根拠を確認します。
 *
 * @param orderType 注文タイプ番号。
 * @param prev_bar 1本前のM15確定足。
 * @param last_bar 直近のM15確定足。
 * @param en H1で決めたエントリー候補価格。
 * @param entry_zone M15平均レンジから算出した候補価格付近の許容幅。
 * @return 注文タイプに沿ったM15根拠があればtrue。
 */
bool IsM15SignalAligned(const int orderType, const MqlRates &prev_bar, const MqlRates &last_bar, const double en, const double entry_zone)
  {
   double range = SafeBarRange(last_bar);
   double body_ratio = MathAbs(last_bar.close - last_bar.open) / range;
   double upper_wick_ratio = (last_bar.high - MathMax(last_bar.open, last_bar.close)) / range;
   double lower_wick_ratio = (MathMin(last_bar.open, last_bar.close) - last_bar.low) / range;

   bool bullish = (last_bar.close > last_bar.open);
   bool bearish = (last_bar.close < last_bar.open);
   bool strong_body = (body_ratio >= M15_MIN_BODY_RATIO);
   bool bullish_break = (last_bar.close > prev_bar.high);
   bool bearish_break = (last_bar.close < prev_bar.low);
   bool lower_rejection = (lower_wick_ratio >= M15_REJECTION_WICK_RATIO);
   bool upper_rejection = (upper_wick_ratio >= M15_REJECTION_WICK_RATIO);

   switch(orderType)
     {
      case 1: // Buy Stop: M15の上方向モメンタムを確認
         return (bullish && (bullish_break || strong_body) && last_bar.close <= en + entry_zone);

      case 2: // Buy Limit: 候補価格付近で下ヒゲ反転または買い戻しを確認
         return (last_bar.low <= en + entry_zone && bullish &&
                 (lower_rejection || bullish_break || strong_body));

      case 3: // Sell Stop: M15の下方向モメンタムを確認
         return (bearish && (bearish_break || strong_body) && last_bar.close >= en - entry_zone);

      case 4: // Sell Limit: 候補価格付近で上ヒゲ反転または売り戻しを確認
         return (last_bar.high >= en - entry_zone && bearish &&
                 (upper_rejection || bearish_break || strong_body));

      default:
         return false;
     }
  }

//+------------------------------------------------------------------+
//| ローソク足レンジを安全に取得する関数
//+------------------------------------------------------------------+
/**
 * @brief ゼロ除算を避けるため、最小値を持つローソク足レンジを返します。
 *
 * @param bar 対象ローソク足。
 * @return high-low。0以下の場合はPoint()を返します。
 */
double SafeBarRange(const MqlRates &bar)
  {
   double range = bar.high - bar.low;
   if(range <= 0.0)
      return Point();

   return range;
  }

//+------------------------------------------------------------------+
//| brokerの最小距離制約を満たすか判定する関数
//+------------------------------------------------------------------+
/**
 * @brief pending価格、TP、SLがstop level / freeze levelの最小距離を満たすか判定します。
 *
 * @param orderType 注文タイプ番号。
 * @param ctx 現在のAsk/Bid情報。
 * @param en エントリー価格。
 * @param tp 利確価格。
 * @param sl 損切価格。
 * @return 最小距離を満たす場合はtrue。
 */
bool MeetsTradeDistanceRules(const int orderType, TickContext &ctx, const double en, const double tp, const double sl)
  {
   int stop_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int freeze_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   int min_level = stop_level;
   if(freeze_level > min_level)
      min_level = freeze_level;
   double min_distance = min_level * Point();

   if(min_distance <= 0.0)
      return true;

   double cur_price = CurrentPriceForOrderType(orderType, ctx);
   string entry_type = EntryTypeName(orderType);

   if(MathAbs(en - cur_price) < min_distance)
     {
      Print("[Skip] ", entry_type, " entry is too close. cur=", cur_price,
            " en=", en, " min_distance=", min_distance);
      return false;
     }

   if(MathAbs(tp - en) < min_distance)
     {
      Print("[Skip] ", entry_type, " TP is too close. en=", en,
            " tp=", tp, " min_distance=", min_distance);
      return false;
     }

   if(MathAbs(en - sl) < min_distance)
     {
      Print("[Skip] ", entry_type, " SL is too close. en=", en,
            " sl=", sl, " min_distance=", min_distance);
      return false;
     }

   return true;
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
   Print("[Retry] no order sent. chk_cnt=", state.chk_cnt, "/", ENTRY_RETRY_LIMIT,
         " (wait next M15 bar)");

   if(state.chk_cnt < ENTRY_RETRY_LIMIT)
     {
      g_bars_H1_check = true;  // 次のM15確定足で再度エントリー判定を実行する
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
//| Python実行中ファイルを作成する関数
//+------------------------------------------------------------------+
/**
 * @brief Python起動時刻を実行中ファイルへ記録します。
 *
 * @param name 作成するrunningファイル名。
 */
void CreateRunningFile(const string name, const uint process_id)
  {
   int h = FileOpen(name, FILE_WRITE | FILE_TXT);
   if(h != INVALID_HANDLE)
     {
       FileWrite(h, IntegerToString((long)TimeCurrent()));
       FileWrite(h, IntegerToString((long)process_id));
       FileClose(h);
      }
   else
      Print("Failed to create running file: ", name, " err=", GetLastError());
  }

//+------------------------------------------------------------------+
//| Python実行中ファイルを削除する関数
//+------------------------------------------------------------------+
/**
 * @brief 指定したrunningファイルを削除します。
 *
 * @param name 削除するrunningファイル名。
 */
void DeleteRunningFile(const string name)
  {
   if(FileIsExist(name))
      FileDelete(name);
  }

//+------------------------------------------------------------------+
//| Python実行開始時刻を読み込む関数
//+------------------------------------------------------------------+
/**
 * @brief runningファイルに記録されたPython起動時刻を読み込みます。
 *
 * @param name 読み込むrunningファイル名。
 * @return 読み込めた起動時刻。失敗時は0。
 */
datetime LoadRunningStartedAt(const string name)
  {
   if(!FileIsExist(name))
      return 0;

   int h = FileOpen(name, FILE_READ | FILE_TXT);
   if(h == INVALID_HANDLE)
     {
      Print("Failed to open running file: ", name, " err=", GetLastError());
      return 0;
     }

   string line = FileReadString(h);
   FileClose(h);
   return (datetime)StringToInteger(line);
  }

//+------------------------------------------------------------------+
//| Python実行プロセスIDを読み込む関数
//+------------------------------------------------------------------+
/**
 * @brief runningファイルに記録されたプロセスIDを読み込みます。
 *
 * @param name 読み込むrunningファイル名。
 * @return 読み込めたプロセスID。旧形式または失敗時は0。
 */
uint LoadRunningProcessId(const string name)
  {
   if(!FileIsExist(name))
      return 0;

   int h = FileOpen(name, FILE_READ | FILE_TXT);
   if(h == INVALID_HANDLE)
     {
      Print("Failed to open running file: ", name, " err=", GetLastError());
      return 0;
     }

   FileReadString(h); // started_at
   if(FileIsEnding(h))
     {
      FileClose(h);
      return 0;
     }

   string line = FileReadString(h);
   FileClose(h);
   return (uint)StringToInteger(line);
  }

//+------------------------------------------------------------------+
//| Python実行中ファイルがタイムアウトしているか判定する関数
//+------------------------------------------------------------------+
/**
 * @brief runningファイルの起動時刻からPython待ち上限を超えているか判定します。
 *
 * @param name 判定するrunningファイル名。
 * @return タイムアウトしている場合はtrue。
 */
bool IsRunningFileTimedOut(const string name)
  {
   datetime started_at = LoadRunningStartedAt(name);
   if(started_at <= 0)
      return true;

   return (TimeCurrent() - started_at >= PYTHON_TIMEOUT_SECONDS);
  }

//+------------------------------------------------------------------+
//| 外部プロセス状態を初期値に戻す関数
//+------------------------------------------------------------------+
void ResetExternalProcessState(ExternalProcessState &process)
  {
   if(process.handle != 0)
      CloseHandle(process.handle);

   process.handle          = 0;
   process.process_id      = 0;
   process.active          = false;
   process.exit_code_ready = false;
   process.exit_code       = 0;
   process.started_at      = 0;
  }

//+------------------------------------------------------------------+
//| runningファイルのPIDからプロセスハンドルを復元する関数
//+------------------------------------------------------------------+
bool AttachRunningProcess(const string running_file, const string label, ExternalProcessState &process)
  {
   if(process.active && process.handle != 0)
      return true;

   uint process_id = LoadRunningProcessId(running_file);
   if(process_id == 0)
      return false;

   long handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, 0, process_id);
   if(handle == 0)
     {
      Print("[", label, "] failed to open running process. pid=", process_id, " err=", GetLastError());
      return false;
     }

   process.handle          = handle;
   process.process_id      = process_id;
   process.active          = true;
   process.exit_code_ready = false;
   process.exit_code       = STILL_ACTIVE;
   process.started_at      = LoadRunningStartedAt(running_file);
   return true;
  }

//+------------------------------------------------------------------+
//| 外部プロセスの終了状態を更新する関数
//+------------------------------------------------------------------+
bool UpdateExternalProcessStatus(ExternalProcessState &process, const string label)
  {
   if(!process.active || process.handle == 0)
      return true;

   int wait_result = WaitForSingleObject(process.handle, 0);
   if(wait_result == WAIT_TIMEOUT)
      return false;

   uint exit_code = 1;
   if(wait_result == WAIT_OBJECT_0)
     {
      if(GetExitCodeProcess(process.handle, exit_code) == 0)
        {
         Print("[", label, "] failed to get process exit code. err=", GetLastError());
         exit_code = 1;
        }
     }
   else
     {
      Print("[", label, "] WaitForSingleObject failed. result=", wait_result, " err=", GetLastError());
      exit_code = 1;
     }

   CloseHandle(process.handle);
   process.handle          = 0;
   process.active          = false;
   process.exit_code_ready = true;
   process.exit_code       = exit_code;
   Print("[", label, "] process finished. pid=", process.process_id, " exit_code=", exit_code);
   return true;
  }

//+------------------------------------------------------------------+
//| 外部プロセスがタイムアウトしているか判定する関数
//+------------------------------------------------------------------+
bool IsExternalProcessTimedOut(ExternalProcessState &process, const string running_file)
  {
   datetime started_at = process.started_at;
   if(started_at <= 0)
      started_at = LoadRunningStartedAt(running_file);
   if(started_at <= 0)
      return true;

   return (TimeCurrent() - started_at >= PYTHON_TIMEOUT_SECONDS);
  }

//+------------------------------------------------------------------+
//| バッチファイルをプロセスハンドル付きで起動する関数
//+------------------------------------------------------------------+
bool StartBatchProcess(const string bat_file, const string running_file, const string label, ExternalProcessState &process)
  {
   STARTUPINFO_W startup_info = {};
   PROCESS_INFORMATION process_info = {};

   startup_info.cb = (uint)sizeof(startup_info);

   string cmd_exe = "C:\\Windows\\System32\\cmd.exe";
   string command_line = "\"" + cmd_exe + "\" /c \"\"" + bat_file + "\"\"";

   int created = CreateProcessW(
                    cmd_exe,
                    command_line,
                    0,
                    0,
                    0,
                    CREATE_NO_WINDOW,
                    0,
                    "C:\\ea_py",
                    startup_info,
                    process_info
                 );

   if(created == 0 || process_info.hProcess == 0)
     {
      Print("[", label, "] CreateProcessW failed. file=", bat_file, " err=", GetLastError());
      ResetExternalProcessState(process);
      DeleteRunningFile(running_file);
      return false;
     }

   if(process_info.hThread != 0)
      CloseHandle(process_info.hThread);

   process.handle          = process_info.hProcess;
   process.process_id      = process_info.dwProcessId;
   process.active          = true;
   process.exit_code_ready = false;
   process.exit_code       = STILL_ACTIVE;
   process.started_at      = TimeCurrent();

   CreateRunningFile(running_file, process.process_id);
   Print("[", label, "] process started. pid=", process.process_id, " file=", bat_file);
   return true;
  }

//+------------------------------------------------------------------+
//| EA起動時のdoneファイル状態を整える関数
//+------------------------------------------------------------------+
/**
 * @brief EA起動時にPython実行中状態を壊さない範囲でdoneファイルを準備します。
 *
 * @param done_file 完了判定ファイル名。
 * @param running_file 実行中判定ファイル名。
 * @param label ログ表示用ラベル。
 */
void PrepareDoneFileOnInit(const string done_file, const string running_file, const string label)
  {
   if(CheckDoneFile(done_file))
     {
      DeleteRunningFile(running_file);
      return;
     }

   if(FileIsExist(running_file))
     {
       if(IsRunningFileTimedOut(running_file))
         {
          Print("[", label, "] stale running file found on init. Remove marker without creating done.");
          DeleteRunningFile(running_file);
         }
      else
         Print("[", label, "] Python seems to be running on init. Keep waiting.");
      return;
     }

   Print("[", label, "] done file not found on init. Keep as not-ready until the next trigger.");
  }

//+------------------------------------------------------------------+
//| Python完了状態を返す関数
//+------------------------------------------------------------------+
/**
 * @brief doneファイルがあれば完了扱いにし、runningファイルを片付けます。
 *
 * @param done_file 完了判定ファイル名。
 * @param running_file 実行中判定ファイル名。
 * @return 完了済みの場合はtrue。
 */
bool IsProcessResultReady(const string done_file, const string running_file, const string result_file, const string label, ExternalProcessState &process)
  {
   if(process.active || FileIsExist(running_file))
     {
      if(process.active || AttachRunningProcess(running_file, label, process))
        {
         if(!UpdateExternalProcessStatus(process, label))
            return false;

         DeleteRunningFile(running_file);
         if(process.exit_code_ready && process.exit_code != 0)
           {
            Print("[", label, "] process failed. exit_code=", process.exit_code);
            return false;
           }
        }
      else if(!CheckDoneFile(done_file))
        {
         return false;
        }
     }

   if(!CheckDoneFile(done_file))
      return false;

   if(!FileIsExist(result_file))
     {
      Print("[", label, "] done exists but result file is missing: ", result_file);
      return false;
     }

   DeleteRunningFile(running_file);
   return true;
  }

//+------------------------------------------------------------------+
//| Python開始可能状態を返す関数
//+------------------------------------------------------------------+
/**
 * @brief done/runningファイル状態からPythonを新規起動できるか判定します。
 *
 * @param done_file 完了判定ファイル名。
 * @param running_file 実行中判定ファイル名。
 * @param label ログ表示用ラベル。
 * @return 起動可能な場合はtrue。
 */
bool IsProcessStartAllowed(const string done_file, const string running_file, const string label, ExternalProcessState &process)
  {
   if(process.active || FileIsExist(running_file))
     {
      if(process.active || AttachRunningProcess(running_file, label, process))
        {
         if(!UpdateExternalProcessStatus(process, label))
           {
            if(IsExternalProcessTimedOut(process, running_file))
               Print("[", label, "] Python timed out, but the process is still running. Keep waiting.");
            else
               Print("[", label, "] Python is still running. Skip execute.");
            return false;
           }

         DeleteRunningFile(running_file);
         if(process.exit_code_ready && process.exit_code != 0)
            Print("[", label, "] previous process failed. exit_code=", process.exit_code, ". Retry is allowed.");
        }
      else
        {
         if(CheckDoneFile(done_file))
           {
            DeleteRunningFile(running_file);
            return true;
           }

         if(IsRunningFileTimedOut(running_file))
           {
            Print("[", label, "] stale running marker without live process. Retry is allowed.");
            DeleteRunningFile(running_file);
            return true;
           }

         Print("[", label, "] running marker exists, but process cannot be verified yet. Skip execute.");
         return false;
        }
     }

   if(CheckDoneFile(done_file))
     {
      DeleteRunningFile(running_file);
      return true;
     }

   Print("[", label, "] done file missing without running marker. Start new process.");
   return true;
  }

//+------------------------------------------------------------------+
//| タイムアウトしたPython待ちを復旧する関数
//+------------------------------------------------------------------+
/**
 * @brief Pythonがdoneファイルを返さない状態を検知し、再実行できる状態へ戻します。
 */
void RecoverTimedOutPythonProcesses()
  {
   if(RecoverTimedOutProcess(done_trend_file, running_trend_file, "trend", g_trend_process))
     {
      g_ea.load_trend_flg = false;
      g_init_trend_pending = true;
     }

   if(RecoverTimedOutProcess(done_entry_file, running_entry_file, "entry", g_entry_process))
     {
      g_ea.load_target_flg = false;
      g_bars_H1_check = false;
      g_bars_M15_check = false;
      g_ea.chk_cnt = 0;
      g_init_entry_pending = true;
     }
  }

//+------------------------------------------------------------------+
//| 個別Python処理のタイムアウトを復旧する関数
//+------------------------------------------------------------------+
/**
 * @brief 1種類のPython処理について、実行中ファイルのタイムアウトを検知します。
 *
 * @param done_file 完了判定ファイル名。
 * @param running_file 実行中判定ファイル名。
 * @param label ログ表示用ラベル。
 * @return タイムアウト復旧を行った場合はtrue。
 */
bool RecoverTimedOutProcess(const string done_file, const string running_file, const string label, ExternalProcessState &process)
  {
   if(CheckDoneFile(done_file) && !process.active)
     {
      DeleteRunningFile(running_file);
      return false;
     }

   if(!process.active && !FileIsExist(running_file))
      return false;

   if(process.active || AttachRunningProcess(running_file, label, process))
     {
      if(!UpdateExternalProcessStatus(process, label))
        {
         if(IsExternalProcessTimedOut(process, running_file))
            Print("[", label, "] Python exceeded ", PYTHON_TIMEOUT_SECONDS,
                  " seconds, but the process is still running. Keep waiting.");
         return false;
        }

      DeleteRunningFile(running_file);
      if(process.exit_code_ready && process.exit_code != 0)
        {
         Print("[", label, "] Python process failed. Retry on next trigger.");
         return true;
        }

      if(!CheckDoneFile(done_file))
        {
         Print("[", label, "] Python process ended without done file. Retry on next trigger.");
         return true;
        }

      return false;
     }

   if(!IsRunningFileTimedOut(running_file))
      return false;

   Print("[", label, "] Python did not finish within ",
         PYTHON_TIMEOUT_SECONDS, " seconds, and no live process was found. Retry is allowed.");
   DeleteRunningFile(running_file);
   return true;
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
 * @return CSV出力に成功した場合はtrue。
 */
bool RecordOHLC(const string filename, const datetime &times[], const double &open_prices[], const double &high_prices[], const double &low_prices[], const double &close_prices[])
  {
// 出力先ファイル名
//  string filename = "ohlc.csv";

// ファイルを "書き込みモード" でオープン (テキスト/ANSI)
   int fileHandle = FileOpen(filename, FILE_WRITE | FILE_TXT | FILE_ANSI);

// ファイルが開けたかチェック
   if(fileHandle == INVALID_HANDLE)
     {
      Print(__FUNCTION__, " : Failed to open file: ", GetLastError());
      return false;
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
   return true;
  }

//+------------------------------------------------------------------+
//| バッチファイル（Pythonスクリプト）を実行する関数
//+------------------------------------------------------------------+
/**
 * @brief H4トレンド判定用バッチファイルを起動します。
 *
 * @return 起動に成功した場合はtrue、Python実行中または起動失敗時はfalse。
 *
 * 起動直前に`process_done_trend.txt`を削除し、プロセスハンドルを保持して終了確認できる状態にします。
 */
bool ExecuteBatchTrend()
  {
   if(!IsProcessStartAllowed(done_trend_file, running_trend_file, "trend", g_trend_process))
      return false;

   DeleteDoneFile(done_trend_file);
   return StartBatchProcess(get_trend_reply_bat, running_trend_file, "trend", g_trend_process);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
/**
 * @brief H1エントリー価格生成用バッチファイルを起動します。
 *
 * @return 起動に成功した場合はtrue、Python実行中または起動失敗時はfalse。
 *
 * 起動直前に`process_done_entry.txt`を削除し、プロセスハンドルを保持して終了確認できる状態にします。
 */
bool ExecuteBatchEntry()
  {
   if(!IsProcessStartAllowed(done_entry_file, running_entry_file, "entry", g_entry_process))
      return false;

   DeleteDoneFile(done_entry_file);
   return StartBatchProcess(get_entry_reply_bat, running_entry_file, "entry", g_entry_process);
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
   if(!IsProcessStartAllowed(done_trend_file, running_trend_file, "trend", g_trend_process))
     {
      Print("Trend Python is still running. Skip H4 CSV update.");
      return false;
     }

   datetime times[];
   double open_prices[], high_prices[], low_prices[], close_prices[];

   if(!GetLatestOHLC(times, open_prices, high_prices, low_prices, close_prices,
                     PERIOD_H4, HISTORY_BARS))
     { Print("GetLatestOHLC(H4) failed."); return false; }

   if(!RecordOHLC("ohlc_H4.csv", times, open_prices, high_prices, low_prices, close_prices))
     { Print("RecordOHLC(H4) failed."); return false; }

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
   if(!IsProcessStartAllowed(done_entry_file, running_entry_file, "entry", g_entry_process))
     {
      Print("Entry Python is still running. Skip H1 CSV update.");
      return false;
     }

   datetime times[];
   double open_prices[], high_prices[], low_prices[], close_prices[];

   if(!GetLatestOHLC(times, open_prices, high_prices, low_prices, close_prices,
                     PERIOD_H1, HISTORY_BARS))
     { Print("GetLatestOHLC(H1) failed."); return false; }

   if(!RecordOHLC("ohlc_H1.csv", times, open_prices, high_prices, low_prices, close_prices))
     { Print("RecordOHLC(H1) failed."); return false; }

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
 * @param state EA全体の状態。H4 market_stateと更新フラグを更新します。
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
      Print("market_state: ", state.trend_state, " (", MarketStateName(state.trend_state), ")");
      g_ea.load_trend_flg = false;
      g_ea.last_trend_update = TimeLocal();
     }
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
/**
 * @brief `trend_state.txt` からH4 market_state判定値を読み込みます。
 *
 * @param trend_state 読み込んだ値を格納する参照。0..6のmarket_state。
 *
 * ファイル未存在、読込失敗、異常値の場合は安全側として6（新規停止）を設定します。
 */
void LoadTrendState(int &trend_state)
  {
   string filename = trend_state_file;
   trend_state = MARKET_ABNORMAL_VOL_STOP;

   if(FileIsExist(filename))
     {
      int filehandle = FileOpen(filename, FILE_READ | FILE_TXT);
      if(filehandle != INVALID_HANDLE)
        {
         string line = FileReadString(filehandle);
         int value = (int)StringToInteger(line);
         if(value >= MARKET_LOW_VOL_RANGE && value <= MARKET_ABNORMAL_VOL_STOP)
            trend_state = value;
         else
            Print("Invalid market_state value: ", line, ". Use 6.");
         FileClose(filehandle);
        }
      else
        { Print("Failed to open trend_state.txt"); trend_state = MARKET_ABNORMAL_VOL_STOP; }
     }
   else
     { Print("trend_state.txt not found"); trend_state = MARKET_ABNORMAL_VOL_STOP; }
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
      g_ea.target_loaded_at = TimeCurrent();
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

    string filename = target_prices_file;

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
   ApplyPendingOrderExpiration(request);

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
//| ペンディング注文の有効期限を設定する関数
//+------------------------------------------------------------------+
/**
 * @brief brokerが対応している範囲でpending orderにサーバー側の期限を設定します。
 *
 * @param request 更新対象の取引リクエスト。
 */
void ApplyPendingOrderExpiration(MqlTradeRequest &request)
  {
   int expiration_seconds = ENTRY_H1_LIMIT * PeriodSeconds(PERIOD_H1);
   long expiration_mode = SymbolInfoInteger(request.symbol, SYMBOL_EXPIRATION_MODE);

   if(expiration_seconds > 0 &&
      (expiration_mode & SYMBOL_EXPIRATION_SPECIFIED) != 0)
     {
      request.type_time = ORDER_TIME_SPECIFIED;
      request.expiration = TimeCurrent() + expiration_seconds;
      return;
     }

   if(expiration_seconds > 0 &&
      (expiration_mode & SYMBOL_EXPIRATION_SPECIFIED_DAY) != 0)
     {
      request.type_time = ORDER_TIME_SPECIFIED_DAY;
      request.expiration = TimeCurrent() + expiration_seconds;
      return;
     }

   if((expiration_mode & SYMBOL_EXPIRATION_DAY) != 0)
     {
      request.type_time = ORDER_TIME_DAY;
      return;
     }

   request.type_time = ORDER_TIME_GTC;
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
//| H4 market_stateに対して許可された注文タイプか判定する関数
//+------------------------------------------------------------------+
/**
 * @brief H4 market_stateに対して指定注文タイプが許可されるか判定します。
 *
 * @param orderType 注文タイプ番号。
 * @param trend_state H4 market_state（0..6）。
 * @return 許可される注文タイプならtrue。異常ボラまたは異常値ではfalse。
 */
bool IsOrderTypeAllowedByTrend(const int orderType, const int trend_state)
  {
   switch(trend_state)
     {
      case MARKET_LOW_VOL_RANGE:
      case MARKET_HIGH_VOL_RANGE:
         return (orderType == 2 || orderType == 4); // Range: Buy Limit / Sell Limitのみ

      case MARKET_LOW_VOL_UP:
      case MARKET_HIGH_VOL_UP:
         return (orderType == 1 || orderType == 2); // Up: Buy Stop / Buy Limitのみ

      case MARKET_LOW_VOL_DOWN:
      case MARKET_HIGH_VOL_DOWN:
         return (orderType == 3 || orderType == 4); // Down: Sell Stop / Sell Limitのみ

      case MARKET_ABNORMAL_VOL_STOP:
      default:
         return false; // 異常ボラまたは異常値は新規注文しない
     }
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
 * @brief 実時間でENTRY_H1_LIMIT時間を超えた未約定注文をキャンセルします。
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

         int expiration_seconds = ENTRY_H1_LIMIT * PeriodSeconds(PERIOD_H1);
         if(open_time <= 0 || expiration_seconds <= 0)
            continue;

         if(TimeCurrent() - open_time >= expiration_seconds)
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
 * @brief 実時間でCLOSE_H1_LIMIT時間を超えた保有ポジションをクローズします。
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

            int expiration_seconds = CLOSE_H1_LIMIT * PeriodSeconds(PERIOD_H1);
            if(entry_time <= 0 || expiration_seconds <= 0)
               continue;

            if(TimeCurrent() - entry_time >= expiration_seconds)
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
