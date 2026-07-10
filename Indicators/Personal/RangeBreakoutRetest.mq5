
//+------------------------------------------------------------------+
//|  Range Breakout & Retest (RBR) - MT5 v7 - Clean rebuild          |
//+------------------------------------------------------------------+
#property copyright   "RBR MT5"
#property version     "1.00"
#property indicator_chart_window
#property indicator_plots 0

input int    InpMinInside  = 4;    // Min Candles Inside Range
input int    InpMaxInside  = 10;   // Max Candles Inside Range
input int    InpSizeMode   = 1;    // 0=Fixed 1=ATR 2=Both
input double InpMaxPips    = 500;  // Max Range (pips)
input int    InpAtrLen     = 14;   // ATR Length
input double InpAtrMult    = 3.0;  // Max Range (ATR x)  <-- generous default
input int    InpMinRetest  = 1;    // Retest Min Bars
input int    InpMaxRetest  = 10;   // Retest Max Bars
input bool   InpBiasOn     = true; // Enable Bias Filter
input double InpStrongPct  = 70.0; // Strong Close %
input bool   InpShowBox    = true;
input bool   InpShowBreak  = true;
input bool   InpShowRetest = true;
input bool   InpShowSignal = true;
input bool   InpShowBias   = true;
input bool   InpShowMid    = true;
input color  InpColBull    = C'0,120,80';
input color  InpColBear    = C'160,20,35';
input color  InpColRetest  = C'160,110,0';
input color  InpColActive  = C'10,35,100';
input color  InpColMidNeut = C'60,60,60';

// States
#define ST_ACCUM   0
#define ST_CONF    1
#define ST_BROKEN  2
#define ST_RETEST  3
#define ST_DONE    4
#define ST_INVALID -1

int    g_state      = ST_INVALID;
double g_hi         = 0;
double g_lo         = 0;
int    g_patBar     = -1;
int    g_breakBar   = -1;
int    g_insideCount= 0;
int    g_biasScore  = 0;
bool   g_brokeUp    = false;
string g_boxName    = "";
string g_midName    = "";
int    g_hATR       = INVALID_HANDLE;
int    g_seq        = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   g_hATR  = iATR(_Symbol, PERIOD_CURRENT, InpAtrLen);
   if(g_hATR==INVALID_HANDLE){ Print("ATR fail"); return INIT_FAILED; }
   g_state = ST_INVALID;
   g_seq   = 0;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0,"RBR_");
   if(g_hATR!=INVALID_HANDLE) IndicatorRelease(g_hATR);
}

//--- object helpers
string N(string p){ return "RBR_"+p+"_"+IntegerToString(g_seq++); }

void Box(string &nm,datetime t1,double h,datetime t2,double l,color c)
{
   nm=N("B");
   ObjectCreate(0,nm,OBJ_RECTANGLE,0,t1,h,t2,l);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,c);
   ObjectSetInteger(0,nm,OBJPROP_FILL,true);
   ObjectSetInteger(0,nm,OBJPROP_BACK,true);
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
}
void Mid(string &nm,datetime t1,double m,datetime t2,color c)
{
   nm=N("M");
   ObjectCreate(0,nm,OBJ_TREND,0,t1,m,t2,m);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,c);
   ObjectSetInteger(0,nm,OBJPROP_STYLE,STYLE_DASH);
   ObjectSetInteger(0,nm,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
}
void Lbl(datetime t,double p,string tx,color c,bool up)
{
   string nm=N("L");
   ObjectCreate(0,nm,OBJ_TEXT,0,t,p);
   ObjectSetString (0,nm,OBJPROP_TEXT,tx);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,c);
   ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,10);
   ObjectSetInteger(0,nm,OBJPROP_ANCHOR,up?ANCHOR_LOWER:ANCHOR_UPPER);
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
}
void BoxRight(string nm,datetime t){ if(nm!="") ObjectSetInteger(0,nm,OBJPROP_TIME,1,t); }
void BoxCol  (string nm,color c)   { if(nm!="") ObjectSetInteger(0,nm,OBJPROP_COLOR,c); }
void MidRC   (string nm,datetime t,color c)
{ if(nm!=""){ ObjectSetInteger(0,nm,OBJPROP_TIME,1,t); ObjectSetInteger(0,nm,OBJPROP_COLOR,c); } }
void DelNm   (string &nm){ if(nm!=""){ ObjectDelete(0,nm); nm=""; } }

color  BClr(int s){ return s>0?InpColBull:s<0?InpColBear:InpColMidNeut; }
string BTxt(int s){ return s>0?"Bias:Bull":s<0?"Bias:Bear":"Bias:Neut"; }
datetime AddBars(datetime t,int n){ return t+(datetime)((long)n*PeriodSeconds(PERIOD_CURRENT)); }

void ResetZone()
{
   DelNm(g_boxName); DelNm(g_midName);
   g_state=-1; g_patBar=-1; g_breakBar=-1;
   g_insideCount=0; g_biasScore=0; g_brokeUp=false;
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],  const double &high[],
                const double &low[],   const double &close[],
                const long &tick_volume[], const long &volume[],
                const int &spread[])
{
   if(rates_total < InpAtrLen+10) return 0;
   if(BarsCalculated(g_hATR) < rates_total) return 0;

   // Copy ATR — series order (0=latest)
   double atr[];
   ArraySetAsSeries(atr,true);
   if(CopyBuffer(g_hATR,0,0,rates_total,atr)<=0) return 0;

   // Full recalc resets everything
   if(prev_calculated<=0)
   {
      ObjectsDeleteAll(0,"RBR_");
      g_seq=0;
      g_state=ST_INVALID;
      g_boxName=""; g_midName="";
   }

   // Process bars oldest to newest
   // MT5 OnCalculate arrays: index 0 = LATEST bar (series order)
   // Chronological bar i maps to array index: arr_idx = rates_total - 1 - i
   int from = (prev_calculated<=0) ? InpAtrLen+3 : prev_calculated-1;

   for(int i=from; i<rates_total; i++)
   {
      int ai = rates_total-1-i; // array index for bar i

      double H = high [ai];
      double L = low  [ai];
      double C = close[ai];
      double O = open [ai];
      datetime T = time[ai];
      double ATR = atr[ai+1 < rates_total ? ai+1 : ai]; // prev bar ATR

      // -------------------------------------------------------
      // Try to detect a new pattern when no zone is active
      // -------------------------------------------------------
      if(g_state==ST_INVALID || g_state==ST_DONE)
      {
         // Need 2 bars back
         if(ai+2 >= rates_total) continue;

         double H1=high[ai+1], L1=low[ai+1], C1=close[ai+1], O1=open[ai+1];
         double H2=high[ai+2], L2=low[ai+2], C2=close[ai+2], O2=open[ai+2];

         bool pat2G1R = (C2>O2)&&(C1>O1)&&(C<O);   // 2 green then 1 red
         bool pat2R1G = (C2<O2)&&(C1<O1)&&(C>O);   // 2 red   then 1 green

         if(pat2G1R || pat2R1G)
         {
            double zH = MathMax(H, MathMax(H1,H2));
            double zL = MathMin(L, MathMin(L1,L2));
            double sz = zH-zL;

            bool fixOk = sz <= InpMaxPips*_Point;
            bool atrOk = (ATR>0) ? sz<=ATR*InpAtrMult : true;
            bool ok    = (InpSizeMode==0)?fixOk:(InpSizeMode==1)?atrOk:(InpSizeMode==2)?(fixOk&&atrOk):true;

            if(ok)
            {
               ResetZone();
               g_hi=zH; g_lo=zL;
               g_state   = ST_ACCUM;
               g_patBar  = i;

               datetime futT = AddBars(T, InpMaxInside+10);
               if(InpShowBox) Box(g_boxName, time[ai+2], zH, futT, zL, InpColActive);
               if(InpShowMid) Mid(g_midName, time[ai+2], (zH+zL)/2.0, futT, InpColMidNeut);
            }
         }
         // Whether or not a pattern was found, move to next bar
         continue;
      }

      // -------------------------------------------------------
      // STATE: ST_ACCUM
      // -------------------------------------------------------
      if(g_state==ST_ACCUM)
      {
         bool inside   = H<=g_hi && L>=g_lo;
         bool wickOnly = (H>g_hi&&C<=g_hi)||(L<g_lo&&C>=g_lo);
         bool outClose = C>g_hi || C<g_lo;
         double mid    = (g_hi+g_lo)*0.5;

         if(inside || wickOnly)
         {
            g_insideCount++;
            g_biasScore += (C>=mid?1:-1);
            datetime ft = AddBars(T,InpMaxInside+5);
            BoxRight(g_boxName,ft);
            MidRC(g_midName,ft,BClr(g_biasScore));

            if(g_insideCount >= InpMinInside)
            {
               g_state = ST_CONF;
               if(InpShowBias) Lbl(T,g_hi,BTxt(g_biasScore),BClr(g_biasScore),true);
            }
            else if(g_insideCount > InpMaxInside)
               ResetZone();
         }
         else if(outClose)
            ResetZone();

         continue;
      }

      // -------------------------------------------------------
      // STATE: ST_CONF
      // -------------------------------------------------------
      if(g_state==ST_CONF)
      {
         bool above = C > g_hi;
         bool below = C < g_lo;
         bool wick  = (H>g_hi&&C<=g_hi)||(L<g_lo&&C>=g_lo);

         // Wick only — extend box, stay confirmed
         if(wick && !above && !below)
         {
            datetime ft=AddBars(T,InpMaxInside+5);
            BoxRight(g_boxName,ft);
            MidRC(g_midName,ft,BClr(g_biasScore));
            continue;
         }

         if(above)
         {
            // bias check
            bool allow=true;
            if(InpBiasOn)
            {
               double sz=g_hi-g_lo;
               bool sc = C > g_hi + sz*((InpStrongPct/100.0)-1.0);
               allow = (g_biasScore>=0)||sc;
            }
            if(allow)
            {
               g_state=ST_BROKEN; g_breakBar=i; g_brokeUp=true;
               BoxRight(g_boxName,T); BoxCol(g_boxName,C'0,70,45');
               MidRC(g_midName,T,BClr(g_biasScore));
               if(InpShowBreak) Lbl(T,g_hi,"^ Break UP",InpColBull,true);
            }
            else ResetZone();
            continue;
         }

         if(below)
         {
            bool allow=true;
            if(InpBiasOn)
            {
               double sz=g_hi-g_lo;
               bool sc = C < g_lo - sz*((InpStrongPct/100.0)-1.0);
               allow = (g_biasScore<=0)||sc;
            }
            if(allow)
            {
               g_state=ST_BROKEN; g_breakBar=i; g_brokeUp=false;
               BoxRight(g_boxName,T); BoxCol(g_boxName,C'110,15,25');
               MidRC(g_midName,T,BClr(g_biasScore));
               if(InpShowBreak) Lbl(T,g_lo,"v Break DN",InpColBear,false);
            }
            else ResetZone();
            continue;
         }

         // Bar closed inside range — stay confirmed
         continue;
      }

      // -------------------------------------------------------
      // STATE: ST_BROKEN — wait for close back inside range
      // -------------------------------------------------------
      if(g_state==ST_BROKEN)
      {
         int bsince = i - g_breakBar;
         bool inside = C>=g_lo && C<=g_hi;

         if(bsince > InpMaxRetest){ ResetZone(); continue; }

         if(bsince >= InpMinRetest && inside)
         {
            g_state = ST_RETEST;
            double lp = g_brokeUp ? g_hi : g_lo;
            if(InpShowRetest) Lbl(T,lp,"Retest",InpColRetest,!g_brokeUp);
         }
         continue;
      }

      // -------------------------------------------------------
      // STATE: ST_RETEST — wait for close back outside (signal)
      // -------------------------------------------------------
      if(g_state==ST_RETEST)
      {
         bool bull = C > g_hi;
         bool bear = C < g_lo;

         if(bull && g_brokeUp)
         {
            if(InpShowSignal) Lbl(T,g_hi,"BUY",InpColBull,true);
            ResetZone(); g_state=ST_DONE;
            continue;
         }
         if(bear && !g_brokeUp)
         {
            if(InpShowSignal) Lbl(T,g_lo,"SELL",InpColBear,false);
            ResetZone(); g_state=ST_DONE;
            continue;
         }
         // Wrong direction or still inside — invalidate
         if(bull || bear)
         { ResetZone(); continue; }

         continue;
      }
   }

   ChartRedraw(0);
   return rates_total;
}
//+------------------------------------------------------------------+
