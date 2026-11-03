//+------------------------------------------------------------------+
//| CalibratedLineEA v0.20 - minimal prototype                        |
//| HMA inflection-line rejection entries + break-even + ONE partial.  |
//| At start and once per day the EA replays the last InpCalBars bars,|
//| simulates every signal (on M1 data, with the same BE/partial       |
//| rules) for a small grid of settings, validates on the newest      |
//| InpValBars bars and trades only with the best validated setting.  |
//| BE and the partial are managed PER TICK. Every closed trade is    |
//| classified (SL / BE no partial / BE with partial / TP ...).       |
//+------------------------------------------------------------------+
#property copyright "Calibrated line EA prototype"
#property version   "0.20"
#include <Trade\Trade.mqh>

input group "Trade"
input double InpLot            = 0.10;      // Lot size
input long   InpMagic          = 20261016;  // Magic number
input int    InpMaxOpen        = 2;         // Max open positions
input int    InpMaxSpread      = 0;         // Max spread pts (0 = off)

input group "Lines (same logic as the main EA)"
input int    InpMaPeriod       = 34;        // HMA period (close)
input int    InpPivotCandles   = 5;         // Pivot candles
input int    InpLineOffset     = 350;       // Line offset pts
input int    InpMinSwing       = 600;       // Min swing pts
input int    InpRejectNear     = 50;        // Rejection: wick may stop this far short (pts)
input int    InpScoreAgeBars   = 50;        // Bars of age for full age points

input group "Base risk (SL/TP scaled by calibration)"
input int    InpBaseSL         = 700;       // Base SL pts
input int    InpBaseTP         = 1400;      // Base TP pts

input group "Break-even and single partial (per tick)"
input int    InpBEPoints       = 200;       // Move SL to break-even after this profit (pts)
input int    InpBEOffset       = 0;         // Break-even offset beyond entry (pts)
input int    InpPartialPoints  = 300;       // Take the partial after this profit (pts)
input double InpPartialPercent = 50.0;      // Partial size, % of the initial volume
input int    InpBETol          = 50;        // Exit within this many pts of BE counts as a BE exit (slippage)

input group "Calibration"
input int    InpCalBars        = 5000;      // Chart bars analysed
input int    InpValBars        = 1000;      // Newest chart bars kept for validation
input int    InpMinTrades      = 30;        // Min simulated trades (train)
input int    InpMinValTrades   = 10;        // Min simulated trades (validation)
input double InpMargin         = 0.05;      // New setting must beat the current one by this (R)
input int    InpMaxHold        = 300;       // Max chart bars a simulated trade is held
input int    InpSimSpread      = 30;        // Spread cost per simulated trade (pts)
input int    InpMaxM1Bars      = 300000;    // Max M1 bars loaded for the simulation
input bool   InpStandAside     = true;      // No valid setting = do not trade
input int    InpLiveBars       = 1000;      // Bars replayed for the live signal

input group "Log"
input bool   InpLog            = true;      // Write CSV logs
input bool   InpCommon         = false;     // Use the common files folder

struct SLine { double price; bool upper; int born; double swing; int touches; bool used; bool alive; };
struct SSig  { int idx; datetime time; int dir; double score; };
struct SPos  { long id; double vol0; double entry; bool isBuy; bool be; bool part; bool partSkipped;
               double mfe; double mae; double score; datetime openT; datetime retry; };

CTrade   g_trade;
datetime g_lastBar = 0;
int      g_calKey  = -1;
bool     g_active  = false;
int      g_cur     = -1;
double   g_minScore = 0.0, g_scale = 1.0;
int      g_side = 0;
SPos     g_ps[];
int      g_cnt[6];
const string G_OC[6] = {"SL_LOSS", "BE_NO_PARTIAL", "BE_WITH_PARTIAL", "TP_NO_PARTIAL", "TP_WITH_PARTIAL", "MANUAL_OTHER"};

const double G_MINSCORE[4] = {0.0, 30.0, 45.0, 60.0};
const double G_SCALE[3]    = {0.7, 1.0, 1.4};

//--------------------------------------------------------------------
void CsvAppend(const string fn, const string header, const string line)
{
   if(!InpLog || MQLInfoInteger(MQL_OPTIMIZATION)) return;
   int flags = FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE;
   if(InpCommon) flags |= FILE_COMMON;
   const int h = FileOpen(fn, flags);
   if(h == INVALID_HANDLE) return;
   if(FileSize(h) == 0) FileWriteString(h, header + "\r\n");
   FileSeek(h, 0, SEEK_END);
   FileWriteString(h, line + "\r\n");
   FileClose(h);
}

//--------------------------------------------------------------------
void Wma(const double &in[], double &out[], const int period, const int n, const int from)
{
   ArrayResize(out, n);
   ArrayInitialize(out, 0.0);
   const double w = period * (period + 1) / 2.0;
   for(int i = from + period - 1; i < n; i++) {
      double s = 0.0;
      for(int k = 0; k < period; k++) s += in[i - k] * (period - k);
      out[i] = s / w;
   }
}

int HmaWarm()
{
   const int sq = (int)MathMax(1, MathRound(MathSqrt((double)InpMaPeriod)));
   return InpMaPeriod - 1 + sq - 1;
}

void Hma(const MqlRates &r[], const int n, double &ma[])
{
   double c[], w1[], w2[], raw[];
   ArrayResize(c, n);
   for(int i = 0; i < n; i++) c[i] = r[i].close;
   const int half = MathMax(1, InpMaPeriod / 2);
   const int sq = (int)MathMax(1, MathRound(MathSqrt((double)InpMaPeriod)));
   Wma(c, w1, half, n, 0);
   Wma(c, w2, InpMaPeriod, n, 0);
   ArrayResize(raw, n);
   ArrayInitialize(raw, 0.0);
   for(int i = InpMaPeriod - 1; i < n; i++) raw[i] = 2.0 * w1[i] - w2[i];
   Wma(raw, ma, sq, n, InpMaPeriod - 1);
}

//--------------------------------------------------------------------
void AddLine(SLine &lines[], const double price, const bool upper, const int born, const double swing)
{
   const int sz = ArraySize(lines);
   ArrayResize(lines, sz + 1);
   lines[sz].price = price; lines[sz].upper = upper; lines[sz].born = born;
   lines[sz].swing = swing; lines[sz].touches = 0; lines[sz].used = false; lines[sz].alive = true;
}

double ScoreSig(const SLine &ln, const MqlRates &b, const int i)
{
   const double ref = MathMax(300, InpMinSwing) * 3.0 * _Point;
   const double sSwing = (ln.swing <= 0.0) ? 0.5 : MathMin(1.0, ln.swing / ref);
   const double sTouch = MathMin(3, ln.touches) / 3.0;
   const double sAge = (InpScoreAgeBars <= 0) ? 1.0 : MathMin(1.0, (double)(i - ln.born) / InpScoreAgeBars);
   const double rng = b.high - b.low;
   double sCandle = 0.0;
   if(rng > 0.0) {
      const double pos = ln.upper ? (b.high - b.close) / rng : (b.close - b.low) / rng;
      sCandle = MathMax(0.0, MathMin(1.0, pos / 0.6));
   }
   return 35.0 * sSwing + 25.0 * sTouch + 15.0 * sAge + 25.0 * sCandle;
}

// Replays closed bars 0..n-1 and returns every rejection signal (ungated, with score).
void Replay(const MqlRates &r[], const int n, const double &ma[], SSig &sigs[])
{
   ArrayResize(sigs, 0);
   SLine lines[];
   ArrayResize(lines, 0);
   const double off = InpLineOffset * _Point;
   const double nr = MathMax(0, InpRejectNear) * _Point;
   const double minSwing = MathMax(0, InpMinSwing) * _Point;
   int pPeak = -1, pTrough = -1, below = 0, above = 0, lastType = 0;
   double lastVal = 0.0;
   const int start = HmaWarm() + 3;

   for(int i = start; i < n; i++) {
      if(ma[i - 1] > ma[i - 2] && ma[i - 1] > ma[i]) { pPeak = i - 1; below = 0; }
      else if(ma[i - 1] < ma[i - 2] && ma[i - 1] < ma[i]) { pTrough = i - 1; above = 0; }
      if(r[i].close < ma[i]) below++; else below = 0;
      if(r[i].close > ma[i]) above++; else above = 0;

      if(pPeak != -1 && below >= InpPivotCandles) {
         if(!(lastType == -1 && minSwing > 0.0 && ma[pPeak] - lastVal < minSwing)) {
            AddLine(lines, ma[pPeak] + off, true, i, (lastType == -1) ? (ma[pPeak] - lastVal) : 0.0);
            lastVal = (lastType == 1) ? MathMax(lastVal, ma[pPeak]) : ma[pPeak];
            lastType = 1;
         }
         pPeak = -1;
      }
      if(pTrough != -1 && above >= InpPivotCandles) {
         if(!(lastType == 1 && minSwing > 0.0 && lastVal - ma[pTrough] < minSwing)) {
            AddLine(lines, ma[pTrough] - off, false, i, (lastType == 1) ? (lastVal - ma[pTrough]) : 0.0);
            lastVal = (lastType == -1) ? MathMin(lastVal, ma[pTrough]) : ma[pTrough];
            lastType = -1;
         }
         pTrough = -1;
      }

      for(int k = 0; k < ArraySize(lines); k++) {
         if(!lines[k].alive || lines[k].born >= i) continue;
         const double L = lines[k].price;
         int dir = 0;
         if(lines[k].upper) {
            if(!lines[k].used && r[i].high >= L - nr && r[i].close < L) dir = -1;
            else if(r[i].close > L) { lines[k].alive = false; continue; }
            else if(r[i].high >= L - nr) lines[k].touches++;
         } else {
            if(!lines[k].used && r[i].low <= L + nr && r[i].close > L) dir = 1;
            else if(r[i].close < L) { lines[k].alive = false; continue; }
            else if(r[i].low <= L + nr) lines[k].touches++;
         }
         if(dir != 0) {
            lines[k].used = true;
            const int s = ArraySize(sigs);
            ArrayResize(sigs, s + 1);
            sigs[s].idx = i; sigs[s].time = r[i].time; sigs[s].dir = dir;
            sigs[s].score = ScoreSig(lines[k], r[i], i);
         }
      }
   }
}

//--------------------------------------------------------------------
// First M1 bar whose open time is >= t (binary search), or -1
int FirstBarAtOrAfter(const MqlRates &m[], const int nm, const datetime t)
{
   int lo = 0, hi = nm - 1, res = -1;
   while(lo <= hi) {
      const int mid = (lo + hi) / 2;
      if(m[mid].time >= t) { res = mid; hi = mid - 1; } else lo = mid + 1;
   }
   return res;
}

// Simulates one trade on M1 bars with the SAME rules as the live management:
// SL, BE after InpBEPoints, one partial at InpPartialPoints, TP.
// Inside one M1 bar the order of high/low is unknown, so the pessimistic order is used:
// original SL first; after the BE trigger a return to the BE price counts as a BE exit.
// cat: 0 SL, 1 BE no partial, 2 BE with partial, 3 TP no partial, 4 TP with partial, 5 timeout
bool SimTrade(const MqlRates &m[], const int nm, const int e, const int dir,
              const double slP, const double tpP, double &resR, int &cat)
{
   if(e < 0 || e >= nm) return false;
   const double entry = m[e].open;
   const double cost = InpSimSpread * _Point;
   const double beP = InpBEPoints * _Point, boff = InpBEOffset * _Point, parP = InpPartialPoints * _Point;
   const double pf = MathMax(0.0, MathMin(1.0, InpPartialPercent / 100.0));
   const int lastK = e + (int)MathMax(1, (double)InpMaxHold * PeriodSeconds() / 60.0);
   bool be = false, part = false;

   for(int k = e; k < nm && k <= lastK; k++) {
      const double fav = (dir > 0) ? m[k].high - entry : entry - m[k].low;
      const double adv = (dir > 0) ? entry - m[k].low : m[k].high - entry;
      double pnl = 0.0;
      if(!be) {
         if(adv >= slP) { pnl = -slP; resR = (pnl - cost) / slP; cat = 0; return true; }
         if(fav < beP) continue;
         be = true;
      }
      if(adv >= -boff) {                              // back at the break-even stop
         pnl = part ? (pf * parP + (1.0 - pf) * boff) : boff;
         resR = (pnl - cost) / slP; cat = part ? 2 : 1; return true;
      }
      if(!part && fav >= parP) part = true;
      if(fav >= tpP) {
         pnl = part ? (pf * parP + (1.0 - pf) * tpP) : tpP;
         resR = (pnl - cost) / slP; cat = part ? 4 : 3; return true;
      }
   }
   if(lastK < nm) {                                   // timeout: close at the last allowed bar
      const double fin = (dir > 0) ? m[lastK].close - entry : entry - m[lastK].close;
      const double pnl = part ? (pf * parP + (1.0 - pf) * fin) : fin;
      resR = (pnl - cost) / slP; cat = 5; return true;
   }
   return false;                                      // data ended first: unresolved, not counted
}

//--------------------------------------------------------------------
bool Calibrate(const string dateStr)
{
   MqlRates r[];
   ArraySetAsSeries(r, false);
   const int got = CopyRates(_Symbol, _Period, 0, InpCalBars + 1, r);
   if(got < 1500) { PrintFormat("Calibration skipped: only %d bars available.", got); return false; }
   const int n = got - 1;                       // last element is the forming bar
   double ma[];
   Hma(r, n, ma);
   SSig sigs[];
   Replay(r, n, ma, sigs);
   const int ns = ArraySize(sigs);
   const int valFrom = n - InpValBars;

   MqlRates m1[];
   ArraySetAsSeries(m1, false);
   const datetime tEnd = r[got - 1].time;
   datetime tStart = r[0].time;
   if((long)(tEnd - tStart) > (long)InpMaxM1Bars * 60) tStart = (datetime)((long)tEnd - (long)InpMaxM1Bars * 60);
   const int nm = CopyRates(_Symbol, PERIOD_M1, tStart, tEnd, m1);
   if(nm < 1000) { PrintFormat("Calibration skipped: only %d M1 bars available.", nm); return false; }

   double resR[]; bool ok[]; int cat[];
   ArrayResize(resR, ns * 3); ArrayResize(ok, ns * 3); ArrayResize(cat, ns * 3);
   const int psec = PeriodSeconds();
   for(int s = 0; s < ns; s++) {
      const int e = FirstBarAtOrAfter(m1, nm, sigs[s].time + psec);
      for(int c = 0; c < 3; c++) {
         const double sl = InpBaseSL * G_SCALE[c] * _Point;
         const double tp = InpBaseTP * G_SCALE[c] * _Point;
         double x = 0.0; int ct = 0;
         ok[s * 3 + c] = (e >= 0 && m1[e].time - (sigs[s].time + psec) <= 2 * psec) && SimTrade(m1, nm, e, sigs[s].dir, sl, tp, x, ct);
         resR[s * 3 + c] = x; cat[s * 3 + c] = ct;
      }
   }

   int    nT[36], nV[36], cc[216];
   double sT[36], sV[36], val[36];
   bool   valid[36];
   ArrayInitialize(cc, 0);
   int best = -1;
   for(int ms = 0; ms < 4; ms++)
      for(int sc = 0; sc < 3; sc++)
         for(int sd = 0; sd < 3; sd++) {
            const int ci = (ms * 3 + sc) * 3 + sd;
            nT[ci] = 0; nV[ci] = 0; sT[ci] = 0.0; sV[ci] = 0.0;
            for(int s = 0; s < ns; s++) {
               if(sigs[s].score < G_MINSCORE[ms]) continue;
               if(sd == 1 && sigs[s].dir < 0) continue;
               if(sd == 2 && sigs[s].dir > 0) continue;
               if(!ok[s * 3 + sc]) continue;
               cc[ci * 6 + cat[s * 3 + sc]]++;
               if(sigs[s].idx >= valFrom) { nV[ci]++; sV[ci] += resR[s * 3 + sc]; }
               else                       { nT[ci]++; sT[ci] += resR[s * 3 + sc]; }
            }
            const double eT = (nT[ci] > 0) ? sT[ci] / nT[ci] : 0.0;
            const double eV = (nV[ci] > 0) ? sV[ci] / nV[ci] : 0.0;
            valid[ci] = (nT[ci] >= InpMinTrades && nV[ci] >= InpMinValTrades && eT > 0.0 && eV > 0.0);
            val[ci] = (nT[ci] + nV[ci] > 0) ? (sT[ci] + sV[ci]) / (nT[ci] + nV[ci]) : 0.0;
            if(valid[ci] && (best < 0 || val[ci] > val[best])) best = ci;
         }

   int chosen = best;
   if(g_cur >= 0 && valid[g_cur] && best >= 0 && best != g_cur && val[best] < val[g_cur] + InpMargin)
      chosen = g_cur;                           // keep the current setting unless clearly beaten

   if(chosen >= 0) {
      g_cur = chosen;
      const int sd = chosen % 3, sc = (chosen / 3) % 3, ms = chosen / 9;
      g_minScore = G_MINSCORE[ms]; g_scale = G_SCALE[sc]; g_side = sd; g_active = true;
   } else {
      g_cur = -1;
      g_active = !InpStandAside;
      g_minScore = 0.0; g_scale = 1.0; g_side = 0;
   }

   for(int ci = 0; ci < 36; ci++) {
      const int sd = ci % 3, sc = (ci / 3) % 3, ms = ci / 9;
      const double eT = (nT[ci] > 0) ? sT[ci] / nT[ci] : 0.0;
      const double eV = (nV[ci] > 0) ? sV[ci] / nV[ci] : 0.0;
      CsvAppend("CalEA_calibration_" + _Symbol + ".csv",
                "date,combo,min_score,scale,side,n_train,exp_train_R,n_val,exp_val_R,valid,chosen,sim_SL,sim_BE_nopart,sim_BE_part,sim_TP_nopart,sim_TP_part,sim_timeout",
                StringFormat("%s,%d,%.0f,%.1f,%d,%d,%.3f,%d,%.3f,%d,%d,%d,%d,%d,%d,%d,%d", dateStr, ci, G_MINSCORE[ms], G_SCALE[sc], sd,
                             nT[ci], eT, nV[ci], eV, valid[ci] ? 1 : 0, (ci == g_cur) ? 1 : 0,
                             cc[ci * 6 + 0], cc[ci * 6 + 1], cc[ci * 6 + 2], cc[ci * 6 + 3], cc[ci * 6 + 4], cc[ci * 6 + 5]));
   }
   PrintFormat("Calibration %s: %d signals, %d M1 bars. %s", dateStr, ns, nm,
               g_active ? StringFormat("ACTIVE minScore %.0f, SL/TP scale %.1f, side %d (value %.3f R)", g_minScore, g_scale, g_side,
                                       (g_cur >= 0) ? val[g_cur] : 0.0)
                        : "NO VALID SETTING - standing aside");
   return true;
}

//--------------------------------------------------------------------
void ShowStatus()
{
   string t = g_active ? StringFormat("CalEA active: minScore %.0f | SL/TP scale %.1f | side %d", g_minScore, g_scale, g_side)
                       : "CalEA: standing aside (no validated setting)";
   t += "\n";
   for(int i = 0; i < 6; i++) t += G_OC[i] + ": " + IntegerToString(g_cnt[i]) + "   ";
   Comment(t);
}

double RoundVolDown(const double v)
{
   const double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   const double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double r = (step > 0.0) ? MathFloor(v / step + 1e-9) * step : v;
   if(r < vmin - 1e-12 || r > vmax + 1e-12) return 0.0;
   return NormalizeDouble(r, 8);
}

bool IsOwned()
{
   return PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic;
}

int CountOpen()
{
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetTicket(i) != 0 && IsOwned()) c++;
   return c;
}

//--------------------------------------------------------------------
int FindPos(const long id)
{
   for(int i = 0; i < ArraySize(g_ps); i++) if(g_ps[i].id == id) return i;
   return -1;
}

// the position must be selected
int EnsurePos(const double score)
{
   const long id = PositionGetInteger(POSITION_IDENTIFIER);
   int i = FindPos(id);
   if(i >= 0) return i;
   const double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   const double vol = PositionGetDouble(POSITION_VOLUME);
   const double sl = PositionGetDouble(POSITION_SL);
   const bool isBuy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   const datetime ot = (datetime)PositionGetInteger(POSITION_TIME);
   double vol0 = vol;
   if(HistorySelectByPosition(id)) {
      double v = 0.0;
      for(int d = 0; d < HistoryDealsTotal(); d++) {
         const ulong dk = HistoryDealGetTicket(d);
         if(dk != 0 && (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dk, DEAL_ENTRY) == DEAL_ENTRY_IN) v += HistoryDealGetDouble(dk, DEAL_VOLUME);
      }
      if(v > 0.0) vol0 = v;
   }
   i = ArraySize(g_ps);
   ArrayResize(g_ps, i + 1);
   g_ps[i].id = id; g_ps[i].vol0 = vol0; g_ps[i].entry = entry; g_ps[i].isBuy = isBuy;
   g_ps[i].be = (sl != 0.0) && (isBuy ? sl >= entry - 1e-9 : sl <= entry + 1e-9);
   g_ps[i].part = (vol < vol0 - 1e-9);
   g_ps[i].partSkipped = false;
   g_ps[i].mfe = 0.0; g_ps[i].mae = 0.0; g_ps[i].score = score; g_ps[i].openT = ot; g_ps[i].retry = 0;
   return i;
}

// Per tick: track excursions, move SL to break-even, take the single partial.
void ManagePositions()
{
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0) return;
   const double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   for(int p = PositionsTotal() - 1; p >= 0; p--) {
      const ulong tk = PositionGetTicket(p);
      if(tk == 0 || !IsOwned()) continue;
      const int i = EnsurePos(0.0);
      const double profit = (g_ps[i].isBuy ? bid - g_ps[i].entry : g_ps[i].entry - ask) / _Point;
      if(profit > g_ps[i].mfe) g_ps[i].mfe = profit;
      if(profit < g_ps[i].mae) g_ps[i].mae = profit;
      if(TimeCurrent() < g_ps[i].retry) continue;

      if(!g_ps[i].be && profit >= InpBEPoints) {
         const double off = InpBEOffset * _Point;
         const double newSL = NormalizeDouble(g_ps[i].isBuy ? g_ps[i].entry + off : g_ps[i].entry - off, _Digits);
         const double sl = PositionGetDouble(POSITION_SL), tpv = PositionGetDouble(POSITION_TP);
         const bool better = (sl == 0.0) || (g_ps[i].isBuy ? newSL > sl + 1e-9 : newSL < sl - 1e-9);
         const bool distOk = g_ps[i].isBuy ? (bid - newSL >= minDist) : (newSL - ask >= minDist);
         if(!better) g_ps[i].be = true;
         else if(distOk) {
            if(g_trade.PositionModify(tk, newSL, tpv)) {
               g_ps[i].be = true;
               PrintFormat("BE: #%I64u SL moved to %s at %.0f pts profit.", tk, DoubleToString(newSL, _Digits), profit);
            } else g_ps[i].retry = TimeCurrent() + 5;
         }
      }
      if(g_ps[i].be && !g_ps[i].part && !g_ps[i].partSkipped && profit >= InpPartialPoints) {
         const double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         const double cur = PositionGetDouble(POSITION_VOLUME);
         const double pv = RoundVolDown(g_ps[i].vol0 * InpPartialPercent / 100.0);
         if(pv <= 0.0 || cur - pv < vmin - 1e-12) {
            g_ps[i].partSkipped = true;
            PrintFormat("Partial skipped on #%I64u: %.2f of %.2f lots would break the minimum lot rules.", tk, pv, cur);
         } else {
            g_trade.SetTypeFillingBySymbol(_Symbol);
            if(g_trade.PositionClosePartial(tk, pv)) {
               g_ps[i].part = true;
               PrintFormat("PARTIAL: #%I64u closed %.2f lots at %.0f pts profit.", tk, pv, profit);
            } else g_ps[i].retry = TimeCurrent() + 5;
         }
      }
   }
}

//--------------------------------------------------------------------
bool PositionStillOpen(const long pid)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetTicket(i) != 0 && PositionGetInteger(POSITION_IDENTIFIER) == pid) return true;
   return false;
}

void LogClosed(const long pid)
{
   if(!HistorySelectByPosition(pid)) return;
   int outs = 0;
   double entryP = 0.0, lastP = 0.0, net = 0.0;
   datetime tin = 0, tout = 0;
   bool buy = true;
   ENUM_DEAL_REASON rs = DEAL_REASON_CLIENT;
   for(int d = 0; d < HistoryDealsTotal(); d++) {
      const ulong dk = HistoryDealGetTicket(d);
      if(dk == 0) continue;
      const ENUM_DEAL_ENTRY e = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dk, DEAL_ENTRY);
      net += HistoryDealGetDouble(dk, DEAL_PROFIT) + HistoryDealGetDouble(dk, DEAL_SWAP)
           + HistoryDealGetDouble(dk, DEAL_COMMISSION) + HistoryDealGetDouble(dk, DEAL_FEE);
      if(e == DEAL_ENTRY_IN) {
         entryP = HistoryDealGetDouble(dk, DEAL_PRICE);
         tin = (datetime)HistoryDealGetInteger(dk, DEAL_TIME);
         buy = ((ENUM_DEAL_TYPE)HistoryDealGetInteger(dk, DEAL_TYPE) == DEAL_TYPE_BUY);
      } else if(e == DEAL_ENTRY_OUT || e == DEAL_ENTRY_OUT_BY) {
         outs++;
         lastP = HistoryDealGetDouble(dk, DEAL_PRICE);
         tout = (datetime)HistoryDealGetInteger(dk, DEAL_TIME);
         rs = (ENUM_DEAL_REASON)HistoryDealGetInteger(dk, DEAL_REASON);
      }
   }
   if(outs == 0) return;
   const int st = FindPos(pid);
   const bool hadPart = (outs >= 2);
   const double dist = MathAbs(lastP - entryP) / _Point;
   int oc = 5;
   if(rs == DEAL_REASON_TP) oc = hadPart ? 4 : 3;
   else if(rs == DEAL_REASON_SL) {
      const bool beSet = (st >= 0) ? g_ps[st].be : true;
      oc = (beSet && dist <= InpBEOffset + InpBETol) ? (hadPart ? 2 : 1) : 0;
   }
   g_cnt[oc]++;
   CsvAppend("CalEA_outcomes_" + _Symbol + ".csv",
             "open_time,close_time,side,outcome,had_partial,be_set,entry,last_exit,mfe_pts,mae_pts,net_money,score,minutes",
             StringFormat("%s,%s,%s,%s,%d,%d,%s,%s,%.0f,%.0f,%.2f,%.1f,%d",
                          TimeToString(tin, TIME_DATE | TIME_MINUTES), TimeToString(tout, TIME_DATE | TIME_MINUTES),
                          buy ? "BUY" : "SELL", G_OC[oc], hadPart ? 1 : 0, (st >= 0 && g_ps[st].be) ? 1 : 0,
                          DoubleToString(entryP, _Digits), DoubleToString(lastP, _Digits),
                          (st >= 0) ? g_ps[st].mfe : 0.0, (st >= 0) ? g_ps[st].mae : 0.0, net,
                          (st >= 0) ? g_ps[st].score : 0.0, (int)((tout - tin) / 60)));
   PrintFormat("CLOSED #%I64d: %s | net %.2f | MFE %.0f pts", pid, G_OC[oc], net, (st >= 0) ? g_ps[st].mfe : 0.0);
   if(st >= 0) {
      const int last = ArraySize(g_ps) - 1;
      if(st != last) g_ps[st] = g_ps[last];
      ArrayResize(g_ps, last);
   }
   ShowStatus();
}

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   const ulong dk = trans.deal;
   if(dk == 0 || !HistoryDealSelect(dk)) return;
   if(HistoryDealGetString(dk, DEAL_SYMBOL) != _Symbol || HistoryDealGetInteger(dk, DEAL_MAGIC) != InpMagic) return;
   const ENUM_DEAL_ENTRY e = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dk, DEAL_ENTRY);
   if(e != DEAL_ENTRY_OUT && e != DEAL_ENTRY_OUT_BY) return;
   const long pid = HistoryDealGetInteger(dk, DEAL_POSITION_ID);
   if(PositionStillOpen(pid)) return;            // that was the partial
   LogClosed(pid);
}

//--------------------------------------------------------------------
void OpenTrade(const int dir, const double score, const datetime barTime)
{
   if(CountOpen() >= InpMaxOpen) return;
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0) return;
   if(InpMaxSpread > 0 && (ask - bid) / _Point > InpMaxSpread) return;
   const double slP = InpBaseSL * g_scale * _Point, tpP = InpBaseTP * g_scale * _Point;
   const double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(slP <= minDist || tpP <= minDist) { Print("Signal skipped: SL/TP inside min stop distance."); return; }
   const double price = (dir > 0) ? ask : bid;
   const double sl = NormalizeDouble((dir > 0) ? price - slP : price + slP, _Digits);
   const double tp = NormalizeDouble((dir > 0) ? price + tpP : price - tpP, _Digits);
   const double vol = MathMax(RoundVolDown(InpLot), SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   const bool ok = (dir > 0) ? g_trade.Buy(vol, _Symbol, price, sl, tp, "CAL") : g_trade.Sell(vol, _Symbol, price, sl, tp, "CAL");
   const uint rc = g_trade.ResultRetcode();
   if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED)) {
      PrintFormat("ENTRY %s at %s SL %s TP %s score %.0f", dir > 0 ? "BUY" : "SELL", DoubleToString(price, _Digits),
                  DoubleToString(sl, _Digits), DoubleToString(tp, _Digits), score);
      for(int p = PositionsTotal() - 1; p >= 0; p--)
         if(PositionGetTicket(p) != 0 && IsOwned()) EnsurePos(score);   // registers the new position with its score
   } else
      PrintFormat("Order failed: retcode %u %s", rc, g_trade.ResultRetcodeDescription());
}

void LiveCheck()
{
   if(!g_active) return;
   MqlRates r[];
   ArraySetAsSeries(r, false);
   const int got = CopyRates(_Symbol, _Period, 0, InpLiveBars + 1, r);
   if(got < 300) return;
   const int n = got - 1;
   double ma[];
   Hma(r, n, ma);
   SSig sigs[];
   Replay(r, n, ma, sigs);
   for(int s = 0; s < ArraySize(sigs); s++) {
      if(sigs[s].idx != n - 1) continue;
      if(sigs[s].score < g_minScore) continue;
      if(g_side == 1 && sigs[s].dir < 0) continue;
      if(g_side == 2 && sigs[s].dir > 0) continue;
      OpenTrade(sigs[s].dir, sigs[s].score, sigs[s].time);
   }
}

//--------------------------------------------------------------------
int OnInit()
{
   if(InpMaPeriod < 2 || InpCalBars < 2000 || InpValBars >= InpCalBars / 2) return INIT_PARAMETERS_INCORRECT;
   if(InpBEPoints <= 0 || InpPartialPoints <= InpBEPoints || InpPartialPercent <= 0.0 || InpPartialPercent >= 100.0) return INIT_PARAMETERS_INCORRECT;
   g_lastBar = 0; g_calKey = -1; g_active = false; g_cur = -1;
   ArrayResize(g_ps, 0);
   ArrayInitialize(g_cnt, 0);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   string t = "CalEA outcome summary:";
   for(int i = 0; i < 6; i++) t += " " + G_OC[i] + "=" + IntegerToString(g_cnt[i]);
   Print(t);
   Comment("");
}

void OnTick()
{
   ManagePositions();
   const datetime bt = iTime(_Symbol, _Period, 0);
   if(bt == 0 || bt == g_lastBar) return;
   g_lastBar = bt;
   MqlDateTime d;
   TimeToStruct(bt, d);
   const int key = d.year * 1000 + d.day_of_year;
   if(key != g_calKey) {
      if(Calibrate(StringFormat("%04d-%02d-%02d", d.year, d.mon, d.day))) g_calKey = key;
      ShowStatus();
   }
   LiveCheck();
}
