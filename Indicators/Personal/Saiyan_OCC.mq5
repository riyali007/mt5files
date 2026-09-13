//+------------------------------------------------------------------+
//|                                                   Saiyan_OCC.mq5 |
//|                                           MQL5 Developer Version |
//+------------------------------------------------------------------+
#property copyright "MQL5 Developer"
#property link      ""
#property version   "1.01"
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   0  // Silent buffers, no standard lines

//--- Enums matching Pine Script MA Types
enum ENUM_CUSTOM_MA_TYPE
  {
   MA_TEMA = 0, // TEMA
   MA_HULL = 1, // HullMA
   MA_ALMA = 2, // ALMA
   MA_EMA  = 3, // EMA
   MA_SMA  = 4  // SMA
  };

//--- Input parameters
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M15;          // Alternate Signal Timeframe
input bool            InpUseRes = true;                   // Use Alternate Signals
input ENUM_CUSTOM_MA_TYPE InpBasisType = MA_ALMA;         // MA Type
input int             InpBasisLen = 2;                    // MA Period
input int             InpOffsetSigma = 5;                 // Offset for LSMA / Sigma for ALMA
input double          InpOffsetALMA = 0.85;               // Offset for ALMA
input int             InpDelayOffset = 0;                 // Delay Open/Close MA
input int             InpSwingLength = 10;                // Swing High/Low Length
input double          InpBoxWidth = 2.5;                  // Supply/Demand Box Width
input double          InpATRPeriod = 50;                  // ATR Period for Zones
input double          InpLvlTP1 = 1.0;                    // Level TP1 (%)
input double          InpLvlSL = 0.5;                     // Stop Loss (%)

//--- Indicator buffers (Silently calculating for the EA)
double         BuyBuffer[];
double         SellBuffer[];
double         CloseMABuffer[];
double         OpenMABuffer[];
double         TP1Buffer[];
double         SLBuffer[];

//--- Global variables for calculation
int            atrHandle;
double         atrBuffer[];
string         prefix = "Saiyan_";

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, BuyBuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(1, SellBuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(2, CloseMABuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(3, OpenMABuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(4, TP1Buffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(5, SLBuffer, INDICATOR_CALCULATIONS);
   
   ArraySetAsSeries(atrBuffer, true);
   ArraySetAsSeries(BuyBuffer, true);
   ArraySetAsSeries(SellBuffer, true);
   ArraySetAsSeries(CloseMABuffer, true);
   ArraySetAsSeries(OpenMABuffer, true);

   atrHandle = iATR(_Symbol, _Period, (int)InpATRPeriod);
   if(atrHandle == INVALID_HANDLE)
     {
      Print("Failed to create ATR handle");
      return(INIT_FAILED);
     }
     
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, prefix);
  }

//+------------------------------------------------------------------+
//| Custom ALMA Calculation Function                                 |
//+------------------------------------------------------------------+
double CalculateALMA(int index, int len, double offset, int sigma, const double &price[])
  {
   if(sigma <= 0) sigma = 1; // Prevent divide by zero
   double m = MathFloor(offset * (len - 1));
   double s = len / (double)sigma;
   double alma = 0.0;
   double wSum = 0.0;
   
   for(int i = 0; i < len; i++)
     {
      if(index + (len - 1 - i) >= ArraySize(price)) return 0.0;
      double w = MathExp(-(MathPow(i - m, 2)) / (2 * MathPow(s, 2)));
      // Reverse index mapping so newest bar gets correct offset weight
      alma += price[index + (len - 1 - i)] * w;
      wSum += w;
     }
   return (wSum != 0) ? (alma / wSum) : 0.0;
  }

//+------------------------------------------------------------------+
//| Helper: Draw Supply and Demand Zones (Outlines Only)             |
//+------------------------------------------------------------------+
void DrawZone(string name, datetime t1, double p1, datetime t2, double p2, color zoneColor)
  {
   string objName = prefix + name;
   if(ObjectFind(0, objName) < 0)
     {
      ObjectCreate(0, objName, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, objName, OBJPROP_COLOR, zoneColor);
      ObjectSetInteger(0, objName, OBJPROP_BACK, false);
      ObjectSetInteger(0, objName, OBJPROP_FILL, false);
     }
  }

//+------------------------------------------------------------------+
//| Helper: Draw Trade Fill Zone (Green for TP, Red for SL)          |
//+------------------------------------------------------------------+
void DrawTradeZone(string name, datetime t1, double p1, datetime t2, double p2, color clr)
  {
   string objName = prefix + name;
   if(ObjectFind(0, objName) < 0)
     {
      ObjectCreate(0, objName, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, objName, OBJPROP_BACK, true); 
      ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, objName, OBJPROP_FILL, true);
     }
   else
     {
      ObjectSetInteger(0, objName, OBJPROP_TIME, 1, t2);
     }
  }

//+------------------------------------------------------------------+
//| Helper: Draw Active Trade Levels with Text Labels                |
//+------------------------------------------------------------------+
void DrawTradeLevel(string name, datetime t1, double price, datetime t2, color clr, string labelText)
  {
   string lineName = prefix + name + "_line";
   if(ObjectFind(0, lineName) < 0)
     {
      ObjectCreate(0, lineName, OBJ_TREND, 0, t1, price, t2, price);
      ObjectSetInteger(0, lineName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false);
     }
   else
     {
      ObjectSetInteger(0, lineName, OBJPROP_TIME, 1, t2);
     }

   string tagName = prefix + name + "_tag";
   if(ObjectFind(0, tagName) < 0)
     {
      ObjectCreate(0, tagName, OBJ_TEXT, 0, t2, price);
      ObjectSetString(0, tagName, OBJPROP_TEXT, labelText + ": " + DoubleToString(price, _Digits));
      ObjectSetInteger(0, tagName, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, tagName, OBJPROP_BGCOLOR, clr);
      ObjectSetInteger(0, tagName, OBJPROP_ANCHOR, ANCHOR_LEFT);
     }
   else
     {
      ObjectSetInteger(0, tagName, OBJPROP_TIME, 0, t2);
     }
  }

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total < MathMax(InpBasisLen + InpDelayOffset, InpSwingLength * 2))
      return(0);

   ArraySetAsSeries(close, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(time, true);

   int copied = CopyBuffer(atrHandle, 0, 0, rates_total, atrBuffer);
   if(copied <= 0) return 0; // Prevent crash if ATR data isn't ready
   
   int limit = rates_total - prev_calculated;
   if(limit <= 0) limit = 1;

   // Safely bind the loop limit so we never ask for data that doesn't exist yet
   int start_i = limit - 1;
   if(start_i >= copied) start_i = copied - 1;
   if(start_i >= rates_total - InpBasisLen - InpDelayOffset) start_i = rates_total - InpBasisLen - InpDelayOffset - 1;

   for(int i = start_i; i >= 0; i--)
     {
      int delayedIdx = i + InpDelayOffset;

      if(InpBasisType == MA_ALMA)
        {
         CloseMABuffer[i] = CalculateALMA(delayedIdx, InpBasisLen, InpOffsetALMA, InpOffsetSigma, close);
         OpenMABuffer[i] = CalculateALMA(delayedIdx, InpBasisLen, InpOffsetALMA, InpOffsetSigma, open);
        }
      else if(InpBasisType == MA_SMA)
        {
         double sumC = 0, sumO = 0;
         for(int j=0; j<InpBasisLen; j++) { sumC+=close[delayedIdx+j]; sumO+=open[delayedIdx+j]; }
         CloseMABuffer[i] = sumC/InpBasisLen;
         OpenMABuffer[i] = sumO/InpBasisLen;
        }

      BuyBuffer[i] = 0.0;
      SellBuffer[i] = 0.0;
      TP1Buffer[i] = 0.0;
      SLBuffer[i] = 0.0;

      if(i < rates_total - 1)
        {
         // MQL5 Series means i+1 is the older bar. This correctly translates close > open AND close[1] <= open[1]
         bool leTrigger = (CloseMABuffer[i] > OpenMABuffer[i]) && (CloseMABuffer[i+1] <= OpenMABuffer[i+1]);
         bool seTrigger = (CloseMABuffer[i] < OpenMABuffer[i]) && (CloseMABuffer[i+1] >= OpenMABuffer[i+1]);

         datetime rightTime = (i > 30) ? time[i - 30] : time[0] + (PeriodSeconds() * 10);

         if(leTrigger)
           {
            BuyBuffer[i] = close[i];
            double slPrice = close[i] - (close[i] * (InpLvlSL / 100.0));
            double tp1Price = close[i] + (close[i] * (InpLvlTP1 / 100.0));
            
            TP1Buffer[i] = tp1Price;
            SLBuffer[i] = slPrice;
            
            string tradeID = "Long_" + IntegerToString(time[i]);
            DrawTradeZone(tradeID + "_TPZone", time[i], close[i], rightTime, tp1Price, clrDarkGreen);
            DrawTradeZone(tradeID + "_SLZone", time[i], close[i], rightTime, slPrice, clrMaroon);
            DrawTradeLevel(tradeID + "_Entry", time[i], close[i], rightTime, clrBlue, "Entry");
            DrawTradeLevel(tradeID + "_TP1", time[i], tp1Price, rightTime, clrGreen, "TP1");
            DrawTradeLevel(tradeID + "_SL", time[i], slPrice, rightTime, clrRed, "SL");
           }
           
         if(seTrigger)
           {
            SellBuffer[i] = close[i];
            double slPrice = close[i] + (close[i] * (InpLvlSL / 100.0));
            double tp1Price = close[i] - (close[i] * (InpLvlTP1 / 100.0));
            
            TP1Buffer[i] = tp1Price;
            SLBuffer[i] = slPrice;
            
            string tradeID = "Short_" + IntegerToString(time[i]);
            DrawTradeZone(tradeID + "_TPZone", time[i], close[i], rightTime, tp1Price, clrDarkGreen);
            DrawTradeZone(tradeID + "_SLZone", time[i], close[i], rightTime, slPrice, clrMaroon);
            DrawTradeLevel(tradeID + "_Entry", time[i], close[i], rightTime, clrBlue, "Entry");
            DrawTradeLevel(tradeID + "_TP1", time[i], tp1Price, rightTime, clrGreen, "TP1");
            DrawTradeLevel(tradeID + "_SL", time[i], slPrice, rightTime, clrRed, "SL");
           }
        }
        
      if (i > InpSwingLength && i < rates_total - InpSwingLength)
        {
         bool isPivotHigh = true;
         bool isPivotLow = true;
         for(int k = 1; k <= InpSwingLength; k++)
           {
            if(high[i] <= high[i+k] || high[i] <= high[i-k]) isPivotHigh = false;
            if(low[i] >= low[i+k] || low[i] >= low[i-k]) isPivotLow = false;
           }
           
         datetime boxEndTime = (i >= 60) ? time[i - 60] : time[0];
           
         if(isPivotHigh)
           {
            double atr_buffer = atrBuffer[i] * (InpBoxWidth / 10.0);
            DrawZone("Supply_" + IntegerToString(time[i]), time[i], high[i], boxEndTime, high[i] - atr_buffer, clrDarkRed);
           }
         if(isPivotLow)
           {
            double atr_buffer = atrBuffer[i] * (InpBoxWidth / 10.0);
            DrawZone("Demand_" + IntegerToString(time[i]), time[i], low[i] + atr_buffer, boxEndTime, low[i], clrDarkGreen);
           }
        }
     }
   return(rates_total);
  }
//+------------------------------------------------------------------+