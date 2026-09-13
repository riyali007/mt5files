//+------------------------------------------------------------------+
//|                                       HMA_with_Engulfing.mq5     |
//|  Base: HMA.mq5 - HMA math is 100% UNCHANGED, byte-for-byte         |
//|  identical to the original working file.                           |
//|                                                                  |
//|  Added: Setup 1 ONLY - Engulfing Break Signal.                     |
//|    1. Price closes above HMA -> check Bullish Engulfing -> Buy     |
//|    2. Price closes below HMA -> check Bearish Engulfing -> Sell    |
//|    3. Draw horizontal range lines over the engulfing candle,       |
//|       extended forward by a configurable number of candles.        |
//|  Signal logic only evaluates fully CLOSED bars - never repaints,   |
//|  never touches the live/forming bar.                                |
//|                                                                  |
//|  Object cleanup: tied ONLY to OnInit(), which fires exactly once   |
//|  per genuine attach / reattach / timeframe switch / symbol switch  |
//|  / input change - never on ordinary tick processing. This removes  |
//|  stale signal lines from a previous timeframe without ever wiping  |
//|  objects on a normal recalculation tick.                           |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots 1
#property indicator_type1 DRAW_LINE
#property indicator_width1 2

//--- Inputs must be strictly in this order (HMA settings first, unchanged)
input int InpPeriod = 14;
input ENUM_APPLIED_PRICE InpPrice = PRICE_CLOSE;
input color InpColor = clrDodgerBlue;

//--- Setup 1: Engulfing signal inputs
input group "=== Setup 1: Engulfing Settings ==="
input bool                EnableEngulfing  = true;        // Enable Engulfing Break Signal
input int                 ExtendBars       = 3;            // Range Line Extend (Candles, 2-3 typical)
input color               BuyRangeColor    = clrLime;      // Buy Range Line Color
input color               SellRangeColor   = clrRed;       // Sell Range Line Color
input int                 RangeLineWidth   = 1;             // Range Line Width
input ENUM_LINE_STYLE     RangeLineStyle   = STYLE_SOLID;   // Range Line Style
input bool                ShowSignalArrows = true;          // Show Buy/Sell Arrows

double ExtBuffer[];
int handle_WMA_half, handle_WMA_full;
double arr_half[], arr_full[];

//--- Track the last closed bar we scanned for engulfing signals
datetime g_last_signal_bar_time = 0;

#define OBJ_PREFIX "HMA_ENG_SIG_"

//+------------------------------------------------------------------+
//| OnInit - identical to original HMA.mq5, PLUS object cleanup.      |
//| ObjectsDeleteAll here (not inside OnCalculate) because OnInit      |
//| only fires on a genuine context change (attach/timeframe/symbol/  |
//| input change), never on a routine tick-driven recalculation.       |
//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, ExtBuffer, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpColor); // Set dynamic color
   IndicatorSetString(INDICATOR_SHORTNAME, "HMA(" + IntegerToString(InpPeriod) + ")");

   int half_period = (int)MathFloor(InpPeriod / 2.0);
   handle_WMA_half = iMA(_Symbol, _Period, half_period, 0, MODE_LWMA, InpPrice);
   handle_WMA_full = iMA(_Symbol, _Period, InpPeriod, 0, MODE_LWMA, InpPrice);

   ArraySetAsSeries(arr_half, true);
   ArraySetAsSeries(arr_full, true);

   g_last_signal_bar_time = 0;

   // Genuine context change (attach, timeframe switch, symbol switch, input change) -
   // clear every signal object we own so nothing from a previous context lingers.
   ObjectsDeleteAll(0, OBJ_PREFIX);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| OnDeinit - clear objects on teardown-style reasons too, as a      |
//| defensive backstop (OnInit's cleanup already covers the normal    |
//| re-attach/timeframe-switch case).                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(reason == REASON_REMOVE || reason == REASON_CHARTCHANGE || reason == REASON_TEMPLATE)
      ObjectsDeleteAll(0, OBJ_PREFIX);
  }

//+------------------------------------------------------------------+
//| Setup 1 Helpers: Engulfing pattern detection                      |
//+------------------------------------------------------------------+
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
//| Draw the range lines + optional arrow for a signal candle         |
//+------------------------------------------------------------------+
void DrawSignalRange(int i, const datetime &time[], const double &high[], const double &low[], bool isBuy)
  {
   datetime tStart = time[i];
   long periodSecs = PeriodSeconds();
   datetime tEnd = tStart + (datetime)(periodSecs * ExtendBars);

   double topPrice    = high[i];
   double bottomPrice = low[i];
   color  lineColor   = isBuy ? BuyRangeColor : SellRangeColor;
   string tag         = isBuy ? "BUY" : "SELL";

   string nameTop    = OBJ_PREFIX + tag + "_TOP_"   + IntegerToString((long)tStart);
   string nameBottom = OBJ_PREFIX + tag + "_BOT_"   + IntegerToString((long)tStart);
   string nameArrow  = OBJ_PREFIX + tag + "_ARROW_" + IntegerToString((long)tStart);

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
//| Setup 1: Engulfing Break Signal Scan - runs on CLOSED bars only.  |
//| ExtBuffer[i] is read DIRECTLY - non-series, aligned with time[i], |
//| exactly as the original HMA.mq5 writes it.                         |
//+------------------------------------------------------------------+
void RunEngulfingSignals(int rates_total, const datetime &time[], const double &open[],
                         const double &high[], const double &low[], const double &close[])
  {
   if(!EnableEngulfing) return;
   if(rates_total < 3) return;

   int lastClosed = rates_total - 2; // absolute index of the last fully closed bar
   if(lastClosed < 1) return;
   if(g_last_signal_bar_time != 0 && time[lastClosed] == g_last_signal_bar_time) return;

   int scanStart = 1;
   if(g_last_signal_bar_time != 0)
     {
      int idx = -1;
      for(int k = lastClosed; k >= 1; k--)
         if(time[k] == g_last_signal_bar_time) { idx = k; break; }
      scanStart = (idx >= 0) ? idx + 1 : MathMax(1, lastClosed - 5);
     }
   else
      scanStart = MathMax(1, lastClosed - 500);

   for(int i = scanStart; i <= lastClosed; i++)
     {
      double hmaVal     = ExtBuffer[i];
      double hmaValPrev = ExtBuffer[i-1];
      if(hmaVal == 0.0 || hmaValPrev == 0.0) continue; // not yet computed for this bar

      bool brokeAbove = (close[i-1] <= hmaValPrev) && (close[i] > hmaVal);
      bool brokeBelow = (close[i-1] >= hmaValPrev) && (close[i] < hmaVal);

      if(brokeAbove && IsBullishEngulfing(open, close, i))
         DrawSignalRange(i, time, high, low, true);
      else if(brokeBelow && IsBearishEngulfing(open, close, i))
         DrawSignalRange(i, time, high, low, false);
     }

   g_last_signal_bar_time = time[lastClosed];
  }

//+------------------------------------------------------------------+
//| OnCalculate - Fixed CopyBuffer fallback to prevent flickering.    |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                 const double &open[], const double &high[], const double &low[], const double &close[],
                 const long &tick_volume[], const long &volume[], const int &spread[])
  {
   if(rates_total < InpPeriod) return 0;

   int limit = rates_total - prev_calculated;
   if(prev_calculated > 0) limit++;
   else limit = rates_total - InpPeriod;

   int sqrt_period = (int)MathFloor(MathSqrt(InpPeriod));
   int to_copy = limit + sqrt_period;

   // FIX: If buffers aren't ready, return prev_calculated instead of 0 to stop chart wiping/flickering
   if(CopyBuffer(handle_WMA_half, 0, 0, to_copy, arr_half) < to_copy || 
      CopyBuffer(handle_WMA_full, 0, 0, to_copy, arr_full) < to_copy)
     {
      return (prev_calculated > 0 ? prev_calculated : 0);
     }

   double raw_hma[];
   ArrayResize(raw_hma, limit + sqrt_period);
   for(int i = 0; i < limit + sqrt_period; i++)
     {
      raw_hma[i] = (2.0 * arr_half[i]) - arr_full[i];
     }

   for(int i = 0; i < limit; i++)
     {
      double sum = 0.0, weight_sum = 0.0;
      for(int j = 0; j < sqrt_period; j++)
        {
         double weight = (double)(sqrt_period - j);
         sum += raw_hma[i + j] * weight;
         weight_sum += weight;
        }
      ExtBuffer[rates_total - 1 - i] = sum / weight_sum;
     }

   // Setup 1 only - self-gates internally, only does real work when a new bar has closed.
   RunEngulfingSignals(rates_total, time, open, high, low, close);

   return(rates_total);
  }
//+------------------------------------------------------------------+