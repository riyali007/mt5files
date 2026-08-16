//+------------------------------------------------------------------+
//|                                                   ORB_MultiTF.mq5|
//|                                      Helpful Assistant Developer |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//--- Enums
enum ENUM_ANCHOR_TYPE
  {
   ANCHOR_START=0, // Start of Candle
   ANCHOR_END=1    // End of Candle
  };

//--- Global Inputs
input group "=== Global Settings ==="
input double InpUTCOffset  = 0.0;  // Label Time Offset (Hours, e.g., +2.0 or -1.5)
input bool   InpShowLabels = true; // Show Labels (Time & High/Low)

//--- Module 1 Inputs
input group "=== Module 1 ==="
input bool             InpM1_Enable        = true;           // Enable Module 1
input ENUM_TIMEFRAMES  InpM1_HTF           = PERIOD_H1;      // Target HTF
input int              InpM1_Shift         = 1;              // HTF Candle Shift (0=Current, 1=Previous)
input ENUM_ANCHOR_TYPE InpM1_Anchor        = ANCHOR_START;   // Anchor Position
input int              InpM1_MinuteRange   = 5;              // Minute Range
input color            InpM1_Color         = clrDodgerBlue;  // High/Low Line Color
input ENUM_LINE_STYLE  InpM1_LineStyle     = STYLE_SOLID;    // High/Low Line Style
input bool             InpM1_ShowSpread    = true;           // Show Spread Lines
input color            InpM1_SpreadColor   = clrDeepSkyBlue; // Spread Lines Color
input ENUM_LINE_STYLE  InpM1_SpreadStyle   = STYLE_DOT;      // Spread Lines Style

//--- Module 2 Inputs
input group "=== Module 2 ==="
input bool             InpM2_Enable        = false;          // Enable Module 2
input ENUM_TIMEFRAMES  InpM2_HTF           = PERIOD_H4;      // Target HTF
input int              InpM2_Shift         = 1;              // HTF Candle Shift
input ENUM_ANCHOR_TYPE InpM2_Anchor        = ANCHOR_START;   // Anchor Position
input int              InpM2_MinuteRange   = 15;             // Minute Range
input color            InpM2_Color         = clrOrange;      // High/Low Line Color
input ENUM_LINE_STYLE  InpM2_LineStyle     = STYLE_DASH;     // High/Low Line Style
input bool             InpM2_ShowSpread    = false;          // Show Spread Lines
input color            InpM2_SpreadColor   = clrGold;        // Spread Lines Color
input ENUM_LINE_STYLE  InpM2_SpreadStyle   = STYLE_DOT;      // Spread Lines Style

//--- Module 3 Inputs
input group "=== Module 3 ==="
input bool             InpM3_Enable        = false;          // Enable Module 3
input ENUM_TIMEFRAMES  InpM3_HTF           = PERIOD_D1;      // Target HTF
input int              InpM3_Shift         = 1;              // HTF Candle Shift
input ENUM_ANCHOR_TYPE InpM3_Anchor        = ANCHOR_END;     // Anchor Position
input int              InpM3_MinuteRange   = 30;             // Minute Range
input color            InpM3_Color         = clrLimeGreen;   // High/Low Line Color
input ENUM_LINE_STYLE  InpM3_LineStyle     = STYLE_DOT;      // High/Low Line Style
input bool             InpM3_ShowSpread    = false;          // Show Spread Lines
input color            InpM3_SpreadColor   = clrYellowGreen; // Spread Lines Color
input ENUM_LINE_STYLE  InpM3_SpreadStyle   = STYLE_DOT;      // Spread Lines Style

//--- Module 4 (CTF) Inputs
input group "=== Module 4 (CTF) ==="
input bool             InpM4_Enable        = false;          // Enable Module 4 (CTF)
input ENUM_TIMEFRAMES  InpM4_TF            = PERIOD_CURRENT; // Target TF (CTF)
input int              InpM4_Shift         = 1;              // TF Candle Shift
input ENUM_ANCHOR_TYPE InpM4_Anchor        = ANCHOR_START;   // Anchor Position
input int              InpM4_MinuteRange   = 5;              // Minute Range
input color            InpM4_Color         = clrMagenta;     // High/Low Line Color
input ENUM_LINE_STYLE  InpM4_LineStyle     = STYLE_SOLID;    // High/Low Line Style
input bool             InpM4_ShowSpread    = false;          // Show Spread Lines
input color            InpM4_SpreadColor   = clrHotPink;     // Spread Lines Color
input ENUM_LINE_STYLE  InpM4_SpreadStyle   = STYLE_DOT;      // Spread Lines Style

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
   ClearObjects();
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ClearObjects();
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
   // Process all modules independently
   ProcessModule(1, InpM1_Enable, InpM1_HTF, InpM1_Shift, InpM1_Anchor, InpM1_MinuteRange, InpM1_Color, InpM1_LineStyle, InpM1_ShowSpread, InpM1_SpreadColor, InpM1_SpreadStyle);
   ProcessModule(2, InpM2_Enable, InpM2_HTF, InpM2_Shift, InpM2_Anchor, InpM2_MinuteRange, InpM2_Color, InpM2_LineStyle, InpM2_ShowSpread, InpM2_SpreadColor, InpM2_SpreadStyle);
   ProcessModule(3, InpM3_Enable, InpM3_HTF, InpM3_Shift, InpM3_Anchor, InpM3_MinuteRange, InpM3_Color, InpM3_LineStyle, InpM3_ShowSpread, InpM3_SpreadColor, InpM3_SpreadStyle);
   ProcessModule(4, InpM4_Enable, InpM4_TF,  InpM4_Shift, InpM4_Anchor, InpM4_MinuteRange, InpM4_Color, InpM4_LineStyle, InpM4_ShowSpread, InpM4_SpreadColor, InpM4_SpreadStyle);
   
   return(rates_total);
  }

//+------------------------------------------------------------------+
//| Core Logic for Isolating and Plotting specific ORB ranges        |
//+------------------------------------------------------------------+
void ProcessModule(int id, bool enable, ENUM_TIMEFRAMES htf, int shift, ENUM_ANCHOR_TYPE anchor, int minRange, color col, ENUM_LINE_STYLE style, bool showSpread, color spreadCol, ENUM_LINE_STYLE spreadStyle)
  {
   if(!enable) return;

   // 1. Target HTF Candle times
   datetime htfTime = iTime(_Symbol, htf, shift);
   if(htfTime == 0) return; // Not enough history

   datetime htfNextTime;
   if(shift == 0) 
     {
      htfNextTime = htfTime + PeriodSeconds(htf);
     } 
   else 
     {
      htfNextTime = iTime(_Symbol, htf, shift - 1);
      if(htfNextTime == 0) htfNextTime = htfTime + PeriodSeconds(htf);
     }
   
   // Exact ending moment of the target HTF candle
   datetime endSearchTime = htfNextTime - 1; 

   // 2. Map HTF constraints to specific LTF Bar Indexes
   int ltfStartIdx = iBarShift(_Symbol, PERIOD_CURRENT, htfTime, false);
   int ltfEndIdx   = iBarShift(_Symbol, PERIOD_CURRENT, endSearchTime, false);
   
   if(ltfStartIdx < 0 || ltfEndIdx < 0) return;

   // 3. Convert minutes to LTF bars
   int currentTfMinutes = PeriodSeconds(PERIOD_CURRENT) / 60;
   if(currentTfMinutes <= 0) currentTfMinutes = 1;
   
   int numBars = minRange / currentTfMinutes;
   if(numBars < 1) numBars = 1;

   // 4. Determine subset bound indexes (0 is current/newest bar in MT5 arrays)
   int evalOldestIdx = 0;
   int evalNewestIdx = 0;

   if(anchor == ANCHOR_START) 
     {
      evalOldestIdx = ltfStartIdx;
      evalNewestIdx = MathMax(ltfStartIdx - numBars + 1, ltfEndIdx); // Clamp to prevent bleeding into next HTF candle
     } 
   else 
     {
      evalNewestIdx = ltfEndIdx;
      evalOldestIdx = MathMin(ltfEndIdx + numBars - 1, ltfStartIdx); // Clamp to prevent bleeding into prev HTF candle
     }

   // Failsafe array checks
   int totalBars = iBars(_Symbol, PERIOD_CURRENT);
   if(evalOldestIdx >= totalBars) evalOldestIdx = totalBars - 1;
   if(evalNewestIdx < 0) evalNewestIdx = 0;

   // 5. Extract strict Highest High & Lowest Low along with their corresponding spread offsets
   double maxHigh = -DBL_MAX;
   double minLow  = DBL_MAX;
   double highSpread = 0.0;
   double lowSpread = 0.0;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int count = evalOldestIdx - evalNewestIdx + 1;
   
   if(CopyRates(_Symbol, PERIOD_CURRENT, evalNewestIdx, count, rates) > 0)
     {
      for(int i = 0; i < ArraySize(rates); i++) 
        {
         double h = rates[i].high;
         double l = rates[i].low;
           
         if(h > maxHigh) 
           {
            maxHigh = h;
            highSpread = rates[i].spread * _Point;
           }
         if(l < minLow)  
           {
            minLow = l;
            lowSpread = rates[i].spread * _Point;
           }
        }
     }

   if(maxHigh == -DBL_MAX || minLow == DBL_MAX) return;

   // 6. Format time outputs based on evaluated LTF boundaries
   datetime t1 = iTime(_Symbol, PERIOD_CURRENT, evalOldestIdx);
   datetime t2 = iTime(_Symbol, PERIOD_CURRENT, evalNewestIdx) + PeriodSeconds(PERIOD_CURRENT);

   long offsetSeconds = (long)(InpUTCOffset * 3600);
   datetime label_t1 = (datetime)((long)t1 + offsetSeconds);
   datetime label_t2 = (datetime)((long)t2 + offsetSeconds);

   string timeStr = TimeToString(label_t1, TIME_MINUTES) + "-" + TimeToString(label_t2, TIME_MINUTES);

   // 7. Render lines and labels
   string prefix = "ORBM_" + IntegerToString(id);
   
   // High & Low Core Lines
   DrawRay(prefix + "_High", t1, maxHigh, col, style);
   DrawRay(prefix + "_Low", t1, minLow, col, style);
   
   // Labels logic controlled by InpShowLabels global variable
   if(InpShowLabels)
     {
      DrawLabel(prefix + "_HighLbl", t1, maxHigh, timeStr + " (High)", col, ANCHOR_LEFT_LOWER);
      DrawLabel(prefix + "_LowLbl", t1, minLow, timeStr + " (Low)", col, ANCHOR_LEFT_UPPER);
     }
   else
     {
      ObjectDelete(0, prefix + "_HighLbl");
      ObjectDelete(0, prefix + "_LowLbl");
     }

   // Spread Boundary Lines
   if(showSpread)
     {
      DrawRay(prefix + "_HighSpread", t1, maxHigh + highSpread, spreadCol, spreadStyle);
      DrawRay(prefix + "_LowSpread", t1, minLow - lowSpread, spreadCol, spreadStyle);
     }
   else
     {
      ObjectDelete(0, prefix + "_HighSpread");
      ObjectDelete(0, prefix + "_LowSpread");
     }
  }

//+------------------------------------------------------------------+
//| Helper: Draws or Updates a Horizontal Ray                        |
//+------------------------------------------------------------------+
void DrawRay(string name, datetime t1, double price, color col, ENUM_LINE_STYLE style)
  {
   datetime t2 = t1 + PeriodSeconds(PERIOD_CURRENT); // Secondary coordinate for vector
   
   if(ObjectFind(0, name) < 0) 
     {
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
     } 
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
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

//+------------------------------------------------------------------+
//| Helper: Draws or Updates Floating Text Object                    |
//+------------------------------------------------------------------+
void DrawLabel(string name, datetime t1, double price, string text, color col, ENUM_ANCHOR_POINT anchor)
  {
   if(ObjectFind(0, name) < 0) 
     {
      ObjectCreate(0, name, OBJ_TEXT, 0, t1, price);
     } 
   else 
     {
      ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
     }
     
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

//+------------------------------------------------------------------+
//| Cleanup graphics mapped to this indicator                        |
//+------------------------------------------------------------------+
void ClearObjects()
  {
   int obj_total = ObjectsTotal(0, 0, -1);
   for(int i = obj_total - 1; i >= 0; i--) 
     {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, "ORBM_") == 0) 
        {
         ObjectDelete(0, name);
        }
     }
  }
//+------------------------------------------------------------------+