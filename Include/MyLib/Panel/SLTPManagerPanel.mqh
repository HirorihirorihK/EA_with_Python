#ifndef SLTP_MANAGER_PANEL_MQH
#define SLTP_MANAGER_PANEL_MQH

#include <Controls/Dialog.mqh>
#include <Controls/Button.mqh>
#include <Controls/Edit.mqh>
#include <Controls/Label.mqh>

#define HIT_SLTP_PANEL_NAME "HIT_SLTP_Manager_Panel"
#define HIT_SLTP_PANEL_WIDTH 620
#define HIT_SLTP_PANEL_HEIGHT 370
#define HIT_SLTP_ROW_HEIGHT 22
#define HIT_SLTP_LABEL_X 15
#define HIT_SLTP_LABEL_WIDTH 125
#define HIT_SLTP_BUTTON_X 150
#define HIT_SLTP_BUTTON_WIDTH 74
#define HIT_SLTP_BUTTON_HEIGHT 26
#define HIT_SLTP_EDIT_X1 240
#define HIT_SLTP_EDIT_X2 330
#define HIT_SLTP_EDIT_X3 420
#define HIT_SLTP_EDIT_X4 510
#define HIT_SLTP_EDIT_WIDTH 80
#define HIT_SLTP_APPLY_WIDTH 90
#define HIT_SLTP_APPLY_HEIGHT 28
#define HIT_SLTP_TITLE_Y 8
#define HIT_SLTP_TITLE_WIDTH 240
#define HIT_SLTP_MASTER_ROW_Y 38
#define HIT_SLTP_BE_ROW_Y 82
#define HIT_SLTP_ELAPSED_ROW_Y 128
#define HIT_SLTP_ACTIVE_ROW_Y 174
#define HIT_SLTP_TP_ROW_Y 220
#define HIT_SLTP_HIGH_VOL_ROW_Y 266
#define HIT_SLTP_APPLY_ROW_Y 302
#define HIT_SLTP_FONT_SIZE 9
#define HIT_SLTP_FONT_STYLE "Arial Black"

#define HIT_SLTP_MASTER_BTN_NAME "HIT_SLTP_MASTER_BTN"
#define HIT_SLTP_BE_BTN_NAME "HIT_SLTP_BE_BTN"
#define HIT_SLTP_ELAPSED_BE_BTN_NAME "HIT_SLTP_ELAPSED_BE_BTN"
#define HIT_SLTP_ACTIVE_TRAIL_BTN_NAME "HIT_SLTP_ACTIVE_TRAIL_BTN"
#define HIT_SLTP_TP_PROGRESS_BTN_NAME "HIT_SLTP_TP_PROGRESS_BTN"
#define HIT_SLTP_HIGH_VOL_BTN_NAME "HIT_SLTP_HIGH_VOL_BTN"
#define HIT_SLTP_APPLY_BTN_NAME "HIT_SLTP_APPLY_BTN"

#define HIT_SLTP_BE_TRIGGER_EDIT_NAME "HIT_SLTP_BE_TRIGGER"
#define HIT_SLTP_BE_BUFFER_EDIT_NAME "HIT_SLTP_BE_BUFFER"
#define HIT_SLTP_ELAPSED_HOURS_EDIT_NAME "HIT_SLTP_ELAPSED_HOURS"
#define HIT_SLTP_ELAPSED_BUFFER_EDIT_NAME "HIT_SLTP_ELAPSED_BUFFER"
#define HIT_SLTP_ACTIVE_START_EDIT_NAME "HIT_SLTP_ACTIVE_START"
#define HIT_SLTP_ACTIVE_OFFSET_EDIT_NAME "HIT_SLTP_ACTIVE_OFFSET"
#define HIT_SLTP_ACTIVE_STEP_TRIGGER_EDIT_NAME "HIT_SLTP_ACTIVE_STEP_TRIGGER"
#define HIT_SLTP_ACTIVE_STEP_MOVE_EDIT_NAME "HIT_SLTP_ACTIVE_STEP_MOVE"
#define HIT_SLTP_TP_TRIGGER_EDIT_NAME "HIT_SLTP_TP_TRIGGER"
#define HIT_SLTP_TP_LOCK_EDIT_NAME "HIT_SLTP_TP_LOCK"

struct SLTPManagerPanelSettings
{
    bool manager_enabled;

    bool use_breakeven;
    double breakeven_trigger_pips;
    double breakeven_buffer_pips;

    bool use_elapsed_breakeven;
    double elapsed_breakeven_hours;
    double elapsed_breakeven_buffer_pips;

    bool use_active_trailing;
    double active_breakeven_pips;
    double active_stop_loss_offset_pips;
    double active_step_trigger_pips;
    double active_step_move_pips;

    bool use_tp_progress_stop;
    double tp_progress_trigger_percent;
    double tp_progress_sl_lock_percent;

    bool use_high_volatility_limit;
};

class CSLTPManagerPanel
{
private:
    CAppDialog m_panel;

    CButton m_button_master;
    CButton m_button_breakeven;
    CButton m_button_elapsed_breakeven;
    CButton m_button_active_trailing;
    CButton m_button_tp_progress;
    CButton m_button_high_volatility;
    CButton m_button_apply;

    CEdit m_edit_breakeven_trigger;
    CEdit m_edit_breakeven_buffer;
    CEdit m_edit_elapsed_hours;
    CEdit m_edit_elapsed_buffer;
    CEdit m_edit_active_start;
    CEdit m_edit_active_offset;
    CEdit m_edit_active_step_trigger;
    CEdit m_edit_active_step_move;
    CEdit m_edit_tp_trigger;
    CEdit m_edit_tp_lock;

    CLabel m_label_title;
    CLabel m_label_master;
    CLabel m_label_breakeven;
    CLabel m_label_elapsed_breakeven;
    CLabel m_label_active_trailing;
    CLabel m_label_tp_progress;
    CLabel m_label_high_volatility;
    CLabel m_label_be_trigger;
    CLabel m_label_be_buffer;
    CLabel m_label_elapsed_hours;
    CLabel m_label_elapsed_buffer;
    CLabel m_label_active_start;
    CLabel m_label_active_offset;
    CLabel m_label_active_step_trigger;
    CLabel m_label_active_step_move;
    CLabel m_label_tp_trigger;
    CLabel m_label_tp_lock;

    SLTPManagerPanelSettings m_settings;

public:
    void Init(const SLTPManagerPanelSettings &initial_settings)
    {
        m_settings = initial_settings;
    }

    bool CreatePanel()
    {
        const int chart_width = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
        int panel_x = chart_width - HIT_SLTP_PANEL_WIDTH - 20;
        if (panel_x < 10)
            panel_x = 10;
        const int panel_y = 25;

        if (!m_panel.Create(0, HIT_SLTP_PANEL_NAME, 0, panel_x, panel_y,
                            panel_x + HIT_SLTP_PANEL_WIDTH + 8,
                            panel_y + HIT_SLTP_PANEL_HEIGHT))
        {
            Print("SLTP panel create failed: err=", GetLastError());
            return false;
        }

        CreateLabel(m_label_title, "HIT_SLTP_LABEL_TITLE", HIT_SLTP_LABEL_X, HIT_SLTP_TITLE_Y,
                    HIT_SLTP_TITLE_WIDTH, "HIT SLTP Manager");

        CreateLabel(m_label_master, "HIT_SLTP_LABEL_MASTER", HIT_SLTP_LABEL_X, HIT_SLTP_MASTER_ROW_Y,
                    HIT_SLTP_LABEL_WIDTH, "Manager");
        CreateButton(m_button_master, HIT_SLTP_MASTER_BTN_NAME, HIT_SLTP_BUTTON_X, HIT_SLTP_MASTER_ROW_Y,
                     HIT_SLTP_BUTTON_WIDTH, HIT_SLTP_BUTTON_HEIGHT);

        CreateLabel(m_label_breakeven, "HIT_SLTP_LABEL_BE", HIT_SLTP_LABEL_X, HIT_SLTP_BE_ROW_Y,
                    HIT_SLTP_LABEL_WIDTH, "BreakEven");
        CreateButton(m_button_breakeven, HIT_SLTP_BE_BTN_NAME, HIT_SLTP_BUTTON_X, HIT_SLTP_BE_ROW_Y,
                     HIT_SLTP_BUTTON_WIDTH, HIT_SLTP_BUTTON_HEIGHT);
        CreateLabel(m_label_be_trigger, "HIT_SLTP_LABEL_BE_TRG", HIT_SLTP_EDIT_X1,
                    HIT_SLTP_BE_ROW_Y - HIT_SLTP_ROW_HEIGHT, HIT_SLTP_EDIT_WIDTH, "Trigger");
        CreateLabel(m_label_be_buffer, "HIT_SLTP_LABEL_BE_BUF", HIT_SLTP_EDIT_X2,
                    HIT_SLTP_BE_ROW_Y - HIT_SLTP_ROW_HEIGHT, HIT_SLTP_EDIT_WIDTH, "Buffer");
        CreateEdit(m_edit_breakeven_trigger, HIT_SLTP_BE_TRIGGER_EDIT_NAME, HIT_SLTP_EDIT_X1,
                   HIT_SLTP_BE_ROW_Y, HIT_SLTP_EDIT_WIDTH);
        CreateEdit(m_edit_breakeven_buffer, HIT_SLTP_BE_BUFFER_EDIT_NAME, HIT_SLTP_EDIT_X2,
                   HIT_SLTP_BE_ROW_Y, HIT_SLTP_EDIT_WIDTH);

        CreateLabel(m_label_elapsed_breakeven, "HIT_SLTP_LABEL_ELAPSED", HIT_SLTP_LABEL_X,
                    HIT_SLTP_ELAPSED_ROW_Y, HIT_SLTP_LABEL_WIDTH, "Elapsed BE");
        CreateButton(m_button_elapsed_breakeven, HIT_SLTP_ELAPSED_BE_BTN_NAME, HIT_SLTP_BUTTON_X,
                     HIT_SLTP_ELAPSED_ROW_Y, HIT_SLTP_BUTTON_WIDTH, HIT_SLTP_BUTTON_HEIGHT);
        CreateLabel(m_label_elapsed_hours, "HIT_SLTP_LABEL_EL_H", HIT_SLTP_EDIT_X1,
                    HIT_SLTP_ELAPSED_ROW_Y - HIT_SLTP_ROW_HEIGHT, HIT_SLTP_EDIT_WIDTH, "Hours");
        CreateLabel(m_label_elapsed_buffer, "HIT_SLTP_LABEL_EL_BUF", HIT_SLTP_EDIT_X2,
                    HIT_SLTP_ELAPSED_ROW_Y - HIT_SLTP_ROW_HEIGHT, HIT_SLTP_EDIT_WIDTH, "Buffer");
        CreateEdit(m_edit_elapsed_hours, HIT_SLTP_ELAPSED_HOURS_EDIT_NAME, HIT_SLTP_EDIT_X1,
                   HIT_SLTP_ELAPSED_ROW_Y, HIT_SLTP_EDIT_WIDTH);
        CreateEdit(m_edit_elapsed_buffer, HIT_SLTP_ELAPSED_BUFFER_EDIT_NAME, HIT_SLTP_EDIT_X2,
                   HIT_SLTP_ELAPSED_ROW_Y, HIT_SLTP_EDIT_WIDTH);

        CreateLabel(m_label_active_trailing, "HIT_SLTP_LABEL_ACTIVE", HIT_SLTP_LABEL_X,
                    HIT_SLTP_ACTIVE_ROW_Y, HIT_SLTP_LABEL_WIDTH, "Active Trail");
        CreateButton(m_button_active_trailing, HIT_SLTP_ACTIVE_TRAIL_BTN_NAME, HIT_SLTP_BUTTON_X,
                     HIT_SLTP_ACTIVE_ROW_Y, HIT_SLTP_BUTTON_WIDTH, HIT_SLTP_BUTTON_HEIGHT);
        CreateLabel(m_label_active_start, "HIT_SLTP_LABEL_ACT_START", HIT_SLTP_EDIT_X1,
                    HIT_SLTP_ACTIVE_ROW_Y - HIT_SLTP_ROW_HEIGHT, HIT_SLTP_EDIT_WIDTH, "Start");
        CreateLabel(m_label_active_offset, "HIT_SLTP_LABEL_ACT_OFFSET", HIT_SLTP_EDIT_X2,
                    HIT_SLTP_ACTIVE_ROW_Y - HIT_SLTP_ROW_HEIGHT, HIT_SLTP_EDIT_WIDTH, "Offset");
        CreateLabel(m_label_active_step_trigger, "HIT_SLTP_LABEL_ACT_TRG", HIT_SLTP_EDIT_X3,
                    HIT_SLTP_ACTIVE_ROW_Y - HIT_SLTP_ROW_HEIGHT, HIT_SLTP_EDIT_WIDTH, "StepTrig");
        CreateLabel(m_label_active_step_move, "HIT_SLTP_LABEL_ACT_MOVE", HIT_SLTP_EDIT_X4,
                    HIT_SLTP_ACTIVE_ROW_Y - HIT_SLTP_ROW_HEIGHT, HIT_SLTP_EDIT_WIDTH, "StepMove");
        CreateEdit(m_edit_active_start, HIT_SLTP_ACTIVE_START_EDIT_NAME, HIT_SLTP_EDIT_X1,
                   HIT_SLTP_ACTIVE_ROW_Y, HIT_SLTP_EDIT_WIDTH);
        CreateEdit(m_edit_active_offset, HIT_SLTP_ACTIVE_OFFSET_EDIT_NAME, HIT_SLTP_EDIT_X2,
                   HIT_SLTP_ACTIVE_ROW_Y, HIT_SLTP_EDIT_WIDTH);
        CreateEdit(m_edit_active_step_trigger, HIT_SLTP_ACTIVE_STEP_TRIGGER_EDIT_NAME, HIT_SLTP_EDIT_X3,
                   HIT_SLTP_ACTIVE_ROW_Y, HIT_SLTP_EDIT_WIDTH);
        CreateEdit(m_edit_active_step_move, HIT_SLTP_ACTIVE_STEP_MOVE_EDIT_NAME, HIT_SLTP_EDIT_X4,
                   HIT_SLTP_ACTIVE_ROW_Y, HIT_SLTP_EDIT_WIDTH);

        CreateLabel(m_label_tp_progress, "HIT_SLTP_LABEL_TP_PROGRESS", HIT_SLTP_LABEL_X,
                    HIT_SLTP_TP_ROW_Y, HIT_SLTP_LABEL_WIDTH, "TP Progress");
        CreateButton(m_button_tp_progress, HIT_SLTP_TP_PROGRESS_BTN_NAME, HIT_SLTP_BUTTON_X,
                     HIT_SLTP_TP_ROW_Y, HIT_SLTP_BUTTON_WIDTH, HIT_SLTP_BUTTON_HEIGHT);
        CreateLabel(m_label_tp_trigger, "HIT_SLTP_LABEL_TP_TRG", HIT_SLTP_EDIT_X1,
                    HIT_SLTP_TP_ROW_Y - HIT_SLTP_ROW_HEIGHT, HIT_SLTP_EDIT_WIDTH, "Trig %");
        CreateLabel(m_label_tp_lock, "HIT_SLTP_LABEL_TP_LOCK", HIT_SLTP_EDIT_X2,
                    HIT_SLTP_TP_ROW_Y - HIT_SLTP_ROW_HEIGHT, HIT_SLTP_EDIT_WIDTH, "Lock %");
        CreateEdit(m_edit_tp_trigger, HIT_SLTP_TP_TRIGGER_EDIT_NAME, HIT_SLTP_EDIT_X1,
                   HIT_SLTP_TP_ROW_Y, HIT_SLTP_EDIT_WIDTH);
        CreateEdit(m_edit_tp_lock, HIT_SLTP_TP_LOCK_EDIT_NAME, HIT_SLTP_EDIT_X2,
                   HIT_SLTP_TP_ROW_Y, HIT_SLTP_EDIT_WIDTH);

        CreateLabel(m_label_high_volatility, "HIT_SLTP_LABEL_HIGH_VOL", HIT_SLTP_LABEL_X,
                    HIT_SLTP_HIGH_VOL_ROW_Y, HIT_SLTP_LABEL_WIDTH, "High Vol");
        CreateButton(m_button_high_volatility, HIT_SLTP_HIGH_VOL_BTN_NAME, HIT_SLTP_BUTTON_X,
                     HIT_SLTP_HIGH_VOL_ROW_Y, HIT_SLTP_BUTTON_WIDTH, HIT_SLTP_BUTTON_HEIGHT);

        CreateButton(m_button_apply, HIT_SLTP_APPLY_BTN_NAME, HIT_SLTP_EDIT_X4, HIT_SLTP_APPLY_ROW_Y,
                     HIT_SLTP_APPLY_WIDTH, HIT_SLTP_APPLY_HEIGHT);
        m_button_apply.Text("APPLY");
        m_button_apply.Color(clrWhite);
        m_button_apply.ColorBackground(clrSeaGreen);
        m_button_apply.ColorBorder(clrSeaGreen);

        RefreshControls();
        m_panel.Run();
        return true;
    }

    void Destroy(const int reason)
    {
        m_panel.Destroy(reason);
    }

    void SetInitialValues()
    {
        RefreshControls();
    }

    bool HandleChartEvent(const int id,
                          const long &lparam,
                          const double &dparam,
                          const string &sparam,
                          SLTPManagerPanelSettings &applied_settings)
    {
        m_panel.ChartEvent(id, lparam, dparam, sparam);

        if (id != CHARTEVENT_OBJECT_CLICK)
            return false;

        if (sparam == HIT_SLTP_MASTER_BTN_NAME)
        {
            m_settings.manager_enabled = !m_settings.manager_enabled;
            RefreshButtons();
            return false;
        }

        if (sparam == HIT_SLTP_BE_BTN_NAME)
        {
            m_settings.use_breakeven = !m_settings.use_breakeven;
            if (m_settings.use_breakeven)
                m_settings.use_active_trailing = false;
            RefreshButtons();
            return false;
        }

        if (sparam == HIT_SLTP_ELAPSED_BE_BTN_NAME)
        {
            m_settings.use_elapsed_breakeven = !m_settings.use_elapsed_breakeven;
            RefreshButtons();
            return false;
        }

        if (sparam == HIT_SLTP_ACTIVE_TRAIL_BTN_NAME)
        {
            m_settings.use_active_trailing = !m_settings.use_active_trailing;
            if (m_settings.use_active_trailing)
                m_settings.use_breakeven = false;
            RefreshButtons();
            return false;
        }

        if (sparam == HIT_SLTP_TP_PROGRESS_BTN_NAME)
        {
            m_settings.use_tp_progress_stop = !m_settings.use_tp_progress_stop;
            RefreshButtons();
            return false;
        }

        if (sparam == HIT_SLTP_HIGH_VOL_BTN_NAME)
        {
            m_settings.use_high_volatility_limit = !m_settings.use_high_volatility_limit;
            RefreshButtons();
            return false;
        }

        if (sparam == HIT_SLTP_APPLY_BTN_NAME)
        {
            if (!ReadInputs())
                return false;

            applied_settings = m_settings;
            Print("HIT SLTP panel settings applied.");
            return true;
        }

        return false;
    }

private:
    void CreateButton(CButton &button,
                      const string name,
                      const int x,
                      const int y,
                      const int width,
                      const int height)
    {
        if (!button.Create(0, name, 0, x, y, 0, 0))
        {
            Print("SLTP button create failed: ", name, " err=", GetLastError());
            return;
        }
        button.Width(width);
        button.Height(height);
        button.Font(HIT_SLTP_FONT_STYLE);
        button.FontSize(HIT_SLTP_FONT_SIZE);
        m_panel.Add(button);
    }

    void CreateLabel(CLabel &label,
                     const string name,
                     const int x,
                     const int y,
                     const int width,
                     const string text)
    {
        if (!label.Create(0, name, 0, x, y, 0, 0))
        {
            Print("SLTP label create failed: ", name, " err=", GetLastError());
            return;
        }
        label.Width(width);
        label.Height(HIT_SLTP_ROW_HEIGHT);
        label.Text(text);
        label.Font(HIT_SLTP_FONT_STYLE);
        label.FontSize(HIT_SLTP_FONT_SIZE);
        label.Color(clrDimGray);
        label.ColorBackground(clrDimGray);
        label.ColorBorder(clrDimGray);
        m_panel.Add(label);
    }

    void CreateEdit(CEdit &edit,
                    const string name,
                    const int x,
                    const int y,
                    const int width)
    {
        if (!edit.Create(0, name, 0, x, y, 0, 0))
        {
            Print("SLTP edit create failed: ", name, " err=", GetLastError());
            return;
        }
        edit.Width(width);
        edit.Height(HIT_SLTP_ROW_HEIGHT);
        edit.Font(HIT_SLTP_FONT_STYLE);
        edit.FontSize(HIT_SLTP_FONT_SIZE);
        edit.Color(clrDimGray);
        edit.ColorBackground(clrWhite);
        edit.ColorBorder(clrDimGray);
        m_panel.Add(edit);
    }

    void RefreshControls()
    {
        RefreshButtons();

        m_edit_breakeven_trigger.Text(DoubleToString(m_settings.breakeven_trigger_pips, 1));
        m_edit_breakeven_buffer.Text(DoubleToString(m_settings.breakeven_buffer_pips, 1));
        m_edit_elapsed_hours.Text(DoubleToString(m_settings.elapsed_breakeven_hours, 1));
        m_edit_elapsed_buffer.Text(DoubleToString(m_settings.elapsed_breakeven_buffer_pips, 1));
        m_edit_active_start.Text(DoubleToString(m_settings.active_breakeven_pips, 1));
        m_edit_active_offset.Text(DoubleToString(m_settings.active_stop_loss_offset_pips, 1));
        m_edit_active_step_trigger.Text(DoubleToString(m_settings.active_step_trigger_pips, 1));
        m_edit_active_step_move.Text(DoubleToString(m_settings.active_step_move_pips, 1));
        m_edit_tp_trigger.Text(DoubleToString(m_settings.tp_progress_trigger_percent, 1));
        m_edit_tp_lock.Text(DoubleToString(m_settings.tp_progress_sl_lock_percent, 1));
    }

    void RefreshButtons()
    {
        ApplyToggleButton(m_button_master, m_settings.manager_enabled, "ON", "OFF");
        ApplyToggleButton(m_button_breakeven, m_settings.use_breakeven, "ON", "OFF");
        ApplyToggleButton(m_button_elapsed_breakeven, m_settings.use_elapsed_breakeven, "ON", "OFF");
        ApplyToggleButton(m_button_active_trailing, m_settings.use_active_trailing, "ON", "OFF");
        ApplyToggleButton(m_button_tp_progress, m_settings.use_tp_progress_stop, "ON", "OFF");
        ApplyToggleButton(m_button_high_volatility, m_settings.use_high_volatility_limit, "ON", "OFF");
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

    bool ReadInputs()
    {
        bool ok = true;

        ok = ReadDoubleValue(m_edit_breakeven_trigger, "BreakEven Trigger", 0.0, 10000.0,
                             m_settings.breakeven_trigger_pips, m_settings.breakeven_trigger_pips) && ok;
        ok = ReadDoubleValue(m_edit_breakeven_buffer, "BreakEven Buffer", 0.0, 10000.0,
                             m_settings.breakeven_buffer_pips, m_settings.breakeven_buffer_pips) && ok;
        ok = ReadDoubleValue(m_edit_elapsed_hours, "Elapsed BE Hours", 0.0, 10000.0,
                             m_settings.elapsed_breakeven_hours, m_settings.elapsed_breakeven_hours) && ok;
        ok = ReadDoubleValue(m_edit_elapsed_buffer, "Elapsed BE Buffer", 0.0, 10000.0,
                             m_settings.elapsed_breakeven_buffer_pips, m_settings.elapsed_breakeven_buffer_pips) && ok;
        ok = ReadDoubleValue(m_edit_active_start, "Active Trail Start", 0.0, 10000.0,
                             m_settings.active_breakeven_pips, m_settings.active_breakeven_pips) && ok;
        ok = ReadDoubleValue(m_edit_active_offset, "Active Trail Offset", 0.0, 10000.0,
                             m_settings.active_stop_loss_offset_pips, m_settings.active_stop_loss_offset_pips) && ok;
        ok = ReadDoubleValue(m_edit_active_step_trigger, "Active Trail Step Trigger", 0.1, 10000.0,
                             m_settings.active_step_trigger_pips, m_settings.active_step_trigger_pips) && ok;
        ok = ReadDoubleValue(m_edit_active_step_move, "Active Trail Step Move", 0.1, 10000.0,
                             m_settings.active_step_move_pips, m_settings.active_step_move_pips) && ok;
        ok = ReadDoubleValue(m_edit_tp_trigger, "TP Progress Trigger", 0.1, 100.0,
                             m_settings.tp_progress_trigger_percent, m_settings.tp_progress_trigger_percent) && ok;
        ok = ReadDoubleValue(m_edit_tp_lock, "TP Progress Lock", 0.0, 100.0,
                             m_settings.tp_progress_sl_lock_percent, m_settings.tp_progress_sl_lock_percent) && ok;

        if (m_settings.use_breakeven && m_settings.use_active_trailing)
        {
            MessageBox("BreakEven and Active Trail cannot both be enabled.", "SLTP panel error", MB_ICONERROR);
            m_settings.use_active_trailing = false;
            RefreshButtons();
            ok = false;
        }

        if (!ok)
            RefreshControls();

        return ok;
    }

    bool ReadDoubleValue(CEdit &edit,
                         const string label,
                         const double min_value,
                         const double max_value,
                         const double default_value,
                         double &target)
    {
        const string text = edit.Text();
        if (!IsNumericText(text))
        {
            ShowValueError(edit, label, min_value, max_value, default_value, target);
            return false;
        }

        const double value = StringToDouble(text);
        if (value < min_value || value > max_value)
        {
            ShowValueError(edit, label, min_value, max_value, default_value, target);
            return false;
        }

        target = value;
        return true;
    }

    void ShowValueError(CEdit &edit,
                        const string label,
                        const double min_value,
                        const double max_value,
                        const double default_value,
                        double &target)
    {
        MessageBox(label + " must be between " + DoubleToString(min_value, 1) +
                   " and " + DoubleToString(max_value, 1) + ".",
                   "SLTP panel error",
                   MB_ICONERROR);
        edit.Text(DoubleToString(default_value, 1));
        target = default_value;
    }

    bool IsNumericText(const string text)
    {
        bool has_digit = false;
        bool has_dot = false;
        bool seen_value_char = false;
        const int length = StringLen(text);

        for (int i = 0; i < length; ++i)
        {
            const ushort ch = StringGetCharacter(text, i);

            if (ch == 32 || ch == 9)
                continue;

            if (ch >= 48 && ch <= 57)
            {
                has_digit = true;
                seen_value_char = true;
                continue;
            }

            if (ch == 46 && !has_dot)
            {
                has_dot = true;
                seen_value_char = true;
                continue;
            }

            if ((ch == 43 || ch == 45) && !seen_value_char)
            {
                seen_value_char = true;
                continue;
            }

            return false;
        }

        return has_digit;
    }
};

#endif
