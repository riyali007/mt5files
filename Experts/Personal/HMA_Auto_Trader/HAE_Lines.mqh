//+------------------------------------------------------------------+
//|                                                 HAE_Lines.mqh    |
//|  HMA Active EA  v0.1                                              |
//|  File 4/10 - inflection lines, grouping, range filter, watching   |
//|  state and the candle-close decision (breakout / rejection).      |
//|                                                                   |
//|  Runs ONCE per new chart bar after HaeMABuild(). It replays the   |
//|  analysed history bar by bar, so line states are deterministic    |
//|  after a restart. Only decisions on the LAST CLOSED bar are       |
//|  returned as tradeable signals (HaeSignals[]).                    |
//|                                                                   |
//|  Per bar i (closed bars only):                                    |
//|   1. evaluate every active line / box against candle i            |
//|   2. detect MA turning points (flat runs handled)                 |
//|   3. confirmed pivot -> new line (pre-scan, range filter)         |
//|  A new line is live from the bar AFTER its confirmation bar.      |
//|                                                                   |
//|  Decision rules (line at price P, "side" = where price was):      |
//|   price below P : close >= P + minClose            -> BUY  breakout
//|                   high >= P + minWick and                         |
//|                   close <= P - minBack             -> SELL rejection
//|   price above P : exact mirror (SELL breakout / BUY rejection)    |
//|   a weaker close past P only flips the side (line keeps watching) |
//|  A decision needs the line to be WATCHED at the start of the      |
//|  candle: previous close or current open within the watch distance.|
//|                                                                   |
//|  IMPORTANT for other modules: arrays keep spare capacity - always |
//|  loop with HaeLineCount / HaeBoxCount, never ArraySize().         |
//+------------------------------------------------------------------+
#ifndef HAE_LINES_MQH
#define HAE_LINES_MQH

#include "HAE_Defines.mqh"
#include "HAE_Symbol.mqh"
#include "HAE_MA.mqh"

//--- public output
SHaeLine   HaeLines[];
int        HaeLineCount   = 0;
SHaeBox    HaeBoxes[];
int        HaeBoxCount    = 0;
SHaeSignal HaeEvents[];            // every decision in the analysed history (drawing / review)
int        HaeEventCount  = 0;
SHaeSignal HaeSignals[];           // decisions on the last closed bar (trading)
int        HaeSignalCount = 0;
bool       HaeLinesValid  = false;
datetime   HaeLastClosedTime = 0;  // open time of the last closed chart bar

//--- runtime data per line (parallel to HaeLines)
int  s_lnSide[];    // +1 price above the line, -1 below
int  s_lnBar[];     // pivot bar index (age)
int  s_lnGroup[];   // same-direction group id
bool s_lnWatch[];   // watched for the forming bar (display)

//--- runtime data per box (parallel to HaeBoxes)
int  s_bxSide[];    // -1 below, 0 inside, +1 above
int  s_bxBar[];     // creation bar index (age)
bool s_bxWatch[];

//--- active lists
int  s_act[];
int  s_actCount   = 0;
int  s_bxAct[];
int  s_bxActCount = 0;
bool s_actDirty    = false;
bool s_groupsDirty = false;
int  s_groupSeq    = 0;
int  s_sortTmp[];

//--- per-build constants (price units)
double s_pOffset, s_pWatch, s_pClose, s_pWick, s_pBack, s_pGroup, s_pRange;

//+------------------------------------------------------------------+
//| Keys and accessors                                                |
//+------------------------------------------------------------------+
string HaeLineKey(const int j)
{
   return (HaeLines[j].upper ? HAE_KEY_UPPER : HAE_KEY_LOWER) + IntegerToString((long)HaeLines[j].startTime);
}

string HaeBoxKey(const int b)
{
   return HAE_KEY_BOX + IntegerToString((long)HaeBoxes[b].startTime);
}

bool HaeLineWatching(const int j) { return (j >= 0 && j < HaeLineCount && s_lnWatch[j]); }
bool HaeBoxWatching(const int b)  { return (b >= 0 && b < HaeBoxCount  && s_bxWatch[b]); }
int  HaeLineGroup(const int j)    { return (j >= 0 && j < HaeLineCount) ? s_lnGroup[j] : -1; }

//+------------------------------------------------------------------+
//| Capacity                                                          |
//+------------------------------------------------------------------+
void HaeLineReserve(const int need)
{
   if(ArraySize(HaeLines) >= need) return;
   const int sz = need + 128;
   ArrayResize(HaeLines,  sz);
   ArrayResize(s_lnSide,  sz);
   ArrayResize(s_lnBar,   sz);
   ArrayResize(s_lnGroup, sz);
   ArrayResize(s_lnWatch, sz);
   ArrayResize(s_act,     sz);
   ArrayResize(s_sortTmp, sz);
}

void HaeBoxReserve(const int need)
{
   if(ArraySize(HaeBoxes) >= need) return;
   const int sz = need + 32;
   ArrayResize(HaeBoxes,  sz);
   ArrayResize(s_bxSide,  sz);
   ArrayResize(s_bxBar,   sz);
   ArrayResize(s_bxWatch, sz);
   ArrayResize(s_bxAct,   sz);
}

void HaeAddEvent(const ENUM_HAE_SIGNAL type, const string key, const double level, const int i, const bool fromBox)
{
   if(ArraySize(HaeEvents) <= HaeEventCount) ArrayResize(HaeEvents, HaeEventCount + 64);
   HaeEvents[HaeEventCount].type     = type;
   HaeEvents[HaeEventCount].key      = key;
   HaeEvents[HaeEventCount].level    = level;
   HaeEvents[HaeEventCount].barTime  = HaeRates[i].time;
   HaeEvents[HaeEventCount].barHigh  = HaeRates[i].high;
   HaeEvents[HaeEventCount].barLow   = HaeRates[i].low;
   HaeEvents[HaeEventCount].barClose = HaeRates[i].close;
   HaeEvents[HaeEventCount].fromBox  = fromBox;
   HaeEventCount++;
}

//+------------------------------------------------------------------+
//| Active-list maintenance                                           |
//+------------------------------------------------------------------+
void HaeCompact()
{
   int w = 0;
   for(int k = 0; k < s_actCount; k++)
      if(HaeLines[s_act[k]].state == LST_ACTIVE) s_act[w++] = s_act[k];
   s_actCount = w;

   w = 0;
   for(int k = 0; k < s_bxActCount; k++)
      if(HaeBoxes[s_bxAct[k]].alive) s_bxAct[w++] = s_bxAct[k];
   s_bxActCount = w;
   s_actDirty = false;
}

void HaeEndLine(const int j, const ENUM_HAE_LINE_STATE st, const int i)
{
   HaeLines[j].state   = st;
   HaeLines[j].endTime = HaeRates[i].time;
   HaeLines[j].rep     = false;
   s_actDirty    = true;
   s_groupsDirty = true;
}

void HaeEndBox(const int b, const int i)
{
   HaeBoxes[b].alive   = false;
   HaeBoxes[b].endTime = HaeRates[i].time;
   for(int j = 0; j < HaeLineCount; j++)
      if(HaeLines[j].state == LST_BOXED && HaeLines[j].boxId == b && HaeLines[j].endTime == 0)
         HaeLines[j].endTime = HaeRates[i].time;
   s_actDirty = true;
}

// Consumes the whole same-direction group of line j
void HaeConsumeGroup(const int j, const int i)
{
   const int  g  = s_lnGroup[j];
   const bool up = HaeLines[j].upper;
   for(int k = 0; k < s_actCount; k++) {
      const int jj = s_act[k];
      if(HaeLines[jj].state != LST_ACTIVE || HaeLines[jj].upper != up) continue;
      if(jj == j || s_lnGroup[jj] == g) HaeEndLine(jj, LST_USED, i);
   }
}

//+------------------------------------------------------------------+
//| Grouping: nearby same-direction lines form one group. The         |
//| OUTERMOST line is the representative (upper -> highest,           |
//| lower -> lowest). Only representatives produce signals.           |
//+------------------------------------------------------------------+
void HaeRegroup()
{
   s_groupsDirty = false;
   const bool on = (Cfg.grouping && Cfg.groupDistPts > 0);

   for(int dir = 0; dir < 2; dir++) {
      const bool up = (dir == 0);
      int cnt = 0;
      for(int k = 0; k < s_actCount; k++) {
         const int j = s_act[k];
         if(HaeLines[j].state == LST_ACTIVE && HaeLines[j].upper == up) s_sortTmp[cnt++] = j;
      }
      if(cnt == 0) continue;

      if(!on) {
         for(int k = 0; k < cnt; k++) { s_lnGroup[s_sortTmp[k]] = ++s_groupSeq; HaeLines[s_sortTmp[k]].rep = true; }
         continue;
      }

      // insertion sort ascending by price (active lines per side are few)
      for(int a = 1; a < cnt; a++) {
         const int key = s_sortTmp[a];
         const double kp = HaeLines[key].price;
         int b = a - 1;
         while(b >= 0 && HaeLines[s_sortTmp[b]].price > kp) { s_sortTmp[b + 1] = s_sortTmp[b]; b--; }
         s_sortTmp[b + 1] = key;
      }

      int s = 0;
      while(s < cnt) {
         int e = s;
         while(e + 1 < cnt && HaeLines[s_sortTmp[e + 1]].price - HaeLines[s_sortTmp[s]].price <= s_pGroup + 1e-12) e++;
         const int gid = ++s_groupSeq;
         for(int k = s; k <= e; k++) { s_lnGroup[s_sortTmp[k]] = gid; HaeLines[s_sortTmp[k]].rep = false; }
         HaeLines[up ? s_sortTmp[e] : s_sortTmp[s]].rep = true;
         s = e + 1;
      }
   }
}

//+------------------------------------------------------------------+
//| Candle decision against one level                                 |
//+------------------------------------------------------------------+
ENUM_HAE_SIGNAL HaeDecideLevel(const double P, const int side, const int i)
{
   const double h = HaeRates[i].high, l = HaeRates[i].low, c = HaeRates[i].close;
   if(side < 0) {                                                        // price came from below
      if(c > P && c >= P + s_pClose)                        return SIGNAL_BUY_BREAKOUT;
      if(h >= P + s_pWick && c < P && c <= P - s_pBack)     return SIGNAL_SELL_REJECTION;
   } else {                                                              // price came from above
      if(c < P && c <= P - s_pClose)                        return SIGNAL_SELL_BREAKOUT;
      if(l <= P - s_pWick && c > P && c >= P + s_pBack)     return SIGNAL_BUY_REJECTION;
   }
   return SIGNAL_NONE;
}

bool HaeNear(const double price, const double level) { return (MathAbs(price - level) <= s_pWatch + 1e-12); }

//+------------------------------------------------------------------+
//| Evaluate one active line on closed bar i                          |
//+------------------------------------------------------------------+
void HaeEvalLine(const int j, const int i)
{
   if(Cfg.lineMaxAgeBars > 0 && i - s_lnBar[j] > Cfg.lineMaxAgeBars) { HaeEndLine(j, LST_USED, i); return; }

   const double P = HaeLines[j].price;
   const double c = HaeRates[i].close;
   const int newSide = (c > P) ? 1 : (c < P ? -1 : s_lnSide[j]);

   if(!HaeLines[j].rep) {                        // group member: silently used when a close crosses it
      if(newSide != s_lnSide[j]) HaeEndLine(j, LST_USED, i);
      return;
   }

   const bool watched = HaeNear(HaeRates[i - 1].close, P) || HaeNear(HaeRates[i].open, P);
   if(watched) {
      const ENUM_HAE_SIGNAL sig = HaeDecideLevel(P, s_lnSide[j], i);
      if(sig != SIGNAL_NONE && HaeSignalAllowed(sig)) {
         HaeAddEvent(sig, HaeLineKey(j), P, i, false);
         HaeConsumeGroup(j, i);
         return;
      }
   }
   s_lnSide[j] = newSide;
}

//+------------------------------------------------------------------+
//| Evaluate one range box on closed bar i                            |
//| Box = thick line: breakout needs a close beyond the far edge,     |
//| rejection = wick past the near edge, close back.                  |
//+------------------------------------------------------------------+
void HaeEvalBox(const int b, const int i)
{
   if(Cfg.lineMaxAgeBars > 0 && i - s_bxBar[b] > Cfg.lineMaxAgeBars) { HaeEndBox(b, i); return; }

   const double top = HaeBoxes[b].top, bot = HaeBoxes[b].bottom;
   const double h = HaeRates[i].high, l = HaeRates[i].low, c = HaeRates[i].close;
   const int side = s_bxSide[b];
   const double pc = HaeRates[i - 1].close, op = HaeRates[i].open;
   const bool watched = (side == 0) || HaeNear(pc, top) || HaeNear(pc, bot) || HaeNear(op, top) || HaeNear(op, bot);

   ENUM_HAE_SIGNAL sig = SIGNAL_NONE;
   double level = 0.0;
   if(watched) {
      if(side <= 0 && c > top && c >= top + s_pClose)      { sig = SIGNAL_BUY_BREAKOUT;  level = top; }
      else if(side >= 0 && c < bot && c <= bot - s_pClose) { sig = SIGNAL_SELL_BREAKOUT; level = bot; }
      else if(side == 0) {
         if(h >= top + s_pWick && c < top && c <= top - s_pBack)      { sig = SIGNAL_SELL_REJECTION; level = top; }
         else if(l <= bot - s_pWick && c > bot && c >= bot + s_pBack) { sig = SIGNAL_BUY_REJECTION;  level = bot; }
      }
      else if(side < 0) {
         if(h >= bot + s_pWick && c < bot && c <= bot - s_pBack)      { sig = SIGNAL_SELL_REJECTION; level = bot; }
      }
      else {
         if(l <= top - s_pWick && c > top && c >= top + s_pBack)      { sig = SIGNAL_BUY_REJECTION;  level = top; }
      }
   }

   if(sig != SIGNAL_NONE && HaeSignalAllowed(sig)) {
      HaeAddEvent(sig, HaeBoxKey(b), level, i, true);
      HaeEndBox(b, i);
      return;
   }
   s_bxSide[b] = (c > top) ? 1 : (c < bot ? -1 : 0);
}

//+------------------------------------------------------------------+
//| Range filter                                                      |
//+------------------------------------------------------------------+
int HaeBoxSideOf(const int b, const double c)
{
   return (c > HaeBoxes[b].top) ? 1 : (c < HaeBoxes[b].bottom ? -1 : 0);
}

void HaeBoxAbsorb(const int b, const int j)
{
   HaeLines[j].state = LST_BOXED;
   HaeLines[j].boxId = b;
   HaeLines[j].rep   = false;
   if(HaeLines[j].price > HaeBoxes[b].top)    HaeBoxes[b].top    = HaeLines[j].price;
   if(HaeLines[j].price < HaeBoxes[b].bottom) HaeBoxes[b].bottom = HaeLines[j].price;
   s_actDirty = true;
   s_groupsDirty = true;
}

int HaeNewBox(const int i, const double price)
{
   // capacity: expire the oldest alive box
   if(s_bxActCount >= HAE_MAX_BOXES) {
      int old = -1;
      for(int k = 0; k < s_bxActCount; k++) {
         const int bb = s_bxAct[k];
         if(HaeBoxes[bb].alive && (old < 0 || s_bxBar[bb] < s_bxBar[old])) old = bb;
      }
      if(old >= 0) HaeEndBox(old, i);
      HaeCompact();
   }

   datetime t = HaeRates[i].time;
   for(int k = 0; k < HaeBoxCount; k++) if(HaeBoxes[k].startTime == t) t++;   // unique key

   HaeBoxReserve(HaeBoxCount + 1);
   const int b = HaeBoxCount++;
   HaeBoxes[b].startTime = t;
   HaeBoxes[b].endTime   = 0;
   HaeBoxes[b].top       = price;
   HaeBoxes[b].bottom    = price;
   HaeBoxes[b].alive     = true;
   s_bxBar[b]   = i;
   s_bxWatch[b] = false;
   s_bxAct[s_bxActCount++] = b;
   return b;
}

// New line j (still ACTIVE) against opposite active lines and boxes
void HaeRangeFilter(const int j, const int i)
{
   const double P  = HaeLines[j].price;
   const bool   up = HaeLines[j].upper;
   const double c  = HaeRates[i].close;

   //--- BOX mode: a line near an existing box joins it
   if(Cfg.rangeMode == RANGE_BOX) {
      for(int k = 0; k < s_bxActCount; k++) {
         const int b = s_bxAct[k];
         if(!HaeBoxes[b].alive) continue;
         if(P < HaeBoxes[b].bottom - s_pRange - 1e-12 || P > HaeBoxes[b].top + s_pRange + 1e-12) continue;
         HaeBoxAbsorb(b, j);
         for(int q = 0; q < s_actCount; q++) {                   // opposite lines conflicting with the new one
            const int o = s_act[q];
            if(HaeLines[o].state == LST_ACTIVE && HaeLines[o].upper != up && MathAbs(HaeLines[o].price - P) <= s_pRange + 1e-12)
               HaeBoxAbsorb(b, o);
         }
         s_bxSide[b] = HaeBoxSideOf(b, c);
         return;
      }
   }

   //--- opposite-direction conflicts (distance between DRAWN lines)
   bool any = false;
   for(int q = 0; q < s_actCount; q++) {
      const int o = s_act[q];
      if(HaeLines[o].state != LST_ACTIVE || HaeLines[o].upper == up) continue;
      if(MathAbs(HaeLines[o].price - P) <= s_pRange + 1e-12) { any = true; break; }
   }
   if(!any) return;

   int box = -1;
   if(Cfg.rangeMode == RANGE_BOX) box = HaeNewBox(i, P);

   for(int q = 0; q < s_actCount; q++) {
      const int o = s_act[q];
      if(HaeLines[o].state != LST_ACTIVE || HaeLines[o].upper == up) continue;
      if(MathAbs(HaeLines[o].price - P) > s_pRange + 1e-12) continue;
      if(box >= 0) HaeBoxAbsorb(box, o);
      else         HaeEndLine(o, LST_FILTERED, i);            // IGNORE_BOTH and KEEP_NEWER drop the older line
   }

   if(box >= 0) {
      HaeBoxAbsorb(box, j);
      s_bxSide[box] = HaeBoxSideOf(box, c);
   }
   else if(Cfg.rangeMode == RANGE_IGNORE_BOTH) HaeEndLine(j, LST_FILTERED, i);
}

//+------------------------------------------------------------------+
//| New line from a confirmed pivot                                   |
//+------------------------------------------------------------------+
void HaeAddLine(const int pivot, const int i, const bool upper)
{
   const double P = HaeMA[pivot] + (upper ? s_pOffset : -s_pOffset);

   // touched between the pivot and its confirmation -> already mitigated, never created
   for(int t = pivot + 1; t <= i; t++)
      if(HaeRates[t].high >= P && HaeRates[t].low <= P) return;

   // capacity: expire the oldest active line
   if(s_actDirty) HaeCompact();
   if(s_actCount >= HAE_MAX_LINES) {
      int old = -1;
      for(int k = 0; k < s_actCount; k++)
         if(old < 0 || s_lnBar[s_act[k]] < s_lnBar[old]) old = s_act[k];
      if(old >= 0) HaeEndLine(old, LST_USED, i);
      HaeCompact();
   }

   HaeLineReserve(HaeLineCount + 1);
   const int j = HaeLineCount++;
   HaeLines[j].price     = P;
   HaeLines[j].startTime = HaeRates[pivot].time;
   HaeLines[j].endTime   = 0;
   HaeLines[j].upper     = upper;
   HaeLines[j].state     = LST_ACTIVE;
   HaeLines[j].rep       = false;
   HaeLines[j].boxId     = -1;
   s_lnSide[j]  = (HaeRates[i].close > P) ? 1 : -1;
   s_lnBar[j]   = pivot;
   s_lnGroup[j] = -1;
   s_lnWatch[j] = false;

   if(Cfg.rangeMode != RANGE_OFF) HaeRangeFilter(j, i);

   if(HaeLines[j].state == LST_ACTIVE) s_act[s_actCount++] = j;
   s_groupsDirty = true;
}

//+------------------------------------------------------------------+
//| Build: replay the analysed history                                |
//+------------------------------------------------------------------+
bool HaeLinesBuild()
{
   HaeLinesValid = false;
   const int n = HaeBars;
   if(n < 50) return false;
   const int last = n - 2;                      // n-1 is the forming bar

   //--- constants
   s_pOffset = HaePts(Cfg.lineOffsetPts);
   s_pWatch  = HaePts(Cfg.watchDistPts);
   s_pClose  = HaePts(Cfg.minCloseBeyondPts);
   s_pWick   = HaePts(Cfg.minWickBeyondPts);
   s_pBack   = HaePts(Cfg.minCloseBackPts);
   s_pGroup  = HaePts(Cfg.groupDistPts);
   s_pRange  = HaePts(Cfg.rangeDistPts);

   //--- reset (capacity is kept)
   HaeLineCount = 0; HaeBoxCount = 0; HaeEventCount = 0; HaeSignalCount = 0;
   s_actCount = 0; s_bxActCount = 0;
   s_actDirty = false; s_groupsDirty = false; s_groupSeq = 0;

   int dir = 0, ext = -1, pPeak = -1, pTrough = -1, below = 0, above = 0;
   const double eps = Sym.point * 1e-3;

   for(int i = 1; i <= last; i++) {
      //--- 1. decisions of existing lines / boxes on candle i
      if(s_actCount > 0 || s_bxActCount > 0) {
         if(s_actDirty)    HaeCompact();
         if(s_groupsDirty) HaeRegroup();
         for(int k = 0; k < s_actCount; k++) {
            const int j = s_act[k];
            if(HaeLines[j].state == LST_ACTIVE) HaeEvalLine(j, i);
         }
         for(int k = 0; k < s_bxActCount; k++) {
            const int b = s_bxAct[k];
            if(HaeBoxes[b].alive) HaeEvalBox(b, i);
         }
      }

      //--- 2. turning points of the MA (flat runs: pivot = first bar of the plateau)
      if(HaeMA[i] == EMPTY_VALUE || HaeMA[i - 1] == EMPTY_VALUE) {
         dir = 0; ext = (HaeMA[i] != EMPTY_VALUE) ? i : -1;
         pPeak = -1; pTrough = -1; below = 0; above = 0;
         continue;
      }
      const double d = HaeMA[i] - HaeMA[i - 1];
      if(d > eps) {
         if(dir < 0 && ext >= 0) { pTrough = ext; above = 0; }
         dir = 1; ext = i;
      } else if(d < -eps) {
         if(dir > 0 && ext >= 0) { pPeak = ext; below = 0; }
         dir = -1; ext = i;
      }

      //--- 3. confirmation: N consecutive closes on the other side of the MA
      const double c = HaeRates[i].close;
      if(c < HaeMA[i]) below++; else below = 0;
      if(c > HaeMA[i]) above++; else above = 0;

      if(pPeak >= 0 && below >= Cfg.pivotCandles)   { HaeAddLine(pPeak,   i, true);  pPeak   = -1; }
      if(pTrough >= 0 && above >= Cfg.pivotCandles) { HaeAddLine(pTrough, i, false); pTrough = -1; }
   }

   if(s_actDirty)    HaeCompact();
   if(s_groupsDirty) HaeRegroup();

   //--- watching state for the forming bar (display)
   const double lc = HaeRates[last].close, fo = HaeRates[n - 1].open;
   for(int j = 0; j < HaeLineCount; j++) s_lnWatch[j] = false;
   for(int k = 0; k < s_actCount; k++) {
      const int j = s_act[k];
      s_lnWatch[j] = HaeLines[j].rep && (HaeNear(lc, HaeLines[j].price) || HaeNear(fo, HaeLines[j].price));
   }
   for(int b = 0; b < HaeBoxCount; b++) s_bxWatch[b] = false;
   for(int k = 0; k < s_bxActCount; k++) {
      const int b = s_bxAct[k];
      s_bxWatch[b] = (s_bxSide[b] == 0) || HaeNear(lc, HaeBoxes[b].top) || HaeNear(lc, HaeBoxes[b].bottom)
                  || HaeNear(fo, HaeBoxes[b].top) || HaeNear(fo, HaeBoxes[b].bottom);
   }

   //--- tradeable signals = decisions on the last closed bar
   HaeLastClosedTime = HaeRates[last].time;
   for(int e = HaeEventCount - 1; e >= 0; e--) {
      if(HaeEvents[e].barTime != HaeLastClosedTime) break;       // events are in time order
      if(ArraySize(HaeSignals) <= HaeSignalCount) ArrayResize(HaeSignals, HaeSignalCount + 8);
      HaeSignals[HaeSignalCount++] = HaeEvents[e];
   }

   HaeLinesValid = true;
   return true;
}

#endif // HAE_LINES_MQH
//+------------------------------------------------------------------+
