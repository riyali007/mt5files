//+------------------------------------------------------------------+
//|                                               HAE_Defines.mqh    |
//|  HMA Active EA  v0.1                                              |
//|  File 1/10 - shared constants, enums, structs and settings.       |
//|                                                                   |
//|  Every other module includes this file. It contains NO trading    |
//|  logic, only types, the global settings object (Cfg) and its      |
//|  validation.                                                      |
//+------------------------------------------------------------------+
#ifndef HAE_DEFINES_MQH
#define HAE_DEFINES_MQH

#define HAE_VERSION          "0.1"

//--- capacity limits
#define HAE_MAX_LINES        400      // active inflection lines kept in memory
#define HAE_MAX_BOXES        100      // active range boxes kept in memory
#define HAE_MAX_DRAWN_LINES  100      // lines drawn on the chart

//--- chart object prefixes
#define HAE_PFX_ALL          "HAE_"
#define HAE_PFX_MA           "HAE_MA_"
#define HAE_PFX_LN           "HAE_LN_"
#define HAE_PFX_BOX          "HAE_BX_"
#define HAE_PFX_SIG          "HAE_SG_"
#define HAE_PFX_PT           "HAE_PT_"

//--- position comment tags (broker limit: 31 chars)
//    main : "HAE_M_<SIG><KEY>"    e.g. HAE_M_BOU1727600000
//    DD   : "HAE_D<lvl>_<anchor>" e.g. HAE_D2_123456789
#define HAE_TAG_MAIN         "HAE_M_"
#define HAE_TAG_DD           "HAE_D"

//--- line / box key prefixes (key = prefix + start time)
#define HAE_KEY_UPPER        "U"
#define HAE_KEY_LOWER        "L"
#define HAE_KEY_BOX          "X"

//--- global variable prefix (persisted state: cooldowns, DD levels)
#define HAE_GV_PFX           "HAE01_"

//+------------------------------------------------------------------+
//| Enums (shown as dropdowns in the input dialog)                    |
//+------------------------------------------------------------------+
enum ENUM_HAE_MA
{
   HAE_MA_SMA = 0,   // SMA
   HAE_MA_EMA = 1,   // EMA
   HAE_MA_RMA = 2,   // RMA (Wilder)
   HAE_MA_WMA = 3,   // WMA
   HAE_MA_HMA = 4    // HMA (Hull)
};

enum ENUM_HAE_RANGE_MODE
{
   RANGE_OFF         = 0,   // Off (no range filter)
   RANGE_IGNORE_BOTH = 1,   // Ignore both conflicting lines
   RANGE_KEEP_NEWER  = 2,   // Keep the newer line, drop the older one
   RANGE_BOX         = 3    // Build a range box, trade only its edges
};

enum ENUM_HAE_SIGNALS
{
   SIGS_BOTH           = 0, // Breakout + Rejection (flip)
   SIGS_BREAKOUT_ONLY  = 1, // Breakout only
   SIGS_REJECTION_ONLY = 2  // Rejection (flip) only
};

enum ENUM_HAE_SL_MODE
{
   SLM_FIXED         = 0,   // Fixed points from entry
   SLM_BEYOND_LINE   = 1,   // Beyond the line + buffer
   SLM_BEYOND_CANDLE = 2    // Beyond the signal candle + buffer
};

enum ENUM_HAE_TP_MODE
{
   TPM_FIXED = 0,           // Fixed points from entry
   TPM_RR    = 1            // Multiple of the SL distance (R:R)
};

enum ENUM_HAE_LOT_MODE
{
   LOTM_FIXED    = 0,       // Fixed lot
   LOTM_RISK_PCT = 1        // % of balance risked at SL
};

enum ENUM_HAE_DD_SL
{
   DDSL_SAME_PRICE    = 0,  // Same SL price as the first order
   DDSL_SAME_DISTANCE = 1   // Same SL distance from the DD entry
};

enum ENUM_HAE_DD_WORST
{
   DDW_CLOSE_AT_GREEN = 0,  // Older entries closed as soon as their own net is green
   DDW_LET_RUN        = 1   // Every entry runs its own partials / BE / TP
};

//--- internal (not inputs)
enum ENUM_HAE_LINE_STATE
{
   LST_ACTIVE   = 0,        // alive, may trade
   LST_FILTERED = 1,        // removed by the range filter (drawn dimmed, never trades)
   LST_BOXED    = 2,        // member of a range box (the box trades, not the line)
   LST_USED     = 3         // decided by a candle (breakout / rejection) or expired
};

enum ENUM_HAE_SIGNAL
{
   SIGNAL_NONE           = 0,
   SIGNAL_BUY_BREAKOUT   = 1,  // came from below, closed above
   SIGNAL_SELL_REJECTION = 2,  // came from below, wick above, closed below (flip)
   SIGNAL_SELL_BREAKOUT  = 3,  // came from above, closed below
   SIGNAL_BUY_REJECTION  = 4   // came from above, wick below, closed above (flip)
};

//+------------------------------------------------------------------+
//| Structs                                                           |
//+------------------------------------------------------------------+
struct SHaeLine
{
   double              price;       // drawn line price (MA pivot +/- offset)
   datetime            startTime;   // pivot bar time (unique key)
   datetime            endTime;     // bar that decided / expired the line (0 = still alive)
   bool                upper;       // true = from a peak, false = from a trough
   ENUM_HAE_LINE_STATE state;
   bool                rep;         // outermost line of its same-direction group
   int                 boxId;       // index into box array when LST_BOXED, else -1
};

struct SHaeBox
{
   datetime startTime;              // creation time (unique key)
   datetime endTime;                // bar that decided the box (0 = alive)
   double   top;
   double   bottom;
   bool     alive;
};

struct SHaeSignal
{
   ENUM_HAE_SIGNAL type;
   string          key;             // line / box key, e.g. U1727600000, X1727600000
   double          level;           // the price level that was broken / rejected
   datetime        barTime;         // signal candle open time
   double          barHigh;
   double          barLow;
   double          barClose;
   bool            fromBox;
};

struct SHaePosState
{
   ulong    ticket;
   long     posId;
   double   entry;
   double   vol0;                   // initial volume
   bool     isBuy;
   double   tpDistPts;              // |TP - entry| at open, in points (partial step base)
   double   slDistPts;              // |SL - entry| at open, in points (SL partial step base)
   int      partials;
   int      slPartials;
   int      ddOpened;               // highest DD level ever opened for this anchor
   bool     beDone;
   bool     volWarned;
   datetime retryAt;
   double   commission;             // cached entry commission (no per-tick history calls)
};

//+------------------------------------------------------------------+
//| Settings - filled once from the inputs in OnInit                  |
//+------------------------------------------------------------------+
struct SHaeSettings
{
   //--- MA engine
   int                 maxBars;
   ENUM_TIMEFRAMES     timeframe;
   ENUM_HAE_MA         baseMethod;
   int                 basePeriod;
   ENUM_APPLIED_PRICE  appliedPrice;
   bool                noRepaint;
   ENUM_HAE_MA         smoothMethod;
   int                 smoothPeriod;

   //--- inflection lines
   int                 lineOffsetPts;
   int                 pivotCandles;
   int                 lineMaxAgeBars;     // 0 = no age limit

   //--- grouping (same direction)
   bool                grouping;
   int                 groupDistPts;

   //--- range filter (opposite direction)
   ENUM_HAE_RANGE_MODE rangeMode;
   int                 rangeDistPts;       // distance between DRAWN upper and lower lines

   //--- active execution
   ENUM_HAE_SIGNALS    signalTypes;
   int                 watchDistPts;       // price within this distance -> watching
   int                 minCloseBeyondPts;  // breakout: close at least this far past the line
   int                 minWickBeyondPts;   // rejection: wick at least this far past the line
   int                 minCloseBackPts;    // rejection: close at least this far back
   int                 maxEntryDistPts;    // do not chase: market price vs level (0 = off)
   int                 maxSpreadPts;       // 0 = off
   int                 maxSignalDelaySec;  // signal older than this (after bar close) is skipped
   int                 slippagePts;

   //--- SL / TP
   ENUM_HAE_SL_MODE    slMode;
   int                 slPts;              // SLM_FIXED distance
   int                 slBufferPts;        // buffer for BEYOND_LINE / BEYOND_CANDLE
   int                 minSlPts;
   int                 maxSlPts;           // 0 = no max
   ENUM_HAE_TP_MODE    tpMode;
   int                 tpPts;
   double              tpRR;

   //--- volume
   ENUM_HAE_LOT_MODE   lotMode;
   double              lot;
   double              riskPct;
   int                 maxOpenMain;        // max open main positions (DD entries not counted)
   long                magic;

   //--- partials
   int                 partials;
   double              partialPct;
   bool                slPartialsEnabled;
   int                 slPartials;
   double              slPartialPct;

   //--- break-even
   int                 bePts;
   int                 beOffsetPts;

   //--- cooldown
   int                 cooldownMin;
   bool                cooldownOnAnyLoss;

   //--- drawdown entries
   int                 ddMax;
   int                 ddStepPts;
   ENUM_HAE_DD_SL      ddSlMode;
   bool                ddBlockedByCooldown;
   ENUM_HAE_DD_WORST   ddWorstMode;
   double              ddGreenMin;
   bool                ddSyncBE;

   //--- display
   bool                drawMA;
   int                 maDrawBars;
   color               clrMA;
   int                 maWidth;
   bool                drawLines;
   color               clrUpper;
   color               clrLower;
   color               clrWatch;
   color               clrDim;             // non-representative / filtered lines
   color               clrBox;
   bool                drawPartials;
   color               clrPartial;
   bool                drawSignals;
   color               clrBuySig;
   color               clrSellSig;

   //--- derived at runtime (not inputs)
   ENUM_TIMEFRAMES     tf;                 // effective MA timeframe
   int                 tfSec;
   int                 chartSec;
   bool                sameTf;
   bool                hedging;
   bool                visuals;            // draw objects (off in non-visual tester / optimisation)
   bool                slPartialsOn;       // effective (auto-off while DD entries are on)
};

SHaeSettings Cfg;   // single global settings object, read by all modules

//+------------------------------------------------------------------+
//| Small shared helpers                                              |
//+------------------------------------------------------------------+
bool HaeIsBuySignal(const ENUM_HAE_SIGNAL s)
{
   return (s == SIGNAL_BUY_BREAKOUT || s == SIGNAL_BUY_REJECTION);
}

bool HaeIsBreakout(const ENUM_HAE_SIGNAL s)
{
   return (s == SIGNAL_BUY_BREAKOUT || s == SIGNAL_SELL_BREAKOUT);
}

string HaeSignalCode(const ENUM_HAE_SIGNAL s)   // 2 chars, used in comments
{
   return HaeIsBreakout(s) ? "BO" : "RJ";
}

string HaeSignalName(const ENUM_HAE_SIGNAL s)
{
   switch(s) {
      case SIGNAL_BUY_BREAKOUT:   return "BUY breakout";
      case SIGNAL_SELL_REJECTION: return "SELL rejection";
      case SIGNAL_SELL_BREAKOUT:  return "SELL breakout";
      case SIGNAL_BUY_REJECTION:  return "BUY rejection";
      default:                    return "none";
   }
}

bool HaeSignalAllowed(const ENUM_HAE_SIGNAL s)
{
   if(s == SIGNAL_NONE) return false;
   if(Cfg.signalTypes == SIGS_BREAKOUT_ONLY)  return HaeIsBreakout(s);
   if(Cfg.signalTypes == SIGS_REJECTION_ONLY) return !HaeIsBreakout(s);
   return true;
}

//+------------------------------------------------------------------+
//| Settings validation - returns false and a reason on bad input     |
//+------------------------------------------------------------------+
bool HaeValidateSettings(string &err)
{
   err = "";
   if(Cfg.maxBars < 100)                          { err = "Max bars must be >= 100";                 return false; }
   if(Cfg.basePeriod < 1 || Cfg.smoothPeriod < 1) { err = "MA periods must be >= 1";                 return false; }
   if(Cfg.pivotCandles < 1)                       { err = "Pivot candles must be >= 1";              return false; }
   if(Cfg.lineOffsetPts < 0)                      { err = "Line offset must be >= 0";                return false; }
   if(Cfg.rangeMode != RANGE_OFF && Cfg.rangeDistPts < 1)
                                                  { err = "Range distance must be >= 1 when the range filter is on"; return false; }
   if(Cfg.watchDistPts < 1)                       { err = "Watch distance must be >= 1";             return false; }
   if(Cfg.minCloseBeyondPts < 0 || Cfg.minWickBeyondPts < 0 || Cfg.minCloseBackPts < 0)
                                                  { err = "Signal thresholds must be >= 0";          return false; }
   if(Cfg.slMode == SLM_FIXED && Cfg.slPts < 1)   { err = "Fixed SL must be >= 1 point";             return false; }
   if(Cfg.maxSlPts > 0 && Cfg.maxSlPts < Cfg.minSlPts)
                                                  { err = "Max SL must be >= min SL";                return false; }
   if(Cfg.tpMode == TPM_FIXED && Cfg.tpPts < 0)   { err = "Fixed TP must be >= 0";                   return false; }
   if(Cfg.tpMode == TPM_RR && Cfg.tpRR <= 0.0)    { err = "R:R must be > 0";                         return false; }
   if(Cfg.lotMode == LOTM_FIXED && Cfg.lot <= 0.0){ err = "Lot must be > 0";                         return false; }
   if(Cfg.lotMode == LOTM_RISK_PCT && (Cfg.riskPct <= 0.0 || Cfg.riskPct > 100.0))
                                                  { err = "Risk % must be in (0, 100]";              return false; }
   if(Cfg.maxOpenMain < 1)                        { err = "Max open main positions must be >= 1";    return false; }
   if(Cfg.partials < 0 || Cfg.slPartials < 0)     { err = "Partial counts must be >= 0";             return false; }
   if(Cfg.partialPct < 0.0 || Cfg.slPartialPct < 0.0)
                                                  { err = "Partial % must be >= 0";                  return false; }
   if(Cfg.partials * Cfg.partialPct > 100.0)      { err = "TP partials exceed 100% of the volume";   return false; }
   if(Cfg.slPartials * Cfg.slPartialPct > 100.0)  { err = "SL partials exceed 100% of the volume";   return false; }
   if(Cfg.ddMax < 0)                              { err = "DD entries must be >= 0";                 return false; }
   if(Cfg.ddMax > 0 && Cfg.ddStepPts < 1)         { err = "DD step must be >= 1 point";              return false; }
   if(Cfg.ddMax > 9)                              { err = "DD entries are limited to 9";             return false; }
   return true;
}

#endif // HAE_DEFINES_MQH
//+------------------------------------------------------------------+
