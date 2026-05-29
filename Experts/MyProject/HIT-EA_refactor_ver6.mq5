//+------------------------------------------------------------------+
//|                                                       HIT_EA.mq5 |
//|                               Copyright 2026,  nanpin-martin.com |
//|                                    https://www.nanpin-martin.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, nanpin-martin.com"
#property link      "https://nanpin-martin.com/"
#property version   "1.01"

#include <MyLib/Trading/SLTPManager.mqh>
#include <MyLib/Panel/SLTPManagerPanel.mqh>

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
#define TASKKILL_WAIT_MILLISECONDS        5000

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
// Python helper scripts are managed under this MT5 data folder:
// <TerminalDataPath>\MQL5\python_for_ea
string python_app_dir      = "";
string get_trend_reply_bat = ""; // H4: trend
string get_entry_reply_bat = ""; // H1: entry
string mt5_file_prefix     = ""; // Python linkage file namespace

// プロセス完了ファイルの設定
string done_trend_file = "process_done_trend.txt";
string done_entry_file = "process_done_entry.txt";

// Python出力ファイル
string ohlc_h4_file = "ohlc_H4.csv";
string ohlc_h1_file = "ohlc_H1.csv";
string trend_state_file = "trend_state.txt";
string target_prices_file = "target_prices.txt";
string target_zones_file = "target_zones.txt";

// Python実行中を判定するための管理ファイル
string running_trend_file = "process_running_trend.txt";
string running_entry_file = "process_running_entry.txt";

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| インプットの設定
//+------------------------------------------------------------------+

enum SplitLotMode
  {
   SPLIT_LOT_TOTAL = 0, // 総ロットをN分割
   SPLIT_LOT_FIXED = 1  // 1注文あたり固定ロット
  };

//--- 入力パラメータ
input double lot_size      = 0.01;  // ロット数
input double spread_limit  = 60;    // 許容スプレッド(point)
input int    magic_number  = 10001; // マジックナンバー
input int    initial_order = 0;     // 起動時の注文(0:なし, 1:あり)
input int    input_position_limit = 10; // 自EAの未約定注文+ポジション上限
input bool   use_split_entry_zone = false; // H1予測ゾーンで分割エントリーする
input int    split_entry_count = 3; // 分割エントリー本数(1..10)
input SplitLotMode split_lot_mode = SPLIT_LOT_TOTAL; // 分割ロット配分モード
input double split_total_lot_size = 0.09; // 総量分割モードの合計ロット
input double split_fixed_lot_size = 0.01; // 固定ロットモードの1注文ロット
input bool   cancel_old_split_pending_on_new_zone = true; // 新ゾーン読込時に旧分割pendingを取消
input bool   use_m15_entry_filter = true;  // M15確定足で発注タイミングを確認
input double m15_entry_zone_atr_multiplier = 1.50; // M15平均レンジ何本分まで候補価格への接近を許可
input bool   use_m15_imbalance_confirmation = true; // T1/T3でM15初動確認を追加
input int    m15_imbalance_avg_body_period = 20; // M15平均実体計算期間
input double m15_imbalance_sensitivity = 2.0; // M15初動検知感度
input double m15_imbalance_min_avg_body_points = 1.0; // 平均実体の最小値(point)
input bool   use_m15_imbalance_debug_log = false; // M15初動確認ログ
input int    input_entry_max_candidate_age_minutes = 120; // H1候補価格を新規発注に使う最大経過分数
input bool   input_sltp_manager_enabled = false;   // UI連動SLTP管理を有効化
input bool   input_sltp_show_panel = true;          // SLTP操作パネルを表示
input bool   input_sltp_use_breakeven = false;      // 通常ブレークイーブンを有効化
input double input_sltp_breakeven_trigger_pips = 30.0; // 通常BE開始pips
input double input_sltp_breakeven_buffer_pips = 3.0;   // 通常BE固定バッファpips
input bool   input_sltp_use_elapsed_breakeven = false; // 保有時間BEを有効化
input double input_sltp_elapsed_breakeven_hours = 4.0; // 保有時間BE開始時間
input double input_sltp_elapsed_breakeven_buffer_pips = 3.0; // 保有時間BE固定バッファpips
input bool   input_sltp_use_active_trailing = false; // アクティブトレーリングを有効化
input double input_sltp_active_breakeven_pips = 30.0; // アクティブ開始pips
input double input_sltp_active_stop_loss_offset_pips = 5.0; // 初期固定pips
input double input_sltp_active_step_trigger_pips = 10.0; // ステップ更新間隔pips
input double input_sltp_active_step_move_pips = 5.0; // 1ステップ固定追加pips
input bool   input_sltp_use_tp_progress_stop = false; // TP進捗SLを有効化
input double input_sltp_tp_progress_trigger_percent = 70.0; // TP進捗SL開始率
input double input_sltp_tp_progress_sl_lock_percent = 30.0; // TP距離固定率
input bool   input_sltp_use_high_volatility_limit = false; // 急変時SL引き締めを有効化
ulong  slippage      = 10;          // スリッページ

//--- 主要な定数・設定
#define POSITION_LIMIT        48
#define ENTRY_H1_LIMIT        2         // H1本数（=2時間）
#define CLOSE_H1_LIMIT        12        // H1本数（=12時間）
#define HISTORY_BARS          72
#define OHLC_START_SHIFT       1         // 1: 確定足のみをPythonへ渡す
#define M15_CONFIRM_BARS       30
#define M15_MIN_ENTRY_ZONE_POINTS 10
#define M15_MIN_BODY_RATIO     0.25
#define M15_REJECTION_WICK_RATIO 0.35
#define ENTRY_RETRY_SECONDS    60
#define ENTRY_RETRY_LIMIT      10
// ANALYZE_TIMEFRAME は削除（H4/H1 両方使うため定数ではなく直接指定）
#define TARGET_SIZE           13
#define TARGET_ZONE_SCHEMA_VERSION 2
#define DEFAULT_TARGET_PRICE  0.0
#define PYTHON_TIMEOUT_SECONDS 600       // Python完了待ちの上限（秒）

#define MARKET_LOW_VOL_RANGE       0
#define MARKET_HIGH_VOL_RANGE      1
#define MARKET_LOW_VOL_UP          2
#define MARKET_HIGH_VOL_UP         3
#define MARKET_LOW_VOL_DOWN        4
#define MARKET_HIGH_VOL_DOWN       5
#define MARKET_TECHNICAL_ERROR_STOP 6

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| EAの状態をまとめる構造体
//+------------------------------------------------------------------+

struct EAState
  {
   int               trend_state;           // H4 market_state（0..5、6は技術エラー停止）を格納する変数
   int               res_chk;               // GPTの回答が正しく取得できたか
   double            en_price[5];           // エントリー基準価格
   double            tp_price[5];           // 利益確定価格
   double            sl_price[5];           // ロスカット基準価格
   int               zone_res_chk;          // 予測ゾーンが正しく取得できたか
   string            zone_candidate_id;      // H1確定足由来の候補ID
   double            zone_low[5];           // 分割エントリー用ゾーン下限
   double            zone_high[5];          // 分割エントリー用ゾーン上限
   double            zone_tp[5];            // 分割エントリー用TP
   double            zone_sl[5];            // 分割エントリー用SL
   bool              load_trend_flg;        // ★変更：トレンドを更新するタイミングか
   bool              load_target_flg;       // ★変更：ターゲット価格を更新するタイミングか
   int               chk_cnt;               // エントリー判定の試行回数
   datetime          last_trend_update;     // ★追加：前回トレンドを更新した時刻
   datetime          last_target_update;    // ★変更：前回ターゲット価格を更新した時刻
   datetime          target_loaded_at;      // H1候補価格をEAへ読み込んだサーバー時刻
   datetime          target_candidate_at;   // H1候補価格の元になった確定足時刻
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

CSLTPManager g_sltp_manager;
CSLTPManagerPanel g_sltp_panel;
SLTPManagerPanelSettings g_sltp_settings;
bool g_sltp_settings_valid = false;
bool g_sltp_panel_created = false;

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Python連携パスをMT5データフォルダから組み立てる関数
//+------------------------------------------------------------------+
/**
 * @brief MT5データフォルダ配下のMQL5ルートを返します。
 */
string MQL5RootPath()
  {
   return TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5";
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
/**
 * @brief EAと同じMQL5ツリー内にあるPython補助アプリのルートを返します。
 */
string PythonAppDir()
  {
   return MQL5RootPath() + "\\python_for_ea";
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
/**
 * @brief Python補助アプリ配下のbatファイル絶対パスを返します。
 */
string PythonBatchPath(const string filename)
  {
   return PythonAppDir() + "\\bat\\" + filename;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
/**
 * @brief ファイル名に使える安全なトークン文字か判定します。
 */
bool IsSafeFileTokenChar(const int ch)
  {
   return ((ch >= 48 && ch <= 57) ||   // 0-9
           (ch >= 65 && ch <= 90) ||   // A-Z
           (ch >= 97 && ch <= 122) ||  // a-z
           ch == 95 || ch == 45);      // _ or -
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
/**
 * @brief シンボル名などをファイル名向けの安全なトークンへ変換します。
 */
string SanitizeFileToken(const string value)
  {
   string result = "";
   int length = StringLen(value);
   for(int i = 0; i < length; i++)
     {
      int ch = StringGetCharacter(value, i);
      if(IsSafeFileTokenChar(ch))
         result += StringSubstr(value, i, 1);
      else
         result += "_";
     }

   if(result == "")
      return "UNKNOWN";

   return result;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
/**
 * @brief 同一Terminal内の複数EA/複数シンボルで連携ファイルが衝突しない接頭辞を返します。
 */
string BuildMT5FilePrefix()
  {
   return "HIT_" + SanitizeFileToken(_Symbol) + "_" + IntegerToString(magic_number);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
/**
 * @brief Python連携ファイル名へEA固有の接頭辞を付けます。
 */
string PrefixedMT5FileName(const string base_name)
  {
   if(mt5_file_prefix == "")
      return base_name;

   return mt5_file_prefix + "_" + base_name;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
/**
 * @brief Python連携で使用するMT5 Files配下のファイル名を初期化します。
 */
void ConfigurePythonGatewayFileNames()
  {
   mt5_file_prefix = BuildMT5FilePrefix();

   ohlc_h4_file        = PrefixedMT5FileName("ohlc_H4.csv");
   ohlc_h1_file        = PrefixedMT5FileName("ohlc_H1.csv");
   done_trend_file     = PrefixedMT5FileName("process_done_trend.txt");
   done_entry_file     = PrefixedMT5FileName("process_done_entry.txt");
   trend_state_file    = PrefixedMT5FileName("trend_state.txt");
   target_prices_file  = PrefixedMT5FileName("target_prices.txt");
   target_zones_file   = PrefixedMT5FileName("target_zones.txt");
   running_trend_file  = PrefixedMT5FileName("process_running_trend.txt");
   running_entry_file  = PrefixedMT5FileName("process_running_entry.txt");

   Print("Python file prefix: ", mt5_file_prefix);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
/**
 * @brief Python連携で使用するbatパスを初期化します。
 */
void ConfigurePythonGatewayPaths()
  {
   ConfigurePythonGatewayFileNames();

   python_app_dir      = PythonAppDir();
   get_trend_reply_bat = PythonBatchPath("get_trend_reply.bat");
   get_entry_reply_bat = PythonBatchPath("get_entry_reply.bat");

   Print("Python app dir: ", python_app_dir);
  }

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
int OnInit()
// プロセス完了ファイルと実行中ファイルの状態を初期化
  {
   ConfigurePythonGatewayPaths();

   PrepareDoneFileOnInit(done_trend_file, running_trend_file, "trend");
   PrepareDoneFileOnInit(done_entry_file, running_entry_file, "entry");

   // initial_order=1 の場合でも、H4/H1を別々に1回だけ初回実行する。
   g_init_trend_pending = (initial_order == 1);
   g_init_entry_pending = (initial_order == 1);

   if(!InitializeSLTPManager())
      return INIT_FAILED;

   return INIT_SUCCEEDED;
   }

//+------------------------------------------------------------------+
//| 終了時の処理
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ResetExternalProcessState(g_trend_process);
   ResetExternalProcessState(g_entry_process);

   if(g_sltp_panel_created)
      g_sltp_panel.Destroy(reason);

   // Clear chart status text left by Comment() when the EA is removed.
   Comment("");
   ChartRedraw(0);
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

   // Existing-position protection stays active even while Python results are pending.
   ManageSLTPPositions();

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
//| SLTP manager panel and settings bridge
//+------------------------------------------------------------------+
string SLTPBoolText(const bool value)
  {
   return value ? "ON" : "OFF";
  }

void LoadSLTPInputSettings(SLTPManagerPanelSettings &settings)
  {
   settings.manager_enabled = input_sltp_manager_enabled;

   settings.use_breakeven = input_sltp_use_breakeven;
   settings.breakeven_trigger_pips = input_sltp_breakeven_trigger_pips;
   settings.breakeven_buffer_pips = input_sltp_breakeven_buffer_pips;

   settings.use_elapsed_breakeven = input_sltp_use_elapsed_breakeven;
   settings.elapsed_breakeven_hours = input_sltp_elapsed_breakeven_hours;
   settings.elapsed_breakeven_buffer_pips = input_sltp_elapsed_breakeven_buffer_pips;

   settings.use_active_trailing = input_sltp_use_active_trailing;
   settings.active_breakeven_pips = input_sltp_active_breakeven_pips;
   settings.active_stop_loss_offset_pips = input_sltp_active_stop_loss_offset_pips;
   settings.active_step_trigger_pips = input_sltp_active_step_trigger_pips;
   settings.active_step_move_pips = input_sltp_active_step_move_pips;

   settings.use_tp_progress_stop = input_sltp_use_tp_progress_stop;
   settings.tp_progress_trigger_percent = input_sltp_tp_progress_trigger_percent;
   settings.tp_progress_sl_lock_percent = input_sltp_tp_progress_sl_lock_percent;

   settings.use_high_volatility_limit = input_sltp_use_high_volatility_limit;
  }

bool ApplySLTPSettings(const SLTPManagerPanelSettings &settings,
                       const bool print_summary)
  {
   g_sltp_settings_valid = false;

   g_sltp_manager.SetMagicNumber((ulong)magic_number);
   g_sltp_manager.SetSymbol(_Symbol);
   g_sltp_manager.SetDeviationInPoints(slippage);
   g_sltp_manager.SetBreakevenSettings(settings.use_breakeven,
                                       settings.breakeven_trigger_pips,
                                       settings.breakeven_buffer_pips);
   g_sltp_manager.SetElapsedBreakevenSettings(settings.use_elapsed_breakeven,
                                              settings.elapsed_breakeven_hours,
                                              settings.elapsed_breakeven_buffer_pips);
   g_sltp_manager.SetActiveTrailingSettings(settings.use_active_trailing,
                                            settings.active_breakeven_pips,
                                            settings.active_stop_loss_offset_pips,
                                            settings.active_step_trigger_pips,
                                            settings.active_step_move_pips);
   g_sltp_manager.SetTpProgressStopSettings(settings.use_tp_progress_stop,
                                            settings.tp_progress_trigger_percent,
                                            settings.tp_progress_sl_lock_percent);
   g_sltp_manager.SetHighVolatilityLimitSettings(settings.use_high_volatility_limit);

   if(!g_sltp_manager.ValidateSettings())
     {
      Print("HIT SLTP settings rejected. Manager is disabled until valid settings are applied.");
      return false;
     }

   g_sltp_settings = settings;
   g_sltp_settings_valid = true;

   if(print_summary)
     {
      Print("HIT SLTP settings: Manager=", SLTPBoolText(settings.manager_enabled),
            " BE=", SLTPBoolText(settings.use_breakeven),
            " ElapsedBE=", SLTPBoolText(settings.use_elapsed_breakeven),
            " ActiveTrail=", SLTPBoolText(settings.use_active_trailing),
            " TPProgress=", SLTPBoolText(settings.use_tp_progress_stop),
            " HighVol=", SLTPBoolText(settings.use_high_volatility_limit));
     }

   return true;
  }

bool InitializeSLTPManager()
  {
   SLTPManagerPanelSettings initial_settings;
   LoadSLTPInputSettings(initial_settings);

   if(!ApplySLTPSettings(initial_settings, true))
      return false;

   g_sltp_panel.Init(g_sltp_settings);
   if(input_sltp_show_panel)
     {
      if(!g_sltp_panel.CreatePanel())
        {
         Print("HIT SLTP panel is unavailable. EA continues with input-based SLTP settings.");
         return true;
        }

      g_sltp_panel.SetInitialValues();
      g_sltp_panel_created = true;
     }

   return true;
  }

void ManageSLTPPositions()
  {
   if(!g_sltp_settings_valid)
      return;
   if(!g_sltp_settings.manager_enabled)
      return;

   g_sltp_manager.ManagePositions();
   g_sltp_manager.HighVolatilityLimit();
  }

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {
   if(!g_sltp_panel_created)
      return;

   SLTPManagerPanelSettings candidate_settings = g_sltp_settings;
   if(g_sltp_panel.HandleChartEvent(id, lparam, dparam, sparam, candidate_settings))
     {
      if(!ApplySLTPSettings(candidate_settings, true))
         Print("HIT SLTP panel apply failed. Please review panel values.");
     }
  }


// Function implementations are kept in project headers so the EA entry points stay compact.
#include <MyLib/Common/HITRuntimeController.mqh>
#include <MyLib/Signals/HITEntrySignal.mqh>
#include <MyLib/Common/HITExternalProcess.mqh>
#include <MyLib/Signals/HITPythonSignalGateway.mqh>
#include <MyLib/Trading/HITTradeManager.mqh>
