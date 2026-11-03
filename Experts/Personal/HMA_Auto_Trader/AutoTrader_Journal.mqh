//+------------------------------------------------------------------+
//| AutoTrader_Journal.mqh  (V1.93)                                   |
//| CSV journal + screenshots (GDI+ JPG live, ChartScreenShot PNG in  |
//| tester, copied to the terminal MQL5\Files folder).                |
//| Include it in the EA at the old "Trade log" position, AFTER the   |
//| globals (g_ps, g_lines, g_trade) and the PFX_* defines.           |
//+------------------------------------------------------------------+
#property strict

input group "Screenshots (GDI+ JPG)"
input bool   InpShotEnable         = true;          // Screenshots master switch
input bool   InpShotOnEntry        = true;          // Shot on every entry (auto, DD, manual)
input bool   InpShotOnSL           = true;          // Shot on SL hit (never after break-even)
input bool   InpShotSkipSurvival   = true;          // No SL shot for survival-group trades
input bool   InpShotCleanChart     = true;          // Hide partials, panel, labels, other objects while shooting
input bool   InpShotUsePrintWindow = false;         // Use PrintWindow instead of BitBlt
input int    InpShotQuality        = 90;            // JPG quality 1-100
input string InpShotFolder         = "Screenshots"; // Folder under MQL5/Files
input string InpShotTesterDir      = "";            // Tester output override (empty = Terminal\<id>\MQL5\Files)

#import "user32.dll"
int   GetClientRect(ulong hWnd, int &rc[]);
ulong GetDC(ulong hWnd);
int   ReleaseDC(ulong hWnd, ulong hDC);
int   PrintWindow(ulong hWnd, ulong hdcBlt, uint nFlags);
#import "gdi32.dll"
ulong CreateCompatibleDC(ulong hdc);
ulong CreateCompatibleBitmap(ulong hdc, int w, int h);
ulong SelectObject(ulong hdc, ulong h);
int   BitBlt(ulong hdcDest, int x, int y, int w, int h, ulong hdcSrc, int xSrc, int ySrc, uint rop);
int   DeleteObject(ulong h);
int   DeleteDC(ulong hdc);
#import "gdiplus.dll"
int   GdiplusStartup(ulong &token, ulong &si[], ulong outp);
void  GdiplusShutdown(ulong token);
int   GdipCreateBitmapFromHBITMAP(ulong hbm, ulong hpal, ulong &bmp);
int   GdipSaveImageToFile(ulong img, string file, ulong &clsid[], ulong &ep[]);
int   GdipDisposeImage(ulong img);
#import "kernel32.dll"
ulong LocalAlloc(uint flags, ulong bytes);
ulong LocalFree(ulong h);
void  RtlMoveMemory(ulong dst, uint &src, ulong n);
int   CopyFileW(string src, string dst, int failIfExists);
int   CreateDirectoryW(string path, ulong sec);
#import

ulong  g_gdipToken = 0;
bool   g_gdipOk = false, g_gdipTried = false;
string g_shotQ[];
long   g_survPos[];

bool ShotInit()
{
   if(g_gdipOk) return true;
   if(g_gdipTried) return false;
   g_gdipTried = true;
   ulong si[3]; si[0] = 1; si[1] = 0; si[2] = 0;
   ulong tok = 0;
   const int st = GdiplusStartup(tok, si, 0);
   if(st != 0) { PrintFormat("Screenshot: GdiplusStartup failed (%d).", st); return false; }
   g_gdipToken = tok;
   g_gdipOk = true;
   return true;
}

void ShotShutdown()
{
   if(g_gdipOk) GdiplusShutdown(g_gdipToken);
   g_gdipOk = false; g_gdipTried = false; g_gdipToken = 0;
}

void ShotMarkSurvival(const long posId)
{
   for(int i = 0; i < ArraySize(g_survPos); i++) if(g_survPos[i] == posId) return;
   if(ArraySize(g_survPos) > 500) ArrayResize(g_survPos, 0);
   const int n = ArraySize(g_survPos);
   ArrayResize(g_survPos, n + 1);
   g_survPos[n] = posId;
}

string CsvQ(string s)
{
   StringReplace(s, "\"", "\"\"");
   return "\"" + s + "\"";
}

string ShotBaseDir()
{
   if(!MQLInfoInteger(MQL_TESTER)) return TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files";
   if(StringLen(InpShotTesterDir) > 0) return InpShotTesterDir;
   const string a = TerminalInfoString(TERMINAL_DATA_PATH);
   const int t = StringFind(a, "\\Tester\\");
   if(t < 0) return a + "\\MQL5\\Files";
   const string rest = StringSubstr(a, t + 8);
   const int s = StringFind(rest, "\\");
   const string id = (s > 0) ? StringSubstr(rest, 0, s) : rest;
   return StringSubstr(a, 0, t) + "\\Terminal\\" + id + "\\MQL5\\Files";
}

string JournalFileName() { return "AutoTraderJournal_" + _Symbol + "_" + IntegerToString(InpMagic) + ".csv"; }

void ShotMirrorCsv()
{
   if(!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION) || !InpTradeLog) return;
   const string src = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\" + JournalFileName();
   const string dst = ShotBaseDir() + "\\" + JournalFileName();
   if(src == dst) return;
   if(CopyFileW(src, dst, 0) == 0) Print("CSV mirror failed: ", src, " -> ", dst);
   else Print("CSV copied to ", dst);
}

string ShotRelDir() { return InpShotFolder + "\\" + _Symbol + "_" + IntegerToString(InpMagic); }

string ShotMakePath(const string tag, const string side, const long pid)
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   const string ext = MQLInfoInteger(MQL_TESTER) ? "png" : "jpg";
   const string f = StringFormat("%04d%02d%02d_%02d%02d%02d_%s_%s_%I64d.%s",
                                 dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec, tag, side, pid, ext);
   return ShotBaseDir() + "\\" + ShotRelDir() + "\\" + f;
}

string ShotRequest(const string tag, const string side, const long pid)
{
   if(!InpShotEnable || MQLInfoInteger(MQL_OPTIMIZATION)) return "";
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return "";
   FolderCreate(InpShotFolder);
   FolderCreate(ShotRelDir());
   if(MQLInfoInteger(MQL_TESTER)) {
      CreateDirectoryW(ShotBaseDir() + "\\" + InpShotFolder, 0);
      CreateDirectoryW(ShotBaseDir() + "\\" + ShotRelDir(), 0);
   }
   const string p = ShotMakePath(tag, side, pid);
   const int n = ArraySize(g_shotQ);
   ArrayResize(g_shotQ, n + 1);
   g_shotQ[n] = p;
   return p;
}

bool ShotGrabTester(const string absPath)
{
   int p = StringLen(absPath) - 1;
   while(p >= 0 && StringGetCharacter(absPath, p) != '\\') p--;
   const string rel = ShotRelDir() + "\\" + StringSubstr(absPath, p + 1);

   if(!ChartScreenShot(0, rel, (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS),
                       (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS), ALIGN_RIGHT)) {
      PrintFormat("Screenshot (tester): ChartScreenShot failed, error %d.", GetLastError());
      return false;
   }
   for(int k = 0; k < 40 && !FileIsExist(rel); k++) Sleep(50);
   if(!FileIsExist(rel)) { Print("Screenshot (tester): capture not found in agent folder: ", rel); return false; }

   const string src = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\" + rel;
   if(src == absPath) return true;
   if(CopyFileW(src, absPath, 0) == 0) { Print("Screenshot (tester): copy failed ", src, " -> ", absPath); return false; }
   return true;
}

bool ShotGrab(const string absPath)
{
   if(MQLInfoInteger(MQL_TESTER)) return ShotGrabTester(absPath);
   if(!ShotInit()) return false;
   const ulong hwnd = (ulong)ChartGetInteger(0, CHART_WINDOW_HANDLE);
   int rc[4]; ArrayInitialize(rc, 0);
   bool ok = false;
   string why = "";

   if(hwnd == 0) why = "CHART_WINDOW_HANDLE = 0";
   else if(GetClientRect(hwnd, rc) == 0) why = "GetClientRect failed";
   else {
      const int w = rc[2] - rc[0], h = rc[3] - rc[1];
      if(w < 50 || h < 50) why = StringFormat("window size %dx%d (minimized?)", w, h);
      else {
         const ulong hdc = GetDC(hwnd);
         if(hdc == 0) why = "GetDC failed";
         else {
            const ulong mem = CreateCompatibleDC(hdc);
            const ulong bmp = CreateCompatibleBitmap(hdc, w, h);
            const ulong old = SelectObject(mem, bmp);
            const bool cap = InpShotUsePrintWindow ? (PrintWindow(hwnd, mem, 2) != 0)
                                                   : (BitBlt(mem, 0, 0, w, h, hdc, 0, 0, 0x40CC0020) != 0);
            if(!cap) why = "BitBlt/PrintWindow failed";
            else {
               ulong img = 0;
               const int s1 = GdipCreateBitmapFromHBITMAP(bmp, 0, img);
               if(s1 != 0 || img == 0) why = StringFormat("GdipCreateBitmapFromHBITMAP status %d", s1);
               else {
                  ulong clsid[2];
                  clsid[0] = 0x11D31A04557CF401;
                  clsid[1] = 0x2EF31EF80000739A;
                  uint q = (uint)MathMax(1, MathMin(100, InpShotQuality));
                  const ulong pq = LocalAlloc(0x40, 8);
                  ulong ep[5];
                  ep[0] = 1;
                  ep[1] = 0x452DFA4A1D5BE4B5;
                  ep[2] = 0xEBE70551B35DDD9C;
                  ep[3] = (ulong)1 | ((ulong)4 << 32);
                  ep[4] = pq;
                  RtlMoveMemory(pq, q, 4);
                  const int s2 = GdipSaveImageToFile(img, absPath, clsid, ep);
                  if(s2 != 0) why = StringFormat("GdipSaveImageToFile status %d", s2);
                  else ok = true;
                  LocalFree(pq);
                  GdipDisposeImage(img);
               }
            }
            SelectObject(mem, old);
            DeleteObject(bmp);
            DeleteDC(mem);
            ReleaseDC(hwnd, hdc);
         }
      }
   }
   if(!ok) PrintFormat("Screenshot GDI step failed: %s (hwnd=%I64u)", why, hwnd);
   return ok;
}

void ShotProcess()
{
   if(ArraySize(g_shotQ) == 0) return;
   string names[]; long tfs[]; int hc = 0;
   long lvl = -1;
   if(InpShotCleanChart) {
      for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--) {
         const string nm = ObjectName(0, i, -1, -1);
         if(StringFind(nm, PFX_MA) == 0 || StringFind(nm, PFX_LN) == 0) continue;
         const long tf = ObjectGetInteger(0, nm, OBJPROP_TIMEFRAMES);
         if(tf == OBJ_NO_PERIODS) continue;
         ArrayResize(names, hc + 1); ArrayResize(tfs, hc + 1);
         names[hc] = nm; tfs[hc] = tf; hc++;
         ObjectSetInteger(0, nm, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      }
      lvl = ChartGetInteger(0, CHART_SHOW_TRADE_LEVELS);
      ChartSetInteger(0, CHART_SHOW_TRADE_LEVELS, false);
   }
   ChartRedraw(0);
   Sleep(200);

   for(int k = 0; k < ArraySize(g_shotQ); k++) {
      const bool ok = ShotGrab(g_shotQ[k]);
      PrintFormat("Screenshot %s: %s", ok ? "saved" : "FAILED", g_shotQ[k]);
   }
   ArrayResize(g_shotQ, 0);

   for(int i = 0; i < hc; i++) ObjectSetInteger(0, names[i], OBJPROP_TIMEFRAMES, tfs[i]);
   if(lvl >= 0) ChartSetInteger(0, CHART_SHOW_TRADE_LEVELS, lvl != 0);
   ChartRedraw(0);
}

bool ShotExitWanted(const ulong dk, const long pid, const bool wasBuy)
{
   if(!InpShotEnable || !InpShotOnSL) return false;
   if((ENUM_DEAL_REASON)HistoryDealGetInteger(dk, DEAL_REASON) != DEAL_REASON_SL) return false;
   const double px = HistoryDealGetDouble(dk, DEAL_PRICE);
   double entry = 0.0; bool be = false;
   for(int i = 0; i < ArraySize(g_ps); i++)
      if(g_ps[i].posId == pid) { entry = g_ps[i].entry; be = g_ps[i].beDone; break; }
   if(be) return false;
   if(entry > 0.0 && (wasBuy ? px >= entry : px <= entry)) return false;
   if(entry <= 0.0 && HistoryDealGetDouble(dk, DEAL_PROFIT) >= 0.0) return false;
   if(InpShotSkipSurvival)
      for(int i = 0; i < ArraySize(g_survPos); i++) if(g_survPos[i] == pid) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Trade journal (CSV)                                               |
//+------------------------------------------------------------------+
void LogRow(const string line)
{
   if(!InpTradeLog || MQLInfoInteger(MQL_OPTIMIZATION)) return;
   const int h = FileOpen(JournalFileName(), FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE) return;
   if(FileSize(h) == 0) FileWriteString(h, "event,time,position_id,side,kind,score,line,price,sl,tp,spread_pts,hour,profit,exit_reason,entry_reason,screenshot_path\r\n");
   FileSeek(h, 0, SEEK_END);
   FileWriteString(h, line + "\r\n");
   FileClose(h);
}

void JournalEntry(const bool buy, const string kind, const double score, const string linePx,
                  const string why, const double price, const double sl, const double tp)
{
   long pid = 0;
   const ulong deal = g_trade.ResultDeal();
   if(deal > 0 && HistoryDealSelect(deal)) pid = HistoryDealGetInteger(deal, DEAL_POSITION_ID);
   const string side = buy ? "BUY" : "SELL";
   string path = "";
   if(InpShotOnEntry) path = ShotRequest("ENTRY", side, pid);
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   const double spr = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
   LogRow(StringFormat("ENTRY,%s,%I64d,%s,%s,%.1f,%s,%s,%s,%s,%.0f,%d,,,%s,%s",
          TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), pid, side, kind, score, linePx,
          DoubleToString(price, _Digits), DoubleToString(sl, _Digits), DoubleToString(tp, _Digits),
          spr, dt.hour, CsvQ(why), CsvQ(path)));
}

void LogEntry(const bool buy, const int j, const string why, const double price, const double sl, const double tp)
{
   JournalEntry(buy, (StringFind(why, "FALSE BREAK") == 0) ? "FALSE_BREAK" : "REJECTION",
                g_lines[j].lastScore, DoubleToString(g_lines[j].price, _Digits), why, price, sl, tp);
}

void LogExitDeal(const ulong dk)
{
   if(dk == 0 || !HistoryDealSelect(dk)) return;
   if(HistoryDealGetString(dk, DEAL_SYMBOL) != _Symbol || HistoryDealGetInteger(dk, DEAL_MAGIC) != InpMagic) return;
   const ENUM_DEAL_ENTRY e = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dk, DEAL_ENTRY);
   if(e != DEAL_ENTRY_OUT && e != DEAL_ENTRY_OUT_BY) return;
   const ENUM_DEAL_REASON rs = (ENUM_DEAL_REASON)HistoryDealGetInteger(dk, DEAL_REASON);
   const string rtxt = (rs == DEAL_REASON_SL) ? "SL" : (rs == DEAL_REASON_TP) ? "TP" : (rs == DEAL_REASON_CLIENT || rs == DEAL_REASON_EXPERT) ? "EA_OR_MANUAL" : "OTHER";
   const double pnl = HistoryDealGetDouble(dk, DEAL_PROFIT) + HistoryDealGetDouble(dk, DEAL_SWAP) + HistoryDealGetDouble(dk, DEAL_COMMISSION);
   const bool wasBuy = ((ENUM_DEAL_TYPE)HistoryDealGetInteger(dk, DEAL_TYPE) == DEAL_TYPE_SELL);
   const long pid = HistoryDealGetInteger(dk, DEAL_POSITION_ID);
   const double dpx = HistoryDealGetDouble(dk, DEAL_PRICE);
   const datetime dtm = (datetime)HistoryDealGetInteger(dk, DEAL_TIME);

   string path = "";
   if(ShotExitWanted(dk, pid, wasBuy)) path = ShotRequest("SL", wasBuy ? "BUY" : "SELL", pid);

   LogRow(StringFormat("EXIT,%s,%I64d,%s,,,,%s,,,,,%.2f,%s,,%s",
          TimeToString(dtm, TIME_DATE | TIME_SECONDS), pid, wasBuy ? "BUY" : "SELL",
          DoubleToString(dpx, _Digits), pnl, rtxt, CsvQ(path)));
}
