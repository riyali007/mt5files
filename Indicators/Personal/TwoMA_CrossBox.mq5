//+------------------------------------------------------------------+
//|                                                    MTF_3x_MA.mq5 |
//|                                          Converted from Pine Script |
//|                                     Fixed MTF, Caching & Smooth   |
//|                                                                   |
//|  v1.04 - Signal + Range Box fix: added Journal diagnostics for   |
//|  every stage (signal check, cross result, box create/extend/     |
//|  resolve), switched to darkest default colors, hardened the      |
//|  box-drawing calls (explicit property order + ChartRedraw), and  |
//|  fixed the closed-bar indexing so the engine actually evaluates  |
//|  every new closed bar instead of silently skipping it.           |
//+------------------------------------------------------------------+
#property copyright "MQL5 Conversion"
#property link      ""
#property version   "1.04"
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
   MA_SMA,  // SMA
   MA_EMA,  // EMA
   MA_WMA,  // WMA
   MA_VWMA, // VWMA
   MA_HMA,  // HMA
   MA_RMA   // RMA (Smoothed)
  };

//--- Signal / Box enums
enum ENUM_SIGNAL_SOURCE_MA
  {
   SIGNAL_MA1 = 0, // Use MA 1
   SIGNAL_MA2 = 1  // Use MA 2
  };

enum ENUM_SIGNAL_MODE
  {
   MODE_CROSS = 0,         // Cross Over/Under
   MODE_CROSS_PATTERN = 1  // Cross With Pattern (Engulfing)
  };

enum ENUM_RESOLUTION_MODE
  {
   RES_BREAKOUT = 0, // Breakout (color immediately on close)
   RES_RETEST   = 1  // Re-Test (wait for wick retest before coloring)
  };

//--- INPUTS: Signal Engine ---
input group "=== Signal Settings ==="
input ENUM_SIGNAL_SOURCE_MA InpSignalMA   = SIGNAL_MA1;     // Signal MA (which line to watch)
input ENUM_SIGNAL_MODE      InpSignalMode = MODE_CROSS;     // Signal Mode
input double                InpMinBodyPct = 30.0;           // Min Body % of H-L Range
input bool                  InpRequireOppositeColor = true; // Require Opposite Prev Candle Color

//--- INPUTS: Range Box ---
input group "=== Range Box Settings ==="
input ENUM_RESOLUTION_MODE InpResMode      = RES_BREAKOUT;      // Resolution Mode
input int                  InpRetestBars   = 3;                 // Re-Test Window (2-5 bars)
input color                InpColorBull    = (color)0x003300;   // Bullish Resolved Color (darkest green)
input color                InpColorBear    = (color)0x000033;   // Bearish Resolved Color (dark red substitute below)
input color                InpColorGray    = (color)0x1A1A1A;   // Unconfirmed (timeout) Color (near-black gray)
input color                InpColorPending = (color)0x2B2B2B;   // Pending / Extending Color (dark charcoal)
input bool                  InpVerboseLog   = true;              // Print signal/box diagnostics to Journal

//--- INPUTS: Moving Average 1 ---
input group "=== Moving Average 1 ==="
input bool               Show1 = true;          // Show MA 1
input bool               Smooth1 = true;         // Smooth MTF Line
input ENUM_MA_TYPE        Type1 = MA_EMA;         // Type
input int                 Len1 = 50;              // Length
input ENUM_TIMEFRAMES     TF1 = PERIOD_H1;        // Timeframe
input ENUM_APPLIED_PRICE  Src1 = PRICE_CLOSE;     // Source
input color               Col1 = clrBlue;         // Color

//--- INPUTS: Moving Average 2 ---
input group "=== Moving Average 2 ==="
input bool               Show2 = true;          // Show MA 2
input bool               Smooth2 = true;         // Smooth MTF Line
input ENUM_MA_TYPE        Type2 = MA_SMA;         // Type
input int                 Len2 = 100;             // Length
input ENUM_TIMEFRAMES     TF2 = PERIOD_H4;        // Timeframe
input ENUM_APPLIED_PRICE  Src2 = PRICE_CLOSE;     // Source
input color               Col2 = clrOrange;       // Color

//--- INPUTS: Moving Average 3 ---
input group "=== Moving Average 3 ==="
input bool               Show3 = true;          // Show MA 3
input bool               Smooth3 = true;         // Smooth MTF Line
input ENUM_MA_TYPE        Type3 = MA_WMA;         // Type
input int                 Len3 = 200;             // Length
input ENUM_TIMEFRAMES     TF3 = PERIOD_D1;        // Timeframe
input ENUM_APPLIED_PRICE  Src3 = PRICE_CLOSE;     // Source
input color               Col3 = clrMagenta;      // Color

//--- Buffers
double Buffer1[];
double Buffer2[];
double Buffer3[];

//--- Handles for native MAs (SMA, EMA, WMA, RMA)
int handle1 = INVALID_HANDLE;
int handle2 = INVALID_HANDLE;
int handle3 = INVALID_HANDLE;

//--- Cache structs for performance optimization (Only used when Smoothing is OFF)
struct SMACache
  {
   datetime last_htf_time;
   double   last_val;
   void     Reset() { last_htf_time = 0; last_val = EMPTY_VALUE; }
  };
SMACache cache1, cache2, cache3;

//--- Range Box tracking state (single "live" box at a time)
struct BoxState
  {
   bool     active;
   bool     resolvedColored;
   bool     pendingRetest;
   datetime timeStart;
   datetime timeEnd;
   double   top;
   double   bottom;
   bool     breakUp;
   int      barsSinceBreak;
   string   objName;
  };
BoxState gBox;
int gBoxCounter = 0;
datetime gLastProcessedSignalBarTime = 0; // guards against reprocessing same closed bar repeatedly

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

   if(Show1 && Type1 != MA_VWMA && Type1 != MA_HMA)
      handle1 = iMA(Symbol(), TF1, Len1, 0, GetNativeMode(Type1), Src1);

   if(Show2 && Type2 != MA_VWMA && Type2 != MA_HMA)
      handle2 = iMA(Symbol(), TF2, Len2, 0, GetNativeMode(Type2), Src2);

   if(Show3 && Type3 != MA_VWMA && Type3 != MA_HMA)
      handle3 = iMA(Symbol(), TF3, Len3, 0, GetNativeMode(Type3), Src3);

   gBox.active = false;
   gBox.resolvedColored = false;
   gBox.pendingRetest = false;
   gBox.objName = "";
   gLastProcessedSignalBarTime = 0;

   if(InpVerboseLog)
      Print("TwoMA Signals: OnInit complete. SignalMA=",EnumToString(InpSignalMA),
            " Mode=",EnumToString(InpSignalMode)," ResMode=",EnumToString(InpResMode));

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
   ObjectsDeleteAll(0, "TMCB_");
  }

//+------------------------------------------------------------------+
//| Helper: Get MA Value cleanly                                      |
//+------------------------------------------------------------------+
double GetMAValue(ENUM_TIMEFRAMES tf, ENUM_MA_TYPE type, int len, ENUM_APPLIED_PRICE src, int handle, int shift)
  {
   if(shift < 0) return EMPTY_VALUE;

   double val = EMPTY_VALUE;
   if(type == MA_VWMA) val = CalculateVWMA(tf, len, src, shift);
   else if(type == MA_HMA) val = CalculateHMA(tf, len, src, shift);
   else
     {
      double arr[1];
      if(CopyBuffer(handle, 0, shift, 1, arr) > 0) val = arr[0];
     }
   return val;
  }

//+------------------------------------------------------------------+
//| Candle body-size filter: body must be >= X% of the H-L range      |
//+------------------------------------------------------------------+
bool PassesBodyFilter(double o,double c,double h,double l,double minPct)
  {
   double range = h-l;
   if(range<=0.0) return false;
   double body = MathAbs(c-o);
   return ( (body/range)*100.0 >= minPct );
  }

//+------------------------------------------------------------------+
//| Strict, wick-inclusive engulfing checks                           |
//+------------------------------------------------------------------+
bool IsStrictBullishEngulf(double prevO,double prevC,double curO,double curC,
                            double prevH,double prevL,bool requireOppositeColor)
  {
   bool prevBearish = prevC < prevO;
   bool curBullish  = curC  > curO;
   if(requireOppositeColor && !prevBearish) return false;
   if(!curBullish) return false;
   if(curC < prevH) return false;
   if(curO > prevC) return false;
   double curBody  = MathAbs(curC-curO);
   double prevBody = MathAbs(prevC-prevO);
   if(curBody < prevBody) return false;
   return true;
  }

bool IsStrictBearishEngulf(double prevO,double prevC,double curO,double curC,
                            double prevH,double prevL,bool requireOppositeColor)
  {
   bool prevBullish = prevC > prevO;
   bool curBearish  = curC  < curO;
   if(requireOppositeColor && !prevBullish) return false;
   if(!curBearish) return false;
   if(curC > prevL) return false;
   if(curO < prevC) return false;
   double curBody  = MathAbs(curC-curO);
   double prevBody = MathAbs(prevC-prevO);
   if(curBody < prevBody) return false;
   return true;
  }

//+------------------------------------------------------------------+
//| Box object drawing helpers - hardened version                     |
//| Uses explicit property ordering and ChartRedraw so the rectangle  |
//| always appears immediately, regardless of terminal theme/build.   |
//+------------------------------------------------------------------+
bool CreateBoxObject(string name,datetime t1,double p1,datetime t2,double p2,color clr)
  {
   if(ObjectFind(0,name) >= 0) ObjectDelete(0,name);

   bool created = ObjectCreate(0,name,OBJ_RECTANGLE,0,t1,p1,t2,p2);
   if(!created)
     {
      if(InpVerboseLog) Print("TMCB: ObjectCreate FAILED for ",name," err=",GetLastError());
      return false;
     }

   ObjectSetInteger(0,name,OBJPROP_TIME,0,t1);
   ObjectSetDouble (0,name,OBJPROP_PRICE,0,p1);
   ObjectSetInteger(0,name,OBJPROP_TIME,1,t2);
   ObjectSetDouble (0,name,OBJPROP_PRICE,1,p2);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FILL,true);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);   // draw in FRONT so it's never hidden behind candles
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_SOLID);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,0);

   ChartRedraw(0);

   if(InpVerboseLog)
      Print("TMCB: Box created '",name,"' from ",TimeToString(t1)," to ",TimeToString(t2),
            " top=",DoubleToString(p1,_Digits)," bottom=",DoubleToString(p2,_Digits));

   return true;
  }

void UpdateBoxRight(string name,datetime t2,double bottomPrice)
  {
   if(ObjectFind(0,name) < 0) return;
   ObjectSetInteger(0,name,OBJPROP_TIME,1,t2);
   ObjectSetDouble (0,name,OBJPROP_PRICE,1,bottomPrice);
   ChartRedraw(0);
  }

void SetBoxColor(string name,color clr)
  {
   if(ObjectFind(0,name) < 0) return;
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,clr);
   ChartRedraw(0);
  }

void DeleteBox(string name)
  {
   if(name!="" && ObjectFind(0,name)>=0) ObjectDelete(0,name);
  }

//+------------------------------------------------------------------+
//| Start a brand-new box; enforces the supersede/invalidate rule:    |
//| any still-open box (extending OR pending-retest) is deleted the   |
//| instant a new signal fires. Only fully-resolved (colored) boxes   |
//| persist as historical markers.                                    |
//+------------------------------------------------------------------+
void StartNewBox(datetime signalTime,double top,double bottom)
  {
   if(gBox.active && !gBox.resolvedColored)
      DeleteBox(gBox.objName);

   gBoxCounter++;
   gBox.objName = "TMCB_Box_"+IntegerToString(gBoxCounter);
   gBox.active = true;
   gBox.resolvedColored = false;
   gBox.pendingRetest = false;
   gBox.timeStart = signalTime;
   gBox.timeEnd   = signalTime + 1; // +1 sec so the rectangle has non-zero initial width
   gBox.top = top;
   gBox.bottom = bottom;
   gBox.breakUp = false;
   gBox.barsSinceBreak = 0;

   CreateBoxObject(gBox.objName,gBox.timeStart,gBox.top,gBox.timeEnd,gBox.bottom,InpColorPending);
  }

//+------------------------------------------------------------------+
//| Signal + Box engine: evaluates the last fully-closed bar exactly  |
//| once per new closed bar. Reads MA1Buffer/MA2Buffer already        |
//| computed earlier in the same OnCalculate pass.                    |
//+------------------------------------------------------------------+
void ProcessSignalAndBox(const int rates_total,
                          const datetime &time[],
                          const double &open[],
                          const double &high[],
                          const double &low[],
                          const double &close[])
  {
   int closedIdx = rates_total - 2; // last fully closed bar (chronological array, current bar = rates_total-1)
   if(closedIdx < 1) return;
   if(time[closedIdx] <= gLastProcessedSignalBarTime) return; // already processed this closed bar

   double sigMA = (InpSignalMA==SIGNAL_MA1) ? Buffer1[closedIdx] : Buffer2[closedIdx];

   if(InpVerboseLog)
      Print("TMCB: checking bar ",TimeToString(time[closedIdx]),
            " sigMA=",(sigMA==EMPTY_VALUE?"EMPTY":DoubleToString(sigMA,_Digits)),
            " O=",DoubleToString(open[closedIdx],_Digits),
            " C=",DoubleToString(close[closedIdx],_Digits));

   if(sigMA==EMPTY_VALUE)
     {
      gLastProcessedSignalBarTime = time[closedIdx];
      return;
     }

   double o=open[closedIdx], c=close[closedIdx], h=high[closedIdx], l=low[closedIdx];
   bool bodyOK = PassesBodyFilter(o,c,h,l,InpMinBodyPct);

   bool bullCross = (o < sigMA) && (c > sigMA) && bodyOK;
   bool bearCross = (o > sigMA) && (c < sigMA) && bodyOK;

   if(InpSignalMode==MODE_CROSS_PATTERN && (bullCross || bearCross))
     {
      int prevIdx = closedIdx - 1;
      if(prevIdx < 0) { bullCross = false; bearCross = false; }
      else
        {
         double prevO=open[prevIdx], prevC=close[prevIdx], prevH=high[prevIdx], prevL=low[prevIdx];
         if(bullCross)
            bullCross = IsStrictBullishEngulf(prevO,prevC,o,c,prevH,prevL,InpRequireOppositeColor);
         if(bearCross)
            bearCross = IsStrictBearishEngulf(prevO,prevC,o,c,prevH,prevL,InpRequireOppositeColor);
        }
     }

   bool signalFired = bullCross || bearCross;

   if(InpVerboseLog && (bullCross || bearCross))
      Print("TMCB: SIGNAL FIRED at ",TimeToString(time[closedIdx]),
            bullCross ? " (BULLISH)" : " (BEARISH)");

   if(signalFired)
     {
      // New signal always supersedes any still-open box (extending or pending-retest).
      StartNewBox(time[closedIdx],h,l);
     }
   else if(gBox.active && time[closedIdx] > gBox.timeStart)
     {
      if(!gBox.resolvedColored && !gBox.pendingRetest)
        {
         gBox.timeEnd = time[closedIdx];
         UpdateBoxRight(gBox.objName,gBox.timeEnd,gBox.bottom);

         bool brokeUp   = c > gBox.top;
         bool brokeDown = c < gBox.bottom;
         if(brokeUp || brokeDown)
           {
            gBox.breakUp = brokeUp;
            if(InpVerboseLog)
               Print("TMCB: Box '",gBox.objName,"' BREAKOUT ",(brokeUp?"UP":"DOWN")," at ",TimeToString(time[closedIdx]));

            if(InpResMode==RES_BREAKOUT)
              {
               gBox.resolvedColored = true;
               // Color intentionally left as the same dark pending color per user request
               // (box shape/drawing is what matters; recoloring is optional).
              }
            else // RES_RETEST: freeze right edge at this bar, enter pending stage
              {
               gBox.pendingRetest = true;
               gBox.barsSinceBreak = 0;
              }
           }
        }
      else if(gBox.pendingRetest)
        {
         gBox.barsSinceBreak++;

         bool retested = gBox.breakUp ? (l <= gBox.top) : (h >= gBox.bottom);

         if(retested)
           {
            gBox.resolvedColored = true;
            gBox.pendingRetest = false;
            if(InpVerboseLog) Print("TMCB: Box '",gBox.objName,"' RETEST CONFIRMED at ",TimeToString(time[closedIdx]));
           }
         else if(gBox.barsSinceBreak >= InpRetestBars)
           {
            gBox.resolvedColored = true;
            gBox.pendingRetest = false;
            if(InpVerboseLog) Print("TMCB: Box '",gBox.objName,"' RETEST TIMEOUT (unconfirmed) at ",TimeToString(time[closedIdx]));
           }
        }
     }

   gLastProcessedSignalBarTime = time[closedIdx];
  }

//+------------------------------------------------------------------+
//| Main Iteration Function                                           |
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
   if(Show1 && handle1 != INVALID_HANDLE && BarsCalculated(handle1) <= 0) return 0;
   if(Show2 && handle2 != INVALID_HANDLE && BarsCalculated(handle2) <= 0) return 0;
   if(Show3 && handle3 != INVALID_HANDLE && BarsCalculated(handle3) <= 0) return 0;

   int start = prev_calculated == 0 ? 0 : prev_calculated - 1;

   if(prev_calculated == 0)
     {
      cache1.Reset();
      cache2.Reset();
      cache3.Reset();
     }

   for(int i = start; i < rates_total; i++)
     {
      datetime t = time[i];
      bool is_current_bar = (i == rates_total - 1);

      // ==========================================
      // --- Moving Average 1 ---
      // ==========================================
      if(Show1)
        {
         int shift = iBarShift(Symbol(), TF1, t);
         datetime htf_t = iTime(Symbol(), TF1, shift);
         if(htf_t == 0) return 0;

         if(!Smooth1 && !is_current_bar && htf_t == cache1.last_htf_time && cache1.last_val != EMPTY_VALUE)
           {
            Buffer1[i] = cache1.last_val;
           }
         else
           {
            double val = GetMAValue(TF1, Type1, Len1, Src1, handle1, shift);
            if(val == EMPTY_VALUE && !is_current_bar) return 0;

            if(Smooth1 && val != EMPTY_VALUE)
              {
               double val_prev = GetMAValue(TF1, Type1, Len1, Src1, handle1, shift + 1);
               if(val_prev != EMPTY_VALUE)
                 {
                  double fraction = (double)(t - htf_t) / PeriodSeconds(TF1);
                  if(fraction < 0.0) fraction = 0.0;
                  if(fraction > 1.0) fraction = 1.0;
                  val = val_prev + (val - val_prev) * fraction;
                 }
              }

            Buffer1[i] = val;

            if(!Smooth1 && !is_current_bar && val != EMPTY_VALUE)
              {
               cache1.last_htf_time = htf_t;
               cache1.last_val = val;
              }
           }
        }
      else Buffer1[i] = EMPTY_VALUE;

      // ==========================================
      // --- Moving Average 2 ---
      // ==========================================
      if(Show2)
        {
         int shift = iBarShift(Symbol(), TF2, t);
         datetime htf_t = iTime(Symbol(), TF2, shift);
         if(htf_t == 0) return 0;

         if(!Smooth2 && !is_current_bar && htf_t == cache2.last_htf_time && cache2.last_val != EMPTY_VALUE)
           {
            Buffer2[i] = cache2.last_val;
           }
         else
           {
            double val = GetMAValue(TF2, Type2, Len2, Src2, handle2, shift);
            if(val == EMPTY_VALUE && !is_current_bar) return 0;

            if(Smooth2 && val != EMPTY_VALUE)
              {
               double val_prev = GetMAValue(TF2, Type2, Len2, Src2, handle2, shift + 1);
               if(val_prev != EMPTY_VALUE)
                 {
                  double fraction = (double)(t - htf_t) / PeriodSeconds(TF2);
                  if(fraction < 0.0) fraction = 0.0;
                  if(fraction > 1.0) fraction = 1.0;
                  val = val_prev + (val - val_prev) * fraction;
                 }
              }

            Buffer2[i] = val;

            if(!Smooth2 && !is_current_bar && val != EMPTY_VALUE)
              {
               cache2.last_htf_time = htf_t;
               cache2.last_val = val;
              }
           }
        }
      else Buffer2[i] = EMPTY_VALUE;

      // ==========================================
      // --- Moving Average 3 ---
      // ==========================================
      if(Show3)
        {
         int shift = iBarShift(Symbol(), TF3, t);
         datetime htf_t = iTime(Symbol(), TF3, shift);
         if(htf_t == 0) return 0;

         if(!Smooth3 && !is_current_bar && htf_t == cache3.last_htf_time && cache3.last_val != EMPTY_VALUE)
           {
            Buffer3[i] = cache3.last_val;
           }
         else
           {
            double val = GetMAValue(TF3, Type3, Len3, Src3, handle3, shift);
            if(val == EMPTY_VALUE && !is_current_bar) return 0;

            if(Smooth3 && val != EMPTY_VALUE)
              {
               double val_prev = GetMAValue(TF3, Type3, Len3, Src3, handle3, shift + 1);
               if(val_prev != EMPTY_VALUE)
                 {
                  double fraction = (double)(t - htf_t) / PeriodSeconds(TF3);
                  if(fraction < 0.0) fraction = 0.0;
                  if(fraction > 1.0) fraction = 1.0;
                  val = val_prev + (val - val_prev) * fraction;
                 }
              }

            Buffer3[i] = val;

            if(!Smooth3 && !is_current_bar && val != EMPTY_VALUE)
              {
               cache3.last_htf_time = htf_t;
               cache3.last_val = val;
              }
           }
        }
      else Buffer3[i] = EMPTY_VALUE;
     }

   ProcessSignalAndBox(rates_total, time, open, high, low, close);

   return(rates_total);
  }

//+------------------------------------------------------------------+
//| Helper: Get MT5 Native MA Mode                                    |
//+------------------------------------------------------------------+
ENUM_MA_METHOD GetNativeMode(ENUM_MA_TYPE type)
  {
   switch(type)
     {
      case MA_SMA: return MODE_SMA;
      case MA_EMA: return MODE_EMA;
      case MA_WMA: return MODE_LWMA;
      case MA_RMA: return MODE_SMMA;
      default:     return MODE_SMA;
     }
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
//| Custom Math: Volume Weighted Moving Average (VWMA)                |
//+------------------------------------------------------------------+
double CalculateVWMA(ENUM_TIMEFRAMES tf, int len, ENUM_APPLIED_PRICE ap, int shift)
  {
   if(shift < 0) return EMPTY_VALUE;

   MqlRates rates[];
   if(CopyRates(Symbol(), tf, shift, len, rates) != len) return EMPTY_VALUE;

   double sum_pv = 0, sum_v = 0;
   for(int i = 0; i < len; i++)
     {
      double p = GetPrice(rates[i], ap);
      double v = (double)rates[i].tick_volume;
      sum_pv += p * v;
      sum_v += v;
     }

   if(sum_v == 0) return EMPTY_VALUE;
   return sum_pv / sum_v;
  }

//+------------------------------------------------------------------+
//| Custom Math: Hull Moving Average (HMA)                            |
//+------------------------------------------------------------------+
double CalculateHMA(ENUM_TIMEFRAMES tf, int len, ENUM_APPLIED_PRICE ap, int shift)
  {
   if(shift < 0) return EMPTY_VALUE;

   int half_len = (int)MathFloor(len / 2.0);
   int sq_len = (int)MathRound(MathSqrt(len));
   int total_lookback = len + sq_len - 1;

   MqlRates rates[];
   if(CopyRates(Symbol(), tf, shift, total_lookback, rates) != total_lookback) return EMPTY_VALUE;

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