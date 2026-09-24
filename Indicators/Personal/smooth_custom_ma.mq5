//+------------------------------------------------------------------+
//|                                    HTF_Inflection_Custom_MA.mq5  |
//|                                    Per-Tick & Pivot Validated    |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1

//--- Plot 1: Final MA
#property indicator_label1  "HTF MA"
#property indicator_type1   DRAW_LINE
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- Custom MA Types
enum ENUM_CUSTOM_MA {
   CMA_SMA=0,  // Simple MA (SMA)
   CMA_EMA=1,  // Exponential MA (EMA)
   CMA_RMA=2,  // Running MA (RMA / Wilder's Smoothing)
   CMA_WMA=3,  // Weighted MA (WMA)
   CMA_HMA=4   // Hull MA (HMA)
};

//--- Inputs
input group "=== Base MA Settings ==="
input int                  InpMaxBars       = 1000;           // Max Historical Bars to Process
input ENUM_TIMEFRAMES      InpTimeframe     = PERIOD_CURRENT; // HTF Timeframe
input ENUM_CUSTOM_MA       InpBaseMethod    = CMA_HMA;        // Base MA Type
input int                  InpBasePeriod    = 34;             // Base MA Period
input ENUM_APPLIED_PRICE   InpAppliedPrice  = PRICE_CLOSE;    // Base Applied Price

input group "=== Smoothing Settings ==="
input ENUM_CUSTOM_MA       InpSmoothMethod  = CMA_SMA;        // Smoothing MA Type
input int                  InpSmoothPeriod  = 1;              // Smoothing Period (1 = No Smoothing)

input group "=== Inflection Line Settings ==="
input int                  InpPivotCandles         = 5;                // Required consecutive candles below/above MA to confirm peak
input int                  InpMitigationExpiryMins = 60;               // Remove mitigated lines after (Mins)
input int                  InpProximityPoints      = 50;               // Highlight proximity distance (Points)
input color                InpMaColor              = clrDodgerBlue;    // MA Line Color
input color                InpDimColor             = clrDarkSlateGray; // Default Dimmed Line Color
input color                InpHighlightUpper       = clrLimeGreen;     // Highlight Upper (Peak) Color
input color                InpHighlightLower       = clrTomato;        // Highlight Lower (Trough) Color

//--- Indicator Buffer
double BufferMA[];

//--- Tracked Inflection Lines State Machine
struct InflectionLine {
   string   name;
   double   price;
   datetime startTime;
   datetime mitigatedTime;
   bool     isMitigated;
   bool     isUpper;
   bool     isHighlighted;
};

InflectionLine g_lines[];
bool g_drawVisuals = true;
int g_last_checked_bar = 0;

//+------------------------------------------------------------------+
//| Custom Initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BufferMA, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpMaColor);
   IndicatorSetString(INDICATOR_SHORTNAME, "HTF MA Inflections");
   ArrayInitialize(BufferMA, EMPTY_VALUE);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   // CRITICAL PERFORMANCE TWEAK: Disable heavy objects during optimization
   if((bool)MQLInfoInteger(MQL_OPTIMIZATION) && !(bool)MQLInfoInteger(MQL_VISUAL_MODE)) {
      g_drawVisuals = false;
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinitialization: Clean up chart objects                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_drawVisuals) ObjectsDeleteAll(0, "HTF_INFL_");
}

//+------------------------------------------------------------------+
//| Custom MA Math Helpers                                           |
//+------------------------------------------------------------------+
void CalcSMA(const double &in[], double &out[], int period) {
   int sz = ArraySize(in); ArrayResize(out, sz);
   for(int i = 0; i < sz; i++) {
      if(i < period - 1) { out[i] = in[i]; continue; }
      double sum = 0;
      for(int j = 0; j < period; j++) sum += in[i - j];
      out[i] = sum / period;
   }
}

void CalcEMA(const double &in[], double &out[], int period) {
   int sz = ArraySize(in); ArrayResize(out, sz);
   double alpha = 2.0 / (period + 1.0);
   for(int i = 0; i < sz; i++) {
      if(i == 0) out[i] = in[i];
      else out[i] = alpha * in[i] + (1.0 - alpha) * out[i-1];
   }
}

void CalcRMA(const double &in[], double &out[], int period) {
   int sz = ArraySize(in); ArrayResize(out, sz);
   double alpha = 1.0 / period;
   for(int i = 0; i < sz; i++) {
      if(i == 0) out[i] = in[i];
      else out[i] = alpha * in[i] + (1.0 - alpha) * out[i-1];
   }
}

void CalcWMA(const double &in[], double &out[], int period) {
   int sz = ArraySize(in); ArrayResize(out, sz);
   double weightSum = (period * (period + 1)) / 2.0;
   for(int i = 0; i < sz; i++) {
      if(i < period - 1) { out[i] = in[i]; continue; }
      double sum = 0;
      for(int j = 0; j < period; j++) sum += in[i - j] * (period - j);
      out[i] = sum / weightSum;
   }
}

void CalcHMA(const double &in[], double &out[], int period) {
   int sz = ArraySize(in); ArrayResize(out, sz);
   double wma1[]; CalcWMA(in, wma1, MathMax(1, period / 2));
   double wma2[]; CalcWMA(in, wma2, period);
   double raw[]; ArrayResize(raw, sz);
   for(int i = 0; i < sz; i++) raw[i] = 2.0 * wma1[i] - wma2[i];
   int smoothPeriod = (int)MathRound(MathSqrt(period));
   CalcWMA(raw, out, MathMax(1, smoothPeriod));
}

void CalcCustomMA(ENUM_CUSTOM_MA type, int period, const double &in[], double &out[]) {
   switch(type) {
      case CMA_SMA: CalcSMA(in, out, period); break;
      case CMA_EMA: CalcEMA(in, out, period); break;
      case CMA_RMA: CalcRMA(in, out, period); break;
      case CMA_WMA: CalcWMA(in, out, period); break;
      case CMA_HMA: CalcHMA(in, out, period); break;
   }
}

//+------------------------------------------------------------------+
//| Add a new horizontal object line tracking the inflection         |
//+------------------------------------------------------------------+
void AddInflection(datetime timeStart, double priceLevel, bool isUpper) {
   int size = ArraySize(g_lines);
   ArrayResize(g_lines, size + 1, 50); 
   
   string name = "";
   if(g_drawVisuals) {
      name = "HTF_INFL_" + TimeToString(timeStart) + "_" + DoubleToString(priceLevel, 5);
      ObjectCreate(0, name, OBJ_TREND, 0, timeStart, priceLevel, timeStart + PeriodSeconds(), priceLevel);
      ObjectSetInteger(0, name, OBJPROP_COLOR, InpDimColor);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
   }
   
   g_lines[size].name = name;
   g_lines[size].price = priceLevel;
   g_lines[size].startTime = timeStart;
   g_lines[size].mitigatedTime = 0;
   g_lines[size].isMitigated = false;
   g_lines[size].isUpper = isUpper;
   g_lines[size].isHighlighted = false;
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
   if(rates_total < 2) return(0);

   int limit = prev_calculated == 0 ? 0 : prev_calculated - 1;
   
   // Restrict historical calculations to 'InpMaxBars'
   if(prev_calculated == 0 && InpMaxBars > 0 && rates_total > InpMaxBars) {
      limit = rates_total - InpMaxBars;
      if(limit < 0) limit = 0;
   }

   // Reset state if chart reloads
   if(prev_calculated == 0) {
      ArrayResize(g_lines, 0, 50);
      g_last_checked_bar = limit + InpPivotCandles + 2; 
      if(g_drawVisuals) ObjectsDeleteAll(0, "HTF_INFL_");
   }

   // ====================================================================
   // 1. FAST HTF MAPPING (Calculates only required bars per tick)
   // ====================================================================
   int warmup_bars = MathMax(InpBasePeriod, InpSmoothPeriod) + 300;
   datetime t_start = time[limit] - PeriodSeconds(InpTimeframe) * warmup_bars;
   datetime t_end = time[rates_total - 1] + PeriodSeconds(InpTimeframe);

   double htfPrice[];
   datetime htfTime[];
   int copied = 0;

   switch(InpAppliedPrice) {
      case PRICE_CLOSE: copied = CopyClose(_Symbol, InpTimeframe, t_start, t_end, htfPrice); break;
      case PRICE_OPEN:  copied = CopyOpen(_Symbol, InpTimeframe, t_start, t_end, htfPrice); break;
      case PRICE_HIGH:  copied = CopyHigh(_Symbol, InpTimeframe, t_start, t_end, htfPrice); break;
      case PRICE_LOW:   copied = CopyLow(_Symbol, InpTimeframe, t_start, t_end, htfPrice); break;
      case PRICE_TYPICAL:
      {
         MqlRates rates[];
         copied = CopyRates(_Symbol, InpTimeframe, t_start, t_end, rates);
         if(copied > 0) {
            ArrayResize(htfPrice, copied);
            for(int i = 0; i < copied; i++) htfPrice[i] = (rates[i].high + rates[i].low + rates[i].close) / 3.0;
         }
         break;
      }
      default: copied = CopyClose(_Symbol, InpTimeframe, t_start, t_end, htfPrice); break;
   }

   if(copied > 0 && CopyTime(_Symbol, InpTimeframe, t_start, t_end, htfTime) == copied) {
      double htfBase[], htfFinalMA[];
      CalcCustomMA(InpBaseMethod, MathMax(1, InpBasePeriod), htfPrice, htfBase);
      if(InpSmoothPeriod > 1) CalcCustomMA(InpSmoothMethod, InpSmoothPeriod, htfBase, htfFinalMA);
      else ArrayCopy(htfFinalMA, htfBase);

      int htfTotal = ArraySize(htfTime);
      int htf_idx = 0;
      if(limit > 0) {
         htf_idx = ArrayBsearch(htfTime, time[limit]);
         if(htf_idx > 0 && htfTime[htf_idx] > time[limit]) htf_idx--;
      }

      for(int i = limit; i < rates_total; i++) {
         while(htf_idx < htfTotal - 1 && time[i] >= htfTime[htf_idx + 1]) htf_idx++;
         BufferMA[i] = htfFinalMA[htf_idx];
      }
   }

   // ====================================================================
   // 2. INFLECTION VALIDATION & HISTORICAL MITIGATION (Only on closed bars)
   // ====================================================================
   for(int i = g_last_checked_bar; i < rates_total - 1; i++) {
      
      int p = i - 1; // 'p' is the potential peak, surrounded by closed bars p-1 and p+1(i)

      if(BufferMA[p] != EMPTY_VALUE && BufferMA[p-1] != EMPTY_VALUE && BufferMA[i] != EMPTY_VALUE) {
         
         bool isPeak   = (BufferMA[p] > BufferMA[p-1] && BufferMA[p] > BufferMA[i]);
         bool isTrough = (BufferMA[p] < BufferMA[p-1] && BufferMA[p] < BufferMA[i]);
         
         // Validate Peak: The preceding N candles must be BELOW the MA
         if(isPeak) {
            bool valid = true;
            for(int k = 1; k <= InpPivotCandles; k++) {
               if(p - k < 0 || close[p - k] > BufferMA[p - k]) { valid = false; break; }
            }
            if(valid) AddInflection(time[p], BufferMA[p], true);
         }
         
         // Validate Trough: The preceding N candles must be ABOVE the MA
         if(isTrough) {
            bool valid = true;
            for(int k = 1; k <= InpPivotCandles; k++) {
               if(p - k < 0 || close[p - k] < BufferMA[p - k]) { valid = false; break; }
            }
            if(valid) AddInflection(time[p], BufferMA[p], false);
         }
      }

      // Check historical mitigations as we process the chart
      for(int j = ArraySize(g_lines) - 1; j >= 0; j--) {
         if(!g_lines[j].isMitigated) {
            if(high[i] >= g_lines[j].price && low[i] <= g_lines[j].price) {
               g_lines[j].isMitigated = true;
               g_lines[j].mitigatedTime = time[i];
               if(g_drawVisuals) {
                  ObjectSetInteger(0, g_lines[j].name, OBJPROP_RAY_RIGHT, false);
                  ObjectSetInteger(0, g_lines[j].name, OBJPROP_TIME, 1, time[i]);
               }
            }
         }
      }
   }
   
   g_last_checked_bar = rates_total - 1; // Update marker so we only check newly closed bars next tick

   // ====================================================================
   // 3. LIVE MITIGATION & VISUAL HIGHLIGHTING (Runs every live tick)
   // ====================================================================
   int current_i = rates_total - 1;
   double currentPrice = close[current_i];
   datetime currentTime = time[current_i];

   for(int j = ArraySize(g_lines) - 1; j >= 0; j--) {
      // Live Mitigation
      if(!g_lines[j].isMitigated) {
         if(high[current_i] >= g_lines[j].price && low[current_i] <= g_lines[j].price) {
            g_lines[j].isMitigated = true;
            g_lines[j].mitigatedTime = currentTime;
            
            if(g_drawVisuals) {
               ObjectSetInteger(0, g_lines[j].name, OBJPROP_RAY_RIGHT, false);
               ObjectSetInteger(0, g_lines[j].name, OBJPROP_TIME, 1, currentTime);
            }
         }
      }

      // Live Expiration and Visuals
      if(g_lines[j].isMitigated) {
         if(currentTime - g_lines[j].mitigatedTime >= InpMitigationExpiryMins * 60) {
            if(g_drawVisuals) ObjectDelete(0, g_lines[j].name);
            g_lines[j] = g_lines[ArraySize(g_lines) - 1]; 
            ArrayResize(g_lines, ArraySize(g_lines) - 1, 50);
         }
      } 
      else if(g_drawVisuals) {
         double diffPoints = MathAbs(currentPrice - g_lines[j].price) / _Point;
         bool inProximity = (diffPoints <= InpProximityPoints);
         
         if(inProximity && !g_lines[j].isHighlighted) {
            color hlColor = g_lines[j].isUpper ? InpHighlightUpper : InpHighlightLower;
            ObjectSetInteger(0, g_lines[j].name, OBJPROP_COLOR, hlColor);
            ObjectSetInteger(0, g_lines[j].name, OBJPROP_WIDTH, 2);
            g_lines[j].isHighlighted = true;
         } 
         else if(!inProximity && g_lines[j].isHighlighted) {
            ObjectSetInteger(0, g_lines[j].name, OBJPROP_COLOR, InpDimColor);
            ObjectSetInteger(0, g_lines[j].name, OBJPROP_WIDTH, 1);
            g_lines[j].isHighlighted = false;
         }
      }
   }

   return(rates_total);
}
//+------------------------------------------------------------------+