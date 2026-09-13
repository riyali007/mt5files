//+------------------------------------------------------------------+
//|                                          MTF_3x_MA_Fixed_v8b.mq5 |
//|                                  Converted from Pine Script      |
//|  v1.03 fixes: HTF==ChartTF, HTF<ChartTF, sync race, no-blank     |
//|  v2.00 adds : MA Selector dropdown, Signal flags,                |
//|               Setup 1 - Engulfing Break & Retest range lines     |
//|  v3.00 adds : Setup 2 - Range Breakout state machine + boxes     |
//|  v4.00 adds : Setup 3 - Breakout + Re-Test confirmation,         |
//|               Perf: MA recompute only on HTF bar close (Option B)|
//|  v5.00 fix  : Setup 2 seed uses SAME-CANDLE open-vs-close test   |
//|  v6.00 fix  : Setup 2/3 invalidation on ANY fresh breakout candle |
//|  v7.00 fix  : MA calc driven strictly from chart time[]          |
//|  v8.00 base : Per-MA write gating (this is the version you liked) |
//|  v8b.00 fix : Reverted to v8 exactly, with ONE change to          |
//|               OnCalculate: if the live bar's time hasn't changed  |
//|               since the last tick (i.e. the candle has not       |
//|               closed), return prev_calculated IMMEDIATELY at the |
//|               very top - before touching any MA computation,     |
//|               signal engine, or box drawing. This is MQL5's       |
//|               equivalent of "return null" for OnCalculate, since  |
//|               the function must return an int.                    |
//+------------------------------------------------------------------+
#property copyright "MQL5 Conversion"
#property link      ""
#property version   "8.10"
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   3

//--- Plot properties
#property indicator_label1  "MA 1"
#property indicator_type1   DRAW_LINE
#property indicator_width1  2

#property indicator_label2  "MA 2"
#property indicator_type2   DRAW_LINE
#property indicator_width2  2

#property indicator_label3  "MA 3"
#property indicator_type3   DRAW_LINE
#property indicator_width3  2

//--- Enums
enum ENUM_MA_TYPE
  {
   MA_SMA,   // SMA
   MA_EMA,   // EMA
   MA_WMA,   // WMA
   MA_VWMA,  // VWMA
   MA_HMA,   // HMA
   MA_RMA    // RMA (Smoothed)
  };

enum ENUM_MA_SELECT
  {
   MA_SELECT_1, // MA 1
   MA_SELECT_2, // MA 2
   MA_SELECT_3  // MA 3
  };

//--- INPUTS: Moving Average 1 ---
input group "=== Moving Average 1 ==="
input bool               Show1   = true;         // Show MA 1
input bool               Smooth1 = true;          // Smooth MTF Line (steps once per HTF close)
input ENUM_MA_TYPE        Type1   = MA_EMA;        // Type
input int                 Len1    = 50;            // Length
input ENUM_TIMEFRAMES     TF1     = PERIOD_H1;     // Timeframe
input ENUM_APPLIED_PRICE  Src1    = PRICE_CLOSE;   // Source
input color                Col1    = clrBlue;       // Color

//--- INPUTS: Moving Average 2 ---
input group "=== Moving Average 2 ==="
input bool               Show2   = true;         // Show MA 2
input bool               Smooth2 = true;          // Smooth MTF Line (steps once per HTF close)
input ENUM_MA_TYPE        Type2   = MA_SMA;        // Type
input int                 Len2    = 100;           // Length
input ENUM_TIMEFRAMES     TF2     = PERIOD_H4;     // Timeframe
input ENUM_APPLIED_PRICE  Src2    = PRICE_CLOSE;   // Source
input color                Col2    = clrOrange;     // Color

//--- INPUTS: Moving Average 3 ---
input group "=== Moving Average 3 ==="
input bool               Show3   = true;         // Show MA 3
input bool               Smooth3 = true;          // Smooth MTF Line (steps once per HTF close)
input ENUM_MA_TYPE        Type3   = MA_WMA;        // Type
input int                 Len3    = 200;           // Length
input ENUM_TIMEFRAMES     TF3     = PERIOD_D1;     // Timeframe
input ENUM_APPLIED_PRICE  Src3    = PRICE_CLOSE;   // Source
input color                Col3    = clrMagenta;    // Color

//--- INPUTS: Signal Setup Selection ---
input group "=== Signal Settings ==="
input ENUM_MA_SELECT      SignalMASource   = MA_SELECT_1; // MA Used For Signals
input bool                EnableEngulfing  = true;        // Setup 1: Engulfing Break Signal
input bool                EnableRangeBreakout = true;     // Setup 2: Range Breakout
input bool                EnableBreakoutRetest = false;   // Setup 3: Breakout + Re-Test Confirmation

input group "=== Setup 1: Engulfing Settings ==="
input int                 ExtendBars       = 3;            // Range Line Extend (Candles, 2-3 typical)
input color               BuyRangeColor    = clrLime;      // Buy Range Line Color
input color               SellRangeColor   = clrRed;       // Sell Range Line Color
input int                 RangeLineWidth   = 1;             // Range Line Width
input ENUM_LINE_STYLE     RangeLineStyle   = STYLE_SOLID;   // Range Line Style
input bool                ShowSignalArrows = true;          // Show Buy/Sell Arrows

input group "=== Setup 2: Range Breakout Settings ==="
input color               ActiveBoxColor   = clrDarkSlateGray; // Active Range Box Color (darker shade)
input color               LockedBuyBoxColor  = clrDarkGreen;   // Locked Box Color After Buy Breakout
input color               LockedSellBoxColor = clrMaroon;      // Locked Box Color After Sell Breakout
input color               InvalidatedBoxColor = clrGray;       // Invalidated Box Color
input int                 BoxExtendBars    = 1;                // Box Right Edge Extend (Candles)
input bool                ShowBreakoutArrows = true;           // Show Buy/Sell Arrows For Setup 2

input group "=== Setup 3: Breakout + Re-Test Settings ==="
input color               AwaitingRetestBoxColor = clrDarkOrange; // Box Color While Awaiting Retest
input color               RetestConfirmedBuyColor = clrForestGreen;  // Box Color On Confirmed Retest Buy
input color               RetestConfirmedSellColor = clrFireBrick;  // Box Color On Confirmed Retest Sell

//--- Buffers
double Buffer1[];
double Buffer2[];
double Buffer3[];

//--- Handles for native MAs (SMA, EMA, WMA, RMA)
int handle1 = INVALID_HANDLE;
int handle2 = INVALID_HANDLE;
int handle3 = INVALID_HANDLE;

//--- Cache structs: keyed on the CLOSED htf bar time derived purely from chart time[].
struct SMACache
  {
   datetime last_htf_time;   // open time of the last CLOSED htf bar we computed for
   double   val_curr;        // MA value at that closed htf bar
   double   val_prev;        // MA value one htf bar before that
   datetime written_for_bar; // chart bar TIME for which we last actually wrote the live buffer
   void Reset() { last_htf_time = 0; val_curr = EMPTY_VALUE; val_prev = EMPTY_VALUE; written_for_bar = 0; }
  };
SMACache cache1, cache2, cache3;

//--- Track last processed bar time for signal engine (avoid re-scanning closed history every tick)
datetime g_last_signal_bar_time = 0;
datetime g_last_breakout_bar_time = 0;

//--- v8b: single top-level gate - the last LIVE bar time we saw at all (open tick or later).
datetime g_lastSeenBarTime = 0;

//--- Setup 2 / Setup 3 state machine
enum ENUM_RANGE_STATUS
  {
   RANGE_NONE,
   RANGE_ACTIVE,
   RANGE_AWAITING_RETEST_BUY,
   RANGE_AWAITING_RETEST_SELL
  };

struct RangeState
  {
   ENUM_RANGE_STATUS status;
   datetime startTime;
   double   high;
   double   low;
   string   boxName;
   void Reset() { status = RANGE_NONE; startTime = 0; high = 0; low = 0; boxName = ""; }
  };
RangeState g_range;

#define OBJ_PREFIX      "MTF_MA_SIG_"
#define OBJ_PREFIX_BOX  "MTF_MA_BOX_"

//+------------------------------------------------------------------+
//| Helper: Get MT5 Native MA Mode                                   |
//+------------------------------------------------------------------+
ENUM_MA_METHOD GetNativeMode(ENUM_MA_TYPE type)
  {
   switch(type)
     {
      case MA_SMA: return MODE_SMA;
      case MA_EMA: return MODE_EMA;
      case MA_WMA: return MODE_LWMA;
      case MA_RMA: return MODE_SMMA; // MT5 SMMA mathematically equals Pine's RMA
      default:     return MODE_SMA;
     }
  }

//+------------------------------------------------------------------+
//| Helper: Resolve the effective TF (handles PERIOD_CURRENT)         |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES ResolveTF(ENUM_TIMEFRAMES tf)
  {
   return (tf == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : tf;
  }

//+------------------------------------------------------------------+
//| Helper: Create handle safely, works for TF == chart TF too       |
//+------------------------------------------------------------------+
int CreateHandle(ENUM_MA_TYPE type, int len, ENUM_TIMEFRAMES tf, ENUM_APPLIED_PRICE src)
  {
   if(type == MA_VWMA || type == MA_HMA)
      return INVALID_HANDLE;

   ENUM_TIMEFRAMES useTf = ResolveTF(tf);
   int h = iMA(Symbol(), useTf, len, 0, GetNativeMode(type), src);
   return h;
  }

//+------------------------------------------------------------------+
//| Initialization                                                    |
//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, Buffer1, INDICATOR_DATA);
   SetIndexBuffer(1, Buffer2, INDICATOR_DATA);
   SetIndexBuffer(2, Buffer3, INDICATOR_DATA);

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   PlotIndexSetInteger(0, PLOT_LINE_COLOR, Col1);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, Col2);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, Col3);

   if(Show1)
      handle1 = CreateHandle(Type1, Len1, TF1, Src1);
   if(Show2)
      handle2 = CreateHandle(Type2, Len2, TF2, Src2);
   if(Show3)
      handle3 = CreateHandle(Type3, Len3, TF3, Src3);

   MqlRates warm[];
   if(Show1) CopyRates(Symbol(), ResolveTF(TF1), 0, MathMax(Len1*2, 10), warm);
   if(Show2) CopyRates(Symbol(), ResolveTF(TF2), 0, MathMax(Len2*2, 10), warm);
   if(Show3) CopyRates(Symbol(), ResolveTF(TF3), 0, MathMax(Len3*2, 10), warm);

   g_last_signal_bar_time = 0;
   g_last_breakout_bar_time = 0;
   g_lastSeenBarTime = 0;
   g_range.Reset();

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Deinitialization                                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(handle1 != INVALID_HANDLE) IndicatorRelease(handle1);
   if(handle2 != INVALID_HANDLE) IndicatorRelease(handle2);
   if(handle3 != INVALID_HANDLE) IndicatorRelease(handle3);

   if(reason == REASON_REMOVE)
     {
      ObjectsDeleteAll(0, OBJ_PREFIX);
      ObjectsDeleteAll(0, OBJ_PREFIX_BOX);
     }
  }

//+------------------------------------------------------------------+
//| Helper: Get MA Value cleanly                                      |
//+------------------------------------------------------------------+
double GetMAValue(ENUM_TIMEFRAMES tf, ENUM_MA_TYPE type, int len, ENUM_APPLIED_PRICE src, int handle, int shift)
  {
   if(shift < 0)
      return EMPTY_VALUE;

   double val = EMPTY_VALUE;
   if(type == MA_VWMA)
      val = CalculateVWMA(tf, len, src, shift);
   else if(type == MA_HMA)
      val = CalculateHMA(tf, len, src, shift);
   else
     {
      double arr[1];
      if(CopyBuffer(handle, 0, shift, 1, arr) > 0)
         val = arr[0];
     }
   return val;
  }

//+------------------------------------------------------------------+
//| Same ProcessMA as v8 - unchanged.                                  |
//+------------------------------------------------------------------+
bool ProcessMA(int i, datetime t, bool is_current_bar,
               ENUM_TIMEFRAMES tf, ENUM_MA_TYPE type, int len, ENUM_APPLIED_PRICE src,
               int handle, bool smooth, SMACache &cache, double &outBuf[])
  {
   ENUM_TIMEFRAMES rtf = ResolveTF(tf);

   int shift = iBarShift(Symbol(), rtf, t, false);
   if(shift < 0)
     {
      if(!(is_current_bar && cache.written_for_bar == t))
         outBuf[i] = EMPTY_VALUE;
      return true;
     }

   int closedShift = shift + 1;
   datetime htf_t = iTime(Symbol(), rtf, closedShift);

   if(htf_t == 0)
     {
      if(!(is_current_bar && cache.written_for_bar == t))
         outBuf[i] = (cache.val_curr != EMPTY_VALUE) ? cache.val_curr : EMPTY_VALUE;
      return (cache.last_htf_time != 0);
     }

   bool htfUnchanged = (htf_t == cache.last_htf_time && cache.val_curr != EMPTY_VALUE);

   if(is_current_bar)
     {
      if(htfUnchanged && cache.written_for_bar == t)
        {
         return true;
        }

      if(htfUnchanged)
        {
         outBuf[i] = cache.val_curr;
         cache.written_for_bar = t;
         return true;
        }

      double newVal = GetMAValue(rtf, type, len, src, handle, closedShift);
      if(newVal == EMPTY_VALUE)
        {
         if(cache.written_for_bar != t)
            outBuf[i] = (cache.val_curr != EMPTY_VALUE) ? cache.val_curr : EMPTY_VALUE;
         return (cache.last_htf_time != 0);
        }

      if(smooth && cache.val_curr != EMPTY_VALUE)
         cache.val_prev = cache.val_curr;

      cache.val_curr = newVal;
      cache.last_htf_time = htf_t;
      outBuf[i] = cache.val_curr;
      cache.written_for_bar = t;
      return true;
     }
   else
     {
      if(htfUnchanged)
        {
         outBuf[i] = cache.val_curr;
         return true;
        }

      double val = GetMAValue(rtf, type, len, src, handle, closedShift);
      if(val == EMPTY_VALUE)
        {
         outBuf[i] = EMPTY_VALUE;
         return false;
        }

      if(smooth && cache.val_curr != EMPTY_VALUE)
         cache.val_prev = cache.val_curr;

      cache.val_curr = val;
      cache.last_htf_time = htf_t;
      outBuf[i] = val;
      return true;
     }
  }

//+------------------------------------------------------------------+
//| Signal Engine Helpers                                             |
//+------------------------------------------------------------------+
double GetSelectedMABuffer(int i, const double &b1[], const double &b2[], const double &b3[])
  {
   switch(SignalMASource)
     {
      case MA_SELECT_1: return b1[i];
      case MA_SELECT_2: return b2[i];
      case MA_SELECT_3: return b3[i];
      default:          return b1[i];
     }
  }

bool IsBullishEngulfing(const double &open[], const double &close[], int i)
  {
   if(i < 1) return false;
   bool prevBearish = close[i-1] < open[i-1];
   bool currBullish = close[i]   > open[i];
   if(!prevBearish || !currBullish) return false;
   return (open[i] <= close[i-1]) && (close[i] >= open[i-1]);
  }

bool IsBearishEngulfing(const double &open[], const double &close[], int i)
  {
   if(i < 1) return false;
   bool prevBullish = close[i-1] > open[i-1];
   bool currBearish = close[i]   < open[i];
   if(!prevBullish || !currBearish) return false;
   return (open[i] >= close[i-1]) && (close[i] <= open[i-1]);
  }

//+------------------------------------------------------------------+
//| Draw the range lines + optional arrow for a Setup 1 signal candle |
//+------------------------------------------------------------------+
void DrawSignalRange(int i, const datetime &time[], const double &high[], const double &low[],
                      const double &close[], bool isBuy)
  {
   datetime tStart = time[i];
   long periodSecs = PeriodSeconds();
   datetime tEnd = tStart + (datetime)(periodSecs * ExtendBars);

   double topPrice    = high[i];
   double bottomPrice = low[i];
   color  lineColor   = isBuy ? BuyRangeColor : SellRangeColor;
   string tag         = isBuy ? "BUY" : "SELL";

   string nameTop    = OBJ_PREFIX + tag + "_TOP_"    + IntegerToString((long)tStart);
   string nameBottom = OBJ_PREFIX + tag + "_BOT_"    + IntegerToString((long)tStart);
   string nameArrow  = OBJ_PREFIX + tag + "_ARROW_"  + IntegerToString((long)tStart);

   if(ObjectFind(0, nameTop) < 0)
     {
      ObjectCreate(0, nameTop, OBJ_TREND, 0, tStart, topPrice, tEnd, topPrice);
      ObjectSetInteger(0, nameTop, OBJPROP_COLOR, lineColor);
      ObjectSetInteger(0, nameTop, OBJPROP_WIDTH, RangeLineWidth);
      ObjectSetInteger(0, nameTop, OBJPROP_STYLE, RangeLineStyle);
      ObjectSetInteger(0, nameTop, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, nameTop, OBJPROP_BACK, true);
      ObjectSetInteger(0, nameTop, OBJPROP_SELECTABLE, false);
     }

   if(ObjectFind(0, nameBottom) < 0)
     {
      ObjectCreate(0, nameBottom, OBJ_TREND, 0, tStart, bottomPrice, tEnd, bottomPrice);
      ObjectSetInteger(0, nameBottom, OBJPROP_COLOR, lineColor);
      ObjectSetInteger(0, nameBottom, OBJPROP_WIDTH, RangeLineWidth);
      ObjectSetInteger(0, nameBottom, OBJPROP_STYLE, RangeLineStyle);
      ObjectSetInteger(0, nameBottom, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, nameBottom, OBJPROP_BACK, true);
      ObjectSetInteger(0, nameBottom, OBJPROP_SELECTABLE, false);
     }

   if(ShowSignalArrows && ObjectFind(0, nameArrow) < 0)
     {
      double arrowPrice = isBuy ? bottomPrice : topPrice;
      ObjectCreate(0, nameArrow, OBJ_ARROW, 0, tStart, arrowPrice);
      ObjectSetInteger(0, nameArrow, OBJPROP_ARROWCODE, isBuy ? 233 : 234);
      ObjectSetInteger(0, nameArrow, OBJPROP_COLOR, lineColor);
      ObjectSetInteger(0, nameArrow, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, nameArrow, OBJPROP_SELECTABLE, false);
     }
  }

//+------------------------------------------------------------------+
//| Setup 1: Engulfing Break Signal Scan                              |
//+------------------------------------------------------------------+
void RunEngulfingSignals(int rates_total, const datetime &time[], const double &open[],
                          const double &high[], const double &low[], const double &close[])
  {
   if(!EnableEngulfing) return;
   if(rates_total < 3) return;

   int lastClosed = rates_total - 2;
   if(lastClosed < 1) return;

   if(g_last_signal_bar_time != 0 && time[lastClosed] == g_last_signal_bar_time)
      return;

   int scanStart = 1;
   if(g_last_signal_bar_time != 0)
     {
      int idx = -1;
      for(int k = lastClosed; k >= 1; k--)
        {
         if(time[k] == g_last_signal_bar_time) { idx = k; break; }
        }
      if(idx >= 0) scanStart = idx + 1;
      else scanStart = MathMax(1, lastClosed - 5);
     }
   else
     {
      scanStart = MathMax(1, lastClosed - 500);
     }

   for(int i = scanStart; i <= lastClosed; i++)
     {
      double maVal      = GetSelectedMABuffer(i, Buffer1, Buffer2, Buffer3);
      double maValPrev   = GetSelectedMABuffer(i-1, Buffer1, Buffer2, Buffer3);
      if(maVal == EMPTY_VALUE || maValPrev == EMPTY_VALUE) continue;

      bool brokeAbove = (close[i-1] <= maValPrev) && (close[i] > maVal);
      bool brokeBelow = (close[i-1] >= maValPrev) && (close[i] < maVal);

      if(brokeAbove && IsBullishEngulfing(open, close, i))
         DrawSignalRange(i, time, high, low, close, true);
      else if(brokeBelow && IsBearishEngulfing(open, close, i))
         DrawSignalRange(i, time, high, low, close, false);
     }

   g_last_signal_bar_time = time[lastClosed];
  }

//+------------------------------------------------------------------+
//| Setup 2/3 Helpers: Box drawing / restyling                        |
//+------------------------------------------------------------------+
string MakeBoxName(datetime t)
  {
   return OBJ_PREFIX_BOX + "RNG_" + IntegerToString((long)t);
  }

void CreateOrUpdateBox(string name, datetime tStart, datetime tEnd, double top, double bottom, color col)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, tStart, top, tEnd, bottom);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
     }
   else
     {
      ObjectMove(0, name, 0, tStart, top);
      ObjectMove(0, name, 1, tEnd, bottom);
     }
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
  }

void DrawBreakoutArrow(datetime t, double price, bool isBuy, color col)
  {
   string tag = isBuy ? "BUY" : "SELL";
   string name = OBJ_PREFIX_BOX + tag + "_ARROW_" + IntegerToString((long)t);
   if(ObjectFind(0, name) >= 0) return;
   ObjectCreate(0, name, OBJ_ARROW, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, isBuy ? 233 : 234);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

//+------------------------------------------------------------------+
//| Helper: Is bar i a qualifying breakout candle (either direction)? |
//+------------------------------------------------------------------+
bool IsBreakoutCandle(double openPrice, double closePrice, double maVal, bool &isBullish)
  {
   if(openPrice < maVal && closePrice > maVal) { isBullish = true;  return true; }
   if(openPrice > maVal && closePrice < maVal) { isBullish = false; return true; }
   return false;
  }

//+------------------------------------------------------------------+
//| Setup 2 + Setup 3: Range Breakout (+ optional Re-Test) State      |
//| Machine. Runs on CLOSED chart-TF bars only.                       |
//+------------------------------------------------------------------+
void RunRangeBreakout(int rates_total, const datetime &time[], const double &open[],
                       const double &high[], const double &low[], const double &close[])
  {
   if(!EnableRangeBreakout) return;
   if(rates_total < 3) return;

   int lastClosed = rates_total - 2;
   if(lastClosed < 1) return;

   if(g_last_breakout_bar_time != 0 && time[lastClosed] == g_last_breakout_bar_time)
      return;

   int scanStart = 1;
   if(g_last_breakout_bar_time != 0)
     {
      int idx = -1;
      for(int k = lastClosed; k >= 1; k--)
        {
         if(time[k] == g_last_breakout_bar_time) { idx = k; break; }
        }
      if(idx >= 0) scanStart = idx + 1;
      else scanStart = MathMax(1, lastClosed - 5);
     }
   else
     {
      scanStart = MathMax(1, lastClosed - 500);
      g_range.Reset();
     }

   long periodSecs = PeriodSeconds();

   for(int i = scanStart; i <= lastClosed; i++)
     {
      double maVal = GetSelectedMABuffer(i, Buffer1, Buffer2, Buffer3);
      if(maVal == EMPTY_VALUE) continue;

      datetime tEndActive = time[i] + (datetime)(periodSecs * BoxExtendBars);
      bool isBullishBreak;
      bool isFreshBreakout = IsBreakoutCandle(open[i], close[i], maVal, isBullishBreak);

      if(g_range.status == RANGE_NONE)
        {
         if(isFreshBreakout)
           {
            g_range.status    = RANGE_ACTIVE;
            g_range.startTime = time[i];
            g_range.high      = high[i];
            g_range.low       = low[i];
            g_range.boxName   = MakeBoxName(time[i]);
            CreateOrUpdateBox(g_range.boxName, time[i], tEndActive, g_range.high, g_range.low, ActiveBoxColor);
           }
        }
      else if(g_range.status == RANGE_ACTIVE)
        {
         bool brokeHigh = close[i] > g_range.high;
         bool brokeLow  = close[i] < g_range.low;

         if(brokeHigh)
           {
            if(EnableBreakoutRetest)
              {
               g_range.status = RANGE_AWAITING_RETEST_BUY;
               CreateOrUpdateBox(g_range.boxName, g_range.startTime, tEndActive, g_range.high, g_range.low, AwaitingRetestBoxColor);
              }
            else
              {
               CreateOrUpdateBox(g_range.boxName, g_range.startTime, tEndActive, g_range.high, g_range.low, LockedBuyBoxColor);
               if(ShowBreakoutArrows) DrawBreakoutArrow(time[i], low[i], true, LockedBuyBoxColor);
               g_range.Reset();
              }
           }
         else if(brokeLow)
           {
            if(EnableBreakoutRetest)
              {
               g_range.status = RANGE_AWAITING_RETEST_SELL;
               CreateOrUpdateBox(g_range.boxName, g_range.startTime, tEndActive, g_range.high, g_range.low, AwaitingRetestBoxColor);
              }
            else
              {
               CreateOrUpdateBox(g_range.boxName, g_range.startTime, tEndActive, g_range.high, g_range.low, LockedSellBoxColor);
               if(ShowBreakoutArrows) DrawBreakoutArrow(time[i], high[i], false, LockedSellBoxColor);
               g_range.Reset();
              }
           }
         else if(isFreshBreakout)
           {
            datetime tEndInvalid = time[i] + (datetime)periodSecs;
            CreateOrUpdateBox(g_range.boxName, g_range.startTime, tEndInvalid, g_range.high, g_range.low, InvalidatedBoxColor);

            g_range.status    = RANGE_ACTIVE;
            g_range.startTime = time[i];
            g_range.high      = high[i];
            g_range.low       = low[i];
            g_range.boxName   = MakeBoxName(time[i]);
            CreateOrUpdateBox(g_range.boxName, time[i], tEndActive, g_range.high, g_range.low, ActiveBoxColor);
           }
         else
           {
            CreateOrUpdateBox(g_range.boxName, g_range.startTime, tEndActive, g_range.high, g_range.low, ActiveBoxColor);
           }
        }
      else if(g_range.status == RANGE_AWAITING_RETEST_BUY)
        {
         bool wickInCloseOut = (low[i] <= g_range.high) && (close[i] > g_range.high);

         if(wickInCloseOut)
           {
            CreateOrUpdateBox(g_range.boxName, g_range.startTime, tEndActive, g_range.high, g_range.low, RetestConfirmedBuyColor);
            if(ShowBreakoutArrows) DrawBreakoutArrow(time[i], low[i], true, RetestConfirmedBuyColor);
            g_range.Reset();
           }
         else if(isFreshBreakout)
           {
            datetime tEndInvalid = time[i] + (datetime)periodSecs;
            CreateOrUpdateBox(g_range.boxName, g_range.startTime, tEndInvalid, g_range.high, g_range.low, InvalidatedBoxColor);

            g_range.status    = RANGE_ACTIVE;
            g_range.startTime = time[i];
            g_range.high      = high[i];
            g_range.low       = low[i];
            g_range.boxName   = MakeBoxName(time[i]);
            CreateOrUpdateBox(g_range.boxName, time[i], tEndActive, g_range.high, g_range.low, ActiveBoxColor);
           }
         else
           {
            CreateOrUpdateBox(g_range.boxName, g_range.startTime, tEndActive, g_range.high, g_range.low, AwaitingRetestBoxColor);
           }
        }
      else if(g_range.status == RANGE_AWAITING_RETEST_SELL)
        {
         bool wickInCloseOut = (high[i] >= g_range.low) && (close[i] < g_range.low);

         if(wickInCloseOut)
           {
            CreateOrUpdateBox(g_range.boxName, g_range.startTime, tEndActive, g_range.high, g_range.low, RetestConfirmedSellColor);
            if(ShowBreakoutArrows) DrawBreakoutArrow(time[i], high[i], false, RetestConfirmedSellColor);
            g_range.Reset();
           }
         else if(isFreshBreakout)
           {
            datetime tEndInvalid = time[i] + (datetime)periodSecs;
            CreateOrUpdateBox(g_range.boxName, g_range.startTime, tEndInvalid, g_range.high, g_range.low, InvalidatedBoxColor);

            g_range.status    = RANGE_ACTIVE;
            g_range.startTime = time[i];
            g_range.high      = high[i];
            g_range.low       = low[i];
            g_range.boxName   = MakeBoxName(time[i]);
            CreateOrUpdateBox(g_range.boxName, time[i], tEndActive, g_range.high, g_range.low, ActiveBoxColor);
           }
         else
           {
            CreateOrUpdateBox(g_range.boxName, g_range.startTime, tEndActive, g_range.high, g_range.low, AwaitingRetestBoxColor);
           }
        }
     }

   g_last_breakout_bar_time = time[lastClosed];
  }

//+------------------------------------------------------------------+
//| Main Iteration Function                                           |
//|                                                                    |
//| v8b: ONE new line added at the very top, right after the handle   |
//| sync checks. If the live bar's time[] is identical to what we saw |
//| last tick, the candle has NOT closed yet - return prev_calculated |
//| immediately (MQL5's "return null" for an int-returning function). |
//| Nothing below this point executes on such ticks: no ProcessMA     |
//| call, no signal engine call, no box redraw. Everything else in    |
//| this function is UNCHANGED from v8.                                |
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
     //--- v8b GATE: candle not closed yet -> return immediately, touch nothing. ---
   if(rates_total > 0 && prev_calculated > 0)
     {
      datetime liveBarTime = time[rates_total - 1];
      if(liveBarTime == g_lastSeenBarTime)
         return prev_calculated; // no new candle - equivalent of "return null"
     }

   if(Show1 && handle1 != INVALID_HANDLE && BarsCalculated(handle1) <= 0) return prev_calculated;
   if(Show2 && handle2 != INVALID_HANDLE && BarsCalculated(handle2) <= 0) return prev_calculated;
   if(Show3 && handle3 != INVALID_HANDLE && BarsCalculated(handle3) <= 0) return prev_calculated;


   int start = prev_calculated == 0 ? 0 : prev_calculated - 1;

   if(prev_calculated == 0)
     {
      cache1.Reset();
      cache2.Reset();
      cache3.Reset();
      g_last_signal_bar_time = 0;
      g_last_breakout_bar_time = 0;
      g_range.Reset();
      ObjectsDeleteAll(0, OBJ_PREFIX);
      ObjectsDeleteAll(0, OBJ_PREFIX_BOX);
     }

   int lastGoodBar = start - 1;

   for(int i = start; i < rates_total; i++)
     {
      datetime t = time[i];
      bool is_current_bar = (i == rates_total - 1);
      bool okAll = true;

      if(Show1)
        {
         if(!ProcessMA(i, t, is_current_bar, TF1, Type1, Len1, Src1, handle1, Smooth1, cache1, Buffer1))
            okAll = false;
        }
      else
         Buffer1[i] = EMPTY_VALUE;

      if(Show2)
        {
         if(!ProcessMA(i, t, is_current_bar, TF2, Type2, Len2, Src2, handle2, Smooth2, cache2, Buffer2))
            okAll = false;
        }
      else
         Buffer2[i] = EMPTY_VALUE;

      if(Show3)
        {
         if(!ProcessMA(i, t, is_current_bar, TF3, Type3, Len3, Src3, handle3, Smooth3, cache3, Buffer3))
            okAll = false;
        }
      else
         Buffer3[i] = EMPTY_VALUE;

      if(okAll)
         lastGoodBar = i;
     }

   RunEngulfingSignals(rates_total, time, open, high, low, close);
   RunRangeBreakout(rates_total, time, open, high, low, close);

   if(rates_total > 0)
      g_lastSeenBarTime = time[rates_total - 1];

   if(lastGoodBar < rates_total - 1 && lastGoodBar >= 0)
      return lastGoodBar + 1;

   return(rates_total);
  }

//+------------------------------------------------------------------+
//| Helper: Extract Specific Price Type from MqlRates                 |
//+------------------------------------------------------------------+
double GetPrice(const MqlRates &r, ENUM_APPLIED_PRICE ap)
  {
   switch(ap)
     {
      case PRICE_CLOSE:    return r.close;
      case PRICE_OPEN:     return r.open;
      case PRICE_HIGH:     return r.high;
      case PRICE_LOW:      return r.low;
      case PRICE_MEDIAN:   return (r.high + r.low) / 2.0;
      case PRICE_TYPICAL:  return (r.high + r.low + r.close) / 3.0;
      case PRICE_WEIGHTED: return (r.high + r.low + r.close * 2.0) / 4.0;
      default:             return r.close;
     }
  }

//+------------------------------------------------------------------+
//| Custom Math: Volume Weighted Moving Average (VWMA)                 |
//+------------------------------------------------------------------+
double CalculateVWMA(ENUM_TIMEFRAMES tf, int len, ENUM_APPLIED_PRICE ap, int shift)
  {
   if(shift < 0)
      return EMPTY_VALUE;

   MqlRates rates[];
   if(CopyRates(Symbol(), tf, shift, len, rates) != len)
      return EMPTY_VALUE;

   double sum_pv = 0, sum_v = 0;
   for(int i = 0; i < len; i++)
     {
      double p = GetPrice(rates[i], ap);
      double v = (double)rates[i].tick_volume;
      sum_pv += p * v;
      sum_v  += v;
     }

   if(sum_v == 0)
      return EMPTY_VALUE;
   return sum_pv / sum_v;
  }

//+------------------------------------------------------------------+
//| Custom Math: Hull Moving Average (HMA)                             |
//+------------------------------------------------------------------+
double CalculateHMA(ENUM_TIMEFRAMES tf, int len, ENUM_APPLIED_PRICE ap, int shift)
  {
   if(shift < 0)
      return EMPTY_VALUE;

   int half_len = (int)MathFloor(len / 2.0);
   int sq_len   = (int)MathRound(MathSqrt(len));
   int total_lookback = len + sq_len - 1;

   MqlRates rates[];
   if(CopyRates(Symbol(), tf, shift, total_lookback, rates) != total_lookback)
      return EMPTY_VALUE;

   double diff[];
   ArrayResize(diff, sq_len);

   for(int k = 0; k < sq_len; k++)
     {
      int end_idx = total_lookback - sq_len + k;

      double wma_full = 0, norm_full = 0;
      for(int j = 0; j < len; j++)
        {
         double weight = len - j;
         wma_full += GetPrice(rates[end_idx - j], ap) * weight;
         norm_full += weight;
        }
      wma_full /= norm_full;

      double wma_half = 0, norm_half = 0;
      for(int j = 0; j < half_len; j++)
        {
         double weight = half_len - j;
         wma_half += GetPrice(rates[end_idx - j], ap) * weight;
         norm_half += weight;
        }
      wma_half /= norm_half;

      diff[k] = 2.0 * wma_half - wma_full;
     }

   double hma = 0, norm_hma = 0;
   for(int j = 0; j < sq_len; j++)
     {
      double weight = sq_len - j;
      hma += diff[sq_len - 1 - j] * weight;
      norm_hma += weight;
     }

   return hma / norm_hma;
  }
//+------------------------------------------------------------------+