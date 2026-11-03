//+------------------------------------------------------------------+
//|                                        BB_HMA_Reversal.mq5       |
//|   Bollinger Bands + HMA reversal signals (port of Pine v6 code)  |
//+------------------------------------------------------------------+
#property copyright   "BB + HMA Reversal Signals"
#property version     "1.00"
#property indicator_chart_window
#property indicator_buffers 13
#property indicator_plots   6

// Plot 1: BB Upper
#property indicator_label1  "BB Upper"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_width1  1
// Plot 2: BB Lower
#property indicator_label2  "BB Lower"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrDodgerBlue
#property indicator_width2  1
// Plot 3: BB Basis
#property indicator_label3  "BB Basis"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrOrange
#property indicator_width3  1
// Plot 4: HMA
#property indicator_label4  "HMA"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrGold
#property indicator_width4  2
// Plot 5: Buy arrow
#property indicator_label5  "Buy Signal"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrLime
#property indicator_width5  2
// Plot 6: Sell arrow
#property indicator_label6  "Sell Signal"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrRed
#property indicator_width6  2

//--- enums
enum ENUM_DIST_UNIT
  {
   DIST_POINTS = 0,   // MT5 points (_Point)
   DIST_PRICE  = 1    // Price units
  };

enum ENUM_BREAK_MODE
  {
   BREAK_CLOSE = 0,   // Close
   BREAK_WICK  = 1    // Wick
  };

//--- inputs
input group "Bollinger Bands"
input int                InpBBLen        = 20;             // BB Length
input double             InpBBMult       = 2.0;            // BB StdDev
input ENUM_APPLIED_PRICE InpBBSrc        = PRICE_CLOSE;    // BB Source

input group "HMA"
input int                InpHMALen       = 21;             // HMA Length
input ENUM_APPLIED_PRICE InpHMASrc       = PRICE_CLOSE;    // HMA Source

input group "Signal Rules"
input int                InpMaxBars      = 2;              // Max candles to confirm after band close
input bool               InpUseDist      = true;           // Use BB-to-HMA distance filter
input double             InpMaxDist      = 200.0;          // Max distance BB level to HMA
input ENUM_DIST_UNIT     InpDistUnit     = DIST_POINTS;    // Distance unit

input group "Direction Check"
input bool               InpUseSellDir   = true;           // SELL: candles must be decreasing
input bool               InpUseBuyDir    = true;           // BUY: candles must be increasing (mirror)

input group "Breakout Candle Break"
input bool               InpUseBreak     = true;           // Require break of breakout candle low (SELL) / high (BUY)
input ENUM_BREAK_MODE    InpBreakMode    = BREAK_CLOSE;    // Break counts when

input group "Display / Alerts"
input bool               InpClosedOnly   = true;           // Show signals only on closed bars
input int                InpArrowOffset  = 30;             // Arrow offset (points)
input bool               InpAlertPopup   = true;           // Popup alert
input bool               InpAlertPush    = false;          // Push notification
input bool               InpAlertSound   = false;          // Sound alert

//--- plot buffers
double BufUpper[];
double BufLower[];
double BufBasis[];
double BufHMA[];
double BufBuy[];
double BufSell[];

//--- calculation buffers
double BufBBPx[];       // BB source price
double BufHMAPx[];      // HMA source price
double BufDiff[];       // 2*WMA(n/2) - WMA(n)
double BufBuyAge[];     // -1 = not armed
double BufSellAge[];    // -1 = not armed
double BufBuyHigh[];    // high of candle that closed below lower band
double BufSellLow[];    // low of candle that closed above upper band

//--- globals
int      g_half;
int      g_sqrt;
double   g_unit;
datetime g_lastAlertBar = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpBBLen < 1 || InpHMALen < 2 || InpMaxBars < 1)
     {
      Print("Invalid input parameters");
      return(INIT_PARAMETERS_INCORRECT);
     }

   g_half = (int)MathFloor(InpHMALen / 2.0);
   g_sqrt = (int)MathRound(MathSqrt((double)InpHMALen));
   if(g_half < 1) g_half = 1;
   if(g_sqrt < 1) g_sqrt = 1;

   g_unit = (InpDistUnit == DIST_POINTS) ? _Point : 1.0;

   SetIndexBuffer(0,  BufUpper,   INDICATOR_DATA);
   SetIndexBuffer(1,  BufLower,   INDICATOR_DATA);
   SetIndexBuffer(2,  BufBasis,   INDICATOR_DATA);
   SetIndexBuffer(3,  BufHMA,     INDICATOR_DATA);
   SetIndexBuffer(4,  BufBuy,     INDICATOR_DATA);
   SetIndexBuffer(5,  BufSell,    INDICATOR_DATA);
   SetIndexBuffer(6,  BufBBPx,    INDICATOR_CALCULATIONS);
   SetIndexBuffer(7,  BufHMAPx,   INDICATOR_CALCULATIONS);
   SetIndexBuffer(8,  BufDiff,    INDICATOR_CALCULATIONS);
   SetIndexBuffer(9,  BufBuyAge,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(10, BufSellAge, INDICATOR_CALCULATIONS);
   SetIndexBuffer(11, BufBuyHigh, INDICATOR_CALCULATIONS);
   SetIndexBuffer(12, BufSellLow, INDICATOR_CALCULATIONS);

   for(int p = 0; p < 6; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   PlotIndexSetInteger(4, PLOT_ARROW, 233);   // up arrow
   PlotIndexSetInteger(5, PLOT_ARROW, 234);   // down arrow

   IndicatorSetString(INDICATOR_SHORTNAME, "BB + HMA Reversal");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
double Px(const ENUM_APPLIED_PRICE t, const int i,
          const double &o[], const double &h[], const double &l[], const double &c[])
  {
   switch(t)
     {
      case PRICE_OPEN:     return o[i];
      case PRICE_HIGH:     return h[i];
      case PRICE_LOW:      return l[i];
      case PRICE_MEDIAN:   return (h[i] + l[i]) / 2.0;
      case PRICE_TYPICAL:  return (h[i] + l[i] + c[i]) / 3.0;
      case PRICE_WEIGHTED: return (h[i] + l[i] + 2.0 * c[i]) / 4.0;
      default:             return c[i];
     }
  }

//--- weighted moving average ending at bar i (caller guarantees i >= len-1)
double WMA(const double &arr[], const int i, const int len)
  {
   double sum = 0.0, wsum = 0.0;
   for(int k = 0; k < len; k++)
     {
      double w = (double)(len - k);
      sum  += arr[i - k] * w;
      wsum += w;
     }
   return sum / wsum;
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
   int minBars = MathMax(InpBBLen, InpHMALen + g_sqrt) + 2;
   if(rates_total < minBars)
      return(0);

   ArraySetAsSeries(time,  false);
   ArraySetAsSeries(open,  false);
   ArraySetAsSeries(high,  false);
   ArraySetAsSeries(low,   false);
   ArraySetAsSeries(close, false);

   int start = (prev_calculated > 1) ? prev_calculated - 1 : 0;

   for(int i = start; i < rates_total; i++)
     {
      BufUpper[i] = EMPTY_VALUE;
      BufLower[i] = EMPTY_VALUE;
      BufBasis[i] = EMPTY_VALUE;
      BufHMA[i]   = EMPTY_VALUE;
      BufBuy[i]   = EMPTY_VALUE;
      BufSell[i]  = EMPTY_VALUE;
      BufDiff[i]  = EMPTY_VALUE;

      BufBBPx[i]  = Px(InpBBSrc,  i, open, high, low, close);
      BufHMAPx[i] = Px(InpHMASrc, i, open, high, low, close);

      //--- Bollinger Bands (population standard deviation, like ta.bb)
      bool bbOk = (i >= InpBBLen - 1);
      if(bbOk)
        {
         double mean = 0.0;
         for(int k = 0; k < InpBBLen; k++)
            mean += BufBBPx[i - k];
         mean /= InpBBLen;

         double var = 0.0;
         for(int k = 0; k < InpBBLen; k++)
           {
            double d = BufBBPx[i - k] - mean;
            var += d * d;
           }
         double sd = MathSqrt(var / InpBBLen);

         BufBasis[i] = mean;
         BufUpper[i] = mean + InpBBMult * sd;
         BufLower[i] = mean - InpBBMult * sd;
        }

      //--- HMA = WMA( 2*WMA(n/2) - WMA(n), sqrt(n) )
      if(i >= InpHMALen - 1)
         BufDiff[i] = 2.0 * WMA(BufHMAPx, i, g_half) - WMA(BufHMAPx, i, InpHMALen);

      bool hmaOk = (i >= InpHMALen - 1 + g_sqrt - 1);
      if(hmaOk)
         BufHMA[i] = WMA(BufDiff, i, g_sqrt);

      //--- carry state from previous bar
      double bAge = -1, sAge = -1, bHigh = 0, sLow = 0;
      if(i > 0)
        {
         bAge  = BufBuyAge[i - 1];
         sAge  = BufSellAge[i - 1];
         bHigh = BufBuyHigh[i - 1];
         sLow  = BufSellLow[i - 1];
        }

      // age pending setups by one bar
      if(bAge >= 0) bAge += 1;
      if(sAge >= 0) sAge += 1;

      //--- direction check
      bool sellBroken = (sAge >= 1 && InpUseSellDir && i > 0 && close[i] >= close[i - 1]);
      bool buyBroken  = (bAge >= 1 && InpUseBuyDir  && i > 0 && close[i] <= close[i - 1]);

      //--- breakout candle level break
      bool sellBreakOk = true, buyBreakOk = true;
      if(InpUseBreak)
        {
         sellBreakOk = (InpBreakMode == BREAK_CLOSE) ? (close[i] < sLow)  : (low[i]  < sLow);
         buyBreakOk  = (InpBreakMode == BREAK_CLOSE) ? (close[i] > bHigh) : (high[i] > bHigh);
        }

      //--- distance filter
      bool buyDistOk = true, sellDistOk = true;
      if(InpUseDist && bbOk && hmaOk)
        {
         buyDistOk  = (MathAbs(BufHMA[i] - BufLower[i]) / g_unit) < InpMaxDist;
         sellDistOk = (MathAbs(BufUpper[i] - BufHMA[i]) / g_unit) < InpMaxDist;
        }

      //--- signals
      bool buySignal  = hmaOk && bAge >= 1 && bAge <= InpMaxBars &&
                        close[i] > BufHMA[i] && buyDistOk && !buyBroken && buyBreakOk;
      bool sellSignal = hmaOk && sAge >= 1 && sAge <= InpMaxBars &&
                        close[i] < BufHMA[i] && sellDistOk && !sellBroken && sellBreakOk;

      //--- disarm after signal, invalidation, or expired window
      if(buySignal  || buyBroken  || (bAge >= 0 && bAge >= InpMaxBars)) bAge = -1;
      if(sellSignal || sellBroken || (sAge >= 0 && sAge >= InpMaxBars)) sAge = -1;

      //--- arm on a close beyond the bands (opposite side cancelled)
      if(bbOk && close[i] < BufLower[i])
        {
         bAge  = 0;
         bHigh = high[i];
         sAge  = -1;
        }
      if(bbOk && close[i] > BufUpper[i])
        {
         sAge = 0;
         sLow = low[i];
         bAge = -1;
        }

      //--- store state for this bar
      BufBuyAge[i]  = bAge;
      BufSellAge[i] = sAge;
      BufBuyHigh[i] = bHigh;
      BufSellLow[i] = sLow;

      //--- arrows (suppressed on the forming bar if closed-only)
      bool allowDraw = !(InpClosedOnly && i == rates_total - 1);
      double off = InpArrowOffset * _Point;
      if(allowDraw && buySignal)  BufBuy[i]  = low[i]  - off;
      if(allowDraw && sellSignal) BufSell[i] = high[i] + off;
     }

   //--- alerts: once per newly closed bar, not on history
   if(prev_calculated > 0 && rates_total >= 2)
     {
      int    last = rates_total - 2;      // last closed bar
      datetime t  = time[last];
      if(t != g_lastAlertBar)
        {
         string msg = "";
         if(BufBuy[last]  != EMPTY_VALUE) msg = "BB + HMA: BUY signal on "  + _Symbol + " " + EnumToString(_Period);
         if(BufSell[last] != EMPTY_VALUE) msg = "BB + HMA: SELL signal on " + _Symbol + " " + EnumToString(_Period);

         if(msg != "")
           {
            if(InpAlertPopup) Alert(msg);
            if(InpAlertPush)  SendNotification(msg);
            if(InpAlertSound) PlaySound("alert.wav");
           }
         g_lastAlertBar = t;
        }
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+