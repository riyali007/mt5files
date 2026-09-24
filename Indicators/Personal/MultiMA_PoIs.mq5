//+------------------------------------------------------------------+
//|                                                 MultiMA_PoIs.mq5 |
//|                    3x HMA inflection rays that freeze on touch   |
//+------------------------------------------------------------------+
#property copyright "Riy Ali"
#property version   "1.33"
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   3

#property indicator_label1  "HMA 1"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

#property indicator_label2  "HMA 2"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrange
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

#property indicator_label3  "HMA 3"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrOrchid
#property indicator_style3  STYLE_SOLID
#property indicator_width3  2

input group "=== Touch rules (shared) ==="
input bool            InpUseWicks        = true;
input bool            InpIgnoreCurrent   = true;
input int             InpLineWidth       = 1;
input int             InpNearWidth       = 2;
input ENUM_LINE_STYLE InpLineStyle       = STYLE_SOLID;
input bool            InpShowLabels      = false;
input int             InpRemoveAfterMin  = 20;    // minutes to keep a mitigated PoI (0 = delete immediately)

input group "=== Proximity highlight ==="
input color           InpDimColor        = C'32,32,32';
input int             InpAtrPeriod       = 14;
input double          InpNearAtrMult     = 1.0;   // highlight if |level-price| <= ATR*mult
input int             InpNearPoints      = 0;     // extra floor in points (0 = ATR only)

input group "=== HMA 1 ==="
input bool            InpHma1On          = true;
input bool            InpHma1InfOn       = true;
input int             InpHma1Period      = 21;
input color           InpHma1Color       = clrDodgerBlue;
input color           InpHma1InfHiColor  = clrDodgerBlue;
input color           InpHma1InfLoColor  = clrDeepSkyBlue;

input group "=== HMA 2 ==="
input bool            InpHma2On          = true;
input bool            InpHma2InfOn       = true;
input int             InpHma2Period      = 55;
input color           InpHma2Color       = clrOrange;
input color           InpHma2InfHiColor  = clrOrange;
input color           InpHma2InfLoColor  = clrGold;

input group "=== HMA 3 ==="
input bool            InpHma3On          = true;
input bool            InpHma3InfOn       = true;
input int             InpHma3Period      = 89;
input color           InpHma3Color       = clrOrchid;
input color           InpHma3InfHiColor  = clrOrchid;
input color           InpHma3InfLoColor  = clrViolet;

input group "=== HMA inflection storage ==="
input int             InpMaxInflections  = 60;

#define PREFIX_H1  "HMA1INF_"
#define PREFIX_H2  "HMA2INF_"
#define PREFIX_H3  "HMA3INF_"

enum ENUM_SWING_TYPE
  {
   SWING_HIGH = 1,
   SWING_LOW  = -1
  };

enum ENUM_LEVEL_GROUP
  {
   GRP_SWING = 0,
   GRP_HMA1  = 1,
   GRP_HMA2  = 2,
   GRP_HMA3  = 3
  };

struct Level
  {
   datetime          time_start;
   datetime          time_end;
   datetime          drawn_end;
   double            price;
   ENUM_SWING_TYPE   type;
   ENUM_LEVEL_GROUP  group;
   bool              frozen;
   bool              drawn;
   bool              near;
   color             drawn_color;
   int               drawn_width;
   string            name;
  };

double g_plot1[];
double g_plot2[];
double g_plot3[];

double g_work1[];
double g_work2[];
double g_work3[];
double g_raw1[];
double g_raw2[];
double g_raw3[];

Level  g_inf1[];
int    g_inf1_count = 0;
Level  g_inf2[];
int    g_inf2_count = 0;
Level  g_inf3[];
int    g_inf3_count = 0;

datetime g_last_bar = 0;
bool     g_dirty    = false;

int      g_lb1 = 0;
int      g_lb2 = 0;
int      g_lb3 = 0;
double   g_wma_den1 = 0.0;
double   g_wma_den2 = 0.0;
double   g_wma_den3 = 0.0;
double   g_wma_den_h1 = 0.0;
double   g_wma_den_h2 = 0.0;
double   g_wma_den_h3 = 0.0;
int      g_half1 = 0, g_half2 = 0, g_half3 = 0;
int      g_hull1 = 0, g_hull2 = 0, g_hull3 = 0;
int      g_atr_handle = INVALID_HANDLE;

#define MAX_GONE 1024
string   g_gone_ids[];
int      g_gone_count = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpMaxInflections < 1 || InpRemoveAfterMin < 0)
      return(INIT_PARAMETERS_INCORRECT);
   if(InpHma1Period < 2 || InpHma2Period < 2 || InpHma3Period < 2)
      return(INIT_PARAMETERS_INCORRECT);

   SetIndexBuffer(0, g_plot1, INDICATOR_DATA);
   SetIndexBuffer(1, g_plot2, INDICATOR_DATA);
   SetIndexBuffer(2, g_plot3, INDICATOR_DATA);
   ArraySetAsSeries(g_plot1, true);
   ArraySetAsSeries(g_plot2, true);
   ArraySetAsSeries(g_plot3, true);

   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, InpHma1On ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(1, PLOT_DRAW_TYPE, InpHma2On ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(2, PLOT_DRAW_TYPE, InpHma3On ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpHma1Color);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, InpHma2Color);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, InpHma3Color);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   ArrayResize(g_inf1, InpMaxInflections);
   ArrayResize(g_inf2, InpMaxInflections);
   ArrayResize(g_inf3, InpMaxInflections);
   ArrayResize(g_gone_ids, MAX_GONE);
   g_gone_count = 0;

   g_half1 = MathMax(InpHma1Period / 2, 1);
   g_half2 = MathMax(InpHma2Period / 2, 1);
   g_half3 = MathMax(InpHma3Period / 2, 1);
   g_hull1 = MathMax((int)MathRound(MathSqrt((double)InpHma1Period)), 1);
   g_hull2 = MathMax((int)MathRound(MathSqrt((double)InpHma2Period)), 1);
   g_hull3 = MathMax((int)MathRound(MathSqrt((double)InpHma3Period)), 1);
   g_lb1 = InpHma1Period + g_hull1 + 2;
   g_lb2 = InpHma2Period + g_hull2 + 2;
   g_lb3 = InpHma3Period + g_hull3 + 2;
   g_wma_den1 = WmaDenom(InpHma1Period);
   g_wma_den2 = WmaDenom(InpHma2Period);
   g_wma_den3 = WmaDenom(InpHma3Period);
   g_wma_den_h1 = WmaDenom(g_hull1);
   g_wma_den_h2 = WmaDenom(g_hull2);
   g_wma_den_h3 = WmaDenom(g_hull3);

   g_atr_handle = iATR(_Symbol, PERIOD_CURRENT, InpAtrPeriod);

   IndicatorSetString(INDICATOR_SHORTNAME, "MultiMA PoIs");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, PREFIX_H1);
   ObjectsDeleteAll(0, PREFIX_H2);
   ObjectsDeleteAll(0, PREFIX_H3);
   if(g_atr_handle != INVALID_HANDLE)
      IndicatorRelease(g_atr_handle);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
double WmaDenom(const int period)
  {
   return(period * (period + 1) * 0.5);
  }

//+------------------------------------------------------------------+
string GoneKey(const datetime t, const ENUM_SWING_TYPE type, const ENUM_LEVEL_GROUP grp)
  {
   return(IntegerToString((int)grp) + "|" + IntegerToString((int)type) + "|" + TimeToString(t, TIME_DATE|TIME_SECONDS));
  }

//+------------------------------------------------------------------+
bool IsGone(const datetime t, const ENUM_SWING_TYPE type, const ENUM_LEVEL_GROUP grp)
  {
   string key = GoneKey(t, type, grp);
   for(int i = 0; i < g_gone_count; i++)
      if(g_gone_ids[i] == key)
         return(true);
   return(false);
  }

//+------------------------------------------------------------------+
void MarkGone(const datetime t, const ENUM_SWING_TYPE type, const ENUM_LEVEL_GROUP grp)
  {
   if(IsGone(t, type, grp))
      return;
   if(g_gone_count >= MAX_GONE)
     {
      for(int i = 1; i < g_gone_count; i++)
         g_gone_ids[i - 1] = g_gone_ids[i];
      g_gone_count--;
     }
   g_gone_ids[g_gone_count++] = GoneKey(t, type, grp);
  }

//+------------------------------------------------------------------+
bool ReadyToRemove(const Level &lvl)
  {
   if(!lvl.frozen)
      return(false);
   int wait = InpRemoveAfterMin * 60;
   return((TimeCurrent() - lvl.time_end) >= wait);
  }

//+------------------------------------------------------------------+
void DeleteLevelObject(const Level &lvl)
  {
   ObjectDelete(0, lvl.name);
   ObjectDelete(0, lvl.name + "_L");
  }

//+------------------------------------------------------------------+
void RemoveAt(Level &arr[], int &count, const int idx)
  {
   if(idx < 0 || idx >= count)
      return;
   DeleteLevelObject(arr[idx]);
   MarkGone(arr[idx].time_start, arr[idx].type, arr[idx].group);
   for(int n = idx + 1; n < count; n++)
      arr[n - 1] = arr[n];
   count--;
   g_dirty = true;
  }

//+------------------------------------------------------------------+
void PurgeMitigated(Level &arr[], int &count)
  {
   for(int n = count - 1; n >= 0; n--)
     {
      if(ReadyToRemove(arr[n]))
         RemoveAt(arr, count, n);
     }
  }

//+------------------------------------------------------------------+
double NearDistance()
  {
   double dist = 0.0;
   if(g_atr_handle != INVALID_HANDLE && InpNearAtrMult > 0.0)
     {
      double atr[1];
      if(CopyBuffer(g_atr_handle, 0, 0, 1, atr) == 1 && atr[0] > 0.0)
         dist = atr[0] * InpNearAtrMult;
     }
   if(InpNearPoints > 0)
     {
      double pts = (double)InpNearPoints * _Point;
      if(pts > dist)
         dist = pts;
     }
   if(dist <= 0.0)
      dist = 50.0 * _Point;
   return(dist);
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
   int need = MathMax(g_lb1, MathMax(g_lb2, g_lb3));
   if(rates_total < need)
      return(0);

   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   const bool new_bar = (g_last_bar != time[0]);
   g_last_bar = time[0];
   g_dirty = false;

   const bool full = (prev_calculated == 0);
   int copy1 = 0, copy2 = 0, copy3 = 0;

   if(InpHma1On)
      copy1 = CalcHma(g_work1, g_raw1, close, rates_total, full,
                      InpHma1Period, g_half1, g_hull1, g_wma_den1, g_wma_den_h1);
   else
      ClearPlot(g_plot1, rates_total, full);

   if(InpHma2On)
      copy2 = CalcHma(g_work2, g_raw2, close, rates_total, full,
                      InpHma2Period, g_half2, g_hull2, g_wma_den2, g_wma_den_h2);
   else
      ClearPlot(g_plot2, rates_total, full);

   if(InpHma3On)
      copy3 = CalcHma(g_work3, g_raw3, close, rates_total, full,
                      InpHma3Period, g_half3, g_hull3, g_wma_den3, g_wma_den_h3);
   else
      ClearPlot(g_plot3, rates_total, full);

   if(InpHma1On)
      CopyWork(g_work1, g_plot1, copy1);
   if(InpHma2On)
      CopyWork(g_work2, g_plot2, copy2);
   if(InpHma3On)
      CopyWork(g_work3, g_plot3, copy3);

   if(full)
     {
      ObjectsDeleteAll(0, PREFIX_H1);
      ObjectsDeleteAll(0, PREFIX_H2);
      ObjectsDeleteAll(0, PREFIX_H3);
      g_inf1_count = 0;
      g_inf2_count = 0;
      g_inf3_count = 0;

      if(InpHma1On && InpHma1InfOn)
         RebuildInflections(g_work1, rates_total, g_lb1, GRP_HMA1, PREFIX_H1,
                            g_inf1, g_inf1_count, time, open, high, low, close);
      if(InpHma2On && InpHma2InfOn)
         RebuildInflections(g_work2, rates_total, g_lb2, GRP_HMA2, PREFIX_H2,
                            g_inf2, g_inf2_count, time, open, high, low, close);
      if(InpHma3On && InpHma3InfOn)
         RebuildInflections(g_work3, rates_total, g_lb3, GRP_HMA3, PREFIX_H3,
                            g_inf3, g_inf3_count, time, open, high, low, close);

      PurgeMitigated(g_inf1, g_inf1_count);
      PurgeMitigated(g_inf2, g_inf2_count);
      PurgeMitigated(g_inf3, g_inf3_count);
      ApplyProximity(close[0]);
      g_dirty = true;
      DrawAllLevels();
      return(rates_total);
     }

   if(new_bar)
     {
      if(InpHma1On && InpHma1InfOn)
         TryAddConfirmedInflection(g_work1, GRP_HMA1, PREFIX_H1, g_inf1, g_inf1_count, time);
      if(InpHma2On && InpHma2InfOn)
         TryAddConfirmedInflection(g_work2, GRP_HMA2, PREFIX_H2, g_inf2, g_inf2_count, time);
      if(InpHma3On && InpHma3InfOn)
         TryAddConfirmedInflection(g_work3, GRP_HMA3, PREFIX_H3, g_inf3, g_inf3_count, time);

      const int test_shift = InpIgnoreCurrent ? 1 : 0;
      UpdateInfFast(InpHma1On && InpHma1InfOn, PREFIX_H1, g_inf1, g_inf1_count, test_shift, time, open, high, low, close);
      UpdateInfFast(InpHma2On && InpHma2InfOn, PREFIX_H2, g_inf2, g_inf2_count, test_shift, time, open, high, low, close);
      UpdateInfFast(InpHma3On && InpHma3InfOn, PREFIX_H3, g_inf3, g_inf3_count, test_shift, time, open, high, low, close);
     }

   PurgeMitigated(g_inf1, g_inf1_count);
   PurgeMitigated(g_inf2, g_inf2_count);
   PurgeMitigated(g_inf3, g_inf3_count);
   ApplyProximity(close[0]);

   if(g_dirty)
      DrawAllLevels();
   return(rates_total);
  }

//+------------------------------------------------------------------+
void ApplyProximity(const double px)
  {
   double near = NearDistance();
   MarkNear(g_inf1, g_inf1_count, px, near);
   MarkNear(g_inf2, g_inf2_count, px, near);
   MarkNear(g_inf3, g_inf3_count, px, near);
  }

//+------------------------------------------------------------------+
void MarkNear(Level &arr[], const int count, const double px, const double near)
  {
   for(int n = 0; n < count; n++)
     {
      if(arr[n].frozen)
        {
         if(arr[n].near)
           {
            arr[n].near = false;
            g_dirty = true;
           }
         continue;
        }

      bool is_near = (MathAbs(arr[n].price - px) <= near);
      if(arr[n].near != is_near)
        {
         arr[n].near = is_near;
         g_dirty = true;
        }
     }
  }

//+------------------------------------------------------------------+
void ClearPlot(double &plot[], const int rates_total, const bool full)
  {
   int n = full ? rates_total - 1 : 0;
   for(int i = n; i >= 0; i--)
      plot[i] = EMPTY_VALUE;
  }

//+------------------------------------------------------------------+
void CopyWork(const double &work[], double &plot[], const int last)
  {
   for(int i = last; i >= 0; i--)
      plot[i] = work[i];
  }

//+------------------------------------------------------------------+
bool EnsureSeries(double &a[], const int rates_total)
  {
   if(ArraySize(a) != rates_total)
     {
      ArrayResize(a, rates_total);
      ArraySetAsSeries(a, true);
      return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
int CalcHma(double &work[],
            double &raw[],
            const double &price[],
            const int rates_total,
            const bool full,
            const int period,
            const int half,
            const int hull,
            const double den_full,
            const double den_hull)
  {
   bool resized = EnsureSeries(work, rates_total);
   resized = EnsureSeries(raw, rates_total) || resized;

   int last_raw = rates_total - period;
   int last_hma = rates_total - period - hull;
   if(last_raw < 0 || last_hma < 0)
      return(0);

   int from_raw;
   int from_hma;
   if(full || resized)
     {
      ArrayInitialize(work, EMPTY_VALUE);
      ArrayInitialize(raw, EMPTY_VALUE);
      from_raw = last_raw;
      from_hma = last_hma;
     }
   else
     {
      from_raw = MathMin(hull + 1, last_raw);
      from_hma = 0;
     }

   for(int i = from_raw; i >= 0; i--)
     {
      double wma_half = WMAAt(price, i, half, WmaDenom(half));
      double wma_full = WMAAt(price, i, period, den_full);
      if(wma_half == EMPTY_VALUE || wma_full == EMPTY_VALUE)
         raw[i] = EMPTY_VALUE;
      else
         raw[i] = 2.0 * wma_half - wma_full;
     }

   for(int i = from_hma; i >= 0; i--)
      work[i] = WMAAt(raw, i, hull, den_hull);

   return(from_hma);
  }

//+------------------------------------------------------------------+
double WMAAt(const double &src[], const int pos, const int period, const double denom)
  {
   if(period < 1 || denom <= 0.0)
      return(EMPTY_VALUE);
   if(pos < 0 || pos + period > ArraySize(src))
      return(EMPTY_VALUE);

   double sum = 0.0;
   int w = period;
   for(int k = 0; k < period; k++, w--)
     {
      double v = src[pos + k];
      if(v == EMPTY_VALUE)
         return(EMPTY_VALUE);
      sum += v * (double)w;
     }
   return(sum / denom);
  }

//+------------------------------------------------------------------+
bool IsHmaPeak(const double &hma[], const int i)
  {
   if(i < 1 || i + 1 >= ArraySize(hma))
      return(false);
   double a = hma[i], b = hma[i + 1], c = hma[i - 1];
   if(a == EMPTY_VALUE || b == EMPTY_VALUE || c == EMPTY_VALUE)
      return(false);
   return(a >= b && a > c);
  }

//+------------------------------------------------------------------+
bool IsHmaTrough(const double &hma[], const int i)
  {
   if(i < 1 || i + 1 >= ArraySize(hma))
      return(false);
   double a = hma[i], b = hma[i + 1], c = hma[i - 1];
   if(a == EMPTY_VALUE || b == EMPTY_VALUE || c == EMPTY_VALUE)
      return(false);
   return(a <= b && a < c);
  }

//+------------------------------------------------------------------+
void RebuildInflections(const double &hma[],
                        const int rates_total,
                        const int lookback,
                        const ENUM_LEVEL_GROUP grp,
                        const string prefix,
                        Level &arr[],
                        int &count,
                        const datetime &time[],
                        const double &open[],
                        const double &high[],
                        const double &low[],
                        const double &close[])
  {
   int oldest = rates_total - lookback - 3;
   if(oldest < 3)
      oldest = rates_total - 4;
   int sz = ArraySize(hma);
   if(oldest >= sz)
      oldest = sz - 2;

   for(int i = oldest; i >= 1; i--)
     {
      if(IsHmaPeak(hma, i))
        {
         if(!IsGone(time[i], SWING_HIGH, grp))
           {
            AddLevel(arr, count, InpMaxInflections, prefix, time[i], hma[i], SWING_HIGH, grp);
            ApplyHitScanFull(count - 1, arr, time, open, high, low, close);
            if(count > 0 && ReadyToRemove(arr[count - 1]))
               RemoveAt(arr, count, count - 1);
           }
        }
      if(IsHmaTrough(hma, i))
        {
         if(!IsGone(time[i], SWING_LOW, grp))
           {
            AddLevel(arr, count, InpMaxInflections, prefix, time[i], hma[i], SWING_LOW, grp);
            ApplyHitScanFull(count - 1, arr, time, open, high, low, close);
            if(count > 0 && ReadyToRemove(arr[count - 1]))
               RemoveAt(arr, count, count - 1);
           }
        }
     }
  }

//+------------------------------------------------------------------+
void TryAddConfirmedInflection(const double &hma[],
                               const ENUM_LEVEL_GROUP grp,
                               const string prefix,
                               Level &arr[],
                               int &count,
                               const datetime &time[])
  {
   if(IsHmaPeak(hma, 1) && !IsGone(time[1], SWING_HIGH, grp))
      AddLevel(arr, count, InpMaxInflections, prefix, time[1], hma[1], SWING_HIGH, grp);
   if(IsHmaTrough(hma, 1) && !IsGone(time[1], SWING_LOW, grp))
      AddLevel(arr, count, InpMaxInflections, prefix, time[1], hma[1], SWING_LOW, grp);
  }

//+------------------------------------------------------------------+
void AddLevel(Level &arr[],
              int &count,
              const int max_count,
              const string prefix,
              const datetime t,
              const double price,
              const ENUM_SWING_TYPE type,
              const ENUM_LEVEL_GROUP grp)
  {
   if(price == EMPTY_VALUE)
      return;
   if(IsGone(t, type, grp))
      return;

   for(int n = 0; n < count; n++)
     {
      if(arr[n].time_start == t && arr[n].type == type && arr[n].group == grp)
         return;
     }

   if(count >= max_count)
     {
      ObjectDelete(0, arr[0].name);
      ObjectDelete(0, arr[0].name + "_L");
      for(int n = 1; n < count; n++)
         arr[n - 1] = arr[n];
      count--;
      g_dirty = true;
     }

   Level s;
   s.time_start  = t;
   s.time_end    = t;
   s.drawn_end   = 0;
   s.price       = price;
   s.type        = type;
   s.group       = grp;
   s.frozen      = false;
   s.drawn       = false;
   s.near        = false;
   s.drawn_color = InpDimColor;
   s.drawn_width = InpLineWidth;
   s.name        = prefix + IntegerToString((int)type) + "_" + TimeToString(t, TIME_DATE|TIME_SECONDS);
   arr[count++]  = s;
   g_dirty = true;
  }

//+------------------------------------------------------------------+
void UpdateInfFast(const bool enabled,
                   const string prefix,
                   Level &arr[],
                   int &count,
                   const int test_shift,
                   const datetime &time[],
                   const double &open[],
                   const double &high[],
                   const double &low[],
                   const double &close[])
  {
   if(!enabled)
     {
      if(count > 0)
        {
         ObjectsDeleteAll(0, prefix);
         count = 0;
         g_dirty = true;
        }
      return;
     }
   UpdateActiveFast(arr, count, test_shift, time, open, high, low, close);
  }

//+------------------------------------------------------------------+
void UpdateActiveFast(Level &arr[],
                      const int count,
                      const int test_shift,
                      const datetime &time[],
                      const double &open[],
                      const double &high[],
                      const double &low[],
                      const double &close[])
  {
   datetime t_test = time[test_shift];
   for(int n = 0; n < count; n++)
     {
      if(arr[n].frozen)
         continue;
      if(t_test <= arr[n].time_start)
        {
         arr[n].time_end = arr[n].time_start;
         continue;
        }
      if(PriceHits(arr[n].type, arr[n].price, test_shift, open, high, low, close))
        {
         arr[n].time_end = t_test;
         arr[n].frozen   = true;
         arr[n].near     = false;
         g_dirty = true;
        }
      else if(arr[n].time_end != t_test)
        {
         arr[n].time_end = t_test;
         g_dirty = true;
        }
     }
  }

//+------------------------------------------------------------------+
void ApplyHitScanFull(const int n,
                      Level &arr[],
                      const datetime &time[],
                      const double &open[],
                      const double &high[],
                      const double &low[],
                      const double &close[])
  {
   if(n < 0 || n >= ArraySize(arr))
      return;

   int start_shift = iBarShift(_Symbol, PERIOD_CURRENT, arr[n].time_start, true);
   if(start_shift < 0)
     {
      arr[n].time_end = time[0];
      return;
     }

   int end_shift = InpIgnoreCurrent ? 1 : 0;
   if(end_shift > start_shift)
     {
      arr[n].time_end = time[end_shift];
      return;
     }

   for(int i = start_shift - 1; i >= end_shift; i--)
     {
      if(PriceHits(arr[n].type, arr[n].price, i, open, high, low, close))
        {
         arr[n].time_end = time[i];
         arr[n].frozen   = true;
         arr[n].near     = false;
         return;
        }
     }
   arr[n].time_end = time[end_shift];
   arr[n].frozen   = false;
  }

//+------------------------------------------------------------------+
bool PriceHits(const ENUM_SWING_TYPE type,
               const double price,
               const int i,
               const double &open[],
               const double &high[],
               const double &low[],
               const double &close[])
  {
   if(InpUseWicks)
      return(type == SWING_HIGH ? high[i] >= price : low[i] <= price);

   if(type == SWING_HIGH)
      return(MathMax(open[i], close[i]) >= price);
   return(MathMin(open[i], close[i]) <= price);
  }

//+------------------------------------------------------------------+
color ColorFor(const ENUM_LEVEL_GROUP group, const ENUM_SWING_TYPE type)
  {
   switch(group)
     {
      case GRP_HMA1: return(type == SWING_HIGH ? InpHma1InfHiColor : InpHma1InfLoColor);
      case GRP_HMA2: return(type == SWING_HIGH ? InpHma2InfHiColor : InpHma2InfLoColor);
      case GRP_HMA3: return(type == SWING_HIGH ? InpHma3InfHiColor : InpHma3InfLoColor);
      default:       return(InpDimColor);
     }
  }

//+------------------------------------------------------------------+
void DrawGroup(Level &arr[], const int count)
  {
   for(int n = 0; n < count; n++)
     {
      bool highlight = (arr[n].near && !arr[n].frozen);
      color clr = highlight ? ColorFor(arr[n].group, arr[n].type) : InpDimColor;
      int   w   = highlight ? InpNearWidth : InpLineWidth;

      bool geom_changed = (!arr[n].drawn || arr[n].drawn_end != arr[n].time_end);
      bool vis_changed  = (arr[n].drawn_color != clr || arr[n].drawn_width != w);
      if(!geom_changed && !vis_changed)
         continue;

      datetime t1 = arr[n].time_start;
      datetime t2 = arr[n].time_end;
      if(t2 <= t1)
         t2 = t1 + PeriodSeconds();

      if(ObjectFind(0, arr[n].name) < 0)
        {
         ObjectCreate(0, arr[n].name, OBJ_TREND, 0, t1, arr[n].price, t2, arr[n].price);
         ObjectSetInteger(0, arr[n].name, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, arr[n].name, OBJPROP_RAY_LEFT, false);
         ObjectSetInteger(0, arr[n].name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, arr[n].name, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, arr[n].name, OBJPROP_BACK, true);
         ObjectSetInteger(0, arr[n].name, OBJPROP_STYLE, InpLineStyle);
        }

      if(geom_changed)
        {
         ObjectSetInteger(0, arr[n].name, OBJPROP_TIME, 0, t1);
         ObjectSetInteger(0, arr[n].name, OBJPROP_TIME, 1, t2);
         ObjectSetDouble(0, arr[n].name, OBJPROP_PRICE, 0, arr[n].price);
         ObjectSetDouble(0, arr[n].name, OBJPROP_PRICE, 1, arr[n].price);
        }

      if(vis_changed || !arr[n].drawn)
        {
         ObjectSetInteger(0, arr[n].name, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, arr[n].name, OBJPROP_WIDTH, w);
        }

      if(InpShowLabels)
        {
         string lab = arr[n].name + "_L";
         if(ObjectFind(0, lab) < 0)
           {
            ObjectCreate(0, lab, OBJ_TEXT, 0, t1, arr[n].price);
            ObjectSetInteger(0, lab, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
            ObjectSetInteger(0, lab, OBJPROP_FONTSIZE, 8);
            ObjectSetInteger(0, lab, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, lab, OBJPROP_HIDDEN, true);
            string tag = (arr[n].type == SWING_HIGH ? "HMA H " : "HMA L ");
            ObjectSetString(0, lab, OBJPROP_TEXT, tag + DoubleToString(arr[n].price, _Digits));
           }
         ObjectSetInteger(0, lab, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, lab, OBJPROP_TIME, t1);
         ObjectSetDouble(0, lab, OBJPROP_PRICE, arr[n].price);
        }

      arr[n].drawn       = true;
      arr[n].drawn_end   = arr[n].time_end;
      arr[n].drawn_color = clr;
      arr[n].drawn_width = w;
     }
  }

//+------------------------------------------------------------------+
void DrawAllLevels()
  {
   if(InpHma1On && InpHma1InfOn)
      DrawGroup(g_inf1, g_inf1_count);
   if(InpHma2On && InpHma2InfOn)
      DrawGroup(g_inf2, g_inf2_count);
   if(InpHma3On && InpHma3InfOn)
      DrawGroup(g_inf3, g_inf3_count);
   ChartRedraw();
  }
//+------------------------------------------------------------------+