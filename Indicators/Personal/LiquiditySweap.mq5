//+------------------------------------------------------------------+
//|                                          LiquiditySweeps.mq5    |
//|                     Converted from LuxAlgo Pine Script           |
//|  Original: Attribution-NonCommercial-ShareAlike 4.0 International|
//+------------------------------------------------------------------+
#property copyright "LuxAlgo (converted to MQL5)"
#property link      "https://creativecommons.org/licenses/by-nc-sa/4.0/"
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots   0
#property indicator_buffers 0

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input int    InpSwings    = 5;             // Swings (len)
input string InpOptions   = "Only Wicks"; // "Only Wicks" | "Only Outbreaks & Retest" | "Wicks + Outbreaks & Retest"
input color  InpBullColor = C'8,153,129'; // Bull Line Color
input color  InpBearColor = C'242,54,69'; // Bear Line Color
input bool   InpExtend    = true;         // Extend Zones
input int    InpMaxBars   = 300;          // Max Bars for Extension
input color  InpBullZone  = C'8,153,129'; // Bull Zone Fill Color
input color  InpBearZone  = C'242,54,69'; // Bear Zone Fill Color

//+------------------------------------------------------------------+
//| Runtime colors (computed once in OnInit)                         |
//+------------------------------------------------------------------+
color BullLineColor, BearLineColor;
color BullFadeColor, BearFadeColor;
color BullZoneFill,  BearZoneFill;
color GrayFill,      GrayLine;

bool oW, oO; // option flags

//+------------------------------------------------------------------+
//| Unique name counter                                              |
//+------------------------------------------------------------------+
int g_ObjCnt = 0;

string NextName(const string prefix)
{
   g_ObjCnt++;
   return prefix + IntegerToString(g_ObjCnt);
}

//+------------------------------------------------------------------+
//| Simulate transparency by blending toward white                   |
//+------------------------------------------------------------------+
color FadeColor(const color clr, const uchar alpha)
{
   uchar r = (uchar)(((int)((clr >> 16) & 0xFF) * alpha + 255 * (255 - alpha)) / 255);
   uchar g = (uchar)(((int)((clr >>  8) & 0xFF) * alpha + 255 * (255 - alpha)) / 255);
   uchar b = (uchar)(((int)( clr        & 0xFF) * alpha + 255 * (255 - alpha)) / 255);
   return (color)((r << 16) | (g << 8) | b);
}

//+------------------------------------------------------------------+
//| Pivot — plain POD struct                                         |
//+------------------------------------------------------------------+
struct PivotPoint
{
   double price;
   int    barIndex;   // absolute bar index in rates array
   bool   isBreak;
   bool   isMitigated;
   bool   isTaken;
   bool   isWick;
};

//+------------------------------------------------------------------+
//| BoxZone                                                          |
//| Object names stored directly — no indirect lookup tables.        |
//| rectRightTime: the DATETIME we last set on the rect right edge.  |
//| We only call ObjectSet when this needs to change (new bar).      |
//+------------------------------------------------------------------+
struct BoxZone
{
   string   rectName;
   string   vlineName;
   string   labelName;
   bool     isBroken;
   int      direction;      //  1 = SELL,  -1 = BUY
   int      leftBarAbs;     // absolute bar index where zone was created
   double   topPrice;
   double   bottomPrice;
   datetime rectRightTime;  // cached right-edge time to avoid redundant sets
};

//+------------------------------------------------------------------+
//| Global state                                                     |
//+------------------------------------------------------------------+
PivotPoint g_PivHigh[];
PivotPoint g_PivLow[];
BoxZone    g_Zones[];

int g_nHigh  = 0;
int g_nLow   = 0;
int g_nZones = 0;

// Track last processed bar to distinguish new-bar vs same-bar tick
int      g_LastBarTotal   = 0;
datetime g_LastBarTime    = 0;

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
datetime BarTime(const int rates_total, const int absIdx)
{
   int off = rates_total - 1 - absIdx;
   if(off < 0) return 0;
   return iTime(_Symbol, _Period, off);
}

datetime OffTime(const int offset)
{
   if(offset < 0) return 0;
   return iTime(_Symbol, _Period, offset);
}

//+------------------------------------------------------------------+
//| Draw static horizontal line (called once, never moved)           |
//+------------------------------------------------------------------+
void DrawHLine(const datetime t1, const datetime t2,
               const double price, const color clr,
               const ENUM_LINE_STYLE style, const int width = 1)
{
   if(t1 == 0 || t2 == 0) return;
   string nm = NextName("LS_HL_");
   if(!ObjectCreate(0, nm, OBJ_TREND, 0, t1, price, t2, price)) return;
   ObjectSetInteger(0, nm, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, nm, OBJPROP_STYLE,      style);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH,      width);
   ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT,  false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN,     true);
}

//+------------------------------------------------------------------+
//| Short dotted marker (called once, never moved)                   |
//+------------------------------------------------------------------+
void DrawDotMarker(const datetime t1, const double price, const color clr)
{
   if(t1 == 0) return;
   string nm = NextName("LS_DT_");
   // 3-bar width visual; second point slightly to the right
   datetime t2 = t1 + PeriodSeconds() * 3;
   if(!ObjectCreate(0, nm, OBJ_TREND, 0, t1, price, t2, price)) return;
   ObjectSetInteger(0, nm, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, nm, OBJPROP_STYLE,      STYLE_DOT);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH,      1);
   ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT,  false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN,     true);
}

//+------------------------------------------------------------------+
//| Create zone objects once. Right edge starts at creation bar.     |
//+------------------------------------------------------------------+
void CreateBoxZone(BoxZone &bz,
                   const datetime tCreate,
                   const double   y1,
                   const double   y2,
                   const color    zoneFillClr,
                   const color    lineClr,
                   const int      direction,
                   const int      curAbsBar)
{
   bz.isBroken      = false;
   bz.direction     = direction;
   bz.leftBarAbs    = curAbsBar;
   bz.topPrice      = MathMax(y1, y2);
   bz.bottomPrice   = MathMin(y1, y2);
   bz.rectRightTime = tCreate;   // will be extended bar-by-bar

   double midY   = (bz.topPrice + bz.bottomPrice) * 0.5;
   color  fill   = FadeColor(zoneFillClr, 65);

   // ── Rectangle ──────────────────────────────────────────────────
   bz.rectName = NextName("LS_RCT_");
   if(ObjectCreate(0, bz.rectName, OBJ_RECTANGLE, 0,
                   tCreate, bz.topPrice, tCreate, bz.bottomPrice))
   {
      ObjectSetInteger(0, bz.rectName, OBJPROP_COLOR,      fill);
      ObjectSetInteger(0, bz.rectName, OBJPROP_FILL,       true);
      ObjectSetInteger(0, bz.rectName, OBJPROP_BACK,       true);
      ObjectSetInteger(0, bz.rectName, OBJPROP_WIDTH,      0);
      ObjectSetInteger(0, bz.rectName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, bz.rectName, OBJPROP_HIDDEN,     true);
   }

   // ── Vertical edge line ─────────────────────────────────────────
   bz.vlineName = NextName("LS_VL_");
   if(ObjectCreate(0, bz.vlineName, OBJ_TREND, 0,
                   tCreate, bz.topPrice, tCreate, bz.bottomPrice))
   {
      ObjectSetInteger(0, bz.vlineName, OBJPROP_COLOR,      lineClr);
      ObjectSetInteger(0, bz.vlineName, OBJPROP_WIDTH,      3);
      ObjectSetInteger(0, bz.vlineName, OBJPROP_STYLE,      STYLE_SOLID);
      ObjectSetInteger(0, bz.vlineName, OBJPROP_RAY_RIGHT,  false);
      ObjectSetInteger(0, bz.vlineName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, bz.vlineName, OBJPROP_HIDDEN,     true);
   }

   // ── Label ──────────────────────────────────────────────────────
   bz.labelName   = NextName("LS_LBL_");
   string lblText = (direction == 1) ? "SELL Zone" : "BUY Zone";
   color  lblClr  = (direction == 1) ? BearLineColor : BullLineColor;
   if(ObjectCreate(0, bz.labelName, OBJ_TEXT, 0, tCreate, midY))
   {
      ObjectSetString (0, bz.labelName, OBJPROP_TEXT,       lblText);
      ObjectSetInteger(0, bz.labelName, OBJPROP_COLOR,      lblClr);
      ObjectSetInteger(0, bz.labelName, OBJPROP_FONTSIZE,   8);
      ObjectSetInteger(0, bz.labelName, OBJPROP_ANCHOR,     ANCHOR_LEFT);
      ObjectSetInteger(0, bz.labelName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, bz.labelName, OBJPROP_HIDDEN,     true);
   }
}

//+------------------------------------------------------------------+
//| Extend zone right edge — only writes if time actually changed    |
//+------------------------------------------------------------------+
void ExtendZone(BoxZone &bz, const datetime tNew)
{
   if(bz.rectName == "" || tNew == bz.rectRightTime) return;
   bz.rectRightTime = tNew;

   ObjectSetInteger(0, bz.rectName, OBJPROP_TIME, 1, tNew);

   datetime tLeft = (datetime)ObjectGetInteger(0, bz.rectName, OBJPROP_TIME, 0);
   datetime tMid  = tLeft + (tNew - tLeft) / 2;
   ObjectSetInteger(0, bz.labelName, OBJPROP_TIME, tMid);
}

//+------------------------------------------------------------------+
//| Freeze right edge (called once when swept)                       |
//+------------------------------------------------------------------+
void FreezeZone(BoxZone &bz, const datetime tSweep)
{
   if(bz.rectName == "") return;
   bz.rectRightTime = tSweep;

   ObjectSetInteger(0, bz.rectName, OBJPROP_TIME, 1, tSweep);

   datetime tLeft = (datetime)ObjectGetInteger(0, bz.rectName, OBJPROP_TIME, 0);
   datetime tMid  = tLeft + (tSweep - tLeft) / 2;
   ObjectSetInteger(0, bz.labelName, OBJPROP_TIME, tMid);
}

//+------------------------------------------------------------------+
//| Gray out a swept zone — called once                              |
//+------------------------------------------------------------------+
void GrayOutZone(BoxZone &bz)
{
   ObjectSetInteger(0, bz.rectName,  OBJPROP_COLOR, GrayFill);
   ObjectSetInteger(0, bz.vlineName, OBJPROP_COLOR, GrayLine);
   ObjectSetInteger(0, bz.labelName, OBJPROP_COLOR, GrayLine);
}

//+------------------------------------------------------------------+
//| Pivot array helpers                                              |
//+------------------------------------------------------------------+
void PushPivotHigh(const double price, const int absIdx)
{
   ArrayResize(g_PivHigh, g_nHigh + 1);
   g_PivHigh[g_nHigh].price       = price;
   g_PivHigh[g_nHigh].barIndex    = absIdx;
   g_PivHigh[g_nHigh].isBreak     = false;
   g_PivHigh[g_nHigh].isMitigated = false;
   g_PivHigh[g_nHigh].isTaken     = false;
   g_PivHigh[g_nHigh].isWick      = false;
   g_nHigh++;
}

void PushPivotLow(const double price, const int absIdx)
{
   ArrayResize(g_PivLow, g_nLow + 1);
   g_PivLow[g_nLow].price       = price;
   g_PivLow[g_nLow].barIndex    = absIdx;
   g_PivLow[g_nLow].isBreak     = false;
   g_PivLow[g_nLow].isMitigated = false;
   g_PivLow[g_nLow].isTaken     = false;
   g_PivLow[g_nLow].isWick      = false;
   g_nLow++;
}

void RemovePivotHigh(const int idx)
{
   for(int i = idx; i < g_nHigh - 1; i++) g_PivHigh[i] = g_PivHigh[i + 1];
   g_nHigh--;
   ArrayResize(g_PivHigh, g_nHigh);
}

void RemovePivotLow(const int idx)
{
   for(int i = idx; i < g_nLow - 1; i++) g_PivLow[i] = g_PivLow[i + 1];
   g_nLow--;
   ArrayResize(g_PivLow, g_nLow);
}

void PushZone(BoxZone &bz)
{
   ArrayResize(g_Zones, g_nZones + 1);
   g_Zones[g_nZones] = bz;
   g_nZones++;
}

//+------------------------------------------------------------------+
//| Detect pivot high — returns price or 0                           |
//+------------------------------------------------------------------+
double DetectPivHigh(const int absIdx, const int len, const double &high[])
{
   int lo = absIdx - len;
   int hi = absIdx + len;
   if(lo < 0) return 0.0;
   double ph = high[absIdx];
   for(int j = lo; j <= hi; j++)
   {
      if(j == absIdx) continue;
      if(high[j] >= ph) return 0.0;
   }
   return ph;
}

double DetectPivLow(const int absIdx, const int len, const double &low[])
{
   int lo = absIdx - len;
   int hi = absIdx + len;
   if(lo < 0) return 0.0;
   double pl = low[absIdx];
   for(int j = lo; j <= hi; j++)
   {
      if(j == absIdx) continue;
      if(low[j] <= pl) return 0.0;
   }
   return pl;
}

//+------------------------------------------------------------------+
//| Wipe all indicator objects from chart                            |
//+------------------------------------------------------------------+
void CleanAllObjects()
{
   int total = ObjectsTotal(0);
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i);
      if(StringFind(nm, "LS_") == 0)
         ObjectDelete(0, nm);
   }
}

//+------------------------------------------------------------------+
//| Reset all state                                                  |
//+------------------------------------------------------------------+
void FullReset()
{
   CleanAllObjects();
   ArrayResize(g_PivHigh, 0); g_nHigh  = 0;
   ArrayResize(g_PivLow,  0); g_nLow   = 0;
   ArrayResize(g_Zones,   0); g_nZones = 0;
   g_ObjCnt      = 0;
   g_LastBarTotal = 0;
   g_LastBarTime  = 0;
}

//+------------------------------------------------------------------+
//| Process a single closed bar (b = absolute index in rates array)  |
//| This is the expensive function — only called once per new bar.   |
//+------------------------------------------------------------------+
void ProcessBar(const int b, const int rates_total,
                const double &high[], const double &low[], const double &close[])
{
   int    curOff   = rates_total - 1 - b;
   double curClose = close[b];
   double curHigh  = high[b];
   double curLow   = low[b];
   datetime tCur   = OffTime(curOff);

   // ── Detect new pivot high ──────────────────────────────────────
   {
      int phAbs = b - InpSwings;
      if(phAbs >= InpSwings)
      {
         double ph = DetectPivHigh(phAbs, InpSwings, high);
         if(ph > 0.0)
         {
            bool dup = false;
            for(int pi = 0; pi < g_nHigh && !dup; pi++)
               if(g_PivHigh[pi].barIndex == phAbs) dup = true;
            if(!dup)
            {
               PushPivotHigh(ph, phAbs);
               datetime tPiv = BarTime(rates_total, phAbs);
               DrawHLine(tPiv, tCur, ph, BearLineColor, STYLE_SOLID);
            }
         }
      }
   }

   // ── Detect new pivot low ───────────────────────────────────────
   {
      int plAbs = b - InpSwings;
      if(plAbs >= InpSwings)
      {
         double pl = DetectPivLow(plAbs, InpSwings, low);
         if(pl > 0.0)
         {
            bool dup = false;
            for(int pi = 0; pi < g_nLow && !dup; pi++)
               if(g_PivLow[pi].barIndex == plAbs) dup = true;
            if(!dup)
            {
               PushPivotLow(pl, plAbs);
               datetime tPiv = BarTime(rates_total, plAbs);
               DrawHLine(tPiv, tCur, pl, BullLineColor, STYLE_SOLID);
            }
         }
      }
   }

   // ── Process pivot highs ────────────────────────────────────────
   for(int i = g_nHigh - 1; i >= 0; i--)
   {
      int age = b - g_PivHigh[i].barIndex;

      if(!g_PivHigh[i].isMitigated)
      {
         if(!g_PivHigh[i].isBreak)
         {
            if(curClose > g_PivHigh[i].price)
            {
               if(!oW) g_PivHigh[i].isBreak    = true;
               else    g_PivHigh[i].isMitigated = true;
            }

            // Wick sweep
            if(!oO && !g_PivHigh[i].isWick)
            {
               if(curHigh > g_PivHigh[i].price && curClose < g_PivHigh[i].price)
               {
                  BoxZone bz;
                  CreateBoxZone(bz, tCur,
                                curHigh, g_PivHigh[i].price,
                                BearZoneFill, BearLineColor, 1, b);
                  PushZone(bz);
                  DrawHLine(tCur, tCur, g_PivHigh[i].price, BearFadeColor, STYLE_DOT);
                  DrawDotMarker(tCur, curLow, BearLineColor);
                  g_PivHigh[i].isWick = true;
               }
            }
         }
         else // broken — watch for retest
         {
            if(curClose < g_PivHigh[i].price)
               g_PivHigh[i].isMitigated = true;

            // Outbreak & retest
            if(!oW && curLow < g_PivHigh[i].price && curClose > g_PivHigh[i].price)
            {
               BoxZone bz;
               CreateBoxZone(bz, tCur,
                             g_PivHigh[i].price, curLow,
                             BullZoneFill, BullLineColor, -1, b);
               PushZone(bz);
               DrawHLine(tCur, tCur, g_PivHigh[i].price, BullFadeColor, STYLE_DASH);
               DrawDotMarker(tCur, curHigh, BullLineColor);
               g_PivHigh[i].isTaken = true;
            }
         }
      }

      if(age > 2000 || g_PivHigh[i].isMitigated || g_PivHigh[i].isTaken)
         RemovePivotHigh(i);
   }

   // ── Process pivot lows ─────────────────────────────────────────
   for(int i = g_nLow - 1; i >= 0; i--)
   {
      int age = b - g_PivLow[i].barIndex;

      if(!g_PivLow[i].isMitigated)
      {
         if(!g_PivLow[i].isBreak)
         {
            if(curClose < g_PivLow[i].price)
            {
               if(!oW) g_PivLow[i].isBreak    = true;
               else    g_PivLow[i].isMitigated = true;
            }

            // Wick sweep
            if(!oO && !g_PivLow[i].isWick)
            {
               if(curLow < g_PivLow[i].price && curClose > g_PivLow[i].price)
               {
                  BoxZone bz;
                  CreateBoxZone(bz, tCur,
                                g_PivLow[i].price, curLow,
                                BullZoneFill, BullLineColor, -1, b);
                  PushZone(bz);
                  DrawHLine(tCur, tCur, g_PivLow[i].price, BullFadeColor, STYLE_DOT);
                  DrawDotMarker(tCur, curHigh, BullLineColor);
                  g_PivLow[i].isWick = true;
               }
            }
         }
         else // broken
         {
            if(curClose > g_PivLow[i].price)
               g_PivLow[i].isMitigated = true;

            // Outbreak & retest
            if(!oW && curHigh > g_PivLow[i].price && curClose < g_PivLow[i].price)
            {
               BoxZone bz;
               CreateBoxZone(bz, tCur,
                             curHigh, g_PivLow[i].price,
                             BearZoneFill, BearLineColor, 1, b);
               PushZone(bz);
               DrawHLine(tCur, tCur, g_PivLow[i].price, BearFadeColor, STYLE_DASH);
               DrawDotMarker(tCur, curLow, BearLineColor);
               g_PivLow[i].isTaken = true;
            }
         }
      }

      if(age > 2000 || g_PivLow[i].isMitigated || g_PivLow[i].isTaken)
         RemovePivotLow(i);
   }

   // ── Update zones for this historical bar (check swept, extend)  ─
   // This runs during history replay only.
   // On live ticks it is handled by ProcessTick() instead.
   for(int zi = 0; zi < g_nZones; zi++)
   {
      if(g_Zones[zi].leftBarAbs >= b)  continue; // zone didn't exist yet
      if(g_Zones[zi].isBroken)         continue; // already frozen

      // Sweep check
      bool swept = (g_Zones[zi].direction == -1 && curClose < g_Zones[zi].bottomPrice)
                || (g_Zones[zi].direction ==  1 && curClose > g_Zones[zi].topPrice);

      if(swept)
      {
         FreezeZone(g_Zones[zi], tCur);
         g_Zones[zi].isBroken = true;
         GrayOutZone(g_Zones[zi]);
      }
      else if(InpExtend && (b - g_Zones[zi].leftBarAbs) <= InpMaxBars)
      {
         ExtendZone(g_Zones[zi], tCur);
      }
   }
}

//+------------------------------------------------------------------+
//| Tick-level zone update                                           |
//| Called on every tick for the LIVE (current) bar only.            |
//| Does NOT loop over historical bars.                              |
//| Does NOT create any objects — only modifies colors/right edge    |
//| on already-existing objects if price crosses a level.            |
//+------------------------------------------------------------------+
void ProcessTick(const int rates_total,
                 const double bid)        // use Bid as current price
{
   datetime tNow = TimeCurrent();

   for(int zi = 0; zi < g_nZones; zi++)
   {
      if(g_Zones[zi].isBroken) continue;

      int age = rates_total - 1 - g_Zones[zi].leftBarAbs;
      if(age > InpMaxBars && InpExtend) continue;

      // Sweep check on current tick price
      bool swept = (g_Zones[zi].direction == -1 && bid < g_Zones[zi].bottomPrice)
                || (g_Zones[zi].direction ==  1 && bid > g_Zones[zi].topPrice);

      if(swept)
      {
         // Freeze & gray out — write to chart objects once
         FreezeZone(g_Zones[zi], tNow);
         g_Zones[zi].isBroken = true;
         GrayOutZone(g_Zones[zi]);
      }
      else if(InpExtend)
      {
         // Extend right edge to now — ExtendZone skips the write
         // if time hasn't changed since last call (cached comparison)
         ExtendZone(g_Zones[zi], tNow);
      }
   }
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   oW = (InpOptions == "Only Wicks");
   oO = (InpOptions == "Only Outbreaks & Retest");

   BullLineColor = InpBullColor;
   BearLineColor = InpBearColor;
   BullFadeColor = FadeColor(InpBullColor, 128);
   BearFadeColor = FadeColor(InpBearColor, 128);
   BullZoneFill  = InpBullZone;
   BearZoneFill  = InpBearZone;
   GrayFill      = FadeColor(C'120,120,120', 80);
   GrayLine      = FadeColor(C'120,120,120', 160);

   FullReset();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   CleanAllObjects();
}

//+------------------------------------------------------------------+
//| OnCalculate                                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
{
   if(rates_total < 2 * InpSwings + 2) return 0;

   // ── Full recalc (indicator first load or bars count changed down) ─
   if(prev_calculated == 0 || rates_total < g_LastBarTotal)
   {
      FullReset();

      // Replay all closed historical bars
      int end = rates_total - 1; // leave last bar for tick processing
      for(int b = InpSwings; b < end; b++)
         ProcessBar(b, rates_total, high, low, close);

      g_LastBarTotal = rates_total;
      g_LastBarTime  = time[rates_total - 1];

      // Now handle live bar tick
      ProcessTick(rates_total, close[rates_total - 1]);
      ChartRedraw(0);
      return rates_total;
   }

   // ── New bar formed since last call ────────────────────────────
   // Process all newly completed bars (usually just 1, rarely 2+)
   if(rates_total > g_LastBarTotal)
   {
      int firstNew = g_LastBarTotal - 1; // the bar that just closed
      int lastNew  = rates_total - 2;    // process up to bar before current live bar

      for(int b = firstNew; b <= lastNew; b++)
         ProcessBar(b, rates_total, high, low, close);

      g_LastBarTotal = rates_total;
      g_LastBarTime  = time[rates_total - 1];
   }

   // ── Intra-bar tick: only update live zones, no heavy work ─────
   ProcessTick(rates_total, close[rates_total - 1]);

   ChartRedraw(0);
   return rates_total;
}
//+------------------------------------------------------------------+  