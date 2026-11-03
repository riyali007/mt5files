//+------------------------------------------------------------------+
//| HMA_Regime_Engine.mq5  v3.02 (multi-partials)                    |
//| Adaptive HTF Hull-MA regime engine. No indicator handles used.   |
//+------------------------------------------------------------------+
#property copyright "Riy Ali"
#property version   "3.02"
#property strict

#include <Trade/Trade.mqh>

input group "HTF Hull MA"
input ENUM_TIMEFRAMES    InpHTF         = PERIOD_H1;
input int                InpFastPeriod  = 21;
input int                InpSlowPeriod  = 55;
input ENUM_APPLIED_PRICE InpPrice       = PRICE_CLOSE;
input int                InpATRPeriod   = 14;
input int                InpERLen       = 20;

input group "Regime scoring (0-100)"
input int    InpMinScore       = 55;
input int    InpMinScoreFlip   = 40;
input double InpMinATRRatio    = 0.50;
input double InpMaxATRRatio    = 2.50;

input group "Entry modes"
input bool   InpUsePullback    = true;
input bool   InpUseFlip        = true;
input double InpTouchATR       = 0.20;

input group "Stops"
input double InpMinSL_ATR      = 0.8;
input double InpMaxSL_ATR      = 2.5;
input double InpFlipSL_ATR     = 1.5;
input double InpTP_R           = 6.0;     // final TP for the runner (0 = none)

input group "Partials (% of INITIAL volume)"
input bool   InpUsePartials    = true;
input double InpP1_R           = 1.0;     // partial 1 -> SL to breakeven
input double InpP1_Pct         = 30.0;
input double InpP2_R           = 2.0;     // partial 2 -> SL locks profit
input double InpP2_Pct         = 30.0;
input double InpLockR          = 0.8;     // SL after partial 2 = entry + LockR x R
input double InpP3_R           = 3.0;     // partial 3 -> start tight trail
input double InpP3_Pct         = 20.0;    // remaining ~20% is the runner
input double InpTrailATR       = 2.0;     // runner trail after partial 2 (x HTF ATR)
input double InpTrailATRTight  = 1.2;     // runner trail after partial 3

input group "Risk"
input double InpBaseRiskPct    = 0.5;
input double InpMaxDailyLossPct= 2.0;
input double InpMaxDrawdownPct = 12.0;
input int    InpMaxTradesDay   = 3;
input int    InpLossStreakHalve= 2;
input int    InpLossStreakStop = 4;
input int    InpCooldownBars   = 6;
input int    InpMaxSpread      = 0;
input long   InpMagic          = 20261003;
input bool   InpAllowMinLot    = true;
input bool   InpDebug          = true;

input group "Session (server time)"
input bool   InpUseSession     = false;
input int    InpStartHour      = 7;
input int    InpEndHour        = 20;

input group "Chart theme"
input bool   InpApplyBlackTheme   = true;
input color  InpBullCandleColor   = C'38,166,154';   // teal
input color  InpBearCandleColor   = C'239,83,80';    // red
input color  InpFastUpColor       = clrAqua;
input color  InpFastDnColor       = clrOrange;
input color  InpSlowColor         = clrGray;
input int    InpDrawBars          = 300;
input bool   InpShowPanel         = true;

#define PFX "HRE_"

struct State
{
   bool   valid;
   int    dir;
   bool   flip;
   double atr;
   double er;
   double slopeN;
   double atrRatio;
   double fastLive;
   int    score;
   int    slowDir;
};

struct Track
{
   ulong  ticket;
   double R;        // initial risk distance
   double vol0;     // initial volume
   int    stage;    // 0 none, 1 P1 done, 2 P2 done, 3 P3 done
};

CTrade   trade;
State    S;
Track    g_tr[];
datetime g_lastHtf = 0, g_lastChart = 0;
double   g_peakEquity = 0;
string   g_reason = "";
int      g_dbgCount = 0;

void Dbg(string m)
{
   if(!InpDebug) return;
   if(g_dbgCount++ % 200 == 0) Print("DBG: ", m, " (sampled)");
}

//+------------------------------------------------------------------+
double PriceOf(const MqlRates &r)
{
   switch(InpPrice)
   {
      case PRICE_OPEN:     return r.open;
      case PRICE_HIGH:     return r.high;
      case PRICE_LOW:      return r.low;
      case PRICE_MEDIAN:   return (r.high + r.low) / 2.0;
      case PRICE_TYPICAL:  return (r.high + r.low + r.close) / 3.0;
      case PRICE_WEIGHTED: return (r.high + r.low + 2.0 * r.close) / 4.0;
   }
   return r.close;
}

double WMAat(const double &a[], int k, int p)
{
   double s = 0, w = 0;
   for(int j = 0; j < p; j++) { double wt = p - j; s += a[k - j] * wt; w += wt; }
   return s / w;
}

void CalcHMA(const double &px[], int n, int period, double &hma[], int &first)
{
   int half = MathMax(1, (int)MathFloor(period / 2.0));
   int sq   = MathMax(1, (int)MathFloor(MathSqrt(period)));
   double raw[];
   ArrayResize(raw, n);
   ArrayResize(hma, n);
   for(int i = 0; i < n; i++) { raw[i] = EMPTY_VALUE; hma[i] = EMPTY_VALUE; }
   for(int k = period - 1; k < n; k++)
      raw[k] = 2.0 * WMAat(px, k, half) - WMAat(px, k, period);
   first = period - 1 + sq - 1;
   for(int k = first; k < n; k++) hma[k] = WMAat(raw, k, sq);
}

int LoadHTF(MqlRates &r[], double &fast[], double &slow[], int &f1, int &f2)
{
   int need = InpDrawBars + InpSlowPeriod * 2 + 150;
   int n = CopyRates(_Symbol, InpHTF, 0, need, r);
   if(n < InpSlowPeriod * 2 + 120) return 0;
   double px[];
   ArrayResize(px, n);
   for(int i = 0; i < n; i++) px[i] = PriceOf(r[i]);
   CalcHMA(px, n, InpFastPeriod, fast, f1);
   CalcHMA(px, n, InpSlowPeriod, slow, f2);
   return n;
}

double TR(const MqlRates &r[], int i)
{
   return MathMax(r[i].high - r[i].low,
          MathMax(MathAbs(r[i].high - r[i-1].close), MathAbs(r[i].low - r[i-1].close)));
}

//+------------------------------------------------------------------+
void Seg(string name, datetime t1, double p1, datetime t2, double p2, color clr, int w)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, w);
   }
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble (0, name, OBJPROP_PRICE, 0, p1);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble (0, name, OBJPROP_PRICE, 1, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

void DrawLines(const MqlRates &r[], const double &fast[], const double &slow[], int n, int f1, int f2)
{
   static datetime lastFull = 0;
   if(r[n-1].time != lastFull) { ObjectsDeleteAll(0, PFX); lastFull = r[n-1].time; }
   int st1 = MathMax(f1 + 1, n - InpDrawBars);
   for(int k = st1; k < n; k++)
   {
      if(fast[k] == EMPTY_VALUE || fast[k-1] == EMPTY_VALUE) continue;
      color c = fast[k] >= fast[k-1] ? InpFastUpColor : InpFastDnColor;
      Seg(PFX + "F" + IntegerToString((long)r[k].time), r[k-1].time, fast[k-1], r[k].time, fast[k], c, 2);
   }
   int st2 = MathMax(f2 + 1, n - InpDrawBars);
   for(int k = st2; k < n; k++)
   {
      if(slow[k] == EMPTY_VALUE || slow[k-1] == EMPTY_VALUE) continue;
      Seg(PFX + "S" + IntegerToString((long)r[k].time), r[k-1].time, slow[k-1], r[k].time, slow[k], InpSlowColor, 1);
   }
   color lc = fast[n-1] >= fast[n-2] ? InpFastUpColor : InpFastDnColor;
   Seg(PFX + "Flive", r[n-1].time, fast[n-1], TimeCurrent() + PeriodSeconds(_Period), fast[n-1], lc, 2);
   Seg(PFX + "Slive", r[n-1].time, slow[n-1], TimeCurrent() + PeriodSeconds(_Period), slow[n-1], InpSlowColor, 1);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
void RefreshState(bool redraw)
{
   S.valid = false;
   MqlRates r[];
   double fast[], slow[];
   int f1, f2;
   int n = LoadHTF(r, fast, slow, f1, f2);
   if(n == 0) { Dbg("not enough HTF history"); return; }

   int c = n - 2;
   if(fast[c] == EMPTY_VALUE || fast[c-1] == EMPTY_VALUE || fast[c-2] == EMPTY_VALUE ||
      slow[c] == EMPTY_VALUE || slow[c-1] == EMPTY_VALUE) return;

   double s = 0;
   for(int i = c; i > c - InpATRPeriod; i--) s += TR(r, i);
   S.atr = s / InpATRPeriod;
   double s2 = 0;
   for(int i = c; i > c - 100; i--) s2 += TR(r, i);
   double avgAtr = s2 / 100.0;
   S.atrRatio = avgAtr > 0 ? S.atr / avgAtr : 1.0;
   if(S.atr <= 0) return;

   S.slopeN = (fast[c] - fast[c-1]) / S.atr;
   S.dir    = fast[c] > fast[c-1] ? 1 : -1;
   S.flip   = (fast[c] > fast[c-1]) != (fast[c-1] > fast[c-2]);
   S.slowDir= slow[c] > slow[c-1] ? 1 : -1;
   S.fastLive = fast[n-1];

   double net = MathAbs(r[c].close - r[c - InpERLen].close), path = 0;
   for(int i = c; i > c - InpERLen; i--) path += MathAbs(r[i].close - r[i-1].close);
   S.er = path > 0 ? net / path : 0;

   double sc = 0;
   sc += MathMin(MathAbs(S.slopeN) / 0.35, 1.0) * 30.0;
   sc += MathMin(S.er / 0.40, 1.0) * 30.0;
   sc += (S.slowDir == S.dir) ? 25.0 : 0.0;
   bool side = (S.dir > 0 && r[c].close > fast[c]) || (S.dir < 0 && r[c].close < fast[c]);
   sc += side ? 15.0 : 0.0;
   S.score = (int)MathRound(sc);
   S.valid = true;

   if(redraw) DrawLines(r, fast, slow, n, f1, f2);
}

//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
void DayStats(double &pnl, int &entries, int &streak, datetime &lastLossTime)
{
   pnl = 0; entries = 0; streak = 0; lastLossTime = 0;
   datetime d0 = iTime(_Symbol, PERIOD_D1, 0);
   if(!HistorySelect(TimeCurrent() - 30 * 86400, TimeCurrent() + 60)) return;
   int total = HistoryDealsTotal();
   bool streakOpen = true;
   for(int i = total - 1; i >= 0; i--)
   {
      ulong t = HistoryDealGetTicket(i);
      if(t == 0) continue;
      if(HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagic) continue;
      if(HistoryDealGetString(t, DEAL_SYMBOL) != _Symbol) continue;
      long entry = HistoryDealGetInteger(t, DEAL_ENTRY);
      datetime tm = (datetime)HistoryDealGetInteger(t, DEAL_TIME);
      double p = HistoryDealGetDouble(t, DEAL_PROFIT) + HistoryDealGetDouble(t, DEAL_COMMISSION)
               + HistoryDealGetDouble(t, DEAL_SWAP);
      if(entry == DEAL_ENTRY_IN && tm >= d0) entries++;
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
      {
         if(tm >= d0) pnl += p;
         if(streakOpen)
         {
            if(p < 0) { streak++; if(lastLossTime == 0) lastLossTime = tm; }
            else if(p > 0) streakOpen = false;
         }
      }
   }
}

double FloatingPnL()
{
   double s = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      s += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return s;
}

bool HasPosition(ulong &ticket)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      ticket = t;
      return true;
   }
   return false;
}

double RiskGate()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY), bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(eq > g_peakEquity) g_peakEquity = eq;
   if(g_peakEquity > 0 && (g_peakEquity - eq) / g_peakEquity * 100.0 >= InpMaxDrawdownPct)
   { g_reason = "Max drawdown halt"; return 0; }

   double pnl; int entries, streak; datetime lastLoss;
   DayStats(pnl, entries, streak, lastLoss);
   if((pnl + FloatingPnL()) <= -bal * InpMaxDailyLossPct / 100.0) { g_reason = "Daily loss limit"; return 0; }
   if(entries >= InpMaxTradesDay)                                  { g_reason = "Max trades today"; return 0; }
   if(streak >= InpLossStreakStop && lastLoss >= iTime(_Symbol, PERIOD_D1, 0))
                                                                   { g_reason = "Loss streak stop"; return 0; }
   if(lastLoss > 0 && InpCooldownBars > 0 &&
      TimeCurrent() < lastLoss + (datetime)(InpCooldownBars * PeriodSeconds(_Period)))
                                                                   { g_reason = "Cooldown"; return 0; }
   g_reason = "OK";
   return streak >= InpLossStreakHalve ? 0.5 : 1.0;
}

bool InSession()
{
   if(!InpUseSession) return true;
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   if(InpStartHour <= InpEndHour) return t.hour >= InpStartHour && t.hour < InpEndHour;
   return t.hour >= InpStartHour || t.hour < InpEndHour;
}

//+------------------------------------------------------------------+
double CalcLots(double slDist, double riskPct)
{
   double risk    = AccountInfoDouble(ACCOUNT_BALANCE) * riskPct / 100.0;
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(slDist <= 0 || tickVal <= 0 || tickSz <= 0) { Dbg("bad tick value/size"); return 0; }
   double lots = MathFloor(risk / (slDist / tickSz * tickVal) / step) * step;
   if(lots < minLot)
   {
      if(!InpAllowMinLot) { if(InpDebug) Print("SKIP: risk-sized lot below min lot: ", DoubleToString(lots, 4)); return 0; }
      lots = minLot;
   }
   return MathMin(maxLot, lots);
}

bool Open(int dir, double slDist, double mult, string tag)
{
   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double riskPct = InpBaseRiskPct * mult * MathMax(0.5, MathMin(1.25, S.score / 80.0));
   double lots = CalcLots(slDist, riskPct);
   if(lots <= 0) return false;
   double price = dir > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = NormalizeDouble(price - dir * slDist, dg);
   double tp = InpTP_R > 0 ? NormalizeDouble(price + dir * slDist * InpTP_R, dg) : 0;
   double margin;
   if(OrderCalcMargin(dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, lots, price, margin) &&
      margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.5)
   { if(InpDebug) Print("SKIP: margin too high for ", DoubleToString(lots, 2), " lots"); return false; }
   if(InpDebug) PrintFormat("OPEN %s dir=%d lots=%.2f slDist=%.5f score=%d", tag, dir, lots, slDist, S.score);
   bool ok = dir > 0 ? trade.Buy(lots, _Symbol, price, sl, tp, tag)
                     : trade.Sell(lots, _Symbol, price, sl, tp, tag);
   if(!ok && InpDebug) Print("Order failed: ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   return ok;
}

//+------------------------------------------------------------------+
//| Partials management                                              |
//+------------------------------------------------------------------+
int FindTrack(ulong ticket)
{
   for(int i = ArraySize(g_tr) - 1; i >= 0; i--)
      if(g_tr[i].ticket == ticket) return i;
   return -1;
}

void PruneTracks()
{
   for(int i = ArraySize(g_tr) - 1; i >= 0; i--)
      if(!PositionSelectByTicket(g_tr[i].ticket))
      {
         for(int j = i; j < ArraySize(g_tr) - 1; j++) g_tr[j] = g_tr[j+1];
         ArrayResize(g_tr, ArraySize(g_tr) - 1);
      }
}

bool PartialClose(ulong ticket, double vol0, double pct)
{
   if(!PositionSelectByTicket(ticket)) return false;
   double cur  = PositionGetDouble(POSITION_VOLUME);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double part = MathFloor(vol0 * pct / 100.0 / step) * step;
   if(part < minL || cur - part < minL) return false;
   bool ok = trade.PositionClosePartial(ticket, part);
   if(InpDebug) PrintFormat("PARTIAL %.2f lots (%.0f%%) ok=%d", part, pct, ok);
   return ok;
}

void MoveSL(ulong ticket, int dir, double newSL, double tp)
{
   if(!PositionSelectByTicket(ticket)) return;
   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double sl = PositionGetDouble(POSITION_SL);
   newSL = NormalizeDouble(newSL, dg);
   if((dir > 0 && (sl == 0 || newSL > sl)) || (dir < 0 && (sl == 0 || newSL < sl)))
      trade.PositionModify(ticket, newSL, tp);
}

void ManagePosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return;
   int    dir  = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl   = PositionGetDouble(POSITION_SL);
   double tp   = PositionGetDouble(POSITION_TP);
   double px   = dir > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double pt   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   int idx = FindTrack(ticket);
   if(idx < 0)
   {
      Track t;
      t.ticket = ticket;
      t.R      = sl > 0 ? MathAbs(open - sl) : 0;
      t.vol0   = PositionGetDouble(POSITION_VOLUME);
      bool beAlready = (dir > 0 && sl >= open) || (dir < 0 && sl > 0 && sl <= open);
      t.stage  = beAlready ? 3 : 0;      // restarted mid-trade: just trail
      int n = ArraySize(g_tr);
      ArrayResize(g_tr, n + 1);
      g_tr[n] = t;
      idx = n;
   }
   if(!InpUsePartials) g_tr[idx].stage = MathMax(g_tr[idx].stage, 3);

   double R = g_tr[idx].R;
   double profitR = R > 0 ? (px - open) * dir / R : 0;

   if(g_tr[idx].stage == 0 && profitR >= InpP1_R)
   {
      PartialClose(ticket, g_tr[idx].vol0, InpP1_Pct);
      MoveSL(ticket, dir, open + dir * pt * 2, tp);                 // breakeven
      g_tr[idx].stage = 1;
      return;
   }
   if(g_tr[idx].stage == 1 && profitR >= InpP2_R)
   {
      PartialClose(ticket, g_tr[idx].vol0, InpP2_Pct);
      MoveSL(ticket, dir, open + dir * R * InpLockR, tp);           // lock profit
      g_tr[idx].stage = 2;
      return;
   }
   if(g_tr[idx].stage == 2 && profitR >= InpP3_R)
   {
      PartialClose(ticket, g_tr[idx].vol0, InpP3_Pct);
      g_tr[idx].stage = 3;
      return;
   }

   if(S.valid && g_tr[idx].stage >= 2)
   {
      double mult = g_tr[idx].stage >= 3 ? InpTrailATRTight : InpTrailATR;
      if(mult > 0) MoveSL(ticket, dir, px - dir * S.atr * mult, tp);
   }
}

//+------------------------------------------------------------------+
void TryEntries(bool newHtf, bool newChart, double mult)
{
   if(!S.valid)     { Dbg("no valid HTF data yet"); return; }
   if(!InSession()) { Dbg("outside session"); return; }
   if(InpMaxSpread > 0 && SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpread)
                    { Dbg("spread too high"); return; }
   if(S.atrRatio < InpMinATRRatio || S.atrRatio > InpMaxATRRatio)
                    { Dbg("ATR ratio out of range " + DoubleToString(S.atrRatio, 2)); return; }

   if(InpUseFlip && newHtf && S.flip && S.slowDir == S.dir)
   {
      if(S.score >= InpMinScoreFlip)
      {
         double sl = MathMax(InpMinSL_ATR, MathMin(InpMaxSL_ATR, InpFlipSL_ATR)) * S.atr;
         if(Open(S.dir, sl, mult, "HRE flip")) return;
      }
      else Dbg("flip score too low: " + IntegerToString(S.score));
   }

   if(InpUsePullback && newChart && S.slowDir == S.dir)
   {
      if(S.score < InpMinScore) { Dbg("score " + IntegerToString(S.score) + " < min"); return; }
      MqlRates b[];
      if(CopyRates(_Symbol, _Period, 1, 1, b) != 1) return;
      double lvl = S.fastLive, tol = InpTouchATR * S.atr;
      if(S.dir > 0 && b[0].low <= lvl + tol && b[0].close > lvl && b[0].close > b[0].open)
      {
         double sl = MathMax(InpMinSL_ATR * S.atr, MathMin(InpMaxSL_ATR * S.atr,
                     SymbolInfoDouble(_Symbol, SYMBOL_ASK) - (MathMin(b[0].low, lvl) - 0.3 * S.atr)));
         Open(1, sl, mult, "HRE pullback");
      }
      else if(S.dir < 0 && b[0].high >= lvl - tol && b[0].close < lvl && b[0].close < b[0].open)
      {
         double sl = MathMax(InpMinSL_ATR * S.atr, MathMin(InpMaxSL_ATR * S.atr,
                     (MathMax(b[0].high, lvl) + 0.3 * S.atr) - SymbolInfoDouble(_Symbol, SYMBOL_BID)));
         Open(-1, sl, mult, "HRE pullback");
      }
   }
}

//+------------------------------------------------------------------+
void Panel()
{
   if(!InpShowPanel) return;
   string s = "HMA Regime Engine\n";
   if(S.valid)
      s += StringFormat("HTF %s | Dir %s | Slow %s\nScore %d | ER %.2f | Slope %.2f ATR | Vol %.2fx\nGate: %s",
            EnumToString(InpHTF), S.dir > 0 ? "UP" : "DOWN", S.slowDir > 0 ? "UP" : "DOWN",
            S.score, S.er, S.slopeN, S.atrRatio, g_reason);
   else s += "Waiting for data...";
   Comment(s);
}

//+------------------------------------------------------------------+
int OnInit()
{
   if(InpFastPeriod < 4 || InpSlowPeriod <= InpFastPeriod) return INIT_PARAMETERS_INCORRECT;
   if(InpP1_Pct + InpP2_Pct + InpP3_Pct >= 100.0) return INIT_PARAMETERS_INCORRECT;
   if(PeriodSeconds(InpHTF) <= PeriodSeconds(_Period))
      Print("WARNING: HTF should be higher than the chart/tester timeframe.");
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);
   g_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(InpDebug)
      PrintFormat("Init: minLot=%.2f tickVal=%.4f balance=%.2f",
                  SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN),
                  SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE),
                  AccountInfoDouble(ACCOUNT_BALANCE));
   if(InpApplyBlackTheme) ApplyTheme();
   RefreshState(true);
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
   datetime htf = iTime(_Symbol, InpHTF, 0), cb = iTime(_Symbol, _Period, 0);
   if(htf == 0 || cb == 0) return;
   bool newHtf = htf != g_lastHtf, newChart = cb != g_lastChart;

   if(newHtf || newChart) RefreshState(true);
   ulong tk;
   if(HasPosition(tk)) ManagePosition(tk);
   else if(ArraySize(g_tr) > 0) ArrayResize(g_tr, 0);

   if(newHtf || newChart)
   {
      if(!HasPosition(tk))
      {
         double mult = RiskGate();
         if(mult > 0) TryEntries(newHtf, newChart, mult);
         else Dbg("gate: " + g_reason);
      }
      g_lastHtf = htf;
      g_lastChart = cb;
      Panel();
   }
}
//+------------------------------------------------------------------+
