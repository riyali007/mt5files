//+------------------------------------------------------------------+
//|                                                  MTF_3x_MA.mq5   |
//|                                      Converted from Pine Script  |
//+------------------------------------------------------------------+
#property copyright "MQL5 Conversion"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   3

//--- Plot properties
#property indicator_label1  "MA 1"
#property indicator_type1   DRAW_LINE
#property indicator_width1  2

#property indicator_label2  "MA 2"
#property indicator_type2   DRAW_LINE
#property indicator_width2  2

#property indicator_label3  "MA 3"
#property indicator_type3   DRAW_LINE
#property indicator_width3  2

//--- Enums
enum ENUM_MA_TYPE
  {
   MA_SMA,  // SMA
   MA_EMA,  // EMA
   MA_WMA,  // WMA
   MA_VWMA, // VWMA
   MA_HMA,  // HMA
   MA_RMA   // RMA (Smoothed)
  };

//--- INPUTS: Moving Average 1 ---
input group "=== Moving Average 1 ==="
input bool               Show1 = true;            // Show MA 1
input ENUM_MA_TYPE       Type1 = MA_EMA;          // Type
input int                Len1  = 50;              // Length
input ENUM_TIMEFRAMES    TF1   = PERIOD_H1;       // Timeframe
input ENUM_APPLIED_PRICE Src1  = PRICE_CLOSE;     // Source
input color              Col1  = clrBlue;         // Color

//--- INPUTS: Moving Average 2 ---
input group "=== Moving Average 2 ==="
input bool               Show2 = true;            // Show MA 2
input ENUM_MA_TYPE       Type2 = MA_SMA;          // Type
input int                Len2  = 100;             // Length
input ENUM_TIMEFRAMES    TF2   = PERIOD_H4;       // Timeframe
input ENUM_APPLIED_PRICE Src2  = PRICE_CLOSE;     // Source
input color              Col2  = clrOrange;       // Color

//--- INPUTS: Moving Average 3 ---
input group "=== Moving Average 3 ==="
input bool               Show3 = true;            // Show MA 3
input ENUM_MA_TYPE       Type3 = MA_WMA;          // Type
input int                Len3  = 200;             // Length
input ENUM_TIMEFRAMES    TF3   = PERIOD_D1;       // Timeframe
input ENUM_APPLIED_PRICE Src3  = PRICE_CLOSE;     // Source
input color              Col3  = clrMagenta;      // Color

//--- Buffers
double Buffer1[];
double Buffer2[];
double Buffer3[];

//--- Handles for native MAs (SMA, EMA, WMA, RMA)
int handle1 = INVALID_HANDLE;
int handle2 = INVALID_HANDLE;
int handle3 = INVALID_HANDLE;

//--- Cache structs for performance optimization
struct SMACache {
   datetime last_htf_time;
   double   last_val;
   void     Reset() { last_htf_time = 0; last_val = EMPTY_VALUE; }
};
SMACache cache1, cache2, cache3;

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Bind buffers
   SetIndexBuffer(0, Buffer1, INDICATOR_DATA);
   SetIndexBuffer(1, Buffer2, INDICATOR_DATA);
   SetIndexBuffer(2, Buffer3, INDICATOR_DATA);

   // Configure empty values
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   // Configure user colors
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, Col1);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, Col2);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, Col3);
   
   // Initialize Native MA Handles (VWMA and HMA are calculated manually)
   if(Show1 && Type1 != MA_VWMA && Type1 != MA_HMA)
      handle1 = iMA(Symbol(), TF1, Len1, 0, GetNativeMode(Type1), Src1);
      
   if(Show2 && Type2 != MA_VWMA && Type2 != MA_HMA)
      handle2 = iMA(Symbol(), TF2, Len2, 0, GetNativeMode(Type2), Src2);
      
   if(Show3 && Type3 != MA_VWMA && Type3 != MA_HMA)
      handle3 = iMA(Symbol(), TF3, Len3, 0, GetNativeMode(Type3), Src3);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(handle1 != INVALID_HANDLE) IndicatorRelease(handle1);
   if(handle2 != INVALID_HANDLE) IndicatorRelease(handle2);
   if(handle3 != INVALID_HANDLE) IndicatorRelease(handle3);
  }

//+------------------------------------------------------------------+
//| Main Iteration Function                                          |
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
   int start = prev_calculated == 0 ? 0 : prev_calculated - 1;

   // Reset cache on full reload to prevent artifacts
   if(prev_calculated == 0)
     {
      cache1.Reset(); 
      cache2.Reset(); 
      cache3.Reset();
     }

   for(int i = start; i < rates_total; i++)
     {
      datetime t = time[i];
      bool is_current_bar = (i == rates_total - 1); // Live forming bar

      // --- Moving Average 1 ---
      if(Show1)
        {
         int shift = iBarShift(Symbol(), TF1, t);
         datetime htf_t = iTime(Symbol(), TF1, shift);
         
         // Use cached value for closed historical bars to boost speed
         if(!is_current_bar && htf_t == cache1.last_htf_time)
           {
            Buffer1[i] = cache1.last_val;
           }
         else
           {
            double val = EMPTY_VALUE;
            if (Type1 == MA_VWMA) val = CalculateVWMA(TF1, Len1, Src1, shift);
            else if (Type1 == MA_HMA) val = CalculateHMA(TF1, Len1, Src1, shift);
            else
              {
               double arr[1];
               if(CopyBuffer(handle1, 0, shift, 1, arr) > 0) val = arr[0];
              }
            Buffer1[i] = val;
            
            if(!is_current_bar)
              {
               cache1.last_htf_time = htf_t;
               cache1.last_val = val;
              }
           }
        } else Buffer1[i] = EMPTY_VALUE;


      // --- Moving Average 2 ---
      if(Show2)
        {
         int shift = iBarShift(Symbol(), TF2, t);
         datetime htf_t = iTime(Symbol(), TF2, shift);
         
         if(!is_current_bar && htf_t == cache2.last_htf_time)
           {
            Buffer2[i] = cache2.last_val;
           }
         else
           {
            double val = EMPTY_VALUE;
            if (Type2 == MA_VWMA) val = CalculateVWMA(TF2, Len2, Src2, shift);
            else if (Type2 == MA_HMA) val = CalculateHMA(TF2, Len2, Src2, shift);
            else
              {
               double arr[1];
               if(CopyBuffer(handle2, 0, shift, 1, arr) > 0) val = arr[0];
              }
            Buffer2[i] = val;
            
            if(!is_current_bar)
              {
               cache2.last_htf_time = htf_t;
               cache2.last_val = val;
              }
           }
        } else Buffer2[i] = EMPTY_VALUE;


      // --- Moving Average 3 ---
      if(Show3)
        {
         int shift = iBarShift(Symbol(), TF3, t);
         datetime htf_t = iTime(Symbol(), TF3, shift);
         
         if(!is_current_bar && htf_t == cache3.last_htf_time)
           {
            Buffer3[i] = cache3.last_val;
           }
         else
           {
            double val = EMPTY_VALUE;
            if (Type3 == MA_VWMA) val = CalculateVWMA(TF3, Len3, Src3, shift);
            else if (Type3 == MA_HMA) val = CalculateHMA(TF3, Len3, Src3, shift);
            else
              {
               double arr[1];
               if(CopyBuffer(handle3, 0, shift, 1, arr) > 0) val = arr[0];
              }
            Buffer3[i] = val;
            
            if(!is_current_bar)
              {
               cache3.last_htf_time = htf_t;
               cache3.last_val = val;
              }
           }
        } else Buffer3[i] = EMPTY_VALUE;
     }
     
   return(rates_total);
  }


//+------------------------------------------------------------------+
//| Helper: Get MT5 Native MA Mode                                   |
//+------------------------------------------------------------------+
ENUM_MA_METHOD GetNativeMode(ENUM_MA_TYPE type)
  {
   switch(type)
     {
      case MA_SMA: return MODE_SMA;
      case MA_EMA: return MODE_EMA;
      case MA_WMA: return MODE_LWMA;
      case MA_RMA: return MODE_SMMA; // MT5 SMMA mathematically equals Pine's RMA
      default:     return MODE_SMA;
     }
  }

//+------------------------------------------------------------------+
//| Helper: Extract Specific Price Type from MqlRates                |
//+------------------------------------------------------------------+
double GetPrice(const MqlRates &r, ENUM_APPLIED_PRICE ap)
  {
   switch(ap)
     {
      case PRICE_CLOSE:    return r.close;
      case PRICE_OPEN:     return r.open;
      case PRICE_HIGH:     return r.high;
      case PRICE_LOW:      return r.low;
      case PRICE_MEDIAN:   return (r.high + r.low) / 2.0;
      case PRICE_TYPICAL:  return (r.high + r.low + r.close) / 3.0;
      case PRICE_WEIGHTED: return (r.high + r.low + r.close * 2.0) / 4.0;
      default:             return r.close;
     }
  }

//+------------------------------------------------------------------+
//| Custom Math: Volume Weighted Moving Average (VWMA)               |
//+------------------------------------------------------------------+
double CalculateVWMA(ENUM_TIMEFRAMES tf, int len, ENUM_APPLIED_PRICE ap, int shift)
  {
   if(shift < 0) return EMPTY_VALUE;

   MqlRates rates[];
   if(CopyRates(Symbol(), tf, shift, len, rates) != len) return EMPTY_VALUE;

   double sum_pv = 0, sum_v = 0;
   // rates[0] is oldest, rates[len-1] is newest
   for(int i = 0; i < len; i++)
     {
      double p = GetPrice(rates[i], ap);
      double v = (double)rates[i].tick_volume;
      sum_pv += p * v;
      sum_v  += v;
     }
     
   if(sum_v == 0) return EMPTY_VALUE;
   return sum_pv / sum_v;
  }

//+------------------------------------------------------------------+
//| Custom Math: Hull Moving Average (HMA)                           |
//+------------------------------------------------------------------+
double CalculateHMA(ENUM_TIMEFRAMES tf, int len, ENUM_APPLIED_PRICE ap, int shift)
  {
   if(shift < 0) return EMPTY_VALUE;

   int half_len = (int)MathFloor(len / 2.0);
   int sq_len = (int)MathRound(MathSqrt(len));
   int total_lookback = len + sq_len - 1; // Amount of bars needed to complete the nesting

   MqlRates rates[];
   if(CopyRates(Symbol(), tf, shift, total_lookback, rates) != total_lookback) return EMPTY_VALUE;

   double diff[];
   ArrayResize(diff, sq_len);

   // Compute inner WMA difference for the last 'sq_len' bars
   for(int k = 0; k < sq_len; k++)
     {
      int end_idx = total_lookback - sq_len + k; 

      double wma_full = 0, norm_full = 0;
      for(int j = 0; j < len; j++)
        {
         double weight = len - j;
         wma_full  += GetPrice(rates[end_idx - j], ap) * weight;
         norm_full += weight;
        }
      wma_full /= norm_full;

      double wma_half = 0, norm_half = 0;
      for(int j = 0; j < half_len; j++)
        {
         double weight = half_len - j;
         wma_half  += GetPrice(rates[end_idx - j], ap) * weight;
         norm_half += weight;
        }
      wma_half /= norm_half;

      // 2 * WMA(len/2) - WMA(len)
      diff[k] = 2.0 * wma_half - wma_full;
     }

   // Outer WMA on the nested differences array
   double hma = 0, norm_hma = 0;
   for(int j = 0; j < sq_len; j++)
     {
      double weight = sq_len - j;
      hma += diff[sq_len - 1 - j] * weight; 
      norm_hma += weight;
     }
     
   return hma / norm_hma;
  }
//+------------------------------------------------------------------+