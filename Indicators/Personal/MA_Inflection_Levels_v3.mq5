//+------------------------------------------------------------------+
//| MA_Inflection_Levels.mq5                                         |
//| Up to 3 moving averages (14 types). Each MA has its own level    |
//| timeframe and its own inflection-line toggle.                    |
//+------------------------------------------------------------------+
#property copyright "MA Inflection Levels"
#property version   "3.00"
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   3
#property indicator_label1  "MA 1"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrAqua
#property indicator_width1  2
#property indicator_label2  "MA 2"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrYellow
#property indicator_width2  2
#property indicator_label3  "MA 3"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrViolet
#property indicator_width3  2

enum ENUM_MA_KIND
{
   KIND_ALMA,
   KIND_DEMA,
   KIND_EMA,
   KIND_HMA,
   KIND_HULLMA,
   KIND_LSMA,
   KIND_RMA,
   KIND_SMMA,
   KIND_SSMA,
   KIND_TMA,
   KIND_TEMA,
   KIND_VWMA,
   KIND_WMA,
   KIND_VWAP
};

enum ENUM_MEASURE
{
   MEASURE_HL,
   MEASURE_CLOSE
};

enum ENUM_MITIGATION
{
   MIT_WICK,
   MIT_BCC,
   MIT_MACROSS
};

input group "Calculation"
input int InpMaxBars = 10000;                   // Calculation bars per level TF (0 = all)

input group "MA 1"
input bool InpMa1On = true;                     // MA 1 on
input ENUM_TIMEFRAMES InpMa1TF = PERIOD_M3;     // MA 1 timeframe (PERIOD_CURRENT = chart)
input bool InpMa1Lvl = true;                    // MA 1 inflection lines on
input ENUM_MA_KIND InpMa1Type = KIND_HMA;
input ENUM_APPLIED_PRICE InpMa1Src = PRICE_CLOSE;
input int InpMa1Len = 21;
input color InpMa1Color = clrAqua;

input group "MA 2"
input bool InpMa2On = true;
input ENUM_TIMEFRAMES InpMa2TF = PERIOD_M3;
input bool InpMa2Lvl = true;
input ENUM_MA_KIND InpMa2Type = KIND_EMA;
input ENUM_APPLIED_PRICE InpMa2Src = PRICE_CLOSE;
input int InpMa2Len = 50;
input color InpMa2Color = clrYellow;

input group "MA 3"
input bool InpMa3On = true;
input ENUM_TIMEFRAMES InpMa3TF = PERIOD_M3;
input bool InpMa3Lvl = true;
input ENUM_MA_KIND InpMa3Type = KIND_RMA;
input ENUM_APPLIED_PRICE InpMa3Src = PRICE_CLOSE;
input int InpMa3Len = 100;
input color InpMa3Color = clrViolet;

input group "Inflection Lines"
input ENUM_MEASURE InpMeasure = MEASURE_HL;
input double InpConfirm = 800;
input double InpOppDst = 1000;
input double InpSameDst = 800;
input ENUM_MITIGATION InpMitMode = MIT_BCC;
input int InpMaxMit = 3;
input bool InpMitAway = true;
input double InpMitAwayPts = 300;
input double InpCluster = 400;
input double InpVOff = 0.0;
input int InpTransp = 70;
input double InpNearDst = 50;
input double InpFarDst = 500;
input int InpDelMin = 500;
input color InpPeakColor = clrTomato;
input color InpBotColor = clrSpringGreen;
input color InpMitColor = clrGray;
input int InpFontSize = 8;

struct SLevel
{
   string ln;
   string lb;
   int    type;
   double lvl;
   double y;
   int    side;
   int    cnt;
   bool   flag;
   bool   away;
};

struct SDone
{
   string   ln;
   string   lb;
   datetime t;
};

struct SMA
{
   bool               on;
   bool               lvl;
   ENUM_TIMEFRAMES    tf;
   ENUM_TIMEFRAMES    ftf;
   ENUM_MA_KIND       type;
   ENUM_APPLIED_PRICE src;
   int                len;
   string             prefix;
   bool               reloaded;
   datetime           lastHTF;
   int                htfN;
   datetime           htfT[];
   double             hO[], hH[], hL[], hC[];
   long               hV[];
   double             px[];
   double             buf[];
   double             a1[], b1[], c1[], d1[];
   double             cpv[], cv[];
   double             w[];
   double             wn;
   double             k1, k2, k3;
   SLevel             act[];
   SDone              done[];
   int                dir;
   int                dirPrev;
   int                candType;
   double             candLvl;
   datetime           candTime;
   int                seq;
};

SMA      g_ma[3];
double   g_p0[], g_p1[], g_p2[];
color    g_bg = clrBlack;
string   g_base = "";

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

double ALMAat(const double &a[], const int i, const int len, const double &w[], const double norm)
{
   if(i - len + 1 < 0) return EMPTY_VALUE;
   double s = 0;
   for(int k = 0; k < len; k++)
   {
      double v = a[i - len + 1 + k];
      if(v == EMPTY_VALUE) return EMPTY_VALUE;
      s += v * w[k];
   }
   return s / norm;
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

void RMAstep(const double &src[], double &out[], const int i, const int len)
{
   if(i > 0 && out[i - 1] != EMPTY_VALUE && src[i] != EMPTY_VALUE)
      out[i] = (src[i] + (len - 1) * out[i - 1]) / len;
   else
      out[i] = SMAat(src, i, len);
}

void SSstep(const double &src[], double &out[], const int i, const double c1, const double c2, const double c3)
{
   double s = src[i];
   double s1 = (i >= 1) ? src[i - 1] : s;
   double f1 = (i >= 1 && out[i - 1] != EMPTY_VALUE) ? out[i - 1] : s;
   double f2 = (i >= 2 && out[i - 2] != EMPTY_VALUE) ? out[i - 2] : s;
   out[i] = c1 * (s + s1) / 2.0 + c2 * f1 + c3 * f2;
}

double PriceAtM(SMA &M, const int i)
{
   switch(M.src)
   {
      case PRICE_OPEN:     return M.hO[i];
      case PRICE_HIGH:     return M.hH[i];
      case PRICE_LOW:      return M.hL[i];
      case PRICE_MEDIAN:   return (M.hH[i] + M.hL[i]) / 2.0;
      case PRICE_TYPICAL:  return (M.hH[i] + M.hL[i] + M.hC[i]) / 3.0;
      case PRICE_WEIGHTED: return (M.hH[i] + M.hL[i] + 2.0 * M.hC[i]) / 4.0;
      default:             return M.hC[i];
   }
}

void ComputeMA(SMA &M, const int i)
{
   const int len = M.len;
   double v = EMPTY_VALUE;
   switch(M.type)
   {
      case KIND_ALMA:
         v = ALMAat(M.px, i, len, M.w, M.wn);
         break;
      case KIND_DEMA:
      {
         EMAstep(M.px, M.a1, i, len);
         EMAstep(M.a1, M.b1, i, len);
         v = (M.a1[i] != EMPTY_VALUE && M.b1[i] != EMPTY_VALUE) ? 2.0 * M.a1[i] - M.b1[i] : EMPTY_VALUE;
         break;
      }
      case KIND_EMA:
         EMAstep(M.px, M.a1, i, len);
         v = M.a1[i];
         break;
      case KIND_HMA:
      {
         int half = MathMax(1, len / 2);
         int root = MathMax(1, (int)MathRound(MathSqrt(len)));
         M.a1[i] = WMAat(M.px, i, half);
         M.b1[i] = WMAat(M.px, i, len);
         M.c1[i] = (M.a1[i] != EMPTY_VALUE && M.b1[i] != EMPTY_VALUE) ? 2.0 * M.a1[i] - M.b1[i] : EMPTY_VALUE;
         v = WMAat(M.c1, i, root);
         break;
      }
      case KIND_HULLMA:
      {
         int half = MathMax(1, (int)MathRound(len / 2.0));
         int root = MathMax(1, (int)MathRound(MathSqrt(len)));
         EMAstep(M.px, M.a1, i, half);
         EMAstep(M.px, M.b1, i, len);
         M.c1[i] = (M.a1[i] != EMPTY_VALUE && M.b1[i] != EMPTY_VALUE) ? 2.0 * M.a1[i] - M.b1[i] : EMPTY_VALUE;
         EMAstep(M.c1, M.d1, i, root);
         v = M.d1[i];
         break;
      }
      case KIND_LSMA:
         v = LSMAat(M.px, i, len);
         break;
      case KIND_RMA:
      case KIND_SMMA:
         RMAstep(M.px, M.a1, i, len);
         v = M.a1[i];
         break;
      case KIND_SSMA:
         SSstep(M.px, M.a1, i, M.k1, M.k2, M.k3);
         v = M.a1[i];
         break;
      case KIND_TMA:
      {
         int a = (int)MathCeil(len / 2.0);
         int b = (int)MathFloor(len / 2.0) + 1;
         M.a1[i] = SMAat(M.px, i, a);
         v = SMAat(M.a1, i, b);
         break;
      }
      case KIND_TEMA:
         EMAstep(M.px, M.a1, i, len);
         EMAstep(M.a1, M.b1, i, len);
         EMAstep(M.b1, M.c1, i, len);
         v = (M.a1[i] != EMPTY_VALUE && M.b1[i] != EMPTY_VALUE && M.c1[i] != EMPTY_VALUE)
             ? 3.0 * (M.a1[i] - M.b1[i]) + M.c1[i] : EMPTY_VALUE;
         break;
      case KIND_VWMA:
      {
         if(i - len + 1 < 0) { v = EMPTY_VALUE; break; }
         double spv = 0, sv = 0;
         bool ok = true;
         for(int k = i - len + 1; k <= i; k++)
         {
            if(M.px[k] == EMPTY_VALUE) { ok = false; break; }
            spv += M.px[k] * (double)M.hV[k];
            sv += (double)M.hV[k];
         }
         v = (ok && sv > 0) ? spv / sv : EMPTY_VALUE;
         break;
      }
      case KIND_WMA:
         v = WMAat(M.px, i, len);
         break;
      case KIND_VWAP:
      {
         bool nd = (i == 0) || (M.cpv[i - 1] == EMPTY_VALUE) || ((long)M.htfT[i] / 86400 != (long)M.htfT[i - 1] / 86400);
         double pv = (nd ? 0.0 : M.cpv[i - 1]) + M.px[i] * (double)M.hV[i];
         double vv = (nd ? 0.0 : M.cv[i - 1]) + (double)M.hV[i];
         M.cpv[i] = pv;
         M.cv[i] = vv;
         v = (vv > 0) ? pv / vv : M.px[i];
         break;
      }
   }
   M.buf[i] = v;
}

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
      for(int k = 0; k < lives; k++) s += ShortToString(0x2665);
   }
   else
      s += " " + ShortToString(0x00D7);
   return s;
}

bool Beyond(const int sd, const double y, const double m, const double hi, const double lo, const double cl)
{
   switch(InpMitMode)
   {
      case MIT_WICK:   return (sd == -1) ? (hi >= y) : (lo <= y);
      case MIT_MACROSS:
         if(m == EMPTY_VALUE) return false;
         return (sd == -1) ? (m > y) : (m < y);
      default:         return (sd == -1) ? (cl > y) : (cl < y);
   }
}

double Proximity(const double y, const double px)
{
   double d = MathAbs(px - y) / _Point;
   double nearD = MathMax(0.0, InpNearDst);
   double farD = MathMax(InpFarDst, nearD + 1.0);
   if(d <= nearD) return 1.0;
   if(d >= farD) return 0.0;
   return 1.0 - (d - nearD) / (farD - nearD);
}

color LevelColor(const SLevel &L, const double px)
{
   int effT = (L.cnt % 2 == 0) ? L.type : -L.type;
   color bc = (effT == 1) ? InpPeakColor : InpBotColor;
   int tr = (int)MathRound(InpTransp * (1.0 - Proximity(L.y, px)));
   return Blend(bc, g_bg, tr);
}

void UpdateProximity(const double px)
{
   bool changed = false;
   for(int m = 0; m < 3; m++)
   {
      if(!g_ma[m].on || !g_ma[m].lvl) continue;
      int n = ArraySize(g_ma[m].act);
      for(int k = 0; k < n; k++)
      {
         color fc = LevelColor(g_ma[m].act[k], px);
         if((color)ObjectGetInteger(0, g_ma[m].act[k].ln, OBJPROP_COLOR) != fc)
         {
            ObjectSetInteger(0, g_ma[m].act[k].ln, OBJPROP_COLOR, fc);
            ObjectSetInteger(0, g_ma[m].act[k].lb, OBJPROP_COLOR, fc);
            changed = true;
         }
      }
   }
   if(changed) ChartRedraw(0);
}

void RemoveAct(SMA &M, const int k)
{
   int n = ArraySize(M.act);
   for(int j = k; j < n - 1; j++) M.act[j] = M.act[j + 1];
   ArrayResize(M.act, n - 1);
}

void RemoveDone(SMA &M, const int k)
{
   int n = ArraySize(M.done);
   for(int j = k; j < n - 1; j++) M.done[j] = M.done[j + 1];
   ArrayResize(M.done, n - 1);
}

void ResetAll(SMA &M)
{
   if(StringLen(M.prefix) > 0) ObjectsDeleteAll(0, M.prefix);
   ArrayResize(M.act, 0);
   ArrayResize(M.done, 0);
   M.dir = 0;
   M.dirPrev = 0;
   M.candType = 0;
   M.candLvl = 0.0;
   M.candTime = 0;
   M.seq = 0;
}

void ProcessBar(SMA &M, const int i)
{
   const double pt = _Point;
   const double hi = M.hH[i], lo = M.hL[i], cl = M.hC[i];
   const double mav = M.buf[i];
   const datetime tNext = M.htfT[i + 1];
   const datetime tLbl = tNext + (datetime)PeriodSeconds(M.ftf);
   const double awayPts = MathMax(0.0, InpMitAwayPts) * pt;
   const bool needAway = (InpMitAway && awayPts > 0.0);
   const bool isLast = (i == M.htfN - 2);
   const datetime tI = M.htfT[i];

   for(int k = ArraySize(M.act) - 1; k >= 0; k--)
   {
      int sdi = M.act[k].side;
      bool beyond = Beyond(sdi, M.act[k].y, mav, hi, lo, cl);
      const bool wasAway = M.act[k].away;
      if(needAway && !M.act[k].away && (hi >= M.act[k].y + awayPts || lo <= M.act[k].y - awayPts))
         M.act[k].away = true;

      if(beyond && !M.act[k].flag && (!needAway || wasAway))
      {
         M.act[k].cnt++;
         M.act[k].away = !needAway;
         double refPx = (InpMitMode == MIT_MACROSS && mav != EMPTY_VALUE) ? mav : cl;
         sdi = (refPx < M.act[k].y) ? -1 : 1;
         M.act[k].side = sdi;
         beyond = Beyond(sdi, M.act[k].y, mav, hi, lo, cl);
         if(needAway)
         {
            if(sdi == -1 && lo <= M.act[k].y - awayPts) M.act[k].away = true;
            if(sdi == 1 && hi >= M.act[k].y + awayPts) M.act[k].away = true;
         }
      }
      M.act[k].flag = beyond;

      if(M.act[k].cnt >= InpMaxMit)
      {
         color mc = Blend(InpMitColor, g_bg, InpTransp);
         ObjectSetInteger(0, M.act[k].ln, OBJPROP_TIME, 1, tI);
         ObjectSetInteger(0, M.act[k].ln, OBJPROP_COLOR, mc);
         ObjectSetInteger(0, M.act[k].lb, OBJPROP_TIME, 0, tNext);
         ObjectSetInteger(0, M.act[k].lb, OBJPROP_COLOR, mc);
         ObjectSetString(0, M.act[k].lb, OBJPROP_TEXT, Lbl(M.act[k].y, 0));
         if(InpDelMin > 0)
         {
            int nd = ArraySize(M.done);
            ArrayResize(M.done, nd + 1);
            M.done[nd].ln = M.act[k].ln;
            M.done[nd].lb = M.act[k].lb;
            M.done[nd].t = tI;
         }
         RemoveAct(M, k);
      }
      else if(isLast)
      {
         color fc = LevelColor(M.act[k], cl);
         ObjectSetInteger(0, M.act[k].ln, OBJPROP_COLOR, fc);
         ObjectSetInteger(0, M.act[k].ln, OBJPROP_TIME, 1, tNext);
         ObjectSetInteger(0, M.act[k].lb, OBJPROP_COLOR, fc);
         ObjectSetInteger(0, M.act[k].lb, OBJPROP_TIME, 0, tLbl);
         ObjectSetString(0, M.act[k].lb, OBJPROP_TEXT, Lbl(M.act[k].y, InpMaxMit - M.act[k].cnt));
      }
   }

   if(InpDelMin > 0)
   {
      for(int d = ArraySize(M.done) - 1; d >= 0; d--)
      {
         if((long)(tI - M.done[d].t) >= (long)InpDelMin * 60)
         {
            ObjectDelete(0, M.done[d].ln);
            ObjectDelete(0, M.done[d].lb);
            RemoveDone(M, d);
         }
      }
   }

   int lastType = 0;
   double lastLvl = 0.0;
   int na = ArraySize(M.act);
   if(na > 0)
   {
      lastType = M.act[na - 1].type;
      lastLvl = M.act[na - 1].lvl;
   }

   M.dirPrev = M.dir;
   if(i >= 1 && M.buf[i] != EMPTY_VALUE && M.buf[i - 1] != EMPTY_VALUE)
   {
      if(M.buf[i] > M.buf[i - 1]) M.dir = 1;
      else if(M.buf[i] < M.buf[i - 1]) M.dir = -1;
   }
   bool flipTop = (M.dir == -1 && M.dirPrev == 1);
   bool flipBot = (M.dir == 1 && M.dirPrev == -1);
   double lvl = (i >= 1) ? M.buf[i - 1] : EMPTY_VALUE;

   if(flipTop && lvl != EMPTY_VALUE)
   {
      bool okT = (lastType == 0) || (lvl >= lastLvl + (lastType == 1 ? InpSameDst : InpOppDst) * pt);
      if(okT && (M.candType != 1 || lvl > M.candLvl))
      {
         M.candType = 1;
         M.candLvl = lvl;
         M.candTime = M.htfT[i - 1];
      }
   }
   if(flipBot && lvl != EMPTY_VALUE)
   {
      bool okB = (lastType == 0) || (lvl <= lastLvl - (lastType == -1 ? InpSameDst : InpOppDst) * pt);
      if(okB && (M.candType != -1 || lvl < M.candLvl))
      {
         M.candType = -1;
         M.candLvl = lvl;
         M.candTime = M.htfT[i - 1];
      }
   }

   if(M.candType != 0)
   {
      bool useClose = (InpMeasure == MEASURE_CLOSE);
      double pxDown = useClose ? cl : lo;
      double pxUp = useClose ? cl : hi;
      bool moved = (M.candType == 1) ? (pxDown <= M.candLvl - InpConfirm * pt)
                                     : (pxUp >= M.candLvl + InpConfirm * pt);
      if(moved)
      {
         bool keepIt = true;
         int nAct = ArraySize(M.act);
         for(int k = 0; k < nAct; k++)
         {
            if(M.act[k].type == M.candType && MathAbs(M.act[k].lvl - M.candLvl) <= InpCluster * pt)
            {
               if((M.candType == 1 && M.act[k].lvl >= M.candLvl) || (M.candType == -1 && M.act[k].lvl <= M.candLvl))
                  keepIt = false;
            }
         }
         if(keepIt)
         {
            for(int k = ArraySize(M.act) - 1; k >= 0; k--)
            {
               if(M.act[k].type == M.candType && MathAbs(M.act[k].lvl - M.candLvl) <= InpCluster * pt)
               {
                  ObjectDelete(0, M.act[k].ln);
                  ObjectDelete(0, M.act[k].lb);
                  RemoveAct(M, k);
               }
            }

            double yC = M.candLvl + M.candType * InpVOff * pt;
            int sdC = (cl < yC) ? -1 : 1;
            color bc = (M.candType == 1) ? InpPeakColor : InpBotColor;
            color c0 = Blend(bc, g_bg, (int)MathRound(InpTransp * (1.0 - Proximity(yC, cl))));

            M.seq++;
            string ln = M.prefix + "L" + IntegerToString(M.seq);
            string lb = M.prefix + "T" + IntegerToString(M.seq);

            ObjectCreate(0, ln, OBJ_TREND, 0, M.candTime, yC, tNext, yC);
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

            int n = ArraySize(M.act);
            ArrayResize(M.act, n + 1);
            M.act[n].ln = ln;
            M.act[n].lb = lb;
            M.act[n].type = M.candType;
            M.act[n].lvl = M.candLvl;
            M.act[n].y = yC;
            M.act[n].side = sdC;
            M.act[n].cnt = 0;
            M.act[n].away = true;
            M.act[n].flag = Beyond(sdC, yC, mav, hi, lo, cl);
         }
         M.candType = 0;
      }
   }
}

void ComputeAll(SMA &M, const int n)
{
   ResetAll(M);
   ArrayResize(M.px, n);  ArrayResize(M.buf, n); ArrayResize(M.a1, n);  ArrayResize(M.b1, n);
   ArrayResize(M.c1, n);  ArrayResize(M.d1, n); ArrayResize(M.cpv, n); ArrayResize(M.cv, n);
   ArrayInitialize(M.buf, EMPTY_VALUE); ArrayInitialize(M.a1, EMPTY_VALUE); ArrayInitialize(M.b1, EMPTY_VALUE);
   ArrayInitialize(M.c1, EMPTY_VALUE);  ArrayInitialize(M.d1, EMPTY_VALUE); ArrayInitialize(M.cpv, EMPTY_VALUE);
   ArrayInitialize(M.cv, EMPTY_VALUE);

   for(int i = 0; i < n; i++)
   {
      M.px[i] = PriceAtM(M, i);
      ComputeMA(M, i);
   }
   if(M.lvl)
      for(int i = 1; i <= n - 2; i++)
         ProcessBar(M, i);
}

void UpdateMA(SMA &M)
{
   M.reloaded = false;
   if(!M.on) return;

   ENUM_TIMEFRAMES tf = (M.tf == PERIOD_CURRENT) ? _Period : M.tf;
   if(PeriodSeconds(tf) < PeriodSeconds(_Period)) tf = _Period;
   M.ftf = tf;

   datetime cur = iTime(_Symbol, tf, 0);
   if(cur == 0) return;

   if(cur != M.lastHTF || M.htfN == 0)
   {
      MqlRates R[];
      int nb = iBars(_Symbol, tf);
      int cnt = (InpMaxBars > 0) ? MathMin(InpMaxBars, nb) : nb;
      int n = CopyRates(_Symbol, tf, 0, cnt, R);
      if(n < 2) return;

      ArrayResize(M.htfT, n); ArrayResize(M.hO, n); ArrayResize(M.hH, n);
      ArrayResize(M.hL, n);   ArrayResize(M.hC, n); ArrayResize(M.hV, n);
      for(int k = 0; k < n; k++)
      {
         M.htfT[k] = R[k].time;
         M.hO[k] = R[k].open;
         M.hH[k] = R[k].high;
         M.hL[k] = R[k].low;
         M.hC[k] = R[k].close;
         M.hV[k] = (long)R[k].tick_volume;
      }
      M.htfN = n;
      M.lastHTF = cur;
      M.reloaded = true;
      ComputeAll(M, n);
   }
   else
   {
      MqlRates R1[];
      if(CopyRates(_Symbol, tf, 0, 1, R1) == 1)
      {
         int j = M.htfN - 1;
         M.hO[j] = R1[0].open;
         M.hH[j] = R1[0].high;
         M.hL[j] = R1[0].low;
         M.hC[j] = R1[0].close;
         M.hV[j] = (long)R1[0].tick_volume;
         M.px[j] = PriceAtM(M, j);
         ComputeMA(M, j);
      }
   }
}

int FindIdx(const SMA &M, const long t, const long P)
{
   int lo = 0, hi = M.htfN - 1, res = -1;
   while(lo <= hi)
   {
      int mid = (lo + hi) >> 1;
      if((long)M.htfT[mid] + P <= t) { res = mid; lo = mid + 1; }
      else hi = mid - 1;
   }
   return res;
}

void FillPlot(SMA &M, double &plot[], const int total, const datetime &time[], const int startI)
{
   ArrayResize(plot, total);
   if(!M.on || M.htfN == 0)
   {
      for(int i = startI; i < total; i++) plot[i] = EMPTY_VALUE;
      return;
   }
   const long P = (long)PeriodSeconds(M.ftf);
   const int n = M.htfN;
   int k = FindIdx(M, (long)time[startI], P);
   for(int i = startI; i < total; i++)
   {
      const long t = (long)time[i];
      while(k + 1 < n && (long)M.htfT[k + 1] + P <= t) k++;
      if(k < 0 || M.buf[k] == EMPTY_VALUE)
      {
         plot[i] = EMPTY_VALUE;
         continue;
      }
      if(k + 1 < n && M.buf[k + 1] != EMPTY_VALUE)
      {
         double fr = (double)(t - ((long)M.htfT[k] + P)) / (double)P;
         fr = MathMax(0.0, MathMin(1.0, fr));
         plot[i] = M.buf[k] + (M.buf[k + 1] - M.buf[k]) * fr;
      }
      else
         plot[i] = M.buf[k];
   }
}

void InitMA(SMA &M, const bool on, const bool lvl, const ENUM_TIMEFRAMES tf, const ENUM_MA_KIND t,
            const ENUM_APPLIED_PRICE s, const int len, const string tag)
{
   M.on = on;
   M.lvl = lvl;
   M.tf = tf;
   M.ftf = _Period;
   M.type = t;
   M.src = s;
   M.len = len;
   M.prefix = g_base + tag + "_";
   M.lastHTF = 0;
   M.htfN = 0;
   M.reloaded = false;

   ArrayResize(M.w, len);
   double m = MathFloor(0.85 * (len - 1));
   double sg = len / 6.0;
   M.wn = 0.0;
   for(int k = 0; k < len; k++)
   {
      M.w[k] = MathExp(-((k - m) * (k - m)) / (2.0 * sg * sg));
      M.wn += M.w[k];
   }

   double a1 = MathExp(-1.414 * M_PI / len);
   double b1 = 2.0 * a1 * MathCos(1.414 * M_PI / len);
   M.k2 = b1;
   M.k3 = -a1 * a1;
   M.k1 = 1.0 - M.k2 - M.k3;

   ResetAll(M);
}

int OnInit()
{
   if(InpMa1Len < 1 || InpMa2Len < 1 || InpMa3Len < 1 || InpMaxMit < 1)
      return INIT_PARAMETERS_INCORRECT;

   g_base = "MAIL" + IntegerToString((long)GetTickCount()) + "_";

   SetIndexBuffer(0, g_p0, INDICATOR_DATA);
   SetIndexBuffer(1, g_p1, INDICATOR_DATA);
   SetIndexBuffer(2, g_p2, INDICATOR_DATA);
   ArraySetAsSeries(g_p0, false);
   ArraySetAsSeries(g_p1, false);
   ArraySetAsSeries(g_p2, false);

   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpMa1Color);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, InpMa2Color);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, InpMa3Color);
   for(int p = 0; p < 3; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, InpMa1Len);
   PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, InpMa2Len);
   PlotIndexSetInteger(2, PLOT_DRAW_BEGIN, InpMa3Len);

   InitMA(g_ma[0], InpMa1On, InpMa1Lvl, InpMa1TF, InpMa1Type, InpMa1Src, InpMa1Len, "A");
   InitMA(g_ma[1], InpMa2On, InpMa2Lvl, InpMa2TF, InpMa2Type, InpMa2Src, InpMa2Len, "B");
   InitMA(g_ma[2], InpMa3On, InpMa3Lvl, InpMa3TF, InpMa3Type, InpMa3Src, InpMa3Len, "C");

   IndicatorSetString(INDICATOR_SHORTNAME, "MA Inflection Levels");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   for(int m = 0; m < 3; m++)
      if(StringLen(g_ma[m].prefix) > 0) ObjectsDeleteAll(0, g_ma[m].prefix);
   ChartRedraw(0);
}

int StartIndex(const SMA &M, const int prev_calculated, const int rates_total)
{
   if(prev_calculated == 0 || M.reloaded) return 0;
   int ratio = (int)((long)PeriodSeconds(M.ftf) / (long)PeriodSeconds(_Period));
   return MathMax(0, rates_total - ratio - 3);
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[],
                const double &close[], const long &tick_volume[], const long &volume[],
                const int &spread[])
{
   if(rates_total < 2) return 0;

   g_bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   for(int m = 0; m < 3; m++)
      UpdateMA(g_ma[m]);

   FillPlot(g_ma[0], g_p0, rates_total, time, StartIndex(g_ma[0], prev_calculated, rates_total));
   FillPlot(g_ma[1], g_p1, rates_total, time, StartIndex(g_ma[1], prev_calculated, rates_total));
   FillPlot(g_ma[2], g_p2, rates_total, time, StartIndex(g_ma[2], prev_calculated, rates_total));

   UpdateProximity(close[rates_total - 1]);
   return rates_total;
}
