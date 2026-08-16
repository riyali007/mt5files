//+------------------------------------------------------------------+
//|                                           CandleSignalsMTF_Fix.mq5 |
//| PineScript Logic Signals + True Non-Repainting Multi-Timeframe   |
//+------------------------------------------------------------------+
#property copyright "Riy Ali"
#property version   "2.10"
#property indicator_chart_window
#property indicator_plots   2
#property indicator_buffers 2

//--- Buy Signal
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrAqua
#property indicator_width1  3
#property indicator_label1  "Buy Signal"

//--- Sell Signal
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  3
#property indicator_label2  "Sell Signal"

//--- Inputs
input group "Multi-Timeframe Settings"
input ENUM_TIMEFRAMES InpHTF             = PERIOD_H4;     // Higher Timeframe (HTF) for Logic

input group "Signal Settings (PineScript Logic)"
input int    InpRsiPeriod                = 14;    // RSI Period
input int    InpMinBody1                 = 10;    // getBody(0) > 1 (in MT5 points)
input int    InpMinBody2                 = 20;    // getBody(0) > 2 (in MT5 points)

input group "Pattern Strict Settings"
input int    InpDojiMaxBodyPoints        = 20;    // Max Doji body size (points)
input double InpDojiCenterTolerancePct   = 10.0;  // Doji center tolerance (%)
input bool   InpEngulfCoversWicks        = false; // Engulfing body must cover prev HIGH/LOW
input int    InpArrowOffsetPoints        = 50;    // Distance from high/low for arrows

//--- Indicator buffers & Global HTF Arrays
double BuySignalBuffer[];
double SellSignalBuffer[];

double htf_open[], htf_high[], htf_low[], htf_close[], htf_rsi[];

int             rsiHandle;
ENUM_TIMEFRAMES activeHTF;

//+------------------------------------------------------------------+
//| Initialize indicator                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BuySignalBuffer,  INDICATOR_DATA);
   SetIndexBuffer(1, SellSignalBuffer, INDICATOR_DATA);

   ArraySetAsSeries(BuySignalBuffer,  true);
   ArraySetAsSeries(SellSignalBuffer, true);

   PlotIndexSetInteger(0, PLOT_ARROW, 225); // Thick Up Arrow
   PlotIndexSetInteger(1, PLOT_ARROW, 226); // Thick Down Arrow
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   activeHTF = InpHTF;
   if(PeriodSeconds(activeHTF) < PeriodSeconds(_Period))
      activeHTF = _Period;

   rsiHandle = iRSI(_Symbol, activeHTF, InpRsiPeriod, PRICE_CLOSE);
   if(rsiHandle == INVALID_HANDLE)
   {
      Print("Error creating RSI Handle");
      return(INIT_FAILED);
   }

   IndicatorSetString(INDICATOR_SHORTNAME, "Signals MTF (" + EnumToString(activeHTF) + ")");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinitialize indicator                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(rsiHandle);
}

//+------------------------------------------------------------------+
//| Pattern Logic Helpers (Using Cached HTF Arrays)                  |
//+------------------------------------------------------------------+
double GetBody(int s)      { return MathAbs(htf_close[s] - htf_open[s]); }
bool   IsBull(int s)       { return htf_close[s] > htf_open[s]; }
bool   IsBear(int s)       { return htf_close[s] < htf_open[s]; }
double GetUpperWick(int s) { return htf_high[s] - MathMax(htf_open[s], htf_close[s]); }
double GetLowerWick(int s) { return MathMin(htf_open[s], htf_close[s]) - htf_low[s]; }

bool IsDoji(int s)
{
   double body = GetBody(s);
   if(body > InpDojiMaxBodyPoints * _Point) return false;
   
   double range = htf_high[s] - htf_low[s];
   if(range <= 0) return true;
   
   double center = MathMin(htf_open[s], htf_close[s]) + (body / 2.0);
   double mid    = htf_low[s] + (range / 2.0);
   
   return MathAbs(center - mid) <= (range * (InpDojiCenterTolerancePct / 100.0));
}

bool IsBullEngulfing(int s)
{
   if(!IsBull(s) || !IsBear(s+1)) return false;
   double pHigh = InpEngulfCoversWicks ? htf_high[s+1] : MathMax(htf_open[s+1], htf_close[s+1]);
   double pLow  = InpEngulfCoversWicks ? htf_low[s+1]  : MathMin(htf_open[s+1], htf_close[s+1]);
   return (htf_close[s] >= pHigh && htf_open[s] <= pLow);
}

bool IsBearEngulfing(int s)
{
   if(!IsBear(s) || !IsBull(s+1)) return false;
   double pHigh = InpEngulfCoversWicks ? htf_high[s+1] : MathMax(htf_open[s+1], htf_close[s+1]);
   double pLow  = InpEngulfCoversWicks ? htf_low[s+1]  : MathMin(htf_open[s+1], htf_close[s+1]);
   return (htf_open[s] >= pHigh && htf_close[s] <= pLow);
}

//+------------------------------------------------------------------+
//| Main calculation                                                 |
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
   if(rates_total < 5) return(0);

   // 1. Validate and download all HTF data at once
   int htf_bars = iBars(_Symbol, activeHTF);
   if(htf_bars < 10) return(0); // Wait for HTF data to generate

   if(CopyOpen(_Symbol, activeHTF, 0, htf_bars, htf_open) <= 0) return(0);
   if(CopyHigh(_Symbol, activeHTF, 0, htf_bars, htf_high) <= 0) return(0);
   if(CopyLow(_Symbol, activeHTF, 0, htf_bars, htf_low)  <= 0) return(0);
   if(CopyClose(_Symbol, activeHTF, 0, htf_bars, htf_close) <= 0) return(0);
   if(CopyBuffer(rsiHandle, 0, 0, htf_bars, htf_rsi) <= 0) return(0);

   ArraySetAsSeries(htf_open, true);
   ArraySetAsSeries(htf_high, true);
   ArraySetAsSeries(htf_low, true);
   ArraySetAsSeries(htf_close, true);
   ArraySetAsSeries(htf_rsi, true);
   
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);

   // 2. Setup Calculation Limits
   int limit;
   if(prev_calculated == 0)
   {
      ArrayInitialize(BuySignalBuffer, EMPTY_VALUE);
      ArrayInitialize(SellSignalBuffer, EMPTY_VALUE);
      limit = rates_total - 2; 
   }
   else
   {
      // Recalculate enough LTF bars to cover the latest HTF candle update
      int ltf_in_htf = (int)(PeriodSeconds(activeHTF) / PeriodSeconds(_Period));
      limit = MathMin(rates_total - 2, ltf_in_htf + 2);
   }

   const double offset = InpArrowOffsetPoints * _Point;

   // 3. Process the Lower Timeframe (LTF) bars
   for(int i = limit; i >= 0; i--)
   {
      BuySignalBuffer[i]  = EMPTY_VALUE;
      SellSignalBuffer[i] = EMPTY_VALUE;
      
      // Find which HTF candle this LTF candle belongs to
      int htf_i      = iBarShift(_Symbol, activeHTF, time[i], false);
      int htf_i_prev = iBarShift(_Symbol, activeHTF, time[i+1], false);

      if(htf_i < 0 || htf_i_prev < 0) continue;

      // We only execute on the VERY FIRST LTF bar of a NEW HTF bar
      if(htf_i != htf_i_prev)
      {
         // The recently closed HTF candle is htf_i_prev.
         // Let's map it to PineScript's [0], [1], [2] lookback structure.
         int h0 = htf_i_prev;      // Closed candle (PineScript index 0)
         int h1 = htf_i_prev + 1;  // Closed candle - 1
         int h2 = htf_i_prev + 2;  // Closed candle - 2
         int h3 = htf_i_prev + 3;  // Closed candle - 3
         
         if(h3 >= htf_bars) continue; // Not enough HTF history

         double rsi_val  = htf_rsi[h0];
         double rsi_val1 = htf_rsi[h1];

         // ==========================================
         // SELL CONDITIONS
         // ==========================================
         bool sellC1 = IsBull(h2) && IsBull(h1) && IsBear(h0) && !IsDoji(h2) && !IsDoji(h1) && !IsDoji(h0);
         
         bool sellC2 = IsBull(h3) && IsBull(h2) && IsBull(h1) && IsBear(h0) && !IsDoji(h1) && !IsDoji(h0) && 
                       htf_close[h0] >= htf_low[h1] && GetBody(h0) > (InpMinBody1 * _Point) && GetUpperWick(h0) > 0;
                       
         bool sellC3 = IsBearEngulfing(h0) && GetBody(h0) > (InpMinBody2 * _Point) && 
                       (rsi_val >= 60.0 || rsi_val1 >= 65.0) && GetUpperWick(h0) > 0;
                       
         bool sellC4 = IsBull(h2) && IsBull(h1) && IsBear(h0) && GetBody(h0) > (InpMinBody2 * _Point) && 
                       (rsi_val >= 70.0 || rsi_val1 >= 70.0) && GetUpperWick(h0) > 0;

         if(sellC1 || sellC2 || sellC3 || sellC4)
         {
            SellSignalBuffer[i] = high[i] + offset;
         }

         // ==========================================
         // BUY CONDITIONS
         // ==========================================
         bool buyC1 = IsBear(h2) && IsBear(h1) && IsBull(h0) && !IsDoji(h2) && !IsDoji(h1) && !IsDoji(h0);
         
         bool buyC2 = IsBear(h3) && IsBear(h2) && IsBear(h1) && IsBull(h0) && !IsDoji(h1) && !IsDoji(h0) && 
                      htf_close[h0] <= htf_high[h1] && GetBody(h0) > (InpMinBody1 * _Point) && GetLowerWick(h0) > 0;
                      
         bool buyC3 = IsBullEngulfing(h0) && GetBody(h0) > (InpMinBody2 * _Point) && 
                      (rsi_val <= 40.0 || rsi_val1 <= 35.0) && GetLowerWick(h0) > 0;
                      
         bool buyC4 = IsBear(h2) && IsBear(h1) && IsBull(h0) && GetBody(h0) > (InpMinBody2 * _Point) && 
                      (rsi_val <= 30.0 || rsi_val1 <= 25.0) && GetLowerWick(h0) > 0;

         if(buyC1 || buyC2 || buyC3 || buyC4)
         {
            BuySignalBuffer[i] = low[i] - offset;
         }
      }
   }

   return(rates_total);
}
//+------------------------------------------------------------------+