#property strict
#property version "1.06"
#include <Trade/Trade.mqh>
input group "Closed-candle signals"
input int InpEmaPeriod=50;
input int InpHmaPeriod=21;
input ENUM_APPLIED_PRICE InpMaPrice=PRICE_CLOSE;
input int InpMinimumMASeparationPoints=100;
input int InpMaximumSignalCloseDistancePoints=100;
input int InpSeparationStartupLookbackBars=500; // Earlier closed bars to seed mandatory qualification
input bool InpEnableEMAPatternEntries=true;
input bool InpUseWickPatterns=true;
input double InpDojiBodyMaxPercent=10;
input bool InpLogSignalDecisions=true;
input ulong InpMagic=20261014;
input int InpSlippagePoints=30;
input group "Orders and BE"
input double InpLot=0.10;
input int InpSLPoints=700;
input int InpTPPoints=1400;
input int InpBreakEvenPoints=200;
input int InpBreakEvenOffsetPoints=0;
input group "Partials and trailing"
input int InpPartialCount=5; // N segments; N-1 partials, final TP closes remainder
input double InpPartialPercent=10;
input int InpTrailStartPoints=1000;
input int InpTrailExtendPoints=1000;
input int InpMaxTPExtensions=3;
input int InpTrailDistancePoints=600;
input group "DD and survival"
input int InpDDStepPoints=200;
input int InpMaxDDEntries=2;
input double InpWorstMinProfit=0;
input bool InpEnableSurvival=true;
input double InpSurvivalMinProfit=0;
input group "Chart"
input bool InpDarkTheme=true;
input int InpDrawBars=250;
input color InpEmaColor=C'80,170,255';
input color InpHmaColor=C'255,167,38';

// Fresh, flat start required. Management state is in memory, not restart-persistent.
// Qualification is historical absolute HMA/EMA separation, not current separation.
// It remains armed across crosses and rejected signals; successful main entry consumes it.
// A closed bar meeting separation can qualify future bars only, never itself.
// All pattern signals use CLOSED candles. One basket per direction, plus DD tickets.
CTrade tr;
int eh=INVALID_HANDLE;
datetime last=0,warnTime=0;
bool armed=false,seeded=false;
string info="Initializing";
struct PositionState { ulong t,id; double entry,initialTP,original; int d,part,ext; bool trail; };
PositionState ps[];
struct Basket { int d,dd; bool active,closing; double lot,sl,fill; datetime start; };
Basket buy,sell;

void Log(string x) { info=x; if(InpLogSignalDecisions) Print(x); }
bool Our(ulong t) { return PositionSelectByTicket(t) && PositionGetString(POSITION_SYMBOL)==_Symbol && (ulong)PositionGetInteger(POSITION_MAGIC)==InpMagic; }
int Direction() { return PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1; }
int Count(int d) { int n=0; for(int i=0;i<PositionsTotal();i++) { ulong t=PositionGetTicket(i); if(Our(t)&&Direction()==d)n++; } return n; }
bool Done() { uint r=tr.ResultRetcode(); return r==TRADE_RETCODE_DONE || r==TRADE_RETCODE_DONE_PARTIAL; }
double P(double x) { double step=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE); return NormalizeDouble(step>0?MathRound(x/step)*step:x,_Digits); }
double V(double x) { double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP); return step>0?NormalizeDouble(MathFloor(x/step+1e-8)*step,8):0; }
bool Valid(int d,double sl,double tp,bool modify=false)
{
 long n=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
 if(modify) n=MathMax(n,SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL));
 double gap=(n+1)*_Point,q=SymbolInfoDouble(_Symbol,d==1?SYMBOL_BID:SYMBOL_ASK);
 return (sl==0 || d*(q-sl)>=gap) && (tp==0 || d*(tp-q)>=gap);
}
bool Mod(ulong t,double sl,double tp)
{
 if(!Our(t))return false;
 sl=P(sl);tp=P(tp);
 if(!Valid(Direction(),sl,tp,true))return false;
 if(MathAbs(PositionGetDouble(POSITION_SL)-sl)<_Point*0.1 && MathAbs(PositionGetDouble(POSITION_TP)-tp)<_Point*0.1)return true;
 if(tr.PositionModify(t,sl,tp)&&Done())return true;
 PrintFormat("Modify %I64u failed: %s",t,tr.ResultRetcodeDescription());return false;
}
int Find(ulong t) { for(int i=0;i<ArraySize(ps);i++)if(ps[i].t==t)return i;return -1; }
void Sync()
{
 for(int i=ArraySize(ps)-1;i>=0;i--)if(!Our(ps[i].t)) { for(int j=i;j<ArraySize(ps)-1;j++)ps[j]=ps[j+1];ArrayResize(ps,ArraySize(ps)-1); }
 for(int i=0;i<PositionsTotal();i++)
 {
  ulong t=PositionGetTicket(i);if(!Our(t)||Find(t)>=0)continue;
  int n=ArraySize(ps);ArrayResize(ps,n+1);
  ps[n].t=t;ps[n].id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);ps[n].d=Direction();
  ps[n].entry=PositionGetDouble(POSITION_PRICE_OPEN);ps[n].initialTP=PositionGetDouble(POSITION_TP);
  ps[n].original=PositionGetDouble(POSITION_VOLUME);ps[n].part=0;ps[n].ext=0;ps[n].trail=false;
 }
}
double Costs(ulong id)
{
 double x=0;if(!HistorySelectByPosition(id))return 0;
 for(int i=0;i<HistoryDealsTotal();i++) { ulong t=HistoryDealGetTicket(i);if(HistoryDealGetInteger(t,DEAL_ENTRY)==DEAL_ENTRY_IN)x+=HistoryDealGetDouble(t,DEAL_COMMISSION)+HistoryDealGetDouble(t,DEAL_FEE); }
 return x;
}
double NetTicket(int i)
{
 if(!Our(ps[i].t))return 0;
 double x=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP),v=PositionGetDouble(POSITION_VOLUME);
 return x+Costs(ps[i].id)*v/ps[i].original;
}
double NetBasket(Basket &b)
{
 double x=0;
 if(HistorySelect(b.start,TimeCurrent()))for(int i=0;i<HistoryDealsTotal();i++)
 {
  ulong t=HistoryDealGetTicket(i);
  if(HistoryDealGetString(t,DEAL_SYMBOL)!=_Symbol || (ulong)HistoryDealGetInteger(t,DEAL_MAGIC)!=InpMagic)continue;
  long typ=HistoryDealGetInteger(t,DEAL_TYPE),ent=HistoryDealGetInteger(t,DEAL_ENTRY);
  if(typ!=DEAL_TYPE_BUY && typ!=DEAL_TYPE_SELL)continue;
  int d=typ==DEAL_TYPE_BUY?1:-1;if(ent==DEAL_ENTRY_OUT || ent==DEAL_ENTRY_OUT_BY)d=-d;
  if(d==b.d)x+=HistoryDealGetDouble(t,DEAL_PROFIT)+HistoryDealGetDouble(t,DEAL_SWAP)+HistoryDealGetDouble(t,DEAL_COMMISSION)+HistoryDealGetDouble(t,DEAL_FEE);
 }
 for(int i=0;i<PositionsTotal();i++){ulong t=PositionGetTicket(i);if(Our(t)&&Direction()==b.d)x+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);}
 return x;
}
bool Send(Basket &b,bool dd)
{
 double lot=dd?b.lot:V(InpLot),q=SymbolInfoDouble(_Symbol,b.d==1?SYMBOL_ASK:SYMBOL_BID);
 if(lot<SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN)||lot>SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX)){Log("ENTRY REJECTED: invalid lot size");return false;}
 double sl=dd?b.sl:P(q-b.d*InpSLPoints*_Point),tp=P(q+b.d*InpTPPoints*_Point);
 if(!Valid(b.d,sl,tp)){Log(StringFormat("ENTRY REJECTED: stops invalid; SL %.8f TP %.8f",sl,tp));return false;}
 string c=StringFormat("HE|%s|%s",b.d==1?"B":"S",dd?"DD":"MAIN");
 bool ok=b.d==1?tr.Buy(lot,_Symbol,0,sl,tp,c):tr.Sell(lot,_Symbol,0,sl,tp,c);
 if(!ok||!Done()){Log("ENTRY REJECTED: "+tr.ResultRetcodeDescription());return false;}
 b.fill=tr.ResultPrice();if(b.fill<=0)b.fill=q;
 if(dd)b.dd++;
 else{b.active=true;b.closing=false;b.dd=0;b.lot=lot;b.sl=sl;b.start=TimeCurrent();}
 Sync();return true;
}
void CloseAll(Basket &b)
{
 for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(Our(t)&&Direction()==b.d)if(!tr.PositionClose(t)||!Done())Print("Close failed: ",tr.ResultRetcodeDescription());}
}
void ManageTicket(int i)
{
 if(!Our(ps[i].t))return;
 ulong t=ps[i].t;int d=ps[i].d;
 double q=SymbolInfoDouble(_Symbol,d==1?SYMBOL_BID:SYMBOL_ASK),gain=d*(q-ps[i].entry)/_Point;
 if(InpBreakEvenPoints>0&&gain>=InpBreakEvenPoints)
 {
  double be=P(ps[i].entry+d*InpBreakEvenOffsetPoints*_Point),sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
  if(sl==0||d*(be-sl)>_Point*0.1)Mod(t,be,tp);
 }
 if(gain>=InpTrailStartPoints)ps[i].trail=true;
 if(ps[i].trail)
 {
  while(ps[i].ext<InpMaxTPExtensions&&gain>=InpTrailStartPoints+ps[i].ext*InpTrailExtendPoints)
  {
   if(!Our(t))return;
   double tp=P(ps[i].initialTP+d*(ps[i].ext+1)*InpTrailExtendPoints*_Point);
   if(!Mod(t,PositionGetDouble(POSITION_SL),tp))break;
   ps[i].ext++;
  }
  if(!Our(t))return;
  double sl=P(q-d*InpTrailDistancePoints*_Point),old=PositionGetDouble(POSITION_SL);
  if(old==0||d*(sl-old)>_Point*0.1)Mod(t,sl,PositionGetDouble(POSITION_TP));return;
 }
 double dist=d*(ps[i].initialTP-ps[i].entry)/_Point;
 if(dist<=0||InpPartialPercent<=0)return;
 for(int k=ps[i].part+1;k<InpPartialCount;k++)
 {
  if(gain+1e-8<dist*k/InpPartialCount)break;if(!Our(t))return;
  double v=PositionGetDouble(POSITION_VOLUME),min=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),piece=V(ps[i].original*InpPartialPercent/100);
  if(piece<min || V(v-piece)<min){ps[i].part=k;Print("Partial skipped: volume minimum on ",t);continue;}
  if(!tr.PositionClosePartial(t,piece)||!Done())break;
  ps[i].part=k;PrintFormat("Partial %d ticket %I64u volume %.8f",k,t,piece);
 }
}
void Manage(Basket &b)
{
 if(!b.active)return;
 if(Count(b.d)==0){b.active=false;b.closing=false;return;}
 if(b.closing){CloseAll(b);return;}
 if(InpEnableSurvival&&InpMaxDDEntries>0&&b.dd>=InpMaxDDEntries&&NetBasket(b)>=InpSurvivalMinProfit){b.closing=true;CloseAll(b);return;}
 ulong newest=0;long stamp=-1;
 for(int i=0;i<PositionsTotal();i++)
 {
  ulong t=PositionGetTicket(i);if(!Our(t)||Direction()!=b.d)continue;long m=PositionGetInteger(POSITION_TIME_MSC);
  if(m>stamp||(m==stamp&&t>newest)){stamp=m;newest=t;}
 }
 if(b.dd>0)for(int i=0;i<ArraySize(ps);i++)if(ps[i].d==b.d&&ps[i].t!=newest&&Our(ps[i].t)&&NetTicket(i)>InpWorstMinProfit)tr.PositionClose(ps[i].t);
 for(int i=0;i<ArraySize(ps);i++)if(ps[i].d==b.d)ManageTicket(i);
 if(Count(b.d)==0||b.dd>=InpMaxDDEntries)return;
 double q=SymbolInfoDouble(_Symbol,b.d==1?SYMBOL_BID:SYMBOL_ASK);
 if(-b.d*(q-b.fill)/_Point>=InpDDStepPoints)Send(b,true);
}
double Applied(MqlRates &r)
{
 switch(InpMaPrice){case PRICE_OPEN:return r.open;case PRICE_HIGH:return r.high;case PRICE_LOW:return r.low;case PRICE_MEDIAN:return (r.high+r.low)/2;case PRICE_TYPICAL:return (r.high+r.low+r.close)/3;case PRICE_WEIGHTED:return (r.high+r.low+2*r.close)/4;default:return r.close;}
}
int Root(){return MathMax(1,(int)MathRound(MathSqrt(InpHmaPeriod)));}
double WMA(double &p[],int start,int n){double x=0,w=0;for(int j=0;j<n;j++){x+=p[start+j]*(n-j);w+=n-j;}return x/w;}
double HMA(double &p[],int start){int root=Root(),half=MathMax(1,InpHmaPeriod/2);double x=0,w=0;for(int j=0;j<root;j++){x+=(2*WMA(p,start+j,half)-WMA(p,start+j,InpHmaPeriod))*(root-j);w+=root-j;}return x/w;}
bool Read(int n,MqlRates &r[],double &e[],double &p[])
{
 ArraySetAsSeries(r,true);ArraySetAsSeries(e,true);ArraySetAsSeries(p,true);
 if(BarsCalculated(eh)<n)return false;
 if(CopyRates(_Symbol,PERIOD_CURRENT,0,n,r)!=n||CopyBuffer(eh,0,0,n,e)!=n)return false;
 ArrayResize(p,n);for(int i=0;i<n;i++){if(e[i]==EMPTY_VALUE||!MathIsValidNumber(e[i]))return false;p[i]=Applied(r[i]);}return true;
}
bool Doji(MqlRates &r){double span=r.high-r.low;return span<=0||MathAbs(r.close-r.open)<=span*InpDojiBodyMaxPercent/100;}
bool Reject(MqlRates &r,int d)
{
 if(Doji(r)||d*(r.close-r.open)<=0)return false;
 double span=r.high-r.low,body=MathAbs(r.close-r.open),up=r.high-MathMax(r.open,r.close),lo=MathMin(r.open,r.close)-r.low;
 double main=d==1?lo:up,other=d==1?up:lo;
 bool end=d==1?r.close>=r.low+span*0.67:r.close<=r.low+span*0.33;
 return end&&main>=2*body&&(other<=body||main>=2*other);
}
bool Engulf(MqlRates &r,MqlRates &prev,int d)
{
 if(Doji(r))return false;
 if(d==1)return r.close>r.open&&prev.close<prev.open&&r.open<=prev.close&&r.close>=prev.open;
 return r.close<r.open&&prev.close>prev.open&&r.open>=prev.close&&r.close<=prev.open;
}
void Signals(MqlRates &r[],double &e[],double &p[])
{
 double h1=HMA(p,1),h2=HMA(p,2);int d=0;string why="";
 bool up=h2<=e[2]&&h1>e[1],down=h2>=e[2]&&h1<e[1];
 if(up){d=1;why="HMA crosses above EMA";}else if(down){d=-1;why="HMA crosses below EMA";}
 else if(InpEnableEMAPatternEntries)
 {
  // True rejection wick: EMA lies between the extreme and the candle body.
  bool bw=r[1].low<e[1]&&MathMin(r[1].open,r[1].close)>e[1]&&r[1].close>r[1].open;
  bool sw=r[1].high>e[1]&&MathMax(r[1].open,r[1].close)<e[1]&&r[1].close<r[1].open;
  bool be=r[2].close<e[2]&&r[1].close>e[1]&&Engulf(r[1],r[2],1);
  bool se=r[2].close>e[2]&&r[1].close<e[1]&&Engulf(r[1],r[2],-1);
  if(be||(bw&&(!InpUseWickPatterns||Reject(r[1],1)))){d=1;why=be?"Bullish engulfing above EMA":"Bullish EMA rejection";}
  else if(se||(sw&&(!InpUseWickPatterns||Reject(r[1],-1)))){d=-1;why=se?"Bearish engulfing below EMA":"Bearish EMA rejection";}
 }
 if(d!=0)
 {
  double gap=MathAbs(r[1].close-e[1])/_Point;
  string label=TimeToString(r[1].time)+" "+why;
  if(!armed)Log(label+": REJECTED, no earlier separation");
  else if(gap>InpMaximumSignalCloseDistancePoints+1e-8)Log(label+StringFormat(": REJECTED, close distance %.1f > %d",gap,InpMaximumSignalCloseDistancePoints));
  else if(Count(d)>0)Log(label+": BLOCKED, basket already active");
  else
  {
   bool ok=d==1?Send(buy,false):Send(sell,false);
   if(ok){armed=false;Log(label+": ENTERED");}
  }
 }
 // Only AFTER evaluating bar 1 can its distance arm future candles.
 if(MathAbs(h1-e[1])/_Point+1e-8>=InpMinimumMASeparationPoints)
 {
  if(!armed&&InpLogSignalDecisions)Print("Separation armed for future bars: ",TimeToString(r[1].time));
  armed=true;
 }
}
void Theme()
{
 if(!InpDarkTheme)return;
 ChartSetInteger(0,CHART_MODE,CHART_CANDLES);ChartSetInteger(0,CHART_SHOW_GRID,false);
 ChartSetInteger(0,CHART_COLOR_BACKGROUND,C'14,16,22');ChartSetInteger(0,CHART_COLOR_FOREGROUND,C'176,184,196');
 ChartSetInteger(0,CHART_COLOR_CHART_UP,C'38,166,154');ChartSetInteger(0,CHART_COLOR_CANDLE_BULL,C'38,166,154');
 ChartSetInteger(0,CHART_COLOR_CHART_DOWN,C'239,83,80');ChartSetInteger(0,CHART_COLOR_CANDLE_BEAR,C'239,83,80');
}
void Line(string name,datetime a,double x,datetime b,double y,color c)
{
 if(ObjectFind(0,name)<0)ObjectCreate(0,name,OBJ_TREND,0,a,x,b,y);
 else{ObjectMove(0,name,0,a,x);ObjectMove(0,name,1,b,y);}
 ObjectSetInteger(0,name,OBJPROP_COLOR,c);ObjectSetInteger(0,name,OBJPROP_WIDTH,2);
 ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false);ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
 ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}
void Draw()
{
 if(MQLInfoInteger(MQL_TESTER)&&!MQLInfoInteger(MQL_VISUAL_MODE))return;
 int base=InpHmaPeriod+Root()+3;
 int avail=MathMin(Bars(_Symbol,PERIOD_CURRENT),BarsCalculated(eh));
 int shown=MathMin(InpDrawBars,avail-base);
 if(shown<3)return;
 MqlRates r[];double e[],p[];if(!Read(shown+base,r,e,p))return;
 for(int i=1;i<shown;i++)
 {
  Line("HE_E_"+IntegerToString(i),r[i].time,e[i],r[i-1].time,e[i-1],InpEmaColor);
  Line("HE_H_"+IntegerToString(i),r[i].time,HMA(p,i),r[i-1].time,HMA(p,i-1),InpHmaColor);
 }
 ChartRedraw();
}
void Seed()
{
 int base=InpHmaPeriod+Root()+3,avail=MathMin(Bars(_Symbol,PERIOD_CURRENT),BarsCalculated(eh));
 int look=MathMin(InpSeparationStartupLookbackBars,avail-base-2);
 if(look<1)return;
 MqlRates r[];double e[],p[];if(!Read(look+base+2,r,e,p))return;
 // Bar 1 is the candidate signal: only bars 2 and older can seed it.
 for(int j=2;j<=look+1;j++)if(MathAbs(HMA(p,j)-e[j])/_Point+1e-8>=InpMinimumMASeparationPoints){armed=true;break;}
 seeded=true;Log(StringFormat("Startup scanned %d earlier bars; separation armed=%s",look,armed?"yes":"no"));
}
int OnInit()
{
 if(InpEmaPeriod<2||InpHmaPeriod<2||InpMinimumMASeparationPoints<=0||InpMaximumSignalCloseDistancePoints<0||InpSeparationStartupLookbackBars<1||InpSLPoints<=0||InpTPPoints<=0||InpLot<=0||InpPartialCount<1||InpPartialPercent<0||InpPartialPercent>100||InpTrailStartPoints<=0||InpTrailExtendPoints<=0||InpMaxTPExtensions<0||InpTrailDistancePoints<=0||InpMaxDDEntries<0||InpDDStepPoints<=0||InpBreakEvenPoints<0||InpBreakEvenOffsetPoints<0||InpDrawBars<3||InpDojiBodyMaxPercent<0||InpDojiBodyMaxPercent>=100)return INIT_PARAMETERS_INCORRECT;
 if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING){Print("Hedging account required");return INIT_FAILED;}
 if(Count(1)>0||Count(-1)>0){Print("Start flat: basket restart recovery is not supported");return INIT_FAILED;}
 buy.d=1;sell.d=-1;tr.SetExpertMagicNumber(InpMagic);tr.SetDeviationInPoints(InpSlippagePoints);tr.SetTypeFillingBySymbol(_Symbol);tr.SetAsyncMode(false);
 eh=iMA(_Symbol,PERIOD_CURRENT,InpEmaPeriod,0,MODE_EMA,InpMaPrice);
 if(eh==INVALID_HANDLE)return INIT_FAILED;
 Theme();return INIT_SUCCEEDED;
}
void OnTick()
{
 Sync();Manage(buy);Manage(sell);Sync();
 datetime bar=iTime(_Symbol,PERIOD_CURRENT,0);
 if(bar>0&&bar!=last)
 {
  // Signal data requirement independent of chart length.
  int need=InpHmaPeriod+Root()+5;MqlRates r[];double e[],p[];
  if(Read(need,r,e,p))
  {
   if(!seeded)Seed();
   if(seeded){Signals(r,e,p);last=bar;Theme();Draw();}
  }
  else if(TimeCurrent()-warnTime>=60){warnTime=TimeCurrent();Log(StringFormat("Waiting for indicator data: need %d, calculated %d",need,BarsCalculated(eh)));}
 }
 Comment(StringFormat("HMA/EMA v1.06\nSeparation armed: %s\n%s\nBUY %d DD %d | SELL %d DD %d",armed?"yes":"no",info,Count(1),buy.dd,Count(-1),sell.dd));
}
void OnDeinit(const int reason){if(eh!=INVALID_HANDLE)IndicatorRelease(eh);ObjectsDeleteAll(0,"HE_");Comment("");}
