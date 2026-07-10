//+------------------------------------------------------------------+
//|                                           CHoCH_DualZone_OB.mq5  |
//|  Market Structure + Dual-Zone Order Block Reversal PoI           |
//+------------------------------------------------------------------+
#property copyright   "Riy Tech"
#property link        ""
#property version     "2.20"
#property indicator_chart_window
#property indicator_plots 0

//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
enum ENUM_TEXT_POSITION
{
   TXTPOS_TOP_LEFT    = 0,  
   TXTPOS_TOP_CENTER  = 1,  
   TXTPOS_TOP_RIGHT   = 2,  
   TXTPOS_MID_LEFT    = 3,  
   TXTPOS_MID_CENTER  = 4,  
   TXTPOS_MID_RIGHT   = 5,  
   TXTPOS_BOT_LEFT    = 6,  
   TXTPOS_BOT_CENTER  = 7,  
   TXTPOS_BOT_RIGHT   = 8,  
};

enum ENUM_ZONE_TRIM_MODE
{
   ZTRIM_NONE       = 0,  
   ZTRIM_UPPER_WICK = 1,  
   ZTRIM_PCT_CAP    = 2,  
};

//+------------------------------------------------------------------+
//| INPUTS — HTF High/Low                                            |
//+------------------------------------------------------------------+
input group "=== 4H High/Low ==="
input bool            Inp4H_Enable  = true;
input color           Inp4H_HighClr = clrRed;
input color           Inp4H_LowClr  = clrLime;
input int             Inp4H_Width   = 2;
input ENUM_LINE_STYLE Inp4H_Style   = STYLE_SOLID;

input group "=== 1H High/Low ==="
input bool            Inp1H_Enable  = true;
input color           Inp1H_HighClr = clrRed;
input color           Inp1H_LowClr  = clrLime;
input int             Inp1H_Width   = 2;
input ENUM_LINE_STYLE Inp1H_Style   = STYLE_SOLID;

input group "=== HTF Label Settings ==="
input bool            InpShowLabels    = true;
input int             InpFontSize      = 9;
input bool            InpShowPrice     = true;
input color           InpHTFLabelColor = clrWhite;

//+------------------------------------------------------------------+
//| INPUTS — CHoCH                                                   |
//+------------------------------------------------------------------+
input group "=== CHoCH — Timeframe 1 ==="
input bool            InpTF1Enable      = true;
input ENUM_TIMEFRAMES InpTF1            = PERIOD_H1;
input int             InpTF1PivotPeriod = 5;
input color           InpTF1BullColor   = clrLime;
input color           InpTF1BearColor   = clrRed;
input ENUM_LINE_STYLE InpTF1LineStyle   = STYLE_SOLID;
input int             InpTF1LineWidth   = 2;

input group "=== CHoCH — Timeframe 2 ==="
input bool            InpTF2Enable      = true;
input ENUM_TIMEFRAMES InpTF2            = PERIOD_H4;
input int             InpTF2PivotPeriod = 5;
input color           InpTF2BullColor   = clrTeal;
input color           InpTF2BearColor   = clrMaroon;
input ENUM_LINE_STYLE InpTF2LineStyle   = STYLE_DASH;
input int             InpTF2LineWidth   = 2;

//+------------------------------------------------------------------+
//| INPUTS — Dual Zone & PoI Settings                                |
//+------------------------------------------------------------------+
input group "=== Dual Zone & PoI Settings ==="
input int             InpMaxBars            = 3000;
input color           Inp_BZoneColor        = clrDarkGreen;
input color           Inp_SZoneColor        = clrDarkRed;
input int             InpPoIOffsetPoints    = 100;     // PoI Offset (in Points)
input color           Inp_PoIBullColor      = clrLimeGreen;
input color           Inp_PoIBearColor      = clrOrangeRed;
input color           InpMidLineColor       = clrGray; // Midline color
input ENUM_LINE_STYLE InpMidLineStyle       = STYLE_DOT; // Midline style

input group "=== Mitigation & Cleanup ==="
input color           InpMitigatedColor         = clrDarkGray;
input int             InpMitigatedExpiryMinutes = 5;   // Expiry of mitigated zones (mins, 0=Keep)

input group "=== Text & Trim Settings ==="
input color           InpZoneLabelColor     = clrWhite;
input int             InpZoneFontSize       = 8;
input ENUM_TEXT_POSITION InpZoneLabelPos    = TXTPOS_BOT_RIGHT;
input double          InpZoneTrimThreshold  = 5.0;
input ENUM_ZONE_TRIM_MODE InpZoneTrimMode   = ZTRIM_NONE;
input double          InpZoneTrimPct        = 50.0;
input int             InpChochFontSize      = 9;
input int             InpChochTextOffset    = 5;
input ENUM_TEXT_POSITION InpChochTextPos    = TXTPOS_BOT_CENTER;
input ENUM_TEXT_POSITION InpChochTextPosBear= TXTPOS_TOP_CENTER;

//+------------------------------------------------------------------+
//| GLOBALS                                                          |
//+------------------------------------------------------------------+
string   g_HTFPrefix   = "HTFHL_";
datetime g_LastBarTime = 0;

struct TFConfig {
   bool            enabled;
   ENUM_TIMEFRAMES tf;
   string          tfName;
   color           highClr;
   color           lowClr;
   int             width;
   ENUM_LINE_STYLE style;
};

struct ActiveZone {
   string          name;
   string          mid_name;      
   string          lbl_name;
   string          poi_name;
   string          poi_mid_name;  
   string          poi_lbl_name;
   int             type;          // 1=Sell, -1=Buy
   double          high;
   double          low;
   ENUM_TIMEFRAMES tf;
};
ActiveZone active_zones[];

struct MitigatedZone {
   string          name;
   string          mid_name;
   string          lbl_name;
   string          poi_name;
   string          poi_mid_name;
   string          poi_lbl_name;
   datetime        mitigated_time;
};
MitigatedZone mitigated_zones[];

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
   datetime        last_processed_time;
};
TFState states[2];

//+------------------------------------------------------------------+
//| Text Anchor Helper                                               |
//+------------------------------------------------------------------+
ENUM_ANCHOR_POINT TextPosToAnchor(ENUM_TEXT_POSITION pos) {
   switch(pos) {
      case TXTPOS_TOP_LEFT:   return ANCHOR_LEFT_UPPER;
      case TXTPOS_TOP_CENTER: return ANCHOR_UPPER;
      case TXTPOS_TOP_RIGHT:  return ANCHOR_RIGHT_UPPER;
      case TXTPOS_MID_LEFT:   return ANCHOR_LEFT;
      case TXTPOS_MID_CENTER: return ANCHOR_CENTER;
      case TXTPOS_MID_RIGHT:  return ANCHOR_RIGHT;
      case TXTPOS_BOT_LEFT:   return ANCHOR_LEFT_LOWER;
      case TXTPOS_BOT_CENTER: return ANCHOR_LOWER;
      case TXTPOS_BOT_RIGHT:  return ANCHOR_RIGHT_LOWER;
   }
   return ANCHOR_RIGHT_LOWER;
}

//+------------------------------------------------------------------+
//| Zone Trim Logic                                                  |
//+------------------------------------------------------------------+
void TrimLargeZone(double &zh, double &zl, double candle_high, double candle_low, double candle_open, double candle_close, int zone_type) {
   if(InpZoneTrimMode == ZTRIM_NONE) return;
   double fullRange = candle_high - candle_low;
   if(fullRange <= 0.0) return;
   
   if(InpZoneTrimThreshold > 0.0) {
      double zonePts = (zh - zl) / _Point;
      if(zonePts <= InpZoneTrimThreshold) return;
   }
   
   if(InpZoneTrimMode == ZTRIM_UPPER_WICK) {
      double bodyTop    = MathMax(candle_open, candle_close);
      double bodyBottom = MathMin(candle_open, candle_close);
      if(zone_type == -1) zh = bodyTop;
      else                zl = bodyBottom;
   }
   else if(InpZoneTrimMode == ZTRIM_PCT_CAP) {
      double keepRange = fullRange * (MathMax(0.0, MathMin(100.0, InpZoneTrimPct)) * 0.01);
      if(zone_type == -1) zh = zl + keepRange;
      else                zl = zh - keepRange;
   }
   if(zh < zl) { double tmp = zh; zh = zl; zl = tmp; }
}

//+------------------------------------------------------------------+
//| HTF Levels                                                       |
//+------------------------------------------------------------------+
void DeleteHTFObjects() {
   for(int i=ObjectsTotal(0)-1; i>=0; i--) {
      string n = ObjectName(0,i,0,-1);
      if(StringFind(n,g_HTFPrefix)==0) ObjectDelete(0,n);
   }
}

void DrawAllHTFLevels() {
   DeleteHTFObjects();
   TFConfig cfg[]; ArrayResize(cfg,2); int count=0;
   
   cfg[count].enabled=Inp4H_Enable; cfg[count].tf=PERIOD_H4; cfg[count].tfName="4H"; cfg[count].highClr=Inp4H_HighClr; cfg[count].lowClr=Inp4H_LowClr; cfg[count].width=Inp4H_Width; cfg[count].style=Inp4H_Style; count++;
   cfg[count].enabled=Inp1H_Enable; cfg[count].tf=PERIOD_H1; cfg[count].tfName="1H"; cfg[count].highClr=Inp1H_HighClr; cfg[count].lowClr=Inp1H_LowClr; cfg[count].width=Inp1H_Width; cfg[count].style=Inp1H_Style; count++;

   datetime lblT = TimeCurrent()+PeriodSeconds(Period());
   for(int t=0; t<count; t++) {
      if(!cfg[t].enabled) continue;
      if(PeriodSeconds(Period()) >= PeriodSeconds(cfg[t].tf)) continue;
      
      double htfH[1], htfL[1]; datetime htfT[1];
      if(CopyHigh(Symbol(),cfg[t].tf,1,1,htfH)<=0) continue;
      if(CopyLow(Symbol(),cfg[t].tf,1,1,htfL)<=0) continue;
      if(CopyTime(Symbol(),cfg[t].tf,1,1,htfT)<=0) continue;

      string hn = StringFormat("%s%s_High",g_HTFPrefix,cfg[t].tfName);
      string ln = StringFormat("%s%s_Low", g_HTFPrefix,cfg[t].tfName);

      ObjectCreate(0,hn,OBJ_TREND,0,htfT[0],htfH[0],htfT[0]+PeriodSeconds(Period()),htfH[0]);
      ObjectSetInteger(0,hn,OBJPROP_COLOR, cfg[t].highClr); ObjectSetInteger(0,hn,OBJPROP_WIDTH, cfg[t].width); ObjectSetInteger(0,hn,OBJPROP_STYLE, cfg[t].style); ObjectSetInteger(0,hn,OBJPROP_RAY_RIGHT, true); ObjectSetInteger(0,hn,OBJPROP_BACK, true);
      
      ObjectCreate(0,ln,OBJ_TREND,0,htfT[0],htfL[0],htfT[0]+PeriodSeconds(Period()),htfL[0]);
      ObjectSetInteger(0,ln,OBJPROP_COLOR, cfg[t].lowClr); ObjectSetInteger(0,ln,OBJPROP_WIDTH, cfg[t].width); ObjectSetInteger(0,ln,OBJPROP_STYLE, cfg[t].style); ObjectSetInteger(0,ln,OBJPROP_RAY_RIGHT, true); ObjectSetInteger(0,ln,OBJPROP_BACK, true);

      if(InpShowLabels) {
         string hTxt = InpShowPrice ? StringFormat("%s H  %.5f",cfg[t].tfName,htfH[0]) : StringFormat("%s H",cfg[t].tfName);
         string lTxt = InpShowPrice ? StringFormat("%s L  %.5f",cfg[t].tfName,htfL[0]) : StringFormat("%s L",cfg[t].tfName);
         
         ObjectCreate(0,hn+"_LBL",OBJ_TEXT,0,lblT,htfH[0]); ObjectSetString(0,hn+"_LBL",OBJPROP_TEXT, hTxt); ObjectSetInteger(0,hn+"_LBL",OBJPROP_COLOR, InpHTFLabelColor); ObjectSetInteger(0,hn+"_LBL",OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
         ObjectCreate(0,ln+"_LBL",OBJ_TEXT,0,lblT,htfL[0]); ObjectSetString(0,ln+"_LBL",OBJPROP_TEXT, lTxt); ObjectSetInteger(0,ln+"_LBL",OBJPROP_COLOR, InpHTFLabelColor); ObjectSetInteger(0,ln+"_LBL",OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      }
   }
}

//+------------------------------------------------------------------+
//| CHoCH Draw Line                                                  |
//+------------------------------------------------------------------+
void DrawCHoCHLine(const string name, datetime t1, double price, datetime t2, color clr, ENUM_LINE_STYLE style, int width, bool isBull) {
   if(ObjectFind(0,name)>=0) return;

   ObjectCreate(0,name,OBJ_TREND,0,t1,price,t2,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR, clr); ObjectSetInteger(0,name,OBJPROP_STYLE, style); ObjectSetInteger(0,name,OBJPROP_WIDTH, width);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT, false); ObjectSetInteger(0,name,OBJPROP_BACK, false); ObjectSetInteger(0,name,OBJPROP_SELECTABLE, false);

   datetime midTime = t1 + (datetime)((t2 - t1) / 2);
   double offset = InpChochTextOffset * _Point;
   double txtPrc = isBull ? price - offset : price + offset;
   string txtName = name + "_TXT";
   
   if(ObjectFind(0,txtName) < 0) {
      ObjectCreate(0,txtName,OBJ_TEXT,0,midTime,txtPrc);
      ObjectSetString(0,txtName,OBJPROP_TEXT, "CHoCH"); ObjectSetInteger(0,txtName,OBJPROP_COLOR, clr);
      ObjectSetInteger(0,txtName,OBJPROP_FONTSIZE, InpChochFontSize); ObjectSetString(0,txtName,OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0,txtName,OBJPROP_ANCHOR, isBull ? TextPosToAnchor(InpChochTextPos) : TextPosToAnchor(InpChochTextPosBear));
   }
}

//+------------------------------------------------------------------+
//| Dual Zone Draw (Main OB + PoI) with Midlines                     |
//+------------------------------------------------------------------+
void DrawDualZone(const string name, datetime t1, double p1, datetime t2, double p2, int zone_type, ENUM_TIMEFRAMES tf) {
   if(ObjectFind(0,name)>=0) return;

   double max_p = MathMax(p1,p2);
   double min_p = MathMin(p1,p2);
   double height = max_p - min_p;
   
   string mid_name     = "CHoCH_Mid_" + name;
   string lbl_name     = "CHoCH_Lbl_" + name;
   string poi_name     = "CHoCH_PoI_" + name;
   string poi_mid_name = "CHoCH_PoIMid_" + name;
   string poi_lbl_name = "CHoCH_PoILbl_" + name;
   
   color obClr  = (zone_type == -1) ? Inp_BZoneColor : Inp_SZoneColor;
   color poiClr = (zone_type == -1) ? Inp_PoIBullColor : Inp_PoIBearColor;

   // 1. Draw Main OB Zone & Midline
   ObjectCreate(0,name,OBJ_RECTANGLE,0,t1,max_p,t2,min_p);
   ObjectSetInteger(0,name,OBJPROP_COLOR, obClr); ObjectSetInteger(0,name,OBJPROP_BGCOLOR, obClr); 
   ObjectSetInteger(0,name,OBJPROP_BACK, true); ObjectSetInteger(0,name,OBJPROP_FILL, true); ObjectSetInteger(0,name,OBJPROP_SELECTABLE, false);

   double mid_p = min_p + height / 2.0;
   ObjectCreate(0, mid_name, OBJ_TREND, 0, t1, mid_p, t2, mid_p);
   ObjectSetInteger(0, mid_name, OBJPROP_COLOR, InpMidLineColor); ObjectSetInteger(0, mid_name, OBJPROP_STYLE, InpMidLineStyle);
   ObjectSetInteger(0, mid_name, OBJPROP_WIDTH, 1); ObjectSetInteger(0, mid_name, OBJPROP_RAY_RIGHT, false); 
   ObjectSetInteger(0, mid_name, OBJPROP_BACK, false); ObjectSetInteger(0, mid_name, OBJPROP_SELECTABLE, false);

   string txtOB = (zone_type == -1 ? "Buy Zone " : "Sell Zone ") + DoubleToString(max_p,_Digits) + " - " + DoubleToString(min_p,_Digits);
   ObjectCreate(0,lbl_name,OBJ_TEXT,0,t2,min_p);
   ObjectSetString(0,lbl_name,OBJPROP_TEXT, txtOB); ObjectSetInteger(0,lbl_name,OBJPROP_COLOR, InpZoneLabelColor); 
   ObjectSetInteger(0,lbl_name,OBJPROP_FONTSIZE, InpZoneFontSize); ObjectSetInteger(0,lbl_name,OBJPROP_ANCHOR, TextPosToAnchor(InpZoneLabelPos));

   // 2. Draw Reversal PoI Zone & Midline
   double poi_top=0, poi_bot=0;
   double offsetVal = InpPoIOffsetPoints * _Point;
   
   if(zone_type == -1) { 
      poi_top = min_p - offsetVal;
      poi_bot = poi_top - height;
   } else { 
      poi_bot = max_p + offsetVal;
      poi_top = poi_bot + height;
   }

   ObjectCreate(0,poi_name,OBJ_RECTANGLE,0,t1,poi_top,t2,poi_bot);
   ObjectSetInteger(0,poi_name,OBJPROP_COLOR, poiClr); ObjectSetInteger(0,poi_name,OBJPROP_BGCOLOR, poiClr); 
   ObjectSetInteger(0,poi_name,OBJPROP_BACK, true); ObjectSetInteger(0,poi_name,OBJPROP_FILL, true); ObjectSetInteger(0,poi_name,OBJPROP_SELECTABLE, false);

   double poi_mid_p = poi_bot + height / 2.0;
   ObjectCreate(0, poi_mid_name, OBJ_TREND, 0, t1, poi_mid_p, t2, poi_mid_p);
   ObjectSetInteger(0, poi_mid_name, OBJPROP_COLOR, InpMidLineColor); ObjectSetInteger(0, poi_mid_name, OBJPROP_STYLE, InpMidLineStyle);
   ObjectSetInteger(0, poi_mid_name, OBJPROP_WIDTH, 1); ObjectSetInteger(0, poi_mid_name, OBJPROP_RAY_RIGHT, false); 
   ObjectSetInteger(0, poi_mid_name, OBJPROP_BACK, false); ObjectSetInteger(0, poi_mid_name, OBJPROP_SELECTABLE, false);

   string txtPoI = "Reversal PoI " + DoubleToString(poi_top,_Digits) + " - " + DoubleToString(poi_bot,_Digits);
   ObjectCreate(0,poi_lbl_name,OBJ_TEXT,0,t2,poi_bot);
   ObjectSetString(0,poi_lbl_name,OBJPROP_TEXT, txtPoI); ObjectSetInteger(0,poi_lbl_name,OBJPROP_COLOR, InpZoneLabelColor); 
   ObjectSetInteger(0,poi_lbl_name,OBJPROP_FONTSIZE, InpZoneFontSize); ObjectSetInteger(0,poi_lbl_name,OBJPROP_ANCHOR, TextPosToAnchor(InpZoneLabelPos));

   // Save State
   int s = ArraySize(active_zones);
   ArrayResize(active_zones, s+1);
   active_zones[s].name          = name;
   active_zones[s].mid_name      = mid_name;
   active_zones[s].lbl_name      = lbl_name;
   active_zones[s].poi_name      = poi_name;
   active_zones[s].poi_mid_name  = poi_mid_name;
   active_zones[s].poi_lbl_name  = poi_lbl_name;
   active_zones[s].type          = zone_type;
   active_zones[s].high          = max_p;
   active_zones[s].low           = min_p;
   active_zones[s].tf            = tf;
}

//+------------------------------------------------------------------+
//| Auto-Cleanup Mitigated Zones                                     |
//+------------------------------------------------------------------+
void CleanupMitigatedZones(datetime current_time) {
   if(InpMitigatedExpiryMinutes <= 0) return; // Feature disabled
   
   int expiry_seconds = InpMitigatedExpiryMinutes * 60;
   
   for(int i = ArraySize(mitigated_zones) - 1; i >= 0; i--) {
      if(current_time - mitigated_zones[i].mitigated_time >= expiry_seconds) {
         
         // Delete all associated objects
         ObjectDelete(0, mitigated_zones[i].name);
         ObjectDelete(0, mitigated_zones[i].mid_name);
         ObjectDelete(0, mitigated_zones[i].lbl_name);
         ObjectDelete(0, mitigated_zones[i].poi_name);
         ObjectDelete(0, mitigated_zones[i].poi_mid_name);
         ObjectDelete(0, mitigated_zones[i].poi_lbl_name);
         
         // Remove from memory
         ArrayRemove(mitigated_zones, i, 1);
      }
   }
}

//+------------------------------------------------------------------+
//| Core CHoCH Logic                                                 |
//+------------------------------------------------------------------+
void ProcessCHoCH(const datetime &time[], const double &high[], const double &low[], const double &close[], int rates_total) {
   for(int t=0; t<2; t++) {
      if(!states[t].enable) continue;
      ENUM_TIMEFRAMES tf = (states[t].tf==PERIOD_CURRENT) ? Period() : states[t].tf;

      MqlRates rates[]; int copied = CopyRates(_Symbol, tf, 0, InpMaxBars, rates);
      int p = states[t].pivot;
      if(copied < p*2+1) continue;

      int limit = p*2;
      if(states[t].last_processed_time > 0) {
         for(int i=copied-1; i>=0; i--)
            if(rates[i].time == states[t].last_processed_time) { limit = MathMax(p*2, i-1); break; }
      }

      for(int i=limit; i<copied-1; i++) {
         int ci = i-p; if(ci < p) continue;

         bool isSH=true, isSL=true;
         for(int j=1; j<=p; j++) {
            if(isSH && (rates[ci].high<=rates[ci-j].high || rates[ci].high<=rates[ci+j].high)) isSH=false;
            if(isSL && (rates[ci].low >=rates[ci-j].low  || rates[ci].low >=rates[ci+j].low))  isSL=false;
            if(!isSH && !isSL) break;
         }

         if(isSH) { states[t].last_sh=rates[ci].high; states[t].last_sh_time=rates[ci].time; }
         if(isSL) { states[t].last_sl=rates[ci].low;  states[t].last_sl_time=rates[ci].time; }

         //--- Bullish CHoCH ---
         if(states[t].last_trend<=0 && states[t].last_sh>0 && rates[i].close>states[t].last_sh) {
            states[t].last_trend = 1;
            string chochName = "CHoCH_"+EnumToString(tf)+"_Bull_"+(string)(int)states[t].last_sh_time;
            DrawCHoCHLine(chochName, states[t].last_sh_time, states[t].last_sh, rates[i].time, states[t].bull_clr, states[t].style, states[t].width, true);

            int si=i; for(int k=i;k>=0;k--) if(rates[k].time<=states[t].last_sh_time){si=k;break;}
            int li=si; double minL=rates[si].low;
            for(int k=si;k<=i;k++) if(rates[k].low<minL){minL=rates[k].low;li=k;}

            double zh=rates[li].high, zl=rates[li].low;
            TrimLargeZone(zh,zl,rates[li].high,rates[li].low,rates[li].open,rates[li].close,-1);
            
            DrawDualZone("CHoCH_"+EnumToString(tf)+"_BZ_"+(string)(int)rates[i].time, rates[li].time, zh, rates[i].time, zl, -1, tf);
            states[t].last_sh = 0.0;
         }

         //--- Bearish CHoCH ---
         if(states[t].last_trend>=0 && states[t].last_sl>0 && rates[i].close<states[t].last_sl) {
            states[t].last_trend = -1;
            string chochName = "CHoCH_"+EnumToString(tf)+"_Bear_"+(string)(int)states[t].last_sl_time;
            DrawCHoCHLine(chochName, states[t].last_sl_time, states[t].last_sl, rates[i].time, states[t].bear_clr, states[t].style, states[t].width, false);

            int si=i; for(int k=i;k>=0;k--) if(rates[k].time<=states[t].last_sl_time){si=k;break;}
            int hi2=si; double maxH=rates[si].high;
            for(int k=si;k<=i;k++) if(rates[k].high>maxH){maxH=rates[k].high;hi2=k;}

            double zh=rates[hi2].high, zl=rates[hi2].low;
            TrimLargeZone(zh,zl,rates[hi2].high,rates[hi2].low,rates[hi2].open,rates[hi2].close,1);

            DrawDualZone("CHoCH_"+EnumToString(tf)+"_SZ_"+(string)(int)rates[i].time, rates[hi2].time, zh, rates[i].time, zl, 1, tf);
            states[t].last_sl = 0.0;
         }

         // Historic Mitigation Check
         for(int z=ArraySize(active_zones)-1; z>=0; z--) {
            if(active_zones[z].tf != tf) continue;
            bool mit = (active_zones[z].type== 1 && rates[i].close > active_zones[z].high) || (active_zones[z].type==-1 && rates[i].close < active_zones[z].low);
            if(mit) {
               // Update Box & Label Colors to Mitigated State
               ObjectSetInteger(0,active_zones[z].name,         OBJPROP_TIME, 1,rates[i].time);
               ObjectSetInteger(0,active_zones[z].name,         OBJPROP_COLOR, InpMitigatedColor);
               ObjectSetInteger(0,active_zones[z].lbl_name,     OBJPROP_COLOR, InpMitigatedColor);
               ObjectSetInteger(0,active_zones[z].poi_name,     OBJPROP_TIME, 1,rates[i].time);
               ObjectSetInteger(0,active_zones[z].poi_name,     OBJPROP_COLOR, InpMitigatedColor);
               ObjectSetInteger(0,active_zones[z].poi_lbl_name, OBJPROP_COLOR, InpMitigatedColor);
               
               // Update Midline Colors to Mitigated State
               ObjectSetInteger(0,active_zones[z].mid_name,     OBJPROP_TIME, 1,rates[i].time);
               ObjectSetInteger(0,active_zones[z].mid_name,     OBJPROP_COLOR, InpMitigatedColor);
               ObjectSetInteger(0,active_zones[z].poi_mid_name, OBJPROP_TIME, 1,rates[i].time);
               ObjectSetInteger(0,active_zones[z].poi_mid_name, OBJPROP_COLOR, InpMitigatedColor);

               // Store in Mitigated Zones array for auto-cleanup
               if(InpMitigatedExpiryMinutes > 0) {
                  int mz = ArraySize(mitigated_zones);
                  ArrayResize(mitigated_zones, mz + 1);
                  mitigated_zones[mz].name           = active_zones[z].name;
                  mitigated_zones[mz].mid_name       = active_zones[z].mid_name;
                  mitigated_zones[mz].lbl_name       = active_zones[z].lbl_name;
                  mitigated_zones[mz].poi_name       = active_zones[z].poi_name;
                  mitigated_zones[mz].poi_mid_name   = active_zones[z].poi_mid_name;
                  mitigated_zones[mz].poi_lbl_name   = active_zones[z].poi_lbl_name;
                  mitigated_zones[mz].mitigated_time = rates[i].time;
               }

               // Remove from Active Zones
               ArrayRemove(active_zones, z, 1);
            }
         }
      }
      if(copied>1) states[t].last_processed_time = rates[copied-2].time;
   }
}

//+------------------------------------------------------------------+
//| Extend Zones to Live Edge                                        |
//+------------------------------------------------------------------+
void ExtendZonesToLive(const datetime &time[], int rates_total) {
   int nz = ArraySize(active_zones); if(nz==0) return;
   datetime live_t = time[rates_total-1];
   
   for(int z=0; z<nz; z++) {
      ObjectSetInteger(0,active_zones[z].name,         OBJPROP_TIME,1,live_t);
      ObjectSetInteger(0,active_zones[z].mid_name,     OBJPROP_TIME,1,live_t);
      ObjectSetInteger(0,active_zones[z].lbl_name,     OBJPROP_TIME,0,live_t);
      ObjectSetInteger(0,active_zones[z].poi_name,     OBJPROP_TIME,1,live_t);
      ObjectSetInteger(0,active_zones[z].poi_mid_name, OBJPROP_TIME,1,live_t);
      ObjectSetInteger(0,active_zones[z].poi_lbl_name, OBJPROP_TIME,0,live_t);
   }
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit() {
   ObjectsDeleteAll(0,"CHoCH_");
   ArrayResize(active_zones, 0);
   ArrayResize(mitigated_zones, 0);

   states[0].enable=InpTF1Enable; states[0].tf=InpTF1; states[0].pivot=InpTF1PivotPeriod;
   states[0].bull_clr=InpTF1BullColor; states[0].bear_clr=InpTF1BearColor; states[0].style=InpTF1LineStyle; states[0].width=InpTF1LineWidth;

   states[1].enable=InpTF2Enable; states[1].tf=InpTF2; states[1].pivot=InpTF2PivotPeriod;
   states[1].bull_clr=InpTF2BullColor; states[1].bear_clr=InpTF2BearColor; states[1].style=InpTF2LineStyle; states[1].width=InpTF2LineWidth;

   DrawAllHTFLevels();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   DeleteHTFObjects();
   ObjectsDeleteAll(0,"CHoCH_");
}

//+------------------------------------------------------------------+
//| MAIN CALCULATE                                                   |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[], const long &tick_volume[], const long &volume[], const int &spread[]) {
   if(rates_total < 10) return 0;
   
   if(prev_calculated==0) {
      ObjectsDeleteAll(0,"CHoCH_");
      ArrayResize(active_zones, 0);
      ArrayResize(mitigated_zones, 0);
      for(int t=0;t<2;t++) {
         states[t].last_trend=0; states[t].last_sh=0.0; states[t].last_sl=0.0; 
         states[t].last_sh_time=0; states[t].last_sl_time=0; states[t].last_processed_time=0;
      }
   }

   if(time[rates_total-1] != g_LastBarTime) {
      g_LastBarTime = time[rates_total-1];
      DrawAllHTFLevels();
   }

   ProcessCHoCH(time, high, low, close, rates_total);
   ExtendZonesToLive(time, rates_total);
   
   // Clean up any mitigated zones that have expired based on current candle time
   CleanupMitigatedZones(time[rates_total-1]);

   return rates_total;
}
//+------------------------------------------------------------------+