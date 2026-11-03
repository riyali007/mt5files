//+------------------------------------------------------------------+
//| MA_Inflection_Levels.mq5                                         |
//| MQL5 port of the TradingView "MA Inflection Levels" indicator    |
//|                                                                  |
//| ONE moving average (14 types) + horizontal inflection levels.    |
//| 1 point = _Point (the symbol's minimum price step).              |
//|                                                                  |
//| 1) The MA turns -> turning point becomes a CANDIDATE peak/bottom |
//| 2) Confirmation: price must move "confirm" points away from it   |
//|    (down for a peak, up for a bottom) on High/Low or Close.      |
//| 3) A line is drawn at the MA turning level (+ offset) from the   |
//|    turning bar to the latest bar, price + lives at the right end.|
//| 4) Next point is compared (MA level to MA level) with the most   |
//|    recent confirmed point whose level is still ALIVE.            |
//| 5) Mitigation (Wick / BCC / MA cross): every crossing counts     |
//|    once. After "max mitigations" the level ends, gets the       |
//|    mitigated color and is deleted after N min.                   |
//| 6) Colors: peak / bottom own colors, flipped after every         |
//|    non-final mitigation.                                         |
//| 7) NEW: transparency follows the LIVE price tick by tick. The    |
//|    closer price is to an alive level, the more opaque it gets;   |
//|    when price moves away it returns to the base transparency.    |
//|                                                                  |
//| Levels are created/mitigated on CLOSED bars only.                |
//+------------------------------------------------------------------+
#property copyright "MA Inflection Levels"
#property version   "1.10"
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1
#property indicator_label1  "MA"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrAqua
#property indicator_width1  2

//--- enums
enum ENUM_MA_KIND
{
   KIND_ALMA,   // ALMA
   KIND_DEMA,   // DEMA
   KIND_EMA,    // EMA
   KIND_HMA,    // HMA
   KIND_HULLMA, // HullMA
   KIND_LSMA,   // LSMA
   KIND_RMA,    // RMA
   KIND_SMMA,   // SMMA
   KIND_SSMA,   // SSMA
   KIND_TMA,    // TMA
   KIND_TEMA,   // TEMA
   KIND_VWMA,   // VWMA
   KIND_WMA,    // WMA
   KIND_VWAP    // VWAP
};

enum ENUM_MEASURE
{
   MEASURE_HL,    // High/Low
   MEASURE_CLOSE  // Close
};

enum ENUM_MITIGATION
{
   MIT_WICK,    // Wick
   MIT_BCC,     // BCC
   MIT_MACROSS  // MA cross
};

//--- inputs
input group "Moving Average"
input ENUM_TIMEFRAMES InpTF = PERIOD_M3; // Level timeframe (PERIOD_CURRENT = chart TF)
input int InpMaxBars = 10000;   // Calculation bars (0 = all history)
input ENUM_MA_KIND       InpMaType   = KIND_EMA;      // Type
input ENUM_APPLIED_PRICE InpSource   = PRICE_CLOSE;   // Source
input int                InpMaLen    = 21;            // Length
input color              InpMaColor  = clrAqua;       // Color

input group "Inflection Lines"
input ENUM_MEASURE    InpMeasure  = MEASURE_HL;   // Price measuring point (for confirmation)
input double          InpConfirm  = 500;          // Confirm: price must move away (points)
input double          InpOppDst   = 1000;         // Min points from last OPPOSITE alive point
input double          InpSameDst  = 500;          // Min points from last SAME-direction alive point
input ENUM_MITIGATION InpMitMode  = MIT_BCC;      // Mitigation type
input int             InpMaxMit   = 2;            // Max mitigations before the line ends
input bool   InpMitAway    = true; // Require move away after mitigation
input double InpMitAwayPts = 300;   // Away distance (points)

input double          InpCluster  = 200;          // Cluster: keep only the highest peak / lowest bottom within (points)
input double          InpVOff     = 0.0;          // Offset (points): peaks move up, bottoms move down
input int             InpTransp   = 50;           // Level transparency (%) when price is far
input double          InpNearDst  = 50;           // Fully visible when LIVE price is within (points)
input double          InpFarDst   = 500;          // NEW: transparency eases back to normal beyond (points)
input int             InpDelMin   = 60;           // Delete mitigated lines after (minutes, 0 = keep)
input color           InpPeakColor = clrTomato;   // Peak line color
input color           InpBotColor  = clrSpringGreen; // Bottom line color
input color           InpMitColor  = clrGray;     // Mitigated line color
input int             InpFontSize  = 8;           // Label font size

//--- level storage
struct SLevel
{
   string ln;     // trend line object name
   string lb;     // label object name
   int    type;   // 1 = peak, -1 = bottom
   double lvl;    // MA level (without offset)
   double y;      // drawn price (with offset)
   int    side;   // price side used for mitigation: -1 below the line, +1 above
   int    cnt;    // mitigations so far
   bool   flag;   // true while price/MA is currently "beyond" the line
   bool   away;     // next mitigation armed after price has moved away
};

struct SDone
{
   string   ln;
   string   lb;
   datetime t;    // time of the mitigation that ended the level
};

//--- buffers / work arrays (all non-series: index 0 = oldest bar)
double g_buf[];
double g_src[], g_a[], g_b[], g_c[], g_d[], g_cpv[], g_cv[];
double g_almaW[];
double g_almaNorm = 1.0;
double g_c1 = 0, g_c2 = 0, g_c3 = 0;

//--- state
SLevel   g_act[];
SDone    g_done[];
int      g_processed = -1;
int      g_dir = 0, g_dirPrev = 0;
int      g_candType = 0;
double   g_candLvl = 0.0;
datetime g_candTime = 0;
int      g_seq = 0;
string   g_prefix = "";
color    g_bg = clrBlack;
ENUM_TIMEFRAMES g_tf = PERIOD_CURRENT;
datetime g_lastHTF = 0;
int g_htfN = 0;
datetime g_htfT[];
double   g_hO[], g_hH[], g_hL[], g_hC[];
long     g_hV[];
double   g_plot[];

//+------------------------------------------------------------------+
//| helpers                                                          |
//+------------------------------------------------------------------+
double SMAat(const double &a[], const int i, const int len)
{
   if(len < 1 || i - len + 1 < 0) return EMPTY_VALUE;
   double s = 0;
   for(int k = i - len + 1; k <= i; k++)
   {
      if(a[k] == EMPTY_VALUE) return EMPTY_VALUE;
      s += a[k];
   }
   return s / len;
}

double WMAat(const double &a[], const int i, const int len)
{
   if(len < 1 || i - len + 1 < 0) return EMPTY_VALUE;
   double num = 0;
   for(int k = 0; k < len; k++)
   {
      double v = a[i - len + 1 + k];
      if(v == EMPTY_VALUE) return EMPTY_VALUE;
      num += v * (k + 1);
   }
   return num / (len * (len + 1) / 2.0);
}

double ALMAat(const double &a[], const int i, const int len)
{
   if(i - len + 1 < 0) return EMPTY_VALUE;
   double s = 0;
   for(int k = 0; k < len; k++)
   {
      double v = a[i - len + 1 + k];
      if(v == EMPTY_VALUE) return EMPTY_VALUE;
      s += v * g_almaW[k];
   }
   return s / g_almaNorm;
}

double LSMAat(const double &a[], const int i, const int len)
{
   if(i - len + 1 < 0) return EMPTY_VALUE;
   double sx = 0, sy = 0, sxy = 0, sxx = 0;
   for(int k = 0; k < len; k++)
   {
      double v = a[i - len + 1 + k];
      if(v == EMPTY_VALUE) return EMPTY_VALUE;
      sx += k;
      sy += v;
      sxy += k * v;
      sxx += (double)k * k;
   }
   double n = len;
   double den = n * sxx - sx * sx;
   if(den == 0) return sy / n;
   double slope = (n * sxy - sx * sy) / den;
   double icpt = (sy - slope * sx) / n;
   return icpt + slope * (n - 1);
}

void EMAstep(const double &src[], double &out[], const int i, const int len)
{
   if(src[i] == EMPTY_VALUE) { out[i] = EMPTY_VALUE; return; }
   double al = 2.0 / (len + 1.0);
   if(i == 0 || out[i - 1] == EMPTY_VALUE) out[i] = src[i];
   else out[i] = al * src[i] + (1.0 - al) * out[i - 1];
}

// RMA / SMMA (Wilder), seeded with an SMA
void RMAstep(const double &src[], double &out[], const int i, const int len)
{
   if(i > 0 && out[i - 1] != EMPTY_VALUE && src[i] != EMPTY_VALUE)
      out[i] = (src[i] + (len - 1) * out[i - 1]) / len;
   else
      out[i] = SMAat(src, i, len);
}

// SSMA = Ehlers 2-pole Super Smoother
void SSstep(const double &src[], double &out[], const int i)
{
   double s  = src[i];
   double s1 = (i >= 1) ? src[i - 1] : s;
   double f1 = (i >= 1 && out[i - 1] != EMPTY_VALUE) ? out[i - 1] : s;
   double f2 = (i >= 2 && out[i - 2] != EMPTY_VALUE) ? out[i - 2] : s;
   out[i] = g_c1 * (s + s1) / 2.0 + g_c2 * f1 + g_c3 * f2;
}

double PriceAt(const int i, const double &o[], const double &h[], const double &l[], const double &c[])
{
   switch(InpSource)
   {
      case PRICE_OPEN:     return o[i];
      case PRICE_HIGH:     return h[i];
      case PRICE_LOW:      return l[i];
      case PRICE_MEDIAN:   return (h[i] + l[i]) / 2.0;
      case PRICE_TYPICAL:  return (h[i] + l[i] + c[i]) / 3.0;
      case PRICE_WEIGHTED: return (h[i] + l[i] + 2.0 * c[i]) / 4.0;
      default:             return c[i];
   }
}

void ComputeMA(const int i, const datetime &time[], const long &vol[])
{
   int len = InpMaLen;
   double v = EMPTY_VALUE;
   switch(InpMaType)
   {
      case KIND_ALMA:
         v = ALMAat(g_src, i, len);
         break;
      case KIND_DEMA:
         EMAstep(g_src, g_a, i, len);
         EMAstep(g_a, g_b, i, len);
         v = (g_a[i] != EMPTY_VALUE && g_b[i] != EMPTY_VALUE) ? 2.0 * g_a[i] - g_b[i] : EMPTY_VALUE;
         break;
      case KIND_EMA:
         EMAstep(g_src, g_a, i, len);
         v = g_a[i];
         break;
      case KIND_HMA:
      {
         int half = MathMax(1, len / 2);
         int root = MathMax(1, (int)MathRound(MathSqrt(len)));
         g_a[i] = WMAat(g_src, i, half);
         g_b[i] = WMAat(g_src, i, len);
         g_c[i] = (g_a[i] != EMPTY_VALUE && g_b[i] != EMPTY_VALUE) ? 2.0 * g_a[i] - g_b[i] : EMPTY_VALUE;
         v = WMAat(g_c, i, root);
         break;
      }
      case KIND_HULLMA:
      {
         int half = MathMax(1, (int)MathRound(len / 2.0));
         int root = MathMax(1, (int)MathRound(MathSqrt(len)));
         EMAstep(g_src, g_a, i, half);
         EMAstep(g_src, g_b, i, len);
         g_c[i] = (g_a[i] != EMPTY_VALUE && g_b[i] != EMPTY_VALUE) ? 2.0 * g_a[i] - g_b[i] : EMPTY_VALUE;
         EMAstep(g_c, g_d, i, root);
         v = g_d[i];
         break;
      }
      case KIND_LSMA:
         v = LSMAat(g_src, i, len);
         break;
      case KIND_RMA:
      case KIND_SMMA:
         RMAstep(g_src, g_a, i, len);
         v = g_a[i];
         break;
      case KIND_SSMA:
         SSstep(g_src, g_a, i);
         v = g_a[i];
         break;
      case KIND_TMA:
      {
         int a = (int)MathCeil(len / 2.0);
         int b = (int)MathFloor(len / 2.0) + 1;
         g_a[i] = SMAat(g_src, i, a);
         v = SMAat(g_a, i, b);
         break;
      }
      case KIND_TEMA:
         EMAstep(g_src, g_a, i, len);
         EMAstep(g_a, g_b, i, len);
         EMAstep(g_b, g_c, i, len);
         v = (g_a[i] != EMPTY_VALUE && g_b[i] != EMPTY_VALUE && g_c[i] != EMPTY_VALUE)
             ? 3.0 * (g_a[i] - g_b[i]) + g_c[i] : EMPTY_VALUE;
         break;
      case KIND_VWMA:
      {
         if(i - len + 1 < 0) { v = EMPTY_VALUE; break; }
         double spv = 0, sv = 0;
         bool ok = true;
         for(int k = i - len + 1; k <= i; k++)
         {
            if(g_src[k] == EMPTY_VALUE) { ok = false; break; }
            spv += g_src[k] * (double)vol[k];
            sv  += (double)vol[k];
         }
         v = (ok && sv > 0) ? spv / sv : EMPTY_VALUE;
         break;
      }
      case KIND_WMA:
         v = WMAat(g_src, i, len);
         break;
      case KIND_VWAP:
      {
         // anchored to the start of each (server) day
                  bool nd = (i == 0) || (g_cpv[i - 1] == EMPTY_VALUE) || ((long)time[i] / 86400 != (long)time[i - 1] / 86400);
         double pv = (nd ? 0.0 : g_cpv[i - 1]) + g_src[i] * (double)vol[i];
         double vv = (nd ? 0.0 : g_cv[i - 1]) + (double)vol[i];
         g_cpv[i] = pv;
         g_cv[i]  = vv;
         v = (vv > 0) ? pv / vv : g_src[i];
         break;
      }
   }
   g_buf[i] = v;
}

//--- color / label helpers
color Blend(const color c, const color bg, const int transp)
{
   double t = MathMax(0, MathMin(100, transp)) / 100.0;
   uint cu = (uint)c, bu = (uint)bg;
   int r1 = (int)(cu & 0xFF), g1 = (int)((cu >> 8) & 0xFF), b1 = (int)((cu >> 16) & 0xFF);
   int r2 = (int)(bu & 0xFF), g2 = (int)((bu >> 8) & 0xFF), b2 = (int)((bu >> 16) & 0xFF);
   int r = (int)MathRound(r1 * (1.0 - t) + r2 * t);
   int g = (int)MathRound(g1 * (1.0 - t) + g2 * t);
   int b = (int)MathRound(b1 * (1.0 - t) + b2 * t);
   return (color)(r | (g << 8) | (b << 16));
}

string Lbl(const double y, const int lives)
{
   string s = DoubleToString(y, _Digits);
   if(lives > 0)
   {
      s += " ";
      for(int k = 0; k < lives; k++) s += ShortToString(0x2665); // heart
   }
   else
      s += " " + ShortToString(0x00D7); // cross
   return s;
}

bool Beyond(const int sd, const double y, const double m, const double hi, const double lo, const double cl)
{
   switch(InpMitMode)
   {
      case MIT_WICK: return (sd == -1) ? (hi >= y) : (lo <= y);
      case MIT_MACROSS:
         if(m == EMPTY_VALUE) return false;
         return (sd == -1) ? (m > y) : (m < y);
      default: return (sd == -1) ? (cl > y) : (cl < y);
   }
}

//--- NEW: proximity of LIVE price to a level. 1.0 = within InpNearDst, 0.0 = beyond InpFarDst,
//    linear in between
double Proximity(const double y, const double px)
{
   double d     = MathAbs(px - y) / _Point;
   double nearD = MathMax(0.0, InpNearDst);
   double farD  = MathMax(InpFarDst, nearD + 1.0);
   if(d <= nearD) return 1.0;
   if(d >= farD)  return 0.0;
   return 1.0 - (d - nearD) / (farD - nearD);
}

//--- NEW: displayed color of an alive level for a given live price
color LevelColor(const SLevel &L, const double px)
{
   int   effT = (L.cnt % 2 == 0) ? L.type : -L.type;
   color bc   = (effT == 1) ? InpPeakColor : InpBotColor;
   int   tr   = (int)MathRound(InpTransp * (1.0 - Proximity(L.y, px)));
   return Blend(bc, g_bg, tr);
}

//--- NEW: runs on EVERY tick with the live price; redraws only if a color changed
void UpdateProximity(const double px)
{
   bool changed = false;
   for(int k = 0; k < ArraySize(g_act); k++)
   {
      color fc = LevelColor(g_act[k], px);
      if((color)ObjectGetInteger(0, g_act[k].ln, OBJPROP_COLOR) != fc)
      {
         ObjectSetInteger(0, g_act[k].ln, OBJPROP_COLOR, fc);
         ObjectSetInteger(0, g_act[k].lb, OBJPROP_COLOR, fc);
         changed = true;
      }
   }
   if(changed) ChartRedraw(0);
}

void RemoveAct(const int k)
{
   int n = ArraySize(g_act);
   for(int j = k; j < n - 1; j++) g_act[j] = g_act[j + 1];
   ArrayResize(g_act, n - 1);
}

void RemoveDone(const int k)
{
   int n = ArraySize(g_done);
   for(int j = k; j < n - 1; j++) g_done[j] = g_done[j + 1];
   ArrayResize(g_done, n - 1);
}

void ResetAll()
{
   ObjectsDeleteAll(0, g_prefix);
   ArrayResize(g_act, 0);
   ArrayResize(g_done, 0);
   g_processed = -1;
   g_dir = 0;
   g_dirPrev = 0;
   g_candType = 0;
   g_candLvl = 0.0;
   g_candTime = 0;
}

//+------------------------------------------------------------------+
//| Process ONE closed bar                                           |
//+------------------------------------------------------------------+
void ProcessBar(const int i, const bool isLast, const datetime &time[],
                const double &high[], const double &low[], const double &close[])
{
   const double pt = _Point;
   const double hi = high[i], lo = low[i], cl = close[i];
   const double mav = g_buf[i];
   const datetime tNext = time[i + 1];
   const datetime tLbl = tNext + (datetime)PeriodSeconds(g_tf);
   const double awayPts = MathMax(0.0, InpMitAwayPts) * pt;
   const bool   needAway = InpMitAway && awayPts > 0.0;
   
   for(int k = ArraySize(g_act) - 1; k >= 0; k--)
   {
      int sdi = g_act[k].side;
      bool beyond = Beyond(sdi, g_act[k].y, mav, hi, lo, cl);
   
      // Arm only after a real excursion. Do not use this bar's cross.
      bool wasAway = g_act[k].away;
      if(needAway && !g_act[k].away)
      {
         if(hi >= g_act[k].y + awayPts || lo <= g_act[k].y - awayPts)
            g_act[k].away = true;
      }
   
      if(beyond && !g_act[k].flag && (!needAway || wasAway))
      {
         g_act[k].cnt++;
         g_act[k].away = !needAway;
   
         double refPx = (InpMitMode == MIT_MACROSS && mav != EMPTY_VALUE) ? mav : cl;
         sdi = (refPx < g_act[k].y) ? -1 : 1;
         g_act[k].side = sdi;
         beyond = Beyond(sdi, g_act[k].y, mav, hi, lo, cl);
   
         // Re-arm only if this bar already extended 300 points on the side just entered.
         if(needAway)
         {
            if(sdi == -1 && lo <= g_act[k].y - awayPts) g_act[k].away = true;
            if(sdi ==  1 && hi >= g_act[k].y + awayPts) g_act[k].away = true;
         }
      }
      g_act[k].flag = beyond;

      if(g_act[k].cnt >= InpMaxMit)
      {
         // level is used up: stop it here, mitigated color, schedule deletion
         color mc = Blend(InpMitColor, g_bg, InpTransp);
         ObjectSetInteger(0, g_act[k].ln, OBJPROP_TIME, 1, time[i]);
         ObjectSetInteger(0, g_act[k].ln, OBJPROP_COLOR, mc);
         ObjectSetInteger(0, g_act[k].lb, OBJPROP_TIME, 0, tNext);
         ObjectSetInteger(0, g_act[k].lb, OBJPROP_COLOR, mc);
         ObjectSetString(0, g_act[k].lb, OBJPROP_TEXT, Lbl(g_act[k].y, 0));
         if(InpDelMin > 0)
         {
            int nd = ArraySize(g_done);
            ArrayResize(g_done, nd + 1);
            g_done[nd].ln = g_act[k].ln;
            g_done[nd].lb = g_act[k].lb;
            g_done[nd].t  = time[i];
         }
         RemoveAct(k);
      }
      else if(isLast)
      {
         // CHANGED: color comes from the same live-proximity function (last closed price as seed;
         // the next tick overrides it with the live price)
         color fc = LevelColor(g_act[k], cl);
         ObjectSetInteger(0, g_act[k].ln, OBJPROP_COLOR, fc);
         ObjectSetInteger(0, g_act[k].ln, OBJPROP_TIME, 1, tNext);
         ObjectSetInteger(0, g_act[k].lb, OBJPROP_COLOR, fc);
         ObjectSetInteger(0, g_act[k].lb, OBJPROP_TIME, 0, tLbl);
         ObjectSetString(0, g_act[k].lb, OBJPROP_TEXT, Lbl(g_act[k].y, InpMaxMit - g_act[k].cnt));
      }
   }

   //--- delete fully mitigated levels after InpDelMin minutes
   if(InpDelMin > 0)
   {
      for(int d = ArraySize(g_done) - 1; d >= 0; d--)
      {
         if((long)(time[i] - g_done[d].t) >= (long)InpDelMin * 60)
         {
            ObjectDelete(0, g_done[d].ln);
            ObjectDelete(0, g_done[d].lb);
            RemoveDone(d);
         }
      }
   }

   //--- reference point = most recent confirmed point whose level is still alive
   int lastType = 0;
   double lastLvl = 0.0;
   int na = ArraySize(g_act);
   if(na > 0)
   {
      lastType = g_act[na - 1].type;
      lastLvl  = g_act[na - 1].lvl;
   }

   //--- MA direction and flips
   g_dirPrev = g_dir;
   if(i >= 1 && g_buf[i] != EMPTY_VALUE && g_buf[i - 1] != EMPTY_VALUE)
   {
      if(g_buf[i] > g_buf[i - 1]) g_dir = 1;
      else if(g_buf[i] < g_buf[i - 1]) g_dir = -1;
   }
   bool flipTop = (g_dir == -1 && g_dirPrev == 1);   // rising -> falling : candidate PEAK
   bool flipBot = (g_dir == 1 && g_dirPrev == -1);   // falling -> rising : candidate BOTTOM
   double lvl = (i >= 1) ? g_buf[i - 1] : EMPTY_VALUE; // turning bar = the bar before the flip is detected

   //--- 2) candidate PEAK
   if(flipTop && lvl != EMPTY_VALUE)
   {
      bool okT = (lastType == 0) || (lvl >= lastLvl + (lastType == 1 ? InpSameDst : InpOppDst) * pt);
      if(okT && (g_candType != 1 || lvl > g_candLvl))
      {
         g_candType = 1;
         g_candLvl  = lvl;
         g_candTime = time[i - 1];
      }
   }

   //--- 3) candidate BOTTOM
   if(flipBot && lvl != EMPTY_VALUE)
   {
      bool okB = (lastType == 0) || (lvl <= lastLvl - (lastType == -1 ? InpSameDst : InpOppDst) * pt);
      if(okB && (g_candType != -1 || lvl < g_candLvl))
      {
         g_candType = -1;
         g_candLvl  = lvl;
         g_candTime = time[i - 1];
      }
   }

   //--- 4) confirmation: price moved far enough away from the candidate -> draw the level
   if(g_candType != 0)
   {
      bool useClose = (InpMeasure == MEASURE_CLOSE);
      double pxDown = useClose ? cl : lo;   // confirms a peak
      double pxUp   = useClose ? cl : hi;   // confirms a bottom
      bool moved = (g_candType == 1) ? (pxDown <= g_candLvl - InpConfirm * pt)
                                     : (pxUp   >= g_candLvl + InpConfirm * pt);
      if(moved)
      {
         //--- Cluster rule: among alive same-type levels within InpCluster points keep only the highest peak / lowest bottom
         bool keepIt = true;
         for(int k = 0; k < ArraySize(g_act); k++)
         {
            if(g_act[k].type == g_candType && MathAbs(g_act[k].lvl - g_candLvl) <= InpCluster * pt)
            {
               if((g_candType == 1 && g_act[k].lvl >= g_candLvl) || (g_candType == -1 && g_act[k].lvl <= g_candLvl))
                  keepIt = false;
            }
         }
         if(keepIt)
         {
            for(int k = ArraySize(g_act) - 1; k >= 0; k--)
            {
               if(g_act[k].type == g_candType && MathAbs(g_act[k].lvl - g_candLvl) <= InpCluster * pt)
               {
                  ObjectDelete(0, g_act[k].ln);
                  ObjectDelete(0, g_act[k].lb);
                  RemoveAct(k);
               }
            }
            double yC = g_candLvl + g_candType * InpVOff * pt; // peaks move up, bottoms move down
            int sdC = (cl < yC) ? -1 : 1;
            color bc = (g_candType == 1) ? InpPeakColor : InpBotColor;
            // CHANGED: initial color from proximity instead of the binary Near()
            color c0 = Blend(bc, g_bg, (int)MathRound(InpTransp * (1.0 - Proximity(yC, cl))));

            g_seq++;
            string ln = g_prefix + "L" + IntegerToString(g_seq);
            string lb = g_prefix + "T" + IntegerToString(g_seq);

            ObjectCreate(0, ln, OBJ_TREND, 0, g_candTime, yC, tNext, yC);
            ObjectSetInteger(0, ln, OBJPROP_COLOR, c0);
            ObjectSetInteger(0, ln, OBJPROP_STYLE, STYLE_DASH);
            ObjectSetInteger(0, ln, OBJPROP_WIDTH, 1);
            ObjectSetInteger(0, ln, OBJPROP_RAY_RIGHT, false);
            ObjectSetInteger(0, ln, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, ln, OBJPROP_HIDDEN, true);
            ObjectSetInteger(0, ln, OBJPROP_BACK, false);

            ObjectCreate(0, lb, OBJ_TEXT, 0, tLbl, yC);
            ObjectSetString(0, lb, OBJPROP_TEXT, Lbl(yC, InpMaxMit));
            ObjectSetString(0, lb, OBJPROP_FONT, "Arial");
            ObjectSetInteger(0, lb, OBJPROP_FONTSIZE, InpFontSize);
            ObjectSetInteger(0, lb, OBJPROP_COLOR, c0);
            ObjectSetInteger(0, lb, OBJPROP_ANCHOR, ANCHOR_LEFT);
            ObjectSetInteger(0, lb, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, lb, OBJPROP_HIDDEN, true);

            int n = ArraySize(g_act);
            ArrayResize(g_act, n + 1);
            g_act[n].ln   = ln;
            g_act[n].lb   = lb;
            g_act[n].type = g_candType;
            g_act[n].lvl  = g_candLvl;
            g_act[n].y    = yC;
            g_act[n].side = sdC;
            g_act[n].cnt  = 0;
            g_act[n].away = true;
            g_act[n].flag = Beyond(sdC, yC, mav, hi, lo, cl);
         }
         g_candType = 0;
      }
   }
}

//+------------------------------------------------------------------+
//| Indicator init / deinit                                          |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpMaLen < 1 || InpMaxMit < 1)
      return INIT_PARAMETERS_INCORRECT;

   SetIndexBuffer(0, g_plot, INDICATOR_DATA);
   ArraySetAsSeries(g_plot, false);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpMaColor);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, InpMaLen);
   IndicatorSetString(INDICATOR_SHORTNAME, "MA Inflection Levels");

   // ALMA weights (offset 0.85, sigma 6)
   ArrayResize(g_almaW, InpMaLen);
   double m = MathFloor(0.85 * (InpMaLen - 1));
   double s = InpMaLen / 6.0;
   g_almaNorm = 0.0;
   for(int k = 0; k < InpMaLen; k++)
   {
      g_almaW[k] = MathExp(-((k - m) * (k - m)) / (2.0 * s * s));
      g_almaNorm += g_almaW[k];
   }

   // Super Smoother coefficients
   double a1 = MathExp(-1.414 * M_PI / InpMaLen);
   double b1 = 2.0 * a1 * MathCos(1.414 * M_PI / InpMaLen);
   g_c2 = b1;
   g_c3 = -a1 * a1;
   g_c1 = 1.0 - g_c2 - g_c3;

   g_prefix = "MAIL" + IntegerToString((long)GetTickCount()) + "_";
   g_seq = 0;
   ResetAll();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, g_prefix);
   ChartRedraw(0);
}

void ComputeAll(const int n, const datetime &time[], const double &open[], const double &high[],
                const double &low[], const double &close[], const long &vol[])
{
   ResetAll();
   ArrayResize(g_buf, n); ArrayResize(g_src, n); ArrayResize(g_a, n); ArrayResize(g_b, n);
   ArrayResize(g_c, n);   ArrayResize(g_d, n);   ArrayResize(g_cpv, n); ArrayResize(g_cv, n);
   ArrayInitialize(g_buf, EMPTY_VALUE); ArrayInitialize(g_src, EMPTY_VALUE);
   ArrayInitialize(g_a, EMPTY_VALUE);   ArrayInitialize(g_b, EMPTY_VALUE);
   ArrayInitialize(g_c, EMPTY_VALUE);   ArrayInitialize(g_d, EMPTY_VALUE);
   ArrayInitialize(g_cpv, EMPTY_VALUE); ArrayInitialize(g_cv, EMPTY_VALUE);
   g_bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);

   for(int i = 0; i < n; i++)
   {
      g_src[i] = PriceAt(i, open, high, low, close);
      ComputeMA(i, time, vol);
   }
   for(int i = 1; i <= n - 2; i++)
      ProcessBar(i, i == n - 2, time, high, low, close);
   g_htfN = n;
}
//+------------------------------------------------------------------+
//| Indicator calculation                                            |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[],
                const double &close[], const long &tick_volume[], const long &volume[],
                const int &spread[])
{
   if(rates_total < 2) return 0;

   ENUM_TIMEFRAMES tf = (InpTF == PERIOD_CURRENT) ? _Period : InpTF;
   if(PeriodSeconds(tf) < PeriodSeconds(_Period)) tf = _Period;
   g_tf = tf;

   datetime cur = iTime(_Symbol, tf, 0);
   if(cur == 0) return 0;

   bool recalc = (prev_calculated == 0 || cur != g_lastHTF || g_htfN == 0);
   if(recalc)
   {
      g_lastHTF = cur;
      MqlRates R[];
      int nb  = iBars(_Symbol, tf);
      int cnt = (InpMaxBars > 0) ? MathMin(InpMaxBars, nb) : nb;
      int n = CopyRates(_Symbol, tf, 0, cnt, R);
      if(n < 2) return 0;

      ArrayResize(g_htfT, n); ArrayResize(g_hO, n); ArrayResize(g_hH, n);
      ArrayResize(g_hL, n);   ArrayResize(g_hC, n); ArrayResize(g_hV, n);
      for(int k = 0; k < n; k++)
      {
         g_htfT[k] = R[k].time; g_hO[k] = R[k].open; g_hH[k] = R[k].high;
         g_hL[k] = R[k].low;    g_hC[k] = R[k].close; g_hV[k] = (long)R[k].tick_volume;
      }
      ComputeAll(n, g_htfT, g_hO, g_hH, g_hL, g_hC, g_hV);
   }
   else
   {
      MqlRates R1[];
      if(CopyRates(_Symbol, tf, 0, 1, R1) == 1)
      {
         int j = g_htfN - 1;
         g_hO[j] = R1[0].open; g_hH[j] = R1[0].high; g_hL[j] = R1[0].low;
         g_hC[j] = R1[0].close; g_hV[j] = (long)R1[0].tick_volume;
         g_src[j] = PriceAt(j, g_hO, g_hH, g_hL, g_hC);
         ComputeMA(j, g_htfT, g_hV);
      }
   }

   long P = (long)PeriodSeconds(tf);
   ArrayResize(g_plot, rates_total);
   int startI = recalc ? 0 : MathMax(0, rates_total - (int)(P / PeriodSeconds(_Period)) - 3);
   for(int i = startI; i < rates_total; i++)
   {
      datetime t = time[i];
      int s = iBarShift(_Symbol, tf, t - (datetime)P, false);
      int k = (s >= 0) ? g_htfN - 1 - s : -1;
      if(k < 0 || k >= g_htfN || g_buf[k] == EMPTY_VALUE)
      {
         g_plot[i] = EMPTY_VALUE;
         continue;
      }
      if(k + 1 < g_htfN && g_buf[k + 1] != EMPTY_VALUE)
      {
         double fr = (double)(t - (g_htfT[k] + P)) / (double)P;
         fr = MathMax(0.0, MathMin(1.0, fr));
         g_plot[i] = g_buf[k] + (g_buf[k + 1] - g_buf[k]) * fr;
      }
      else
         g_plot[i] = g_buf[k];
   }

   UpdateProximity(close[rates_total - 1]);
   return rates_total;
}
//+------------------------------------------------------------------+