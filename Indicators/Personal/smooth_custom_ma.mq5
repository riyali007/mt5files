//+------------------------------------------------------------------+
//|                                  smooth_custom_ma.mq5           |
//|                                  HTF MA, chart-side smoothing    |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1

#property indicator_label1  "HTF MA"
#property indicator_type1   DRAW_LINE
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

#define MAX_ACTIVE_LINES 400
#define MAX_DRAWN_LINES  200

enum ENUM_CUSTOM_MA {
   CMA_SMA=0,
   CMA_EMA=1,
   CMA_RMA=2,
   CMA_WMA=3,
   CMA_HMA=4
};

input group "=== Base MA Settings ==="
input int                InpMaxBars      = 1000;
input ENUM_TIMEFRAMES    InpTimeframe    = PERIOD_CURRENT;
input ENUM_CUSTOM_MA     InpBaseMethod   = CMA_HMA;
input int                InpBasePeriod   = 34;
input ENUM_APPLIED_PRICE InpAppliedPrice = PRICE_CLOSE;

input group "=== Smoothing Settings ==="
input ENUM_CUSTOM_MA InpSmoothMethod = CMA_SMA;
input int            InpSmoothPeriod = 1;

input group "=== Inflection Line Settings ==="
input int   InpLineOffsetPoints     = 350;
input int   InpPivotCandles         = 5;
input int   InpMitigationExpiryMins = 60;
input color InpMaColor              = clrDodgerBlue;
input color InpDimColor             = clrDarkSlateGray;

input group "=== Clustering / Merging Settings ==="
input bool InpEnableClustering      = true;
input int  InpClusterDistancePoints = 100;

input group "=== Price Label Settings ==="
input color InpLabelDim = clrDarkSlateGray;

double BufferMA[];

struct InflectionLine {
   string   name;
   double   price;
   datetime startTime;
   datetime mitigatedTime;
   bool     isMitigated;
   bool     isUpper;
   bool     drawn;
};

InflectionLine g_lines[];
int            g_active[];
int            g_nActive = 0;

bool     g_drawVisuals = false;
bool     g_isTester    = false;
datetime g_lastChartBar = 0;

int g_last_checked_bar = 0;
int g_pending_peak_idx = -1;
int g_pending_trough_idx = -1;
int g_candles_below = 0;
int g_candles_above = 0;

double   g_px[];
datetime g_tm[];
double   g_base[];
int      g_htfCount = 0;
double   g_chartBase[];

int      g_basePeriod = 1;
int      g_smoothPeriod = 1;
double   g_baseAlpha = 0.0;
double   g_smoothAlpha = 0.0;
ENUM_TIMEFRAMES g_tf = PERIOD_CURRENT;
int      g_tfSec = 60;
bool     g_sameTf = true;

double g_slice[];
double g_part[];
double g_wmaA[];
double g_wmaB[];
double g_raw[];

//+------------------------------------------------------------------+
int WorkCap(const int period)
{
   // Hull needs the base window plus the sqrt window. period+8 is not enough.
   return period + (int)MathCeil(MathSqrt((double)MathMax(period, 1))) + 8;
}

void EnsureWork(const int need)
{
   if(need <= ArraySize(g_slice)) return;
   ArrayResize(g_slice, need);
   ArrayResize(g_part,  need);
   ArrayResize(g_wmaA,  need);
   ArrayResize(g_wmaB,  need);
   ArrayResize(g_raw,   need);
}

//+------------------------------------------------------------------+
int OnInit()
{
   if(InpBasePeriod < 1 || InpSmoothPeriod < 1 || InpPivotCandles < 1)
      return(INIT_PARAMETERS_INCORRECT);

   SetIndexBuffer(0, BufferMA, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpMaColor);
   IndicatorSetString(INDICATOR_SHORTNAME, "HTF MA Inflections");
   ArrayInitialize(BufferMA, EMPTY_VALUE);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   g_isTester = (bool)MQLInfoInteger(MQL_TESTER) || (bool)MQLInfoInteger(MQL_OPTIMIZATION);
   const bool visual = (bool)MQLInfoInteger(MQL_VISUAL_MODE);
   g_drawVisuals = !g_isTester || visual;

   g_tf = (InpTimeframe == PERIOD_CURRENT ? (ENUM_TIMEFRAMES)_Period : InpTimeframe);
   g_tfSec = (int)PeriodSeconds(g_tf);
   if(g_tfSec < 1) g_tfSec = (int)PeriodSeconds((ENUM_TIMEFRAMES)_Period);
   g_sameTf = (g_tf == (ENUM_TIMEFRAMES)_Period);

   g_basePeriod = MathMax(1, InpBasePeriod);
   g_smoothPeriod = MathMax(1, InpSmoothPeriod);
   g_baseAlpha = (InpBaseMethod == CMA_EMA) ? 2.0 / (g_basePeriod + 1.0) : 1.0 / (double)g_basePeriod;
   g_smoothAlpha = (InpSmoothMethod == CMA_EMA) ? 2.0 / (g_smoothPeriod + 1.0) : 1.0 / (double)g_smoothPeriod;

   EnsureWork(MathMax(WorkCap(g_basePeriod), WorkCap(g_smoothPeriod)));
   ResetSeries();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_drawVisuals) ObjectsDeleteAll(0, "HTF_INFL_");
}

//+------------------------------------------------------------------+
void ResetSeries()
{
   g_htfCount = 0;
   g_nActive = 0;
   g_lastChartBar = 0;
   ArrayFree(g_px);
   ArrayFree(g_tm);
   ArrayFree(g_base);
   ArrayFree(g_chartBase);
}

//+------------------------------------------------------------------+
int TailNeed(const ENUM_CUSTOM_MA type, const int period)
{
   if(type == CMA_HMA)
      return period + (int)MathRound(MathSqrt((double)period)) + 3;
   return period + 2;
}

//+------------------------------------------------------------------+
void WmaInto(const double &in[], double &out[], const int period, const int count)
{
   if(period <= 1) {
      for(int i = 0; i < count; i++) out[i] = in[i];
      return;
   }
   const double weightSum = (period * (period + 1)) * 0.5;
   double sum = 0.0, wsum = 0.0;
   for(int i = 0; i < count; i++) {
      if(i < period) {
         sum += in[i];
         wsum += in[i] * (i + 1);
         out[i] = (i < period - 1) ? in[i] : wsum / weightSum;
      } else {
         wsum = wsum - sum + period * in[i];
         sum = sum - in[i - period] + in[i];
         out[i] = wsum / weightSum;
      }
   }
}

//+------------------------------------------------------------------+
bool SliceOk(const double &src[], const int from, const int to)
{
   if(from < 0) return false;
   for(int j = from; j <= to; j++)
      if(src[j] == EMPTY_VALUE) return false;
   return true;
}

//+------------------------------------------------------------------+
double MaAt(const ENUM_CUSTOM_MA type, const int period, const double alpha,
            const double &src[], const int i)
{
   if(i <= 0 || src[i] == EMPTY_VALUE) return src[MathMax(i, 0)];
   if(type == CMA_EMA || type == CMA_RMA) {
      if(src[i - 1] == EMPTY_VALUE) return src[i];
      return alpha * src[i] + (1.0 - alpha) * g_part[0];
   }
   if(type == CMA_SMA || period <= 1) {
      if(i < period - 1 || !SliceOk(src, i - period + 1, i)) return src[i];
      double sum = 0.0;
      for(int j = i - period + 1; j <= i; j++) sum += src[j];
      return sum / period;
   }

   const int need = TailNeed(type, period);
   const int from = MathMax(0, i - need + 1);
   const int len = i - from + 1;
   if(!SliceOk(src, from, i)) return src[i];
   EnsureWork(len);

   for(int k = 0; k < len; k++) g_slice[k] = src[from + k];

   if(type == CMA_WMA) {
      WmaInto(g_slice, g_part, period, len);
      return g_part[len - 1];
   }

   const int half = MathMax(1, period / 2);
   const int smooth = MathMax(1, (int)MathRound(MathSqrt((double)period)));
   WmaInto(g_slice, g_wmaA, half, len);
   WmaInto(g_slice, g_wmaB, MathMax(1, period), len);
   for(int k = 0; k < len; k++) g_raw[k] = 2.0 * g_wmaA[k] - g_wmaB[k];
   WmaInto(g_raw, g_part, smooth, len);
   return g_part[len - 1];
}

//+------------------------------------------------------------------+
void AppendBase(const int i)
{
   if(InpBaseMethod == CMA_EMA || InpBaseMethod == CMA_RMA)
      g_base[i] = g_baseAlpha * g_px[i] + (1.0 - g_baseAlpha) * g_base[i - 1];
   else if(InpBaseMethod == CMA_SMA) {
      if(i < g_basePeriod - 1) g_base[i] = g_px[i];
      else if(i == g_basePeriod - 1) {
         double sum = 0.0;
         for(int j = 0; j <= i; j++) sum += g_px[j];
         g_base[i] = sum / g_basePeriod;
      } else
         g_base[i] = g_base[i - 1] + (g_px[i] - g_px[i - g_basePeriod]) / g_basePeriod;
   } else
      g_base[i] = MaAt(InpBaseMethod, g_basePeriod, g_baseAlpha, g_px, i);
}

//+------------------------------------------------------------------+
double PriceFromRates(const MqlRates &r)
{
   switch(InpAppliedPrice) {
      case PRICE_OPEN:     return r.open;
      case PRICE_HIGH:     return r.high;
      case PRICE_LOW:      return r.low;
      case PRICE_MEDIAN:   return (r.high + r.low) * 0.5;
      case PRICE_TYPICAL:  return (r.high + r.low + r.close) / 3.0;
      case PRICE_WEIGHTED: return (r.high + r.low + 2.0 * r.close) * 0.25;
      default:             return r.close;
   }
}

double PriceFromBar(const int i,
                    const double &open[], const double &high[],
                    const double &low[], const double &close[])
{
   switch(InpAppliedPrice) {
      case PRICE_OPEN:     return open[i];
      case PRICE_HIGH:     return high[i];
      case PRICE_LOW:      return low[i];
      case PRICE_MEDIAN:   return (high[i] + low[i]) * 0.5;
      case PRICE_TYPICAL:  return (high[i] + low[i] + close[i]) / 3.0;
      case PRICE_WEIGHTED: return (high[i] + low[i] + 2.0 * close[i]) * 0.25;
      default:             return close[i];
   }
}

//+------------------------------------------------------------------+
bool PushBar(const datetime t, const double px)
{
   const int i = g_htfCount;
   if(ArraySize(g_px) < i + 1) {
      const int n = i + 128;
      ArrayResize(g_px, n);
      ArrayResize(g_tm, n);
      ArrayResize(g_base, n);
   }
   g_tm[i] = t;
   g_px[i] = px;
   g_htfCount = i + 1;
   if(i == 0) g_base[0] = px;
   else AppendBase(i);
   return true;
}

//+------------------------------------------------------------------+
void ReplaceLastPrice(const double px)
{
   if(g_htfCount <= 0 || g_px[g_htfCount - 1] == px) return;
   const int i = g_htfCount - 1;
   g_px[i] = px;
   if(i == 0) {
      g_base[0] = px;
      return;
   }
   if(InpBaseMethod == CMA_EMA || InpBaseMethod == CMA_RMA)
      g_base[i] = g_baseAlpha * px + (1.0 - g_baseAlpha) * g_base[i - 1];
   else if(InpBaseMethod == CMA_SMA) {
      if(i < g_basePeriod - 1) g_base[i] = px;
      else {
         double sum = 0.0;
         for(int j = i - g_basePeriod + 1; j <= i; j++) sum += g_px[j];
         g_base[i] = sum / g_basePeriod;
      }
   } else
      g_base[i] = MaAt(InpBaseMethod, g_basePeriod, g_baseAlpha, g_px, i);
}

//+------------------------------------------------------------------+
bool LoadRecent(const int barsWanted)
{
   MqlRates rates[];
   const int copied = CopyRates(_Symbol, g_tf, 0, barsWanted, rates);
   if(copied <= 0) return false;
   for(int i = 0; i < copied; i++)
      PushBar(rates[i].time, PriceFromRates(rates[i]));
   return (g_htfCount > 0);
}

//+------------------------------------------------------------------+
bool SyncFromChart(const int rates_total, const datetime &time[],
                   const double &open[], const double &high[],
                   const double &low[], const double &close[],
                   const int limit)
{
   if(g_htfCount == 0) {
      int from = limit - (g_basePeriod + g_smoothPeriod + 5);
      if(from < 0) from = 0;
      for(int i = from; i < rates_total; i++)
         PushBar(time[i], PriceFromBar(i, open, high, low, close));
      return (g_htfCount > 0);
   }
   const datetime lastT = g_tm[g_htfCount - 1];
   int i = rates_total - 1;
   while(i > 0 && time[i] > lastT) i--;
   if(time[i] == lastT)
      ReplaceLastPrice(PriceFromBar(i, open, high, low, close));
   for(int k = i + 1; k < rates_total; k++)
      PushBar(time[k], PriceFromBar(k, open, high, low, close));
   return true;
}

//+------------------------------------------------------------------+
bool SyncFromHtf(const bool allowTickCopy)
{
   if(g_htfCount == 0) {
      const int need = MathMax(InpMaxBars, 100) + g_basePeriod + g_smoothPeriod + 320;
      return LoadRecent(need);
   }
   if(!allowTickCopy) return true;

   MqlRates rates[];
   int copied = CopyRates(_Symbol, g_tf, 0, 2, rates);
   if(copied <= 0) return true;

   const datetime cached = g_tm[g_htfCount - 1];
   if(copied == 2 && rates[0].time > cached) {
      copied = CopyRates(_Symbol, g_tf, 0, 64, rates);
      if(copied <= 0) return true;
   }

   int start = 0;
   while(start < copied && rates[start].time < cached) start++;
   if(start < copied && rates[start].time == cached) {
      ReplaceLastPrice(PriceFromRates(rates[start]));
      start++;
   }
   for(int k = start; k < copied; k++)
      PushBar(rates[k].time, PriceFromRates(rates[k]));
   return true;
}

//+------------------------------------------------------------------+
//| Map the unsmoothed HTF MA onto chart bars. Returns the first    |
//| chart index whose base value was written.                       |
//+------------------------------------------------------------------+
int MapBaseToChart(const datetime &time[], const int rates_total, const int fromBar, const bool rewriteFormingHtf)
{
   if(ArraySize(g_chartBase) < rates_total) {
      const int old = ArraySize(g_chartBase);
      ArrayResize(g_chartBase, rates_total);
      for(int i = old; i < rates_total; i++) g_chartBase[i] = EMPTY_VALUE;
   }
   if(g_htfCount <= 0) return rates_total;

   int i0 = MathMax(0, fromBar);
   if(rewriteFormingHtf) {
      const datetime htfOpen = g_tm[g_htfCount - 1];
      while(i0 > 0 && time[i0 - 1] >= htfOpen) i0--;
   }

   int htf_idx = 0;
   while(htf_idx < g_htfCount - 1 && g_tm[htf_idx + 1] <= time[i0])
      htf_idx++;

   for(int i = i0; i < rates_total; i++) {
      while(htf_idx < g_htfCount - 1 && time[i] >= g_tm[htf_idx + 1])
         htf_idx++;
      g_chartBase[i] = g_base[htf_idx];
   }
   return i0;
}

//+------------------------------------------------------------------+
//| Smooth the mapped chart series. This is what makes smoothing    |
//| visible on a lower-timeframe chart.                             |
//+------------------------------------------------------------------+
void ApplyChartSmooth(const int changedFrom, const int rates_total)
{
   int from = changedFrom;
   if(from < 0) from = 0;
   if(from >= rates_total) return;

   if(g_smoothPeriod <= 1) {
      for(int i = from; i < rates_total; i++)
         BufferMA[i] = g_chartBase[i];
      return;
   }

   if(InpSmoothMethod != CMA_EMA && InpSmoothMethod != CMA_RMA) {
      const int back = TailNeed(InpSmoothMethod, g_smoothPeriod);
      from = MathMax(0, changedFrom - back + 1);
   }

   for(int i = from; i < rates_total; i++) {
      if(g_chartBase[i] == EMPTY_VALUE) {
         BufferMA[i] = EMPTY_VALUE;
         continue;
      }
      if(InpSmoothMethod == CMA_EMA || InpSmoothMethod == CMA_RMA) {
         if(i == 0 || BufferMA[i - 1] == EMPTY_VALUE || g_chartBase[i - 1] == EMPTY_VALUE)
            BufferMA[i] = g_chartBase[i];
         else
            BufferMA[i] = g_smoothAlpha * g_chartBase[i] + (1.0 - g_smoothAlpha) * BufferMA[i - 1];
      } else {
         g_part[0] = (i > 0 ? BufferMA[i - 1] : g_chartBase[i]);
         BufferMA[i] = MaAt(InpSmoothMethod, g_smoothPeriod, g_smoothAlpha, g_chartBase, i);
      }
   }
}

//+------------------------------------------------------------------+
void ActiveAdd(const int idx)
{
   if(g_nActive >= ArraySize(g_active))
      ArrayResize(g_active, g_nActive + 64);
   g_active[g_nActive++] = idx;
}

void ActiveRemoveAt(const int pos)
{
   g_nActive--;
   if(pos != g_nActive) g_active[pos] = g_active[g_nActive];
}

int ActivePos(const int lineIdx)
{
   for(int i = 0; i < g_nActive; i++)
      if(g_active[i] == lineIdx) return i;
   return -1;
}

//+------------------------------------------------------------------+
void DeleteDrawn(const int idx)
{
   if(!g_lines[idx].drawn) return;
   ObjectDelete(0, g_lines[idx].name);
   ObjectDelete(0, g_lines[idx].name + "_LBL");
   g_lines[idx].drawn = false;
}

//+------------------------------------------------------------------+
void RemoveLine(const int idx)
{
   DeleteDrawn(idx);
   const int pos = ActivePos(idx);
   if(pos >= 0) ActiveRemoveAt(pos);

   const int last = ArraySize(g_lines) - 1;
   if(idx != last) {
      g_lines[idx] = g_lines[last];
      const int moved = ActivePos(last);
      if(moved >= 0) g_active[moved] = idx;
   }
   ArrayResize(g_lines, last);
}

//+------------------------------------------------------------------+
void DropOldestActive()
{
   if(g_nActive <= 0) return;
   int oldestPos = 0;
   datetime oldest = g_lines[g_active[0]].startTime;
   for(int i = 1; i < g_nActive; i++) {
      if(g_lines[g_active[i]].startTime < oldest) {
         oldest = g_lines[g_active[i]].startTime;
         oldestPos = i;
      }
   }
   RemoveLine(g_active[oldestPos]);
}

//+------------------------------------------------------------------+
void ClusterActive()
{
   if(!InpEnableClustering || g_nActive < 2) return;
   const double threshold = InpClusterDistancePoints * _Point;

   for(int a = 1; a < g_nActive; a++) {
      const int key = g_active[a];
      const double kp = g_lines[key].price;
      int b = a - 1;
      while(b >= 0 && g_lines[g_active[b]].price > kp) {
         g_active[b + 1] = g_active[b];
         b--;
      }
      g_active[b + 1] = key;
   }

   int s = 0;
   while(s < g_nActive) {
      int e = s;
      while(e + 1 < g_nActive &&
            (g_lines[g_active[e + 1]].price - g_lines[g_active[s]].price) <= threshold)
         e++;
      if(e > s) {
         double sum = 0.0;
         datetime minTime = g_lines[g_active[s]].startTime;
         int survivor = g_active[s];
         for(int k = s; k <= e; k++) {
            sum += g_lines[g_active[k]].price;
            if(g_lines[g_active[k]].startTime < minTime) {
               minTime = g_lines[g_active[k]].startTime;
               survivor = g_active[k];
            }
         }
         g_lines[survivor].price = sum / (e - s + 1);
         if(g_lines[survivor].drawn) {
            ObjectSetDouble(0, g_lines[survivor].name, OBJPROP_PRICE, 0, g_lines[survivor].price);
            ObjectSetDouble(0, g_lines[survivor].name, OBJPROP_PRICE, 1, g_lines[survivor].price);
            const string lbl = g_lines[survivor].name + "_LBL";
            ObjectSetDouble(0, lbl, OBJPROP_PRICE, 0, g_lines[survivor].price);
            ObjectSetString(0, lbl, OBJPROP_TEXT, " " + DoubleToString(g_lines[survivor].price, _Digits));
         }
         for(int k = e; k >= s; k--) {
            if(g_active[k] != survivor) RemoveLine(g_active[k]);
         }
         ClusterActive();
         return;
      }
      s = e + 1;
   }
}

//+------------------------------------------------------------------+
void AddInflection(const datetime timeStart, const double priceLevel, const bool isUpper)
{
   while(g_nActive >= MAX_ACTIVE_LINES) DropOldestActive();

   const int size = ArraySize(g_lines);
   ArrayResize(g_lines, size + 1, 64);
   g_lines[size].name = "";
   g_lines[size].price = priceLevel;
   g_lines[size].startTime = timeStart;
   g_lines[size].mitigatedTime = 0;
   g_lines[size].isMitigated = false;
   g_lines[size].isUpper = isUpper;
   g_lines[size].drawn = false;
   ActiveAdd(size);
   ClusterActive();
}

//+------------------------------------------------------------------+
void MitigateAt(const int idx, const datetime when)
{
   if(idx < 0 || idx >= ArraySize(g_lines) || g_lines[idx].isMitigated) return;
   g_lines[idx].isMitigated = true;
   g_lines[idx].mitigatedTime = when;
   const int pos = ActivePos(idx);
   if(pos >= 0) ActiveRemoveAt(pos);

   if(!g_drawVisuals) {
      RemoveLine(idx);
      return;
   }
   if(g_lines[idx].drawn) {
      ObjectSetInteger(0, g_lines[idx].name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, g_lines[idx].name, OBJPROP_TIME, 1, when);
      ObjectDelete(0, g_lines[idx].name + "_LBL");
   }
}

//+------------------------------------------------------------------+
void PurgeExpired(const datetime now)
{
   if(!g_drawVisuals) return;
   const int expirySec = InpMitigationExpiryMins * 60;
   for(int j = ArraySize(g_lines) - 1; j >= 0; j--) {
      if(!g_lines[j].isMitigated) continue;
      if(now - g_lines[j].mitigatedTime >= expirySec) RemoveLine(j);
   }
}

//+------------------------------------------------------------------+
void EnsureDrawn(const int idx, const datetime anchor)
{
   if(g_lines[idx].drawn) return;
   const string name = "HTF_INFL_" + IntegerToString((long)g_lines[idx].startTime) + "_" + IntegerToString(idx);
   g_lines[idx].name = name;
   const datetime t1 = g_lines[idx].isMitigated ? g_lines[idx].mitigatedTime : (g_lines[idx].startTime + g_tfSec);
   ObjectCreate(0, name, OBJ_TREND, 0, g_lines[idx].startTime, g_lines[idx].price, t1, g_lines[idx].price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, InpDimColor);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, !g_lines[idx].isMitigated);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);

   if(!g_lines[idx].isMitigated) {
      const string lbl = name + "_LBL";
      ObjectCreate(0, lbl, OBJ_TEXT, 0, anchor, g_lines[idx].price);
      ObjectSetInteger(0, lbl, OBJPROP_COLOR, InpLabelDim);
      ObjectSetString(0, lbl, OBJPROP_TEXT, " " + DoubleToString(g_lines[idx].price, _Digits));
      ObjectSetString(0, lbl, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, lbl, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, lbl, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0, lbl, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, lbl, OBJPROP_HIDDEN, true);
   }
   g_lines[idx].drawn = true;
}

//+------------------------------------------------------------------+
void SyncObjects(const datetime anchor, const bool moveLabels)
{
   if(!g_drawVisuals) return;

   int drawn = 0;
   for(int i = 0; i < g_nActive && drawn < MAX_DRAWN_LINES; i++) {
      const int idx = g_active[i];
      const bool wasDrawn = g_lines[idx].drawn;
      EnsureDrawn(idx, anchor);
      if(moveLabels && wasDrawn && g_lines[idx].drawn && !g_lines[idx].isMitigated)
         ObjectSetInteger(0, g_lines[idx].name + "_LBL", OBJPROP_TIME, 0, anchor);
      drawn++;
   }
   if(g_nActive > MAX_DRAWN_LINES) {
      for(int i = MAX_DRAWN_LINES; i < g_nActive; i++)
         DeleteDrawn(g_active[i]);
   }
}

//+------------------------------------------------------------------+
void ScanBar(const int i, const datetime &time[], const double &high[],
             const double &low[], const double &close[])
{
   if(i < 2) return;
   if(BufferMA[i - 2] != EMPTY_VALUE && BufferMA[i - 1] != EMPTY_VALUE && BufferMA[i] != EMPTY_VALUE) {
      if(BufferMA[i - 1] > BufferMA[i - 2] && BufferMA[i - 1] > BufferMA[i]) {
         g_pending_peak_idx = i - 1;
         g_candles_below = 0;
      } else if(BufferMA[i - 1] < BufferMA[i - 2] && BufferMA[i - 1] < BufferMA[i]) {
         g_pending_trough_idx = i - 1;
         g_candles_above = 0;
      }
   }

   if(close[i] < BufferMA[i]) g_candles_below++; else g_candles_below = 0;
   if(close[i] > BufferMA[i]) g_candles_above++; else g_candles_above = 0;

   if(g_pending_peak_idx != -1 && g_candles_below >= InpPivotCandles) {
      AddInflection(time[g_pending_peak_idx],
                    BufferMA[g_pending_peak_idx] + InpLineOffsetPoints * _Point, true);
      g_pending_peak_idx = -1;
   }
   if(g_pending_trough_idx != -1 && g_candles_above >= InpPivotCandles) {
      AddInflection(time[g_pending_trough_idx],
                    BufferMA[g_pending_trough_idx] - InpLineOffsetPoints * _Point, false);
      g_pending_trough_idx = -1;
   }

   for(int a = g_nActive - 1; a >= 0; a--) {
      const int j = g_active[a];
      if(time[i] <= g_lines[j].startTime) continue;
      if(high[i] >= g_lines[j].price && low[i] <= g_lines[j].price)
         MitigateAt(j, time[i]);
   }
   if((i & 15) == 0) PurgeExpired(time[i]);
}

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
   if(rates_total < 3) return(0);

   const datetime barTime = time[rates_total - 1];
   const bool sameBar = (prev_calculated > 0 && prev_calculated == rates_total && barTime == g_lastChartBar);

   if(sameBar && g_isTester && !g_drawVisuals)
      return(rates_total);

   if(prev_calculated == 0) {
      ArrayResize(g_lines, 0);
      g_nActive = 0;
      g_last_checked_bar = 2;
      g_pending_peak_idx = -1;
      g_pending_trough_idx = -1;
      g_candles_below = 0;
      g_candles_above = 0;
      ResetSeries();
      ArrayInitialize(BufferMA, EMPTY_VALUE);
      if(g_drawVisuals) ObjectsDeleteAll(0, "HTF_INFL_");
   }

   int limit = (prev_calculated == 0) ? 0 : prev_calculated - 1;
   if(prev_calculated == 0 && InpMaxBars > 0 && rates_total > InpMaxBars)
      limit = rates_total - InpMaxBars;
   if(limit < 2) limit = 2;

   bool ready = false;
   if(g_sameTf)
      ready = SyncFromChart(rates_total, time, open, high, low, close, limit);
   else {
      const bool needCopy = (!sameBar) || !g_isTester;
      ready = SyncFromHtf(needCopy || g_htfCount == 0);
   }
   if(!ready) return(rates_total);

   const bool full = (prev_calculated == 0);
   const int mapFrom = full ? limit : (sameBar ? rates_total - 1 : prev_calculated - 1);
   const int changed = MapBaseToChart(time, rates_total, mapFrom, !full);
   ApplyChartSmooth(changed, rates_total);

   if(full || !sameBar) {
      if(g_last_checked_bar < limit) g_last_checked_bar = limit;
      if(g_last_checked_bar < 2) g_last_checked_bar = 2;
      for(int i = g_last_checked_bar; i < rates_total - 1; i++)
         ScanBar(i, time, high, low, close);
      g_last_checked_bar = rates_total - 1;
   }

   g_lastChartBar = barTime;

   const int cur = rates_total - 1;
   if(g_nActive > 0) {
      for(int a = g_nActive - 1; a >= 0; a--) {
         const int j = g_active[a];
         if(barTime > g_lines[j].startTime && high[cur] >= g_lines[j].price && low[cur] <= g_lines[j].price)
            MitigateAt(j, barTime);
      }
   }
   PurgeExpired(barTime);
   if(g_drawVisuals && !sameBar)
      SyncObjects(barTime, true);

   return(rates_total);
}
//+------------------------------------------------------------------+