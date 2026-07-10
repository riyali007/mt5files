//+------------------------------------------------------------------+
//|                                     TradeManagerPro_v9.12.mq5    |
//|                     Professional MT5 Trade Panel & Manager v9.09 |
//|        Updated: InpScenarioOffset input added, Spread applied to BUY entries, SL=0 support    |
//+------------------------------------------------------------------+
#property copyright "Professional MT5 Developer"
#property version   "9.12"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\DealInfo.mqh>

//--- Resource & Inputs
input group "Panel Settings"
input ENUM_BASE_CORNER InpPanelCorner = CORNER_LEFT_UPPER; 

input group "Risk Settings (XAUUSD Defaults)"
input double   InpDefaultLot      = 0.05;       // Default Lot Size
input int      InpDefaultSL       = 500;        // Default SL (50 Pips for Gold)
input int      InpDefaultTP       = 1500;       // Default TP (150 Pips for Gold)

input group "Partial Settings"
input double   InpMainPartialVol  = 40.0;       // 1st Partial Volume % (Secure 40%)
input double   InpRollingPartialVol = 20.0;     // Subsequent Partials % (20% each)
input int      InpDefaultPartial = 3;           // Default Partials (Creates 4 Split Orders)

input group "Advanced Management"
input bool     InpUseSteppedSL    = true;       // Move SL to previous TP level?
input int      InpBE_Trigger      = 1;          // Set BE after Partial #
input int      InpBE_Offset       = 20;         // BE Offset (2 Pips - Covers Gold Spread)

input group "Scenario Settings"
input int      InpScenarioOffset  = 0;          // Scenario Offset (points beyond box edge)

input group "Trailing Stop Settings"
input bool     InpUseTrailing       = true;     // Enable Trailing Stop?
input int      InpTrailStartPoints  = 300;      // Activate after X points profit
input int      InpTrailStartPartial = 3;        // OR Activate after Partial # (0 = disable)
input int      InpTrailStep         = 100;      // Move SL every X points
input int      InpTrailDistance     = 100;      // Distance behind price to keep SL

input group "Sound Settings"
input bool     InpEnableSounds    = true;
input string   InpSoundEntry      = "Ok.wav";
input string   InpSoundPartial    = "News.wav";
input string   InpSoundBE         = "Expert.wav";
input string   InpSoundSL         = "timeout.wav";
input string   InpSoundTP         = "alert.wav";
input string   InpSoundClose      = "stops.wav"; 

//--- Global Classes
CTrade          trade;
CPositionInfo   posInfo;

//--- State Enums
enum ENUM_ORDER_TYPE_UI { UI_MARKET, UI_LIMIT };
enum ENUM_SIDE_UI       { UI_BUY, UI_SELL };
enum ENUM_SCENARIO_MODE { SCENARIO_OFF, SCENARIO_BREAKOUT, SCENARIO_RANGE };

//--- Global State
struct State {
   ENUM_ORDER_TYPE_UI orderType;
   ENUM_SIDE_UI       side;
   double             lotSize;
   int                slPoints;
   int                tpPoints;
   double             slPrice;        
   double             tpPrice;        
   int                partialsCount;
   double             customPrice;    
   bool               isVisualizing;
   bool               splitOrders;    
   
   // Scenario State
   ENUM_SCENARIO_MODE scenarioMode;
   string             boxObjName;
   double             boxHigh;
   double             boxLow;
   int                scenarioOffset; // Offset points for scenario limit orders
};

State uiState;
int   global_ChartWidth  = 0;
int   global_ChartHeight = 0;

//--- GUI Constants
#define PREFIX          "TMP_"
#define COLOR_BG        C'35,35,35'
#define COLOR_BTN       C'60,60,60'
#define COLOR_BTN_ACT   C'0,120,215'
#define COLOR_BUY       C'46,204,113'
#define COLOR_SELL      C'231,76,60'
#define COLOR_TEXT      clrWhite
#define COLOR_LABEL     C'180,180,180'
#define COLOR_EDIT_BG   C'50,50,50'
#define PANEL_W         230             
#define PANEL_H         550             
#define ROW_H           25
#define PAD             5

//+------------------------------------------------------------------+
//| FORWARD DECLARATIONS                                             |
//+------------------------------------------------------------------+
void SaveUIState();
void LoadUIState();
void ClearSavedState();
void UpdatePanelPosition(bool force = false);
void CreatePanelElements(int x, int y);
void UpdatePanelUI();
void UpdateSLTPPrices(double entryPrice);
void UpdateStats(double priceRef);
void UpdatePartialTPList(int x, int y);
void ToggleVisualization();
void DrawVisualization(double entryPrice);
void ToggleScenario();
void DrawScenario();
void ExecuteOrder();
void ExecuteScenarioOrders();
void ManualPartial();
void CloseAllPositions(); 
void SetBreakEven(int mode);
void ManagePartialsAndVisuals();
void ManageTrailingStop(); // NEW
void CleanupOrphanedLines();
bool IsPartialTaken(long posID, int partialIndex);
void CreateBtn(string name, int x, int y, int w, int h, string text, bool active, color baseCol=COLOR_BTN);
void CreateRect(string name, int x, int y, int w, int h, color bg, ENUM_BORDER_TYPE border);
void CreateEdit(string name, int x, int y, int w, int h, string text);
void CreateLabel(string name, int x, int y, string text);
void CreateLine(string suffix, double price, color col, ENUM_LINE_STYLE style, int width, string labelText="");
void ApplySteppedSL(ulong t, int k, double o, double step, double curSL, double curTP);
double CalculateRealBEPrice(ulong ticket);


//+------------------------------------------------------------------+
//| Returns current broker spread in points                          |
//+------------------------------------------------------------------+
int GetCurrentSpread()
{
   return (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
}
//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   uiState.orderType = UI_MARKET;
   uiState.side      = UI_BUY;
   uiState.lotSize   = InpDefaultLot;
   uiState.slPoints  = InpDefaultSL;
   uiState.tpPoints  = InpDefaultTP;
   uiState.partialsCount = InpDefaultPartial;
   uiState.isVisualizing = false;
   uiState.splitOrders   = false; 
   uiState.customPrice   = 0; 
   uiState.scenarioMode  = SCENARIO_OFF;
   uiState.scenarioOffset = InpScenarioOffset;
   
   LoadUIState();
   trade.SetExpertMagicNumber(123456);
   UpdatePanelPosition(true); 
   double currentP = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   UpdateSLTPPrices(currentP);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(reason == REASON_CHARTCHANGE || reason == REASON_RECOMPILE || reason == REASON_CLOSE)
      SaveUIState();
   else if(reason == REASON_REMOVE)
      ClearSavedState();
   ObjectsDeleteAll(0, PREFIX);
}

void OnTick()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double currentPrice = (uiState.side == UI_BUY) ? ask : bid;

   if(uiState.orderType == UI_MARKET) {
      if(ObjectFind(0, PREFIX+"Edit_Price") >= 0) {
         ObjectSetString(0, PREFIX+"Edit_Price", OBJPROP_TEXT, DoubleToString(currentPrice, _Digits));
         ObjectSetInteger(0, PREFIX+"Edit_Price", OBJPROP_READONLY, true);
         ObjectSetInteger(0, PREFIX+"Edit_Price", OBJPROP_BGCOLOR, C'40,40,40'); 
         ObjectSetInteger(0, PREFIX+"Edit_Price", OBJPROP_COLOR, C'150,150,150');
      }
      UpdateSLTPPrices(currentPrice);
      if(uiState.isVisualizing) DrawVisualization(currentPrice);
   } else {
      if(ObjectFind(0, PREFIX+"Edit_Price") >= 0) {
         ObjectSetInteger(0, PREFIX+"Edit_Price", OBJPROP_READONLY, false);
         ObjectSetInteger(0, PREFIX+"Edit_Price", OBJPROP_BGCOLOR, COLOR_EDIT_BG);
         ObjectSetInteger(0, PREFIX+"Edit_Price", OBJPROP_COLOR, clrWhite);
      }
      UpdateSLTPPrices(uiState.customPrice);
      if(uiState.isVisualizing) DrawVisualization(uiState.customPrice);
   }

   double refPrice = (uiState.orderType == UI_LIMIT) ? uiState.customPrice : currentPrice;
   UpdateStats(refPrice);
   ManagePartialsAndVisuals();
   ManageTrailingStop(); // <--- NEW: Trailing Logic Hook
   CleanupOrphanedLines();
   
   if(uiState.scenarioMode != SCENARIO_OFF) DrawScenario(); 
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE) {
      int w = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
      int h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
      if(w != global_ChartWidth || h != global_ChartHeight) {
         global_ChartWidth = w; global_ChartHeight = h;
         UpdatePanelPosition(false);
      }
      return;
   }

   if(id == CHARTEVENT_OBJECT_CLICK) {
      if(sparam == PREFIX "Btn_Mkt")  { uiState.orderType = UI_MARKET; UpdatePanelUI(); SaveUIState(); }
      if(sparam == PREFIX "Btn_Lim")  { 
         uiState.orderType = UI_LIMIT;  
         uiState.customPrice = (uiState.side == UI_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
         ObjectSetString(0, PREFIX+"Edit_Price", OBJPROP_TEXT, DoubleToString(uiState.customPrice, _Digits));
         UpdatePanelUI(); SaveUIState();
      }
      if(sparam == PREFIX "Btn_Buy")  { uiState.side = UI_BUY;  UpdatePanelUI(); SaveUIState(); }
      if(sparam == PREFIX "Btn_Sell") { uiState.side = UI_SELL; UpdatePanelUI(); SaveUIState(); }
      
      if(sparam == PREFIX "Btn_Mode") { 
         uiState.splitOrders = !uiState.splitOrders; 
         UpdatePanelUI(); 
         SaveUIState(); 
      }
      
      if(sparam == PREFIX "Btn_Vis")  { ToggleVisualization(); }
      if(sparam == PREFIX "Btn_Scen") { ToggleScenario(); }
      
      if(sparam == PREFIX "Btn_Exec") { 
         if(uiState.scenarioMode != SCENARIO_OFF) ExecuteScenarioOrders();
         else ExecuteOrder(); 
      }
      
      if(sparam == PREFIX "Btn_Part") { ManualPartial(); }
      if(sparam == PREFIX "Btn_BE_E") { SetBreakEven(1); }
      if(sparam == PREFIX "Btn_BE_A") { SetBreakEven(2); }
      if(sparam == PREFIX "Btn_CloseAll") { CloseAllPositions(); }
   }
   
   if(id == CHARTEVENT_OBJECT_ENDEDIT) {
      if(sparam == PREFIX "Edit_Lot")   uiState.lotSize  = StringToDouble(ObjectGetString(0, sparam, OBJPROP_TEXT));
      if(sparam == PREFIX "Edit_Part")  {
         uiState.partialsCount = (int)StringToInteger(ObjectGetString(0, sparam, OBJPROP_TEXT));
         UpdatePanelPosition(true); 
      }
      
      if(sparam == PREFIX "Edit_Price" && uiState.orderType == UI_LIMIT) {
         uiState.customPrice = StringToDouble(ObjectGetString(0, sparam, OBJPROP_TEXT));
         if(uiState.isVisualizing) DrawVisualization(uiState.customPrice);
      }
      
      double entry = (uiState.orderType == UI_LIMIT) ? uiState.customPrice : 
                     ((uiState.side == UI_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID));
      
      if(sparam == PREFIX "Edit_SL") {
         uiState.slPoints = (int)StringToInteger(ObjectGetString(0, sparam, OBJPROP_TEXT));
         UpdateSLTPPrices(entry); 
      }
      if(sparam == PREFIX "Edit_TP") {
         uiState.tpPoints = (int)StringToInteger(ObjectGetString(0, sparam, OBJPROP_TEXT));
         UpdateSLTPPrices(entry); 
         UpdatePanelPosition(true); 
      }
      if(sparam == PREFIX "Edit_SL_Prc") {
         double userPrice = StringToDouble(ObjectGetString(0, sparam, OBJPROP_TEXT));
         if(entry > 0) {
            uiState.slPoints = (int)MathAbs((entry - userPrice) / _Point);
            ObjectSetString(0, PREFIX+"Edit_SL", OBJPROP_TEXT, IntegerToString(uiState.slPoints));
         }
      }
      if(sparam == PREFIX "Edit_TP_Prc") {
         double userPrice = StringToDouble(ObjectGetString(0, sparam, OBJPROP_TEXT));
         if(entry > 0) {
            uiState.tpPoints = (int)MathAbs((entry - userPrice) / _Point);
            ObjectSetString(0, PREFIX+"Edit_TP", OBJPROP_TEXT, IntegerToString(uiState.tpPoints));
            UpdatePanelPosition(true); 
         }
      }
      
      if(sparam == PREFIX "Edit_ScenOff") {
         uiState.scenarioOffset = (int)StringToInteger(ObjectGetString(0, sparam, OBJPROP_TEXT));
         if(uiState.scenarioMode != SCENARIO_OFF) DrawScenario();
      }
      if(uiState.isVisualizing) DrawVisualization(entry);
      if(uiState.scenarioMode != SCENARIO_OFF) DrawScenario();
      UpdateStats(entry);
      SaveUIState();
   }
}

//+------------------------------------------------------------------+
//| Management Logic                                                 |
//+------------------------------------------------------------------+
void ManagePartialsAndVisuals() {
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol() == _Symbol && posInfo.Magic() == 123456) {
         double o = posInfo.PriceOpen(), tp = posInfo.TakeProfit(), sl = posInfo.StopLoss();
         double curr = 0.0;
         if(posInfo.PositionType() == POSITION_TYPE_BUY) curr = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         else curr = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

         if(tp == 0 && !uiState.splitOrders) continue; 
         
         double theoreticalDist = uiState.tpPoints * _Point; 
         double step = theoreticalDist / (uiState.partialsCount + 1);
         ulong t = posInfo.Ticket();
         
         for(int k=1; k<=uiState.partialsCount; k++) {
            double pP = (posInfo.PositionType() == POSITION_TYPE_BUY) ? o + (step * k) : o - (step * k);
            string lN = PREFIX + "Live_P_" + IntegerToString(t) + "_" + IntegerToString(k);
            bool crossed = (posInfo.PositionType() == POSITION_TYPE_BUY) ? (curr >= pP) : (curr <= pP);
            
            // --- MODE: PARTIALS (Single Order) ---
            if(!uiState.splitOrders) {
               if(IsPartialTaken(posInfo.Identifier(), k)) { 
                  if(ObjectFind(0, lN) >= 0) ObjectDelete(0, lN);
                  if(InpUseSteppedSL) ApplySteppedSL(t, k, o, step, sl, tp);
               } else {
                  int displayPts = (int)MathRound((step * k) / _Point);
                  if(ObjectFind(0, lN) < 0) CreateLine("Live_P_" + IntegerToString(t) + "_" + IntegerToString(k), pP, clrGoldenrod, STYLE_DOT, 1, "TP"+IntegerToString(k)+": "+IntegerToString(displayPts)+" pts"); 
                  if(crossed) {
                     double pct = (k==1) ? InpMainPartialVol : InpRollingPartialVol;
                     double amt = NormalizeDouble(posInfo.Volume() * (pct / 100.0), 2);
                     if(amt < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) amt = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
                     if(trade.PositionClosePartial(t, amt)) { if(InpEnableSounds) PlaySound(InpSoundPartial); }
                  }
               }
            }
            // --- MODE: ORDERS (Split) ---
            else {
               if(ObjectFind(0, lN) >= 0) ObjectDelete(0, lN); 
               if(crossed) {
                  if(InpUseSteppedSL) ApplySteppedSL(t, k, o, step, sl, tp);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| REAL BE LOGIC - ** CUSTOMER EDIT ZONE ** |
//+------------------------------------------------------------------+
// This is where you requested to fix the Real BE calculation yourself.
// You can use 'posInfo.PriceOpen()' and your own math here.
double CalculateRealBEPrice(ulong ticket) {
   if(!posInfo.SelectByTicket(ticket)) return 0;
   
   // --- BEGIN: CUSTOM BE CALCULATION ---
   // Implement your logic here:
   // e.g. For Buy: Entry - (Entry % 20)
   // NOTE: Be careful with (Entry - 20%), this sets SL BELOW entry.
   
   // Current Default Logic (Swap + Comm):
   double totalCost = 0.0;
   totalCost += posInfo.Swap();
   
   if(HistorySelectByPosition(posInfo.Identifier())) {
      for(int i=0; i<HistoryDealsTotal(); i++) {
         ulong dTicket = HistoryDealGetTicket(i);
         totalCost += HistoryDealGetDouble(dTicket, DEAL_COMMISSION) + HistoryDealGetDouble(dTicket, DEAL_SWAP);
      }
   }
   
   double bufferPoints = 0.0;
   if(totalCost < 0) {
      double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      
      if(tickVal > 0 && posInfo.Volume() > 0) {
         bufferPoints = (MathAbs(totalCost) / (posInfo.Volume() * tickVal)) * tickSize;
      }
   }
   
   bufferPoints += (InpBE_Offset * _Point); 
   
   if(posInfo.PositionType() == POSITION_TYPE_BUY) return posInfo.PriceOpen() + bufferPoints;
   else return posInfo.PriceOpen() - bufferPoints;
   
   // --- END: CUSTOM BE CALCULATION ---
}

void ApplySteppedSL(ulong t, int k, double o, double step, double curSL, double curTP) {
   // 1. Guard: If the current partial (k) is LESS than your configured trigger, DO NOT MOVE.
   if (k < InpBE_Trigger) return;

   double targetSL = 0;

   // 2. If we just hit the Trigger (e.g., Partial 5), Move to Break Even
   if (k == InpBE_Trigger) {
      // Simple BE with offset (Auto Real BE removed)
      targetSL = (posInfo.PositionType() == POSITION_TYPE_BUY) ? o + InpBE_Offset*_Point : o - InpBE_Offset*_Point;
   } 
   // 3. If we are PAST the Trigger (e.g., Partial 6, 7...), use Stepped Logic
   else {
      // Moves SL to the previous partial level (k-1)
      targetSL = (posInfo.PositionType() == POSITION_TYPE_BUY) ? o + (step * (k-1)) : o - (step * (k-1));
   }
   
   // 4. Execute the Modification if it improves the position
   bool update = false;
   // Only move SL UP for Buys
   if(posInfo.PositionType() == POSITION_TYPE_BUY && targetSL > curSL) update = true;
   // Only move SL DOWN for Sells
   if(posInfo.PositionType() == POSITION_TYPE_SELL && (targetSL < curSL || curSL == 0)) update = true;
   
   if(update) trade.PositionModify(t, targetSL, curTP);
}

void SetBreakEven(int mode) {
   if(!posInfo.Select(Symbol())) return;
   double open  = posInfo.PriceOpen(), tp = posInfo.TakeProfit(), point = _Point;
   double newSL = 0.0;
   
   if(mode == 1) {
      // Simple BE (Entry + Offset)
      double offset = InpBE_Offset * point;
      if(posInfo.PositionType() == POSITION_TYPE_BUY) newSL = open + offset; else newSL = open - offset;
   } else if(mode == 2) {
      // Real BE (Calculate Costs + Offset)
      newSL = CalculateRealBEPrice(posInfo.Ticket());
   }
   
   // Round to Tick Size to avoid invalid price errors
   double tickSz = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSz > 0) newSL = MathRound(newSL / tickSz) * tickSz;
   
   if(trade.PositionModify(posInfo.Ticket(), newSL, tp)) if(InpEnableSounds) PlaySound(InpSoundBE);
}

//+------------------------------------------------------------------+
//| Order Execution Logic                                            |
//+------------------------------------------------------------------+
void ExecuteOrder() {
   double p = (uiState.orderType == UI_LIMIT) ? uiState.customPrice : (uiState.side == UI_BUY ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID));
   double sl = 0;
   if(uiState.slPoints > 0)
      sl = (uiState.side == UI_BUY) ? p - uiState.slPoints*_Point : p + uiState.slPoints*_Point;
   double tp = (uiState.side == UI_BUY) ? p + uiState.tpPoints*_Point : p - uiState.tpPoints*_Point;
   bool res = false;
   
   if(!uiState.splitOrders) {
      if(uiState.orderType == UI_MARKET) {
         if(uiState.side == UI_BUY) res = trade.Buy(uiState.lotSize, _Symbol, p, sl, tp, "TM_Pro");
         else res = trade.Sell(uiState.lotSize, _Symbol, p, sl, tp, "TM_Pro");
      } else {
         if(uiState.side == UI_BUY) res = trade.BuyLimit(uiState.lotSize, p, _Symbol, sl, tp);
         else res = trade.SellLimit(uiState.lotSize, p, _Symbol, sl, tp);
      }
   }
   else {
      double remainingLot = uiState.lotSize;
      double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double distStep = MathAbs(tp - p) / (uiState.partialsCount + 1);
      int totalOrders = uiState.partialsCount + 1;
      
      for(int i=1; i<=totalOrders; i++) {
         double orderLot = 0;
         double orderTP = 0;
         int ordersLeftAfterThis = totalOrders - i;
         double requiredReservation = ordersLeftAfterThis * minLot;
         
         if(i <= uiState.partialsCount) {
             double pct = (i==1) ? InpMainPartialVol : InpRollingPartialVol;
             double ideal = uiState.lotSize * (pct / 100.0);
             ideal = MathFloor(ideal / volStep) * volStep; 
             double maxAllowable = remainingLot - requiredReservation;
             orderLot = MathMin(ideal, maxAllowable);
             orderLot = MathMax(orderLot, minLot);
             orderLot = NormalizeDouble(orderLot, 2);
             remainingLot -= orderLot;
         } else {
             orderLot = NormalizeDouble(remainingLot, 2);
         }
         
         if(orderLot < minLot) continue; 
         
         string comment = "";
         if(i <= uiState.partialsCount) {
            orderTP = (uiState.side == UI_BUY) ? p + (distStep * i) : p - (distStep * i);
            comment = "TM_Pro_Ord"+IntegerToString(i);
         } else {
            // RUNNER LOGIC: use full TP
            orderTP = tp;
            comment = "TM_Pro_Runner";
         }
         
         if(uiState.orderType == UI_MARKET) {
            if(uiState.side == UI_BUY) res = trade.Buy(orderLot, _Symbol, p, sl, orderTP, comment);
            else res = trade.Sell(orderLot, _Symbol, p, sl, orderTP, comment);
         } else {
            if(uiState.side == UI_BUY) res = trade.BuyLimit(orderLot, p, _Symbol, sl, orderTP, ORDER_TIME_GTC, 0, comment);
            else res = trade.SellLimit(orderLot, p, _Symbol, sl, orderTP, ORDER_TIME_GTC, 0, comment);
         }
      }
   }
   if(res) { if(InpEnableSounds) PlaySound(InpSoundEntry); if(uiState.isVisualizing) ToggleVisualization(); }
}

void ExecuteScenarioOrders()
{
   if(uiState.scenarioMode == SCENARIO_OFF) return;
   double top = uiState.boxHigh; double bot = uiState.boxLow; double pt = _Point;
   double lot = uiState.lotSize; 
   bool r1=false, r2=false;
   
   double off      = uiState.scenarioOffset * pt;
   int    spread   = GetCurrentSpread();
   double spreadPt = spread * pt;
   // For BREAKOUT: add spread to BUY entry (price you actually get filled at ask)
   // For RANGE:    add spread to BUY entry (limit fill uses ask for buys)
   if(!uiState.splitOrders) {
      if(uiState.scenarioMode == SCENARIO_BREAKOUT) {
         double bEntry = top + off + spreadPt; // BUY: add spread so stop triggers at ask
         double sEntry = bot - off;            // SELL: bid-based, no spread needed
         double bSL = (uiState.slPoints > 0) ? bEntry - uiState.slPoints*pt : 0;
         double sSL = (uiState.slPoints > 0) ? sEntry + uiState.slPoints*pt : 0;
         r1 = trade.BuyStop(lot, bEntry, _Symbol, bSL, bEntry+uiState.tpPoints*pt, ORDER_TIME_GTC, 0, "TM_Pro_Scen");
         r2 = trade.SellStop(lot, sEntry, _Symbol, sSL, sEntry-uiState.tpPoints*pt, ORDER_TIME_GTC, 0, "TM_Pro_Scen");
      }
      else if(uiState.scenarioMode == SCENARIO_RANGE) {
         double sEntry = top - off;            // SELL LIMIT: bid-based
         double bEntry = bot + off + spreadPt; // BUY LIMIT: add spread (ask fill)
         double sSL = (uiState.slPoints > 0) ? sEntry + uiState.slPoints*pt : 0;
         double bSL = (uiState.slPoints > 0) ? bEntry - uiState.slPoints*pt : 0;
         r1 = trade.SellLimit(lot, sEntry, _Symbol, sSL, sEntry-uiState.tpPoints*pt, ORDER_TIME_GTC, 0, "TM_Pro_Scen");
         r2 = trade.BuyLimit(lot, bEntry, _Symbol, bSL, bEntry+uiState.tpPoints*pt, ORDER_TIME_GTC, 0, "TM_Pro_Scen");
      }
   } else {
      double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double distStep = (uiState.tpPoints * pt) / (uiState.partialsCount + 1);
      double remLot = lot;
      int totalOrders = uiState.partialsCount + 1;
      
      for(int i=1; i<=totalOrders; i++) {
         double oLot = 0; 
         int ordersLeft = totalOrders - i;
         double resv = ordersLeft * minLot;
         
         if(i <= uiState.partialsCount) {
             double pct = (i==1) ? InpMainPartialVol : InpRollingPartialVol;
             double ideal = lot * (pct/100.0);
             ideal = MathFloor(ideal / volStep) * volStep;
             double maxA = remLot - resv;
             oLot = MathMin(ideal, maxA);
             oLot = MathMax(oLot, minLot);
             oLot = NormalizeDouble(oLot, 2);
             remLot -= oLot;
         } else oLot = NormalizeDouble(remLot, 2);
         
         if(oLot < minLot) continue;
         
         double dist = (i <= uiState.partialsCount) ? (distStep * i) : (uiState.tpPoints * pt);
         string comment = "";
         double tpOffset = 0;
         
         if(i == totalOrders) {
             comment = "TM_Pro_Runner";
             // tpOffset stays 0 (Rolling TP removed)
         } else {
             comment = "TM_S_"+IntegerToString(i);
         }
         
         double finalDist = dist + tpOffset;
         
         if(uiState.scenarioMode == SCENARIO_BREAKOUT) {
            double bE    = top + off + spreadPt; // BUY STOP: spread-adjusted ask
            double sE    = bot - off;             // SELL STOP: bid-based
            double bSL_s = (uiState.slPoints > 0) ? bE - uiState.slPoints*pt : 0;
            double sSL_s = (uiState.slPoints > 0) ? sE + uiState.slPoints*pt : 0;
            trade.BuyStop(oLot, bE, _Symbol, bSL_s, bE+finalDist, ORDER_TIME_GTC, 0, comment);
            trade.SellStop(oLot, sE, _Symbol, sSL_s, sE-finalDist, ORDER_TIME_GTC, 0, comment);
         } else {
            double sE    = top - off;             // SELL LIMIT: bid-based
            double bE    = bot + off + spreadPt;  // BUY LIMIT: spread-adjusted ask
            double sSL_s = (uiState.slPoints > 0) ? sE + uiState.slPoints*pt : 0;
            double bSL_s = (uiState.slPoints > 0) ? bE - uiState.slPoints*pt : 0;
            trade.SellLimit(oLot, sE, _Symbol, sSL_s, sE-finalDist, ORDER_TIME_GTC, 0, comment);
            trade.BuyLimit(oLot, bE, _Symbol, bSL_s, bE+finalDist, ORDER_TIME_GTC, 0, comment);
         }
         r1 = true; 
      }
   }
   
   if(r1 || r2) {
      if(InpEnableSounds) PlaySound(InpSoundEntry);
      uiState.scenarioMode = SCENARIO_OFF; ObjectsDeleteAll(0, PREFIX + "Scen_"); UpdatePanelUI();
   }
}

//+------------------------------------------------------------------+
//| NEW: Trailing Stop Logic                                         |
//+------------------------------------------------------------------+
void ManageTrailingStop() {
   if(!InpUseTrailing) return;

   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol() == _Symbol && posInfo.Magic() == 123456) {
         double currentPrice = (posInfo.PositionType() == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double entry = posInfo.PriceOpen();
         double sl = posInfo.StopLoss();
         double pt = _Point;
         
         // 1. Check Activation Conditions
         bool active = false;
         
         // Condition A: Points Distance (e.g., 300 points)
         double distFromEntry = MathAbs(currentPrice - entry);
         if(distFromEntry >= InpTrailStartPoints * pt) active = true;
         
         // Condition B: Partials Taken (e.g., after 3rd Partial)
         if(!active && InpTrailStartPartial > 0) {
             if(IsPartialTaken(posInfo.Identifier(), InpTrailStartPartial)) active = true;
         }
         
         if(!active) continue;
         
         // 2. Calculate New SL
         double newSL = 0.0;
         double trailDist = InpTrailDistance * pt;
         double trailStep = InpTrailStep * pt;
         
         if(posInfo.PositionType() == POSITION_TYPE_BUY) {
             double potentialSL = currentPrice - trailDist;
             
             // Check if price moved enough (Step logic)
             // We only update if potentialSL is greater than current SL + Step
             if(potentialSL > sl + trailStep) {
                 trade.PositionModify(posInfo.Ticket(), potentialSL, posInfo.TakeProfit());
             }
         }
         else { // SELL
             double potentialSL = currentPrice + trailDist;
             
             // We only update if potentialSL is lower than current SL - Step
             // Or if SL is 0 (no SL set yet)
             if(potentialSL < sl - trailStep || sl == 0) {
                 trade.PositionModify(posInfo.Ticket(), potentialSL, posInfo.TakeProfit());
             }
         }
      }
   }
}

// ... UI and Helper Functions ...
void SaveUIState() {
   string id = IntegerToString(ChartID());
   GlobalVariableSet("TMP_"+id+"_Type", (double)uiState.orderType);
   GlobalVariableSet("TMP_"+id+"_Side", (double)uiState.side);
   GlobalVariableSet("TMP_"+id+"_Lot", uiState.lotSize);
   GlobalVariableSet("TMP_"+id+"_SL", (double)uiState.slPoints);
   GlobalVariableSet("TMP_"+id+"_TP", (double)uiState.tpPoints);
   GlobalVariableSet("TMP_"+id+"_Parts", (double)uiState.partialsCount);
   GlobalVariableSet("TMP_"+id+"_Split", (double)uiState.splitOrders);
   GlobalVariableSet("TMP_"+id+"_ScenOff", (double)uiState.scenarioOffset);
}
void LoadUIState() {
   string id = IntegerToString(ChartID());
   if(GlobalVariableCheck("TMP_"+id+"_Type")) {
      uiState.orderType = (ENUM_ORDER_TYPE_UI)GlobalVariableGet("TMP_"+id+"_Type");
      uiState.side      = (ENUM_SIDE_UI)GlobalVariableGet("TMP_"+id+"_Side");
      uiState.lotSize   = GlobalVariableGet("TMP_"+id+"_Lot");
      uiState.slPoints  = (int)GlobalVariableGet("TMP_"+id+"_SL");
      uiState.tpPoints  = (int)GlobalVariableGet("TMP_"+id+"_TP");
      uiState.partialsCount = (int)GlobalVariableGet("TMP_"+id+"_Parts");
      if(GlobalVariableCheck("TMP_"+id+"_Split")) uiState.splitOrders = (bool)GlobalVariableGet("TMP_"+id+"_Split");
      if(GlobalVariableCheck("TMP_"+id+"_ScenOff")) uiState.scenarioOffset = (int)GlobalVariableGet("TMP_"+id+"_ScenOff");
   }
}
void ClearSavedState() {
   string id = IntegerToString(ChartID());
   GlobalVariableDel("TMP_"+id+"_Type"); GlobalVariableDel("TMP_"+id+"_Side");
   GlobalVariableDel("TMP_"+id+"_Lot"); GlobalVariableDel("TMP_"+id+"_SL");
   GlobalVariableDel("TMP_"+id+"_TP"); GlobalVariableDel("TMP_"+id+"_Parts");
   GlobalVariableDel("TMP_"+id+"_Split");
   GlobalVariableDel("TMP_"+id+"_ScenOff");
}
void UpdatePanelPosition(bool force = false)
{
   int screenW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int screenH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   int baseX = 10, baseY = 50;
   
   if(InpPanelCorner == CORNER_RIGHT_UPPER) baseX = screenW - PANEL_W - 10;
   else if(InpPanelCorner == CORNER_LEFT_LOWER) baseY = screenH - PANEL_H - 30;
   else if(InpPanelCorner == CORNER_RIGHT_LOWER) { baseX = screenW - PANEL_W - 10; baseY = screenH - PANEL_H - 30; }
   
   CreatePanelElements(baseX, baseY);
   if(force) UpdatePanelUI();
}
void CreatePanelElements(int x, int y)
{
   CreateRect("BG", x, y, PANEL_W, PANEL_H, COLOR_BG, BORDER_FLAT);
   y += PAD;
   CreateBtn("Btn_Mkt", x+5, y, 110, ROW_H, "MARKET", (uiState.orderType==UI_MARKET));
   CreateBtn("Btn_Lim", x+115, y, 110, ROW_H, "LIMIT", (uiState.orderType==UI_LIMIT));
   y += ROW_H + PAD;
   CreateLabel("Lbl_Prc", x+5, y+5, "Price:");
   CreateEdit("Edit_Price", x+50, y, 175, ROW_H, "0.00000");
   y += ROW_H + PAD;
   CreateBtn("Btn_Buy", x+5, y, 110, ROW_H, "BUY", (uiState.side==UI_BUY), COLOR_BUY);
   CreateBtn("Btn_Sell", x+115, y, 110, ROW_H, "SELL", (uiState.side==UI_SELL), COLOR_SELL);
   y += ROW_H + PAD;
   CreateLabel("Lbl_Lot", x+5, y+5, "Lot Size:");
   CreateEdit("Edit_Lot", x+115, y, 110, ROW_H, DoubleToString(uiState.lotSize, 2));
   y += ROW_H + PAD;
   CreateLabel("Lbl_SL", x+5, y+5, "SL:");
   CreateEdit("Edit_SL", x+35, y, 65, ROW_H, IntegerToString(uiState.slPoints));
   CreateLabel("Lbl_SLP", x+105, y+5, "Prc:");
   CreateEdit("Edit_SL_Prc", x+135, y, 90, ROW_H, "0.00000"); 
   y += ROW_H + PAD;
   CreateLabel("Lbl_TP", x+5, y+5, "TP:");
   CreateEdit("Edit_TP", x+35, y, 65, ROW_H, IntegerToString(uiState.tpPoints));
   CreateLabel("Lbl_TPP", x+105, y+5, "Prc:");
   CreateEdit("Edit_TP_Prc", x+135, y, 90, ROW_H, "0.00000"); 
   y += ROW_H + PAD;
   CreateLabel("Lbl_Part", x+5, y+5, "Partials #:");
   CreateEdit("Edit_Part", x+115, y, 110, ROW_H, IntegerToString(uiState.partialsCount));
   y += ROW_H + PAD + 5;
   CreateRect("Sep3", x+5, y, PANEL_W-10, 1, C'80,80,80', BORDER_FLAT);
   y += 5;
   UpdatePartialTPList(x, y);
   y += (uiState.partialsCount > 0 ? (uiState.partialsCount * 18) : 5);
   CreateRect("Sep1", x+5, y, PANEL_W-10, 1, C'60,60,60', BORDER_FLAT); 
   y += 5;
   CreateLabel("Lbl_Risk", x+5, y+5, "Risk:");
   CreateLabel("Val_Risk", x+50, y+5, "$0.00");
   ObjectSetInteger(0, PREFIX+"Val_Risk", OBJPROP_COLOR, clrCrimson);
   CreateLabel("Lbl_Rew", x+105, y+5, "Est. Profit:");
   CreateLabel("Val_Rew", x+160, y+5, "$0.00");
   ObjectSetInteger(0, PREFIX+"Val_Rew", OBJPROP_COLOR, clrLimeGreen);
   y += 20;
   CreateRect("Sep2", x+5, y, PANEL_W-10, 1, C'60,60,60', BORDER_FLAT);
   y += 5;
   CreateBtn("Btn_Mode", x+5, y, 220, ROW_H, "MODE: PARTIALS", true, C'50,50,50');
   y += ROW_H + PAD;
   CreateBtn("Btn_Vis", x+5, y, 110, ROW_H, "VISUALIZE", false, C'100,100,100');
   CreateBtn("Btn_Scen", x+115, y, 110, ROW_H, "SCENARIO", (uiState.scenarioMode!=SCENARIO_OFF), C'140,80,0');
   y += ROW_H + PAD;
   CreateLabel("Lbl_ScenOff", x+5, y+5, "Scen Offset:");
   CreateEdit("Edit_ScenOff", x+115, y, 110, ROW_H, IntegerToString(uiState.scenarioOffset > 0 ? uiState.scenarioOffset : InpScenarioOffset));
   y += ROW_H + PAD;
   CreateBtn("Btn_Exec", x+5, y, 220, ROW_H, "PLACE", false, C'0,120,0');
   y += ROW_H + PAD + 5;
   CreateEdit("Edit_ManPart", x+5, y, 50, ROW_H, "50");
   CreateBtn("Btn_Part", x+60, y, 165, ROW_H, "TAKE PARTIAL %", false, C'80,80,0');
   y += ROW_H + PAD;
   CreateBtn("Btn_BE_E", x+5, y, 110, ROW_H, "BE (Entry)", false, C'0,80,80');
   CreateBtn("Btn_BE_A", x+115, y, 110, ROW_H, "BE (Real)", false, C'0,80,120');
   y += ROW_H + PAD + 5;
   CreateBtn("Btn_CloseAll", x+5, y, 220, ROW_H, "CLOSE ALL POSITIONS", false, clrRed);
}
void UpdatePanelUI()
{
   ObjectSetInteger(0, PREFIX+"Btn_Mkt", OBJPROP_BGCOLOR, (uiState.orderType==UI_MARKET ? COLOR_BTN_ACT : COLOR_BTN));
   ObjectSetInteger(0, PREFIX+"Btn_Lim", OBJPROP_BGCOLOR, (uiState.orderType==UI_LIMIT ? COLOR_BTN_ACT : COLOR_BTN));
   ObjectSetInteger(0, PREFIX+"Btn_Buy", OBJPROP_BGCOLOR, (uiState.side==UI_BUY ? COLOR_BUY : COLOR_BTN));
   ObjectSetInteger(0, PREFIX+"Btn_Sell", OBJPROP_BGCOLOR, (uiState.side==UI_SELL ? COLOR_SELL : COLOR_BTN));
   ObjectSetInteger(0, PREFIX+"Btn_Buy", OBJPROP_COLOR, (uiState.side==UI_BUY ? COLOR_TEXT : clrGray));
   ObjectSetInteger(0, PREFIX+"Btn_Sell", OBJPROP_COLOR, (uiState.side==UI_SELL ? COLOR_TEXT : clrGray));
   string modeTxt = uiState.splitOrders ? "MODE: ORDERS (Split)" : "MODE: PARTIALS (Managed)";
   color modeCol  = uiState.splitOrders ? C'0,100,180' : C'180,100,0'; 
   ObjectSetString(0, PREFIX+"Btn_Mode", OBJPROP_TEXT, modeTxt);
   ObjectSetInteger(0, PREFIX+"Btn_Mode", OBJPROP_BGCOLOR, modeCol);
   color scenCol = COLOR_BTN;
   string scenTxt = "SCENARIO";
   if(uiState.scenarioMode == SCENARIO_BREAKOUT) { scenCol = clrOrangeRed; scenTxt = "BREAKOUT"; }
   else if(uiState.scenarioMode == SCENARIO_RANGE) { scenCol = clrDodgerBlue; scenTxt = "RANGE"; }
   ObjectSetInteger(0, PREFIX+"Btn_Scen", OBJPROP_BGCOLOR, scenCol);
   ObjectSetString(0, PREFIX+"Btn_Scen", OBJPROP_TEXT, scenTxt);
   ChartRedraw();
}
void CloseAllPositions() {
   bool closedAny = false;
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(posInfo.SelectByIndex(i)) {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == 123456) {
            trade.PositionClose(posInfo.Ticket());
            closedAny = true;
         }
      }
   }
   for(int i=OrdersTotal()-1; i>=0; i--) {
      ulong ticket = OrderGetTicket(i);
      if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == 123456) {
         trade.OrderDelete(ticket);
         closedAny = true;
      }
   }
   if(closedAny && InpEnableSounds) PlaySound(InpSoundClose);
}
void UpdateSLTPPrices(double entryPrice) {
   double point = _Point;
   if(uiState.side == UI_BUY) {
      uiState.slPrice = (uiState.slPoints > 0) ? entryPrice - (uiState.slPoints * point) : 0;
      uiState.tpPrice = entryPrice + (uiState.tpPoints * point);
   } else {
      uiState.slPrice = (uiState.slPoints > 0) ? entryPrice + (uiState.slPoints * point) : 0;
      uiState.tpPrice = entryPrice - (uiState.tpPoints * point);
   }
   string slPrcTxt = (uiState.slPoints > 0) ? DoubleToString(uiState.slPrice, _Digits) : "NONE";
   if(ObjectFind(0, PREFIX+"Edit_SL_Prc") >= 0) ObjectSetString(0, PREFIX+"Edit_SL_Prc", OBJPROP_TEXT, slPrcTxt);
   if(ObjectFind(0, PREFIX+"Edit_TP_Prc") >= 0) ObjectSetString(0, PREFIX+"Edit_TP_Prc", OBJPROP_TEXT, DoubleToString(uiState.tpPrice, _Digits));
}
void CleanupOrphanedLines() {
   for(int i=ObjectsTotal(0, -1, -1)-1; i>=0; i--) {
      string n = ObjectName(0, i);
      if(StringFind(n, PREFIX + "Live_P_") == 0) {
         string pts[]; if(StringSplit(n, '_', pts) >= 4) {
            ulong t = (ulong)StringToInteger(pts[3]);
            if(!PositionSelectByTicket(t)) ObjectDelete(0, n);
         }
      }
   }
}
bool IsPartialTaken(long posID, int partialIndex) {
   if(!HistorySelectByPosition(posID)) return false;
   int partialsFound = 0;
   int totalDeals = HistoryDealsTotal();
   for(int i=0; i<totalDeals; i++) {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT) partialsFound++;
   }
   return (partialsFound >= partialIndex);
}
void ManualPartial() {
   if(!posInfo.Select(Symbol())) return;
   double amt = NormalizeDouble(posInfo.Volume() * (StringToDouble(ObjectGetString(0, PREFIX+"Edit_ManPart", OBJPROP_TEXT)) / 100.0), 2);
   if(trade.PositionClosePartial(posInfo.Ticket(), amt)) if(InpEnableSounds) PlaySound(InpSoundPartial);
}
void UpdatePartialTPList(int x, int y) {
   ObjectsDeleteAll(0, PREFIX+"PTL_");
   if(uiState.partialsCount <= 0 || uiState.tpPoints <= 0) return;
   double step = (double)uiState.tpPoints / (uiState.partialsCount + 1);
   for(int i=1; i<=uiState.partialsCount; i++) {
      int pts = (int)MathRound(step * i);
      string txt = "TP" + IntegerToString(i) + " Target: " + IntegerToString(pts) + " pts";
      CreateLabel("PTL_"+IntegerToString(i), x+10, y, txt);
      ObjectSetInteger(0, PREFIX+"PTL_"+IntegerToString(i), OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, PREFIX+"PTL_"+IntegerToString(i), OBJPROP_COLOR, C'140,140,140');
      y += 18;
   }
}
void CreateBtn(string n, int x, int y, int w, int h, string t, bool a, color b=COLOR_BTN) {
   string obj = PREFIX + n; if(ObjectFind(0, obj) < 0) ObjectCreate(0, obj, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, w); ObjectSetInteger(0, obj, OBJPROP_YSIZE, h);
   ObjectSetString(0, obj, OBJPROP_TEXT, t); ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, a ? COLOR_BTN_ACT : b);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, COLOR_TEXT); ObjectSetInteger(0, obj, OBJPROP_BORDER_COLOR, a ? COLOR_BTN_ACT : b);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_ZORDER, 10); 
}
void CreateRect(string n, int x, int y, int w, int h, color bg, ENUM_BORDER_TYPE brd) {
   string obj = PREFIX + n; if(ObjectFind(0, obj) < 0) ObjectCreate(0, obj, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, w); ObjectSetInteger(0, obj, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, bg); ObjectSetInteger(0, obj, OBJPROP_BORDER_TYPE, brd);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_ZORDER, 10); 
}
void CreateEdit(string n, int x, int y, int w, int h, string t) {
   string obj = PREFIX + n; if(ObjectFind(0, obj) < 0) ObjectCreate(0, obj, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, w); ObjectSetInteger(0, obj, OBJPROP_YSIZE, h);
   ObjectSetString(0, obj, OBJPROP_TEXT, t); ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, COLOR_EDIT_BG);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, COLOR_TEXT); ObjectSetInteger(0, obj, OBJPROP_ALIGN, ALIGN_CENTER);
   ObjectSetInteger(0, obj, OBJPROP_BORDER_TYPE, BORDER_FLAT); ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_ZORDER, 10); 
}
void CreateLabel(string n, int x, int y, string t) {
   string obj = PREFIX + n; if(ObjectFind(0, obj) < 0) ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, obj, OBJPROP_TEXT, t); ObjectSetInteger(0, obj, OBJPROP_COLOR, COLOR_LABEL);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_ZORDER, 10); 
}
void ToggleVisualization() {
   uiState.isVisualizing = !uiState.isVisualizing;
   if(!uiState.isVisualizing) ObjectsDeleteAll(0, PREFIX + "Vis_");
   else {
      double p = (uiState.orderType == UI_LIMIT) ? uiState.customPrice : (uiState.side == UI_BUY ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID));
      DrawVisualization(p);
   }
}
void DrawVisualization(double entryPrice) {
   ObjectsDeleteAll(0, PREFIX + "Vis_");
   double point = _Point;
   double slP = (uiState.side == UI_BUY) ? entryPrice - uiState.slPoints * point : entryPrice + uiState.slPoints * point;
   double tpP = (uiState.side == UI_BUY) ? entryPrice + uiState.tpPoints * point : entryPrice - uiState.tpPoints * point;
   CreateLine("Vis_Entry", entryPrice, clrGray, STYLE_SOLID, 2, "ENTRY");
   if(uiState.slPoints > 0) CreateLine("Vis_SL", slP, clrRed, STYLE_SOLID, 1, "SL");
   CreateLine("Vis_TP", tpP, clrGreen, STYLE_SOLID, 1, "FULL TP");
   double dist = MathAbs(tpP - entryPrice);
   double step = dist / (uiState.partialsCount + 1);
   for(int i=1; i<=uiState.partialsCount; i++) {
      double pLevel = (uiState.side == UI_BUY) ? entryPrice + (step * i) : entryPrice - (step * i);
      int displayPts = (int)MathRound(step * i / _Point);
      CreateLine("Vis_P" + IntegerToString(i), pLevel, clrGold, STYLE_DOT, 1, "TP"+IntegerToString(i)+": "+IntegerToString(displayPts)+" pts");
   }
   ChartRedraw();
}
void ToggleScenario() {
   if(uiState.isVisualizing) ToggleVisualization();
   if(uiState.scenarioMode == SCENARIO_OFF) {
      string selObj = "";
      for(int i=ObjectsTotal(0, -1, -1)-1; i>=0; i--) {
         string name = ObjectName(0, i);
         if(ObjectGetInteger(0, name, OBJPROP_TYPE) == OBJ_RECTANGLE && ObjectGetInteger(0, name, OBJPROP_SELECTED)) {
            selObj = name; break;
         }
      }
      if(selObj == "") { Alert("Please select a drawn Rectangle (Box) on the chart first."); return; }
      uiState.boxObjName = selObj; uiState.scenarioMode = SCENARIO_BREAKOUT;
      double p1 = ObjectGetDouble(0, selObj, OBJPROP_PRICE, 0); double p2 = ObjectGetDouble(0, selObj, OBJPROP_PRICE, 1);
      uiState.boxHigh = MathMax(p1, p2); uiState.boxLow  = MathMin(p1, p2); DrawScenario();
   }
   else if(uiState.scenarioMode == SCENARIO_BREAKOUT) { uiState.scenarioMode = SCENARIO_RANGE; DrawScenario(); }
   else { uiState.scenarioMode = SCENARIO_OFF; ObjectsDeleteAll(0, PREFIX + "Scen_"); }
   UpdatePanelUI();
}
void DrawScenario() {
   ObjectsDeleteAll(0, PREFIX + "Scen_");
   if(ObjectFind(0, uiState.boxObjName) >= 0) {
      double p1 = ObjectGetDouble(0, uiState.boxObjName, OBJPROP_PRICE, 0);
      double p2 = ObjectGetDouble(0, uiState.boxObjName, OBJPROP_PRICE, 1);
      uiState.boxHigh = MathMax(p1, p2);
      uiState.boxLow  = MathMin(p1, p2);
   } else if(uiState.scenarioMode != SCENARIO_OFF) {
      uiState.scenarioMode = SCENARIO_OFF; UpdatePanelUI(); return;
   }

   double top = uiState.boxHigh;
   double bot = uiState.boxLow;
   double pt  = _Point;
   double off      = uiState.scenarioOffset * pt;
   int    spread   = GetCurrentSpread();
   double spreadPt = spread * pt;

   // Helper lambda-style: draw partial TP lines for a given entry and direction
   // BUY direction: dir=+1, SELL direction: dir=-1
   double tpDist = uiState.tpPoints * pt;
   double stepDist = (uiState.partialsCount > 0) ? tpDist / (uiState.partialsCount + 1) : tpDist;

   if(uiState.scenarioMode == SCENARIO_BREAKOUT) {
      // BUY STOP: entry = top + offset
      double bEntry = top + off + spreadPt;   // offset + spread (ask adjustment)
      double bSL    = top - uiState.slPoints * pt;
      string bLabel = "BUY STOP @ " + DoubleToString(bEntry, _Digits) +
                      " [off=" + IntegerToString(uiState.scenarioOffset) +
                      " sprd=" + IntegerToString(spread) + " pts]";
      CreateLine("Scen_B_Ent", bEntry, clrLime, STYLE_SOLID, 2, bLabel);
      if(uiState.slPoints > 0) CreateLine("Scen_B_SL", bSL, clrRed, STYLE_DOT, 1, "B-SL");
      for(int i=1; i<=uiState.partialsCount; i++) {
         double lvl = bEntry + stepDist * i;
         CreateLine("Scen_B_TP"+IntegerToString(i), lvl, clrGold, STYLE_DOT, 1,
                    "B-TP"+IntegerToString(i)+": "+(string)(int)MathRound(stepDist*i/pt)+" pts");
      }
      CreateLine("Scen_B_TP", bEntry + tpDist, clrGreen, STYLE_DOT, 1,
                 "B-TP FULL: " + (string)uiState.tpPoints + " pts");

      // SELL STOP: entry = bot - offset
      double sEntry = bot - off;   // SELL STOP: no spread added (fills at bid)
      double sSL    = bot + uiState.slPoints * pt;
      string sLabel = "SELL STOP @ " + DoubleToString(sEntry, _Digits) +
                      " [off=" + IntegerToString(uiState.scenarioOffset) +
                      " sprd=" + IntegerToString(spread) + " pts]";
      CreateLine("Scen_S_Ent", sEntry, clrRed, STYLE_SOLID, 2, sLabel);
      if(uiState.slPoints > 0) CreateLine("Scen_S_SL", sSL, clrRed, STYLE_DOT, 1, "S-SL");
      for(int i=1; i<=uiState.partialsCount; i++) {
         double lvl = sEntry - stepDist * i;
         CreateLine("Scen_S_TP"+IntegerToString(i), lvl, clrGold, STYLE_DOT, 1,
                    "S-TP"+IntegerToString(i)+": "+(string)(int)MathRound(stepDist*i/pt)+" pts");
      }
      CreateLine("Scen_S_TP", sEntry - tpDist, clrGreen, STYLE_DOT, 1,
                 "S-TP FULL: " + (string)uiState.tpPoints + " pts");
   }
   else if(uiState.scenarioMode == SCENARIO_RANGE) {
      // SELL LIMIT: entry = top - offset (SELL fills at bid, no spread added)
      double sEntry = top - off;
      double sSL    = top + uiState.slPoints * pt;
      string sLbl   = "SELL LIMIT @ " + DoubleToString(sEntry, _Digits) +
                      " [off=" + IntegerToString(uiState.scenarioOffset) +
                      " sprd=" + IntegerToString(spread) + " pts]";
      CreateLine("Scen_S_Ent", sEntry, clrRed, STYLE_SOLID, 2, sLbl);
      if(uiState.slPoints > 0) CreateLine("Scen_S_SL", sSL, clrRed, STYLE_DOT, 1, "S-SL");
      for(int i=1; i<=uiState.partialsCount; i++) {
         double lvl = sEntry - stepDist * i;
         CreateLine("Scen_S_TP"+IntegerToString(i), lvl, clrGold, STYLE_DOT, 1,
                    "S-TP"+IntegerToString(i)+": "+(string)(int)MathRound(stepDist*i/pt)+" pts");
      }
      CreateLine("Scen_S_TP", sEntry - tpDist, clrGreen, STYLE_DOT, 1,
                 "S-TP FULL: " + (string)uiState.tpPoints + " pts");

      // BUY LIMIT: entry = bot + offset + spread (ask adjustment for buys)
      double bEntry = bot + off + spreadPt;
      double bSL    = bot - uiState.slPoints * pt;
      string bLbl   = "BUY LIMIT @ " + DoubleToString(bEntry, _Digits) +
                      " [off=" + IntegerToString(uiState.scenarioOffset) +
                      " sprd=" + IntegerToString(spread) + " pts]";
      CreateLine("Scen_B_Ent", bEntry, clrLime, STYLE_SOLID, 2, bLbl);
      if(uiState.slPoints > 0) CreateLine("Scen_B_SL", bSL, clrRed, STYLE_DOT, 1, "B-SL");
      for(int i=1; i<=uiState.partialsCount; i++) {
         double lvl = bEntry + stepDist * i;
         CreateLine("Scen_B_TP"+IntegerToString(i), lvl, clrGold, STYLE_DOT, 1,
                    "B-TP"+IntegerToString(i)+": "+(string)(int)MathRound(stepDist*i/pt)+" pts");
      }
      CreateLine("Scen_B_TP", bEntry + tpDist, clrGreen, STYLE_DOT, 1,
                 "B-TP FULL: " + (string)uiState.tpPoints + " pts");
   }
   ChartRedraw();
}
void CreateLine(string suffix, double price, color col, ENUM_LINE_STYLE style, int width, string labelText="") {
   string name = PREFIX + suffix;
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   else ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col); ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width); ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   if(labelText != "") { ObjectSetString(0, name, OBJPROP_TEXT, labelText); ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8); }
}
void UpdateStats(double priceRef) {
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point    = _Point;
   if(tickVal == 0 || tickSize == 0 || point == 0) return;
   double pointsToMoneyFactor = (point / tickSize) * tickVal;
   double riskUSD = uiState.lotSize * uiState.slPoints * pointsToMoneyFactor;
   double totalRewardUSD = 0;
   double remainingLot = uiState.lotSize;
   double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   
   if(uiState.partialsCount > 0) {
      double stepPoints = (double)uiState.tpPoints / (uiState.partialsCount + 1);
      for(int i=1; i<=uiState.partialsCount; i++) {
         double pct = (i==1) ? InpMainPartialVol : InpRollingPartialVol;
         double rawPartLot = uiState.lotSize * (pct / 100.0);
         double partLot = MathFloor(rawPartLot / volStep) * volStep;
         if(partLot < minLot) partLot = 0;
         if(partLot > 0 && partLot <= remainingLot) {
            double distance = stepPoints * i;
            totalRewardUSD += (partLot * distance * pointsToMoneyFactor);
            remainingLot -= partLot;
         }
      }
   }
   remainingLot = NormalizeDouble(remainingLot, 2); 
   if(remainingLot > 0) totalRewardUSD += (remainingLot * uiState.tpPoints * pointsToMoneyFactor);
   if(ObjectFind(0, PREFIX+"Val_Risk") >= 0) ObjectSetString(0, PREFIX+"Val_Risk", OBJPROP_TEXT, "$" + DoubleToString(riskUSD, 2));
   if(ObjectFind(0, PREFIX+"Val_Rew") >= 0)  ObjectSetString(0, PREFIX+"Val_Rew", OBJPROP_TEXT, "$" + DoubleToString(totalRewardUSD, 2));
}