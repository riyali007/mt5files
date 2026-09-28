//+------------------------------------------------------------------+
//|                                        smooth_custom_ma_EA.mq5   |
//|  HTF smoothed MA (drawn on chart) + inflection lines +           |
//|  pending-limit trading with cancel / BE / trail / partials       |
//|  Production release V1.0                                         |
//|                                                                  |
//|  Upper line -> SELL LIMIT at the line price                      |
//|  Lower line -> BUY  LIMIT at the line price                      |
//|  Lines are recalculated from history on each new chart bar.      |
//|  Order placement, cancellation and position management run on    |
//|  every tick.                                                     |
//+------------------------------------------------------------------+
#property copyright "smooth_custom_ma EA"
#property version   "1.00"
#property description "HTF MA inflection-line limit-order EA"

#include <Trade\Trade.mqh>

#define MAX_ACTIVE_LINES 400
#define MAX_DRAWN_LINES  100
#define PFX_ALL          "SMEA_"
#define PFX_MA           "SMEA_MA_"
#define PFX_LN           "SMEA_LN_"

enum ENUM_CUSTOM_MA {
   CMA_SMA=0,
   CMA_EMA=1,
   CMA_RMA=2,
   CMA_WMA=3,
   CMA_HMA=4
};

input group "=== Base MA Settings ==="
input int                InpMaxBars      = 1000;            // Chart bars analysed on each new bar
input ENUM_TIMEFRAMES    InpTimeframe    = PERIOD_CURRENT;  // MA timeframe (must be >= chart TF)
input ENUM_CUSTOM_MA     InpBaseMethod   = CMA_HMA;
input int                InpBasePeriod   = 34;
input ENUM_APPLIED_PRICE InpAppliedPrice = PRICE_CLOSE;
input bool               InpNoRepaint    = true;            // Use only completed HTF values (no look-ahead)

input group "=== Smoothing Settings ==="
input ENUM_CUSTOM_MA InpSmoothMethod = CMA_SMA;
input int            InpSmoothPeriod = 1;

input group "=== Display ==="
input bool  InpDrawMA       = true;               // Draw the MA line on the chart
input int   InpMaDrawBars   = 400;                // How many recent bars of MA to draw
input color InpMaColor      = clrDodgerBlue;
input int   InpMaWidth      = 2;
input bool  InpDrawLines    = true;               // Draw active inflection levels
input color InpDimColor     = clrDarkSlateGray;

input group "=== Inflection Line Settings ==="
input int   InpLineOffsetPoints = 350;
input int   InpPivotCandles     = 5;

input group "=== Clustering / Merging Settings ==="
input bool InpEnableClustering      = true;
input int  InpClusterDistancePoints = 100;

input group "=== Pending Order Settings ==="
input double InpLot                  = 0.5;
input int    InpSLPoints             = 700;
input int    InpTPPoints             = 1400;
input int    InpMaxPending           = 30;
input int    InpOrderProximityPoints = 200;
input int    InpCancelAwayPoints     = 500;
input long   InpMagic                = 20260928;

input group "=== Position Management ==="
input int    InpBEPoints            = 200;
input int    InpTrailStartPoints    = 1000;
input int    InpTrailDistancePoints = 200;
input int    InpPartials            = 2;      // Tranches: milestones at k*TP/N, k=1..N-1 (2 = one at TP/2)
input double InpPartialPercent      = 10.0;   // % of INITIAL volume closed per milestone

//--- lines (rebuilt on every new chart bar)
struct SLine {
   double   price;
   datetime startTime;
   bool     upper;
   bool     mitigated;
   bool     alive;
};
SLine g_lines[];

//--- per-line order records (persist across rebuilds)
struct SOrderRec {
   string   key;
   bool     sent;
   datetime nextTry;
};
SOrderRec g_recs[];

//--- per-position state
struct SPosState {
   ulong  ticket;
   double entry;
   double vol0;
   bool   isBuy;
   int    partials;
   bool   beDone;
   bool   trailStarted;
};
SPosState g_ps[];

CTrade          g_trade;
ENUM_TIMEFRAMES g_tf      = PERIOD_CURRENT;
int             g_tfSec   = 60;
int             g_chartSec= 60;
bool            g_sameTf  = true;
int             g_basePeriod   = 1;
int             g_smoothPeriod = 1;
bool            g_drawVisuals  = false;
datetime        g_lastBar = 0;

void DrawLines(const datetime anchor);
void DrawMA(const MqlRates &cr[], const double &ma[], const int n);

//+------------------------------------------------------------------+
//| Moving average maths                                              |
//+------------------------------------------------------------------+
void Wma(const double &in[], double &out[], const int period, const int n)
{
   ArrayResize(out, n);
   if(period <= 1) {
      for(int i = 0; i < n; i++) out[i] = in[i];
      return;
   }
   const double weightSum = (period * (period + 1)) * 0.5;
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

void MaCore(const ENUM_CUSTOM_MA type, const int period,
            const double &seg[], const int m, double &res[])
{
   ArrayResize(res, m);
   if(period <= 1) {
      for(int i = 0; i < m; i++) res[i] = seg[i];
      return;
   }

   if(type == CMA_SMA) {
      double sum = 0.0;
      for(int i = 0; i < m; i++) {
         sum += seg[i];
         if(i >= period) sum -= seg[i - period];
         res[i] = (i < period - 1) ? seg[i] : sum / period;
      }
   }
   else if(type == CMA_EMA || type == CMA_RMA) {
      const double alpha = (type == CMA_EMA) ? 2.0 / (period + 1.0) : 1.0 / (double)period;
      res[0] = seg[0];
      for(int i = 1; i < m; i++)
         res[i] = alpha * seg[i] + (1.0 - alpha) * res[i - 1];
   }
   else if(type == CMA_WMA) {
      Wma(seg, res, period, m);
   }
   else { // HMA
      double a[], b[], raw[];
      Wma(seg, a, MathMax(1, period / 2), m);
      Wma(seg, b, period, m);
      ArrayResize(raw, m);
      for(int i = 0; i < m; i++) raw[i] = 2.0 * a[i] - b[i];
      Wma(raw, res, MathMax(1, (int)MathRound(MathSqrt((double)period))), m);
   }
}

// Runs an MA over a series that may start with EMPTY_VALUE entries.
void MaSeries(const ENUM_CUSTOM_MA type, const int period,
              const double &src[], const int n, double &dst[])
{
   ArrayResize(dst, n);
   int s = 0;
   while(s < n && src[s] == EMPTY_VALUE) s++;
   for(int i = 0; i < s && i < n; i++) dst[i] = EMPTY_VALUE;
   const int m = n - s;
   if(m <= 0) return;

   double seg[], res[];
   ArrayResize(seg, m);
   for(int i = 0; i < m; i++) seg[i] = src[s + i];
   MaCore(type, period, seg, m, res);
   for(int i = 0; i < m; i++) dst[s + i] = res[i];
}

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

//+------------------------------------------------------------------+
//| Inflection line management                                        |
//+------------------------------------------------------------------+
int ActiveCount()
{
   int c = 0;
   for(int i = 0; i < ArraySize(g_lines); i++)
      if(g_lines[i].alive && !g_lines[i].mitigated) c++;
   return c;
}

void DropOldestActive()
{
   int idx = -1;
   for(int i = 0; i < ArraySize(g_lines); i++) {
      if(!g_lines[i].alive || g_lines[i].mitigated) continue;
      if(idx < 0 || g_lines[i].startTime < g_lines[idx].startTime) idx = i;
   }
   if(idx >= 0) g_lines[idx].alive = false;
}

void ClusterActive()
{
   if(!InpEnableClustering) return;
   const double thr = InpClusterDistancePoints * _Point;

   bool merged = true;
   while(merged) {
      merged = false;
      int idx[];
      int cnt = 0;
      ArrayResize(idx, ArraySize(g_lines));
      for(int i = 0; i < ArraySize(g_lines); i++)
         if(g_lines[i].alive && !g_lines[i].mitigated) idx[cnt++] = i;
      if(cnt < 2) return;

      for(int a = 1; a < cnt; a++) {
         const int key = idx[a];
         const double kp = g_lines[key].price;
         int b = a - 1;
         while(b >= 0 && g_lines[idx[b]].price > kp) {
            idx[b + 1] = idx[b];
            b--;
         }
         idx[b + 1] = key;
      }

      int s = 0;
      while(s < cnt && !merged) {
         int e = s;
         while(e + 1 < cnt && (g_lines[idx[e + 1]].price - g_lines[idx[s]].price) <= thr) e++;
         if(e > s) {
            double sum = 0.0;
            int survivor = idx[s];
            datetime minTime = g_lines[survivor].startTime;
            for(int k = s; k <= e; k++) {
               sum += g_lines[idx[k]].price;
               if(g_lines[idx[k]].startTime < minTime) {
                  minTime = g_lines[idx[k]].startTime;
                  survivor = idx[k];
               }
            }
            g_lines[survivor].price = sum / (e - s + 1);
            for(int k = s; k <= e; k++)
               if(idx[k] != survivor) g_lines[idx[k]].alive = false;
            merged = true;
         }
         s = e + 1;
      }
   }
}

void AddInflection(const datetime t, const double price, const bool upper)
{
   while(ActiveCount() >= MAX_ACTIVE_LINES) DropOldestActive();
   const int sz = ArraySize(g_lines);
   ArrayResize(g_lines, sz + 1);
   g_lines[sz].price     = price;
   g_lines[sz].startTime = t;
   g_lines[sz].upper     = upper;
   g_lines[sz].mitigated = false;
   g_lines[sz].alive     = true;
   ClusterActive();
}

//+------------------------------------------------------------------+
//| Rebuild MA + inflection lines from history (closed bars only)     |
//+------------------------------------------------------------------+
bool Rebuild()
{
   MqlRates cr[];
   ArraySetAsSeries(cr, false);
   const int n = CopyRates(_Symbol, _Period, 0, MathMax(InpMaxBars, 100), cr);
   if(n < 50) return false;

   //--- HTF price series
   double   hp[];
   datetime ht[];
   int m = 0;
   if(g_sameTf) {
      m = n;
      ArrayResize(hp, m);
      ArrayResize(ht, m);
      for(int i = 0; i < m; i++) { hp[i] = PriceFromRates(cr[i]); ht[i] = cr[i].time; }
   } else {
      MqlRates hr[];
      ArraySetAsSeries(hr, false);
      const long warm = (long)(g_basePeriod * 4 + 50) * g_tfSec * 8 / 5;
      const datetime st = (datetime)((long)cr[0].time - warm);
      m = CopyRates(_Symbol, g_tf, st, cr[n - 1].time, hr);
      if(m < 2) return false;
      ArrayResize(hp, m);
      ArrayResize(ht, m);
      for(int i = 0; i < m; i++) { hp[i] = PriceFromRates(hr[i]); ht[i] = hr[i].time; }
   }

   double base[];
   MaSeries(InpBaseMethod, g_basePeriod, hp, m, base);

   //--- map HTF MA to chart bars
   double cb[];
   ArrayResize(cb, n);
   int k = 0;
   for(int i = 0; i < n; i++) {
      if(cr[i].time < ht[0]) { cb[i] = EMPTY_VALUE; continue; }
      while(k + 1 < m && ht[k + 1] <= cr[i].time) k++;
      int use = k;
      if(InpNoRepaint && !g_sameTf) {
         if((long)cr[i].time + g_chartSec < (long)ht[k] + g_tfSec) use = k - 1;
      }
      cb[i] = (use >= 0) ? base[use] : EMPTY_VALUE;
   }

   //--- chart-side smoothing
   double ma[];
   MaSeries(InpSmoothMethod, g_smoothPeriod, cb, n, ma);

   //--- scan closed bars (n-1 is the forming bar)
   ArrayResize(g_lines, 0);
   const int last = n - 2;
   int pPeak = -1, pTrough = -1, below = 0, above = 0;

   for(int i = 2; i <= last; i++) {
      if(ma[i] == EMPTY_VALUE) { below = 0; above = 0; continue; }

      if(ma[i - 2] != EMPTY_VALUE && ma[i - 1] != EMPTY_VALUE) {
         if(ma[i - 1] > ma[i - 2] && ma[i - 1] > ma[i]) {
            pPeak = i - 1;
            below = 0;
         } else if(ma[i - 1] < ma[i - 2] && ma[i - 1] < ma[i]) {
            pTrough = i - 1;
            above = 0;
         }
      }

      if(cr[i].close < ma[i]) below++; else below = 0;
      if(cr[i].close > ma[i]) above++; else above = 0;

      if(pPeak != -1 && below >= InpPivotCandles) {
         AddInflection(cr[pPeak].time, ma[pPeak] + InpLineOffsetPoints * _Point, true);
         pPeak = -1;
      }
      if(pTrough != -1 && above >= InpPivotCandles) {
         AddInflection(cr[pTrough].time, ma[pTrough] - InpLineOffsetPoints * _Point, false);
         pTrough = -1;
      }

      for(int j = 0; j < ArraySize(g_lines); j++) {
         if(!g_lines[j].alive || g_lines[j].mitigated) continue;
         if(cr[i].time <= g_lines[j].startTime) continue;
         if(cr[i].high >= g_lines[j].price && cr[i].low <= g_lines[j].price)
            g_lines[j].mitigated = true;
      }
   }

   if(g_drawVisuals) {
      if(InpDrawMA) DrawMA(cr, ma, n);
      if(InpDrawLines) DrawLines(cr[n - 1].time);
      ChartRedraw(0);
   }
   return true;
}

//+------------------------------------------------------------------+
//| Drawing                                                           |
//+------------------------------------------------------------------+
void DrawMA(const MqlRates &cr[], const double &ma[], const int n)
{
   ObjectsDeleteAll(0, PFX_MA);
   const int from = MathMax(1, n - MathMax(InpMaDrawBars, 2));
   int c = 0;
   for(int i = from; i < n; i++) {
      if(ma[i] == EMPTY_VALUE || ma[i - 1] == EMPTY_VALUE) continue;
      const string name = PFX_MA + IntegerToString(c++);
      if(!ObjectCreate(0, name, OBJ_TREND, 0, cr[i - 1].time, ma[i - 1], cr[i].time, ma[i])) continue;
      ObjectSetInteger(0, name, OBJPROP_COLOR, InpMaColor);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, InpMaWidth);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
}

void DrawLines(const datetime anchor)
{
   ObjectsDeleteAll(0, PFX_LN);
   int drawn = 0;
   for(int i = ArraySize(g_lines) - 1; i >= 0 && drawn < MAX_DRAWN_LINES; i--) {
      if(!g_lines[i].alive || g_lines[i].mitigated) continue;
      const string name = PFX_LN + IntegerToString(drawn);
      ObjectCreate(0, name, OBJ_TREND, 0, g_lines[i].startTime, g_lines[i].price,
                   g_lines[i].startTime + g_tfSec, g_lines[i].price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, InpDimColor);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);

      const string lbl = name + "_L";
      ObjectCreate(0, lbl, OBJ_TEXT, 0, anchor, g_lines[i].price);
      ObjectSetString(0, lbl, OBJPROP_TEXT, " " + DoubleToString(g_lines[i].price, _Digits));
      ObjectSetInteger(0, lbl, OBJPROP_COLOR, InpDimColor);
      ObjectSetInteger(0, lbl, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, lbl, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0, lbl, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, lbl, OBJPROP_HIDDEN, true);
      drawn++;
   }
}

//+------------------------------------------------------------------+
//| Generic helpers                                                   |
//+------------------------------------------------------------------+
double NormalizeToTick(const double p)
{
   const double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts <= 0.0) return NormalizeDouble(p, _Digits);
   return NormalizeDouble(MathRound(p / ts) * ts, _Digits);
}

double MinStopDist()
{
   return (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
}

double VolStep()
{
   const double s = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   return (s > 0.0) ? s : 0.01;
}

int VolDigits()
{
   double s = VolStep();
   int d = 0;
   while(d < 8 && MathAbs(s - MathRound(s)) > 1e-9) { s *= 10.0; d++; }
   return d;
}

// Rounds DOWN to the volume step. Returns 0 if outside broker limits.
double RoundVolDown(const double v)
{
   const double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   const double step = VolStep();
   const double r = NormalizeDouble(MathFloor(v / step + 1e-9) * step, VolDigits());
   if(r < vmin - 1e-12 || r > vmax + 1e-12) return 0.0;
   return r;
}

// True only if the request was sent AND the server accepted it.
bool TradeOk(const bool called)
{
   if(!called) return false;
   const uint rc = g_trade.ResultRetcode();
   return (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED || rc == TRADE_RETCODE_DONE_PARTIAL);
}

void LogFail(const string what)
{
   PrintFormat("%s failed: retcode=%u (%s)", what, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| Order records                                                     |
//+------------------------------------------------------------------+
int FindRec(const string key)
{
   for(int i = 0; i < ArraySize(g_recs); i++)
      if(g_recs[i].key == key) return i;
   return -1;
}

int EnsureRec(const string key)
{
   int i = FindRec(key);
   if(i >= 0) return i;
   i = ArraySize(g_recs);
   ArrayResize(g_recs, i + 1);
   g_recs[i].key = key;
   g_recs[i].sent = false;
   g_recs[i].nextTry = 0;
   return i;
}

string LineKey(const int j)
{
   return (g_lines[j].upper ? "HTF_S_" : "HTF_B_") + IntegerToString((long)g_lines[j].startTime);
}

//+------------------------------------------------------------------+
//| Pending orders                                                    |
//+------------------------------------------------------------------+
int CountPendingOwned()
{
   int c = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      const ulong tk = OrderGetTicket(i);
      if(tk == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;
      c++;
   }
   return c;
}

bool CommentExists(const string key)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      const ulong tk = OrderGetTicket(i);
      if(tk == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;
      if(StringFind(OrderGetString(ORDER_COMMENT), key) >= 0) return true;
   }
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      const ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(StringFind(PositionGetString(POSITION_COMMENT), key) >= 0) return true;
   }
   return false;
}

bool LineTouchedNow(const int j)
{
   const datetime t0 = iTime(_Symbol, _Period, 0);
   if(t0 <= g_lines[j].startTime) return false;
   return (iHigh(_Symbol, _Period, 0) >= g_lines[j].price &&
           iLow(_Symbol, _Period, 0)  <= g_lines[j].price);
}

void PlaceOrders()
{
   int pending = CountPendingOwned();
   if(pending >= InpMaxPending) return;

   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0) return;
   const double md   = MinStopDist();
   const double prox = InpOrderProximityPoints * _Point;
   const datetime now = TimeCurrent();

   for(int j = 0; j < ArraySize(g_lines); j++) {
      if(!g_lines[j].alive || g_lines[j].mitigated) continue;

      const bool sell = g_lines[j].upper;
      const string key = LineKey(j);

      const int ri = FindRec(key);
      if(ri >= 0 && (g_recs[ri].sent || now < g_recs[ri].nextTry)) continue;

      const double price = NormalizeToTick(g_lines[j].price);
      if(sell) {
         if(price - ask <= md) continue;      // must be above ask by more than min stop distance
         if(price - ask > prox) continue;     // too far from market
      } else {
         if(bid - price <= md) continue;      // must be below bid by more than min stop distance
         if(bid - price > prox) continue;
      }

      if(LineTouchedNow(j)) continue;         // mitigated on the forming bar
      if(CommentExists(key)) continue;

      const double vol = RoundVolDown(InpLot);
      if(vol <= 0.0) { Print("Invalid order volume after rounding: ", InpLot); continue; }

      double sl = 0.0, tp = 0.0;
      if(sell) {
         if(InpSLPoints > 0) sl = NormalizeToTick(price + InpSLPoints * _Point);
         if(InpTPPoints > 0) tp = NormalizeToTick(price - InpTPPoints * _Point);
      } else {
         if(InpSLPoints > 0) sl = NormalizeToTick(price - InpSLPoints * _Point);
         if(InpTPPoints > 0) tp = NormalizeToTick(price + InpTPPoints * _Point);
      }

      g_trade.SetTypeFilling(ORDER_FILLING_RETURN);
      bool called = sell ? g_trade.SellLimit(vol, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, key)
                         : g_trade.BuyLimit (vol, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, key);

      const int idx = EnsureRec(key);
      if(TradeOk(called)) {
         g_recs[idx].sent = true;
         pending++;
         if(pending >= InpMaxPending) return;
      } else {
         LogFail((sell ? "SellLimit " : "BuyLimit ") + key);
         g_recs[idx].nextTry = now + 30;      // avoid retry spam every tick
      }
   }
}

// Deletes a pending order once the market has moved away from it.
// The line's "sent" flag is reset so the order can be re-placed if price
// returns to the level before the inflection line is mitigated.
void CancelFarOrders()
{
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0) return;
   const double away = InpCancelAwayPoints * _Point;

   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      const ulong tk = OrderGetTicket(i);
      if(tk == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;

      const ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      const double op = OrderGetDouble(ORDER_PRICE_OPEN);

      bool del = false;
      if(ot == ORDER_TYPE_SELL_LIMIT && ask <= op - away - 1e-9) del = true;
      if(ot == ORDER_TYPE_BUY_LIMIT  && bid >= op + away + 1e-9) del = true;

      if(del) {
         const string cmt = OrderGetString(ORDER_COMMENT);   // read before deleting
         if(TradeOk(g_trade.OrderDelete(tk))) {
            // Re-arm the line: it may place a new order when price returns
            // within proximity, until the inflection line is mitigated.
            const int ri = FindRec(cmt);
            if(ri >= 0) {
               g_recs[ri].sent = false;
               g_recs[ri].nextTry = 0;
            }
         } else LogFail("OrderDelete #" + IntegerToString((long)tk));
      }
   }
}

//+------------------------------------------------------------------+
//| Open position management                                          |
//+------------------------------------------------------------------+
int FindState(const ulong ticket)
{
   for(int i = 0; i < ArraySize(g_ps); i++)
      if(g_ps[i].ticket == ticket) return i;
   return -1;
}

int EnsureState(const ulong ticket)
{
   int i = FindState(ticket);
   if(i >= 0) return i;
   if(!PositionSelectByTicket(ticket)) return -1;

   i = ArraySize(g_ps);
   ArrayResize(g_ps, i + 1);
   g_ps[i].ticket = ticket;
   g_ps[i].entry  = PositionGetDouble(POSITION_PRICE_OPEN);
   g_ps[i].vol0   = PositionGetDouble(POSITION_VOLUME);
   g_ps[i].isBuy  = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   g_ps[i].partials = 0;

   // Recover sensible state if the EA was restarted with a position already open
   const double sl = PositionGetDouble(POSITION_SL);
   const double tp = PositionGetDouble(POSITION_TP);
   g_ps[i].beDone = (sl > 0.0 && (g_ps[i].isBuy ? sl >= g_ps[i].entry - 1e-9 : sl <= g_ps[i].entry + 1e-9));
   g_ps[i].trailStarted = (tp == 0.0);
   return i;
}

void CleanupStates()
{
   for(int i = ArraySize(g_ps) - 1; i >= 0; i--) {
      if(!PositionSelectByTicket(g_ps[i].ticket)) {
         const int last = ArraySize(g_ps) - 1;
         if(i != last) g_ps[i] = g_ps[last];
         ArrayResize(g_ps, last);
      }
   }
}

void ManageOnePosition(const ulong ticket)
{
   const int si = EnsureState(ticket);
   if(si < 0) return;
   if(!PositionSelectByTicket(ticket)) return;

   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0) return;

   const bool   isBuy = g_ps[si].isBuy;
   const double entry = g_ps[si].entry;
   const double md    = MinStopDist();
   const double profitPts = (isBuy ? (bid - entry) : (entry - ask)) / _Point;

   double sl = PositionGetDouble(POSITION_SL);
   double tp = PositionGetDouble(POSITION_TP);

   g_trade.SetTypeFillingBySymbol(_Symbol);

   //--- 1) Break-even
   if(!g_ps[si].trailStarted && !g_ps[si].beDone && profitPts >= InpBEPoints) {
      const double newSL = NormalizeToTick(entry);
      const bool already = (sl > 0.0 && (isBuy ? sl >= newSL - 1e-9 : sl <= newSL + 1e-9));
      if(already) {
         g_ps[si].beDone = true;
      } else {
         const bool distOk = isBuy ? (bid - newSL > md) : (newSL - ask > md);
         if(distOk) {
            if(TradeOk(g_trade.PositionModify(ticket, newSL, tp))) {
               g_ps[si].beDone = true;
               sl = newSL;
            } else LogFail("Break-even #" + IntegerToString((long)ticket));
         }
      }
   }

   //--- 2) Trailing (and removal of the original TP)
   if(g_ps[si].trailStarted || profitPts >= InpTrailStartPoints) {
      const double prop = NormalizeToTick(isBuy ? bid - InpTrailDistancePoints * _Point
                                                : ask + InpTrailDistancePoints * _Point);
      const bool improves = isBuy ? (sl == 0.0 || prop > sl + 1e-9)
                                  : (sl == 0.0 || prop < sl - 1e-9);
      const bool distOk = isBuy ? (bid - prop > md) : (prop - ask > md);

      if(improves && distOk) {
         if(TradeOk(g_trade.PositionModify(ticket, prop, 0.0))) {
            g_ps[si].trailStarted = true;
            return;   // trailing started/advanced: skip partials this tick
         } else LogFail("Trail #" + IntegerToString((long)ticket));
      }
      else if(!g_ps[si].trailStarted && tp != 0.0) {
         // SL cannot improve; still remove the full TP
         if(TradeOk(g_trade.PositionModify(ticket, sl, 0.0))) {
            g_ps[si].trailStarted = true;
            return;
         } else LogFail("Remove TP #" + IntegerToString((long)ticket));
      }
   }

   //--- 3) Partial closes (only before trailing starts)
   if(g_ps[si].trailStarted) return;
   if(InpPartials < 2 || InpPartialPercent <= 0.0 || InpTPPoints <= 0) return;
   if(g_ps[si].partials >= InpPartials - 1) return;

   const double milestone = (double)InpTPPoints * (g_ps[si].partials + 1) / (double)InpPartials;
   if(profitPts < milestone) return;

   if(!PositionSelectByTicket(ticket)) return;
   const double curVol = PositionGetDouble(POSITION_VOLUME);
   const double vmin   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double piece  = RoundVolDown(g_ps[si].vol0 * InpPartialPercent / 100.0);
   if(piece <= 0.0) return;
   if(curVol - piece < vmin - 1e-12) return;   // would leave less than minimum volume

   if(TradeOk(g_trade.PositionClosePartial(ticket, piece)))
      g_ps[si].partials++;
   else
      LogFail("Partial close #" + IntegerToString((long)ticket));
}

void ManagePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      const ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      ManageOnePosition(tk);
   }
   CleanupStates();
}

//+------------------------------------------------------------------+
int OnInit()
{
   if(InpBasePeriod < 1 || InpSmoothPeriod < 1 || InpPivotCandles < 1 || InpMaxBars < 100)
      return(INIT_PARAMETERS_INCORRECT);
   if(InpLot <= 0.0 || InpMaxPending < 1)
      return(INIT_PARAMETERS_INCORRECT);

   g_tf = (InpTimeframe == PERIOD_CURRENT ? (ENUM_TIMEFRAMES)_Period : InpTimeframe);
   g_tfSec = PeriodSeconds(g_tf);
   g_chartSec = PeriodSeconds((ENUM_TIMEFRAMES)_Period);
   if(g_tfSec < g_chartSec) {
      Print("MA timeframe must be equal to or higher than the chart timeframe.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   g_sameTf = (g_tf == (ENUM_TIMEFRAMES)_Period);

   g_basePeriod   = MathMax(1, InpBasePeriod);
   g_smoothPeriod = MathMax(1, InpSmoothPeriod);

   const bool tester = (bool)MQLInfoInteger(MQL_TESTER) || (bool)MQLInfoInteger(MQL_OPTIMIZATION);
   const bool visual = (bool)MQLInfoInteger(MQL_VISUAL_MODE);
   g_drawVisuals = !(bool)MQLInfoInteger(MQL_OPTIMIZATION) && (!tester || visual);

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(20);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   ArrayResize(g_lines, 0);
   ArrayResize(g_recs, 0);
   ArrayResize(g_ps, 0);
   g_lastBar = 0;
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, PFX_ALL);
}

//+------------------------------------------------------------------+
void OnTick()
{
   //--- lines / MA: refresh once per new chart bar (retry each tick until data is ready)
   const datetime bar = iTime(_Symbol, _Period, 0);
   if(bar != 0 && bar != g_lastBar) {
      if(Rebuild()) g_lastBar = bar;
   }

   //--- per-tick trade logic
   CancelFarOrders();
   ManagePositions();
   PlaceOrders();
}
//+------------------------------------------------------------------+