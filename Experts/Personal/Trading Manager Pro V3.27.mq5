//+------------------------------------------------------------------+
//|                                       TradeManager_v3.27.mq5       |
//|   Riy Tech — External trade adoption + per-position BE/Close     |
//|   v3.27 — Enhanced broker-proof exit detection & v3.27 upgrade   |
//+------------------------------------------------------------------+
#property copyright "Riy Tech"
#property version   "3.27"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| Windows GDI+ and Kernel32 API Imports (For JPEG Compression)     |
//+------------------------------------------------------------------+
#import "gdiplus.dll"
int GdiplusStartup(ulong &token, uchar &gdiInput[], ulong gdiOutput);
void GdiplusShutdown(ulong token);
int GdipLoadImageFromFile(string filename, ulong &image);
int GdipDisposeImage(ulong image);
int GdipSaveImageToFile(ulong image, string filename, uchar &clsid[], uchar &encoderParams[]);
#import

#import "ole32.dll"
int CLSIDFromString(string lpsz, uchar &pclsid[]);
#import

#import "kernel32.dll"
ulong GlobalAlloc(uint uFlags, ulong dwBytes);
ulong GlobalFree(ulong hMem);
void RtlMoveMemory(ulong dest, uint &src[], ulong length);
#import

// Helper to cast pointers in 64-bit memory
union ULongToBytes {
   ulong value;
   uchar bytes[8];
};

//+------------------------------------------------------------------+
//| INPUTS                                                            |
//+------------------------------------------------------------------+
input group "Panel Settings"
input ENUM_BASE_CORNER InpPanelCorner = CORNER_LEFT_UPPER;

input group "Risk Settings"
input double InpDefaultLot   = 0.3;   // Default Lot Size
input int    InpDefaultSL    = 500;   // Default SL (points)
input int    InpDefaultTP    = 1000;  // Default TP (points)

input group "Inverse Order Settings"
input int    InpInverseOffset = 50;   // Inverse Pending Offset (points)

input group "Auto Risk Settings"
input int    InpAutoRiskPartials = 2; // Auto Risk / SL Partials max count

input group "Daily Limits"
input bool   InpEnableDailyLossLimit = true;
input int    InpMaxDailyLosingTrades = 3;

input group "Partial Settings"
input double InpMainPartialVol    = 40.0;
input double InpRollingPartialVol = 20.0;
input int    InpDefaultPartial    = 3;

input group "Breakeven Settings"
input int    InpBE_Trigger = 1;
input int    InpBE_Offset  = 20;

input group "Trailing Stop Settings"
input bool   InpUseTrailingStop = true;
input int    InpTrailingStart   = 1000;
input int    InpTrailingStep    = 600;

input group "Sound Settings"
input bool   InpEnableSounds = true;
input string InpSoundEntry      = "Ok.wav";
input string InpSoundOk         = "Ok.wav";
input string InpSoundPartial    = "News.wav";
input string InpSoundBE         = "Expert.wav";
input string InpSoundSL         = "timeout.wav";
input string InpSoundTP         = "alert.wav";
input string InpSoundClose      = "stops.wav";

input group "External Trade Monitoring"
input bool   InpMonitorExternal   = true;   // Monitor trades opened outside this EA?
input bool   InpExternalAlerts    = true;   // Alert when external trade detected?
input string InpSoundExtDetected  = "notify.wav";
input bool   InpAutoAdoptExternal = true;   // Auto-apply default SL/TP to external trades missing them
input bool   InpOverwriteExtSLTP  = false;  // If true, overwrite existing SL/TP too (default: only fill missing)

input group "Trade Limits"
input int    InpMaxOpenTrades = 10;

input group "Auto Trade Handler"
input bool   InpBasketEnabled     = true;
input int    InpBasketGreenPoints = 0;

input group "Journaling Settings"
input bool   InpEnableJournaling = true;
input string InpWebhookURL       = "https://your-webhook-url.com/endpoint";
input string APP_SHORT_NAME      = "TM3_Pro";
input int    InpMagicNumber      = 234567;
input int    InpImageQuality     = 30; // Compressed GDI+ JPEG Quality

//--- Add to Globals ---
double g_cached_sl[];
double g_cached_tp[];

//+------------------------------------------------------------------+
//| CONSTANTS                                                         |
//+------------------------------------------------------------------+
#define MAGIC       234567
#define COLOR_BG    C'35,35,35'
#define COLOR_BTN   C'60,60,60'
#define COLOR_ACT   C'0,120,215'
#define COLOR_BUY   C'46,204,113'
#define COLOR_SELL  C'231,76,60'
#define COLOR_TEXT  clrWhite
#define COLOR_EDIT  C'50,50,50'
#define PANEL_W     230
#define ROW_H       25
#define PAD         5
#define POS_ROW_H   22

//+------------------------------------------------------------------+
//| ENUMS & STRUCTS                                                    |
//+------------------------------------------------------------------+
enum ENUM_ORDER_TYPE_UI { UI_MARKET, UI_LIMIT };
enum ENUM_SIDE_UI       { UI_BUY, UI_SELL };

struct UIState
{
   ENUM_ORDER_TYPE_UI orderType;
   ENUM_SIDE_UI       side;
   double lotSize;
   int    slPoints;
   int    tpPoints;
   double slPrice;
   double tpPrice;
   int    partialsCount;
   double customPrice;
   bool   isVisualizing;
   bool   basketEnabled;
   bool   inverseEnabled;
   bool   autoRiskEnabled;
};

struct ExtTradeRec { ulong ticket; long posID; bool alertSent; bool adopted; };

struct PosState
{
   long   posID;
   ulong  ticket;
   int    partialsTaken;
   int    slPartialsTaken;
   bool   beSet;
   double lastSL;
   double lastTP;
};

//--- Journaling Queue System ---
struct JournalTask
{
   datetime trigger_time;
   string   event_name;
   ulong    ticket;
   string   symbol;
   string   side;
   double   volume;
   double   price;
   double   sl;
   double   tp;
   double   profit;
   string   note;
   string   source;
};

JournalTask g_JournalQueue[];

//+------------------------------------------------------------------+
//| GLOBALS                                                            |
//+------------------------------------------------------------------+
string        g_prefix;
UIState       ui;
CTrade        trade;
CPositionInfo posInfo;
int           g_ChartW = 0;
int           g_ChartH = 0;
datetime      g_LastExtScan = 0;
int           g_BasketPts = 0;
ExtTradeRec   g_ExtTrades[];
PosState      g_PosStates[];
int           g_PosListX = 0;
int           g_PosListY = 0;
ulong         g_SelectedTicket = 0;
bool          g_HasOpenTrades = false;

//+------------------------------------------------------------------+
//| FORWARD DECLARATIONS                                              |
//+------------------------------------------------------------------+
void   RecomputeHasOpenTrades();
void   SaveState();
void   LoadState();
void   ClearState();
void   RebuildPanel(bool updateUI = false);
void   CreatePanelElements(int x, int y);
void   UpdatePanelUI();
void   UpdateSLTPPrices(double entry);
void   UpdateStats(double priceRef);
void   UpdatePartialLine(int x, int y);
int    PanelHeight();
void   ToggleVisualization();
void   DrawVisualization();
void   DrawSideVis(double ep, ENUM_SIDE_UI side);
void   ExecuteOrder();
void   ManualPartial();
void   CycleSelectedTrade(int direction);
void   ValidateSelectedTicket();
void   CloseSelectedTrade();
int    BuildManagedTicketList(ulong &list[]);
void   UpdateSelectedTradeLabel();
ulong  GetManagedTicketByOffset(int offset);
int    FindManagedTicketIndex(ulong ticket);
void   CloseAll();
void   SetBreakEvenManual();
void   SetBreakEvenTicket(ulong ticket);
void   CloseTicket(ulong ticket);
bool   IsDailyLossLimitReached();
void   ManagePositions();
void   ManageTrailingStop();
void   ScanExternalTrades();
void   AdoptExternalTrade(ulong ticket);
void   ManageDrawdownBasket();
void   ProcessBasketByType(ENUM_POSITION_TYPE type);
void   CleanupOrphanedLines();
void   SyncPosStates();
void   RemovePosState(long posID);
bool   IsRegisteredExternal(ulong ticket);
void   RemoveClosedExternals();
bool   IsManagedPosition();
int    CountManagedOpenPositions();
double NormaliseSL(double price);
void   ToggleBasket();
void   DrawPositionList(int x, int y);
void   RefreshPositionList();
int    PositionListHeight();
void   ExportToCSV();
void   Btn (string n, int x, int y, int w, int h, string t, bool act, color b = COLOR_BTN);
void   Rect(string n, int x, int y, int w, int h, color bg);
void   Edit(string n, int x, int y, int w, int h, string t);
void   Lbl (string n, int x, int y, string t);
void   Line(string sfx, double price, color col, ENUM_LINE_STYLE st, int wd, string lbl = "");
string TakeCleanScreenshot(ulong ticket, string event_name);
string BuildJSON(string event_name, ulong ticket, string symbol, string side, double volume, double price, double sl, double tp, double profit, string note, string source, string screenshot_file);
bool   SendJournalWebhook(const string event_name, const ulong ticket, const string symbol, const string side, const double volume, const double price, const double sl, const double tp, const double profit, const string note, const string source, const string screenshot_file);
string BuildMultipartBoundary();
bool   ReadScreenshotFileToArray(const string file_name, uchar &data[]);
void   CharArrayAppendString(char &body[], const string text);
void   CharArrayAppendBytes(char &body[], const uchar &data[]);
bool   CompressJPEG(string inputFile, string outputFile, uint qualityLevel);
void   JournalEvent(string event_name, ulong ticket, string symbol, string side, double volume, double price, double sl, double tp, double profit, string note, string source);
void   ProcessJournalEvent(string event_name, ulong ticket, string symbol, string side, double volume, double price, double sl, double tp, double profit, string note, string source);

//+------------------------------------------------------------------+
//| INIT / DEINIT                                                      |
//+------------------------------------------------------------------+
int OnInit()
{
   g_prefix = "TM3_" + IntegerToString(ChartID()) + "_";
   ui.orderType = UI_MARKET;
   ui.side = UI_BUY;
   ui.lotSize = InpDefaultLot;
   ui.slPoints = InpDefaultSL;
   ui.tpPoints = InpDefaultTP;
   ui.partialsCount = InpDefaultPartial;
   ui.isVisualizing = false;
   ui.basketEnabled = InpBasketEnabled;
   ui.customPrice = 0;
   g_BasketPts = InpBasketGreenPoints;

   LoadState();
   trade.SetExpertMagicNumber(MAGIC);
   SyncPosStates();

   RecomputeHasOpenTrades();
   RebuildPanel(true);
   UpdateSLTPPrices(SymbolInfoDouble(_Symbol, SYMBOL_ASK));

   PrintFormat("[TM3 v3.27] Ready | BE after Partial#%d (+%dpts) | Trailing=%s | AutoAdoptExternal=%s",
               InpBE_Trigger, InpBE_Offset, InpUseTrailingStop ? "ON" : "OFF", InpAutoAdoptExternal ? "ON" : "OFF");
   EventSetTimer(1);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(reason == REASON_CHARTCHANGE || reason == REASON_RECOMPILE || reason == REASON_CLOSE)
      SaveState();
   else if(reason == REASON_REMOVE)
      ClearState();

   ObjectsDeleteAll(0, g_prefix);
   ArrayFree(g_ExtTrades);
   ArrayFree(g_PosStates);
   EventKillTimer();
}

//+------------------------------------------------------------------+
//| ON TRADE TRANSACTION                                             |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                         const MqlTradeRequest &request,
                         const MqlTradeResult &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      RecomputeHasOpenTrades();
      
      ulong ticket = trans.position;
      if(HistoryDealSelect(trans.deal))
      {
         long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
         string symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
         long type = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
         double vol = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
         double price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
         
         // Event 1: OPEN (Screenshot Taken)
         if(entry == DEAL_ENTRY_IN)
         {
            string side = (type == DEAL_TYPE_BUY) ? "BUY" : "SELL";
            JournalEvent("OPEN", ticket, symbol, side, vol, price, 0, 0, 0, "Trade Opened", "System");
         }
         // Events 2, 3, 4, etc: OUT Deals
         else if(entry == DEAL_ENTRY_OUT)
         {
            string actual_side = (type == DEAL_TYPE_SELL) ? "BUY" : "SELL";
            double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION) + HistoryDealGetDouble(trans.deal, DEAL_SWAP);
            long reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
            
            string event_type = "";
            
            if(PositionSelectByTicket(ticket)) 
            {
               event_type = "PARTIAL";
            }
            else
            {
               ulong order_ticket = HistoryDealGetInteger(trans.deal, DEAL_ORDER);
               double order_sl = 0;
               double order_tp = 0;
               if(HistoryOrderSelect(order_ticket))
               {
                  order_sl = HistoryOrderGetDouble(order_ticket, ORDER_SL);
                  order_tp = HistoryOrderGetDouble(order_ticket, ORDER_TP);
               }
               
               bool is_sl_hit = (reason == DEAL_REASON_SL);
               bool is_tp_hit = (reason == DEAL_REASON_TP);
               
               if(!is_sl_hit && !is_tp_hit)
               {
                  if(order_sl > 0)
                  {
                     if(actual_side == "BUY" && price <= order_sl) is_sl_hit = true;
                     if(actual_side == "SELL" && price >= order_sl) is_sl_hit = true;
                  }
                  if(order_tp > 0)
                  {
                     if(actual_side == "BUY" && price >= order_tp) is_tp_hit = true;
                     if(actual_side == "SELL" && price <= order_tp) is_tp_hit = true;
                  }
               }

               if(is_sl_hit)
               {
                  if(profit < 0) event_type = "SL_Hit";
                  else event_type = "BE_Hit";
               }
               else if(is_tp_hit)
               {
                  event_type = "TP_Hit";
               }
               else 
               {
                  event_type = "Manually_Closed";
               }
            }
            
            JournalEvent(event_type, ticket, symbol, actual_side, vol, price, 0, 0, profit, "Position Exit", "System");
         }
      }
   }
   else if(trans.type == TRADE_TRANSACTION_POSITION)
   {
      RecomputeHasOpenTrades();
   }
}

void RecomputeHasOpenTrades()
{
   g_HasOpenTrades = (PositionsTotal() > 0);
}

//+------------------------------------------------------------------+
//| ON TICK                                                            |
//+------------------------------------------------------------------+
void OnTick()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   static double lastBid = 0, lastAsk = 0;
   static ulong  lastUITick = 0;
   ulong nowMs = GetTickCount();

   if(nowMs - lastUITick >= 250)
   {
      if(MathAbs(bid - lastBid) >= _Point || MathAbs(ask - lastAsk) >= _Point)
      {
         lastBid = bid;
         lastAsk = ask;
         lastUITick = nowMs;

         double curr = (ui.side == UI_BUY) ? ask : bid;

         if(ui.orderType == UI_MARKET)
         {
            if(ObjectFind(0, g_prefix + "Edit_Price") >= 0)
               ObjectSetString(0, g_prefix + "Edit_Price", OBJPROP_TEXT, DoubleToString(curr, _Digits));
            UpdateSLTPPrices(curr);
            if(ui.isVisualizing) DrawVisualization();
         }
         else
         {
            UpdateSLTPPrices(ui.customPrice);
         }

         double ref = (ui.orderType == UI_LIMIT) ? ui.customPrice : curr;
         UpdateStats(ref);
      }
   }

   if(g_HasOpenTrades)
   {
      ScanExternalTrades();
      ManagePositions();
      ManageTrailingStop();
      ManageDrawdownBasket();
   }
   else if(InpMonitorExternal)
   {
      ScanExternalTrades();
   }

   static ulong lastPosListMs = 0;
   static bool wasFlat = true;
   if(nowMs - lastPosListMs >= 500)
   {
      lastPosListMs = nowMs;

      if(!g_HasOpenTrades)
      {
         if(!wasFlat)
         {
            g_SelectedTicket = 0;
            ArrayResize(g_ManagedTickets, 0);
            RebuildPanel(false);
            wasFlat = true;
         }
      }
      else
      {
         wasFlat = false;
         int newHeight = PanelHeight();
         static int lastPanelHeight = -1;
         if(newHeight != lastPanelHeight)
         {
            lastPanelHeight = newHeight;
            RebuildPanel(false);
         }
         else
         {
            RefreshPositionList();
         }
      }
   }

   static datetime lastCleanup = 0;
   if(TimeCurrent() - lastCleanup >= 3)
   {
      CleanupOrphanedLines();
      lastCleanup = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| BACKGROUND TIMER FOR ASYNCHRONOUS QUEUE                          |
//+------------------------------------------------------------------+
void OnTimer()
{
   int n = ArraySize(g_JournalQueue);
   if(n == 0) return;
   
   datetime now = TimeCurrent();
   
   if(now >= g_JournalQueue[0].trigger_time)
   {
      ProcessJournalEvent(
         g_JournalQueue[0].event_name, g_JournalQueue[0].ticket, g_JournalQueue[0].symbol, 
         g_JournalQueue[0].side, g_JournalQueue[0].volume, g_JournalQueue[0].price, 
         g_JournalQueue[0].sl, g_JournalQueue[0].tp, g_JournalQueue[0].profit, 
         g_JournalQueue[0].note, g_JournalQueue[0].source
      );
                   
      for(int i = 0; i < n - 1; i++)
      {
         g_JournalQueue[i] = g_JournalQueue[i + 1];
      }
      ArrayResize(g_JournalQueue, n - 1);
   }
}

//+------------------------------------------------------------------+
//| CHART EVENTS                                                       |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lp, const double &dp, const string &sp)
{
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      int w = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
      int h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
      if(w != g_ChartW || h != g_ChartH)
      {
         g_ChartW = w; g_ChartH = h;
         RebuildPanel(false);
      }
      return;
   }

   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sp == g_prefix + "Btn_Mkt") { ui.orderType = UI_MARKET; UpdatePanelUI(); SaveState(); }
      if(sp == g_prefix + "Btn_Lim")
      {
         ui.orderType = UI_LIMIT;
         ui.customPrice = (ui.side == UI_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
         ObjectSetString(0, g_prefix + "Edit_Price", OBJPROP_TEXT, DoubleToString(ui.customPrice, _Digits));
         UpdatePanelUI(); SaveState();
      }
      if(sp == g_prefix + "Btn_Buy")  { ui.side = UI_BUY;  UpdatePanelUI(); ExecuteOrder(); SaveState(); }
      if(sp == g_prefix + "Btn_Sell") { ui.side = UI_SELL; UpdatePanelUI(); ExecuteOrder(); SaveState(); }
      if(sp == g_prefix + "Btn_Vis")  { ToggleVisualization(); }
      if(sp == g_prefix + "Btn_Part") { ManualPartial(); }
      if(sp == g_prefix + "Btn_BE")   { SetBreakEvenManual(); }
      if(sp == g_prefix + "Btn_CloseAll") { CloseAll(); }
      if(sp == g_prefix + "Btn_Export")   { ExportToCSV(); }
      if(sp == g_prefix + "Btn_Inverse")  { ui.inverseEnabled = !ui.inverseEnabled; UpdatePanelUI(); SaveState(); }
      if(sp == g_prefix + "Btn_AutoRisk") { ui.autoRiskEnabled = !ui.autoRiskEnabled; UpdatePanelUI(); SaveState(); }
      if(sp == g_prefix + "Btn_Basket")   { ToggleBasket(); }
      if(sp == g_prefix + "Btn_SelPrev")  { CycleSelectedTrade(-1); }
      if(sp == g_prefix + "Btn_SelNext")  { CycleSelectedTrade(1); }
      if(sp == g_prefix + "Btn_CloseSel") { CloseSelectedTrade(); }
   }

   if(id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      double entry = (ui.orderType == UI_LIMIT) ? ui.customPrice : ((ui.side == UI_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID));
      if(sp == g_prefix + "Edit_Lot") ui.lotSize = StringToDouble(ObjectGetString(0, sp, OBJPROP_TEXT));
      if(sp == g_prefix + "Edit_Part")
      {
         ui.partialsCount = (int)StringToInteger(ObjectGetString(0, sp, OBJPROP_TEXT));
         RebuildPanel(true);
      }
      if(sp == g_prefix + "Edit_Price" && ui.orderType == UI_LIMIT)
      {
         ui.customPrice = StringToDouble(ObjectGetString(0, sp, OBJPROP_TEXT));
         entry = ui.customPrice;
         if(ui.isVisualizing) DrawVisualization();
      }
      if(sp == g_prefix + "Edit_SL")
      {
         ui.slPoints = (int)StringToInteger(ObjectGetString(0, sp, OBJPROP_TEXT));
         UpdateSLTPPrices(entry);
      }
      if(sp == g_prefix + "Edit_TP")
      {
         ui.tpPoints = (int)StringToInteger(ObjectGetString(0, sp, OBJPROP_TEXT));
         UpdateSLTPPrices(entry);
         RebuildPanel(true);
      }
      if(sp == g_prefix + "Edit_SL_Prc")
      {
         double p = StringToDouble(ObjectGetString(0, sp, OBJPROP_TEXT));
         if(entry > 0) { ui.slPoints = (int)MathAbs((entry - p) / _Point); ObjectSetString(0, g_prefix + "Edit_SL", OBJPROP_TEXT, IntegerToString(ui.slPoints)); }
      }
      if(sp == g_prefix + "Edit_TP_Prc")
      {
         double p = StringToDouble(ObjectGetString(0, sp, OBJPROP_TEXT));
         if(entry > 0) { ui.tpPoints = (int)MathAbs((entry - p) / _Point); ObjectSetString(0, g_prefix + "Edit_TP", OBJPROP_TEXT, IntegerToString(ui.tpPoints)); RebuildPanel(true); }
      }
      if(sp == g_prefix + "Edit_GreenPts") g_BasketPts = (int)StringToInteger(ObjectGetString(0, sp, OBJPROP_TEXT));

      if(ui.isVisualizing) DrawVisualization();
      UpdateStats(entry);
      SaveState();
   }
}

//+------------------------------------------------------------------+
//| POSITION STATE MANAGEMENT                                          |
//+------------------------------------------------------------------+
int FindPosStateIdx(long posID)
{
   for(int i = 0; i < ArraySize(g_PosStates); i++)
      if(g_PosStates[i].posID == posID) return i;
   return -1;
}

void EnsurePosState(long posID, ulong ticket)
{
   if(FindPosStateIdx(posID) >= 0) return;
   int n = ArraySize(g_PosStates);
   ArrayResize(g_PosStates, n + 1);
   g_PosStates[n].posID = posID;
   g_PosStates[n].ticket = ticket;
   g_PosStates[n].partialsTaken = 0;
   g_PosStates[n].slPartialsTaken = 0;
   g_PosStates[n].beSet = false;
   g_PosStates[n].lastSL = 0.0;
   g_PosStates[n].lastTP = 0.0;
}

void RemovePosState(long posID)
{
   int idx = FindPosStateIdx(posID);
   if(idx < 0) return;
   int n = ArraySize(g_PosStates);
   for(int i = idx; i < n - 1; i++)
      g_PosStates[i] = g_PosStates[i + 1];
   ArrayResize(g_PosStates, n - 1);
}

void SyncPosStates()
{
   ArrayFree(g_PosStates);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      bool isOwn = (posInfo.Magic() == MAGIC);
      bool isExt = InpMonitorExternal;
      if(!isOwn && !isExt) continue;

      long pid = posInfo.Identifier();
      ulong ticket = posInfo.Ticket();
      EnsurePosState(pid, ticket);

      int idx = FindPosStateIdx(pid);
      if(idx < 0) continue;
      if(HistorySelectByPosition(pid))
      {
         int cnt = 0;
         for(int d = 0; d < HistoryDealsTotal(); d++)
         {
            ulong dt = HistoryDealGetTicket(d);
            if(HistoryDealGetInteger(dt, DEAL_ENTRY) == DEAL_ENTRY_OUT)
               cnt++;
         }
         g_PosStates[idx].partialsTaken = cnt;
         if(InpBE_Trigger > 0 && cnt >= InpBE_Trigger)
            g_PosStates[idx].beSet = true;
      }
   }
}

void PurgeClosedPosStates()
{
   for(int i = ArraySize(g_PosStates) - 1; i >= 0; i--)
   {
      bool found = false;
      for(int j = PositionsTotal() - 1; j >= 0; j--)
      {
         if(posInfo.SelectByIndex(j) && posInfo.Identifier() == g_PosStates[i].posID)
         { found = true; break; }
      }
      if(!found) RemovePosState(g_PosStates[i].posID);
   }
}

//+------------------------------------------------------------------+
//| CORE: MANAGE POSITIONS                                             |
//+------------------------------------------------------------------+
void ManagePositions()
{
   static ulong lastMs = 0;
   ulong nowMs = (ulong)GetTickCount();
   if(nowMs - lastMs < 200) return;
   lastMs = nowMs;

   PurgeClosedPosStates();
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;

      bool isOwn = (posInfo.Magic() == MAGIC);
      bool isExt = InpMonitorExternal && IsRegisteredExternal(posInfo.Ticket());
      if(!isOwn && !isExt) continue;

      long   pid   = posInfo.Identifier();
      ulong  ticket = posInfo.Ticket();
      double open  = posInfo.PriceOpen();
      double tp    = posInfo.TakeProfit();
      double curSL = posInfo.StopLoss();
      double curTP = posInfo.TakeProfit();
      bool   isBuy = (posInfo.PositionType() == POSITION_TYPE_BUY);

      if(tp == 0.0) continue;

      double totalDist = MathAbs(tp - open);
      if(totalDist < _Point) continue;

      EnsurePosState(pid, ticket);
      int stIdx = FindPosStateIdx(pid);
      if(stIdx < 0) continue;

      if(g_PosStates[stIdx].lastSL != curSL)
      {
         if(g_PosStates[stIdx].lastSL != 0.0 && g_PosStates[stIdx].beSet==false) 
         {
            JournalEvent("SL_CHANGE", ticket, _Symbol, isBuy ? "BUY" : "SELL", posInfo.Volume(), open, curSL, curTP, 0, "SL Modified", "System");
         }
         g_PosStates[stIdx].lastSL = curSL;
      }
      
      if(g_PosStates[stIdx].lastTP != curTP)
      {
         if(g_PosStates[stIdx].lastTP != 0.0) 
         {
            JournalEvent("TP_CHANGE", ticket, _Symbol, isBuy ? "BUY" : "SELL", posInfo.Volume(), open, curSL, curTP, 0, "TP Modified", "System");
         }
         g_PosStates[stIdx].lastTP = curTP;
      }

      int totalPartials = ui.partialsCount;
      double step = totalDist / (totalPartials + 1);
      int taken = g_PosStates[stIdx].partialsTaken;
      bool beSet = g_PosStates[stIdx].beSet;

      double curr = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);

      for(int k = 1; k <= totalPartials; k++)
      {
         double lvl = isBuy ? open + step * k : open - step * k;
         string lnm = g_prefix + "P_" + IntegerToString((int)ticket) + "_" + IntegerToString(k);
         if(k <= taken)
         {
            if(ObjectFind(0, lnm) >= 0) ObjectDelete(0, lnm);
            continue;
         }
         Line("P_" + IntegerToString((int)ticket) + "_" + IntegerToString(k), lvl, clrGoldenrod, STYLE_DOT, 1, "");
      }

      int nextPartial = taken + 1;
      if(nextPartial > totalPartials) continue;

      double nextLvl = isBuy ? open + step * nextPartial : open - step * nextPartial;
      bool crossed = isBuy ? (curr >= nextLvl) : (curr <= nextLvl);
      if(!crossed) continue;

      double pct = (nextPartial == 1) ? InpMainPartialVol : InpRollingPartialVol;
      double amt = NormalizeDouble(posInfo.Volume() * (pct * 0.01), 2);
      double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      if(amt < minV) amt = minV;
      if(amt > posInfo.Volume()) amt = posInfo.Volume();

      if(!trade.PositionClosePartial(ticket, amt)) continue;

      g_PosStates[stIdx].partialsTaken = nextPartial;
      if(InpEnableSounds) PlaySound(InpSoundPartial);

      if(ui.autoRiskEnabled && curSL > 0)
      {
         double minV2 = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         double slDist = MathAbs(open - curSL);
         double slStep = slDist / 2.0;
         int slTaken = g_PosStates[stIdx].slPartialsTaken;
         int nextSLPartial = slTaken + 1;
         if(nextSLPartial <= 2)
         {
            double nextSLLvl = isBuy ? open - slStep * nextSLPartial : open + slStep * nextSLPartial;
            bool crossedSL = isBuy ? (curr <= nextSLLvl) : (curr >= nextSLLvl);
            if(crossedSL)
            {
               if(nextSLPartial >= 2)
               {
                  trade.PositionClose(ticket);
                  continue;
               }
               else
               {
                  double slAmt = NormalizeDouble(posInfo.Volume() / 2.0, 2);
                  if(slAmt < minV2) slAmt = minV2;
                  if(slAmt > posInfo.Volume()) slAmt = posInfo.Volume();
                  if(trade.PositionClosePartial(ticket, slAmt))
                  {
                     g_PosStates[stIdx].slPartialsTaken = nextSLPartial;
                     if(InpEnableSounds) PlaySound(InpSoundSL);
                  }
               }
            }
         }
      }

      if(InpBE_Trigger > 0 && nextPartial == InpBE_Trigger && !beSet)
      {
         if(posInfo.SelectByTicket(ticket))
         {
            double newSL = isBuy ? open + InpBE_Offset * _Point : open - InpBE_Offset * _Point;
            newSL = NormaliseSL(newSL);
            double freshSL = posInfo.StopLoss();
            bool better = isBuy ? (newSL > freshSL) : (freshSL == 0 || newSL < freshSL);
            if(better)
            {
               if(trade.PositionModify(ticket, newSL, posInfo.TakeProfit()))
               {
                  g_PosStates[stIdx].beSet = true;
                  if(InpEnableSounds) PlaySound(InpSoundBE);
               }
            }
            else
            {
               g_PosStates[stIdx].beSet = true;
            }
            
            if (g_PosStates[stIdx].beSet)
               JournalEvent("SL_CHANGE", ticket, _Symbol, isBuy ? "BUY" : "SELL", posInfo.Volume(), open, curSL, curTP, 0, "SL Set to BE", "System");
         }
      }
   }

   RecomputeHasOpenTrades();
}

//+------------------------------------------------------------------+
//| TRAILING STOP                                                      |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   if(!InpUseTrailingStop) return;

   static ulong lastTrailMs = 0;
   ulong nowMsT = (ulong)GetTickCount();
   if(nowMsT - lastTrailMs < 200) return;
   lastTrailMs = nowMsT;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      bool isOwn = (posInfo.Magic() == MAGIC);
      bool isExt = InpMonitorExternal && IsRegisteredExternal(posInfo.Ticket());
      if(!isOwn && !isExt) continue;

      double open = posInfo.PriceOpen();
      double curSL = posInfo.StopLoss();
      double curTP = posInfo.TakeProfit();
      double pt = _Point;
      bool isBuy = (posInfo.PositionType() == POSITION_TYPE_BUY);

      if(isBuy)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double profit = bid - open;
         if(profit < InpTrailingStart * pt) continue;
         double target = NormaliseSL(bid - InpTrailingStep * pt);
         if(curSL <= 0 || target > curSL + pt)
            trade.PositionModify(posInfo.Ticket(), target, curTP);
      }
      else
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double profit = open - ask;
         if(profit < InpTrailingStart * pt) continue;
         double target = NormaliseSL(ask + InpTrailingStep * pt);
         if(curSL <= 0 || target < curSL - pt)
            trade.PositionModify(posInfo.Ticket(), target, curTP);
      }
   }
}

//+------------------------------------------------------------------+
//| DAILY LOSS LIMIT                                                   |
//+------------------------------------------------------------------+
bool IsDailyLossLimitReached()
{
   if(!InpEnableDailyLossLimit) return false;
   datetime now = TimeCurrent();
   datetime startOfDay = now - (now % 86400);
   if(!HistorySelect(startOfDay, now)) return false;

   int losers = 0;
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong dt = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(dt, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      if(HistoryDealGetInteger(dt, DEAL_MAGIC) != MAGIC) continue;
      if(HistoryDealGetString (dt, DEAL_SYMBOL) != _Symbol) continue;

      double p = HistoryDealGetDouble(dt, DEAL_PROFIT)
               + HistoryDealGetDouble(dt, DEAL_COMMISSION)
               + HistoryDealGetDouble(dt, DEAL_SWAP);
      if(p < 0) losers++;
   }
   return (losers >= InpMaxDailyLosingTrades);
}

//+------------------------------------------------------------------+
//| ORDER EXECUTION                                                    |
//+------------------------------------------------------------------+
void ExecuteOrder()
{
   if(InpEnableDailyLossLimit && IsDailyLossLimitReached())
   { Alert("[TM3] Daily loss limit reached. Cool down first."); return; }

   if(CountManagedOpenPositions() >= InpMaxOpenTrades)
   { Alert(StringFormat("[TM3] Max managed trades reached (%d)", InpMaxOpenTrades)); return; }

   double p = (ui.orderType == UI_LIMIT)
              ? ui.customPrice
              : ((ui.side == UI_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID));

   bool isInverse = (ui.orderType == UI_MARKET && ui.inverseEnabled);
   if(isInverse)
   {
      if(ui.side == UI_BUY) p = SymbolInfoDouble(_Symbol, SYMBOL_BID) - InpInverseOffset * _Point;
      else p = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + InpInverseOffset * _Point;
      p = NormaliseSL(p);
   }

   double sl = (ui.slPoints > 0) ? ((ui.side == UI_BUY) ? p - ui.slPoints * _Point : p + ui.slPoints * _Point) : 0;
   double tp = (ui.side == UI_BUY) ? p + ui.tpPoints * _Point : p - ui.tpPoints * _Point;
   bool res = false;

   if(ui.orderType == UI_MARKET && !isInverse)
   {
      if(ui.side == UI_BUY) res = trade.Buy (ui.lotSize, _Symbol, p, sl, tp, "TM3");
      else res = trade.Sell(ui.lotSize, _Symbol, p, sl, tp, "TM3");
   }
   else
   {
      if(ui.side == UI_BUY) res = trade.BuyLimit (ui.lotSize, p, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "TM3");
      else res = trade.SellLimit(ui.lotSize, p, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "TM3");
   }

   if(res && InpEnableSounds) PlaySound(InpSoundEntry);
   if(res && ui.isVisualizing) ToggleVisualization();
}

double NormaliseVolume(double vol)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   return MathFloor(vol / step) * step;
}

void SetBreakEvenManual()
{
   if(g_SelectedTicket == 0)
   {
      Alert("[TM3] No trade selected. Use the Trade Selector to pick a ticket first.");
      return;
   }
   SetBreakEvenTicket(g_SelectedTicket);
}

void SetBreakEvenTicket(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return;
   if(!posInfo.SelectByTicket(ticket)) return;
   double open = posInfo.PriceOpen();
   bool isBuy = (posInfo.PositionType() == POSITION_TYPE_BUY);
   double newSL = NormaliseSL(isBuy ? open + InpBE_Offset * _Point : open - InpBE_Offset * _Point);

   if(trade.PositionModify(ticket, newSL, posInfo.TakeProfit()))
   {
      if(InpEnableSounds) PlaySound(InpSoundBE);
      int idx = FindPosStateIdx(posInfo.Identifier());
      if(idx >= 0) g_PosStates[idx].beSet = true;
   }
}

void CloseTicket(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return;
   if(trade.PositionClose(ticket))
      if(InpEnableSounds) PlaySound(InpSoundClose);
}

void ManualPartial()
{
   if(g_SelectedTicket == 0)
   {
      Alert("[TM3] No trade selected. Use the Trade Selector to pick a ticket first.");
      return;
   }
   if(!PositionSelectByTicket(g_SelectedTicket)) { Alert("[TM3] Selected trade no longer exists."); return; }
   if(!posInfo.SelectByTicket(g_SelectedTicket)) return;

   double pct = StringToDouble(ObjectGetString(0, g_prefix + "Edit_ManPart", OBJPROP_TEXT));
   double amt = NormalizeDouble(posInfo.Volume() * (pct * 0.01), 2);
   double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(amt < minV) amt = minV;
   if(amt > posInfo.Volume()) amt = posInfo.Volume();

   if(trade.PositionClosePartial(g_SelectedTicket, amt))
      if(InpEnableSounds) PlaySound(InpSoundPartial);
}

void CloseAll()
{
   bool any = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      bool isOwn = (posInfo.Magic() == MAGIC);
      bool isExt = InpMonitorExternal && IsRegisteredExternal(posInfo.Ticket());
      if(!isOwn && !isExt) continue;
      trade.PositionClose(posInfo.Ticket());
      any = true;
   }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ot = OrderGetTicket(i);
      if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == MAGIC)
      { trade.OrderDelete(ot); any = true; }
   }
   if(any && InpEnableSounds) PlaySound(InpSoundClose);
}

ulong g_ManagedTickets[];
datetime g_ManagedTicketsCacheTime = 0;

int BuildManagedTicketList(ulong &list[])
{
   ArrayResize(list, 0);
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      bool isOwn = (posInfo.Magic() == MAGIC);
      bool isExt = InpMonitorExternal && IsRegisteredExternal(posInfo.Ticket());
      if(!isOwn && !isExt) continue;
      int n = ArraySize(list);
      ArrayResize(list, n + 1);
      list[n] = posInfo.Ticket();
   }
   ArraySort(list);
   return ArraySize(list);
}

void RefreshManagedTicketCache()
{
   BuildManagedTicketList(g_ManagedTickets);
}

int FindManagedTicketIndex(ulong ticket)
{
   int n = ArraySize(g_ManagedTickets);
   for(int i = 0; i < n; i++)
      if(g_ManagedTickets[i] == ticket) return i;
   return -1;
}

ulong GetManagedTicketByOffset(int offset)
{
   int n = ArraySize(g_ManagedTickets);
   if(n == 0) return 0;

   int curIdx = FindManagedTicketIndex(g_SelectedTicket);
   int newIdx;
   if(curIdx < 0) newIdx = 0;
   else newIdx = (curIdx + offset + n) % n;

   return g_ManagedTickets[newIdx];
}

void CycleSelectedTrade(int direction)
{
   RefreshManagedTicketCache();
   ulong t = GetManagedTicketByOffset(direction);
   g_SelectedTicket = t;
   UpdateSelectedTradeLabel();
}

void ValidateSelectedTicket()
{
   int n = ArraySize(g_ManagedTickets);
   if(n == 0) { g_SelectedTicket = 0; return; }
   if(FindManagedTicketIndex(g_SelectedTicket) < 0)
      g_SelectedTicket = g_ManagedTickets[0];
}

void UpdateSelectedTradeLabel()
{
   string txt;
   if(g_SelectedTicket == 0 || !PositionSelectByTicket(g_SelectedTicket))
   {
      txt = "Selected: none";
   }
   else
   {
      posInfo.SelectByTicket(g_SelectedTicket);
      bool isBuy = (posInfo.PositionType() == POSITION_TYPE_BUY);
      double profit = posInfo.Profit() + posInfo.Swap() + posInfo.Commission();
      txt = StringFormat("Sel: #%d %s %.2f %s%.2f",
                          (int)g_SelectedTicket,
                          isBuy ? "BUY" : "SELL",
                          posInfo.Volume(),
                          profit >= 0 ? "+" : "",
                          profit);
   }
   if(ObjectFind(0, g_prefix+"Lbl_Selected") >= 0)
      ObjectSetString(0, g_prefix+"Lbl_Selected", OBJPROP_TEXT, txt);
}

void CloseSelectedTrade()
{
   if(g_SelectedTicket == 0) { Alert("[TM3] No trade selected."); return; }
   ulong t = g_SelectedTicket;
   if(!PositionSelectByTicket(t)) { Alert("[TM3] Selected trade no longer exists."); return; }
   if(trade.PositionClose(t))
   {
      if(InpEnableSounds) PlaySound(InpSoundClose);
      g_SelectedTicket = 0;
      ValidateSelectedTicket();
      UpdateSelectedTradeLabel();
   }
}

//+------------------------------------------------------------------+
//| BASKET (Auto Trade Handler)                                       |
//+------------------------------------------------------------------+
void ToggleBasket()
{
   ui.basketEnabled = !ui.basketEnabled;
   UpdatePanelUI();
   SaveState();
}

void ManageDrawdownBasket()
{
   if(!ui.basketEnabled) return;

   static ulong lastBasketMs = 0;
   ulong nowMsB = (ulong)GetTickCount();
   if(nowMsB - lastBasketMs < 200) return;
   lastBasketMs = nowMsB;

   ProcessBasketByType(POSITION_TYPE_BUY);
   ProcessBasketByType(POSITION_TYPE_SELL);
}

void ProcessBasketByType(ENUM_POSITION_TYPE type)
{
   struct MP { ulong ticket; double profit; double priceDiff; datetime openTime; };
   MP managed[];

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      if(posInfo.PositionType() != type) continue;

      bool isOwn = (posInfo.Magic() == InpMagicNumber);
      bool isExt = InpMonitorExternal && IsRegisteredExternal(posInfo.Ticket());
      if(!isOwn && !isExt) continue;

      bool isBuy = (type == POSITION_TYPE_BUY);
      double curr = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sign = isBuy ? 1.0 : -1.0;

      int n = ArraySize(managed);
      ArrayResize(managed, n + 1);
      managed[n].ticket = posInfo.Ticket();
      managed[n].profit = posInfo.Profit() + posInfo.Swap() + posInfo.Commission();
      managed[n].priceDiff = sign * (curr - posInfo.PriceOpen()) / _Point;
      managed[n].openTime = (datetime)posInfo.Time();
   }

   if(ArraySize(managed) <= 1) return;

   int worstIdx = 0;
   for(int i = 1; i < ArraySize(managed); i++)
   {
      if(managed[i].priceDiff < managed[worstIdx].priceDiff) 
      {
         worstIdx = i;
      }
   }

   if(managed[worstIdx].priceDiff >= g_BasketPts && managed[worstIdx].profit > 0.0)
   {
      trade.PositionClose(managed[worstIdx].ticket);
   }
}

//+------------------------------------------------------------------+
//| EXTERNAL TRADE MONITORING & AUTO-ADOPTION                         |
//+------------------------------------------------------------------+
void ScanExternalTrades()
{
   if(!InpMonitorExternal) return;
   datetime now = TimeCurrent();
   if(now - g_LastExtScan < 1) return;
   g_LastExtScan = now;

   RemoveClosedExternals();
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      if(posInfo.Magic() == MAGIC) continue;
      ulong ticket = posInfo.Ticket();
      if(IsRegisteredExternal(ticket)) continue;

      int n = ArraySize(g_ExtTrades);
      ArrayResize(g_ExtTrades, n + 1);
      g_ExtTrades[n].ticket = ticket;
      g_ExtTrades[n].posID = posInfo.Identifier();
      g_ExtTrades[n].alertSent = false;
      g_ExtTrades[n].adopted = false;

      EnsurePosState(posInfo.Identifier(), ticket);

      if(InpExternalAlerts)
      {
         string dir = (posInfo.PositionType() == POSITION_TYPE_BUY) ? "BUY" : "SELL";
         Alert(StringFormat("[TM3] External %s %.2f lots @ %.5f — adopting into management", dir, posInfo.Volume(), posInfo.PriceOpen()));
         if(InpEnableSounds) PlaySound(InpSoundExtDetected);
         g_ExtTrades[n].alertSent = true;
      }

      if(InpAutoAdoptExternal)
         AdoptExternalTrade(ticket);

      g_HasOpenTrades = true;
   }
}

void AdoptExternalTrade(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return;
   if(!posInfo.SelectByTicket(ticket)) return;

   double open  = posInfo.PriceOpen();
   double curSL = posInfo.StopLoss();
   double curTP = posInfo.TakeProfit();
   bool   isBuy = (posInfo.PositionType() == POSITION_TYPE_BUY);

   double newSL = curSL;
   double newTP = curTP;
   bool needModify = false;

   if(curSL == 0.0 || InpOverwriteExtSLTP)
   {
      newSL = isBuy ? open - InpDefaultSL * _Point : open + InpDefaultSL * _Point;
      newSL = NormaliseSL(newSL);
      needModify = true;
   }
   if(curTP == 0.0 || InpOverwriteExtSLTP)
   {
      newTP = isBuy ? open + InpDefaultTP * _Point : open - InpDefaultTP * _Point;
      newTP = NormaliseSL(newTP);
      needModify = true;
   }

   if(needModify)
   {
      if(trade.PositionModify(ticket, newSL, newTP))
      {
         Print("[TM3] Adopted external ticket ", ticket, " — SL=", newSL, " TP=", newTP);
         for(int i = 0; i < ArraySize(g_ExtTrades); i++)
            if(g_ExtTrades[i].ticket == ticket) { g_ExtTrades[i].adopted = true; break; }
      }
      else
      {
         Print("[TM3] Failed to adopt external ticket ", ticket, " — Error: ", GetLastError());
      }
   }
}

bool IsRegisteredExternal(ulong ticket)
{
   for(int i = 0; i < ArraySize(g_ExtTrades); i++)
      if(g_ExtTrades[i].ticket == ticket) return true;
   return false;
}

void RemoveClosedExternals()
{
   for(int i = ArraySize(g_ExtTrades) - 1; i >= 0; i--)
   {
      if(!PositionSelectByTicket(g_ExtTrades[i].ticket))
      {
         string pfx = g_prefix + "P_" + IntegerToString((int)g_ExtTrades[i].ticket) + "_";
         for(int j = ObjectsTotal(0, -1, -1) - 1; j >= 0; j--)
         {
            string nm = ObjectName(0, j);
            if(StringFind(nm, pfx) == 0) ObjectDelete(0, nm);
         }
         RemovePosState(g_ExtTrades[i].posID);
         ArrayRemove(g_ExtTrades, i, 1);
      }
   }
}

//+------------------------------------------------------------------+
//| EXPORT TO CSV                                                      |
//+------------------------------------------------------------------+
void ExportToCSV()
{
   string filename = "TM3_Export_" + _Symbol + "_" + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES) + ".csv";
   StringReplace(filename, ":", "-");
   StringReplace(filename, ".", "");

   int handle = FileOpen(filename, FILE_WRITE|FILE_CSV|FILE_ANSI, ",");
   if(handle == INVALID_HANDLE)
   {
      Alert("[TM3] Failed to open file for export: ", filename);
      return;
   }

   FileWrite(handle, "Ticket", "Time", "Type", "Volume", "Price", "SL", "TP", "Profit", "Commission", "Swap", "Comment");

   HistorySelect(0, TimeCurrent());
   int total = HistoryDealsTotal();
   int exportedCount = 0;

   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != MAGIC) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;

      datetime time = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      long type = HistoryDealGetInteger(ticket, DEAL_TYPE);
      double vol = HistoryDealGetDouble(ticket, DEAL_VOLUME);
      double price = HistoryDealGetDouble(ticket, DEAL_PRICE);
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      double comm = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
      string comment = HistoryDealGetString(ticket, DEAL_COMMENT);

      double sl = 0, tp = 0;
      string typeStr = "Unknown";
      if(type == DEAL_TYPE_BUY) typeStr = "Buy";
      else if(type == DEAL_TYPE_SELL) typeStr = "Sell";

      FileWrite(handle,
         IntegerToString((int)ticket),
         TimeToString(time),
         typeStr,
         DoubleToString(vol, 2),
         DoubleToString(price, _Digits),
         DoubleToString(sl, _Digits),
         DoubleToString(tp, _Digits),
         DoubleToString(profit, 2),
         DoubleToString(comm, 2),
         DoubleToString(swap, 2),
         comment
      );
      exportedCount++;
   }

   FileClose(handle);
   Print("[TM3] Successfully exported ", exportedCount, " deals to ", filename);
   Alert("[TM3] Export complete: ", filename);
   if(InpEnableSounds) PlaySound(InpSoundOk);
}

//+------------------------------------------------------------------+
//| UTILITIES                                                          |
//+------------------------------------------------------------------+
bool IsManagedPosition()
{
   if(posInfo.Symbol() != _Symbol) return false;
   return (posInfo.Magic() == MAGIC) || (InpMonitorExternal && IsRegisteredExternal(posInfo.Ticket()));
}

int CountManagedOpenPositions()
{
   if(PositionsTotal() == 0) return 0;
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(posInfo.SelectByIndex(i) && IsManagedPosition()) count++;
   return count;
}

double NormaliseSL(double price)
{
   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick > 0) price = MathRound(price / tick) * tick;
   return price;
}

void CleanupOrphanedLines()
{
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i);
      if(StringFind(nm, g_prefix + "P_") != 0) continue;
      string sfx = StringSubstr(nm, StringLen(g_prefix));
      string parts[];
      if(StringSplit(sfx, '_', parts) >= 2)
      {
         ulong t = (ulong)StringToInteger(parts[1]);
         if(t > 0 && !PositionSelectByTicket(t)) ObjectDelete(0, nm);
      }
   }
}

int GetSpread()
{
   return (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
}

//+------------------------------------------------------------------+
//| STATE PERSISTENCE                                                  |
//+------------------------------------------------------------------+
void SaveState()
{
   string id = IntegerToString(ChartID());
   GlobalVariableSet("TM3_" + id + "_Type", (double)ui.orderType);
   GlobalVariableSet("TM3_" + id + "_Side", (double)ui.side);
   GlobalVariableSet("TM3_" + id + "_Lot", ui.lotSize);
   GlobalVariableSet("TM3_" + id + "_SL", (double)ui.slPoints);
   GlobalVariableSet("TM3_" + id + "_TP", (double)ui.tpPoints);
   GlobalVariableSet("TM3_" + id + "_Parts", (double)ui.partialsCount);
   GlobalVariableSet("TM3_" + id + "_Basket", (double)ui.basketEnabled);
   GlobalVariableSet("TM3_" + id + "_Inv", (double)ui.inverseEnabled);
   GlobalVariableSet("TM3_" + id + "_AutoRisk", (double)ui.autoRiskEnabled);
}

void LoadState()
{
   string id = IntegerToString(ChartID());
   if(!GlobalVariableCheck("TM3_" + id + "_Type")) return;
   ui.orderType = (ENUM_ORDER_TYPE_UI)(int)GlobalVariableGet("TM3_" + id + "_Type");
   ui.side = (ENUM_SIDE_UI) (int)GlobalVariableGet("TM3_" + id + "_Side");
   ui.lotSize = GlobalVariableGet("TM3_" + id + "_Lot");
   ui.slPoints = (int) GlobalVariableGet("TM3_" + id + "_SL");
   ui.tpPoints = (int) GlobalVariableGet("TM3_" + id + "_TP");
   ui.partialsCount = (int) GlobalVariableGet("TM3_" + id + "_Parts");
   if(GlobalVariableCheck("TM3_" + id + "_Basket")) ui.basketEnabled = (bool)GlobalVariableGet("TM3_" + id + "_Basket");
   if(GlobalVariableCheck("TM3_" + id + "_Inv")) ui.inverseEnabled = (bool)GlobalVariableGet("TM3_" + id + "_Inv");
   if(GlobalVariableCheck("TM3_" + id + "_AutoRisk")) ui.autoRiskEnabled = (bool)GlobalVariableGet("TM3_" + id + "_AutoRisk");
}

void ClearState()
{
   string id = IntegerToString(ChartID());
   string keys[] = {"_Type","_Side","_Lot","_SL","_TP","_Parts","_Basket"};
   for(int i = 0; i < 7; i++) GlobalVariableDel("TM3_" + id + keys[i]);
}

//+------------------------------------------------------------------+
//| GUI PANEL                                                          |
//+------------------------------------------------------------------+
int PanelHeight()
{
   return 550 + PositionListHeight() + 20;
}

int PositionListHeight()
{
   int count = CountManagedOpenPositions();
   if(count <= 0) return 20;
   return 20 + count * POS_ROW_H;
}

void RebuildPanel(bool doUpdateUI)
{
   int sw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int sh = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   int bx = 10, by = 50;

   if(InpPanelCorner == CORNER_RIGHT_UPPER) bx = sw - PANEL_W - 10;
   if(InpPanelCorner == CORNER_LEFT_LOWER) by = sh - PanelHeight() - 30;
   if(InpPanelCorner == CORNER_RIGHT_LOWER) { bx = sw - PANEL_W - 10; by = sh - PanelHeight() - 30; }

   CreatePanelElements(bx, by);
   if(doUpdateUI) UpdatePanelUI();
}

void CreatePanelElements(int x, int y)
{
   Rect("BG", x, y, PANEL_W, PanelHeight(), COLOR_BG);
   y += PAD;
   Btn("Btn_Mkt", x+5, y, 110, ROW_H, "MARKET", (ui.orderType == UI_MARKET));
   Btn("Btn_Lim", x+115, y, 110, ROW_H, "LIMIT", (ui.orderType == UI_LIMIT));
   y += ROW_H + PAD;
   Lbl("Lbl_Prc", x+5, y+5, "Price:");
   Edit("Edit_Price", x+55, y, 170, ROW_H, "0.00000");
   y += ROW_H + PAD;
   Btn("Btn_Buy", x+5, y, 110, ROW_H, "BUY", false, COLOR_BUY);
   Btn("Btn_Sell", x+115, y, 110, ROW_H, "SELL", false, COLOR_SELL);
   y += ROW_H + PAD;
   Lbl("Lbl_Lot", x+5, y+5, "Lot:");
   Edit("Edit_Lot", x+115, y, 110, ROW_H, DoubleToString(ui.lotSize, 2));
   y += ROW_H + PAD;
   Lbl("Lbl_SL", x+5, y+5, "SL pts:");
   Edit("Edit_SL", x+65, y, 55, ROW_H, IntegerToString(ui.slPoints));
   Lbl("Lbl_SLP", x+125, y+5, "Prc:");
   Edit("Edit_SL_Prc", x+148, y, 77, ROW_H, "0.00000");
   y += ROW_H + PAD;
   Lbl("Lbl_TP", x+5, y+5, "TP pts:");
   Edit("Edit_TP", x+65, y, 55, ROW_H, IntegerToString(ui.tpPoints));
   Lbl("Lbl_TPP", x+125, y+5, "Prc:");
   Edit("Edit_TP_Prc", x+148, y, 77, ROW_H, "0.00000");
   y += ROW_H + PAD;
   Lbl("Lbl_Part", x+5, y+5, "Partials #:");
   Edit("Edit_Part", x+115, y, 110, ROW_H, IntegerToString(ui.partialsCount));
   y += ROW_H + PAD;
   Rect("Sep3", x+5, y, PANEL_W-10, 1, C'80,80,80');
   y += 5;

   UpdatePartialLine(x, y);
   y += 18;

   Rect("Sep1", x+5, y, PANEL_W-10, 1, C'60,60,60');
   y += 5;
   Lbl("Lbl_Risk", x+5, y+5, "Risk:");
   Lbl("Val_Risk", x+45, y+5, "$0.00");
   ObjectSetInteger(0, g_prefix+"Val_Risk", OBJPROP_COLOR, clrCrimson);
   Lbl("Lbl_Rew", x+115, y+5, "Profit:");
   Lbl("Val_Rew", x+158, y+5, "$0.00");
   ObjectSetInteger(0, g_prefix+"Val_Rew", OBJPROP_COLOR, clrLimeGreen);
   y += 20;
   Rect("Sep2", x+5, y, PANEL_W-10, 1, C'60,60,60');
   y += 5;
   Btn("Btn_Vis", x+5, y, 220, ROW_H, "VISUALIZE", false, C'80,80,80');
   y += ROW_H + PAD;
   Rect("SepSel1", x+5, y, PANEL_W-10, 1, C'80,80,80');
   y += 6;

   Lbl("Lbl_SelHdr", x+5, y+2, "Trade Selector:");
   y += 14;
   Btn("Btn_SelPrev", x+5, y, 35, ROW_H, "<", false, C'70,70,70');
   Lbl("Lbl_Selected", x+45, y+7, "Selected: none");
   Btn("Btn_SelNext", x+PANEL_W-45, y, 35, ROW_H, ">", false, C'70,70,70');
   y += ROW_H + PAD;

   Edit("Edit_ManPart", x+5, y, 50, ROW_H, "20");
   Btn("Btn_Part", x+60, y, 165, ROW_H, "PARTIAL % (SEL)", false, C'80,80,0');
   y += ROW_H + PAD;
   Btn("Btn_BE", x+5, y, 110, ROW_H, "BE (SEL)", false, C'0,80,80');
   Btn("Btn_CloseSel", x+115, y, 110, ROW_H, "CLOSE (SEL)", false, C'180,60,0');
   y += ROW_H + PAD;
   Rect("SepSel2", x+5, y, PANEL_W-10, 1, C'80,80,80');
   y += 6;

   Btn("Btn_CloseAll", x+5, y, 220, ROW_H, "CLOSE ALL", false, clrRed);
   y += ROW_H + PAD;

   Btn("Btn_Export", x+5, y, 105, ROW_H, "EXPORT CSV", false, C'50,100,50');
   Btn("Btn_Inverse", x+115, y, 110, ROW_H, ui.inverseEnabled ? "INV: ON" : "INV: OFF", false, ui.inverseEnabled ? C'180,100,0' : C'80,80,80');
   y += ROW_H + PAD;
   Rect("Sep4", x+5, y, PANEL_W-10, 1, C'80,80,80');
   y += 6;

   Btn("Btn_AutoRisk", x+5, y, 105, ROW_H, ui.autoRiskEnabled ? "Auto Risk: ON" : "Auto Risk: OFF", false, ui.autoRiskEnabled ? C'180,0,100' : C'120,0,0');
   Btn("Btn_Basket", x+115, y, 110, ROW_H, ui.basketEnabled ? "Handler: ON" : "Handler: OFF", false, ui.basketEnabled ? C'0,140,0' : C'120,0,0');
   y += ROW_H + PAD;

   Lbl("Lbl_GreenPts", x+5, y+5, "Close pts:");
   Edit("Edit_GreenPts", x+85, y, 140, ROW_H, IntegerToString(InpBasketGreenPoints));
   y += ROW_H + PAD;
   Rect("Sep5", x+5, y, PANEL_W-10, 1, C'80,80,80');
   y += 6;

   g_PosListX = x;
   g_PosListY = y;
   DrawPositionList(x, y);
}

void UpdatePanelUI()
{
   ObjectSetInteger(0, g_prefix+"Btn_Mkt", OBJPROP_BGCOLOR, ui.orderType==UI_MARKET ? COLOR_ACT : COLOR_BTN);
   ObjectSetInteger(0, g_prefix+"Btn_Lim", OBJPROP_BGCOLOR, ui.orderType==UI_LIMIT ? COLOR_ACT : COLOR_BTN);
   ObjectSetInteger(0, g_prefix+"Btn_Buy", OBJPROP_BGCOLOR, COLOR_BUY);
   ObjectSetInteger(0, g_prefix+"Btn_Sell", OBJPROP_BGCOLOR, COLOR_SELL);
   ObjectSetInteger(0, g_prefix+"Btn_Buy", OBJPROP_COLOR, COLOR_TEXT);
   ObjectSetInteger(0, g_prefix+"Btn_Sell", OBJPROP_COLOR, COLOR_TEXT);
   ObjectSetInteger(0, g_prefix+"Btn_Vis", OBJPROP_BGCOLOR, ui.isVisualizing ? COLOR_ACT : C'80,80,80');

   if(ObjectFind(0, g_prefix+"Btn_Basket") >= 0)
   {
      ObjectSetString (0, g_prefix+"Btn_Basket", OBJPROP_TEXT, ui.basketEnabled ? "Handler: ON" : "Handler: OFF");
      ObjectSetInteger(0, g_prefix+"Btn_Basket", OBJPROP_BGCOLOR, ui.basketEnabled ? C'0,140,0' : C'120,0,0');
   }
   if(ObjectFind(0, g_prefix+"Btn_Inverse") >= 0)
   {
      ObjectSetString (0, g_prefix+"Btn_Inverse", OBJPROP_TEXT, ui.inverseEnabled ? "INV: ON" : "INV: OFF");
      ObjectSetInteger(0, g_prefix+"Btn_Inverse", OBJPROP_BGCOLOR, ui.inverseEnabled ? C'180,100,0' : C'80,80,80');
   }
   if(ObjectFind(0, g_prefix+"Btn_AutoRisk") >= 0)
   {
      ObjectSetString (0, g_prefix+"Btn_AutoRisk", OBJPROP_TEXT, ui.autoRiskEnabled ? "Auto Risk: ON" : "Auto Risk: OFF");
      ObjectSetInteger(0, g_prefix+"Btn_AutoRisk", OBJPROP_BGCOLOR, ui.autoRiskEnabled ? C'180,0,100' : C'120,0,0');
   }
}

void UpdatePartialLine(int x, int y)
{
   string nm = "PTL_Line";
   if(ui.partialsCount <= 0 || ui.tpPoints <= 0)
   {
      Lbl(nm, x+10, y, "No partials configured");
      ObjectSetInteger(0, g_prefix+nm, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, g_prefix+nm, OBJPROP_COLOR, C'140,140,140');
      return;
   }

   double step = (double)ui.tpPoints / (ui.partialsCount + 1);
   string txt = "";
   for(int i = 1; i <= ui.partialsCount; i++)
   {
      int pts = (int)MathRound(step * i);
      txt += "TP" + IntegerToString(i) + ":" + IntegerToString(pts/10);
      if(i < ui.partialsCount) txt += " | ";
   }

   Lbl(nm, x+10, y, txt);
   ObjectSetInteger(0, g_prefix+nm, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, g_prefix+nm, OBJPROP_COLOR, C'140,140,140');
}

void UpdateSLTPPrices(double ep)
{
   if(ui.side == UI_BUY)
   {
      ui.slPrice = (ui.slPoints > 0) ? ep - ui.slPoints * _Point : 0;
      ui.tpPrice = ep + ui.tpPoints * _Point;
   }
   else
   {
      ui.slPrice = (ui.slPoints > 0) ? ep + ui.slPoints * _Point : 0;
      ui.tpPrice = ep - ui.tpPoints * _Point;
   }
   string slTxt = (ui.slPoints > 0) ? DoubleToString(ui.slPrice, _Digits) : "NONE";
   if(ObjectFind(0, g_prefix+"Edit_SL_Prc") >= 0) ObjectSetString(0, g_prefix+"Edit_SL_Prc", OBJPROP_TEXT, slTxt);
   if(ObjectFind(0, g_prefix+"Edit_TP_Prc") >= 0) ObjectSetString(0, g_prefix+"Edit_TP_Prc", OBJPROP_TEXT, DoubleToString(ui.tpPrice, _Digits));
}

void UpdateStats(double priceRef)
{
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tv == 0 || ts == 0 || _Point == 0) return;

   double pmf = (_Point / ts) * tv;
   double riskUSD = ui.lotSize * ui.slPoints * pmf;
   double rewUSD = 0;
   double remLot = ui.lotSize;
   double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double stepPts = (double)ui.tpPoints / (ui.partialsCount + 1);

   for(int i = 1; i <= ui.partialsCount; i++)
   {
      double pct = (i == 1) ? InpMainPartialVol : InpRollingPartialVol;
      double partLot = MathFloor(ui.lotSize * (pct * 0.01) / volStep) * volStep;
      if(partLot < minLot) partLot = 0;
      if(partLot > 0 && partLot <= remLot)
      { rewUSD += partLot * stepPts * i * pmf; remLot -= partLot; }
   }
   remLot = NormalizeDouble(remLot, 2);
   if(remLot > 0) rewUSD += remLot * ui.tpPoints * pmf;

   if(ObjectFind(0, g_prefix+"Val_Risk") >= 0) ObjectSetString(0, g_prefix+"Val_Risk", OBJPROP_TEXT, "$"+DoubleToString(riskUSD, 2));
   if(ObjectFind(0, g_prefix+"Val_Rew") >= 0) ObjectSetString(0, g_prefix+"Val_Rew", OBJPROP_TEXT, "$"+DoubleToString(rewUSD, 2));
}

void ToggleVisualization()
{
   ui.isVisualizing = !ui.isVisualizing;
   if(!ui.isVisualizing)
   {
      ObjectDelete(0, g_prefix+"VisB_Entry"); ObjectDelete(0, g_prefix+"VisS_Entry");
      ObjectDelete(0, g_prefix+"VisB_SL"); ObjectDelete(0, g_prefix+"VisS_SL");
      ObjectDelete(0, g_prefix+"VisB_TP"); ObjectDelete(0, g_prefix+"VisS_TP");
      for(int i = 1; i <= 20; i++)
      {
         ObjectDelete(0, g_prefix+"VisB_P"+IntegerToString(i));
         ObjectDelete(0, g_prefix+"VisS_P"+IntegerToString(i));
      }
   }
   else
   {
      DrawVisualization();
   }
   UpdatePanelUI();
}

void DrawVisualization()
{
   double pBuy = (ui.orderType == UI_LIMIT) ? ui.customPrice : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double pSell = (ui.orderType == UI_LIMIT) ? ui.customPrice : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   DrawSideVis(pBuy, UI_BUY);
   DrawSideVis(pSell, UI_SELL);
}

void DrawSideVis(double ep, ENUM_SIDE_UI side)
{
   color c = (side == UI_BUY) ? COLOR_BUY : COLOR_SELL;
   string pfx = (side == UI_BUY) ? "VisB_" : "VisS_";

   double sl = (ui.slPoints > 0) ? ((side == UI_BUY) ? ep - ui.slPoints * _Point : ep + ui.slPoints * _Point) : 0;
   double tp = (side == UI_BUY) ? ep + ui.tpPoints * _Point : ep - ui.tpPoints * _Point;
   double step = (ui.partialsCount > 0) ? (ui.tpPoints * _Point) / (ui.partialsCount + 1) : 0;

   Line(pfx+"Entry", ep, c, STYLE_SOLID, 2, (side==UI_BUY ? "BUY" : "SELL") + " ENTRY");

   if(sl > 0) Line(pfx+"SL", sl, c, STYLE_DASH, 1, (side==UI_BUY ? "B_SL" : "S_SL"));
   else ObjectDelete(0, g_prefix+pfx+"SL");

   Line(pfx+"TP", tp, c, STYLE_SOLID, 1, (side==UI_BUY ? "B_TP" : "S_TP"));

   for(int i = 1; i <= ui.partialsCount; i++)
   {
      double lvl = (side == UI_BUY) ? ep + step * i : ep - step * i;
      Line(pfx+"P"+IntegerToString(i), lvl, c, STYLE_DOT, 1, (side==UI_BUY?"B_P":"S_P")+IntegerToString(i));
   }

   for(int i = ui.partialsCount + 1; i <= 20; i++) ObjectDelete(0, g_prefix+pfx+"P"+IntegerToString(i));
}

void DrawPositionList(int x, int y)
{
   Lbl("Lbl_PosList", x+5, y, "Open Positions:");
   y += 16;

   int rowIdx = 0;
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0 && rowIdx < 20; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      bool isOwn = (posInfo.Magic() == MAGIC);
      bool isExt = InpMonitorExternal && IsRegisteredExternal(posInfo.Ticket());
      if(!isOwn && !isExt) continue;

      ulong ticket = posInfo.Ticket();
      bool isBuy = (posInfo.PositionType() == POSITION_TYPE_BUY);
      double vol = posInfo.Volume();
      double profit = posInfo.Profit() + posInfo.Swap() + posInfo.Commission();
      bool isSelected = (ticket == g_SelectedTicket);

      string marker = isSelected ? "> " : "  ";
      string rowTxt = StringFormat("%s#%d %s %.2f %s%.2f",
                                    marker,
                                    (int)ticket,
                                    isBuy ? "BUY" : "SELL",
                                    vol,
                                    profit >= 0 ? "+" : "",
                                    profit);

      string lblName = "PosRow_" + IntegerToString((int)ticket);
      Lbl(lblName, x+5, y+3, rowTxt);
      ObjectSetInteger(0, g_prefix+lblName, OBJPROP_FONTSIZE, 8);
      color rowColor = isSelected ? clrYellow : (profit >= 0 ? clrLimeGreen : clrSalmon);
      ObjectSetInteger(0, g_prefix+lblName, OBJPROP_COLOR, rowColor);

      rowIdx++;
      y += POS_ROW_H;
   }

   if(rowIdx == 0)
   {
      Lbl("PosRow_None", x+10, y+2, "No open positions");
      ObjectSetInteger(0, g_prefix+"PosRow_None", OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, g_prefix+"PosRow_None", OBJPROP_COLOR, C'140,140,140');
   }
   else
   {
      ObjectDelete(0, g_prefix+"PosRow_None");
   }

   int objTotal = ObjectsTotal(0, -1, -1);
   for(int j = objTotal - 1; j >= 0; j--)
   {
      string nm = ObjectName(0, j);
      string base = g_prefix;
      if(StringFind(nm, base + "PosRow_") == 0 && StringFind(nm, "PosRow_None") < 0)
      {
         string tstr = StringSubstr(nm, StringLen(base + "PosRow_"));
         ulong t = (ulong)StringToInteger(tstr);
         if(t > 0 && !PositionSelectByTicket(t)) ObjectDelete(0, nm);
      }
   }
}

void RefreshPositionList()
{
   if(g_PosListX == 0 && g_PosListY == 0) return;
   RefreshManagedTicketCache();
   ValidateSelectedTicket();
   UpdateSelectedTradeLabel();
   DrawPositionList(g_PosListX, g_PosListY);
}

void Btn(string n, int x, int y, int w, int h, string t, bool act, color b = COLOR_BTN)
{
   string nm = g_prefix + n;
   if(ObjectFind(0, nm) < 0)
   {
      ObjectCreate(0, nm, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_CORNER, InpPanelCorner);
   }
   ObjectSetInteger(0, nm, OBJPROP_ZORDER, 1000);
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nm, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, nm, OBJPROP_YSIZE, h);
   ObjectSetString (0, nm, OBJPROP_TEXT, t);
   ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, act ? COLOR_ACT : b);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, COLOR_TEXT);
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, nm, OBJPROP_BORDER_COLOR, C'80,80,80');
}

void Rect(string n, int x, int y, int w, int h, color bg)
{
   string nm = g_prefix + n;
   if(ObjectFind(0, nm) < 0)
   {
      ObjectCreate(0, nm, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_CORNER, InpPanelCorner);
   }
   ObjectSetInteger(0, nm, OBJPROP_ZORDER, 999);
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nm, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, nm, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, nm, OBJPROP_BORDER_COLOR, bg);
}

void Edit(string n, int x, int y, int w, int h, string t)
{
   string nm = g_prefix + n;
   bool isNew = (ObjectFind(0, nm) < 0);
   if(isNew)
   {
      ObjectCreate(0, nm, OBJ_EDIT, 0, 0, 0);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_CORNER, InpPanelCorner);
      ObjectSetInteger(0, nm, OBJPROP_ZORDER, 1000);
      ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, COLOR_EDIT);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, COLOR_TEXT);
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, nm, OBJPROP_BORDER_COLOR, C'80,80,80');
      ObjectSetString (0, nm, OBJPROP_TEXT, t);
      ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, nm, OBJPROP_XSIZE, w);
      ObjectSetInteger(0, nm, OBJPROP_YSIZE, h);
      return;
   }

   if((int)ObjectGetInteger(0, nm, OBJPROP_XDISTANCE) != x)
      ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
   if((int)ObjectGetInteger(0, nm, OBJPROP_YDISTANCE) != y)
      ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   if((int)ObjectGetInteger(0, nm, OBJPROP_XSIZE) != w)
      ObjectSetInteger(0, nm, OBJPROP_XSIZE, w);
   if((int)ObjectGetInteger(0, nm, OBJPROP_YSIZE) != h)
      ObjectSetInteger(0, nm, OBJPROP_YSIZE, h);
}

void Lbl(string n, int x, int y, string t)
{
   string nm = g_prefix + n;
   if(ObjectFind(0, nm) < 0)
   {
      ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_CORNER, InpPanelCorner);
   }
   ObjectSetInteger(0, nm, OBJPROP_ZORDER, 1000);
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   ObjectSetString (0, nm, OBJPROP_TEXT, t);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, C'180,180,180');
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 8);
}

void Line(string sfx, double price, color col, ENUM_LINE_STYLE st, int wd, string lbl = "")
{
   string nm = g_prefix + sfx;
   if(ObjectFind(0, nm) < 0)
      ObjectCreate(0, nm, OBJ_HLINE, 0, 0, price);
   ObjectSetDouble (0, nm, OBJPROP_PRICE, price);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, col);
   ObjectSetInteger(0, nm, OBJPROP_STYLE, st);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, wd);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE,false);
   if(lbl != "") ObjectSetString(0, nm, OBJPROP_TEXT, lbl);
}

string EscapeJsonString(string _input)
{
   string output = _input;
   StringReplace(output, "\\", "\\\\");
   StringReplace(output, "\"", "\\\"");
   StringReplace(output, "\r", "");
   StringReplace(output, "\n", " ");
   return output;
}

string BuildJSON(string event_name, ulong ticket, string symbol, string side, 
                 double volume, double price, double sl, double tp, 
                 double profit, string note, string source, string screenshot_file)
{
   string json = "{";
   json += "\"timestamp\":\"" + EscapeJsonString(TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS)) + "\",";
   json += "\"event\":\"" + EscapeJsonString(event_name) + "\",";
   json += "\"ticket\":\"" + (string)ticket + "\",";
   json += "\"symbol\":\"" + EscapeJsonString(symbol) + "\",";
   json += "\"side\":\"" + EscapeJsonString(side) + "\",";
   json += "\"volume\":" + DoubleToString(volume,2) + ",";
   json += "\"price\":" + DoubleToString(price,_Digits) + ",";
   json += "\"sl\":" + DoubleToString(sl,_Digits) + ",";
   json += "\"tp\":" + DoubleToString(tp,_Digits) + ",";
   json += "\"profit\":" + DoubleToString(profit,2) + ",";
   json += "\"note\":\"" + EscapeJsonString(note) + "\",";
   json += "\"magic\":\"" + (string)InpMagicNumber + "\",";
   json += "\"source\":\"" + EscapeJsonString(source) + "\",";
   json += "\"ea_name\":\"" + EscapeJsonString(APP_SHORT_NAME) + "\",";
   json += "\"account_login\":\"" + (string)AccountInfoInteger(ACCOUNT_LOGIN) + "\",";
   json += "\"account_server\":\"" + EscapeJsonString(AccountInfoString(ACCOUNT_SERVER)) + "\",";
   json += "\"chart_symbol\":\"" + EscapeJsonString(_Symbol) + "\",";
   json += "\"screenshot_file\":\"" + EscapeJsonString(screenshot_file) + "\"";
   json += "}";
   
   return json;
}

string TakeCleanScreenshot(ulong ticket, string event_name)
{
   int total = ObjectsTotal(0, -1, -1);
   for(int i = 0; i < total; i++)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, g_prefix) == 0) 
      {
         long x = ObjectGetInteger(0, name, OBJPROP_XDISTANCE);
         ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x - 5000); 
      }
   }
   
   ChartRedraw(0);
   Sleep(50); 
   
   string baseFilename = "Journal\\" + (string)ticket + "_" + event_name + "_" + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
   StringReplace(baseFilename, ":", "");
   StringReplace(baseFilename, ".", "");
   StringReplace(baseFilename, " ", "_");
   
   string bmpFile = baseFilename + "_raw.bmp";
   string jpgFile = baseFilename + ".jpg";
   
   int chart_w = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int chart_h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   ChartScreenShot(0, bmpFile, chart_w, chart_h, ALIGN_RIGHT);
   
   for(int i = 0; i < total; i++)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, g_prefix) == 0)
      {
         long x = ObjectGetInteger(0, name, OBJPROP_XDISTANCE);
         ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x + 5000); 
      }
   }
   ChartRedraw(0);
   
   if(CompressJPEG(bmpFile, jpgFile, InpImageQuality))
   {
      FileDelete(bmpFile);
      return jpgFile;
   }
   
   return bmpFile;
}

void JournalEvent(string event_name, ulong ticket, string symbol, string side, 
                  double volume, double price, double sl, double tp, 
                  double profit, string note, string source)
{
   if(!InpEnableJournaling) return;
   
   int n = ArraySize(g_JournalQueue);
   ArrayResize(g_JournalQueue, n + 1);
   
   g_JournalQueue[n].trigger_time = TimeCurrent() + 2; 
   g_JournalQueue[n].event_name = event_name;
   g_JournalQueue[n].ticket = ticket;
   g_JournalQueue[n].symbol = symbol;
   g_JournalQueue[n].side = side;
   g_JournalQueue[n].volume = volume;
   g_JournalQueue[n].price = price;
   g_JournalQueue[n].sl = sl;
   g_JournalQueue[n].tp = tp;
   g_JournalQueue[n].profit = profit;
   g_JournalQueue[n].note = note;
   g_JournalQueue[n].source = source;
}

void ProcessJournalEvent(string event_name, ulong ticket, string symbol, string side, 
                  double volume, double price, double sl, double tp, 
                  double profit, string note, string source)
{
   if(!InpEnableJournaling) return;

   string screenshot_file = "";
   
   if(event_name == "OPEN")
   {
      screenshot_file = TakeCleanScreenshot(ticket, event_name);
   }
   
   string csv_filename = "TM3_Journal.csv";
   int handle = FileOpen(csv_filename, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON, ",");
   if(handle != INVALID_HANDLE)
   {
      if(FileSize(handle) == 0)
      {
         FileWrite(handle, "Timestamp", "Event", "Ticket", "Symbol", "Side", "Volume", "Price", "SL", "TP", "Profit", "Note", "Screenshot");
      }
      FileSeek(handle, 0, SEEK_END);
      FileWrite(handle, TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), event_name, ticket, symbol, side, volume, price, sl, tp, profit, note, screenshot_file);
      FileClose(handle);
   }

   SendJournalWebhook(event_name, ticket, symbol, side, volume, price, sl, tp, profit, note, source, screenshot_file);
}

bool SendJournalWebhook(const string event_name, const ulong ticket, const string symbol, 
                        const string side, const double volume, const double price, 
                        const double sl, const double tp, const double profit, 
                        const string note, const string source, const string screenshot_file)
{
   if(InpWebhookURL == "") return false;

   uchar file_data[];
   bool has_file = false;
   
   if(StringLen(screenshot_file) > 0)
   {
      has_file = ReadScreenshotFileToArray(screenshot_file, file_data);
   }

   if(has_file)
   {
      string boundary = BuildMultipartBoundary();
      char body[];
      ArrayResize(body, 0);

      string fields[17][2];
      fields[0][0] = "timestamp";      fields[0][1] = TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS);
      fields[1][0] = "event";          fields[1][1] = event_name;
      fields[2][0] = "ticket";         fields[2][1] = (string)ticket;
      fields[3][0] = "symbol";         fields[3][1] = symbol;
      fields[4][0] = "side";           fields[4][1] = side;
      fields[5][0] = "volume";         fields[5][1] = DoubleToString(volume,2);
      fields[6][0] = "price";          fields[6][1] = DoubleToString(price,_Digits);
      fields[7][0] = "sl";             fields[7][1] = DoubleToString(sl,_Digits);
      fields[8][0] = "tp";             fields[8][1] = DoubleToString(tp,_Digits);
      fields[9][0] = "profit";         fields[9][1] = DoubleToString(profit,2);
      fields[10][0] = "note";          fields[10][1] = note;
      fields[11][0] = "magic";         fields[11][1] = (string)InpMagicNumber;
      fields[12][0] = "source";        fields[12][1] = source;
      fields[13][0] = "ea_name";       fields[13][1] = APP_SHORT_NAME;
      fields[14][0] = "account_login"; fields[14][1] = (string)AccountInfoInteger(ACCOUNT_LOGIN);
      fields[15][0] = "account_server";fields[15][1] = AccountInfoString(ACCOUNT_SERVER);
      fields[16][0] = "chart_symbol";  fields[16][1] = _Symbol;

      for(int i = 0; i < 17; i++)
      {
         CharArrayAppendString(body, "--" + boundary + "\r\n");
         CharArrayAppendString(body, "Content-Disposition: form-data; name=\"" + fields[i][0] + "\"\r\n\r\n");
         CharArrayAppendString(body, fields[i][1] + "\r\n");
      }

      CharArrayAppendString(body, "--" + boundary + "\r\n");
      CharArrayAppendString(body, "Content-Disposition: form-data; name=\"screenshot\"; filename=\"" + screenshot_file + "\"\r\n");
      CharArrayAppendString(body, "Content-Type: image/jpeg\r\n\r\n");
      CharArrayAppendBytes(body, file_data);
      CharArrayAppendString(body, "\r\n");
      CharArrayAppendString(body, "--" + boundary + "--\r\n");

      char response_body[];
      string response_headers;
      string headers = "Content-Type: multipart/form-data; boundary=" + boundary + "\r\n";

      ResetLastError();
      int http_code = WebRequest("POST", InpWebhookURL, headers, 10000, body, response_body, response_headers);
      
      if(http_code < 200 || http_code >= 300)
         Print("[TM3] Multipart Webhook failed. HTTP=", http_code, " Err=", GetLastError());
      
      return (http_code >= 200 && http_code < 300);
   }
   else 
   {
      string payload = BuildJSON(event_name, ticket, symbol, side, volume, price, sl, tp, profit, note, source, "");
      
      char request_body[];
      char response_body[];
      string response_headers;

      StringToCharArray(payload, request_body, 0, WHOLE_ARRAY, CP_UTF8);
      if(ArraySize(request_body) > 0) 
         ArrayResize(request_body, ArraySize(request_body) - 1); 

      string headers = "Content-Type: application/json\r\n";

      ResetLastError();
      int http_code = WebRequest("POST", InpWebhookURL, headers, 5000, request_body, response_body, response_headers);
      
      if(http_code < 200 || http_code >= 300)
         Print("[TM3] JSON Webhook failed. HTTP=", http_code, " Err=", GetLastError());
         
      return (http_code >= 200 && http_code < 300);
   }
}

string BuildMultipartBoundary()
{
   return("----TM3Boundary" + IntegerToString((int)TimeLocal()) + IntegerToString(GetTickCount()));
}

bool ReadScreenshotFileToArray(const string file_name, uchar &data[])
{
   ArrayResize(data, 0);
   if(StringLen(file_name) <= 0) return false;

   int handle = FileOpen(file_name, FILE_READ|FILE_BIN|FILE_SHARE_READ);
   if(handle == INVALID_HANDLE)
   {
      Print("[TM3] Cannot open screenshot '", file_name, "' err=", GetLastError());
      return false;
   }

   ulong size = FileSize(handle);
   if(size == 0 || size > 15000000)
   {
      FileClose(handle);
      Print("[TM3] Screenshot size invalid: ", size);
      return false;
   }

   ArrayResize(data, (int)size);
   uint read = FileReadArray(handle, data, 0, (int)size);
   FileClose(handle);

   if(read != size)
   {
      ArrayResize(data, 0);
      Print("[TM3] Screenshot read incomplete");
      return false;
   }

   return true;
}

void CharArrayAppendString(char &body[], const string text)
{
   uchar tmp[];
   StringToCharArray(text, tmp, 0, WHOLE_ARRAY, CP_UTF8);
   int add = ArraySize(tmp);
   if(add <= 0) return;
   
   add--; 
   if(add <= 0) return;

   int old = ArraySize(body);
   ArrayResize(body, old + add);
   for(int i = 0; i < add; i++) body[old + i] = (char)tmp[i];
}

void CharArrayAppendBytes(char &body[], const uchar &data[])
{
   int add = ArraySize(data);
   if(add <= 0) return;

   int old = ArraySize(body);
   ArrayResize(body, old + add);
   for(int i = 0; i < add; i++) body[old + i] = (char)data[i];
}

bool CompressJPEG(string inputFile, string outputFile, uint qualityLevel)
{
   string dataPath = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\";
   string absInput = dataPath + inputFile;
   string absOutput = dataPath + outputFile;

   uchar startupInput[24] = {1,0,0,0, 0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0, 0,0,0,0};
   ulong gdiToken = 0;
   if(GdiplusStartup(gdiToken, startupInput, 0) != 0) return false;

   uchar jpegClsid[16];
   CLSIDFromString("{557CF401-1A04-11D3-9A73-0000F81EF32E}", jpegClsid);

   ulong imagePtr = 0;
   if(GdipLoadImageFromFile(absInput, imagePtr) != 0)
   {
      GdiplusShutdown(gdiToken);
      return false;
   }

   ulong valPtr = GlobalAlloc(0x0040, 4);
   uint qualArr[1];
   qualArr[0] = qualityLevel;
   RtlMoveMemory(valPtr, qualArr, 4);

   uchar encParams[40];
   ArrayInitialize(encParams, 0);
   encParams[0] = 1;
   
   uchar guid[16] = {0xB5,0xE4,0x5B,0x1D, 0x4A,0xFA, 0x2D,0x45, 0x9C,0xDD, 0x5D,0xB3,0x51,0x05,0xE7,0xEB};
   ArrayCopy(encParams, guid, 8, 0, 16);
   
   encParams[24] = 1;
   encParams[28] = 4;
   
   ULongToBytes ptrConv;
   ptrConv.value = valPtr;
   ArrayCopy(encParams, ptrConv.bytes, 32, 0, 8);

   int res = GdipSaveImageToFile(imagePtr, absOutput, jpegClsid, encParams);

   GlobalFree(valPtr);
   GdipDisposeImage(imagePtr);
   GdiplusShutdown(gdiToken);

   return (res == 0);
}
//+------------------------------------------------------------------+