//+------------------------------------------------------------------+
//|                                        TradeManager_v3.1.mq5     |
//|  Riy Tech — Clean rewrite. Partial mgmt, BE, Trailing, Basket    |
//|  v3.1 — Dual Visualization & Split-Direction Basket Management   |
//+------------------------------------------------------------------+
#property copyright "Riy Tech"
#property version   "3.10"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+
input group "Panel Settings"
input ENUM_BASE_CORNER InpPanelCorner = CORNER_LEFT_UPPER;

input group "Risk Settings"
input double InpDefaultLot = 0.3;      // Default Lot Size
input int    InpDefaultSL  = 500;       // Default SL (points)
input int    InpDefaultTP  = 1000;      // Default TP (points)

input group "Inverse Order Settings"
input int InpInverseOffset = 50; // Inverse Pending Offset (points)

input group "Auto Risk Settings"
input int InpAutoRiskPartials = 2; // Auto Risk / SL Partials max count

input group "Daily Limits"
input bool InpEnableDailyLossLimit = true; // Enable Daily Loss Limit?
input int  InpMaxDailyLosingTrades = 3;    // Max Losing Trades Per Day

input group "Partial Settings"
input double InpMainPartialVol    = 40.0;  // 1st Partial % of position
input double InpRollingPartialVol = 20.0;  // Subsequent Partials %
input int    InpDefaultPartial    = 3;     // Number of Partials

input group "Breakeven Settings"
input int  InpBE_Trigger = 1;           // Set BE after Partial # (0 = disabled)
input int  InpBE_Offset  = 20;          // BE Offset (points above/below open)

input group "Trailing Stop Settings"
input bool InpUseTrailingStop = true;  // Enable Trailing Stop?
input int  InpTrailingStart   = 800;    // Points in profit to activate trailing
input int  InpTrailingStep    = 500;     // Trail distance behind price (points)

input group "Sound Settings"
input bool   InpEnableSounds    = true;
input string InpSoundEntry      = "Ok.wav";
input string InpSoundOk      = "Ok.wav";
input string InpSoundPartial    = "News.wav";
input string InpSoundBE         = "Expert.wav";
input string InpSoundSL         = "timeout.wav";
input string InpSoundTP         = "alert.wav";
input string InpSoundClose      = "stops.wav";

input group "External Trade Monitoring"
input bool   InpMonitorExternal   = true;         // Monitor trades opened outside this EA?
input bool   InpExternalAlerts    = true;         // Alert when external trade detected?
input string InpSoundExtDetected  = "notify.wav"; // Sound on external trade detection

input group "Trade Limits"
input int InpMaxOpenTrades = 10;        // Maximum managed open trades (increased for multi-trade)

input group "Auto Trade Handler"
input bool InpBasketEnabled     = true; // Enable Auto Trade Handler?
input int  InpBasketGreenPoints = 0;    // Min profit points to close older trades (0=any green)

//+------------------------------------------------------------------+
//| CONSTANTS                                                        |
//+------------------------------------------------------------------+
#define MAGIC      234567
#define COLOR_BG   C'35,35,35'
#define COLOR_BTN  C'60,60,60'
#define COLOR_ACT  C'0,120,215'
#define COLOR_BUY  C'46,204,113'
#define COLOR_SELL C'231,76,60'
#define COLOR_TEXT clrWhite
#define COLOR_EDIT C'50,50,50'
#define PANEL_W    230
#define ROW_H      25
#define PAD        5

//+------------------------------------------------------------------+
//| ENUMS & STRUCTS                                                  |
//+------------------------------------------------------------------+
enum ENUM_ORDER_TYPE_UI { UI_MARKET, UI_LIMIT };
enum ENUM_SIDE_UI       { UI_BUY,    UI_SELL  };

struct UIState
{
   ENUM_ORDER_TYPE_UI orderType;
   ENUM_SIDE_UI side;
   double lotSize;
   int slPoints;
   int tpPoints;
   double slPrice;
   double tpPrice;
   int partialsCount;
   double customPrice;
   bool isVisualizing;
   bool basketEnabled;
   bool inverseEnabled;
   bool autoRiskEnabled;
};

struct ExtTradeRec { ulong ticket; long posID; bool alertSent; };

struct PosState
{
   long   posID;
   ulong  ticket;
   int    partialsTaken; 
   int    slPartialsTaken; // Tracks AutoRisk scale-outs
   bool   beSet;         
};

//+------------------------------------------------------------------+
//| GLOBALS                                                          |
//+------------------------------------------------------------------+
string        g_prefix;
UIState       ui;
CTrade        trade;
CPositionInfo posInfo;
int           g_ChartW = 0;
int           g_ChartH = 0;
datetime      g_LastExtScan  = 0;
int           g_BasketPts    = 0;
ExtTradeRec   g_ExtTrades[];
PosState      g_PosStates[];   

//+------------------------------------------------------------------+
//| FORWARD DECLARATIONS                                             |
//+------------------------------------------------------------------+
void SaveState();
void LoadState();
void ClearState();
void RebuildPanel(bool updateUI = false);
void CreatePanelElements(int x, int y);
void UpdatePanelUI();
void UpdateSLTPPrices(double entry);
void UpdateStats(double priceRef);
void UpdatePartialList(int x, int y);
int  PanelHeight();
void ToggleVisualization();
void DrawVisualization(); 
void DrawSideVis(double ep, ENUM_SIDE_UI side);
void ExecuteOrder();
void ManualPartial();
void CloseAll();
void SetBreakEvenManual();
bool IsDailyLossLimitReached();
void ManagePositions();
void ManageTrailingStop();
void ScanExternalTrades();
void ManageDrawdownBasket();
void ProcessBasketByType(ENUM_POSITION_TYPE type);
void CleanupOrphanedLines();
void SyncPosStates();
void RemovePosState(long posID);
bool IsRegisteredExternal(ulong ticket);
void RemoveClosedExternals();
bool IsManagedPosition();
int    CountManagedOpenPositions();
double NormaliseSL(double price);
void   ToggleBasket();
void Btn (string n, int x, int y, int w, int h, string t, bool act, color b = COLOR_BTN);
void Rect(string n, int x, int y, int w, int h, color bg);
void Edit(string n, int x, int y, int w, int h, string t);
void Lbl (string n, int x, int y, string t);
void Line(string sfx, double price, color col, ENUM_LINE_STYLE st, int wd, string lbl = "");

//+------------------------------------------------------------------+
//| INIT / DEINIT                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   g_prefix = "TM3_" + IntegerToString(ChartID()) + "_";
   ui.orderType     = UI_MARKET;
   ui.side          = UI_BUY;
   ui.lotSize       = InpDefaultLot;
   ui.slPoints      = InpDefaultSL;
   ui.tpPoints      = InpDefaultTP;
   ui.partialsCount = InpDefaultPartial;
   ui.isVisualizing = false;
   ui.basketEnabled = InpBasketEnabled;
   ui.customPrice   = 0;
   g_BasketPts      = InpBasketGreenPoints;

   LoadState();
   trade.SetExpertMagicNumber(MAGIC);
   SyncPosStates();

   RebuildPanel(true);
   UpdateSLTPPrices(SymbolInfoDouble(_Symbol, SYMBOL_ASK));

   PrintFormat("[TM3 v3.1] Ready | BE after Partial#%d (+%dpts) | Trailing=%s",
               InpBE_Trigger, InpBE_Offset, InpUseTrailingStop ? "ON" : "OFF");
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
}

//+------------------------------------------------------------------+
//| ON TICK                                                          |
//+------------------------------------------------------------------+
void OnTick()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   static double lastBid = 0, lastAsk = 0;
   static ulong lastUITick = 0;
   ulong nowMs = GetTickCount();
   
   // PERFORMANCE FIX: Throttle UI/Line redraws to max 4 times per second (250ms)
   // This prevents MT5 rendering queue from overflowing during volatile market moves
   if(nowMs - lastUITick >= 250)
   {
      // Only recalculate if price actually moved a reasonable amount
      if(MathAbs(bid - lastBid) >= _Point || MathAbs(ask - lastAsk) >= _Point)
      {
         lastBid = bid;
         lastAsk = ask;
         lastUITick = nowMs;
         
         double curr = (ui.side == UI_BUY) ? ask : bid;
         
         if(ui.orderType == UI_MARKET)
         {
            if(ObjectFind(0, g_prefix + "Edit_Price") >= 0)
            {
               // ONLY update the text. We removed the OBJPROP_BGCOLOR and COLOR 
               // updates because setting them on every tick causes massive lag.
               ObjectSetString(0, g_prefix + "Edit_Price", OBJPROP_TEXT, DoubleToString(curr, _Digits));
            }
            UpdateSLTPPrices(curr);
            if(ui.isVisualizing) DrawVisualization();
         }
         else
         {
            // For Limit orders, the entry price is static (customPrice).
            // We only need to ensure SL/TP prices are aligned with it.
            UpdateSLTPPrices(ui.customPrice);
         }
         
         double ref = (ui.orderType == UI_LIMIT) ? ui.customPrice : curr;
         UpdateStats(ref);
      }
   }

   // --- Trade Management ---
   // These functions have their own internal safe-guards so they don't drag performance
   ScanExternalTrades();
   ManagePositions();
   ManageTrailingStop();
   ManageDrawdownBasket();
   
   // Cleanup ghost lines every 3 seconds
   static datetime lastCleanup = 0;
   if(TimeCurrent() - lastCleanup >= 3)
   {
      CleanupOrphanedLines();
      lastCleanup = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| CHART EVENTS                                                     |
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
      if(sp == g_prefix + "Btn_Mkt")  { ui.orderType = UI_MARKET; UpdatePanelUI(); SaveState(); }
      if(sp == g_prefix + "Btn_Lim")
      {
         ui.orderType   = UI_LIMIT;
         ui.customPrice = (ui.side == UI_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
         ObjectSetString(0, g_prefix + "Edit_Price", OBJPROP_TEXT, DoubleToString(ui.customPrice, _Digits));
         UpdatePanelUI(); SaveState();
      }
      if(sp == g_prefix + "Btn_Buy")  { ui.side = UI_BUY;  UpdatePanelUI(); ExecuteOrder(); SaveState(); }
      if(sp == g_prefix + "Btn_Sell") { ui.side = UI_SELL; UpdatePanelUI(); ExecuteOrder(); SaveState(); }
      if(sp == g_prefix + "Btn_Vis")      { ToggleVisualization(); }
      if(sp == g_prefix + "Btn_Part")     { ManualPartial(); }
      if(sp == g_prefix + "Btn_BE")       { SetBreakEvenManual(); }
      if(sp == g_prefix + "Btn_CloseAll") { CloseAll(); }
      if(sp == g_prefix + "Btn_Export") { ExportToCSV(); }
      if(sp == g_prefix + "Btn_Inverse") { ui.inverseEnabled = !ui.inverseEnabled; UpdatePanelUI(); SaveState(); }
      if(sp == g_prefix + "Btn_AutoRisk") { ui.autoRiskEnabled = !ui.autoRiskEnabled; UpdatePanelUI(); SaveState(); }
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
//| POSITION STATE MANAGEMENT                                        |
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
   g_PosStates[n].posID        = posID;
   g_PosStates[n].ticket       = ticket;
   g_PosStates[n].partialsTaken = 0;
   g_PosStates[n].beSet        = false;
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
      
      long  pid    = posInfo.Identifier();
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
//| CORE: MANAGE POSITIONS                                           |
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

      int    totalPartials = ui.partialsCount;
      double step          = totalDist / (totalPartials + 1);
      int    taken         = g_PosStates[stIdx].partialsTaken;
      bool   beSet         = g_PosStates[stIdx].beSet;

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
      // --- STAGE 3: AUTO RISK SL SCALING ---
      if(ui.autoRiskEnabled && curSL > 0)
      {
         double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         double slDist = MathAbs(open - curSL);
         
         // Split SL into 2 segments: at midpoint take 1st loss, at final SL close all.
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
                  // Step 2: fully close the losing position
                  trade.PositionClose(ticket);
                  continue; 
               }
               else
               {
                  // Step 1: chop volume exactly in half
                  double slAmt = NormalizeDouble(posInfo.Volume() / 2.0, 2);
                  if(slAmt < minV) slAmt = minV;
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
      // -------------------------------------
      if(InpBE_Trigger > 0 && nextPartial == InpBE_Trigger && !beSet)
      {
         if(posInfo.SelectByTicket(ticket))
         {
            double newSL = isBuy ? open + InpBE_Offset * _Point : open - InpBE_Offset * _Point;
            newSL = NormaliseSL(newSL);

            double freshSL = posInfo.StopLoss();
            bool better = isBuy  ? (newSL > freshSL) : (freshSL == 0 || newSL < freshSL);
            
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
         }
      }
   }
}

//+------------------------------------------------------------------+
//| TRAILING STOP                                                    |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   if(!InpUseTrailingStop) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      bool isOwn = (posInfo.Magic() == MAGIC);
      bool isExt = InpMonitorExternal && IsRegisteredExternal(posInfo.Ticket());
      if(!isOwn && !isExt) continue;
      
      double open   = posInfo.PriceOpen();
      double curSL  = posInfo.StopLoss();
      double curTP  = posInfo.TakeProfit();
      double pt     = _Point;
      bool   isBuy  = (posInfo.PositionType() == POSITION_TYPE_BUY);
      
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
//| DAILY LOSS LIMIT                                                 |
//+------------------------------------------------------------------+
bool IsDailyLossLimitReached()
{
   if(!InpEnableDailyLossLimit) return false;
   datetime now        = TimeCurrent();
   datetime startOfDay = now - (now % 86400);
   if(!HistorySelect(startOfDay, now)) return false;

   int losers = 0;
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong dt = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(dt, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      if(HistoryDealGetInteger(dt, DEAL_MAGIC)  != MAGIC)         continue;
      if(HistoryDealGetString (dt, DEAL_SYMBOL) != _Symbol)       continue;
      
      double p = HistoryDealGetDouble(dt, DEAL_PROFIT)
               + HistoryDealGetDouble(dt, DEAL_COMMISSION)
               + HistoryDealGetDouble(dt, DEAL_SWAP);
               
      if(p < 0) losers++;
   }
   return (losers >= InpMaxDailyLosingTrades);
}

//+------------------------------------------------------------------+
//| ORDER EXECUTION                                                  |
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
      
   // --- STAGE 2: INVERSE LOGIC ---
   bool isInverse = (ui.orderType == UI_MARKET && ui.inverseEnabled);
   if(isInverse)
   {
       if(ui.side == UI_BUY) p = SymbolInfoDouble(_Symbol, SYMBOL_BID) - InpInverseOffset * _Point;
       else                  p = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + InpInverseOffset * _Point;
       p = NormaliseSL(p); 
   }
   // ------------------------------

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

// Helper to normalize volume for split logic (Add this right above ExecuteOrder)
double NormaliseVolume(double vol)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   return MathFloor(vol / step) * step;
}
//+------------------------------------------------------------------+
//| MANUAL ACTIONS                                                   |
//+------------------------------------------------------------------+
void SetBreakEvenManual()
{
   if(!posInfo.Select(_Symbol)) return;
   double open   = posInfo.PriceOpen();
   bool   isBuy  = (posInfo.PositionType() == POSITION_TYPE_BUY);
   double newSL  = NormaliseSL(isBuy ? open + InpBE_Offset * _Point : open - InpBE_Offset * _Point);
   
   if(trade.PositionModify(posInfo.Ticket(), newSL, posInfo.TakeProfit()))
   {
      if(InpEnableSounds) PlaySound(InpSoundBE);
      int idx = FindPosStateIdx(posInfo.Identifier());
      if(idx >= 0) g_PosStates[idx].beSet = true;
   }
}

void ManualPartial()
{
   if(!posInfo.Select(_Symbol)) return;
   double pct = StringToDouble(ObjectGetString(0, g_prefix + "Edit_ManPart", OBJPROP_TEXT));
   double amt = NormalizeDouble(posInfo.Volume() * (pct * 0.01), 2);
   double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(amt < minV) amt = minV;
   
   if(trade.PositionClosePartial(posInfo.Ticket(), amt))
      if(InpEnableSounds) PlaySound(InpSoundPartial);
}

void CloseAll()
{
   bool any = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != MAGIC) continue;
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

//+------------------------------------------------------------------+
//| BASKET (Auto Trade Handler)                                      |
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
   
   // Process Buy and Sell baskets entirely independently
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
      if(posInfo.PositionType() != type) continue; // Critical: Filter by direction
      
      bool isOwn = (posInfo.Magic() == MAGIC);
      bool isExt = InpMonitorExternal && IsRegisteredExternal(posInfo.Ticket());
      if(!isOwn && !isExt) continue;
      
      bool   isBuy = (type == POSITION_TYPE_BUY);
      double curr  = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sign  = isBuy ? 1.0 : -1.0;

      int n = ArraySize(managed);
      ArrayResize(managed, n + 1);
      managed[n].ticket    = posInfo.Ticket();
      managed[n].profit    = posInfo.Profit() + posInfo.Swap() + posInfo.Commission();
      managed[n].priceDiff = sign * (curr - posInfo.PriceOpen()) / _Point;
      managed[n].openTime  = (datetime)posInfo.Time();
   }

   if(ArraySize(managed) <= 1) return;
   
   int newestIdx = 0;
   for(int i = 1; i < ArraySize(managed); i++)
      if(managed[i].openTime > managed[newestIdx].openTime) newestIdx = i;
      
   for(int i = 0; i < ArraySize(managed); i++)
   {
      if(i == newestIdx) continue;
      bool green = (g_BasketPts <= 0) ? (managed[i].profit >= 0.0) : (managed[i].priceDiff >= g_BasketPts);
      if(green) trade.PositionClose(managed[i].ticket);
   }
}

//+------------------------------------------------------------------+
//| EXTERNAL TRADE MONITORING                                        |
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
      if(!posInfo.SelectByIndex(i))   continue;
      if(posInfo.Symbol() != _Symbol) continue;
      if(posInfo.Magic()  == MAGIC)   continue;
      ulong ticket = posInfo.Ticket();
      if(IsRegisteredExternal(ticket)) continue;
      
      int n = ArraySize(g_ExtTrades);
      ArrayResize(g_ExtTrades, n + 1);
      g_ExtTrades[n].ticket    = ticket;
      g_ExtTrades[n].posID     = posInfo.Identifier();
      g_ExtTrades[n].alertSent = false;
      
      EnsurePosState(posInfo.Identifier(), ticket);
      
      if(InpExternalAlerts)
      {
         string dir = (posInfo.PositionType() == POSITION_TYPE_BUY) ? "BUY" : "SELL";
         Alert(StringFormat("[TM3] External %s %.2f lots @ %.5f — partials activated", dir, posInfo.Volume(), posInfo.PriceOpen()));
         if(InpEnableSounds) PlaySound(InpSoundExtDetected);
         g_ExtTrades[n].alertSent = true;
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
//| EXPORT TO CSV                                                    |
//+------------------------------------------------------------------+
// Exports trading history for the current symbol and magic number
// Saves the file to the MQL5\\Files directory
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

   // Write header
   FileWrite(handle, "Ticket", "Time", "Type", "Volume", "Price", "SL", "TP", "Profit", "Commission", "Swap", "Comment");

   // Select all history
   HistorySelect(0, TimeCurrent());
   int total = HistoryDealsTotal();
   int exportedCount = 0;

   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      // Filter by magic number and symbol
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != MAGIC) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;

      // Get deal properties
      datetime time = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      long type = HistoryDealGetInteger(ticket, DEAL_TYPE);
      double vol = HistoryDealGetDouble(ticket, DEAL_VOLUME);
      double price = HistoryDealGetDouble(ticket, DEAL_PRICE);
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      double comm = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
      string comment = HistoryDealGetString(ticket, DEAL_COMMENT);

      // Get SL and TP from associated position if available
      double sl = 0, tp = 0;

      string typeStr = "Unknown";
      if(type == DEAL_TYPE_BUY) typeStr = "Buy";
      else if(type == DEAL_TYPE_SELL) typeStr = "Sell";

      // Write row
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
//| UTILITIES |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| UTILITIES                                                       |
//+------------------------------------------------------------------+
bool IsManagedPosition()
{
   if(posInfo.Symbol() != _Symbol) return false;
   return (posInfo.Magic() == MAGIC) || (InpMonitorExternal && IsRegisteredExternal(posInfo.Ticket()));
}

int CountManagedOpenPositions()
{
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
//| STATE PERSISTENCE                                                |
//+------------------------------------------------------------------+
void SaveState()
{
   string id = IntegerToString(ChartID());
   GlobalVariableSet("TM3_" + id + "_Type",   (double)ui.orderType);
   GlobalVariableSet("TM3_" + id + "_Side",   (double)ui.side);
   GlobalVariableSet("TM3_" + id + "_Lot",    ui.lotSize);
   GlobalVariableSet("TM3_" + id + "_SL",     (double)ui.slPoints);
   GlobalVariableSet("TM3_" + id + "_TP",     (double)ui.tpPoints);
   GlobalVariableSet("TM3_" + id + "_Parts",  (double)ui.partialsCount);
   GlobalVariableSet("TM3_" + id + "_Basket", (double)ui.basketEnabled);
   GlobalVariableSet("TM3_" + id + "_Inv", (double)ui.inverseEnabled);
   GlobalVariableSet("TM3_" + id + "_AutoRisk", (double)ui.autoRiskEnabled);
}

void LoadState()
{
   string id = IntegerToString(ChartID());
   if(!GlobalVariableCheck("TM3_" + id + "_Type")) return;
   ui.orderType     = (ENUM_ORDER_TYPE_UI)(int)GlobalVariableGet("TM3_" + id + "_Type");
   ui.side          = (ENUM_SIDE_UI)      (int)GlobalVariableGet("TM3_" + id + "_Side");
   ui.lotSize       =                         GlobalVariableGet("TM3_" + id + "_Lot");
   ui.slPoints      = (int)                   GlobalVariableGet("TM3_" + id + "_SL");
   ui.tpPoints      = (int)                   GlobalVariableGet("TM3_" + id + "_TP");
   ui.partialsCount = (int)                   GlobalVariableGet("TM3_" + id + "_Parts");
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
//| GUI PANEL                                                        |
//+------------------------------------------------------------------+
int PanelHeight()
{
   return 500 + MathMax(ui.partialsCount, 0) * 18;
}

void RebuildPanel(bool doUpdateUI)
{
   int sw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int sh = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   int bx = 10, by = 50;

   if(InpPanelCorner == CORNER_RIGHT_UPPER)  bx = sw - PANEL_W - 10;
   if(InpPanelCorner == CORNER_LEFT_LOWER)   by = sh - PanelHeight() - 30;
   if(InpPanelCorner == CORNER_RIGHT_LOWER) { bx = sw - PANEL_W - 10; by = sh - PanelHeight() - 30; }

   CreatePanelElements(bx, by);
   if(doUpdateUI) UpdatePanelUI();
}

void CreatePanelElements(int x, int y)
{
   Rect("BG", x, y, PANEL_W, PanelHeight(), COLOR_BG);
   y += PAD;
   Btn("Btn_Mkt", x+5,   y, 110, ROW_H, "MARKET", (ui.orderType == UI_MARKET));
   Btn("Btn_Lim", x+115, y, 110, ROW_H, "LIMIT",  (ui.orderType == UI_LIMIT));
   y += ROW_H + PAD;
   Lbl("Lbl_Prc",   x+5,  y+5, "Price:");
   Edit("Edit_Price", x+55, y, 170, ROW_H, "0.00000");
   y += ROW_H + PAD;
   Btn("Btn_Buy",  x+5,   y, 110, ROW_H, "BUY",  false, COLOR_BUY);
   Btn("Btn_Sell", x+115, y, 110, ROW_H, "SELL", false, COLOR_SELL);
   y += ROW_H + PAD;
   Lbl("Lbl_Lot", x+5, y+5, "Lot:");
   Edit("Edit_Lot", x+115, y, 110, ROW_H, DoubleToString(ui.lotSize, 2));
   y += ROW_H + PAD;
   Lbl("Lbl_SL",    x+5,   y+5, "SL pts:");
   Edit("Edit_SL",  x+65,  y, 55, ROW_H, IntegerToString(ui.slPoints));
   Lbl("Lbl_SLP",   x+125, y+5, "Prc:");
   Edit("Edit_SL_Prc", x+148, y, 77, ROW_H, "0.00000");
   y += ROW_H + PAD;
   Lbl("Lbl_TP",    x+5,   y+5, "TP pts:");
   Edit("Edit_TP",  x+65,  y, 55, ROW_H, IntegerToString(ui.tpPoints));
   Lbl("Lbl_TPP",   x+125, y+5, "Prc:");
   Edit("Edit_TP_Prc", x+148, y, 77, ROW_H, "0.00000");
   y += ROW_H + PAD;
   Lbl("Lbl_Part",   x+5,   y+5, "Partials #:");
   Edit("Edit_Part", x+115, y, 110, ROW_H, IntegerToString(ui.partialsCount));
   y += ROW_H + PAD;
   Rect("Sep3", x+5, y, PANEL_W-10, 1, C'80,80,80');
   y += 5;
   UpdatePartialList(x, y);
   y += (ui.partialsCount > 0 ? ui.partialsCount * 18 : 5);
   Rect("Sep1", x+5, y, PANEL_W-10, 1, C'60,60,60');
   y += 5;
   Lbl("Lbl_Risk", x+5,   y+5, "Risk:");
   Lbl("Val_Risk", x+45,  y+5, "$0.00");
   ObjectSetInteger(0, g_prefix+"Val_Risk", OBJPROP_COLOR, clrCrimson);
   Lbl("Lbl_Rew",  x+115, y+5, "Profit:");
   Lbl("Val_Rew",  x+158, y+5, "$0.00");
   ObjectSetInteger(0, g_prefix+"Val_Rew", OBJPROP_COLOR, clrLimeGreen);
   y += 20;
   Rect("Sep2", x+5, y, PANEL_W-10, 1, C'60,60,60');
   y += 5;
   Btn("Btn_Vis",  x+5, y, 220, ROW_H, "VISUALIZE", false, C'80,80,80');
   y += ROW_H + PAD;
   Edit("Edit_ManPart", x+5,  y, 50,  ROW_H, "20");
   Btn("Btn_Part",      x+60, y, 165, ROW_H, "TAKE PARTIAL %", false, C'80,80,0');
   y += ROW_H + PAD;
   Btn("Btn_BE",       x+5, y, 220, ROW_H, "BREAK EVEN",  false, C'0,80,80');
   y += ROW_H + PAD;
      Btn("Btn_CloseAll", x+5, y, 220, ROW_H, "CLOSE ALL", false, clrRed);
   y += ROW_H + PAD;
   
   // Toggles (Side by Side)
   Btn("Btn_Export", x+5, y, 105, ROW_H, "EXPORT CSV", false, C'50,100,50');
   Btn("Btn_Inverse", x+115, y, 110, ROW_H, ui.inverseEnabled ? "INV: ON" : "INV: OFF", false, ui.inverseEnabled ? C'180,100,0' : C'80,80,80');
   y += ROW_H + PAD;
   
   Rect("Sep4", x+5, y, PANEL_W-10, 1, C'80,80,80');
   y += 6;
   
   Lbl("Lbl_AutoRisk", x+5, y+5, "Auto Risk:");
   Btn("Btn_AutoRisk", x+95, y, 130, ROW_H, ui.autoRiskEnabled ? "ON" : "OFF", false, ui.autoRiskEnabled ? C'180,0,100' : C'120,0,0');
   y += ROW_H + PAD;
   
   Lbl("Lbl_Basket", x+5, y+5, "Auto Handler:");
   Btn("Btn_Basket", x+95, y, 130, ROW_H, ui.basketEnabled ? "ON" : "OFF", false, ui.basketEnabled ? C'0,140,0' : C'120,0,0');
   y += ROW_H + PAD;
   
   Lbl("Lbl_GreenPts", x+5, y+5, "Close pts:");
   Edit("Edit_GreenPts", x+85, y, 140, ROW_H, IntegerToString(InpBasketGreenPoints));
}

void UpdatePanelUI()
{
   ObjectSetInteger(0, g_prefix+"Btn_Mkt",  OBJPROP_BGCOLOR, ui.orderType==UI_MARKET ? COLOR_ACT : COLOR_BTN);
   ObjectSetInteger(0, g_prefix+"Btn_Lim",  OBJPROP_BGCOLOR, ui.orderType==UI_LIMIT  ? COLOR_ACT : COLOR_BTN);
   ObjectSetInteger(0, g_prefix+"Btn_Buy",  OBJPROP_BGCOLOR, COLOR_BUY);
   ObjectSetInteger(0, g_prefix+"Btn_Sell", OBJPROP_BGCOLOR, COLOR_SELL);
   ObjectSetInteger(0, g_prefix+"Btn_Buy",  OBJPROP_COLOR,   COLOR_TEXT);
   ObjectSetInteger(0, g_prefix+"Btn_Sell", OBJPROP_COLOR,   COLOR_TEXT);
   ObjectSetInteger(0, g_prefix+"Btn_Vis",  OBJPROP_BGCOLOR, ui.isVisualizing ? COLOR_ACT : C'80,80,80');
   if(ObjectFind(0, g_prefix+"Btn_Basket") >= 0)
   {
      ObjectSetString (0, g_prefix+"Btn_Basket", OBJPROP_TEXT,    ui.basketEnabled ? "ON" : "OFF");
      ObjectSetInteger(0, g_prefix+"Btn_Basket", OBJPROP_BGCOLOR, ui.basketEnabled ? C'0,140,0' : C'120,0,0');
   }
      if(ObjectFind(0, g_prefix+"Btn_Inverse") >= 0)
   {
      ObjectSetString (0, g_prefix+"Btn_Inverse", OBJPROP_TEXT, ui.inverseEnabled ? "INV: ON" : "INV: OFF");
      ObjectSetInteger(0, g_prefix+"Btn_Inverse", OBJPROP_BGCOLOR, ui.inverseEnabled ? C'180,100,0' : C'80,80,80');
   }
   if(ObjectFind(0, g_prefix+"Btn_AutoRisk") >= 0)
   {
      ObjectSetString (0, g_prefix+"Btn_AutoRisk", OBJPROP_TEXT, ui.autoRiskEnabled ? "ON" : "OFF");
      ObjectSetInteger(0, g_prefix+"Btn_AutoRisk", OBJPROP_BGCOLOR, ui.autoRiskEnabled ? C'180,0,100' : C'120,0,0');
   }
}

void UpdatePartialList(int x, int y)
{
   for(int i = 1; i <= 20; i++) ObjectDelete(0, g_prefix + "PTL_" + IntegerToString(i));
   if(ui.partialsCount <= 0 || ui.tpPoints <= 0) return;

   double step = (double)ui.tpPoints / (ui.partialsCount + 1);
   for(int i = 1; i <= ui.partialsCount; i++)
   {
      int    pts = (int)MathRound(step * i);
      string txt = "TP" + IntegerToString(i) + ": " + IntegerToString(pts) + " pts";
      Lbl("PTL_" + IntegerToString(i), x+10, y, txt);
      ObjectSetInteger(0, g_prefix+"PTL_"+IntegerToString(i), OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, g_prefix+"PTL_"+IntegerToString(i), OBJPROP_COLOR,    C'140,140,140');
      y += 18;
   }
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
   
   double pmf      = (_Point / ts) * tv;
   double riskUSD  = ui.lotSize * ui.slPoints * pmf;
   double rewUSD   = 0;
   double remLot   = ui.lotSize;
   double volStep  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double stepPts  = (double)ui.tpPoints / (ui.partialsCount + 1);

   for(int i = 1; i <= ui.partialsCount; i++)
   {
      double pct     = (i == 1) ? InpMainPartialVol : InpRollingPartialVol;
      double partLot = MathFloor(ui.lotSize * (pct * 0.01) / volStep) * volStep;
      if(partLot < minLot) partLot = 0;
      if(partLot > 0 && partLot <= remLot)
      { rewUSD += partLot * stepPts * i * pmf; remLot -= partLot; }
   }
   remLot = NormalizeDouble(remLot, 2);
   if(remLot > 0) rewUSD += remLot * ui.tpPoints * pmf;
   
   if(ObjectFind(0, g_prefix+"Val_Risk") >= 0) ObjectSetString(0, g_prefix+"Val_Risk", OBJPROP_TEXT, "$"+DoubleToString(riskUSD, 2));
   if(ObjectFind(0, g_prefix+"Val_Rew") >= 0)  ObjectSetString(0, g_prefix+"Val_Rew",  OBJPROP_TEXT, "$"+DoubleToString(rewUSD,  2));
}

void ToggleVisualization()
{
   ui.isVisualizing = !ui.isVisualizing;
   if(!ui.isVisualizing)
   {
      // Cleanup dual lines
      ObjectDelete(0, g_prefix+"VisB_Entry"); ObjectDelete(0, g_prefix+"VisS_Entry");
      ObjectDelete(0, g_prefix+"VisB_SL");    ObjectDelete(0, g_prefix+"VisS_SL");
      ObjectDelete(0, g_prefix+"VisB_TP");    ObjectDelete(0, g_prefix+"VisS_TP");
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
   double pBuy  = (ui.orderType == UI_LIMIT) ? ui.customPrice : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double pSell = (ui.orderType == UI_LIMIT) ? ui.customPrice : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Draw both paths simultaneously
   DrawSideVis(pBuy, UI_BUY);
   DrawSideVis(pSell, UI_SELL);
}

void DrawSideVis(double ep, ENUM_SIDE_UI side)
{
   color  c    = (side == UI_BUY) ? COLOR_BUY : COLOR_SELL;
   string pfx  = (side == UI_BUY) ? "VisB_" : "VisS_";
   
   double sl   = (ui.slPoints > 0) ? ((side == UI_BUY) ? ep - ui.slPoints * _Point : ep + ui.slPoints * _Point) : 0;
   double tp   = (side == UI_BUY) ? ep + ui.tpPoints * _Point : ep - ui.tpPoints * _Point;
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

//+------------------------------------------------------------------+
//| GUI PRIMITIVE HELPERS                                            |
//+------------------------------------------------------------------+
void Btn(string n, int x, int y, int w, int h, string t, bool act, color b = COLOR_BTN)
{
   string nm = g_prefix + n;
   if(ObjectFind(0, nm) < 0)
   {
      ObjectCreate(0, nm, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_CORNER,     InpPanelCorner);
   }
   ObjectSetInteger(0, nm, OBJPROP_ZORDER, 100);
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nm, OBJPROP_XSIZE,     w);
   ObjectSetInteger(0, nm, OBJPROP_YSIZE,     h);
   ObjectSetString (0, nm, OBJPROP_TEXT,      t);
   ObjectSetInteger(0, nm, OBJPROP_BGCOLOR,   act ? COLOR_ACT : b);
   ObjectSetInteger(0, nm, OBJPROP_COLOR,     COLOR_TEXT);
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE,  8);
   ObjectSetInteger(0, nm, OBJPROP_BORDER_COLOR, C'80,80,80');
}

void Rect(string n, int x, int y, int w, int h, color bg)
{
   string nm = g_prefix + n;
   if(ObjectFind(0, nm) < 0)
   {
      ObjectCreate(0, nm, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_CORNER,     InpPanelCorner);
   }
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nm, OBJPROP_XSIZE,     w);
   ObjectSetInteger(0, nm, OBJPROP_YSIZE,     h);
   ObjectSetInteger(0, nm, OBJPROP_BGCOLOR,   bg);
   ObjectSetInteger(0, nm, OBJPROP_BORDER_COLOR, bg);
}

void Edit(string n, int x, int y, int w, int h, string t)
{
   string nm = g_prefix + n;
   if(ObjectFind(0, nm) < 0)
   {
      ObjectCreate(0, nm, OBJ_EDIT, 0, 0, 0);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_CORNER,     InpPanelCorner);
   }
   ObjectSetInteger(0, nm, OBJPROP_ZORDER, 200);
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nm, OBJPROP_XSIZE,     w);
   ObjectSetInteger(0, nm, OBJPROP_YSIZE,     h);
   ObjectSetString (0, nm, OBJPROP_TEXT,      t);
   ObjectSetInteger(0, nm, OBJPROP_BGCOLOR,   COLOR_EDIT);
   ObjectSetInteger(0, nm, OBJPROP_COLOR,     COLOR_TEXT);
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE,  8);
   ObjectSetInteger(0, nm, OBJPROP_BORDER_COLOR, C'80,80,80');
}

void Lbl(string n, int x, int y, string t)
{
   string nm = g_prefix + n;
   if(ObjectFind(0, nm) < 0)
   {
      ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_CORNER,     InpPanelCorner);
   }
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   ObjectSetString (0, nm, OBJPROP_TEXT,      t);
   ObjectSetInteger(0, nm, OBJPROP_COLOR,     C'180,180,180');
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE,  8);
}

void Line(string sfx, double price, color col, ENUM_LINE_STYLE st, int wd, string lbl = "")
{
   string nm = g_prefix + sfx;
   if(ObjectFind(0, nm) < 0)
      ObjectCreate(0, nm, OBJ_HLINE, 0, 0, price);
   ObjectSetDouble (0, nm, OBJPROP_PRICE,     price);
   ObjectSetInteger(0, nm, OBJPROP_COLOR,     col);
   ObjectSetInteger(0, nm, OBJPROP_STYLE,     st);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH,     wd);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE,false);
   if(lbl != "") ObjectSetString(0, nm, OBJPROP_TEXT, lbl);
}
//+------------------------------------------------------------------+