//+------------------------------------------------------------------+
//|                                   HMA_Engulfing_Crossover.mq5    |
//|  Base: HMA.mq5 - HMA math is 100% UNCHANGED, byte-for-byte       |
//|  identical to the original working file.                         |
//|                                                                  |
//|  MA1 = Original HMA[cite: 1]                                              |
//|  MA2 = Custom MA 1                                               |
//|  MA3 = Custom MA 2                                               |
//|                                                                  |
//|  Setup 1: Engulfing & Simple Breakout Signals (Selectable MA)    |
//|  Setup 2: Comprehensive MA Crossover with multi-source selection |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots 3

#property indicator_type1 DRAW_LINE
#property indicator_width1 2

#property indicator_type2 DRAW_LINE
#property indicator_width2 1

#property indicator_type3 DRAW_LINE
#property indicator_width3 1

enum ENUM_CUSTOM_MA
  {
   MA_EMA=0,   // Exponential MA (EMA)
   MA_WMA=1,   // Linear Weighted MA (WMA)
   MA_HMA=2,   // Hull MA (HMA)
   MA_ALMA=3,  // Arnaud Legoux MA (ALMA)
   MA_DEMA=4   // Double EMA (DEMA)
  };

enum ENUM_CROSS_MODE
  {
   CROSS_MA1_MA2 = 0, // MA1 Crosses MA2
   CROSS_MA2_MA1 = 1, // MA2 Crosses MA1
   CROSS_MA1_MA3 = 2, // MA1 Crosses MA3
   CROSS_MA3_MA1 = 3, // MA3 Crosses MA1
   CROSS_MA2_MA3 = 4, // MA2 Crosses MA3
   CROSS_MA3_MA2 = 5  // MA3 Crosses MA2
  };

enum ENUM_SIGNAL_MA
  {
   SIG_MA1 = 0, // MA1 (Original HMA)
   SIG_MA2 = 1, // MA2
   SIG_MA3 = 2  // MA3
  };

//--- MA1 (Original HMA) Settings
input group "=== MA1 (Original HMA) Settings ==="
input int                 MA1_Period       = 14;           // MA1 Period
input ENUM_APPLIED_PRICE  MA1_Price        = PRICE_CLOSE;  // MA1 Applied Price
input color               MA1_Color        = clrDodgerBlue;// MA1 Line Color

//--- MA2 Settings
input group "=== MA2 Settings ==="
input ENUM_CUSTOM_MA      MA2_Type         = MA_EMA;       // MA2 Type
input int                 MA2_Period       = 50;           // MA2 Period
input ENUM_APPLIED_PRICE  MA2_Price        = PRICE_CLOSE;  // MA2 Applied Price
input color               MA2_Color        = clrYellow;    // MA2 Line Color

//--- MA3 Settings
input group "=== MA3 Settings ==="
input ENUM_CUSTOM_MA      MA3_Type         = MA_EMA;       // MA3 Type
input int                 MA3_Period       = 200;          // MA3 Period
input ENUM_APPLIED_PRICE  MA3_Price        = PRICE_CLOSE;  // MA3 Applied Price
input color               MA3_Color        = clrMagenta;   // MA3 Line Color

input group "=== ALMA Specific Settings ==="
input double              ALMA_Offset      = 0.85;         // ALMA Offset (if used)
input int                 ALMA_Sigma       = 6;            // ALMA Sigma (if used)

//--- Setup 1: Signal inputs
input group "=== Setup 1: Breakout & Engulfing Signals ==="
input ENUM_SIGNAL_MA      SignalSourceMA   = SIG_MA1;      // Source MA for Signals
input bool                EnableEngulfing  = true;         // Mark Engulfing Breakout[cite: 1]
input bool                EnableBreakout   = false;        // Mark Simple Breakout
input int                 ExtendBars       = 3;            // Range Line Extend (Candles)
input color               BuyRangeColor    = clrLime;      // Buy Range Line Color
input color               SellRangeColor   = clrRed;       // Sell Range Line Color
input int                 RangeLineWidth   = 1;            // Range Line Width
input ENUM_LINE_STYLE     RangeLineStyle   = STYLE_SOLID;  // Range Line Style
input bool                ShowSignalArrows = true;         // Show Buy/Sell Arrows

//--- Setup 2: MA Crossover Settings
input group "=== Setup 2: MA Crossover Settings ==="
input bool                EnableCrossover  = true;          // Enable MA Crossover Signals
input ENUM_CROSS_MODE     CrossoverMode    = CROSS_MA1_MA2; // Crossover Pair Selection
input bool                EnableAlerts     = true;          // Enable Pop-up Alerts
input color               CrossBuyColor    = clrAqua;       // Crossover Buy Arrow Color
input color               CrossSellColor   = clrOrange;     // Crossover Sell Arrow Color

//--- Buffers
double MA1Buffer[];
double MA2Buffer[];
double MA3Buffer[];

//--- Handles & Arrays for MA1 (Original HMA)
int hMA1Half, hMA1Full;
double arrMA1Half[], arrMA1Full[];

//--- Handles & Arrays for MA2
int hMA2, hMA2Half, hMA2Full, hMA2Price;
double arrMA2Half[], arrMA2Full[];

//--- Handles & Arrays for MA3
int hMA3, hMA3Half, hMA3Full, hMA3Price;
double arrMA3Half[], arrMA3Full[];

//--- Global trackers
datetime g_last_signal_bar_time = 0;
datetime g_last_cross_time = 0;

//--- Overlap trackers for Setup 1
datetime g_last_buy_end = 0;
string g_last_buy_top = "", g_last_buy_bot = "", g_last_buy_arrow = "";

datetime g_last_sell_end = 0;
string g_last_sell_top = "", g_last_sell_bot = "", g_last_sell_arrow = "";

#define OBJ_PREFIX "HMA_SIG_"
#define OBJ_PREFIX_CROSS "MA_CROSS_"

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, MA1Buffer, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, MA1_Color);
   IndicatorSetString(INDICATOR_SHORTNAME, "HMA+Cross");

   SetIndexBuffer(1, MA2Buffer, INDICATOR_DATA);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, MA2_Color);

   SetIndexBuffer(2, MA3Buffer, INDICATOR_DATA);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, MA3_Color);

   // MA1 Handles[cite: 1]
   int main_half = (int)MathFloor(MA1_Period / 2.0);
   hMA1Half = iMA(_Symbol, _Period, main_half, 0, MODE_LWMA, MA1_Price);
   hMA1Full = iMA(_Symbol, _Period, MA1_Period, 0, MODE_LWMA, MA1_Price);
   ArraySetAsSeries(arrMA1Half, true);
   ArraySetAsSeries(arrMA1Full, true);

   // Custom MA Handles
   InitCustomMA(MA2_Type, MA2_Period, MA2_Price, hMA2, hMA2Half, hMA2Full, hMA2Price, arrMA2Half, arrMA2Full);
   InitCustomMA(MA3_Type, MA3_Period, MA3_Price, hMA3, hMA3Half, hMA3Full, hMA3Price, arrMA3Half, arrMA3Full);

   g_last_signal_bar_time = 0;
   g_last_cross_time = 0;
   g_last_buy_end = 0;
   g_last_sell_end = 0;

   ObjectsDeleteAll(0, OBJ_PREFIX);
   ObjectsDeleteAll(0, OBJ_PREFIX_CROSS);

   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(reason == REASON_REMOVE || reason == REASON_CHARTCHANGE || reason == REASON_TEMPLATE)
     {
      ObjectsDeleteAll(0, OBJ_PREFIX);
      ObjectsDeleteAll(0, OBJ_PREFIX_CROSS);
     }
  }

//+------------------------------------------------------------------+
//| Custom MA Helpers                                                |
//+------------------------------------------------------------------+
void InitCustomMA(ENUM_CUSTOM_MA type, int period, ENUM_APPLIED_PRICE price, 
                  int &h, int &hHalf, int &hFull, int &hPrice, double &arrHalf[], double &arrFull[])
  {
   h = INVALID_HANDLE; hHalf = INVALID_HANDLE; hFull = INVALID_HANDLE; hPrice = INVALID_HANDLE;
   if(type == MA_EMA) h = iMA(_Symbol, _Period, period, 0, MODE_EMA, price);
   else if(type == MA_WMA) h = iMA(_Symbol, _Period, period, 0, MODE_LWMA, price);
   else if(type == MA_DEMA) h = iDEMA(_Symbol, _Period, period, 0, price);
   else if(type == MA_HMA)
     {
      int half = (int)MathFloor(period / 2.0);
      hHalf = iMA(_Symbol, _Period, half, 0, MODE_LWMA, price);
      hFull = iMA(_Symbol, _Period, period, 0, MODE_LWMA, price);
      ArraySetAsSeries(arrHalf, true);
      ArraySetAsSeries(arrFull, true);
     }
   else if(type == MA_ALMA) hPrice = iMA(_Symbol, _Period, 1, 0, MODE_SMA, price); 
  }

bool CalcHMA(int rates_total, int prev_calculated, int period, int hHalf, int hFull,
             double &arr_half[], double &arr_full[], double &buffer[])
  {
   int limit = rates_total - prev_calculated;
   if(prev_calculated > 0) limit++;
   else limit = rates_total - period;
   if(limit <= 0) return true;

   int sqrt_period = (int)MathFloor(MathSqrt(period));
   int to_copy = limit + sqrt_period;

   if(CopyBuffer(hHalf, 0, 0, to_copy, arr_half) < to_copy ||
      CopyBuffer(hFull, 0, 0, to_copy, arr_full) < to_copy)
      return false;

   double raw_hma[];
   ArrayResize(raw_hma, to_copy);
   for(int i = 0; i < to_copy; i++) raw_hma[i] = (2.0 * arr_half[i]) - arr_full[i];

   for(int i = 0; i < limit; i++)
     {
      double sum = 0.0, weight_sum = 0.0;
      for(int j = 0; j < sqrt_period; j++)
        {
         double weight = (double)(sqrt_period - j);
         sum += raw_hma[i + j] * weight;
         weight_sum += weight;
        }
      buffer[rates_total - 1 - i] = sum / weight_sum;
     }
   return true;
  }

bool CalcStandardMA(int rates_total, int prev_calculated, int handle, double &buffer[])
  {
   int limit = rates_total - prev_calculated;
   if(prev_calculated > 0) limit++;
   else limit = rates_total;
   if(limit <= 0) return true;

   double temp[];
   if(CopyBuffer(handle, 0, 0, limit, temp) < limit) return false;
   for(int i=0; i<limit; i++) buffer[rates_total - limit + i] = temp[i];
   return true;
  }

bool CalcALMA(int rates_total, int prev_calculated, int period, double offset, int sigma, int hPrice, double &buffer[])
  {
   int limit = rates_total - prev_calculated;
   if(prev_calculated > 0) limit++;
   else limit = rates_total - period;
   if(limit <= 0) return true;

   double priceArray[];
   if(CopyBuffer(hPrice, 0, 0, limit + period, priceArray) < (limit + period)) return false;

   int m = (int)MathFloor(offset * (period - 1));
   double s = (double)period / sigma;

   for(int i = rates_total - limit; i < rates_total; i++)
     {
      if(i < period - 1) { buffer[i] = 0.0; continue; }
      double sum = 0.0, weight_sum = 0.0;
      for(int j = 0; j < period; j++)
        {
         double w = MathExp(-0.5 * MathPow((j - m) / s, 2));
         double p = priceArray[(limit + period - 1) - (rates_total - 1 - (i - j))]; 
         sum += p * w;
         weight_sum += w;
        }
      buffer[i] = sum / weight_sum;
     }
   return true;
  }

bool ProcessCustomMA(ENUM_CUSTOM_MA type, int rates_total, int prev_calculated, int period,
                     int h, int hHalf, int hFull, int hPrice, double &arrHalf[], double &arrFull[],
                     double offset, int sigma, double &buffer[])
  {
   if(type == MA_ALMA) return CalcALMA(rates_total, prev_calculated, period, offset, sigma, hPrice, buffer);
   else if(type == MA_HMA) return CalcHMA(rates_total, prev_calculated, period, hHalf, hFull, arrHalf, arrFull, buffer);
   else return CalcStandardMA(rates_total, prev_calculated, h, buffer);
  }

//+------------------------------------------------------------------+
//| Setup 1: Pattern Detection & Signal Processing                   |
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

void DrawSignalRange(int i, const datetime &time[], const double &high[], const double &low[], bool isBuy, string typeTag)
  {
   datetime tStart = time[i];
   datetime tEnd = tStart + (datetime)(PeriodSeconds() * ExtendBars);

   double topPrice    = high[i];
   double bottomPrice = low[i];
   color  lineColor   = isBuy ? BuyRangeColor : SellRangeColor;
   string tag         = isBuy ? "BUY_" + typeTag : "SELL_" + typeTag;

   string nameTop    = OBJ_PREFIX + tag + "_TOP_"   + IntegerToString((long)tStart);
   string nameBottom = OBJ_PREFIX + tag + "_BOT_"   + IntegerToString((long)tStart);
   string nameArrow  = OBJ_PREFIX + tag + "_ARROW_" + IntegerToString((long)tStart);

   // Overlap Fix: If a new signal appears while the previous one is still active, delete the previous one.
   if(isBuy)
     {
      if(g_last_buy_end != 0 && tStart <= g_last_buy_end)
        {
         ObjectDelete(0, g_last_buy_top);
         ObjectDelete(0, g_last_buy_bot);
         ObjectDelete(0, g_last_buy_arrow);
        }
      g_last_buy_end = tEnd;
      g_last_buy_top = nameTop;
      g_last_buy_bot = nameBottom;
      g_last_buy_arrow = nameArrow;
     }
   else
     {
      if(g_last_sell_end != 0 && tStart <= g_last_sell_end)
        {
         ObjectDelete(0, g_last_sell_top);
         ObjectDelete(0, g_last_sell_bot);
         ObjectDelete(0, g_last_sell_arrow);
        }
      g_last_sell_end = tEnd;
      g_last_sell_top = nameTop;
      g_last_sell_bot = nameBottom;
      g_last_sell_arrow = nameArrow;
     }

   if(ObjectFind(0, nameTop) < 0)
     {
      ObjectCreate(0, nameTop, OBJ_TREND, 0, tStart, topPrice, tEnd, topPrice);
      ObjectSetInteger(0, nameTop, OBJPROP_COLOR, lineColor);
      ObjectSetInteger(0, nameTop, OBJPROP_WIDTH, RangeLineWidth);
      ObjectSetInteger(0, nameTop, OBJPROP_STYLE, RangeLineStyle);
      ObjectSetInteger(0, nameTop, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, nameTop, OBJPROP_BACK, true);
     }
   if(ObjectFind(0, nameBottom) < 0)
     {
      ObjectCreate(0, nameBottom, OBJ_TREND, 0, tStart, bottomPrice, tEnd, bottomPrice);
      ObjectSetInteger(0, nameBottom, OBJPROP_COLOR, lineColor);
      ObjectSetInteger(0, nameBottom, OBJPROP_WIDTH, RangeLineWidth);
      ObjectSetInteger(0, nameBottom, OBJPROP_STYLE, RangeLineStyle);
      ObjectSetInteger(0, nameBottom, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, nameBottom, OBJPROP_BACK, true);
     }
   if(ShowSignalArrows && ObjectFind(0, nameArrow) < 0)
     {
      double arrowPrice = isBuy ? bottomPrice : topPrice;
      ObjectCreate(0, nameArrow, OBJ_ARROW, 0, tStart, arrowPrice);
      ObjectSetInteger(0, nameArrow, OBJPROP_ARROWCODE, isBuy ? 233 : 234);
      ObjectSetInteger(0, nameArrow, OBJPROP_COLOR, lineColor);
      ObjectSetInteger(0, nameArrow, OBJPROP_WIDTH, 2);
     }
  }

void RunBreakoutSignals(int rates_total, const datetime &time[], const double &open[],
                        const double &high[], const double &low[], const double &close[])
  {
   if(!EnableEngulfing && !EnableBreakout) return;
   if(rates_total < 3) return;

   int lastClosed = rates_total - 2; 
   if(lastClosed < 1) return;
   if(g_last_signal_bar_time != 0 && time[lastClosed] == g_last_signal_bar_time) return;

   int scanStart = (g_last_signal_bar_time != 0) ? MathMax(1, lastClosed - 5) : MathMax(1, lastClosed - 500);

   for(int i = scanStart; i <= lastClosed; i++)
     {
      double maVal = 0.0, maValPrev = 0.0;
      switch(SignalSourceMA)
        {
         case SIG_MA1: maVal = MA1Buffer[i]; maValPrev = MA1Buffer[i-1]; break;
         case SIG_MA2: maVal = MA2Buffer[i]; maValPrev = MA2Buffer[i-1]; break;
         case SIG_MA3: maVal = MA3Buffer[i]; maValPrev = MA3Buffer[i-1]; break;
        }

      if(maVal == 0.0 || maValPrev == 0.0) continue; 

      bool brokeAbove = (close[i-1] <= maValPrev) && (close[i] > maVal);
      bool brokeBelow = (close[i-1] >= maValPrev) && (close[i] < maVal);

      if(brokeAbove)
        {
         if(EnableEngulfing && IsBullishEngulfing(open, close, i)) DrawSignalRange(i, time, high, low, true, "ENG");
         else if(EnableBreakout) DrawSignalRange(i, time, high, low, true, "BRK");
        }
      else if(brokeBelow)
        {
         if(EnableEngulfing && IsBearishEngulfing(open, close, i)) DrawSignalRange(i, time, high, low, false, "ENG");
         else if(EnableBreakout) DrawSignalRange(i, time, high, low, false, "BRK");
        }
     }
   g_last_signal_bar_time = time[lastClosed];
  }

//+------------------------------------------------------------------+
//| Setup 2: MA Crossover Scanner                                    |
//+------------------------------------------------------------------+
void RunCrossoverSignals(int rates_total, const datetime &time[], const double &high[], const double &low[])
  {
   if(!EnableCrossover || rates_total < 3) return;

   int lastClosed = rates_total - 2; 
   if(lastClosed < 1) return;
   if(g_last_cross_time != 0 && time[lastClosed] == g_last_cross_time) return;

   int scanStart = (g_last_cross_time != 0) ? MathMax(1, lastClosed - 5) : MathMax(1, lastClosed - 500);

   for(int i = scanStart; i <= lastClosed; i++)
     {
      double mFast = 0, mFastPrev = 0;
      double mSlow = 0, mSlowPrev = 0;

      switch(CrossoverMode)
        {
         case CROSS_MA1_MA2: mFast = MA1Buffer[i]; mFastPrev = MA1Buffer[i-1]; mSlow = MA2Buffer[i]; mSlowPrev = MA2Buffer[i-1]; break;
         case CROSS_MA2_MA1: mFast = MA2Buffer[i]; mFastPrev = MA2Buffer[i-1]; mSlow = MA1Buffer[i]; mSlowPrev = MA1Buffer[i-1]; break;
         case CROSS_MA1_MA3: mFast = MA1Buffer[i]; mFastPrev = MA1Buffer[i-1]; mSlow = MA3Buffer[i]; mSlowPrev = MA3Buffer[i-1]; break;
         case CROSS_MA3_MA1: mFast = MA3Buffer[i]; mFastPrev = MA3Buffer[i-1]; mSlow = MA1Buffer[i]; mSlowPrev = MA1Buffer[i-1]; break;
         case CROSS_MA2_MA3: mFast = MA2Buffer[i]; mFastPrev = MA2Buffer[i-1]; mSlow = MA3Buffer[i]; mSlowPrev = MA3Buffer[i-1]; break;
         case CROSS_MA3_MA2: mFast = MA3Buffer[i]; mFastPrev = MA3Buffer[i-1]; mSlow = MA2Buffer[i]; mSlowPrev = MA2Buffer[i-1]; break;
        }

      if(mFast == 0.0 || mSlow == 0.0 || mFastPrev == 0.0 || mSlowPrev == 0.0) continue;

      bool crossUp = (mFastPrev <= mSlowPrev) && (mFast > mSlow); 
      bool crossDn = (mFastPrev >= mSlowPrev) && (mFast < mSlow); 

      if(crossUp || crossDn)
        {
         string tag  = crossUp ? "BUY_" : "SELL_";
         string name = OBJ_PREFIX_CROSS + tag + IntegerToString((long)time[i]);
         
         if(ObjectFind(0, name) < 0)
           {
            ObjectCreate(0, name, OBJ_ARROW, 0, time[i], crossUp ? low[i] : high[i]);
            ObjectSetInteger(0, name, OBJPROP_ARROWCODE, crossUp ? 233 : 234);
            ObjectSetInteger(0, name, OBJPROP_COLOR, crossUp ? CrossBuyColor : CrossSellColor);
            ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, name, OBJPROP_ANCHOR, crossUp ? ANCHOR_TOP : ANCHOR_BOTTOM);
            
            if(EnableAlerts && i == lastClosed) 
               Alert(_Symbol, " ", EnumToString(_Period), ": MA Crossover ", crossUp ? "BUY" : "SELL");
           }
        }
     }
   g_last_cross_time = time[lastClosed];
  }

//+------------------------------------------------------------------+
//| OnCalculate                                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
  {
   if(rates_total < MA1_Period) return 0;

   // 1. Process MA1 (Original HMA)
   if(!CalcHMA(rates_total, prev_calculated, MA1_Period, hMA1Half, hMA1Full, arrMA1Half, arrMA1Full, MA1Buffer))
      return (prev_calculated > 0 ? prev_calculated : 0);

   // 2. Process MA2
   if(!ProcessCustomMA(MA2_Type, rates_total, prev_calculated, MA2_Period, hMA2, hMA2Half, hMA2Full, hMA2Price, arrMA2Half, arrMA2Full, ALMA_Offset, ALMA_Sigma, MA2Buffer))
      return (prev_calculated > 0 ? prev_calculated : 0);

   // 3. Process MA3
   if(!ProcessCustomMA(MA3_Type, rates_total, prev_calculated, MA3_Period, hMA3, hMA3Half, hMA3Full, hMA3Price, arrMA3Half, arrMA3Full, ALMA_Offset, ALMA_Sigma, MA3Buffer))
      return (prev_calculated > 0 ? prev_calculated : 0);

   // Evaluate Signals (Only triggers on fully closed bars)
   RunBreakoutSignals(rates_total, time, open, high, low, close);
   RunCrossoverSignals(rates_total, time, high, low);

   return(rates_total);
  }
//+------------------------------------------------------------------+