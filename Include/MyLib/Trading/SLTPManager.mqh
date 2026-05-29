#ifndef SLTP_MANAGER_MQH
#define SLTP_MANAGER_MQH

#include <Trade/Trade.mqh>

/// @brief 同一シンボル・同一マジックナンバーの建玉に対して、SLを段階的に引き上げる管理クラス。
/// @details 建値移動、アクティブトレーリング、TP進捗率ベースのSL固定をまとめて評価し、
///          現在のSLより有利な候補だけを `CTrade::PositionModify` で反映する。
class CSLTPManager
{
private:
    ulong  m_magic;
    string m_symbol;
    ulong  m_deviation_points;
    CTrade m_trade;

    bool   m_use_breakeven;
    double m_breakeven_trigger_pips;
    double m_breakeven_buffer_pips;

    bool   m_use_elapsed_breakeven;
    double m_elapsed_breakeven_hours;
    double m_elapsed_breakeven_buffer_pips;

    bool   m_use_active_trailing;
    double m_active_breakeven_pips;
    double m_active_stop_loss_offset_pips;
    double m_active_step_trigger_pips;
    double m_active_step_move_pips;

    bool   m_use_tp_progress_stop;
    double m_tp_progress_trigger_percent;
    double m_tp_progress_sl_lock_percent;

    bool   m_use_high_volatility_limit;

public:
    /// @brief SL/TP管理クラスの初期状態を構築する。
    /// @details デフォルトでは現在チャートのシンボルを対象にし、すべてのSL移動ロジックを無効化する。
    CSLTPManager()
    {
        m_magic = 0;
        m_symbol = _Symbol;
        m_deviation_points = 10;

        m_use_breakeven = false;
        m_breakeven_trigger_pips = 0.0;
        m_breakeven_buffer_pips = 0.0;

        m_use_elapsed_breakeven = false;
        m_elapsed_breakeven_hours = 0.0;
        m_elapsed_breakeven_buffer_pips = 0.0;

        m_use_active_trailing = false;
        m_active_breakeven_pips = 0.0;
        m_active_stop_loss_offset_pips = 0.0;
        m_active_step_trigger_pips = 0.0;
        m_active_step_move_pips = 0.0;

        m_use_tp_progress_stop = false;
        m_tp_progress_trigger_percent = 0.0;
        m_tp_progress_sl_lock_percent = 0.0;

        m_use_high_volatility_limit = false;
    }

    /// @brief 管理対象ポジションのマジックナンバーを設定する。
    /// @param magic 対象EAに割り当てられたマジックナンバー。
    /// @details `CTrade` にも同じマジックナンバーを渡し、注文変更ログと実行元を揃える。
    void SetMagicNumber(const ulong magic)
    {
        m_magic = magic;
        m_trade.SetExpertMagicNumber(m_magic);
    }

    /// @brief 管理対象のシンボルを設定する。
    /// @param symbol `_Symbol` または任意の取引シンボル名。
    void SetSymbol(const string symbol)
    {
        m_symbol = symbol;
    }

    /// @brief SL変更注文に使用する許容スリッページをポイント単位で設定する。
    /// @param deviation_points `CTrade::SetDeviationInPoints` に渡すポイント数。
    void SetDeviationInPoints(const ulong deviation_points)
    {
        m_deviation_points = deviation_points;
        m_trade.SetDeviationInPoints((int)m_deviation_points);
    }

    /// @brief 建値移動ロジックの有効化とバッファー幅を設定する。
    /// @param use_breakeven true の場合、利益が閾値を超えた時にSLを建値付近へ移動する。
    /// @param breakeven_trigger_pips 建値移動を開始する含み益のpips。
    /// @param breakeven_buffer_pips 建値から利益方向へずらして固定するバッファーpips。
    void SetBreakevenSettings(const bool use_breakeven,
                              const double breakeven_trigger_pips,
                              const double breakeven_buffer_pips)
    {
        m_use_breakeven = use_breakeven;
        m_breakeven_trigger_pips = breakeven_trigger_pips;
        m_breakeven_buffer_pips = breakeven_buffer_pips;
    }

    /// @brief 保有時間ベースの建値移動ロジックを設定する。
    /// @param use_elapsed_breakeven true の場合、保有時間と建値超過を条件にSLを建値付近へ移動する。
    /// @param elapsed_breakeven_hours 建値移動を許可するまでの保有時間。小数指定も可能。
    /// @param elapsed_breakeven_buffer_pips 建値から利益方向へずらして固定するバッファーpips。
    void SetElapsedBreakevenSettings(const bool use_elapsed_breakeven,
                                     const double elapsed_breakeven_hours,
                                     const double elapsed_breakeven_buffer_pips)
    {
        m_use_elapsed_breakeven = use_elapsed_breakeven;
        m_elapsed_breakeven_hours = elapsed_breakeven_hours;
        m_elapsed_breakeven_buffer_pips = elapsed_breakeven_buffer_pips;
    }

    /// @brief アクティブトレーリングロジックの有効化と段階移動幅を設定する。
    /// @param use_active_trailing true の場合、利益進捗に応じてSLを段階的に更新する。
    /// @param active_breakeven_pips トレーリングを開始する含み益のpips。
    /// @param active_stop_loss_offset_pips 開始時点で建値から固定する初期pips。
    /// @param active_step_trigger_pips SLを次段階へ進めるために必要な追加利益pips。
    /// @param active_step_move_pips 1段階ごとにSLを利益方向へ動かすpips。
    void SetActiveTrailingSettings(const bool use_active_trailing,
                                   const double active_breakeven_pips,
                                   const double active_stop_loss_offset_pips,
                                   const double active_step_trigger_pips,
                                   const double active_step_move_pips)
    {
        m_use_active_trailing = use_active_trailing;
        m_active_breakeven_pips = active_breakeven_pips;
        m_active_stop_loss_offset_pips = active_stop_loss_offset_pips;
        m_active_step_trigger_pips = active_step_trigger_pips;
        m_active_step_move_pips = active_step_move_pips;
    }

    /// @brief TP到達進捗率を基準にSLを固定するロジックを設定する。
    /// @param use_tp_progress_stop true の場合、現在価格がTP距離の一定割合へ到達した時にSLを固定する。
    /// @param tp_progress_trigger_percent SL固定を開始するTP進捗率。範囲は `(0, 100]`。
    /// @param tp_progress_sl_lock_percent TP距離のうちSLで固定する割合。範囲は `[0, 100]`。
    void SetTpProgressStopSettings(const bool use_tp_progress_stop,
                                   const double tp_progress_trigger_percent,
                                   const double tp_progress_sl_lock_percent)
    {
        m_use_tp_progress_stop = use_tp_progress_stop;
        m_tp_progress_trigger_percent = tp_progress_trigger_percent;
        m_tp_progress_sl_lock_percent = tp_progress_sl_lock_percent;
    }

    /// @brief 高ボラティリティ時のSL引き締めロジックを有効化/無効化する。
    /// @param use_high_volatility_limit true の場合、HighVolatilityLimit() 呼び出し時に急変幅ベースでSLを更新する。
    void SetHighVolatilityLimitSettings(const bool use_high_volatility_limit)
    {
        m_use_high_volatility_limit = use_high_volatility_limit;
    }

    /// @brief 設定値とシンボル状態が実行可能か検証する。
    /// @return すべての設定が有効で、シンボル選択とpips換算が可能な場合は true。
    /// @details 建値移動とアクティブトレーリングの同時有効化など、矛盾する設定を事前に弾く。
    bool ValidateSettings()
    {
        if (m_symbol == "")
        {
            Print("SLTPManager settings error: symbol is empty.");
            return false;
        }

        if (!SymbolSelect(m_symbol, true))
        {
            Print("SLTPManager settings error: failed to select symbol=", m_symbol,
                  " err=", GetLastError());
            return false;
        }

        if (m_use_breakeven && m_use_active_trailing)
        {
            Print("SLTPManager settings error: use_breakeven and use_active_trailing cannot both be true.");
            return false;
        }

        if (m_use_breakeven)
        {
            if (m_breakeven_trigger_pips < 0.0 || m_breakeven_buffer_pips < 0.0)
            {
                Print("SLTPManager settings error: breakeven trigger and buffer pips must be non-negative.");
                return false;
            }
        }

        if (m_use_elapsed_breakeven)
        {
            if (m_elapsed_breakeven_hours < 0.0 || m_elapsed_breakeven_buffer_pips < 0.0)
            {
                Print("SLTPManager settings error: elapsed breakeven hours and buffer pips must be non-negative.");
                return false;
            }
        }

        if (m_use_active_trailing)
        {
            if (m_active_breakeven_pips < 0.0 ||
                m_active_stop_loss_offset_pips < 0.0 ||
                m_active_step_trigger_pips <= 0.0 ||
                m_active_step_move_pips <= 0.0)
            {
                Print("SLTPManager settings error: active trailing requires non-negative breakeven/offset and positive step values.");
                return false;
            }
        }

        if (m_use_tp_progress_stop)
        {
            if (m_tp_progress_trigger_percent <= 0.0 ||
                m_tp_progress_trigger_percent > 100.0 ||
                m_tp_progress_sl_lock_percent < 0.0 ||
                m_tp_progress_sl_lock_percent > 100.0)
            {
                Print("SLTPManager settings error: TP progress percentages must be trigger=(0,100], lock=[0,100].");
                return false;
            }
        }

        if (PipSize() <= 0.0)
            return false;

        return true;
    }

    /// @brief 現在保有中の対象ポジションを走査し、必要に応じてSLを更新する。
    /// @details 対象は `m_magic` と `m_symbol` が一致するポジションのみ。複数のSL候補がある場合、
    ///          BUYでは最も高いSL、SELLでは最も低いSLを採用し、既存SLより不利な変更は行わない。
    void ManagePositions()
    {
        const double pip_size = PipSize();
        if (pip_size <= 0.0)
            return;

        MqlTick tick;
        if (!SymbolInfoTick(m_symbol, tick))
        {
            Print("SLTPManager tick read failed: symbol=", m_symbol, " err=", GetLastError());
            return;
        }

        const int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
        const datetime current_time = tick.time;
        const int pos_total = PositionsTotal();

        for (int i = pos_total - 1; i >= 0; --i)
        {
            const ulong ticket = PositionGetTicket(i);
            if (!PositionSelectByTicket(ticket))
                continue;
            if (!IsTargetPosition())
                continue;

            const ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            if (type != POSITION_TYPE_BUY && type != POSITION_TYPE_SELL)
                continue;

            const double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
            const double current_sl = PositionGetDouble(POSITION_SL);
            const double current_tp = PositionGetDouble(POSITION_TP);
            const double market_price = (type == POSITION_TYPE_BUY) ? tick.bid : tick.ask;
            const double profit_pips = GetProfitPips(type, open_price, market_price, pip_size);
            const datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);

            bool has_candidate = false;
            double candidate_sl = 0.0;
            double sl_value = 0.0;

            if (CalcBreakevenSL(type, open_price, profit_pips, pip_size, digits, sl_value))
                UpdateBestCandidate(type, sl_value, has_candidate, candidate_sl);

            if (CalcElapsedBreakevenSL(type, open_price, profit_pips, open_time, current_time, pip_size, digits, sl_value))
                UpdateBestCandidate(type, sl_value, has_candidate, candidate_sl);

            if (CalcActiveTrailingSL(type, open_price, profit_pips, pip_size, digits, sl_value))
                UpdateBestCandidate(type, sl_value, has_candidate, candidate_sl);

            if (CalcTpProgressSL(type, open_price, current_tp, market_price, digits, sl_value))
                UpdateBestCandidate(type, sl_value, has_candidate, candidate_sl);

            if (!has_candidate)
                continue;

            candidate_sl = NormalizeDouble(candidate_sl, digits);

            if (!IsBetterStopLoss(type, candidate_sl, current_sl))
                continue;

            if (!IsStopDistanceAllowed(type, market_price, candidate_sl))
                continue;

            ModifyStopLoss(ticket, candidate_sl, current_tp);
        }
    }

    /// @brief 短時間で大きな価格変動が発生した場合にSLを引き締める。
    /// @details M1/M3/M5/M10/M15 の始値から現在Bidまでの変動幅を見て、
    ///          しきい値を超えた場合だけ利益方向へSL候補を作る。ManagePositions() とは独立して呼び出す。
    void HighVolatilityLimit()
    {
        if (!m_use_high_volatility_limit)
            return;

        const double pip_size = PipSize();
        if (pip_size <= 0.0)
            return;

        MqlTick tick;
        if (!SymbolInfoTick(m_symbol, tick))
        {
            Print("SLTPManager tick read failed: symbol=", m_symbol, " err=", GetLastError());
            return;
        }

        const int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
        const double open_m1 = iOpen(m_symbol, PERIOD_M1, 0);
        const double open_m3 = iOpen(m_symbol, PERIOD_M3, 0);
        const double open_m5 = iOpen(m_symbol, PERIOD_M5, 0);
        const double open_m10 = iOpen(m_symbol, PERIOD_M10, 0);
        const double open_m15 = iOpen(m_symbol, PERIOD_M15, 0);
        const int pos_total = PositionsTotal();

        for (int i = pos_total - 1; i >= 0; --i)
        {
            const ulong ticket = PositionGetTicket(i);
            if (!PositionSelectByTicket(ticket))
                continue;
            if (!IsTargetPosition())
                continue;

            const ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            if (type != POSITION_TYPE_BUY && type != POSITION_TYPE_SELL)
                continue;

            double candidate_sl = 0.0;
            const double evaluation_price = (type == POSITION_TYPE_BUY) ? tick.bid : tick.ask;
            if (!CalcHighVolatilitySL(type,
                                      evaluation_price,
                                      open_m1,
                                      open_m3,
                                      open_m5,
                                      open_m10,
                                      open_m15,
                                      pip_size,
                                      digits,
                                      candidate_sl))
            {
                continue;
            }

            const double current_sl = PositionGetDouble(POSITION_SL);
            const double current_tp = PositionGetDouble(POSITION_TP);
            const double market_price = (type == POSITION_TYPE_BUY) ? tick.bid : tick.ask;

            if (!IsBetterStopLoss(type, candidate_sl, current_sl))
                continue;

            if (!IsStopDistanceAllowed(type, market_price, candidate_sl))
                continue;

            ModifyStopLoss(ticket, candidate_sl, current_tp);
        }
    }

private:
    /// @brief 現在選択中のポジションが管理対象か判定する。
    /// @return マジックナンバーとシンボルが一致する場合は true。
    bool IsTargetPosition()
    {
        if ((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
            return false;
        if (PositionGetString(POSITION_SYMBOL) != m_symbol)
            return false;

        return true;
    }

    /// @brief 対象シンボルの1 pip相当の価格幅を取得する。
    /// @return 1 pip の価格幅。取得できない場合は 0.0。
    /// @details GOLD/XAUUSD は 0.1、2/3桁は0.01、4/5桁は0.0001を1 pipとして扱う。
    double PipSize()
    {
        string normalized_symbol = m_symbol;
        StringToUpper(normalized_symbol);
        if (StringFind(normalized_symbol, "XAUUSD") >= 0 ||
            StringFind(normalized_symbol, "GOLD") >= 0)
            return 0.1;

        const int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);

        switch (digits)
        {
        case 2:
        case 3:
            return 0.01;
        case 4:
        case 5:
            return 0.0001;
        }

        Print("SLTPManager pip conversion error: unsupported symbol digits. symbol=", m_symbol,
              " digits=", digits);
        return 0.0;
    }

    /// @brief 現在価格から建値に対する含み益をpipsで計算する。
    /// @param type ポジション種別。BUY/SELLで計算方向を切り替える。
    /// @param open_price 建値。
    /// @param market_price BUYはBid、SELLはAskを想定した現在価格。
    /// @param pip_size `PipSize()` で取得した1 pipの価格幅。
    /// @return 利益方向なら正、損失方向なら負のpips。
    double GetProfitPips(const ENUM_POSITION_TYPE type,
                         const double open_price,
                         const double market_price,
                         const double pip_size)
    {
        if (pip_size <= 0.0)
            return 0.0;

        if (type == POSITION_TYPE_BUY)
            return (market_price - open_price) / pip_size;

        return (open_price - market_price) / pip_size;
    }

    /// @brief 建値移動ロジックに基づくSL候補を計算する。
    /// @param type ポジション種別。
    /// @param open_price 建値。
    /// @param profit_pips 現在の含み益pips。
    /// @param pip_size 1 pipの価格幅。
    /// @param digits 対象シンボルの小数桁数。
    /// @param sl_value 計算に成功したSL候補の出力先。
    /// @return 建値移動条件を満たし、SL候補を出力した場合は true。
    /// @details BUYでは建値 + バッファー、SELLでは建値 - バッファーへSLを置き、
    ///          スプレッドや手数料分を考慮した利益保護ラインとして扱う。
    bool CalcBreakevenSL(const ENUM_POSITION_TYPE type,
                         const double open_price,
                         const double profit_pips,
                         const double pip_size,
                         const int digits,
                         double &sl_value)
    {
        if (!m_use_breakeven)
            return false;
        if (profit_pips < m_breakeven_trigger_pips)
            return false;

        if (type == POSITION_TYPE_BUY)
            sl_value = open_price + m_breakeven_buffer_pips * pip_size;
        else
            sl_value = open_price - m_breakeven_buffer_pips * pip_size;

        sl_value = NormalizeDouble(sl_value, digits);
        return true;
    }

    /// @brief 保有時間ベースの建値移動ロジックに基づくSL候補を計算する。
    /// @param type ポジション種別。
    /// @param open_price 建値。
    /// @param profit_pips 現在の含み益pips。現在レートが建値を超えているかの判定に使う。
    /// @param open_time ポジションの約定時刻。
    /// @param current_time 評価時点のサーバー時刻。
    /// @param pip_size 1 pipの価格幅。
    /// @param digits 対象シンボルの小数桁数。
    /// @param sl_value 計算に成功したSL候補の出力先。
    /// @return 保有時間と建値超過条件を満たし、SL候補を出力した場合は true。
    /// @details 通常ブレークイーブンとは独立した候補として評価し、長時間保有ポジションの損失化を防ぐ。
    bool CalcElapsedBreakevenSL(const ENUM_POSITION_TYPE type,
                                const double open_price,
                                const double profit_pips,
                                const datetime open_time,
                                const datetime current_time,
                                const double pip_size,
                                const int digits,
                                double &sl_value)
    {
        if (!m_use_elapsed_breakeven)
            return false;
        if (open_time <= 0 || current_time <= open_time)
            return false;
        if (profit_pips <= 0.0)
            return false;

        const double required_seconds = m_elapsed_breakeven_hours * 3600.0;
        const double held_seconds = (double)(current_time - open_time);
        if (held_seconds < required_seconds)
            return false;

        if (type == POSITION_TYPE_BUY)
            sl_value = open_price + m_elapsed_breakeven_buffer_pips * pip_size;
        else
            sl_value = open_price - m_elapsed_breakeven_buffer_pips * pip_size;

        sl_value = NormalizeDouble(sl_value, digits);
        return true;
    }

    /// @brief アクティブトレーリングロジックに基づくSL候補を計算する。
    /// @param type ポジション種別。
    /// @param open_price 建値。
    /// @param profit_pips 現在の含み益pips。
    /// @param pip_size 1 pipの価格幅。
    /// @param digits 対象シンボルの小数桁数。
    /// @param sl_value 計算に成功したSL候補の出力先。
    /// @return トレーリング開始条件を満たし、SL候補を出力した場合は true。
    /// @details 開始利益からの超過分をステップ数へ変換し、固定済み利益幅を段階的に増やす。
    bool CalcActiveTrailingSL(const ENUM_POSITION_TYPE type,
                              const double open_price,
                              const double profit_pips,
                              const double pip_size,
                              const int digits,
                              double &sl_value)
    {
        if (!m_use_active_trailing)
            return false;
        if (profit_pips < m_active_breakeven_pips)
            return false;

        int trail_steps = (int)MathFloor((profit_pips - m_active_breakeven_pips) / m_active_step_trigger_pips);
        if (trail_steps < 0)
            trail_steps = 0;

        const double locked_pips = m_active_stop_loss_offset_pips + trail_steps * m_active_step_move_pips;

        if (type == POSITION_TYPE_BUY)
            sl_value = open_price + locked_pips * pip_size;
        else
            sl_value = open_price - locked_pips * pip_size;

        sl_value = NormalizeDouble(sl_value, digits);
        return true;
    }

    /// @brief TP進捗率ベースのSL候補を計算する。
    /// @param type ポジション種別。
    /// @param open_price 建値。
    /// @param current_tp 現在設定されているTP価格。未設定の場合は 0.0。
    /// @param market_price BUYはBid、SELLはAskを想定した現在価格。
    /// @param digits 対象シンボルの小数桁数。
    /// @param sl_value 計算に成功したSL候補の出力先。
    /// @return TP方向と進捗率が有効で、SL候補を出力した場合は true。
    bool CalcTpProgressSL(const ENUM_POSITION_TYPE type,
                          const double open_price,
                          const double current_tp,
                          const double market_price,
                          const int digits,
                          double &sl_value)
    {
        if (!m_use_tp_progress_stop)
            return false;
        if (current_tp == 0.0)
            return false;

        double tp_distance = 0.0;
        double progressed_distance = 0.0;

        if (type == POSITION_TYPE_BUY)
        {
            if (current_tp <= open_price)
                return false;

            tp_distance = current_tp - open_price;
            progressed_distance = market_price - open_price;
            sl_value = open_price + tp_distance * (m_tp_progress_sl_lock_percent / 100.0);
        }
        else
        {
            if (current_tp >= open_price)
                return false;

            tp_distance = open_price - current_tp;
            progressed_distance = open_price - market_price;
            sl_value = open_price - tp_distance * (m_tp_progress_sl_lock_percent / 100.0);
        }

        if (tp_distance <= 0.0)
            return false;

        const double progress_percent = (progressed_distance / tp_distance) * 100.0;
        if (progress_percent < m_tp_progress_trigger_percent)
            return false;

        sl_value = NormalizeDouble(sl_value, digits);
        return true;
    }

    /// @brief 高ボラティリティ判定に基づくSL候補を計算する。
    /// @return いずれかの時間足でしきい値を超え、SL候補を出力した場合は true。
    bool CalcHighVolatilitySL(const ENUM_POSITION_TYPE type,
                              const double current_price,
                              const double open_m1,
                              const double open_m3,
                              const double open_m5,
                              const double open_m10,
                              const double open_m15,
                              const double pip_size,
                              const int digits,
                              double &sl_value)
    {
        bool has_candidate = false;
        double candidate_sl = 0.0;
        const double rate_ratio = 0.9;

        EvaluateHighVolatilityOpen(type, current_price, open_m1, 100.0, rate_ratio, pip_size, digits, has_candidate, candidate_sl);
        EvaluateHighVolatilityOpen(type, current_price, open_m3, 150.0, rate_ratio, pip_size, digits, has_candidate, candidate_sl);
        EvaluateHighVolatilityOpen(type, current_price, open_m5, 200.0, rate_ratio, pip_size, digits, has_candidate, candidate_sl);
        EvaluateHighVolatilityOpen(type, current_price, open_m10, 300.0, rate_ratio, pip_size, digits, has_candidate, candidate_sl);
        EvaluateHighVolatilityOpen(type, current_price, open_m15, 400.0, rate_ratio, pip_size, digits, has_candidate, candidate_sl);

        if (!has_candidate)
            return false;

        sl_value = NormalizeDouble(candidate_sl, digits);
        return true;
    }

    /// @brief 1本の時間足始値から急変幅を評価し、有効なSL候補なら最良候補へ反映する。
    void EvaluateHighVolatilityOpen(const ENUM_POSITION_TYPE type,
                                    const double current_price,
                                    const double open_price,
                                    const double limit_pips,
                                    const double rate_ratio,
                                    const double pip_size,
                                    const int digits,
                                    bool &has_candidate,
                                    double &candidate_sl)
    {
        if (open_price <= 0.0 || pip_size <= 0.0)
            return;

        double movement_pips = 0.0;
        double sl_value = 0.0;

        if (type == POSITION_TYPE_BUY)
        {
            movement_pips = (current_price - open_price) / pip_size;
            sl_value = open_price + limit_pips * rate_ratio * pip_size;
        }
        else if (type == POSITION_TYPE_SELL)
        {
            movement_pips = (open_price - current_price) / pip_size;
            sl_value = open_price - limit_pips * rate_ratio * pip_size;
        }
        else
        {
            return;
        }

        if (movement_pips < limit_pips)
            return;

        sl_value = NormalizeDouble(sl_value, digits);
        UpdateBestCandidate(type, sl_value, has_candidate, candidate_sl);
    }

    /// @brief 複数ロジックから得たSL候補のうち、最も有利な値を保持する。
    /// @param type ポジション種別。BUYは高いSL、SELLは低いSLを優先する。
    /// @param sl_value 新しく評価するSL候補。
    /// @param has_candidate 既に候補が存在するかを示す入出力フラグ。
    /// @param candidate_sl 現在の最良SL候補の入出力値。
    void UpdateBestCandidate(const ENUM_POSITION_TYPE type,
                             const double sl_value,
                             bool &has_candidate,
                             double &candidate_sl)
    {
        if (!has_candidate)
        {
            candidate_sl = sl_value;
            has_candidate = true;
            return;
        }

        if (type == POSITION_TYPE_BUY)
            candidate_sl = MathMax(candidate_sl, sl_value);
        else
            candidate_sl = MathMin(candidate_sl, sl_value);
    }

    /// @brief 新しいSLが既存SLより利益保護方向へ改善しているか判定する。
    /// @param type ポジション種別。
    /// @param new_sl 新しく設定したいSL価格。
    /// @param current_sl 現在のSL価格。未設定の場合は 0.0。
    /// @return 未設定または利益保護方向へ十分に改善している場合は true。
    /// @details 小数誤差による微小な再変更を避けるため、pointの10%を許容差として使う。
    bool IsBetterStopLoss(const ENUM_POSITION_TYPE type,
                          const double new_sl,
                          const double current_sl)
    {
        const double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        const double tolerance = point * 0.1;

        if (current_sl == 0.0)
            return true;

        if (type == POSITION_TYPE_BUY)
            return (new_sl > current_sl + tolerance);

        return (new_sl < current_sl - tolerance);
    }

    /// @brief ブローカーのストップレベルとフリーズレベルに対してSL変更が可能か判定する。
    /// @param type ポジション種別。
    /// @param market_price BUYはBid、SELLはAskを想定した現在価格。
    /// @param new_sl 新しく設定したいSL価格。
    /// @return 現在価格から必要距離を確保できている場合は true。
    bool IsStopDistanceAllowed(const ENUM_POSITION_TYPE type,
                               const double market_price,
                               const double new_sl)
    {
        const double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        const int stops_level = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
        const int freeze_level = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_FREEZE_LEVEL);
        const double stop_gap = stops_level * point;
        const double freeze_gap = freeze_level * point;

        if (point <= 0.0)
            return false;

        if (type == POSITION_TYPE_BUY)
        {
            if (new_sl > market_price - stop_gap)
                return false;
            if (freeze_level > 0 && new_sl > market_price - freeze_gap)
                return false;
            return true;
        }

        if (new_sl < market_price + stop_gap)
            return false;
        if (freeze_level > 0 && new_sl < market_price + freeze_gap)
            return false;

        return true;
    }

    /// @brief 対象チケットのSLを更新し、TPは現在値を維持する。
    /// @param ticket 変更対象ポジションのチケット番号。
    /// @param new_sl 新しいSL価格。
    /// @param current_tp 変更前のTP価格。
    /// @return `CTrade::PositionModify` が成功した場合は true。
    /// @details 失敗時はretcode、GetLastError、設定しようとしたSLをログ出力する。
    bool ModifyStopLoss(const ulong ticket,
                        const double new_sl,
                        const double current_tp)
    {
        ResetLastError();
        if (!m_trade.PositionModify(ticket, new_sl, current_tp))
        {
            Print("SLTPManager SL modify failed: ticket=", ticket,
                  " symbol=", m_symbol,
                  " magic=", m_magic,
                  " retcode=", m_trade.ResultRetcode(),
                  " err=", GetLastError(),
                  " new_sl=", DoubleToString(new_sl, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS)));
            return false;
        }

        return true;
    }
};

#endif
