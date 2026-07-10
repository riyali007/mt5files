//+------------------------------------------------------------------+
//|                                          HTF_Fibonacci_Wicks.mq5 |
//|                                  Converted from Pine Script v5   |
//+------------------------------------------------------------------+
#property copyright "Converted by AI"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 0     // Increased to 9 for Dummy Buffer
#property indicator_plots   0      // CHANGED: 0 -> 1 to fix Error 539
#property indicator_type1   DRAW_NONE
// =============================================================================
// --- INPUTS ---
// =============================================================================

input group "Timeframe Settings"
input ENUM_TIMEFRAMES InpFibTF = PERIOD_H1; // Fibonacci Timeframe
input int      InpCandleBack   = 1;         // Candle Back (1=Previous, 2=2 Candles Back...)
input int      InpXOffset      = 0;         // X Offset (Minutes)

input group "Fibonacci Levels (Upper/Lower)"
// Level 1
input bool     InpL1_On        = true;      // Level 1 On
input double   InpL1_Val       = 0.0;       // Level 1 Value
input color    InpL1_Col       = clrGray;   // Level 1 Color
// Level 2
input bool     InpL2_On        = true;      // Level 2 On
input double   InpL2_Val       = 0.236;     // Level 2 Value
input color    InpL2_Col       = clrRed;    // Level 2 Color
// Level 3
input bool     InpL3_On        = true;      // Level 3 On
input double   InpL3_Val       = 0.382;     // Level 3 Value
input color    InpL3_Col       = clrOrange; // Level 3 Color
// Level 4
input bool     InpL4_On        = true;      // Level 4 On
input double   InpL4_Val       = 0.5;       // Level 4 Value
input color    InpL4_Col       = clrYellow; // Level 4 Color
// Level 5
input bool     InpL5_On        = true;      // Level 5 On
input double   InpL5_Val       = 0.618;     // Level 5 Value
input color    InpL5_Col       = clrGreen;  // Level 5 Color
// Level 6
input bool     InpL6_On        = true;      // Level 6 On
input double   InpL6_Val       = 0.786;     // Level 6 Value
input color    InpL6_Col       = clrBlue;   // Level 6 Color
// Level 7
input bool     InpL7_On        = true;      // Level 7 On
input double   InpL7_Val       = 1.0;       // Level 7 Value
input color    InpL7_Col       = clrGray;   // Level 7 Color
// Level 8
input bool     InpL8_On        = true;      // Level 8 On
input double   InpL8_Val       = 1.618;     // Level 8 Value
input color    InpL8_Col       = clrPurple; // Level 8 Color

input group "Visual Settings"
input int      InpLineWidth    = 1;         // Line Width
input ENUM_LINE_STYLE InpLineStyle = STYLE_SOLID; // Line Style
input bool     InpShowLabels   = true;      // Show Labels
input bool     InpShowPrices   = true;      // Show Prices

// =============================================================================
// --- GLOBALS ---
// =============================================================================
long  last_htf_time = 0;
string prefix = "HFW_"; // Object prefix

// =============================================================================
// --- HELPER FUNCTIONS ---
// =============================================================================

// Function to draw line
void DrawLine(string name, datetime t1, double p1, datetime t2, double p2, color col)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_STYLE, InpLineStyle);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, InpLineWidth);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true); // Extend right like Pine's extend.right
}

// Function to draw label
void DrawLabel(string name, datetime t, double p, string txt, color col)
{
   ObjectDelete(0, name);
   if(!InpShowLabels) return;
   
   ObjectCreate(0, name, OBJ_TEXT, 0, t, p);
   ObjectSetString(0, name, OBJPROP_TEXT, "  " + txt); // Add padding
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
}

// =============================================================================
// --- MAIN FUNCTIONS ---
// =============================================================================

int OnInit()
{
   // Cleanup old objects on init
   ObjectsDeleteAll(0, prefix);
   ChartRedraw();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   // Cleanup on remove
   ObjectsDeleteAll(0, prefix);
   ChartRedraw();
}

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
   // Only run calculation on new bar or first run
   if(prev_calculated == rates_total) return(rates_total);

   // Get HTF Data
   // We use iTime to get the opening time of the requested bar
   datetime htf_t = iTime(Symbol(), InpFibTF, 0); 
   
   // Check if we have a new HTF bar
   if(htf_t != last_htf_time)
   {
      last_htf_time = (long)htf_t;
      UpdateFibonacci();
   }

   return(rates_total);
}

void UpdateFibonacci()
{
   // Get Index of the candle back
   int shift = InpCandleBack;

   // Fetch Data
   double t_open  = iOpen(Symbol(), InpFibTF, shift);
   double t_high  = iHigh(Symbol(), InpFibTF, shift);
   double t_low   = iLow(Symbol(), InpFibTF, shift);
   double t_close = iClose(Symbol(), InpFibTF, shift);
   datetime t_time = iTime(Symbol(), InpFibTF, shift);
   
   // Safety check for valid data
   if(t_open == 0 || t_high == 0) return;

   // Get end time (Open time of the bar AFTER the target bar)
   datetime t_end_time = iTime(Symbol(), InpFibTF, shift - 1);
   
   // If shift-1 is 0 (current bar), the "end time" might be 0 or current time. 
   // We need a stable end time. If shift-1 is 0, we use TimeCurrent() or project the close time.
   if(shift == 1) {
       // If we are looking at the previous closed candle, the "end" is the open of the current candle
       t_end_time = iTime(Symbol(), InpFibTF, 0);
   } 
   else if (shift == 0) {
       // If looking at current candle, end time is not yet fixed, assume period duration
       t_end_time = t_time + PeriodSeconds(InpFibTF);
   }

   // Calculate Body and Wicks
   bool is_bull = t_close >= t_open;
   double body_top = is_bull ? t_close : t_open;
   double body_bottom = is_bull ? t_open : t_close;

   double upper_wick_start = body_top;
   double upper_wick_end = t_high;
   double lower_wick_start = body_bottom;
   double lower_wick_end = t_low;

   double upper_range = upper_wick_end - upper_wick_start;
   double lower_range = lower_wick_start - lower_wick_end;

   // --- OFFSET FIX ---
   // Convert Input Minutes to Seconds
   int offset_seconds = InpXOffset * 60; 
   
   // Apply offset to drawing coordinates
   datetime start_draw = t_time + offset_seconds;
   datetime end_draw   = t_end_time + offset_seconds;
   
   // --- DRAW UPPER WICK ---
   if(t_high > body_top)
   {
      DrawLevel("U1", start_draw, end_draw, upper_wick_start, upper_range, InpL1_Val, InpL1_On, InpL1_Col);
      DrawLevel("U2", start_draw, end_draw, upper_wick_start, upper_range, InpL2_Val, InpL2_On, InpL2_Col);
      DrawLevel("U3", start_draw, end_draw, upper_wick_start, upper_range, InpL3_Val, InpL3_On, InpL3_Col);
      DrawLevel("U4", start_draw, end_draw, upper_wick_start, upper_range, InpL4_Val, InpL4_On, InpL4_Col);
      DrawLevel("U5", start_draw, end_draw, upper_wick_start, upper_range, InpL5_Val, InpL5_On, InpL5_Col);
      DrawLevel("U6", start_draw, end_draw, upper_wick_start, upper_range, InpL6_Val, InpL6_On, InpL6_Col);
      DrawLevel("U7", start_draw, end_draw, upper_wick_start, upper_range, InpL7_Val, InpL7_On, InpL7_Col);
      DrawLevel("U8", start_draw, end_draw, upper_wick_start, upper_range, InpL8_Val, InpL8_On, InpL8_Col);
   }
   else 
   {
      DeleteGroup("U");
   }

   // --- DRAW LOWER WICK ---
   if(t_low < body_bottom)
   {
      // Note: Logic fixed to match Pine Script lower wick subtraction
      DrawLevel("L1", start_draw, end_draw, lower_wick_start, lower_range, InpL1_Val, InpL1_On, InpL1_Col);
      DrawLevel("L2", start_draw, end_draw, lower_wick_start, lower_range, InpL2_Val, InpL2_On, InpL2_Col);
      DrawLevel("L3", start_draw, end_draw, lower_wick_start, lower_range, InpL3_Val, InpL3_On, InpL3_Col);
      DrawLevel("L4", start_draw, end_draw, lower_wick_start, lower_range, InpL4_Val, InpL4_On, InpL4_Col);
      DrawLevel("L5", start_draw, end_draw, lower_wick_start, lower_range, InpL5_Val, InpL5_On, InpL5_Col);
      DrawLevel("L6", start_draw, end_draw, lower_wick_start, lower_range, InpL6_Val, InpL6_On, InpL6_Col);
      DrawLevel("L7", start_draw, end_draw, lower_wick_start, lower_range, InpL7_Val, InpL7_On, InpL7_Col);
      DrawLevel("L8", start_draw, end_draw, lower_wick_start, lower_range, InpL8_Val, InpL8_On, InpL8_Col);
   }
   else
   {
      DeleteGroup("L");
   }
   
   ChartRedraw();
}

// Consolidates logic for drawing line + label
void DrawLevel(string id, datetime t1, datetime t2, double base, double range, double level, bool on, color col)
{
   string lname = prefix + id + "_Line";
   string tname = prefix + id + "_Txt";
   
   if(on)
   {
      double price;
      
      // Upper Wick Logic: Base (Body Top) + (Range * Level)
      if (StringFind(id, "U") >= 0) {
          price = base + (range * level); 
      }
      // Lower Wick Logic: Base (Body Bottom) - (Range * Level)
      else {
          price = base - (range * level);
      }

      DrawLine(lname, t1, price, t2, price, col);
      
      if(InpShowLabels)
      {
         string txt = DoubleToString(level, 3);
         if(InpShowPrices) txt += " (" + DoubleToString(price, _Digits) + ")";
         DrawLabel(tname, t2, price, txt, col);
      }
      else
      {
         ObjectDelete(0, tname);
      }
   }
   else
   {
      ObjectDelete(0, lname);
      ObjectDelete(0, tname);
   }
}
void DeleteGroup(string group_id)
{
   for(int i=1; i<=8; i++)
   {
      ObjectDelete(0, prefix + group_id + IntegerToString(i) + "_Line");
      ObjectDelete(0, prefix + group_id + IntegerToString(i) + "_Txt");
   }
}
//+------------------------------------------------------------------+