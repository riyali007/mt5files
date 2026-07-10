//+------------------------------------------------------------------+
//|                                                      Suite_v1.mq5 |
//|  MultiMA + HTF High/Low + CHoCH/PoI Zones — Combined Suite       |
//|  v1.2 — Riy Tech                                                  |
//+------------------------------------------------------------------+
#property copyright   "Riy Tech"
#property link        ""
#property version     "1.20"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   1

#property indicator_label1  "MultiMA"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//+------------------------------------------------------------------+
//| ENUMS                                                             |
//+------------------------------------------------------------------+
enum ENUM_MULTI_MA
{
   MA_SMA    = 0,  // SMA  — Simple Moving Average
   MA_EMA    = 1,  // EMA  — Exponential Moving Average
   MA_WMA    = 2,  // WMA  — Weighted Moving Average
   MA_RMA    = 3,  // RMA  — Wilder's Smoothed Moving Average
   MA_HMA    = 4,  // HMA  — Hull Moving Average
   MA_VWAP   = 5,  // VWAP — Volume Weighted (rolling)
   MA_ALMA   = 6,  // ALMA — Arnaud Legoux Moving Average
   MA_TEMA   = 7,  // TEMA — Triple Exponential Moving Average
   MA_HULLMA = 8,  // HULLMA — Hull MA (WMA variant)
};

//+------------------------------------------------------------------+
//| =====================  MA INPUTS  ================================|
//+------------------------------------------------------------------+
input group "=== Moving Average ==="
input ENUM_MULTI_MA      InpMAType    = MA_EMA;
input int                InpPeriod    = 20;
input ENUM_APPLIED_PRICE InpPrice     = PRICE_CLOSE;

input group "=== ALMA Settings (ALMA only) ==="
input double             InpALMASigma  = 6.0;
input double             InpALMAOffset = 0.85;

input group "=== MA Visual ==="
input color              InpMAColor   = clrDodgerBlue;
input ENUM_LINE_STYLE    InpMAStyle   = STYLE_SOLID;
input int                InpMAWidth   = 2;

//+------------------------------------------------------------------+
//| =====================  HTF H/L INPUTS  ===========================|
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

input group "=== 30M High/Low ==="
input bool            Inp30M_Enable  = true;
input color           Inp30M_HighClr = clrRed;
input color           Inp30M_LowClr  = clrLime;
input int             Inp30M_Width   = 1;
input ENUM_LINE_STYLE Inp30M_Style   = STYLE_DASH;

input group "=== 15M High/Low ==="
input bool            Inp15M_Enable  = true;
input color           Inp15M_HighClr = clrRed;
input color           Inp15M_LowClr  = clrLime;
input int             Inp15M_Width   = 1;
input ENUM_LINE_STYLE Inp15M_Style   = STYLE_DASH;

input group "=== 5M High/Low ==="
input bool            Inp5M_Enable  = true;
input color           Inp5M_HighClr = clrRed;
input color           Inp5M_LowClr  = clrLime;
input int             Inp5M_Width   = 1;
input ENUM_LINE_STYLE Inp5M_Style   = STYLE_DOT;

input group "=== HTF Label Settings ==="
input bool            InpShowLabels    = true;
input int             InpFontSize      = 9;
input bool            InpShowPrice     = true;
input color           InpHTFLabelColor = clrWhite; // HTF Label Text Color

//+------------------------------------------------------------------+
//| =====================  CHoCH INPUTS  =============================|
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

input group "=== Zone Settings ==="
input int             InpMaxBars         = 3000;
input color           Inp_BZoneColor     = clrLightGreen;
input color           Inp_SZoneColor     = clrLightCoral;
input color           InpMidLineColor    = clrBlack;
input color           InpMitigatedColor  = clrDarkGray;
input color           InpZoneLabelColor  = clrBlack;   // Zone Label Text Color
input double          Inp_BZoneOffsetPct = 0.0;
input double          Inp_SZoneOffsetPct = 0.0;

input group "=== Alert Settings ==="
input bool            InpEnableAlerts      = true;
input string          InpSoundBullCHoCH    = "alert.wav";
input string          InpSoundBearCHoCH    = "alert.wav";
input string          InpSound_BZoneTop    = "alert.wav";
input string          InpSound_BZoneMid    = "alert.wav";
input string          InpSound_BZoneBottom = "alert.wav";
input string          InpSound_SZoneTop    = "alert.wav";
input string          InpSound_SZoneMid    = "alert.wav";
input string          InpSound_SZoneBottom = "alert.wav";

//+------------------------------------------------------------------+
//| MA BUFFERS                                                        |
//+------------------------------------------------------------------+
double BufMA[];      // INDICATOR_DATA   — plotted line
double BufCalc[];    // INDICATOR_CALCULATIONS — applied price / temp workspace

//+------------------------------------------------------------------+
//| GLOBAL — ALMA                                                     |
//+------------------------------------------------------------------+
double g_ALMAWeights[];
bool   g_ALMAReady = false;

//+------------------------------------------------------------------+
//| GLOBAL — SMA running sum cache (avoids O(N*P) per tick)          |
//+------------------------------------------------------------------+
double g_SMASum    = 0.0;
int    g_SMALast   = -1;

//+------------------------------------------------------------------+
//| HTF H/L STATE                                                     |
//+------------------------------------------------------------------+
string   g_HTFPrefix   = "HTFHL_";
datetime g_LastBarTime = 0;

struct TFConfig
{
   bool            enabled;
   ENUM_TIMEFRAMES tf;
   string          tfName;
   color           highClr;
   color           lowClr;
   int             width;
   ENUM_LINE_STYLE style;
};

//+------------------------------------------------------------------+
//| CHoCH STATE                                                       |
//+------------------------------------------------------------------+
struct ActiveZone
{
   string          name;
   string          mid_name;
   int             type;        // 1=Buy, -1=Sell
   double          high;
   double          low;
   double          mid;
   bool            high_alerted;
   bool            mid_alerted;
   bool            low_alerted;
   ENUM_TIMEFRAMES tf;
};
ActiveZone active_zones[];

struct TFState
{
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
int OnInit()
{
   SetIndexBuffer(0, BufMA,   INDICATOR_DATA);
   SetIndexBuffer(1, BufCalc, INDICATOR_CALCULATIONS);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR,  InpMAColor);
   PlotIndexSetInteger(0, PLOT_LINE_STYLE,  InpMAStyle);
   PlotIndexSetInteger(0, PLOT_LINE_WIDTH,  InpMAWidth);
   PlotIndexSetDouble (0, PLOT_EMPTY_VALUE, 0.0);

   IndicatorSetString(INDICATOR_SHORTNAME,
      StringFormat("%s(%d) | HTF HL | CHoCH v1.2", MATypeName(InpMAType), InpPeriod));

   // Pre-compute ALMA weights once — O(period) done here, not per tick
   if(InpMAType == MA_ALMA)
      ComputeALMAWeights();

   ObjectsDeleteAll(0, "CHoCH_");
   ArrayResize(active_zones, 0);

   states[0].enable=InpTF1Enable; states[0].tf=InpTF1; states[0].pivot=InpTF1PivotPeriod;
   states[0].bull_clr=InpTF1BullColor; states[0].bear_clr=InpTF1BearColor;
   states[0].style=InpTF1LineStyle;    states[0].width=InpTF1LineWidth;

   states[1].enable=InpTF2Enable; states[1].tf=InpTF2; states[1].pivot=InpTF2PivotPeriod;
   states[1].bull_clr=InpTF2BullColor; states[1].bear_clr=InpTF2BearColor;
   states[1].style=InpTF2LineStyle;    states[1].width=InpTF2LineWidth;

   DrawAllHTFLevels();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   DeleteHTFObjects();
   ObjectsDeleteAll(0, "CHoCH_");
}

//+------------------------------------------------------------------+
//|  ═══  MA HELPERS  ════════════════════════════════════════════════|
//+------------------------------------------------------------------+
string MATypeName(ENUM_MULTI_MA t)
{
   switch(t)
   {
      case MA_SMA:    return "SMA";   case MA_EMA:    return "EMA";
      case MA_WMA:    return "WMA";   case MA_RMA:    return "RMA";
      case MA_HMA:    return "HMA";   case MA_VWAP:   return "VWAP";
      case MA_ALMA:   return "ALMA";  case MA_TEMA:   return "TEMA";
      case MA_HULLMA: return "HULLMA";
   }
   return "MA";
}

double GetPrice(const double &open[], const double &high[],
                const double &low[],  const double &close[], int i)
{
   switch(InpPrice)
   {
      case PRICE_OPEN:     return open[i];
      case PRICE_HIGH:     return high[i];
      case PRICE_LOW:      return low[i];
      case PRICE_CLOSE:    return close[i];
      case PRICE_MEDIAN:   return (high[i]+low[i])*0.5;
      case PRICE_TYPICAL:  return (high[i]+low[i]+close[i])*(1.0/3.0);
      case PRICE_WEIGHTED: return (high[i]+low[i]+close[i]*2.0)*0.25;
   }
   return close[i];
}

// Sliding-window SMA — O(1) per bar after first call (cached running sum)
// Only valid when called sequentially i = start..rates_total-1
double CalcSMASlidingInit(int from, int period)
{
   g_SMASum = 0.0;
   for(int k = from-period+1; k <= from; k++) g_SMASum += BufCalc[k];
   g_SMALast = from;
   return g_SMASum / period;
}
double CalcSMASliding(int i, int period)
{
   // Advance the window by one bar — drop oldest, add newest
   g_SMASum += BufCalc[i] - BufCalc[i-period];
   g_SMALast = i;
   return g_SMASum / period;
}

// WMA — closed-form denominator, single forward pass
double CalcWMADirect(const double &src[], int i, int period)
{
   if(i < period-1) return 0.0;
   double sum  = 0.0;
   int    base = i-period+1;
   for(int k=0; k<period; k++) sum += src[base+k]*(double)(k+1);
   return sum / ((double)period*(period+1)*0.5);
}

// VWAP rolling — O(period) but unavoidable; no shortcut without extra buffers
// Kept as-is, only called when MA_VWAP is selected

// ALMA — weights pre-computed once in ComputeALMAWeights()
void ComputeALMAWeights()
{
   int period = MathMax(InpPeriod,2);
   ArrayResize(g_ALMAWeights, period);
   double m=InpALMAOffset*(period-1), s=period/InpALMASigma, wsum=0.0;
   for(int j=0;j<period;j++) { g_ALMAWeights[j]=MathExp(-((j-m)*(j-m))/(2.0*s*s)); wsum+=g_ALMAWeights[j]; }
   if(wsum!=0.0) for(int j=0;j<period;j++) g_ALMAWeights[j]/=wsum;
   g_ALMAReady=true;
}

//+------------------------------------------------------------------+
//|  ═══  HTF H/L HELPERS  ═══════════════════════════════════════════|
//+------------------------------------------------------------------+
void DeleteHTFObjects()
{
   int total=ObjectsTotal(0,0,-1);
   for(int i=total-1;i>=0;i--)
   {
      string n=ObjectName(0,i,0,-1);
      if(StringFind(n,g_HTFPrefix)==0) ObjectDelete(0,n);
   }
}

void BuildHTFConfigs(TFConfig &cfg[], int &count)
{
   ArrayResize(cfg,5); count=0;
   TFConfig c;
   c.enabled=Inp4H_Enable;  c.tf=PERIOD_H4;  c.tfName="4H";  c.highClr=Inp4H_HighClr;  c.lowClr=Inp4H_LowClr;  c.width=Inp4H_Width;  c.style=Inp4H_Style;  cfg[count++]=c;
   c.enabled=Inp1H_Enable;  c.tf=PERIOD_H1;  c.tfName="1H";  c.highClr=Inp1H_HighClr;  c.lowClr=Inp1H_LowClr;  c.width=Inp1H_Width;  c.style=Inp1H_Style;  cfg[count++]=c;
   c.enabled=Inp30M_Enable; c.tf=PERIOD_M30; c.tfName="30M"; c.highClr=Inp30M_HighClr; c.lowClr=Inp30M_LowClr; c.width=Inp30M_Width; c.style=Inp30M_Style; cfg[count++]=c;
   c.enabled=Inp15M_Enable; c.tf=PERIOD_M15; c.tfName="15M"; c.highClr=Inp15M_HighClr; c.lowClr=Inp15M_LowClr; c.width=Inp15M_Width; c.style=Inp15M_Style; cfg[count++]=c;
   c.enabled=Inp5M_Enable;  c.tf=PERIOD_M5;  c.tfName="5M";  c.highClr=Inp5M_HighClr;  c.lowClr=Inp5M_LowClr;  c.width=Inp5M_Width;  c.style=Inp5M_Style;  cfg[count++]=c;
}

void DrawHTFRay(const string name, datetime t, double price,
                color clr, int width, ENUM_LINE_STYLE style)
{
   if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
   ObjectCreate(0,name,OBJ_TREND,0,t,price,t+PeriodSeconds(Period()),price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,     clr);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,     width);
   ObjectSetInteger(0,name,OBJPROP_STYLE,     style);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,  false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,    true);
   ObjectSetInteger(0,name,OBJPROP_BACK,      true);
}

void DrawHTFLabel(const string name, datetime t, double price,
                  const string text, bool isHigh)
{
   if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
   ObjectCreate(0,name,OBJ_TEXT,0,t,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,      InpHTFLabelColor);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,   InpFontSize);
   ObjectSetString (0,name,OBJPROP_FONT,       "Arial Bold");
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,     isHigh ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_BACK,       false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,     true);
   ObjectSetString (0,name,OBJPROP_TEXT,       text);
}

string BuildHTFLabel(const string tfName, const string hl, double price)
{
   return InpShowPrice ? StringFormat("%s %s  %.5f",tfName,hl,price)
                       : StringFormat("%s %s",tfName,hl);
}

void DrawAllHTFLevels()
{
   DeleteHTFObjects();
   TFConfig cfg[]; int count=0;
   BuildHTFConfigs(cfg,count);
   datetime lblT = TimeCurrent()+PeriodSeconds(Period());

   for(int t=0;t<count;t++)
   {
      if(!cfg[t].enabled) continue;
      if(PeriodSeconds(Period()) >= PeriodSeconds(cfg[t].tf)) continue;

      double htfH[1], htfL[1]; datetime htfT[1];
      if(CopyHigh(Symbol(),cfg[t].tf,1,1,htfH)<=0) continue;
      if(CopyLow (Symbol(),cfg[t].tf,1,1,htfL)<=0) continue;
      if(CopyTime(Symbol(),cfg[t].tf,1,1,htfT)<=0) continue;

      string hn=StringFormat("%s%s_High",g_HTFPrefix,cfg[t].tfName);
      string ln=StringFormat("%s%s_Low", g_HTFPrefix,cfg[t].tfName);

      DrawHTFRay(hn,htfT[0],htfH[0],cfg[t].highClr,cfg[t].width,cfg[t].style);
      DrawHTFRay(ln,htfT[0],htfL[0],cfg[t].lowClr, cfg[t].width,cfg[t].style);

      if(InpShowLabels)
      {
         DrawHTFLabel(hn+"_LBL",lblT,htfH[0],BuildHTFLabel(cfg[t].tfName,"H",htfH[0]),true);
         DrawHTFLabel(ln+"_LBL",lblT,htfL[0],BuildHTFLabel(cfg[t].tfName,"L",htfL[0]),false);
      }
   }
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//|  ═══  CHoCH HELPERS  ═════════════════════════════════════════════|
//+------------------------------------------------------------------+
void DrawCHoCHLine(const string name, datetime t1, double price,
                   datetime t2, color clr, ENUM_LINE_STYLE style, int width)
{
   if(ObjectFind(0,name)>=0) return; // already exists — skip
   ObjectCreate(0,name,OBJ_TREND,0,t1,price,t2,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,     clr);
   ObjectSetInteger(0,name,OBJPROP_STYLE,     style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,     width);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0,name,OBJPROP_BACK,      false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetString (0,name,OBJPROP_TOOLTIP,   "CHoCH");
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,    true);
}

void DrawZone(const string name, datetime t1, double p1, datetime t2, double p2,
              color clr, const string tooltip, int zone_type, ENUM_TIMEFRAMES tf)
{
   if(ObjectFind(0,name)>=0) return; // already exists — skip

   double max_p = MathMax(p1,p2);
   double min_p = MathMin(p1,p2);
   double mid_p = min_p+(max_p-min_p)*0.5;
   string mid_name = "CHoCH_Mid_"+name;
   string lbl_name = "CHoCH_Lbl_"+name;

   // Zone rectangle
   ObjectCreate(0,name,OBJ_RECTANGLE,0,t1,max_p,t2,min_p);
   ObjectSetInteger(0,name,OBJPROP_COLOR,      clr);
   ObjectSetInteger(0,name,OBJPROP_BACK,       true);
   ObjectSetInteger(0,name,OBJPROP_FILL,       true);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,     false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE, false);
   ObjectSetString (0,name,OBJPROP_TOOLTIP,    tooltip);

   // Midline
   ObjectCreate(0,mid_name,OBJ_TREND,0,t1,mid_p,t2,mid_p);
   ObjectSetInteger(0,mid_name,OBJPROP_COLOR,      InpMidLineColor);
   ObjectSetInteger(0,mid_name,OBJPROP_STYLE,      STYLE_DOT);
   ObjectSetInteger(0,mid_name,OBJPROP_WIDTH,      1);
   ObjectSetInteger(0,mid_name,OBJPROP_RAY_RIGHT,  false);
   ObjectSetInteger(0,mid_name,OBJPROP_BACK,       false);
   ObjectSetInteger(0,mid_name,OBJPROP_HIDDEN,     false);
   ObjectSetInteger(0,mid_name,OBJPROP_SELECTABLE, false);
   ObjectSetString (0,mid_name,OBJPROP_TOOLTIP,    tooltip+" Midline");

   // Zone text label
   ObjectCreate(0,lbl_name,OBJ_TEXT,0,t1,max_p);
   ObjectSetString (0,lbl_name,OBJPROP_TEXT,       tooltip);
   ObjectSetInteger(0,lbl_name,OBJPROP_COLOR,      InpZoneLabelColor);
   ObjectSetInteger(0,lbl_name,OBJPROP_FONTSIZE,   8);
   ObjectSetString (0,lbl_name,OBJPROP_FONT,       "Arial Bold");
   ObjectSetInteger(0,lbl_name,OBJPROP_ANCHOR,     ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,lbl_name,OBJPROP_BACK,       false);
   ObjectSetInteger(0,lbl_name,OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0,lbl_name,OBJPROP_HIDDEN,     false);

   // Register in active zones array
   int s=ArraySize(active_zones);
   ArrayResize(active_zones,s+1);
   active_zones[s].name         = name;
   active_zones[s].mid_name     = mid_name;
   active_zones[s].type         = zone_type;
   active_zones[s].high         = max_p;
   active_zones[s].low          = min_p;
   active_zones[s].mid          = mid_p;
   active_zones[s].tf           = tf;
   active_zones[s].high_alerted = false;
   active_zones[s].mid_alerted  = false;
   active_zones[s].low_alerted  = false;
}

//+------------------------------------------------------------------+
//|  ═══  CHoCH PROCESSING  ══════════════════════════════════════════|
//+------------------------------------------------------------------+
void ProcessCHoCH(const datetime &time[], const double &high[],
                  const double &low[],   const double &close[],
                  int rates_total)
{
   for(int t=0; t<2; t++)
   {
      if(!states[t].enable) continue;

      ENUM_TIMEFRAMES tf = (states[t].tf==PERIOD_CURRENT) ? Period() : states[t].tf;

      MqlRates rates[];
      int copied = CopyRates(_Symbol,tf,0,InpMaxBars,rates);
      int p = states[t].pivot;
      if(copied < p*2+1) continue;

      // Incremental: only reprocess from the last known bar (minus pivot look-back)
      int limit = p*2; // default full scan starting point
      if(states[t].last_processed_time > 0)
      {
         for(int i=copied-1; i>=0; i--)
            if(rates[i].time == states[t].last_processed_time) { limit = MathMax(p*2, i-1); break; }
      }

      for(int i=limit; i<copied-1; i++)
      {
         int ci = i-p;
         if(ci < p) continue;

         // Swing detection — short-circuit on first disqualifying bar
         bool isSH=true, isSL=true;
         for(int j=1; j<=p; j++)
         {
            if(isSH && (rates[ci].high<=rates[ci-j].high || rates[ci].high<=rates[ci+j].high)) isSH=false;
            if(isSL && (rates[ci].low >=rates[ci-j].low  || rates[ci].low >=rates[ci+j].low))  isSL=false;
            if(!isSH && !isSL) break; // both disqualified — exit early
         }

         if(isSH) { states[t].last_sh=rates[ci].high; states[t].last_sh_time=rates[ci].time; }
         if(isSL) { states[t].last_sl=rates[ci].low;  states[t].last_sl_time=rates[ci].time; }

         //--- Bullish CHoCH ---
         if(states[t].last_trend<=0 && states[t].last_sh>0 && rates[i].close>states[t].last_sh)
         {
            states[t].last_trend=1;
            DrawCHoCHLine("CHoCH_"+EnumToString(tf)+"_Bull_"+(string)(int)rates[i].time,
                          states[t].last_sh_time, states[t].last_sh, rates[i].time,
                          states[t].bull_clr, states[t].style, states[t].width);

            if(InpEnableAlerts && i==copied-2 && rates[i].time>states[t].last_choch_alert_time)
            { Alert(Symbol()+" "+EnumToString(tf)+": Bullish CHoCH"); PlaySound(InpSoundBullCHoCH); states[t].last_choch_alert_time=rates[i].time; }

            // Find lowest low between last_sh_time and now
            int si=i;
            for(int k=i;k>=0;k--) if(rates[k].time<=states[t].last_sh_time){si=k;break;}
            int li=si; double minL=rates[si].low;
            for(int k=si;k<=i;k++) if(rates[k].low<minL){minL=rates[k].low;li=k;}

            double zh=rates[li].high, zl=rates[li].low;
            double off=(zh-zl)*(Inp_BZoneOffsetPct*0.01); zh+=off; zl+=off;

            DrawZone("CHoCH_"+EnumToString(tf)+"_BZ_"+(string)(int)rates[i].time,
                     rates[li].time,zh,rates[i].time,zl,Inp_BZoneColor,"Buy Zone",-1,tf);
            states[t].last_sh=0.0;
         }

         //--- Bearish CHoCH ---
         if(states[t].last_trend>=0 && states[t].last_sl>0 && rates[i].close<states[t].last_sl)
         {
            states[t].last_trend=-1;
            DrawCHoCHLine("CHoCH_"+EnumToString(tf)+"_Bear_"+(string)(int)rates[i].time,
                          states[t].last_sl_time, states[t].last_sl, rates[i].time,
                          states[t].bear_clr, states[t].style, states[t].width);

            if(InpEnableAlerts && i==copied-2 && rates[i].time>states[t].last_choch_alert_time)
            { Alert(Symbol()+" "+EnumToString(tf)+": Bearish CHoCH"); PlaySound(InpSoundBearCHoCH); states[t].last_choch_alert_time=rates[i].time; }

            // Find highest high between last_sl_time and now
            int si=i;
            for(int k=i;k>=0;k--) if(rates[k].time<=states[t].last_sl_time){si=k;break;}
            int hi=si; double maxH=rates[si].high;
            for(int k=si;k<=i;k++) if(rates[k].high>maxH){maxH=rates[k].high;hi=k;}

            double zh=rates[hi].high, zl=rates[hi].low;
            double off=(zh-zl)*(Inp_SZoneOffsetPct*0.01); zh+=off; zl+=off;

            DrawZone("CHoCH_"+EnumToString(tf)+"_SZ_"+(string)(int)rates[i].time,
                     rates[hi].time,zh,rates[i].time,zl,Inp_SZoneColor,"Sell Zone",1,tf);
            states[t].last_sl=0.0;
         }

         // Historic mitigation — only scan zones owned by this TF
         for(int z=ArraySize(active_zones)-1; z>=0; z--)
         {
            if(active_zones[z].tf!=tf) continue;
            bool mit=(active_zones[z].type== 1 && rates[i].close>active_zones[z].high)
                    ||(active_zones[z].type==-1 && rates[i].close<active_zones[z].low);
            if(mit)
            {
               ObjectSetInteger(0,active_zones[z].name,    OBJPROP_TIME, 1,rates[i].time);
               ObjectSetInteger(0,active_zones[z].mid_name, OBJPROP_TIME,1,rates[i].time);
               ObjectSetInteger(0,active_zones[z].name,    OBJPROP_COLOR,  InpMitigatedColor);
               ObjectSetInteger(0,active_zones[z].mid_name, OBJPROP_COLOR, InpMitigatedColor);
               ArrayRemove(active_zones,z,1);
            }
         }
      }
      if(copied>1) states[t].last_processed_time=rates[copied-2].time;
   }
}

//+------------------------------------------------------------------+
void ExtendZonesAndAlerts(const datetime &time[], const double &high[],
                          const double &low[], int rates_total)
{
   int nz = ArraySize(active_zones);
   if(nz==0) return;

   datetime live_t = time[rates_total-1];
   double   live_h = high[rates_total-1];
   double   live_l = low[rates_total-1];

   for(int z=0; z<nz; z++)
   {
      // Extend zone rectangle and midline right edge to current bar
      ObjectSetInteger(0,active_zones[z].name,     OBJPROP_TIME,1,live_t);
      ObjectSetInteger(0,active_zones[z].mid_name,  OBJPROP_TIME,1,live_t);

      if(!InpEnableAlerts) continue;
      string tfs=EnumToString(active_zones[z].tf);

      if(active_zones[z].type==-1) // SELL ZONE — price entering from above
      {
         if(!active_zones[z].high_alerted && live_l<=active_zones[z].high && live_h>=active_zones[z].high)
         { Alert(Symbol()+" "+tfs+": Tapped Top of Buy Zone");    PlaySound(InpSound_SZoneTop);    active_zones[z].high_alerted=true; }
         if(!active_zones[z].mid_alerted  && live_l<=active_zones[z].mid  && live_h>=active_zones[z].mid)
         { Alert(Symbol()+" "+tfs+": Tapped Mid of Buy Zone");    PlaySound(InpSound_SZoneMid);    active_zones[z].mid_alerted=true;  }
         if(!active_zones[z].low_alerted  && live_l<=active_zones[z].low  && live_h>=active_zones[z].low)
         { Alert(Symbol()+" "+tfs+": Tapped Bottom of Buy Zone"); PlaySound(InpSound_SZoneBottom); active_zones[z].low_alerted=true;  }
      }
      else // BUY ZONE — price entering from below
      {
         if(!active_zones[z].high_alerted && live_l<=active_zones[z].high && live_h>=active_zones[z].high)
         { Alert(Symbol()+" "+tfs+": Tapped Top of Sell Zone");    PlaySound(InpSound_BZoneTop);    active_zones[z].high_alerted=true; }
         if(!active_zones[z].mid_alerted  && live_l<=active_zones[z].mid  && live_h>=active_zones[z].mid)
         { Alert(Symbol()+" "+tfs+": Tapped Mid of Sell Zone");    PlaySound(InpSound_BZoneMid);    active_zones[z].mid_alerted=true;  }
         if(!active_zones[z].low_alerted  && live_l<=active_zones[z].low  && live_h>=active_zones[z].low)
         { Alert(Symbol()+" "+tfs+": Tapped Bottom of Sell Zone"); PlaySound(InpSound_BZoneBottom); active_zones[z].low_alerted=true;  }
      }
   }
}

//+------------------------------------------------------------------+
//|  ═══  MAIN CALCULATE  ════════════════════════════════════════════|
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
{
   if(rates_total < 10) return 0;

   // CHoCH full reset on first run
   if(prev_calculated==0)
   {
      ObjectsDeleteAll(0,"CHoCH_");
      ArrayResize(active_zones,0);
      for(int t=0;t<2;t++)
      {
         states[t].last_trend=0;        states[t].last_sh=0.0;
         states[t].last_sl=0.0;         states[t].last_sh_time=0;
         states[t].last_sl_time=0;      states[t].last_choch_alert_time=0;
         states[t].last_processed_time=0;
      }
   }

   // HTF H/L — redraw only on new bar (not every tick)
   if(time[rates_total-1] != g_LastBarTime)
   {
      g_LastBarTime = time[rates_total-1];
      DrawAllHTFLevels();
   }

   // CHoCH (incremental — skips already-processed bars)
   ProcessCHoCH(time,high,low,close,rates_total);

   // Extend zones + tick alerts
   ExtendZonesAndAlerts(time,high,low,rates_total);

   //================================================================
   //  MA CALCULATION
   //================================================================
   if(rates_total < InpPeriod) return 0;
   int period = MathMax(InpPeriod,2);
   int start  = (prev_calculated>1) ? prev_calculated-1 : 0;

   // Fill applied price buffer
   for(int i=start; i<rates_total; i++)
      BufCalc[i] = GetPrice(open,high,low,close,i);

   switch(InpMAType)
   {
      //--- SMA — sliding window O(1) per bar ---
      case MA_SMA:
      {
         if(start < period-1)
         {
            for(int i=0; i<period-1 && i<rates_total; i++) BufMA[i]=0.0;
            if(rates_total >= period)
            {
               BufMA[period-1] = CalcSMASlidingInit(period-1, period);
               for(int i=period; i<rates_total; i++)
                  BufMA[i] = CalcSMASliding(i, period);
            }
         }
         else
         {
            // Incremental: re-init window at start-1 then slide forward
            if(start >= period) CalcSMASlidingInit(start-1, period);
            for(int i=start; i<rates_total; i++)
               BufMA[i] = (i<period-1) ? 0.0 : CalcSMASliding(i, period);
         }
         break;
      }

      //--- EMA — O(1) per bar, already optimal ---
      case MA_EMA:
      {
         double k=2.0/(period+1.0);
         if(start==0)
         {
            for(int i=0;i<period-1;i++) BufMA[i]=0.0;
            // Seed with first SMA
            double s=0.0; for(int k2=0;k2<period;k2++) s+=BufCalc[k2];
            BufMA[period-1]=s/period;
            for(int i=period;i<rates_total;i++) BufMA[i]=BufCalc[i]*k+BufMA[i-1]*(1.0-k);
         }
         else for(int i=start;i<rates_total;i++) BufMA[i]=BufCalc[i]*k+BufMA[i-1]*(1.0-k);
         break;
      }

      //--- WMA ---
      case MA_WMA:
         for(int i=start;i<rates_total;i++)
            BufMA[i] = CalcWMADirect(BufCalc,i,period);
         break;

      //--- RMA (Wilder's) ---
      case MA_RMA:
      {
         double alpha=1.0/period;
         if(start==0)
         {
            for(int i=0;i<period-1;i++) BufMA[i]=0.0;
            double s=0.0; for(int k2=0;k2<period;k2++) s+=BufCalc[k2];
            BufMA[period-1]=s/period;
            for(int i=period;i<rates_total;i++) BufMA[i]=BufCalc[i]*alpha+BufMA[i-1]*(1.0-alpha);
         }
         else for(int i=start;i<rates_total;i++) BufMA[i]=BufCalc[i]*alpha+BufMA[i-1]*(1.0-alpha);
         break;
      }

      //--- HMA / HULLMA ---
      case MA_HMA:
      case MA_HULLMA:
      {
         int halfP=(int)MathFloor(period*0.5); if(halfP<1) halfP=1;
         int sqrtP=(int)MathRound(MathSqrt((double)period)); if(sqrtP<1) sqrtP=1;

         // Intermediate hull series stored in BufMA temporarily, then overwritten
         // Use a separate array only for the hull intermediate values
         static double tmpHull[];
         if(ArraySize(tmpHull) < rates_total) ArrayResize(tmpHull,rates_total);

         for(int i=period-1;i<rates_total;i++)
            tmpHull[i] = 2.0*CalcWMADirect(BufCalc,i,halfP) - CalcWMADirect(BufCalc,i,period);

         // Final WMA of tmpHull over sqrtP
         int hs=period-1+sqrtP-1;
         for(int i=0;i<hs&&i<rates_total;i++) BufMA[i]=0.0;
         for(int i=hs;i<rates_total;i++)       BufMA[i]=CalcWMADirect(tmpHull,i,sqrtP);
         break;
      }

      //--- VWAP (rolling) ---
      case MA_VWAP:
         for(int i=start;i<rates_total;i++)
         {
            if(i<period-1){BufMA[i]=0.0;continue;}
            double tpv=0.0,vol=0.0;
            for(int k=i-period+1;k<=i;k++)
            {
               double v=(double)tick_volume[k]; if(v<=0.0)v=1.0;
               tpv+=(high[k]+low[k]+close[k])*(1.0/3.0)*v;
               vol+=v;
            }
            BufMA[i]=(vol>0.0)?tpv/vol:0.0;
         }
         break;

      //--- ALMA (pre-computed weights) ---
      case MA_ALMA:
         if(!g_ALMAReady) ComputeALMAWeights();
         for(int i=start;i<rates_total;i++)
         {
            if(i<period-1){BufMA[i]=0.0;continue;}
            double val=0.0;
            int base=i-period+1;
            for(int j=0;j<period;j++) val+=g_ALMAWeights[j]*BufCalc[base+j];
            BufMA[i]=val;
         }
         break;

      //--- TEMA — Triple EMA ---
      case MA_TEMA:
      {
         double k=2.0/(period+1.0);
         // Use static arrays — avoids heap reallocation on every tick
         static double ema1[], ema2[], ema3[];
         if(ArraySize(ema1)<rates_total){ ArrayResize(ema1,rates_total); ArrayInitialize(ema1,0.0); }
         if(ArraySize(ema2)<rates_total){ ArrayResize(ema2,rates_total); ArrayInitialize(ema2,0.0); }
         if(ArraySize(ema3)<rates_total){ ArrayResize(ema3,rates_total); ArrayInitialize(ema3,0.0); }

         if(start==0)
         {
            for(int i=0;i<period-1;i++) ema1[i]=0.0;
            double s=0.0; for(int k2=0;k2<period;k2++) s+=BufCalc[k2];
            ema1[period-1]=s/period;
            for(int i=period;i<rates_total;i++) ema1[i]=BufCalc[i]*k+ema1[i-1]*(1.0-k);
         }
         else { ema1[start-1]=BufMA[start-1]; for(int i=start;i<rates_total;i++) ema1[i]=BufCalc[i]*k+ema1[i-1]*(1.0-k); }

         int s2=2*(period-1);
         if(s2<rates_total)
         {
            if(ema2[s2]==0.0){ double ss=0.0; for(int j=s2-(period-1);j<=s2;j++) ss+=ema1[j]; ema2[s2]=ss/period; }
            for(int i=(start>s2?start:s2)+1;i<rates_total;i++) ema2[i]=ema1[i]*k+ema2[i-1]*(1.0-k);
         }
         int s3=3*(period-1);
         if(s3<rates_total)
         {
            if(ema3[s3]==0.0){ double ss=0.0; for(int j=s3-(period-1);j<=s3;j++) ss+=ema2[j]; ema3[s3]=ss/period; }
            for(int i=(start>s3?start:s3)+1;i<rates_total;i++) ema3[i]=ema2[i]*k+ema3[i-1]*(1.0-k);
         }
         for(int i=(start>s3?start:0);i<rates_total;i++)
            BufMA[i]=(ema3[i]==0.0)?0.0:3.0*ema1[i]-3.0*ema2[i]+ema3[i];
         break;
      }
   }

   return rates_total;
}
//+------------------------------------------------------------------+