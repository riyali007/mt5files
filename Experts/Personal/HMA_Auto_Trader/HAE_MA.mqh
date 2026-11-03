//+------------------------------------------------------------------+
//|                                                    HAE_MA.mqh    |
//|  HMA Active EA  v0.1                                              |
//|  File 3/10 - MA maths and the chart-mapped smoothed MA series.    |
//|                                                                   |
//|  Output (module globals, rebuilt once per new chart bar):         |
//|     HaeRates[]  chart bars, oldest -> newest (index n-1 = forming)|
//|     HaeMA[]     smoothed MA per chart bar (EMPTY_VALUE = not ready)|
//|     HaeBars     number of bars in both arrays                     |
//|                                                                   |
//|  Changes vs v2.07:                                                |
//|   - HMA warm-up = period + sqrt(period) (was period + 2)          |
//|   - work buffers are reused between rebuilds (no re-allocation)   |
//+------------------------------------------------------------------+
#ifndef HAE_MA_MQH
#define HAE_MA_MQH

#include "HAE_Defines.mqh"

//--- public output
MqlRates HaeRates[];
double   HaeMA[];
int      HaeBars = 0;

//--- reusable work buffers
double   s_hp[];      // MA-timeframe price series
datetime s_ht[];      // MA-timeframe bar times
double   s_base[];    // base MA on the MA timeframe
double   s_cb[];      // base MA mapped to chart bars
double   s_seg[];     // MaSeries segment in
double   s_res[];     // MaSeries segment out
double   s_wa[];      // HMA: WMA(period/2)
double   s_wb[];      // HMA: WMA(period)
double   s_raw[];     // HMA: 2*wa - wb

//+------------------------------------------------------------------+
//| Core maths                                                        |
//+------------------------------------------------------------------+
// Linear-weighted MA, O(n). Values before the first full window are the raw input
// (they are blanked later by the warm-up logic).
void HaeWma(const double &in[], double &out[], const int period, const int n)
{
   if(ArraySize(out) < n) ArrayResize(out, n);
   if(period <= 1) { for(int i = 0; i < n; i++) out[i] = in[i]; return; }

   const double weightSum = period * (period + 1) * 0.5;
   double sum = 0.0, wsum = 0.0;
   for(int i = 0; i < n; i++) {
      if(i < period) {
         sum  += in[i];
         wsum += in[i] * (i + 1);
         out[i] = (i < period - 1) ? in[i] : wsum / weightSum;
      } else {
         wsum = wsum - sum + period * in[i];
         sum  = sum - in[i - period] + in[i];
         out[i] = wsum / weightSum;
      }
   }
}

void HaeMaCore(const ENUM_HAE_MA type, const int period, const double &seg[], const int m, double &res[])
{
   if(ArraySize(res) < m) ArrayResize(res, m);
   if(period <= 1) { for(int i = 0; i < m; i++) res[i] = seg[i]; return; }

   switch(type) {
      case HAE_MA_SMA: {
         double sum = 0.0;
         for(int i = 0; i < m; i++) {
            sum += seg[i];
            if(i >= period) sum -= seg[i - period];
            res[i] = (i < period - 1) ? seg[i] : sum / period;
         }
         break;
      }
      case HAE_MA_EMA:
      case HAE_MA_RMA: {
         const double a = (type == HAE_MA_EMA) ? 2.0 / (period + 1.0) : 1.0 / (double)period;
         res[0] = seg[0];
         for(int i = 1; i < m; i++) res[i] = a * seg[i] + (1.0 - a) * res[i - 1];
         break;
      }
      case HAE_MA_WMA:
         HaeWma(seg, res, period, m);
         break;
      default: { // HMA = WMA( 2*WMA(n/2) - WMA(n), sqrt(n) )
         HaeWma(seg, s_wa, MathMax(1, period / 2), m);
         HaeWma(seg, s_wb, period, m);
         if(ArraySize(s_raw) < m) ArrayResize(s_raw, m);
         for(int i = 0; i < m; i++) s_raw[i] = 2.0 * s_wa[i] - s_wb[i];
         HaeWma(s_raw, res, MathMax(1, (int)MathRound(MathSqrt((double)period))), m);
         break;
      }
   }
}

// Runs an MA over a series that may start with EMPTY_VALUE entries.
void HaeMaSeries(const ENUM_HAE_MA type, const int period, const double &src[], const int n, double &dst[])
{
   if(ArraySize(dst) < n) ArrayResize(dst, n);
   int s = 0;
   while(s < n && src[s] == EMPTY_VALUE) s++;
   for(int i = 0; i < s; i++) dst[i] = EMPTY_VALUE;
   const int m = n - s;
   if(m <= 0) return;

   if(ArraySize(s_seg) < m) ArrayResize(s_seg, m);
   for(int i = 0; i < m; i++) s_seg[i] = src[s + i];
   HaeMaCore(type, period, s_seg, m, s_res);
   for(int i = 0; i < m; i++) dst[s + i] = s_res[i];
}

// Number of leading values that are not yet settled
int HaeWarmBars(const ENUM_HAE_MA type, const int period)
{
   if(period <= 1) return 0;
   switch(type) {
      case HAE_MA_EMA:
      case HAE_MA_RMA: return period * 4;                                                // exponential tail
      case HAE_MA_HMA: return period + (int)MathRound(MathSqrt((double)period)) + 1;     // WMA(n) + WMA(sqrt n)
      default:         return period + 1;                                                // SMA / WMA
   }
}

// Blanks the first `w` valid values so start-up values never create pivots
void HaeBlankWarmup(double &ma[], const int n, const int w)
{
   if(w <= 0) return;
   int f = 0;
   while(f < n && ma[f] == EMPTY_VALUE) f++;
   const int to = MathMin(n, f + w);
   for(int i = f; i < to; i++) ma[i] = EMPTY_VALUE;
}

double HaePrice(const MqlRates &r)
{
   switch(Cfg.appliedPrice) {
      case PRICE_OPEN:     return r.open;
      case PRICE_HIGH:     return r.high;
      case PRICE_LOW:      return r.low;
      case PRICE_MEDIAN:   return (r.high + r.low) * 0.5;
      case PRICE_TYPICAL:  return (r.high + r.low + r.close) / 3.0;
      case PRICE_WEIGHTED: return (r.high + r.low + 2.0 * r.close) * 0.25;
      default:             return r.close;
   }
}

//+------------------------------------------------------------------+
//| Build the smoothed, chart-mapped MA.                              |
//| Returns false while history is not ready (caller retries).        |
//+------------------------------------------------------------------+
bool HaeMABuild()
{
   const int baseWarm   = HaeWarmBars(Cfg.baseMethod,   Cfg.basePeriod);
   const int smoothWarm = HaeWarmBars(Cfg.smoothMethod, Cfg.smoothPeriod);
   const int extra      = Cfg.sameTf ? baseWarm + smoothWarm : smoothWarm;

   ArraySetAsSeries(HaeRates, false);
   const int n = CopyRates(_Symbol, _Period, 0, Cfg.maxBars + extra, HaeRates);
   if(n < 50) { HaeBars = 0; return false; }

   //--- price series on the MA timeframe
   int m = 0;
   if(Cfg.sameTf) {
      m = n;
      if(ArraySize(s_hp) < m) { ArrayResize(s_hp, m); ArrayResize(s_ht, m); }
      for(int i = 0; i < m; i++) { s_hp[i] = HaePrice(HaeRates[i]); s_ht[i] = HaeRates[i].time; }
   } else {
      MqlRates hr[];
      ArraySetAsSeries(hr, false);
      const long     warmSec = (long)(baseWarm + 50) * Cfg.tfSec * 8 / 5;   // +60% for weekends / gaps
      const datetime from    = (datetime)((long)HaeRates[0].time - warmSec);
      m = CopyRates(_Symbol, Cfg.tf, from, HaeRates[n - 1].time, hr);
      if(m < 2) { HaeBars = 0; return false; }
      if(ArraySize(s_hp) < m) { ArrayResize(s_hp, m); ArrayResize(s_ht, m); }
      for(int i = 0; i < m; i++) { s_hp[i] = HaePrice(hr[i]); s_ht[i] = hr[i].time; }
   }

   //--- base MA on the MA timeframe
   HaeMaSeries(Cfg.baseMethod, Cfg.basePeriod, s_hp, m, s_base);
   HaeBlankWarmup(s_base, m, baseWarm);

   //--- map to chart bars (no look-ahead when NoRepaint is on)
   if(ArraySize(s_cb) < n) ArrayResize(s_cb, n);
   int k = 0;
   for(int i = 0; i < n; i++) {
      if(HaeRates[i].time < s_ht[0]) { s_cb[i] = EMPTY_VALUE; continue; }
      while(k + 1 < m && s_ht[k + 1] <= HaeRates[i].time) k++;
      int use = k;
      if(Cfg.noRepaint && !Cfg.sameTf) {
         // chart bar closes before the HTF bar closes -> HTF value still forming, use the previous one
         if((long)HaeRates[i].time + Cfg.chartSec < (long)s_ht[k] + Cfg.tfSec) use = k - 1;
      }
      s_cb[i] = (use >= 0) ? s_base[use] : EMPTY_VALUE;
   }

   //--- chart-side smoothing
   if(ArraySize(HaeMA) < n) ArrayResize(HaeMA, n);
   HaeMaSeries(Cfg.smoothMethod, Cfg.smoothPeriod, s_cb, n, HaeMA);
   HaeBlankWarmup(HaeMA, n, smoothWarm);

   HaeBars = n;
   return true;
}

#endif // HAE_MA_MQH
//+------------------------------------------------------------------+
