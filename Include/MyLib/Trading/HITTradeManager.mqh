#ifndef HIT_TRADE_MANAGER_MQH
#define HIT_TRADE_MANAGER_MQH


//+------------------------------------------------------------------+
//| 注文ロットがブローカー制約を満たすか判定する関数
//+------------------------------------------------------------------+
/**
 * @brief 通常注文と分割注文の最終送信前に volume min/max/step を検証します。
 */
bool IsOrderVolumeAllowed(const double volume, const string context)
  {
   double min_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(volume <= 0.0 || min_volume <= 0.0 || max_volume <= 0.0 || step_volume <= 0.0)
     {
      Print("[Order Skip] invalid volume setting. context=", context,
            " volume=", volume, " min=", min_volume,
            " max=", max_volume, " step=", step_volume);
      return false;
     }

   if(volume < min_volume || volume > max_volume)
     {
      Print("[Order Skip] volume out of range. context=", context,
            " volume=", volume, " min=", min_volume, " max=", max_volume);
      return false;
     }

   double steps = (volume - min_volume) / step_volume;
   double nearest = MathRound(steps);
   if(MathAbs(steps - nearest) > 0.000001)
     {
      Print("[Order Skip] volume does not match broker step. context=", context,
            " volume=", volume, " min=", min_volume, " step=", step_volume);
      return false;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| ブローカーのロットstepから正規化桁数を推定する関数
//+------------------------------------------------------------------+
int VolumeDigits()
  {
   int volume_digits = 2;
   double step_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step_volume > 0.0)
     {
      volume_digits = 0;
      double step = step_volume;
      while(step < 1.0 && volume_digits < 8)
        {
         step *= 10.0;
         volume_digits++;
        }
     }

   return volume_digits;
  }

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
 * @param volume 注文ロット。
 * @param comment_suffix 分割注文識別用のコメント接尾辞。空なら従来コメント。
 * @return 注文が正常に受理された場合はtrue、それ以外はfalse。
 */
bool SendOrder(int orderType, double price, double tp, double sl, double volume, string comment_suffix)
  {
   MqlTradeRequest request  = {};
   MqlTradeResult result    = {};

   request.magic            = magic_number;
   request.symbol           = _Symbol;
   request.volume           = NormalizeDouble(volume, VolumeDigits());
   request.deviation        = slippage;
   request.type_filling     = GetOrderFillingPolicy(_Symbol);
   request.price            = NormalizeDouble(price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   request.tp               = NormalizeDouble(tp, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   request.sl               = NormalizeDouble(sl, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   request.comment          = RequestComment(orderType, comment_suffix);

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

   string volume_context = orderTypeStr;
   if(comment_suffix != "")
      volume_context += " " + comment_suffix;
   if(!IsOrderVolumeAllowed(volume, volume_context))
      return false;

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
 * @param comment_suffix 分割注文識別用のコメント接尾辞。
 * @return 注文タイプとPCローカル時刻、または分割注文識別子を含むコメント文字列。
 */
string RequestComment(int orderType, string comment_suffix)
  {
   if(comment_suffix != "")
      return "T" + IntegerToString(orderType) + " " + comment_suffix;

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
 * @param trend_state H4 market_state（0..5、6は技術エラー停止）。
 * @return 許可される注文タイプならtrue。技術エラー停止または異常値ではfalse。
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

      case MARKET_TECHNICAL_ERROR_STOP:
      default:
         return false; // 技術エラー停止または異常値は新規注文しない
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
//| 実効ポジション上限を返す関数
//+------------------------------------------------------------------+
/**
 * @brief input指定の上限を安全な範囲に丸めて返します。
 */
int EffectivePositionLimit()
  {
   int limit = input_position_limit;
   if(limit < 1)
      limit = 1;
   if(limit > POSITION_LIMIT)
      limit = POSITION_LIMIT;

   return limit;
  }

//+------------------------------------------------------------------+
//| 分割注文コメントか判定する関数
//+------------------------------------------------------------------+
bool IsSplitOrderComment(const string comment)
  {
   return (StringFind(comment, " Z") >= 0 && StringFind(comment, "#") >= 0);
  }

//+------------------------------------------------------------------+
//| 指定候補IDの分割注文コメントか判定する関数
//+------------------------------------------------------------------+
bool IsCurrentSplitCandidateComment(const string comment, const string candidate_id)
  {
   if(candidate_id == "" || candidate_id == "0")
      return false;

   return (StringFind(comment, "Z" + candidate_id + "#") >= 0);
  }

//+------------------------------------------------------------------+
//| 分割slotが既存注文/ポジションに存在するか判定する関数
//+------------------------------------------------------------------+
bool HasExistingSplitSlot(const string slot_key)
  {
   if(slot_key == "")
      return false;

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
      if(StringFind(OrderGetString(ORDER_COMMENT), slot_key) >= 0)
         return true;
     }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      string symbol = PositionGetSymbol(i);
      if(symbol == "")
         continue;
      if(symbol != _Symbol)
         continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != magic_number)
         continue;
      if(StringFind(PositionGetString(POSITION_COMMENT), slot_key) >= 0)
         return true;
     }

   return false;
  }

//+------------------------------------------------------------------+
//| 古い分割pending注文を取消する関数
//+------------------------------------------------------------------+
bool CancelStaleSplitPendingOrders(const string current_candidate_id)
  {
   bool result = false;
   bool keep_current_candidate = (current_candidate_id != "" && current_candidate_id != "0");

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

      string comment = OrderGetString(ORDER_COMMENT);
      if(!IsSplitOrderComment(comment))
         continue;
      if(keep_current_candidate && IsCurrentSplitCandidateComment(comment, current_candidate_id))
         continue;

      MqlTradeRequest request = {};
      MqlTradeResult trade_result = {};
      request.action = TRADE_ACTION_REMOVE;
      request.order = ticket;

      if(!OrderSend(request, trade_result))
        {
         Print("Failed to delete stale split order. Ticket: ", ticket, " Error: ", GetLastError());
         continue;
        }

      if(trade_result.retcode == TRADE_RETCODE_DONE)
        {
         Print("Stale split order canceled. Ticket: ", ticket, " comment=", comment);
         result = true;
        }
      else
        {
         Print("Stale split order cancellation failed. Ticket: ", ticket, " Retcode: ", trade_result.retcode);
        }
     }

   return result;
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

#endif
