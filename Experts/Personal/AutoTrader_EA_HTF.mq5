//+------------------------------------------------------------------+
//|                                Auto_EA_SMC_Pivot_CHoCH_v1.50.mq5 |
//+------------------------------------------------------------------+
#property copyright "Senior Trading Systems Architect"
#property link      ""
#property version   "1.50"

#include <Trade\Trade.mqh>

//--- Core Inputs
input ENUM_TIMEFRAMES InpHTF = PERIOD_H1;         // SMC Higher Timeframe (HTF)
input double          InpLotSize = 0.1;           // Lot Size
input ulong           InpMagicNumber = 777888;    // Magic Number

//--- Pivot Settings
sinput string         Pivot_Settings = "--- Pivot Settings ---";
input int             InpPivotLeft = 3;           // Pivot Left Strength (Older bars)
input int             InpPivotRight = 2;          // Pivot Right Strength (Newer bars)

//--- SMC Execution Settings
sinput string         Execution_Settings = "--- Execution Options ---";
enum ENUM_ENTRY_TYPE {
   ENTRY_LIMIT,      // 1. Pending Limit at POI Edge
   ENTRY_REJECTION   // 2. Market Order on LTF Rejection inside POI
};
input ENUM_ENTRY_TYPE InpEntryType = ENTRY_LIMIT; // Entry Trigger Method

//--- Risk Management Settings
sinput string         Risk_Settings = "--- Risk Management ---";
enum ENUM_SL_TYPE {
   SL_SWEEP,         // Structural SL (Behind Sweep Extreme)
   SL_POINTS         // Fixed Points SL
};
input ENUM_SL_TYPE    InpSLType = SL_SWEEP;       // Stop Loss Type
input int             InpSLPoints = 100;          // Fixed SL in Points (if SL_POINTS selected)
input double          InpRR_Ratio = 3.0;          // Full Risk:Reward Ratio (Final TP Target)

//--- Advanced Trade Management
sinput string         TM_Settings = "--- Advanced Trade Management ---";
input bool            InpUseAdvancedTM = true;        // Enable Partials & Trailing Stop
input int             InpNumPartials = 3;             // Number of Partial Levels (Divides Full TP)
input double          InpPartial_Close_Pct = 25.0;    // % of Initial Lot to Close per Partial
input int             InpMoveBE_AfterPartial = 1;     // Move SL to BE after Partial #
input int             InpStartTrail_AfterPartial = 2; // Start Trailing & Remove TP after Partial #
input double          InpTrailingDistancePoints = 100;// Trailing Distance (Points)
input double          InpTrailingStepPoints = 20;     // Trailing Step (Points)
input bool            InpShowPartialLines = true;     // Show Target Lines on Chart

//--- Visual Settings
sinput string         Visual_Settings = "--- Visual Settings ---";
input bool            InpShowVisuals = true;      // Draw Sweep, CHoCH, POI, and RR Boxes
input color           ClrSweepLine = clrWhite;    // Liquidity Sweep Line Color
input color           ClrChochLine = clrYellow;   // CHoCH Pivot Line Color
input color           ClrPOI = clrDarkSlateBlue;  // iFVG / Engulfing Box Color
input color           ClrRisk = clrMaroon;        // SL Box Color
input color           ClrReward = clrDarkGreen;   // TP Box Color

//--- Global Variables
CTrade         trade;
datetime       lastHTFBarTime = 0;

// Struct to hold active SMC Setup
struct SMC_Setup {
   bool     isActive;
   int      type;             // POSITION_TYPE_BUY or POSITION_TYPE_SELL
   datetime setupTime;        
   
   double   sweepPrice;       // The extreme sweep
   double   poiTop;           // Top of the POI (iFVG/Engulfing)
   double   poiBottom;        // Bottom of the POI
   string   poiType;          // "iFVG" or "Engulfing"
   
   bool     limitPlaced;      // Has a limit order been placed?
};
SMC_Setup currentSetup;

// State Struct for Position Management (Partials/Trailing)
struct PositionState {
   ulong  pos_id;
   int    partials_taken;
   double initial_lot;
   double entry_price;
   double risk;         
   int    type;         
   bool   trailing_active;
};
PositionState states[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);
   lastHTFBarTime = iTime(_Symbol, InpHTF, 0);
   currentSetup.isActive = false;
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, "SMC_");
   ObjectsDeleteAll(0, "Partial_");
  }

//+------------------------------------------------------------------+
//| Pivot Detection Functions                                        |
//+------------------------------------------------------------------+
bool IsPivotHigh(MqlRates &r[], int index, int left, int right)
  {
   if(index < right || index >= ArraySize(r) - left) return false;
   double val = r[index].high;
   for(int i = 1; i <= right; i++) if(r[index - i].high >= val) return false;
   for(int i = 1; i <= left; i++) if(r[index + i].high >= val) return false;
   return true;
  }

bool IsPivotLow(MqlRates &r[], int index, int left, int right)
  {
   if(index < right || index >= ArraySize(r) - left) return false;
   double val = r[index].low;
   for(int i = 1; i <= right; i++) if(r[index - i].low <= val) return false;
   for(int i = 1; i <= left; i++) if(r[index + i].low <= val) return false;
   return true;
  }

int GetHighestIndex(MqlRates &r[], int start, int count)
  {
   int maxIdx = start;
   for(int i = start; i < start + count && i < ArraySize(r); i++)
      if(r[i].high > r[maxIdx].high) maxIdx = i;
   return maxIdx;
  }

int GetLowestIndex(MqlRates &r[], int start, int count)
  {
   int minIdx = start;
   for(int i = start; i < start + count && i < ArraySize(r); i++)
      if(r[i].low < r[minIdx].low) minIdx = i;
   return minIdx;
  }

//+------------------------------------------------------------------+
//| Visual Drawing Helpers                                           |
//+------------------------------------------------------------------+
void DrawLine(string label, datetime time1, double price, color clr, string text)
  {
   if(!InpShowVisuals) return;
   string name = "SMC_" + label + "_" + IntegerToString(time1);
   ObjectCreate(0, name, OBJ_TREND, 0, time1, price, TimeCurrent() + PeriodSeconds(InpHTF)*10, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
  }

void DrawPOIBox(datetime time1, double top, double bottom, string text)
  {
   if(!InpShowVisuals) return;
   string name = "SMC_POI_" + IntegerToString(time1);
   ObjectCreate(0, name, OBJ_RECTANGLE, 0, time1, top, TimeCurrent() + PeriodSeconds(InpHTF)*15, bottom);
   ObjectSetInteger(0, name, OBJPROP_COLOR, ClrPOI);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
  }

void DrawRRBox(datetime time1, double entry, double sl, double tp, int type)
  {
   if(!InpShowVisuals) return;
   string riskName = "SMC_Risk_" + IntegerToString(time1);
   string rewardName = "SMC_Reward_" + IntegerToString(time1);
   datetime time2 = TimeCurrent() + PeriodSeconds(InpHTF)*15;
   
   ObjectCreate(0, riskName, OBJ_RECTANGLE, 0, time1, sl, time2, entry);
   ObjectSetInteger(0, riskName, OBJPROP_COLOR, ClrRisk);
   ObjectSetInteger(0, riskName, OBJPROP_FILL, true);
   ObjectSetInteger(0, riskName, OBJPROP_BACK, true);
   
   ObjectCreate(0, rewardName, OBJ_RECTANGLE, 0, time1, entry, time2, tp);
   ObjectSetInteger(0, rewardName, OBJPROP_COLOR, ClrReward);
   ObjectSetInteger(0, rewardName, OBJPROP_FILL, true);
   ObjectSetInteger(0, rewardName, OBJPROP_BACK, true);
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

void DrawTradeLevels(ulong pos_id, int type, double entry, double risk)
  {
   if(!InpShowPartialLines || risk <= 0 || !InpUseAdvancedTM) return;
   
   // Divide the Full TP (InpRR_Ratio) into equidistant partial levels.
   // E.g., if Full TP = 3.0 and Partials = 2, then Step = 1.0 (TP1=1R, TP2=2R, Final=3R)
   double stepRR = InpRR_Ratio / (InpNumPartials + 1.0);
   
   for(int i = 1; i <= InpNumPartials; i++)
     {
      double target_R = i * stepRR;
      double price = (type == POSITION_TYPE_BUY) ? (entry + (risk * target_R)) : (entry - (risk * target_R));
      
      string name = "Partial_" + IntegerToString(pos_id) + "_TP" + IntegerToString(i);
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, (type == POSITION_TYPE_BUY) ? clrMediumSeaGreen : clrIndianRed);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASHDOT);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetString(0, name, OBJPROP_TEXT, "TP" + IntegerToString(i) + " (" + DoubleToString(target_R, 2) + "R)");
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
     }
  }

void CleanupTradeLevels(ulong pos_id)
  {
   for(int i = 1; i <= InpNumPartials; i++)
      ObjectDelete(0, "Partial_" + IntegerToString(pos_id) + "_TP" + IntegerToString(i));
  }

void SyncStates()
  {
   if(!InpUseAdvancedTM) return;

   for(int i = ArraySize(states) - 1; i >= 0; i--)
     {
      if(!SelectPositionById(states[i].pos_id))
        {
         CleanupTradeLevels(states[i].pos_id);
         ArrayRemove(states, i, 1);
        }
     }
   
   for(int i=0; i<PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      ulong pos_id = PositionGetInteger(POSITION_IDENTIFIER);
      
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
        {
         bool found = false;
         for(int j=0; j<ArraySize(states); j++)
           {
            if(states[j].pos_id == pos_id) { found = true; break; }
           }
         
         if(!found)
           {
            int idx = ArraySize(states);
            ArrayResize(states, idx + 1);
            states[idx].pos_id = pos_id;
            states[idx].partials_taken = 0;
            states[idx].initial_lot = PositionGetDouble(POSITION_VOLUME);
            states[idx].entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
            states[idx].type = (int)PositionGetInteger(POSITION_TYPE);
            
            double sl = PositionGetDouble(POSITION_SL);
            states[idx].risk = MathAbs(states[idx].entry_price - sl);
            states[idx].trailing_active = false;
            
            DrawTradeLevels(states[idx].pos_id, states[idx].type, states[idx].entry_price, states[idx].risk);
           }
        }
     }
  }

void ManageTrades()
  {
   if(!InpUseAdvancedTM) return;

   for(int i=0; i<ArraySize(states); i++)
     {
      if(!SelectPositionById(states[i].pos_id)) continue;
      
      ulong ticket = PositionGetInteger(POSITION_TICKET);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double volume = PositionGetDouble(POSITION_VOLUME);
      
      if(states[i].risk <= 0) continue;
      
      double current_bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double current_ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double eval_price = (states[i].type == POSITION_TYPE_BUY) ? current_bid : current_ask;
      
      double profit_pts = (states[i].type == POSITION_TYPE_BUY) ? (eval_price - states[i].entry_price) : (states[i].entry_price - eval_price);
      double current_R = profit_pts / states[i].risk;
      
      // --- Evaluate Partials ---
      if(states[i].partials_taken < InpNumPartials)
        {
         double stepRR = InpRR_Ratio / (InpNumPartials + 1.0);
         double target_R = (states[i].partials_taken + 1) * stepRR;
         
         if(current_R >= target_R)
           {
            double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
            double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            
            double lot_to_close = states[i].initial_lot * (InpPartial_Close_Pct / 100.0);
            lot_to_close = MathFloor(lot_to_close / step) * step; 
            
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
            else states[i].partials_taken++;
            
            // Move to BE
            if(states[i].partials_taken == InpMoveBE_AfterPartial)
              {
               double be_price = states[i].entry_price;
               if(MathAbs(sl - be_price) > _Point)
                 {
                  if(states[i].type == POSITION_TYPE_BUY && sl < be_price)
                     trade.PositionModify(ticket, be_price, tp);
                  else if(states[i].type == POSITION_TYPE_SELL && (sl > be_price || sl == 0))
                     trade.PositionModify(ticket, be_price, tp);
                  sl = be_price; 
                 }
              }
            
            // Start Trailing
            if(states[i].partials_taken == InpStartTrail_AfterPartial)
              {
               states[i].trailing_active = true;
               if(tp != 0.0)
                 {
                  trade.PositionModify(ticket, sl, 0.0);
                  tp = 0.0; 
                 }
              }
           }
        }
      
      // --- Evaluate Trailing Stop ---
      if(states[i].trailing_active)
        {
         double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         double trail_dist = InpTrailingDistancePoints * point;
         double trail_step = InpTrailingStepPoints * point;
         
         if(states[i].type == POSITION_TYPE_BUY)
           {
            double new_sl = NormalizeDouble(current_bid - trail_dist, _Digits);
            if(sl == 0 || new_sl > sl + trail_step)
               trade.PositionModify(ticket, new_sl, tp);
           }
         else
           {
            double new_sl = NormalizeDouble(current_ask + trail_dist, _Digits);
            if(sl == 0 || new_sl < sl - trail_step)
               trade.PositionModify(ticket, new_sl, tp);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| POI Identification (iFVG & Engulfing)                            |
//+------------------------------------------------------------------+
bool FindBearishPOI(MqlRates &r[], int startIdx, int endIdx, double &top, double &bottom, string &poiName)
  {
   for(int i = startIdx - 1; i >= endIdx; i--)
     {
      if(r[i].close < r[i].open && r[i+1].close > r[i+1].open)
        {
         if(r[i].close < r[i+1].low && r[i].open > r[i+1].close)
           {
            top = r[i+1].high;
            bottom = r[i+1].low;
            poiName = "Engulfing";
            return true;
           }
        }
      
      if(i+2 <= startIdx)
        {
         double fvgBottom = r[i+2].high;
         double fvgTop = r[i].low;
         if(fvgTop > fvgBottom)
           {
            for(int j = i - 1; j >= endIdx; j--)
              {
               if(r[j].close < fvgBottom)
                 {
                  top = fvgTop;
                  bottom = fvgBottom;
                  poiName = "iFVG";
                  return true;
                 }
              }
           }
        }
     }
   return false;
  }

bool FindBullishPOI(MqlRates &r[], int startIdx, int endIdx, double &top, double &bottom, string &poiName)
  {
   for(int i = startIdx - 1; i >= endIdx; i--)
     {
      if(r[i].close > r[i].open && r[i+1].close < r[i+1].open)
        {
         if(r[i].close > r[i+1].high && r[i].open < r[i+1].close)
           {
            top = r[i+1].high;
            bottom = r[i+1].low;
            poiName = "Engulfing";
            return true;
           }
        }
      
      if(i+2 <= startIdx)
        {
         double fvgTop = r[i+2].low;
         double fvgBottom = r[i].high;
         if(fvgTop > fvgBottom)
           {
            for(int j = i - 1; j >= endIdx; j--)
              {
               if(r[j].close > fvgTop)
                 {
                  top = fvgTop;
                  bottom = fvgBottom;
                  poiName = "iFVG";
                  return true;
                 }
              }
           }
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Evaluate SMC Logic on HTF                                        |
//+------------------------------------------------------------------+
void EvaluateHTFSetup()
  {
   if(currentSetup.isActive) return;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   if(CopyRates(_Symbol, InpHTF, 0, 200, rates) != 200) return;

   int searchStart = InpPivotRight + 1;

   // ==========================================
   // BEARISH SETUP (SELL)
   // ==========================================
   for(int p = searchStart; p < 80; p++)
     {
      if(IsPivotLow(rates, p, InpPivotLeft, InpPivotRight))
        {
         if(rates[1].close < rates[p].low && rates[2].close > rates[p].low)
           {
            int highestIdx = GetHighestIndex(rates, 2, p - 2);
            
            bool swept = false;
            int sweptPivotIdx = -1;
            for(int ph = highestIdx + 1; ph < 180; ph++)
              {
               if(IsPivotHigh(rates, ph, InpPivotLeft, InpPivotRight))
                 {
                  if(rates[highestIdx].high > rates[ph].high)
                    {
                     swept = true;
                     sweptPivotIdx = ph;
                    }
                  break; 
                 }
              }
            
            if(swept)
              {
               double zoneTop = 0, zoneBottom = 0;
               string poiName = "";
               
               if(FindBearishPOI(rates, highestIdx, 1, zoneTop, zoneBottom, poiName))
                 {
                  currentSetup.isActive = true;
                  currentSetup.type = POSITION_TYPE_SELL;
                  currentSetup.setupTime = rates[1].time;
                  currentSetup.sweepPrice = rates[highestIdx].high;
                  currentSetup.poiTop = zoneTop;
                  currentSetup.poiBottom = zoneBottom;
                  currentSetup.poiType = poiName;
                  currentSetup.limitPlaced = false;

                  DrawLine("Sweep", rates[sweptPivotIdx].time, rates[sweptPivotIdx].high, ClrSweepLine, "Liquidity Sweep");
                  DrawLine("CHoCH", rates[p].time, rates[p].low, ClrChochLine, "CHoCH Pivot");
                  DrawPOIBox(rates[highestIdx].time, zoneTop, zoneBottom, poiName);
                  return;
                 }
              }
           }
        }
     }
     
   // ==========================================
   // BULLISH SETUP (BUY)
   // ==========================================
   for(int p = searchStart; p < 80; p++)
     {
      if(IsPivotHigh(rates, p, InpPivotLeft, InpPivotRight))
        {
         if(rates[1].close > rates[p].high && rates[2].close < rates[p].high)
           {
            int lowestIdx = GetLowestIndex(rates, 2, p - 2);
            
            bool swept = false;
            int sweptPivotIdx = -1;
            for(int pl = lowestIdx + 1; pl < 180; pl++)
              {
               if(IsPivotLow(rates, pl, InpPivotLeft, InpPivotRight))
                 {
                  if(rates[lowestIdx].low < rates[pl].low)
                    {
                     swept = true;
                     sweptPivotIdx = pl;
                    }
                  break; 
                 }
              }
            
            if(swept)
              {
               double zoneTop = 0, zoneBottom = 0;
               string poiName = "";
               
               if(FindBullishPOI(rates, lowestIdx, 1, zoneTop, zoneBottom, poiName))
                 {
                  currentSetup.isActive = true;
                  currentSetup.type = POSITION_TYPE_BUY;
                  currentSetup.setupTime = rates[1].time;
                  currentSetup.sweepPrice = rates[lowestIdx].low;
                  currentSetup.poiTop = zoneTop;
                  currentSetup.poiBottom = zoneBottom;
                  currentSetup.poiType = poiName;
                  currentSetup.limitPlaced = false;

                  DrawLine("Sweep", rates[sweptPivotIdx].time, rates[sweptPivotIdx].low, ClrSweepLine, "Liquidity Sweep");
                  DrawLine("CHoCH", rates[p].time, rates[p].high, ClrChochLine, "CHoCH Pivot");
                  DrawPOIBox(rates[lowestIdx].time, zoneTop, zoneBottom, poiName);
                  return;
                 }
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Helper: Calculate Stop Loss                                      |
//+------------------------------------------------------------------+
double CalculateStopLoss(double entryPrice, int type)
  {
   if(InpSLType == SL_SWEEP)
     {
      return currentSetup.sweepPrice;
     }
   else // SL_POINTS
     {
      if(type == POSITION_TYPE_SELL) return NormalizeDouble(entryPrice + (InpSLPoints * _Point), _Digits);
      else                           return NormalizeDouble(entryPrice - (InpSLPoints * _Point), _Digits);
     }
  }

//+------------------------------------------------------------------+
//| LTF Execution Monitor (Limit or Rejection)                       |
//+------------------------------------------------------------------+
void MonitorLTFExecution()
  {
   if(!currentSetup.isActive) return;
   
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   double intendedEntry = (currentSetup.type == POSITION_TYPE_SELL) ? currentSetup.poiBottom : currentSetup.poiTop;
   double intendedSL = CalculateStopLoss(intendedEntry, currentSetup.type);

   if(currentSetup.type == POSITION_TYPE_SELL && ask > intendedSL) { currentSetup.isActive = false; return; }
   if(currentSetup.type == POSITION_TYPE_BUY  && bid < intendedSL) { currentSetup.isActive = false; return; }

   if(PositionsTotal() > 0)
     {
      for(int i=0; i<PositionsTotal(); i++)
         if(PositionGetTicket(i) > 0 && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
           {
            currentSetup.isActive = false; 
            return;
           }
     }

   // Always use InpRR_Ratio as the final TP Target
   double final_RR_Target = InpRR_Ratio;

   // ==========================================
   // OPTION 1: ENTRY_LIMIT
   // ==========================================
   if(InpEntryType == ENTRY_LIMIT && !currentSetup.limitPlaced)
     {
      if(currentSetup.type == POSITION_TYPE_SELL)
        {
         double sl = intendedSL;
         double risk = sl - intendedEntry;
         double tp = intendedEntry - (risk * final_RR_Target);
         
         if(ask < intendedEntry) 
           {
            trade.SellLimit(InpLotSize, intendedEntry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "SMC Limit " + currentSetup.poiType);
            currentSetup.limitPlaced = true;
            DrawRRBox(TimeCurrent(), intendedEntry, sl, tp, POSITION_TYPE_SELL);
           }
        }
      else if(currentSetup.type == POSITION_TYPE_BUY)
        {
         double sl = intendedSL;
         double risk = intendedEntry - sl;
         double tp = intendedEntry + (risk * final_RR_Target);
         
         if(bid > intendedEntry) 
           {
            trade.BuyLimit(InpLotSize, intendedEntry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "SMC Limit " + currentSetup.poiType);
            currentSetup.limitPlaced = true;
            DrawRRBox(TimeCurrent(), intendedEntry, sl, tp, POSITION_TYPE_BUY);
           }
        }
     }
     
   // ==========================================
   // OPTION 2: ENTRY_REJECTION
   // ==========================================
   if(InpEntryType == ENTRY_REJECTION)
     {
      MqlRates ltf[];
      ArraySetAsSeries(ltf, true);
      if(CopyRates(_Symbol, PERIOD_CURRENT, 1, 1, ltf) != 1) return;
      
      if(currentSetup.type == POSITION_TYPE_SELL)
        {
         bool tappedZone = (ltf[0].high >= currentSetup.poiBottom);
         bool bearishClose = (ltf[0].close < ltf[0].open);
         bool validStructure = (ltf[0].close <= currentSetup.poiTop);
         
         if(tappedZone && bearishClose && validStructure)
           {
            double entry = bid;
            double sl = CalculateStopLoss(entry, POSITION_TYPE_SELL);
            double risk = sl - entry;
            double tp = entry - (risk * final_RR_Target);
            
            trade.Sell(InpLotSize, _Symbol, bid, sl, tp, "SMC Reject " + currentSetup.poiType);
            currentSetup.isActive = false; 
            DrawRRBox(ltf[0].time, entry, sl, tp, POSITION_TYPE_SELL);
           }
        }
      else if(currentSetup.type == POSITION_TYPE_BUY)
        {
         bool tappedZone = (ltf[0].low <= currentSetup.poiTop);
         bool bullishClose = (ltf[0].close > ltf[0].open);
         bool validStructure = (ltf[0].close >= currentSetup.poiBottom);
         
         if(tappedZone && bullishClose && validStructure)
           {
            double entry = bid;
            double sl = CalculateStopLoss(entry, POSITION_TYPE_BUY);
            double risk = entry - sl;
            double tp = entry + (risk * final_RR_Target);
            
            trade.Buy(InpLotSize, _Symbol, ask, sl, tp, "SMC Reject " + currentSetup.poiType);
            currentSetup.isActive = false; 
            DrawRRBox(ltf[0].time, entry, sl, tp, POSITION_TYPE_BUY);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   SyncStates();
   ManageTrades();
   MonitorLTFExecution();
   
   datetime currentHTFBarTime = iTime(_Symbol, InpHTF, 0);
   if(currentHTFBarTime != lastHTFBarTime)
     {
      lastHTFBarTime = currentHTFBarTime;
      EvaluateHTFSetup();
     }
  }
//+------------------------------------------------------------------+