//+------------------------------------------------------------------+
//| MA_Inflection_AI_EA.mq5   v1.30                                  |
//| MA Inflection Levels v3 -> AI-driven EA                          |
//| - Level engine + drawing ported 1:1 from the indicator           |
//| - Requests: inflection proximity, MA cross, MANAGE, MANUAL button|
//| - Trade management: partials, SL->BE, DD entries, $ close of     |
//|   worst DD entries, trailing after N points                      |
//| - InpTestMode: ask AI, only log decision in Experts journal      |
//| Allow your AI URL: Tools > Options > Expert Advisors > WebRequest|
//+------------------------------------------------------------------+
#property copyright "MA Inflection AI EA"
#property version   "1.30"
#property strict
#include <Trade/Trade.mqh>

enum ENUM_MA_KIND    { KIND_ALMA,KIND_DEMA,KIND_EMA,KIND_HMA,KIND_HULLMA,KIND_LSMA,KIND_RMA,KIND_SMMA,KIND_SSMA,KIND_TMA,KIND_TEMA,KIND_VWMA,KIND_WMA,KIND_VWAP };
enum ENUM_MEASURE    { MEASURE_HL, MEASURE_CLOSE };
enum ENUM_MITIGATION { MIT_WICK, MIT_BCC, MIT_MACROSS };

input group "AI Endpoint"
input string InpAiUrl        = "https://your-server/decision"; // AI URL (add to WebRequest allow-list)
input string InpAiKey        = "";      // Bearer token (optional)
input int    InpAiTimeoutMs  = 20000;   // Wait for AI decision (ms)
input int    InpCandles      = 50;      // Candles per timeframe (M15,M5,M3,M1)
input bool   InpSendExtra    = true;    // Send account/symbol constraints + nearby levels

input group "Testing"
input bool   InpTestMode         = true;   // TEST: ask AI, only log decision, NO trading
input int    InpTestIntervalSec  = 60;     // TEST: send nearest level to AI every N sec (0 = normal proximity trigger)
input bool   InpTestAnyDistance  = true;   // TEST: nearest live level at any distance (false = within InpTriggerPts)
input bool   InpLogPayload       = false;  // TEST: print JSON sent to AI
input bool   InpLogRawReply      = true;   // TEST: print raw AI reply

input group "Triggers"
input double InpTriggerPts   = 150;     // Ask AI when price within X points of a level
input int    InpLevelCoolMin = 15;      // Min minutes before re-asking same level (same life)
input int    InpMgmtSec      = 60;      // Ask AI to manage open trades every N sec (0=off)
input int    InpPendingMin   = 60;      // Pending expiry (min) if AI gives none

input group "MA Cross Request"
input bool            InpCrossOn         = true;
input bool            InpCrossMa1        = true;
input bool            InpCrossMa2        = false;
input bool            InpCrossMa3        = false;
input ENUM_TIMEFRAMES InpCrossTF         = PERIOD_CURRENT;
input bool            InpCrossNeedEngulf = false;
input bool            InpCrossDebug      = true;
input int             InpCrossScanBars   = 0;       // TEST ONLY
input bool            InpCrossForceSend  = false;   // TEST ONLY

input group "Manual Analysis"
input bool InpShowButton    = true;    // Show "Analyze current market" button
input bool InpManualExecute = false;   // false = manual requests only log the decision

input group "Trade Management"
input double InpPartialPct      = 20;     // Each partial closes X% of the REMAINING volume
input int    InpDefaultPartials = 0;      // Partials generated when AI gives none (0 = none)
input int    InpDefaultDD       = 2;      // DD entries when AI gives none (same lot, SL, TP)
input double InpDDCloseUSD      = 10.0;   // With DD fills: close older entries once each is +$X, keep the latest
input int    InpTrailStartPts   = 1000;   // After X points profit: remove TP and start trailing (0=off)
input int    InpTrailDistPts    = 600;    // Trailing distance (points)
input int    InpTrailStepPts    = 10;     // Min SL improvement per trail update (points)
input int    InpDDExpiryMin     = 0;      // DD limit expiry (0 = until setup ends)
input int    InpMinConfidence   = 0;      // Reject entries below this confidence (0 = off)

input group "Safety Limits"
input bool   InpRequireSL    = true;
input double InpDefaultLot   = 0.10;      // used when AI lot = 0
input double InpMaxLot       = 20.0;      // max single order lot (AI range is 0-20)
input double InpMaxTotalLot  = 60.0;      // max total lots (main + DD)
input int    InpMaxDD        = 2;         // max DD entries per setup
input double InpMaxSlipPts   = 100;
input double InpMaxSpreadPts = 80;
input ulong  InpMagic        = 770011;
input bool   InpAllowEntries = true;

input group "Calculation"
input int    InpMaxBars = 10000;

input group "MA 1"
input bool InpMa1On = true;  input ENUM_TIMEFRAMES InpMa1TF = PERIOD_M3; input bool InpMa1Lvl = true;
input ENUM_MA_KIND InpMa1Type = KIND_HMA; input ENUM_APPLIED_PRICE InpMa1Src = PRICE_CLOSE; input int InpMa1Len = 21;
input group "MA 2"
input bool InpMa2On = true;  input ENUM_TIMEFRAMES InpMa2TF = PERIOD_M3; input bool InpMa2Lvl = true;
input ENUM_MA_KIND InpMa2Type = KIND_EMA; input ENUM_APPLIED_PRICE InpMa2Src = PRICE_CLOSE; input int InpMa2Len = 50;
input group "MA 3"
input bool InpMa3On = true;  input ENUM_TIMEFRAMES InpMa3TF = PERIOD_M3; input bool InpMa3Lvl = true;
input ENUM_MA_KIND InpMa3Type = KIND_RMA; input ENUM_APPLIED_PRICE InpMa3Src = PRICE_CLOSE; input int InpMa3Len = 100;

input group "Inflection Lines"
input ENUM_MEASURE    InpMeasure = MEASURE_HL;
input double InpConfirm = 800;
input double InpOppDst  = 1000;
input double InpSameDst = 800;
input ENUM_MITIGATION InpMitMode = MIT_BCC;
input int    InpMaxMit  = 3;
input bool   InpMitAway = true;
input double InpMitAwayPts = 300;
input double InpCluster = 400;
input double InpVOff    = 0.0;

input group "Display"
input bool   InpDraw        = true;
input color  InpMa1Color    = clrAqua;
input color  InpMa2Color    = clrYellow;
input color  InpMa3Color    = clrViolet;
input int    InpMaWidth     = 2;
input int    InpMaDrawBars  = 500;
input int    InpTransp      = 70;
input double InpNearDst     = 50;
input double InpFarDst      = 500;
input int    InpDelMin      = 500;
input color  InpPeakColor   = clrTomato;
input color  InpBotColor    = clrSpringGreen;
input color  InpMitColor    = clrGray;
input int    InpFontSize    = 8;

struct SLevel { int id; string ln; string lb; int type; double lvl; double y; int side; int cnt; bool flag; bool away; };
struct SDone  { string ln; string lb; datetime t; };
struct SMA {
   bool on, lvl; ENUM_TIMEFRAMES tf, ftf; ENUM_MA_KIND type; ENUM_APPLIED_PRICE src; int len; string tag, prefix;
   datetime lastHTF; int htfN; datetime htfT[]; double hO[],hH[],hL[],hC[]; long hV[];
   double px[],buf[],a1[],b1[],c1[],d1[],cpv[],cv[],w[]; double wn,k1,k2,k3;
   SLevel act[]; SDone done[]; int dir,dirPrev,candType; double candLvl; datetime candTime; int seq;
};
struct SPart  { double price; double pct; bool done; };
struct SSetup { SPart parts[]; double beSl; bool beDone; };
struct SCool  { string key; datetime t; };

SMA      g_ma[3];
CTrade   g_trade;
SSetup   g_set[2];            // 0 = BUY setup, 1 = SELL setup
SCool    g_cool[];
datetime g_lastMgmt = 0;
datetime g_lastTest = 0;
datetime g_lastChartBar = 0;
datetime g_crossBar = 0;
bool     g_scanDone = false;
color    g_bg = clrBlack;
string   g_base = "";
string   g_lvlExtra = "";
string   g_crossExtra = "";
const string BTN = "AIEA_BTN_ANALYZE";
bool     g_manualReq = false;
bool     g_busy = false;

//==================== MA helpers ===================================
double SMAat(const double &a[],const int i,const int len){
   if(len<1||i-len+1<0) return EMPTY_VALUE; double s=0;
   for(int k=i-len+1;k<=i;k++){ if(a[k]==EMPTY_VALUE) return EMPTY_VALUE; s+=a[k]; } return s/len; }
double WMAat(const double &a[],const int i,const int len){
   if(len<1||i-len+1<0) return EMPTY_VALUE; double num=0;
   for(int k=0;k<len;k++){ double v=a[i-len+1+k]; if(v==EMPTY_VALUE) return EMPTY_VALUE; num+=v*(k+1); }
   return num/(len*(len+1)/2.0); }
double ALMAat(const double &a[],const int i,const int len,const double &w[],const double norm){
   if(i-len+1<0) return EMPTY_VALUE; double s=0;
   for(int k=0;k<len;k++){ double v=a[i-len+1+k]; if(v==EMPTY_VALUE) return EMPTY_VALUE; s+=v*w[k]; } return s/norm; }
double LSMAat(const double &a[],const int i,const int len){
   if(i-len+1<0) return EMPTY_VALUE; double sx=0,sy=0,sxy=0,sxx=0;
   for(int k=0;k<len;k++){ double v=a[i-len+1+k]; if(v==EMPTY_VALUE) return EMPTY_VALUE; sx+=k; sy+=v; sxy+=k*v; sxx+=(double)k*k; }
   double n=len, den=n*sxx-sx*sx; if(den==0) return sy/n;
   double slope=(n*sxy-sx*sy)/den, icpt=(sy-slope*sx)/n; return icpt+slope*(n-1); }
void EMAstep(const double &src[],double &out[],const int i,const int len){
   if(src[i]==EMPTY_VALUE){ out[i]=EMPTY_VALUE; return; }
   double al=2.0/(len+1.0);
   if(i==0||out[i-1]==EMPTY_VALUE) out[i]=src[i]; else out[i]=al*src[i]+(1.0-al)*out[i-1]; }
void RMAstep(const double &src[],double &out[],const int i,const int len){
   if(i>0&&out[i-1]!=EMPTY_VALUE&&src[i]!=EMPTY_VALUE) out[i]=(src[i]+(len-1)*out[i-1])/len;
   else out[i]=SMAat(src,i,len); }
void SSstep(const double &src[],double &out[],const int i,const double c1,const double c2,const double c3){
   double s=src[i], s1=(i>=1)?src[i-1]:s;
   double f1=(i>=1&&out[i-1]!=EMPTY_VALUE)?out[i-1]:s, f2=(i>=2&&out[i-2]!=EMPTY_VALUE)?out[i-2]:s;
   out[i]=c1*(s+s1)/2.0+c2*f1+c3*f2; }

double PriceAtM(SMA &M,const int i){
   switch(M.src){
      case PRICE_OPEN: return M.hO[i]; case PRICE_HIGH: return M.hH[i]; case PRICE_LOW: return M.hL[i];
      case PRICE_MEDIAN: return (M.hH[i]+M.hL[i])/2.0;
      case PRICE_TYPICAL: return (M.hH[i]+M.hL[i]+M.hC[i])/3.0;
      case PRICE_WEIGHTED: return (M.hH[i]+M.hL[i]+2.0*M.hC[i])/4.0;
      default: return M.hC[i]; } }

void ComputeMA(SMA &M,const int i){
   const int len=M.len; double v=EMPTY_VALUE;
   switch(M.type){
      case KIND_ALMA: v=ALMAat(M.px,i,len,M.w,M.wn); break;
      case KIND_DEMA: { EMAstep(M.px,M.a1,i,len); EMAstep(M.a1,M.b1,i,len);
         v=(M.a1[i]!=EMPTY_VALUE&&M.b1[i]!=EMPTY_VALUE)?2.0*M.a1[i]-M.b1[i]:EMPTY_VALUE; break; }
      case KIND_EMA: EMAstep(M.px,M.a1,i,len); v=M.a1[i]; break;
      case KIND_HMA: { int half=MathMax(1,len/2); int root=MathMax(1,(int)MathRound(MathSqrt(len)));
         M.a1[i]=WMAat(M.px,i,half); M.b1[i]=WMAat(M.px,i,len);
         M.c1[i]=(M.a1[i]!=EMPTY_VALUE&&M.b1[i]!=EMPTY_VALUE)?2.0*M.a1[i]-M.b1[i]:EMPTY_VALUE;
         v=WMAat(M.c1,i,root); break; }
      case KIND_HULLMA: { int half=MathMax(1,(int)MathRound(len/2.0)); int root=MathMax(1,(int)MathRound(MathSqrt(len)));
         EMAstep(M.px,M.a1,i,half); EMAstep(M.px,M.b1,i,len);
         M.c1[i]=(M.a1[i]!=EMPTY_VALUE&&M.b1[i]!=EMPTY_VALUE)?2.0*M.a1[i]-M.b1[i]:EMPTY_VALUE;
         EMAstep(M.c1,M.d1,i,root); v=M.d1[i]; break; }
      case KIND_LSMA: v=LSMAat(M.px,i,len); break;
      case KIND_RMA: case KIND_SMMA: RMAstep(M.px,M.a1,i,len); v=M.a1[i]; break;
      case KIND_SSMA: SSstep(M.px,M.a1,i,M.k1,M.k2,M.k3); v=M.a1[i]; break;
      case KIND_TMA: { int a=(int)MathCeil(len/2.0); int b=(int)MathFloor(len/2.0)+1;
         M.a1[i]=SMAat(M.px,i,a); v=SMAat(M.a1,i,b); break; }
      case KIND_TEMA: EMAstep(M.px,M.a1,i,len); EMAstep(M.a1,M.b1,i,len); EMAstep(M.b1,M.c1,i,len);
         v=(M.a1[i]!=EMPTY_VALUE&&M.b1[i]!=EMPTY_VALUE&&M.c1[i]!=EMPTY_VALUE)?3.0*(M.a1[i]-M.b1[i])+M.c1[i]:EMPTY_VALUE; break;
      case KIND_VWMA: { if(i-len+1<0){ v=EMPTY_VALUE; break; } double spv=0,sv=0; bool ok=true;
         for(int k=i-len+1;k<=i;k++){ if(M.px[k]==EMPTY_VALUE){ ok=false; break; } spv+=M.px[k]*(double)M.hV[k]; sv+=(double)M.hV[k]; }
         v=(ok&&sv>0)?spv/sv:EMPTY_VALUE; break; }
      case KIND_WMA: v=WMAat(M.px,i,len); break;
      case KIND_VWAP: { bool nd=(i==0)||(M.cpv[i-1]==EMPTY_VALUE)||((long)M.htfT[i]/86400!=(long)M.htfT[i-1]/86400);
         double pv=(nd?0.0:M.cpv[i-1])+M.px[i]*(double)M.hV[i]; double vv=(nd?0.0:M.cv[i-1])+(double)M.hV[i];
         M.cpv[i]=pv; M.cv[i]=vv; v=(vv>0)?pv/vv:M.px[i]; break; }
   }
   M.buf[i]=v; }

//==================== Drawing helpers ==============================
color Blend(const color c,const color bg,const int transp){
   double t=MathMax(0,MathMin(100,transp))/100.0; uint cu=(uint)c,bu=(uint)bg;
   int r1=(int)(cu&0xFF),g1=(int)((cu>>8)&0xFF),b1=(int)((cu>>16)&0xFF);
   int r2=(int)(bu&0xFF),g2=(int)((bu>>8)&0xFF),b2=(int)((bu>>16)&0xFF);
   return (color)((int)MathRound(r1*(1-t)+r2*t)|((int)MathRound(g1*(1-t)+g2*t)<<8)|((int)MathRound(b1*(1-t)+b2*t)<<16)); }
string Lbl(const double y,const int lives){
   string s=DoubleToString(y,_Digits);
   if(lives>0){ s+=" "; for(int k=0;k<lives;k++) s+=ShortToString(0x2665); } else s+=" "+ShortToString(0x00D7);
   return s; }
double Proximity(const double y,const double px){
   double d=MathAbs(px-y)/_Point, nearD=MathMax(0.0,InpNearDst), farD=MathMax(InpFarDst,nearD+1.0);
   if(d<=nearD) return 1.0; if(d>=farD) return 0.0; return 1.0-(d-nearD)/(farD-nearD); }
color LevelColor(const SLevel &L,const double px){
   int effT=(L.cnt%2==0)?L.type:-L.type; color bc=(effT==1)?InpPeakColor:InpBotColor;
   return Blend(bc,g_bg,(int)MathRound(InpTransp*(1.0-Proximity(L.y,px)))); }
void UpdateProximity(const double px){
   if(!InpDraw) return; bool changed=false;
   for(int m=0;m<3;m++){ if(!g_ma[m].on||!g_ma[m].lvl) continue;
      for(int k=0;k<ArraySize(g_ma[m].act);k++){ color fc=LevelColor(g_ma[m].act[k],px);
         if((color)ObjectGetInteger(0,g_ma[m].act[k].ln,OBJPROP_COLOR)!=fc){
            ObjectSetInteger(0,g_ma[m].act[k].ln,OBJPROP_COLOR,fc); ObjectSetInteger(0,g_ma[m].act[k].lb,OBJPROP_COLOR,fc); changed=true; } } }
   if(changed) ChartRedraw(0); }

//==================== Level engine =================================
bool Beyond(const int sd,const double y,const double m,const double hi,const double lo,const double cl){
   switch(InpMitMode){
      case MIT_WICK: return (sd==-1)?(hi>=y):(lo<=y);
      case MIT_MACROSS: if(m==EMPTY_VALUE) return false; return (sd==-1)?(m>y):(m<y);
      default: return (sd==-1)?(cl>y):(cl<y); } }
void RemoveAct(SMA &M,const int k){ int n=ArraySize(M.act); for(int j=k;j<n-1;j++) M.act[j]=M.act[j+1]; ArrayResize(M.act,n-1); }
void RemoveDone(SMA &M,const int k){ int n=ArraySize(M.done); for(int j=k;j<n-1;j++) M.done[j]=M.done[j+1]; ArrayResize(M.done,n-1); }
void ResetAll(SMA &M){
   if(StringLen(M.prefix)>0) ObjectsDeleteAll(0,M.prefix);
   ArrayResize(M.act,0); ArrayResize(M.done,0);
   M.dir=0; M.dirPrev=0; M.candType=0; M.candLvl=0; M.candTime=0; M.seq=0; }

void ProcessBar(SMA &M,const int i){
   const double pt=_Point, hi=M.hH[i], lo=M.hL[i], cl=M.hC[i], mav=M.buf[i];
   const datetime tNext=M.htfT[i+1], tI=M.htfT[i];
   const datetime tLbl=tNext+(datetime)PeriodSeconds(M.ftf);
   const bool isLast=(i==M.htfN-2);
   const double awayPts=MathMax(0.0,InpMitAwayPts)*pt;
   const bool needAway=(InpMitAway&&awayPts>0.0);
   for(int k=ArraySize(M.act)-1;k>=0;k--){
      int sdi=M.act[k].side;
      bool beyond=Beyond(sdi,M.act[k].y,mav,hi,lo,cl);
      const bool wasAway=M.act[k].away;
      if(needAway&&!M.act[k].away&&(hi>=M.act[k].y+awayPts||lo<=M.act[k].y-awayPts)) M.act[k].away=true;
      if(beyond&&!M.act[k].flag&&(!needAway||wasAway)){
         M.act[k].cnt++; M.act[k].away=!needAway;
         double refPx=(InpMitMode==MIT_MACROSS&&mav!=EMPTY_VALUE)?mav:cl;
         sdi=(refPx<M.act[k].y)?-1:1; M.act[k].side=sdi;
         beyond=Beyond(sdi,M.act[k].y,mav,hi,lo,cl);
         if(needAway){ if(sdi==-1&&lo<=M.act[k].y-awayPts) M.act[k].away=true; if(sdi==1&&hi>=M.act[k].y+awayPts) M.act[k].away=true; }
      }
      M.act[k].flag=beyond;
      if(M.act[k].cnt>=InpMaxMit){
         color mc=Blend(InpMitColor,g_bg,InpTransp);
         ObjectSetInteger(0,M.act[k].ln,OBJPROP_TIME,1,tI);
         ObjectSetInteger(0,M.act[k].ln,OBJPROP_COLOR,mc);
         ObjectSetInteger(0,M.act[k].lb,OBJPROP_TIME,0,tNext);
         ObjectSetInteger(0,M.act[k].lb,OBJPROP_COLOR,mc);
         ObjectSetString (0,M.act[k].lb,OBJPROP_TEXT,Lbl(M.act[k].y,0));
         if(InpDelMin>0){ int nd=ArraySize(M.done); ArrayResize(M.done,nd+1);
            M.done[nd].ln=M.act[k].ln; M.done[nd].lb=M.act[k].lb; M.done[nd].t=tI; }
         RemoveAct(M,k);
      }
      else if(isLast){
         color fc=LevelColor(M.act[k],cl);
         ObjectSetInteger(0,M.act[k].ln,OBJPROP_TIME,1,tNext); ObjectSetInteger(0,M.act[k].ln,OBJPROP_COLOR,fc);
         ObjectSetInteger(0,M.act[k].lb,OBJPROP_TIME,0,tLbl);  ObjectSetInteger(0,M.act[k].lb,OBJPROP_COLOR,fc);
         ObjectSetString (0,M.act[k].lb,OBJPROP_TEXT,Lbl(M.act[k].y,InpMaxMit-M.act[k].cnt));
      }
   }
   if(InpDelMin>0)
      for(int d=ArraySize(M.done)-1;d>=0;d--)
         if((long)(tI-M.done[d].t)>=(long)InpDelMin*60){ ObjectDelete(0,M.done[d].ln); ObjectDelete(0,M.done[d].lb); RemoveDone(M,d); }

   int lastType=0; double lastLvl=0.0; int na=ArraySize(M.act);
   if(na>0){ lastType=M.act[na-1].type; lastLvl=M.act[na-1].lvl; }
   M.dirPrev=M.dir;
   if(i>=1&&M.buf[i]!=EMPTY_VALUE&&M.buf[i-1]!=EMPTY_VALUE){ if(M.buf[i]>M.buf[i-1]) M.dir=1; else if(M.buf[i]<M.buf[i-1]) M.dir=-1; }
   bool flipTop=(M.dir==-1&&M.dirPrev==1), flipBot=(M.dir==1&&M.dirPrev==-1);
   double lvl=(i>=1)?M.buf[i-1]:EMPTY_VALUE;
   if(flipTop&&lvl!=EMPTY_VALUE){
      bool okT=(lastType==0)||(lvl>=lastLvl+(lastType==1?InpSameDst:InpOppDst)*pt);
      if(okT&&(M.candType!=1||lvl>M.candLvl)){ M.candType=1; M.candLvl=lvl; M.candTime=M.htfT[i-1]; } }
   if(flipBot&&lvl!=EMPTY_VALUE){
      bool okB=(lastType==0)||(lvl<=lastLvl-(lastType==-1?InpSameDst:InpOppDst)*pt);
      if(okB&&(M.candType!=-1||lvl<M.candLvl)){ M.candType=-1; M.candLvl=lvl; M.candTime=M.htfT[i-1]; } }
   if(M.candType!=0){
      bool useClose=(InpMeasure==MEASURE_CLOSE);
      double pxDown=useClose?cl:lo, pxUp=useClose?cl:hi;
      bool moved=(M.candType==1)?(pxDown<=M.candLvl-InpConfirm*pt):(pxUp>=M.candLvl+InpConfirm*pt);
      if(moved){
         bool keepIt=true; int nAct=ArraySize(M.act);
         for(int k=0;k<nAct;k++)
            if(M.act[k].type==M.candType&&MathAbs(M.act[k].lvl-M.candLvl)<=InpCluster*pt)
               if((M.candType==1&&M.act[k].lvl>=M.candLvl)||(M.candType==-1&&M.act[k].lvl<=M.candLvl)) keepIt=false;
         if(keepIt){
            for(int k=ArraySize(M.act)-1;k>=0;k--)
               if(M.act[k].type==M.candType&&MathAbs(M.act[k].lvl-M.candLvl)<=InpCluster*pt){
                  ObjectDelete(0,M.act[k].ln); ObjectDelete(0,M.act[k].lb); RemoveAct(M,k); }
            double yC=M.candLvl+M.candType*InpVOff*pt; int sdC=(cl<yC)?-1:1;
            color bc=(M.candType==1)?InpPeakColor:InpBotColor;
            color c0=Blend(bc,g_bg,(int)MathRound(InpTransp*(1.0-Proximity(yC,cl))));
            M.seq++;
            string ln=M.prefix+"L"+IntegerToString(M.seq), lb=M.prefix+"T"+IntegerToString(M.seq);
            ObjectCreate(0,ln,OBJ_TREND,0,M.candTime,yC,tNext,yC);
            ObjectSetInteger(0,ln,OBJPROP_COLOR,c0); ObjectSetInteger(0,ln,OBJPROP_STYLE,STYLE_DASH); ObjectSetInteger(0,ln,OBJPROP_WIDTH,1);
            ObjectSetInteger(0,ln,OBJPROP_RAY_RIGHT,false); ObjectSetInteger(0,ln,OBJPROP_SELECTABLE,false);
            ObjectSetInteger(0,ln,OBJPROP_HIDDEN,true); ObjectSetInteger(0,ln,OBJPROP_BACK,false);
            ObjectCreate(0,lb,OBJ_TEXT,0,tLbl,yC);
            ObjectSetString(0,lb,OBJPROP_TEXT,Lbl(yC,InpMaxMit)); ObjectSetString(0,lb,OBJPROP_FONT,"Arial");
            ObjectSetInteger(0,lb,OBJPROP_FONTSIZE,InpFontSize); ObjectSetInteger(0,lb,OBJPROP_COLOR,c0);
            ObjectSetInteger(0,lb,OBJPROP_ANCHOR,ANCHOR_LEFT); ObjectSetInteger(0,lb,OBJPROP_SELECTABLE,false); ObjectSetInteger(0,lb,OBJPROP_HIDDEN,true);
            int n=ArraySize(M.act); ArrayResize(M.act,n+1);
            M.act[n].id=M.seq; M.act[n].ln=ln; M.act[n].lb=lb; M.act[n].type=M.candType; M.act[n].lvl=M.candLvl; M.act[n].y=yC;
            M.act[n].side=sdC; M.act[n].cnt=0; M.act[n].away=true; M.act[n].flag=Beyond(sdC,yC,mav,hi,lo,cl);
         }
         M.candType=0;
      }
   } }

void ComputeAll(SMA &M,const int n){
   ResetAll(M);
   ArrayResize(M.px,n); ArrayResize(M.buf,n); ArrayResize(M.a1,n); ArrayResize(M.b1,n);
   ArrayResize(M.c1,n); ArrayResize(M.d1,n); ArrayResize(M.cpv,n); ArrayResize(M.cv,n);
   ArrayInitialize(M.buf,EMPTY_VALUE); ArrayInitialize(M.a1,EMPTY_VALUE); ArrayInitialize(M.b1,EMPTY_VALUE);
   ArrayInitialize(M.c1,EMPTY_VALUE); ArrayInitialize(M.d1,EMPTY_VALUE); ArrayInitialize(M.cpv,EMPTY_VALUE); ArrayInitialize(M.cv,EMPTY_VALUE);
   for(int i=0;i<n;i++){ M.px[i]=PriceAtM(M,i); ComputeMA(M,i); }
   if(M.lvl) for(int i=1;i<=n-2;i++) ProcessBar(M,i); }

bool UpdateMA(SMA &M){
   if(!M.on) return false;
   ENUM_TIMEFRAMES tf=(M.tf==PERIOD_CURRENT)?_Period:M.tf;
   if(PeriodSeconds(tf)<PeriodSeconds(_Period)) tf=_Period;
   M.ftf=tf;
   datetime cur=iTime(_Symbol,tf,0); if(cur==0) return false;
   if(cur==M.lastHTF&&M.htfN>0){
      MqlRates R1[];
      if(CopyRates(_Symbol,tf,0,1,R1)==1){ int j=M.htfN-1;
         M.hO[j]=R1[0].open; M.hH[j]=R1[0].high; M.hL[j]=R1[0].low; M.hC[j]=R1[0].close; M.hV[j]=(long)R1[0].tick_volume;
         M.px[j]=PriceAtM(M,j); ComputeMA(M,j); }
      return false; }
   MqlRates R[]; int nb=iBars(_Symbol,tf); int cnt=(InpMaxBars>0)?MathMin(InpMaxBars,nb):nb;
   int n=CopyRates(_Symbol,tf,0,cnt,R); if(n<2) return false;
   ArrayResize(M.htfT,n); ArrayResize(M.hO,n); ArrayResize(M.hH,n); ArrayResize(M.hL,n); ArrayResize(M.hC,n); ArrayResize(M.hV,n);
   for(int k=0;k<n;k++){ M.htfT[k]=R[k].time; M.hO[k]=R[k].open; M.hH[k]=R[k].high; M.hL[k]=R[k].low; M.hC[k]=R[k].close; M.hV[k]=(long)R[k].tick_volume; }
   M.htfN=n; M.lastHTF=cur; ComputeAll(M,n); return true; }

void InitMA(SMA &M,bool on,bool lvl,ENUM_TIMEFRAMES tf,ENUM_MA_KIND t,ENUM_APPLIED_PRICE s,int len,string tag){
   M.on=on; M.lvl=lvl; M.tf=tf; M.ftf=_Period; M.type=t; M.src=s; M.len=len; M.tag=tag; M.prefix=g_base+tag+"_"; M.lastHTF=0; M.htfN=0;
   ArrayResize(M.w,len); double m=MathFloor(0.85*(len-1)); double sg=len/6.0; M.wn=0;
   for(int k=0;k<len;k++){ M.w[k]=MathExp(-((k-m)*(k-m))/(2.0*sg*sg)); M.wn+=M.w[k]; }
   double a1=MathExp(-1.414*M_PI/len); double b1=2.0*a1*MathCos(1.414*M_PI/len);
   M.k2=b1; M.k3=-a1*a1; M.k1=1.0-M.k2-M.k3; ResetAll(M); }

int FindIdx(const SMA &M,const long t,const long per){
   int lo=0,hi=M.htfN-1,res=-1;
   while(lo<=hi){ int mid=(lo+hi)>>1; if((long)M.htfT[mid]+per<=t){ res=mid; lo=mid+1; } else hi=mid-1; }
   return res; }

double MAAtTime(const int m,const datetime t){
   if(!g_ma[m].on||g_ma[m].htfN==0) return EMPTY_VALUE;
   const long per=(long)PeriodSeconds(g_ma[m].ftf); const int n=g_ma[m].htfN;
   int k=FindIdx(g_ma[m],(long)t,per); if(k<0||g_ma[m].buf[k]==EMPTY_VALUE) return EMPTY_VALUE;
   if(k+1<n&&g_ma[m].buf[k+1]!=EMPTY_VALUE){
      double fr=MathMax(0.0,MathMin(1.0,(double)((long)t-((long)g_ma[m].htfT[k]+per))/(double)per));
      return g_ma[m].buf[k]+(g_ma[m].buf[k+1]-g_ma[m].buf[k])*fr; }
   return g_ma[m].buf[k]; }

void DrawLevels(){
   if(!InpDraw) return;
   color cols[3]; cols[0]=InpMa1Color; cols[1]=InpMa2Color; cols[2]=InpMa3Color;
   for(int m=0;m<3;m++){ if(!g_ma[m].on||g_ma[m].htfN==0) continue;
      string pf=g_ma[m].prefix+"M_"; ObjectsDeleteAll(0,pf);
      datetime t[]; int nb=MathMin(InpMaDrawBars,Bars(_Symbol,_Period)); if(CopyTime(_Symbol,_Period,0,nb,t)<2) continue;
      double pv=EMPTY_VALUE; datetime ptm=0;
      for(int i=0;i<nb;i++){
         double v=MAAtTime(m,t[i]);
         if(v!=EMPTY_VALUE&&pv!=EMPTY_VALUE){ string nm=pf+IntegerToString(i);
            ObjectCreate(0,nm,OBJ_TREND,0,ptm,pv,t[i],v); ObjectSetInteger(0,nm,OBJPROP_COLOR,cols[m]);
            ObjectSetInteger(0,nm,OBJPROP_WIDTH,InpMaWidth); ObjectSetInteger(0,nm,OBJPROP_RAY_RIGHT,false);
            ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false); ObjectSetInteger(0,nm,OBJPROP_HIDDEN,true); }
         pv=v; ptm=t[i]; } }
   ChartRedraw(0); }

//==================== JSON helpers (string-aware) ==================
string StripArrays(const string j){
   string o=""; int depth=0; bool q=false; int n=StringLen(j);
   for(int i=0;i<n;i++){ ushort c=StringGetCharacter(j,i);
      if(q){
         if(depth==0) o+=ShortToString(c);
         if(c=='\\'&&i+1<n){ i++; if(depth==0) o+=ShortToString(StringGetCharacter(j,i)); }
         else if(c=='"') q=false;
         continue; }
      if(c=='"'){ q=true; if(depth==0) o+=ShortToString(c); continue; }
      if(c=='[') depth++;
      else if(c==']'){ if(depth>0) depth--; }
      else if(depth==0) o+=ShortToString(c); }
   return o; }
string JStr(const string j,const string key,const string def=""){
   int p=StringFind(j,"\""+key+"\""); if(p<0) return def;
   p=StringFind(j,":",p); if(p<0) return def; p++;
   while(p<StringLen(j)&&(StringGetCharacter(j,p)==' '||StringGetCharacter(j,p)=='\n'||StringGetCharacter(j,p)=='\r'||StringGetCharacter(j,p)=='\t')) p++;
   if(StringGetCharacter(j,p)=='"'){ int e=p+1; while(e<StringLen(j)){ ushort c=StringGetCharacter(j,e); if(c=='\\'){ e+=2; continue; } if(c=='"') break; e++; }
      if(e>=StringLen(j)) return def; return StringSubstr(j,p+1,e-p-1); }
   int e=p; while(e<StringLen(j)){ ushort c=StringGetCharacter(j,e); if(c==','||c=='}'||c==']') break; e++; }
   string s=StringSubstr(j,p,e-p); StringTrimLeft(s); StringTrimRight(s); return s; }
double JNum(const string j,const string key,const double def=0.0){ string s=JStr(j,key,""); if(s==""||s=="null") return def; return StringToDouble(s); }
// 0 = missing/other, 1 = array, 2 = number
int JKind(const string j,const string key){
   int p=StringFind(j,"\""+key+"\""); if(p<0) return 0;
   p=StringFind(j,":",p); if(p<0) return 0; p++;
   while(p<StringLen(j)){ ushort w=StringGetCharacter(j,p); if(w==' '||w=='\n'||w=='\r'||w=='\t') p++; else break; }
   if(p>=StringLen(j)) return 0;
   ushort c=StringGetCharacter(j,p);
   if(c=='[') return 1;
   if((c>='0'&&c<='9')||c=='-'||c=='.') return 2;
   return 0; }
// raw array elements (objects or scalars)
int JItems(const string j,const string key,string &items[]){
   ArrayResize(items,0); int p=StringFind(j,"\""+key+"\""); if(p<0) return 0;
   p=StringFind(j,"[",p); if(p<0) return 0;
   int depth=0,start=p+1; bool q=false;
   for(int i=p+1;i<StringLen(j);i++){ ushort c=StringGetCharacter(j,i);
      if(q){ if(c=='\\') i++; else if(c=='"') q=false; continue; }
      if(c=='"'){ q=true; continue; }
      if(c=='{'||c=='[') depth++;
      else if(c=='}'||(c==']'&&depth>0)) depth--;
      else if(depth==0&&(c==','||c==']')){
         string s=StringSubstr(j,start,i-start); StringTrimLeft(s); StringTrimRight(s);
         if(s!=""){ int n=ArraySize(items); ArrayResize(items,n+1); items[n]=s; }
         start=i+1; if(c==']') break; } }
   return ArraySize(items); }
double ItemNum(const string it,const string key,const double def){
   if(StringGetCharacter(it,0)=='{') return JNum(it,key,def);
   return StringToDouble(it); }
string P(double v){ return DoubleToString(v,_Digits); }

//==================== Payload builders =============================
string Candles(ENUM_TIMEFRAMES tf,int n){
   MqlRates r[]; ArraySetAsSeries(r,false);
   int c=CopyRates(_Symbol,tf,1,n,r); string s="[";
   for(int i=0;i<c;i++){ if(i>0) s+=",";
      s+="{\"t\":\""+TimeToString(r[i].time,TIME_DATE|TIME_MINUTES)+"\",\"o\":"+P(r[i].open)+",\"l\":"+P(r[i].low)+",\"h\":"+P(r[i].high)+",\"c\":"+P(r[i].close)+",\"v\":"+IntegerToString((long)r[i].tick_volume)+"}"; }
   return s+"]"; }
string CandleJson(const MqlRates &r){
   return "{\"t\":\""+TimeToString(r.time,TIME_DATE|TIME_SECONDS)+"\",\"o\":"+P(r.open)+",\"l\":"+P(r.low)+",\"h\":"+P(r.high)
         +",\"c\":"+P(r.close)+",\"v\":"+IntegerToString((long)r.tick_volume)+"}"; }

string EngulfJson(const MqlRates &c,const MqlRates &p,bool &isEng){
   bool cBull=c.close>c.open, cBear=c.close<c.open, pBull=p.close>p.open, pBear=p.close<p.open;
   double cLo=MathMin(c.open,c.close), cHi=MathMax(c.open,c.close), pLo=MathMin(p.open,p.close), pHi=MathMax(p.open,p.close);
   bool bodyEng=((cBull&&pBear)||(cBear&&pBull))&&cLo<=pLo&&cHi>=pHi;
   bool fullEng=bodyEng&&cLo<=p.low&&cHi>=p.high;
   bool outside=c.high>p.high&&c.low<p.low;
   isEng=bodyEng;
   string type=fullEng?"FULL_RANGE":(bodyEng?"BODY":"NONE");
   string dir=!bodyEng?"NONE":(cBull?"BULLISH":"BEARISH");
   return ",\"engulfing\":{\"is_engulfing\":"+(bodyEng?"true":"false")+",\"type\":\""+type+"\",\"direction\":\""+dir
         +"\",\"outside_bar\":"+(outside?"true":"false")+"}"; }

//==================== Position / order helpers =====================
bool SelPos(const int i,ulong &t){
   t=PositionGetTicket(i); if(t==0||!PositionSelectByTicket(t)) return false;
   return PositionGetString(POSITION_SYMBOL)==_Symbol&&PositionGetInteger(POSITION_MAGIC)==(long)InpMagic; }
int PosDir(){ return PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1; }
bool SelOrd(const int i,ulong &t){
   t=OrderGetTicket(i); if(t==0) return false;
   return OrderGetString(ORDER_SYMBOL)==_Symbol&&OrderGetInteger(ORDER_MAGIC)==(long)InpMagic; }
int OrdDir(){
   ENUM_ORDER_TYPE t=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
   return (t==ORDER_TYPE_BUY_LIMIT||t==ORDER_TYPE_BUY_STOP||t==ORDER_TYPE_BUY_STOP_LIMIT)?1:-1; }
int CountDir(const int side){
   int c=0; ulong t;
   for(int i=0;i<PositionsTotal();i++) if(SelPos(i,t)&&PosDir()==side) c++;
   for(int i=0;i<OrdersTotal();i++)    if(SelOrd(i,t)&&OrdDir()==side) c++;
   return c; }
int CountOurs(){ return CountDir(1)+CountDir(-1); }
int CountDD(const int side){
   int c=0; ulong t;
   for(int i=0;i<PositionsTotal();i++) if(SelPos(i,t)&&PosDir()==side&&PositionGetString(POSITION_COMMENT)=="AIEA-D") c++;
   for(int i=0;i<OrdersTotal();i++)    if(SelOrd(i,t)&&OrdDir()==side&&OrderGetString(ORDER_COMMENT)=="AIEA-D") c++;
   return c; }
double TotalLots(){
   double s=0; ulong t;
   for(int i=0;i<PositionsTotal();i++) if(SelPos(i,t)) s+=PositionGetDouble(POSITION_VOLUME);
   for(int i=0;i<OrdersTotal();i++)    if(SelOrd(i,t)) s+=OrderGetDouble(ORDER_VOLUME_CURRENT);
   return s; }
// reference of the main trade (position or pending) in a direction
bool MainRef(const int side,double &open,double &sl,double &tp,double &lot){
   ulong t;
   for(int i=0;i<PositionsTotal();i++) if(SelPos(i,t)&&PosDir()==side&&PositionGetString(POSITION_COMMENT)=="AIEA-M"){
      open=PositionGetDouble(POSITION_PRICE_OPEN); sl=PositionGetDouble(POSITION_SL); tp=PositionGetDouble(POSITION_TP); lot=PositionGetDouble(POSITION_VOLUME); return true; }
   for(int i=0;i<OrdersTotal();i++) if(SelOrd(i,t)&&OrdDir()==side&&OrderGetString(ORDER_COMMENT)=="AIEA-M"){
      open=OrderGetDouble(ORDER_PRICE_OPEN); sl=OrderGetDouble(ORDER_SL); tp=OrderGetDouble(ORDER_TP); lot=OrderGetDouble(ORDER_VOLUME_CURRENT); return true; }
   return false; }

string PositionsJson(){
   string s="["; bool first=true; ulong t;
   for(int i=0;i<PositionsTotal();i++){ if(!SelPos(i,t)) continue;
      if(!first) s+=","; first=false;
      s+="{\"ticket\":"+IntegerToString((long)t)+",\"side\":\""+(PosDir()>0?"BUY":"SELL")+"\",\"lot\":"+DoubleToString(PositionGetDouble(POSITION_VOLUME),2)
         +",\"open\":"+P(PositionGetDouble(POSITION_PRICE_OPEN))+",\"sl\":"+P(PositionGetDouble(POSITION_SL))+",\"tp\":"+P(PositionGetDouble(POSITION_TP))
         +",\"profit\":"+DoubleToString(PositionGetDouble(POSITION_PROFIT),2)+",\"comment\":\""+PositionGetString(POSITION_COMMENT)+"\"}"; }
   return s+"]"; }
string OrdersJson(){
   string s="["; bool first=true; ulong t;
   for(int i=0;i<OrdersTotal();i++){ if(!SelOrd(i,t)) continue;
      if(!first) s+=","; first=false;
      ENUM_ORDER_TYPE ot=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      s+="{\"ticket\":"+IntegerToString((long)t)+",\"type\":\""+EnumToString(ot)+"\",\"lot\":"+DoubleToString(OrderGetDouble(ORDER_VOLUME_CURRENT),2)
         +",\"price\":"+P(OrderGetDouble(ORDER_PRICE_OPEN))+",\"sl\":"+P(OrderGetDouble(ORDER_SL))+",\"tp\":"+P(OrderGetDouble(ORDER_TP))
         +",\"comment\":\""+OrderGetString(ORDER_COMMENT)+"\"}"; }
   return s+"]"; }

string NearbyLevels(){
   string s="["; bool first=true; double mid=(SymbolInfoDouble(_Symbol,SYMBOL_BID)+SymbolInfoDouble(_Symbol,SYMBOL_ASK))/2.0;
   for(int m=0;m<3;m++){ if(!g_ma[m].on||!g_ma[m].lvl) continue;
      for(int k=0;k<ArraySize(g_ma[m].act);k++){ double d=MathAbs(g_ma[m].act[k].y-mid)/_Point; if(d>3000) continue;
         if(!first) s+=","; first=false;
         s+="{\"price\":"+P(g_ma[m].act[k].y)+",\"ma\":"+IntegerToString(m+1)+",\"lives\":"+IntegerToString(InpMaxMit-g_ma[m].act[k].cnt)+",\"distance_points\":"+DoubleToString(d,0)+"}"; } }
   return s+"]"; }

string LevelMeta(const int m,const SLevel &L){
   int eff=(L.cnt%2==0)?L.type:-L.type;
   double mid=(SymbolInfoDouble(_Symbol,SYMBOL_BID)+SymbolInfoDouble(_Symbol,SYMBOL_ASK))/2.0;
   string role=(mid<L.y)?"RESISTANCE":"SUPPORT";
   return ",\"inflection_line\":{\"id\":\""+g_ma[m].tag+IntegerToString(L.id)+"\",\"price\":"+P(L.y)
      +",\"origin_type\":\""+(L.type==1?"PEAK":"BOTTOM")+"\",\"current_type\":\""+(eff==1?"PEAK":"BOTTOM")+"\""
      +",\"role_vs_price\":\""+role+"\",\"mitigations_used\":"+IntegerToString(L.cnt)+",\"lives_left\":"+IntegerToString(InpMaxMit-L.cnt)
      +",\"ma_index\":"+IntegerToString(m+1)+",\"ma_type\":\""+EnumToString(g_ma[m].type)+"\",\"ma_length\":"+IntegerToString(g_ma[m].len)
      +",\"ma_timeframe\":\""+EnumToString(g_ma[m].ftf)+"\"}"; }

string BuildPayload(const string mode,const double lvlPx,const string lvlType,const string tfName,const int lives,const string maName){
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID), ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   string s="{\"mode\":\""+mode+"\",\"symbol\":\""+_Symbol+"\""
      +",\"chart_timeframe\":\""+EnumToString((ENUM_TIMEFRAMES)_Period)+"\""
      +",\"chart_time\":\""+TimeToString(iTime(_Symbol,_Period,0),TIME_DATE|TIME_SECONDS)+"\""
      +",\"server_time\":\""+TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS)+"\""
      +",\"gmt_time\":\""+TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS)+"\""
      +",\"local_time\":\""+TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS)+"\"";
   s+=",\"inflection_price\":"+P(lvlPx)+",\"inflection_type\":\""+lvlType+"\",\"inflection_source\":\""+maName+" "+tfName+"\"";
   s+=",\"inflection_lives_left\":"+IntegerToString(lives)+",\"inflection_lives_total\":"+IntegerToString(InpMaxMit)+",\"inflection_mitigations\":"+IntegerToString(InpMaxMit-lives);
   s+=",\"market_price\":{\"bid\":"+P(bid)+",\"ask\":"+P(ask)+"}";
   s+=",\"distance_points\":"+DoubleToString(MathAbs((bid+ask)/2.0-lvlPx)/_Point,0);
   s+=g_lvlExtra;
   s+=g_crossExtra;
   if(InpSendExtra){
      s+=",\"symbol_info\":{\"digits\":"+IntegerToString(_Digits)+",\"point\":"+DoubleToString(_Point,_Digits)
         +",\"min_lot\":"+DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),2)+",\"max_lot_allowed\":"+DoubleToString(InpMaxLot,2)
         +",\"lot_step\":"+DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP),2)+",\"stops_level_points\":"+IntegerToString((int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL))
         +",\"spread_points\":"+IntegerToString((int)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD))+",\"max_dd_entries\":"+IntegerToString(InpMaxDD)+",\"max_total_lot\":"+DoubleToString(InpMaxTotalLot,2)+"}";
      s+=",\"account\":{\"balance\":"+DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2)+",\"equity\":"+DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2)+"}";
      s+=",\"nearby_levels\":"+NearbyLevels(); }
   s+=",\"candles\":{\"M15\":"+Candles(PERIOD_M15,InpCandles)+",\"M5\":"+Candles(PERIOD_M5,InpCandles)+",\"M3\":"+Candles(PERIOD_M3,InpCandles)+",\"M1\":"+Candles(PERIOD_M1,InpCandles)+"}";
   s+=",\"open_positions\":"+PositionsJson()+",\"pending_orders\":"+OrdersJson()+"}";
   return s; }

//==================== AI call ======================================
bool AskAI(const string payload,string &response){
   char data[],res[]; string rh;
   int len=StringToCharArray(payload,data,0,WHOLE_ARRAY,CP_UTF8); ArrayResize(data,len-1);
   if(InpTestMode&&InpLogPayload) PrintFormat("[AI-TEST] request (%d bytes): %s",len-1,payload);
   if(InpTestMode) Print("[AI-TEST] sending request, waiting for AI...");
   string headers="Content-Type: application/json\r\n"; if(InpAiKey!="") headers+="Authorization: Bearer "+InpAiKey+"\r\n";
   ResetLastError();
   int code=WebRequest("POST",InpAiUrl,headers,InpAiTimeoutMs,data,res,rh);
   if(code==-1){ PrintFormat("AI WebRequest failed err=%d (allow URL in Options>Expert Advisors)",GetLastError()); return false; }
   response=CharArrayToString(res,0,WHOLE_ARRAY,CP_UTF8);
   if(code!=200){ PrintFormat("AI HTTP %d: %s",code,response); return false; }
   return true; }

//==================== Trading helpers ==============================
double NormLot(double l){
   double st=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP), mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN), mx=MathMin(InpMaxLot,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX));
   if(l<=0) l=InpDefaultLot; l=MathFloor(l/st+1e-9)*st; l=MathMax(mn,MathMin(mx,l)); return NormalizeDouble(l,2); }
bool StopsOK(int side,double entry,double sl,double tp){
   double md=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   if(sl>0){ if(side>0&&!(sl<entry-md)) return false; if(side<0&&!(sl>entry+md)) return false; }
   else if(InpRequireSL) return false;
   if(tp>0){ if(side>0&&!(tp>entry+md)) return false; if(side<0&&!(tp<entry-md)) return false; }
   return true; }

// ---- partial levels: AI array (numbers or {price,percent}) | AI count N (even spacing entry->TP) | default
int PartialLevels(const string json,const int side,const double entry,const double tp,double &price[],double &pct[]){
   ArrayResize(price,0); ArrayResize(pct,0);
   int kind=JKind(json,"partials"); int N=InpDefaultPartials;
   if(kind==1){
      string it[]; int n=JItems(json,"partials",it);
      for(int i=0;i<n&&i<10;i++){
         double pr=NormalizeDouble(ItemNum(it[i],"price",0),_Digits); double pc=(StringGetCharacter(it[i],0)=='{')?JNum(it[i],"percent",InpPartialPct):InpPartialPct;
         bool ok=(side>0)?(pr>entry&&(tp<=0||pr<tp)):(pr<entry&&(tp<=0||pr>tp));
         if(!ok||pr<=0) continue;
         int k=ArraySize(price); ArrayResize(price,k+1); ArrayResize(pct,k+1); price[k]=pr; pct[k]=MathMax(1.0,MathMin(100.0,pc)); }
      return ArraySize(price); }
   if(kind==2) N=(int)JNum(json,"partials");
   N=MathMax(0,MathMin(10,N));
   if(N<=0||tp<=0) return 0;
   for(int k=1;k<=N;k++){
      int n=ArraySize(price); ArrayResize(price,n+1); ArrayResize(pct,n+1);
      price[n]=NormalizeDouble(entry+k*(tp-entry)/(N+1),_Digits); pct[n]=InpPartialPct; }
   return N; }

void StorePartials(const int side,const double &price[],const double &pct[],const int n){
   int d=(side>0)?0:1; ArrayResize(g_set[d].parts,n);
   for(int i=0;i<n;i++){ g_set[d].parts[i].price=price[i]; g_set[d].parts[i].pct=pct[i]; g_set[d].parts[i].done=false; } }

// ---- DD prices: AI array | AI count N | default; same lot/SL/TP as main
int DDPrices(const string json,const int side,const double entry,const double sl,double &out[]){
   ArrayResize(out,0); int kind=JKind(json,"dd_entries"); int N=InpDefaultDD;
   if(kind==1){
      string it[]; int n=JItems(json,"dd_entries",it);
      for(int i=0;i<n&&ArraySize(out)<InpMaxDD;i++){
         double pr=NormalizeDouble(ItemNum(it[i],"price",0),_Digits); if(pr<=0) continue;
         bool ok=(side>0)?(pr<entry&&(sl<=0||pr>sl)):(pr>entry&&(sl<=0||pr<sl)); if(!ok) continue;
         int k=ArraySize(out); ArrayResize(out,k+1); out[k]=pr; }
      return ArraySize(out); }
   if(kind==2) N=(int)JNum(json,"dd_entries");
   N=MathMax(0,MathMin(InpMaxDD,N));
   if(N<=0||sl<=0) return 0;
   double dist=MathAbs(entry-sl);
   for(int k=1;k<=N;k++){ int n=ArraySize(out); ArrayResize(out,n+1); out[n]=NormalizeDouble(entry-side*k*dist/(N+1),_Digits); }
   return N; }

int PlaceDD(const int side,const double sl,const double tp,const double lot,const double &prices[],const int n){
   int placed=0; ENUM_ORDER_TYPE_TIME tt=(InpDDExpiryMin>0)?ORDER_TIME_SPECIFIED:ORDER_TIME_GTC;
   datetime exp=(InpDDExpiryMin>0)?TimeCurrent()+InpDDExpiryMin*60:0;
   for(int i=0;i<n;i++){
      double pr=prices[i];
      if(!StopsOK(side,pr,sl,tp)){ PrintFormat("DD %s rejected (stops)",P(pr)); continue; }
      if(TotalLots()+lot>InpMaxTotalLot){ Print("DD rejected: total lot cap"); break; }
      bool ok=(side>0)?g_trade.BuyLimit(lot,pr,_Symbol,sl,tp,tt,exp,"AIEA-D"):g_trade.SellLimit(lot,pr,_Symbol,sl,tp,tt,exp,"AIEA-D");
      if(ok) placed++; else PrintFormat("DD order failed %d %s",g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription()); }
   return placed; }

void ModifyAll(const double sl,const double tp,const int side){
   ulong t;
   for(int i=PositionsTotal()-1;i>=0;i--){ if(!SelPos(i,t)) continue; int s=PosDir(); if(side!=0&&s!=side) continue;
      double nsl=sl>0?sl:PositionGetDouble(POSITION_SL), ntp=tp>0?tp:PositionGetDouble(POSITION_TP);
      if(!StopsOK(s,SymbolInfoDouble(_Symbol,s>0?SYMBOL_BID:SYMBOL_ASK),nsl,ntp)){ Print("MODIFY rejected by stop validation"); continue; }
      g_trade.PositionModify(t,nsl,ntp); }
   for(int i=OrdersTotal()-1;i>=0;i--){ if(!SelOrd(i,t)) continue; int s=OrdDir(); if(side!=0&&s!=side) continue;
      double nsl=sl>0?sl:OrderGetDouble(ORDER_SL), ntp=tp>0?tp:OrderGetDouble(ORDER_TP);
      g_trade.OrderModify(t,OrderGetDouble(ORDER_PRICE_OPEN),nsl,ntp,(ENUM_ORDER_TYPE_TIME)OrderGetInteger(ORDER_TYPE_TIME),(datetime)OrderGetInteger(ORDER_TIME_EXPIRATION)); } }

void CancelPending(const int side){
   ulong t; for(int i=OrdersTotal()-1;i>=0;i--){ if(!SelOrd(i,t)) continue; if(side!=0&&OrdDir()!=side) continue; g_trade.OrderDelete(t); } }

// close pct % of each position's CURRENT volume
void ClosePct(const double pct,const int side){
   ulong t;
   for(int i=PositionsTotal()-1;i>=0;i--){ if(!SelPos(i,t)) continue; if(side!=0&&PosDir()!=side) continue;
      double vol=PositionGetDouble(POSITION_VOLUME), mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN), st=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
      double cv=MathFloor(vol*pct/100.0/st+1e-9)*st;
      if(pct>=100.0||vol-cv<mn){ if(pct>=100.0||cv>=mn) g_trade.PositionClose(t); continue; }
      if(cv>=mn) g_trade.PositionClosePartial(t,NormalizeDouble(cv,2)); } }

// move SL to AI's sl_to_be (or each position's open price if none)
void ApplyBE(const int side){
   int d=(side>0)?0:1; double md=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID), ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK); ulong t;
   for(int i=PositionsTotal()-1;i>=0;i--){ if(!SelPos(i,t)||PosDir()!=side) continue;
      double be=(g_set[d].beSl>0)?g_set[d].beSl:PositionGetDouble(POSITION_PRICE_OPEN); be=NormalizeDouble(be,_Digits);
      double csl=PositionGetDouble(POSITION_SL), ctp=PositionGetDouble(POSITION_TP);
      bool ok=(side>0)?(be<bid-md&&(csl==0||be>csl)):(be>ask+md&&(csl==0||be<csl));
      if(ok){ if(g_trade.PositionModify(t,be,ctp)) PrintFormat("SL->BE %s ticket %I64u",P(be),t); } }
   g_set[d].beDone=true; }

//==================== Live trade management ========================
void CheckPartials(){
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID), ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double st=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP), mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   for(int d=0;d<2;d++){ int side=(d==0)?1:-1;
      for(int p=0;p<ArraySize(g_set[d].parts);p++){ if(g_set[d].parts[p].done) continue;
         bool hit=(side>0)?(bid>=g_set[d].parts[p].price):(ask<=g_set[d].parts[p].price); if(!hit) continue;
         g_set[d].parts[p].done=true;
         ulong tk[]; ulong t; for(int i=PositionsTotal()-1;i>=0;i--) if(SelPos(i,t)&&PosDir()==side){ int n=ArraySize(tk); ArrayResize(tk,n+1); tk[n]=t; }
         for(int k=0;k<ArraySize(tk);k++){ if(!PositionSelectByTicket(tk[k])) continue;
            double vol=PositionGetDouble(POSITION_VOLUME);
            double cv=MathFloor(vol*g_set[d].parts[p].pct/100.0/st+1e-9)*st;      // % of REMAINING volume
            if(cv>=mn&&vol-cv>=mn) g_trade.PositionClosePartial(tk[k],NormalizeDouble(cv,2)); }
         PrintFormat("Partial %d hit @ %s (%.0f%% of remaining)",p+1,P(g_set[d].parts[p].price),g_set[d].parts[p].pct);
         if(!g_set[d].beDone) ApplyBE(side); } } }

// DD rule: with 2+ positions in a direction, close each older entry once it is +$X, keep the latest
void CloseWorstDD(){
   if(InpDDCloseUSD<=0) return; ulong t;
   for(int side=1;side>=-1;side-=2){
      int cnt=0; ulong latest=0; long lt=-1;
      for(int i=0;i<PositionsTotal();i++) if(SelPos(i,t)&&PosDir()==side){ cnt++; long tm=PositionGetInteger(POSITION_TIME_MSC); if(tm>=lt){ lt=tm; latest=t; } }
      if(cnt<2) continue;
      ulong del[];
      for(int i=0;i<PositionsTotal();i++) if(SelPos(i,t)&&PosDir()==side&&t!=latest){
         double pr=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
         if(pr>=InpDDCloseUSD){ int n=ArraySize(del); ArrayResize(del,n+1); del[n]=t; } }
      for(int k=0;k<ArraySize(del);k++){ if(g_trade.PositionClose(del[k])) PrintFormat("DD rule: closed older entry %I64u at +$%.2f+, keeping latest %I64u",del[k],InpDDCloseUSD,latest); } } }

// after InpTrailStartPts profit: remove TP, trail SL InpTrailDistPts behind price
void TrailPositions(){
   if(InpTrailStartPts<=0) return;
   double pt=_Point, md=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*pt;
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID), ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK); ulong t;
   for(int i=PositionsTotal()-1;i>=0;i--){ if(!SelPos(i,t)) continue;
      bool buy=(PosDir()>0); double open=PositionGetDouble(POSITION_PRICE_OPEN), sl=PositionGetDouble(POSITION_SL), tp=PositionGetDouble(POSITION_TP);
      double prof=(buy?(bid-open):(open-ask))/pt; if(prof<InpTrailStartPts) continue;
      double nsl=NormalizeDouble(buy?bid-InpTrailDistPts*pt:ask+InpTrailDistPts*pt,_Digits);
      bool better=buy?(sl==0||nsl>=sl+InpTrailStepPts*pt):(sl==0||nsl<=sl-InpTrailStepPts*pt);
      bool valid=buy?(nsl<bid-md):(nsl>ask+md);
      if(!(better&&valid)&&tp==0) continue;
      if(!(better&&valid)) nsl=sl;
      if(nsl!=sl||tp!=0) g_trade.PositionModify(t,nsl,0.0); } }

void Housekeeping(){
   ulong t;
   for(int d=0;d<2;d++){ int side=(d==0)?1:-1; bool anyPos=false, mainPend=false;
      for(int i=0;i<PositionsTotal();i++) if(SelPos(i,t)&&PosDir()==side) anyPos=true;
      for(int i=0;i<OrdersTotal();i++)    if(SelOrd(i,t)&&OrdDir()==side&&OrderGetString(ORDER_COMMENT)=="AIEA-M") mainPend=true;
      if(!anyPos&&!mainPend){
         if(CountDir(side)>0) CancelPending(side);
         ArrayResize(g_set[d].parts,0); g_set[d].beSl=0; g_set[d].beDone=false; } } }

void ManageOpen(){ CheckPartials(); CloseWorstDD(); TrailPositions(); Housekeeping(); }

//==================== Decision executor ============================
void LogTestDecision(const string json,const string mode,const string dec,const string sd,const string extra,
                     const double entry,const double sl,const double tp,const double lot,const int expMin,
                     const double &pPrice[],const double &pPct[],const int nP,const double &ddP[],const int nD,const string reason){
   PrintFormat("[AI-TEST] ===== %s | %s | bid=%s ask=%s =====",mode,_Symbol,P(SymbolInfoDouble(_Symbol,SYMBOL_BID)),P(SymbolInfoDouble(_Symbol,SYMBOL_ASK)));
   PrintFormat("[AI-TEST] decision=%s side=%s entry=%s sl=%s tp=%s lot=%.2f expiry=%dmin %s",dec,sd,P(entry),P(sl),P(tp),lot,expMin,extra);
   for(int i=0;i<nP;i++) PrintFormat("[AI-TEST] partial #%d price=%s close %.0f%% of remaining",i+1,P(pPrice[i]),pPct[i]);
   for(int i=0;i<nD;i++) PrintFormat("[AI-TEST] dd #%d price=%s lot=%.2f (same SL/TP)",i+1,P(ddP[i]),lot);
   if(reason!="") PrintFormat("[AI-TEST] reason: %s",reason);
   if(InpLogRawReply) PrintFormat("[AI-TEST] raw reply: %s",json); }

void ApplyDecision(const string json,const string mode){
   string top=StripArrays(json); string dec=JStr(top,"decision","HOLD"); StringToUpper(dec);
   string rsn=JStr(top,"reason",""); PrintFormat("AI decision=%s mode=%s",dec,mode);
   string sd=JStr(top,"side",""); StringToUpper(sd); int side=(sd=="BUY")?1:(sd=="SELL"?-1:0);
   double entry=NormalizeDouble(JNum(top,"entry"),_Digits), sl=NormalizeDouble(JNum(top,"sl"),_Digits), tp=NormalizeDouble(JNum(top,"tp"),_Digits);
   double slBE=NormalizeDouble(JNum(top,"sl_to_be"),_Digits);
   double lot=NormLot(JNum(top,"lot",0));
   double conf=JNum(top,"confidence_level",100);
   double pctNow=MathMax(10.0,MathMin(60.0,JNum(top,"percent",InpPartialPct)));
   int expMin=(int)MathMax(1,MathMin(60,JNum(top,"expiry_min",InpPendingMin))); datetime exp=TimeCurrent()+expMin*60;
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID), ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   double refE=entry>0?entry:(side>0?ask:bid);
   double pPrice[],pPct[],ddP[]; int nP=0,nD=0;
   if(side!=0){ nP=PartialLevels(json,side,refE,tp,pPrice,pPct); nD=DDPrices(json,side,refE,sl,ddP); }
   string extra=StringFormat("confidence=%.0f percent=%.0f sl_to_be=%s",conf,pctNow,P(slBE));

   if(InpTestMode||(mode=="MANUAL"&&!InpManualExecute)){
      LogTestDecision(json,mode,dec,sd,extra,entry,sl,tp,lot,expMin,pPrice,pPct,nP,ddP,nD,rsn); return; }

   if(dec=="HOLD") return;
   if(dec=="CANCEL"){ CancelPending(side); return; }
   if(dec=="CLOSE"){ ClosePct(100,side); CancelPending(side); return; }
   if(dec=="PARTIAL"){ ClosePct(pctNow,side); return; }
   if(dec=="MODIFY"){
      ModifyAll(sl,tp,side);
      for(int s=1;s>=-1;s-=2){ if(side!=0&&side!=s) continue; int d=(s>0)?0:1;
         if(slBE>0){ g_set[d].beSl=slBE; ApplyBE(s); }
         if(JKind(json,"partials")!=0){ double o,msl,mtp,ml; if(MainRef(s,o,msl,mtp,ml)){
            double rp[],rc[]; int n=PartialLevels(json,s,entry>0?entry:o,tp>0?tp:mtp,rp,rc); StorePartials(s,rp,rc,n); } } }
      return; }
   if(dec=="ADD_DD"){
      if(side==0){ Print("ADD_DD needs side"); return; }
      double o,msl,mtp,ml; if(!MainRef(side,o,msl,mtp,ml)){ Print("ADD_DD: no main trade in that direction"); return; }
      double dp[]; int n=DDPrices(json,side,o,sl>0?sl:msl,dp);
      int room=InpMaxDD-CountDD(side); if(room<=0){ Print("ADD_DD: DD limit reached"); return; }
      n=MathMin(n,room); PlaceDD(side,sl>0?sl:msl,tp>0?tp:mtp,NormLot(ml),dp,n); return; }

   if(dec!="EXECUTE"&&dec!="LIMIT"){ Print("Unknown decision"); return; }
   if(!InpAllowEntries){ Print("Entries disabled (log only)"); return; }
   if(mode!="ENTRY"&&mode!="MA_CROSS"&&mode!="MANUAL"){ Print("Entry ignored: wrong mode"); return; }
   if(side==0){ Print("Missing side"); return; }
   if(CountDir(side)>0){ Print("Entry ignored: already 1 trade (with DD) in this direction"); return; }
   if(InpMinConfidence>0&&conf<InpMinConfidence){ PrintFormat("Entry ignored: confidence %.0f < %d",conf,InpMinConfidence); return; }
   if(SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)>InpMaxSpreadPts){ Print("Spread too wide"); return; }
   if(TotalLots()+lot>InpMaxTotalLot){ Print("Total lot cap"); return; }

   bool ok=false; double ref=entry;
   if(dec=="EXECUTE"){
      ref=(side>0)?ask:bid;
      if(entry>0&&MathAbs(ref-entry)>InpMaxSlipPts*_Point){ Print("EXECUTE rejected: price moved from AI entry"); return; }
      if(!StopsOK(side,ref,sl,tp)){ Print("EXECUTE rejected: SL/TP invalid"); return; }
   } else {
      if(entry<=0){ Print("LIMIT needs entry"); return; }
      if((side>0&&entry>=ask)||(side<0&&entry<=bid)){ Print("LIMIT rejected: entry on wrong side of market"); return; }
      if(!StopsOK(side,entry,sl,tp)){ Print("LIMIT rejected: SL/TP invalid"); return; } }

   nP=PartialLevels(json,side,ref,tp,pPrice,pPct);
   nD=DDPrices(json,side,ref,sl,ddP);
   while(nD>0&&TotalLots()+lot*(1+nD)>InpMaxTotalLot) nD--;       // keep setup inside total lot cap

   if(dec=="EXECUTE") ok=(side>0)?g_trade.Buy(lot,_Symbol,0,sl,tp,"AIEA-M"):g_trade.Sell(lot,_Symbol,0,sl,tp,"AIEA-M");
   else ok=(side>0)?g_trade.BuyLimit(lot,entry,_Symbol,sl,tp,ORDER_TIME_SPECIFIED,exp,"AIEA-M"):g_trade.SellLimit(lot,entry,_Symbol,sl,tp,ORDER_TIME_SPECIFIED,exp,"AIEA-M");
   if(!ok){ PrintFormat("Order failed retcode=%d %s",g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription()); return; }

   int d=(side>0)?0:1; g_set[d].beSl=slBE; g_set[d].beDone=false;
   StorePartials(side,pPrice,pPct,nP);
   if(nD>0) PlaceDD(side,sl,tp,lot,ddP,nD);
   PrintFormat("Setup placed: %s lot=%.2f partials=%d dd=%d sl_to_be=%s",side>0?"BUY":"SELL",lot,nP,nD,P(slBE)); }

//==================== Level triggers ===============================
bool OnCooldown(const string key){
   for(int i=0;i<ArraySize(g_cool);i++) if(g_cool[i].key==key) return (TimeCurrent()-g_cool[i].t)<InpLevelCoolMin*60;
   return false; }
void SetCooldown(const string key){
   for(int i=0;i<ArraySize(g_cool);i++) if(g_cool[i].key==key){ g_cool[i].t=TimeCurrent(); return; }
   int n=ArraySize(g_cool); ArrayResize(g_cool,n+1); g_cool[n].key=key; g_cool[n].t=TimeCurrent(); }

bool NearestLevel(const double maxPts,int &bm,int &bk,const bool useCooldown){
   double mid=(SymbolInfoDouble(_Symbol,SYMBOL_BID)+SymbolInfoDouble(_Symbol,SYMBOL_ASK))/2.0; double bd=DBL_MAX; bm=-1; bk=-1;
   for(int m=0;m<3;m++){ if(!g_ma[m].on||!g_ma[m].lvl) continue;
      for(int k=0;k<ArraySize(g_ma[m].act);k++){
         double d=MathAbs(mid-g_ma[m].act[k].y)/_Point; if(d>maxPts) continue;
         if(useCooldown){ string key=IntegerToString(m)+"_"+IntegerToString(g_ma[m].act[k].id)+"_"+IntegerToString(g_ma[m].act[k].cnt); if(OnCooldown(key)) continue; }
         if(d<bd){ bd=d; bm=m; bk=k; } } }
   return bm>=0; }

void SendLevel(const int bm,const int bk){
   SLevel L=g_ma[bm].act[bk];
   SetCooldown(IntegerToString(bm)+"_"+IntegerToString(L.id)+"_"+IntegerToString(L.cnt));
   int eff=(L.cnt%2==0)?L.type:-L.type;
   g_lvlExtra=LevelMeta(bm,L); g_crossExtra="";
   string payload=BuildPayload("ENTRY",L.y,eff==1?"PEAK":"BOTTOM",EnumToString(g_ma[bm].ftf),InpMaxMit-L.cnt,"MA"+IntegerToString(bm+1));
   g_lvlExtra="";
   string resp; if(!AskAI(payload,resp)) return;
   ApplyDecision(resp,"ENTRY"); }

void CheckEntryTrigger(){ int bm,bk; if(NearestLevel(InpTriggerPts,bm,bk,true)) SendLevel(bm,bk); }

void TestTimer(){
   if(!InpTestMode||InpTestIntervalSec<=0) return;
   if(TimeLocal()-g_lastTest<InpTestIntervalSec) return; g_lastTest=TimeLocal();
   bool ch=false; for(int m=0;m<3;m++) if(UpdateMA(g_ma[m])) ch=true;
   if(ch){ g_lastChartBar=iTime(_Symbol,_Period,0); DrawLevels(); }
   int bm,bk;
   if(NearestLevel(InpTestAnyDistance?DBL_MAX:InpTriggerPts,bm,bk,false)) SendLevel(bm,bk);
   else Print("[AI-TEST] no live inflection level in range, nothing sent"); }

void ManageTrades(){
   if(InpMgmtSec<=0||CountOurs()==0) return;
   if(TimeCurrent()-g_lastMgmt<InpMgmtSec) return; g_lastMgmt=TimeCurrent();
   double mid=(SymbolInfoDouble(_Symbol,SYMBOL_BID)+SymbolInfoDouble(_Symbol,SYMBOL_ASK))/2.0;
   int bm=-1,bk=-1; double bd=DBL_MAX;
   for(int m=0;m<3;m++){ if(!g_ma[m].on||!g_ma[m].lvl) continue;
      for(int k=0;k<ArraySize(g_ma[m].act);k++){ double d=MathAbs(mid-g_ma[m].act[k].y); if(d<bd){ bd=d; bm=m; bk=k; } } }
   double lp=0; string lt="NONE"; int lives=0; string nm=""; g_lvlExtra=""; g_crossExtra="";
   if(bm>=0){ SLevel L=g_ma[bm].act[bk]; lp=L.y; int eff=(L.cnt%2==0)?L.type:-L.type; lt=eff==1?"PEAK":"BOTTOM"; lives=InpMaxMit-L.cnt;
      nm="MA"+IntegerToString(bm+1)+" "+EnumToString(g_ma[bm].ftf); g_lvlExtra=LevelMeta(bm,L); }
   string payload=BuildPayload("MANAGE",lp,lt,"",lives,nm);
   g_lvlExtra="";
   string resp; if(!AskAI(payload,resp)) return;
   ApplyDecision(resp,"MANAGE"); }

//==================== MA cross request =============================
bool EvalCross(const int m,const ENUM_TIMEFRAMES tf,const int shift,const bool force){
   MqlRates r[]; ArraySetAsSeries(r,true);
   if(CopyRates(_Symbol,tf,shift,2,r)<2) return false;
   double maO=MAAtTime(m,r[0].time);
   double maC=MAAtTime(m,r[0].time+(datetime)PeriodSeconds(tf));
   if(maO==EMPTY_VALUE||maC==EMPTY_VALUE){ if(InpCrossDebug) PrintFormat("[CROSS-DBG] MA%d no MA value at %s",m+1,TimeToString(r[0].time)); return false; }
   string dir="NONE";
   if(r[0].open<maO&&r[0].close>maC)      dir="BULLISH_CROSS";
   else if(r[0].open>maO&&r[0].close<maC) dir="BEARISH_CROSS";
   bool isEng=false; string eng=EngulfJson(r[0],r[1],isEng);
   if(InpCrossDebug) PrintFormat("[CROSS-DBG] MA%d %s o=%s c=%s maOpen=%s maClose=%s -> %s eng=%s",m+1,TimeToString(r[0].time),
        P(r[0].open),P(r[0].close),P(maO),P(maC),dir,isEng?"yes":"no");
   if(dir=="NONE"&&!force) return false;
   if(dir!="NONE"&&InpCrossNeedEngulf&&!isEng&&!force){ Print("[CROSS-DBG] skipped: not engulfing"); return false; }

   g_crossExtra=",\"ma_cross\":{\"direction\":\""+dir+"\",\"forced_test\":"+((dir=="NONE")?"true":"false")
      +",\"ma_index\":"+IntegerToString(m+1)+",\"ma_type\":\""+EnumToString(g_ma[m].type)+"\",\"ma_length\":"+IntegerToString(g_ma[m].len)
      +",\"ma_timeframe\":\""+EnumToString(g_ma[m].ftf)+"\",\"ma_value\":"+P(maC)+",\"ma_value_at_open\":"+P(maO)
      +",\"cross_timeframe\":\""+EnumToString(tf)+"\",\"candle\":"+CandleJson(r[0])+",\"previous_candle\":"+CandleJson(r[1])
      +",\"body_points\":"+DoubleToString(MathAbs(r[0].close-r[0].open)/_Point,0)+eng+"}";

   int bm,bk; double lp=0; string lt="NONE"; int lives=0; string nm=""; g_lvlExtra="";
   if(NearestLevel(DBL_MAX,bm,bk,false)){ SLevel L=g_ma[bm].act[bk]; int ef=(L.cnt%2==0)?L.type:-L.type;
      lp=L.y; lt=ef==1?"PEAK":"BOTTOM"; lives=InpMaxMit-L.cnt; nm="MA"+IntegerToString(bm+1)+" "+EnumToString(g_ma[bm].ftf); g_lvlExtra=LevelMeta(bm,L); }
   if(InpTestMode) PrintFormat("[AI-TEST] MA%d cross %s @ %s engulfing=%s -> sending",m+1,dir,TimeToString(r[0].time),isEng?"yes":"no");
   string payload=BuildPayload("MA_CROSS",lp,lt,"",lives,nm);
   g_crossExtra=""; g_lvlExtra="";
   string resp; if(AskAI(payload,resp)) ApplyDecision(resp,"MA_CROSS");
   return true; }

void CheckMaCross(){
   if(!InpCrossOn) return;
   bool ch=false; for(int m=0;m<3;m++) if(UpdateMA(g_ma[m])) ch=true;
   if(ch){ g_lastChartBar=iTime(_Symbol,_Period,0); DrawLevels(); }
   ENUM_TIMEFRAMES tf=(InpCrossTF==PERIOD_CURRENT)?_Period:InpCrossTF;
   bool en[3]; en[0]=InpCrossMa1; en[1]=InpCrossMa2; en[2]=InpCrossMa3;

   if(!g_scanDone&&InpTestMode&&(InpCrossScanBars>0||InpCrossForceSend)&&(g_ma[0].htfN+g_ma[1].htfN+g_ma[2].htfN)>0){
      g_scanDone=true;
      for(int s=InpCrossScanBars;s>=1;s--) for(int m=0;m<3;m++) if(en[m]&&g_ma[m].on) EvalCross(m,tf,s,false);
      if(InpCrossForceSend) for(int m=0;m<3;m++) if(en[m]&&g_ma[m].on){ EvalCross(m,tf,1,true); break; }
   }

   datetime cur=iTime(_Symbol,tf,0); if(cur==0) return;
   if(g_crossBar==0){ g_crossBar=cur; return; }
   if(cur==g_crossBar) return;
   g_crossBar=cur;
   for(int m=0;m<3;m++){
      if(!en[m]||!g_ma[m].on) continue;
      EvalCross(m,tf,1,false); } }

//==================== Manual button ================================
void SetButtonText(const string txt,const color bg){
   if(!InpShowButton) return;
   ObjectSetString(0,BTN,OBJPROP_TEXT,txt); ObjectSetInteger(0,BTN,OBJPROP_BGCOLOR,bg); ChartRedraw(0); }

void CreateButton(){
   if(!InpShowButton) return;
   ObjectCreate(0,BTN,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,BTN,OBJPROP_CORNER,CORNER_LEFT_LOWER);
   ObjectSetInteger(0,BTN,OBJPROP_XDISTANCE,10);
   ObjectSetInteger(0,BTN,OBJPROP_YDISTANCE,40);
   ObjectSetInteger(0,BTN,OBJPROP_XSIZE,190);
   ObjectSetInteger(0,BTN,OBJPROP_YSIZE,28);
   ObjectSetInteger(0,BTN,OBJPROP_FONTSIZE,9);
   ObjectSetInteger(0,BTN,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,BTN,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,BTN,OBJPROP_ZORDER,10);
   SetButtonText("Analyze current market",C'38,92,160'); }

void RunManualAnalysis(){
   g_busy=true; SetButtonText("Analyzing...",clrDimGray);
   bool ch=false; for(int m=0;m<3;m++) if(UpdateMA(g_ma[m])) ch=true;
   if(ch){ g_lastChartBar=iTime(_Symbol,_Period,0); DrawLevels(); }
   int bm,bk; double lp=0; string lt="NONE"; int lives=0; string nm=""; g_lvlExtra="";
   if(NearestLevel(DBL_MAX,bm,bk,false)){ SLevel L=g_ma[bm].act[bk]; int ef=(L.cnt%2==0)?L.type:-L.type;
      lp=L.y; lt=ef==1?"PEAK":"BOTTOM"; lives=InpMaxMit-L.cnt; nm="MA"+IntegerToString(bm+1)+" "+EnumToString(g_ma[bm].ftf); g_lvlExtra=LevelMeta(bm,L); }
   g_crossExtra=",\"manual_request\":true";
   string payload=BuildPayload("MANUAL",lp,lt,"",lives,nm);
   g_crossExtra=""; g_lvlExtra="";
   string resp;
   if(AskAI(payload,resp)) ApplyDecision(resp,"MANUAL"); else Print("[MANUAL] AI request failed");
   SetButtonText("Analyze current market",C'38,92,160'); g_busy=false; }

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam){
   if(id==CHARTEVENT_OBJECT_CLICK&&sparam==BTN){
      ObjectSetInteger(0,BTN,OBJPROP_STATE,false);
      if(!g_busy) g_manualReq=true; } }

//==================== Events =======================================
int OnInit(){
   if(InpMa1Len<1||InpMa2Len<1||InpMa3Len<1||InpMaxMit<1) return INIT_PARAMETERS_INCORRECT;
   g_bg=(color)ChartGetInteger(0,CHART_COLOR_BACKGROUND);
   g_base="MAIL"+IntegerToString((long)GetTickCount())+"_";
   g_trade.SetExpertMagicNumber(InpMagic); g_trade.SetDeviationInPoints(30); g_trade.SetTypeFillingBySymbol(_Symbol);
   InitMA(g_ma[0],InpMa1On,InpMa1Lvl,InpMa1TF,InpMa1Type,InpMa1Src,InpMa1Len,"A");
   InitMA(g_ma[1],InpMa2On,InpMa2Lvl,InpMa2TF,InpMa2Type,InpMa2Src,InpMa2Len,"B");
   InitMA(g_ma[2],InpMa3On,InpMa3Lvl,InpMa3TF,InpMa3Type,InpMa3Src,InpMa3Len,"C");
   for(int d=0;d<2;d++){ g_set[d].beSl=0; g_set[d].beDone=false; }
   CreateButton();
   EventSetMillisecondTimer(250);
   if(InpTestMode) Print("[AI-TEST] TEST MODE ON: decisions are logged only, no orders will be placed");
   return INIT_SUCCEEDED; }
void OnDeinit(const int reason){
   EventKillTimer();
   ObjectDelete(0,BTN);
   for(int m=0;m<3;m++) if(StringLen(g_ma[m].prefix)>0) ObjectsDeleteAll(0,g_ma[m].prefix);
   ChartRedraw(0); }
void OnTimer(){
   if(g_manualReq&&!g_busy){ g_manualReq=false; RunManualAnalysis(); return; }
   CheckMaCross(); TestTimer(); }
void OnTick(){
   bool ch=false; for(int m=0;m<3;m++) if(UpdateMA(g_ma[m])) ch=true;
   datetime cb=iTime(_Symbol,_Period,0);
   if(ch||cb!=g_lastChartBar){ g_lastChartBar=cb; DrawLevels(); }
   UpdateProximity((SymbolInfoDouble(_Symbol,SYMBOL_BID)+SymbolInfoDouble(_Symbol,SYMBOL_ASK))/2.0);
   if(InpTestMode&&InpTestIntervalSec>0) return;
   ManageOpen();
   if(CountOurs()>0) ManageTrades();
   CheckEntryTrigger(); }
