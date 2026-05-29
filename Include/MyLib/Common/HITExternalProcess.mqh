#ifndef HIT_EXTERNAL_PROCESS_MQH
#define HIT_EXTERNAL_PROCESS_MQH

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
/**
 * @brief パス内の最後のディレクトリ区切り文字位置を返します。
 */
int LastPathSeparatorIndex(const string path)
  {
   for(int i = StringLen(path) - 1; i >= 0; i--)
     {
      int ch = StringGetCharacter(path, i);
      if(ch == 92 || ch == 47) // backslash or slash
         return i;
     }

   return -1;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
/**
 * @brief ファイルパスから親ディレクトリを返します。
 */
string ParentDirectory(const string path)
  {
   int index = LastPathSeparatorIndex(path);
   if(index <= 0)
      return "";

   return StringSubstr(path, 0, index);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
/**
 * @brief batファイルの位置からPythonアプリの作業ディレクトリを返します。
 */
string BatchWorkingDirectory(const string bat_file)
  {
   string bat_dir = ParentDirectory(bat_file);
   int length = StringLen(bat_dir);
   if(length >= 4 && StringSubstr(bat_dir, length - 4) == "\\bat")
      return StringSubstr(bat_dir, 0, length - 4);

   return bat_dir;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool StartBatchProcess(const string bat_file,
                       const string running_file,
                       const string label,
                       ExternalProcessState &process,
                       const string file_prefix)
  {
   STARTUPINFO_W startup_info = {};
   PROCESS_INFORMATION process_info = {};

   startup_info.cb = (uint)sizeof(startup_info);

   string cmd_exe = "C:\\Windows\\System32\\cmd.exe";
   string command_line = "\"" + cmd_exe + "\" /c \"\"" + bat_file + "\" \"" + file_prefix + "\"\"";
   string current_directory = BatchWorkingDirectory(bat_file);

   int created = CreateProcessW(
                    cmd_exe,
                    command_line,
                    0,
                    0,
                    0,
                    CREATE_NO_WINDOW,
                    0,
                    current_directory,
                    startup_info,
                    process_info
                 );

   if(created == 0 || process_info.hProcess == 0)
     {
      Print("[", label, "] CreateProcessW failed. file=", bat_file,
            " cwd=", current_directory, " err=", GetLastError());
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
   Print("[", label, "] process started. pid=", process.process_id,
         " file=", bat_file, " cwd=", current_directory, " prefix=", file_prefix);
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


#endif
