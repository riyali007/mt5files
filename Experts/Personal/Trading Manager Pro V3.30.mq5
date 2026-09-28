//+------------------------------------------------------------------+
//| Trading-Manager-Pro-V3.34.mq5                                    |
//| Riy Tech — v3.34 group survival + runner TP                      |
//| Groups are comment-scoped (Gid / Did), not symbol-scoped.        |
//+------------------------------------------------------------------+
#property copyright "Riy Tech"
#property version   "3.34"
#property strict
#property description "TM3.34 survival basket (2nd DD) + runner TP"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| Windows GDI+ and Kernel32 API Imports (JPEG compression)         |
//+------------------------------------------------------------------+
#import "gdiplus.dll"
int  GdiplusStartup(ulong &token, uchar &gdiInput[], ulong gdiOutput);
void GdiplusShutdown(ulong token);
int  GdipLoadImageFromFile(string filename, ulong &image);
int  GdipDisposeImage(ulong image);
int  GdipSaveImageToFile(ulong image, string filename, uchar &clsid[], uchar &encoderParams[]);
#import

#import "ole32.dll"
int  CLSIDFromString(string lpsz, uchar &pclsid[]);
#import

#import "kernel32.dll"
ulong GlobalAlloc(uint uFlags, ulong dwBytes);
ulong GlobalFree(ulong hMem);
void  RtlMoveMemory(ulong dest, uint &src[], ulong length);
#import

union ULongToBytes
{
   ulong value;
   uchar bytes[8];
};

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+
input group "Panel Settings"
input ENUM_BASE_CORNER InpPanelCorner = CORNER_LEFT_UPPER;

input group "Risk Settings"
input double InpDefaultLot     = 0.3;   // Default Lot Size
input double InpDefaultRiskPct = 1.0;   // Default Risk % of Equity
input int    InpDefaultSL      = 500;   // Default SL (points)
input int    InpDefaultTP      = 1000;  // Default TP (points)

input group "Inverse Order Settings"
input int InpInverseOffset = 50;        // Inverse Pending Offset (points)

input group "DrawDown Entries"
input bool   InpEnableDDEntries  = true;
input int    InpDD_OrderCount    = 4;
input bool   InpDD_AutoSpacingSL = true;
input int    InpDD_Spacing       = 200;
input bool   InpDD_SameSL        = true;
input bool   InpDD_ScaleLots     = true;
input double InpDD_LotStartPct   = 25.0;
input double InpDD_LotEndPct     = 100.0;

input group "Partial Settings"
input double InpMainPartialVol    = 40.0;
input double InpRollingPartialVol = 20.0;
input int    InpDefaultPartial    = 3;

input group "Breakeven Settings"
input int InpBE_Trigger = 1;
input int InpBE_Offset  = 20;

input group "Trailing Stop Settings"
input bool InpUseTrailingStop = true;
input int  InpTrailingStart   = 1000;
input int  InpTrailingStep    = 600;

input group "Survival Mode"
input bool InpEnableSurvival  = true;  // Arm after Nth DD fill, close group at combined BE
input int  InpSurvivalDDFill  = 2;     // Which DD fill arms survival (2 = 2nd DD)

input group "Runner TP"
input bool InpEnableRunner = true;     // Extend TP when price is within Runner points of TP
input int  InpRunnerPoints = 200;      // Push TP by this many points

input group "Sound Settings"
input bool   InpEnableSounds      = true;
input string InpSoundEntry        = "Ok.wav";
input string InpSoundOk           = "Ok.wav";
input string InpSoundPartial      = "News.wav";
input string InpSoundBE           = "Expert.wav";
input string InpSoundSL           = "timeout.wav";
input string InpSoundTP           = "alert.wav";
input string InpSoundClose        = "stops.wav";

input group "External Trade Monitoring"
input bool   InpMonitorExternal   = true;
input bool   InpExternalAlerts    = true;
input string InpSoundExtDetected  = "notify.wav";
input bool   InpAutoAdoptExternal = true;
input bool   InpOverwriteExtSLTP  = false;

input group "Trade Limits"
input int InpMaxOpenTrades = 10;

input group "Auto Trade Handler"
input bool InpBasketEnabled     = true;
input int  InpBasketGreenPoints = 0;
input bool InpWorstAutoSL       = false;

input group "Journaling Settings"
input bool   InpEnableJournaling = true;
input string InpWebhookURL       = "https://your-webhook-url.com/endpoint";
input string APP_SHORT_NAME      = "TM3_Pro";
input int    InpMagicNumber      = 234567;
input int    InpImageQuality     = 30;

//+------------------------------------------------------------------+
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

enum ENUM_ORDER_TYPE_UI { UI_MARKET, UI_LIMIT };
enum ENUM_SIDE_UI       { UI_BUY, UI_SELL };

struct UIState
{
   ENUM_ORDER_TYPE_UI orderType;
   ENUM_SIDE_UI       side;
   double             lotSize;
   double             riskPercent;
   int                slPoints;
   int                tpPoints;
   double             slPrice;
   double             tpPrice;
   int                partialsCount;
   double             customPrice;
   bool               isVisualizing;
   bool               basketEnabled;
   bool               worstAutoSL;
   bool               inverseEnabled;
};

struct ExtTradeRec { ulong ticket; long posID; bool alertSent; bool adopted; };

struct PosState
{
   long   posID;
   ulong  ticket;
   int    partialsTaken;
   bool   beSet;
   double lastSL;
   double lastTP;
};

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

string         g_prefix;
UIState        ui;
CTrade         trade;
CPositionInfo  posInfo;
int            g_ChartW = 0;
int            g_ChartH = 0;
datetime       g_LastExtScan = 0;
int            g_BasketPts = 0;
ExtTradeRec    g_ExtTrades[];
PosState       g_PosStates[];
int            g_PosListX = 0;
int            g_PosListY = 0;
ulong          g_SelectedTicket = 0;
bool           g_HasOpenTrades = false;
double         g_TickValue = 0.0;
double         g_TickSize  = 0.0;
double         g_PointMult = 0.0;
ulong          g_ManagedTickets[];
int            g_GroupSeq = 0;
string         g_SurvivalStatus = "";

void RecomputeHasOpenTrades();
void SaveState();
void LoadState();
void ClearState();
void RebuildPanel(bool updateUI = false);
void CreatePanelElements(int x, int y);
void UpdatePanelUI();
void UpdateSLTPPrices(double entry);
void UpdateStats(double priceRef);
void UpdatePartialLine(int x, int &y);
int  PartialLinesHeight();
int  PanelHeight();
void ToggleVisualization();
void DrawVisualization();
void DrawSideVis(double ep, ENUM_SIDE_UI side);
void ExecuteOrder();
double NormaliseVolume(double vol);
void ManualPartial();
void CycleSelectedTrade(int direction);
void ValidateSelectedTicket();
void CloseSelectedTrade();
int  BuildManagedTicketList(ulong &list[]);
void UpdateSelectedTradeLabel();
ulong GetManagedTicketByOffset(int offset);
int  FindManagedTicketIndex(ulong ticket);
void CloseAll();
void SetBreakEvenManual();
void SetBreakEvenTicket(ulong ticket);
void CloseTicket(ulong ticket);
void ManagePositions();
void ManageTrailingStop();
void ManageRunner();
void ManageSurvival();
void ScanExternalTrades();
void AdoptExternalTrade(ulong ticket);
void ManageDrawdownBasket();
void ProcessBasketByType(ENUM_POSITION_TYPE type);
void CleanupOrphanedLines();
void SyncPosStates();
void RemovePosState(long posID);
bool IsRegisteredExternal(ulong ticket);
void RemoveClosedExternals();
bool IsManagedPosition();
int  CountManagedOpenPositions();
double NormaliseSL(double price);
double NormalisePrice(const string sym, double price);
void ToggleBasket();
void ToggleWorstAutoSL();
void DrawPositionList(int x, int y);
void RefreshPositionList();
int  PositionListHeight();
void ExportToCSV();
void RecalculateLotFromRisk();
void RecalculateRiskFromLot();
void UpdateSymbolCache();
void CancelAllLimitOrders();
void SetSLAllPositions(double slPrice);
int  NextGroupId();
int  GroupIdFromComment(const string cmt, bool &isDD);
string GroupComment(const int gid, const bool isDD);
void RegisterDDFill(const int gid);
bool IsGroupArmed(const int gid);
void ArmGroup(const int gid);
void CancelGroupOrders(const int gid);
void CloseGroup(const int gid);
int  CountOpenDD(const int gid);
void RebuildSurvivalFromHistory();
int  MagicNumber();

int MagicNumber()
{
   return InpMagicNumber;
}

int OnInit()
{
   g_prefix = "TM3_" + IntegerToString(ChartID()) + "_";
   ui.orderType = UI_MARKET;
   ui.side = UI_BUY;
   ui.lotSize = InpDefaultLot;
   ui.riskPercent = InpDefaultRiskPct;
   ui.slPoints = InpDefaultSL;
   ui.tpPoints = InpDefaultTP;
   ui.partialsCount = InpDefaultPartial;
   ui.isVisualizing = false;
   ui.basketEnabled = InpBasketEnabled;
   ui.worstAutoSL = InpWorstAutoSL;
   ui.inverseEnabled = false;
   ui.customPrice = 0;
   g_BasketPts = InpBasketGreenPoints;

   UpdateSymbolCache();
   LoadState();
   RecalculateRiskFromLot();
   trade.SetExpertMagicNumber(MagicNumber());
   trade.SetDeviationInPoints(20);
   SyncPosStates();
   RebuildSurvivalFromHistory();
   RecomputeHasOpenTrades();
   RebuildPanel(true);
   UpdateSLTPPrices(SymbolInfoDouble(_Symbol, SYMBOL_ASK));
   PrintFormat("[TM3 v3.34] Ready | Survival=%s after DD#%d | Runner=%s %d pts",
               InpEnableSurvival ? "ON" : "OFF", InpSurvivalDDFill,
               InpEnableRunner ? "ON" : "OFF", InpRunnerPoints);
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

void UpdateSymbolCache()
{
   g_TickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   g_TickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(g_TickSize > 0 && _Point > 0)
      g_PointMult = (_Point / g_TickSize) * g_TickValue;
   else
      g_PointMult = 1.0;
}

void RecalculateLotFromRisk()
{
   UpdateSymbolCache();
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0 || ui.slPoints <= 0 || g_PointMult <= 0) return;
   double riskAmount = equity * (ui.riskPercent / 100.0);
   double calculatedLot = riskAmount / (ui.slPoints * g_PointMult);
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(stepLot <= 0) stepLot = 0.01;
   calculatedLot = MathFloor(calculatedLot / stepLot) * stepLot;
   calculatedLot = MathMax(minLot, MathMin(maxLot, calculatedLot));
   ui.lotSize = NormalizeDouble(calculatedLot, 2);
   if(ObjectFind(0, g_prefix + "Edit_Lot") >= 0)
      ObjectSetString(0, g_prefix + "Edit_Lot", OBJPROP_TEXT, DoubleToString(ui.lotSize, 2));
}

void RecalculateRiskFromLot()
{
   UpdateSymbolCache();
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0 || ui.slPoints <= 0 || g_PointMult <= 0) return;
   double riskAmount = ui.lotSize * ui.slPoints * g_PointMult;
   ui.riskPercent = NormalizeDouble((riskAmount / equity) * 100.0, 2);
   if(ObjectFind(0, g_prefix + "Edit_RiskPct") >= 0)
      ObjectSetString(0, g_prefix + "Edit_RiskPct", OBJPROP_TEXT, DoubleToString(ui.riskPercent, 2));
}

//+------------------------------------------------------------------+
//| Group identity — stored in order/position comment, any symbol    |
//+------------------------------------------------------------------+
int NextGroupId()
{
   g_GroupSeq++;
   int id = (int)(TimeCurrent() % 1000000);
   id = id * 10 + (g_GroupSeq % 10);
   if(id <= 0) id = g_GroupSeq;
   return id;
}

int GroupIdFromComment(const string cmt, bool &isDD)
{
   isDD = false;
   if(StringLen(cmt) < 2) return 0;
   ushort ch = StringGetCharacter(cmt, 0);
   if(ch == 'D') isDD = true;
   else if(ch != 'G') return 0;
   int id = (int)StringToInteger(StringSubstr(cmt, 1));
   return (id > 0 ? id : 0);
}

string GroupComment(const int gid, const bool isDD)
{
   return (isDD ? "D" : "G") + IntegerToString(gid);
}

string FillKey(const int gid) { return "TM3SV_"  + IntegerToString(gid); }
string ArmKey(const int gid)  { return "TM3ARM_" + IntegerToString(gid); }

bool IsGroupArmed(const int gid)
{
   return GlobalVariableCheck(ArmKey(gid)) && GlobalVariableGet(ArmKey(gid)) > 0.5;
}

void RegisterDDFill(const int gid)
{
   if(gid <= 0 || !InpEnableSurvival) return;
   string key = FillKey(gid);
   double v = GlobalVariableCheck(key) ? GlobalVariableGet(key) : 0.0;
   v += 1.0;
   GlobalVariableSet(key, v);
   PrintFormat("[TM3] Group %d DD fill #%d", gid, (int)v);
   if((int)v >= InpSurvivalDDFill)
      ArmGroup(gid);
}

void ArmGroup(const int gid)
{
   if(gid <= 0) return;
   bool already = IsGroupArmed(gid);
   GlobalVariableSet(ArmKey(gid), 1.0);
   CancelGroupOrders(gid);
   if(!already)
   {
      g_SurvivalStatus = "SURV G" + IntegerToString(gid);
      PrintFormat("[TM3] Survival ARMED group %d — waiting for combined P/L >= 0", gid);
      if(InpEnableSounds) PlaySound(InpSoundBE);
   }
}

void CancelGroupOrders(const int gid)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ot = OrderGetTicket(i);
      if(ot == 0 || !OrderSelect(ot)) continue;
      if((int)OrderGetInteger(ORDER_MAGIC) != MagicNumber()) continue;
      bool isDD = false;
      int id = GroupIdFromComment(OrderGetString(ORDER_COMMENT), isDD);
      if(id == gid)
         trade.OrderDelete(ot);
   }
}

int CountOpenDD(const int gid)
{
   int cnt = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if((int)posInfo.Magic() != MagicNumber()) continue;
      bool isDD = false;
      int id = GroupIdFromComment(posInfo.Comment(), isDD);
      if(id == gid && isDD) cnt++;
   }
   return cnt;
}

void CloseGroup(const int gid)
{
   bool any = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber()) continue;
      bool isDD = false;
      int id = GroupIdFromComment(PositionGetString(POSITION_COMMENT), isDD);
      if(id != gid) continue;
      if(trade.PositionClose(ticket)) any = true;
   }
   CancelGroupOrders(gid);
   GlobalVariableSet(ArmKey(gid), 0.0);
   g_SurvivalStatus = "";
   if(any && InpEnableSounds) PlaySound(InpSoundClose);
   PrintFormat("[TM3] Survival closed group %d at combined break-even", gid);
   RecomputeHasOpenTrades();
}

void RebuildSurvivalFromHistory()
{
   if(!InpEnableSurvival) return;
   datetime from = TimeCurrent() - 30 * 86400;
   if(!HistorySelect(from, TimeCurrent())) return;

   int ids[];
   int counts[];
   int deals = HistoryDealsTotal();
   for(int i = 0; i < deals; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      if((int)HistoryDealGetInteger(deal, DEAL_MAGIC) != MagicNumber()) continue;
      if(HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
      bool isDD = false;
      int gid = GroupIdFromComment(HistoryDealGetString(deal, DEAL_COMMENT), isDD);
      if(!isDD || gid <= 0) continue;
      int idx = -1;
      for(int k = 0; k < ArraySize(ids); k++)
         if(ids[k] == gid) { idx = k; break; }
      if(idx < 0)
      {
         idx = ArraySize(ids);
         ArrayResize(ids, idx + 1);
         ArrayResize(counts, idx + 1);
         ids[idx] = gid;
         counts[idx] = 0;
      }
      counts[idx]++;
   }

   for(int k = 0; k < ArraySize(ids); k++)
   {
      string key = FillKey(ids[k]);
      double cur = GlobalVariableCheck(key) ? GlobalVariableGet(key) : 0.0;
      double use = MathMax(cur, (double)counts[k]);
      GlobalVariableSet(key, use);
      if((int)use >= InpSurvivalDDFill)
         ArmGroup(ids[k]);
   }
}

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
         long   entry  = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
         string symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
         long   type   = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
         double vol    = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
         double price  = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
         int    magic  = (int)HistoryDealGetInteger(trans.deal, DEAL_MAGIC);

         if(entry == DEAL_ENTRY_IN)
         {
            string side = (type == DEAL_TYPE_BUY) ? "BUY" : "SELL";
            JournalEvent("OPEN", ticket, symbol, side, vol, price, 0, 0, 0, "Trade Opened", "System");
            if(magic == MagicNumber() && InpEnableSurvival)
            {
               bool isDD = false;
               int gid = GroupIdFromComment(HistoryDealGetString(trans.deal, DEAL_COMMENT), isDD);
               if(isDD && gid > 0)
               {
                  static ulong lastDDDeal = 0;
                  if(lastDDDeal != trans.deal)
                  {
                     lastDDDeal = trans.deal;
                     RegisterDDFill(gid);
                  }
               }
            }
         }
         else if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
         {
            string actual_side = (type == DEAL_TYPE_SELL) ? "BUY" : "SELL";
            double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                          + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION)
                          + HistoryDealGetDouble(trans.deal, DEAL_SWAP);
            long reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
            string event_type = "";
            if(PositionSelectByTicket(ticket))
               event_type = "PARTIAL";
            else
            {
               ulong order_ticket = (ulong)HistoryDealGetInteger(trans.deal, DEAL_ORDER);
               double order_sl = 0, order_tp = 0;
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
                     if(actual_side == "BUY"  && price <= order_sl) is_sl_hit = true;
                     if(actual_side == "SELL" && price >= order_sl) is_sl_hit = true;
                  }
                  if(order_tp > 0)
                  {
                     if(actual_side == "BUY"  && price >= order_tp) is_tp_hit = true;
                     if(actual_side == "SELL" && price <= order_tp) is_tp_hit = true;
                  }
               }
               if(is_sl_hit)      event_type = (profit < 0 ? "SL_Hit" : "BE_Hit");
               else if(is_tp_hit) event_type = "TP_Hit";
               else               event_type = "Manually_Closed";
            }
            JournalEvent(event_type, ticket, symbol, actual_side, vol, price, 0, 0, profit, "Position Exit", "System");
         }
      }
   }
   else if(trans.type == TRADE_TRANSACTION_POSITION)
      RecomputeHasOpenTrades();
}

void RecomputeHasOpenTrades()
{
   g_HasOpenTrades = (PositionsTotal() > 0);
}

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
            UpdateSLTPPrices(ui.customPrice);
         double ref = (ui.orderType == UI_LIMIT) ? ui.customPrice : curr;
         UpdateStats(ref);
      }
   }

   if(g_HasOpenTrades)
   {
      ScanExternalTrades();
      ManagePositions();
      ManageRunner();
      ManageTrailingStop();
      ManageDrawdownBasket();
      ManageSurvival();
   }
   else if(InpMonitorExternal)
      ScanExternalTrades();

   static ulong lastPosListMs = 0;
   static bool  wasFlat = true;
   if(nowMs - lastPosListMs >= 500)
   {
      lastPosListMs = nowMs;
      if(!g_HasOpenTrades)
      {
         if(!wasFlat)
         {
            g_SelectedTicket = 0;
            ArrayResize(g_ManagedTickets, 0);
            g_SurvivalStatus = "";
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
            RefreshPositionList();
      }
   }

   static datetime lastCleanup = 0;
   if(TimeCurrent() - lastCleanup >= 3)
   {
      CleanupOrphanedLines();
      lastCleanup = TimeCurrent();
   }
}

void OnTimer()
{
   int n = ArraySize(g_JournalQueue);
   if(n == 0) return;
   if(TimeCurrent() >= g_JournalQueue[0].trigger_time)
   {
      ProcessJournalEvent(g_JournalQueue[0].event_name, g_JournalQueue[0].ticket, g_JournalQueue[0].symbol,
                          g_JournalQueue[0].side, g_JournalQueue[0].volume, g_JournalQueue[0].price,
                          g_JournalQueue[0].sl, g_JournalQueue[0].tp, g_JournalQueue[0].profit,
                          g_JournalQueue[0].note, g_JournalQueue[0].source);
      for(int i = 0; i < n - 1; i++)
         g_JournalQueue[i] = g_JournalQueue[i + 1];
      ArrayResize(g_JournalQueue, n - 1);
   }
}

void OnChartEvent(const int id, const long &lp, const double &dp, const string &sp)
{
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      int w = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
      int h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
      if(w != g_ChartW || h != g_ChartH)
      {
         g_ChartW = w;
         g_ChartH = h;
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
         UpdatePanelUI();
         SaveState();
      }
      if(sp == g_prefix + "Btn_Buy")      { ui.side = UI_BUY;  UpdatePanelUI(); ExecuteOrder(); SaveState(); }
      if(sp == g_prefix + "Btn_Sell")     { ui.side = UI_SELL; UpdatePanelUI(); ExecuteOrder(); SaveState(); }
      if(sp == g_prefix + "Btn_Vis")      ToggleVisualization();
      if(sp == g_prefix + "Btn_Part")     ManualPartial();
      if(sp == g_prefix + "Btn_BE")       SetBreakEvenManual();
      if(sp == g_prefix + "Btn_CloseAll") CloseAll();
      if(sp == g_prefix + "Btn_Export")   ExportToCSV();
      if(sp == g_prefix + "Btn_Inverse")  { ui.inverseEnabled = !ui.inverseEnabled; UpdatePanelUI(); SaveState(); }
      if(sp == g_prefix + "Btn_Basket")   ToggleBasket();
      if(sp == g_prefix + "Btn_WorstSL")  ToggleWorstAutoSL();
      if(sp == g_prefix + "Btn_SelPrev")  CycleSelectedTrade(-1);
      if(sp == g_prefix + "Btn_SelNext")  CycleSelectedTrade(1);
      if(sp == g_prefix + "Btn_CloseSel") CloseSelectedTrade();
   }

   if(id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      double entry = (ui.orderType == UI_LIMIT) ? ui.customPrice
                     : ((ui.side == UI_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID));
      if(sp == g_prefix + "Edit_RiskPct")
      {
         ui.riskPercent = StringToDouble(ObjectGetString(0, sp, OBJPROP_TEXT));
         RecalculateLotFromRisk();
      }
      if(sp == g_prefix + "Edit_Lot")
      {
         ui.lotSize = StringToDouble(ObjectGetString(0, sp, OBJPROP_TEXT));
         RecalculateRiskFromLot();
      }
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
         RecalculateRiskFromLot();
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
         if(entry > 0)
         {
            ui.slPoints = (int)MathAbs((entry - p) / _Point);
            ObjectSetString(0, g_prefix + "Edit_SL", OBJPROP_TEXT, IntegerToString(ui.slPoints));
            RecalculateRiskFromLot();
         }
      }
      if(sp == g_prefix + "Edit_TP_Prc")
      {
         double p = StringToDouble(ObjectGetString(0, sp, OBJPROP_TEXT));
         if(entry > 0)
         {
            ui.tpPoints = (int)MathAbs((entry - p) / _Point);
            ObjectSetString(0, g_prefix + "Edit_TP", OBJPROP_TEXT, IntegerToString(ui.tpPoints));
            RebuildPanel(true);
         }
      }
      if(sp == g_prefix + "Edit_GreenPts")
         g_BasketPts = (int)StringToInteger(ObjectGetString(0, sp, OBJPROP_TEXT));
      if(ui.isVisualizing) DrawVisualization();
      UpdateStats(entry);
      SaveState();
   }
}

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
      bool isOwn = ((int)posInfo.Magic() == MagicNumber());
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

void CancelAllLimitOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ot = OrderGetTicket(i);
      if(OrderGetString(ORDER_SYMBOL) == _Symbol)
      {
         if((int)OrderGetInteger(ORDER_MAGIC) == MagicNumber() || InpMonitorExternal)
            trade.OrderDelete(ot);
      }
   }
}

void SetSLAllPositions(double slPrice)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      bool isOwn = ((int)posInfo.Magic() == MagicNumber());
      bool isExt = InpMonitorExternal && IsRegisteredExternal(posInfo.Ticket());
      if(isOwn || isExt)
      {
         trade.PositionModify(posInfo.Ticket(), slPrice, posInfo.TakeProfit());
         int idx = FindPosStateIdx(posInfo.Identifier());
         if(idx >= 0) g_PosStates[idx].beSet = true;
      }
   }
}

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
      bool isOwn = ((int)posInfo.Magic() == MagicNumber());
      bool isExt = InpMonitorExternal && IsRegisteredExternal(posInfo.Ticket());
      if(!isOwn && !isExt) continue;

      long   pid    = posInfo.Identifier();
      ulong  ticket = posInfo.Ticket();
      double open   = posInfo.PriceOpen();
      double tp     = posInfo.TakeProfit();
      double curSL  = posInfo.StopLoss();
      double curTP  = posInfo.TakeProfit();
      bool   isBuy  = (posInfo.PositionType() == POSITION_TYPE_BUY);
      if(tp == 0.0) continue;
      double totalDist = MathAbs(tp - open);
      if(totalDist < _Point) continue;

      EnsurePosState(pid, ticket);
      int stIdx = FindPosStateIdx(pid);
      if(stIdx < 0) continue;

      if(g_PosStates[stIdx].lastSL != curSL)
      {
         if(g_PosStates[stIdx].lastSL != 0.0 && g_PosStates[stIdx].beSet == false)
            JournalEvent("SL_CHANGE", ticket, _Symbol, isBuy ? "BUY" : "SELL", posInfo.Volume(), open, curSL, curTP, 0, "SL Modified", "System");
         g_PosStates[stIdx].lastSL = curSL;
      }
      if(g_PosStates[stIdx].lastTP != curTP)
      {
         if(g_PosStates[stIdx].lastTP != 0.0)
            JournalEvent("TP_CHANGE", ticket, _Symbol, isBuy ? "BUY" : "SELL", posInfo.Volume(), open, curSL, curTP, 0, "TP Modified", "System");
         g_PosStates[stIdx].lastTP = curTP;
      }

      int    totalPartials = ui.partialsCount;
      if(totalPartials < 1) continue;
      double step = totalDist / (totalPartials + 1);
      int    taken = g_PosStates[stIdx].partialsTaken;
      bool   beSet = g_PosStates[stIdx].beSet;
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
      if(amt >= posInfo.Volume()) continue;
      if(!trade.PositionClosePartial(ticket, amt)) continue;

      g_PosStates[stIdx].partialsTaken = nextPartial;
      if(InpEnableSounds) PlaySound(InpSoundPartial);

      if(nextPartial == 1)
      {
         CancelAllLimitOrders();
         SetSLAllPositions(NormaliseSL(open));
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
               g_PosStates[stIdx].beSet = true;
            if(g_PosStates[stIdx].beSet)
               JournalEvent("SL_CHANGE", ticket, _Symbol, isBuy ? "BUY" : "SELL", posInfo.Volume(), open, curSL, curTP, 0, "SL Set to BE", "System");
         }
      }
   }
   RecomputeHasOpenTrades();
}

//+------------------------------------------------------------------+
//| Runner: distance to current TP <= N points -> push TP + N        |
//| Trailing stop is not modified here.                              |
//+------------------------------------------------------------------+
void ManageRunner()
{
   if(!InpEnableRunner || InpRunnerPoints <= 0) return;
   static ulong lastRunMs = 0;
   ulong nowMs = (ulong)GetTickCount();
   if(nowMs - lastRunMs < 200) return;
   lastRunMs = nowMs;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber() &&
         !(InpMonitorExternal && IsRegisteredExternal(ticket)))
         continue;

      string sym = PositionGetString(POSITION_SYMBOL);
      double point = SymbolInfoDouble(sym, SYMBOL_POINT);
      if(point <= 0) continue;
      double curTP = PositionGetDouble(POSITION_TP);
      double curSL = PositionGetDouble(POSITION_SL);
      if(curTP <= 0) continue;

      bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double bid = SymbolInfoDouble(sym, SYMBOL_BID);
      double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
      double distPts = isBuy ? (curTP - bid) / point : (ask - curTP) / point;
      if(distPts > InpRunnerPoints) continue;

      double newTP = isBuy ? curTP + InpRunnerPoints * point : curTP - InpRunnerPoints * point;
      int stops = (int)SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
      double minDist = stops * point;
      if(isBuy && newTP < ask + minDist) newTP = ask + minDist;
      if(!isBuy && (newTP > bid - minDist || newTP <= 0)) newTP = bid - minDist;
      newTP = NormalisePrice(sym, newTP);
      if(MathAbs(newTP - curTP) < point) continue;
      trade.PositionModify(ticket, curSL, newTP);
   }
}

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
      bool isOwn = ((int)posInfo.Magic() == MagicNumber());
      bool isExt = InpMonitorExternal && IsRegisteredExternal(posInfo.Ticket());
      if(!isOwn && !isExt) continue;

      double open  = posInfo.PriceOpen();
      double curSL = posInfo.StopLoss();
      double curTP = posInfo.TakeProfit();
      double pt    = _Point;
      bool   isBuy = (posInfo.PositionType() == POSITION_TYPE_BUY);

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
//| Survival: armed group closes only when combined net P/L >= 0     |
//+------------------------------------------------------------------+
void ManageSurvival()
{
   if(!InpEnableSurvival) return;
   static ulong lastSv = 0;
   ulong nowMs = (ulong)GetTickCount();
   if(nowMs - lastSv < 200) return;
   lastSv = nowMs;

   int gids[];
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber()) continue;
      bool isDD = false;
      int gid = GroupIdFromComment(PositionGetString(POSITION_COMMENT), isDD);
      if(gid <= 0) continue;

      if(!IsGroupArmed(gid))
      {
         int fills = 0;
         if(GlobalVariableCheck(FillKey(gid)))
            fills = (int)GlobalVariableGet(FillKey(gid));
         int openDD = CountOpenDD(gid);
         if(openDD > fills)
         {
            GlobalVariableSet(FillKey(gid), openDD);
            fills = openDD;
         }
         if(fills >= InpSurvivalDDFill)
            ArmGroup(gid);
      }
      if(!IsGroupArmed(gid)) continue;

      bool seen = false;
      for(int k = 0; k < ArraySize(gids); k++)
         if(gids[k] == gid) { seen = true; break; }
      if(!seen)
      {
         int n = ArraySize(gids);
         ArrayResize(gids, n + 1);
         gids[n] = gid;
      }
   }

   for(int g = 0; g < ArraySize(gids); g++)
   {
      int gid = gids[g];
      double pnl = 0.0;
      int count = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
         if((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber()) continue;
         bool isDD = false;
         int id = GroupIdFromComment(PositionGetString(POSITION_COMMENT), isDD);
         if(id != gid) continue;
         pnl += PositionGetDouble(POSITION_PROFIT)
              + PositionGetDouble(POSITION_SWAP)
              + PositionGetDouble(POSITION_COMMISSION);
         count++;
      }
      g_SurvivalStatus = StringFormat("SURV G%d %+.2f", gid, pnl);
      if(count > 0 && pnl >= 0.0)
         CloseGroup(gid);
   }
}

void ExecuteOrder()
{
   if(CountManagedOpenPositions() >= InpMaxOpenTrades)
   {
      Alert(StringFormat("[TM3] Max managed trades reached (%d)", InpMaxOpenTrades));
      return;
   }

   double p = (ui.orderType == UI_LIMIT)
              ? ui.customPrice
              : ((ui.side == UI_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID));

   bool isInverse = (ui.orderType == UI_MARKET && ui.inverseEnabled);
   if(isInverse)
   {
      if(ui.side == UI_BUY) p = SymbolInfoDouble(_Symbol, SYMBOL_BID) - InpInverseOffset * _Point;
      else                  p = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + InpInverseOffset * _Point;
      p = NormaliseSL(p);
   }

   int gid = NextGroupId();
   string cmtMain = GroupComment(gid, false);
   string cmtDD   = GroupComment(gid, true);

   double sl = (ui.slPoints > 0) ? ((ui.side == UI_BUY) ? p - ui.slPoints * _Point : p + ui.slPoints * _Point) : 0;
   double tp = (ui.side == UI_BUY) ? p + ui.tpPoints * _Point : p - ui.tpPoints * _Point;
   sl = (sl > 0 ? NormaliseSL(sl) : 0);
   tp = NormaliseSL(tp);
   bool res = false;

   if(ui.orderType == UI_MARKET && !isInverse)
   {
      if(ui.side == UI_BUY) res = trade.Buy (ui.lotSize, _Symbol, p, sl, tp, cmtMain);
      else                  res = trade.Sell(ui.lotSize, _Symbol, p, sl, tp, cmtMain);
   }
   else
   {
      if(ui.side == UI_BUY) res = trade.BuyLimit (ui.lotSize, p, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmtMain);
      else                  res = trade.SellLimit(ui.lotSize, p, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmtMain);
   }

   if(!res)
   {
      Alert("[TM3] Order failed: ", trade.ResultRetcodeDescription());
      return;
   }

   if(InpEnableSounds) PlaySound(InpSoundEntry);
   if(ui.isVisualizing) ToggleVisualization();
   PrintFormat("[TM3] Group %d opened (%s)", gid, cmtMain);

   if(InpEnableDDEntries && InpDD_OrderCount > 0)
   {
      int dynamicSpacing = InpDD_Spacing;
      if(InpDD_AutoSpacingSL && ui.slPoints > 0)
         dynamicSpacing = ui.slPoints / (InpDD_OrderCount + 1);

      for(int i = 1; i <= InpDD_OrderCount; i++)
      {
         double ddLot = ui.lotSize;
         if(InpDD_ScaleLots)
         {
            double currentPct = InpDD_LotStartPct;
            if(InpDD_OrderCount > 1)
               currentPct = InpDD_LotStartPct + (InpDD_LotEndPct - InpDD_LotStartPct) * ((double)(i - 1) / (double)(InpDD_OrderCount - 1));
            ddLot = NormaliseVolume(ui.lotSize * (currentPct / 100.0));
            double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            double maxV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
            if(ddLot < minV) ddLot = minV;
            if(ddLot > maxV) ddLot = maxV;
         }

         double p_dd = (ui.side == UI_BUY) ? p - (i * dynamicSpacing * _Point) : p + (i * dynamicSpacing * _Point);
         p_dd = NormaliseSL(p_dd);
         double sl_dd = 0;
         if(InpDD_SameSL)
            sl_dd = sl;
         else
            sl_dd = (ui.slPoints > 0) ? ((ui.side == UI_BUY) ? p_dd - ui.slPoints * _Point : p_dd + ui.slPoints * _Point) : 0;
         double tp_dd = (ui.side == UI_BUY) ? p_dd + ui.tpPoints * _Point : p_dd - ui.tpPoints * _Point;
         if(sl_dd > 0) sl_dd = NormaliseSL(sl_dd);
         tp_dd = NormaliseSL(tp_dd);

         if(ui.side == UI_BUY)
            trade.BuyLimit(ddLot, p_dd, _Symbol, sl_dd, tp_dd, ORDER_TIME_GTC, 0, cmtDD);
         else
            trade.SellLimit(ddLot, p_dd, _Symbol, sl_dd, tp_dd, ORDER_TIME_GTC, 0, cmtDD);
      }
   }
}

double NormaliseVolume(double vol)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) return vol;
   return MathFloor(vol / step) * step;
}

void SetBreakEvenManual()
{
   datetime latestTime = 0;
   ulong latestTicket = 0;
   double latestOpenPrice = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      bool isOwn = ((int)posInfo.Magic() == MagicNumber());
      bool isExt = InpMonitorExternal && IsRegisteredExternal(posInfo.Ticket());
      if(!isOwn && !isExt) continue;
      if((datetime)posInfo.Time() > latestTime)
      {
         latestTime = (datetime)posInfo.Time();
         latestTicket = posInfo.Ticket();
         latestOpenPrice = posInfo.PriceOpen();
      }
   }
   if(latestTicket > 0)
   {
      CancelAllLimitOrders();
      SetSLAllPositions(NormaliseSL(latestOpenPrice));
      if(InpEnableSounds) PlaySound(InpSoundBE);
   }
   else
      Alert("[TM3] No managed open trades found to set BE.");
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
      bool isOwn = ((int)posInfo.Magic() == MagicNumber());
      bool isExt = InpMonitorExternal && IsRegisteredExternal(posInfo.Ticket());
      if(!isOwn && !isExt) continue;
      trade.PositionClose(posInfo.Ticket());
      any = true;
   }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ot = OrderGetTicket(i);
      if(OrderGetString(ORDER_SYMBOL) == _Symbol && (int)OrderGetInteger(ORDER_MAGIC) == MagicNumber())
      { trade.OrderDelete(ot); any = true; }
   }
   if(any && InpEnableSounds) PlaySound(InpSoundClose);
}

int BuildManagedTicketList(ulong &list[])
{
   ArrayResize(list, 0);
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      bool isOwn = ((int)posInfo.Magic() == MagicNumber());
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
   int newIdx = (curIdx < 0) ? 0 : (curIdx + offset + n) % n;
   return g_ManagedTickets[newIdx];
}

void CycleSelectedTrade(int direction)
{
   RefreshManagedTicketCache();
   g_SelectedTicket = GetManagedTicketByOffset(direction);
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
      txt = "Selected: none";
   else
   {
      posInfo.SelectByTicket(g_SelectedTicket);
      bool isBuy = (posInfo.PositionType() == POSITION_TYPE_BUY);
      double profit = posInfo.Profit() + posInfo.Swap() + posInfo.Commission();
      txt = StringFormat("Sel: #%d %s %.2f %s%.2f",
                         (int)g_SelectedTicket, isBuy ? "BUY" : "SELL", posInfo.Volume(),
                         profit >= 0 ? "+" : "", profit);
   }
   if(ObjectFind(0, g_prefix + "Lbl_Selected") >= 0)
      ObjectSetString(0, g_prefix + "Lbl_Selected", OBJPROP_TEXT, txt);
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

void ToggleBasket()
{
   ui.basketEnabled = !ui.basketEnabled;
   UpdatePanelUI();
   SaveState();
}

void ToggleWorstAutoSL()
{
   ui.worstAutoSL = !ui.worstAutoSL;
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
      bool isOwn = ((int)posInfo.Magic() == MagicNumber());
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
      if(managed[i].priceDiff < managed[worstIdx].priceDiff)
         worstIdx = i;
   if(managed[worstIdx].priceDiff >= g_BasketPts && managed[worstIdx].profit > 0.0)
   {
      if(ui.worstAutoSL && PositionSelectByTicket(managed[worstIdx].ticket))
      {
         double open = posInfo.PriceOpen();
         bool isBuy = (posInfo.PositionType() == POSITION_TYPE_BUY);
         double targetBE = NormaliseSL(isBuy ? open + InpBE_Offset * _Point : open - InpBE_Offset * _Point);
         double curSL = posInfo.StopLoss();
         bool isBEAlready = isBuy ? (curSL >= targetBE) : (curSL > 0 && curSL <= targetBE);
         if(!isBEAlready)
            SetBreakEvenTicket(managed[worstIdx].ticket);
      }
   }
   else
      trade.PositionClose(managed[worstIdx].ticket);
}

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
      if((int)posInfo.Magic() == MagicNumber()) continue;
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
      if(InpAutoAdoptExternal) AdoptExternalTrade(ticket);
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
   bool isBuy = (posInfo.PositionType() == POSITION_TYPE_BUY);
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
         Print("[TM3] Adopted external ticket ", ticket, " SL=", newSL, " TP=", newTP);
         for(int i = 0; i < ArraySize(g_ExtTrades); i++)
            if(g_ExtTrades[i].ticket == ticket) { g_ExtTrades[i].adopted = true; break; }
      }
      else
         Print("[TM3] Failed to adopt external ticket ", ticket, " Error: ", GetLastError());
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

void ExportToCSV()
{
   string filename = "TM3_Export_" + _Symbol + "_" + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES) + ".csv";
   StringReplace(filename, ":", "-");
   StringReplace(filename, ".", "");
   int handle = FileOpen(filename, FILE_WRITE | FILE_CSV | FILE_ANSI, ",");
   if(handle == INVALID_HANDLE)
   {
      Alert("[TM3] Failed to open file for export: ", filename);
      return;
   }
   FileWrite(handle, "Ticket", "Time", "Type", "Volume", "Price", "SL", "TP", "Profit", "Commission", "Swap", "Comment");
   HistorySelect(0, TimeCurrent());
   int exportedCount = 0;
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if((int)HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber()) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      datetime time = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      long type = HistoryDealGetInteger(ticket, DEAL_TYPE);
      string typeStr = (type == DEAL_TYPE_BUY) ? "Buy" : (type == DEAL_TYPE_SELL ? "Sell" : "Unknown");
      FileWrite(handle,
                IntegerToString((int)ticket),
                TimeToString(time),
                typeStr,
                DoubleToString(HistoryDealGetDouble(ticket, DEAL_VOLUME), 2),
                DoubleToString(HistoryDealGetDouble(ticket, DEAL_PRICE), _Digits),
                "0", "0",
                DoubleToString(HistoryDealGetDouble(ticket, DEAL_PROFIT), 2),
                DoubleToString(HistoryDealGetDouble(ticket, DEAL_COMMISSION), 2),
                DoubleToString(HistoryDealGetDouble(ticket, DEAL_SWAP), 2),
                HistoryDealGetString(ticket, DEAL_COMMENT));
      exportedCount++;
   }
   FileClose(handle);
   Print("[TM3] Successfully exported ", exportedCount, " deals to ", filename);
   Alert("[TM3] Export complete: ", filename);
   if(InpEnableSounds) PlaySound(InpSoundOk);
}

bool IsManagedPosition()
{
   if(posInfo.Symbol() != _Symbol) return false;
   return ((int)posInfo.Magic() == MagicNumber()) || (InpMonitorExternal && IsRegisteredExternal(posInfo.Ticket()));
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
   return NormalisePrice(_Symbol, price);
}

double NormalisePrice(const string sym, double price)
{
   double tick = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
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

void SaveState()
{
   string id = IntegerToString(ChartID());
   GlobalVariableSet("TM3_" + id + "_Type", (double)ui.orderType);
   GlobalVariableSet("TM3_" + id + "_Side", (double)ui.side);
   GlobalVariableSet("TM3_" + id + "_Lot", ui.lotSize);
   GlobalVariableSet("TM3_" + id + "_RiskPct", ui.riskPercent);
   GlobalVariableSet("TM3_" + id + "_SL", (double)ui.slPoints);
   GlobalVariableSet("TM3_" + id + "_TP", (double)ui.tpPoints);
   GlobalVariableSet("TM3_" + id + "_Parts", (double)ui.partialsCount);
   GlobalVariableSet("TM3_" + id + "_Basket", (double)ui.basketEnabled);
   GlobalVariableSet("TM3_" + id + "_WorstSL", (double)ui.worstAutoSL);
   GlobalVariableSet("TM3_" + id + "_Inv", (double)ui.inverseEnabled);
   GlobalVariableSet("TM3_" + id + "_Green", (double)g_BasketPts);
}

void LoadState()
{
   string id = IntegerToString(ChartID());
   if(!GlobalVariableCheck("TM3_" + id + "_Type")) return;
   ui.orderType = (ENUM_ORDER_TYPE_UI)(int)GlobalVariableGet("TM3_" + id + "_Type");
   ui.side = (ENUM_SIDE_UI)(int)GlobalVariableGet("TM3_" + id + "_Side");
   ui.lotSize = GlobalVariableGet("TM3_" + id + "_Lot");
   if(GlobalVariableCheck("TM3_" + id + "_RiskPct")) ui.riskPercent = GlobalVariableGet("TM3_" + id + "_RiskPct");
   ui.slPoints = (int)GlobalVariableGet("TM3_" + id + "_SL");
   ui.tpPoints = (int)GlobalVariableGet("TM3_" + id + "_TP");
   ui.partialsCount = (int)GlobalVariableGet("TM3_" + id + "_Parts");
   if(GlobalVariableCheck("TM3_" + id + "_Basket"))  ui.basketEnabled = (bool)GlobalVariableGet("TM3_" + id + "_Basket");
   if(GlobalVariableCheck("TM3_" + id + "_WorstSL")) ui.worstAutoSL = (bool)GlobalVariableGet("TM3_" + id + "_WorstSL");
   if(GlobalVariableCheck("TM3_" + id + "_Inv"))     ui.inverseEnabled = (bool)GlobalVariableGet("TM3_" + id + "_Inv");
   if(GlobalVariableCheck("TM3_" + id + "_Green"))   g_BasketPts = (int)GlobalVariableGet("TM3_" + id + "_Green");
}

void ClearState()
{
   string id = IntegerToString(ChartID());
   string keys[] = {"_Type","_Side","_Lot","_RiskPct","_SL","_TP","_Parts","_Basket","_WorstSL","_Inv","_Green"};
   for(int i = 0; i < ArraySize(keys); i++)
      GlobalVariableDel("TM3_" + id + keys[i]);
}

int PartialLinesHeight()
{
   if(ui.partialsCount <= 0 || ui.tpPoints <= 0) return 18;
   int lines = ((ui.partialsCount - 1) / 4) + 1;
   return 14 * lines + 4;
}

int PanelHeight()
{
   return 562 + PartialLinesHeight() + PositionListHeight() + 20;
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
   if(InpPanelCorner == CORNER_LEFT_LOWER)  by = sh - PanelHeight() - 30;
   if(InpPanelCorner == CORNER_RIGHT_LOWER) { bx = sw - PANEL_W - 10; by = sh - PanelHeight() - 30; }
   CreatePanelElements(bx, by);
   if(doUpdateUI) UpdatePanelUI();
}

void CreatePanelElements(int x, int y)
{
   Rect("BG", x, y, PANEL_W, PanelHeight(), COLOR_BG);
   y += PAD;
   Btn("Btn_Mkt", x + 5, y, 110, ROW_H, "MARKET", (ui.orderType == UI_MARKET));
   Btn("Btn_Lim", x + 115, y, 110, ROW_H, "LIMIT", (ui.orderType == UI_LIMIT));
   y += ROW_H + PAD;
   Lbl("Lbl_Prc", x + 5, y + 5, "Price:");
   Edit("Edit_Price", x + 55, y, 170, ROW_H, "0.00000");
   y += ROW_H + PAD;
   Btn("Btn_Buy", x + 5, y, 110, ROW_H, "BUY", false, COLOR_BUY);
   Btn("Btn_Sell", x + 115, y, 110, ROW_H, "SELL", false, COLOR_SELL);
   y += ROW_H + PAD;
   Lbl("Lbl_Lot", x + 5, y + 5, "Lot:");
   Edit("Edit_Lot", x + 45, y, 65, ROW_H, DoubleToString(ui.lotSize, 2));
   Lbl("Lbl_RiskPct", x + 115, y + 5, "Risk%:");
   Edit("Edit_RiskPct", x + 160, y, 65, ROW_H, DoubleToString(ui.riskPercent, 2));
   y += ROW_H + PAD;
   Lbl("Lbl_SL", x + 5, y + 5, "SL pts:");
   Edit("Edit_SL", x + 65, y, 55, ROW_H, IntegerToString(ui.slPoints));
   Lbl("Lbl_SLP", x + 125, y + 5, "Prc:");
   Edit("Edit_SL_Prc", x + 148, y, 77, ROW_H, "0.00000");
   y += ROW_H + PAD;
   Lbl("Lbl_TP", x + 5, y + 5, "TP pts:");
   Edit("Edit_TP", x + 65, y, 55, ROW_H, IntegerToString(ui.tpPoints));
   Lbl("Lbl_TPP", x + 125, y + 5, "Prc:");
   Edit("Edit_TP_Prc", x + 148, y, 77, ROW_H, "0.00000");
   y += ROW_H + PAD;
   Lbl("Lbl_Part", x + 5, y + 5, "Partials #:");
   Edit("Edit_Part", x + 115, y, 110, ROW_H, IntegerToString(ui.partialsCount));
   y += ROW_H + PAD;
   Rect("Sep3", x + 5, y, PANEL_W - 10, 1, C'80,80,80');
   y += 5;
   UpdatePartialLine(x, y);
   Rect("Sep1", x + 5, y, PANEL_W - 10, 1, C'60,60,60');
   y += 5;
   Lbl("Lbl_Risk", x + 5, y + 5, "Risk:");
   Lbl("Val_Risk", x + 45, y + 5, "$0.00");
   ObjectSetInteger(0, g_prefix + "Val_Risk", OBJPROP_COLOR, clrCrimson);
   Lbl("Lbl_Rew", x + 115, y + 5, "Profit:");
   Lbl("Val_Rew", x + 158, y + 5, "$0.00");
   ObjectSetInteger(0, g_prefix + "Val_Rew", OBJPROP_COLOR, clrLimeGreen);
   y += 20;
   Rect("Sep2", x + 5, y, PANEL_W - 10, 1, C'60,60,60');
   y += 5;
   Btn("Btn_Vis", x + 5, y, 220, ROW_H, "VISUALIZE", false, C'80,80,80');
   y += ROW_H + PAD;
   Rect("SepSel1", x + 5, y, PANEL_W - 10, 1, C'80,80,80');
   y += 6;
   Lbl("Lbl_SelHdr", x + 5, y + 2, "Trade Selector:");
   y += 14;
   Btn("Btn_SelPrev", x + 5, y, 35, ROW_H, "<", false, C'70,70,70');
   Lbl("Lbl_Selected", x + 45, y + 7, "Selected: none");
   Btn("Btn_SelNext", x + PANEL_W - 45, y, 35, ROW_H, ">", false, C'70,70,70');
   y += ROW_H + PAD;
   Edit("Edit_ManPart", x + 5, y, 50, ROW_H, "20");
   Btn("Btn_Part", x + 60, y, 165, ROW_H, "PARTIAL % (SEL)", false, C'80,80,0');
   y += ROW_H + PAD;
   Btn("Btn_BE", x + 5, y, 110, ROW_H, "BE ALL (LATEST)", false, C'0,80,80');
   Btn("Btn_CloseSel", x + 115, y, 110, ROW_H, "CLOSE (SEL)", false, C'180,60,0');
   y += ROW_H + PAD;
   Rect("SepSel2", x + 5, y, PANEL_W - 10, 1, C'80,80,80');
   y += 6;
   Btn("Btn_CloseAll", x + 5, y, 220, ROW_H, "CLOSE ALL", false, clrRed);
   y += ROW_H + PAD;
   Btn("Btn_Export", x + 5, y, 105, ROW_H, "EXPORT CSV", false, C'50,100,50');
   Btn("Btn_Inverse", x + 115, y, 110, ROW_H, ui.inverseEnabled ? "INV: ON" : "INV: OFF", false, ui.inverseEnabled ? C'180,100,0' : C'80,80,80');
   y += ROW_H + PAD;
   Rect("Sep4", x + 5, y, PANEL_W - 10, 1, C'80,80,80');
   y += 6;
   Btn("Btn_Basket", x + 5, y, 220, ROW_H, ui.basketEnabled ? "Handler: ON" : "Handler: OFF", false, ui.basketEnabled ? C'0,140,0' : C'120,0,0');
   y += ROW_H + PAD;
   Btn("Btn_WorstSL", x + 5, y, 105, ROW_H, ui.worstAutoSL ? "Worst SL: BE" : "Worst SL: OFF", false, ui.worstAutoSL ? C'0,140,140' : C'80,80,80');
   Lbl("Lbl_GreenPts", x + 115, y + 5, "Pts:");
   Edit("Edit_GreenPts", x + 148, y, 77, ROW_H, IntegerToString(g_BasketPts));
   y += ROW_H + PAD;
   Rect("Sep5", x + 5, y, PANEL_W - 10, 1, C'80,80,80');
   y += 6;
   g_PosListX = x;
   g_PosListY = y;
   DrawPositionList(x, y);
}

void UpdatePanelUI()
{
   ObjectSetInteger(0, g_prefix + "Btn_Mkt", OBJPROP_BGCOLOR, ui.orderType == UI_MARKET ? COLOR_ACT : COLOR_BTN);
   ObjectSetInteger(0, g_prefix + "Btn_Lim", OBJPROP_BGCOLOR, ui.orderType == UI_LIMIT ? COLOR_ACT : COLOR_BTN);
   ObjectSetInteger(0, g_prefix + "Btn_Buy", OBJPROP_BGCOLOR, COLOR_BUY);
   ObjectSetInteger(0, g_prefix + "Btn_Sell", OBJPROP_BGCOLOR, COLOR_SELL);
   ObjectSetInteger(0, g_prefix + "Btn_Buy", OBJPROP_COLOR, COLOR_TEXT);
   ObjectSetInteger(0, g_prefix + "Btn_Sell", OBJPROP_COLOR, COLOR_TEXT);
   ObjectSetInteger(0, g_prefix + "Btn_Vis", OBJPROP_BGCOLOR, ui.isVisualizing ? COLOR_ACT : C'80,80,80');
   if(ObjectFind(0, g_prefix + "Btn_Basket") >= 0)
   {
      ObjectSetString(0, g_prefix + "Btn_Basket", OBJPROP_TEXT, ui.basketEnabled ? "Handler: ON" : "Handler: OFF");
      ObjectSetInteger(0, g_prefix + "Btn_Basket", OBJPROP_BGCOLOR, ui.basketEnabled ? C'0,140,0' : C'120,0,0');
   }
   if(ObjectFind(0, g_prefix + "Btn_WorstSL") >= 0)
   {
      ObjectSetString(0, g_prefix + "Btn_WorstSL", OBJPROP_TEXT, ui.worstAutoSL ? "Worst SL: BE" : "Worst SL: OFF");
      ObjectSetInteger(0, g_prefix + "Btn_WorstSL", OBJPROP_BGCOLOR, ui.worstAutoSL ? C'0,140,140' : C'80,80,80');
   }
   if(ObjectFind(0, g_prefix + "Btn_Inverse") >= 0)
   {
      ObjectSetString(0, g_prefix + "Btn_Inverse", OBJPROP_TEXT, ui.inverseEnabled ? "INV: ON" : "INV: OFF");
      ObjectSetInteger(0, g_prefix + "Btn_Inverse", OBJPROP_BGCOLOR, ui.inverseEnabled ? C'180,100,0' : C'80,80,80');
   }
}

void UpdatePartialLine(int x, int &y)
{
   ObjectDelete(0, g_prefix + "PTL_Line");
   if(ui.partialsCount <= 0 || ui.tpPoints <= 0)
   {
      Lbl("PTL_Line_0", x + 10, y, "No partials configured");
      ObjectSetInteger(0, g_prefix + "PTL_Line_0", OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, g_prefix + "PTL_Line_0", OBJPROP_COLOR, C'140,140,140');
      for(int j = 1; j < 20; j++) ObjectDelete(0, g_prefix + "PTL_Line_" + IntegerToString(j));
      y += 18;
      return;
   }
   double step = (double)ui.tpPoints / (ui.partialsCount + 1);
   string txt = "";
   int lineIdx = 0;
   for(int i = 1; i <= ui.partialsCount; i++)
   {
      int pts = (int)MathRound(step * i);
      txt += "TP" + IntegerToString(i) + ":" + IntegerToString(pts / 10);
      if(i % 4 == 0 || i == ui.partialsCount)
      {
         string nm = "PTL_Line_" + IntegerToString(lineIdx);
         Lbl(nm, x + 10, y, txt);
         ObjectSetInteger(0, g_prefix + nm, OBJPROP_FONTSIZE, 8);
         ObjectSetInteger(0, g_prefix + nm, OBJPROP_COLOR, C'140,140,140');
         y += 14;
         lineIdx++;
         txt = "";
      }
      else
         txt += " | ";
   }
   y += 4;
   for(int j = lineIdx; j < 20; j++)
      ObjectDelete(0, g_prefix + "PTL_Line_" + IntegerToString(j));
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
   if(ObjectFind(0, g_prefix + "Edit_SL_Prc") >= 0)
      ObjectSetString(0, g_prefix + "Edit_SL_Prc", OBJPROP_TEXT, slTxt);
   if(ObjectFind(0, g_prefix + "Edit_TP_Prc") >= 0)
      ObjectSetString(0, g_prefix + "Edit_TP_Prc", OBJPROP_TEXT, DoubleToString(ui.tpPrice, _Digits));
}

void UpdateStats(double priceRef)
{
   UpdateSymbolCache();
   if(g_PointMult <= 0) return;
   double riskUSD = ui.lotSize * ui.slPoints * g_PointMult;
   double rewUSD = 0;
   double remLot = ui.lotSize;
   double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(volStep <= 0) volStep = 0.01;
   int parts = ui.partialsCount;
   if(parts < 1) parts = 0;
   double stepPts = (parts > 0) ? (double)ui.tpPoints / (parts + 1) : 0;
   for(int i = 1; i <= parts; i++)
   {
      double pct = (i == 1) ? InpMainPartialVol : InpRollingPartialVol;
      double partLot = MathFloor(ui.lotSize * (pct * 0.01) / volStep) * volStep;
      if(partLot < minLot) partLot = 0;
      if(partLot > 0 && partLot <= remLot)
      {
         rewUSD += partLot * stepPts * i * g_PointMult;
         remLot -= partLot;
      }
   }
   remLot = NormalizeDouble(remLot, 2);
   if(remLot > 0) rewUSD += remLot * ui.tpPoints * g_PointMult;
   if(ObjectFind(0, g_prefix + "Val_Risk") >= 0)
      ObjectSetString(0, g_prefix + "Val_Risk", OBJPROP_TEXT, "$" + DoubleToString(riskUSD, 2));
   if(ObjectFind(0, g_prefix + "Val_Rew") >= 0)
      ObjectSetString(0, g_prefix + "Val_Rew", OBJPROP_TEXT, "$" + DoubleToString(rewUSD, 2));
}

void ToggleVisualization()
{
   ui.isVisualizing = !ui.isVisualizing;
   if(!ui.isVisualizing)
   {
      ObjectDelete(0, g_prefix + "VisB_Entry"); ObjectDelete(0, g_prefix + "VisS_Entry");
      ObjectDelete(0, g_prefix + "VisB_SL");    ObjectDelete(0, g_prefix + "VisS_SL");
      ObjectDelete(0, g_prefix + "VisB_TP");    ObjectDelete(0, g_prefix + "VisS_TP");
      for(int i = 1; i <= 20; i++)
      {
         ObjectDelete(0, g_prefix + "VisB_P" + IntegerToString(i));
         ObjectDelete(0, g_prefix + "VisS_P" + IntegerToString(i));
      }
   }
   else
      DrawVisualization();
   UpdatePanelUI();
}

void DrawVisualization()
{
   double pBuy  = (ui.orderType == UI_LIMIT) ? ui.customPrice : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
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
   Line(pfx + "Entry", ep, c, STYLE_SOLID, 2, (side == UI_BUY ? "BUY" : "SELL") + " ENTRY");
   if(sl > 0) Line(pfx + "SL", sl, c, STYLE_DASH, 1, (side == UI_BUY ? "B_SL" : "S_SL"));
   else ObjectDelete(0, g_prefix + pfx + "SL");
   Line(pfx + "TP", tp, c, STYLE_SOLID, 1, (side == UI_BUY ? "B_TP" : "S_TP"));
   for(int i = 1; i <= ui.partialsCount; i++)
   {
      double lvl = (side == UI_BUY) ? ep + step * i : ep - step * i;
      Line(pfx + "P" + IntegerToString(i), lvl, c, STYLE_DOT, 1, (side == UI_BUY ? "B_P" : "S_P") + IntegerToString(i));
   }
   for(int i = ui.partialsCount + 1; i <= 20; i++)
      ObjectDelete(0, g_prefix + pfx + "P" + IntegerToString(i));
}

void DrawPositionList(int x, int y)
{
   string hdr = "Open Positions";
   if(StringLen(g_SurvivalStatus) > 0) hdr = g_SurvivalStatus;
   Lbl("Lbl_PosList", x + 5, y, hdr);
   y += 16;
   int rowIdx = 0;
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0 && rowIdx < 20; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      bool isOwn = ((int)posInfo.Magic() == MagicNumber());
      bool isExt = InpMonitorExternal && IsRegisteredExternal(posInfo.Ticket());
      if(!isOwn && !isExt) continue;
      ulong ticket = posInfo.Ticket();
      bool isBuy = (posInfo.PositionType() == POSITION_TYPE_BUY);
      double vol = posInfo.Volume();
      double profit = posInfo.Profit() + posInfo.Swap() + posInfo.Commission();
      bool isSelected = (ticket == g_SelectedTicket);
      string marker = isSelected ? "> " : "  ";
      string rowTxt = StringFormat("%s#%d %s %.2f %s%.2f", marker, (int)ticket, isBuy ? "BUY" : "SELL", vol, profit >= 0 ? "+" : "", profit);
      string lblName = "PosRow_" + IntegerToString((int)ticket);
      Lbl(lblName, x + 5, y + 3, rowTxt);
      ObjectSetInteger(0, g_prefix + lblName, OBJPROP_FONTSIZE, 8);
      color rowColor = isSelected ? clrYellow : (profit >= 0 ? clrLimeGreen : clrSalmon);
      ObjectSetInteger(0, g_prefix + lblName, OBJPROP_COLOR, rowColor);
      rowIdx++;
      y += POS_ROW_H;
   }
   if(rowIdx == 0)
   {
      Lbl("PosRow_None", x + 10, y + 2, "No open positions");
      ObjectSetInteger(0, g_prefix + "PosRow_None", OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, g_prefix + "PosRow_None", OBJPROP_COLOR, C'140,140,140');
   }
   else
      ObjectDelete(0, g_prefix + "PosRow_None");

   int objTotal = ObjectsTotal(0, -1, -1);
   for(int j = objTotal - 1; j >= 0; j--)
   {
      string nm = ObjectName(0, j);
      if(StringFind(nm, g_prefix + "PosRow_") == 0 && StringFind(nm, "PosRow_None") < 0)
      {
         string tstr = StringSubstr(nm, StringLen(g_prefix + "PosRow_"));
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
   ObjectSetString(0, nm, OBJPROP_TEXT, t);
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
      ObjectSetString(0, nm, OBJPROP_TEXT, t);
      ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, nm, OBJPROP_XSIZE, w);
      ObjectSetInteger(0, nm, OBJPROP_YSIZE, h);
      return;
   }
   if((int)ObjectGetInteger(0, nm, OBJPROP_XDISTANCE) != x) ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
   if((int)ObjectGetInteger(0, nm, OBJPROP_YDISTANCE) != y) ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   if((int)ObjectGetInteger(0, nm, OBJPROP_XSIZE) != w)     ObjectSetInteger(0, nm, OBJPROP_XSIZE, w);
   if((int)ObjectGetInteger(0, nm, OBJPROP_YSIZE) != h)     ObjectSetInteger(0, nm, OBJPROP_YSIZE, h);
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
   ObjectSetString(0, nm, OBJPROP_TEXT, t);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, C'180,180,180');
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 8);
}

void Line(string sfx, double price, color col, ENUM_LINE_STYLE st, int wd, string lbl = "")
{
   string nm = g_prefix + sfx;
   if(ObjectFind(0, nm) < 0)
      ObjectCreate(0, nm, OBJ_HLINE, 0, 0, price);
   ObjectSetDouble(0, nm, OBJPROP_PRICE, price);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, col);
   ObjectSetInteger(0, nm, OBJPROP_STYLE, st);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, wd);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
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
   json += "\"timestamp\":\"" + EscapeJsonString(TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS)) + "\",";
   json += "\"event\":\"" + EscapeJsonString(event_name) + "\",";
   json += "\"ticket\":\"" + (string)ticket + "\",";
   json += "\"symbol\":\"" + EscapeJsonString(symbol) + "\",";
   json += "\"side\":\"" + EscapeJsonString(side) + "\",";
   json += "\"volume\":" + DoubleToString(volume, 2) + ",";
   json += "\"price\":" + DoubleToString(price, _Digits) + ",";
   json += "\"sl\":" + DoubleToString(sl, _Digits) + ",";
   json += "\"tp\":" + DoubleToString(tp, _Digits) + ",";
   json += "\"profit\":" + DoubleToString(profit, 2) + ",";
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
   string baseFilename = "Journal\\" + (string)ticket + "_" + event_name + "_" + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES);
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
      screenshot_file = TakeCleanScreenshot(ticket, event_name);
   string csv_filename = "TM3_Journal.csv";
   int handle = FileOpen(csv_filename, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ",");
   if(handle != INVALID_HANDLE)
   {
      if(FileSize(handle) == 0)
         FileWrite(handle, "Timestamp", "Event", "Ticket", "Symbol", "Side", "Volume", "Price", "SL", "TP", "Profit", "Note", "Screenshot");
      FileSeek(handle, 0, SEEK_END);
      FileWrite(handle, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), event_name, ticket, symbol, side, volume, price, sl, tp, profit, note, screenshot_file);
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
      has_file = ReadScreenshotFileToArray(screenshot_file, file_data);

   if(has_file)
   {
      string boundary = BuildMultipartBoundary();
      char body[];
      ArrayResize(body, 0);
      string fields[17][2];
      fields[0][0] = "timestamp";      fields[0][1] = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
      fields[1][0] = "event";          fields[1][1] = event_name;
      fields[2][0] = "ticket";         fields[2][1] = (string)ticket;
      fields[3][0] = "symbol";         fields[3][1] = symbol;
      fields[4][0] = "side";           fields[4][1] = side;
      fields[5][0] = "volume";         fields[5][1] = DoubleToString(volume, 2);
      fields[6][0] = "price";          fields[6][1] = DoubleToString(price, _Digits);
      fields[7][0] = "sl";             fields[7][1] = DoubleToString(sl, _Digits);
      fields[8][0] = "tp";             fields[8][1] = DoubleToString(tp, _Digits);
      fields[9][0] = "profit";         fields[9][1] = DoubleToString(profit, 2);
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

string BuildMultipartBoundary()
{
   return "----TM3Boundary" + IntegerToString((int)TimeLocal()) + IntegerToString(GetTickCount());
}

bool ReadScreenshotFileToArray(const string file_name, uchar &data[])
{
   ArrayResize(data, 0);
   if(StringLen(file_name) <= 0) return false;
   int handle = FileOpen(file_name, FILE_READ | FILE_BIN | FILE_SHARE_READ);
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