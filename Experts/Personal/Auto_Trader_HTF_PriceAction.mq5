//+------------------------------------------------------------------+
//|                                       HTF_BigPair_AutoTrader.mq5  |
//|  EA built on the "HTF Big Candle Pair Zones" engine               |
//|  5 setups per side, partials, BE, trailing, DD entries            |
//|  REQUIRES a HEDGING account (several positions per symbol).       |
//+------------------------------------------------------------------+
#property version   "1.00"
#property description "HTF pair zones + 5 retest/engulf/rejection/sweep/50% setups, with DD basket management."

#include <Trade\Trade.mqh>

//--- enums -----------------------------------------------------------
enum ENUM_MIT_MODE
  {
   MIT_WICK = 0, // Wick
   MIT_BODY = 1  // Body close
  };

enum ENUM_LINE_STYLE_IN
  {
   LS_SOLID = 0,  // Solid
   LS_DASHED = 1, // Dashed
   LS_DOTTED = 2  // Dotted
  };

enum ENUM_DD_MODE
  {
   DD_ON_SIGNAL = 0,   // DD entry on a new same-direction setup
   DD_ON_DISTANCE = 1  // DD entry when price moves against last entry (grid)
  };

enum ENUM_HALF_MODE
  {
   HALF_BODY = 0,  // 50% of breakout candle BODY
   HALF_RANGE = 1  // 50% of breakout candle FULL RANGE
  };

enum ENUM_NOWICK_RULE
  {
   NOWICK_BOTH = 0,   // Invalid if NO wick on both sides
   NOWICK_EITHER = 1  // Invalid if a wick is missing on either side
  };

//--- Inputs: zone engine (same as indicator) ------------------------------
input group "Timeframe"
input ENUM_TIMEFRAMES htf        = PERIOD_H4;  // Higher timeframe (pattern detection)

input group "Big candle definition"
input int      avgLen            = 20;         // Average body length (min 2)
input double   bigMult           = 1.5;        // Min body size (x average body)
input double   minBodyPct        = 60.0;       // Min body % of full range (small wicks)

input group "Pair similarity"
input double   simMin            = 0.6;        // Min size ratio (2nd body / 1st body)
input double   simMax            = 1.7;        // Max size ratio (2nd body / 1st body)
input bool     needOverlap       = true;       // Require bodies to overlap

input group "Patterns"
input bool     showGR            = true;       // Detect Green -> Red
input bool     showRG            = true;       // Detect Red -> Green
input bool     useGap            = true;       // Enforce minimum gap between patterns
input int      minGap            = 4;          // Min gap between patterns (HTF candles)

input group "Lines"
input ENUM_MIT_MODE mitMode      = MIT_WICK;   // Mitigation mode
input bool     keepMit           = true;       // Keep mitigated lines
input bool     extendMit         = true;       // Extend mitigated lines until next pattern
input int      maxActive         = 150;        // Max tracked zones (lines)
input bool     showMid           = true;       // Show midline (create midline zones)
input ENUM_LINE_STYLE_IN lineStyleIn = LS_SOLID;  // High / Low line style
input ENUM_LINE_STYLE_IN midStyleIn  = LS_DOTTED; // Midline style
input int      lineWidth         = 1;          // Line width
input color    colGR             = C'242,54,69';   // Green -> Red line color
input color    colRG             = C'8,153,129';   // Red -> Green line color
input color    colMitFade        = C'120,123,134'; // Mitigated line color
input int      mitAlpha          = 102;        // Mitigated line opacity 0-255
input bool     drawLines         = true;       // Draw zone lines on chart

//--- Inputs: which levels are traded -------------------------------------
input group "Levels to trade"
input bool     tradeMid          = true;       // Trade midline zones
input bool     tradeHigh         = false;      // Trade high-line zones
input bool     tradeLow          = false;      // Trade low-line zones

//--- Inputs: setups -------------------------------------------------------
input group "Setups"
input bool     enableSells       = true;       // Enable SELL trades
input bool     enableBuys        = true;       // Enable BUY trades (mirror of sells)
input bool     setup1            = true;       // 1: Breakout candle + same-direction re-test candle
input bool     setup2            = true;       // 2: Opposite breakout candle + engulfing candle
input bool     setup3            = true;       // 3: Rejection candle without breakout
input bool     setup4            = true;       // 4: Liquidity sweep
input bool     setup5            = true;       // 5: Opposite breakout + close beyond 50% of breakout candle
input int      retestLookback    = 3;          // S1: max candles between breakout and re-test (1-10)
input int      retestTolPts      = 0;          // S1: re-test wick may stop this many points short of level
input int      rejNoBreakBars    = 3;          // S3: previous candles must not have closed beyond level (1-10)
input double   rejWickMult       = 1.0;        // S3: rejection wick >= this x body
input int      sweepLookback     = 5;          // S4: candles whose extreme must be swept (2-20)
input double   sweepWickMult     = 1.0;        // S4: sweep wick >= this x body
input ENUM_HALF_MODE halfMode    = HALF_BODY;  // S5: what "50%" is measured on
input bool     reqSignalDir      = true;       // S1/S3/S4: signal candle must have trade-direction colour

input group "Invalid setup filters"
input int      maxBodyDistPts    = 100;        // Invalid if body-to-level distance > points
input double   dojiBodyPct       = 10.0;       // Doji: body % of range below this = invalid
input ENUM_NOWICK_RULE noWickRule = NOWICK_BOTH; // "Candle with no wicks" rule
input int      noWickTolPts      = 0;          // Wick <= this many points counts as "no wick"
input int      exactTolPts       = 0;          // Body edge within this many points of level = "exactly at level"

//--- Inputs: trade management --------------------------------------------
input group "Trade management"
input double   lotSize           = 0.3;        // Lot size
input int      slPts             = 700;        // Stop loss (points)
input int      tpPts             = 1400;       // Full take profit (points)
input int      partialsN         = 3;          // Number of partial closes
input double   partialPct        = 20.0;       // Each partial = % of REMAINING lot
input int      partialStepPts    = 0;          // Distance between partials (0 = TP / (partials+1))
input int      beTrigPts         = 200;        // Move SL to break-even after (points)
input int      beOffsetPts       = 0;          // Break-even offset (points)
input int      trailStartPts     = 1000;       // After this move: remove TP and start trailing
input int      trailDistPts      = 600;        // Trailing distance (points)
input int      trailStepPts      = 10;         // Min SL improvement per modify (points)

input group "DD entries"
input int      ddMax             = 2;          // Max DD entries per basket
input ENUM_DD_MODE ddMode        = DD_ON_SIGNAL; // DD entry trigger
input int      ddMinDistPts      = 200;        // Min adverse distance from last entry (points)
input bool     ddSameLevels      = false;      // DD entries copy the first entry's SL/TP price levels
input double   ddCloseProfit     = 10.0;       // Close older (worst) entries at this profit ($)

input group "General"
input long     magic             = 770011;     // Magic number
input int      deviationPts      = 30;         // Max slippage (points)
input int      maxSpreadPts      = 0;          // Max spread to enter (0 = off)
input bool     allowBothSides    = true;       // Allow buy and sell baskets at the same time
input bool     oneTradePerZoneDir = true;      // A zone can open only one new basket per direction
input int      warmupBars        = 5000;       // Chart bars used to build zones at start

//--- Types -------------------------------------------------------------------
struct Zone
  {
   long     lineId;
   double   level;
   bool     isHigh;
   bool     isMid;
   bool     mitigated;
   int      birth;
   int      side;
   bool     usedBuy;
   bool     usedSell;
  };

struct PInfo
  {
   ulong    ticket;
   datetime time;
   double   price;
   double   vol;
   double   profit;
   double   sl;
   double   tp;
  };

#define PINE_MAX_LINES 500
#define GUARD_BARS     25

//--- Globals -------------------------------------------------------------------
CTrade   trade;
Zone     g_zones[];
long     g_extLines[];
long     g_reg[];
long     g_lineSeq = 0;

datetime g_hTime[];
int      g_sig[];
double   g_pHi[];
double   g_pLo[];

ENUM_TIMEFRAMES g_htf;
bool     g_ready = false;
bool     g_hasLast = false;
int      g_lastHBar = 0;
datetime g_htfStart = 0;
datetime g_lastProcTime = 0;
datetime g_lastBarTime = 0;
int      g_abs = 0;
string   g_prefix;
ENUM_LINE_STYLE g_lStyle, g_mStyle;
uint     g_fadeARGB;
int      g_ddUsed[2];     // [0] = buy basket, [1] = sell basket
int      g_volDigits = 2;

//+------------------------------------------------------------------+
string LineName(const long id) { return g_prefix + "L" + IntegerToString(id); }

ENUM_LINE_STYLE MapStyle(const ENUM_LINE_STYLE_IN s)
  {
   if(s == LS_DASHED) return STYLE_DASH;
   if(s == LS_DOTTED) return STYLE_DOT;
   return STYLE_SOLID;
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   g_htf = (htf == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : htf;

   if(PeriodSeconds(g_htf) < PeriodSeconds((ENUM_TIMEFRAMES)_Period))
     {
      Print("Higher timeframe must be equal to or higher than the chart timeframe.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(avgLen < 2 || bigMult < 0.5 || minBodyPct < 0 || minBodyPct > 100 ||
      simMin < 0.1 || simMax < 0.1 || minGap < 1 || minGap > 50 ||
      maxActive < 3 || maxActive > 300 || lineWidth < 1 || lineWidth > 4 ||
      retestLookback < 1 || retestLookback > 10 || rejNoBreakBars < 1 || rejNoBreakBars > 10 ||
      sweepLookback < 2 || sweepLookback > 20 || warmupBars < 200)
     {
      Print("Input parameter out of range.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      Print("This EA needs a HEDGING account (separate positions for DD entries / partials).");
      return INIT_FAILED;
     }

   trade.SetExpertMagicNumber(magic);
   trade.SetDeviationInPoints(deviationPts);
   trade.SetTypeFillingBySymbol(_Symbol);

   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   g_volDigits = (step > 0) ? (int)MathMax(0, MathRound(-MathLog10(step))) : 2;

   g_lStyle   = MapStyle(lineStyleIn);
   g_mStyle   = MapStyle(midStyleIn);
   g_fadeARGB = ColorToARGB(colMitFade, (uchar)MathMax(0, MathMin(255, mitAlpha)));
   g_prefix   = StringFormat("HTFEA%d_", (int)(GetMicrosecondCount() % 1000000));

   // restore DD counters after a restart
   PInfo arr[];
   int nb = CollectPositions(POSITION_TYPE_BUY, arr);
   int ns = CollectPositions(POSITION_TYPE_SELL, arr);
   g_ddUsed[0] = (int)MathMax(0, nb - 1);
   g_ddUsed[1] = (int)MathMax(0, ns - 1);

   Warmup();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, g_prefix);
  }

//+------------------------------------------------------------------+
//| Line registry / zone drawing (same engine as the indicator)      |
//+------------------------------------------------------------------+
void RegAdd(const long id)
  {
   int n = ArraySize(g_reg);
   ArrayResize(g_reg, n + 1);
   g_reg[n] = id;
   if(ArraySize(g_reg) > PINE_MAX_LINES)
     {
      ObjectDelete(0, LineName(g_reg[0]));
      int m = ArraySize(g_reg);
      for(int k = 0; k < m - 1; k++)
         g_reg[k] = g_reg[k + 1];
      ArrayResize(g_reg, m - 1);
     }
  }

void RegRemove(const long id)
  {
   int n = ArraySize(g_reg);
   for(int k = n - 1; k >= 0; k--)
      if(g_reg[k] == id)
        {
         for(int j = k; j < n - 1; j++)
            g_reg[j] = g_reg[j + 1];
         ArrayResize(g_reg, n - 1);
         return;
        }
  }

void DeleteLine(const long id)
  {
   if(id == 0) return;
   ObjectDelete(0, LineName(id));
   RegRemove(id);
  }

long CreateLine(const datetime t1, const double level, const datetime t2,
                const color c, const ENUM_LINE_STYLE style)
  {
   if(!drawLines) return 0;
   g_lineSeq++;
   string nm = LineName(g_lineSeq);
   if(ObjectCreate(0, nm, OBJ_TREND, 0, t1, level, t2, level))
     {
      ObjectSetInteger(0, nm, OBJPROP_COLOR, c);
      ObjectSetInteger(0, nm, OBJPROP_STYLE, style);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH, lineWidth);
      ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, true);
      ObjectSetInteger(0, nm, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, nm, OBJPROP_BACK, false);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
     }
   RegAdd(g_lineSeq);
   return g_lineSeq;
  }

void FreezeLine(const long id, const datetime t)
  {
   if(id == 0) return;
   string nm = LineName(id);
   ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, nm, OBJPROP_TIME, 1, t);
  }

void FadeLine(const long id)
  {
   if(id == 0) return;
   ObjectSetInteger(0, LineName(id), OBJPROP_COLOR, g_fadeARGB);
  }

void ZoneRemove(const int idx)
  {
   int n = ArraySize(g_zones);
   for(int k = idx; k < n - 1; k++)
      g_zones[k] = g_zones[k + 1];
   ArrayResize(g_zones, n - 1);
  }

void AddZone(const double level, const bool isHigh, const bool isMid, const color c,
             const datetime startTime, const double refClose, const int barIdx,
             const datetime nowTime)
  {
   long id = CreateLine(startTime, level, nowTime, c, isMid ? g_mStyle : g_lStyle);
   int n = ArraySize(g_zones);
   ArrayResize(g_zones, n + 1);
   g_zones[n].lineId    = id;
   g_zones[n].level     = level;
   g_zones[n].isHigh    = isHigh;
   g_zones[n].isMid     = isMid;
   g_zones[n].mitigated = false;
   g_zones[n].birth     = barIdx;
   g_zones[n].side      = (refClose >= level) ? 1 : -1;
   g_zones[n].usedBuy   = false;
   g_zones[n].usedSell  = false;
   if(ArraySize(g_zones) > maxActive)
      ZoneRemove(0);
  }

void ResetState()
  {
   ObjectsDeleteAll(0, g_prefix);
   ArrayResize(g_zones, 0);
   ArrayResize(g_extLines, 0);
   ArrayResize(g_reg, 0);
   g_lineSeq = 0;
   g_hasLast = false;
   g_lastHBar = 0;
  }

//+------------------------------------------------------------------+
//| HTF pattern detection                                            |
//+------------------------------------------------------------------+
bool LoadHtf(const datetime tEnd)
  {
   MqlRates r[];
   ArraySetAsSeries(r, false);
   int n = CopyRates(_Symbol, g_htf, g_htfStart, tEnd, r);
   if(n <= 0)
      return false;

   ArrayResize(g_hTime, n);
   ArrayResize(g_sig, n);
   ArrayResize(g_pHi, n);
   ArrayResize(g_pLo, n);

   double body[], rng[], sma[];
   bool   bigBull[], bigBear[];
   ArrayResize(body, n);
   ArrayResize(rng, n);
   ArrayResize(sma, n);
   ArrayResize(bigBull, n);
   ArrayResize(bigBear, n);

   for(int h = 0; h < n; h++)
     {
      body[h] = MathAbs(r[h].close - r[h].open);
      rng[h]  = r[h].high - r[h].low;
      g_hTime[h] = r[h].time;
     }
   for(int h = 0; h < n; h++)
     {
      if(h >= avgLen - 1)
        {
         double s = 0.0;
         for(int k = h - avgLen + 1; k <= h; k++)
            s += body[k];
         sma[h] = s / avgLen;
        }
      else
         sma[h] = EMPTY_VALUE;
     }
   for(int h = 0; h < n; h++)
     {
      double ref = (h >= 1) ? sma[h - 1] : EMPTY_VALUE;
      bool isBig = rng[h] > 0 && ref != EMPTY_VALUE &&
                   body[h] >= ref * bigMult &&
                   (body[h] / rng[h] * 100.0) >= minBodyPct;
      bigBull[h] = isBig && r[h].close > r[h].open;
      bigBear[h] = isBig && r[h].close < r[h].open;
     }
   for(int h = 0; h < n; h++)
     {
      g_sig[h] = 0;
      g_pHi[h] = EMPTY_VALUE;
      g_pLo[h] = EMPTY_VALUE;
      if(h < 1)
         continue;

      bool similar = false;
      if(body[h - 1] > 0)
        {
         double ratio = body[h] / body[h - 1];
         similar = (ratio >= simMin && ratio <= simMax);
        }
      double bodyHi  = MathMax(r[h].open, r[h].close);
      double bodyLo  = MathMin(r[h].open, r[h].close);
      double bodyHi1 = MathMax(r[h - 1].open, r[h - 1].close);
      double bodyLo1 = MathMin(r[h - 1].open, r[h - 1].close);
      bool overlap = !needOverlap || (bodyHi > bodyLo1 && bodyLo < bodyHi1);

      bool gr = bigBull[h - 1] && bigBear[h] && similar && overlap;
      bool rg = bigBear[h - 1] && bigBull[h] && similar && overlap;
      g_sig[h] = gr ? 1 : (rg ? 2 : 0);

      g_pHi[h] = MathMax(r[h].high, r[h - 1].high);
      g_pLo[h] = MathMin(r[h].low,  r[h - 1].low);
     }
   return true;
  }

int HtfIndex(const datetime t)
  {
   int n = ArraySize(g_hTime);
   if(n == 0 || t < g_hTime[0])
      return -1;
   int lo = 0, hi = n - 1;
   while(lo < hi)
     {
      int mid = (lo + hi + 1) / 2;
      if(g_hTime[mid] <= t)
         lo = mid;
      else
         hi = mid - 1;
     }
   return lo;
  }

//+------------------------------------------------------------------+
//| Candle validity (invalid setups 1-4 from the brief)              |
//+------------------------------------------------------------------+
bool CandleValid(const MqlRates &r[], const int i, const double L)
  {
   double hi = r[i].high, lo = r[i].low, o = r[i].open, c = r[i].close;
   double rng = hi - lo;
   if(rng <= 0)
      return false;
   double body = MathAbs(c - o);
   if(body / rng * 100.0 < dojiBodyPct)                       // doji
      return false;

   double bodyHi = MathMax(o, c), bodyLo = MathMin(o, c);
   double up = hi - bodyHi, dn = bodyLo - lo;
   double wTol = _Point * 0.5 + noWickTolPts * _Point;
   bool noUp = up < wTol, noDn = dn < wTol;
   if(noWickRule == NOWICK_BOTH ? (noUp && noDn) : (noUp || noDn))   // candle with no wicks
      return false;

   double Ln = NormalizeDouble(L, _Digits);
   double eTol = _Point * 0.5 + exactTolPts * _Point;
   if(MathAbs(o - Ln) < eTol || MathAbs(c - Ln) < eTol)       // body starts/closes exactly at level
      return false;

   double dist = 0.0;
   if(L < bodyLo)      dist = bodyLo - L;
   else if(L > bodyHi) dist = L - bodyHi;
   if(dist > maxBodyDistPts * _Point)                          // body too far from level
      return false;
   return true;
  }

//+------------------------------------------------------------------+
//| SELL setups (signal candle = bar i, just closed)                 |
//+------------------------------------------------------------------+
bool IsBullBreakout(const MqlRates &r[], const int k, const double L)
  { return r[k].close > r[k].open && r[k].open < L && r[k].close > L; }

bool IsBearBreakout(const MqlRates &r[], const int k, const double L)
  { return r[k].close < r[k].open && r[k].open > L && r[k].close < L; }

double HalfLevel(const MqlRates &r[], const int k)
  {
   if(halfMode == HALF_BODY)
      return (r[k].open + r[k].close) / 2.0;
   return (r[k].high + r[k].low) / 2.0;
  }

bool Sell1(const MqlRates &r[], const int i, const double L)   // bearish breakout, bearish re-test
  {
   double bodyHi = MathMax(r[i].open, r[i].close);
   if(reqSignalDir && !(r[i].close < r[i].open)) return false;
   if(!(bodyHi < L)) return false;
   if(r[i].high < L - retestTolPts * _Point) return false;
   for(int k = 1; k <= retestLookback; k++)
     {
      int b = i - k;
      if(!IsBearBreakout(r, b, L)) continue;
      bool ok = true;
      for(int m = b + 1; m < i; m++)
         if(r[m].close >= L) { ok = false; break; }
      if(ok) return true;
     }
   return false;
  }

bool Sell2(const MqlRates &r[], const int i, const double L)   // bullish breakout, bearish engulfing
  {
   int k = i - 1;
   if(!IsBullBreakout(r, k, L)) return false;
   return r[i].close < r[i].open && r[i].open >= r[k].close && r[i].close <= r[k].open;
  }

bool Sell3(const MqlRates &r[], const int i, const double L)   // rejection, no breakout
  {
   double o = r[i].open, c = r[i].close;
   double bodyHi = MathMax(o, c);
   if(reqSignalDir && !(c < o)) return false;
   if(!(bodyHi < L) || r[i].high < L) return false;
   for(int k = 1; k <= rejNoBreakBars; k++)
      if(r[i - k].close >= L) return false;
   double up = r[i].high - bodyHi;
   return up >= rejWickMult * MathAbs(c - o);
  }

bool Sell4(const MqlRates &r[], const int i, const double L)   // liquidity sweep above level
  {
   double o = r[i].open, c = r[i].close;
   double bodyHi = MathMax(o, c);
   if(reqSignalDir && !(c < o)) return false;
   if(!(bodyHi < L) || r[i].high <= L) return false;
   double hh = -DBL_MAX;
   for(int k = 1; k <= sweepLookback; k++)
      hh = MathMax(hh, r[i - k].high);
   if(hh < L) return false;            // there must be liquidity resting at/above the level
   if(r[i].high <= hh) return false;   // and it must be swept
   double up = r[i].high - bodyHi;
   return up >= sweepWickMult * MathAbs(c - o);
  }

bool Sell5(const MqlRates &r[], const int i, const double L)   // bullish breakout, close below 50%
  {
   int k = i - 1;
   if(!IsBullBreakout(r, k, L)) return false;
   return r[i].close < r[i].open && r[i].close < HalfLevel(r, k);
  }

int DetectSell(const MqlRates &r[], const int i, const double L)
  {
   if(i < GUARD_BARS || !CandleValid(r, i, L)) return 0;
   if(setup1 && Sell1(r, i, L)) return 1;
   if(setup2 && Sell2(r, i, L)) return 2;
   if(setup3 && Sell3(r, i, L)) return 3;
   if(setup4 && Sell4(r, i, L)) return 4;
   if(setup5 && Sell5(r, i, L)) return 5;
   return 0;
  }

//+------------------------------------------------------------------+
//| BUY setups (exact mirror)                                        |
//+------------------------------------------------------------------+
bool Buy1(const MqlRates &r[], const int i, const double L)
  {
   double bodyLo = MathMin(r[i].open, r[i].close);
   if(reqSignalDir && !(r[i].close > r[i].open)) return false;
   if(!(bodyLo > L)) return false;
   if(r[i].low > L + retestTolPts * _Point) return false;
   for(int k = 1; k <= retestLookback; k++)
     {
      int b = i - k;
      if(!IsBullBreakout(r, b, L)) continue;
      bool ok = true;
      for(int m = b + 1; m < i; m++)
         if(r[m].close <= L) { ok = false; break; }
      if(ok) return true;
     }
   return false;
  }

bool Buy2(const MqlRates &r[], const int i, const double L)
  {
   int k = i - 1;
   if(!IsBearBreakout(r, k, L)) return false;
   return r[i].close > r[i].open && r[i].open <= r[k].close && r[i].close >= r[k].open;
  }

bool Buy3(const MqlRates &r[], const int i, const double L)
  {
   double o = r[i].open, c = r[i].close;
   double bodyLo = MathMin(o, c);
   if(reqSignalDir && !(c > o)) return false;
   if(!(bodyLo > L) || r[i].low > L) return false;
   for(int k = 1; k <= rejNoBreakBars; k++)
      if(r[i - k].close <= L) return false;
   double dn = bodyLo - r[i].low;
   return dn >= rejWickMult * MathAbs(c - o);
  }

bool Buy4(const MqlRates &r[], const int i, const double L)
  {
   double o = r[i].open, c = r[i].close;
   double bodyLo = MathMin(o, c);
   if(reqSignalDir && !(c > o)) return false;
   if(!(bodyLo > L) || r[i].low >= L) return false;
   double ll = DBL_MAX;
   for(int k = 1; k <= sweepLookback; k++)
      ll = MathMin(ll, r[i - k].low);
   if(ll > L) return false;
   if(r[i].low >= ll) return false;
   double dn = bodyLo - r[i].low;
   return dn >= sweepWickMult * MathAbs(c - o);
  }

bool Buy5(const MqlRates &r[], const int i, const double L)
  {
   int k = i - 1;
   if(!IsBearBreakout(r, k, L)) return false;
   return r[i].close > r[i].open && r[i].close > HalfLevel(r, k);
  }

int DetectBuy(const MqlRates &r[], const int i, const double L)
  {
   if(i < GUARD_BARS || !CandleValid(r, i, L)) return 0;
   if(setup1 && Buy1(r, i, L)) return 1;
   if(setup2 && Buy2(r, i, L)) return 2;
   if(setup3 && Buy3(r, i, L)) return 3;
   if(setup4 && Buy4(r, i, L)) return 4;
   if(setup5 && Buy5(r, i, L)) return 5;
   return 0;
  }

//+------------------------------------------------------------------+
//| Positions / orders                                               |
//+------------------------------------------------------------------+
double NormVol(double v)
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double mn   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step > 0)
      v = MathFloor(v / step + 1e-9) * step;
   v = MathMax(mn, MathMin(mx, v));
   return NormalizeDouble(v, g_volDigits);
  }

int CollectPositions(const long type, PInfo &arr[])
  {
   ArrayResize(arr, 0);
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      if(PositionGetInteger(POSITION_TYPE) != type) continue;
      ArrayResize(arr, n + 1);
      arr[n].ticket = t;
      arr[n].time   = (datetime)PositionGetInteger(POSITION_TIME);
      arr[n].price  = PositionGetDouble(POSITION_PRICE_OPEN);
      arr[n].vol    = PositionGetDouble(POSITION_VOLUME);
      arr[n].profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      arr[n].sl     = PositionGetDouble(POSITION_SL);
      arr[n].tp     = PositionGetDouble(POSITION_TP);
      n++;
     }
   return n;
  }

int LatestIndex(const PInfo &arr[])
  {
   int best = -1;
   for(int i = 0; i < ArraySize(arr); i++)
      if(best < 0 || arr[i].time > arr[best].time ||
         (arr[i].time == arr[best].time && arr[i].ticket > arr[best].ticket))
         best = i;
   return best;
  }

int EarliestIndex(const PInfo &arr[])
  {
   int best = -1;
   for(int i = 0; i < ArraySize(arr); i++)
      if(best < 0 || arr[i].time < arr[best].time ||
         (arr[i].time == arr[best].time && arr[i].ticket < arr[best].ticket))
         best = i;
   return best;
  }

bool OpenTrade(const bool isBuy, const string tag, const bool useBasketLevels)
  {
   if(maxSpreadPts > 0 && SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > maxSpreadPts)
     {
      Print("Entry skipped: spread too high.");
      return false;
     }
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double price = isBuy ? ask : bid;
   double sl = 0, tp = 0;

   bool done = false;
   if(useBasketLevels && ddSameLevels)
     {
      PInfo arr[];
      if(CollectPositions(isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL, arr) > 0)
        {
         int e = EarliestIndex(arr);
         sl = arr[e].sl;
         tp = arr[e].tp;
         done = true;
        }
     }
   if(!done)
     {
      if(slPts > 0) sl = isBuy ? price - slPts * _Point : price + slPts * _Point;
      if(tpPts > 0) tp = isBuy ? price + tpPts * _Point : price - tpPts * _Point;
     }
   sl = (sl > 0) ? NormalizeDouble(sl, _Digits) : 0;
   tp = (tp > 0) ? NormalizeDouble(tp, _Digits) : 0;

   double vol = NormVol(lotSize);
   bool ok = isBuy ? trade.Buy(vol, _Symbol, 0.0, sl, tp, tag)
                   : trade.Sell(vol, _Symbol, 0.0, sl, tp, tag);
   if(!ok)
      PrintFormat("Order failed (%s): retcode=%d %s", tag, trade.ResultRetcode(), trade.ResultRetcodeDescription());
   return ok;
  }

//--- signal -> entry ---------------------------------------------------
void TryEnter(const bool isBuy, const int setup, const int zoneIdx)
  {
   int d = isBuy ? 0 : 1;
   long type = isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   long opp  = isBuy ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;

   PInfo arr[], arrOpp[];
   int n = CollectPositions(type, arr);
   if(!allowBothSides && CollectPositions(opp, arrOpp) > 0)
      return;

   string side = isBuy ? "B" : "S";
   if(n == 0)
     {
      if(oneTradePerZoneDir && (isBuy ? g_zones[zoneIdx].usedBuy : g_zones[zoneIdx].usedSell))
         return;
      g_ddUsed[d] = 0;
      if(OpenTrade(isBuy, "HTFEA " + side + IntegerToString(setup), false))
        {
         if(isBuy) g_zones[zoneIdx].usedBuy = true; else g_zones[zoneIdx].usedSell = true;
         PrintFormat("%s setup %d @ level %.*f", isBuy ? "BUY" : "SELL", setup, _Digits, g_zones[zoneIdx].level);
        }
      return;
     }

   // DD entry on a new same-direction setup
   if(ddMode == DD_ON_SIGNAL && g_ddUsed[d] < ddMax)
     {
      int li = LatestIndex(arr);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double adverse = isBuy ? (arr[li].price - ask) : (bid - arr[li].price);
      if(adverse >= ddMinDistPts * _Point)
        {
         if(OpenTrade(isBuy, "HTFEA " + side + IntegerToString(setup) + " DD" + IntegerToString(g_ddUsed[d] + 1), true))
           {
            g_ddUsed[d]++;
            PrintFormat("%s DD entry %d (setup %d)", isBuy ? "BUY" : "SELL", g_ddUsed[d], setup);
           }
        }
     }
  }

//--- DD entry by distance (grid mode), runs every tick ------------------
void CheckDdByDistance()
  {
   if(ddMode != DD_ON_DISTANCE) return;
   for(int d = 0; d < 2; d++)
     {
      bool isBuy = (d == 0);
      PInfo arr[];
      int n = CollectPositions(isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL, arr);
      if(n == 0 || g_ddUsed[d] >= ddMax) continue;
      int li = LatestIndex(arr);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double adverse = isBuy ? (arr[li].price - ask) : (bid - arr[li].price);
      if(adverse >= ddMinDistPts * _Point)
         if(OpenTrade(isBuy, "HTFEA " + (isBuy ? "B" : "S") + " DD" + IntegerToString(g_ddUsed[d] + 1), true))
            g_ddUsed[d]++;
     }
  }

//--- rule 8: close older (worst) entries at profit, keep the latest -----
void CloseWorstDD()
  {
   for(int d = 0; d < 2; d++)
     {
      PInfo arr[];
      int n = CollectPositions(d == 0 ? POSITION_TYPE_BUY : POSITION_TYPE_SELL, arr);
      if(n == 0) { g_ddUsed[d] = 0; continue; }
      if(n < 2) continue;
      int li = LatestIndex(arr);
      for(int j = 0; j < n; j++)
        {
         if(j == li) continue;
         if(arr[j].profit >= ddCloseProfit)
           {
            if(trade.PositionClose(arr[j].ticket))
               PrintFormat("DD entry #%I64u closed at %.2f profit", arr[j].ticket, arr[j].profit);
           }
        }
     }
  }

//--- partial state (persistent) ------------------------------------------
string GvName(const ulong t) { return "HTFEA_" + IntegerToString(magic) + "_" + IntegerToString((long)t); }
int GetPartials(const ulong t)
  {
   string n = GvName(t);
   return GlobalVariableCheck(n) ? (int)GlobalVariableGet(n) : 0;
  }
void SetPartials(const ulong t, const int v) { GlobalVariableSet(GvName(t), v); }

void CleanGv()
  {
   string pre = "HTFEA_" + IntegerToString(magic) + "_";
   for(int g = GlobalVariablesTotal() - 1; g >= 0; g--)
     {
      string nm = GlobalVariableName(g);
      if(StringFind(nm, pre) != 0) continue;
      ulong t = (ulong)StringToInteger(StringSubstr(nm, StringLen(pre)));
      if(!PositionSelectByTicket(t))
         GlobalVariableDel(nm);
     }
  }

double PartialStep()
  {
   if(partialStepPts > 0) return partialStepPts;
   if(tpPts > 0) return (double)tpPts / (partialsN + 1);
   return 350.0;
  }

//--- per-position management: partials, BE, TP removal + trailing --------
void ManageOne(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket)) return;
   bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl   = PositionGetDouble(POSITION_SL);
   double tp   = PositionGetDouble(POSITION_TP);
   double vol  = PositionGetDouble(POSITION_VOLUME);
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double profPts = isBuy ? (bid - open) / _Point : (open - ask) / _Point;

   //--- partials: each closes partialPct % of the REMAINING volume
   int done = GetPartials(ticket);
   if(partialsN > 0 && done < partialsN && profPts >= (done + 1) * PartialStep())
     {
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double mn   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double v = vol * partialPct / 100.0;
      if(step > 0) v = MathFloor(v / step + 1e-9) * step;
      if(v < mn) v = mn;
      v = NormalizeDouble(v, g_volDigits);
      if(vol - v >= mn - 1e-9)
        {
         if(trade.PositionClosePartial(ticket, v))
            SetPartials(ticket, done + 1);
        }
      else
         SetPartials(ticket, done + 1);   // too small to split - skip this partial
      if(!PositionSelectByTicket(ticket)) return;
     }

   //--- break-even / TP removal / trailing
   double newSL = sl, newTP = tp;
   double eps = _Point * 0.5;

   if(beTrigPts > 0 && profPts >= beTrigPts)
     {
      double be = isBuy ? open + beOffsetPts * _Point : open - beOffsetPts * _Point;
      if(isBuy ? (sl == 0 || sl < be - eps) : (sl == 0 || sl > be + eps))
         newSL = be;
     }

   if(trailStartPts > 0 && profPts >= trailStartPts)
     {
      if(tp != 0) newTP = 0;                                   // remove full TP
      double ts = isBuy ? bid - trailDistPts * _Point : ask + trailDistPts * _Point;
      double stp = trailStepPts * _Point;
      if(isBuy ? (newSL == 0 || ts > newSL + stp) : (newSL == 0 || ts < newSL - stp))
         newSL = ts;
     }

   newSL = (newSL > 0) ? NormalizeDouble(newSL, _Digits) : 0;

   // respect broker stop level
   double lvl = (double)MathMax(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
                                SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL)) * _Point;
   if(newSL != sl && newSL > 0)
     {
      if(isBuy && newSL > bid - lvl) newSL = sl;
      if(!isBuy && newSL < ask + lvl) newSL = sl;
     }

   if(MathAbs(newSL - sl) > eps || MathAbs(newTP - tp) > eps)
      trade.PositionModify(ticket, newSL, newTP);
  }

void ManageAll()
  {
   CloseWorstDD();
   CheckDdByDistance();
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      ManageOne(t);
     }
  }

//+------------------------------------------------------------------+
//| One closed chart bar (zone engine + setup detection)             |
//+------------------------------------------------------------------+
bool LevelAllowed(const int zi)
  {
   if(g_zones[zi].isMid) return tradeMid;
   return g_zones[zi].isHigh ? tradeHigh : tradeLow;
  }

void ProcessBar(const MqlRates &r[], const int i, const int absIdx, const bool trading)
  {
   datetime tm = r[i].time;

   int      h    = HtfIndex(tm);
   int      sigv = 0;
   double   pHi = 0, pLo = 0;
   datetime tH = 0;
   int      hBar = -1;
   if(h >= 1)
     {
      sigv = g_sig[h - 1];
      pHi  = g_pHi[h - 1];
      pLo  = g_pLo[h - 1];
      tH   = g_hTime[h - 1];
      hBar = h - 1;
     }
   datetime tPrev = 0;
   if(i > 0)
     {
      int hp = HtfIndex(r[i - 1].time);
      if(hp >= 1)
         tPrev = g_hTime[hp - 1];
     }

   bool rawPair = (i > 0) && sigv > 0 && (tPrev == 0 || tH != tPrev);
   bool gapOk   = !useGap || !g_hasLast || (hBar - g_lastHBar >= minGap);
   bool newGR   = rawPair && gapOk && sigv == 1 && showGR;
   bool newRG   = rawPair && gapOk && sigv == 2 && showRG;
   bool newAny  = newGR || newRG;

   if(newAny)
     {
      g_lastHBar = hBar;
      g_hasLast  = true;
     }

   //--- STEP 1
   if(newAny)
     {
      for(int j = 0; j < ArraySize(g_extLines); j++)
         FreezeLine(g_extLines[j], tm);
      ArrayResize(g_extLines, 0);
      for(int k = ArraySize(g_zones) - 1; k >= 0; k--)
         if(g_zones[k].mitigated)
            ZoneRemove(k);
     }

   //--- STEP 2
   if(newAny)
     {
      color    c           = newGR ? colGR : colRG;
      datetime confirmTime = r[i - 1].time;
      double   refClose    = r[i - 1].close;
      AddZone(pHi, true,  false, c, confirmTime, refClose, absIdx, tm);
      AddZone(pLo, false, false, c, confirmTime, refClose, absIdx, tm);
      if(showMid)
        {
         double mid = (pHi + pLo) / 2;
         AddZone(mid, refClose < mid, true, c, confirmTime, refClose, absIdx, tm);
        }
     }

   //--- STEP 3: setups + mitigation
   int sellZone = -1, buyZone = -1, sellSetup = 0, buySetup = 0;

   for(int zi = ArraySize(g_zones) - 1; zi >= 0; zi--)
     {
      double L = g_zones[zi].level;

      if(trading && LevelAllowed(zi))
        {
         if(enableSells && sellZone < 0)
           {
            int s = DetectSell(r, i, L);
            if(s > 0) { sellZone = zi; sellSetup = s; }
           }
         if(enableBuys && buyZone < 0)
           {
            int b = DetectBuy(r, i, L);
            if(b > 0) { buyZone = zi; buySetup = b; }
           }
        }

      // ---- mitigation (same as indicator) ----
      bool hit = g_zones[zi].isHigh
                 ? (mitMode == MIT_WICK ? (r[i].high >= L) : (r[i].close >= L))
                 : (mitMode == MIT_WICK ? (r[i].low  <= L) : (r[i].close <= L));
      if(hit && !g_zones[zi].mitigated)
        {
         g_zones[zi].mitigated = true;
         long id = g_zones[zi].lineId;
         if(keepMit)
           {
            FadeLine(id);
            if(extendMit)
              {
               if(newAny && g_zones[zi].birth < absIdx)
                  FreezeLine(id, tm);
               else if(id != 0)
                 {
                  int n = ArraySize(g_extLines);
                  ArrayResize(g_extLines, n + 1);
                  g_extLines[n] = id;
                 }
              }
            else
               FreezeLine(id, tm);
           }
         else
            DeleteLine(id);
        }
     }

   //--- entries (market order right after the signal bar closes)
   if(trading)
     {
      if(sellZone >= 0) TryEnter(false, sellSetup, sellZone);
      if(buyZone  >= 0) TryEnter(true,  buySetup,  buyZone);
     }
  }

//+------------------------------------------------------------------+
//| Warm-up: build zones from history (no trading)                   |
//+------------------------------------------------------------------+
bool Warmup()
  {
   MqlRates r[];
   ArraySetAsSeries(r, false);
   int n = CopyRates(_Symbol, _Period, 0, warmupBars, r);
   if(n < 60) return false;
   if(!SeriesInfoInteger(_Symbol, g_htf, SERIES_SYNCHRONIZED)) return false;

   ResetState();
   g_htfStart = r[0].time - (datetime)((long)(avgLen + 5) * PeriodSeconds(g_htf));
   if(!LoadHtf(r[n - 1].time)) return false;

   for(int i = 0; i <= n - 2; i++)
      ProcessBar(r, i, i, false);

   g_abs          = n - 2;
   g_lastProcTime = r[n - 2].time;
   g_lastBarTime  = r[n - 1].time;
   g_ready        = true;
   ChartRedraw(0);
   return true;
  }

//+------------------------------------------------------------------+
void OnNewBar()
  {
   MqlRates r[];
   ArraySetAsSeries(r, false);
   int n = CopyRates(_Symbol, _Period, 0, 400, r);
   if(n < GUARD_BARS + 5) return;
   if(!LoadHtf(r[n - 1].time)) return;

   for(int i = 1; i <= n - 2; i++)
     {
      if(r[i].time <= g_lastProcTime) continue;
      g_abs++;
      ProcessBar(r, i, g_abs, i == n - 2);
      g_lastProcTime = r[i].time;
     }
   CleanGv();
   ChartRedraw(0);
  }

void OnTick()
  {
   if(!g_ready)
     {
      if(!Warmup()) return;
     }
   ManageAll();

   datetime bt = iTime(_Symbol, _Period, 0);
   if(bt != g_lastBarTime)
     {
      g_lastBarTime = bt;
      OnNewBar();
     }
  }
//+------------------------------------------------------------------+