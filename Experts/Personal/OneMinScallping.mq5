//+------------------------------------------------------------------+
//|                                    CandlePatternMTF.mq5          |
//|                        Simple Candle Pattern Indicator           |
//+------------------------------------------------------------------+
#property copyright   "MT5 Developer"
#property version     "1.00"
#property indicator_chart_window
#property indicator_plots 2

#property indicator_label1  "Sell Signal"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrRed
#property indicator_width1  2

#property indicator_label2  "Buy Signal"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrLime
#property indicator_width2  2

input double InpDojiBodyPct = 5.0;  // Doji: max body % of range
input int    InpArrowGap    = 5;    // Arrow gap in points
input int    InpSellArrow   = 234;  // Sell arrow code
input int    InpBuyArrow    = 233;  // Buy arrow code

double SellBuffer[];
double BuyBuffer[];

//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, SellBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, BuyBuffer,  INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_ARROW, InpSellArrow);
   PlotIndexSetInteger(1, PLOT_ARROW, InpBuyArrow);

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   IndicatorSetString(INDICATOR_SHORTNAME, "CandlePattern");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
bool isBull(int i, const double &open[], const double &close[])
  { return close[i] > open[i]; }

bool isBear(int i, const double &open[], const double &close[])
  { return close[i] < open[i]; }

bool isDoji(int i, const double &open[], const double &high[],
            const double &low[], const double &close[])
  {
   double range = high[i] - low[i];
   if(range == 0.0) return true;
   return (MathAbs(close[i] - open[i]) / range * 100.0) <= InpDojiBodyPct;
  }

//+------------------------------------------------------------------+
int OnCalculate(const int      rates_total,
                const int      prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
  {
   if(rates_total < 3)
      return 0;

   //--- Step 1: determine the start index for this pass
   int startBar;
   if(prev_calculated <= 0)
     {
      //--- First run: initialise every buffer slot from scratch
      ArrayInitialize(SellBuffer, EMPTY_VALUE);
      ArrayInitialize(BuyBuffer,  EMPTY_VALUE);
      startBar = 2;            // first bar where i-2 exists
     }
   else
     {
      startBar = prev_calculated - 1;   // recheck the last bar
     }
   if (startBar>2)
   {
   //--- Step 2: evaluate signals — buffers already set to EMPTY_VALUE
   for(int i = startBar; i < rates_total; i++)
     {
      SellBuffer[i] = EMPTY_VALUE;
      BuyBuffer[i]  = EMPTY_VALUE;

      //--- sellC1: Bull(i-2), Bull(i-1), Bear(i), no dojis
      if(isBull(i-2, open, close) &&
         isBull(i-1, open, close) &&
         isBear(i,   open, close) &&
        !isDoji(i-2, open, high, low, close) &&
        !isDoji(i-1, open, high, low, close) &&
        !isDoji(i,   open, high, low, close))
        {
         SellBuffer[i] = high[i] + InpArrowGap * _Point;
        }

      //--- buyC1: Bear(i-2), Bear(i-1), Bull(i), no dojis
      if(isBear(i-2, open, close) &&
         isBear(i-1, open, close) &&
         isBull(i,   open, close) &&
        !isDoji(i-2, open, high, low, close) &&
        !isDoji(i-1, open, high, low, close) &&
        !isDoji(i,   open, high, low, close))
        {
         BuyBuffer[i] = low[i] - InpArrowGap * _Point;
        }
     }
     }

   return rates_total;
  }
//+------------------------------------------------------------------+