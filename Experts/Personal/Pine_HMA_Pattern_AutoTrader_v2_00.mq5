//+------------------------------------------------------------------+
//|                                       AutoTrader_HMA_Engulfing.mq5|
//|                                                      MQL5 Coder  |
//+------------------------------------------------------------------+
#property copyright "MQL5 Coder"
#property link      ""
#property version   "1.10"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

CTrade         trade;
CPositionInfo  pos;
CSymbolInfo    sym;

//--- Inputs ---
input group "=== Indicator Settings ==="
input int      InpHmaLength      = 34;       // HMA Period
input int      InpEmaLength      = 233;      // EMA Period

input group "=== Trade Settings ==="
input double   InpLotSize        = 0.10;     // Initial Lot Size
input int      InpStopLoss       = 500;      // Stop Loss (Points)
input int      InpTakeProfit     = 1000;     // Full Take Profit (Points)

input group "=== Partials & Trailing ==="
input int      InpNumPartials    = 3;        // Number of Partials
input double   InpPartialPercent = 10.0;     // % of Initial Lot per Partial
input int      InpTrailTrigger   = 1000;     // Points in profit to start trailing/extending
input int      InpTrailStep      = 600;      // Trailing Distance (Points)
input int      InpMaxTPExtensions= 3;        // Max times TP can be extended

input group "=== DD Entries (Grid) ==="
input int      InpDDStep         = 200;      // Distance for DD Entry (Points)
input int      InpMaxDDEntries   = 2;        // Max DD Entries Allowed
input bool     InpCloseWorstProf = true;     // Close worst entry in small profit

input group "=== Survival Mode ==="
input bool     InpSurvivalMode   = true;     // Close all at breakeven if max DD reached
input int      InpSurvivalProfit = 10;       // Breakeven profit (Points)

//--- Globals ---
int emaHandle;
int hmaHandle;
datetime lastBarTime = 0;

struct PositionState {
   ulong  ticket;
   int    partialsTaken;
   int    tpExtensions;
   bool   isTrailing;
};
PositionState states[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   sym.Name(_Symbol);
   sym.RefreshRates();
   
   emaHandle = iMA(_Symbol, _Period, InpEmaLength, 0, MODE_EMA, PRICE_CLOSE);
   hmaHandle = iCustom(_Symbol, _Period, "HMA", InpHmaLength, 0, PRICE_CLOSE); 
   
   if(emaHandle == INVALID_HANDLE || hmaHandle == INVALID_HANDLE) {
      Print("Error loading indicators. Please ensure HMA.ex5 exists in MQL5/Indicators.");
      return(INIT_FAILED);
   }

   ChartIndicatorAdd(0, 0, emaHandle);
   ChartIndicatorAdd(0, 0, hmaHandle);
   ApplyDarkTheme();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Helper Candlestick Functions (Matched to Pine)                   |
//+------------------------------------------------------------------+
bool isRed(int o, double &op[], double &cl[]) { return cl[o] < op[o]; }
bool isGreen(int o, double &op[], double &cl[]) { return cl[o] > op[o]; }

bool isBullishEngulfing(int o, double &op[], double &cl[], double &hi[]) {
   return (cl[o] - op[o]) > (op[o+1] - cl[o+1]) && op[o+1] > cl[o+1];
}

bool isBearishEngulfing(int o, double &op[], double &cl[], double &hi[]) {
   return (op[o] - cl[o]) > (cl[o+1] - op[o+1]) && op[o+1] < cl[o+1];
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!sym.RefreshRates()) return;

   // Trade Management Variables
   int buyCount = 0, sellCount = 0;
   double worstBuyPrice = 999999, worstSellPrice = 0;
   double totalBuyVolume = 0, totalSellVolume = 0;
   double avgBuyPrice = 0, avgSellPrice = 0;

   // Analyze Open Positions
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(pos.SelectByIndex(i) && pos.Symbol() == _Symbol) {
         ManageState(pos.Ticket());
         if(pos.PositionType() == POSITION_TYPE_BUY) {
            buyCount++;
            totalBuyVolume += pos.Volume();
            avgBuyPrice += (pos.PriceOpen() * pos.Volume());
            if(pos.PriceOpen() < worstBuyPrice) worstBuyPrice = pos.PriceOpen();
            ManageTradeMechanics(pos.Ticket(), POSITION_TYPE_BUY);
         }
         else if(pos.PositionType() == POSITION_TYPE_SELL) {
            sellCount++;
            totalSellVolume += pos.Volume();
            avgSellPrice += (pos.PriceOpen() * pos.Volume());
            if(pos.PriceOpen() > worstSellPrice) worstSellPrice = pos.PriceOpen();
            ManageTradeMechanics(pos.Ticket(), POSITION_TYPE_SELL);
         }
      }
   }
   if(buyCount > 0) avgBuyPrice /= totalBuyVolume;
   if(sellCount > 0) avgSellPrice /= totalSellVolume;

   //--- Survival Mode ---
   if(InpSurvivalMode) {
      if(buyCount > InpMaxDDEntries && sym.Bid() >= avgBuyPrice + (InpSurvivalProfit * sym.Point())) {
         CloseAllType(POSITION_TYPE_BUY);
         return;
      }
      if(sellCount > InpMaxDDEntries && sym.Ask() <= avgSellPrice - (InpSurvivalProfit * sym.Point())) {
         CloseAllType(POSITION_TYPE_SELL);
         return;
      }
   }

   //--- DD Entries ---
   if(buyCount > 0 && buyCount <= InpMaxDDEntries) {
      if(sym.Ask() <= worstBuyPrice - (InpDDStep * sym.Point())) {
         trade.Buy(InpLotSize, _Symbol, sym.Ask(), sym.Ask() - (InpStopLoss * sym.Point()), sym.Ask() + (InpTakeProfit * sym.Point()));
      }
   }
   if(sellCount > 0 && sellCount <= InpMaxDDEntries) {
      if(sym.Bid() >= worstSellPrice + (InpDDStep * sym.Point())) {
         trade.Sell(InpLotSize, _Symbol, sym.Bid(), sym.Bid() + (InpStopLoss * sym.Point()), sym.Bid() - (InpTakeProfit * sym.Point()));
      }
   }

   //--- Signal Logic (Executes Once Per Bar Close) ---
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime != lastBarTime) {
      
      double o[15], h[15], l[15], c[15], hma[15], ema[15];
      CopyOpen(_Symbol, _Period, 0, 15, o);
      CopyHigh(_Symbol, _Period, 0, 15, h);
      CopyLow(_Symbol, _Period, 0, 15, l);
      CopyClose(_Symbol, _Period, 0, 15, c);
      CopyBuffer(hmaHandle, 0, 0, 15, hma);
      CopyBuffer(emaHandle, 0, 0, 15, ema);
      
      // MQL5 arrays are copied oldest to newest by default. We need to reverse them as timeseries to match Pine's [0], [1] logic
      ArraySetAsSeries(o, true); ArraySetAsSeries(h, true); 
      ArraySetAsSeries(l, true); ArraySetAsSeries(c, true);
      ArraySetAsSeries(hma, true); ArraySetAsSeries(ema, true);

      // Index 1 is the recently closed bar (Pine's [0])
      // Index 2 is Pine's [1], Index 11 is Pine's [10]
      
      bool buyC2 = o[1]<hma[1] && c[1]>hma[1] && isBullishEngulfing(1,o,c,h) && isRed(2,o,c) && (hma[11]-hma[1])>3 && (c[1]-o[1])<3 && c[2]<hma[1] && h[2]<c[1] && h[3]<c[1];
      bool buyC3 = isRed(3,o,c) && isGreen(2,o,c) && isGreen(1,o,c) && o[1]<hma[1] && c[1]>hma[1] && (hma[11]-hma[1])>3 && (h[1]-c[1])>0.1;
      bool buyC4 = l[1]<hma[1] && c[1]>hma[1] && o[1]>hma[1] && h[1]>hma[1] && (hma[11]-hma[1])>3 && isBullishEngulfing(1,o,c,h) && (h[1]-c[1])>0.1;
      bool buyC5 = l[1]<hma[1] && c[1]>hma[1] && o[1]>hma[1] && h[1]>hma[1] && (hma[11]-hma[1])>3 && (h[1]-c[1])>0.1 && (hma[1]-c[5])>2;
      bool buyC6 = isRed(4,o,c) && isGreen(3,o,c) && isGreen(2,o,c) && isGreen(1,o,c) && o[1]<hma[1] && c[1]>hma[1] && (hma[1]-c[5])>2;
      bool buyC7 = isRed(3,o,c) && isGreen(2,o,c) && isGreen(1,o,c) && o[1]<hma[1] && c[1]>hma[1] && (hma[1]-c[3])>5;

      bool sellC2 = o[1]>hma[1] && c[1]<hma[1] && isBearishEngulfing(1,o,c,h) && isGreen(2,o,c) && (hma[11]-hma[1])<-3 && (o[1]-c[1])<3 && c[2]>hma[1] && l[2]<c[1] && l[3]<c[1];
      bool sellC3 = isGreen(3,o,c) && isRed(2,o,c) && isRed(1,o,c) && o[1]>hma[1] && c[1]<hma[1] && (hma[11]-hma[1])<-3 && (c[1]-l[1])>0.1;
      bool sellC4 = h[1]>hma[1] && c[1]<hma[1] && o[1]<hma[1] && l[1]<hma[1] && (hma[11]-hma[1])<-3 && isBearishEngulfing(1,o,c,h) && (c[1]-l[1])>0.1;
      bool sellC5 = h[1]>hma[1] && c[1]<hma[1] && o[1]<hma[1] && l[1]<hma[1] && (hma[11]-hma[1])<-3 && (c[1]-l[1])>0.1 && (c[5]-hma[1])>2;
      bool sellC6 = isGreen(3,o,c) && isGreen(2,o,c) && isRed(1,o,c) && o[3]>o[1] && isBearishEngulfing(1,o,c,h) && o[1]>hma[1] && c[1]<hma[1] && (hma[11]-hma[1])<-3;
      bool sellC7 = isRed(3,o,c) && isRed(2,o,c) && isGreen(1,o,c) && c[1]<hma[1] && h[1]>hma[1] && (hma[11]-hma[1])<-3;
      bool sellC8 = isRed(4,o,c) && isRed(3,o,c) && isGreen(2,o,c) && isRed(1,o,c) && h[3]>o[1] && isBearishEngulfing(1,o,c,h) && c[1]<hma[1] && h[1]>hma[1] && (hma[11]-hma[1])<-3;
      bool sellC9 = isRed(3,o,c) && isGreen(2,o,c) && isRed(1,o,c) && c[1]<hma[1] && h[1]>hma[1] && o[1]>hma[1] && h[1]>h[2] && (hma[11]-hma[1])<-3;

      bool buySignal = (buyC2 || buyC3 || buyC4 || buyC5 || buyC6 || buyC7);
      bool sellSignal = (sellC2 || sellC3 || sellC4 || sellC5 || sellC6 || sellC7 || sellC8 || sellC9);

      if(buyCount == 0 && sellCount == 0) {
         if(buySignal) {
            trade.Buy(InpLotSize, _Symbol, sym.Ask(), sym.Ask() - (InpStopLoss * sym.Point()), sym.Ask() + (InpTakeProfit * sym.Point()));
            lastBarTime = currentBarTime;
         }
         else if(sellSignal) {
            trade.Sell(InpLotSize, _Symbol, sym.Bid(), sym.Bid() + (InpStopLoss * sym.Point()), sym.Bid() - (InpTakeProfit * sym.Point()));
            lastBarTime = currentBarTime;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Management per position (Partials, Trailing, TP Extension)       |
//+------------------------------------------------------------------+
void ManageTradeMechanics(ulong ticket, ENUM_POSITION_TYPE type)
{
   if(!pos.SelectByTicket(ticket)) return;
   
   int sIdx = GetStateIndex(ticket);
   if(sIdx < 0) return;

   double openPrice = pos.PriceOpen();
   double currentPrice = (type == POSITION_TYPE_BUY) ? sym.Bid() : sym.Ask();
   double profitPoints = (type == POSITION_TYPE_BUY) ? (currentPrice - openPrice) / sym.Point() : (openPrice - currentPrice) / sym.Point();

   // 1. Trailing & TP Extension 
   if(profitPoints >= InpTrailTrigger) {
      states[sIdx].isTrailing = true;
      
      if(states[sIdx].tpExtensions < InpMaxTPExtensions) {
         double newTP = (type == POSITION_TYPE_BUY) ? pos.TakeProfit() + (InpTrailTrigger * sym.Point()) : pos.TakeProfit() - (InpTrailTrigger * sym.Point());
         trade.PositionModify(ticket, pos.StopLoss(), newTP);
         states[sIdx].tpExtensions++;
      }
      
      double newSL = (type == POSITION_TYPE_BUY) ? currentPrice - (InpTrailStep * sym.Point()) : currentPrice + (InpTrailStep * sym.Point());
      if(type == POSITION_TYPE_BUY && newSL > pos.StopLoss() + sym.Point()) trade.PositionModify(ticket, newSL, pos.TakeProfit());
      else if(type == POSITION_TYPE_SELL && (newSL < pos.StopLoss() - sym.Point() || pos.StopLoss() == 0)) trade.PositionModify(ticket, newSL, pos.TakeProfit());
   }

   // 2. Partials 
   if(!states[sIdx].isTrailing && states[sIdx].partialsTaken < InpNumPartials) {
      double partialDist = InpTakeProfit / (InpNumPartials + 1.0); 
      double nextTarget = (states[sIdx].partialsTaken + 1) * partialDist;
      
      if(profitPoints >= nextTarget) {
         double volToClose = NormalizeDouble(InpLotSize * (InpPartialPercent / 100.0), 2);
         if(volToClose >= sym.LotsMin() && pos.Volume() > volToClose) {
            trade.PositionClosePartial(ticket, volToClose);
            states[sIdx].partialsTaken++;
         }
      }
   }

   // 3. Close Worst Entry
   if(InpCloseWorstProf && profitPoints > InpSurvivalProfit) {
       int totalDir = 0;
       for(int i=0; i<PositionsTotal(); i++) {
          if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_TYPE) == type) totalDir++;
       }
       if(totalDir > 1) trade.PositionClose(ticket);
   }
}

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
void CloseAllType(ENUM_POSITION_TYPE type) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(pos.SelectByIndex(i) && pos.Symbol() == _Symbol && pos.PositionType() == type) {
         trade.PositionClose(pos.Ticket());
      }
   }
}

int GetStateIndex(ulong ticket) {
   for(int i=0; i<ArraySize(states); i++) {
      if(states[i].ticket == ticket) return i;
   }
   int size = ArraySize(states);
   ArrayResize(states, size + 1);
   states[size].ticket = ticket;
   states[size].partialsTaken = 0;
   states[size].tpExtensions = 0;
   states[size].isTrailing = false;
   return size;
}

void ManageState(ulong ticket) {
   GetStateIndex(ticket); 
}

void ApplyDarkTheme() {
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrBlack);
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, clrWhite);
   ChartSetInteger(0, CHART_COLOR_GRID, clrDarkSlateGray);
   ChartSetInteger(0, CHART_COLOR_CHART_UP, clrLime);
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN, clrRed);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, clrBlack);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, clrRed);
   ChartSetInteger(0, CHART_MODE, CHART_CANDLES);
}