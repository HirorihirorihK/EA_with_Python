//+------------------------------------------------------------------+
//| TradingPanel EA entry point
//+------------------------------------------------------------------+
#include <MyLib/Trading/TradingPanelTradingManagers.mqh>
#include <MyLib/Panel/TradingPanelPanel.mqh>

#define POSITION_TYPE_ALL ((ENUM_POSITION_TYPE) - 1) // フィルタ無し

// トータルブレークイーブン
#define BE_BUY "BreakEvenBuy"
#define BE_SELL "BreakEvenSell"

//--- カテゴリ1：取引設定
input group "■ 取引設定";
input int exit_time_interval = 4; // 時間制限クローズまでの保有時間（時間）

//--- カテゴリ2：基本設定
input group "■ 基本設定";
input ulong slippage = 10;       //  スリッページ
input int magic_number = 10001;  //  マジックナンバー

input group "■ SLTP設定: Common";
input double take_profit_pips = 150.0;   // TP設定値
input double default_sl = 100.0;         // SL初期値
input double stop_offset_pips = 10.0;    // ストップロスオフセット(pips)

input group "■ SLTP設定: TRAIL";
input bool enable_breakeven = true;          // ブレークイーブンを有効化
input double breakeven_pips = 30.0;       // ブレークイーブン判定利幅
input double stop_loss_offset_pips = 5.0; // 建値からのマージン
input double step_trigger_pips = 10.0;    // トレール更新トリガーpips
input double step_move_pips = 8.0;        // トレール更新pips
input double tp_edit_pips = 10.0;         // TP更新初期pips

//--- カテゴリ4：フィルター設定
input group "■ レンジフィルター設定";
input double range_pips = 80.0;     // レンジ幅pips1

//--- カテゴリ5：時間設定
input group "■ 取引時間設定";
input bool isTradingTimeEnabled = true; // 取引時間を制限
input int TradeStartHour = 4;           // 開始時間GMT(時間)
input int TradeStartMin = 0;            // 開始時間GMT(分)
input int TradeEndHour = 23;            // 終了時間GMT(時間)
input int TradeEndMin = 0;              // 終了時間GMT(分)

int TimerPeriod_sec = 1; // n 秒ごとに OnTimer

bool wasInTradingTime = false;
bool beforeTradingInitDone = false;
bool afterTradingInitDone = false;

bool timelimit_exit = true;   // 時間制限クローズ 初期状態

bool input_lock = true; // 時間制限クローズ 初期状態

// --------------------------------------------------------------
// EAとの共有用グローバル変数
// --------------------------------------------------------------
int gl_exitTimeIntervalInSeconds = exit_time_interval * 3600;
double gl_breakeven_pips = breakeven_pips;
double gl_stop_loss_offset_pips = stop_loss_offset_pips;
double gl_step_trigger_pips = step_trigger_pips;
double gl_step_move_pips = step_move_pips;
double gl_default_sl_pips = default_sl;
double gl_take_profit_pips = take_profit_pips;
double gl_stop_offset_pips = stop_offset_pips;

int buy_position = 0;             // CountPositions() で随時更新
int sell_position = 0;
datetime last_buy_time = 0;
datetime last_sell_time = 0;
bool buy_total_be_flg = false;
bool sell_total_be_flg = false;

//+------------------------------------------------------------------+
//| トータルのブレークイーブン用変数
//+------------------------------------------------------------------+
bool InpShowBuyLine = true;   // 買いのブレークイーブンライン
bool InpShowSellLine = true;  // 売りのブレークイーブンライン
double BufferPips = 2.0;      // BE バッファ
int LabelShiftBars = 60;      // 何本前のバーにラベルを置くか
double LabelOffsetPips = 4.0; // ライン ⇔ ラベルの距離

CTradingPanelStopManager g_stop_manager;
CTradingPanelPositionManager g_position_manager;
CTradingPanelBreakEvenLineManager g_break_even_manager;
CTradingPanelPanel g_panel;

//+------------------------------------------------------------------+
//| 起動時の処理
//+------------------------------------------------------------------+
int OnInit()
{
    g_stop_manager.Init(_Symbol, (ulong)magic_number, slippage);
    g_position_manager.Init(_Symbol, (ulong)magic_number, slippage);
    g_break_even_manager.Init(_Symbol, (ulong)magic_number);
    g_panel.Init(exit_time_interval,
                 range_pips,
                 breakeven_pips,
                 stop_loss_offset_pips,
                 step_trigger_pips,
                 step_move_pips,
                 default_sl,
                 take_profit_pips,
                 tp_edit_pips,
                 stop_offset_pips);

    // EA設定変更用のパネルを表示
    if (!g_panel.CreatePanel(input_lock))
        return INIT_FAILED;
    g_panel.SetInitialValues();

    // Backfill missing initial stops for existing matching positions.
    g_position_manager.ApplyInitialStops(gl_default_sl_pips, gl_take_profit_pips);

    // タイマーをセット
    EventSetTimer(TimerPeriod_sec);

    return (INIT_SUCCEEDED); // 成功コードを明示しておく
}

//+------------------------------------------------------------------+
//| 削除時の処理
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    EventKillTimer();

    // EA適用後のプロパティで変更すると、EAを再読み込みする。
    g_panel.Destroy(reason);

    // トータルブレークイーブンラインを削除
    if (InpShowBuyLine)
        g_break_even_manager.DeleteLine(BE_BUY);

    if (InpShowSellLine)
        g_break_even_manager.DeleteLine(BE_SELL);

    // EAが削除された際にコメントを消す
    Comment("");
}

//+------------------------------------------------------------------+
//| タイマー処理
//+------------------------------------------------------------------+
void OnTimer()
{
    // 時間状態の変化を検知
    HandleTradingTimeTransition();

    // ティックが少ない時間帯でも時間制限クローズを監視する。
    g_position_manager.CloseTimedPositions(POSITION_TYPE_BUY, ORDER_TYPE_SELL,
                                           timelimit_exit, gl_exitTimeIntervalInSeconds, slippage);
    g_position_manager.CloseTimedPositions(POSITION_TYPE_SELL, ORDER_TYPE_BUY,
                                           timelimit_exit, gl_exitTimeIntervalInSeconds, slippage);

    // 取引時間が指定時間内か確認
    if (!IsTradingTime())
        return;
}

//+------------------------------------------------------------------+
//| ティック毎の処理
//+------------------------------------------------------------------+
void OnTick()
{
    // 時間状態の変化を検知
    HandleTradingTimeTransition();

    // EAの設定を画面上に表示
    DisplayEAValues();

    // 時間制限クローズは取引時間フィルターとは独立して実行する。
    g_position_manager.CloseTimedPositions(POSITION_TYPE_BUY, ORDER_TYPE_SELL,
                                           timelimit_exit, gl_exitTimeIntervalInSeconds, slippage);
    g_position_manager.CloseTimedPositions(POSITION_TYPE_SELL, ORDER_TYPE_BUY,
                                           timelimit_exit, gl_exitTimeIntervalInSeconds, slippage);

    // 取引時間が指定時間内か確認
    if (!IsTradingTime())
        return;

    // レート急伸SL
    g_stop_manager.HighVolatilityLimit();

    //------------------------------------
    // ブレークイーブン / トレールストップ監視
    //------------------------------------
    g_stop_manager.ManageStops(enable_breakeven,
                               gl_breakeven_pips,
                               gl_stop_loss_offset_pips,
                               gl_step_trigger_pips,
                               gl_step_move_pips);

    g_break_even_manager.ManageBuy(buy_total_be_flg && InpShowBuyLine,
                                   buy_total_be_flg,
                                   BufferPips,
                                   LabelShiftBars,
                                   LabelOffsetPips,
                                   gl_default_sl_pips,
                                   g_stop_manager);
    g_break_even_manager.ManageSell(sell_total_be_flg && InpShowSellLine,
                                    sell_total_be_flg,
                                    BufferPips,
                                    LabelShiftBars,
                                    LabelOffsetPips,
                                    gl_default_sl_pips,
                                    g_stop_manager);

    // 保有ポジションの確認
    buy_position = g_position_manager.CountPositions(POSITION_TYPE_BUY, magic_number);
    sell_position = g_position_manager.CountPositions(POSITION_TYPE_SELL, magic_number);
}

//+------------------------------------------------------------------+
//| 取引時間を指定する関数
//+------------------------------------------------------------------+
bool IsTradingTime()
{
    // 取引時間が有効化されていない場合、常にtrueを返す
    if (!isTradingTimeEnabled)
    {
        return true;
    }

    MqlDateTime structTime;
    TimeCurrent(structTime);
    structTime.sec = 0;

    structTime.hour = TradeStartHour;
    structTime.min = TradeStartMin;
    datetime timeStart = StructToTime(structTime);

    structTime.hour = TradeEndHour;
    structTime.min = TradeEndMin;
    datetime timeEnd = StructToTime(structTime);

    // エラーチェック
    if (TradeStartHour >= TradeEndHour && TradeStartMin >= TradeEndMin)
    {
        Print("Error: Invalid Time input");
        return false;
    }

    // 現在の時間を取得
    datetime now = TimeCurrent();

    // 時間内かどうかをチェック
    return (now >= timeStart && now < timeEnd);
}

//+------------------------------------------------------------------+
//| 取引時間内外に状態が変化した時の初期化処理
//+------------------------------------------------------------------+
void HandleTradingTimeTransition()
{
    bool nowInTradingTime = IsTradingTime();

    // --- 時間内に入った瞬間 ---
    if (nowInTradingTime && !wasInTradingTime)
    {
        if (!beforeTradingInitDone)
        {
            Print("取引時間内 初期化処理");
            beforeTradingInitDone = true;
        }
        afterTradingInitDone = false;
    }

    // --- 時間外に出た瞬間 ---
    if (!nowInTradingTime && wasInTradingTime)
    {
        if (!afterTradingInitDone)
        {
            Print("取引時間外 初期化処理");
            afterTradingInitDone = true;
        }
        beforeTradingInitDone = false;
    }

    wasInTradingTime = nowInTradingTime;
}

//+------------------------------------------------------------------+
//| pipsを価格に換算する関数
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
// 出力処理を関数にまとめる
//+------------------------------------------------------------------+
void DisplayEAValues()
{
    Comment("\n",
            "ブレークイーブン: ", (int)gl_breakeven_pips, "pips\n",
            "時間制限クローズ: ", timelimit_exit ? "ON" : "OFF",
            " | 保有時間: ", gl_exitTimeIntervalInSeconds / 3600, "時間\n",
            "------------------------------------------------------------------------------------\n");
}

// +------------------------------------------------------------------+
// | チャートイベントのハンドラ
// +------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    ENUM_POSITION_TYPE tp_side = POSITION_TYPE_ALL;
    double tp_adjust_pips = 0.0;

    if (g_panel.HandleChartEvent(id,
                                 lparam,
                                 dparam,
                                 sparam,
                                 exit_time_interval,
                                 range_pips,
                                 breakeven_pips,
                                 stop_loss_offset_pips,
                                 step_trigger_pips,
                                 step_move_pips,
                                 default_sl,
                                 take_profit_pips,
                                 tp_edit_pips,
                                 stop_offset_pips,
                                 timelimit_exit,
                                 input_lock,
                                 buy_total_be_flg,
                                 sell_total_be_flg,
                                 gl_exitTimeIntervalInSeconds,
                                 gl_breakeven_pips,
                                 gl_stop_loss_offset_pips,
                                 gl_step_trigger_pips,
                                 gl_step_move_pips,
                                 gl_default_sl_pips,
                                 gl_take_profit_pips,
                                 gl_stop_offset_pips,
                                 tp_side,
                                 tp_adjust_pips))
    {
        g_position_manager.AdjustTakeProfit(tp_adjust_pips, tp_side);
    }
}

//------------------------------------------------------------------
// 取引イベントコールバック（再エントリーを防止）
//------------------------------------------------------------------
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
    bool recalc_needed = false; // ポジション再集計フラグ

    // 1) Deal が追加された（約定）
    if (trans.type == TRADE_TRANSACTION_DEAL_ADD)
    {
        recalc_needed = true;

        //---- Deal 詳細を取得 --------------------------------------
        if (HistoryDealSelect(trans.deal)) // Deal を選択
        {
            ENUM_DEAL_REASON deal_reason = (ENUM_DEAL_REASON)
                HistoryDealGetInteger(trans.deal, DEAL_REASON);

            ENUM_DEAL_ENTRY deal_entry = (ENUM_DEAL_ENTRY)
                HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

            //==== ★ クローズ条件（手動 or SL/TP） ===================
            bool is_close =
                (deal_entry == DEAL_ENTRY_OUT) &&
                (deal_reason == DEAL_REASON_CLIENT || // 手動決済
                 deal_reason == DEAL_REASON_MOBILE || // スマホアプリ決済
                 deal_reason == DEAL_REASON_WEB ||    // WEB版決済
                 deal_reason == DEAL_REASON_EXPERT || // EAのタイマー決済
                 deal_reason == DEAL_REASON_SL ||     // SL ヒット（部分／全量とも）
                 deal_reason == DEAL_REASON_TP);      // TP ヒット（部分／全量とも）

            if (is_close)
            {
                Print("Position closed (", EnumToString(deal_reason), ") — EA waits for next prediction.");
            }
        }
    }

    // 2) サーバ側でポジション内容が変更 (数量減少・SL変更等)
    else if (trans.type == TRADE_TRANSACTION_POSITION)
    {
        recalc_needed = true;
    }

    // 3) 必要に応じてポジション再集計
    if (recalc_needed)
    {
        g_position_manager.CheckPositions(buy_position, sell_position, last_buy_time, last_sell_time);
        g_position_manager.ApplyInitialStops(gl_default_sl_pips, gl_take_profit_pips);
    }
}

