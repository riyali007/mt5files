//+------------------------------------------------------------------+
//|                               Auto_EA_Momentum_Grid_v2.50.mq5    |
//+------------------------------------------------------------------+
#property copyright "Senior Trading Systems Architect"
#property link      ""
#property version   "2.50"

#include <Trade\Trade.mqh>

//--- Enums
enum ENUM_EXECUTION_TYPE {
   EXEC_MARKET,      // Market Order Execution
   EXEC_LIMIT        // Pending Limit Order Execution
};

enum ENUM_TRIGGER_MODE {
   TRIGGER_STANDARD,   // Standard Streak (Whole candle beyond EMA + within Max Distance)
   TRIGGER_CROSSOVER,  // Cross/Tap Streak (Whole candle beyond EMA + Origin crossed EMA)
   TRIGGER_CLOSE_ONLY  // Close Only (Candles close above/below EMA + Origin crossed EMA + within Max Distance)
};

//--- Core Inputs
sinput string         Grid_Settings = "--- Momentum Grid Settings ---";
input ENUM_TRIGGER_MODE InpTriggerMode = TRIGGER_CLOSE_ONLY; // Strategy Mode
input int             InpConsecutiveCandles = 2;          // Consecutive Candles to Trigger
input int             InpMaxTrades = 5;                   // Max Open Trades/Orders (Grid Limit)
input bool            InpCloseOnReversal = true;          // Close Opposite Trades/Orders on Reversal?

sinput string         Filter_Settings = "--- Trend Filter (EMA) ---";
input bool            InpUseEMA = true;                   // Enable EMA Filter
input int             InpEMAPeriod = 200;                 // EMA Period
input int             InpEMAMaxDistancePoints = 100;      // Max distance from EMA allowed
input bool            InpDrawEMA = true;                  // Draw EMA Line on Chart

sinput string         Execution_Settings = "--- Execution & Order Type ---";
input ENUM_EXECUTION_TYPE InpExecType = EXEC_MARKET;      // Order Execution Type
input int             InpLimitPullbackPoints = 50;        // Limit Pullback Distance (if Limit selected)

sinput string         Session_Settings = "--- Trading Sessions ---";
input bool            InpUseSessions = true;              // Enforce Session Times
input bool            InpEnableAsia = true;               // Trade Asia Session
input string          InpAsiaStart = "00:00";             // Asia Start Time (HH:MM)
input string          InpAsiaEnd = "08:00";               // Asia End Time (HH:MM)
input bool            InpEnableLondon = true;             // Trade London Session
input string          InpLondonStart = "08:00";           // London Start Time (HH:MM)
input string          InpLondonEnd = "16:00";             // London End Time (HH:MM)
input bool            InpEnableNY = true;                 // Trade New York Session
input string          InpNYStart = "14:00";               // NY Start Time (HH:MM)
input string          InpNYEnd = "22:00";                 // NY End Time (HH:MM)

sinput string         Risk_Settings = "--- Risk & Trade Settings ---";
input double          InpLotSize = 0.10;                  // Initial Lot Size
input int             InpTakeProfitPoints = 300;          // Final Take Profit (in Points)
input int             InpStopLossPoints = 200;            // Stop Loss (in Points, 0 = Disabled)
input ulong           InpMagicNumber = 555666;            // Magic Number

sinput string         TM_Settings = "--- Advanced Trade Management ---";
input bool            InpUseAdvancedTM = true;            // Enable Partials & BE
input int             InpNumPartials = 2;                 // Number of Partial Levels (Divides distance to TP)
input double          InpPartial_Close_Pct = 25.0;        // % of Initial Lot to Close per Partial
input int             InpMoveBE_AfterPartial = 1;         // Move SL to BE after Partial # 

sinput string         Basket_Settings = "--- Accumulated Basket Target ($) ---";
input bool            InpUseBasketProfit = true;          // Enable Dollar-Based TP
input double          InpBasketTargetProfit = 50.0;       // Target Profit ($) per direction
input bool            InpUseBasketLoss = true;            // Enable Dollar-Based SL
input double          InpBasketTargetLoss = 20.0;         // Target Loss ($) per direction 

//--- Global Variables
CTrade         trade;
int            handleEMA;
datetime       lastBarTime = 0;
bool           isFirstRun = true;

// State Struct for Position Management (Partials/Trailing)
struct PositionState {
   ulong  pos_id;
   int    partials_taken;
   double initial_lot;
   double entry_price;
   int    type;         
};
PositionState states[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);
   lastBarTime = 0; 
   isFirstRun = true;
   
   if(InpUseEMA)
     {
      handleEMA = iMA(_Symbol, PERIOD_CURRENT, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(handleEMA == INVALID_HANDLE) { Print("Failed to load EMA"); return INIT_FAILED; }
      if(InpDrawEMA) ChartIndicatorAdd(0, 0, handleEMA);
     }
   
   Print("Momentum Grid v2.50 Initialized. Mode: ", EnumToString(InpTriggerMode));
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(InpUseEMA) 
     {
      if(InpDrawEMA) ChartIndicatorDelete(0, 0, "Moving Average");
      IndicatorRelease(handleEMA);
     }
  }

//+------------------------------------------------------------------+
//| Helper: Normalize Lot Size                                       |
//+------------------------------------------------------------------+
double GetNormalizedLot(double rawLot)
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   double lot = MathFloor(rawLot / step) * step;
   if(lot < min) lot = min;
   if(lot > max) lot = max;
   return lot;
  }

//+------------------------------------------------------------------+
//| Helpers: Time and Sessions                                       |
//+------------------------------------------------------------------+
int ParseTimeStrToMins(string timeStr)
  {
   string sep = ":";
   ushort u_sep = StringGetCharacter(sep, 0);
   string res[];
   if(StringSplit(timeStr, u_sep, res) == 2)
      return (int)StringToInteger(res[0]) * 60 + (int)StringToInteger(res[1]);
   return 0;
  }

bool IsTimeInRange(int currentMins, string startStr, string endStr)
  {
   int startMins = ParseTimeStrToMins(startStr);
   int endMins = ParseTimeStrToMins(endStr);
   if(startMins < endMins) return (currentMins >= startMins && currentMins < endMins);
   else return (currentMins >= startMins || currentMins < endMins);
  }

bool IsInTradingSession()
  {
   if(!InpUseSessions) return true; 
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   int currentMins = dt.hour * 60 + dt.min;
   if(InpEnableAsia && IsTimeInRange(currentMins, InpAsiaStart, InpAsiaEnd)) return true;
   if(InpEnableLondon && IsTimeInRange(currentMins, InpLondonStart, InpLondonEnd)) return true;
   if(InpEnableNY && IsTimeInRange(currentMins, InpNYStart, InpNYEnd)) return true;
   return false;
  }

bool IsNewBar()
  {
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime != lastBarTime)
     {
      lastBarTime = currentBarTime;
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Order Count & Cleanup Helpers                                    |
//+------------------------------------------------------------------+
void CloseAllPositionsAndOrders()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
         trade.PositionClose(ticket);
        }
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(OrderGetInteger(ORDER_MAGIC) == InpMagicNumber && OrderGetString(ORDER_SYMBOL) == _Symbol)
        {
         trade.OrderDelete(ticket);
        }
     }
  }

void CloseTradesAndOrders(int posTypeToClose, int orderTypeToCancel)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
         if(PositionGetInteger(POSITION_TYPE) == posTypeToClose) trade.PositionClose(ticket);
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(OrderGetInteger(ORDER_MAGIC) == InpMagicNumber && OrderGetString(ORDER_SYMBOL) == _Symbol)
         if(OrderGetInteger(ORDER_TYPE) == orderTypeToCancel) trade.OrderDelete(ticket);
     }
  }

int CountTradesAndOrders(int posType, int orderType)
  {
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
         if(PositionGetInteger(POSITION_TYPE) == posType) count++;
     }
   for(int i = 0; i < OrdersTotal(); i++)
     {
      ulong ticket = OrderGetTicket(i);
      if(OrderGetInteger(ORDER_MAGIC) == InpMagicNumber && OrderGetString(ORDER_SYMBOL) == _Symbol)
         if(OrderGetInteger(ORDER_TYPE) == orderType) count++;
     }
   return count;
  }

//+------------------------------------------------------------------+
//| Basket Profit/Loss Monitor (Per Direction)                       |
//+------------------------------------------------------------------+
void CheckBasketTarget()
  {
   if(!InpUseBasketProfit && !InpUseBasketLoss) return;
   
   double totalBuyProfit = 0.0, totalSellProfit = 0.0;
   int buyCount = 0, sellCount = 0;
   
   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i); 
      if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
         double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP) + PositionGetDouble(POSITION_COMMISSION);
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) { totalBuyProfit += profit; buyCount++; }
         else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) { totalSellProfit += profit; sellCount++; }
        }
     }
     
   if(buyCount > 0)
     {
      if(InpUseBasketProfit && totalBuyProfit >= InpBasketTargetProfit) CloseTradesAndOrders(POSITION_TYPE_BUY, ORDER_TYPE_BUY_LIMIT);
      else if(InpUseBasketLoss && totalBuyProfit <= -MathAbs(InpBasketTargetLoss)) CloseTradesAndOrders(POSITION_TYPE_BUY, ORDER_TYPE_BUY_LIMIT);
     }
     
   if(sellCount > 0)
     {
      if(InpUseBasketProfit && totalSellProfit >= InpBasketTargetProfit) CloseTradesAndOrders(POSITION_TYPE_SELL, ORDER_TYPE_SELL_LIMIT);
      else if(InpUseBasketLoss && totalSellProfit <= -MathAbs(InpBasketTargetLoss)) CloseTradesAndOrders(POSITION_TYPE_SELL, ORDER_TYPE_SELL_LIMIT);
     }
  }

//+------------------------------------------------------------------+
//| Advanced Trade Management Helpers                                |
//+------------------------------------------------------------------+
bool SelectPositionById(ulong id)
  {
   for(int i=0; i<PositionsTotal(); i++) 
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetInteger(POSITION_IDENTIFIER) == id) return true;
     }
   return false;
  }

void SyncStates()
  {
   if(!InpUseAdvancedTM) return;
   for(int i = ArraySize(states) - 1; i >= 0; i--) if(!SelectPositionById(states[i].pos_id)) ArrayRemove(states, i, 1);
   
   for(int i=0; i<PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i); 
      ulong pos_id = PositionGetInteger(POSITION_IDENTIFIER);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
        {
         bool found = false;
         for(int j=0; j<ArraySize(states); j++) if(states[j].pos_id == pos_id) { found = true; break; }
         if(!found)
           {
            int idx = ArraySize(states);
            ArrayResize(states, idx + 1);
            states[idx].pos_id = pos_id;
            states[idx].partials_taken = 0;
            states[idx].initial_lot = PositionGetDouble(POSITION_VOLUME);
            states[idx].entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
            states[idx].type = (int)PositionGetInteger(POSITION_TYPE);
           }
        }
     }
  }

void ManageTrades()
  {
   if(!InpUseAdvancedTM || InpTakeProfitPoints <= 0 || InpNumPartials <= 0) return;

   // Calculate the mathematical distance (in points) per partial slice
   // e.g. If Final TP is 300 points, and Partials = 2. 
   // Step = 300 / (2 + 1) = 100 points per slice.
   double stepPoints = (double)InpTakeProfitPoints / (InpNumPartials + 1.0);

   for(int i=0; i<ArraySize(states); i++)
     {
      if(!SelectPositionById(states[i].pos_id)) continue;
      
      ulong ticket = PositionGetInteger(POSITION_TICKET);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double volume = PositionGetDouble(POSITION_VOLUME);
      
      double current_bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double current_ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double eval_price = (states[i].type == POSITION_TYPE_BUY) ? current_bid : current_ask;
      double profit_pts = (states[i].type == POSITION_TYPE_BUY) ? (eval_price - states[i].entry_price)/_Point : (states[i].entry_price - eval_price)/_Point;
      
      if(states[i].partials_taken < InpNumPartials)
        {
         double target_pts = (states[i].partials_taken + 1) * stepPoints;
         
         if(profit_pts >= target_pts)
           {
            double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
            double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            double lot_to_close = MathFloor((states[i].initial_lot * (InpPartial_Close_Pct / 100.0)) / step) * step; 
            
            if(lot_to_close < min_lot) lot_to_close = min_lot;
            if(lot_to_close > volume) lot_to_close = volume;
            
            if(volume > min_lot)
              {
               if(trade.PositionClosePartial(ticket, lot_to_close))
                 {
                  states[i].partials_taken++;
                  if(!SelectPositionById(states[i].pos_id)) continue;
                  ticket = PositionGetInteger(POSITION_TICKET);
                  volume = PositionGetDouble(POSITION_VOLUME);
                 }
              }
            else states[i].partials_taken++; // Insufficient volume, just increment counter
            
            if(states[i].partials_taken == InpMoveBE_AfterPartial)
              {
               double be_price = states[i].entry_price;
               if(MathAbs(sl - be_price) > _Point) 
                 {
                  if(states[i].type == POSITION_TYPE_BUY && sl < be_price) trade.PositionModify(ticket, be_price, tp);
                  else if(states[i].type == POSITION_TYPE_SELL && (sl > be_price || sl == 0)) trade.PositionModify(ticket, be_price, tp);
                  sl = be_price; 
                 }
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Main Expert Tick Function                                        |
//+------------------------------------------------------------------+
void OnTick()
  {
   SyncStates();
   ManageTrades();
   CheckBasketTarget();

   bool newBar = IsNewBar();
   if(!newBar && !isFirstRun) return;
   isFirstRun = false; 

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   if(CopyRates(_Symbol, PERIOD_CURRENT, 1, InpConsecutiveCandles + 1, rates) <= InpConsecutiveCandles) 
      return;

   // EMA Calculation
   bool isAboveEMA = true;
   bool isBelowEMA = true;
   
   double emaVal[];
   ArraySetAsSeries(emaVal, true);
   
   if(InpUseEMA && CopyBuffer(handleEMA, 0, 1, InpConsecutiveCandles + 1, emaVal) >= InpConsecutiveCandles)
     {
      // ==========================================
      // STRATEGY 1: STANDARD MOMENTUM
      // ==========================================
      if(InpTriggerMode == TRIGGER_STANDARD)
        {
         for(int i = 0; i < InpConsecutiveCandles; i++)
           {
            if(rates[i].low <= emaVal[i]) isAboveEMA = false;
            if(rates[i].high >= emaVal[i]) isBelowEMA = false;
            
            double distToEMA = MathAbs(rates[i].close - emaVal[i]) / _Point;
            if(isAboveEMA && distToEMA > InpEMAMaxDistancePoints) isAboveEMA = false;
            if(isBelowEMA && distToEMA > InpEMAMaxDistancePoints) isBelowEMA = false;
           }
        }
      // ==========================================
      // STRATEGY 2: CROSSOVER / TAP MOMENTUM
      // ==========================================
      else if(InpTriggerMode == TRIGGER_CROSSOVER)
        {
         for(int i = 0; i < InpConsecutiveCandles; i++)
           {
            if(rates[i].low <= emaVal[i]) isAboveEMA = false;
            if(rates[i].high >= emaVal[i]) isBelowEMA = false;
           }
           
         int originIdx = InpConsecutiveCandles;
         bool originTappedEMA = (rates[originIdx].low <= emaVal[originIdx] && rates[originIdx].high >= emaVal[originIdx]);
         
         if(isAboveEMA && !originTappedEMA) isAboveEMA = false;
         if(isBelowEMA && !originTappedEMA) isBelowEMA = false;
        }
      // ==========================================
      // STRATEGY 3: CLOSE ONLY MOMENTUM (With Origin Cross & Distance)
      // ==========================================
      else if(InpTriggerMode == TRIGGER_CLOSE_ONLY)
        {
         // 1. Candles must close above/below the EMA
         for(int i = 0; i < InpConsecutiveCandles; i++)
           {
            if(rates[i].close <= emaVal[i]) isAboveEMA = false;
            if(rates[i].close >= emaVal[i]) isBelowEMA = false;
            
            // 2. The Close price must still be within the Max Distance configured
            double distToEMA = MathAbs(rates[i].close - emaVal[i]) / _Point;
            if(isAboveEMA && distToEMA > InpEMAMaxDistancePoints) isAboveEMA = false;
            if(isBelowEMA && distToEMA > InpEMAMaxDistancePoints) isBelowEMA = false;
           }
           
         // 3. The exact candle that starts the streak must cross the EMA
         int firstStreakIdx = InpConsecutiveCandles - 1; 
         
         bool crossedFromAbove = (rates[firstStreakIdx].open >= emaVal[firstStreakIdx] && rates[firstStreakIdx].close < emaVal[firstStreakIdx]);
         bool crossedFromBelow = (rates[firstStreakIdx].open <= emaVal[firstStreakIdx] && rates[firstStreakIdx].close > emaVal[firstStreakIdx]);
         
         if(isAboveEMA && !crossedFromBelow) isAboveEMA = false;
         if(isBelowEMA && !crossedFromAbove) isBelowEMA = false;
        }
     }
   else
     {
      isAboveEMA = false; 
      isBelowEMA = false;
     }

   // Momentum Streak Detection
   bool isBullishStreak = true;
   bool isBearishStreak = true;

   for(int i = 0; i < InpConsecutiveCandles; i++)
     {
      if(InpTriggerMode == TRIGGER_CLOSE_ONLY)
        {
         if(i == InpConsecutiveCandles - 1) 
           {
            if(rates[i].close <= rates[i].open) isBullishStreak = false; 
            if(rates[i].close >= rates[i].open) isBearishStreak = false; 
           }
        }
      else
        {
         if(rates[i].close <= rates[i].open) isBullishStreak = false; 
         if(rates[i].close >= rates[i].open) isBearishStreak = false; 
        }
     }

   // Apply Final Filter
   if(InpUseEMA && !isAboveEMA) isBullishStreak = false;
   if(InpUseEMA && !isBelowEMA) isBearishStreak = false;

   // --- BULLISH STREAK DETECTED (BUY SIGNAL) ---
   if(isBullishStreak)
     {
      if(InpCloseOnReversal) CloseTradesAndOrders(POSITION_TYPE_SELL, ORDER_TYPE_SELL_LIMIT); 
      
      if(!IsInTradingSession()) return;
      
      int currentBuys = CountTradesAndOrders(POSITION_TYPE_BUY, ORDER_TYPE_BUY_LIMIT);
      
      if(currentBuys < InpMaxTrades)
        {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double normLot = GetNormalizedLot(InpLotSize);
         
         if(InpExecType == EXEC_MARKET)
           {
            double sl = (InpStopLossPoints > 0) ? NormalizeDouble(ask - (InpStopLossPoints * _Point), _Digits) : 0;
            double tp = (InpTakeProfitPoints > 0) ? NormalizeDouble(ask + (InpTakeProfitPoints * _Point), _Digits) : 0;
            trade.Buy(normLot, _Symbol, ask, sl, tp, "Momentum Grid Buy");
           }
         else if(InpExecType == EXEC_LIMIT)
           {
            double limitPrice = NormalizeDouble(ask - (InpLimitPullbackPoints * _Point), _Digits);
            double sl = (InpStopLossPoints > 0) ? NormalizeDouble(limitPrice - (InpStopLossPoints * _Point), _Digits) : 0;
            double tp = (InpTakeProfitPoints > 0) ? NormalizeDouble(limitPrice + (InpTakeProfitPoints * _Point), _Digits) : 0;
            trade.BuyLimit(normLot, limitPrice, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "Momentum Buy Limit");
           }
        }
     }

   // --- BEARISH STREAK DETECTED (SELL SIGNAL) ---
   if(isBearishStreak)
     {
      if(InpCloseOnReversal) CloseTradesAndOrders(POSITION_TYPE_BUY, ORDER_TYPE_BUY_LIMIT); 
      
      if(!IsInTradingSession()) return;
      
      int currentSells = CountTradesAndOrders(POSITION_TYPE_SELL, ORDER_TYPE_SELL_LIMIT);
      
      if(currentSells < InpMaxTrades)
        {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double normLot = GetNormalizedLot(InpLotSize);
         
         if(InpExecType == EXEC_MARKET)
           {
            double sl = (InpStopLossPoints > 0) ? NormalizeDouble(bid + (InpStopLossPoints * _Point), _Digits) : 0;
            double tp = (InpTakeProfitPoints > 0) ? NormalizeDouble(bid - (InpTakeProfitPoints * _Point), _Digits) : 0;
            trade.Sell(normLot, _Symbol, bid, sl, tp, "Momentum Grid Sell");
           }
         else if(InpExecType == EXEC_LIMIT)
           {
            double limitPrice = NormalizeDouble(bid + (InpLimitPullbackPoints * _Point), _Digits);
            double sl = (InpStopLossPoints > 0) ? NormalizeDouble(limitPrice + (InpStopLossPoints * _Point), _Digits) : 0;
            double tp = (InpTakeProfitPoints > 0) ? NormalizeDouble(limitPrice - (InpTakeProfitPoints * _Point), _Digits) : 0;
            trade.SellLimit(normLot, limitPrice, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "Momentum Sell Limit");
           }
        }
     }
  }
//+------------------------------------------------------------------+