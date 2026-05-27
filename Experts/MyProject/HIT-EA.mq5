//+------------------------------------------------------------------+
//|                                                       HIT_EA.mq5 |
//|                               Copyright 2026,  nanpin-martin.com |
//|                                    https://www.nanpin-martin.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, nanpin-martin.com"
#property link      "https://nanpin-martin.com/"
#property version   "1.00"

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
input double spread_limit  = 20;    // 許容スプレッド(point)
input int    magic_number  = 10001; // マジックナンバー
input int    initial_order = 0;     // 起動時の注文(0:なし, 1:あり)
ulong  slippage      = 10;          // スリッページ

//--- 主要な定数・設定
#define POSITION_LIMIT        48
#define ENTRY_H1_LIMIT        1         // H1本数（=1時間）
#define CLOSE_H1_LIMIT        12        // H1本数（=12時間）
#define HISTORY_BARS          72
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

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 必要な関数プロトタイプ宣言
//|   プロセス完了ファイル("process_done.txt")関連
//+------------------------------------------------------------------+

// "process_done.txt"を作成する関数
void CreateDoneFile(const string name);

// "process_done.txt"を削除する関数
void DeleteDoneFile(const string name);

// "process_done.txt"の存在を確認し、存在する場合はtrueを返す関数
bool CheckDoneFile(const string name);

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 必要な関数プロトタイプ宣言
//|   OHLCデータの取得からターゲット価格の取得まで
//+------------------------------------------------------------------+

//| 最新のOHLCデータを取得する関数
bool GetLatestOHLC(datetime &times[], double &open_prices[], double &high_prices[], double &low_prices[], double &close_prices[], ENUM_TIMEFRAMES tf, int bars_count);

//| "ohlc.csv"を出力する関数
void RecordOHLC(const string filename, const datetime &times[], const double &open_prices[], const double &high_prices[], const double &low_prices[], const double &close_prices[]);

//| バッチファイル（Pythonスクリプト）を実行する関数
void ExecuteBatchTrend();
void ExecuteBatchEntry();

// | "ohlc.csv"を出力後、バッチファイルの実行する関数
bool RecordOHLCAndExecuteBatch_Trend(EAState &state);
bool RecordOHLCAndExecuteBatch_Entry(EAState &state);

//| ターゲット価格を取得する関数
bool GetTargetPrices(EAState &state);

//| "target_prices.txt"を読み込む関数
void LoadTargetPrices(double &target_prices[]);

//| "xxx"を読み込む関数
bool GetTrendState(EAState &state);
void LoadTrendState(int &trend_state);

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 必要な関数プロトタイプ宣言
//|   エントリー注文関連
//+------------------------------------------------------------------+

//| エントリー注文を送信する関数 (1:buy-stop, 2:buy-limit, 3:sell-stop, 4:sell-limit)
bool SendOrder(int orderType, double price, double tp, double sl);

//| 注文の執行ポリシーを取得する関数
ENUM_ORDER_TYPE_FILLING GetOrderFillingPolicy(string symbol);

//| 注文コメント(ローカル時刻)を生成する関数（先頭に orderType を付与）
string  RequestComment(int orderType);

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 必要な関数プロトタイプ宣言
//|   時間制限処理関連
//+------------------------------------------------------------------+

//| 時間が経過したエントリー注文をキャンセルする関数
bool CancelExpiredOrders();

//| 時間が経過したポジションをクローズする関数
bool CloseExpiredPositions();

//| 指定された時間に最も近いバーのインデックスを返す関数
// int GetBarIndexByTime(datetime time, int default_index = 0);
int GetBarShiftByTime(datetime time, ENUM_TIMEFRAMES tf, int default_shift = -1);

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 起動時の処理
//+------------------------------------------------------------------+
void OnInit()
// プロセス完了ファイル("process_done.txt)"を作成
  {
   CreateDoneFile(done_trend_file);
   CreateDoneFile(done_entry_file);
  }

//+------------------------------------------------------------------+
//| ティック毎の処理
//+------------------------------------------------------------------+
void OnTick()
  {
   static int init_order_flg = initial_order;

// ─────────────────────────────────────────────
// (1) H4更新検知：トレンド用
// ─────────────────────────────────────────────
   int current_bars_H4 = iBars(NULL, PERIOD_H4);
   static int pre_bars_H4 = current_bars_H4;
   int bars_H4_change = current_bars_H4 - pre_bars_H4;

   if(bars_H4_change > 0 || init_order_flg == 1)
     {
      RecordOHLCAndExecuteBatch_Trend(g_ea);
     }
   pre_bars_H4 = current_bars_H4;

// trend done待ち（なければ以降をスキップ）
   if(!CheckDoneFile(done_trend_file))
      return;

// トレンド取得
   GetTrendState(g_ea);

// ─────────────────────────────────────────────
// (2) H1更新検知：エントリー用
// ─────────────────────────────────────────────
   static bool bars_H1_check = false;

   int current_bars_H1 = iBars(NULL, PERIOD_H1);
   static int pre_bars_H1 = current_bars_H1;
   int bars_H1_change = current_bars_H1 - pre_bars_H1;

   if(bars_H1_change > 0 || init_order_flg == 1)
     {
      init_order_flg = 0;
      bars_H1_check = true;
      g_ea.chk_cnt = 0;
      g_ea.last_chk = 0;
      RecordOHLCAndExecuteBatch_Entry(g_ea);
     }
   pre_bars_H1 = current_bars_H1;

// ── ティック情報・コメント表示 ──
   MqlTick last_tick;
   if(!SymbolInfoTick(_Symbol, last_tick))
     {
      return;
     }
   double Ask = last_tick.ask;
   double Bid = last_tick.bid;
   double Spread = MathRound((Ask - Bid) / Point()) * Point();

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   string message = StringFormat(
                       " \nAsk: %." + IntegerToString(digits) + "f"
                       "\nBid: %." + IntegerToString(digits) + "f"
                       "\nSpread: %." + IntegerToString(digits) + "f"
                       "\n\nLast Trend Update:\n %s"
                       "\n\nTrend State: %.0f"           // ★追加
                       "\n\nLast Target Update:\n %s"
                       "\n\n[T1 Buy Stop ] en: %." + IntegerToString(digits) + "f  tp: %." + IntegerToString(digits) + "f  sl: %." + IntegerToString(digits) + "f"
                       "\n[T2 Buy Limit] en: %." + IntegerToString(digits) + "f  tp: %." + IntegerToString(digits) + "f  sl: %." + IntegerToString(digits) + "f"
                       "\n[T3 Sell Stop] en: %." + IntegerToString(digits) + "f  tp: %." + IntegerToString(digits) + "f  sl: %." + IntegerToString(digits) + "f"
                       "\n[T4 SellLimit] en: %." + IntegerToString(digits) + "f  tp: %." + IntegerToString(digits) + "f  sl: %." + IntegerToString(digits) + "f\n",
                       Ask, Bid, Spread,
                       TimeToString(g_ea.last_trend_update, TIME_DATE | TIME_MINUTES),
                       g_ea.trend_state,                             // ★追加
                       TimeToString(g_ea.last_target_update, TIME_DATE | TIME_MINUTES),
                       g_ea.en_price[1], g_ea.tp_price[1], g_ea.sl_price[1],
                       g_ea.en_price[2], g_ea.tp_price[2], g_ea.sl_price[2],
                       g_ea.en_price[3], g_ea.tp_price[3], g_ea.sl_price[3],
                       g_ea.en_price[4], g_ea.tp_price[4], g_ea.sl_price[4]
                    );
   Comment(message);

// スプレッド制限
   if(Spread > spread_limit * Point())
      return;

// entry done待ち
   if(!CheckDoneFile(done_entry_file))
      return;

// ターゲット取得
   GetTargetPrices(g_ea);

// 期限切れ注文キャンセル・ポジクローズ
   if(OrdersTotal() > 0)
      CancelExpiredOrders();
   if(PositionsTotal() > 0)
      CloseExpiredPositions();

// ─────────────────────────────────────────────
// エントリー条件判定＆注文送信（H1更新タイミングで1回）
// ─────────────────────────────────────────────
//  if(bars_H4_check && TimeCurrent() - g_ea.last_chk >= 60)
//    {
//     bars_H4_check = false;
//     g_ea.last_chk = TimeCurrent();
   if(bars_H1_check && TimeCurrent() - g_ea.last_chk >= 60)
     {
      bars_H1_check = false;
      g_ea.last_chk = TimeCurrent();

      if(g_ea.res_chk == 0)
        {
         Print("[Entry Skip] res_chk=0 (range). No entry orders are sent.");
         g_ea.chk_cnt = 0;
        }
      else
        {
         int used = OrdersTotal() + PositionsTotal();
         if(used >= POSITION_LIMIT)
           {
            Print("Position limit exceeded: used=", used, " limit=", POSITION_LIMIT);
           }
         else
           {
            int sent_success = 0; // ★ 送信成功数（= SendOrder true の回数）

            // ★ 1..4 を順に判定して、条件OKなら送る
            for(int t=1; t<=4; t++)
              {
               // ポジション上限チェック（途中で到達したら打ち切り）
               used = OrdersTotal() + PositionsTotal();
               if(used >= POSITION_LIMIT)
                 {
                  Print("Position limit reached while sending. used=", used, " limit=", POSITION_LIMIT);
                  break;
                 }

               string entry_type;
               double cur_price; // ログ用（Ask/Bid）

               if(t==1)
                 {
                  entry_type="Buy Stop";
                  cur_price=Ask;
                 }
               else
                  if(t==2)
                    {
                     entry_type="Buy Limit";
                     cur_price=Ask;
                    }
                  else
                     if(t==3)
                       {
                        entry_type="Sell Stop";
                        cur_price=Bid;
                       }
                     else
                       {
                        entry_type="Sell Limit";  // t==4
                        cur_price=Bid;
                       }

               double en = g_ea.en_price[t];
               double tp = g_ea.tp_price[t];
               double sl = g_ea.sl_price[t];

               bool ok=false;

               if(t==1)
                  ok = (Ask < en && tp > en && sl < en); // buy-stop
               else
                  if(t==2)
                     ok = (Ask > en && tp > en && sl < en); // buy-limit
                  else
                     if(t==3)
                        ok = (Bid > en && tp < en && sl > en); // sell-stop
                     else
                        ok = (Bid < en && tp < en && sl > en); // sell-limit

               if(ok)
                 {
                  Print("[", entry_type, " Order Try at ", cur_price, "] en=", en, " tp=", tp, " sl=", sl);

                  if(SendOrder(t, en, tp, sl))
                    {
                     sent_success++;
                     Print("[", entry_type, " Order Sent] ticket ok. en=", en, " tp=", tp, " sl=", sl);
                    }
                  else
                    {
                     Print("[", entry_type, " Order Failed] en=", en, " tp=", tp, " sl=", sl);
                    }
                 }
               else
                 {
                  Print("[No ", entry_type, "] cur=", cur_price, " en=", en, " tp=", tp, " sl=", sl);
                 }
              }

            if(sent_success > 0)
              {
               g_ea.chk_cnt = 0; // 1件でも通ったら終了
              }
            else
              {
               g_ea.chk_cnt += 1;
               Print("[Retry] no order sent. chk_cnt=", g_ea.chk_cnt, "/10");

               if(g_ea.chk_cnt < 10)
                 {
                  //  bars_H4_check = true; // 60秒後に再度このブロックに入る
                  bars_H1_check = true;  // ★ GPT-EAの bars_H4_check → bars_H1_check に変更
                 }
               else
                 {
                  Print("[Retry End] reached max tries. reset chk_cnt.");
                  g_ea.chk_cnt = 0;
                 }
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| "process_done.txt"を作成する関数
//+------------------------------------------------------------------+
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
void DeleteDoneFile(const string name)
  {
   if(FileIsExist(name))
      FileDelete(name);
  }


//+------------------------------------------------------------------+
//| "process_done.txt"の存在を確認し、存在する場合はtrueを返す関数
//+------------------------------------------------------------------+
bool CheckDoneFile(const string name)
  {
   return FileIsExist(name);
  }

//+------------------------------------------------------------------+
//| 最新のOHLCデータを取得する関数
//+------------------------------------------------------------------+
bool GetLatestOHLC(datetime &times[], double &open_prices[], double &high_prices[], double &low_prices[], double &close_prices[], ENUM_TIMEFRAMES tf, int bars_count)
  {
   ArrayResize(times, 0);
   ArrayResize(open_prices, 0);
   ArrayResize(high_prices, 0);
   ArrayResize(low_prices, 0);
   ArrayResize(close_prices, 0);

   if(bars_count < 2)
      return false;

// 時間データを取得
   if(CopyTime(_Symbol, tf, 0, bars_count, times) <= 0)
     {
      Print(__FUNCTION__, ": Failed to copy time data (bars=", bars_count, ") err=", GetLastError());
      return false;
     }

// OHLCデータを取得
   MqlRates rates[];
   if(CopyRates(_Symbol, tf, 0, bars_count, rates) <= 0)
     {
      Print(__FUNCTION__, ": Failed to copy rates data (bars=", bars_count, ") err=", GetLastError());
      return false;
     }

// 必要なデータを配列に格納
   for(int i = 0; i < ArraySize(rates); i++)
     {
      ArrayResize(open_prices, i + 1);
      ArrayResize(high_prices, i + 1);
      ArrayResize(low_prices, i + 1);
      ArrayResize(close_prices, i + 1);

      open_prices[i] = rates[i].open;
      high_prices[i] = rates[i].high;
      low_prices[i] = rates[i].low;
      close_prices[i] = rates[i].close;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| "ohlc.csv"を出力する関数
//+------------------------------------------------------------------+
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
void ExecuteBatchTrend()
  {
   if(CheckDoneFile(done_trend_file))
     {
      DeleteDoneFile(done_trend_file);
      ShellExecuteW(0, "open", get_trend_reply_bat, "", "", 1);
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ExecuteBatchEntry()
  {
   if(CheckDoneFile(done_entry_file))
     {
      DeleteDoneFile(done_entry_file);
      ShellExecuteW(0, "open", get_entry_reply_bat, "", "", 1);
     }
  }


//+------------------------------------------------------------------+
//| "ohlc.csv"を出力後、バッチファイルの実行する関数
//+------------------------------------------------------------------+
bool RecordOHLCAndExecuteBatch_Trend(EAState &state)
  {
   datetime times[];
   double open_prices[], high_prices[], low_prices[], close_prices[];

   if(!GetLatestOHLC(times, open_prices, high_prices, low_prices, close_prices,
                     PERIOD_H4, HISTORY_BARS))
     { Print("GetLatestOHLC(H4) failed."); return false; }

   RecordOHLC("ohlc_H4.csv", times, open_prices, high_prices, low_prices, close_prices);
   ExecuteBatchTrend();

   state.load_trend_flg = true;
   return true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool RecordOHLCAndExecuteBatch_Entry(EAState &state)
  {
   datetime times[];
   double open_prices[], high_prices[], low_prices[], close_prices[];

   if(!GetLatestOHLC(times, open_prices, high_prices, low_prices, close_prices,
                     PERIOD_H1, HISTORY_BARS))
     { Print("GetLatestOHLC(H1) failed."); return false; }

   RecordOHLC("ohlc_H1.csv", times, open_prices, high_prices, low_prices, close_prices);
   ExecuteBatchEntry();

   state.load_target_flg = true;
   return true;
  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
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
void LoadTrendState(int &trend_state)
  {
   string filename = "trend_state.txt";
   if(FileIsExist(filename))
     {
      int filehandle = FileOpen(filename, FILE_READ | FILE_TXT);
      if(filehandle != INVALID_HANDLE)
        {
         string line = FileReadString(filehandle);
         trend_state = (int)StringToInteger(line);
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
void LoadTargetPrices(double &target_prices[])
  {
   ArrayResize(target_prices, TARGET_SIZE);
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
        }
      else
        {
         Print("Failed to open file. Error code: ", GetLastError());
         for(int i = 0; i < TARGET_SIZE; i++)
           {
            target_prices[i] = DEFAULT_TARGET_PRICE;
           }
        }
     }
   else
     {
      Print("File does not exist: ", filename);
      for(int i = 0; i < TARGET_SIZE; i++)
        {
         target_prices[i] = DEFAULT_TARGET_PRICE;
        }
     }
  }

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| エントリー注文を送信する関数 (1:buy-stop, 2:buy-limit, 3:sell-stop, 4:sell-limit)
//+------------------------------------------------------------------+
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
string RequestComment(int orderType)
  {
   datetime localTime = TimeLocal();
   string timeStr     = TimeToString(localTime, TIME_DATE|TIME_MINUTES);

// 先頭に 1,2,3,4 を付ける（例: "1 | PC Time: 2026.02.14 19:05"）
   return IntegerToString(orderType) + " | PC Time: " + timeStr;
  }

//+------------------------------------------------------------------+
//| 時間が経過したエントリー注文をキャンセルする関数
//+------------------------------------------------------------------+
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
