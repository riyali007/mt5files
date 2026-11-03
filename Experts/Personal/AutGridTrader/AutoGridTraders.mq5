//+------------------------------------------------------------------+
//| AutoGridTraders.mq5  v1.10                                       |
//| Elastic Risk-Budget Grid: ATR-spaced, HMA-anchored, regime-gated |
//| v1.10: InpInvertMode (momentum pyramid instead of dip/rally grid)|
//| Requires a HEDGING account to run buy and sell baskets together. |
//+------------------------------------------------------------------+
#property copyright "Riy Ali"
#property version   "1.10"
#property strict

#include <Trade/Trade.mqh>

input group "Mode"
input bool   InpInvertMode    = false;     // true = trade the opposite way of every grid signal

input group "Grid engine"
input ENUM_TIMEFRAMES InpGridTF       = PERIOD_M15;
input int    InpHmaPeriod     = 21;
input int    InpATRPeriod     = 14;
input double InpStepATR       = 0.60;
input double InpMinStepPts    = 50;
input double InpMaxStepPts    = 0;
input int    InpMaxLevels     = 6;
input double InpLotDecay      = 0.30;
input double InpEscapeSteps   = 1.0;

input group "Risk budget"
input double InpBasketRiskPct = 1.0;
input double InpMaxDrawdownPct= 10.0;
input double InpMaxDailyLossPct=3.0;
input int    InpMaxSpread     = 0;
input long   InpMagic         = 20261010;

input group "Basket exit"
input double InpTPStep        = 1.0;
input double InpTrailStep     = 0.5;
input int    InpMaxBasketHours= 48;

input group "Regime gate (efficiency ratio on grid TF)"
input int    InpERLen         = 20;
input double InpERRange       = 0.30;
input double InpERTrend       = 0.55;
input int    InpCounterLevels = 2;
input int    InpTrendLevels   = 4;

input group "Trend escape (normal mode only)"
input bool   InpFlipOnEscape  = true;
input double InpFlipRiskPct   = 0.5;
input double InpFlipSL_ATR    = 1.5;
input double InpFlipTrailATR  = 1.2;
input int    InpCooldownMin   = 60;

input group "Session (server time)"
input bool   InpUseSession    = false;
input int    InpStartHour     = 7;
input int    InpEndHour       = 20;

input group "Chart theme"
input bool   InpApplyBlackTheme   = true;
input color  InpBullCandleColor   = C'38,166,154';   // teal
input color  InpBearCandleColor   = C'239,83,80';    // red
input bool   InpDrawGrid          = true;
input bool   InpShowPanel         = true;
input bool   InpDebug             = true;

#define PFX "AGT_"
#define MAXL 20

struct Basket
{
   bool     active;
   int      dir;      // actual order direction
   int      sig;      // grid signal direction (dir, or -dir in invert mode)
   double   anchor, step, stopPx, peak;
   int      N, nFilled;
   double   lots[MAXL + 1];
   bool     filled[MAXL + 1];
   bool     armed;
   datetime opened, cooldownUntil;
};

struct Grid
{
   bool   valid;
   double atr, step, er, hma;
   int    trend;
};

CTrade   trade;
Basket   gB[2];        // 0 = buy basket, 1 = sell basket (actual direction)
Grid     G;
bool     g_hedging = true, g_draw = true, g_dirty = true;
double   g_peakEq = 0, g_dayStartEq = 0;
datetime g_haltDay = 0, g_lastM1 = 0, g_lastD1 = 0;
string   g_status = "";
int      g_dbg = 0;

void Dbg(string m) { if(InpDebug && (g_dbg++ % 300 == 0)) Print("DBG: ", m); }
int  Idx(int dir)  { return dir > 0 ? 0 : 1; }
string Tag(int dir){ return dir > 0 ? "AGT_B" : "AGT_S"; }

//+------------------------------------------------------------------+
double WMAat(const double &a[], int k, int p)
{
   double s = 0, w = 0;
   for(int j = 0; j < p; j++) { double wt = p - j; s += a[k - j] * wt; w += wt; }
   return s / w;
}

bool CalcGrid()
{
   G.valid = false;
   MqlRates r[];
   int need = InpHmaPeriod * 3 + InpERLen + InpATRPeriod + 60;
   int n = CopyRates(_Symbol, InpGridTF, 0, need, r);
   if(n < need - 5) return false;

   int half = MathMax(1, InpHmaPeriod / 2);
   int sq   = MathMax(1, (int)MathFloor(MathSqrt(InpHmaPeriod)));
   double px[], raw[];
   ArrayResize(px, n); ArrayResize(raw, n);
   for(int i = 0; i < n; i++) { px[i] = r[i].close; raw[i] = 0; }
   for(int k = InpHmaPeriod - 1; k < n; k++)
      raw[k] = 2.0 * WMAat(px, k, half) - WMAat(px, k, InpHmaPeriod);
   int f = InpHmaPeriod - 1 + sq - 1;
   if(n - 3 < f) return false;
   double h0 = WMAat(raw, n - 1, sq), h1 = WMAat(raw, n - 2, sq), h2 = WMAat(raw, n - 3, sq);
   G.hma   = h0;
   G.trend = h1 >= h2 ? 1 : -1;

   int c = n - 2;
   double s = 0;
   for(int i = c; i > c - InpATRPeriod; i--)
      s += MathMax(r[i].high - r[i].low, MathMax(MathAbs(r[i].high - r[i-1].close), MathAbs(r[i].low - r[i-1].close)));
   G.atr = s / InpATRPeriod;
   if(G.atr <= 0) return false;

   double net = MathAbs(r[c].close - r[c - InpERLen].close), path = 0;
   for(int i = c; i > c - InpERLen; i--) path += MathAbs(r[i].close - r[i-1].close);
   G.er = path > 0 ? net / path : 0;

   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double st = G.atr * InpStepATR;
   if(InpMinStepPts > 0) st = MathMax(st, InpMinStepPts * pt);
   if(InpMaxStepPts > 0) st = MathMin(st, InpMaxStepPts * pt);
   G.step  = st;
   G.valid = true;
   return true;
}

//+------------------------------------------------------------------+
int SideStats(int dir, double &vol, double &avg, datetime &oldest)
{
   int cnt = 0; vol = 0; avg = 0; oldest = 0;
   double wsum = 0;
   string tg = Tag(dir);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_COMMENT) != tg) continue;
      double v = PositionGetDouble(POSITION_VOLUME);
      wsum += PositionGetDouble(POSITION_PRICE_OPEN) * v;
      vol  += v;
      cnt++;
      datetime tm = (datetime)PositionGetInteger(POSITION_TIME);
      if(oldest == 0 || tm < oldest) oldest = tm;
   }
   if(vol > 0) avg = wsum / vol;
   return cnt;
}

void CloseTag(string tg)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(tg != "" && PositionGetString(POSITION_COMMENT) != tg) continue;
      trade.PositionClose(t);
   }
}

//+------------------------------------------------------------------+
// Distance (in steps) from level k to the hard stop.
double RiskSteps(int N, int k)
{
   if(InpInvertMode) return k + InpEscapeSteps;          // stop sits on the far side of the anchor
   return (N + InpEscapeSteps) - k;                      // stop sits beyond the last level
}

bool PlanBasket(Basket &b, double budget)
{
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double stepL   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minL    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(tickVal <= 0 || tickSz <= 0 || b.step <= 0) return false;
   double vpu = tickVal / tickSz;
   double decay = MathMax(0.0, MathMin(0.7, InpLotDecay));

   for(int N = b.N; N >= 1; N--)
   {
      double wsum = 0;
      double w[MAXL + 1];
      for(int k = 1; k <= N; k++)
      {
         w[k] = 1.0 - decay * (N > 1 ? (double)(k - 1) / (N - 1) : 0.0);
         wsum += w[k] * RiskSteps(N, k) * b.step;
      }
      if(wsum <= 0) continue;
      double L = budget / (vpu * wsum);
      double loss = 0;
      for(int k = 1; k <= N; k++)
      {
         double lot = MathFloor(L * w[k] / stepL) * stepL;
         lot = MathMin(maxL, MathMax(minL, lot));
         b.lots[k] = lot;
         loss += lot * vpu * RiskSteps(N, k) * b.step;
      }
      if(loss <= budget * 1.10)
      {
         b.N = N;
         if(InpInvertMode) b.stopPx = b.anchor + b.sig * InpEscapeSteps * b.step;
         else              b.stopPx = b.anchor - b.sig * (N + InpEscapeSteps) * b.step;
         return true;
      }
   }
   return false;
}

// dir = actual order direction
int LevelsAllowed(int dir)
{
   int maxL = MathMin(MAXL, InpMaxLevels);
   if(G.er < InpERRange) return maxL;
   bool withTrend = (dir == G.trend);
   if(G.er < InpERTrend) return withTrend ? maxL : MathMin(maxL, InpCounterLevels);
   return withTrend ? MathMin(maxL, InpTrendLevels) : 0;
}

bool InSession()
{
   if(!InpUseSession) return true;
   MqlDateTime t; TimeToStruct(TimeCurrent(), t);
   if(InpStartHour <= InpEndHour) return t.hour >= InpStartHour && t.hour < InpEndHour;
   return t.hour >= InpStartHour || t.hour < InpEndHour;
}

bool OpenLevel(Basket &b, int k)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double lot = b.lots[k], price = b.dir > 0 ? ask : bid;
   double margin;
   if(OrderCalcMargin(b.dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, lot, price, margin) &&
      margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.6) { Dbg("margin too high for level"); return false; }
   double sl = NormalizeDouble(b.stopPx, dg);
   bool valid = b.dir > 0 ? (sl < price) : (sl > price);
   if(!valid) { Dbg("stop on wrong side of price, level skipped"); return false; }
   bool ok = b.dir > 0 ? trade.Buy(lot, _Symbol, price, sl, 0, Tag(b.dir))
                       : trade.Sell(lot, _Symbol, price, sl, 0, Tag(b.dir));
   if(InpDebug) PrintFormat("%s L%d lot=%.2f px=%.5f stop=%.5f ok=%d", Tag(b.dir), k, lot, price, sl, ok);
   if(ok) { b.filled[k] = true; b.nFilled++; g_dirty = true; }
   return ok;
}

void ResetBasket(Basket &b, int dir)
{
   b.active = false; b.dir = dir; b.sig = InpInvertMode ? -dir : dir;
   b.nFilled = 0; b.armed = false; b.peak = 0; b.N = 0;
   for(int i = 0; i <= MAXL; i++) { b.filled[i] = false; b.lots[i] = 0; }
   g_dirty = true;
}

//+------------------------------------------------------------------+
void OpenTrendTrade(int dir)
{
   if(!G.valid) return;
   double vpu = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double slDist = G.atr * InpFlipSL_ATR;
   double risk = AccountInfoDouble(ACCOUNT_EQUITY) * InpFlipRiskPct / 100.0;
   double stepL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lot = MathFloor(risk / (slDist * vpu) / stepL) * stepL;
   if(lot < minL) { Dbg("trend trade lot below min"); return; }
   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double price = dir > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = NormalizeDouble(price - dir * slDist, dg);
   if(dir > 0) trade.Buy(lot, _Symbol, price, sl, 0, "AGT_T");
   else        trade.Sell(lot, _Symbol, price, sl, 0, "AGT_T");
   if(InpDebug) PrintFormat("TREND ESCAPE trade dir=%d lot=%.2f", dir, lot);
}

void ManageTrendTrade()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_COMMENT) != "AGT_T") continue;
      int dir = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
      double sl = PositionGetDouble(POSITION_SL);
      double px = dir > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(!G.valid) return;
      int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double nsl = NormalizeDouble(px - dir * G.atr * InpFlipTrailATR, dg);
      if((dir > 0 && nsl > sl) || (dir < 0 && (sl == 0 || nsl < sl)))
         trade.PositionModify(t, nsl, 0);
   }
}

bool HasTrendTrade()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic &&
         PositionGetString(POSITION_COMMENT) == "AGT_T") return true;
   }
   return false;
}

void HandleEscape(Basket &b)
{
   if(InpDebug) PrintFormat("STOP %s basket hit at %.5f", Tag(b.dir), b.stopPx);
   CloseTag(Tag(b.dir));
   int d = b.dir;
   datetime cd = TimeCurrent() + InpCooldownMin * 60;
   ResetBasket(b, d);
   b.cooldownUntil = cd;
   if(InpFlipOnEscape && !InpInvertMode && !HasTrendTrade()) OpenTrendTrade(-d);
}

//+------------------------------------------------------------------+
void ManageBasket(Basket &b)
{
   double vol, avg; datetime oldest;
   int cnt = SideStats(b.dir, vol, avg, oldest);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double px = b.dir > 0 ? bid : ask;

   if(!b.active) return;
   bool beyond = b.dir > 0 ? (bid <= b.stopPx) : (ask >= b.stopPx);
   if(beyond) { HandleEscape(b); return; }
   if(cnt == 0)
   {
      if(b.nFilled > 0) { int d = b.dir; datetime cd = b.cooldownUntil; ResetBasket(b, d); b.cooldownUntil = cd; }
      return;
   }

   if(InpMaxBasketHours > 0 && TimeCurrent() - oldest > InpMaxBasketHours * 3600)
   {
      if(InpDebug) Print("Basket time stop ", Tag(b.dir));
      CloseTag(Tag(b.dir));
      int d = b.dir; ResetBasket(b, d);
      return;
   }

   double target = avg + b.dir * InpTPStep * b.step;
   bool reached = b.dir > 0 ? px >= target : px <= target;
   if(reached)
   {
      if(InpTrailStep <= 0) { CloseTag(Tag(b.dir)); int d = b.dir; ResetBasket(b, d); return; }
      b.armed = true;
   }
   if(b.armed)
   {
      if(b.peak == 0 || (b.dir > 0 && px > b.peak) || (b.dir < 0 && px < b.peak)) b.peak = px;
      double back = InpTrailStep * b.step;
      bool trailHit = b.dir > 0 ? px <= b.peak - back : px >= b.peak + back;
      if(trailHit)
      {
         if(InpDebug) PrintFormat("%s basket exit, avg=%.5f px=%.5f", Tag(b.dir), avg, px);
         CloseTag(Tag(b.dir));
         int d = b.dir; ResetBasket(b, d);
         return;
      }
   }

   if(b.nFilled < b.N)
   {
      int k = 0;
      for(int i = 1; i <= b.N; i++) if(!b.filled[i]) { k = i; break; }
      if(k > 0)
      {
         double lvl = b.anchor - b.sig * k * b.step;
         double entryPx = b.dir > 0 ? ask : bid;
         bool hit = b.sig > 0 ? entryPx <= lvl : entryPx >= lvl;
         bool spreadOk = InpMaxSpread <= 0 || SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) <= InpMaxSpread;
         if(hit && spreadOk) OpenLevel(b, k);
      }
   }
}

// sig = grid signal side (+1 price below anchor, -1 price above anchor)
void TryNewBasket(int sig)
{
   int dir = InpInvertMode ? -sig : sig;
   Basket b0 = gB[Idx(dir)];
   if(b0.active || !G.valid || !InSession()) return;
   if(TimeCurrent() < b0.cooldownUntil) return;
   if(InpMaxSpread > 0 && SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpread) return;
   if(!g_hedging && gB[Idx(-dir)].active) return;

   int N = LevelsAllowed(dir);
   if(N <= 0) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entryPx = dir > 0 ? ask : bid;
   double anchor = G.hma, step = G.step;
   double lvl1 = anchor - sig * step, lvl2 = anchor - sig * 2 * step;
   bool trig;
   if(sig > 0) trig = entryPx <= lvl1 && entryPx > lvl2;
   else        trig = entryPx >= lvl1 && entryPx < lvl2;
   if(!trig) return;

   Basket nb;
   ResetBasket(nb, dir);
   nb.anchor = anchor; nb.step = step; nb.N = N;
   nb.cooldownUntil = b0.cooldownUntil;
   double budget = AccountInfoDouble(ACCOUNT_EQUITY) * InpBasketRiskPct / 100.0;
   if(!PlanBasket(nb, budget)) { Dbg("risk budget too small for min lot"); return; }
   nb.active = true;
   nb.opened = TimeCurrent();
   gB[Idx(dir)] = nb;
   if(InpDebug) PrintFormat("NEW %s basket (signal %d, invert=%d) anchor=%.5f step=%.5f N=%d stop=%.5f ER=%.2f",
                            Tag(dir), sig, InpInvertMode, nb.anchor, nb.step, nb.N, nb.stopPx, G.er);
   if(!OpenLevel(gB[Idx(dir)], 1)) ResetBasket(gB[Idx(dir)], dir);
}

//+------------------------------------------------------------------+
bool KillSwitch()
{
   datetime d0 = iTime(_Symbol, PERIOD_D1, 0);
   if(d0 != g_lastD1) { g_lastD1 = d0; g_dayStartEq = AccountInfoDouble(ACCOUNT_EQUITY); }
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > g_peakEq) g_peakEq = eq;
   if(g_haltDay == d0) { g_status = "HALTED today"; return true; }
   bool dd  = g_peakEq > 0 && (g_peakEq - eq) / g_peakEq * 100.0 >= InpMaxDrawdownPct;
   bool day = g_dayStartEq > 0 && (g_dayStartEq - eq) / g_dayStartEq * 100.0 >= InpMaxDailyLossPct;
   if(dd || day)
   {
      Print("KILL SWITCH: ", dd ? "max drawdown" : "daily loss", " - closing all");
      CloseTag("");
      ResetBasket(gB[0], 1); ResetBasket(gB[1], -1);
      g_haltDay = d0;
      g_status = "HALTED";
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void HLine(string n, double p, color c, ENUM_LINE_STYLE st, int w)
{
   ObjectCreate(0, n, OBJ_HLINE, 0, 0, p);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetInteger(0, n, OBJPROP_STYLE, st);
   ObjectSetInteger(0, n, OBJPROP_WIDTH, w);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
}

void DrawGrid()
{
   if(!g_draw || !InpDrawGrid) return;
   ObjectsDeleteAll(0, PFX);
   if(G.valid) HLine(PFX + "anchor", G.hma, clrAqua, STYLE_DOT, 1);
   for(int s = 0; s < 2; s++)
   {
      Basket b = gB[s];
      if(!b.active) continue;
      for(int k = 1; k <= b.N; k++)
      {
         double lv = b.anchor - b.sig * k * b.step;
         color c = b.filled[k] ? (b.dir > 0 ? InpBullCandleColor : InpBearCandleColor) : clrDimGray;
         HLine(PFX + (b.dir > 0 ? "B" : "S") + IntegerToString(k), lv, c, b.filled[k] ? STYLE_SOLID : STYLE_DASH, 1);
      }
      HLine(PFX + (b.dir > 0 ? "Bstop" : "Sstop"), b.stopPx, clrRed, STYLE_SOLID, 2);
   }
   ChartRedraw(0);
}

void ApplyTheme()
{
   long id = 0;
   ChartSetInteger(id, CHART_MODE, CHART_CANDLES);
   ChartSetInteger(id, CHART_COLOR_BACKGROUND,  clrBlack);
   ChartSetInteger(id, CHART_COLOR_FOREGROUND,  clrSilver);
   ChartSetInteger(id, CHART_COLOR_GRID,        C'30,30,30');
   ChartSetInteger(id, CHART_SHOW_GRID,         false);
   ChartSetInteger(id, CHART_COLOR_CHART_UP,    InpBullCandleColor);
   ChartSetInteger(id, CHART_COLOR_CHART_DOWN,  InpBearCandleColor);
   ChartSetInteger(id, CHART_COLOR_CHART_LINE,  clrSilver);
   ChartSetInteger(id, CHART_COLOR_CANDLE_BULL, InpBullCandleColor);
   ChartSetInteger(id, CHART_COLOR_CANDLE_BEAR, InpBearCandleColor);
   ChartSetInteger(id, CHART_COLOR_VOLUME,      clrDimGray);
   ChartSetInteger(id, CHART_COLOR_BID,         clrDimGray);
   ChartSetInteger(id, CHART_COLOR_ASK,         clrDimGray);
   ChartSetInteger(id, CHART_COLOR_LAST,        clrDimGray);
   ChartSetInteger(id, CHART_COLOR_STOP_LEVEL,  InpBearCandleColor);
   ChartRedraw(id);
}

void Panel()
{
   if(!InpShowPanel || !g_draw) return;
   string s = "Auto Grid Traders" + (InpInvertMode ? "  [INVERTED]" : "") + "\n";
   if(G.valid)
   {
      string reg = G.er < InpERRange ? "RANGE" : (G.er < InpERTrend ? "MIXED" : "TREND");
      s += StringFormat("Regime %s | ER %.2f | Trend %s | Step %.1f pts\n", reg, G.er, G.trend > 0 ? "UP" : "DOWN", G.step / SymbolInfoDouble(_Symbol, SYMBOL_POINT));
      for(int i = 0; i < 2; i++)
      {
         Basket b = gB[i];
         s += StringFormat("%s: %s\n", i == 0 ? "BUY " : "SELL", b.active ? StringFormat("levels %d/%d", b.nFilled, b.N) : "idle");
      }
   }
   else s += "Waiting for data...\n";
   s += g_status;
   Comment(s);
}

//+------------------------------------------------------------------+
int OnInit()
{
   if(InpMaxLevels < 1 || InpHmaPeriod < 4) return INIT_PARAMETERS_INCORRECT;
   g_hedging = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
   if(!g_hedging) Print("WARNING: non-hedging account - only one basket side will run at a time.");
   g_draw = !(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE));
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);
   ResetBasket(gB[0], 1); ResetBasket(gB[1], -1);
   gB[0].cooldownUntil = 0; gB[1].cooldownUntil = 0;
   g_peakEq = g_dayStartEq = AccountInfoDouble(ACCOUNT_EQUITY);
   g_lastD1 = iTime(_Symbol, PERIOD_D1, 0);
   Print("Auto Grid Traders started. Invert mode: ", InpInvertMode ? "ON" : "OFF");
   if(PositionsTotal() > 0)
      Print("NOTE: existing positions with this magic are not re-adopted after a restart; manage them manually.");
   if(InpApplyBlackTheme && g_draw) ApplyTheme();
   CalcGrid();
   Panel();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, PFX);
   Comment("");
   ChartRedraw(0);
}

void OnTick()
{
   datetime m1 = iTime(_Symbol, PERIOD_M1, 0);
   if(m1 != g_lastM1)
   {
      g_lastM1 = m1;
      CalcGrid();
      g_dirty = true;
   }
   if(KillSwitch()) { Panel(); return; }
   g_status = "Running";
   if(!G.valid) return;

   ManageBasket(gB[0]);
   ManageBasket(gB[1]);
   ManageTrendTrade();
   TryNewBasket(1);
   TryNewBasket(-1);

   if(g_dirty) { DrawGrid(); Panel(); g_dirty = false; }
}
//+------------------------------------------------------------------+
