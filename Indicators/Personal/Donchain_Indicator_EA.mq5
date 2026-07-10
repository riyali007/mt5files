//+------------------------------------------------------------------+
//|                                       DonchianSignal.mq5 |
//|                                   Based on Pine Script "Pure %" |
//|                                      Exact Replica Logic |
//+------------------------------------------------------------------+
#property copyright "Gemini"
#property indicator_chart_window
#property indicator_buffers 9
#property indicator_plots   5

//--- Plot 1: Middle Line
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1
#property indicator_label1  "Middle"

//--- Plot 2: Upper Line
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrGreen
#property indicator_label2  "Upper"

//--- Plot 3: Lower Line
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrRed
#property indicator_label3  "Lower"

//--- Plot 4: Buy Signal (Buffer for EA)
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrDarkGreen
#property indicator_width4  2
#property indicator_label4  "Buy Signal"

//--- Plot 5: Sell Signal (Buffer for EA)
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrDarkRed
#property indicator_width5  2
#property indicator_label5  "Sell Signal"


//--- Inputs ---
input group "Strategy Settings"
input int      InpRange        = 11;       // Donchian Period
input double   InpSLPercent    = 2.0;      // Stop Loss %
input int      InpSLToBe       = 2;        // Put Stop Loss to BE After TP (0-4)
input string   InpCloseAfter   = "Never";  // Close Trade After Hit (Never, TP1-TP4)

input group "Take Profit Settings (%)"
input double   InpTP1          = 2.0;      // TP1 %
input double   InpTP2          = 4.0;      // TP2 %
input double   InpTP3          = 6.0;      // TP3 %
input double   InpTP4          = 10.0;     // TP4 %

input group "Entry Logic"
input bool     InpUseSLParams  = false;    // Use SL as Entry (Limit Order)

input group "Display Options"
input bool     InpShowUp       = true;     // Show Upper Line
input bool     InpShowMid      = true;     // Show Middle Line
input bool     InpShowLow      = true;     // Show Lower Line
input bool     InpShowEntry    = true;     // Show Entry Arrows
input bool     InpShowSL       = true;     // Show SL Line/Label
input bool     InpShowTP1      = true;     // Show TP1 Line/Label
input bool     InpShowTP2      = true;     // Show TP2 Line/Label
input bool     InpShowTP3      = true;     // Show TP3 Line/Label
input bool     InpShowTP4      = true;     // Show TP4 Line/Label

input group "Filters & Cooldown"
input int      InpCoolBars     = 5;        // Cooldown Bars

input group "Visuals & History"
input int      InpMaxTrades    = 10;       // Max Simultaneous Active Trades
input ENUM_LINE_STYLE InpTPStyle = STYLE_DASH; // TP Line Style
input color    InpColSL        = clrRed;   // SL Color
input color    InpColTPDef     = C'192,192,192'; // TP Default (Ghost Gray)
input color    InpColHit       = clrGreen; // TP Hit Color
input color    InpColWait      = clrYellow;// Pending Entry Color
input color    InpColBuyArr    = clrDarkGreen; // Buy Arrow Color
input color    InpColSellArr   = clrDarkRed;   // Sell Arrow Color
input int      InpMaxHistory   = 1000;     // Max Bars to Simulate

//--- Buffers
double BufMid[];   // Buffer 0 (Plot 1)
double BufUp[];    // Buffer 1 (Plot 2)
double BufLow[];   // Buffer 2 (Plot 3)
double BufBuy[];   // Buffer 3 (Plot 4) - For EA
double BufSell[];  // Buffer 4 (Plot 5) - For EA

// Calculation Buffers (Hidden)
double BufUps[];   // Buffer 5
double BufDns[];   // Buffer 6
double BufBC[];    // Buffer 7
double BufSC[];    // Buffer 8

//--- Structures
struct Trade {
   int      id;
   int      dir; 
   double   entry_price;
   double   sl;
   double   tp1; double   tp2; double   tp3; double   tp4;
   bool     active;
   bool     tp1_hit; bool     tp2_hit; bool     tp3_hit; bool     any_hit;
   string   obj_sl;  string   obj_tp1; string   obj_tp2; string   obj_tp3; string   obj_tp4;
   string   lbl_sl;  string   lbl_tp1; string   lbl_tp2; string   lbl_tp3; string   lbl_tp4; string arrow_entry;
};

struct Pending {
   bool     active;
   int      dir;
   double   limit_price;
   string   obj_vis;
   string   lbl_vis;
};

//--- Globals
Trade    trades[];
Pending  pend;
bool     entry_locked = false;
int      last_exit_bar_idx = -999; 
int      global_id_counter = 0;

//+------------------------------------------------------------------+
//| Custom Indicator Initialization Function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BufMid, INDICATOR_DATA);
   SetIndexBuffer(1, BufUp, INDICATOR_DATA);
   SetIndexBuffer(2, BufLow, INDICATOR_DATA);
   SetIndexBuffer(3, BufBuy, INDICATOR_DATA);
   SetIndexBuffer(4, BufSell, INDICATOR_DATA);
   
   SetIndexBuffer(5, BufUps, INDICATOR_CALCULATIONS);
   SetIndexBuffer(6, BufDns, INDICATOR_CALCULATIONS);
   SetIndexBuffer(7, BufBC, INDICATOR_CALCULATIONS);
   SetIndexBuffer(8, BufSC, INDICATOR_CALCULATIONS);

   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, InpRange);
   PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, InpRange); 
   PlotIndexSetInteger(2, PLOT_DRAW_BEGIN, InpRange);
   PlotIndexSetInteger(3, PLOT_DRAW_BEGIN, InpRange);
   PlotIndexSetInteger(4, PLOT_DRAW_BEGIN, InpRange);

   // Apply Individual Visibility for Main Indicator Lines
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, InpShowMid ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(1, PLOT_DRAW_TYPE, InpShowUp  ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(2, PLOT_DRAW_TYPE, InpShowLow ? DRAW_LINE : DRAW_NONE);
   
   // Arrow Types
   PlotIndexSetInteger(3, PLOT_ARROW, 233); // Up Arrow
   PlotIndexSetInteger(4, PLOT_ARROW, 234); // Down Arrow

   pend.active = false;
   ObjectsDeleteAll(0, "DS_");
   
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { ObjectsDeleteAll(0, "DS_"); }

//--- Helpers ---
int GetCloseAtTPNum() {
   if(InpCloseAfter == "TP1") return 1;
   if(InpCloseAfter == "TP2") return 2;
   if(InpCloseAfter == "TP3") return 3;
   if(InpCloseAfter == "TP4") return 4;
   return 0;
}

bool IsVisible(string name) {
   if(StringFind(name, "_sl") != -1 || StringFind(name, "SL") != -1) return InpShowSL;
   if(StringFind(name, "_t1") != -1 || StringFind(name, "TP1") != -1) return InpShowTP1;
   if(StringFind(name, "_t2") != -1 || StringFind(name, "TP2") != -1) return InpShowTP2;
   if(StringFind(name, "_t3") != -1 || StringFind(name, "TP3") != -1) return InpShowTP3;
   if(StringFind(name, "_t4") != -1 || StringFind(name, "TP4") != -1) return InpShowTP4;
   return true;
}

void CreateLine(string name, datetime t1, double p1, datetime t2, double p2, color clr, ENUM_LINE_STYLE style) {
   if(!IsVisible(name)) return;
   if(ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2)) {
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, style);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
}

void CreateLabel(string name, datetime t, double p, string txt, color clr, ENUM_ANCHOR_POINT anchor) {
   if(!IsVisible(name)) return;
   if(ObjectCreate(0, name, OBJ_TEXT, 0, t, p)) {
      ObjectSetString(0, name, OBJPROP_TEXT, txt);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
}

void UpdateVisuals(Trade &t, datetime current_time) {
   if(ObjectFind(0, t.obj_sl) >= 0) ObjectSetInteger(0, t.obj_sl, OBJPROP_TIME, 1, current_time);
   if(ObjectFind(0, t.obj_tp1) >= 0) ObjectSetInteger(0, t.obj_tp1, OBJPROP_TIME, 1, current_time);
   if(ObjectFind(0, t.obj_tp2) >= 0) ObjectSetInteger(0, t.obj_tp2, OBJPROP_TIME, 1, current_time);
   if(ObjectFind(0, t.obj_tp3) >= 0) ObjectSetInteger(0, t.obj_tp3, OBJPROP_TIME, 1, current_time);
   if(ObjectFind(0, t.obj_tp4) >= 0) ObjectSetInteger(0, t.obj_tp4, OBJPROP_TIME, 1, current_time);
   
   if(ObjectFind(0, t.lbl_sl) >= 0) ObjectSetInteger(0, t.lbl_sl, OBJPROP_TIME, current_time);
   if(ObjectFind(0, t.lbl_tp1) >= 0) ObjectSetInteger(0, t.lbl_tp1, OBJPROP_TIME, current_time);
   if(ObjectFind(0, t.lbl_tp2) >= 0) ObjectSetInteger(0, t.lbl_tp2, OBJPROP_TIME, current_time);
   if(ObjectFind(0, t.lbl_tp3) >= 0) ObjectSetInteger(0, t.lbl_tp3, OBJPROP_TIME, current_time);
   if(ObjectFind(0, t.lbl_tp4) >= 0) ObjectSetInteger(0, t.lbl_tp4, OBJPROP_TIME, current_time);
}

void MoveToBE(Trade &t) {
   t.sl = t.entry_price;
   if(ObjectFind(0, t.obj_sl) >= 0) {
      ObjectSetDouble(0, t.obj_sl, OBJPROP_PRICE, 0, t.sl);
      ObjectSetDouble(0, t.obj_sl, OBJPROP_PRICE, 1, t.sl);
   }
   if(ObjectFind(0, t.lbl_sl) >= 0) {
      ObjectSetInteger(0, t.lbl_sl, OBJPROP_COLOR, clrGray);
      ObjectSetString(0, t.lbl_sl, OBJPROP_TEXT, "SL: BE");
   }
}

void MarkHit(string ln, string lb, string txt, double p) {
   if(ObjectFind(0, ln) >= 0) {
      ObjectSetInteger(0, ln, OBJPROP_COLOR, InpColHit);
      ObjectSetInteger(0, ln, OBJPROP_STYLE, InpTPStyle);
   }
   if(ObjectFind(0, lb) >= 0) {
      ObjectSetInteger(0, lb, OBJPROP_COLOR, InpColHit);
      ObjectSetString(0, lb, OBJPROP_TEXT, txt + ": " + DoubleToString(p, _Digits));
   }
}

void ClearTPs(Trade &t) {
   ObjectDelete(0, t.obj_tp1); ObjectDelete(0, t.obj_tp2); ObjectDelete(0, t.obj_tp3); ObjectDelete(0, t.obj_tp4);
   ObjectDelete(0, t.lbl_tp1); ObjectDelete(0, t.lbl_tp2); ObjectDelete(0, t.lbl_tp3); ObjectDelete(0, t.lbl_tp4);
}

//+------------------------------------------------------------------+
//| Main Calculation Loop                                            |
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
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   
   ArraySetAsSeries(BufMid, true);
   ArraySetAsSeries(BufUp, true);
   ArraySetAsSeries(BufLow, true);
   ArraySetAsSeries(BufBuy, true);
   ArraySetAsSeries(BufSell, true);
   
   ArraySetAsSeries(BufUps, true);
   ArraySetAsSeries(BufDns, true);
   ArraySetAsSeries(BufBC, true);
   ArraySetAsSeries(BufSC, true);

   int limit = rates_total - prev_calculated;
   if(prev_calculated == 0) {
      limit = rates_total - 1;
      ArrayResize(trades, 0);
      ObjectsDeleteAll(0, "DS_");
      last_exit_bar_idx = rates_total + 999; 
   }
   
   for(int i = limit; i >= 0; i--)
   {
      BufBuy[i] = EMPTY_VALUE;
      BufSell[i] = EMPTY_VALUE;

      if(i >= rates_total - InpRange) continue; 

      int highest_idx = iHighest(NULL, 0, MODE_HIGH, InpRange, i);
      int lowest_idx  = iLowest(NULL, 0, MODE_LOW, InpRange, i);
      
      double h = high[highest_idx];
      double l = low[lowest_idx];
      double m = (h + l) / 2.0;
      
      BufUp[i]    = h; 
      BufLow[i]   = l; 
      BufMid[i]   = m;

      double prev_ups = (i < rates_total - 1) ? BufUps[i+1] : 0.0;
      double prev_dns = (i < rates_total - 1) ? BufDns[i+1] : 0.0;
      
      double ups = (high[i] == h) ? low[i] : prev_ups;
      double dns = (low[i] == l) ? high[i] : prev_dns;
      
      if(ups == 0) ups = low[i];
      if(dns == 0) dns = high[i];
      
      BufUps[i] = ups;
      BufDns[i] = dns;
      
      bool buy_cond = (close[i] > dns && close[i+1] <= dns) && (close[i] < m);
      bool sell_cond = (close[i] < ups && close[i+1] >= ups) && (close[i] > m);
      
      double prev_bc = (i < rates_total - 1) ? BufBC[i+1] : 0.0;
      double prev_sc = (i < rates_total - 1) ? BufSC[i+1] : 0.0;
      
      double bc = 0;
      if(ups == prev_ups && buy_cond) bc = prev_bc + 1;
      else if(dns == high[i]) bc = 0;
      else bc = prev_bc;
      
      double sc = 0;
      if(dns == prev_dns && sell_cond) sc = prev_sc + 1;
      else if(ups == low[i]) sc = 0;
      else sc = prev_sc;
      
      BufBC[i] = bc;
      BufSC[i] = sc;

      if(i > InpMaxHistory) continue;

      if(pend.active) {
         ObjectSetInteger(0, pend.obj_vis, OBJPROP_TIME, 1, time[i]);
         ObjectSetInteger(0, pend.lbl_vis, OBJPROP_TIME, time[i]);
         
         bool filled = false;
         if(pend.dir == 1 && low[i] <= pend.limit_price) filled = true;
         if(pend.dir == -1 && high[i] >= pend.limit_price) filled = true;
         
         if(filled) {
            entry_locked = true;
            double en = pend.limit_price;
            int dir = pend.dir;
            
            double sl_p = (dir==1) ? en - (en*(InpSLPercent/100)) : en + (en*(InpSLPercent/100));
            double tp1 = (dir==1) ? en + (en*(InpTP1/100)) : en - (en*(InpTP1/100));
            double tp2 = (dir==1) ? en + (en*(InpTP2/100)) : en - (en*(InpTP2/100));
            double tp3 = (dir==1) ? en + (en*(InpTP3/100)) : en - (en*(InpTP3/100));
            double tp4 = (dir==1) ? en + (en*(InpTP4/100)) : en - (en*(InpTP4/100));
            
            global_id_counter++;
            string pfx = "DS_" + IntegerToString(global_id_counter);
            Trade t; t.id=global_id_counter; t.dir=dir; t.entry_price=en; t.sl=sl_p;
            t.tp1=tp1; t.tp2=tp2; t.tp3=tp3; t.tp4=tp4; t.active=true;
            t.tp1_hit=false; t.tp2_hit=false; t.tp3_hit=false; t.any_hit=false;
            
            t.obj_sl=pfx+"_sl"; CreateLine(t.obj_sl, time[i], sl_p, time[i], sl_p, InpColSL, STYLE_DASH);
            t.obj_tp1=pfx+"_t1"; CreateLine(t.obj_tp1, time[i], tp1, time[i], tp1, InpColTPDef, InpTPStyle);
            t.obj_tp2=pfx+"_t2"; CreateLine(t.obj_tp2, time[i], tp2, time[i], tp2, InpColTPDef, InpTPStyle);
            t.obj_tp3=pfx+"_t3"; CreateLine(t.obj_tp3, time[i], tp3, time[i], tp3, InpColTPDef, InpTPStyle);
            t.obj_tp4=pfx+"_t4"; CreateLine(t.obj_tp4, time[i], tp4, time[i], tp4, InpColTPDef, InpTPStyle);
            
            t.lbl_sl=pfx+"_lsl"; CreateLabel(t.lbl_sl, time[i], sl_p, "SL", InpColSL, dir==1?ANCHOR_UPPER:ANCHOR_LOWER);
            t.lbl_tp1=pfx+"_lt1"; CreateLabel(t.lbl_tp1, time[i], tp1, "TP1", InpColTPDef, dir==1?ANCHOR_LOWER:ANCHOR_UPPER);
            t.lbl_tp2=pfx+"_lt2"; CreateLabel(t.lbl_tp2, time[i], tp2, "TP2", InpColTPDef, dir==1?ANCHOR_LOWER:ANCHOR_UPPER);
            t.lbl_tp3=pfx+"_lt3"; CreateLabel(t.lbl_tp3, time[i], tp3, "TP3", InpColTPDef, dir==1?ANCHOR_LOWER:ANCHOR_UPPER);
            t.lbl_tp4=pfx+"_lt4"; CreateLabel(t.lbl_tp4, time[i], tp4, "TP4", InpColTPDef, dir==1?ANCHOR_LOWER:ANCHOR_UPPER);
            
            if(InpShowEntry) BufBuy[i] = low[i]; // Visualize on chart using Arrow logic via EA buffer (optional duplication)
            
            int s=ArraySize(trades); ArrayResize(trades, s+1); trades[s]=t;
            pend.active=false; ObjectDelete(0, pend.obj_vis); ObjectDelete(0, pend.lbl_vis);
         }
      }

      int active_count = 0;
      for(int k=ArraySize(trades)-1; k>=0; k--) {
         Trade t = trades[k];
         if(!t.active) continue;
         active_count++;
         UpdateVisuals(t, time[i]);
         
         bool close_t = false;
         if(t.dir == 1) {
            if(low[i] <= t.sl) { close_t=true; CreateLabel(t.obj_sl+"h", time[i], low[i], t.any_hit?"BE":"SL", clrGray, ANCHOR_UPPER); if(!t.any_hit) ClearTPs(t); }
            else {
               if(high[i] >= t.tp1 && !t.tp1_hit) { t.tp1_hit=true; t.any_hit=true; entry_locked=false; if(InpSLToBe==1) MoveToBE(t); MarkHit(t.obj_tp1, t.lbl_tp1, "TP1", t.tp1); if(GetCloseAtTPNum()==1) close_t=true;}
               if(high[i] >= t.tp2 && !t.tp2_hit) { t.tp2_hit=true; if(InpSLToBe==2) MoveToBE(t); MarkHit(t.obj_tp2, t.lbl_tp2, "TP2", t.tp2); if(GetCloseAtTPNum()==2) close_t=true;}
               if(high[i] >= t.tp3 && !t.tp3_hit) { t.tp3_hit=true; if(InpSLToBe==3) MoveToBE(t); MarkHit(t.obj_tp3, t.lbl_tp3, "TP3", t.tp3); if(GetCloseAtTPNum()==3) close_t=true;}
               if(high[i] >= t.tp4) { close_t=true; MarkHit(t.obj_tp4, t.lbl_tp4, "Full", t.tp4); }
            }
         }
         else {
            if(high[i] >= t.sl) { close_t=true; CreateLabel(t.obj_sl+"h", time[i], high[i], t.any_hit?"BE":"SL", clrGray, ANCHOR_LOWER); if(!t.any_hit) ClearTPs(t); }
            else {
               if(low[i] <= t.tp1 && !t.tp1_hit) { t.tp1_hit=true; t.any_hit=true; entry_locked=false; if(InpSLToBe==1) MoveToBE(t); MarkHit(t.obj_tp1, t.lbl_tp1, "TP1", t.tp1); if(GetCloseAtTPNum()==1) close_t=true;}
               if(low[i] <= t.tp2 && !t.tp2_hit) { t.tp2_hit=true; if(InpSLToBe==2) MoveToBE(t); MarkHit(t.obj_tp2, t.lbl_tp2, "TP2", t.tp2); if(GetCloseAtTPNum()==2) close_t=true;}
               if(low[i] <= t.tp3 && !t.tp3_hit) { t.tp3_hit=true; if(InpSLToBe==3) MoveToBE(t); MarkHit(t.obj_tp3, t.lbl_tp3, "TP3", t.tp3); if(GetCloseAtTPNum()==3) close_t=true;}
               if(low[i] <= t.tp4) { close_t=true; MarkHit(t.obj_tp4, t.lbl_tp4, "Full", t.tp4); }
            }
         }
         trades[k] = t;
         if(close_t) { trades[k].active=false; last_exit_bar_idx=i; if(!t.any_hit) entry_locked=false; active_count--;}
      }

      bool cooldown = (last_exit_bar_idx - i >= InpCoolBars); 
      
      if(!entry_locked && !pend.active && cooldown && active_count < InpMaxTrades) {
         if(buy_cond && bc == 1.0) {
            
            // --- SIGNAL BUFFER UPDATE FOR EA ---
            BufBuy[i] = low[i];
            // -----------------------------------
            
            double dist = close[i] * (InpSLPercent/100.0);
            double limit = close[i] - dist;
            if(InpUseSLParams) {
               pend.active=true; pend.dir=1; pend.limit_price=limit; 
               pend.obj_vis="DS_P_"+IntegerToString(i); pend.lbl_vis="DS_PL_"+IntegerToString(i);
               CreateLine(pend.obj_vis, time[i], limit, time[i], limit, InpColWait, STYLE_DOT);
               CreateLabel(pend.lbl_vis, time[i], limit, "Wait", InpColWait, ANCHOR_RIGHT);
            } else {
            
               entry_locked = true;
               double en = close[i]; int dir = 1;
               double sl_p = en - (close[i+1]*(InpSLPercent/100));
               double tp1 = en + (en*(InpTP1/100)); double tp2 = en + (en*(InpTP2/100));
               double tp3 = en + (en*(InpTP3/100)); double tp4 = en + (en*(InpTP4/100));
               
               global_id_counter++; string pfx = "DS_" + IntegerToString(global_id_counter);
               Trade t; t.id=global_id_counter; t.dir=dir; t.entry_price=en; t.sl=sl_p;
               t.tp1=tp1; t.tp2=tp2; t.tp3=tp3; t.tp4=tp4; t.active=true;
               t.tp1_hit=false; t.tp2_hit=false; t.tp3_hit=false; t.any_hit=false;
               
               t.obj_sl=pfx+"_sl"; CreateLine(t.obj_sl, time[i], sl_p, time[i], sl_p, InpColSL, STYLE_DASH);
               t.obj_tp1=pfx+"_t1"; CreateLine(t.obj_tp1, time[i], tp1, time[i], tp1, InpColTPDef, InpTPStyle);
               t.obj_tp2=pfx+"_t2"; CreateLine(t.obj_tp2, time[i], tp2, time[i], tp2, InpColTPDef, InpTPStyle);
               t.obj_tp3=pfx+"_t3"; CreateLine(t.obj_tp3, time[i], tp3, time[i], tp3, InpColTPDef, InpTPStyle);
               t.obj_tp4=pfx+"_t4"; CreateLine(t.obj_tp4, time[i], tp4, time[i], tp4, InpColTPDef, InpTPStyle);
               
               t.lbl_sl=pfx+"_lsl"; CreateLabel(t.lbl_sl, time[i], sl_p, "SL", InpColSL, ANCHOR_UPPER);
               t.lbl_tp1=pfx+"_lt1"; CreateLabel(t.lbl_tp1, time[i], tp1, "TP1", InpColTPDef, ANCHOR_LOWER);
               t.lbl_tp2=pfx+"_lt2"; CreateLabel(t.lbl_tp2, time[i], tp2, "TP2", InpColTPDef, ANCHOR_LOWER);
               t.lbl_tp3=pfx+"_lt3"; CreateLabel(t.lbl_tp3, time[i], tp3, "TP3", InpColTPDef, ANCHOR_LOWER);
               t.lbl_tp4=pfx+"_lt4"; CreateLabel(t.lbl_tp4, time[i], tp4, "TP4", InpColTPDef, ANCHOR_LOWER);
               
               // ENTRY ARROW REPLACEMENT
               if(InpShowEntry) {
                   // We don't use object create here because BUFFER 3 does it automatically now
               }
               PlaySound("alert.wav");
               int s=ArraySize(trades); ArrayResize(trades, s+1); trades[s]=t;
            }
         }
         if(sell_cond && sc == 1.0) {
            // --- SIGNAL BUFFER UPDATE FOR EA ---
            BufSell[i] = high[i];
            // -----------------------------------
            
            double dist = close[i] * (InpSLPercent/100.0);
            double limit = close[i] + dist;
            if(InpUseSLParams) {
               pend.active=true; pend.dir=-1; pend.limit_price=limit; 
               pend.obj_vis="DS_P_"+IntegerToString(i); pend.lbl_vis="DS_PL_"+IntegerToString(i);
               CreateLine(pend.obj_vis, time[i], limit, time[i], limit, InpColWait, STYLE_DOT);
               CreateLabel(pend.lbl_vis, time[i], limit, "Wait", InpColWait, ANCHOR_RIGHT);
            } else {
               entry_locked = true;
               double en = close[i]; int dir = -1;
               double sl_p = en + (en*(InpSLPercent/100));
               double tp1 = en - (en*(InpTP1/100)); double tp2 = en - (en*(InpTP2/100));
               double tp3 = en - (en*(InpTP3/100)); double tp4 = en - (en*(InpTP4/100));
               
               global_id_counter++; string pfx = "DS_" + IntegerToString(global_id_counter);
               Trade t; t.id=global_id_counter; t.dir=dir; t.entry_price=en; t.sl=sl_p;
               t.tp1=tp1; t.tp2=tp2; t.tp3=tp3; t.tp4=tp4; t.active=true;
               t.tp1_hit=false; t.tp2_hit=false; t.tp3_hit=false; t.any_hit=false;
               
               t.obj_sl=pfx+"_sl"; CreateLine(t.obj_sl, time[i], sl_p, time[i], sl_p, InpColSL, STYLE_DASH);
               t.obj_tp1=pfx+"_t1"; CreateLine(t.obj_tp1, time[i], tp1, time[i], tp1, InpColTPDef, InpTPStyle);
               t.obj_tp2=pfx+"_t2"; CreateLine(t.obj_tp2, time[i], tp2, time[i], tp2, InpColTPDef, InpTPStyle);
               t.obj_tp3=pfx+"_t3"; CreateLine(t.obj_tp3, time[i], tp3, time[i], tp3, InpColTPDef, InpTPStyle);
               t.obj_tp4=pfx+"_t4"; CreateLine(t.obj_tp4, time[i], tp4, time[i], tp4, InpColTPDef, InpTPStyle);
               
               t.lbl_sl=pfx+"_lsl"; CreateLabel(t.lbl_sl, time[i], sl_p, "SL", InpColSL, ANCHOR_LOWER);
               t.lbl_tp1=pfx+"_lt1"; CreateLabel(t.lbl_tp1, time[i], tp1, "TP1", InpColTPDef, ANCHOR_UPPER);
               t.lbl_tp2=pfx+"_lt2"; CreateLabel(t.lbl_tp2, time[i], tp2, "TP2", InpColTPDef, ANCHOR_UPPER);
               t.lbl_tp3=pfx+"_lt3"; CreateLabel(t.lbl_tp3, time[i], tp3, "TP3", InpColTPDef, ANCHOR_UPPER);
               t.lbl_tp4=pfx+"_lt4"; CreateLabel(t.lbl_tp4, time[i], tp4, "TP4", InpColTPDef, ANCHOR_UPPER);
               
               PlaySound("alert.wav");
               int s=ArraySize(trades); ArrayResize(trades, s+1); trades[s]=t;
            }
         }
      }
   }
   
   return(rates_total);
}
//+------------------------------------------------------------------+
