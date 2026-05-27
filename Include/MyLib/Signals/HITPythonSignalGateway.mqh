#ifndef HIT_PYTHON_SIGNAL_GATEWAY_MQH
#define HIT_PYTHON_SIGNAL_GATEWAY_MQH

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
 * @param trend_state 読み込んだ値を格納する参照。0..5のmarket_state。6は技術エラー停止。
 *
 * ファイル未存在、読込失敗、異常値の場合は安全側として6（技術エラー停止）を設定します。
 */
void LoadTrendState(int &trend_state)
  {
   string filename = trend_state_file;
   trend_state = MARKET_TECHNICAL_ERROR_STOP;

   if(FileIsExist(filename))
     {
      int filehandle = FileOpen(filename, FILE_READ | FILE_TXT);
      if(filehandle != INVALID_HANDLE)
        {
         string line = FileReadString(filehandle);
         int value = (int)StringToInteger(line);
         if(value >= MARKET_LOW_VOL_RANGE && value <= MARKET_TECHNICAL_ERROR_STOP)
            trend_state = value;
         else
            Print("Invalid market_state value: ", line, ". Use technical error stop(6).");
         FileClose(filehandle);
        }
      else
        { Print("Failed to open trend_state.txt"); trend_state = MARKET_TECHNICAL_ERROR_STOP; }
     }
   else
     { Print("trend_state.txt not found"); trend_state = MARKET_TECHNICAL_ERROR_STOP; }
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

      LoadTargetZones(state);
      if(use_split_entry_zone && cancel_old_split_pending_on_new_zone && state.zone_res_chk == 1)
         CancelStaleSplitPendingOrders(state.zone_candidate_id);

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
//| target_zones.txt の状態を停止値へ初期化する関数
//+------------------------------------------------------------------+
void ResetTargetZones(EAState &state)
  {
   state.zone_res_chk = 0;
   state.zone_candidate_id = "0";

   for(int t = 1; t <= 4; t++)
     {
      state.zone_low[t] = 0.0;
      state.zone_high[t] = 0.0;
      state.zone_tp[t] = 0.0;
      state.zone_sl[t] = 0.0;
     }
  }

//+------------------------------------------------------------------+
//| target_zones.txt の1戦略行を読み込む関数
//+------------------------------------------------------------------+
bool ParseTargetZoneLine(const string line, EAState &state, const int digits)
  {
   string parts[];
   int count = StringSplit(line, StringGetCharacter(",", 0), parts);
   if(count < 5)
      return false;

   int strategy = (int)StringToInteger(parts[0]);
   if(strategy < 1 || strategy > 4)
      return false;

   state.zone_low[strategy] = NormalizeDouble(StringToDouble(parts[1]), digits);
   state.zone_high[strategy] = NormalizeDouble(StringToDouble(parts[2]), digits);
   state.zone_tp[strategy] = NormalizeDouble(StringToDouble(parts[3]), digits);
   state.zone_sl[strategy] = NormalizeDouble(StringToDouble(parts[4]), digits);
   return true;
  }

//+------------------------------------------------------------------+
//| target_zones.txt を読み込む関数
//+------------------------------------------------------------------+
void LoadTargetZones(EAState &state)
  {
   ResetTargetZones(state);

   string filename = target_zones_file;
   if(!FileIsExist(filename))
     {
      Print("target_zones.txt not found. Split entry zones disabled for this candidate.");
      return;
     }

   int filehandle = FileOpen(filename, FILE_READ | FILE_TXT);
   if(filehandle == INVALID_HANDLE)
     {
      Print("Failed to open target_zones.txt. Error code: ", GetLastError());
      return;
     }

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   int line_index = 0;
   int loaded_strategies = 0;

   while(!FileIsEnding(filehandle))
     {
      string line = FileReadString(filehandle);
      if(line == "")
         continue;

      line_index++;
      if(line_index == 1)
        {
         int schema_version = (int)StringToInteger(line);
         if(schema_version != TARGET_ZONE_SCHEMA_VERSION)
           {
            Print("target_zones schema mismatch. loaded=", schema_version,
                  " required=", TARGET_ZONE_SCHEMA_VERSION);
            FileClose(filehandle);
            ResetTargetZones(state);
            return;
           }
         continue;
        }

      if(line_index == 2)
        {
         state.zone_res_chk = (int)StringToInteger(line);
         continue;
        }

      if(line_index == 3)
        {
         state.zone_candidate_id = line;
         continue;
        }

      if(ParseTargetZoneLine(line, state, digits))
         loaded_strategies++;
     }

   FileClose(filehandle);

   if(line_index < 7 || loaded_strategies < 4)
     {
      Print("target_zones.txt line count is short. loaded_lines=", line_index,
            " loaded_strategies=", loaded_strategies);
      ResetTargetZones(state);
      return;
     }

   if(state.zone_res_chk != 1)
      ResetTargetZones(state);

   Print("target_zones: res=", state.zone_res_chk,
         " id=", state.zone_candidate_id,
         " | T1 zone=", state.zone_low[1], "-", state.zone_high[1],
         " tp=", state.zone_tp[1], " sl=", state.zone_sl[1],
         " | T2 zone=", state.zone_low[2], "-", state.zone_high[2],
         " tp=", state.zone_tp[2], " sl=", state.zone_sl[2],
         " | T3 zone=", state.zone_low[3], "-", state.zone_high[3],
         " tp=", state.zone_tp[3], " sl=", state.zone_sl[3],
         " | T4 zone=", state.zone_low[4], "-", state.zone_high[4],
         " tp=", state.zone_tp[4], " sl=", state.zone_sl[4]);
  }

//+------------------------------------------------------------------+

#endif
