#ifndef TRADING_PANEL_TRADING_MANAGERS_MQH
#define TRADING_PANEL_TRADING_MANAGERS_MQH

#include <Trade/Trade.mqh>
#include <MyLib/Common/TradingPanelSymbolUtils.mqh>

#define TRADING_PANEL_POSITION_TYPE_ALL ((ENUM_POSITION_TYPE)-1)

/**
 * TradingPanel のポジションに対するストップロス更新を管理します。
 *
 * ブローカーの最小距離チェック、固定SL設定、建値/トレーリングSL、
 * 高ボラティリティ時の保護SL更新を担当します。
 */
class CTradingPanelStopManager
{
private:
    string m_symbol;
    ulong m_magic;
    CTrade m_trade;

public:
    /**
     * 対象シンボル、マジックナンバー、CTrade の実行設定を初期化します。
     *
     * @param symbol 対象の取引シンボル。
     * @param magic パネルのポジションだけを抽出・変更するためのマジックナンバー。
     * @param allowed_slippage 許容スリッページの最大値（ポイント）。
     */
    void Init(const string symbol, const ulong magic, const ulong allowed_slippage)
    {
        m_symbol = symbol;
        m_magic = magic;
        m_trade.SetExpertMagicNumber(m_magic);
        m_trade.SetDeviationInPoints((int)allowed_slippage);
    }

    /**
     * 候補となるストップロス価格がブローカー制限を満たすか検証します。
     *
     * @param type ポジション方向。
     * @param price_now 売買方向に応じた現在の市場価格。
     * @param new_sl 候補となるストップロス価格。
     * @return ストップレベルとフリーズレベルの両方から十分に離れている場合 true。
     */
    bool CheckStopDistance(const ENUM_POSITION_TYPE type,
                           const double price_now,
                           const double new_sl)
    {
        const double point_value = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        const int stop_pts = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
        const int freeze_pts = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_FREEZE_LEVEL);
        const double stop_dist = stop_pts * point_value;
        const double freeze_dist = freeze_pts * point_value;

        if (type == POSITION_TYPE_BUY)
        {
            return (new_sl <= price_now - stop_dist) &&
                   (freeze_pts == 0 || new_sl <= price_now - freeze_dist);
        }

        return (new_sl >= price_now + stop_dist) &&
               (freeze_pts == 0 || new_sl >= price_now + freeze_dist);
    }

    /**
     * 指定チケットのTPを維持したままストップロスを変更します。
     *
     * @param ticket 変更対象のポジションチケット。
     * @param new_sl 新しいストップロス価格。
     * @param tp_current 維持する現在のテイクプロフィット価格。
     * @return ブローカーが変更を受け付けた場合 true。
     */
    bool ModifyPositionStop(const ulong ticket,
                            const double new_sl,
                            const double tp_current)
    {
        ResetLastError();
        if (!m_trade.PositionModify(ticket, new_sl, tp_current))
        {
            Print("SL modify failed: ticket=", ticket,
                  " ret=", m_trade.ResultRetcode(),
                  " err=", GetLastError(),
                  " new_sl=", DoubleToString(new_sl, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS)));
            return false;
        }
        return true;
    }

    /**
     * 管理対象ポジションに建値移動と段階式トレーリングSLを適用します。
     *
     * @param breakeven_enabled トレーリング開始前の建値ロックを有効にします。
     * @param active_breakeven_pips 建値移動を開始する利益幅（pips）。
     * @param active_stop_loss_offset_pips 確保する利益として建値からずらす幅（pips）。
     * @param active_step_trigger_pips トレーリングを1段進めるために必要な利益間隔（pips）。
     * @param active_step_move_pips 1段ごとにSLを移動する幅（pips）。
     */
    void ManageStops(const bool breakeven_enabled,
                     const double active_breakeven_pips,
                     const double active_stop_loss_offset_pips,
                     const double active_step_trigger_pips,
                     const double active_step_move_pips)
    {
        const double pt = TradingPanelAdjustPoint(m_symbol);
        const int dg = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);

        if (pt <= 0.0)
            return;

        const int pos_total = PositionsTotal();
        const double be_trigger_pips = MathMax(active_breakeven_pips, 0.0);
        const double step_trigger = MathMax(active_step_trigger_pips, 0.0);
        const double step_move = MathMax(active_step_move_pips, 0.0);

        if (pos_total == 0 || step_trigger <= 0.0 || step_move <= 0.0)
            return;

        for (int idx = pos_total - 1; idx >= 0; --idx)
        {
            const ulong ticket = PositionGetTicket(idx);
            if (!PositionSelectByTicket(ticket))
                continue;
            if ((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
                continue;
            if (PositionGetString(POSITION_SYMBOL) != m_symbol)
                continue;

            const ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            const double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
            double sl_current = PositionGetDouble(POSITION_SL);
            const double tp_current = PositionGetDouble(POSITION_TP);
            const double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
            const double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);

            if (type == POSITION_TYPE_BUY)
            {
                const double profit_pips = (bid - open_price) / pt;
                const double be_sl = NormalizeDouble(open_price + active_stop_loss_offset_pips * pt, dg);

                if (breakeven_enabled)
                {
                    if (profit_pips < be_trigger_pips)
                        continue;

                    if ((sl_current == 0.0 || sl_current < be_sl) &&
                        CheckStopDistance(type, bid, be_sl) &&
                        ModifyPositionStop(ticket, be_sl, tp_current))
                    {
                        sl_current = be_sl;
                    }
                }
                else if (profit_pips < step_trigger)
                {
                    continue;
                }

                const double trailing_base_pips = breakeven_enabled ? be_trigger_pips : 0.0;
                double locked_pips = breakeven_enabled ? active_stop_loss_offset_pips : 0.0;
                int trail_steps = (int)MathFloor((profit_pips - trailing_base_pips) / step_trigger);
                if (trail_steps < 0)
                    trail_steps = 0;
                locked_pips += trail_steps * step_move;

                const double target_sl = NormalizeDouble(open_price + locked_pips * pt, dg);
                if ((sl_current == 0.0 || target_sl > sl_current) &&
                    CheckStopDistance(type, bid, target_sl) &&
                    ModifyPositionStop(ticket, target_sl, tp_current))
                {
                    sl_current = target_sl;
                }
            }
            else if (type == POSITION_TYPE_SELL)
            {
                const double profit_pips = (open_price - ask) / pt;
                const double be_sl = NormalizeDouble(open_price - active_stop_loss_offset_pips * pt, dg);

                if (breakeven_enabled)
                {
                    if (profit_pips < be_trigger_pips)
                        continue;

                    if ((sl_current == 0.0 || sl_current > be_sl) &&
                        CheckStopDistance(type, ask, be_sl) &&
                        ModifyPositionStop(ticket, be_sl, tp_current))
                    {
                        sl_current = be_sl;
                    }
                }
                else if (profit_pips < step_trigger)
                {
                    continue;
                }

                const double trailing_base_pips = breakeven_enabled ? be_trigger_pips : 0.0;
                double locked_pips = breakeven_enabled ? active_stop_loss_offset_pips : 0.0;
                int trail_steps = (int)MathFloor((profit_pips - trailing_base_pips) / step_trigger);
                if (trail_steps < 0)
                    trail_steps = 0;
                locked_pips += trail_steps * step_move;

                const double target_sl = NormalizeDouble(open_price - locked_pips * pt, dg);
                if ((sl_current == 0.0 || target_sl < sl_current) &&
                    CheckStopDistance(type, ask, target_sl) &&
                    ModifyPositionStop(ticket, target_sl, tp_current))
                {
                    sl_current = target_sl;
                }
            }
        }
    }

    /**
     * 短時間で大きな価格変動が発生した場合にSLを引き締めます。
     *
     * 現在価格を M1/M3/M5/M10/M15 の始値と比較し、ブローカーの距離制限を
     * 満たす場合に検出した変動幅の一部を利益として固定します。
     */
    void HighVolatilityLimit()
    {
        const double pt = TradingPanelAdjustPoint(m_symbol);
        const int dg = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
        if (pt <= 0.0)
            return;

        const int pos_total = PositionsTotal();
        if (pos_total == 0)
            return;

        MqlTick tick;
        if (!SymbolInfoTick(m_symbol, tick))
            return;
        const double bid = tick.bid;
        const double ask = tick.ask;

        const double rate_ratio = 0.9;
        const double limit_m1 = 100.0;
        const double limit_m3 = 150.0;
        const double limit_m5 = 200.0;
        const double limit_m10 = 300.0;
        const double limit_m15 = 400.0;

        const double open_m1 = iOpen(m_symbol, PERIOD_M1, 0);
        const double open_m3 = iOpen(m_symbol, PERIOD_M3, 0);
        const double open_m5 = iOpen(m_symbol, PERIOD_M5, 0);
        const double open_m10 = iOpen(m_symbol, PERIOD_M10, 0);
        const double open_m15 = iOpen(m_symbol, PERIOD_M15, 0);

        for (int idx = pos_total - 1; idx >= 0; --idx)
        {
            const ulong ticket = PositionGetTicket(idx);
            if (!PositionSelectByTicket(ticket))
                continue;
            if ((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
                continue;
            if (PositionGetString(POSITION_SYMBOL) != m_symbol)
                continue;

            const ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            const double sl_current = PositionGetDouble(POSITION_SL);
            const double tp_current = PositionGetDouble(POSITION_TP);
            double target_sl = sl_current;
            bool has_candidate = false;

            if (type == POSITION_TYPE_BUY)
            {
                const double diff_m1 = (bid - open_m1) / pt;
                const double diff_m3 = (bid - open_m3) / pt;
                const double diff_m5 = (bid - open_m5) / pt;
                const double diff_m10 = (bid - open_m10) / pt;
                const double diff_m15 = (bid - open_m15) / pt;

                if (diff_m1 >= limit_m1)
                    UpdateBuyCandidate(open_m1, limit_m1, rate_ratio, pt, dg, target_sl, has_candidate);
                if (diff_m3 >= limit_m3)
                    UpdateBuyCandidate(open_m3, limit_m3, rate_ratio, pt, dg, target_sl, has_candidate);
                if (diff_m5 >= limit_m5)
                    UpdateBuyCandidate(open_m5, limit_m5, rate_ratio, pt, dg, target_sl, has_candidate);
                if (diff_m10 >= limit_m10)
                    UpdateBuyCandidate(open_m10, limit_m10, rate_ratio, pt, dg, target_sl, has_candidate);
                if (diff_m15 >= limit_m15)
                    UpdateBuyCandidate(open_m15, limit_m15, rate_ratio, pt, dg, target_sl, has_candidate);

                if (has_candidate && (sl_current == 0.0 || target_sl > sl_current) &&
                    CheckStopDistance(type, bid, target_sl))
                {
                    ModifyPositionStop(ticket, target_sl, tp_current);
                }
            }
            else if (type == POSITION_TYPE_SELL)
            {
                const double diff_m1 = (open_m1 - bid) / pt;
                const double diff_m3 = (open_m3 - bid) / pt;
                const double diff_m5 = (open_m5 - bid) / pt;
                const double diff_m10 = (open_m10 - bid) / pt;
                const double diff_m15 = (open_m15 - bid) / pt;

                if (diff_m1 >= limit_m1)
                    UpdateSellCandidate(open_m1, limit_m1, rate_ratio, pt, dg, target_sl, has_candidate);
                if (diff_m3 >= limit_m3)
                    UpdateSellCandidate(open_m3, limit_m3, rate_ratio, pt, dg, target_sl, has_candidate);
                if (diff_m5 >= limit_m5)
                    UpdateSellCandidate(open_m5, limit_m5, rate_ratio, pt, dg, target_sl, has_candidate);
                if (diff_m10 >= limit_m10)
                    UpdateSellCandidate(open_m10, limit_m10, rate_ratio, pt, dg, target_sl, has_candidate);
                if (diff_m15 >= limit_m15)
                    UpdateSellCandidate(open_m15, limit_m15, rate_ratio, pt, dg, target_sl, has_candidate);

                if (has_candidate && (sl_current == 0.0 || target_sl < sl_current) &&
                    CheckStopDistance(type, ask, target_sl))
                {
                    ModifyPositionStop(ticket, target_sl, tp_current);
                }
            }
        }
    }

    /**
     * 指定されたポジションチケット群に固定距離のストップロスを適用します。
     *
     * @param tickets 呼び出し元で収集済みのポジションチケット配列。
     * @param side 指定チケット群に共通する売買方向。
     * @param pips_from_open 各ポジションの建値からSLまでの距離（pips）。
     */
    void ApplyFixedSL(ulong &tickets[],
                      const ENUM_POSITION_TYPE side,
                      const double pips_from_open)
    {
        if (ArraySize(tickets) == 0)
            return;

        const double pip_size = TradingPanelAdjustPoint(m_symbol);
        const double point_size = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        const int dg = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
        const int stop_lvl = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
        const int freeze = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_FREEZE_LEVEL);
        const double cur_bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        const double cur_ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);

        for (int i = 0; i < ArraySize(tickets); ++i)
        {
            const ulong ticket = tickets[i];
            if (!PositionSelectByTicket(ticket))
                continue;

            const double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
            const double tp_current = PositionGetDouble(POSITION_TP);
            const double new_sl = (side == POSITION_TYPE_BUY)
                                      ? NormalizeDouble(open_price - pips_from_open * pip_size, dg)
                                      : NormalizeDouble(open_price + pips_from_open * pip_size, dg);
            const double gap = (side == POSITION_TYPE_BUY) ? cur_bid - new_sl : new_sl - cur_ask;
            if (gap < (stop_lvl + freeze) * point_size)
                continue;

            ModifyPositionStop(ticket, new_sl, tp_current);
        }
    }

private:
    /**
     * 買いポジション用の高ボラティリティSL候補を更新します。
     *
     * @param open_price 判定基準となるローソク足の始値。
     * @param limit 変動判定のしきい値（pips）。
     * @param rate_ratio しきい値のうち利益固定に使う割合。
     * @param pt シンボルに合わせて調整済みのpipsサイズ。
     * @param digits 価格正規化に使うシンボル桁数。
     * @param target_sl 現在の最良SL候補。参照渡しで更新されます。
     * @param has_candidate 候補が存在する場合 true に更新されます。
     */
    void UpdateBuyCandidate(const double open_price,
                            const double limit,
                            const double rate_ratio,
                            const double pt,
                            const int digits,
                            double &target_sl,
                            bool &has_candidate)
    {
        const double sl_new = NormalizeDouble(open_price + limit * rate_ratio * pt, digits);
        if (!has_candidate || sl_new > target_sl)
        {
            target_sl = sl_new;
            has_candidate = true;
        }
    }

    /**
     * 売りポジション用の高ボラティリティSL候補を更新します。
     *
     * @param open_price 判定基準となるローソク足の始値。
     * @param limit 変動判定のしきい値（pips）。
     * @param rate_ratio しきい値のうち利益固定に使う割合。
     * @param pt シンボルに合わせて調整済みのpipsサイズ。
     * @param digits 価格正規化に使うシンボル桁数。
     * @param target_sl 現在の最良SL候補。参照渡しで更新されます。
     * @param has_candidate 候補が存在する場合 true に更新されます。
     */
    void UpdateSellCandidate(const double open_price,
                             const double limit,
                             const double rate_ratio,
                             const double pt,
                             const int digits,
                             double &target_sl,
                             bool &has_candidate)
    {
        const double sl_new = NormalizeDouble(open_price - limit * rate_ratio * pt, digits);
        if (!has_candidate || sl_new < target_sl || target_sl == 0.0)
        {
            target_sl = sl_new;
            has_candidate = true;
        }
    }
};

/**
 * TradingPanel のポジション数集計、決済、TP/SL初期設定を管理します。
 *
 * すべての管理処理の前にマジックナンバーとシンボルで絞り込み、
 * ライブ実行時の処理対象を明確かつ再現可能に保ちます。
 */
class CTradingPanelPositionManager
{
private:
    string m_symbol;
    ulong m_magic;
    CTrade m_trade;

public:
    /**
     * 対象シンボル、マジックナンバー、CTrade の実行設定を初期化します。
     *
     * @param symbol 対象の取引シンボル。
     * @param magic パネルのポジションを識別するマジックナンバー。
     * @param allowed_slippage 許容スリッページの最大値（ポイント）。
     */
    void Init(const string symbol, const ulong magic, const ulong allowed_slippage)
    {
        m_symbol = symbol;
        m_magic = magic;
        m_trade.SetExpertMagicNumber(m_magic);
        m_trade.SetDeviationInPoints((int)allowed_slippage);
    }

    /**
     * 現在の買い/売りポジション数と直近の建玉時刻を取得します。
     *
     * @param buy_count 管理対象の買いポジション数を返します。
     * @param sell_count 管理対象の売りポジション数を返します。
     * @param last_buy_open_time 直近の買いエントリー時刻を返します。
     * @param last_sell_open_time 直近の売りエントリー時刻を返します。
     */
    void CheckPositions(int &buy_count,
                        int &sell_count,
                        datetime &last_buy_open_time,
                        datetime &last_sell_open_time)
    {
        buy_count = 0;
        sell_count = 0;
        last_buy_open_time = 0;
        last_sell_open_time = 0;

        const int total = PositionsTotal();
        for (int i = total - 1; i >= 0; --i)
        {
            const ulong ticket = PositionGetTicket(i);
            if (ticket == 0)
                continue;
            if (!PositionSelectByTicket(ticket))
                continue;
            if ((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
                continue;

            const ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            const datetime opentime = (datetime)PositionGetInteger(POSITION_TIME);

            if (type == POSITION_TYPE_BUY)
            {
                ++buy_count;
                if (opentime > last_buy_open_time)
                    last_buy_open_time = opentime;
            }
            else if (type == POSITION_TYPE_SELL)
            {
                ++sell_count;
                if (opentime > last_sell_open_time)
                    last_sell_open_time = opentime;
            }
        }
    }

    /**
     * 管理対象ポジションに未設定の初期SL/TPを追加します。
     *
     * 既存のSL/TPは維持します。ブローカーのストップレベルまたは
     * フリーズレベル制限に抵触する候補価格はスキップします。
     *
     * @param initial_sl_pips 建値から初期ストップロスまでの距離（pips）。
     * @param initial_tp_pips 建値から初期テイクプロフィットまでの距離（pips）。
     * @return 1件以上のポジションを変更した場合 true。
     */
    bool ApplyInitialStops(const double initial_sl_pips,
                           const double initial_tp_pips)
    {
        const double pip_size = TradingPanelAdjustPoint(m_symbol);
        if (pip_size <= 0.0)
            return false;

        const double point_size = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        const int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
        bool modified = false;

        for (int i = PositionsTotal() - 1; i >= 0; --i)
        {
            const ulong ticket = PositionGetTicket(i);
            if (ticket == 0)
                continue;
            if (!PositionSelectByTicket(ticket))
                continue;
            if ((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
                continue;
            if (PositionGetString(POSITION_SYMBOL) != m_symbol)
                continue;

            const ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            const double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
            const double sl_current = PositionGetDouble(POSITION_SL);
            const double tp_current = PositionGetDouble(POSITION_TP);
            double target_sl = sl_current;
            double target_tp = tp_current;
            bool needs_modify = false;

            if (sl_current == 0.0 && initial_sl_pips > 0.0)
            {
                const double candidate_sl = (type == POSITION_TYPE_BUY)
                                                ? NormalizeDouble(open_price - initial_sl_pips * pip_size, digits)
                                                : NormalizeDouble(open_price + initial_sl_pips * pip_size, digits);
                if (IsStopPriceAllowed(type, candidate_sl, false))
                {
                    target_sl = candidate_sl;
                    needs_modify = true;
                }
                else
                {
                    PrintFormat("Initial SL skipped: ticket=%llu type=%s candidate=%.*f",
                                ticket, EnumToString(type), digits, candidate_sl);
                }
            }

            if (tp_current == 0.0 && initial_tp_pips > 0.0)
            {
                const double candidate_tp = (type == POSITION_TYPE_BUY)
                                                ? NormalizeDouble(open_price + initial_tp_pips * pip_size, digits)
                                                : NormalizeDouble(open_price - initial_tp_pips * pip_size, digits);
                if (IsStopPriceAllowed(type, candidate_tp, true))
                {
                    target_tp = candidate_tp;
                    needs_modify = true;
                }
                else
                {
                    PrintFormat("Initial TP skipped: ticket=%llu type=%s candidate=%.*f",
                                ticket, EnumToString(type), digits, candidate_tp);
                }
            }

            if (!needs_modify ||
                (MathAbs(target_sl - sl_current) < point_size / 2.0 &&
                 MathAbs(target_tp - tp_current) < point_size / 2.0))
            {
                continue;
            }

            ResetLastError();
            if (m_trade.PositionModify(ticket, target_sl, target_tp))
            {
                modified = true;
            }
            else
            {
                PrintFormat("Initial SL/TP modify failed: ticket=%llu ret=%u err=%u sl=%.*f tp=%.*f",
                            ticket, m_trade.ResultRetcode(), GetLastError(),
                            digits, target_sl, digits, target_tp);
            }
        }

        return modified;
    }

    /**
     * 売買方向とマジックナンバーでポジション数を集計します。
     *
     * @param type 集計対象のポジション方向。
     * @param magic マジックナンバーのフィルタ。
     * @return 条件に一致する保有ポジション数。
     */
    int CountPositions(const ENUM_POSITION_TYPE type, const ulong magic)
    {
        int cnt = 0;
        const int total = PositionsTotal();

        for (int i = total - 1; i >= 0; --i)
        {
            const ulong ticket = PositionGetTicket(i);
            if (ticket == 0)
                continue;
            if (!PositionSelectByTicket(ticket))
                continue;
            if (PositionGetInteger(POSITION_TYPE) != type)
                continue;
            if ((ulong)PositionGetInteger(POSITION_MAGIC) != magic)
                continue;

            ++cnt;
        }
        return cnt;
    }

    /**
     * 設定された最大保有時間を超えたポジションを決済します。
     *
     * @param dir 決済対象のポジション方向。
     * @param opposite_order_type 決済に使う反対売買の成行注文タイプ。
     * @param time_limit_enabled 時間制限決済を有効にします。
     * @param hold_seconds 最大保有時間（秒）。
     * @param allowed_slippage 決済時の最大許容スリッページ（ポイント）。
     * @return 1件以上のポジションを決済した場合 true。
     */
    bool CloseTimedPositions(const ENUM_POSITION_TYPE dir,
                             const ENUM_ORDER_TYPE opposite_order_type,
                             const bool time_limit_enabled,
                             const long hold_seconds,
                             const ulong allowed_slippage)
    {
        if (!time_limit_enabled || hold_seconds <= 0)
            return false;

        bool closed = false;

        for (int i = PositionsTotal() - 1; i >= 0; --i)
        {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};

            const ulong ticket = PositionGetTicket(i);
            if (ticket == 0)
                continue;
            if (!PositionSelectByTicket(ticket))
                continue;
            if ((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
                continue;
            if (PositionGetString(POSITION_SYMBOL) != m_symbol)
                continue;
            if (PositionGetInteger(POSITION_TYPE) != dir)
                continue;

            const datetime entry_time = (datetime)PositionGetInteger(POSITION_TIME);
            const datetime close_time = (datetime)((long)entry_time + hold_seconds);
            if (TimeCurrent() < close_time)
                continue;

            request.action = TRADE_ACTION_DEAL;
            request.position = ticket;
            request.type = opposite_order_type;
            request.symbol = m_symbol;
            request.volume = PositionGetDouble(POSITION_VOLUME);
            request.price = (dir == POSITION_TYPE_BUY)
                                ? SymbolInfoDouble(m_symbol, SYMBOL_BID)
                                : SymbolInfoDouble(m_symbol, SYMBOL_ASK);
            request.deviation = allowed_slippage;
            request.magic = m_magic;
            request.type_filling = TradingPanelGetOrderFillingPolicy(m_symbol);

            ResetLastError();
            if (OrderSend(request, result) &&
                (result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_DONE_PARTIAL))
            {
                closed = true;
            }
            else
            {
                PrintFormat("Timed close failed: ticket=%llu ret=%u err=%u close_time=%s",
                            ticket, result.retcode, GetLastError(),
                            TimeToString(close_time, TIME_DATE | TIME_SECONDS));
            }
        }
        return closed;
    }

    /**
     * 管理対象ポジションのテイクプロフィットをpips指定で移動します。
     *
     * @param pips_adjust TP調整幅（pips）。正の値は買いTPを上方向へ、
     *                    売りTPを下方向へ広げます。
     * @param side_filter 任意の売買方向フィルタ。未指定時は全ポジション。
     */
    void AdjustTakeProfit(const double pips_adjust,
                          const ENUM_POSITION_TYPE side_filter = TRADING_PANEL_POSITION_TYPE_ALL)
    {
        if (pips_adjust == 0.0)
            return;

        const double pip_size = TradingPanelAdjustPoint(m_symbol);
        const double point_size = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        const int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
        const int stops_level = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
        const int freeze_level = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_FREEZE_LEVEL);

        for (int i = PositionsTotal() - 1; i >= 0; --i)
        {
            const ulong ticket = PositionGetTicket(i);
            if (!PositionSelectByTicket(ticket))
                continue;
            if ((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
                continue;
            if (PositionGetString(POSITION_SYMBOL) != m_symbol)
                continue;

            const ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            if (side_filter != TRADING_PANEL_POSITION_TYPE_ALL && type != side_filter)
                continue;

            const double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
            const double sl_current = PositionGetDouble(POSITION_SL);
            double tp_current = PositionGetDouble(POSITION_TP);

            if (tp_current == 0.0)
                tp_current = open_price;

            const double signed_pips = (type == POSITION_TYPE_BUY ? pips_adjust : -pips_adjust);
            double new_tp = tp_current + signed_pips * pip_size;
            const double safety = 10.0 * pip_size;

            if (type == POSITION_TYPE_BUY)
                new_tp = MathMax(new_tp, open_price + safety);
            else
                new_tp = MathMin(new_tp, open_price - safety);

            new_tp = NormalizeDouble(new_tp, digits);

            const double market_price = (type == POSITION_TYPE_BUY)
                                            ? SymbolInfoDouble(m_symbol, SYMBOL_ASK)
                                            : SymbolInfoDouble(m_symbol, SYMBOL_BID);

            if (type == POSITION_TYPE_BUY)
            {
                if (new_tp <= market_price + (freeze_level + 1) * point_size)
                    continue;
                if ((new_tp - market_price) < (stops_level + 1) * point_size)
                    continue;
            }
            else
            {
                if (new_tp >= market_price - (freeze_level + 1) * point_size)
                    continue;
                if ((market_price - new_tp) < (stops_level + 1) * point_size)
                    continue;
            }

            if (MathAbs(new_tp - tp_current) >= point_size / 2.0)
            {
                ResetLastError();
                if (!m_trade.PositionModify(ticket, sl_current, new_tp))
                {
                    PrintFormat("TP adjust failed: ticket=%llu ret=%u err=%u new_tp=%.*f",
                                ticket, m_trade.ResultRetcode(), GetLastError(), digits, new_tp);
                }
            }
        }
    }

private:
    /**
     * SL/TP候補価格が現在のブローカー制限を満たすか確認します。
     *
     * @param type ポジション方向。
     * @param price 候補となるSLまたはTP価格。
     * @param is_take_profit TP検証の場合 true、SL検証の場合 false。
     * @return ストップレベルとフリーズレベルから安全に離れている場合 true。
     */
    bool IsStopPriceAllowed(const ENUM_POSITION_TYPE type,
                            const double price,
                            const bool is_take_profit)
    {
        const double point_size = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        const int stops_level = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
        const int freeze_level = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_FREEZE_LEVEL);
        const double stop_gap = (stops_level + 1) * point_size;
        const double freeze_gap = (freeze_level + 1) * point_size;
        const double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        const double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);

        if (type == POSITION_TYPE_BUY)
        {
            if (is_take_profit)
                return (price > ask + stop_gap) &&
                       (freeze_level == 0 || price > ask + freeze_gap);
            return (price < bid - stop_gap) &&
                   (freeze_level == 0 || price < bid - freeze_gap);
        }

        if (is_take_profit)
            return (price < bid - stop_gap) &&
                   (freeze_level == 0 || price < bid - freeze_gap);
        return (price > ask + stop_gap) &&
               (freeze_level == 0 || price > ask + freeze_gap);
    }
};

/**
 * 買い/売りバスケットの総建値ライン表示とSL更新を管理します。
 *
 * 出来高加重平均の建値を計算してチャートオブジェクトを表示し、
 * 価格がラインに到達した際に各ポジションのSL更新をStopManagerへ依頼します。
 */
class CTradingPanelBreakEvenLineManager
{
private:
    string m_symbol;
    ulong m_magic;
    bool m_prev_buy_flag;
    bool m_prev_sell_flag;
    int m_prev_buy_count;
    int m_prev_sell_count;

public:
    /**
     * 対象シンボル、マジックナンバー、前回のUI状態を初期化します。
     *
     * @param symbol 対象の取引シンボル。
     * @param magic パネルのポジションを収集するためのマジックナンバー。
     */
    void Init(const string symbol, const ulong magic)
    {
        m_symbol = symbol;
        m_magic = magic;
        m_prev_buy_flag = false;
        m_prev_sell_flag = false;
        m_prev_buy_count = -1;
        m_prev_sell_count = -1;
    }

    /**
     * 建値ラインと対応するラベルをチャートから削除します。
     *
     * @param base ライン/テキストペアに使うオブジェクト名の接頭辞。
     */
    void DeleteLine(const string base)
    {
        DrawLineAndText(base, 0.0, clrNONE, "", 0.0, 0, true);
    }

    /**
     * 買い側の総建値ライン表示とSL更新を管理します。
     *
     * @param show_line 買い建値ラインのチャート表示を有効にします。
     * @param buy_total_be_flag 買いバスケットの建値SL更新を有効にします。
     * @param buffer_pips 加重平均建値からのオフセット（pips）。
     * @param label_shift_bars ラベルの横方向シフト（バー数）。
     * @param label_offset_pips ラベルの縦方向オフセット（pips）。
     * @param default_sl_pips フラグ無効化時に復元する固定SL距離（pips）。
     * @param stop_manager 各ポジションの変更に使用するStopManager。
     */
    void ManageBuy(const bool show_line,
                   const bool buy_total_be_flag,
                   const double buffer_pips,
                   const int label_shift_bars,
                   const double label_offset_pips,
                   const double default_sl_pips,
                   CTradingPanelStopManager &stop_manager)
    {
        double avg = 0.0;
        ulong tickets[];
        const bool has_pos = CollectSideInfo(POSITION_TYPE_BUY, avg, tickets);
        const int cur_cnt = (int)ArraySize(tickets);
        const bool flag_changed = (buy_total_be_flag != m_prev_buy_flag);

        UpdateSideLine(POSITION_TYPE_BUY, show_line, has_pos, avg,
                       buffer_pips, label_shift_bars, label_offset_pips);

        if (buy_total_be_flag && has_pos)
            ExecuteSideBreakEven(POSITION_TYPE_BUY, avg, tickets, buffer_pips, stop_manager);

        if (flag_changed && !buy_total_be_flag && has_pos)
            stop_manager.ApplyFixedSL(tickets, POSITION_TYPE_BUY, default_sl_pips);

        m_prev_buy_flag = buy_total_be_flag;
        m_prev_buy_count = cur_cnt;
    }

    /**
     * 売り側の総建値ライン表示とSL更新を管理します。
     *
     * @param show_line 売り建値ラインのチャート表示を有効にします。
     * @param sell_total_be_flag 売りバスケットの建値SL更新を有効にします。
     * @param buffer_pips 加重平均建値からのオフセット（pips）。
     * @param label_shift_bars ラベルの横方向シフト（バー数）。
     * @param label_offset_pips ラベルの縦方向オフセット（pips）。
     * @param default_sl_pips フラグ無効化時に復元する固定SL距離（pips）。
     * @param stop_manager 各ポジションの変更に使用するStopManager。
     */
    void ManageSell(const bool show_line,
                    const bool sell_total_be_flag,
                    const double buffer_pips,
                    const int label_shift_bars,
                    const double label_offset_pips,
                    const double default_sl_pips,
                    CTradingPanelStopManager &stop_manager)
    {
        double avg = 0.0;
        ulong tickets[];
        const bool has_pos = CollectSideInfo(POSITION_TYPE_SELL, avg, tickets);
        const int cur_cnt = (int)ArraySize(tickets);
        const bool flag_changed = (sell_total_be_flag != m_prev_sell_flag);

        UpdateSideLine(POSITION_TYPE_SELL, show_line, has_pos, avg,
                       buffer_pips, label_shift_bars, label_offset_pips);

        if (sell_total_be_flag && has_pos)
            ExecuteSideBreakEven(POSITION_TYPE_SELL, avg, tickets, buffer_pips, stop_manager);

        if (flag_changed && !sell_total_be_flag && has_pos)
            stop_manager.ApplyFixedSL(tickets, POSITION_TYPE_SELL, default_sl_pips);

        m_prev_sell_flag = sell_total_be_flag;
        m_prev_sell_count = cur_cnt;
    }

private:
    /**
     * 動的な ulong 配列へチケット値を追加します。
     *
     * @param values 拡張対象の動的配列。
     * @param value 追加するチケット値。
     */
    void Push(ulong &values[], const ulong value)
    {
        const int n = ArraySize(values);
        ArrayResize(values, n + 1);
        values[n] = value;
    }

    /**
     * チャート上のラインとテキストラベルのペアを作成、更新、削除します。
     *
     * @param base オブジェクト名の接頭辞。
     * @param price 水平ラインの価格。
     * @param line_color ラインとラベルの色。
     * @param text ラベル文字列。
     * @param offset ラベル価格のオフセット（pips）。
     * @param shift_bars ラベル時刻のシフト（バー数）。
     * @param del true の場合、両方のチャートオブジェクトを削除します。
     */
    void DrawLineAndText(const string base,
                         const double price,
                         const color line_color,
                         const string text,
                         const double offset,
                         const int shift_bars = 0,
                         const bool del = false)
    {
        const long chart_id = ChartID();
        const string line_name = base + "_LINE";
        const string text_name = base + "_TEXT";

        if (del)
        {
            if (ObjectFind(chart_id, line_name) >= 0)
                ObjectDelete(chart_id, line_name);
            if (ObjectFind(chart_id, text_name) >= 0)
                ObjectDelete(chart_id, text_name);
            return;
        }

        if (ObjectFind(chart_id, line_name) >= 0)
            ObjectSetDouble(chart_id, line_name, OBJPROP_PRICE, price);
        else if (ObjectCreate(chart_id, line_name, OBJ_HLINE, 0, 0, price))
        {
            ObjectSetInteger(chart_id, line_name, OBJPROP_COLOR, line_color);
            ObjectSetInteger(chart_id, line_name, OBJPROP_STYLE, STYLE_DASH);
            ObjectSetInteger(chart_id, line_name, OBJPROP_WIDTH, 1);
        }

        const double y = price + offset * TradingPanelAdjustPoint(m_symbol);
        const datetime x = iTime(m_symbol, _Period, shift_bars);

        if (ObjectFind(chart_id, text_name) >= 0)
        {
            ObjectMove(chart_id, text_name, 0, x, y);
            ObjectSetString(chart_id, text_name, OBJPROP_TEXT, text);
        }
        else if (ObjectCreate(chart_id, text_name, OBJ_TEXT, 0, x, y))
        {
            ObjectSetString(chart_id, text_name, OBJPROP_TEXT, text);
            ObjectSetInteger(chart_id, text_name, OBJPROP_COLOR, line_color);
            ObjectSetInteger(chart_id, text_name, OBJPROP_FONTSIZE, 9);
            ObjectSetInteger(chart_id, text_name, OBJPROP_BACK, false);
            ObjectSetInteger(chart_id, text_name, OBJPROP_ANCHOR, ANCHOR_RIGHT);
        }
    }

    /**
     * 指定方向のポジションについて加重平均建値とチケット一覧を収集します。
     *
     * @param side 収集対象のポジション方向。
     * @param avg 出来高加重平均の建値を返します。
     * @param tickets シンボル、マジックナンバー、方向が一致するチケットを返します。
     * @return 条件に一致するポジションが1件以上ある場合 true。
     */
    bool CollectSideInfo(const ENUM_POSITION_TYPE side,
                         double &avg,
                         ulong &tickets[])
    {
        double sum_volume = 0.0;
        double sum_cost = 0.0;
        ArrayResize(tickets, 0);

        for (int i = PositionsTotal() - 1; i >= 0; --i)
        {
            const ulong ticket = PositionGetTicket(i);
            if (!PositionSelectByTicket(ticket))
                continue;
            if (PositionGetString(POSITION_SYMBOL) != m_symbol)
                continue;
            if ((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
                continue;
            if ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != side)
                continue;

            const double volume = PositionGetDouble(POSITION_VOLUME);
            const double price = PositionGetDouble(POSITION_PRICE_OPEN);
            sum_volume += volume;
            sum_cost += price * volume;
            Push(tickets, ticket);
        }

        if (sum_volume == 0.0)
            return false;

        avg = sum_cost / sum_volume;
        return true;
    }

    /**
     * 売買方向別の総建値ラインとラベルを描画します。
     *
     * @param avg 出来高加重平均の建値。
     * @param buffer_pips 平均建値からのオフセット（pips）。
     * @param side ラインが表すポジション方向。
     * @param label_shift_bars ラベルの横方向シフト（バー数）。
     * @param label_offset_pips ラベルの縦方向オフセット（pips）。
     */
    void DrawSideBreakEvenLine(const double avg,
                               const double buffer_pips,
                               const ENUM_POSITION_TYPE side,
                               const int label_shift_bars,
                               const double label_offset_pips)
    {
        const string base = (side == POSITION_TYPE_BUY ? "BreakEvenBuy" : "BreakEvenSell");
        const color line_color = (side == POSITION_TYPE_BUY ? clrSeaGreen : clrBrown);
        const string label = (side == POSITION_TYPE_BUY ? "BuyTotal_BE" : "SellTotal_BE");
        const double pt = TradingPanelAdjustPoint(m_symbol);
        const double price = NormalizeDouble(avg + (side == POSITION_TYPE_BUY ? +buffer_pips : -buffer_pips) * pt,
                                             (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS));
        const double offset = (side == POSITION_TYPE_BUY ? +label_offset_pips : -label_offset_pips);

        DrawLineAndText(base, price, line_color, label, offset, label_shift_bars);
    }

    /**
     * 指定方向の建値ラインを更新または削除します。
     *
     * @param side ラインが表すポジション方向。
     * @param show_line ポジションが存在する場合の描画を有効にします。
     * @param has_pos 条件に一致するポジションが1件以上ある場合 true。
     * @param avg_price 出来高加重平均の建値。
     * @param buffer_pips 平均建値からのオフセット（pips）。
     * @param label_shift_bars ラベルの横方向シフト（バー数）。
     * @param label_offset_pips ラベルの縦方向オフセット（pips）。
     */
    void UpdateSideLine(const ENUM_POSITION_TYPE side,
                        const bool show_line,
                        const bool has_pos,
                        const double avg_price,
                        const double buffer_pips,
                        const int label_shift_bars,
                        const double label_offset_pips)
    {
        const string base = (side == POSITION_TYPE_BUY ? "BreakEvenBuy" : "BreakEvenSell");

        if (show_line)
        {
            if (has_pos)
                DrawSideBreakEvenLine(avg_price, buffer_pips, side, label_shift_bars, label_offset_pips);
            else
                DrawLineAndText(base, 0.0, clrNONE, "", 0.0, 0, true);
        }
        else
        {
            DrawLineAndText(base, 0.0, clrNONE, "", 0.0, 0, true);
        }
    }

    /**
     * 市場価格が総建値ラインへ到達した後、SLをライン付近へ移動します。
     *
     * @param line_price 建値判定および目標SLの基準価格。
     * @param tickets 更新対象のチケット配列。
     * @param side 検証と価格選択に使うポジション方向。
     * @param stop_manager ブローカー制限を考慮した変更に使うStopManager。
     */
    void UpdateSideStopLoss(const double line_price,
                            ulong &tickets[],
                            const ENUM_POSITION_TYPE side,
                            CTradingPanelStopManager &stop_manager)
    {
        const double point_size = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        const int stop_level = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
        const int freeze = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_FREEZE_LEVEL);
        const double min_gap = stop_level * point_size;
        const double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        const double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
        const bool reached = (side == POSITION_TYPE_BUY) ? (bid >= line_price) : (ask <= line_price);

        if (!reached)
            return;

        for (int i = 0; i < ArraySize(tickets); ++i)
        {
            const ulong ticket = tickets[i];
            if (!PositionSelectByTicket(ticket))
                continue;

            const double cur_sl = PositionGetDouble(POSITION_SL);
            double sl_price = 0.0;

            if (side == POSITION_TYPE_BUY)
                sl_price = MathMin(line_price, bid - min_gap);
            else
                sl_price = MathMax(line_price, ask + min_gap);

            const bool in_freeze = (freeze > 0) &&
                                   ((side == POSITION_TYPE_BUY)
                                        ? ((bid - sl_price) / point_size < freeze)
                                        : ((sl_price - ask) / point_size < freeze));
            if (in_freeze)
                continue;

            const bool need = (cur_sl == 0.0) ||
                              (side == POSITION_TYPE_BUY
                                   ? (sl_price > cur_sl + 0.1 * point_size)
                                   : (sl_price < cur_sl - 0.1 * point_size));
            if (!need)
                continue;

            stop_manager.ModifyPositionStop(ticket, sl_price, PositionGetDouble(POSITION_TP));
        }
    }

    /**
     * 総建値ラインを計算し、必要なSL更新を実行します。
     *
     * @param side 管理対象のポジション方向。
     * @param avg_price 出来高加重平均の建値。
     * @param tickets バスケットに含まれるチケット配列。
     * @param buffer_pips 平均建値からのオフセット（pips）。
     * @param stop_manager 各ポジションの変更に使用するStopManager。
     */
    void ExecuteSideBreakEven(const ENUM_POSITION_TYPE side,
                              const double avg_price,
                              ulong &tickets[],
                              const double buffer_pips,
                              CTradingPanelStopManager &stop_manager)
    {
        if (ArraySize(tickets) == 0)
            return;

        const double pt = TradingPanelAdjustPoint(m_symbol);
        const double line_price = NormalizeDouble(avg_price + ((side == POSITION_TYPE_BUY ? +buffer_pips : -buffer_pips) * pt),
                                                  (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS));

        UpdateSideStopLoss(line_price, tickets, side, stop_manager);
    }
};

#endif

