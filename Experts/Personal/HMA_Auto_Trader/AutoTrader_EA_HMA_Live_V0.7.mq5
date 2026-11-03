#property copyright "smooth_custom_ma EA - Live"
#property version   "0.70"
#property description "HTF MA inflection-line LIVE-entry EA v0.7 (CSV journal, daily limits, session)"

#include <Trade\Trade.mqh>

#define MAX_ACTIVE_LINES 400
#define MAX_DRAWN_LINES  100
#define PFX_ALL          "SMEL_"
#define PFX_MA           "SMEL_MA_"
#define PFX_LN           "SMEL_LN_"
#define PFX_PT           "SMEL_PT_"   // per-trade partial levels
#define KEY_SELL         "HTF_S_"
#define KEY_BUY          "HTF_B_"

enum ENUM_DD_SL {
   DDSL_SAME_PRICE    = 0,   // Same SL price as the first order
   DDSL_SAME_DISTANCE = 1    // Same SL distance (points) from the DD entry
};

enum ENUM_DD_WORST {
   DDW_CLOSE_AT_GREEN = 0,   // Older entries are closed as soon as their own net value is green
   DDW_LET_RUN        = 1    // Nobody is closed early; every entry runs its own partials / BE / TP
};

enum ENUM_CUSTOM_MA {
   CMA_SMA=0,
   CMA_EMA=1,
   CMA_RMA=2,
   CMA_WMA=3,
   CMA_HMA=4
};

enum ENUM_LIMIT_MODE {
   LIM_MONEY   = 0,   // Account currency amount
   LIM_PERCENT = 1    // % of the day-start balance
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
input color InpDimColor     = clrDarkSlateGray;   // Lines in a group that carry no order
input color InpActiveColor  = clrOrange;          // Lines that carry (or may carry) an order
input bool  InpDrawPartials = true;               // Draw partial levels for each open trade
input color InpPartialColor = clrDarkGray;        // Colour of the partial level lines

input group "=== Inflection Line Settings ==="
input int   InpLineOffsetPoints = 350;
input int   InpPivotCandles     = 5;

input group "=== Line Grouping (lines within range: one trade, neighbours retired) ==="
input bool InpEnableGrouping      = true;   // Group nearby same-direction lines; one order per group
input int  InpGroupDistancePoints = 100;    // Lines within this range form one group

input group "=== Order Settings (market entries) ==="
input double InpLot                  = 0.5;
input int    InpSLPoints             = 700;
input int    InpTPPoints             = 1400;
input int    InpOrderProximityPoints = 200;   // WATCHING: a bar within this range of a line puts the line in watching state
input long   InpMagic                = 20260930;

input group "=== Ranging Filter (false-line filter) ==="
input int    InpMinSwingPoints      = 600;    // New pivot accepted only if MA moved >= this from the last opposite pivot (0 = off)
input int    InpSwingATRPeriod      = 14;     // ATR period (chart TF) for the optional ATR swing minimum
input double InpSwingATRMult        = 0.0;    // Min swing = max(points, ATR x mult). 0 = ATR off

input group "=== Live Entry ==="
input int    InpWaitCandles         = 1;      // After a close through the line, the trade must come within this many candles, otherwise the line is dropped (1 = 2nd candle only)
input int    InpRetraceTouchPoints  = 100;    // Retracement: the candle must come back within this range of the line (or cross it)
input int    InpConflictDistancePoints = 300; // Buy & sell lines closer than this form a conflict zone (0 = off)
input int    InpMaxOpenMain         = 5;      // Max open main (non-DD) positions
input int    InpMaxSpreadPoints     = 0;      // Skip entry if spread is wider (0 = off)
input color  InpWatchColor          = clrGold;// Lines in watching state

input group "=== Trading Session (server time) ==="
input bool   InpUseSession          = true;   // New entries only inside the session
input string InpSessionStart        = "08:00";// Session start HH:MM (server time)
input string InpSessionEnd          = "20:00";// Session end HH:MM (server time); start > end = overnight session
input bool   InpCloseAtSessionEnd   = false;  // Also close all open positions when the session ends

input group "=== Daily Profit / Loss Limits ==="
input ENUM_LIMIT_MODE InpLimitMode  = LIM_MONEY; // How the two limits below are interpreted
input double InpDailyProfitTarget   = 0.0;    // Stop trading for the day when daily P&L >= this (0 = off)
input double InpDailyLossLimit      = 0.0;    // Stop trading for the day when daily P&L <= -this (0 = off, enter as a positive number)
input bool   InpLimitIncludeFloating= true;   // Daily P&L = closed deals + floating profit of open positions
input bool   InpCloseOnLimit        = true;   // Close all open positions when a daily limit is hit (false = only block new entries)

input group "=== CSV Journal ==="
input bool   InpCsvEnable           = true;   // Write the journal to a CSV file
input bool   InpCsvCommon           = true;   // true = Terminal\Common\Files, false = this terminal's MQL5\Files
input string InpCsvDelim            = ";";    // Column delimiter (";" opens correctly in Swedish Excel)
input bool   InpCsvDetail           = true;   // Also log WATCH_WAIT / WAIT_DROPPED events

input group "=== Partials ==="
input int    InpPartials            = 7;      // Number of partials; step = TP / N (TP 1400, N=7 -> 200, 400, ... 1400)
input double InpPartialPercent      = 10.0;   // % of INITIAL volume closed per partial

input group "=== SL Partials (losing side) ==="
input bool   InpEnableSLPartials    = true;   // Toggle SL partials
input int    InpSLPartials          = 7;      // Number of SL partials; step = SL / N (SL 700, N=7 -> -100, -200, ... -700). 0 = off
input double InpSLPartialPercent    = 10.0;   // % of INITIAL volume closed per SL partial

input group "=== Cooldown after SL ==="
input int    InpSLCooldownMinutes   = 60;     // After a full SL hit: no trades in the SAME direction for this long (0 = off)
input bool   InpCooldownOnAnyLoss   = false;  // Also start the cooldown when a trade closes in loss for another reason

input group "=== Drawdown (DD) Entries ==="
input int        InpMaxDDEntries      = 2;               // DD entries per first order (0 = off; hedging accounts only)
input int        InpDDStepPoints      = 200;             // Adverse move between DD entries
input ENUM_DD_SL InpDDSLMode          = DDSL_SAME_PRICE;
input bool       InpCooldownBlocksDD  = true;            // No DD entries while the direction is in cooldown
input ENUM_DD_WORST InpDDWorstMode     = DDW_CLOSE_AT_GREEN; // How older (worst) entries of a group are handled
input double     InpDDGreenMinUSD     = 0.0;             // CLOSE_AT_GREEN: net (profit+swap+commission) must exceed this
input bool       InpDDSyncSLOnBE      = true;            // When the latest entry reaches BE, give the whole group that SL

input group "=== Break-even ==="
input int    InpBEPoints            = 200;    // Move SL to break-even after this many points in profit (0 = off)
input int    InpBEOffsetPoints      = 0;      // BE stop = entry +/- this buffer (covers spread/commission)

//--- lines (rebuilt on every new chart bar)
struct SLine {
   double   price;
   datetime startTime;
   bool     upper;
   bool     mitigated;
   bool     alive;
   bool     rep;        // representative of its group (display only in live mode)
   datetime createTime; // bar on which the line was confirmed (state machine starts after it)
   int      state;      // 0 idle/watching-near, 1 = waiting after a close through the line
   int      waitBars;   // closed bars spent in state 1
};
SLine g_lines[];

//--- per-line order records (persist across rebuilds)
struct SOrderRec {
   string   key;
   bool     sent;
   datetime nextTry;
};
SOrderRec g_recs[];

//--- per-position state (partials)
struct SPosState {
   ulong    ticket;
   long     posId;      // POSITION_IDENTIFIER (for history lookups after the position is gone)
   double   entry;
   double   vol0;
   bool     isBuy;
   int      partials;
   int      slPartials;
   int      ddOpened;
   bool     beDone;
   bool     volWarned;
   datetime partialRetry;
};
SPosState g_ps[];

//--- DD ticket -> main-order ticket map (filled when a DD order is accepted; comment is the fallback)
struct SDDLink { ulong dd; ulong anchor; };
SDDLink  g_ddLinks[];
datetime g_ddRetry[2];

//--- group roles, rebuilt every tick: which open positions are "worst" (older) entries
struct SRole { ulong ticket; ulong anchor; bool latest; int members; };
SRole    g_roles[];
bool     g_slPartialsOn = true;   // SL partials are disabled automatically while DD entries are enabled

#define KEY_DD "HTF_DD"
const int InpMaxPending = 30;        // legacy (limit-order code kept but unused)
const int InpCancelAwayPoints = 500; // legacy

CTrade          g_trade;
ENUM_TIMEFRAMES g_tf      = PERIOD_CURRENT;
int             g_tfSec   = 60;
int             g_chartSec= 60;
bool            g_sameTf  = true;
int             g_basePeriod   = 1;
int             g_smoothPeriod = 1;
bool            g_drawVisuals  = false;
datetime        g_lastBar = 0;
datetime        g_cooldownUntil[2];   // [0] = BUY side, [1] = SELL side
bool            g_hedging = true;
bool            g_linesValid = false;
int             g_sigJ[];
int             g_sigD[];
string          g_sigWhy[];
int             g_nSig = 0;
datetime        g_lastExecBar = 0;
int             g_atrH = INVALID_HANDLE;
int             g_rejPrinted = -1;
bool            g_replayLast = false;
MqlRates        g_lastBarRates;
MqlRates        g_noBar;
string          g_csvName = "";
ushort          g_csvDelim = ';';
bool            g_csvOff = false;
bool            g_halted = false;
string          g_haltReason = "";
datetime        g_dayKey = 0;
double          g_closedPnl = 0.0;
double          g_dayStartBalance = 0.0;
int             g_sessStartMin = 0;
int             g_sessEndMin = 0;
datetime        g_nextClose = 0;

void DrawLines(const datetime anchor);
void ExecuteSignals(const datetime barTime);
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

// Number of leading values of an MA that are not yet "settled"
int WarmBars(const ENUM_CUSTOM_MA type, const int period)
{
   if(period <= 1) return 0;
   if(type == CMA_EMA || type == CMA_RMA) return period * 4;   // exponential tail
   return period + 2;                                           // SMA / WMA / HMA
}

// Blanks the first `w` valid values so raw start-up values never create pivots
void BlankWarmup(double &ma[], const int n, const int w)
{
   if(w <= 0) return;
   int f = 0;
   while(f < n && ma[f] == EMPTY_VALUE) f++;
   for(int i = f; i < n && i < f + w; i++) ma[i] = EMPTY_VALUE;
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

void AddInflection(const datetime t, const double price, const bool upper, const datetime created)
{
   while(ActiveCount() >= MAX_ACTIVE_LINES) DropOldestActive();
   const int sz = ArraySize(g_lines);
   ArrayResize(g_lines, sz + 1);
   g_lines[sz].price     = price;
   g_lines[sz].startTime = t;
   g_lines[sz].upper     = upper;
   g_lines[sz].mitigated = false;
   g_lines[sz].alive     = true;
   g_lines[sz].rep       = false;
   g_lines[sz].createTime= created;
   g_lines[sz].state     = 0;
   g_lines[sz].waitBars  = 0;
}

// Groups active lines per direction (lines within InpGroupDistancePoints of
// the group's lowest line). Marks ONE representative per group:
//   sell group -> highest line, buy group -> lowest line.
// Lines are never moved or removed here.
void SelectRepresentatives()
{
   const int total = ArraySize(g_lines);
   for(int i = 0; i < total; i++) g_lines[i].rep = false;

   const double thr = (InpEnableGrouping && InpGroupDistancePoints > 0)
                      ? InpGroupDistancePoints * _Point : -1.0;

   for(int dir = 0; dir < 2; dir++) {
      const bool upper = (dir == 0);
      int idx[];
      int cnt = 0;
      ArrayResize(idx, total);
      for(int i = 0; i < total; i++)
         if(g_lines[i].alive && !g_lines[i].mitigated && g_lines[i].upper == upper) idx[cnt++] = i;
      if(cnt == 0) continue;

      if(thr < 0.0) {                       // grouping off: every line is its own group
         for(int k = 0; k < cnt; k++) g_lines[idx[k]].rep = true;
         continue;
      }

      // sort ascending by price (insertion sort, cnt is small)
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
      while(s < cnt) {
         int e = s;
         while(e + 1 < cnt && (g_lines[idx[e + 1]].price - g_lines[idx[s]].price) <= thr) e++;
         const int rep = upper ? idx[e] : idx[s];
         g_lines[rep].rep = true;
         s = e + 1;
      }
   }
}

//+------------------------------------------------------------------+
//| CSV journal                                                        |
//+------------------------------------------------------------------+
string JS(const string s)
{
   string r = s;
   StringReplace(r, ShortToString(g_csvDelim), "/");
   StringReplace(r, "\n", " ");
   StringReplace(r, "\r", " ");
   return r;
}

string JN(const double v, const int d)
{
   return (v == 0.0) ? "" : DoubleToString(v, d);
}

void JournalWrite(const string ev, const string side, const string lineType, const double linePrice, const int lineState,
                  const MqlRates &b, const double price, const double sl, const double tp, const double lot,
                  const long posId, const ulong deal, const string dealReason, const double pnl, const string reason)
{
   if(!InpCsvEnable || g_csvOff) return;
   const uint fl = FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE | (InpCsvCommon ? FILE_COMMON : 0);
   const int h = FileOpen(g_csvName, fl, g_csvDelim);
   if(h == INVALID_HANDLE) return;
   if(FileSize(h) == 0)
      FileWrite(h, "time", "event", "symbol", "tf", "side", "line_type", "line_price", "line_state", "bar_time",
                "open", "high", "low", "close", "spread_pts", "price", "sl", "tp", "lot",
                "position_id", "deal", "deal_reason", "net_profit", "reason");
   FileSeek(h, 0, SEEK_END);
   const double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   FileWrite(h, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), ev, _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period),
             side, lineType, JN(linePrice, _Digits), (lineType == "" ? "" : (lineState == 0 ? "idle" : "waiting")),
             (b.time > 0 ? TimeToString(b.time, TIME_DATE | TIME_MINUTES) : ""),
             (b.time > 0 ? DoubleToString(b.open, _Digits) : ""), (b.time > 0 ? DoubleToString(b.high, _Digits) : ""),
             (b.time > 0 ? DoubleToString(b.low, _Digits) : ""), (b.time > 0 ? DoubleToString(b.close, _Digits) : ""),
             DoubleToString(spread, 0),
             JN(price, _Digits), JN(sl, _Digits), JN(tp, _Digits), JN(lot, 2),
             (posId > 0 ? IntegerToString(posId) : ""), (deal > 0 ? IntegerToString((long)deal) : ""),
             dealReason, (ev == "DEAL_OUT" ? DoubleToString(pnl, 2) : ""), JS(reason));
   FileClose(h);
}

void JLine(const string ev, const int j, const MqlRates &b, const string reason, const int dir = 0)
{
   if(!InpCsvDetail) return;
   JournalWrite(ev, dir > 0 ? "BUY" : (dir < 0 ? "SELL" : ""), g_lines[j].upper ? "SELL-line" : "BUY-line",
                g_lines[j].price, g_lines[j].state, b, 0, 0, 0, 0, 0, 0, "", 0, reason);
}

string DealReasonText(const ENUM_DEAL_REASON r)
{
   switch(r) {
      case DEAL_REASON_CLIENT: return "manual";
      case DEAL_REASON_MOBILE: return "manual-mobile";
      case DEAL_REASON_WEB:    return "manual-web";
      case DEAL_REASON_EXPERT: return "EA (partial/close)";
      case DEAL_REASON_SL:     return "stop-loss";
      case DEAL_REASON_TP:     return "take-profit";
      case DEAL_REASON_SO:     return "stop-out";
      default:                 return "other";
   }
}

void JournalDeal(const ulong dk)
{
   if(!InpCsvEnable || dk == 0 || !HistoryDealSelect(dk)) return;
   if(HistoryDealGetString(dk, DEAL_SYMBOL) != _Symbol || HistoryDealGetInteger(dk, DEAL_MAGIC) != InpMagic) return;
   const ENUM_DEAL_ENTRY e = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dk, DEAL_ENTRY);
   if(e != DEAL_ENTRY_IN && e != DEAL_ENTRY_OUT && e != DEAL_ENTRY_OUT_BY) return;
   const bool dealBuy = ((ENUM_DEAL_TYPE)HistoryDealGetInteger(dk, DEAL_TYPE) == DEAL_TYPE_BUY);
   const bool posBuy  = (e == DEAL_ENTRY_IN) ? dealBuy : !dealBuy;
   const double pnl = HistoryDealGetDouble(dk, DEAL_PROFIT) + HistoryDealGetDouble(dk, DEAL_SWAP) + HistoryDealGetDouble(dk, DEAL_COMMISSION);
   JournalWrite(e == DEAL_ENTRY_IN ? "DEAL_IN" : "DEAL_OUT", posBuy ? "BUY" : "SELL", "", 0, 0, g_noBar,
                HistoryDealGetDouble(dk, DEAL_PRICE), 0, 0, HistoryDealGetDouble(dk, DEAL_VOLUME),
                HistoryDealGetInteger(dk, DEAL_POSITION_ID), dk,
                DealReasonText((ENUM_DEAL_REASON)HistoryDealGetInteger(dk, DEAL_REASON)), pnl,
                "deal comment: " + HistoryDealGetString(dk, DEAL_COMMENT));
}

//+------------------------------------------------------------------+
//| Trading session + daily profit / loss limits                       |
//+------------------------------------------------------------------+
int ParseHHMM(const string s)
{
   const int p = StringFind(s, ":");
   if(p < 1) return -1;
   const int hh = (int)StringToInteger(StringSubstr(s, 0, p));
   const int mm = (int)StringToInteger(StringSubstr(s, p + 1));
   if(hh < 0 || hh > 24 || mm < 0 || mm > 59) return -1;
   return hh * 60 + mm;
}

bool InSession()
{
   if(!InpUseSession) return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   const int m = dt.hour * 60 + dt.min;
   if(g_sessStartMin == g_sessEndMin) return true;
   if(g_sessStartMin < g_sessEndMin) return (m >= g_sessStartMin && m < g_sessEndMin);
   return (m >= g_sessStartMin || m < g_sessEndMin);
}

void RefreshClosedPnl()
{
   const datetime now = TimeCurrent();
   const datetime dayStart = now - (now % 86400);
   double sum = 0.0;
   if(HistorySelect(dayStart, now + 86400)) {
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--) {
         const ulong dk = HistoryDealGetTicket(i);
         if(dk == 0) continue;
         if(HistoryDealGetInteger(dk, DEAL_MAGIC) != InpMagic) continue;
         if(HistoryDealGetString(dk, DEAL_SYMBOL) != _Symbol) continue;
         const ENUM_DEAL_ENTRY e = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dk, DEAL_ENTRY);
         if(e != DEAL_ENTRY_IN && e != DEAL_ENTRY_OUT && e != DEAL_ENTRY_OUT_BY) continue;
         sum += HistoryDealGetDouble(dk, DEAL_PROFIT) + HistoryDealGetDouble(dk, DEAL_SWAP)
              + HistoryDealGetDouble(dk, DEAL_COMMISSION) + HistoryDealGetDouble(dk, DEAL_FEE);
      }
   }
   g_closedPnl = sum;
}

double FloatingPnl()
{
   double f = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionGetTicket(i) == 0 || !IsOwnedPositionSelected()) continue;
      f += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return f;
}

int CountOwnedPositions()
{
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionGetTicket(i) == 0 || !IsOwnedPositionSelected()) continue;
      c++;
   }
   return c;
}

void CloseAllOwned(const string why)
{
   g_trade.SetTypeFillingBySymbol(_Symbol);
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      const ulong tk = PositionGetTicket(i);
      if(tk == 0 || !IsOwnedPositionSelected()) continue;
      if(TradeOk(g_trade.PositionClose(tk)))
         PrintFormat("Position #%I64u closed: %s.", tk, why);
      else
         LogFail("Close #" + IntegerToString((long)tk) + " (" + why + ")");
   }
}

double LimitValue(const double v)
{
   if(v <= 0.0) return 0.0;
   return (InpLimitMode == LIM_PERCENT) ? g_dayStartBalance * v / 100.0 : v;
}

void HaltTrading(const string reason)
{
   g_halted = true;
   g_haltReason = reason;
   PrintFormat("TRADING HALTED for today: %s", reason);
   JournalWrite("DAILY_LIMIT", "", "", 0, 0, g_noBar, 0, 0, 0, 0, 0, 0, "", 0, reason + (InpCloseOnLimit ? " | all open positions closed" : " | open positions left to run, no new entries"));
   if(InpCloseOnLimit) CloseAllOwned("daily limit");
}

void DayRollover()
{
   const datetime now = TimeCurrent();
   const datetime d = now - (now % 86400);
   if(d == g_dayKey) return;
   g_dayKey = d;
   RefreshClosedPnl();
   g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE) - g_closedPnl;
   if(g_halted) {
      Print("New trading day: daily halt cleared.");
      JournalWrite("DAILY_RESET", "", "", 0, 0, g_noBar, 0, 0, 0, 0, 0, 0, "", 0, "new server day: daily halt cleared");
   }
   g_halted = false;
   g_haltReason = "";
}

void CheckDailyLimits()
{
   DayRollover();
   const datetime now = TimeCurrent();

   const double pnl = g_closedPnl + (InpLimitIncludeFloating ? FloatingPnl() : 0.0);
   const double target = LimitValue(InpDailyProfitTarget);
   const double lossLim = LimitValue(InpDailyLossLimit);

   if(!g_halted) {
      if(target > 0.0 && pnl >= target)
         HaltTrading(StringFormat("daily profit target reached: P&L %.2f >= %.2f", pnl, target));
      else if(lossLim > 0.0 && pnl <= -lossLim)
         HaltTrading(StringFormat("daily loss limit reached: P&L %.2f <= -%.2f", pnl, lossLim));
   } else if(InpCloseOnLimit && now >= g_nextClose && CountOwnedPositions() > 0) {
      CloseAllOwned("daily limit");
      g_nextClose = now + 5;
   }

   if(InpUseSession && InpCloseAtSessionEnd && !InSession() && now >= g_nextClose && CountOwnedPositions() > 0) {
      CloseAllOwned("session ended");
      JournalWrite("SESSION_CLOSE", "", "", 0, 0, g_noBar, 0, 0, 0, 0, 0, 0, "", 0, "session ended: all open positions closed");
      g_nextClose = now + 5;
   }

   if(g_drawVisuals)
      Comment(StringFormat("Live EA v0.7 | %s\nSession %s-%s (%s) | server %s\nDay P&L %.2f  (closed %.2f)  target %s  loss limit %s",
                           g_halted ? "HALTED: " + g_haltReason : (InSession() ? "trading" : "outside session"),
                           InpSessionStart, InpSessionEnd, InpUseSession ? "on" : "off", TimeToString(now, TIME_MINUTES),
                           pnl, g_closedPnl,
                           target > 0.0 ? DoubleToString(target, 2) : "off", lossLim > 0.0 ? DoubleToString(lossLim, 2) : "off"));
}

bool TradingAllowed(string &why)
{
   if(g_halted) { why = "trading halted for today: " + g_haltReason; return false; }
   if(!InSession()) {
      why = StringFormat("outside trading session %s-%s (server time %s)", InpSessionStart, InpSessionEnd, TimeToString(TimeCurrent(), TIME_MINUTES));
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Live engine: ranging filter, line state machine, conflict zone,    |
//| market execution                                                   |
//+------------------------------------------------------------------+
double SwingMinPrice()
{
   double m = MathMax(0, InpMinSwingPoints) * _Point;
   if(InpSwingATRMult > 0.0 && g_atrH != INVALID_HANDLE) {
      double b[];
      if(CopyBuffer(g_atrH, 0, 1, 1, b) == 1 && b[0] > 0.0) m = MathMax(m, b[0] * InpSwingATRMult);
   }
   return m;
}

void MarkUsed(const int j)
{
   g_lines[j].mitigated = true;
   if(!InpEnableGrouping || InpGroupDistancePoints <= 0) return;
   const double thr = InpGroupDistancePoints * _Point;
   for(int k = 0; k < ArraySize(g_lines); k++) {
      if(k == j || !g_lines[k].alive || g_lines[k].mitigated) continue;
      if(g_lines[k].upper != g_lines[j].upper) continue;
      if(MathAbs(g_lines[k].price - g_lines[j].price) <= thr) g_lines[k].mitigated = true;
   }
}

bool ZoneBlocks(const int j, const int dir, const double close)
{
   if(InpConflictDistancePoints <= 0) return false;
   const double thr = InpConflictDistancePoints * _Point;
   double lo = g_lines[j].price, hi = g_lines[j].price;
   bool any = false;
   for(int k = 0; k < ArraySize(g_lines); k++) {
      if(k == j || !g_lines[k].alive || g_lines[k].mitigated) continue;
      if(g_lines[k].upper == g_lines[j].upper) continue;
      if(MathAbs(g_lines[k].price - g_lines[j].price) > thr) continue;
      any = true;
      lo = MathMin(lo, g_lines[k].price);
      hi = MathMax(hi, g_lines[k].price);
   }
   if(!any) return false;
   return (dir > 0) ? (close <= hi) : (close >= lo);
}

// One closed bar against one line. Returns +1 BUY, -1 SELL, 0 nothing. `why` = reason text of a signal.
int StepLine(const int j, const MqlRates &b, string &why)
{
   why = "";
   const double L    = g_lines[j].price;
   const double prox = InpOrderProximityPoints * _Point;
   const bool buyLine = !g_lines[j].upper;
   const string lt = buyLine ? "BUY-line " : "SELL-line ";
   int sig = 0;

   if(g_lines[j].state == 0) {
      if(!(b.high >= L - prox && b.low <= L + prox)) return 0;
      if(buyLine) {
         if(b.low < L && b.close > L) {
            sig = 1;
            why = StringFormat("%s%s: candle wicked %.0f pts below the line and closed %.0f pts above it (rejection from below)",
                               lt, DoubleToString(L, _Digits), (L - b.low) / _Point, (b.close - L) / _Point);
         } else if(b.close < L) {
            g_lines[j].state = 1; g_lines[j].waitBars = 0;
            if(g_replayLast) JLine("WATCH_WAIT", j, b, "candle closed below the line; the next candle must retrace or the line is dropped");
         }
      } else {
         if(b.high > L && b.close < L) {
            sig = -1;
            why = StringFormat("%s%s: candle wicked %.0f pts above the line and closed %.0f pts below it (rejection from above)",
                               lt, DoubleToString(L, _Digits), (b.high - L) / _Point, (L - b.close) / _Point);
         } else if(b.close > L) {
            g_lines[j].state = 1; g_lines[j].waitBars = 0;
            if(g_replayLast) JLine("WATCH_WAIT", j, b, "candle closed above the line; the next candle must retrace or the line is dropped");
         }
      }
      if(sig != 0 && ZoneBlocks(j, sig, b.close)) {
         if(g_replayLast) JLine("ZONE_BLOCKED", j, b, "conflict zone: close not yet beyond the opposite-line zone | " + why, sig);
         why = "";
         return 0;
      }
      return sig;
   }

   g_lines[j].waitBars++;
   const double touch = InpRetraceTouchPoints * _Point;
   if(buyLine) {
      if(b.close > L) {
         sig = 1;
         why = StringFormat("%s%s: after an earlier close below, this candle closed back above the line by %.0f pts (retracement, price returned)",
                            lt, DoubleToString(L, _Digits), (b.close - L) / _Point);
      } else if(b.close < L && b.high >= L - touch) {
         sig = -1;
         why = StringFormat("%s%s: after an earlier close below, price retraced to within %.0f pts of the line (high %s) and closed %.0f pts below it (line rejected)",
                            lt, DoubleToString(L, _Digits), (L - b.high) / _Point, DoubleToString(b.high, _Digits), (L - b.close) / _Point);
      }
   } else {
      if(b.close < L) {
         sig = -1;
         why = StringFormat("%s%s: after an earlier close above, this candle closed back below the line by %.0f pts (retracement, price returned)",
                            lt, DoubleToString(L, _Digits), (L - b.close) / _Point);
      } else if(b.close > L && b.low <= L + touch) {
         sig = 1;
         why = StringFormat("%s%s: after an earlier close above, price retraced to within %.0f pts of the line (low %s) and closed %.0f pts above it (line rejected)",
                            lt, DoubleToString(L, _Digits), (b.low - L) / _Point, DoubleToString(b.low, _Digits), (b.close - L) / _Point);
      }
   }
   bool zoneHit = false;
   if(sig != 0 && ZoneBlocks(j, sig, b.close)) {
      zoneHit = true;
      if(g_replayLast) JLine("ZONE_BLOCKED", j, b, "conflict zone: close not yet beyond the opposite-line zone | " + why, sig);
      sig = 0;
      why = "";
   }
   if(sig == 0 && g_lines[j].waitBars >= MathMax(1, InpWaitCandles)) {
      g_lines[j].mitigated = true;
      if(g_replayLast) JLine("WAIT_DROPPED", j, b, zoneHit ? "signal blocked by the conflict zone, line dropped" : "no retracement on the candle after the break: line dropped, no trade");
   }
   return sig;
}

int CountMainPositions()
{
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionGetTicket(i) == 0 || !IsOwnedPositionSelected()) continue;
      if(StringFind(PositionGetString(POSITION_COMMENT), KEY_DD) == 0) continue;
      c++;
   }
   return c;
}

bool SkipSig(const string side, const int j, const string why, const string msg)
{
   PrintFormat("Signal %s skipped: %s | %s", side, msg, why);
   JournalWrite("SKIPPED", side, g_lines[j].upper ? "SELL-line" : "BUY-line", g_lines[j].price, g_lines[j].state, g_lastBarRates,
                0, 0, 0, 0, 0, 0, "", 0, msg + " | " + why);
   return false;
}

bool OpenMarket(const bool buy, const int j, const string why)
{
   const string side = buy ? "BUY" : "SELL";
   string allowWhy = "";
   if(!TradingAllowed(allowWhy))               return SkipSig(side, j, why, allowWhy);
   if(InCooldown(buy))                         return SkipSig(side, j, why, "cooldown active");
   if(NettingConflict(!buy))                   return SkipSig(side, j, why, "netting conflict");
   if(CountMainPositions() >= InpMaxOpenMain)  return SkipSig(side, j, why, "max open main positions");

   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0) return false;
   if(InpMaxSpreadPoints > 0 && (ask - bid) / _Point > InpMaxSpreadPoints)
      return SkipSig(side, j, why, StringFormat("spread %.0f pts too wide", (ask - bid) / _Point));
   const double price = buy ? ask : bid;
   double sl = 0.0, tp = 0.0;
   if(InpSLPoints > 0) sl = NormalizeToTick(buy ? price - InpSLPoints * _Point : price + InpSLPoints * _Point);
   if(InpTPPoints > 0) tp = NormalizeToTick(buy ? price + InpTPPoints * _Point : price - InpTPPoints * _Point);
   const double md = MinStopDist();
   if(sl > 0.0 && MathAbs(price - sl) <= md) return SkipSig(side, j, why, "SL inside min stop distance");
   if(tp > 0.0 && MathAbs(price - tp) <= md) return SkipSig(side, j, why, "TP inside min stop distance");

   const double vol = RoundVolDown(InpLot);
   if(vol <= 0.0) return SkipSig(side, j, why, "invalid volume after rounding");
   if(!RiskOk(buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, vol, price, "Market " + side)) return SkipSig(side, j, why, "not enough free margin");

   const string cmt = "V3_" + (buy ? "B_" : "S_") + IntegerToString((long)g_lines[j].startTime);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   const bool called = buy ? g_trade.Buy(vol, _Symbol, price, sl, tp, cmt)
                           : g_trade.Sell(vol, _Symbol, price, sl, tp, cmt);
   if(TradeOk(called)) {
      long pid = 0;
      const ulong dl = g_trade.ResultDeal();
      if(dl > 0 && HistoryDealSelect(dl)) pid = HistoryDealGetInteger(dl, DEAL_POSITION_ID);
      const string full = StringFormat("%s | spread %.0f pts | SL %d pts, TP %d pts from entry",
                                       why, (ask - bid) / _Point, InpSLPoints, InpTPPoints);
      PrintFormat("LIVE %s at %s | %s", side, DoubleToString(g_trade.ResultPrice(), _Digits), full);
      JournalWrite("ENTRY", side, g_lines[j].upper ? "SELL-line" : "BUY-line", g_lines[j].price, g_lines[j].state, g_lastBarRates,
                   g_trade.ResultPrice(), sl, tp, vol, pid, dl, "", 0, full);
      return true;
   }
   LogFail("Market " + side);
   JournalWrite("ORDER_FAILED", side, g_lines[j].upper ? "SELL-line" : "BUY-line", g_lines[j].price, g_lines[j].state, g_lastBarRates,
                price, sl, tp, vol, 0, 0, "", 0, StringFormat("retcode %u %s | %s", g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription(), why));
   return false;
}

void ExecuteSignals(const datetime barTime)
{
   if(g_nSig == 0 || g_lastExecBar == barTime) return;
   g_lastExecBar = barTime;

   int ib = -1, is = -1;
   for(int k = 0; k < g_nSig; k++) {
      if(g_sigD[k] > 0 && ib < 0) ib = k;
      if(g_sigD[k] < 0 && is < 0) is = k;
   }
   if(ib >= 0 && is >= 0) {
      Print("Conflicting BUY and SELL signals on the same closed bar: no trade, lines kept.");
      JournalWrite("SKIPPED", "", "", 0, 0, g_lastBarRates, 0, 0, 0, 0, 0, 0, "", 0,
                   "conflicting BUY and SELL signals on the same closed bar | BUY: " + g_sigWhy[ib] + " | SELL: " + g_sigWhy[is]);
      return;
   }
   const int k0 = (ib >= 0) ? ib : is;
   const bool buy = (g_sigD[k0] > 0);
   OpenMarket(buy, g_sigJ[k0], g_sigWhy[k0]);
   for(int k = 0; k < g_nSig; k++) MarkUsed(g_sigJ[k]);
}

//+------------------------------------------------------------------+
//| Rebuild MA + inflection lines from history (closed bars only)     |
//+------------------------------------------------------------------+
bool Rebuild()
{
   const int baseWarm   = WarmBars(InpBaseMethod, g_basePeriod);
   const int smoothWarm = WarmBars(InpSmoothMethod, g_smoothPeriod);
   const int extra      = g_sameTf ? baseWarm + smoothWarm : smoothWarm;

   MqlRates cr[];
   ArraySetAsSeries(cr, false);
   const int n = CopyRates(_Symbol, _Period, 0, MathMax(InpMaxBars, 100) + extra, cr);
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
      const long warm = (long)(baseWarm + g_basePeriod * 4 + 50) * g_tfSec * 8 / 5;
      const datetime st = (datetime)((long)cr[0].time - warm);
      m = CopyRates(_Symbol, g_tf, st, cr[n - 1].time, hr);
      if(m < 2) return false;
      ArrayResize(hp, m);
      ArrayResize(ht, m);
      for(int i = 0; i < m; i++) { hp[i] = PriceFromRates(hr[i]); ht[i] = hr[i].time; }
   }

   double base[];
   MaSeries(InpBaseMethod, g_basePeriod, hp, m, base);
   BlankWarmup(base, m, baseWarm);        // raw start-up values must not become pivots

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
   BlankWarmup(ma, n, smoothWarm);

   //--- scan closed bars (n-1 is the forming bar)
   ArrayResize(g_lines, 0);
   const int last = n - 2;
   int pPeak = -1, pTrough = -1, below = 0, above = 0;
   int lastType = 0;
   double lastVal = 0.0;
   int rejected = 0;
   const double minSwing = SwingMinPrice();
   g_nSig = 0;
   ArrayResize(g_sigJ, 0);
   ArrayResize(g_sigD, 0);
   ArrayResize(g_sigWhy, 0);

   for(int i = 2; i <= last; i++) {
      if(ma[i] == EMPTY_VALUE) { below = 0; above = 0; pPeak = -1; pTrough = -1; lastType = 0; continue; }

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
         if(lastType == -1 && minSwing > 0.0 && ma[pPeak] - lastVal < minSwing) {
            rejected++;
         } else {
            AddInflection(cr[pPeak].time, ma[pPeak] + InpLineOffsetPoints * _Point, true, cr[i].time);
            lastVal  = (lastType == 1) ? MathMax(lastVal, ma[pPeak]) : ma[pPeak];
            lastType = 1;
         }
         pPeak = -1;
      }
      if(pTrough != -1 && above >= InpPivotCandles) {
         if(lastType == 1 && minSwing > 0.0 && lastVal - ma[pTrough] < minSwing) {
            rejected++;
         } else {
            AddInflection(cr[pTrough].time, ma[pTrough] - InpLineOffsetPoints * _Point, false, cr[i].time);
            lastVal  = (lastType == -1) ? MathMin(lastVal, ma[pTrough]) : ma[pTrough];
            lastType = -1;
         }
         pTrough = -1;
      }

      g_replayLast = (i == last);
      if(i == last) g_lastBarRates = cr[i];

      for(int j = 0; j < ArraySize(g_lines); j++) {
         if(!g_lines[j].alive || g_lines[j].mitigated) continue;
         if(cr[i].time <= g_lines[j].createTime) continue;
         string why = "";
         const int sg = StepLine(j, cr[i], why);
         if(sg == 0) continue;
         if(i == last) {
            const int n0 = g_nSig;
            ArrayResize(g_sigJ, n0 + 1);
            ArrayResize(g_sigD, n0 + 1);
            ArrayResize(g_sigWhy, n0 + 1);
            g_sigJ[n0] = j;
            g_sigD[n0] = sg;
            g_sigWhy[n0] = why;
            g_nSig = n0 + 1;
         } else
            MarkUsed(j);
      }
   }
   g_replayLast = false;

   SelectRepresentatives();
   g_linesValid = true;
   PruneRecs();

   if(rejected != g_rejPrinted) {
      PrintFormat("Ranging filter: %d pivot(s) ignored (min swing %.0f pts) in the analysed window.", rejected, minSwing / _Point);
      g_rejPrinted = rejected;
   }
   ExecuteSignals(cr[last].time);

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
      const bool rep = g_lines[i].rep;
      const bool watching = (g_lines[i].state != 0);
      const color clr = watching ? InpWatchColor : (rep ? InpActiveColor : InpDimColor);
      const string name = PFX_LN + IntegerToString(drawn);
      ObjectCreate(0, name, OBJ_TREND, 0, g_lines[i].startTime, g_lines[i].price,
                   g_lines[i].startTime + g_tfSec, g_lines[i].price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, rep ? STYLE_SOLID : STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);

      if(rep || watching) {
         const string lbl = name + "_L";
         ObjectCreate(0, lbl, OBJ_TEXT, 0, anchor, g_lines[i].price);
         ObjectSetString(0, lbl, OBJPROP_TEXT, (g_lines[i].upper ? " S " : " B ") + (watching ? "WAIT " : "") + DoubleToString(g_lines[i].price, _Digits));
         ObjectSetInteger(0, lbl, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, lbl, OBJPROP_FONTSIZE, 8);
         ObjectSetInteger(0, lbl, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
         ObjectSetInteger(0, lbl, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, lbl, OBJPROP_HIDDEN, true);
      }
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

double FreezeDist()
{
   return (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
}

// True if a price level is inside the broker's freeze zone (cannot be modified/deleted now)
bool Frozen(const double level, const double bid, const double ask)
{
   const double fz = FreezeDist();
   if(fz <= 0.0 || level <= 0.0) return false;
   return (MathAbs(level - bid) <= fz || MathAbs(level - ask) <= fz);
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

bool IsOwnedOrderSelected()
{
   return (OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagic);
}

bool IsOwnedPositionSelected()
{
   return (PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic);
}

// Free-margin check before sending any new order
bool RiskOk(const ENUM_ORDER_TYPE type, const double vol, const double price, const string what)
{
   double margin = 0.0;
   if(!OrderCalcMargin(type, _Symbol, vol, price, margin)) return true;   // cannot evaluate: do not block
   const double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(margin > freeMargin) {
      PrintFormat("%s skipped: required margin %.2f > free margin %.2f.", what, margin, freeMargin);
      return false;
   }
   return true;
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
   return (g_lines[j].upper ? KEY_SELL : KEY_BUY) + IntegerToString((long)g_lines[j].startTime);
}

bool IsLineKey(const string s)
{
   return (StringFind(s, KEY_SELL) == 0 || StringFind(s, KEY_BUY) == 0);
}

// Index of the ACTIVE line with this key, or -1
int FindLineByKey(const string key)
{
   for(int j = 0; j < ArraySize(g_lines); j++) {
      if(!g_lines[j].alive || g_lines[j].mitigated) continue;
      if(LineKey(j) == key) return j;
   }
   return -1;
}

// Drop records of lines that no longer exist and have no live order/position
void PruneRecs()
{
   for(int i = ArraySize(g_recs) - 1; i >= 0; i--) {
      if(FindLineByKey(g_recs[i].key) >= 0) continue;
      if(CommentExists(g_recs[i].key)) continue;
      const int last = ArraySize(g_recs) - 1;
      if(i != last) g_recs[i] = g_recs[last];
      ArrayResize(g_recs, last);
   }
}

//+------------------------------------------------------------------+
//| Pending orders                                                    |
//+------------------------------------------------------------------+
int CountPendingOwned()
{
   int c = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      if(OrderGetTicket(i) == 0 || !IsOwnedOrderSelected()) continue;
      c++;
   }
   return c;
}

bool CommentExists(const string key)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      if(OrderGetTicket(i) == 0 || !IsOwnedOrderSelected()) continue;
      if(StringFind(OrderGetString(ORDER_COMMENT), key) >= 0) return true;
   }
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionGetTicket(i) == 0 || !IsOwnedPositionSelected()) continue;
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

// Netting accounts: an opposite-direction fill would close/reduce the open
// position instead of opening a new one. Block those orders.
bool NettingConflict(const bool sell)
{
   if(g_hedging) return false;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionGetTicket(i) == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;   // any position on the symbol counts on netting
      const bool posBuy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      if(posBuy == sell) return true;
   }
   return false;
}

void PlaceOrders()
{
   if(!g_linesValid) return;

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
      if(!g_lines[j].rep) continue;            // only the group representative carries an order

      const bool sell = g_lines[j].upper;
      if(InCooldown(!sell)) continue;          // this direction is in cooldown after an SL
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
      if(NettingConflict(sell)) continue;

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

      const int idx = EnsureRec(key);
      if(!RiskOk(sell ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_BUY_LIMIT, vol, price, "Limit " + key)) {
         g_recs[idx].nextTry = now + 60;
         continue;
      }

      g_trade.SetTypeFilling(ORDER_FILLING_RETURN);
      bool called = sell ? g_trade.SellLimit(vol, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, key)
                         : g_trade.BuyLimit (vol, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, key);

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

// Deletes an EA pending order and re-arms its line so the order can be
// placed again if price returns before the line is mitigated.
bool DeleteOwnedOrder(const ulong tk)
{
   if(!OrderSelect(tk)) return false;
   const string cmt = OrderGetString(ORDER_COMMENT);   // read before deleting
   const double op  = OrderGetDouble(ORDER_PRICE_OPEN);
   if(Frozen(op, SymbolInfoDouble(_Symbol, SYMBOL_BID), SymbolInfoDouble(_Symbol, SYMBOL_ASK)))
      return false;                                     // inside freeze zone: try again next tick
   if(!TradeOk(g_trade.OrderDelete(tk))) {
      LogFail("OrderDelete #" + IntegerToString((long)tk));
      return false;
   }
   const int ri = FindRec(cmt);
   if(ri >= 0) {
      g_recs[ri].sent = false;
      g_recs[ri].nextTry = 0;
   }
   return true;
}

// Deletes a pending order once the market has moved away from it.
void CancelFarOrders()
{
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0) return;
   const double away = InpCancelAwayPoints * _Point;

   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      const ulong tk = OrderGetTicket(i);
      if(tk == 0 || !IsOwnedOrderSelected()) continue;

      const ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      const double op = OrderGetDouble(ORDER_PRICE_OPEN);

      bool del = false;
      if(ot == ORDER_TYPE_SELL_LIMIT && ask <= op - away - 1e-9) del = true;
      if(ot == ORDER_TYPE_BUY_LIMIT  && bid >= op + away + 1e-9) del = true;

      if(del) DeleteOwnedOrder(tk);
   }
}

// Deletes pending orders whose line is no longer an active group
// representative (a better line joined the group, the line was mitigated,
// or it fell out of the analysed history window).
void CancelSupersededOrders()
{
   if(!g_linesValid) return;
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      const ulong tk = OrderGetTicket(i);
      if(tk == 0 || !IsOwnedOrderSelected()) continue;
      const string cmt = OrderGetString(ORDER_COMMENT);
      if(!IsLineKey(cmt)) continue;                     // comment altered by broker: leave it alone
      const int j = FindLineByKey(cmt);
      if(j >= 0 && g_lines[j].rep) continue;
      if(DeleteOwnedOrder(tk))
         PrintFormat("Order #%I64u (%s) removed: line superseded or gone.", tk, cmt);
   }
}

//+------------------------------------------------------------------+
//| Partials                                                          |
//+------------------------------------------------------------------+
int FindState(const ulong ticket)
{
   for(int i = 0; i < ArraySize(g_ps); i++)
      if(g_ps[i].ticket == ticket) return i;
   return -1;
}

// Re-counts partials already taken (winning / losing side) from the deal history.
// Called on tracking start and whenever a new milestone is due, so the counter
// always reflects what the server really executed (async fills, restarts).
void SyncPartialsFromHistory(const int i)
{
   if(!HistorySelectByPosition(g_ps[i].posId)) return;
   int outsWin = 0, outsLoss = 0;
   const int total = HistoryDealsTotal();
   for(int d = 0; d < total; d++) {
      const ulong dk = HistoryDealGetTicket(d);
      if(dk == 0) continue;
      const ENUM_DEAL_ENTRY e = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dk, DEAL_ENTRY);
      if(e != DEAL_ENTRY_OUT && e != DEAL_ENTRY_OUT_BY) continue;
      const double px = HistoryDealGetDouble(dk, DEAL_PRICE);
      const bool win = g_ps[i].isBuy ? (px > g_ps[i].entry) : (px < g_ps[i].entry);
      if(win) outsWin++; else outsLoss++;
   }
   g_ps[i].partials   = MathMin(outsWin,  MathMax(InpPartials, 0));
   g_ps[i].slPartials = MathMin(outsLoss, MathMax(InpSLPartials, 0));
}

// Rebuilds initial volume / entry / partials taken from the deal history,
// so a restart with an open position continues where it left off.
void RecoverFromHistory(const int i)
{
   const long pid = PositionGetInteger(POSITION_IDENTIFIER);
   if(!HistorySelectByPosition(pid)) return;
   double volIn = 0.0, pxIn = 0.0;
   const int total = HistoryDealsTotal();
   for(int d = 0; d < total; d++) {                       // first pass: entry
      const ulong dk = HistoryDealGetTicket(d);
      if(dk == 0) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(dk, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
      const double v = HistoryDealGetDouble(dk, DEAL_VOLUME);
      pxIn = (volIn + v > 0.0) ? (pxIn * volIn + HistoryDealGetDouble(dk, DEAL_PRICE) * v) / (volIn + v) : pxIn;
      volIn += v;
   }
   if(volIn > 0.0) {
      g_ps[i].vol0 = volIn;
      if(pxIn > 0.0) g_ps[i].entry = pxIn;
   }
   SyncPartialsFromHistory(i);
}

int EnsureState(const ulong ticket)
{
   int i = FindState(ticket);
   if(i >= 0) return i;
   if(!PositionSelectByTicket(ticket)) return -1;

   i = ArraySize(g_ps);
   ArrayResize(g_ps, i + 1);
   g_ps[i].ticket = ticket;
   g_ps[i].posId  = PositionGetInteger(POSITION_IDENTIFIER);
   g_ps[i].entry  = PositionGetDouble(POSITION_PRICE_OPEN);
   g_ps[i].vol0   = PositionGetDouble(POSITION_VOLUME);
   g_ps[i].isBuy  = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   g_ps[i].partials = 0;
   g_ps[i].slPartials = 0;
   g_ps[i].ddOpened = 0;
   g_ps[i].volWarned = false;
   g_ps[i].partialRetry = 0;

   const double sl = PositionGetDouble(POSITION_SL);
   g_ps[i].beDone = (sl > 0.0 && (g_ps[i].isBuy ? sl >= g_ps[i].entry - 1e-9 : sl <= g_ps[i].entry + 1e-9));

   RecoverFromHistory(i);
   g_ps[i].ddOpened = CountDDFor(ticket);
   PositionSelectByTicket(ticket);   // restore selection after history calls
   PrintFormat("Tracking #%I64u: %s entry %s vol %.2f | TP step %.0f pts, done %d | SL step %.0f pts, done %d | BE %s.",
               ticket, g_ps[i].isBuy ? "BUY" : "SELL", DoubleToString(g_ps[i].entry, _Digits), g_ps[i].vol0,
               PartialStepPts(), g_ps[i].partials, SLPartialStepPts(), g_ps[i].slPartials,
               g_ps[i].beDone ? "done" : "pending");
   DrawPartialLevels(i);
   return i;
}

int DirIndex(const bool isBuy) { return isBuy ? 0 : 1; }

bool InCooldown(const bool isBuy)
{
   return (TimeCurrent() < g_cooldownUntil[DirIndex(isBuy)]);
}

void StartCooldown(const bool isBuy, const string why)
{
   if(InpSLCooldownMinutes <= 0) return;
   const datetime until = TimeCurrent() + (datetime)(InpSLCooldownMinutes * 60);
   const int d = DirIndex(isBuy);
   if(until > g_cooldownUntil[d]) g_cooldownUntil[d] = until;
   PrintFormat("Cooldown: no %s trades until %s (%s).", isBuy ? "BUY" : "SELL",
               TimeToString(g_cooldownUntil[d], TIME_DATE | TIME_MINUTES), why);
}

// Looks at the closed position's history: was the final exit a stop-loss (or a loss)?
void CheckClosedForCooldown(const int i)
{
   const ulong ticket = g_ps[i].ticket;
   if(!HistorySelectByPosition(g_ps[i].posId)) return;
   bool slHit = false;
   double pnl = 0.0;
   for(int d = 0; d < HistoryDealsTotal(); d++) {
      const ulong dk = HistoryDealGetTicket(d);
      if(dk == 0) continue;
      const ENUM_DEAL_ENTRY e = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dk, DEAL_ENTRY);
      if(e != DEAL_ENTRY_OUT && e != DEAL_ENTRY_OUT_BY) continue;
      pnl += HistoryDealGetDouble(dk, DEAL_PROFIT) + HistoryDealGetDouble(dk, DEAL_SWAP) + HistoryDealGetDouble(dk, DEAL_COMMISSION);
      if((ENUM_DEAL_REASON)HistoryDealGetInteger(dk, DEAL_REASON) == DEAL_REASON_SL) slHit = true;
   }
   if(slHit)
      StartCooldown(g_ps[i].isBuy, "SL hit on #" + IntegerToString((long)ticket));
   else if(InpCooldownOnAnyLoss && pnl < 0.0)
      StartCooldown(g_ps[i].isBuy, StringFormat("#%I64u closed in loss %.2f", ticket, pnl));
}

// During a cooldown, remove pending orders in that direction (re-placed afterwards if price is still near)
void CancelCooldownOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      const ulong tk = OrderGetTicket(i);
      if(tk == 0 || !IsOwnedOrderSelected()) continue;
      const ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      const bool isBuy = (ot == ORDER_TYPE_BUY_LIMIT || ot == ORDER_TYPE_BUY_STOP || ot == ORDER_TYPE_BUY);
      if(!InCooldown(isBuy)) continue;
      if(DeleteOwnedOrder(tk))
         PrintFormat("Order #%I64u removed: %s side in cooldown.", tk, isBuy ? "BUY" : "SELL");
   }
}

void CleanupStates()
{
   for(int i = ArraySize(g_ps) - 1; i >= 0; i--) {
      if(!PositionSelectByTicket(g_ps[i].ticket)) {
         CheckClosedForCooldown(i);
         DeletePartialLevels(g_ps[i].ticket);
         const int last = ArraySize(g_ps) - 1;
         if(i != last) g_ps[i] = g_ps[last];
         ArrayResize(g_ps, last);
      }
   }
}

// Distance between partial levels: TP / N  (1400 / 7 = 200)
double PartialStepPts()
{
   if(InpPartials < 1 || InpTPPoints <= 0) return 0.0;
   return (double)InpTPPoints / (double)InpPartials;
}

// Distance between SL partial levels: SL / N_sl  (700 / 7 = 100)
double SLPartialStepPts()
{
   if(!g_slPartialsOn || InpSLPartials < 1 || InpSLPoints <= 0) return 0.0;
   return (double)InpSLPoints / (double)InpSLPartials;
}

// Closes one piece of `pct` % of the initial volume. Returns true on success.
bool ClosePiece(const int si, const ulong ticket, const double pct, const string tag, const double distPts, const double level)
{
   const double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(!PositionSelectByTicket(ticket)) return false;
   const double curVol = PositionGetDouble(POSITION_VOLUME);
   const double raw    = g_ps[si].vol0 * pct / 100.0;
   double piece        = RoundVolDown(raw);
   if(piece <= 0.0) {
      piece = vmin;   // configured % is below the broker's minimum lot: use the minimum lot
      if(!g_ps[si].volWarned) {
         PrintFormat("%s partial %.1f%% of %.2f = %.4f is below min lot %.2f; using min lot.", tag, pct, g_ps[si].vol0, raw, vmin);
         g_ps[si].volWarned = true;
      }
   }
   if(curVol - piece < vmin - 1e-12) {
      if(!g_ps[si].volWarned) {
         PrintFormat("%s partial skipped on #%I64u: closing %.2f would leave less than min lot (vol %.2f).", tag, ticket, piece, curVol);
         g_ps[si].volWarned = true;
      }
      return false;
   }
   g_trade.SetTypeFillingBySymbol(_Symbol);
   if(TradeOk(g_trade.PositionClosePartial(ticket, piece))) {
      PrintFormat("%s partial on #%I64u: closed %.2f lots at %+.0f pts (level %.0f).", tag, ticket, piece, distPts, level);
      return true;
   }
   LogFail(tag + " partial close #" + IntegerToString((long)ticket));
   g_ps[si].partialRetry = TimeCurrent() + 5;
   return false;
}

// SL partials: k (1..N_sl) triggers at entry -/+ k * (SL / N_sl) against the trade.
void TakeSLPartials(const int si, const ulong ticket, const double profitPts)
{
   if(!g_slPartialsOn || InpSLPartials < 1 || InpSLPartialPercent <= 0.0 || InpSLPoints <= 0) return;
   if(TimeCurrent() < g_ps[si].partialRetry) return;

   const double step = SLPartialStepPts();
   const double lossPts = -profitPts;
   if(lossPts < step * (g_ps[si].slPartials + 1)) return;   // nothing due

   SyncPartialsFromHistory(si);
   int guard = 0;
   bool any = false;
   while(g_ps[si].slPartials < InpSLPartials && guard++ < InpSLPartials) {
      const double milestone = step * (g_ps[si].slPartials + 1);
      if(lossPts < milestone) break;
      if(!ClosePiece(si, ticket, InpSLPartialPercent, "SL", profitPts, -milestone)) break;
      g_ps[si].slPartials++;
      any = true;
   }
   if(any) DrawPartialLevels(si);
}

//+------------------------------------------------------------------+
//| Per-trade partial level lines (dark gray)                         |
//| dotted = pending, solid = taken. SL-side levels are dashed.        |
//+------------------------------------------------------------------+
string PartialObjName(const ulong ticket, const string side, const int k)
{
   return PFX_PT + IntegerToString((long)ticket) + "_" + side + IntegerToString(k);
}

void DrawOneLevel(const string name, const datetime t0, const double price, const bool taken, const bool slSide, const string text)
{
   if(ObjectFind(0, name) < 0)
      if(!ObjectCreate(0, name, OBJ_TREND, 0, t0, price, t0 + g_chartSec, price)) return;
   ObjectSetDouble (0, name, OBJPROP_PRICE, 0, price);
   ObjectSetDouble (0, name, OBJPROP_PRICE, 1, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t0);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t0 + g_chartSec);
   ObjectSetInteger(0, name, OBJPROP_COLOR, InpPartialColor);
   ObjectSetInteger(0, name, OBJPROP_STYLE, taken ? STYLE_SOLID : (slSide ? STYLE_DASH : STYLE_DOT));
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetString (0, name, OBJPROP_TOOLTIP, text);
   ObjectSetString (0, name, OBJPROP_TEXT, text);
}

void DrawPartialLevels(const int si)
{
   if(!g_drawVisuals || !InpDrawPartials) return;
   const ulong ticket = g_ps[si].ticket;
   if(!PositionSelectByTicket(ticket)) return;
   const datetime t0 = (datetime)PositionGetInteger(POSITION_TIME);
   const bool isBuy  = g_ps[si].isBuy;
   const double entry = g_ps[si].entry;

   const double stepTP = PartialStepPts();
   if(stepTP > 0.0) {
      for(int k = 1; k <= InpPartials; k++) {
         const double lvl = isBuy ? entry + k * stepTP * _Point : entry - k * stepTP * _Point;
         DrawOneLevel(PartialObjName(ticket, "T", k), t0, lvl, k <= g_ps[si].partials, false,
                      StringFormat("#%I64u TP partial %d/%d (+%.0f pts)", ticket, k, InpPartials, k * stepTP));
      }
   }
   const double stepSL = SLPartialStepPts();
   if(stepSL > 0.0) {
      for(int k = 1; k <= InpSLPartials; k++) {
         const double lvl = isBuy ? entry - k * stepSL * _Point : entry + k * stepSL * _Point;
         DrawOneLevel(PartialObjName(ticket, "S", k), t0, lvl, k <= g_ps[si].slPartials, true,
                      StringFormat("#%I64u SL partial %d/%d (-%.0f pts)", ticket, k, InpSLPartials, k * stepSL));
      }
   }
   ChartRedraw(0);
}

void DeletePartialLevels(const ulong ticket)
{
   if(!g_drawVisuals) return;
   ObjectsDeleteAll(0, PFX_PT + IntegerToString((long)ticket) + "_");
}

// Takes EVERY partial that is due at the current price (catches up after gaps).
// Partial k (1..N) triggers at entry +/- k * step.
void TakePartials(const int si, const ulong ticket, const double profitPts)
{
   if(InpPartials < 1 || InpPartialPercent <= 0.0 || InpTPPoints <= 0) return;
   if(TimeCurrent() < g_ps[si].partialRetry) return;

   const double step = PartialStepPts();
   if(profitPts < step * (g_ps[si].partials + 1)) return;   // nothing due

   SyncPartialsFromHistory(si);                              // trust the server, not the counter
   int guard = 0;
   bool any = false;
   while(g_ps[si].partials < InpPartials && guard++ < InpPartials) {
      const double milestone = step * (g_ps[si].partials + 1);
      if(profitPts < milestone) break;
      if(!ClosePiece(si, ticket, InpPartialPercent, "TP", profitPts, milestone)) break;
      g_ps[si].partials++;
      any = true;
   }
   if(any) DrawPartialLevels(si);
}

void ManagePositions()
{
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      const ulong tk = PositionGetTicket(i);
      if(tk == 0 || !IsOwnedPositionSelected()) continue;
      const int si = EnsureState(tk);
      if(si < 0) continue;
      const double profitPts = (g_ps[si].isBuy ? (bid - g_ps[si].entry) : (g_ps[si].entry - ask)) / _Point;
      const bool waitingWorst = (InpDDWorstMode == DDW_CLOSE_AT_GREEN && IsWorstEntry(tk));
      if(!waitingWorst) {
         TakePartials(si, tk, profitPts);   // winning side (runner / stand-alone trades only)
      }
      TakeSLPartials(si, tk, profitPts);    // losing side (off while DD is enabled)
      if(!waitingWorst) MoveToBreakEven(si, tk, profitPts, bid, ask);
   }
   CleanupStates();
}

// SL to entry (+/- buffer) once the trade is InpBEPoints in profit
void MoveToBreakEven(const int si, const ulong ticket, const double profitPts, const double bid, const double ask)
{
   if(InpBEPoints <= 0 || g_ps[si].beDone) return;
   if(profitPts < InpBEPoints) return;
   if(!PositionSelectByTicket(ticket)) return;

   const bool   isBuy = g_ps[si].isBuy;
   const double entry = g_ps[si].entry;
   const double sl    = PositionGetDouble(POSITION_SL);
   const double tp    = PositionGetDouble(POSITION_TP);
   if(Frozen(sl, bid, ask) || Frozen(tp, bid, ask)) return;

   const double buf   = MathMax(0, InpBEOffsetPoints) * _Point;
   const double newSL = NormalizeToTick(isBuy ? entry + buf : entry - buf);
   const bool already = (sl > 0.0 && (isBuy ? sl >= newSL - 1e-9 : sl <= newSL + 1e-9));
   if(already) { g_ps[si].beDone = true; return; }

   const double md = MinStopDist();
   const bool distOk = isBuy ? (bid - newSL > md) : (newSL - ask > md);
   if(!distOk) return;   // too close right now, retry next tick

   if(TradeOk(g_trade.PositionModify(ticket, newSL, tp))) {
      g_ps[si].beDone = true;
      PrintFormat("Break-even on #%I64u: SL -> %s at +%.0f pts.", ticket, DoubleToString(newSL, _Digits), profitPts);
      if(InpDDSyncSLOnBE && IsLatestOfGroup(ticket)) SyncGroupSL(ticket, newSL, bid, ask);
   } else LogFail("Break-even #" + IntegerToString((long)ticket));
}

//+------------------------------------------------------------------+
//| Drawdown (DD) entries                                             |
//+------------------------------------------------------------------+
void AddDDLink(const ulong dd, const ulong anchor)
{
   if(dd == 0) return;
   for(int i = 0; i < ArraySize(g_ddLinks); i++) if(g_ddLinks[i].dd == dd) { g_ddLinks[i].anchor = anchor; return; }
   const int n = ArraySize(g_ddLinks);
   ArrayResize(g_ddLinks, n + 1);
   g_ddLinks[n].dd = dd;
   g_ddLinks[n].anchor = anchor;
}

void PruneDDLinks()
{
   for(int i = ArraySize(g_ddLinks) - 1; i >= 0; i--) {
      if(PositionSelectByTicket(g_ddLinks[i].dd)) continue;
      const int last = ArraySize(g_ddLinks) - 1;
      if(i != last) g_ddLinks[i] = g_ddLinks[last];
      ArrayResize(g_ddLinks, last);
   }
}

// Main-order ticket a position belongs to: in-memory link first, then
// "HTF_DD<n>_<ticket>" comment, otherwise its own ticket (= a main order)
ulong AnchorFor(const ulong own, const string cmt)
{
   for(int i = 0; i < ArraySize(g_ddLinks); i++) if(g_ddLinks[i].dd == own) return g_ddLinks[i].anchor;
   if(StringFind(cmt, KEY_DD) != 0) return own;
   const int p = StringFind(cmt, "_", StringLen(KEY_DD));
   if(p < 0) return own;
   const long t = StringToInteger(StringSubstr(cmt, p + 1));
   return (t > 0) ? (ulong)t : own;
}

// Number of open DD entries that belong to the given first-order ticket
int CountDDFor(const ulong anchor)
{
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      const ulong tk = PositionGetTicket(i);
      if(tk == 0 || !IsOwnedPositionSelected()) continue;
      if(tk == anchor) continue;
      if(AnchorFor(tk, PositionGetString(POSITION_COMMENT)) == anchor) c++;
   }
   return c;
}

struct SPosInfo {
   ulong    ticket;
   datetime time;
   double   entry;
   double   net;      // profit + swap + commission so far
   bool     isBuy;
   ulong    anchor;
};

// Commission booked so far on a position (from its deals)
double PositionCommission(const long posId)
{
   if(!HistorySelectByPosition(posId)) return 0.0;
   double c = 0.0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--) {
      const ulong dk = HistoryDealGetTicket(i);
      if(dk != 0) c += HistoryDealGetDouble(dk, DEAL_COMMISSION);
   }
   return c;
}

int CollectOwned(const bool buy, SPosInfo &out[])
{
   ArrayResize(out, 0);
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      const ulong tk = PositionGetTicket(i);
      if(tk == 0 || !IsOwnedPositionSelected()) continue;
      const bool isBuy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      if(isBuy != buy) continue;
      ArrayResize(out, c + 1);
      out[c].ticket = tk;
      out[c].time   = (datetime)PositionGetInteger(POSITION_TIME);
      out[c].entry  = PositionGetDouble(POSITION_PRICE_OPEN);
      out[c].isBuy  = isBuy;
      out[c].anchor = AnchorFor(tk, PositionGetString(POSITION_COMMENT));
      const long pid = PositionGetInteger(POSITION_IDENTIFIER);
      out[c].net    = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP) + PositionCommission(pid);
      c++;
   }
   return c;
}

void OpenDD(const int d, const int si, const int level)
{
   const bool buy = (d == 0);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0) return;
   const double md = MinStopDist();
   const double price = buy ? ask : bid;
   const double anchorEntry = g_ps[si].entry;

   double sl = 0.0, tp = 0.0;
   if(InpSLPoints > 0) {
      if(InpDDSLMode == DDSL_SAME_PRICE) {
         double anchorSL = 0.0;
         if(PositionSelectByTicket(g_ps[si].ticket)) anchorSL = PositionGetDouble(POSITION_SL);
         if(anchorSL > 0.0) sl = anchorSL;
         else sl = buy ? anchorEntry - InpSLPoints * _Point : anchorEntry + InpSLPoints * _Point;
      } else {
         sl = buy ? price - InpSLPoints * _Point : price + InpSLPoints * _Point;
      }
      sl = NormalizeToTick(sl);
      const bool distOk = buy ? (bid - sl > md) : (sl - ask > md);
      if(!distOk) {
         PrintFormat("DD entry skipped: SL %s too close to market (min stop distance).", DoubleToString(sl, _Digits));
         g_ddRetry[d] = TimeCurrent() + 30;
         return;
      }
   }
   if(InpTPPoints > 0)
      tp = NormalizeToTick(buy ? price + InpTPPoints * _Point : price - InpTPPoints * _Point);

   const double vol = RoundVolDown(g_ps[si].vol0);   // same lot as the first order
   if(vol <= 0.0) return;

   const string cmt = KEY_DD + IntegerToString(level) + "_" + IntegerToString((long)g_ps[si].ticket);
   if(!RiskOk(buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, vol, price, "DD entry " + cmt)) {
      g_ddRetry[d] = TimeCurrent() + 60;
      return;
   }

   g_trade.SetTypeFillingBySymbol(_Symbol);
   const bool called = buy ? g_trade.Buy(vol, _Symbol, price, sl, tp, cmt)
                           : g_trade.Sell(vol, _Symbol, price, sl, tp, cmt);
   if(TradeOk(called)) {
      g_ps[si].ddOpened = level;
      ulong ddTicket = g_trade.ResultOrder();
      const ulong deal = g_trade.ResultDeal();
      if(deal > 0 && HistoryDealSelect(deal)) ddTicket = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      AddDDLink(ddTicket, g_ps[si].ticket);
      PrintFormat("DD entry %d/%d opened as #%I64u for main #%I64u at %s.", level, InpMaxDDEntries, ddTicket,
                  g_ps[si].ticket, DoubleToString(price, _Digits));
   } else {
      LogFail("DD entry " + cmt);
      g_ddRetry[d] = TimeCurrent() + 30;
   }
}

void ManageDD()
{
   if(!g_hedging || InpMaxDDEntries < 1 || InpDDStepPoints < 1) return;
   if(g_halted || !InSession()) return;
   PruneDDLinks();

   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0) return;

   for(int d = 0; d < 2; d++) {
      const bool buy = (d == 0);
      if(TimeCurrent() < g_ddRetry[d]) continue;
      if(InpCooldownBlocksDD && InCooldown(buy)) continue;

      SPosInfo ps[];
      const int cnt = CollectOwned(buy, ps);
      if(cnt < 1) continue;

      // first order = earliest main (non-DD) position in this direction
      int a = -1;
      for(int k = 0; k < cnt; k++) {
         if(ps[k].anchor != ps[k].ticket) continue;
         if(a < 0 || ps[k].time < ps[a].time || (ps[k].time == ps[a].time && ps[k].ticket < ps[a].ticket)) a = k;
      }
      if(a < 0) continue;

      const int si = EnsureState(ps[a].ticket);
      if(si < 0) continue;

      const int next = g_ps[si].ddOpened + 1;
      if(next > InpMaxDDEntries) continue;

      const double adverse = (buy ? (g_ps[si].entry - bid) : (ask - g_ps[si].entry)) / _Point;
      if(adverse < (double)next * InpDDStepPoints) continue;

      OpenDD(d, si, next);
   }
}

//+------------------------------------------------------------------+
//| Group roles                                                       |
//| latest (newest) entry of a group = runner; all older = "worst"    |
//| entries, ranked by recency (worst 1 = the one just before latest)|
//+------------------------------------------------------------------+
void BuildRoles()
{
   ArrayResize(g_roles, 0);
   if(!g_hedging || InpMaxDDEntries < 1) return;

   for(int d = 0; d < 2; d++) {
      SPosInfo ps[];
      const int cnt = CollectOwned(d == 0, ps);
      if(cnt < 2) continue;

      for(int k = 0; k < cnt; k++) {
         int members = 0, latest = -1;
         for(int m = 0; m < cnt; m++) {
            if(ps[m].anchor != ps[k].anchor) continue;
            members++;
            if(latest < 0 || ps[m].time > ps[latest].time ||
               (ps[m].time == ps[latest].time && ps[m].ticket > ps[latest].ticket)) latest = m;
         }
         if(members < 2) continue;
         const int n = ArraySize(g_roles);
         ArrayResize(g_roles, n + 1);
         g_roles[n].ticket  = ps[k].ticket;
         g_roles[n].anchor  = ps[k].anchor;
         g_roles[n].latest  = (latest == k);
         g_roles[n].members = members;
      }
   }
}

int RoleIndex(const ulong ticket)
{
   for(int i = 0; i < ArraySize(g_roles); i++) if(g_roles[i].ticket == ticket) return i;
   return -1;
}

bool IsWorstEntry(const ulong ticket)
{
   const int r = RoleIndex(ticket);
   return (r >= 0 && !g_roles[r].latest);
}

bool IsLatestOfGroup(const ulong ticket)
{
   const int r = RoleIndex(ticket);
   return (r >= 0 && g_roles[r].latest);
}

// Gives every other member of the runner's group the runner's new SL
void SyncGroupSL(const ulong runner, const double newSL, const double bid, const double ask)
{
   const int r = RoleIndex(runner);
   if(r < 0) return;
   const ulong anchor = g_roles[r].anchor;
   const double md = MinStopDist();

   for(int i = 0; i < ArraySize(g_roles); i++) {
      if(g_roles[i].anchor != anchor || g_roles[i].ticket == runner) continue;
      const ulong tk = g_roles[i].ticket;
      if(!PositionSelectByTicket(tk)) continue;
      const bool isBuy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      const double sl = PositionGetDouble(POSITION_SL);
      const double tp = PositionGetDouble(POSITION_TP);
      if(MathAbs(sl - newSL) < _Point * 0.5) continue;                 // already there
      if(Frozen(sl, bid, ask) || Frozen(tp, bid, ask)) continue;
      const bool distOk = isBuy ? (bid - newSL > md) : (newSL - ask > md);
      if(!distOk) continue;
      if(TradeOk(g_trade.PositionModify(tk, newSL, tp)))
         PrintFormat("Group %I64u: SL of #%I64u synced to runner BE %s.", anchor, tk, DoubleToString(newSL, _Digits));
      else
         LogFail("Sync SL #" + IntegerToString((long)tk));
   }
}

//+------------------------------------------------------------------+
//| Older (worst) entries of a DD group -> closed as soon as green    |
//| Each one is judged on its own net value (profit+swap+commission). |
//| The latest entry is never touched here.                           |
//+------------------------------------------------------------------+
void ManageWorstEntries()
{
   if(!g_hedging || InpMaxDDEntries < 1) return;
   if(InpDDWorstMode != DDW_CLOSE_AT_GREEN) return;
   if(ArraySize(g_roles) == 0) return;
   g_trade.SetTypeFillingBySymbol(_Symbol);

   for(int i = 0; i < ArraySize(g_roles); i++) {
      if(g_roles[i].latest) continue;
      const ulong tk = g_roles[i].ticket;
      if(!PositionSelectByTicket(tk)) continue;
      const long pid = PositionGetInteger(POSITION_IDENTIFIER);
      const double net = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP) + PositionCommission(pid);
      if(net <= InpDDGreenMinUSD) continue;

      if(TradeOk(g_trade.PositionClose(tk)))
         PrintFormat("Group %I64u: worst entry #%I64u closed green (net %.2f).", g_roles[i].anchor, tk, net);
      else
         LogFail("Close worst #" + IntegerToString((long)tk));
   }
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
   g_linesValid = false;
   g_cooldownUntil[0] = 0;
   g_cooldownUntil[1] = 0;
   ArrayResize(g_ddLinks, 0);
   ArrayResize(g_roles, 0);
   g_ddRetry[0] = 0;
   g_ddRetry[1] = 0;

   g_slPartialsOn = InpEnableSLPartials;
   const bool hedgingAcc = ((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
   if(hedgingAcc && InpMaxDDEntries > 0 && InpEnableSLPartials) {
      g_slPartialsOn = false;
      Print("SL partials and DD entries cannot be used together: SL partials are DISABLED while DD entries are enabled.");
   }

   const ENUM_ACCOUNT_MARGIN_MODE mm = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   g_hedging = (mm == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
   if(!g_hedging)
      Print("NETTING account detected: DD entries disabled; opposite-direction entries are blocked while a position is open.");
   g_sessStartMin = ParseHHMM(InpSessionStart);
   g_sessEndMin   = ParseHHMM(InpSessionEnd);
   if(InpUseSession && (g_sessStartMin < 0 || g_sessEndMin < 0)) {
      Print("Session times must be HH:MM, e.g. 08:00 and 20:00.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpSwingATRMult > 0.0) {
      g_atrH = iATR(_Symbol, _Period, MathMax(1, InpSwingATRPeriod));
      if(g_atrH == INVALID_HANDLE) return(INIT_FAILED);
   }
   g_lastExecBar = 0;
   g_nSig = 0;
   g_rejPrinted = -1;
   g_halted = false;
   g_haltReason = "";
   g_dayKey = 0;
   g_nextClose = 0;
   g_csvDelim = (StringLen(InpCsvDelim) > 0) ? (ushort)StringGetCharacter(InpCsvDelim, 0) : (ushort)';';
   g_csvOff = (bool)MQLInfoInteger(MQL_OPTIMIZATION);
   g_csvName = "LiveEA_V0.7_" + _Symbol + "_" + IntegerToString(InpMagic) + ".csv";
   DayRollover();
   JournalWrite("EA_START", "", "", 0, 0, g_noBar, 0, 0, 0, InpLot, 0, 0, "", 0,
                StringFormat("v0.70 | SL %d TP %d | minSwing %d | wait %d candle(s) | retrace %d | conflict zone %d | session %s %s-%s | daily target %.2f loss %.2f (%s, floating %s, close on limit %s)",
                             InpSLPoints, InpTPPoints, InpMinSwingPoints, InpWaitCandles, InpRetraceTouchPoints,
                             InpConflictDistancePoints, InpUseSession ? "on" : "off", InpSessionStart, InpSessionEnd,
                             InpDailyProfitTarget, InpDailyLossLimit, InpLimitMode == LIM_PERCENT ? "percent" : "money",
                             InpLimitIncludeFloating ? "yes" : "no", InpCloseOnLimit ? "yes" : "no"));
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(g_atrH != INVALID_HANDLE) IndicatorRelease(g_atrH);
   Comment("");
   ObjectsDeleteAll(0, PFX_ALL);
}

//+------------------------------------------------------------------+
//| Immediate SL detection: the SL deal itself starts the cooldown,   |
//| even if the position was filled and stopped within one tick.      |
//| Buy SL -> delete all remaining BUY limits, no new BUY orders.     |
//| Sell SL -> same for SELL. The other side is not affected.         |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   RefreshClosedPnl();
   JournalDeal(trans.deal);
   if(InpSLCooldownMinutes <= 0) return;
   const ulong dk = trans.deal;
   if(dk == 0 || !HistoryDealSelect(dk)) return;
   if(HistoryDealGetString(dk, DEAL_SYMBOL) != _Symbol) return;
   if(HistoryDealGetInteger(dk, DEAL_MAGIC) != InpMagic) return;
   const ENUM_DEAL_ENTRY e = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dk, DEAL_ENTRY);
   if(e != DEAL_ENTRY_OUT && e != DEAL_ENTRY_OUT_BY) return;
   if((ENUM_DEAL_REASON)HistoryDealGetInteger(dk, DEAL_REASON) != DEAL_REASON_SL) return;

   // an OUT deal of a BUY position is a SELL deal
   const bool posWasBuy = ((ENUM_DEAL_TYPE)HistoryDealGetInteger(dk, DEAL_TYPE) == DEAL_TYPE_SELL);
   StartCooldown(posWasBuy, "SL deal #" + IntegerToString((long)dk));
   CancelCooldownOrders();
}

//+------------------------------------------------------------------+
void OnTick()
{
   CheckDailyLimits();
   //--- lines / MA: refresh once per new chart bar (retry each tick until data is ready)
   const datetime bar = iTime(_Symbol, _Period, 0);
   if(bar != 0 && bar != g_lastBar) {
      if(Rebuild()) g_lastBar = bar;
   }

   //--- per-tick trade logic
   BuildRoles();               // who is runner / worst entry in each DD group
   ManagePositions();          // partials / BE / cooldown detection
   ManageDD();                 // DD entries against the first order
   ManageWorstEntries();       // close older entries of a DD group as soon as they are green
   CancelCooldownOrders();     // direction in cooldown -> remove its pending orders
}
//+------------------------------------------------------------------+
