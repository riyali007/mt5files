//+------------------------------------------------------------------+
//|                                          HMA_Inflection.mq5      |
//|  HMA inflection lines: horizontal, extend until mitigated        |
//|  v1.1 - performance optimized                                    |
//+------------------------------------------------------------------+
#property copyright "Riy Ali"
#property version   "1.10"
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1
#property indicator_label1  "HMA"
#property indicator_type1   DRAW_LINE
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

enum ENUM_INFL_MODE { INFL_SLOPE_FLIP = 0,   // Slope flip (HMA peak / trough)
                      INFL_CURVATURE  = 1 }; // Curvature change (2nd derivative)
enum ENUM_MIT_MODE  { MIT_WICK        = 0,   // Wick touch (high/low)
                      MIT_BODY_CLOSE  = 1 }; // Candle close beyond line

input group "HMA"
input int                InpPeriod        = 14;            // HMA period
input ENUM_APPLIED_PRICE InpPrice         = PRICE_CLOSE;   // Applied price
input bool               InpShowHMA       = true;          // Show HMA line
input color              InpHmaColor      = clrDodgerBlue; // HMA color

input group "Inflection"
input ENUM_INFL_MODE     InpInflMode      = INFL_SLOPE_FLIP; // Inflection definition
input int                InpLookbackBars  = 1000;          // Bars to scan for lines
input int                InpOffsetPoints  = 0;             // Line offset (points, +/-)
input int                InpMaxLines      = 100;           // Max lines kept

input group "Mitigation"
input ENUM_MIT_MODE      InpMitMode       = MIT_WICK;      // Mitigation test
input int                InpKeepMinutes   = 30;            // Keep mitigated line (server min)

input group "Appearance"
input color              InpDarkColor     = C'60,60,60';   // Line color (far from price)
input color              InpLightColor    = clrYellow;     // Line color (price near)
input color              InpMitColor      = clrGray;       // Mitigated line color
input int                InpLineWidth     = 1;             // Line width (1 = dashed visible)
input int                InpATRPeriod     = 14;            // ATR period (proximity)
input double             InpProxATRMult   = 0.5;           // Near distance = ATR x this

input group "Label"
input bool               InpShowLabel     = true;          // Show price label
input color              InpLabelColor    = clrOrange;     // Label color
input int                InpLabelSize     = 8;             // Label font size
input int                InpLabelShiftBars= 3;             // Label shift right (bars)

input group "Chart theme"
input bool   InpApplyBlackTheme   = true;
input color  InpBullCandleColor   = C'38,166,154';   // teal
input color  InpBearCandleColor   = C'239,83,80';    // red
struct SLine
{
   long     id;
   double   price;
   datetime t_start;
   datetime t_check;
   datetime t_mit;
   bool     mitigated;
   bool     created;
   int      side;
   int      state;     // -1 new, 0 dark, 1 light, 2 mitigated
   string   nameL;
   string   nameT;
   string   text;
};

#define PFX "HIFX_"

double   ExtBuffer[];
double   gp[], graw[], ghma[];
SLine    g_lines[];
long     g_nextId   = 1;
int      g_valid    = 0;
int      g_lastRates= 0;
int      g_nMit     = 0;
datetime g_scanTime = 0;
double   g_atr      = 0.0;
datetime g_lastBarTime = 0;
int      g_period, g_sqrtP, g_half, g_psec;
double   g_denHalf, g_denFull, g_denSqrt;

//+------------------------------------------------------------------+
double PriceAt(int i, const double &o[], const double &h[], const double &l[], const double &c[])
{
   switch(InpPrice)
   {
      case PRICE_OPEN:     return o[i];
      case PRICE_HIGH:     return h[i];
      case PRICE_LOW:      return l[i];
      case PRICE_MEDIAN:   return (h[i]+l[i])*0.5;
      case PRICE_TYPICAL:  return (h[i]+l[i]+c[i])/3.0;
      case PRICE_WEIGHTED: return (h[i]+l[i]+2.0*c[i])*0.25;
   }
   return c[i];
}

double WMA(const double &arr[], int idx, int n, double den)
{
   double s = 0.0;
   for(int k = 0; k < n; k++) s += arr[idx-k] * (n-k);
   return s / den;
}
//+------------------------------------------------------------------+
void ApplyBlackChartTheme()
{
   long chartId = ChartID();
   ChartSetInteger(chartId, CHART_MODE, CHART_CANDLES);
   ChartSetInteger(chartId, CHART_COLOR_BACKGROUND,   C'14,14,14');
   ChartSetInteger(chartId, CHART_COLOR_FOREGROUND,   C'200,200,200');
   ChartSetInteger(chartId, CHART_COLOR_GRID,         C'28,28,28');
   ChartSetInteger(chartId, CHART_COLOR_CHART_UP,     InpBullCandleColor);
   ChartSetInteger(chartId, CHART_COLOR_CHART_DOWN,   InpBearCandleColor);
   ChartSetInteger(chartId, CHART_COLOR_CANDLE_BULL,  InpBullCandleColor);
   ChartSetInteger(chartId, CHART_COLOR_CANDLE_BEAR,  InpBearCandleColor);
   ChartSetInteger(chartId, CHART_COLOR_CHART_LINE,   C'200,200,200');
   ChartSetInteger(chartId, CHART_COLOR_VOLUME,       C'90,90,90');
   ChartSetInteger(chartId, CHART_COLOR_BID,          C'90,90,90');
   ChartSetInteger(chartId, CHART_COLOR_ASK,          C'90,90,90');
   ChartSetInteger(chartId, CHART_COLOR_LAST,         C'90,90,90');
   ChartSetInteger(chartId, CHART_COLOR_STOP_LEVEL,   C'120,40,40');
   ChartSetInteger(chartId, CHART_SHOW_GRID,          true);
   ChartSetInteger(chartId, CHART_SHOW_VOLUMES,       false);
   ChartRedraw(chartId);
}


//+------------------------------------------------------------------+
int OnInit()
{
   if(InpApplyBlackTheme) ApplyBlackChartTheme();
   g_period = MathMax(InpPeriod, 4);
   g_half   = g_period / 2;
   g_sqrtP  = (int)MathFloor(MathSqrt((double)g_period));
   g_denHalf= g_half   * (g_half+1)   / 2.0;
   g_denFull= g_period * (g_period+1) / 2.0;
   g_denSqrt= g_sqrtP  * (g_sqrtP+1)  / 2.0;
   g_psec   = PeriodSeconds();

   SetIndexBuffer(0, ExtBuffer, INDICATOR_DATA);
   ArraySetAsSeries(ExtBuffer, false);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpHmaColor);
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, InpShowHMA ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   IndicatorSetString(INDICATOR_SHORTNAME, "HMA Inflection(" + IntegerToString(g_period) + ")");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   EventSetTimer(1);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, PFX);
   ChartRedraw();
}

//+------------------------------------------------------------------+
void RemoveLine(int idx)
{
   if(g_lines[idx].created)
   {
      ObjectDelete(0, g_lines[idx].nameL);
      if(InpShowLabel) ObjectDelete(0, g_lines[idx].nameT);
   }
   if(g_lines[idx].mitigated) g_nMit--;
   int n = ArraySize(g_lines);
   for(int i = idx; i < n-1; i++) g_lines[i] = g_lines[i+1];
   ArrayResize(g_lines, n-1);
}

void AddLine(double price, datetime t_start, datetime t_confirm, int side)
{
   int n = ArraySize(g_lines);
   ArrayResize(g_lines, n+1, 128);
   g_lines[n].id        = g_nextId++;
   g_lines[n].price     = NormalizeDouble(price, _Digits);
   g_lines[n].t_start   = t_start;
   g_lines[n].t_check   = t_confirm;
   g_lines[n].t_mit     = 0;
   g_lines[n].mitigated = false;
   g_lines[n].created   = false;
   g_lines[n].side      = side;
   g_lines[n].state     = -1;
   g_lines[n].nameL     = PFX + "L_" + IntegerToString(g_lines[n].id);
   g_lines[n].nameT     = PFX + "T_" + IntegerToString(g_lines[n].id);
   g_lines[n].text      = DoubleToString(g_lines[n].price, _Digits);
}

//+------------------------------------------------------------------+
// Full check - run once per new bar
void CheckMitigationFull(const int rates_total, const datetime &time[],
                         const double &high[], const double &low[], const double &close[])
{
   if(rates_total < 3) return;
   int endBar = (InpMitMode == MIT_WICK) ? rates_total-1 : rates_total-2;
   datetime tClosed = time[rates_total-2];

   for(int li = 0; li < ArraySize(g_lines); li++)
   {
      if(g_lines[li].mitigated) continue;
      int s = ArrayBsearch(time, g_lines[li].t_check) + 1;
      if(s < 1) s = 1;
      double lv = g_lines[li].price;
      int    sd = g_lines[li].side;
      for(int b = s; b <= endBar; b++)
      {
         bool hit;
         if(InpMitMode == MIT_WICK) hit = (sd > 0) ? (low[b] <= lv) : (high[b] >= lv);
         else                       hit = (sd > 0) ? (close[b] <= lv) : (close[b] >= lv);
         if(hit)
         {
            g_lines[li].mitigated = true;
            g_nMit++;
            g_lines[li].t_mit = (b == rates_total-1) ? TimeCurrent() : time[b] + g_psec;
            break;
         }
      }
      if(!g_lines[li].mitigated) g_lines[li].t_check = tClosed;
   }
}

// Light check - every tick, forming bar only, wick mode only
void CheckMitigationTick(const double hi, const double lo)
{
   if(InpMitMode != MIT_WICK) return;
   for(int li = ArraySize(g_lines)-1; li >= 0; li--)
   {
      if(g_lines[li].mitigated) continue;
      double lv = g_lines[li].price;
      bool hit = (g_lines[li].side > 0) ? (lo <= lv) : (hi >= lv);
      if(hit)
      {
         g_lines[li].mitigated = true;
         g_lines[li].t_mit = TimeCurrent();
         g_nMit++;
      }
   }
}

bool ExpireAndTrim()
{
   bool removed = false;
   if(g_nMit > 0)
   {
      datetime now = TimeCurrent();
      long keep = (long)InpKeepMinutes * 60;
      for(int i = ArraySize(g_lines)-1; i >= 0; i--)
         if(g_lines[i].mitigated && (now - g_lines[i].t_mit) >= keep)
         { RemoveLine(i); removed = true; }
   }
   while(ArraySize(g_lines) > InpMaxLines) { RemoveLine(0); removed = true; }
   return removed;
}

//+------------------------------------------------------------------+
// Touches chart objects only when something actually changed
void DrawLines(bool newBar, bool force)
{
   int n = ArraySize(g_lines);
   if(n == 0) { if(force) ChartRedraw(); return; }

   bool changed = force;
   double px    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double nearD = g_atr * InpProxATRMult;
   datetime lblT = g_lastBarTime + (datetime)(g_psec * MathMax(InpLabelShiftBars, 0));

   for(int i = 0; i < n; i++)
   {
      double p = g_lines[i].price;

      if(!g_lines[i].created)
      {
         string ln = g_lines[i].nameL;
         ObjectCreate(0, ln, OBJ_TREND, 0, g_lines[i].t_start, p, g_lines[i].t_start + g_psec, p);
         ObjectSetInteger(0, ln, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, ln, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, ln, OBJPROP_BACK, true);
         ObjectSetInteger(0, ln, OBJPROP_RAY_RIGHT, true);
         ObjectSetInteger(0, ln, OBJPROP_WIDTH, InpLineWidth);
         if(InpShowLabel)
         {
            string tn = g_lines[i].nameT;
            ObjectCreate(0, tn, OBJ_TEXT, 0, lblT, p);
            ObjectSetInteger(0, tn, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, tn, OBJPROP_HIDDEN, true);
            ObjectSetInteger(0, tn, OBJPROP_ANCHOR, ANCHOR_LEFT);
            ObjectSetString (0, tn, OBJPROP_TEXT, g_lines[i].text);
            ObjectSetInteger(0, tn, OBJPROP_COLOR, InpLabelColor);
            ObjectSetInteger(0, tn, OBJPROP_FONTSIZE, InpLabelSize);
         }
         g_lines[i].created = true;
         changed = true;
      }

      int st;
      if(g_lines[i].mitigated) st = 2;
      else st = (nearD > 0.0 && MathAbs(px - p) <= nearD) ? 1 : 0;

      if(st != g_lines[i].state)
      {
         string ln = g_lines[i].nameL;
         if(st == 2)
         {
            ObjectSetInteger(0, ln, OBJPROP_TIME, 1, g_lines[i].t_mit);
            ObjectSetInteger(0, ln, OBJPROP_RAY_RIGHT, false);
            ObjectSetInteger(0, ln, OBJPROP_COLOR, InpMitColor);
            ObjectSetInteger(0, ln, OBJPROP_STYLE, STYLE_DOT);
            if(InpShowLabel) ObjectSetInteger(0, g_lines[i].nameT, OBJPROP_TIME, 0, g_lines[i].t_mit);
         }
         else
         {
            ObjectSetInteger(0, ln, OBJPROP_COLOR, st == 1 ? InpLightColor : InpDarkColor);
            ObjectSetInteger(0, ln, OBJPROP_STYLE, STYLE_DASH);
         }
         g_lines[i].state = st;
         changed = true;
      }
      else if(newBar && st != 2 && InpShowLabel)
      {
         ObjectSetInteger(0, g_lines[i].nameT, OBJPROP_TIME, 0, lblT);
         changed = true;
      }
   }
   if(changed) ChartRedraw();
}

//+------------------------------------------------------------------+
void OnTimer()
{
   if(ArraySize(g_lines) == 0) return;
   bool removed = ExpireAndTrim();
   DrawLines(false, removed);
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[], const double &high[],
                const double &low[], const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[])
{
   if(rates_total < g_period + g_sqrtP + 10) return 0;

   bool isFirst = (prev_calculated == 0);
   bool newBar  = isFirst || (rates_total != g_lastRates);
   g_lastRates  = rates_total;

   int calcStart;
   if(isFirst)
   {
      ObjectsDeleteAll(0, PFX);
      ArrayResize(g_lines, 0);
      g_nMit = 0;
      g_scanTime = 0;
      ArrayInitialize(ExtBuffer, EMPTY_VALUE);
      int base = MathMax(0, rates_total - InpLookbackBars - g_period - g_sqrtP - 10);
      calcStart = base;
      g_valid   = base + g_period - 1 + g_sqrtP - 1;
   }
   else
      calcStart = MathMax(prev_calculated - 1, 0);

   if(newBar)
   {
      ArrayResize(gp,   rates_total, 1000);
      ArrayResize(graw, rates_total, 1000);
      ArrayResize(ghma, rates_total, 1000);
   }

   for(int i = calcStart; i < rates_total; i++)
      gp[i] = PriceAt(i, open, high, low, close);

   int rawValid = g_valid - g_sqrtP + 1;
   for(int i = MathMax(calcStart, rawValid); i < rates_total; i++)
      graw[i] = 2.0 * WMA(gp, i, g_half, g_denHalf) - WMA(gp, i, g_period, g_denFull);

   for(int i = MathMax(calcStart, g_valid); i < rates_total; i++)
   {
      ghma[i] = WMA(graw, i, g_sqrtP, g_denSqrt);
      ExtBuffer[i] = ghma[i];
   }

   g_lastBarTime = time[rates_total-1];

   if(!newBar)
   {
      // tick path: no scan, no ATR, forming-bar mitigation only
      if(ArraySize(g_lines) > 0)
      {
         int before = g_nMit;
         CheckMitigationTick(high[rates_total-1], low[rates_total-1]);
         DrawLines(false, before != g_nMit);
      }
      return rates_total;
   }

   // ---- new bar path ----
   int lastClosed = rates_total - 2;

   double sum = 0.0; int cnt = 0;
   for(int i = lastClosed; i > lastClosed - InpATRPeriod && i > 0; i--)
   {
      double tr = MathMax(high[i]-low[i], MathMax(MathAbs(high[i]-close[i-1]), MathAbs(low[i]-close[i-1])));
      sum += tr; cnt++;
   }
   if(cnt > 0) g_atr = sum / cnt;

   int k0;
   if(g_scanTime == 0) k0 = MathMax(g_valid + 4, rates_total - 1 - InpLookbackBars);
   else                k0 = ArrayBsearch(time, g_scanTime) + 1;
   k0 = MathMax(k0, g_valid + 4);

   for(int k = k0; k <= lastClosed; k++)
   {
      int pivot = -1;
      if(InpInflMode == INFL_SLOPE_FLIP)
      {
         double d1 = ghma[k-1] - ghma[k-2];
         double d2 = ghma[k]   - ghma[k-1];
         if(d1 * d2 < 0.0) pivot = k-1;
      }
      else
      {
         double c0 = ghma[k-1] - 2.0*ghma[k-2] + ghma[k-3];
         double c1 = ghma[k]   - 2.0*ghma[k-1] + ghma[k-2];
         if(c0 * c1 < 0.0) pivot = (MathAbs(c0) < MathAbs(c1)) ? k-2 : k-1;
      }
      if(pivot < 0) continue;

      double level = ghma[pivot] + InpOffsetPoints * _Point;
      AddLine(level, time[pivot], time[k], (close[k] > level) ? 1 : -1);
   }
   g_scanTime = time[lastClosed];

   CheckMitigationFull(rates_total, time, high, low, close);
   ExpireAndTrim();
   DrawLines(true, false);

   return rates_total;
}
//+------------------------------------------------------------------+
