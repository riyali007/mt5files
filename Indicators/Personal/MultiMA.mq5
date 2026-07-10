//+------------------------------------------------------------------+
//|                                                       MultiMA.mq5 |
//|         Multi Moving Average — SMA/EMA/WMA/RMA/HMA/VWAP/         |
//|                                ALMA/TEMA/HULLMA                   |
//|                              v1.0 — Riy Tech                      |
//+------------------------------------------------------------------+
#property copyright   "Riy Tech"
#property link        ""
#property version     "1.00"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   1

#property indicator_label1  "MultiMA"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//+------------------------------------------------------------------+
//| MA Type Enum                                                      |
//+------------------------------------------------------------------+
enum ENUM_MULTI_MA
{
   MA_SMA    = 0,   // SMA  — Simple Moving Average
   MA_EMA    = 1,   // EMA  — Exponential Moving Average
   MA_WMA    = 2,   // WMA  — Weighted Moving Average
   MA_RMA    = 3,   // RMA  — Wilder's Smoothed Moving Average
   MA_HMA    = 4,   // HMA  — Hull Moving Average
   MA_VWAP   = 5,   // VWAP — Volume Weighted Average Price (rolling)
   MA_ALMA   = 6,   // ALMA — Arnaud Legoux Moving Average
   MA_TEMA   = 7,   // TEMA — Triple Exponential Moving Average
   MA_HULLMA = 8,   // HULLMA — Hull MA (variant with WMA smoothing)
};

//+------------------------------------------------------------------+
//| INPUTS                                                            |
//+------------------------------------------------------------------+
input group "=== MA Settings ==="
input ENUM_MULTI_MA InpMAType   = MA_EMA;    // MA Type
input int           InpPeriod   = 20;         // Period
input ENUM_APPLIED_PRICE InpPrice = PRICE_CLOSE; // Applied Price

input group "=== ALMA Settings (only used when ALMA selected) ==="
input double        InpALMASigma  = 6.0;      // ALMA Sigma
input double        InpALMAOffset = 0.85;      // ALMA Offset (0.0–1.0)

input group "=== Visual ==="
input color         InpColor      = clrDodgerBlue; // Line Color
input ENUM_LINE_STYLE InpStyle    = STYLE_SOLID;    // Line Style
input int           InpWidth      = 2;              // Line Width

//+------------------------------------------------------------------+
//| BUFFERS                                                           |
//+------------------------------------------------------------------+
double BufMA[];       // Main output
double BufCalc[];     // Internal calculation buffer (INDICATOR_CALCULATIONS)

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BufMA,   INDICATOR_DATA);
   SetIndexBuffer(1, BufCalc, INDICATOR_CALCULATIONS);

   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpColor);
   PlotIndexSetInteger(0, PLOT_LINE_STYLE, InpStyle);
   PlotIndexSetInteger(0, PLOT_LINE_WIDTH, InpWidth);
   PlotIndexSetDouble (0, PLOT_EMPTY_VALUE, 0.0);

   string maName = MATypeName(InpMAType);
   IndicatorSetString(INDICATOR_SHORTNAME,
      StringFormat("%s(%d)", maName, InpPeriod));

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
string MATypeName(ENUM_MULTI_MA t)
{
   switch(t)
   {
      case MA_SMA:    return "SMA";
      case MA_EMA:    return "EMA";
      case MA_WMA:    return "WMA";
      case MA_RMA:    return "RMA";
      case MA_HMA:    return "HMA";
      case MA_VWAP:   return "VWAP";
      case MA_ALMA:   return "ALMA";
      case MA_TEMA:   return "TEMA";
      case MA_HULLMA: return "HULLMA";
   }
   return "MA";
}

//+------------------------------------------------------------------+
// Get applied price value for a single bar
//+------------------------------------------------------------------+
double GetPrice(const double &open[],  const double &high[],
                const double &low[],   const double &close[],
                int i)
{
   switch(InpPrice)
   {
      case PRICE_OPEN:    return open[i];
      case PRICE_HIGH:    return high[i];
      case PRICE_LOW:     return low[i];
      case PRICE_CLOSE:   return close[i];
      case PRICE_MEDIAN:  return (high[i] + low[i]) / 2.0;
      case PRICE_TYPICAL: return (high[i] + low[i] + close[i]) / 3.0;
      case PRICE_WEIGHTED:return (high[i] + low[i] + close[i] + close[i]) / 4.0;
   }
   return close[i];
}

//+------------------------------------------------------------------+
// SMA of BufCalc[i-period+1 .. i]
//+------------------------------------------------------------------+
double CalcSMA(int i, int period)
{
   if(i < period - 1) return 0.0;
   double sum = 0.0;
   for(int k = i - period + 1; k <= i; k++)
      sum += BufCalc[k];
   return sum / period;
}

//+------------------------------------------------------------------+
// WMA of BufCalc[i-period+1 .. i]
//+------------------------------------------------------------------+
double CalcWMA(int i, int period)
{
   if(i < period - 1) return 0.0;
   double sum = 0.0, wsum = 0.0;
   for(int k = i - period + 1; k <= i; k++)
   {
      double w = (double)(k - (i - period + 1) + 1);
      sum  += BufCalc[k] * w;
      wsum += w;
   }
   return sum / wsum;
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
{
   if(rates_total < InpPeriod) return 0;

   int period = InpPeriod;
   if(period < 2) period = 2;

   int start = (prev_calculated > 1) ? prev_calculated - 1 : 0;

   // Fill BufCalc with applied price
   for(int i = start; i < rates_total; i++)
      BufCalc[i] = GetPrice(open, high, low, close, i);

   //------------------------------------------------------------
   switch(InpMAType)
   {
      //----------------------------------------------------------
      case MA_SMA:
      {
         for(int i = start; i < rates_total; i++)
            BufMA[i] = (i < period - 1) ? 0.0 : CalcSMA(i, period);
         break;
      }

      //----------------------------------------------------------
      case MA_EMA:
      {
         double k = 2.0 / (period + 1.0);
         // Find a valid seed point
         int seed = (start == 0) ? period - 1 : start;
         if(start == 0)
         {
            for(int i = 0; i < period - 1; i++) BufMA[i] = 0.0;
            BufMA[period - 1] = CalcSMA(period - 1, period);
            for(int i = period; i < rates_total; i++)
               BufMA[i] = BufCalc[i] * k + BufMA[i-1] * (1.0 - k);
         }
         else
         {
            for(int i = start; i < rates_total; i++)
               BufMA[i] = BufCalc[i] * k + BufMA[i-1] * (1.0 - k);
         }
         break;
      }

      //----------------------------------------------------------
      case MA_WMA:
      {
         for(int i = start; i < rates_total; i++)
            BufMA[i] = (i < period - 1) ? 0.0 : CalcWMA(i, period);
         break;
      }

      //----------------------------------------------------------
      // RMA — Wilder's Smoothed MA (same as EMA with alpha = 1/period)
      case MA_RMA:
      {
         double alpha = 1.0 / period;
         if(start == 0)
         {
            for(int i = 0; i < period - 1; i++) BufMA[i] = 0.0;
            BufMA[period - 1] = CalcSMA(period - 1, period);
            for(int i = period; i < rates_total; i++)
               BufMA[i] = BufCalc[i] * alpha + BufMA[i-1] * (1.0 - alpha);
         }
         else
         {
            for(int i = start; i < rates_total; i++)
               BufMA[i] = BufCalc[i] * alpha + BufMA[i-1] * (1.0 - alpha);
         }
         break;
      }

      //----------------------------------------------------------
      // HMA — Hull Moving Average = WMA(2*WMA(n/2) - WMA(n), sqrt(n))
      // HULLMA uses the same formula — they are identical
      case MA_HMA:
      case MA_HULLMA:
      {
         int halfP  = (int)MathFloor(period / 2.0);
         int sqrtP  = (int)MathRound(MathSqrt((double)period));
         if(halfP < 1)  halfP  = 1;
         if(sqrtP < 1)  sqrtP  = 1;

         // Need a temporary array for the intermediate WMA series
         double tmpHull[];
         ArrayResize(tmpHull, rates_total);
         ArrayInitialize(tmpHull, 0.0);

         // Step 1: build intermediate series = 2*WMA(halfP) - WMA(period)
         // We need BufCalc to already be filled (it is)
         for(int i = period - 1; i < rates_total; i++)
         {
            double wmaFull = CalcWMA(i, period);
            double wmaHalf = CalcWMA(i, halfP);
            tmpHull[i] = 2.0 * wmaHalf - wmaFull;
         }

         // Step 2: WMA of tmpHull over sqrtP
         // Temporarily swap BufCalc for WMA calc
         double savedCalc[];
         ArrayResize(savedCalc, rates_total);
         ArrayCopy(savedCalc, BufCalc, 0, 0, rates_total);
         ArrayCopy(BufCalc, tmpHull, 0, 0, rates_total);

         int hullStart = period - 1 + sqrtP - 1;
         for(int i = 0; i < hullStart && i < rates_total; i++) BufMA[i] = 0.0;
         for(int i = hullStart; i < rates_total; i++)
            BufMA[i] = CalcWMA(i, sqrtP);

         // Restore BufCalc
         ArrayCopy(BufCalc, savedCalc, 0, 0, rates_total);
         break;
      }

      //----------------------------------------------------------
      // VWAP — Rolling VWAP over `period` bars
      case MA_VWAP:
      {
         for(int i = start; i < rates_total; i++)
         {
            if(i < period - 1) { BufMA[i] = 0.0; continue; }
            double tpvSum = 0.0, volSum = 0.0;
            for(int k = i - period + 1; k <= i; k++)
            {
               double tp  = (high[k] + low[k] + close[k]) / 3.0;
               double vol = (double)tick_volume[k];
               if(vol <= 0.0) vol = 1.0;
               tpvSum += tp * vol;
               volSum += vol;
            }
            BufMA[i] = (volSum > 0.0) ? tpvSum / volSum : 0.0;
         }
         break;
      }

      //----------------------------------------------------------
      // ALMA — Arnaud Legoux Moving Average
      case MA_ALMA:
      {
         // Pre-compute weights
         double weights[];
         ArrayResize(weights, period);
         double m    = InpALMAOffset * (period - 1);
         double s    = period / InpALMASigma;
         double wsum = 0.0;
         for(int j = 0; j < period; j++)
         {
            weights[j] = MathExp(-((j - m) * (j - m)) / (2.0 * s * s));
            wsum += weights[j];
         }
         // Normalise
         if(wsum != 0.0)
            for(int j = 0; j < period; j++) weights[j] /= wsum;

         for(int i = start; i < rates_total; i++)
         {
            if(i < period - 1) { BufMA[i] = 0.0; continue; }
            double val = 0.0;
            for(int j = 0; j < period; j++)
               val += weights[j] * BufCalc[i - period + 1 + j];
            BufMA[i] = val;
         }
         break;
      }

      //----------------------------------------------------------
      // TEMA — Triple EMA = 3*EMA1 - 3*EMA2 + EMA3
      case MA_TEMA:
      {
         double k = 2.0 / (period + 1.0);

         double ema1[], ema2[], ema3[];
         ArrayResize(ema1, rates_total);
         ArrayResize(ema2, rates_total);
         ArrayResize(ema3, rates_total);
         ArrayInitialize(ema1, 0.0);
         ArrayInitialize(ema2, 0.0);
         ArrayInitialize(ema3, 0.0);

         // EMA1
         if(start == 0)
         {
            for(int i = 0; i < period - 1; i++) ema1[i] = 0.0;
            ema1[period-1] = CalcSMA(period-1, period);
            for(int i = period; i < rates_total; i++)
               ema1[i] = BufCalc[i] * k + ema1[i-1] * (1.0-k);
         }
         else
         {
            ArrayCopy(ema1, BufMA, 0, 0, start); // seed from prev
            for(int i = start; i < rates_total; i++)
            {
               // Reseed ema1 from BufMA (which held ema1 on last pass)
               if(i == start && BufMA[i-1] > 0.0)
                  ema1[i-1] = BufMA[i-1];
               ema1[i] = BufCalc[i] * k + ema1[i-1] * (1.0-k);
            }
         }

         // EMA2 of EMA1
         int seed2 = 2 * (period - 1);
         for(int i = 0; i < seed2 && i < rates_total; i++) ema2[i] = 0.0;
         if(seed2 < rates_total)
         {
            double s2 = 0.0;
            for(int j = seed2 - (period-1); j <= seed2; j++) s2 += ema1[j];
            ema2[seed2] = s2 / period;
            for(int i = seed2+1; i < rates_total; i++)
               ema2[i] = ema1[i] * k + ema2[i-1] * (1.0-k);
         }

         // EMA3 of EMA2
         int seed3 = 3 * (period - 1);
         for(int i = 0; i < seed3 && i < rates_total; i++) ema3[i] = 0.0;
         if(seed3 < rates_total)
         {
            double s3 = 0.0;
            for(int j = seed3 - (period-1); j <= seed3; j++) s3 += ema2[j];
            ema3[seed3] = s3 / period;
            for(int i = seed3+1; i < rates_total; i++)
               ema3[i] = ema2[i] * k + ema3[i-1] * (1.0-k);
         }

         // TEMA = 3*EMA1 - 3*EMA2 + EMA3
         for(int i = 0; i < rates_total; i++)
         {
            if(ema3[i] == 0.0) BufMA[i] = 0.0;
            else BufMA[i] = 3.0*ema1[i] - 3.0*ema2[i] + ema3[i];
         }
         break;
      }
   }

   return rates_total;
}
//+------------------------------------------------------------------+