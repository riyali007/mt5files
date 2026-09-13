//+------------------------------------------------------------------+
//|                                                       HMA_EA.mq5 |
//|   Auto-trading EA: HMA Breakout & Engulfing Signals              |
//|   - Breakout: Cross & Close above/below HMA (pure breakout)     |
//|   - Engulfing: Cross & Bullish/Bearish Engulfing pattern        |
//|   - 5 partial exits (20% each), breakeven after partial #1       |
//|   - Per-trade chart visuals cleaned up as partials/TP are hit    |
//|   - Basket closure on accumulated target profit                  |
//|   - Daily Target Profit & Daily Loss Limit + Trading Halt        |
//|   - Re-open trade if SL is hit before Breakeven                  |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>

//--- Signal Entry Mode Enum
enum ENUM_ENTRY_MODE
  {
   ENTRY_BREAKOUT_ONLY = 0,     // Pure HMA Breakout (Cross & Close across HMA)
   ENTRY_ENGULFING_ONLY = 1,    // HMA Cross + Engulfing Candle
   ENTRY_BOTH = 2               // Either Breakout OR Engulfing (First valid signal triggers)
  };

//--- Signal Inputs
input group "=== Signal & Entry Settings ==="
input ENUM_ENTRY_MODE InpEntryMode       = ENTRY_BREAKOUT_ONLY; // Entry Trigger Mode
input int             InpPeriod          = 14;                  // HMA Period
input ENUM_APPLIED_PRICE InpPrice        = PRICE_CLOSE;         // HMA Applied Price

//--- Trade Execution Settings
input group "=== Trade Settings ==="
input double InpLotSize         = 0.5;   // Fixed lot size
input int    InpSLPoints        = 700;   // Stop Loss, points
input int    InpTPPoints        = 1400;  // Final Take Profit, points
input int    InpPartials        = 5;     // Number of partial exits
input double InpPartialPercent  = 20.0;  // % of ORIGINAL volume closed per partial
input int    InpMagic           = 20260825;
input int    InpSlippage        = 20;    // points
input int    InpMaxOpenTrades   = 0;     // 0 = unlimited concurrent trades

//--- Retry Settings
input group "=== Retry Settings ==="
input int    InpMaxRetries      = 1;     // Max re-entries if SL hit before BE (0 = disable)

//--- Basket Profit Settings
input group "=== Basket Profit Settings ==="
input bool   InpEnableBasketTP     = true;   // Enable Accumulated Open Trades Close
input double InpBasketProfitTarget = 100.0;  // Target Accumulated Profit (Account Currency)

//--- Daily Limits Settings
input group "=== Daily Limits Settings ==="
input bool   InpEnableDailyLimits  = true;   // Enable Daily Profit / Loss Halt
input double InpDailyProfitTarget  = 500.0;  // Daily Target Profit (Stop trading for the day)
input double InpDailyLossLimit     = 200.0;  // Daily Loss Limit (Input as positive number, e.g. 200)

CTrade trade;

int    handle_WMA_half, handle_WMA_full;
double arr_half[], arr_full[];
static datetime lastBarTime = 0;
bool   tradingHaltedToday = false; // Tracks if daily limit was hit

#define OBJ_PREFIX "EA_"

//--- one record per trade we opened and are managing
struct TradeInfo
  {
   ulong    ticket;
   int      dir;             // 1 = buy, -1 = sell
   double   entryPrice;
   double   originalVolume;
   double   partialVolume;   // normalized 20% of originalVolume
   int      nextPartial;     // index 0..InpPartials-1 of the next unclaimed partial
   int      retries;         // Tracks how many times this specific setup has been re-opened
   double   tpLevels[];      // InpPartials price levels, last one == final TP
   string   signalType;      // "Breakout" or "Engulfing"
  };
TradeInfo trades[];

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippage);

   int half_period = (int)MathFloor(InpPeriod / 2.0);
   handle_WMA_half = iMA(_Symbol, _Period, half_period, 0, MODE_LWMA, InpPrice);
   handle_WMA_full = iMA(_Symbol, _Period, InpPeriod, 0, MODE_LWMA, InpPrice);
   if(handle_WMA_half == INVALID_HANDLE || handle_WMA_full == INVALID_HANDLE)
      return(INIT_FAILED);

   ArraySetAsSeries(arr_half, true);
   ArraySetAsSeries(arr_full, true);

   lastBarTime = 0;
   tradingHaltedToday = false;
   ArrayResize(trades, 0);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(handle_WMA_half);
   IndicatorRelease(handle_WMA_full);
   if(reason == REASON_REMOVE)
      ObjectsDeleteAll(0, OBJ_PREFIX);
  }

//+------------------------------------------------------------------+
bool GetLastTwoHMA(double &hma_c, double &hma_p)
  {
   int sqrt_period = (int)MathFloor(MathSqrt(InpPeriod));
   int need = sqrt_period + 2;

   if(CopyBuffer(handle_WMA_half, 0, 1, need, arr_half) <= 0) return(false);
   if(CopyBuffer(handle_WMA_full, 0, 1, need, arr_full) <= 0) return(false);

   double raw[];
   ArrayResize(raw, need);
   for(int i = 0; i < need; i++)
      raw[i] = 2.0 * arr_half[i] - arr_full[i];

   double sum_c = 0, wsum_c = 0, sum_p = 0, wsum_p = 0;
   for(int j = 0; j < sqrt_period; j++)
     {
      double weight = (double)(sqrt_period - j);
      sum_c  += raw[j]   * weight; wsum_c += weight;
      sum_p  += raw[j+1] * weight; wsum_p += weight;
     }
   hma_c = sum_c / wsum_c;
   hma_p = sum_p / wsum_p;
   return(true);
  }

//+------------------------------------------------------------------+
//| CheckSignal: Evaluates Breakout, Engulfing, or Both              |
//+------------------------------------------------------------------+
bool CheckSignal(int &direction, string &signalType)
  {
   direction = 0;
   signalType = "";

   double hma_c, hma_p;
   if(!GetLastTwoHMA(hma_c, hma_p)) return(false);

   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(_Symbol, _Period, 1, 3, r) < 3) return(false);

   double open_c = r[0].open, close_c = r[0].close;
   double open_p = r[1].open, close_p = r[1].close;

   // 1. Breakout Conditions: Price crossed & closed across HMA
   bool bullBreakout = (close_p <= hma_p) && (close_c > hma_c);
   bool bearBreakout = (close_p >= hma_p) && (close_c < hma_c);

   // 2. Engulfing Conditions
   bool bullEngulf = (close_p < open_p) && (close_c > open_c) &&
                      (open_c <= close_p) && (close_c >= open_p);
   bool bearEngulf = (close_p > open_p) && (close_c < open_c) &&
                      (open_c >= close_p) && (close_c <= open_p);

   // Mode 0: Breakout Only (triggers as soon as price crosses & closes across HMA)
   if(InpEntryMode == ENTRY_BREAKOUT_ONLY)
     {
      if(bullBreakout) { direction =  1; signalType = "HMA-Breakout"; return(true); }
      if(bearBreakout) { direction = -1; signalType = "HMA-Breakout"; return(true); }
     }
   // Mode 1: Engulfing Only (Cross + Engulfing candle confirmation)
   else if(InpEntryMode == ENTRY_ENGULFING_ONLY)
     {
      if(bullBreakout && bullEngulf) { direction =  1; signalType = "HMA-Engulf"; return(true); }
      if(bearBreakout && bearEngulf) { direction = -1; signalType = "HMA-Engulf"; return(true); }
     }
   // Mode 2: Both (Prioritizes Engulfing if present, otherwise takes pure Breakout)
   else if(InpEntryMode == ENTRY_BOTH)
     {
      if(bullBreakout)
        {
         direction = 1;
         signalType = bullEngulf ? "HMA-Engulf" : "HMA-Breakout";
         return(true);
        }
      if(bearBreakout)
        {
         direction = -1;
         signalType = bearEngulf ? "HMA-Engulf" : "HMA-Breakout";
         return(true);
        }
     }

   return(false);
  }

//+------------------------------------------------------------------+
double NormalizeVolume(double vol)
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minv = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxv = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0) step = 0.01;
   vol = MathRound(vol / step) * step;
   vol = MathMax(minv, MathMin(maxv, vol));
   return(NormalizeDouble(vol, 2));
  }

//+------------------------------------------------------------------+
int CountOurPositions()
  {
   int cnt = 0;
   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk) &&
         PositionGetInteger(POSITION_MAGIC) == InpMagic &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
         cnt++;
     }
   return(cnt);
  }

//+------------------------------------------------------------------+
double GetOpenPositionsProfit()
  {
   double totalProfit = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk) &&
         PositionGetInteger(POSITION_MAGIC) == InpMagic &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
         totalProfit += PositionGetDouble(POSITION_PROFIT) + 
                        PositionGetDouble(POSITION_SWAP) + 
                        PositionGetDouble(POSITION_COMMISSION);
        }
     }
   return totalProfit;
  }

//+------------------------------------------------------------------+
void CheckDailyLimits()
  {
   if(!InpEnableDailyLimits) return;
   
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   
   static int lastDay = -1;
   if(lastDay != dt.day_of_year)
     {
      lastDay = dt.day_of_year;
      tradingHaltedToday = false;
     }
     
   if(tradingHaltedToday) return;

   MqlDateTime dtStart = dt;
   dtStart.hour = 0;
   dtStart.min = 0;
   dtStart.sec = 0;
   datetime todayStart = StructToTime(dtStart);

   HistorySelect(todayStart, now);
   double closedProfit = 0.0;
   int total = HistoryDealsTotal();
   
   for(int i = 0; i < total; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > 0)
        {
         if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagic &&
            HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol)
           {
            closedProfit += HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                            HistoryDealGetDouble(ticket, DEAL_SWAP) +
                            HistoryDealGetDouble(ticket, DEAL_COMMISSION);
           }
        }
     }

   double openProfit = GetOpenPositionsProfit();
   double totalDailyProfit = closedProfit + openProfit;

   bool hitLimit = false;
   if(totalDailyProfit >= InpDailyProfitTarget)
     {
      PrintFormat("Daily Profit Target Reached! Total: %.2f. Halting trades for today.", totalDailyProfit);
      hitLimit = true;
     }
   else if(totalDailyProfit <= -InpDailyLossLimit)
     {
      PrintFormat("Daily Loss Limit Reached! Total: %.2f. Halting trades for today.", totalDailyProfit);
      hitLimit = true;
     }

   if(hitLimit)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong tk = PositionGetTicket(i);
         if(PositionSelectByTicket(tk) &&
            PositionGetInteger(POSITION_MAGIC) == InpMagic &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
           {
            trade.PositionClose(tk);
           }
        }
      tradingHaltedToday = true;
     }
  }

//+------------------------------------------------------------------+
void CreateHLineObj(const string name, const double price, const color clr, const string text)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
     }
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
  }

//+------------------------------------------------------------------+
void DrawTradeVisuals(const ulong ticket, const int dir, const double entry,
                       const double sl, const double &tpLevels[], const string signalType)
  {
   string base = OBJ_PREFIX + IntegerToString(ticket) + "_";
   color  tpClr = (dir == 1) ? clrLime : clrOrange;

   CreateHLineObj(base + "Entry", entry, clrWhite, signalType + " #" + IntegerToString(ticket));
   CreateHLineObj(base + "SL",    sl,    clrRed,   "SL");
   for(int k = 0; k < ArraySize(tpLevels); k++)
      CreateHLineObj(base + "TP" + IntegerToString(k+1), tpLevels[k], tpClr,
                      "TP" + IntegerToString(k+1));
  }

//+------------------------------------------------------------------+
void MoveSLLine(const ulong ticket, const double newSL)
  {
   string name = OBJ_PREFIX + IntegerToString(ticket) + "_SL";
   if(ObjectFind(0, name) >= 0)
     {
      ObjectSetDouble(0, name, OBJPROP_PRICE, 0, newSL);
      ObjectSetString(0, name, OBJPROP_TEXT, "SL (BE)");
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrYellow);
     }
  }

//+------------------------------------------------------------------+
void DeleteTradeVisuals(const ulong ticket)
  {
   string prefix = OBJ_PREFIX + IntegerToString(ticket) + "_";
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
     {
      string nm = ObjectName(0, i, 0, -1);
      if(StringFind(nm, prefix) == 0)
         ObjectDelete(0, nm);
     }
  }

//+------------------------------------------------------------------+
void OpenTrade(const int dir, const string signalType = "HMA-Trade", int retryCount = 0)
  {
   double point = _Point;
   double price = (dir == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                              : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = (dir == 1) ? price - InpSLPoints * point : price + InpSLPoints * point;
   double tp = (dir == 1) ? price + InpTPPoints * point : price - InpTPPoints * point;
   double vol = NormalizeVolume(InpLotSize);

   bool ok = (dir == 1) ? trade.Buy(vol, _Symbol, price, sl, tp, signalType)
                         : trade.Sell(vol, _Symbol, price, sl, tp, signalType);
   if(!ok)
     {
      PrintFormat("Order failed (%d): %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
      return;
     }

   ulong ticket = trade.ResultOrder();

   int n = ArraySize(trades);
   ArrayResize(trades, n + 1);
   trades[n].ticket         = ticket;
   trades[n].dir            = dir;
   trades[n].entryPrice     = price;
   trades[n].originalVolume = vol;
   trades[n].partialVolume  = NormalizeVolume(vol * InpPartialPercent / 100.0);
   trades[n].nextPartial    = 0;
   trades[n].retries        = retryCount;
   trades[n].signalType     = signalType;
   ArrayResize(trades[n].tpLevels, InpPartials);
   
   for(int k = 0; k < InpPartials; k++)
     {
      double dist = InpTPPoints * point * (double)(k + 1) / (double)InpPartials;
      trades[n].tpLevels[k] = (dir == 1) ? price + dist : price - dist;
     }

   DrawTradeVisuals(ticket, dir, price, sl, trades[n].tpLevels, signalType);
  }

//+------------------------------------------------------------------+
bool ManageBasketProfit()
  {
   if(!InpEnableBasketTP) return false;
   
   double totalProfit = GetOpenPositionsProfit();
   int openCount = CountOurPositions();

   if(openCount > 0 && totalProfit >= InpBasketProfitTarget)
     {
      PrintFormat("Basket Profit Target Reached! Closing %d trades. Total Profit: %.2f", openCount, totalProfit);
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong tk = PositionGetTicket(i);
         if(PositionSelectByTicket(tk) &&
            PositionGetInteger(POSITION_MAGIC) == InpMagic &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
           {
            trade.PositionClose(tk);
           }
        }
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
void ManageOpenTrades(bool skipReopen)
  {
   for(int i = ArraySize(trades) - 1; i >= 0; i--)
     {
      if(!PositionSelectByTicket(trades[i].ticket))
        {
         bool isSLHit = false;
         
         if(trades[i].nextPartial == 0 && !tradingHaltedToday && !skipReopen)
           {
            if(HistorySelectByPosition(trades[i].ticket))
              {
               double posProfit = 0;
               for(int d = 0; d < HistoryDealsTotal(); d++)
                 {
                  ulong dealTk = HistoryDealGetTicket(d);
                  posProfit += HistoryDealGetDouble(dealTk, DEAL_PROFIT);
                 }
               if(posProfit < 0) isSLHit = true;
              }
           }

         int dir = trades[i].dir;
         int retries = trades[i].retries;
         string sigType = trades[i].signalType;
         
         DeleteTradeVisuals(trades[i].ticket);
         ArrayRemove(trades, i, 1);
         
         if(isSLHit && retries < InpMaxRetries)
           {
            PrintFormat("Trade hit SL without BE. Re-opening... (Retry %d of %d)", retries + 1, InpMaxRetries);
            OpenTrade(dir, sigType, retries + 1);
           }
         continue;
        }

      double curVol = PositionGetDouble(POSITION_VOLUME);
      if(curVol <= 0.0)
        {
         DeleteTradeVisuals(trades[i].ticket);
         ArrayRemove(trades, i, 1);
         continue;
        }

      int np = trades[i].nextPartial;
      if(np >= InpPartials) continue;

      double level = trades[i].tpLevels[np];
      double price = (trades[i].dir == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                          : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      bool hit = (trades[i].dir == 1) ? (price >= level) : (price <= level);
      if(!hit) continue;

      bool isLast = (np == InpPartials - 1);
      double volToClose = isLast ? curVol : MathMin(trades[i].partialVolume, curVol);

      bool ok;
      if(isLast || volToClose >= curVol - 0.0000001)
         ok = trade.PositionClose(trades[i].ticket);
      else
         ok = trade.PositionClosePartial(trades[i].ticket, volToClose);

      if(!ok)
        {
         PrintFormat("Partial close failed (%d): %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
         continue;
        }

      ObjectDelete(0, OBJ_PREFIX + IntegerToString(trades[i].ticket) + "_TP" + IntegerToString(np + 1));

      if(np == 0 && !isLast)
        {
         double curTP = PositionGetDouble(POSITION_TP);
         if(trade.PositionModify(trades[i].ticket, trades[i].entryPrice, curTP))
            MoveSLLine(trades[i].ticket, trades[i].entryPrice);
        }

      trades[i].nextPartial++;

      if(isLast || trades[i].nextPartial >= InpPartials)
        {
         DeleteTradeVisuals(trades[i].ticket);
         ArrayRemove(trades, i, 1);
        }
     }
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   // 1. Monitor Daily Stop Limits (Takes priority)
   CheckDailyLimits();

   // 2. Monitor floating Basket TP
   bool basketClosedJustNow = false;
   if(!tradingHaltedToday) 
     {
      basketClosedJustNow = ManageBasketProfit();
     }

   // 3. Manage open trade partials and visual cleanup
   ManageOpenTrades(basketClosedJustNow);

   // 4. Do not evaluate new trades if we hit the daily limits
   if(tradingHaltedToday) return;

   datetime t[];
   ArraySetAsSeries(t, true);
   if(CopyTime(_Symbol, _Period, 0, 1, t) < 1) return;
   if(t[0] == lastBarTime) return;
   lastBarTime = t[0];

   int dir;
   string signalType;
   if(!CheckSignal(dir, signalType)) return;

   if(InpMaxOpenTrades > 0 && CountOurPositions() >= InpMaxOpenTrades) return;

   OpenTrade(dir, signalType, 0); // Fresh signal trade, 0 retries
  }
//+------------------------------------------------------------------+