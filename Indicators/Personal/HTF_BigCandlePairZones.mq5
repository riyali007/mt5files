//+------------------------------------------------------------------+
//|                                     HTF_BigCandlePairZones.mq5    |
//|  MQL5 port of Pine v6 "HTF Big Candle Pair Zones" (TEMPLATE)      |
//+------------------------------------------------------------------+
#property version   "1.00"
#property description "HTF Big Candle Pair Zones - HTF big green/red candle pairs, high/low/mid zone lines."
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   4

#property indicator_label1  "Green->Red pair (trigger bar)"
#property indicator_type1   DRAW_NONE
#property indicator_label2  "Red->Green pair (trigger bar)"
#property indicator_type2   DRAW_NONE
#property indicator_label3  "Midline sell triangle"
#property indicator_type3   DRAW_NONE
#property indicator_label4  "Midline buy triangle"
#property indicator_type4   DRAW_NONE

//--- enums (text after // is what the inputs dialog shows)
enum ENUM_MIT_MODE
  {
   MIT_WICK = 0, // Wick
   MIT_BODY = 1  // Body close
  };

enum ENUM_LINE_STYLE_IN
  {
   LS_SOLID = 0, // Solid
   LS_DASHED = 1,// Dashed
   LS_DOTTED = 2 // Dotted
  };

//--- Inputs ----------------------------------------------------------
input group "Timeframe"
input ENUM_TIMEFRAMES htf        = PERIOD_H4;  // Higher timeframe (pattern detection)

input group "Big candle definition"
input int      avgLen            = 20;         // Average body length (min 2)
input double   bigMult           = 1.5;        // Min body size (x average body) (min 0.5)
input double   minBodyPct        = 60.0;       // Min body % of full range (small wicks) (0-100)

input group "Pair similarity"
input double   simMin            = 0.6;        // Min size ratio (2nd body / 1st body) (min 0.1)
input double   simMax            = 1.7;        // Max size ratio (2nd body / 1st body) (min 0.1)
input bool     needOverlap       = true;       // Require bodies to overlap

input group "Patterns"
input bool     showGR            = true;       // Detect Green -> Red
input bool     showRG            = true;       // Detect Red -> Green
input bool     useGap            = true;       // Enforce minimum gap between patterns
input int      minGap            = 4;          // Min gap between patterns (HTF candles) (1-50)

input group "Lines"
input ENUM_MIT_MODE mitMode      = MIT_WICK;   // Mitigation mode (Wick: wick touch / Body close: close beyond level)
input bool     keepMit           = true;       // Keep mitigated lines
input bool     extendMit         = true;       // Extend mitigated lines until next pattern
input int      maxActive         = 150;        // Max tracked zones (lines) (3-300)
input bool     showMid           = true;       // Show midline
input ENUM_LINE_STYLE_IN lineStyleIn = LS_SOLID;  // High / Low line style
input ENUM_LINE_STYLE_IN midStyleIn  = LS_DOTTED; // Midline style
input int      lineWidth         = 1;          // Line width (1-4)
input color    colGR             = C'242,54,69';   // Green -> Red line color (TV red)
input color    colRG             = C'8,153,129';   // Red -> Green line color (TV green)
input color    colMitFade        = C'120,123,134'; // Mitigated line color (TV gray)
input int      mitAlpha          = 102;        // Mitigated line opacity 0-255 (Pine: transparency 60 = 102)

input group "Display"
input bool     showMarks         = true;       // Show pair confirmation markers
input bool     showMidSig        = true;       // Show midline triangles

input group "Alerts (MT5)"
input bool     alertPopup        = false;      // Popup alert
input bool     alertPush         = false;      // Push notification
input bool     alertEmail        = false;      // Email
input bool     alertSound        = false;      // Sound

//--- YOUR SIGNAL INPUTS GO HERE ----------------------------------------
// Example:
// input group "My signals"
// input double myMinPts = 10.0;   // My min distance

//--- Constants ---------------------------------------------------------
#define PINE_MAX_LINES 500

//--- Zone storage ------------------------------------------------------
struct Zone
  {
   long     lineId;       // chart object id of the line
   double   level;
   bool     isHigh;       // true = mitigated when price rises to the level (resistance side)
   bool     isMid;        // true = midline
   bool     mitigated;
   int      birth;        // bar index where the zone was created
   int      side;         // +1 = price was above the level at creation, -1 = below
   //--- your own per-zone state (free to use / rename / add more)
   int      st;
   int      stBar;        // -1 = na
   double   stVal;        // EMPTY_VALUE = na
  };

Zone     g_zones[];
long     g_extLines[];    // mitigated lines still extending until next pattern
long     g_reg[];         // registry of live lines (FIFO, Pine max_lines_count = 500)
long     g_lineSeq = 0;

//--- HTF series (chronological) ---------------------------------------
datetime g_hTime[];
int      g_sig[];         // 0 none, 1 G->R, 2 R->G   (signal AT that HTF bar)
double   g_pHi[];
double   g_pLo[];

//--- state ---------------------------------------------------------------
ENUM_TIMEFRAMES g_htf;
int      g_lastProc = -1;
bool     g_hasLast  = false;
int      g_lastHBar = 0;
datetime g_htfStart = 0;
string   g_prefix;
ENUM_LINE_STYLE g_lStyle, g_mStyle;
uint     g_fadeARGB;

//--- buffers -------------------------------------------------------------
double   bufGR[], bufRG[], bufSell[], bufBuy[];

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
      maxActive < 3 || maxActive > 300 || lineWidth < 1 || lineWidth > 4)
     {
      Print("Input parameter out of range (see min/max in input labels).");
      return INIT_PARAMETERS_INCORRECT;
     }

   SetIndexBuffer(0, bufGR,   INDICATOR_DATA);
   SetIndexBuffer(1, bufRG,   INDICATOR_DATA);
   SetIndexBuffer(2, bufSell, INDICATOR_DATA);
   SetIndexBuffer(3, bufBuy,  INDICATOR_DATA);
   for(int p = 0; p < 4; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   IndicatorSetString(INDICATOR_SHORTNAME, "HTF BigPair TEMPLATE");

   g_lStyle    = MapStyle(lineStyleIn);
   g_mStyle    = MapStyle(midStyleIn);
   int a       = (int)MathMax(0, MathMin(255, mitAlpha));
   g_fadeARGB  = ColorToARGB(colMitFade, (uchar)a);
   g_prefix    = StringFormat("HTFBP%d_", (int)(GetMicrosecondCount() % 1000000));

   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, g_prefix);
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Line registry (emulates Pine max_lines_count)                    |
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
     {
      if(g_reg[k] == id)
        {
         for(int j = k; j < n - 1; j++)
            g_reg[j] = g_reg[j + 1];
         ArrayResize(g_reg, n - 1);
         return;
        }
     }
  }

void DeleteLine(const long id)
  {
   ObjectDelete(0, LineName(id));
   RegRemove(id);
  }

long CreateLine(const datetime t1, const double level, const datetime t2,
                const color c, const ENUM_LINE_STYLE style)
  {
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
   string nm = LineName(id);
   ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, false);   // extend.none
   ObjectSetInteger(0, nm, OBJPROP_TIME, 1, t);         // set_x2(time)
  }

//+------------------------------------------------------------------+
//| Zones                                                            |
//+------------------------------------------------------------------+
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
   g_zones[n].st        = 0;
   g_zones[n].stBar     = -1;
   g_zones[n].stVal     = EMPTY_VALUE;
   if(ArraySize(g_zones) > maxActive)
      ZoneRemove(0);                       // zones.shift() (line object stays, like Pine)
  }

void ResetState()
  {
   ObjectsDeleteAll(0, g_prefix);
   ArrayResize(g_zones, 0);
   ArrayResize(g_extLines, 0);
   ArrayResize(g_reg, 0);
   g_lineSeq  = 0;
   g_lastProc = -1;
   g_hasLast  = false;
   g_lastHBar = 0;
  }

//+------------------------------------------------------------------+
//| Pattern detection on the HTF series                              |
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
      double ref = (h >= 1) ? sma[h - 1] : EMPTY_VALUE;   // avgBody[1]
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

// index of the HTF bar containing time t (largest open time <= t), -1 if none
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
//| Drawing / alert helpers                                          |
//+------------------------------------------------------------------+
void PutText(const string tag, const datetime t, const double price, const string txt,
             const color c, const string font, const int size, const ENUM_ANCHOR_POINT anchor)
  {
   string nm = g_prefix + tag + "_" + IntegerToString((long)t);
   if(ObjectFind(0, nm) >= 0)
      ObjectDelete(0, nm);
   if(!ObjectCreate(0, nm, OBJ_TEXT, 0, t, price))
      return;
   ObjectSetString(0, nm, OBJPROP_TEXT, txt);
   ObjectSetString(0, nm, OBJPROP_FONT, font);
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, c);
   ObjectSetInteger(0, nm, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
  }

void FireAlert(const string msg)
  {
   string full = _Symbol + ": " + msg;
   if(alertPopup) Alert(full);
   if(alertPush)  SendNotification(full);
   if(alertEmail) SendMail("HTF BigPair", full);
   if(alertSound) PlaySound("alert.wav");
  }

//+------------------------------------------------------------------+
//| One chart bar (closed) - mirrors the Pine per-bar execution      |
//+------------------------------------------------------------------+
void ProcessBar(const int i, const bool alertsOn,
                const datetime &time[], const double &open[], const double &high[],
                const double &low[], const double &close[])
  {
   //--- request.security values (shifted [1] inside the HTF function)
   int      h    = HtfIndex(time[i]);
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
   datetime tPrev = 0;                                  // tHtf[1]
   if(i > 0)
     {
      int hp = HtfIndex(time[i - 1]);
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

   //--- STEP 1: a new pattern freezes mitigated lines of EARLIER patterns
   if(newAny)
     {
      for(int j = 0; j < ArraySize(g_extLines); j++)
         FreezeLine(g_extLines[j], time[i]);
      ArrayResize(g_extLines, 0);
      for(int k = ArraySize(g_zones) - 1; k >= 0; k--)
         if(g_zones[k].mitigated)
            ZoneRemove(k);
     }

   //--- STEP 2: create lines on the exact LTF candle that confirms the pattern
   if(newAny)
     {
      color    c           = newGR ? colGR : colRG;
      datetime confirmTime = time[i - 1];               // time[1]
      double   refClose    = close[i - 1];              // close[1]
      AddZone(pHi, true,  false, c, confirmTime, refClose, i, time[i]);
      AddZone(pLo, false, false, c, confirmTime, refClose, i, time[i]);
      if(showMid)
        {
         double mid = (pHi + pLo) / 2;
         AddZone(mid, refClose < mid, true, c, confirmTime, refClose, i, time[i]);
        }
     }

   //--- STEP 3: signals + mitigation
   bool sellMid = false;   // set to true inside your block to draw a triangle on this bar
   bool buyMid  = false;

   // Handy candle helpers for your rules (chart timeframe, current bar):
   bool bearEngulf = false, bullEngulf = false;
   if(i > 0)
     {
      bearEngulf = close[i-1] > open[i-1] && close[i] < open[i] && open[i] >= close[i-1] && close[i] <= open[i-1];
      bullEngulf = close[i-1] < open[i-1] && close[i] > open[i] && open[i] <= close[i-1] && close[i] >= open[i-1];
     }

   for(int zi = ArraySize(g_zones) - 1; zi >= 0; zi--)
     {
      double L = g_zones[zi].level;
      bool removed = false;

      // +----------------------------------------------------------------+
      // |  YOUR SIGNAL CODE GOES HERE (runs once per bar for every zone) |
      // +----------------------------------------------------------------+
      // |  g_zones[zi].level / L        price of this line               |
      // |  g_zones[zi].isMid            true = midline                   |
      // |  g_zones[zi].isHigh           true = high line side            |
      // |  g_zones[zi].mitigated        true once price touched/closed   |
      // |  g_zones[zi].birth            bar index when zone was created  |
      // |  g_zones[zi].side             +1/-1 side of level at creation  |
      // |  g_zones[zi].st/stBar/stVal   free state variables             |
      // |  i                            current bar index                |
      // |  Only midline zones draw triangles:                            |
      // |     if(g_zones[zi].isMid && <your sell condition>) sellMid = true; |
      // |     if(g_zones[zi].isMid && <your buy condition>)  buyMid  = true; |
      // |  To stop tracking a zone: ZoneRemove(zi); removed = true;      |
      // +----------------------------------------------------------------+

      // ---- your code ----


      if(removed)
         continue;

      // ---- mitigation (keep this block) ----
      bool hit = g_zones[zi].isHigh
                 ? (mitMode == MIT_WICK ? (high[i] >= L) : (close[i] >= L))
                 : (mitMode == MIT_WICK ? (low[i]  <= L) : (close[i] <= L));
      if(hit && !g_zones[zi].mitigated)
        {
         g_zones[zi].mitigated = true;
         long id = g_zones[zi].lineId;
         if(keepMit)
           {
            ObjectSetInteger(0, LineName(id), OBJPROP_COLOR, g_fadeARGB);
            if(extendMit)
              {
               // An OLD zone mitigated on the very bar a new pattern is accepted stops right here.
               // A zone born on this bar keeps extending until the NEXT pattern.
               if(newAny && g_zones[zi].birth < i)
                  FreezeLine(id, time[i]);
               else
                 {
                  int n = ArraySize(g_extLines);
                  ArrayResize(g_extLines, n + 1);
                  g_extLines[n] = id;
                 }
              }
            else
               FreezeLine(id, time[i]);
           }
         else
            DeleteLine(id);
        }
     }

   //--- Plots (markers drawn on the confirming bar = offset -1)
   bufGR[i]   = newGR ? high[i] : EMPTY_VALUE;
   bufRG[i]   = newRG ? low[i]  : EMPTY_VALUE;
   bufSell[i] = (showMidSig && sellMid) ? high[i] : EMPTY_VALUE;
   bufBuy[i]  = (showMidSig && buyMid)  ? low[i]  : EMPTY_VALUE;

   string arrow = ShortToString(0x2192);
   if(showMarks && newGR && i > 0)
      PutText("GR", time[i - 1], high[i - 1], "G" + arrow + "R", colGR, "Arial", 8, ANCHOR_LOWER);
   if(showMarks && newRG && i > 0)
      PutText("RG", time[i - 1], low[i - 1],  "R" + arrow + "G", colRG, "Arial", 8, ANCHOR_UPPER);
   if(showMidSig && sellMid)
      PutText("SELL", time[i], high[i], "q", clrRed,   "Wingdings 3", 9, ANCHOR_LOWER);   // down triangle
   if(showMidSig && buyMid)
      PutText("BUY",  time[i], low[i],  "p", clrGreen, "Wingdings 3", 9, ANCHOR_UPPER);   // up triangle

   //--- Alerts
   if(alertsOn)
     {
      if(newGR)   FireAlert("HTF big green then big red candle confirmed on " + _Symbol);
      if(newRG)   FireAlert("HTF big red then big green candle confirmed on " + _Symbol);
      if(sellMid) FireAlert("SELL triangle at HTF pair midline on " + _Symbol);
      if(buyMid)  FireAlert("BUY triangle at HTF pair midline on " + _Symbol);
     }
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total < 3)
      return 0;

   ArraySetAsSeries(time,  false);
   ArraySetAsSeries(open,  false);
   ArraySetAsSeries(high,  false);
   ArraySetAsSeries(low,   false);
   ArraySetAsSeries(close, false);

   if(prev_calculated == 0)
     {
      ResetState();
      g_htfStart = time[0] - (datetime)((long)(avgLen + 5) * PeriodSeconds(g_htf));
      ArrayInitialize(bufGR,   EMPTY_VALUE);
      ArrayInitialize(bufRG,   EMPTY_VALUE);
      ArrayInitialize(bufSell, EMPTY_VALUE);
      ArrayInitialize(bufBuy,  EMPTY_VALUE);
     }

   // All logic is evaluated on CLOSED chart bars (same result as Pine on history / bar close)
   int last  = rates_total - 2;
   int first = g_lastProc + 1;

   if(first <= last)
     {
      if(!SeriesInfoInteger(_Symbol, g_htf, SERIES_SYNCHRONIZED))
         return 0;
      if(!LoadHtf(time[rates_total - 1]))
         return 0;

      for(int i = first; i <= last; i++)
        {
         bool alertsOn = (prev_calculated > 0 && i == last);
         ProcessBar(i, alertsOn, time, open, high, low, close);
        }
      g_lastProc = last;
      ChartRedraw(0);
     }

   bufGR[rates_total - 1]   = EMPTY_VALUE;
   bufRG[rates_total - 1]   = EMPTY_VALUE;
   bufSell[rates_total - 1] = EMPTY_VALUE;
   bufBuy[rates_total - 1]  = EMPTY_VALUE;

   return rates_total;
  }
//+------------------------------------------------------------------+