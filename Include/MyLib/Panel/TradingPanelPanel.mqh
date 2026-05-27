#ifndef TRADING_PANEL_PANEL_MQH
#define TRADING_PANEL_PANEL_MQH

#include <Controls/Dialog.mqh>
#include <Controls/Button.mqh>
#include <Controls/Edit.mqh>
#include <Controls/Label.mqh>

#define PANEL_NAME "SettingPanel"
#define PANEL_WIDTH 420
#define PANEL_HIEIGHT 260
#define ROW_HEIGHT 18
#define LBL_X 15
#define EDIT_X 105
#define BTN_X 160
#define FONT_SIZE 9
#define FONT_STYLE "Arial Black"

#define HEIKIN_BTN_NAME "Use_Heikin BTN"
#define LIMIT_BTN_NAME "Time_Limit_Close BTN"
#define INPUT_LOCK_BTN_NAME "INPUT_LOCK BTN"
#define BUY_TP_PLUS_BTN_NAME "Buy_TP_Plus BTN"
#define BUY_TP_MINUS_BTN_NAME "Buy_TP_Minus BTN"
#define SELL_TP_PLUS_BTN_NAME "Sell_TP_Plus BTN"
#define SELL_TP_MINUS_BTN_NAME "Sell_TP_Minus BTN"
#define BUY_TOTAL_BE_BTN_NAME "BuyTotal_BE BTN"
#define SELL_TOTAL_BE_BTN_NAME "SellTotal_BE BTN"

#define EDIT_EI_NAME "ExitTimeInterval"
#define EDIT_RANGE_NAME "RangePips"
#define EDIT_BREAKEVEN_NAME "BreakEven"
#define EDIT_BREAKEVEN_INIT_NAME "BreakEvenInit"
#define EDIT_STEP_TRAIL_NAME "StepTrail"
#define EDIT_STEP_MOVE_NAME "StepMove"
#define EDIT_SL_NAME "StopLoss"
#define EDIT_TP_NAME "TakeProfit"
#define EDIT_BUY_PLUS_NAME "Buy_TP"
#define EDIT_SELL_TP_PLUS_NAME "Sell_TP"
#define EDIT_SL_OFFSET_NAME "StopLossOffset"

class CTradingPanelPanel
{
private:
    CAppDialog m_panel;

    CEdit m_input_1st;
    CEdit m_input_2nd;
    CEdit m_input_3rd;
    CEdit m_input_4th;
    CEdit m_input_5th;
    CEdit m_input_6th;
    CEdit m_input_7th;
    CEdit m_input_8th;
    CEdit m_input_9th;
    CEdit m_input_10th;
    CEdit m_input_11th;

    CButton m_button_timelimit_exit;
    CButton m_button_input_lock;
    CButton m_button_buy_tp_plus;
    CButton m_button_buy_tp_minus;
    CButton m_button_sell_tp_plus;
    CButton m_button_sell_tp_minus;
    CButton m_button_buy_total_be;
    CButton m_button_sell_total_be;

    CLabel m_infoLabel_1st;
    CLabel m_infoLabel_2nd;
    CLabel m_infoLabel_3rd;
    CLabel m_infoLabel_4th;
    CLabel m_infoLabel_5th;
    CLabel m_infoLabel_6th;
    CLabel m_infoLabel_7th;
    CLabel m_infoLabel_9th;
    CLabel m_infoLabel_10th;
    CLabel m_infoLabel_11th;
    CLabel m_infoLabel_12th;
    CLabel m_infoLabel_13th;
    CLabel m_infoLabel_14th;
    CLabel m_infoLabel_15th;
    CLabel m_infoLabel_16th;

    int m_exitTimeIntervalInSeconds;
    double m_range_pips;
    double m_breakeven_pips;
    double m_stop_loss_offset_pips;
    double m_step_trigger_pips;
    double m_step_move_pips;
    double m_default_sl_pips;
    double m_take_profit_pips;
    double m_buy_tp_pips;
    double m_sell_tp_pips;
    double m_stop_offset_pips;

public:
    void Init(const int initial_exit_time_interval_hours,
              const double initial_range_pips,
              const double initial_breakeven_pips,
              const double initial_stop_loss_offset_pips,
              const double initial_step_trigger_pips,
              const double initial_step_move_pips,
              const double initial_default_sl_pips,
              const double initial_take_profit_pips,
              const double initial_tp_edit_pips,
              const double initial_stop_offset_pips)
    {
        m_exitTimeIntervalInSeconds = initial_exit_time_interval_hours * 3600;
        m_range_pips = initial_range_pips;
        m_breakeven_pips = initial_breakeven_pips;
        m_stop_loss_offset_pips = initial_stop_loss_offset_pips;
        m_step_trigger_pips = initial_step_trigger_pips;
        m_step_move_pips = initial_step_move_pips;
        m_default_sl_pips = initial_default_sl_pips;
        m_take_profit_pips = initial_take_profit_pips;
        m_buy_tp_pips = initial_tp_edit_pips;
        m_sell_tp_pips = initial_tp_edit_pips;
        m_stop_offset_pips = initial_stop_offset_pips;
    }

    bool CreatePanel(const bool is_input_locked)
    {
        const int chart_height = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
        const int panel_x = 10;
        const int panel_y = chart_height - PANEL_HIEIGHT - 10;

        if (!m_panel.Create(0, PANEL_NAME, 0, panel_x, panel_y,
                            panel_x + PANEL_WIDTH + 8, panel_y + PANEL_HIEIGHT))
        {
            Print("Panel create failed: err=", GetLastError());
            return false;
        }

        CreateButton(m_button_timelimit_exit, LIMIT_BTN_NAME, BTN_X, 150, 80, ROW_HEIGHT + 5,
                     "ON", clrRoyalBlue, clrWhite);
        CreateButton(m_button_input_lock, INPUT_LOCK_BTN_NAME, BTN_X, 195, 80, ROW_HEIGHT + 5,
                     "UNLOCK", clrRoyalBlue, clrWhite);
        CreateButton(m_button_buy_tp_plus, BUY_TP_PLUS_BTN_NAME, BTN_X + 193, 20, 22, ROW_HEIGHT,
                     "▲", clrGreen, clrWhite);
        CreateButton(m_button_buy_tp_minus, BUY_TP_MINUS_BTN_NAME, BTN_X + 219, 20, 22, ROW_HEIGHT,
                     "▼", clrRed, clrWhite);
        CreateButton(m_button_sell_tp_plus, SELL_TP_PLUS_BTN_NAME, BTN_X + 193, 45, 22, ROW_HEIGHT,
                     "▼", clrGreen, clrWhite);
        CreateButton(m_button_sell_tp_minus, SELL_TP_MINUS_BTN_NAME, BTN_X + 219, 45, 22, ROW_HEIGHT,
                     "▲", clrRed, clrWhite);
        CreateButton(m_button_buy_total_be, BUY_TOTAL_BE_BTN_NAME, BTN_X + 100, 105, 60, ROW_HEIGHT + 5,
                     "OFF", clrWhite, clrRoyalBlue);
        CreateButton(m_button_sell_total_be, SELL_TOTAL_BE_BTN_NAME, BTN_X + 180, 105, 60, ROW_HEIGHT + 5,
                     "OFF", clrWhite, clrRoyalBlue);

        CreateLabel(m_infoLabel_1st, "label_1", LBL_X, 20, "ExitTime(h)");
        CreateLabel(m_infoLabel_2nd, "label_2", LBL_X, 42, "Range");
        CreateLabel(m_infoLabel_3rd, "label_3", LBL_X, 64, "BreakEven");
        CreateLabel(m_infoLabel_4th, "label_4", LBL_X, 109, "TrailStep");
        CreateLabel(m_infoLabel_5th, "label_5", LBL_X, 131, "StepMove");
        CreateLabel(m_infoLabel_6th, "label_6", LBL_X, 153, "StopLoss");
        CreateLabel(m_infoLabel_7th, "label_7", LBL_X, 175, "TakeProfit");
        CreateLabel(m_infoLabel_9th, "label_9", BTN_X + 4, 130, "EXIT_TIME");
        CreateLabel(m_infoLabel_10th, "label_10", BTN_X + 10, 175, "SETTING");
        CreateLabel(m_infoLabel_11th, "label_11", BTN_X + 100, 20, "Buy TP");
        CreateLabel(m_infoLabel_12th, "label_12", BTN_X + 100, 45, "Sell TP");
        CreateLabel(m_infoLabel_13th, "label_13", BTN_X + 95, 85, "AllBuy_BE");
        CreateLabel(m_infoLabel_14th, "label_14", BTN_X + 175, 85, "AllSell_BE");
        CreateLabel(m_infoLabel_15th, "label_19", LBL_X, 87, "BE_Offset");
        CreateLabel(m_infoLabel_16th, "label_22", LBL_X, 197, "StopOffset");

        CreateEdit(m_input_1st, EDIT_EI_NAME, EDIT_X, 20);
        CreateEdit(m_input_2nd, EDIT_RANGE_NAME, EDIT_X, 42);
        CreateEdit(m_input_3rd, EDIT_BREAKEVEN_NAME, EDIT_X, 64);
        CreateEdit(m_input_10th, EDIT_BREAKEVEN_INIT_NAME, EDIT_X, 86);
        CreateEdit(m_input_4th, EDIT_STEP_TRAIL_NAME, EDIT_X, 108);
        CreateEdit(m_input_5th, EDIT_STEP_MOVE_NAME, EDIT_X, 130);
        CreateEdit(m_input_6th, EDIT_SL_NAME, EDIT_X, 152);
        CreateEdit(m_input_7th, EDIT_TP_NAME, EDIT_X, 174);
        CreateEdit(m_input_8th, EDIT_BUY_PLUS_NAME, BTN_X + 151, 20);
        CreateEdit(m_input_9th, EDIT_SELL_TP_PLUS_NAME, BTN_X + 151, 45);
        CreateEdit(m_input_11th, EDIT_SL_OFFSET_NAME, EDIT_X, 196);

        SetReadOnly(is_input_locked);
        m_panel.Run();
        return true;
    }

    void Destroy(const int reason)
    {
        m_panel.Destroy(reason);
    }

    void SetInitialValues()
    {
        m_input_1st.Text(IntegerToString(m_exitTimeIntervalInSeconds / 3600));
        m_input_2nd.Text(DoubleToString(m_range_pips, 0));
        m_input_3rd.Text(DoubleToString(m_breakeven_pips, 0));
        m_input_4th.Text(DoubleToString(m_step_trigger_pips, 0));
        m_input_5th.Text(DoubleToString(m_step_move_pips, 0));
        m_input_6th.Text(DoubleToString(m_default_sl_pips, 0));
        m_input_7th.Text(DoubleToString(m_take_profit_pips, 0));
        m_input_8th.Text(DoubleToString(m_buy_tp_pips, 0));
        m_input_9th.Text(DoubleToString(m_sell_tp_pips, 0));
        m_input_10th.Text(DoubleToString(m_stop_loss_offset_pips, 0));
        m_input_11th.Text(DoubleToString(m_stop_offset_pips, 0));
    }

    bool HandleChartEvent(const int id,
                          const long &lparam,
                          const double &dparam,
                          const string &sparam,
                          const int default_exit_time_interval_hours,
                          const double default_range_pips,
                          const double default_breakeven_pips,
                          const double default_stop_loss_offset_pips,
                          const double default_step_trigger_pips,
                          const double default_step_move_pips,
                          const double default_sl_pips,
                          const double default_take_profit_pips,
                          const double default_tp_edit_pips,
                          const double default_stop_offset_pips,
                          bool &io_timelimit_exit,
                          bool &io_input_lock,
                          bool &io_buy_total_be_flg,
                          bool &io_sell_total_be_flg,
                          int &active_exit_seconds,
                          double &active_breakeven_pips,
                          double &active_stop_loss_offset_pips,
                          double &active_step_trigger_pips,
                          double &active_step_move_pips,
                          double &active_default_sl_pips,
                          double &active_take_profit_pips,
                          double &active_stop_offset_pips,
                          ENUM_POSITION_TYPE &tp_side,
                          double &tp_adjust_pips)
    {
        tp_side = (ENUM_POSITION_TYPE)-1;
        tp_adjust_pips = 0.0;

        UpdateInputValues(default_exit_time_interval_hours,
                          default_range_pips,
                          default_breakeven_pips,
                          default_stop_loss_offset_pips,
                          default_step_trigger_pips,
                          default_step_move_pips,
                          default_sl_pips,
                          default_take_profit_pips,
                          default_tp_edit_pips,
                          default_stop_offset_pips);

        m_panel.ChartEvent(id, lparam, dparam, sparam);

        if (id != CHARTEVENT_OBJECT_CLICK)
            return false;

        if (sparam == LIMIT_BTN_NAME)
        {
            io_timelimit_exit = !io_timelimit_exit;
            ApplyToggleButton(m_button_timelimit_exit, io_timelimit_exit, "ON", "OFF");
            Print("TimeExit: ", io_timelimit_exit ? "ON" : "OFF");
            return false;
        }

        if (sparam == INPUT_LOCK_BTN_NAME)
        {
            io_input_lock = !io_input_lock;
            SetReadOnly(io_input_lock);

            if (io_input_lock)
            {
                m_button_input_lock.Text("UNLOCK");
                m_button_input_lock.Color(clrWhite);
                m_button_input_lock.ColorBackground(clrRoyalBlue);
                m_button_input_lock.ColorBorder(clrRoyalBlue);
                Print("button_input_lock: パネルのインプット：ロック");

                active_exit_seconds = m_exitTimeIntervalInSeconds;
                active_breakeven_pips = m_breakeven_pips;
                active_stop_loss_offset_pips = m_stop_loss_offset_pips;
                active_step_trigger_pips = m_step_trigger_pips;
                active_step_move_pips = m_step_move_pips;
                active_take_profit_pips = m_take_profit_pips;
                active_default_sl_pips = m_default_sl_pips;
                active_stop_offset_pips = m_stop_offset_pips;

                Print("--------------------------------------------------------");
                Print("時間制限クローズ(時間): ", active_exit_seconds / 3600, "\n",
                      "ブレークイーブン(pips): ", active_breakeven_pips, "\n",
                      "ブレークイーブン建値(pips): ", active_stop_loss_offset_pips, "\n",
                      "トレール更新(pips): ", active_step_trigger_pips, "\n",
                      "トレール更新幅(pips): ", active_step_move_pips, "\n",
                      "ストップロス(pips): ", active_default_sl_pips, "\n",
                      "テイクプロフィット(pips): ", active_take_profit_pips, "\n",
                      "ストップロスオフセット(pips): ", active_stop_offset_pips);
                Print("--------------------------------------------------------");
                Print("EA設定変更");
            }
            else
            {
                m_button_input_lock.Text("LOCK");
                m_button_input_lock.Color(clrRoyalBlue);
                m_button_input_lock.ColorBackground(clrWhite);
                m_button_input_lock.ColorBorder(clrRoyalBlue);
                Print("button_input_lock: パネルのインプット：ロック解除");
            }
            return false;
        }

        if (sparam == BUY_TP_PLUS_BTN_NAME)
        {
            Print("Buy_TP Plus PRESSED ", m_buy_tp_pips, " pips");
            tp_side = POSITION_TYPE_BUY;
            tp_adjust_pips = +m_buy_tp_pips;
            return true;
        }

        if (sparam == BUY_TP_MINUS_BTN_NAME)
        {
            Print("Buy_TP Minus PRESSED ", m_buy_tp_pips, " pips");
            tp_side = POSITION_TYPE_BUY;
            tp_adjust_pips = -m_buy_tp_pips;
            return true;
        }

        if (sparam == SELL_TP_PLUS_BTN_NAME)
        {
            Print("Sell_TP Plus PRESSED ", m_sell_tp_pips, " pips");
            tp_side = POSITION_TYPE_SELL;
            tp_adjust_pips = +m_sell_tp_pips;
            return true;
        }

        if (sparam == SELL_TP_MINUS_BTN_NAME)
        {
            Print("Sell_TP Minus PRESSED ", m_sell_tp_pips, " pips");
            tp_side = POSITION_TYPE_SELL;
            tp_adjust_pips = -m_sell_tp_pips;
            return true;
        }

        if (sparam == BUY_TOTAL_BE_BTN_NAME)
        {
            io_buy_total_be_flg = !io_buy_total_be_flg;
            ApplyToggleButton(m_button_buy_total_be, io_buy_total_be_flg, "ON", "OFF");
            Print("Buy_Total_BE: ", io_buy_total_be_flg ? "ON" : "OFF");
            return false;
        }

        if (sparam == SELL_TOTAL_BE_BTN_NAME)
        {
            io_sell_total_be_flg = !io_sell_total_be_flg;
            ApplyToggleButton(m_button_sell_total_be, io_sell_total_be_flg, "ON", "OFF");
            Print("Sell_Total_BE: ", io_sell_total_be_flg ? "ON" : "OFF");
            return false;
        }

        return false;
    }

private:
    void CreateButton(CButton &button,
                      const string name,
                      const int x,
                      const int y,
                      const int width,
                      const int height,
                      const string text,
                      const color bg_color,
                      const color text_color)
    {
        if (!button.Create(0, name, 0, x, y, 0, 0))
        {
            Print("Button create failed: ", name, " err=", GetLastError());
            return;
        }
        button.Width(width);
        button.Height(height);
        button.ColorBackground(bg_color);
        button.ColorBorder(text_color == clrRoyalBlue ? clrRoyalBlue : bg_color);
        button.Text(text);
        button.Color(text_color);
        button.Font(FONT_STYLE);
        button.FontSize(FONT_SIZE);
        m_panel.Add(button);
    }

    void CreateLabel(CLabel &label,
                     const string name,
                     const int x,
                     const int y,
                     const string text)
    {
        if (!label.Create(0, name, 0, x, y, 0, 0))
        {
            Print("Label create failed: ", name, " err=", GetLastError());
            return;
        }
        label.Width(0);
        label.Height(ROW_HEIGHT);
        label.Text(text);
        label.Font(FONT_STYLE);
        label.FontSize(FONT_SIZE);
        label.ColorBackground(clrDimGray);
        label.Color(clrDimGray);
        label.ColorBorder(clrDimGray);
        m_panel.Add(label);
    }

    void CreateEdit(CEdit &edit,
                    const string name,
                    const int x,
                    const int y)
    {
        if (!edit.Create(0, name, 0, x, y, 0, 0))
        {
            Print("Edit create failed: ", name, " err=", GetLastError());
            return;
        }
        edit.Width(37);
        edit.Height(ROW_HEIGHT);
        edit.Text("");
        edit.Font(FONT_STYLE);
        edit.FontSize(FONT_SIZE);
        edit.ColorBackground(clrWhite);
        edit.Color(clrDimGray);
        edit.ColorBorder(clrDimGray);
        m_panel.Add(edit);
    }

    void SetReadOnly(const bool is_input_locked)
    {
        m_input_1st.ReadOnly(is_input_locked);
        m_input_2nd.ReadOnly(is_input_locked);
        m_input_3rd.ReadOnly(is_input_locked);
        m_input_4th.ReadOnly(is_input_locked);
        m_input_5th.ReadOnly(is_input_locked);
        m_input_6th.ReadOnly(is_input_locked);
        m_input_7th.ReadOnly(is_input_locked);
        m_input_8th.ReadOnly(is_input_locked);
        m_input_9th.ReadOnly(is_input_locked);
        m_input_10th.ReadOnly(is_input_locked);
        m_input_11th.ReadOnly(is_input_locked);
    }

    void ApplyToggleButton(CButton &button,
                           const bool enabled,
                           const string on_text,
                           const string off_text)
    {
        if (enabled)
        {
            button.Text(on_text);
            button.Color(clrWhite);
            button.ColorBackground(clrRoyalBlue);
            button.ColorBorder(clrRoyalBlue);
        }
        else
        {
            button.Text(off_text);
            button.Color(clrRoyalBlue);
            button.ColorBackground(clrWhite);
            button.ColorBorder(clrRoyalBlue);
        }
    }

    void UpdateInputValues(const int default_exit_time_interval_hours,
                           const double default_range_pips,
                           const double default_breakeven_pips,
                           const double default_stop_loss_offset_pips,
                           const double default_step_trigger_pips,
                           const double default_step_move_pips,
                           const double default_sl_pips,
                           const double default_take_profit_pips,
                           const double default_tp_edit_pips,
                           const double default_stop_offset_pips)
    {
        UpdateIntAsHours(m_input_1st, "ExitTimeIntervalは1〜240時間の範囲で入力してください",
                         1, 240, default_exit_time_interval_hours,
                         m_exitTimeIntervalInSeconds);
        UpdateIntValue(m_input_2nd, "Rangeは10〜300の範囲で入力してください",
                       10, 300, default_range_pips, m_range_pips);
        UpdateIntValue(m_input_3rd, "BreakEvenは20〜200の範囲で入力してください",
                       10, 200, default_breakeven_pips, m_breakeven_pips);

        const int be_offset = (int)StringToInteger(m_input_10th.Text());
        if (be_offset >= 0 && be_offset <= 200 && be_offset <= m_breakeven_pips)
            m_stop_loss_offset_pips = be_offset;
        else
        {
            MessageBox("BreakEvenOffsetは0〜200の範囲かつ、BreakEven以下の範囲で入力してください", "エラー", MB_ICONERROR);
            m_input_10th.Text(DoubleToString(default_stop_loss_offset_pips, 0));
            m_stop_loss_offset_pips = default_stop_loss_offset_pips;
        }

        UpdateIntValue(m_input_4th, "StepTrigerは2〜100の範囲で入力してください",
                       2, 100, default_step_trigger_pips, m_step_trigger_pips);
        UpdateIntValue(m_input_5th, "StepMoveは1〜50の範囲で入力してください",
                       1, 50, default_step_move_pips, m_step_move_pips);
        UpdateIntValue(m_input_6th, "StopLossは0〜999の範囲で入力してください",
                       0, 999, default_sl_pips, m_default_sl_pips);
        UpdateIntValue(m_input_7th, "TakeProfitは0〜999の範囲で入力してください",
                       0, 999, default_take_profit_pips, m_take_profit_pips);
        UpdateIntValue(m_input_11th, "StopLossOffsetは0〜50の範囲で入力してください",
                       0, 50, default_stop_offset_pips, m_stop_offset_pips);
        UpdateIntValue(m_input_8th, "TakeProfitは0〜999の範囲で入力してください",
                       0, 999, default_tp_edit_pips, m_buy_tp_pips);
        UpdateIntValue(m_input_9th, "TakeProfitは0〜999の範囲で入力してください",
                       0, 999, default_tp_edit_pips, m_sell_tp_pips);
    }

    void UpdateIntAsHours(CEdit &edit,
                          const string error_message,
                          const int min_value,
                          const int max_value,
                          const int default_hours,
                          int &target_seconds)
    {
        const int value = (int)StringToInteger(edit.Text());
        if (value >= min_value && value <= max_value)
        {
            target_seconds = value * 3600;
            return;
        }

        MessageBox(error_message, "エラー", MB_ICONERROR);
        edit.Text(IntegerToString(default_hours));
        target_seconds = default_hours * 3600;
    }

    void UpdateIntValue(CEdit &edit,
                        const string error_message,
                        const int min_value,
                        const int max_value,
                        const double default_value,
                        double &target)
    {
        const int value = (int)StringToInteger(edit.Text());
        if (value >= min_value && value <= max_value)
        {
            target = value;
            return;
        }

        MessageBox(error_message, "エラー", MB_ICONERROR);
        edit.Text(DoubleToString(default_value, 0));
        target = default_value;
    }
};

#endif

