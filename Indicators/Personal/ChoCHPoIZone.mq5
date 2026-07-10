//+------------------------------------------------------------------+
//|                                              CHoCH_with_Zones.mq5|
//|                            Production Ready Indicator Code V1.3  |
//|                                      Copyright 2026, Perplexity AI|
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//--- TF1 Settings
input bool            InpTF1Enable         = true;          // [TF1] Enable
input ENUM_TIMEFRAMES InpTF1               = PERIOD_H1;     // [TF1] Timeframe
input int             InpTF1PivotPeriod    = 5;             // [TF1] Pivot Period
input color           InpTF1BullColor      = clrLime;       // [TF1] Bullish CHoCH Color
input color           InpTF1BearColor      = clrRed;        // [TF1] Bearish CHoCH Color
input ENUM_LINE_STYLE InpTF1LineStyle      = STYLE_SOLID;   // [TF1] CHoCH Line Style
input int             InpTF1LineWidth      = 2;             // [TF1] CHoCH Line Width

//--- TF2 Settings
input bool            InpTF2Enable         = true;          // [TF2] Enable
input ENUM_TIMEFRAMES InpTF2               = PERIOD_H4;     // [TF2] Timeframe
input int             InpTF2PivotPeriod    = 5;             // [TF2] Pivot Period
input color           InpTF2BullColor      = clrTeal;       // [TF2] Bullish CHoCH Color
input color           InpTF2BearColor      = clrMaroon;     // [TF2] Bearish CHoCH Color
input ENUM_LINE_STYLE InpTF2LineStyle      = STYLE_DASH;    // [TF2] CHoCH Line Style
input int             InpTF2LineWidth      = 2;             // [TF2] CHoCH Line Width

//--- Global Zone Settings
input int             InpMaxBars           = 3000;          // Max Historical Bars to Process
input color           InpSellZoneColor     = clrLightCoral; // Sell Zone Color
input color           InpBuyZoneColor      = clrLightGreen; // Buy Zone Color
input color           InpMidLineColor      = clrBlack;      // Midline Color
input color           InpMitigatedColor    = clrDarkGray;   // Mitigated Zone Color
input double          InpSellZoneOffsetPct = 0.0;           // Sell Zone Vertical Offset (%)
input double          InpBuyZoneOffsetPct  = 0.0;           // Buy Zone Vertical Offset (%)

//--- Alert Settings
input bool            InpEnableAlerts        = true;          // Enable Alerts (Popup & Sound)
input string          InpSoundBullCHoCH      = "alert.wav";   // Sound: Bullish CHoCH
input string          InpSoundBearCHoCH      = "alert.wav";   // Sound: Bearish CHoCH
input string          InpSoundSellZoneTop    = "alert.wav";   // Sound: Sell Zone Top (Level 1)
input string          InpSoundSellZoneMid    = "alert.wav";   // Sound: Sell Zone Mid (Level 2)
input string          InpSoundSellZoneBottom = "alert.wav";   // Sound: Sell Zone Bottom (Level 3)
input string          InpSoundBuyZoneTop     = "alert.wav";   // Sound: Buy Zone Top (Level 3)
input string          InpSoundBuyZoneMid     = "alert.wav";   // Sound: Buy Zone Mid (Level 2)
input string          InpSoundBuyZoneBottom  = "alert.wav";   // Sound: Buy Zone Bottom (Level 1)

//--- Fast Tracking Array for Extending Zones & Midlines
struct ActiveZone {
   string           name;
   string           mid_name; 
   int              type;     // 1 for Buy Zone, -1 for Sell Zone
   double           high;
   double           low;
   double           mid;
   bool             high_alerted;
   bool             mid_alerted;
   bool             low_alerted;
   ENUM_TIMEFRAMES  tf;       // Identifies which TF owns this zone
};
ActiveZone active_zones[];

//--- State Tracking Per Timeframe
struct TFState {
   bool            enable;
   ENUM_TIMEFRAMES tf;
   int             pivot;
   color           bull_clr;
   color           bear_clr;
   ENUM_LINE_STYLE style;
   int             width;
   
   double          last_sh;
   double          last_sl;
   datetime        last_sh_time;
   datetime        last_sl_time;
   int             last_trend;
   datetime        last_choch_alert_time;
   datetime        last_processed_time;
};
TFState states[2];

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
   IndicatorSetString(INDICATOR_SHORTNAME, "CHoCH MTF Zones V1.3");
   
   // Clean up any stray objects
   ObjectsDeleteAll(0, "CHoCH_"); 
   ArrayResize(active_zones, 0);
   
   // Map Inputs to Timeframe States
   states[0].enable   = InpTF1Enable;
   states[0].tf       = InpTF1;
   states[0].pivot    = InpTF1PivotPeriod;
   states[0].bull_clr = InpTF1BullColor;
   states[0].bear_clr = InpTF1BearColor;
   states[0].style    = InpTF1LineStyle;
   states[0].width    = InpTF1LineWidth;
   
   states[1].enable   = InpTF2Enable;
   states[1].tf       = InpTF2;
   states[1].pivot    = InpTF2PivotPeriod;
   states[1].bull_clr = InpTF2BullColor;
   states[1].bear_clr = InpTF2BearColor;
   states[1].style    = InpTF2LineStyle;
   states[1].width    = InpTF2LineWidth;
   
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, "CHoCH_");
  }

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
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
   if(rates_total < 10) return(0);

   // 1. Reset cleanly if timeframe changes or first load
   if(prev_calculated == 0)
     {
      ObjectsDeleteAll(0, "CHoCH_");
      ArrayResize(active_zones, 0);
      
      for(int t = 0; t < 2; t++)
        {
         states[t].last_trend = 0;
         states[t].last_sh = 0.0;
         states[t].last_sl = 0.0;
         states[t].last_sh_time = 0;
         states[t].last_sl_time = 0;
         states[t].last_choch_alert_time = 0;
         states[t].last_processed_time = 0;
        }
     }

   // 2. Loop through configured Higher Timeframes Independently
   for(int t = 0; t < 2; t++)
     {
      if(!states[t].enable) continue; // Skip disabled timeframes
      
      ENUM_TIMEFRAMES tf = states[t].tf;
      if(tf == PERIOD_CURRENT) tf = Period(); 
      
      MqlRates rates[];
      int copied = CopyRates(_Symbol, tf, 0, InpMaxBars, rates);
      int p_period = states[t].pivot;
      
      if(copied < p_period * 2 + 1) continue;

      int limit = p_period * 2;
      
      // Fast forward calculation skip
      if(states[t].last_processed_time > 0)
        {
         for(int i = copied - 1; i >= 0; i--)
           {
            if(rates[i].time == states[t].last_processed_time) { limit = i; break; }
           }
        }

      // Process only fully closed bars for the specific timeframe
      for(int i = limit; i < copied - 1; i++)
        {
         int check_idx = i - p_period;
         bool isSwingHigh = true;
         bool isSwingLow = true;
         
         for(int j = 1; j <= p_period; j++)
           {
            if(rates[check_idx].high <= rates[check_idx - j].high || rates[check_idx].high <= rates[check_idx + j].high) isSwingHigh = false;
            if(rates[check_idx].low >= rates[check_idx - j].low || rates[check_idx].low >= rates[check_idx + j].low) isSwingLow = false;
           }
           
         if(isSwingHigh) { states[t].last_sh = rates[check_idx].high; states[t].last_sh_time = rates[check_idx].time; }
         if(isSwingLow)  { states[t].last_sl = rates[check_idx].low;  states[t].last_sl_time = rates[check_idx].time; }

         //--- A. Check for Bullish CHoCH
         if(states[t].last_trend <= 0 && states[t].last_sh > 0 && rates[i].close > states[t].last_sh)
           {
            states[t].last_trend = 1; 
            string line_name = "CHoCH_" + EnumToString(tf) + "_BullLine_" + IntegerToString((int)rates[i].time);
            
            DrawCHoCHLine(line_name, states[t].last_sh_time, states[t].last_sh, rates[i].time, 
                          states[t].bull_clr, states[t].style, states[t].width);
            
            if(InpEnableAlerts && i == copied - 2 && rates[i].time > states[t].last_choch_alert_time)
              {
               Alert(Symbol() + " " + EnumToString(tf) + ": Confirmed Bullish CHoCH!");
               PlaySound(InpSoundBullCHoCH);
               states[t].last_choch_alert_time = rates[i].time;
              }
            
            int start_idx = i;
            for(int k = i; k >= 0; k--) { if(rates[k].time <= states[t].last_sh_time) { start_idx = k; break; } }
              
            int lowest_idx = start_idx; double min_low = rates[start_idx].low;
            for(int k = start_idx; k <= i; k++) { if(rates[k].low < min_low) { min_low = rates[k].low; lowest_idx = k; } }
            
            double z_high = rates[lowest_idx].high;
            double z_low  = rates[lowest_idx].low;
            double offset_val = (z_high - z_low) * (InpSellZoneOffsetPct / 100.0);
            z_high += offset_val; z_low += offset_val;
              
            string box_name = "CHoCH_" + EnumToString(tf) + "_SellZone_" + IntegerToString((int)rates[i].time);
            DrawZone(box_name, rates[lowest_idx].time, z_high, rates[i].time, z_low, InpSellZoneColor, "Sell Zone", -1, tf);
            
            states[t].last_sh = 0.0; 
           }

         //--- B. Check for Bearish CHoCH
         if(states[t].last_trend >= 0 && states[t].last_sl > 0 && rates[i].close < states[t].last_sl)
           {
            states[t].last_trend = -1; 
            string line_name = "CHoCH_" + EnumToString(tf) + "_BearLine_" + IntegerToString((int)rates[i].time);
            
            DrawCHoCHLine(line_name, states[t].last_sl_time, states[t].last_sl, rates[i].time, 
                          states[t].bear_clr, states[t].style, states[t].width);
            
            if(InpEnableAlerts && i == copied - 2 && rates[i].time > states[t].last_choch_alert_time)
              {
               Alert(Symbol() + " " + EnumToString(tf) + ": Confirmed Bearish CHoCH!");
               PlaySound(InpSoundBearCHoCH);
               states[t].last_choch_alert_time = rates[i].time;
              }
              
            int start_idx = i;
            for(int k = i; k >= 0; k--) { if(rates[k].time <= states[t].last_sl_time) { start_idx = k; break; } }
              
            int highest_idx = start_idx; double max_high = rates[start_idx].high;
            for(int k = start_idx; k <= i; k++) { if(rates[k].high > max_high) { max_high = rates[k].high; highest_idx = k; } }
              
            double z_high = rates[highest_idx].high;
            double z_low  = rates[highest_idx].low;
            double offset_val = (z_high - z_low) * (InpBuyZoneOffsetPct / 100.0);
            z_high += offset_val; z_low += offset_val;
              
            string box_name = "CHoCH_" + EnumToString(tf) + "_BuyZone_" + IntegerToString((int)rates[i].time);
            DrawZone(box_name, rates[highest_idx].time, z_high, rates[i].time, z_low, InpBuyZoneColor, "Buy Zone", 1, tf);
            
            states[t].last_sl = 0.0; 
           }

         //--- C. Historic Mitigation Check (Checks closures ONLY on its specific timeframe)
         for(int z = ArraySize(active_zones) - 1; z >= 0; z--)
           {
            if(active_zones[z].tf != tf) continue; 

            bool is_mitigated = false;
            if(active_zones[z].type == 1 && rates[i].close > active_zones[z].high) is_mitigated = true;        
            if(active_zones[z].type == -1 && rates[i].close < active_zones[z].low) is_mitigated = true;      

            if(is_mitigated)
              {
               // Lock the objects specifically at the exact HTF candle that mitigated them
               ObjectSetInteger(0, active_zones[z].name, OBJPROP_TIME, 1, rates[i].time);
               ObjectSetInteger(0, active_zones[z].mid_name, OBJPROP_TIME, 1, rates[i].time);
               
               // Turn gray to indicate broken
               ObjectSetInteger(0, active_zones[z].name, OBJPROP_COLOR, InpMitigatedColor);
               ObjectSetInteger(0, active_zones[z].mid_name, OBJPROP_COLOR, InpMitigatedColor);
               
               ArrayRemove(active_zones, z, 1);
              }
           }
        }
      // Save last processed closed candle
      if(copied > 1) states[t].last_processed_time = rates[copied - 2].time; 
     }
     
   // 3. --- LIVE EXTENSION & TICK ALERTS (Runs once per tick utilizing the current chart timeframe)
   datetime current_live_time = time[rates_total - 1];
   double live_high = high[rates_total - 1];
   double live_low  = low[rates_total - 1];

   for(int z = 0; z < ArraySize(active_zones); z++)
     {
      // Extend dynamically to current chart's live price edge
      ObjectSetInteger(0, active_zones[z].name, OBJPROP_TIME, 1, current_live_time);
      ObjectSetInteger(0, active_zones[z].mid_name, OBJPROP_TIME, 1, current_live_time);

      // Process Tapping Alerts using current live wicks
      if(InpEnableAlerts)
        {
         string tf_str = EnumToString(active_zones[z].tf);

         if(active_zones[z].type == -1) // SELL ZONE
           {
            if(!active_zones[z].high_alerted && live_low <= active_zones[z].high && live_high >= active_zones[z].high)
              {
               Alert(Symbol() + " " + tf_str + ": Price tapped Top Level of Sell Zone");
               PlaySound(InpSoundSellZoneTop);
               active_zones[z].high_alerted = true;
              }
            if(!active_zones[z].mid_alerted && live_low <= active_zones[z].mid && live_high >= active_zones[z].mid)
              {
               Alert(Symbol() + " " + tf_str + ": Price tapped Mid Level of Sell Zone");
               PlaySound(InpSoundSellZoneMid);
               active_zones[z].mid_alerted = true;
              }
            if(!active_zones[z].low_alerted && live_low <= active_zones[z].low && live_high >= active_zones[z].low)
              {
               Alert(Symbol() + " " + tf_str + ": Price tapped Bottom Level of Sell Zone");
               PlaySound(InpSoundSellZoneBottom);
               active_zones[z].low_alerted = true;
              }
           }
         else if(active_zones[z].type == 1) // BUY ZONE
           {
            if(!active_zones[z].high_alerted && live_low <= active_zones[z].high && live_high >= active_zones[z].high)
              {
               Alert(Symbol() + " " + tf_str + ": Price tapped Top Level of Buy Zone");
               PlaySound(InpSoundBuyZoneTop);
               active_zones[z].high_alerted = true;
              }
            if(!active_zones[z].mid_alerted && live_low <= active_zones[z].mid && live_high >= active_zones[z].mid)
              {
               Alert(Symbol() + " " + tf_str + ": Price tapped Mid Level of Buy Zone");
               PlaySound(InpSoundBuyZoneMid);
               active_zones[z].mid_alerted = true;
              }
            if(!active_zones[z].low_alerted && live_low <= active_zones[z].low && live_high >= active_zones[z].low)
              {
               Alert(Symbol() + " " + tf_str + ": Price tapped Bottom Level of Buy Zone");
               PlaySound(InpSoundBuyZoneBottom);
               active_zones[z].low_alerted = true;
              }
           }
        }
     }
     
   return(rates_total);
  }

//+------------------------------------------------------------------+
//| Function to draw the CHoCH line on the chart                     |
//+------------------------------------------------------------------+
void DrawCHoCHLine(string name, datetime time1, double price, datetime time2, color clr, ENUM_LINE_STYLE style, int width)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_TREND, 0, time1, price, time2, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, style);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false); 
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetString(0, name, OBJPROP_TOOLTIP, "CHoCH");
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true); 
     }
  }

//+------------------------------------------------------------------+
//| Function to draw the filled Zone & Midline on the chart          |
//+------------------------------------------------------------------+
void DrawZone(string name, datetime time1, double price1, datetime time2, double price2, color clr, string tooltip, int zone_type, ENUM_TIMEFRAMES tf)
  {
   double max_p = MathMax(price1, price2);
   double min_p = MathMin(price1, price2);
   double mid_p = min_p + ((max_p - min_p) / 2.0);
   string mid_name = "CHoCH_Mid_" + name; 

   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, time1, max_p, time2, min_p);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);    
      ObjectSetInteger(0, name, OBJPROP_FILL, true);    
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true); 
      ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
      
      ObjectCreate(0, mid_name, OBJ_TREND, 0, time1, mid_p, time2, mid_p);
      ObjectSetInteger(0, mid_name, OBJPROP_COLOR, InpMidLineColor);
      ObjectSetInteger(0, mid_name, OBJPROP_STYLE, STYLE_DOT); 
      ObjectSetInteger(0, mid_name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, mid_name, OBJPROP_RAY_RIGHT, false); 
      ObjectSetInteger(0, mid_name, OBJPROP_BACK, false); 
      ObjectSetInteger(0, mid_name, OBJPROP_HIDDEN, true); 
      ObjectSetString(0, mid_name, OBJPROP_TOOLTIP, tooltip + " Midline");

      int s = ArraySize(active_zones);
      ArrayResize(active_zones, s + 1);
      active_zones[s].name     = name;
      active_zones[s].mid_name = mid_name;
      active_zones[s].type     = zone_type;
      active_zones[s].high     = max_p;
      active_zones[s].low      = min_p;
      active_zones[s].mid      = mid_p;
      active_zones[s].tf       = tf;
      
      active_zones[s].high_alerted = false;
      active_zones[s].mid_alerted  = false;
      active_zones[s].low_alerted  = false;
     }
  }
//+------------------------------------------------------------------+