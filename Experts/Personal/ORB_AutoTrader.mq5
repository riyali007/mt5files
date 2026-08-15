//+------------------------------------------------------------------+
//|                                              ORB_AutoTrader.mq5  |
//|                                      Helpful Assistant Developer |
//+------------------------------------------------------------------+
#property copyright "Optimized ORB Strategy with Dynamic Partials"
#property link      ""
#property version   "6.00"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

CTrade         trade;
CPositionInfo  posInfo;

//--- Enums
enum ENUM_ANCHOR_TYPE { ANCHOR_START=0, ANCHOR_END=1 };
enum ENUM_HTF_SEL     { SEL_HTF_1=1, SEL_HTF_2=2, SEL_HTF_3=3, SEL_CTF=4 };

//--- Trading Setup
input group "=== Trading Setup ==="
input ENUM_HTF_SEL     InpTradeHTF       = SEL_HTF_1;      // Select Which Timeframe to Trade
input double           InpLotSize        = 0.1;            // Initial Lot Size
input double           InpTargetRR       = 3.0;            // Final Take Profit (Risk:Reward Ratio)

//--- Entry Strategy Checkboxes
input group "=== Entry Strategy ==="
input bool             InpEntryBreakout  = false;          // 1. Entry at Breakout (Live Tick)
input bool             InpEntryRetest    = true;           // 2. Entry at Re-test (Bar Close)
input bool             InpEntryFakeout   = true;           // 3. Entry at Failed Breakout (Bar Close)

//--- Multi-Partial Management
input group "=== Multi-Partial Management ==="
input int              InpNumPartials      = 3;              // Total TP Steps (2-10)
input double           InpFirstPartialPct  = 30.0;           // % Vol to Close on 1st TP
input double           InpRestPartialPct   = 10.0;           // % Vol to Close on subsequent TPs
input bool             InpMoveToBE         = true;           // Move SL to Break-Even after 1st TP

//--- Trade Visuals
input group "=== Trade Visuals ==="
input bool             InpDrawTradeLines = true;           // Draw Trade Levels on Chart
input color            InpColEntry       = clrBlue;        // Entry Line Color
input color            InpColSL          = clrRed;         // Stop Loss Line Color
input color            InpColTP          = clrLimeGreen;   // Final TP Line Color
input color            InpColPartial     = clrGold;        // Partial TP Line Color

//--- Global Display Settings
input group "=== Global ORB Settings ==="
input double           InpUTCOffset      = 0.0;            // Label Time Offset (Hours)

//--- HTF 1 Inputs
input group "=== HTF 1 ==="
input bool             InpHTF1_Plot      = true;           
input ENUM_TIMEFRAMES  InpHTF1_TF        = PERIOD_H1;      
input int              InpHTF1_Shift     = 1;
input ENUM_ANCHOR_TYPE InpHTF1_Anchor    = ANCHOR_START;
input int              InpHTF1_MinRange  = 5;
input color            InpHTF1_Color     = clrDodgerBlue;

//--- HTF 2 Inputs
input group "=== HTF 2 ==="
input bool             InpHTF2_Plot      = false;          
input ENUM_TIMEFRAMES  InpHTF2_TF        = PERIOD_H4;      
input int              InpHTF2_Shift     = 1;
input ENUM_ANCHOR_TYPE InpHTF2_Anchor    = ANCHOR_START;
input int              InpHTF2_MinRange  = 15;
input color            InpHTF2_Color     = clrOrange;

//--- HTF 3 Inputs
input group "=== HTF 3 ==="
input bool             InpHTF3_Plot      = false;          
input ENUM_TIMEFRAMES  InpHTF3_TF        = PERIOD_D1;      
input int              InpHTF3_Shift     = 1;
input ENUM_ANCHOR_TYPE InpHTF3_Anchor    = ANCHOR_END;
input int              InpHTF3_MinRange  = 30;
input color            InpHTF3_Color     = clrLimeGreen;

//--- Current TF Inputs
input group "=== Current TF ==="
input bool             InpCTF_Plot       = false;          
input ENUM_TIMEFRAMES  InpCTF_TF         = PERIOD_CURRENT; 
input int              InpCTF_Shift      = 1;
input ENUM_ANCHOR_TYPE InpCTF_Anchor     = ANCHOR_START;
input int              InpCTF_MinRange   = 5;
input color            InpCTF_Color      = clrMagenta;


//--- Multi-Partial Structures
struct PartialData {
   double rrTarget;
   double percent;
};
PartialData parsedPartials[];

struct PositionTracker {
   ulong  identifier;
   int    nextPartialIdx;
   double initialVol;
   double openPrice;
   double slPrice;
   bool   slMovedToBE;
};
PositionTracker activeTrackers[];

//--- Global Variables for State Machine
enum ENUM_TRADE_STATE { STATE_IDLE=0, STATE_WAIT_RETEST_HIGH=1, STATE_WAIT_RETEST_LOW=2 };

ENUM_TRADE_STATE currentState = STATE_IDLE;
double           breakoutSL   = 0.0;
datetime         lastBarTime  = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(19920812); 
   BuildPartialsArray();
   ClearObjects();
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   ClearObjects();
  }

//+------------------------------------------------------------------+
//| Dynamic Partials Builder                                         |
//+------------------------------------------------------------------+
void BuildPartialsArray()
  {
   int numSteps = (int)MathMax(2, MathMin(10, InpNumPartials)); 
   double rrStep = InpTargetRR / (double)numSteps;
   
   ArrayResize(parsedPartials, numSteps - 1);
   
   for(int i = 0; i < numSteps - 1; i++)
     {
      parsedPartials[i].rrTarget = NormalizeDouble(rrStep * (i + 1), 2);
      parsedPartials[i].percent  = (i == 0) ? InpFirstPartialPct : InpRestPartialPct;
     }
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // 1. Tick-by-tick Trade Management
   ManagePositionsAndTrackers();
   
   // 2. Update Trade Visuals
   UpdateTradeVisuals();

   // Plot HTFs for UI Visuals
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime != lastBarTime)
     {
      ProcessHTF(1, InpHTF1_Plot, InpHTF1_TF, InpHTF1_Shift, InpHTF1_Anchor, InpHTF1_MinRange, InpHTF1_Color);
      ProcessHTF(2, InpHTF2_Plot, InpHTF2_TF, InpHTF2_Shift, InpHTF2_Anchor, InpHTF2_MinRange, InpHTF2_Color);
      ProcessHTF(3, InpHTF3_Plot, InpHTF3_TF, InpHTF3_Shift, InpHTF3_Anchor, InpHTF3_MinRange, InpHTF3_Color);
      ProcessHTF(4, InpCTF_Plot,  InpCTF_TF,  InpCTF_Shift,  InpCTF_Anchor,  InpCTF_MinRange,  InpCTF_Color);
     }

   // Ensure valid ORB levels before trading logic
   double orbHigh, orbLow;
   if(GetActiveORBLevels(orbHigh, orbLow))
     {
      // -----------------------------------------------------------
      // ENTRY RULE 1: LIVE TICK BREAKOUT
      // -----------------------------------------------------------
      if(InpEntryBreakout && PositionsTotal() == 0)
        {
         static datetime lastBreakoutTime = 0;
         if(currentBarTime != lastBreakoutTime)
           {
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
            
            if(close1 <= orbHigh && bid > orbHigh)
              {
               ExecuteTrade(ORDER_TYPE_BUY, iLow(_Symbol, PERIOD_CURRENT, 0));
               lastBreakoutTime = currentBarTime;
              }
            else if(close1 >= orbLow && bid < orbLow)
              {
               ExecuteTrade(ORDER_TYPE_SELL, iHigh(_Symbol, PERIOD_CURRENT, 0));
               lastBreakoutTime = currentBarTime;
              }
           }
        }

      // -----------------------------------------------------------
      // ENTRY RULES 2 & 3: BAR CLOSE EVALUATION (RE-TEST & FAKEOUT)
      // -----------------------------------------------------------
      if(currentBarTime != lastBarTime)
        {
         double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
         double low1   = iLow(_Symbol, PERIOD_CURRENT, 1);
         double high1  = iHigh(_Symbol, PERIOD_CURRENT, 1);

         if(currentState == STATE_IDLE)
           {
            // FAKEOUT RULE 2: Single-Candle Wick Fakeout
            if(InpEntryFakeout && high1 > orbHigh && close1 < orbHigh)
              {
               breakoutSL = high1; 
               ExecuteTrade(ORDER_TYPE_SELL, breakoutSL);
              }
            else if(InpEntryFakeout && low1 < orbLow && close1 > orbLow)
              {
               breakoutSL = low1;
               ExecuteTrade(ORDER_TYPE_BUY, breakoutSL);
              }
            // Standard Breakout (Moves to Retest/Multi-candle Fakeout State)
            else if(close1 > orbHigh)
              {
               currentState = STATE_WAIT_RETEST_HIGH;
               breakoutSL = low1; // Default SL for retest setup
              }
            else if(close1 < orbLow)
              {
               currentState = STATE_WAIT_RETEST_LOW;
               breakoutSL = high1; // Default SL for retest setup
              }
           }
         else if(currentState == STATE_WAIT_RETEST_HIGH)
           {
            // FAKEOUT RULE 1: Multi-Candle Fakeout (Closed back under High)
            if(close1 < orbHigh)
              {
               if(InpEntryFakeout) 
                 {
                  breakoutSL = high1; // SL above fakeout candle
                  ExecuteTrade(ORDER_TYPE_SELL, breakoutSL);
                 }
               currentState = STATE_IDLE;
              }
            // Retest: Tapped high but closed above
            else if(low1 <= orbHigh && close1 > orbHigh)
              {
               if(InpEntryRetest) ExecuteTrade(ORDER_TYPE_BUY, breakoutSL);
               currentState = STATE_IDLE;
              }
           }
         else if(currentState == STATE_WAIT_RETEST_LOW)
           {
            // FAKEOUT RULE 1: Multi-Candle Fakeout (Closed back above Low)
            if(close1 > orbLow)
              {
               if(InpEntryFakeout)
                 {
                  breakoutSL = low1; // SL below fakeout candle
                  ExecuteTrade(ORDER_TYPE_BUY, breakoutSL);
                 }
               currentState = STATE_IDLE;
              }
            // Retest: Tapped low but closed below
            else if(high1 >= orbLow && close1 < orbLow)
              {
               if(InpEntryRetest) ExecuteTrade(ORDER_TYPE_SELL, breakoutSL);
               currentState = STATE_IDLE;
              }
           }
         lastBarTime = currentBarTime;
        }
     }
  }

//+------------------------------------------------------------------+
//| Trade Execution Engine                                           |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type, double slPrice)
  {
   if(PositionsTotal() > 0) return; 

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double openPrice = (type == ORDER_TYPE_BUY) ? ask : bid;
   
   if(slPrice == 0 || slPrice == openPrice) return; 

   double riskDist = MathAbs(openPrice - slPrice);
   double tpPrice  = (type == ORDER_TYPE_BUY) ? (openPrice + (riskDist * InpTargetRR)) : (openPrice - (riskDist * InpTargetRR));

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   slPrice = NormalizeDouble(slPrice, digits);
   tpPrice = NormalizeDouble(tpPrice, digits);

   if(type == ORDER_TYPE_BUY)
      trade.Buy(InpLotSize, _Symbol, 0, slPrice, tpPrice, "ORB Buy Signal");
   else
      trade.Sell(InpLotSize, _Symbol, 0, slPrice, tpPrice, "ORB Sell Signal");
  }

//+------------------------------------------------------------------+
//| Multi-Partial & Break-Even Management                            |
//+------------------------------------------------------------------+
void ManagePositionsAndTrackers()
  {
   for(int i = ArraySize(activeTrackers) - 1; i >= 0; i--)
     {
      if(!PositionSelectByTicket(activeTrackers[i].identifier))
         ArrayRemove(activeTrackers, i, 1);
     }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(posInfo.SelectByIndex(i) && posInfo.Magic() == 19920812 && posInfo.Symbol() == _Symbol)
        {
         ulong posID = posInfo.Identifier();
         
         int tIdx = -1;
         for(int j = 0; j < ArraySize(activeTrackers); j++) 
           {
            if(activeTrackers[j].identifier == posID) { tIdx = j; break; }
           }
           
         if(tIdx == -1) 
           {
            int sz = ArraySize(activeTrackers);
            ArrayResize(activeTrackers, sz + 1);
            activeTrackers[sz].identifier     = posID;
            activeTrackers[sz].initialVol     = posInfo.Volume();
            activeTrackers[sz].openPrice      = posInfo.PriceOpen();
            activeTrackers[sz].slPrice        = posInfo.StopLoss();
            activeTrackers[sz].nextPartialIdx = 0;
            activeTrackers[sz].slMovedToBE    = false;
            tIdx = sz;
           }

         double currentPrice = (posInfo.PositionType() == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double riskDist     = MathAbs(activeTrackers[tIdx].openPrice - activeTrackers[tIdx].slPrice);
         if(riskDist == 0) continue;

         if(activeTrackers[tIdx].nextPartialIdx < ArraySize(parsedPartials))
           {
            int pIdx = activeTrackers[tIdx].nextPartialIdx;
            double pTarget = (posInfo.PositionType() == POSITION_TYPE_BUY) ? 
                             (activeTrackers[tIdx].openPrice + (riskDist * parsedPartials[pIdx].rrTarget)) : 
                             (activeTrackers[tIdx].openPrice - (riskDist * parsedPartials[pIdx].rrTarget));
                             
            bool hitPartial = (posInfo.PositionType() == POSITION_TYPE_BUY) ? (currentPrice >= pTarget) : (currentPrice <= pTarget);
            
            if(hitPartial)
              {
               double minVol  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
               double stepVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
               
               double closeVol = MathFloor((activeTrackers[tIdx].initialVol * (parsedPartials[pIdx].percent / 100.0)) / stepVol) * stepVol;
               if(closeVol < minVol) closeVol = minVol;
               if(closeVol >= posInfo.Volume()) closeVol = posInfo.Volume(); 
               
               if(trade.PositionClosePartial(posInfo.Ticket(), closeVol))
                 {
                  activeTrackers[tIdx].nextPartialIdx++; 
                 }
              }
           }

         if(InpMoveToBE && !activeTrackers[tIdx].slMovedToBE && activeTrackers[tIdx].nextPartialIdx > 0)
           {
            int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
            double bePrice = NormalizeDouble(activeTrackers[tIdx].openPrice, digits);
            
            if(trade.PositionModify(posInfo.Ticket(), bePrice, posInfo.TakeProfit()))
              {
               activeTrackers[tIdx].slMovedToBE = true;
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Trade Visuals Manager                                            |
//+------------------------------------------------------------------+
void UpdateTradeVisuals()
  {
   if(!InpDrawTradeLines) return;

   bool posFound = false;
   for(int i = 0; i < PositionsTotal(); i++)
     {
      if(posInfo.SelectByIndex(i) && posInfo.Magic() == 19920812 && posInfo.Symbol() == _Symbol)
        {
         posFound = true;
         ulong posID = posInfo.Identifier();
         
         int tIdx = -1;
         for(int j=0; j<ArraySize(activeTrackers); j++) 
           { if(activeTrackers[j].identifier == posID) { tIdx = j; break; } }
           
         if(tIdx == -1) break;

         double openPrice = activeTrackers[tIdx].openPrice;
         double initSL    = activeTrackers[tIdx].slPrice;
         double tpPrice   = posInfo.TakeProfit();
         int    type      = posInfo.PositionType();
         
         double riskDist  = MathAbs(openPrice - initSL);

         DrawHLine("ORB_Trade_Entry", openPrice, InpColEntry, "Entry");
         DrawHLine("ORB_Trade_SL", posInfo.StopLoss(), InpColSL, activeTrackers[tIdx].slMovedToBE ? "SL (BE)" : "Stop Loss");
         DrawHLine("ORB_Trade_TP", tpPrice, InpColTP, "Final TP");
         
         for(int p = 0; p < ArraySize(parsedPartials); p++)
           {
            string lineName = "ORB_Trade_Partial_" + IntegerToString(p);
            if(p >= activeTrackers[tIdx].nextPartialIdx)
              {
               double pTarget = (type == POSITION_TYPE_BUY) ? (openPrice + (riskDist * parsedPartials[p].rrTarget)) : (openPrice - (riskDist * parsedPartials[p].rrTarget));
               DrawHLine(lineName, pTarget, InpColPartial, "TP " + IntegerToString(p+1) + " (" + DoubleToString(parsedPartials[p].rrTarget, 2) + " RR)");
              }
            else
              {
               ObjectDelete(0, lineName);
              }
           }
         break; 
        }
     }

   if(!posFound)
     {
      ObjectDelete(0, "ORB_Trade_Entry");
      ObjectDelete(0, "ORB_Trade_SL");
      ObjectDelete(0, "ORB_Trade_TP");
      for(int p = 0; p < 10; p++) ObjectDelete(0, "ORB_Trade_Partial_" + IntegerToString(p));
     }
  }

void DrawHLine(string name, double price, color col, string text)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, col);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
     }
   else
     {
      ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
     }
  }

//+------------------------------------------------------------------+
//| ORB Plotting Logic (Ported from Indicator)                       |
//+------------------------------------------------------------------+
void ProcessHTF(int id, bool plot, ENUM_TIMEFRAMES htf, int shift, ENUM_ANCHOR_TYPE anchor, int minRange, color col)
  {
   if(!plot) 
     {
      ObjectDelete(0, "ORB_M" + IntegerToString(id) + "_High");
      ObjectDelete(0, "ORB_M" + IntegerToString(id) + "_Low");
      return;
     }

   datetime htfTime = iTime(_Symbol, htf, shift);
   if(htfTime == 0) return;

   datetime htfNextTime;
   if(shift == 0) htfNextTime = htfTime + PeriodSeconds(htf);
   else 
     {
      htfNextTime = iTime(_Symbol, htf, shift - 1);
      if(htfNextTime == 0) htfNextTime = htfTime + PeriodSeconds(htf);
     }
   
   datetime endSearchTime = htfNextTime - 1; 
   int ltfStartIdx = iBarShift(_Symbol, PERIOD_CURRENT, htfTime, false);
   int ltfEndIdx   = iBarShift(_Symbol, PERIOD_CURRENT, endSearchTime, false);
   
   if(ltfStartIdx < 0 || ltfEndIdx < 0) return;

   int currentTfMinutes = PeriodSeconds(PERIOD_CURRENT) / 60;
   if(currentTfMinutes <= 0) currentTfMinutes = 1;
   
   int numBars = minRange / currentTfMinutes;
   if(numBars < 1) numBars = 1;

   int evalOldestIdx = 0;
   int evalNewestIdx = 0;

   if(anchor == ANCHOR_START) 
     {
      evalOldestIdx = ltfStartIdx;
      evalNewestIdx = MathMax(ltfStartIdx - numBars + 1, ltfEndIdx);
     } 
   else 
     {
      evalNewestIdx = ltfEndIdx;
      evalOldestIdx = MathMin(ltfEndIdx + numBars - 1, ltfStartIdx);
     }

   int totalBars = iBars(_Symbol, PERIOD_CURRENT);
   if(evalOldestIdx >= totalBars) evalOldestIdx = totalBars - 1;
   if(evalNewestIdx < 0) evalNewestIdx = 0;

   double maxHigh = -DBL_MAX;
   double minLow  = DBL_MAX;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int count = evalOldestIdx - evalNewestIdx + 1;
   
   if(CopyRates(_Symbol, PERIOD_CURRENT, evalNewestIdx, count, rates) > 0)
     {
      for(int i = 0; i < ArraySize(rates); i++) 
        {
         if(rates[i].high > maxHigh) maxHigh = rates[i].high;
         if(rates[i].low < minLow)   minLow  = rates[i].low;
        }
     }

   if(maxHigh == -DBL_MAX || minLow == DBL_MAX) return;

   datetime t1 = iTime(_Symbol, PERIOD_CURRENT, evalOldestIdx);
   datetime t2 = t1 + PeriodSeconds(PERIOD_CURRENT);
   
   string prefix = "ORB_M" + IntegerToString(id);
   DrawRay(prefix + "_High", t1, t2, maxHigh, col);
   DrawRay(prefix + "_Low", t1, t2, minLow, col);
  }

void DrawRay(string name, datetime t1, datetime t2, double price, color col)
  {
   if(ObjectFind(0, name) < 0) 
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
   else 
     {
      ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 1, price);
     }
     
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
  }

//+------------------------------------------------------------------+
//| Get the ORB Levels for the specific HTF selected to trade        |
//+------------------------------------------------------------------+
bool GetActiveORBLevels(double &outHigh, double &outLow)
  {
   ENUM_TIMEFRAMES  htf;
   int              shift;
   ENUM_ANCHOR_TYPE anchor;
   int              minRange;

   switch(InpTradeHTF)
     {
      case SEL_HTF_1: htf = InpHTF1_TF; shift = InpHTF1_Shift; anchor = InpHTF1_Anchor; minRange = InpHTF1_MinRange; break;
      case SEL_HTF_2: htf = InpHTF2_TF; shift = InpHTF2_Shift; anchor = InpHTF2_Anchor; minRange = InpHTF2_MinRange; break;
      case SEL_HTF_3: htf = InpHTF3_TF; shift = InpHTF3_Shift; anchor = InpHTF3_Anchor; minRange = InpHTF3_MinRange; break;
      case SEL_CTF:   htf = InpCTF_TF;  shift = InpCTF_Shift;  anchor = InpCTF_Anchor;  minRange = InpCTF_MinRange;  break;
      default: return false;
     }

   datetime htfTime = iTime(_Symbol, htf, shift);
   if(htfTime == 0) return false;

   datetime htfNextTime;
   if(shift == 0) htfNextTime = htfTime + PeriodSeconds(htf);
   else 
     {
      htfNextTime = iTime(_Symbol, htf, shift - 1);
      if(htfNextTime == 0) htfNextTime = htfTime + PeriodSeconds(htf);
     }
   
   datetime endSearchTime = htfNextTime - 1; 
   int ltfStartIdx = iBarShift(_Symbol, PERIOD_CURRENT, htfTime, false);
   int ltfEndIdx   = iBarShift(_Symbol, PERIOD_CURRENT, endSearchTime, false);
   
   if(ltfStartIdx < 0 || ltfEndIdx < 0) return false;

   int currentTfMinutes = PeriodSeconds(PERIOD_CURRENT) / 60;
   if(currentTfMinutes <= 0) currentTfMinutes = 1;
   
   int numBars = minRange / currentTfMinutes;
   if(numBars < 1) numBars = 1;

   int evalOldestIdx = 0;
   int evalNewestIdx = 0;

   if(anchor == ANCHOR_START) 
     {
      evalOldestIdx = ltfStartIdx;
      evalNewestIdx = MathMax(ltfStartIdx - numBars + 1, ltfEndIdx);
     } 
   else 
     {
      evalNewestIdx = ltfEndIdx;
      evalOldestIdx = MathMin(ltfEndIdx + numBars - 1, ltfStartIdx);
     }

   int totalBars = iBars(_Symbol, PERIOD_CURRENT);
   if(evalOldestIdx >= totalBars) evalOldestIdx = totalBars - 1;
   if(evalNewestIdx < 0) evalNewestIdx = 0;

   outHigh = -DBL_MAX;
   outLow  = DBL_MAX;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int count = evalOldestIdx - evalNewestIdx + 1;
   
   if(CopyRates(_Symbol, PERIOD_CURRENT, evalNewestIdx, count, rates) > 0)
     {
      for(int i = 0; i < ArraySize(rates); i++) 
        {
         if(rates[i].high > outHigh) outHigh = rates[i].high;
         if(rates[i].low < outLow)   outLow  = rates[i].low;
        }
     }

   return (outHigh != -DBL_MAX && outLow != DBL_MAX);
  }

//+------------------------------------------------------------------+
//| Cleanup graphics mapped to this EA                               |
//+------------------------------------------------------------------+
void ClearObjects()
  {
   int obj_total = ObjectsTotal(0, 0, -1);
   for(int i = obj_total - 1; i >= 0; i--) 
     {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, "ORB_") == 0) ObjectDelete(0, name);
     }
  }