//+------------------------------------------------------------------+
//| HMA_Engulfing_Crossover.mq5                                      |
//| Chart-timeframe MA intersections for all configured MA sources   |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   3
#property indicator_type1   DRAW_LINE
#property indicator_width1  2
#property indicator_type2   DRAW_LINE
#property indicator_width2  1
#property indicator_type3   DRAW_LINE
#property indicator_width3  1

enum ENUM_CUSTOM_MA  { MA_EMA=0, MA_WMA=1, MA_HMA=2, MA_ALMA=3, MA_DEMA=4, MA_SMA=5 };
enum ENUM_SIGNAL_MA  { SIG_MA1=0, SIG_MA2=1, SIG_MA3=2 };

//--- FIX #2 / #1: MA1 now has its own selectable MA type, just like MA2/MA3.
//--- FIX #6: inputs renamed/grouped consistently with descriptive comments.
input group "=== MA1 Settings ==="
input ENUM_CUSTOM_MA     Inp_MA1_Type         = MA_HMA;         // MA1: calculation type (EMA/WMA/HMA/ALMA/DEMA/SMA)
input ENUM_TIMEFRAMES    Inp_MA1_Timeframe    = PERIOD_CURRENT;  // MA1: source timeframe
input int                Inp_MA1_Period       = 14;              // MA1: period
input ENUM_APPLIED_PRICE Inp_MA1_AppliedPrice = PRICE_CLOSE;      // MA1: applied price
input color              Inp_MA1_LineColor    = clrDodgerBlue;    // MA1: line color
input ENUM_CUSTOM_MA     Inp_MA1_PostSmoothType   = MA_EMA;       // MA1: post-smoothing filter type
input int                Inp_MA1_PostSmoothPeriod = 1;            // MA1: post-smoothing period (1 = off)

input group "=== MA2 Settings ==="
input ENUM_CUSTOM_MA     Inp_MA2_Type         = MA_EMA;           // MA2: calculation type
input ENUM_TIMEFRAMES    Inp_MA2_Timeframe    = PERIOD_CURRENT;   // MA2: source timeframe
input int                Inp_MA2_Period       = 50;               // MA2: period
input ENUM_APPLIED_PRICE Inp_MA2_AppliedPrice = PRICE_CLOSE;       // MA2: applied price
input color              Inp_MA2_LineColor    = clrYellow;        // MA2: line color
input ENUM_CUSTOM_MA     Inp_MA2_PostSmoothType   = MA_EMA;       // MA2: post-smoothing filter type
input int                Inp_MA2_PostSmoothPeriod = 1;            // MA2: post-smoothing period (1 = off)

input group "=== MA3 Settings ==="
input ENUM_CUSTOM_MA     Inp_MA3_Type         = MA_EMA;           // MA3: calculation type
input ENUM_TIMEFRAMES    Inp_MA3_Timeframe    = PERIOD_CURRENT;   // MA3: source timeframe
input int                Inp_MA3_Period       = 200;              // MA3: period
input ENUM_APPLIED_PRICE Inp_MA3_AppliedPrice = PRICE_CLOSE;       // MA3: applied price
input color              Inp_MA3_LineColor    = clrMagenta;       // MA3: line color
input ENUM_CUSTOM_MA     Inp_MA3_PostSmoothType   = MA_EMA;       // MA3: post-smoothing filter type
input int                Inp_MA3_PostSmoothPeriod = 1;            // MA3: post-smoothing period (1 = off)

input group "=== ALMA Specific Settings (applies to any MA set to ALMA) ==="
input double Inp_ALMA_Offset = 0.85; // ALMA: offset (0..1, higher = more responsive)
input int    Inp_ALMA_Sigma  = 6;    // ALMA: sigma (smoothness)

input group "=== Setup 1: Breakout & Engulfing Signals ==="
input ENUM_SIGNAL_MA   Inp_Signal_SourceMA     = SIG_MA1;      // Signal source: which MA line drives breakout signals
input bool              Inp_Signal_EnableEngulfing = true;      // Enable engulfing-candle signals
input bool              Inp_Signal_EnableBreakout  = false;     // Enable simple MA breakout signals
input int                Inp_Signal_ExtendBars      = 3;         // Bars to extend the signal range box
input color              Inp_Signal_BuyColor        = clrLime;   // Buy signal color
input color              Inp_Signal_SellColor       = clrRed;    // Sell signal color
input int                Inp_Signal_LineWidth       = 1;         // Signal range line width
input ENUM_LINE_STYLE    Inp_Signal_LineStyle       = STYLE_SOLID;// Signal range line style
input bool                Inp_Signal_ShowArrows      = true;      // Show buy/sell arrows on signals

//--- FIX #7: new alert system for price crossing a chosen MA line.
input group "=== MA Price-Cross Alerts ==="
input bool          Inp_PriceCrossAlert_Enable   = false;    // Enable alert when price crosses a chosen MA
input ENUM_SIGNAL_MA Inp_PriceCrossAlert_MA      = SIG_MA1;   // Which MA line to watch for price crosses
input bool          Inp_PriceCrossAlert_UseWicks = false;    // true = use High/Low, false = use Close only
input bool          Inp_PriceCrossAlert_PopupAlert = true;   // Show terminal popup Alert()
input bool          Inp_PriceCrossAlert_PushNotify = false;  // Send push notification
input bool          Inp_PriceCrossAlert_PlaySound  = true;   // Play sound on alert
input string        Inp_PriceCrossAlert_SoundFile  = "alert.wav"; // Sound file to play

input group "=== PoI Marking: General ==="
input bool  Inp_Poi_ShowOnMA1        = true;   // Show inflection points on MA1
input bool  Inp_Poi_ShowOnMA2        = true;   // Show inflection points on MA2
input bool  Inp_Poi_ShowOnMA3        = true;   // Show inflection points on MA3
input bool  Inp_Poi_ShowIntersects   = true;   // Show MA-MA intersection points
input bool  Inp_Poi_Intersect_MA1MA2 = true;   // Include MA1 x MA2 intersections
input bool  Inp_Poi_Intersect_MA1MA3 = true;   // Include MA1 x MA3 intersections
input bool  Inp_Poi_Intersect_MA2MA3 = true;   // Include MA2 x MA3 intersections
input bool  Inp_Poi_ShowPriceLabel   = true;   // Show price text label at line's right edge
input bool  Inp_Poi_UseWicksForHit   = true;   // Use High/Low (wicks) instead of Open/Close to detect a level hit
input bool  Inp_Poi_IgnoreLastBar    = true;   // Ignore the still-forming (current) bar when scanning

input group "=== PoI Marking: Timing & Removal ==="
input int   Inp_Poi_MitigationDelayBars = 5;   // Bars to wait after a level forms before it can be mitigated
//--- FIX #3: level retention is now measured from the moment a level is
//--- mitigated (frozen), using chart bar-time, not wall-clock TimeCurrent().
input int   Inp_Poi_RetainAfterHitMinutes = 20; // Minutes to KEEP a level visible after price hits/mitigates it

input group "=== PoI Marking: Appearance ==="
input int             Inp_Poi_LineWidth       = 1;              // Normal line width
input int             Inp_Poi_NearLineWidth   = 2;               // Line width when price is "near" the level
input ENUM_LINE_STYLE Inp_Poi_LineStyle       = STYLE_SOLID;     // Line style
input color           Inp_Poi_DimColor        = C'32,32,32';     // Color used when level is not "near" price
//--- FIX #5: dedicated, independent color input for the price text labels.
input color           Inp_Poi_LabelColor      = clrWhite;        // Price text label color (independent of line color)

input group "=== PoI Marking: Proximity / ATR ==="
input int    Inp_Poi_AtrPeriod        = 14;    // ATR period used for proximity & clustering distance
input double Inp_Poi_NearAtrMult      = 1.0;   // "Near" band distance = ATR * this multiplier
input int    Inp_Poi_NearMinPoints    = 0;      // Minimum "near" distance in points (floor for ATR band)
input double Inp_Poi_ClusterAtrMult   = 0.15;  // Cluster merge distance = ATR * this multiplier
input double Inp_Poi_CrossTolerancePoints = 1.0; // Tolerance in points to ignore MA-MA cross noise

input group "=== PoI Marking: Inflection Detection ==="
input int    Inp_Poi_MaxInflections = 60;    // Max stored inflection levels per MA line
input double Inp_Poi_MinCurveDegrees = 25.0; // Minimum curvature angle (degrees) to count as a real swing
input int    Inp_Poi_CurveLookbackBars = 5;  // Bars left/right used to measure curvature

input group "=== PoI Marking: Colors per Group ==="
input color Inp_Poi_MA1_HighColor = clrDodgerBlue;  // MA1 inflection color: swing high
input color Inp_Poi_MA1_LowColor  = clrDeepSkyBlue;  // MA1 inflection color: swing low
input color Inp_Poi_MA2_HighColor = clrYellow;       // MA2 inflection color: swing high
input color Inp_Poi_MA2_LowColor  = clrGold;         // MA2 inflection color: swing low
input color Inp_Poi_MA3_HighColor = clrMagenta;      // MA3 inflection color: swing high
input color Inp_Poi_MA3_LowColor  = clrOrchid;       // MA3 inflection color: swing low
input color Inp_Poi_Intersect_HighColor = clrAqua;   // Intersection color: swing high
input color Inp_Poi_Intersect_LowColor  = clrOrange; // Intersection color: swing low

double MA1Buffer[], MA2Buffer[], MA3Buffer[];
int hMA1,hMA1Half,hMA1Full,hMA1Price; double arrMA1Half[], arrMA1Full[];
int hMA2,hMA2Half,hMA2Full,hMA2Price; double arrMA2Half[], arrMA2Full[];
int hMA3,hMA3Half,hMA3Full,hMA3Price; double arrMA3Half[], arrMA3Full[];
double g_htf1[], g_htf2[], g_htf3[];
double g_raw1[], g_raw2[], g_raw3[];

datetime g_last_signal_bar_time=0, g_last_buy_end=0, g_last_sell_end=0;
string g_last_buy_top="", g_last_buy_bot="", g_last_buy_arrow="";
string g_last_sell_top="", g_last_sell_bot="", g_last_sell_arrow="";

//--- FIX #7: state for the new MA price-cross alert
datetime g_last_pricecross_alert_time=0;

#define OBJ_PREFIX "HMA_SIG_"
#define PREFIX_H1  "HMA1INF_"
#define PREFIX_H2  "HMA2INF_"
#define PREFIX_H3  "HMA3INF_"
#define PREFIX_X   "MAXING_"

enum ENUM_SWING_TYPE { SWING_HIGH=1, SWING_LOW=-1 };
enum ENUM_LEVEL_GROUP { GRP_SWING=0, GRP_HMA1=1, GRP_HMA2=2, GRP_HMA3=3 };

struct Level
{
   datetime time_start, time_end, drawn_end;
   double   price;
   ENUM_SWING_TYPE type;
   ENUM_LEVEL_GROUP group;
   bool     frozen, drawn, near;
   //--- FIX #3: timestamp of when the level was actually mitigated (hit),
   //--- used as the retention anchor instead of wall-clock time.
   datetime frozen_at;
   color    drawn_color;
   int      drawn_width;
   string   name;
};

struct ClusterItem
{
   int    src;
   int    idx;
   double price;
};

Level g_inf1[]; int g_inf1_count=0;
Level g_inf2[]; int g_inf2_count=0;
Level g_inf3[]; int g_inf3_count=0;
Level g_x[];    int g_x_count=0;
datetime g_last_bar=0, g_atr_bar=0;
bool g_poi_ready=false;
double g_near_on=0.0, g_near_off=0.0;
int g_atr_handle=INVALID_HANDLE;
#define MAX_GONE 1024
string g_gone_ids[]; int g_gone_count=0;

ENUM_TIMEFRAMES ResolveTF(const ENUM_TIMEFRAMES tf)
{ return((tf==PERIOD_CURRENT)?(ENUM_TIMEFRAMES)_Period:tf); }
bool IsSameTF(const ENUM_TIMEFRAMES tf)
{ return(ResolveTF(tf)==(ENUM_TIMEFRAMES)_Period); }
int SmoothLookback(const ENUM_CUSTOM_MA type,const int period)
{
   if(period<=1) return 2;
   if(type==MA_HMA)  return period+(int)MathRound(MathSqrt((double)period))+3;
   if(type==MA_DEMA) return period*2+3;
   return period+3;
}

bool CurveSharpEnough(const double &ma[],const int i,const int rates_total)
{
   int n=Inp_Poi_CurveLookbackBars;
   if(n<1) n=1;
   if(i-n<0 || i+n>=rates_total) return false;   // FIX: was "if(i=rates_total)" (assignment bug, always-true/corrupting i)
   double left=ma[i]-ma[i-n], right=ma[i+n]-ma[i];
   if(left==0.0 && right==0.0) return false;
   double yscale=_Point;
   if(g_atr_handle!=INVALID_HANDLE)
   {
      double atr[1];
      if(CopyBuffer(g_atr_handle,0,1,1,atr)==1 && atr[0]>0.0) yscale=atr[0]/(double)n;
   }
   if(yscale<=0.0) yscale=_Point;
   const double rad2deg=180.0/3.141592653589793;
   double a1=MathArctan(left/((double)n*yscale))*rad2deg;
   double a2=MathArctan(right/((double)n*yscale))*rad2deg;
   return(MathAbs(a1-a2)>=Inp_Poi_MinCurveDegrees);
}

//+------------------------------------------------------------------+
//| Initializes handles for ANY of the 6 MA types on ANY of MA1/2/3   |
//| FIX #1 / #2: this is now used for MA1 too (previously MA1 was     |
//| hardcoded to HMA/LWMA half+full inside OnInit).                   |
//+------------------------------------------------------------------+
void InitCustomMA(ENUM_CUSTOM_MA type,int period,ENUM_APPLIED_PRICE price,ENUM_TIMEFRAMES tf,
                   int &h,int &hHalf,int &hFull,int &hPrice,double &arrHalf[],double &arrFull[])
{
   h=INVALID_HANDLE; hHalf=INVALID_HANDLE; hFull=INVALID_HANDLE; hPrice=INVALID_HANDLE;
   if(type==MA_EMA)       h=iMA(_Symbol,tf,period,0,MODE_EMA,price);
   else if(type==MA_SMA)  h=iMA(_Symbol,tf,period,0,MODE_SMA,price);
   else if(type==MA_WMA)  h=iMA(_Symbol,tf,period,0,MODE_LWMA,price);
   else if(type==MA_DEMA) h=iDEMA(_Symbol,tf,period,0,price);
   else if(type==MA_HMA)
   {
      int half=(int)MathFloor(period/2.0);
      hHalf=iMA(_Symbol,tf,half,0,MODE_LWMA,price);
      hFull=iMA(_Symbol,tf,period,0,MODE_LWMA,price);
      ArraySetAsSeries(arrHalf,true); ArraySetAsSeries(arrFull,true);
   }
   else if(type==MA_ALMA) hPrice=iMA(_Symbol,tf,1,0,MODE_SMA,price);
}

void ApplySmoothMA(double &src[],double &dst[],const int rates_total,const bool full,const ENUM_CUSTOM_MA type,const int period)
{
   int start=full?0:MathMax(0,rates_total-SmoothLookback(type,period));
   if(period<=1){ for(int i=start;i<rates_total;i++) dst[i]=src[i]; return; }
   if(type==MA_EMA)
   {
      double k=2.0/(period+1.0);
      if(full && start==0){ dst[0]=src[0]; start=1; }
      for(int i=start;i<rates_total;i++)
      {
         if(src[i]==0.0){ dst[i]=0.0; continue; }
         double prev=(i>0 && dst[i-1]!=0.0)?dst[i-1]:src[i-1];
         dst[i]=prev+k*(src[i]-prev);
      }
      return;
   }
   if(type==MA_DEMA)
   {
      double e1[],e2[];
      ArrayResize(e1,rates_total); ArrayResize(e2,rates_total);
      ApplySmoothMA(src,e1,rates_total,true,MA_EMA,period);
      ApplySmoothMA(e1,e2,rates_total,true,MA_EMA,period);
      for(int i=start;i<rates_total;i++) dst[i]=2.0*e1[i]-e2[i];
      return;
   }
   if(type==MA_HMA)
   {
      int half=MathMax(period/2,1), hull=MathMax((int)MathRound(MathSqrt((double)period)),1);
      double a[],b[],raw[];
      ArrayResize(a,rates_total); ArrayResize(b,rates_total); ArrayResize(raw,rates_total);
      ApplySmoothMA(src,a,rates_total,true,MA_WMA,half);
      ApplySmoothMA(src,b,rates_total,true,MA_WMA,period);
      for(int i=0;i<rates_total;i++) raw[i]=(a[i]==0.0||b[i]==0.0)?0.0:(2.0*a[i]-b[i]);
      ApplySmoothMA(raw,dst,rates_total,true,MA_WMA,hull);
      return;
   }
   for(int i=start;i<rates_total;i++)
   {
      if(i+1<period){ dst[i]=src[i]; continue; }
      double sum=0.0, wsum=0.0;
      if(type==MA_WMA)
      {
         int w=1;
         for(int j=i-period+1;j<=i;j++,w++){ sum+=src[j]*w; wsum+=w; }
         dst[i]=(wsum==0.0)?0.0:sum/wsum;
      }
      else
      {
         for(int j=i-period+1;j<=i;j++) sum+=src[j];
         dst[i]=sum/period;
      }
   }
}

void MapSeriesToChart(const datetime &time[],const int rates_total,const bool full,const ENUM_TIMEFRAMES tf,const double &src[],const int copied,double &dest[])
{
   int step=PeriodSeconds(tf); step=MathMax(step,PeriodSeconds());
   int start=full?0:MathMax(0,rates_total-step*3);
   for(int i=start;i<rates_total;i++)
   {
      int sh=iBarShift(_Symbol,tf,time[i],false);
      dest[i]=(sh<0||sh>=copied)?0.0:src[sh];
   }
}

bool CalcHMA_Series(int copied,int period,int hHalf,int hFull,double &half[],double &full[],double &out[])
{
   int sp=MathMax((int)MathFloor(MathSqrt((double)period)),1);
   if(copied<=sp) return false;
   if(CopyBuffer(hHalf,0,0,copied,half)!=copied || CopyBuffer(hFull,0,0,copied,full)!=copied) return false;
   ArrayResize(out,copied); ArraySetAsSeries(out,true);
   double raw[]; ArrayResize(raw,copied);
   for(int i=0;i<copied;i++) raw[i]=2.0*half[i]-full[i];
   for(int i=0;i<copied-sp;i++)
   {
      double sum=0.0, ws=0.0;
      for(int j=0;j<sp;j++){ double w=sp-j; sum+=raw[i+j]*w; ws+=w; }
      out[i]=sum/ws;
   }
   return true;
}

bool CalcHMA_Chart(int rates_total,int prev,int period,int hHalf,int hFull,double &half[],double &full[],double &buf[])
{
   int limit=rates_total-prev;
   if(prev>0) limit++; else limit=rates_total-period;
   if(limit<=0) return true;
   int sp=(int)MathFloor(MathSqrt((double)period)), n=limit+sp;
   if(CopyBuffer(hHalf,0,0,n,half)!=n || CopyBuffer(hFull,0,0,n,full)!=n) return false;
   double raw[]; ArrayResize(raw,n);
   for(int i=0;i<n;i++) raw[i]=2.0*half[i]-full[i];
   for(int i=0;i<limit;i++)
   {
      double sum=0.0, ws=0.0;
      for(int j=0;j<sp;j++){ double w=sp-j; sum+=raw[i+j]*w; ws+=w; }
      buf[rates_total-1-i]=sum/ws;
   }
   return true;
}

bool CalcStandardChart(int rates_total,int prev,int h,double &buf[])
{
   int limit=rates_total-prev;
   if(prev>0) limit++; else limit=rates_total;
   if(limit<=0) return true;
   double t[]; if(CopyBuffer(h,0,0,limit,t)!=limit) return false;
   for(int i=0;i<limit;i++) buf[rates_total-limit+i]=t[i];
   return true;
}

bool CalcALMAChart(int rates_total,int prev,int period,double offset,int sigma,int hPrice,double &buf[])
{
   int limit=rates_total-prev;
   if(prev>0) limit++; else limit=rates_total-period;
   if(limit<=0) return true;
   double px[]; if(CopyBuffer(hPrice,0,0,limit+period,px)!=limit+period) return false;
   int m=(int)MathFloor(offset*(period-1));
   double s=(double)period/sigma;
   for(int i=rates_total-limit;i<rates_total;i++)
   {
      if(i<period-1){ buf[i]=0.0; continue; }
      double sum=0.0, ws=0.0;
      for(int j=0;j<period;j++)
      {
         double w=MathExp(-0.5*MathPow((j-m)/s,2));
         double p=px[limit+period-1-(rates_total-1-i)-j];
         sum+=p*w; ws+=w;
      }
      buf[i]=sum/ws;
   }
   return true;
}

//+------------------------------------------------------------------+
//| FIX #1/#2: 'ma1hma' force-flag removed. Every MA (1/2/3) now runs |
//| through the exact same generic path driven purely by 'type'.     |
//+------------------------------------------------------------------+
bool FillMA(const ENUM_TIMEFRAMES tfIn,const ENUM_CUSTOM_MA type,const int period,
            const ENUM_CUSTOM_MA smoothType,const int smoothPeriod,const int rates_total,const int prev,
            const datetime &time[], int h,int hHalf,int hFull,int hPrice,double &arrHalf[],double &arrFull[],
            double &htf[],double &raw[],double &out[])
{
   ENUM_TIMEFRAMES tf=ResolveTF(tfIn);
   ArrayResize(raw,rates_total);
   bool full=(prev==0), ok;
   if(IsSameTF(tfIn))
   {
      if(type==MA_HMA)       ok=CalcHMA_Chart(rates_total,prev,period,hHalf,hFull,arrHalf,arrFull,raw);
      else if(type==MA_ALMA) ok=CalcALMAChart(rates_total,prev,period,Inp_ALMA_Offset,Inp_ALMA_Sigma,hPrice,raw);
      else                   ok=CalcStandardChart(rates_total,prev,h,raw);
   }
   else
   {
      int copied=iBars(_Symbol,tf);
      if(copied<period+5) return false;
      if(copied>5000) copied=5000;
      if(type==MA_HMA) ok=CalcHMA_Series(copied,period,hHalf,hFull,arrHalf,arrFull,htf);
      else if(type==MA_ALMA)
      {
         ArrayResize(htf,copied); ArraySetAsSeries(htf,true);
         double px[]; ArraySetAsSeries(px,true);
         if(CopyBuffer(hPrice,0,0,copied,px)!=copied) return false;
         int m=(int)MathFloor(Inp_ALMA_Offset*(period-1));
         double s=(double)period/Inp_ALMA_Sigma;
         for(int i=0;i<copied-period;i++)
         {
            double sum=0.0, ws=0.0;
            for(int j=0;j<period;j++)
            {
               double w=MathExp(-0.5*MathPow((j-m)/s,2));
               sum+=px[i+period-1-j]*w; ws+=w;
            }
            htf[i]=(ws==0.0)?0.0:sum/ws;
         }
         ok=true;
      }
      else
      {
         ArrayResize(htf,copied); ArraySetAsSeries(htf,true);
         ok=(CopyBuffer(h,0,0,copied,htf)==copied);
      }
      if(ok) MapSeriesToChart(time,rates_total,full,tf,htf,copied,raw);
   }
   if(!ok) return false;
   ApplySmoothMA(raw,out,rates_total,full,smoothType,smoothPeriod);
   return true;
}

bool IsBullishEngulfing(const double &open[],const double &close[],int i)
{return(i>=1 && close[i-1]<open[i-1] && close[i]>open[i] && open[i]<=close[i-1] && close[i]>=open[i-1]);}
bool IsBearishEngulfing(const double &open[],const double &close[],int i)
{return(i>=1 && close[i-1]>open[i-1] && close[i]<open[i] && open[i]>=close[i-1] && close[i]<=open[i-1]);}

void DrawSignalRange(int i,const datetime &time[],const double &high[],const double &low[],bool buy,string tag)
{
   datetime t=time[i],e=t+(datetime)(PeriodSeconds()*Inp_Signal_ExtendBars);
   color c=buy?Inp_Signal_BuyColor:Inp_Signal_SellColor;
   string p=buy?"BUY_"+tag:"SELL_"+tag;
   string nt=OBJ_PREFIX+p+"_TOP_"+IntegerToString((long)t),nb=OBJ_PREFIX+p+"_BOT_"+IntegerToString((long)t),na=OBJ_PREFIX+p+"_ARROW_"+IntegerToString((long)t);
   if(buy){ if(g_last_buy_end!=0 && t<=g_last_buy_end){ObjectDelete(0,g_last_buy_top);ObjectDelete(0,g_last_buy_bot);ObjectDelete(0,g_last_buy_arrow);} g_last_buy_end=e;g_last_buy_top=nt;g_last_buy_bot=nb;g_last_buy_arrow=na; }
   else{ if(g_last_sell_end!=0 && t<=g_last_sell_end){ObjectDelete(0,g_last_sell_top);ObjectDelete(0,g_last_sell_bot);ObjectDelete(0,g_last_sell_arrow);} g_last_sell_end=e;g_last_sell_top=nt;g_last_sell_bot=nb;g_last_sell_arrow=na; }
   if(ObjectFind(0,nt)<0){ObjectCreate(0,nt,OBJ_TREND,0,t,high[i],e,high[i]);ObjectSetInteger(0,nt,OBJPROP_COLOR,c);ObjectSetInteger(0,nt,OBJPROP_WIDTH,Inp_Signal_LineWidth);ObjectSetInteger(0,nt,OBJPROP_STYLE,Inp_Signal_LineStyle);ObjectSetInteger(0,nt,OBJPROP_RAY_RIGHT,false);ObjectSetInteger(0,nt,OBJPROP_BACK,true);}
   if(ObjectFind(0,nb)<0){ObjectCreate(0,nb,OBJ_TREND,0,t,low[i],e,low[i]);ObjectSetInteger(0,nb,OBJPROP_COLOR,c);ObjectSetInteger(0,nb,OBJPROP_WIDTH,Inp_Signal_LineWidth);ObjectSetInteger(0,nb,OBJPROP_STYLE,Inp_Signal_LineStyle);ObjectSetInteger(0,nb,OBJPROP_RAY_RIGHT,false);ObjectSetInteger(0,nb,OBJPROP_BACK,true);}
   if(Inp_Signal_ShowArrows && ObjectFind(0,na)<0){ObjectCreate(0,na,OBJ_ARROW,0,t,buy?low[i]:high[i]);ObjectSetInteger(0,na,OBJPROP_ARROWCODE,buy?233:234);ObjectSetInteger(0,na,OBJPROP_COLOR,c);ObjectSetInteger(0,na,OBJPROP_WIDTH,2);}
}

void RunBreakoutSignals(int total,const datetime &time[],const double &open[],const double &high[],const double &low[],const double &close[])
{
   if((!Inp_Signal_EnableEngulfing && !Inp_Signal_EnableBreakout) || total<3) return;
   int last=total-2; if(last<1 || (g_last_signal_bar_time!=0 && time[last]==g_last_signal_bar_time)) return;
   int first=(g_last_signal_bar_time!=0)?MathMax(1,last-5):MathMax(1,last-500);
   for(int i=first;i<=last;i++)
   {
      double ma=0,mp=0;
      if(Inp_Signal_SourceMA==SIG_MA1){ma=MA1Buffer[i];mp=MA1Buffer[i-1];}
      else if(Inp_Signal_SourceMA==SIG_MA2){ma=MA2Buffer[i];mp=MA2Buffer[i-1];}
      else{ma=MA3Buffer[i];mp=MA3Buffer[i-1];}
      if(ma==0||mp==0) continue;
      bool up=close[i-1]<=mp && close[i]>ma, dn=close[i-1]>=mp && close[i]<ma;
      if(up)
      {
         if(Inp_Signal_EnableEngulfing && IsBullishEngulfing(open,close,i)) DrawSignalRange(i,time,high,low,true,"ENG");
         else if(Inp_Signal_EnableBreakout) DrawSignalRange(i,time,high,low,true,"BRK");
      }
      else if(dn)
      {
         if(Inp_Signal_EnableEngulfing && IsBearishEngulfing(open,close,i)) DrawSignalRange(i,time,high,low,false,"ENG");
         else if(Inp_Signal_EnableBreakout) DrawSignalRange(i,time,high,low,false,"BRK");
      }
   }
   g_last_signal_bar_time=time[last];
}

//+------------------------------------------------------------------+
//| FIX #7: alert when price crosses the chosen MA line               |
//+------------------------------------------------------------------+
void FirePriceCrossAlert(bool up,datetime t,ENUM_SIGNAL_MA which)
{
   string maName=(which==SIG_MA1)?"MA1":(which==SIG_MA2)?"MA2":"MA3";
   string msg=StringFormat("%s %s: Price crossed %s (%s)",_Symbol,EnumToString((ENUM_TIMEFRAMES)_Period),maName,up?"UP":"DOWN");
   if(Inp_PriceCrossAlert_PopupAlert) Alert(msg);
   if(Inp_PriceCrossAlert_PushNotify) SendNotification(msg);
   if(Inp_PriceCrossAlert_PlaySound && StringLen(Inp_PriceCrossAlert_SoundFile)>0) PlaySound(Inp_PriceCrossAlert_SoundFile);
}

void RunPriceCrossAlert(int total,const datetime &time[],const double &open[],const double &high[],const double &low[],const double &close[])
{
   if(!Inp_PriceCrossAlert_Enable || total<3) return;
   int i=total-2; if(i<1) return;
   if(g_last_pricecross_alert_time!=0 && time[i]==g_last_pricecross_alert_time) return;

   double ma=0,mp=0;
   if(Inp_PriceCrossAlert_MA==SIG_MA1){ma=MA1Buffer[i];mp=MA1Buffer[i-1];}
   else if(Inp_PriceCrossAlert_MA==SIG_MA2){ma=MA2Buffer[i];mp=MA2Buffer[i-1];}
   else{ma=MA3Buffer[i];mp=MA3Buffer[i-1];}
   if(ma==0 || mp==0) return;

   if(Inp_PriceCrossAlert_UseWicks)
   {
      bool up=low[i-1]<=mp && high[i]>ma;
      bool dn=high[i-1]>=mp && low[i]<ma;
      if(!up && !dn) return;
      FirePriceCrossAlert(up,time[i],Inp_PriceCrossAlert_MA);
   }
   else
   {
      bool up=close[i-1]<=mp && close[i]>ma;
      bool dn=close[i-1]>=mp && close[i]<ma;
      if(!up && !dn) return;
      FirePriceCrossAlert(up,time[i],Inp_PriceCrossAlert_MA);
   }
   g_last_pricecross_alert_time=time[i];
}

string GoneKey(datetime t,ENUM_SWING_TYPE type,ENUM_LEVEL_GROUP grp,string p)
{ return(p+IntegerToString((int)grp)+IntegerToString((int)type)+TimeToString(t,TIME_DATE|TIME_SECONDS)); }
bool IsGone(datetime t,ENUM_SWING_TYPE type,ENUM_LEVEL_GROUP grp,string p)
{ string k=GoneKey(t,type,grp,p); for(int i=0;i<g_gone_count;i++) if(g_gone_ids[i]==k) return true; return false; }
void MarkGone(datetime t,ENUM_SWING_TYPE type,ENUM_LEVEL_GROUP grp,string p)
{
   if(IsGone(t,type,grp,p)) return;
   if(g_gone_count>=MAX_GONE){ for(int i=1;i<g_gone_count;i++) g_gone_ids[i-1]=g_gone_ids[i]; g_gone_count--; }
   g_gone_ids[g_gone_count]=GoneKey(t,type,grp,p); g_gone_count++;
}

//+------------------------------------------------------------------+
//| FIX #3: retention is now anchored to the moment of mitigation      |
//| (l.frozen_at, a chart bar time) instead of wall-clock TimeCurrent()|
//| compared against a historical bar time. This makes levels persist |
//| for Inp_Poi_RetainAfterHitMinutes AFTER they are actually hit,     |
//| instead of disappearing on the very next recalculation.            |
//+------------------------------------------------------------------+
bool ReadyToRemove(const Level &l)
{
   if(!l.frozen) return false;
   if(l.frozen_at==0) return false;
   return((TimeCurrent()-l.frozen_at)>=Inp_Poi_RetainAfterHitMinutes*60);
}

color ColorFor(ENUM_LEVEL_GROUP g,ENUM_SWING_TYPE t)
{
   if(g==GRP_HMA1) return(t==SWING_HIGH?Inp_Poi_MA1_HighColor:Inp_Poi_MA1_LowColor);
   if(g==GRP_HMA2) return(t==SWING_HIGH?Inp_Poi_MA2_HighColor:Inp_Poi_MA2_LowColor);
   if(g==GRP_HMA3) return(t==SWING_HIGH?Inp_Poi_MA3_HighColor:Inp_Poi_MA3_LowColor);
   return(t==SWING_HIGH?Inp_Poi_Intersect_HighColor:Inp_Poi_Intersect_LowColor);
}

datetime RightEdgeTime(double price)
{
   int w=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS),x=0,y=0,sub=0;
   datetime t=TimeCurrent(); double d=price;
   if(ChartTimePriceToXY(0,0,TimeCurrent(),price,x,y)) ChartXYToTimePrice(0,MathMax(1,w-4),y,sub,t,d);
   return t;
}

//--- FIX #5: label color is now Inp_Poi_LabelColor, independent of the line color.
void UpsertPriceLabel(const Level &l)
{
   string n=l.name+"_P";
   if(!Inp_Poi_ShowPriceLabel || l.frozen){ObjectDelete(0,n); return;}
   datetime t=RightEdgeTime(l.price);
   if(ObjectFind(0,n)<0) ObjectCreate(0,n,OBJ_TEXT,0,t,l.price);
   ObjectSetInteger(0,n,OBJPROP_TIME,t);
   ObjectSetDouble(0,n,OBJPROP_PRICE,l.price);
   ObjectSetString(0,n,OBJPROP_TEXT,DoubleToString(l.price,_Digits));
   ObjectSetInteger(0,n,OBJPROP_COLOR,Inp_Poi_LabelColor);
   ObjectSetInteger(0,n,OBJPROP_FONTSIZE,8);
   ObjectSetInteger(0,n,OBJPROP_ANCHOR,ANCHOR_RIGHT_LOWER);
   ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,n,OBJPROP_HIDDEN,true);
   ObjectSetString(0,n,OBJPROP_FONT,"Arial");
}

void CreateOrUpdateLine(Level &l,bool force)
{
   datetime t1=l.time_start,t2=(l.time_end>t1?l.time_end:t1+PeriodSeconds());
   bool hi=l.near && !l.frozen;
   color c=hi?ColorFor(l.group,l.type):Inp_Poi_DimColor;
   int w=hi?Inp_Poi_NearLineWidth:Inp_Poi_LineWidth;
   if(force || ObjectFind(0,l.name)<0)
   {
      if(ObjectFind(0,l.name)<0) ObjectCreate(0,l.name,OBJ_TREND,0,t1,l.price,t2,l.price);
      ObjectSetInteger(0,l.name,OBJPROP_RAY_LEFT,false);
      ObjectSetInteger(0,l.name,OBJPROP_RAY_RIGHT,l.frozen?false:true);
      ObjectSetInteger(0,l.name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,l.name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,l.name,OBJPROP_BACK,true);
      ObjectSetInteger(0,l.name,OBJPROP_STYLE,Inp_Poi_LineStyle);
      ObjectSetInteger(0,l.name,OBJPROP_TIME,0,t1);
      ObjectSetInteger(0,l.name,OBJPROP_TIME,1,t2);
      ObjectSetDouble(0,l.name,OBJPROP_PRICE,0,l.price);
      ObjectSetDouble(0,l.name,OBJPROP_PRICE,1,l.price);
      ObjectSetInteger(0,l.name,OBJPROP_COLOR,c);
      ObjectSetInteger(0,l.name,OBJPROP_WIDTH,w);
      l.drawn=true; l.drawn_end=t2; l.drawn_color=c; l.drawn_width=w;
      UpsertPriceLabel(l);
      return;
   }
   ObjectSetDouble(0,l.name,OBJPROP_PRICE,0,l.price);
   ObjectSetDouble(0,l.name,OBJPROP_PRICE,1,l.price);
   if(l.frozen && l.drawn_end!=t2){ObjectSetInteger(0,l.name,OBJPROP_RAY_RIGHT,false);ObjectSetInteger(0,l.name,OBJPROP_TIME,1,t2);l.drawn_end=t2;}
   if(l.drawn_color!=c || l.drawn_width!=w){ObjectSetInteger(0,l.name,OBJPROP_COLOR,c);ObjectSetInteger(0,l.name,OBJPROP_WIDTH,w);l.drawn_color=c;l.drawn_width=w;}
   UpsertPriceLabel(l);
}

void RepositionGroupLabels(Level &a[],int c){ for(int i=0;i<c;i++) if(!a[i].frozen) UpsertPriceLabel(a[i]); }
void RepositionAllPriceLabels()
{
   RepositionGroupLabels(g_inf1,g_inf1_count);
   RepositionGroupLabels(g_inf2,g_inf2_count);
   RepositionGroupLabels(g_inf3,g_inf3_count);
   RepositionGroupLabels(g_x,g_x_count);
}

int XMaxCount(){ return MathMax(Inp_Poi_MaxInflections*3,180); }

void RemoveAt(Level &a[],int &c,int x)
{
   if(x<0 || x>=c) return;
   ObjectDelete(0,a[x].name); ObjectDelete(0,a[x].name+"_P");
   MarkGone(a[x].time_start,a[x].type,a[x].group,a[x].name);
   for(int i=x+1;i<c;i++) a[i-1]=a[i];
   c--;
}

void PurgeMitigated(Level &a[],int &c)
{ for(int i=c-1;i>=0;i--) if(ReadyToRemove(a[i])) RemoveAt(a,c,i); }

double ClusterDistance()
{
   double d=10*_Point;
   if(g_atr_handle!=INVALID_HANDLE && Inp_Poi_ClusterAtrMult>0)
   { double a[1]; if(CopyBuffer(g_atr_handle,0,1,1,a)==1 && a[0]>0) d=a[0]*Inp_Poi_ClusterAtrMult; }
   return d;
}

void CollectUnfrozen(Level &a[],int c,int src,ClusterItem &it[],int &n)
{ for(int i=0;i<c;i++) if(!a[i].frozen){ it[n].src=src; it[n].idx=i; it[n].price=a[i].price; n++; } }

void SortItems(ClusterItem &it[],int n)
{
   for(int i=0;i<n-1;i++)
      for(int j=i+1;j<n;j++)
         if(it[j].price<it[i].price){ ClusterItem t=it[i]; it[i]=it[j]; it[j]=t; }
}

void SnapMedian(int src,int idx,double p)
{
   if(src==0 && idx<g_inf1_count){ g_inf1[idx].price=p; CreateOrUpdateLine(g_inf1[idx],true); }
   else if(src==1 && idx<g_inf2_count){ g_inf2[idx].price=p; CreateOrUpdateLine(g_inf2[idx],true); }
   else if(src==2 && idx<g_inf3_count){ g_inf3[idx].price=p; CreateOrUpdateLine(g_inf3[idx],true); }
   else if(src==3 && idx<g_x_count){ g_x[idx].price=p; CreateOrUpdateLine(g_x[idx],true); }
}

void DropItem(const ClusterItem &it)
{
   if(it.src==0) RemoveAt(g_inf1,g_inf1_count,it.idx);
   else if(it.src==1) RemoveAt(g_inf2,g_inf2_count,it.idx);
   else if(it.src==2) RemoveAt(g_inf3,g_inf3_count,it.idx);
   else RemoveAt(g_x,g_x_count,it.idx);
}

double MedianPrice(const ClusterItem &it[],int s,int e)
{
   int c=e-s+1, m=s+c/2;
   return(c%2==1)?it[m].price:0.5*(it[m-1].price+it[m].price);
}

void ClusterNearbyUnfrozen()
{
   int cap=g_inf1_count+g_inf2_count+g_inf3_count+g_x_count;
   if(cap<2) return;
   ClusterItem it[]; ArrayResize(it,cap);
   int n=0;
   CollectUnfrozen(g_inf1,g_inf1_count,0,it,n);
   CollectUnfrozen(g_inf2,g_inf2_count,1,it,n);
   CollectUnfrozen(g_inf3,g_inf3_count,2,it,n);
   CollectUnfrozen(g_x,g_x_count,3,it,n);
   if(n<2) return;
   SortItems(it,n);
   double d=ClusterDistance();
   ClusterItem lose[]; ArrayResize(lose,n);
   int ln=0,s=0;
   while(s<n)
   {
      int e=s; while(e+1<n && it[e+1].price-it[s].price<=d) e++;
      if(e>s)
      {
         double med=MedianPrice(it,s,e);
         int w=s; double best=MathAbs(it[s].price-med);
         for(int k=s;k<=e;k++){ double z=MathAbs(it[k].price-med); if(z<best){best=z;w=k;} }
         SnapMedian(it[w].src,it[w].idx,med);
         for(int k=s;k<=e;k++) if(k!=w){ lose[ln]=it[k]; ln++; }
      }
      s=e+1;
   }
   for(int a=0;a<ln-1;a++)
      for(int b=a+1;b<ln;b++)
         if(lose[b].src>lose[a].src || (lose[b].src==lose[a].src && lose[b].idx>lose[a].idx))
         { ClusterItem t=lose[a]; lose[a]=lose[b]; lose[b]=t; }
   for(int i=0;i<ln;i++) DropItem(lose[i]);
}

void RefreshNearBand(datetime t)
{
   if(g_atr_bar==t && g_near_on!=0) return;
   g_atr_bar=t;
   double d=50*_Point;
   if(g_atr_handle!=INVALID_HANDLE && Inp_Poi_NearAtrMult>0)
   { double a[1]; if(CopyBuffer(g_atr_handle,0,1,1,a)==1 && a[0]>0) d=a[0]*Inp_Poi_NearAtrMult; }
   if(Inp_Poi_NearMinPoints>0){ double p=Inp_Poi_NearMinPoints*_Point; if(p>d) d=p; }
   g_near_on=d; g_near_off=d*1.25;
}

bool IsMaPeak(const double &m[],int i,int n)
{ if(i<1||i+1>=n) return false; double a=m[i],b=m[i-1],c=m[i+1]; return(a!=0&&b!=0&&c!=0&&a>=b&&a>c&&CurveSharpEnough(m,i,n)); }
bool IsMaTrough(const double &m[],int i,int n)
{ if(i<1||i+1>=n) return false; double a=m[i],b=m[i-1],c=m[i+1]; return(a!=0&&b!=0&&c!=0&&a<=b&&a<c&&CurveSharpEnough(m,i,n)); }

bool PriceHitsNS(ENUM_SWING_TYPE type,double p,int i,const double &o[],const double &h[],const double &l[],const double &c[])
{
   if(Inp_Poi_UseWicksForHit) return(type==SWING_HIGH?h[i]>=p:l[i]<=p);
   return(type==SWING_HIGH?MathMax(o[i],c[i])>=p:MathMin(o[i],c[i])<=p);
}

void AddLevel(Level &a[],int &c,string pfx,datetime t,double p,ENUM_SWING_TYPE type,ENUM_LEVEL_GROUP grp)
{
   if(p==0 || IsGone(t,type,grp,pfx)) return;
   for(int i=0;i<c;i++) if(a[i].time_start==t && a[i].type==type && a[i].group==grp && StringFind(a[i].name,pfx)==0) return;
   int maxc=(grp==GRP_SWING)?XMaxCount():Inp_Poi_MaxInflections;
   if(c>=maxc){ ObjectDelete(0,a[0].name); ObjectDelete(0,a[0].name+"_P"); for(int i=1;i<c;i++) a[i-1]=a[i]; c--; }
   Level s;
   s.time_start=t; s.time_end=t; s.drawn_end=0; s.price=p; s.type=type; s.group=grp;
   s.frozen=false; s.drawn=false; s.near=false; s.frozen_at=0;
   s.drawn_color=Inp_Poi_DimColor; s.drawn_width=Inp_Poi_LineWidth;
   s.name=pfx+IntegerToString((int)type)+TimeToString(t,TIME_DATE|TIME_SECONDS);
   a[c]=s; c++;
}

void ApplyHitScanFull(int n,Level &a[],int total,const datetime &time[],const double &o[],const double &h[],const double &l[],const double &c[])
{
   if(n<0 || n>=ArraySize(a)) return;
   int sh=iBarShift(_Symbol,PERIOD_CURRENT,a[n].time_start,true);
   if(sh<0){ a[n].time_end=time[total-1]; return; }
   int origin=total-1-sh, end=Inp_Poi_IgnoreLastBar?total-2:total-1;
   if(origin>=end){ a[n].time_end=time[end]; return; }
   for(int i=origin+1;i<=end;i++)
   {
      if((i-origin)<=Inp_Poi_MitigationDelayBars) continue;
      if(PriceHitsNS(a[n].type,a[n].price,i,o,h,l,c))
      {
         a[n].time_end=time[i]; a[n].frozen=true; a[n].near=false; a[n].frozen_at=TimeCurrent();
         return;
      }
   }
   a[n].time_end=time[end]; a[n].frozen=false;
}

void RebuildInflections(const double &m[],int total,int lb,ENUM_LEVEL_GROUP grp,string pfx,Level &a[],int &c,const datetime &time[],const double &o[],const double &h[],const double &l[],const double &cl[])
{
   int old=lb+2,newest=total-2; if(newest<=old) return;
   for(int i=old;i<=newest;i++)
   {
      if(IsMaPeak(m,i,total) && !IsGone(time[i],SWING_HIGH,grp,pfx))
      {
         AddLevel(a,c,pfx,time[i],m[i],SWING_HIGH,grp);
         ApplyHitScanFull(c-1,a,total,time,o,h,l,cl);
         if(c>0 && ReadyToRemove(a[c-1])) RemoveAt(a,c,c-1); else if(c>0) CreateOrUpdateLine(a[c-1],true);
      }
      if(IsMaTrough(m,i,total) && !IsGone(time[i],SWING_LOW,grp,pfx))
      {
         AddLevel(a,c,pfx,time[i],m[i],SWING_LOW,grp);
         ApplyHitScanFull(c-1,a,total,time,o,h,l,cl);
         if(c>0 && ReadyToRemove(a[c-1])) RemoveAt(a,c,c-1); else if(c>0) CreateOrUpdateLine(a[c-1],true);
      }
   }
}

int SignTol(double value,const double tol){ if(value>tol) return 1; if(value<-tol) return -1; return 0; }

bool DetectChartCross(const double &a[],const double &b[],const int i,bool &up,bool &dn)
{
   up=false; dn=false; if(i<1) return false;
   double ap=a[i-1],ac=a[i],bp=b[i-1],bc=b[i];
   if(ap==0||ac==0||bp==0||bc==0) return false;
   double tol=MathMax(Inp_Poi_CrossTolerancePoints*_Point,_Point*0.1);
   int prev=SignTol(ap-bp,tol), cur=SignTol(ac-bc,tol);
   if(prev==0){ int j=i-1; while(j>0 && SignTol(a[j]-b[j],tol)==0) j--; prev=SignTol(a[j]-b[j],tol); }
   if(cur==0) return false;
   up=(prev<=0 && cur>0); dn=(prev>=0 && cur<0);
   return(up||dn);
}

void AddOneIntersect(const double &a[],const double &b[],int pair,int i,int total,const datetime &time[],const double &o[],const double &h[],const double &l[],const double &cl[],bool create)
{
   bool up,dn; if(!DetectChartCross(a,b,i,up,dn)) return;
   ENUM_SWING_TYPE typ=up?SWING_LOW:SWING_HIGH;
   double p=0.5*(a[i]+b[i]);
   string pfx=PREFIX_X+IntegerToString(pair)+"_";
   AddLevel(g_x,g_x_count,pfx,time[i],p,typ,GRP_SWING);
   ApplyHitScanFull(g_x_count-1,g_x,total,time,o,h,l,cl);
   if(g_x_count>0 && ReadyToRemove(g_x[g_x_count-1])) RemoveAt(g_x,g_x_count,g_x_count-1);
   else if(create && g_x_count>0) CreateOrUpdateLine(g_x[g_x_count-1],true);
}

void AddAllIntersectsAt(int i,int total,const datetime &time[],const double &o[],const double &h[],const double &l[],const double &cl[],bool create)
{
   if(!Inp_Poi_ShowIntersects) return;
   if(Inp_Poi_Intersect_MA1MA2) AddOneIntersect(MA1Buffer,MA2Buffer,12,i,total,time,o,h,l,cl,create);
   if(Inp_Poi_Intersect_MA1MA3) AddOneIntersect(MA1Buffer,MA3Buffer,13,i,total,time,o,h,l,cl,create);
   if(Inp_Poi_Intersect_MA2MA3) AddOneIntersect(MA2Buffer,MA3Buffer,23,i,total,time,o,h,l,cl,create);
}

void RebuildIntersects(int total,const datetime &time[],const double &o[],const double &h[],const double &l[],const double &cl[])
{ for(int i=2;i<=total-2;i++) AddAllIntersectsAt(i,total,time,o,h,l,cl,true); }

void TryAddConfirmedInflection(const double &m[],int total,ENUM_LEVEL_GROUP grp,string pfx,Level &a[],int &c,const datetime &time[])
{
   int i=total-2, before=c;
   if(IsMaPeak(m,i,total) && !IsGone(time[i],SWING_HIGH,grp,pfx)) AddLevel(a,c,pfx,time[i],m[i],SWING_HIGH,grp);
   if(c>before) CreateOrUpdateLine(a[c-1],true);
   before=c;
   if(IsMaTrough(m,i,total) && !IsGone(time[i],SWING_LOW,grp,pfx)) AddLevel(a,c,pfx,time[i],m[i],SWING_LOW,grp);
   if(c>before) CreateOrUpdateLine(a[c-1],true);
}

void MitigateOnly(Level &a[],int c,int test,int total,const datetime &time[],const double &o[],const double &h[],const double &l[],const double &cl[])
{
   datetime tt=time[test];
   for(int n=0;n<c;n++)
   {
      if(a[n].frozen || tt<=a[n].time_start) continue;
      int sh=iBarShift(_Symbol,PERIOD_CURRENT,a[n].time_start,true);
      if(sh<0) continue;
      int origin=total-1-sh;
      if((test-origin)<=Inp_Poi_MitigationDelayBars) continue;
      if(PriceHitsNS(a[n].type,a[n].price,test,o,h,l,cl))
      {
         a[n].time_end=tt; a[n].frozen=true; a[n].near=false; a[n].frozen_at=TimeCurrent();
         CreateOrUpdateLine(a[n],false);
      }
   }
}

void ApplyProximity(Level &a[],int c,double p)
{
   for(int n=0;n<c;n++)
   {
      if(a[n].frozen){ if(a[n].near){a[n].near=false; CreateOrUpdateLine(a[n],false);} continue; }
      double d=MathAbs(a[n].price-p);
      bool next=a[n].near;
      if(!a[n].near && d<g_near_on) next=true;
      else if(a[n].near && d>=g_near_off) next=false;
      if(next!=a[n].near){ a[n].near=next; CreateOrUpdateLine(a[n],false); }
   }
}

void ProcessPois(int total,const datetime &time[],const double &o[],const double &h[],const double &l[],const double &cl[])
{
   bool nb=(g_last_bar!=time[total-1]); if(nb) g_last_bar=time[total-1];
   if(!g_poi_ready)
   {
      if(Inp_Poi_ShowOnMA1) RebuildInflections(MA1Buffer,total,Inp_MA1_Period,GRP_HMA1,PREFIX_H1,g_inf1,g_inf1_count,time,o,h,l,cl);
      if(Inp_Poi_ShowOnMA2) RebuildInflections(MA2Buffer,total,Inp_MA2_Period,GRP_HMA2,PREFIX_H2,g_inf2,g_inf2_count,time,o,h,l,cl);
      if(Inp_Poi_ShowOnMA3) RebuildInflections(MA3Buffer,total,Inp_MA3_Period,GRP_HMA3,PREFIX_H3,g_inf3,g_inf3_count,time,o,h,l,cl);
      if(Inp_Poi_ShowIntersects) RebuildIntersects(total,time,o,h,l,cl);
      ClusterNearbyUnfrozen();
      PurgeMitigated(g_inf1,g_inf1_count); PurgeMitigated(g_inf2,g_inf2_count); PurgeMitigated(g_inf3,g_inf3_count); PurgeMitigated(g_x,g_x_count);
      g_poi_ready=true; return;
   }
   if(nb)
   {
      RefreshNearBand(time[total-1]);
      if(Inp_Poi_ShowOnMA1) TryAddConfirmedInflection(MA1Buffer,total,GRP_HMA1,PREFIX_H1,g_inf1,g_inf1_count,time);
      if(Inp_Poi_ShowOnMA2) TryAddConfirmedInflection(MA2Buffer,total,GRP_HMA2,PREFIX_H2,g_inf2,g_inf2_count,time);
      if(Inp_Poi_ShowOnMA3) TryAddConfirmedInflection(MA3Buffer,total,GRP_HMA3,PREFIX_H3,g_inf3,g_inf3_count,time);
      if(Inp_Poi_ShowIntersects) AddAllIntersectsAt(total-2,total,time,o,h,l,cl,true);
      ClusterNearbyUnfrozen();
      int test=Inp_Poi_IgnoreLastBar?total-2:total-1;
      if(Inp_Poi_ShowOnMA1) MitigateOnly(g_inf1,g_inf1_count,test,total,time,o,h,l,cl);
      if(Inp_Poi_ShowOnMA2) MitigateOnly(g_inf2,g_inf2_count,test,total,time,o,h,l,cl);
      if(Inp_Poi_ShowOnMA3) MitigateOnly(g_inf3,g_inf3_count,test,total,time,o,h,l,cl);
      if(Inp_Poi_ShowIntersects) MitigateOnly(g_x,g_x_count,test,total,time,o,h,l,cl);
      PurgeMitigated(g_inf1,g_inf1_count); PurgeMitigated(g_inf2,g_inf2_count); PurgeMitigated(g_inf3,g_inf3_count); PurgeMitigated(g_x,g_x_count);
   }
   if(g_near_on<=0) RefreshNearBand(time[total-1]);
   double p=cl[total-1];
   if(Inp_Poi_ShowOnMA1) ApplyProximity(g_inf1,g_inf1_count,p);
   if(Inp_Poi_ShowOnMA2) ApplyProximity(g_inf2,g_inf2_count,p);
   if(Inp_Poi_ShowOnMA3) ApplyProximity(g_inf3,g_inf3_count,p);
   if(Inp_Poi_ShowIntersects) ApplyProximity(g_x,g_x_count,p);
}

void OnChartEvent(const int id,const long &l,const double &d,const string &s)
{ if(id==CHARTEVENT_CHART_CHANGE) RepositionAllPriceLabels(); }

int OnInit()
{
   SetIndexBuffer(0,MA1Buffer,INDICATOR_DATA); PlotIndexSetInteger(0,PLOT_LINE_COLOR,Inp_MA1_LineColor);
   SetIndexBuffer(1,MA2Buffer,INDICATOR_DATA); PlotIndexSetInteger(1,PLOT_LINE_COLOR,Inp_MA2_LineColor);
   SetIndexBuffer(2,MA3Buffer,INDICATOR_DATA); PlotIndexSetInteger(2,PLOT_LINE_COLOR,Inp_MA3_LineColor);
   IndicatorSetString(INDICATOR_SHORTNAME,"HMA+PoI");

   //--- FIX #1/#2: MA1 now goes through the same generic InitCustomMA as MA2/MA3.
   InitCustomMA(Inp_MA1_Type,Inp_MA1_Period,Inp_MA1_AppliedPrice,ResolveTF(Inp_MA1_Timeframe),hMA1,hMA1Half,hMA1Full,hMA1Price,arrMA1Half,arrMA1Full);
   InitCustomMA(Inp_MA2_Type,Inp_MA2_Period,Inp_MA2_AppliedPrice,ResolveTF(Inp_MA2_Timeframe),hMA2,hMA2Half,hMA2Full,hMA2Price,arrMA2Half,arrMA2Full);
   InitCustomMA(Inp_MA3_Type,Inp_MA3_Period,Inp_MA3_AppliedPrice,ResolveTF(Inp_MA3_Timeframe),hMA3,hMA3Half,hMA3Full,hMA3Price,arrMA3Half,arrMA3Full);

   ArrayResize(g_inf1,Inp_Poi_MaxInflections); ArrayResize(g_inf2,Inp_Poi_MaxInflections); ArrayResize(g_inf3,Inp_Poi_MaxInflections);
   ArrayResize(g_x,MathMax(Inp_Poi_MaxInflections*3,180)); ArrayResize(g_gone_ids,MAX_GONE);
   g_atr_handle=iATR(_Symbol,PERIOD_CURRENT,Inp_Poi_AtrPeriod);
   g_poi_ready=false; g_gone_count=0;
   ObjectsDeleteAll(0,OBJ_PREFIX);
   ObjectsDeleteAll(0,PREFIX_H1); ObjectsDeleteAll(0,PREFIX_H2); ObjectsDeleteAll(0,PREFIX_H3); ObjectsDeleteAll(0,PREFIX_X);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(reason==REASON_REMOVE || reason==REASON_CHARTCHANGE || reason==REASON_TEMPLATE)
   {
      ObjectsDeleteAll(0,OBJ_PREFIX);
      ObjectsDeleteAll(0,PREFIX_H1); ObjectsDeleteAll(0,PREFIX_H2); ObjectsDeleteAll(0,PREFIX_H3); ObjectsDeleteAll(0,PREFIX_X);
   }
   if(g_atr_handle!=INVALID_HANDLE) IndicatorRelease(g_atr_handle);
}

int OnCalculate(const int total,const int prev,const datetime &time[],const double &o[],const double &h[],const double &l[],const double &cl[],const long &tv[],const long &v[],const int &sp[])
{
   if(total<Inp_MA1_Period) return prev;

   if(!FillMA(Inp_MA1_Timeframe,Inp_MA1_Type,Inp_MA1_Period,Inp_MA1_PostSmoothType,Inp_MA1_PostSmoothPeriod,total,prev,time,hMA1,hMA1Half,hMA1Full,hMA1Price,arrMA1Half,arrMA1Full,g_htf1,g_raw1,MA1Buffer)) return(prev>0?prev:0);
   if(!FillMA(Inp_MA2_Timeframe,Inp_MA2_Type,Inp_MA2_Period,Inp_MA2_PostSmoothType,Inp_MA2_PostSmoothPeriod,total,prev,time,hMA2,hMA2Half,hMA2Full,hMA2Price,arrMA2Half,arrMA2Full,g_htf2,g_raw2,MA2Buffer)) return(prev>0?prev:0);
   if(!FillMA(Inp_MA3_Timeframe,Inp_MA3_Type,Inp_MA3_Period,Inp_MA3_PostSmoothType,Inp_MA3_PostSmoothPeriod,total,prev,time,hMA3,hMA3Half,hMA3Full,hMA3Price,arrMA3Half,arrMA3Full,g_htf3,g_raw3,MA3Buffer)) return(prev>0?prev:0);

   RunBreakoutSignals(total,time,o,h,l,cl);
   RunPriceCrossAlert(total,time,o,h,l,cl);
   //--- FIX #4: Setup 2 (MA Crossover) removed per request.
   ProcessPois(total,time,o,h,l,cl);
   return total;
}
//+------------------------------------------------------------------+