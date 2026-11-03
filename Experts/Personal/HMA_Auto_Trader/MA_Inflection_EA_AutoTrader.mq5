//+------------------------------------------------------------------+
//| MA_Inflection_EA_AutoTrader.mq5                                  |
//| Auto-trades the "MA Inflection Levels" levels (engine embedded). |
//| Hedging account required. Works on the chart symbol/timeframe.   |
//+------------------------------------------------------------------+
#property copyright "MA Inflection EA"
#property version   "1.10"
#include <Trade/Trade.mqh>
#include "KillZones.mqh"

//--- enums
enum ENUM_MA_KIND { KIND_ALMA, KIND_DEMA, KIND_EMA, KIND_HMA, KIND_HULLMA, KIND_LSMA, KIND_RMA,
                    KIND_SMMA, KIND_SSMA, KIND_TMA, KIND_TEMA, KIND_VWMA, KIND_WMA, KIND_VWAP };
enum ENUM_MEASURE    { MEASURE_HL, MEASURE_CLOSE };
enum ENUM_MITIGATION { MIT_WICK, MIT_BCC, MIT_MACROSS };
enum ENUM_COVER      { COVER_RANGE, COVER_BODY };
enum ENUM_DD_MODE    { DD_OFF, DD_DISTANCE, DD_SIGNAL };  // how drawdown entries are triggered

//--- inputs: levels (same as the indicator)
input group "Moving Average"
input ENUM_MA_KIND       InpMaType   = KIND_EMA;
input ENUM_APPLIED_PRICE InpSource   = PRICE_CLOSE;
input int                InpMaLen    = 21;
input color              InpMaColor  = clrAqua;

input group "Inflection Lines"
input int             InpMaxBars  = 10000;           // Calculation bars (0 = all)
input ENUM_MEASURE    InpMeasure  = MEASURE_HL;
input double          InpConfirm  = 500;
input double          InpOppDst   = 1000;
input double          InpSameDst  = 500;
input ENUM_MITIGATION InpMitMode  = MIT_BCC;
input int             InpMaxMit   = 2;
input double          InpCluster  = 200;
input double          InpVOff     = 0.0;
input int             InpTransp   = 50;
input double          InpNearDst  = 50;
input double          InpFarDst   = 500;
input int             InpDelMin   = 60;
input color           InpPeakColor = clrTomato;
input color           InpBotColor  = clrSpringGreen;
input color           InpMitColor  = clrGray;
input int             InpFontSize  = 8;
input bool            InpDraw      = true;

input group "Entry rules"
input bool          InpRule1    = true;     // Rule 1: wick rejection (body stays on one side of the line)
input bool          InpRule2    = true;     // Rule 2: break, then close back + cover 50% of breakout candle
input bool          InpRule3    = true;     // Rule 3: retest of a broken resistance/support
input double        InpMinWick  = 30;       // Min wick beyond the line (points)
input ENUM_COVER    InpCover    = COVER_RANGE;
input int           InpR2Window = 10;       // Rule 2: max bars to wait for the reversal
input int           InpMaxTradesPerLevel = 4; // Max trades per level & direction (0 = unlimited)

input group "Invalidation"
input bool          InpInv1            = true;   // Next candle range > signal candle range -> close
input bool          InpInv1AdverseOnly = false;  // ...only if the next candle is against the trade
input bool          InpInv2            = true;   // Engulfing next candle -> close
input bool          InpInvOnR2         = false;  // Also apply invalidation to Rule 2 trades
input int           InpCooldownMin     = 15;     // Cooldown after a loss (minutes, 0 = off)
input double        InpCooldownLossPts = 50;     // Only losses >= this many points start the cooldown (BE exits are ignored)

input group "Trade management"
input ulong         InpMagic        = 20261023;
input double        InpLot          = 0.3;
input int           InpSLPts        = 700;
input int           InpTPPts        = 1400;
input int           InpPartials     = 3;
input double        InpPartialPct   = 20.0;
input int           InpPartialStep  = 300;
input int           InpBEPts        = 200;
input double        InpBEOffset     = 0;
input int           InpTrailStart   = 1000;
input int           InpTrailDist    = 600;
input int           InpTrailStep    = 20;
input ENUM_DD_MODE  InpDDMode       = DD_DISTANCE; // DD entries: off / by adverse distance / by new signal
input int           InpDDEntries    = 2;
input double        InpDDStep       = 350;    // DD entry when price is this far (points) worse than the last entry
input double        InpDDClose      = 10.0;   // close older DD entries at this profit ($, 0 = off)
input int           InpDeviation    = 30;
input double        InpMaxSpread    = 0;
input bool          InpDebug        = true;   // Print signal / skip reasons to the Experts log

//--- structures
struct SLevel { string ln; string lb; int type; double lvl; double y; int side; int cnt; bool flag; };
struct SDone  { string ln; string lb; datetime t; };
struct SPend  { string ln; int dir; double y; double o, h, l, c; int bar; };
struct SSig   { bool on; int reason; string ln; double y; double dist; datetime t; double o, h, l, c; };
struct SMeta  { ulong ticket; int parts; int reason; datetime sigTime; double so, sh, sl, sc; bool invDone; };
struct SLC    { string ln; int dir; int n; };

//--- rates (non-series, index 0 = oldest)
datetime g_time[]; double g_open[], g_high[], g_low[], g_close[]; long g_vol[];
double g_buf[], g_src[], g_a[], g_b[], g_c[], g_d[], g_cpv[], g_cv[], g_almaW[];
double g_almaNorm = 1.0, g_c1 = 0, g_c2 = 0, g_c3 = 0;
int      g_n = 0;
datetime g_t0 = 0;

//--- state
SLevel g_act[]; SDone g_done[]; SPend g_pend[]; SMeta g_pm[]; SLC g_lc[];
SSig   g_sb, g_ss, g_cur;
int g_processed = -1, g_dir = 0, g_dirPrev = 0, g_candType = 0, g_seq = 0;
double g_candLvl = 0.0; datetime g_candTime = 0;
string g_prefix = ""; color g_bg = clrBlack;
bool g_draw = false, g_ready = false;
datetime g_lastBar = 0, g_cdUntil = 0;
CTrade g_trade;

void Dbg(const string s) { if(InpDebug) Print("[MAIE] ", s); }

//+------------------------------------------------------------------+
//| MA helpers                                                       |
//+------------------------------------------------------------------+
double SMAat(const double &a[], const int i, const int len)
{
   if(len < 1 || i - len + 1 < 0) return EMPTY_VALUE;
   double s = 0;
   for(int k = i - len + 1; k <= i; k++) { if(a[k] == EMPTY_VALUE) return EMPTY_VALUE; s += a[k]; }
   return s / len;
}
double WMAat(const double &a[], const int i, const int len)
{
   if(len < 1 || i - len + 1 < 0) return EMPTY_VALUE;
   double num = 0;
   for(int k = 0; k < len; k++) { double v = a[i - len + 1 + k]; if(v == EMPTY_VALUE) return EMPTY_VALUE; num += v * (k + 1); }
   return num / (len * (len + 1) / 2.0);
}
double ALMAat(const double &a[], const int i, const int len)
{
   if(i - len + 1 < 0) return EMPTY_VALUE;
   double s = 0;
   for(int k = 0; k < len; k++) { double v = a[i - len + 1 + k]; if(v == EMPTY_VALUE) return EMPTY_VALUE; s += v * g_almaW[k]; }
   return s / g_almaNorm;
}
double LSMAat(const double &a[], const int i, const int len)
{
   if(i - len + 1 < 0) return EMPTY_VALUE;
   double sx = 0, sy = 0, sxy = 0, sxx = 0;
   for(int k = 0; k < len; k++)
   {
      double v = a[i - len + 1 + k]; if(v == EMPTY_VALUE) return EMPTY_VALUE;
      sx += k; sy += v; sxy += k * v; sxx += (double)k * k;
   }
   double n = len, den = n * sxx - sx * sx;
   if(den == 0) return sy / n;
   double slope = (n * sxy - sx * sy) / den, icpt = (sy - slope * sx) / n;
   return icpt + slope * (n - 1);
}
void EMAstep(const double &src[], double &out[], const int i, const int len)
{
   if(src[i] == EMPTY_VALUE) { out[i] = EMPTY_VALUE; return; }
   double al = 2.0 / (len + 1.0);
   if(i == 0 || out[i - 1] == EMPTY_VALUE) out[i] = src[i];
   else out[i] = al * src[i] + (1.0 - al) * out[i - 1];
}
void RMAstep(const double &src[], double &out[], const int i, const int len)
{
   if(i > 0 && out[i - 1] != EMPTY_VALUE && src[i] != EMPTY_VALUE) out[i] = (src[i] + (len - 1) * out[i - 1]) / len;
   else out[i] = SMAat(src, i, len);
}
void SSstep(const double &src[], double &out[], const int i)
{
   double s  = src[i];
   double s1 = (i >= 1) ? src[i - 1] : s;
   double f1 = (i >= 1 && out[i - 1] != EMPTY_VALUE) ? out[i - 1] : s;
   double f2 = (i >= 2 && out[i - 2] != EMPTY_VALUE) ? out[i - 2] : s;
   out[i] = g_c1 * (s + s1) / 2.0 + g_c2 * f1 + g_c3 * f2;
}
double PriceAt(const int i)
{
   switch(InpSource)
   {
      case PRICE_OPEN:     return g_open[i];
      case PRICE_HIGH:     return g_high[i];
      case PRICE_LOW:      return g_low[i];
      case PRICE_MEDIAN:   return (g_high[i] + g_low[i]) / 2.0;
      case PRICE_TYPICAL:  return (g_high[i] + g_low[i] + g_close[i]) / 3.0;
      case PRICE_WEIGHTED: return (g_high[i] + g_low[i] + 2.0 * g_close[i]) / 4.0;
      default:             return g_close[i];
   }
}
void ComputeMA(const int i)
{
   int len = InpMaLen;
   double v = EMPTY_VALUE;
   switch(InpMaType)
   {
      case KIND_ALMA: v = ALMAat(g_src, i, len); break;
      case KIND_DEMA:
         EMAstep(g_src, g_a, i, len); EMAstep(g_a, g_b, i, len);
         v = (g_a[i] != EMPTY_VALUE && g_b[i] != EMPTY_VALUE) ? 2.0 * g_a[i] - g_b[i] : EMPTY_VALUE; break;
      case KIND_EMA: EMAstep(g_src, g_a, i, len); v = g_a[i]; break;
      case KIND_HMA:
      {
         int half = MathMax(1, len / 2), root = MathMax(1, (int)MathRound(MathSqrt(len)));
         g_a[i] = WMAat(g_src, i, half); g_b[i] = WMAat(g_src, i, len);
         g_c[i] = (g_a[i] != EMPTY_VALUE && g_b[i] != EMPTY_VALUE) ? 2.0 * g_a[i] - g_b[i] : EMPTY_VALUE;
         v = WMAat(g_c, i, root); break;
      }
      case KIND_HULLMA:
      {
         int half = MathMax(1, (int)MathRound(len / 2.0)), root = MathMax(1, (int)MathRound(MathSqrt(len)));
         EMAstep(g_src, g_a, i, half); EMAstep(g_src, g_b, i, len);
         g_c[i] = (g_a[i] != EMPTY_VALUE && g_b[i] != EMPTY_VALUE) ? 2.0 * g_a[i] - g_b[i] : EMPTY_VALUE;
         EMAstep(g_c, g_d, i, root); v = g_d[i]; break;
      }
      case KIND_LSMA: v = LSMAat(g_src, i, len); break;
      case KIND_RMA:
      case KIND_SMMA: RMAstep(g_src, g_a, i, len); v = g_a[i]; break;
      case KIND_SSMA: SSstep(g_src, g_a, i); v = g_a[i]; break;
      case KIND_TMA:
      {
         int a = (int)MathCeil(len / 2.0), b = (int)MathFloor(len / 2.0) + 1;
         g_a[i] = SMAat(g_src, i, a); v = SMAat(g_a, i, b); break;
      }
      case KIND_TEMA:
         EMAstep(g_src, g_a, i, len); EMAstep(g_a, g_b, i, len); EMAstep(g_b, g_c, i, len);
         v = (g_a[i] != EMPTY_VALUE && g_b[i] != EMPTY_VALUE && g_c[i] != EMPTY_VALUE)
             ? 3.0 * (g_a[i] - g_b[i]) + g_c[i] : EMPTY_VALUE; break;
      case KIND_VWMA:
      {
         if(i - len + 1 < 0) { v = EMPTY_VALUE; break; }
         double spv = 0, sv = 0;
         for(int k = i - len + 1; k <= i; k++) { spv += g_src[k] * (double)g_vol[k]; sv += (double)g_vol[k]; }
         v = (sv > 0) ? spv / sv : EMPTY_VALUE; break;
      }
      case KIND_WMA: v = WMAat(g_src, i, len); break;
      case KIND_VWAP:
      {
         bool nd = (i == 0) || ((long)g_time[i] / 86400 != (long)g_time[i - 1] / 86400);
         double pv = (nd ? 0.0 : g_cpv[i - 1]) + g_src[i] * (double)g_vol[i];
         double vv = (nd ? 0.0 : g_cv[i - 1]) + (double)g_vol[i];
         g_cpv[i] = pv; g_cv[i] = vv;
         v = (vv > 0) ? pv / vv : g_src[i]; break;
      }
   }
   g_buf[i] = v;
}

//+------------------------------------------------------------------+
//| Color / label / graphics helpers                                 |
//+------------------------------------------------------------------+
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
   if(lives > 0) { s += " "; for(int k = 0; k < lives; k++) s += ShortToString(0x2665); }
   else s += " " + ShortToString(0x00D7);
   return s;
}
double Proximity(const double y, const double px)
{
   double d = MathAbs(px - y) / _Point, nearD = MathMax(0.0, InpNearDst), farD = MathMax(InpFarDst, nearD + 1.0);
   if(d <= nearD) return 1.0;
   if(d >= farD)  return 0.0;
   return 1.0 - (d - nearD) / (farD - nearD);
}
color LevelColor(const SLevel &L, const double px)
{
   int effT = (L.cnt % 2 == 0) ? L.type : -L.type;
   color bc = (effT == 1) ? InpPeakColor : InpBotColor;
   return Blend(bc, g_bg, (int)MathRound(InpTransp * (1.0 - Proximity(L.y, px))));
}
void UpdateProximity(const double px)
{
   if(!g_draw) return;
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
void GfxCreate(const string ln, const string lb, const double y, const datetime t1, const datetime t2,
               const datetime tLbl, const color c0, const int lives)
{
   if(!g_draw) return;
   ObjectCreate(0, ln, OBJ_TREND, 0, t1, y, t2, y);
   ObjectSetInteger(0, ln, OBJPROP_COLOR, c0);
   ObjectSetInteger(0, ln, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, ln, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, ln, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, ln, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, ln, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, ln, OBJPROP_BACK, false);
   ObjectCreate(0, lb, OBJ_TEXT, 0, tLbl, y);
   ObjectSetString(0, lb, OBJPROP_TEXT, Lbl(y, lives));
   ObjectSetString(0, lb, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, lb, OBJPROP_FONTSIZE, InpFontSize);
   ObjectSetInteger(0, lb, OBJPROP_COLOR, c0);
   ObjectSetInteger(0, lb, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(0, lb, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, lb, OBJPROP_HIDDEN, true);
}
void GfxAlive(const SLevel &L, const datetime tNext, const datetime tLbl, const color fc)
{
   if(!g_draw) return;
   ObjectSetInteger(0, L.ln, OBJPROP_COLOR, fc);
   ObjectSetInteger(0, L.ln, OBJPROP_TIME, 1, tNext);
   ObjectSetInteger(0, L.lb, OBJPROP_COLOR, fc);
   ObjectSetInteger(0, L.lb, OBJPROP_TIME, 0, tLbl);
   ObjectSetString(0, L.lb, OBJPROP_TEXT, Lbl(L.y, InpMaxMit - L.cnt));
}
void GfxEnd(const SLevel &L, const datetime tEnd, const datetime tNext, const color mc)
{
   if(!g_draw) return;
   ObjectSetInteger(0, L.ln, OBJPROP_TIME, 1, tEnd);
   ObjectSetInteger(0, L.ln, OBJPROP_COLOR, mc);
   ObjectSetInteger(0, L.lb, OBJPROP_TIME, 0, tNext);
   ObjectSetInteger(0, L.lb, OBJPROP_COLOR, mc);
   ObjectSetString(0, L.lb, OBJPROP_TEXT, Lbl(L.y, 0));
}
void GfxDel(const string ln, const string lb)
{
   if(!g_draw) return;
   ObjectDelete(0, ln);
   ObjectDelete(0, lb);
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
void RemovePend(const int k)
{
   int n = ArraySize(g_pend);
   for(int j = k; j < n - 1; j++) g_pend[j] = g_pend[j + 1];
   ArrayResize(g_pend, n - 1);
}
void ClearSig(SSig &s) { s.on = false; s.reason = 0; s.ln = ""; s.y = 0; s.dist = 0; s.t = 0; s.o = s.h = s.l = s.c = 0; }
void ResetAll()
{
   if(g_draw) ObjectsDeleteAll(0, g_prefix);
   ArrayResize(g_act, 0); ArrayResize(g_done, 0); ArrayResize(g_pend, 0); ArrayResize(g_lc, 0);
   g_processed = -1; g_dir = 0; g_dirPrev = 0; g_candType = 0; g_candLvl = 0.0; g_candTime = 0;
   ClearSig(g_sb); ClearSig(g_ss);
}

//--- trades taken per level & direction
int LCget(const string ln, const int dir)
{
   for(int k = 0; k < ArraySize(g_lc); k++) if(g_lc[k].ln == ln && g_lc[k].dir == dir) return g_lc[k].n;
   return 0;
}
void LCinc(const string ln, const int dir)
{
   for(int k = 0; k < ArraySize(g_lc); k++) if(g_lc[k].ln == ln && g_lc[k].dir == dir) { g_lc[k].n++; return; }
   int n = ArraySize(g_lc);
   ArrayResize(g_lc, n + 1);
   g_lc[n].ln = ln; g_lc[n].dir = dir; g_lc[n].n = 1;
}

//+------------------------------------------------------------------+
//| Signals (evaluated on the just-closed bar, BEFORE its mitigation)|
//+------------------------------------------------------------------+
void OfferSignal(SSig &s, const int reason, const string ln, const double y, const int i)
{
   Dbg(StringFormat("SIGNAL %s rule=%d line=%s bar=%s", (g_close[i] > y ? "BUY" : "SELL"), reason,
                    DoubleToString(y, _Digits), TimeToString(g_time[i])));
   double dist = MathAbs(g_close[i] - y);
   if(s.on && dist >= s.dist) return;
   s.on = true; s.reason = reason; s.ln = ln; s.y = y; s.dist = dist; s.t = g_time[i];
   s.o = g_open[i]; s.h = g_high[i]; s.l = g_low[i]; s.c = g_close[i];
}
void ScanSignals(const int i)
{
   if(i < 1) return;
   const double pt = _Point, minW = InpMinWick * pt;
   const double op = g_open[i], hi = g_high[i], lo = g_low[i], cl = g_close[i], pcl = g_close[i - 1];

   //--- Rule 2: evaluate existing setups
   for(int p = ArraySize(g_pend) - 1; p >= 0; p--)
   {
      if(i - g_pend[p].bar > InpR2Window) { RemovePend(p); continue; }
      if(i <= g_pend[p].bar) continue;
      double cover = (InpCover == COVER_RANGE) ? (g_pend[p].h + g_pend[p].l) / 2.0 : (g_pend[p].o + g_pend[p].c) / 2.0;
      if(g_pend[p].dir == 1 && cl > g_pend[p].y && cl >= cover)
      {
         if(InpRule2) OfferSignal(g_sb, 2, g_pend[p].ln, g_pend[p].y, i);
         RemovePend(p);
      }
      else if(g_pend[p].dir == -1 && cl < g_pend[p].y && cl <= cover)
      {
         if(InpRule2) OfferSignal(g_ss, 2, g_pend[p].ln, g_pend[p].y, i);
         RemovePend(p);
      }
   }

   for(int k = 0; k < ArraySize(g_act); k++)
   {
      double y = g_act[k].y;
      //--- Rule 1 / 3 (buy): wick below the line, whole body above it
      bool r1b = (y - lo >= minW) && op > y && cl > y;
      bool r3b = r1b && g_act[k].type == 1 && pcl > y;
      if((InpRule1 && r1b) || (InpRule3 && r3b)) OfferSignal(g_sb, r3b ? 3 : 1, g_act[k].ln, y, i);
      //--- Rule 1 / 3 (sell): wick above the line, whole body below it
      bool r1s = (hi - y >= minW) && op < y && cl < y;
      bool r3s = r1s && g_act[k].type == -1 && pcl < y;
      if((InpRule1 && r1s) || (InpRule3 && r3s)) OfferSignal(g_ss, r3s ? 3 : 1, g_act[k].ln, y, i);

      //--- Rule 2: register a new breakout candle
      if(InpRule2)
      {
         int dir = 0;
         if(cl < y && pcl >= y) dir = 1;
         else if(cl > y && pcl <= y) dir = -1;
         if(dir != 0)
         {
            bool dup = false;
            for(int p = 0; p < ArraySize(g_pend); p++)
               if(g_pend[p].ln == g_act[k].ln && g_pend[p].dir == dir) { dup = true; break; }
            if(!dup)
            {
               int n = ArraySize(g_pend);
               ArrayResize(g_pend, n + 1);
               g_pend[n].ln = g_act[k].ln; g_pend[n].dir = dir; g_pend[n].y = y;
               g_pend[n].o = op; g_pend[n].h = hi; g_pend[n].l = lo; g_pend[n].c = cl; g_pend[n].bar = i;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Process ONE closed bar                                           |
//+------------------------------------------------------------------+
void ProcessBar(const int i, const bool isLast)
{
   const double pt = _Point;
   const double hi = g_high[i], lo = g_low[i], cl = g_close[i];
   const double mav = g_buf[i];
   const datetime tNext = g_time[i + 1];
   const datetime tLbl  = tNext + (datetime)PeriodSeconds();

   if(isLast) ScanSignals(i);

   //--- 1) mitigation of alive levels
   for(int k = ArraySize(g_act) - 1; k >= 0; k--)
   {
      int sdi = g_act[k].side;
      bool beyond = Beyond(sdi, g_act[k].y, mav, hi, lo, cl);
      if(beyond && !g_act[k].flag)
      {
         g_act[k].cnt++;
         double refPx = (InpMitMode == MIT_MACROSS && mav != EMPTY_VALUE) ? mav : cl;
         sdi = (refPx < g_act[k].y) ? -1 : 1;
         g_act[k].side = sdi;
         beyond = Beyond(sdi, g_act[k].y, mav, hi, lo, cl);
      }
      g_act[k].flag = beyond;

      if(g_act[k].cnt >= InpMaxMit)
      {
         GfxEnd(g_act[k], g_time[i], tNext, Blend(InpMitColor, g_bg, InpTransp));
         if(InpDelMin > 0 && g_draw)
         {
            int nd = ArraySize(g_done);
            ArrayResize(g_done, nd + 1);
            g_done[nd].ln = g_act[k].ln; g_done[nd].lb = g_act[k].lb; g_done[nd].t = g_time[i];
         }
         else GfxDel(g_act[k].ln, g_act[k].lb);
         RemoveAct(k);
      }
      else if(isLast)
         GfxAlive(g_act[k], tNext, tLbl, LevelColor(g_act[k], cl));
   }

   if(InpDelMin > 0)
      for(int d = ArraySize(g_done) - 1; d >= 0; d--)
         if((long)(g_time[i] - g_done[d].t) >= (long)InpDelMin * 60)
         { GfxDel(g_done[d].ln, g_done[d].lb); RemoveDone(d); }

   //--- reference point
   int lastType = 0; double lastLvl = 0.0;
   int na = ArraySize(g_act);
   if(na > 0) { lastType = g_act[na - 1].type; lastLvl = g_act[na - 1].lvl; }

   //--- MA direction and flips
   g_dirPrev = g_dir;
   if(i >= 1 && g_buf[i] != EMPTY_VALUE && g_buf[i - 1] != EMPTY_VALUE)
   {
      if(g_buf[i] > g_buf[i - 1]) g_dir = 1;
      else if(g_buf[i] < g_buf[i - 1]) g_dir = -1;
   }
   bool flipTop = (g_dir == -1 && g_dirPrev == 1);
   bool flipBot = (g_dir == 1 && g_dirPrev == -1);
   double lvl = (i >= 1) ? g_buf[i - 1] : EMPTY_VALUE;

   if(flipTop && lvl != EMPTY_VALUE)
   {
      bool okT = (lastType == 0) || (lvl >= lastLvl + (lastType == 1 ? InpSameDst : InpOppDst) * pt);
      if(okT && (g_candType != 1 || lvl > g_candLvl)) { g_candType = 1; g_candLvl = lvl; g_candTime = g_time[i - 1]; }
   }
   if(flipBot && lvl != EMPTY_VALUE)
   {
      bool okB = (lastType == 0) || (lvl <= lastLvl - (lastType == -1 ? InpSameDst : InpOppDst) * pt);
      if(okB && (g_candType != -1 || lvl < g_candLvl)) { g_candType = -1; g_candLvl = lvl; g_candTime = g_time[i - 1]; }
   }

   //--- confirmation -> new level
   if(g_candType != 0)
   {
      bool useClose = (InpMeasure == MEASURE_CLOSE);
      double pxDown = useClose ? cl : lo, pxUp = useClose ? cl : hi;
      bool moved = (g_candType == 1) ? (pxDown <= g_candLvl - InpConfirm * pt) : (pxUp >= g_candLvl + InpConfirm * pt);
      if(moved)
      {
         bool keepIt = true;
         for(int k = 0; k < ArraySize(g_act); k++)
            if(g_act[k].type == g_candType && MathAbs(g_act[k].lvl - g_candLvl) <= InpCluster * pt)
               if((g_candType == 1 && g_act[k].lvl >= g_candLvl) || (g_candType == -1 && g_act[k].lvl <= g_candLvl)) keepIt = false;
         if(keepIt)
         {
            for(int k = ArraySize(g_act) - 1; k >= 0; k--)
               if(g_act[k].type == g_candType && MathAbs(g_act[k].lvl - g_candLvl) <= InpCluster * pt)
               { GfxDel(g_act[k].ln, g_act[k].lb); RemoveAct(k); }

            double yC = g_candLvl + g_candType * InpVOff * pt;
            int sdC = (cl < yC) ? -1 : 1;
            color bc = (g_candType == 1) ? InpPeakColor : InpBotColor;
            color c0 = Blend(bc, g_bg, (int)MathRound(InpTransp * (1.0 - Proximity(yC, cl))));
            g_seq++;
            string ln = g_prefix + "L" + IntegerToString(g_seq);
            string lb = g_prefix + "T" + IntegerToString(g_seq);
            GfxCreate(ln, lb, yC, g_candTime, tNext, tLbl, c0, InpMaxMit);

            int n = ArraySize(g_act);
            ArrayResize(g_act, n + 1);
            g_act[n].ln = ln; g_act[n].lb = lb; g_act[n].type = g_candType; g_act[n].lvl = g_candLvl;
            g_act[n].y = yC; g_act[n].side = sdC; g_act[n].cnt = 0;
            g_act[n].flag = Beyond(sdC, yC, mav, hi, lo, cl);
         }
         g_candType = 0;
      }
   }
}

//+------------------------------------------------------------------+
//| Engine update                                                    |
//+------------------------------------------------------------------+
bool EngineUpdate()
{
   MqlRates r[];
   ArraySetAsSeries(r, false);
   int got;
   if(g_t0 == 0)
   {
      int avail = Bars(_Symbol, _Period);
      int want = (InpMaxBars > 0) ? MathMin(avail, InpMaxBars) : avail;
      got = CopyRates(_Symbol, _Period, 0, want, r);
   }
   else got = CopyRates(_Symbol, _Period, g_t0, iTime(_Symbol, _Period, 0), r);
   if(got < 3) return false;

   int prevN = g_n;
   if(g_t0 == 0) { g_t0 = r[0].time; ResetAll(); prevN = 0; }
   if(got < prevN) { ResetAll(); prevN = 0; }

   ArrayResize(g_time, got, 1000); ArrayResize(g_open, got, 1000); ArrayResize(g_high, got, 1000);
   ArrayResize(g_low, got, 1000);  ArrayResize(g_close, got, 1000); ArrayResize(g_vol, got, 1000);
   ArrayResize(g_buf, got, 1000);  ArrayResize(g_src, got, 1000);   ArrayResize(g_a, got, 1000);
   ArrayResize(g_b, got, 1000);    ArrayResize(g_c, got, 1000);     ArrayResize(g_d, got, 1000);
   ArrayResize(g_cpv, got, 1000);  ArrayResize(g_cv, got, 1000);

   int from = (prevN > 0) ? prevN - 1 : 0;
   for(int i = from; i < got; i++)
   {
      g_time[i] = r[i].time; g_open[i] = r[i].open; g_high[i] = r[i].high;
      g_low[i] = r[i].low;   g_close[i] = r[i].close; g_vol[i] = (long)r[i].tick_volume;
      g_src[i] = PriceAt(i);
      ComputeMA(i);
   }
   g_n = got;

   g_bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   int to = got - 2;
   bool did = false;
   for(int i = g_processed + 1; i <= to; i++) { ProcessBar(i, i == to); did = true; }
   if(did) { g_processed = to; if(g_draw) ChartRedraw(0); }
   return true;
}

//+------------------------------------------------------------------+
//| Trading helpers                                                  |
//+------------------------------------------------------------------+
double NormVol(const double v)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double r = MathFloor(v / step + 1e-9) * step;
   return NormalizeDouble(MathMin(mx, MathMax(0.0, r)), 8);
}
int FindMeta(const ulong tk)
{
   for(int m = 0; m < ArraySize(g_pm); m++) if(g_pm[m].ticket == tk) return m;
   return -1;
}
void SyncPositions(const SSig &s)
{
   for(int m = ArraySize(g_pm) - 1; m >= 0; m--)
      if(!PositionSelectByTicket(g_pm[m].ticket))
      {
         int n = ArraySize(g_pm);
         for(int j = m; j < n - 1; j++) g_pm[j] = g_pm[j + 1];
         ArrayResize(g_pm, n - 1);
      }
   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      ulong tk = PositionGetTicket(p);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != (long)InpMagic) continue;
      if(FindMeta(tk) >= 0) continue;
      int n = ArraySize(g_pm);
      ArrayResize(g_pm, n + 1);
      g_pm[n].ticket = tk; g_pm[n].parts = 0; g_pm[n].invDone = false;
      g_pm[n].reason = s.reason; g_pm[n].sigTime = s.t;
      g_pm[n].so = s.o; g_pm[n].sh = s.h; g_pm[n].sl = s.l; g_pm[n].sc = s.c;
   }
}
int CountDir(const long type, double &lastPrice, datetime &lastTime)
{
   int cnt = 0; lastPrice = 0; lastTime = 0;
   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      ulong tk = PositionGetTicket(p);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != (long)InpMagic) continue;
      if(PositionGetInteger(POSITION_TYPE) != type) continue;
      cnt++;
      datetime t = (datetime)PositionGetInteger(POSITION_TIME);
      if(t >= lastTime) { lastTime = t; lastPrice = PositionGetDouble(POSITION_PRICE_OPEN); }
   }
   return cnt;
}
bool InCooldown() { return (InpCooldownMin > 0 && TimeCurrent() < g_cdUntil); }

// isDD = true -> drawdown (averaging) entry; false -> fresh signal entry
void OpenTrade(const int dir, const SSig &s, const bool isDD)
{
   string side = (dir > 0) ? "BUY" : "SELL";
   if(InCooldown()) { if(!isDD) Dbg(side + " skipped: cooldown until " + TimeToString(g_cdUntil, TIME_DATE | TIME_SECONDS)); return; }
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(InpMaxSpread > 0 && (ask - bid) / _Point > InpMaxSpread) { Dbg(side + " skipped: spread"); return; }
   if((!isDD || InpKZApplyDD) && !KZ_Allow()) { Dbg(side + " skipped: outside kill zone"); return; }

   double lastPx; datetime lastT;
   long type = (dir > 0) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   int cnt = CountDir(type, lastPx, lastT);

   if(!isDD)
   {
      if(cnt > 0) { Dbg(side + " signal ignored: already in a " + side + " trade"); return; }
      if(InpMaxTradesPerLevel > 0 && LCget(s.ln, dir) >= InpMaxTradesPerLevel)
      { Dbg(side + " skipped: max trades on this level reached"); return; }
   }
   else
   {
      if(cnt < 1 || cnt >= 1 + InpDDEntries) return;
      double worse = (dir > 0) ? (lastPx - ask) : (bid - lastPx);
      if(worse < InpDDStep * _Point) return;
   }
   double lot = NormVol(InpLot);
   if(lot < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) { Dbg("skipped: lot below minimum"); return; }

   double px = (dir > 0) ? ask : bid;
   double sl = (InpSLPts > 0) ? NormalizeDouble(px - dir * InpSLPts * _Point, _Digits) : 0;
   double tp = (InpTPPts > 0) ? NormalizeDouble(px + dir * InpTPPts * _Point, _Digits) : 0;
   string cm = isDD ? ("MAIL DD" + IntegerToString(cnt)) : ("MAIL R" + IntegerToString(s.reason));

   bool ok = (dir > 0) ? g_trade.Buy(lot, _Symbol, 0, sl, tp, cm) : g_trade.Sell(lot, _Symbol, 0, sl, tp, cm);
   if(!ok) { Print("Order failed: ", g_trade.ResultRetcode(), " ", g_trade.ResultRetcodeDescription()); return; }
   if(!isDD) LCinc(s.ln, dir);
   Dbg(side + " opened: " + cm + " lot=" + DoubleToString(lot, 2));
   SyncPositions(s);
}

void TryDistanceDD()
{
   if(InpDDMode != DD_DISTANCE || InpDDEntries < 1) return;
   SSig d; ClearSig(d);
   for(int k = 0; k < 2; k++) OpenTrade(k == 0 ? 1 : -1, d, true);
}

void CheckInvalidations()
{
   int c = g_n - 2, p = g_n - 3;
   if(p < 0) return;
   for(int m = ArraySize(g_pm) - 1; m >= 0; m--)
   {
      if(g_pm[m].invDone || g_pm[m].reason == 0) continue;
      if(g_pm[m].reason == 2 && !InpInvOnR2) continue;
      if(g_pm[m].sigTime != g_time[p]) continue;
      g_pm[m].invDone = true;
      ulong tk = g_pm[m].ticket;
      if(!PositionSelectByTicket(tk)) continue;
      bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double sigRange = g_pm[m].sh - g_pm[m].sl, nxtRange = g_high[c] - g_low[c];
      bool bearC = g_close[c] < g_open[c], bullC = g_close[c] > g_open[c];
      bool close = false;

      if(InpInv1 && nxtRange > sigRange)
      {
         if(!InpInv1AdverseOnly) close = true;
         else close = isBuy ? bearC : bullC;
      }
      if(InpInv2 && !close)
      {
         if(isBuy)
            close = (g_pm[m].sc > g_pm[m].so) && bearC && g_open[c] >= g_pm[m].sc &&
                    g_close[c] <= g_pm[m].so && g_low[c] <= g_pm[m].sl;
         else
            close = (g_pm[m].sc < g_pm[m].so) && bullC && g_open[c] <= g_pm[m].sc &&
                    g_close[c] >= g_pm[m].so && g_high[c] >= g_pm[m].sh;
      }
      if(close) { Dbg("invalidation: closing ticket " + (string)tk); g_trade.PositionClose(tk); }
   }
}

void ManagePositions()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double stopsLvl = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   ulong tks[];
   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      ulong tk = PositionGetTicket(p);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != (long)InpMagic) continue;
      int n = ArraySize(tks); ArrayResize(tks, n + 1); tks[n] = tk;
   }
   for(int q = 0; q < ArraySize(tks); q++)
   {
      ulong tk = tks[q];
      if(!PositionSelectByTicket(tk)) continue;
      int m = FindMeta(tk);
      if(m < 0) continue;
      bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double open = PositionGetDouble(POSITION_PRICE_OPEN), sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP), vol = PositionGetDouble(POSITION_VOLUME);
      double profPts = (isBuy ? (bid - open) : (open - ask)) / _Point;

      if(g_pm[m].parts < InpPartials && profPts >= (g_pm[m].parts + 1) * (double)InpPartialStep)
      {
         double cv = NormVol(vol * InpPartialPct / 100.0);
         if(cv >= minV && vol - cv >= minV)
         {
            if(g_trade.PositionClosePartial(tk, cv)) g_pm[m].parts++;
         }
         else g_pm[m].parts = InpPartials;
         if(!PositionSelectByTicket(tk)) continue;
         vol = PositionGetDouble(POSITION_VOLUME);
      }

      double newSL = sl, newTP = tp;
      bool trailing = (profPts >= InpTrailStart);
      if(trailing)
      {
         newTP = 0;
         double cand = isBuy ? bid - InpTrailDist * _Point : ask + InpTrailDist * _Point;
         cand = NormalizeDouble(cand, _Digits);
         double stepP = InpTrailStep * _Point;
         bool better = (sl == 0) || (isBuy ? cand >= sl + stepP : cand <= sl - stepP);
         double dist = isBuy ? bid - cand : cand - ask;
         if(better && dist >= stopsLvl) newSL = cand;
      }
      else if(InpBEPts > 0 && profPts >= InpBEPts)
      {
         double be = NormalizeDouble(open + (isBuy ? 1 : -1) * InpBEOffset * _Point, _Digits);
         bool need = (sl == 0) || (isBuy ? sl < be : sl > be);
         double dist = isBuy ? bid - be : be - ask;
         if(need && dist >= stopsLvl) newSL = be;
      }
      if(newSL != sl || newTP != tp) g_trade.PositionModify(tk, newSL, newTP);
   }
}

void DDCleanup()
{
   if(InpDDClose <= 0) return;
   for(int d = 0; d < 2; d++)
   {
      long type = (d == 0) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      ulong tks[]; datetime tms[]; double prf[];
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong tk = PositionGetTicket(p);
         if(tk == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != (long)InpMagic) continue;
         if(PositionGetInteger(POSITION_TYPE) != type) continue;
         int n = ArraySize(tks);
         ArrayResize(tks, n + 1); ArrayResize(tms, n + 1); ArrayResize(prf, n + 1);
         tks[n] = tk; tms[n] = (datetime)PositionGetInteger(POSITION_TIME);
         prf[n] = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      }
      int cnt = ArraySize(tks);
      if(cnt < 2) continue;
      int latest = 0;
      for(int j = 1; j < cnt; j++)
         if(tms[j] > tms[latest] || (tms[j] == tms[latest] && tks[j] > tks[latest])) latest = j;
      for(int j = 0; j < cnt; j++)
         if(j != latest && prf[j] >= InpDDClose) g_trade.PositionClose(tks[j]);
   }
}

//+------------------------------------------------------------------+
//| Events                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpMaLen < 1 || InpMaxMit < 1) return INIT_PARAMETERS_INCORRECT;
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      Print("This EA needs a HEDGING account (multiple positions per symbol).");
      return INIT_FAILED;
   }
   g_draw = InpDraw && (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE));

   ArrayResize(g_almaW, InpMaLen);
   double m = MathFloor(0.85 * (InpMaLen - 1)), s = InpMaLen / 6.0;
   g_almaNorm = 0.0;
   for(int k = 0; k < InpMaLen; k++)
   {
      g_almaW[k] = MathExp(-((k - m) * (k - m)) / (2.0 * s * s));
      g_almaNorm += g_almaW[k];
   }
   double a1 = MathExp(-1.414 * M_PI / InpMaLen), b1 = 2.0 * a1 * MathCos(1.414 * M_PI / InpMaLen);
   g_c2 = b1; g_c3 = -a1 * a1; g_c1 = 1.0 - g_c2 - g_c3;

   g_prefix = "MAIE" + IntegerToString((long)GetTickCount()) + "_";
   g_seq = 0; g_t0 = 0; g_n = 0; g_ready = false;
   ClearSig(g_cur);
   
   KZ_Init();
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpDeviation);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   if(EngineUpdate())
   {
      ClearSig(g_sb); ClearSig(g_ss);
      g_lastBar = iTime(_Symbol, _Period, 0);
      g_ready = true;
   }
   SyncPositions(g_cur);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_draw) { ObjectsDeleteAll(0, g_prefix); ChartRedraw(0); }
}

void OnTick()
{
   if(!g_ready)
   {
      if(EngineUpdate()) { ClearSig(g_sb); ClearSig(g_ss); g_lastBar = iTime(_Symbol, _Period, 0); g_ready = true; }
      return;
   }
   SyncPositions(g_cur);

   datetime bt = iTime(_Symbol, _Period, 0);
   if(bt != g_lastBar)
   {
      g_lastBar = bt;
      ClearSig(g_sb); ClearSig(g_ss);
      if(EngineUpdate())
      {
         CheckInvalidations();
         if(g_sb.on && g_ss.on) Dbg("buy and sell signals on the same bar: both skipped");
         else if(g_sb.on)
         {
            if(InpDDMode == DD_SIGNAL && InpDDEntries > 0)
            {
               double lp; datetime lt;
               int c = CountDir(POSITION_TYPE_BUY, lp, lt);
               if(c > 0) OpenTrade(1, g_sb, true); else OpenTrade(1, g_sb, false);
            }
            else OpenTrade(1, g_sb, false);
         }
         else if(g_ss.on)
         {
            if(InpDDMode == DD_SIGNAL && InpDDEntries > 0)
            {
               double lp; datetime lt;
               int c = CountDir(POSITION_TYPE_SELL, lp, lt);
               if(c > 0) OpenTrade(-1, g_ss, true); else OpenTrade(-1, g_ss, false);
            }
            else OpenTrade(-1, g_ss, false);
         }
      }
   }
   TryDistanceDD();
   ManagePositions();
   DDCleanup();
   if(g_draw) UpdateProximity(SymbolInfoDouble(_Symbol, SYMBOL_BID));
}

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &req, const MqlTradeResult &res)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != (long)InpMagic) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;
   if(InpCooldownMin <= 0) return;

   double pl = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
             + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION) + HistoryDealGetDouble(trans.deal, DEAL_FEE);
   double closePx = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   long   dtype   = HistoryDealGetInteger(trans.deal, DEAL_TYPE);       // SELL deal closes a BUY position
   datetime dtime = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
   ulong  pid     = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   if(pl >= 0) return;

   double openPx = 0;
   if(HistorySelectByPosition(pid))
      for(int k = 0; k < HistoryDealsTotal(); k++)
      {
         ulong dt = HistoryDealGetTicket(k);
         if(HistoryDealGetInteger(dt, DEAL_ENTRY) == DEAL_ENTRY_IN) { openPx = HistoryDealGetDouble(dt, DEAL_PRICE); break; }
      }
   if(openPx == 0) return;
   double lossPts = ((dtype == DEAL_TYPE_SELL) ? (openPx - closePx) : (closePx - openPx)) / _Point;
   if(lossPts >= InpCooldownLossPts)
   {
      g_cdUntil = dtime + InpCooldownMin * 60;
      Dbg(StringFormat("loss %.0f pts -> cooldown until %s", lossPts, TimeToString(g_cdUntil, TIME_DATE | TIME_SECONDS)));
   }
   else Dbg(StringFormat("small loss %.0f pts (< %.0f) -> no cooldown", lossPts, InpCooldownLossPts));
}
//+------------------------------------------------------------------+
