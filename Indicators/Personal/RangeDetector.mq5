#property copyright "Professional MT5 Developer"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

//--- Plot Settings (Arrows)
#property indicator_label1  "Bullish Signal"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrYellow // Yellow to match your image
#property indicator_width1  3

#property indicator_label2  "Bearish Signal"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrYellow // Yellow to match your image
#property indicator_width2  3

//--- Inputs
input group "Range (Green Box) Settings"
input int      InpMinRangeLen       = 3;              // Min candles to create a box
input color    InpBoxColor          = clrLime;        // Bright Green Box
input int      InpBoxWidth          = 2;              // Box line width
input bool     InpFillBox           = false;          // Hollow box (like image) or filled

input group "Signal (Yellow Arrow) Settings"
input int      InpTrendLookback     = 3;              // Trend candles before Reversal
input bool     InpAlerts            = true;
input bool     InpSound             = true;
input string   InpSoundFile         = "alert.wav";

//--- Buffers
double         BuyBuffer[];
double         SellBuffer[];

//--- Global
int            lastAlertBar = 0;

int OnInit()
{
   SetIndexBuffer(0, BuyBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, SellBuffer, INDICATOR_DATA);
   
   // Arrow Codes
   PlotIndexSetInteger(0, PLOT_ARROW, 241); // Up Arrow (Standard MT5 Arrow)
   PlotIndexSetInteger(1, PLOT_ARROW, 242); // Down Arrow
   
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "ImgRange_");
}

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
   if(rates_total < 10) return(0);
   
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(BuyBuffer, true);
   ArraySetAsSeries(SellBuffer, true);
   
   if(prev_calculated == 0) ObjectsDeleteAll(0, "ImgRange_");
   
   int limit = rates_total - prev_calculated;
   if(prev_calculated > 0) limit += 1;
   else limit = rates_total - 20; // Look back enough for testing
   
   // 1. MAIN SCANNING LOOP
   // We iterate backwards. 'i' is our potential "Base" or "Trend Start".
   for(int i = limit; i >= 1; i--)
   {
      BuyBuffer[i-1] = EMPTY_VALUE;
      SellBuffer[i-1] = EMPTY_VALUE;
      
      bool signalFound = false;
      
      // --- LOGIC A: RANGE DETECTION (The Green Boxes) ---
      // 1. Treat 'i' as the Base Candle.
      double boxHigh = high[i];
      double boxLow  = low[i];
      int candlesInside = 0;
      int breakIdx = -1;
      
      // 2. Look forward to see how long price stays inside this Base
      for(int k=1; k<50; k++) // Safety limit
      {
         int next = i - k;
         if(next < 0) break;
         
         double cClose = close[next];
         double cHigh  = high[next];
         double cLow   = low[next];
         
         // STRICT CONTAINMENT: 
         // The image shows candles staying roughly inside the base range.
         // We allow wicks to poke slightly, but the BODY (Close) must be contained.
         // Or strictly: Close must be <= BoxHigh and >= BoxLow.
         
         if(cClose <= boxHigh && cClose >= boxLow)
         {
            candlesInside++;
            // Optional: You can slightly expand the box if you want "Dynamic Range"
            // boxHigh = MathMax(boxHigh, cHigh); 
            // boxLow  = MathMin(boxLow, cLow);
         }
         else
         {
            // Breakout detected!
            breakIdx = next;
            break;
         }
      }
      
      // 3. DRAW BOX if valid
      if(candlesInside >= InpMinRangeLen)
      {
         int endIdx = i - candlesInside; // The last candle INSIDE
         string boxName = "ImgRange_" + IntegerToString(time[i]);
         
         // Draw Green Box around the consolidation area
         DrawBox(boxName, time[i], time[endIdx], boxHigh, boxLow);
         
         // 4. CHECK BREAKOUT (Right Arrow in Image)
         if(breakIdx != -1)
         {
            double bClose = close[breakIdx];
            // Buy Breakout
            if(bClose > boxHigh) {
               BuyBuffer[breakIdx] = low[breakIdx] - 10 * _Point;
               signalFound = true; // Mark handled
               // Advance loop to avoid re-detecting inside this range
               i = breakIdx + 1; 
            }
            // Sell Breakout
            else if(bClose < boxLow) {
               SellBuffer[breakIdx] = high[breakIdx] + 10 * _Point;
               signalFound = true;
               i = breakIdx + 1;
            }
         }
      }
      
      // --- LOGIC B: TREND REVERSAL (Left Arrow in Image) ---
      // Only check if we are NOT in a box breakout
      if(!signalFound)
      {
         // We need a trend before the reversal (e.g. 3 red candles)
         bool isDowntrend = true;
         bool isUptrend   = true;
         
         for(int t=0; t<InpTrendLookback; t++) {
            if(i+t >= rates_total) { isDowntrend=false; isUptrend=false; break; }
            if(close[i+t] > open[i+t]) isDowntrend = false; // Found a green, not downtrend
            if(close[i+t] < open[i+t]) isUptrend = false;   // Found a red, not uptrend
         }
         
         // Check the Signal Candle (i-1)
         double sigClose = close[i-1];
         double sigOpen  = open[i-1];
         double prevHigh = high[i];
         double prevLow  = low[i];
         
         // Bullish Engulfing (Left Arrow Scenario)
         if(isDowntrend)
         {
            // Current is Green + Closes ABOVE previous High (Strong Engulfing)
            if(sigClose > sigOpen && sigClose > prevHigh) {
               BuyBuffer[i-1] = low[i-1] - 10 * _Point;
               if(i-1 == 0 && lastAlertBar != i-1) { TriggerAlert("Reversal Buy!"); lastAlertBar = i-1; }
            }
         }
         
         // Bearish Engulfing
         if(isUptrend)
         {
            // Current is Red + Closes BELOW previous Low
            if(sigClose < sigOpen && sigClose < prevLow) {
               SellBuffer[i-1] = high[i-1] + 10 * _Point;
               if(i-1 == 0 && lastAlertBar != i-1) { TriggerAlert("Reversal Sell!"); lastAlertBar = i-1; }
            }
         }
      }
   }
   
   return(rates_total);
}

void DrawBox(string name, datetime t1, datetime t2, double p1, double p2)
{
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   else {
      ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1); ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2); ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
   }
   ObjectSetInteger(0, name, OBJPROP_COLOR, InpBoxColor);
   ObjectSetInteger(0, name, OBJPROP_FILL, InpFillBox);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, InpBoxWidth);
}

void TriggerAlert(string msg)
{
   if(!InpAlerts && !InpSound) return;
   if(InpAlerts) Alert(msg);
   if(InpSound) PlaySound(InpSoundFile);
}