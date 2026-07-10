//+------------------------------------------------------------------+
//|                                            Fib_HTF_Indicator.mq5 |
//|                                                       Riy Tech   |
//+------------------------------------------------------------------+
#property copyright "Riy Tech"
#property version   "1.40"
#property indicator_chart_window
#property indicator_plots 0

//--- Input Groups
input group "=== General Settings ==="
input int InpTimeOffsetHours = 0; // Broker Time Offset (Hours) for Fib projection

input group "=== HTF 1 Settings ==="
input bool InpEnableHTF1 = true;
input ENUM_TIMEFRAMES InpHTF1 = PERIOD_H4;
input color InpFibColor1 = clrDarkGray; // HTF 1 Fib Color
input bool InpDrawZones1 = true;
input bool InpDrawPoI1 = true;

input group "=== HTF 2 Settings ==="
input bool InpEnableHTF2 = true;
input ENUM_TIMEFRAMES InpHTF2 = PERIOD_D1;
input color InpFibColor2 = clrOrange;   // HTF 2 Fib Color
input bool InpDrawZones2 = true;
input bool InpDrawPoI2 = true;

input group "=== HTF 3 Settings ==="
input bool InpEnableHTF3 = false;
input ENUM_TIMEFRAMES InpHTF3 = PERIOD_W1;
input color InpFibColor3 = clrDodgerBlue; // HTF 3 Fib Color
input bool InpDrawZones3 = true;
input bool InpDrawPoI3 = true;

input group "=== Fibonacci Levels (Applies to all) ==="
input double InpFibLevel1 = 0.000;
input double InpFibLevel2 = 0.236;
input double InpFibLevel3 = 0.382;
input double InpFibLevel4 = 0.500;
input double InpFibLevel5 = 0.618;
input double InpFibLevel6 = 0.705;
input double InpFibLevel7 = 0.786;
input double InpFibLevel8 = 0.886;
input double InpFibLevel9 = 1.000;
input double InpFibLevel10 = -0.272;

input group "=== LTF Zone & Label Settings ==="
input bool InpPersistOldOBs = false; // Persist Old Unmitigated OBs
input color Inp_BZoneColor = clrDarkGreen;
input color Inp_SZoneColor = clrDarkRed;
input int InpPoIOffsetPoints = 100;
input color Inp_PoIBullColor = clrLimeGreen;
input color Inp_PoIBearColor = clrOrangeRed;
input bool InpShowZoneTexts = true;
input color InpZoneLabelColor = clrWhite;
input int InpZoneFontSize = 8;

input group "=== LTF CHoCH Settings ==="
input int InpPivotPeriod = 5;
input color InpBullChochColor = clrLime;
input color InpBearChochColor = clrRed;
input ENUM_LINE_STYLE InpChochStyle = STYLE_SOLID;
input int InpChochWidth = 2;

input group "=== FVG Settings ==="
input bool InpEnableFVG = true;
input color InpBullFVGColor = clrTeal;
input color InpBearFVGColor = clrMaroon;

//--- Global Variables & Structs
datetime g_last_htf_time[3] = {0, 0, 0};

double g_last_sh = 0, g_last_sl = 0;
datetime g_last_sh_time = 0, g_last_sl_time = 0;
int g_last_trend = 0;
datetime g_last_processed_time = 0;

struct HTFConfig {
   bool enable;
   ENUM_TIMEFRAMES tf;
   color fib_color;
   string prefix;
   string display_name;
   bool draw_zones;
   bool draw_pois;
};
HTFConfig htf_cfg[3];

struct HTFZone {
   string ob_name;
   string poi_name;
   string lbl_name;
   int type; // 1 = Sell (Top), -1 = Buy (Bottom)
   double ob_high, ob_low;
   double poi_high, poi_low;
   bool ob_mitigated;
   bool poi_mitigated;
   string htf_prefix;
};

HTFZone htf_zones[];

//--- Helper: Convert Timeframe Enum to clean string
string GetTFName(ENUM_TIMEFRAMES tf)
{
   string s = EnumToString(tf);
   StringReplace(s, "PERIOD_", "");
   return s;
}

//--- Delete old objects
void CleanChart(string prefix)
{
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
   {
      string n = ObjectName(0, i, 0, -1);
      if(StringFind(n, prefix) == 0) ObjectDelete(0, n);
   }
}

//--- Draw Fibonacci for a specific HTF
void DrawFibonacci(string prefix, string display_name, datetime t1, double p1, datetime t2, double p2, color clr)
{
   string name = prefix + "FIB_Obj";
   ObjectDelete(0, name); // Refresh it every new HTF
   
   ObjectCreate(0, name, OBJ_FIBO, 0, t1, p1, t2, p2);
   
   // Hide the diagonal trendline by setting its main color to NONE
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrNONE); 
   // Apply the requested color ONLY to the horizontal levels
   ObjectSetInteger(0, name, OBJPROP_LEVELCOLOR, clr); 
   
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false); 
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   
   double levels[10] = {InpFibLevel1, InpFibLevel2, InpFibLevel3, InpFibLevel4, InpFibLevel5, InpFibLevel6, InpFibLevel7, InpFibLevel8, InpFibLevel9, InpFibLevel10};
   ObjectSetInteger(0, name, OBJPROP_LEVELS, 10);
   
   for(int i = 0; i < 10; i++)
   {
      ObjectSetDouble(0, name, OBJPROP_LEVELVALUE, i, levels[i]);
      ObjectSetString(0, name, OBJPROP_LEVELTEXT, i, display_name + " " + DoubleToString(levels[i]*100, 1) + "%");
   }
}

//--- Create and Track a New HTF Zone
void AddActiveHTFZone(string prefix, string display_name, string base_name, datetime t1, double ob_h, double ob_l, double poi_h, double poi_l, int type, bool draw_ob, bool draw_poi)
{
   string ob_name = prefix + base_name + "_OB";
   string poi_name = prefix + base_name + "_PoI";
   string lbl_name = prefix + base_name + "_LBL";
   
   color ob_clr = (type == 1) ? Inp_SZoneColor : Inp_BZoneColor;
   color poi_clr = (type == 1) ? Inp_PoIBearColor : Inp_PoIBullColor;

   // Create OB and Text Label
   if(draw_ob)
   {
      ObjectCreate(0, ob_name, OBJ_RECTANGLE, 0, t1, ob_h, t1, ob_l); 
      ObjectSetInteger(0, ob_name, OBJPROP_COLOR, ob_clr);
      ObjectSetInteger(0, ob_name, OBJPROP_BGCOLOR, ob_clr);
      ObjectSetInteger(0, ob_name, OBJPROP_BACK, true); ObjectSetInteger(0, ob_name, OBJPROP_FILL, true);
      ObjectSetInteger(0, ob_name, OBJPROP_SELECTABLE, false);
      
      if(InpShowZoneTexts)
      {
         string txt = display_name + (type == 1 ? " Sell Zone " : " Buy Zone ") + DoubleToString(ob_h, _Digits) + " - " + DoubleToString(ob_l, _Digits);
         double anchor_price = (type == 1) ? ob_h : ob_l;
         ObjectCreate(0, lbl_name, OBJ_TEXT, 0, t1, anchor_price);
         ObjectSetString(0, lbl_name, OBJPROP_TEXT, txt);
         ObjectSetInteger(0, lbl_name, OBJPROP_COLOR, InpZoneLabelColor);
         ObjectSetInteger(0, lbl_name, OBJPROP_FONTSIZE, InpZoneFontSize);
         ObjectSetInteger(0, lbl_name, OBJPROP_ANCHOR, (type == 1) ? ANCHOR_RIGHT_UPPER : ANCHOR_RIGHT_LOWER);
         ObjectSetInteger(0, lbl_name, OBJPROP_SELECTABLE, false);
      }
   }

   // Create PoI
   if(draw_poi)
   {
      ObjectCreate(0, poi_name, OBJ_RECTANGLE, 0, t1, poi_h, t1, poi_l);
      ObjectSetInteger(0, poi_name, OBJPROP_COLOR, poi_clr);
      ObjectSetInteger(0, poi_name, OBJPROP_BGCOLOR, poi_clr);
      ObjectSetInteger(0, poi_name, OBJPROP_BACK, true); ObjectSetInteger(0, poi_name, OBJPROP_FILL, true);
      ObjectSetInteger(0, poi_name, OBJPROP_SELECTABLE, false);
   }

   // Track it
   int s = ArraySize(htf_zones);
   ArrayResize(htf_zones, s + 1);
   htf_zones[s].ob_name = ob_name;
   htf_zones[s].poi_name = poi_name;
   htf_zones[s].lbl_name = lbl_name;
   htf_zones[s].type = type;
   htf_zones[s].ob_high = ob_h; htf_zones[s].ob_low = ob_l;
   htf_zones[s].poi_high = poi_h; htf_zones[s].poi_low = poi_l;
   htf_zones[s].ob_mitigated = !draw_ob; 
   htf_zones[s].poi_mitigated = !draw_poi;
   htf_zones[s].htf_prefix = prefix;
}

//--- Extend unmitigated zones and text labels to the live price
void ExtendHTFZonesToLive(const datetime &time[], int rates_total)
{
   if(rates_total == 0) return;
   datetime live_t = time[rates_total - 1];
   
   for(int z = 0; z < ArraySize(htf_zones); z++)
   {
      if(!htf_zones[z].ob_mitigated) 
      {
         ObjectSetInteger(0, htf_zones[z].ob_name, OBJPROP_TIME, 1, live_t);
         if(InpShowZoneTexts && ObjectFind(0, htf_zones[z].lbl_name) >= 0)
         {
            ObjectSetInteger(0, htf_zones[z].lbl_name, OBJPROP_TIME, 0, live_t);
         }
      }
      if(!htf_zones[z].poi_mitigated) 
      {
         ObjectSetInteger(0, htf_zones[z].poi_name, OBJPROP_TIME, 1, live_t);
      }
   }
}

//--- Check if recently closed candles mitigated any zones
void ProcessHTFMitigation(const double &close[], int rates_total)
{
   if(rates_total < 2) return;
   int i = rates_total - 2; // Index of the most recently CLOSED candle

   for(int z = ArraySize(htf_zones) - 1; z >= 0; z--)
   {
      if(!htf_zones[z].ob_mitigated)
      {
         bool mit = (htf_zones[z].type == 1 && close[i] > htf_zones[z].ob_high) || 
                    (htf_zones[z].type == -1 && close[i] < htf_zones[z].ob_low);
         if(mit)
         {
            htf_zones[z].ob_mitigated = true;
            ObjectDelete(0, htf_zones[z].ob_name);
            ObjectDelete(0, htf_zones[z].lbl_name);
         }
      }

      if(!htf_zones[z].poi_mitigated)
      {
         bool mit = (htf_zones[z].type == 1 && close[i] > htf_zones[z].poi_high) || 
                    (htf_zones[z].type == -1 && close[i] < htf_zones[z].poi_low);
         if(mit)
         {
            htf_zones[z].poi_mitigated = true;
            ObjectDelete(0, htf_zones[z].poi_name);
         }
      }

      if(htf_zones[z].ob_mitigated && htf_zones[z].poi_mitigated)
      {
         ArrayRemove(htf_zones, z, 1);
      }
   }
}

//--- Process the HTF Candles
void ProcessHTFCandles()
{
   int offset_seconds = InpTimeOffsetHours * 3600;

   for(int t = 0; t < 3; t++)
   {
      if(!htf_cfg[t].enable) continue;

      // OPTIMIZATION: Fetch rates in one call instead of separate CopyHigh/Low/Time arrays
      MqlRates htf_rates[1];
      if(CopyRates(_Symbol, htf_cfg[t].tf, 1, 1, htf_rates) <= 0) continue;

      if(htf_rates[0].time == g_last_htf_time[t]) continue; // Already processed
      g_last_htf_time[t] = htf_rates[0].time;

      // PERSIST LOGIC
      if(!InpPersistOldOBs)
      {
         for(int z = ArraySize(htf_zones) - 1; z >= 0; z--)
         {
            if(htf_zones[z].htf_prefix == htf_cfg[t].prefix)
            {
               ObjectDelete(0, htf_zones[z].ob_name);
               ObjectDelete(0, htf_zones[z].poi_name);
               ObjectDelete(0, htf_zones[z].lbl_name);
               ArrayRemove(htf_zones, z, 1);
            }
         }
      }

      // FIBONACCI DIRECTION LOGIC (Green vs Red Candle)
      double p1, p2;
      if(htf_rates[0].close > htf_rates[0].open) {
         // Green Candle: Draw Top to Bottom
         p1 = htf_rates[0].high;
         p2 = htf_rates[0].low;
      } else {
         // Red Candle: Draw Bottom to Top
         p1 = htf_rates[0].low;
         p2 = htf_rates[0].high;
      }

      datetime htf_end_time = htf_rates[0].time + PeriodSeconds(htf_cfg[t].tf);
      
      // APPLY TIME OFFSET FOR FIB PROJECTION
      datetime fib_start = htf_end_time + offset_seconds;
      datetime fib_end   = fib_start + PeriodSeconds(htf_cfg[t].tf);
      
      DrawFibonacci(htf_cfg[t].prefix, htf_cfg[t].display_name, fib_start, p1, fib_end, p2, htf_cfg[t].fib_color);

      // EXTRACT LTF OBs
      MqlRates ltf_rates[];
      int copied = CopyRates(_Symbol, PERIOD_CURRENT, htf_rates[0].time, htf_end_time, ltf_rates);
      
      if(copied > 0)
      {
         double max_h = 0, min_l = 999999;
         int idx_high = -1, idx_low = -1;
         
         for(int i=0; i<copied; i++)
         {
            if(ltf_rates[i].high > max_h) { max_h = ltf_rates[i].high; idx_high = i; }
            if(ltf_rates[i].low < min_l)  { min_l = ltf_rates[i].low;  idx_low = i; }
         }
         
         string unique_id = (string)htf_rates[0].time;

         if(idx_high >= 0 && (htf_cfg[t].draw_zones || htf_cfg[t].draw_pois))
         {
            double sz_high = ltf_rates[idx_high].high;
            double sz_low = ltf_rates[idx_high].low;
            double poi_bot = sz_high + (InpPoIOffsetPoints * _Point);
            double poi_top = poi_bot + (sz_high - sz_low);
            AddActiveHTFZone(htf_cfg[t].prefix, htf_cfg[t].display_name, "Sell_" + unique_id, ltf_rates[idx_high].time, sz_high, sz_low, poi_top, poi_bot, 1, htf_cfg[t].draw_zones, htf_cfg[t].draw_pois);
         }
         
         if(idx_low >= 0 && (htf_cfg[t].draw_zones || htf_cfg[t].draw_pois))
         {
            double bz_high = ltf_rates[idx_low].high;
            double bz_low = ltf_rates[idx_low].low;
            double poi_top = bz_low - (InpPoIOffsetPoints * _Point);
            double poi_bot = poi_top - (bz_high - bz_low);
            AddActiveHTFZone(htf_cfg[t].prefix, htf_cfg[t].display_name, "Buy_" + unique_id, ltf_rates[idx_low].time, bz_high, bz_low, poi_top, poi_bot, -1, htf_cfg[t].draw_zones, htf_cfg[t].draw_pois);
         }
      }
   }
}

//--- Process CHoCH and FVG 
void ProcessCHoCH(int rates_total, const datetime &time[], const double &high[], const double &low[], const double &close[])
{
   int p = InpPivotPeriod;
   int limit = MathMax(p * 2, 10);
   
   for(int i = limit; i < rates_total - 1; i++) 
   {
      if(time[i] <= g_last_processed_time) continue;

      int ci = i - p;
      bool isSH = true, isSL = true;
      
      for(int j = 1; j <= p; j++)
      {
         if(high[ci] <= high[ci-j] || high[ci] <= high[ci+j]) isSH = false;
         if(low[ci]  >= low[ci-j]  || low[ci]  >= low[ci+j])  isSL = false;
         if(!isSH && !isSL) break;
      }
      
      if(isSH) { g_last_sh = high[ci]; g_last_sh_time = time[ci]; }
      if(isSL) { g_last_sl = low[ci];  g_last_sl_time = time[ci]; }

      if(g_last_trend <= 0 && g_last_sh > 0 && close[i] > g_last_sh)
      {
         g_last_trend = 1;
         string n = "FIB_CHoCH_Bull_" + (string)time[i];
         ObjectCreate(0, n, OBJ_TREND, 0, g_last_sh_time, g_last_sh, time[i], g_last_sh);
         ObjectSetInteger(0, n, OBJPROP_COLOR, InpBullChochColor);
         ObjectSetInteger(0, n, OBJPROP_STYLE, InpChochStyle);
         ObjectSetInteger(0, n, OBJPROP_WIDTH, InpChochWidth);
         ObjectSetInteger(0, n, OBJPROP_RAY_RIGHT, false);
         
         if(InpEnableFVG && i >= 2)
         {
            double fvg_top = low[i];
            double fvg_bot = high[i-2];
            if(fvg_top > fvg_bot && g_last_sh >= fvg_bot && g_last_sh <= fvg_top)
            {
               string fn = "FIB_FVG_Bull_" + (string)time[i];
               ObjectCreate(0, fn, OBJ_RECTANGLE, 0, time[i-2], fvg_top, time[i] + PeriodSeconds(), fvg_bot);
               ObjectSetInteger(0, fn, OBJPROP_COLOR, InpBullFVGColor); ObjectSetInteger(0, fn, OBJPROP_BGCOLOR, InpBullFVGColor);
               ObjectSetInteger(0, fn, OBJPROP_BACK, true); ObjectSetInteger(0, fn, OBJPROP_FILL, true); ObjectSetInteger(0, fn, OBJPROP_RAY_RIGHT, false);
            }
         }
         g_last_sh = 0.0;
      }

      if(g_last_trend >= 0 && g_last_sl > 0 && close[i] < g_last_sl)
      {
         g_last_trend = -1;
         string n = "FIB_CHoCH_Bear_" + (string)time[i];
         ObjectCreate(0, n, OBJ_TREND, 0, g_last_sl_time, g_last_sl, time[i], g_last_sl);
         ObjectSetInteger(0, n, OBJPROP_COLOR, InpBearChochColor);
         ObjectSetInteger(0, n, OBJPROP_STYLE, InpChochStyle);
         ObjectSetInteger(0, n, OBJPROP_WIDTH, InpChochWidth);
         ObjectSetInteger(0, n, OBJPROP_RAY_RIGHT, false);
         
         if(InpEnableFVG && i >= 2)
         {
            double fvg_bot = high[i];
            double fvg_top = low[i-2];
            if(fvg_top > fvg_bot && g_last_sl >= fvg_bot && g_last_sl <= fvg_top)
            {
               string fn = "FIB_FVG_Bear_" + (string)time[i];
               ObjectCreate(0, fn, OBJ_RECTANGLE, 0, time[i-2], fvg_top, time[i] + PeriodSeconds(), fvg_bot);
               ObjectSetInteger(0, fn, OBJPROP_COLOR, InpBearFVGColor); ObjectSetInteger(0, fn, OBJPROP_BGCOLOR, InpBearFVGColor);
               ObjectSetInteger(0, fn, OBJPROP_BACK, true); ObjectSetInteger(0, fn, OBJPROP_FILL, true); ObjectSetInteger(0, fn, OBJPROP_RAY_RIGHT, false);
            }
         }
         g_last_sl = 0.0;
      }
      
      g_last_processed_time = time[i];
   }
}

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "Fib HTF Multi v1.40");
   
   htf_cfg[0].enable = InpEnableHTF1; htf_cfg[0].tf = InpHTF1; htf_cfg[0].fib_color = InpFibColor1; htf_cfg[0].prefix = "HTF1_"; htf_cfg[0].display_name = GetTFName(InpHTF1); htf_cfg[0].draw_zones = InpDrawZones1; htf_cfg[0].draw_pois = InpDrawPoI1;
   htf_cfg[1].enable = InpEnableHTF2; htf_cfg[1].tf = InpHTF2; htf_cfg[1].fib_color = InpFibColor2; htf_cfg[1].prefix = "HTF2_"; htf_cfg[1].display_name = GetTFName(InpHTF2); htf_cfg[1].draw_zones = InpDrawZones2; htf_cfg[1].draw_pois = InpDrawPoI2;
   htf_cfg[2].enable = InpEnableHTF3; htf_cfg[2].tf = InpHTF3; htf_cfg[2].fib_color = InpFibColor3; htf_cfg[2].prefix = "HTF3_"; htf_cfg[2].display_name = GetTFName(InpHTF3); htf_cfg[2].draw_zones = InpDrawZones3; htf_cfg[2].draw_pois = InpDrawPoI3;
   
   CleanChart("HTF1_");
   CleanChart("HTF2_");
   CleanChart("HTF3_");
   CleanChart("FIB_CHoCH_");
   CleanChart("FIB_FVG_");
   
   ArrayResize(htf_zones, 0); 
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   CleanChart("HTF1_");
   CleanChart("HTF2_");
   CleanChart("HTF3_");
   CleanChart("FIB_CHoCH_");
   CleanChart("FIB_FVG_");
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
   if(rates_total < InpPivotPeriod * 2) return 0;

   // 1. Process all enabled HTFs
   ProcessHTFCandles();
   
   // 2. Process Mitigations on Closed Candles
   ProcessHTFMitigation(close, rates_total);
   
   // 3. Visually Extend Unmitigated Zones to Live Price
   ExtendHTFZonesToLive(time, rates_total);
   
   // 4. Track Market Structure & Mark CHoCH/FVG
   ProcessCHoCH(rates_total, time, high, low, close);

   return(rates_total);
}
//+------------------------------------------------------------------+