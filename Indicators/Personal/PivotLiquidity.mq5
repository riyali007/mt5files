//+------------------------------------------------------------------+
//|                                           PivotLiquidity.mq5    |
//|                      Pivot Liquidity Zones  v2.2                 |
//|                                                                  |
//|  BOX GEOMETRY (matches reference image):                         |
//|                                                                  |
//|  SELL zone (swing HIGH):                                         |
//|    wickHigh  ──────────────────  ← box TOP    (wick tip)         |
//|                  SELL BOX                                         |
//|    wickMid   ──────────────────  ← box BOTTOM (50% of wick)      |
//|    bodyTop   (max open/close)                                    |
//|                                                                  |
//|  BUY zone (swing LOW):                                           |
//|    bodyBottom (min open/close)                                   |
//|    wickMid   ──────────────────  ← box TOP    (50% of wick)      |
//|                  BUY BOX                                          |
//|    wickLow   ──────────────────  ← box BOTTOM (wick tip)         |
//|                                                                  |
//|  INVALIDATION:                                                   |
//|    SELL: price CLOSES above wickHigh  → gray out, freeze         |
//|    BUY:  price CLOSES below wickLow   → gray out, freeze         |
//|                                                                  |
//|  Both box edges extend as dotted lines to the right until        |
//|  invalidated. No bar-count limit.                                |
//+------------------------------------------------------------------+
#property copyright "PivotLiquidity v2.2"
#property version   "2.20"
#property indicator_chart_window
#property indicator_plots   0
#property indicator_buffers 0

//+------------------------------------------------------------------+
//| ── INPUTS                                                        |
//+------------------------------------------------------------------+
input group "════════ Pivot Settings ════════"
input int             InpSwings  = 5;              // Swing Length
input ENUM_TIMEFRAMES InpHTF     = PERIOD_CURRENT; // Higher Timeframe
input bool            InpShowCTF = false;          // Also Show Current TF Zones

input group "════════ Zone Appearance ════════"
input int  InpBoxOffset = 0;    // Box Start Offset (bars, 0=pivot)
input bool InpExtend    = true; // Extend Zones Until Invalidated
input int  InpFillAlpha = 40;   // Zone Fill Alpha (0=invisible, 255=solid)

input group "════════ HTF Bull — Buy Zone ════════"
input color InpHTFBullLine  = C'8,153,129';  // HTF Bull Line Color
input color InpHTFBullFill  = C'8,153,129';  // HTF Bull Fill Color
input color InpHTFBullLabel = C'8,153,129';  // HTF Bull Label Color

input group "════════ HTF Bear — Sell Zone ════════"
input color InpHTFBearLine  = C'242,54,69';  // HTF Bear Line Color
input color InpHTFBearFill  = C'242,54,69';  // HTF Bear Fill Color
input color InpHTFBearLabel = C'242,54,69';  // HTF Bear Label Color

input group "════════ CTF Bull — Buy Zone ════════"
input color InpCTFBullLine  = C'0,191,160';  // CTF Bull Line Color
input color InpCTFBullFill  = C'0,191,160';  // CTF Bull Fill Color
input color InpCTFBullLabel = C'0,191,160';  // CTF Bull Label Color

input group "════════ CTF Bear — Sell Zone ════════"
input color InpCTFBearLine  = C'255,80,100'; // CTF Bear Line Color
input color InpCTFBearFill  = C'255,80,100'; // CTF Bear Fill Color
input color InpCTFBearLabel = C'255,80,100'; // CTF Bear Label Color

input group "════════ Invalidated Zone ════════"
input color InpGrayFill  = C'120,120,120'; // Invalidated Fill Color
input color InpGrayLine  = C'120,120,120'; // Invalidated Line Color
input int   InpGrayAlpha = 60;             // Invalidated Alpha (0=invisible, 255=solid)

//+------------------------------------------------------------------+
//| ── RUNTIME COLORS                                                |
//+------------------------------------------------------------------+
color g_HTFBullFill, g_HTFBearFill;
color g_CTFBullFill, g_CTFBearFill;
color g_GrayFill,    g_GrayLine;

//+------------------------------------------------------------------+
//| ── OBJECT NAME COUNTER                                           |
//+------------------------------------------------------------------+
int g_ObjCnt = 0;
string NextName(const string prefix)
{
   g_ObjCnt++;
   return prefix + IntegerToString(g_ObjCnt);
}

//+------------------------------------------------------------------+
//| Alpha-blend color toward white  (0=white, 255=full color)        |
//+------------------------------------------------------------------+
color FadeColor(const color clr, const int alpha255)
{
   uchar a = (uchar)MathMax(0, MathMin(255, alpha255));
   uchar r = (uchar)(((int)((clr >> 16) & 0xFF) * a + 255 * (255 - a)) / 255);
   uchar g = (uchar)(((int)((clr >>  8) & 0xFF) * a + 255 * (255 - a)) / 255);
   uchar b = (uchar)(((int)( clr        & 0xFF) * a + 255 * (255 - a)) / 255);
   return (color)((r << 16) | (g << 8) | b);
}

//+------------------------------------------------------------------+
//| ── LiqZone STRUCT                                                |
//+------------------------------------------------------------------+
struct LiqZone
{
   // Chart object names
   string   rectName;    // filled box  (50% of wick)
   string   topLine;     // dotted line at box top edge
   string   botLine;     // dotted line at box bottom edge
   string   vlineName;   // left-edge vertical bar
   string   labelName;

   // Drawn box boundaries
   double   top;         // box top  price
   double   bottom;      // box bottom price

   // Invalidation level (full wick tip — outside the drawn box)
   //   SELL: wickHigh  → price closes ABOVE this → invalid
   //   BUY:  wickLow   → price closes BELOW this → invalid
   double   wickTip;

   int      direction;      //  1 = SELL,  -1 = BUY
   bool     isBroken;
   datetime leftTime;       // zone left edge time
   datetime rectRightTime;  // cached right edge (skip redundant writes)
};

//+------------------------------------------------------------------+
//| ── TFContext — bundles everything for one timeframe              |
//+------------------------------------------------------------------+
struct TFContext
{
   ENUM_TIMEFRAMES tf;
   string          prefix;      // "PLH_" (HTF) or "PLC_" (CTF)

   // Colors
   color  bullFill, bearFill;
   color  bullLine, bearLine;
   color  bullLabel, bearLabel;

   // OHLCT buffers (as-series: 0=latest)
   double   hi[], lo[], op[], cl[];
   datetime tm[];
   int      bars;

   // Zones for this TF
   LiqZone  zones[];
   int      nZones;

   int      lastTotal;
};

//+------------------------------------------------------------------+
//| ── GLOBAL CONTEXTS                                               |
//+------------------------------------------------------------------+
TFContext g_HTF;
TFContext g_CTF;

//+------------------------------------------------------------------+
//| ── HELPERS                                                       |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES ResolvedHTF() { return (InpHTF == PERIOD_CURRENT) ? Period() : InpHTF; }
bool            HTFisCTF()    { return ResolvedHTF() == Period(); }

//+------------------------------------------------------------------+
//| Load OHLCT into context. Returns bars loaded, 0 on fail.         |
//+------------------------------------------------------------------+
int RefreshTFData(TFContext &ctx)
{
   int count = iBars(_Symbol, ctx.tf);
   if(count < 2 * InpSwings + 4) return 0;

   int n = MathMin(count, 3000);
   ArraySetAsSeries(ctx.hi, true);
   ArraySetAsSeries(ctx.lo, true);
   ArraySetAsSeries(ctx.op, true);
   ArraySetAsSeries(ctx.cl, true);
   ArraySetAsSeries(ctx.tm, true);

   int cH = CopyHigh (_Symbol, ctx.tf, 0, n, ctx.hi);
   int cL = CopyLow  (_Symbol, ctx.tf, 0, n, ctx.lo);
   int cO = CopyOpen (_Symbol, ctx.tf, 0, n, ctx.op);
   int cC = CopyClose(_Symbol, ctx.tf, 0, n, ctx.cl);
   int cT = CopyTime (_Symbol, ctx.tf, 0, n, ctx.tm);

   if(cH <= 0 || cL <= 0 || cO <= 0 || cC <= 0 || cT <= 0) return 0;
   ctx.bars = MathMin(MathMin(MathMin(MathMin(cH, cL), cO), cC), cT);
   return ctx.bars;
}

//+------------------------------------------------------------------+
//| Pivot detection — operates on TFContext arrays (as-series)       |
//+------------------------------------------------------------------+
double PivHigh(const TFContext &ctx, const int idx)
{
   int len = InpSwings;
   if(idx - len < 0 || idx + len >= ctx.bars) return 0.0;
   double ph = ctx.hi[idx];
   for(int j = idx - len; j <= idx + len; j++)
   {
      if(j == idx) continue;
      if(ctx.hi[j] >= ph) return 0.0;
   }
   return ph;
}

double PivLow(const TFContext &ctx, const int idx)
{
   int len = InpSwings;
   if(idx - len < 0 || idx + len >= ctx.bars) return 0.0;
   double pl = ctx.lo[idx];
   for(int j = idx - len; j <= idx + len; j++)
   {
      if(j == idx) continue;
      if(ctx.lo[j] <= pl) return 0.0;
   }
   return pl;
}

//+------------------------------------------------------------------+
//| Check if zone already registered for this left-time + direction  |
//+------------------------------------------------------------------+
bool ZoneExists(const TFContext &ctx, const datetime tLeft, const int dir)
{
   for(int i = 0; i < ctx.nZones; i++)
      if(ctx.zones[i].leftTime == tLeft && ctx.zones[i].direction == dir)
         return true;
   return false;
}

//+------------------------------------------------------------------+
//| Create all chart objects for one zone                            |
//|                                                                  |
//| top / bottom  = the DRAWN BOX bounds (50% of wick)               |
//| wickTip       = full wick tip (INVALIDATION level)               |
//+------------------------------------------------------------------+
void CreateZone(TFContext  &ctx,
                LiqZone    &z,
                datetime    tLeft,
                double      top,
                double      bottom,
                double      wickTip,
                int         direction)
{
   z.top          = top;
   z.bottom       = bottom;
   z.wickTip      = wickTip;
   z.direction    = direction;
   z.isBroken     = false;
   z.leftTime     = tLeft;
   z.rectRightTime= tLeft;

   double midY    = (top + bottom) * 0.5;
   color  fill    = (direction ==  1) ? ctx.bearFill  : ctx.bullFill;
   color  lineClr = (direction ==  1) ? ctx.bearLine  : ctx.bullLine;
   color  lblClr  = (direction ==  1) ? ctx.bearLabel : ctx.bullLabel;
   string lblTxt  = (direction ==  1) ? "SELL Zone"   : "BUY Zone";

   // ── Filled rectangle (the 50% wick box) ──────────────────────
   z.rectName = NextName(ctx.prefix + "RCT_");
   if(ObjectCreate(0, z.rectName, OBJ_RECTANGLE, 0, tLeft, top, tLeft, bottom))
   {
      ObjectSetInteger(0, z.rectName, OBJPROP_COLOR,      fill);
      ObjectSetInteger(0, z.rectName, OBJPROP_FILL,       true);
      ObjectSetInteger(0, z.rectName, OBJPROP_BACK,       true);
      ObjectSetInteger(0, z.rectName, OBJPROP_WIDTH,      0);
      ObjectSetInteger(0, z.rectName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, z.rectName, OBJPROP_HIDDEN,     true);
   }

   // ── Top dotted extension line (box top edge) ──────────────────
   z.topLine = NextName(ctx.prefix + "TL_");
   if(ObjectCreate(0, z.topLine, OBJ_TREND, 0, tLeft, top, tLeft, top))
   {
      ObjectSetInteger(0, z.topLine, OBJPROP_COLOR,      lineClr);
      ObjectSetInteger(0, z.topLine, OBJPROP_WIDTH,      1);
      ObjectSetInteger(0, z.topLine, OBJPROP_STYLE,      STYLE_DOT);
      ObjectSetInteger(0, z.topLine, OBJPROP_RAY_RIGHT,  false);
      ObjectSetInteger(0, z.topLine, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, z.topLine, OBJPROP_HIDDEN,     true);
   }

   // ── Bottom dotted extension line (box bottom edge) ────────────
   z.botLine = NextName(ctx.prefix + "BL_");
   if(ObjectCreate(0, z.botLine, OBJ_TREND, 0, tLeft, bottom, tLeft, bottom))
   {
      ObjectSetInteger(0, z.botLine, OBJPROP_COLOR,      lineClr);
      ObjectSetInteger(0, z.botLine, OBJPROP_WIDTH,      1);
      ObjectSetInteger(0, z.botLine, OBJPROP_STYLE,      STYLE_DOT);
      ObjectSetInteger(0, z.botLine, OBJPROP_RAY_RIGHT,  false);
      ObjectSetInteger(0, z.botLine, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, z.botLine, OBJPROP_HIDDEN,     true);
   }

   // ── Left-edge vertical bar ────────────────────────────────────
   z.vlineName = NextName(ctx.prefix + "VL_");
   if(ObjectCreate(0, z.vlineName, OBJ_TREND, 0, tLeft, top, tLeft, bottom))
   {
      ObjectSetInteger(0, z.vlineName, OBJPROP_COLOR,      lineClr);
      ObjectSetInteger(0, z.vlineName, OBJPROP_WIDTH,      2);
      ObjectSetInteger(0, z.vlineName, OBJPROP_STYLE,      STYLE_SOLID);
      ObjectSetInteger(0, z.vlineName, OBJPROP_RAY_RIGHT,  false);
      ObjectSetInteger(0, z.vlineName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, z.vlineName, OBJPROP_HIDDEN,     true);
   }

   // ── Label centred in the box ──────────────────────────────────
   z.labelName = NextName(ctx.prefix + "LBL_");
   if(ObjectCreate(0, z.labelName, OBJ_TEXT, 0, tLeft, midY))
   {
      ObjectSetString (0, z.labelName, OBJPROP_TEXT,       lblTxt);
      ObjectSetInteger(0, z.labelName, OBJPROP_COLOR,      lblClr);
      ObjectSetInteger(0, z.labelName, OBJPROP_FONTSIZE,   8);
      ObjectSetInteger(0, z.labelName, OBJPROP_ANCHOR,     ANCHOR_LEFT);
      ObjectSetInteger(0, z.labelName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, z.labelName, OBJPROP_HIDDEN,     true);
   }
}

//+------------------------------------------------------------------+
//| Extend zone right edge — skip write if time unchanged            |
//+------------------------------------------------------------------+
void ExtendZone(LiqZone &z, const datetime tNew)
{
   if(z.rectName == "" || tNew <= z.rectRightTime) return;
   z.rectRightTime = tNew;

   // Extend filled box
   ObjectSetInteger(0, z.rectName, OBJPROP_TIME, 1, tNew);

   // Extend both dotted edge lines
   ObjectSetInteger(0, z.topLine,  OBJPROP_TIME, 1, tNew);
   ObjectSetInteger(0, z.botLine,  OBJPROP_TIME, 1, tNew);

   // Move label to horizontal midpoint
   datetime tMid = z.leftTime + (tNew - z.leftTime) / 2;
   ObjectSetInteger(0, z.labelName, OBJPROP_TIME, tMid);
}

//+------------------------------------------------------------------+
//| Freeze + gray out zone on invalidation — called ONCE             |
//+------------------------------------------------------------------+
void InvalidateZone(LiqZone &z, const datetime tSweep)
{
   if(z.rectName == "") return;
   z.isBroken      = true;
   z.rectRightTime = tSweep;

   // Freeze all right edges at sweep bar
   ObjectSetInteger(0, z.rectName, OBJPROP_TIME,  1,      tSweep);
   ObjectSetInteger(0, z.topLine,  OBJPROP_TIME,  1,      tSweep);
   ObjectSetInteger(0, z.botLine,  OBJPROP_TIME,  1,      tSweep);

   // Centre label in frozen zone
   datetime tMid = z.leftTime + (tSweep - z.leftTime) / 2;
   ObjectSetInteger(0, z.labelName, OBJPROP_TIME, tMid);

   // Gray out everything
   ObjectSetInteger(0, z.rectName,  OBJPROP_COLOR, g_GrayFill);
   ObjectSetInteger(0, z.topLine,   OBJPROP_COLOR, g_GrayLine);
   ObjectSetInteger(0, z.botLine,   OBJPROP_COLOR, g_GrayLine);
   ObjectSetInteger(0, z.vlineName, OBJPROP_COLOR, g_GrayLine);
   ObjectSetInteger(0, z.labelName, OBJPROP_COLOR, g_GrayLine);
}

//+------------------------------------------------------------------+
//| Push zone into context array                                     |
//+------------------------------------------------------------------+
void PushZone(TFContext &ctx, LiqZone &z)
{
   ArrayResize(ctx.zones, ctx.nZones + 1);
   ctx.zones[ctx.nZones] = z;
   ctx.nZones++;
}

//+------------------------------------------------------------------+
//| Calculate shifted time for box start                             |
//+------------------------------------------------------------------+
datetime GetOffsetTime(const TFContext &ctx, int pivotIdx, int offset)
{
   int targetIdx = pivotIdx - offset;
   
   if(targetIdx >= 0 && targetIdx < ctx.bars)
      return ctx.tm[targetIdx];
      
   // If targetIdx < 0 (future bars, beyond current price)
   if(targetIdx < 0)
   {
      datetime baseTime = ctx.tm[0];
      int diff = -targetIdx;
      return baseTime + diff * PeriodSeconds(ctx.tf);
   }
   
   // If targetIdx >= ctx.bars (deep past, beyond loaded history)
   datetime baseTime = ctx.tm[ctx.bars - 1];
   int diff = targetIdx - (ctx.bars - 1);
   return baseTime - diff * PeriodSeconds(ctx.tf);
}

//+------------------------------------------------------------------+
//| Process one source-TF bar — detect pivot, compute geometry,      |
//| create zone objects.                                             |
//|                                                                  |
//| as-series arrays: idx 0 = newest, idx N = oldest                 |
//| tfIdx  = pivot candidate bar offset                              |
//+------------------------------------------------------------------+
void ProcessSourceBar(TFContext &ctx, const int tfIdx)
{
   if(tfIdx < 0) return;
   
   // Calculate zone start time applying the offset
   datetime tZoneStart = GetOffsetTime(ctx, tfIdx, InpBoxOffset);

   // ══════════════════════════════════════════════════════════════
   // SELL zone — Swing HIGH
   //
   //   Box = the upper wick region of the pivot candle,
   //   drawn to the right starting from the offset time.
   //
   //   boxTop    = wickHigh  (candle high = wick tip)
   //   boxBottom = bodyTop   (max of open, close)
   //   height    = wickLen
   //
   //   Invalidation: price (high) crosses ABOVE boxTop
   // ══════════════════════════════════════════════════════════════
   double ph = PivHigh(ctx, tfIdx);
   if(ph > 0.0 && !ZoneExists(ctx, tZoneStart, 1))
   {
      double wickHigh = ctx.hi[tfIdx];
      double bodyTop  = MathMax(ctx.op[tfIdx], ctx.cl[tfIdx]);
      double wickLen  = wickHigh - bodyTop;

      if(wickLen > _Point)
      {
         LiqZone z;
         // wickTip = boxTop = invalidation level (price crosses above this)
         CreateZone(ctx, z, tZoneStart, wickHigh, bodyTop, wickHigh, 1);
         PushZone(ctx, z);
      }
   }

   // ══════════════════════════════════════════════════════════════
   // BUY zone — Swing LOW
   //
   //   Box = the lower wick region of the pivot candle,
   //   drawn to the right starting from the offset time.
   //
   //   boxTop    = bodyBottom  (min of open, close)
   //   boxBottom = wickLow     (candle low = wick tip)
   //   height    = wickLen
   //
   //   Invalidation: price (low) crosses BELOW boxBottom
   // ══════════════════════════════════════════════════════════════
   double pl = PivLow(ctx, tfIdx);
   if(pl > 0.0 && !ZoneExists(ctx, tZoneStart, -1))
   {
      double wickLow    = ctx.lo[tfIdx];
      double bodyBottom = MathMin(ctx.op[tfIdx], ctx.cl[tfIdx]);
      double wickLen    = bodyBottom - wickLow;

      if(wickLen > _Point)
      {
         LiqZone z;
         // wickTip = boxBottom = invalidation level (price crosses below this)
         CreateZone(ctx, z, tZoneStart, bodyBottom, wickLow, wickLow, -1);
         PushZone(ctx, z);
      }
   }
}

//+------------------------------------------------------------------+
//| Scan all valid historical bars for a context                     |
//+------------------------------------------------------------------+
void ScanAllBars(TFContext &ctx)
{
   int lo = InpSwings + 1;
   int hi = ctx.bars - InpSwings - 1;
   for(int idx = lo; idx <= hi; idx++)
      ProcessSourceBar(ctx, idx);
}

//+------------------------------------------------------------------+
//| Update all zones: invalidate when price CROSSES the level,       |
//| extend on every bar/tick until invalidated.                      |
//|                                                                  |
//| SELL invalidation: high  > wickTip  (any bar/tick high crosses)  |
//| BUY  invalidation: low   < wickTip  (any bar/tick low crosses)   |
//+------------------------------------------------------------------+
void UpdateZones(TFContext     &ctx,
                 const double   high,
                 const double   low,
                 const datetime tBar)
{
   for(int i = 0; i < ctx.nZones; i++)
   {
      if(ctx.zones[i].isBroken)         continue;
      if(ctx.zones[i].leftTime >= tBar) continue;

      // Invalidation fires on ANY bar (closed or live tick) when price crosses
      bool broken = (ctx.zones[i].direction ==  1 && high > ctx.zones[i].wickTip)
                 || (ctx.zones[i].direction == -1 && low  < ctx.zones[i].wickTip);
      if(broken)
      {
         InvalidateZone(ctx.zones[i], tBar);
         continue;
      }

      // Extend right edge until invalidated
      if(InpExtend)
         ExtendZone(ctx.zones[i], tBar);
   }
}

//+------------------------------------------------------------------+
//| Delete all objects with a given name prefix                      |
//+------------------------------------------------------------------+
void CleanObjects(const string prefix)
{
   int total = ObjectsTotal(0);
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i);
      if(StringFind(nm, prefix) == 0)
         ObjectDelete(0, nm);
   }
}

//+------------------------------------------------------------------+
//| Reset one TFContext                                              |
//+------------------------------------------------------------------+
void ResetContext(TFContext &ctx)
{
   CleanObjects(ctx.prefix);
   ArrayResize(ctx.zones, 0);
   ctx.nZones    = 0;
   ctx.bars      = 0;
   ctx.lastTotal = 0;
}

//+------------------------------------------------------------------+
//| Full reset                                                       |
//+------------------------------------------------------------------+
void FullReset()
{
   ResetContext(g_HTF);
   ResetContext(g_CTF);
   g_ObjCnt = 0;
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpSwings < 1) { Alert("Swing Length must be >= 1"); return INIT_PARAMETERS_INCORRECT; }

   int fillA = MathMax(0, MathMin(255, InpFillAlpha));
   int grayA = MathMax(0, MathMin(255, InpGrayAlpha));

   g_HTFBullFill = FadeColor(InpHTFBullFill, fillA);
   g_HTFBearFill = FadeColor(InpHTFBearFill, fillA);
   g_CTFBullFill = FadeColor(InpCTFBullFill, fillA);
   g_CTFBearFill = FadeColor(InpCTFBearFill, fillA);
   g_GrayFill    = FadeColor(InpGrayFill,    grayA);
   g_GrayLine    = FadeColor(InpGrayLine,    160);

   // HTF context
   g_HTF.tf        = ResolvedHTF();
   g_HTF.prefix    = "PLH_";
   g_HTF.bullFill  = g_HTFBullFill; g_HTF.bearFill  = g_HTFBearFill;
   g_HTF.bullLine  = InpHTFBullLine; g_HTF.bearLine  = InpHTFBearLine;
   g_HTF.bullLabel = InpHTFBullLabel; g_HTF.bearLabel = InpHTFBearLabel;
   g_HTF.nZones    = 0; g_HTF.bars = 0; g_HTF.lastTotal = 0;

   // CTF context
   g_CTF.tf        = Period();
   g_CTF.prefix    = "PLC_";
   g_CTF.bullFill  = g_CTFBullFill; g_CTF.bearFill  = g_CTFBearFill;
   g_CTF.bullLine  = InpCTFBullLine; g_CTF.bearLine  = InpCTFBearLine;
   g_CTF.bullLabel = InpCTFBullLabel; g_CTF.bearLabel = InpCTFBearLabel;
   g_CTF.nZones    = 0; g_CTF.bars = 0; g_CTF.lastTotal = 0;

   FullReset();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   CleanObjects("PLH_");
   CleanObjects("PLC_");
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
   if(rates_total < 3) return 0;

   bool runCTF = InpShowCTF && !HTFisCTF();

   // ══════════════════════════════════════════════════════════════
   // FULL RECALC
   // ══════════════════════════════════════════════════════════════
   if(prev_calculated == 0 || rates_total < g_HTF.lastTotal)
   {
      FullReset();

      if(RefreshTFData(g_HTF) < 2 * InpSwings + 4)
      {
         Print("PivotLiquidity: waiting for HTF bars...");
         return 0;
      }
      ScanAllBars(g_HTF);

      if(runCTF && RefreshTFData(g_CTF) >= 2 * InpSwings + 4)
         ScanAllBars(g_CTF);

      // Replay all closed historical chart bars for invalidation
      // time[] / high[] / low[] are NOT as-series inside OnCalculate
      for(int b = 1; b < rates_total - 1; b++)
      {
         UpdateZones(g_HTF, high[b], low[b], time[b]);
         if(runCTF) UpdateZones(g_CTF, high[b], low[b], time[b]);
      }

      g_HTF.lastTotal = rates_total;
      g_CTF.lastTotal = rates_total;

      // Live bar tick
      double   ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double   bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      datetime tNow = TimeCurrent();
      UpdateZones(g_HTF, ask, bid, tNow);
      if(runCTF) UpdateZones(g_CTF, ask, bid, tNow);

      ChartRedraw(0);
      return rates_total;
   }

   // ══════════════════════════════════════════════════════════════
   // NEW BAR
   // ══════════════════════════════════════════════════════════════
   if(rates_total > g_HTF.lastTotal)
   {
      g_HTF.lastTotal = rates_total;
      g_CTF.lastTotal = rates_total;

      // HTF — check for newly confirmable pivot
      if(RefreshTFData(g_HTF) >= 2 * InpSwings + 4)
      {
         int newPivIdx = InpSwings + 1;
         if(newPivIdx < g_HTF.bars - InpSwings - 1)
            ProcessSourceBar(g_HTF, newPivIdx);
      }

      // CTF — same
      if(runCTF && RefreshTFData(g_CTF) >= 2 * InpSwings + 4)
      {
         int newPivIdx = InpSwings + 1;
         if(newPivIdx < g_CTF.bars - InpSwings - 1)
            ProcessSourceBar(g_CTF, newPivIdx);
      }

      // Check bar that just closed using its actual high/low
      double   prevHigh = high[rates_total - 2];
      double   prevLow  = low[rates_total - 2];
      datetime prevTime = time[rates_total - 2];
      UpdateZones(g_HTF, prevHigh, prevLow, prevTime);
      if(runCTF) UpdateZones(g_CTF, prevHigh, prevLow, prevTime);
   }

   // ══════════════════════════════════════════════════════════════
   // INTRA-BAR TICK — check current ask/bid for immediate cross
   // ══════════════════════════════════════════════════════════════
   double   ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double   bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   datetime tNow = TimeCurrent();
   UpdateZones(g_HTF, ask, bid, tNow);
   if(runCTF) UpdateZones(g_CTF, ask, bid, tNow);

   ChartRedraw(0);
   return rates_total;
}
//+------------------------------------------------------------------+
