#property strict
#property version "1.05"
#include <Trade/Trade.mqh>

input group "Signal - closed candles"
input int InpEmaPeriod=50;
input int InpHmaPeriod=21;
input ENUM_APPLIED_PRICE InpMaPrice=PRICE_CLOSE;
input int InpMinimumMASeparationPoints=100; // Mandatory earlier HMA/EMA separation
input int InpMaximumSignalCloseDistancePoints=100; // Maximum absolute close-to-EMA distance
input bool InpEnableEMAPatternEntries=true; // Enable EMA rejection alternatives
input bool InpUseWickPatterns=true; // Require hammer/pin/engulfing; reject doji
input double InpDojiBodyMaxPercent=10;
input ulong InpMagic=20261014;
input int InpSlippagePoints=30;

input group "Orders and breakeven"
input double InpLot=0.10;
input int InpSLPoints=700;
input int InpTPPoints=1400;
input int InpBreakEvenPoints=200; // 0 disables per-ticket BE
input int InpBreakEvenOffsetPoints=0;

input group "Partials and trailing"
input int InpPartialCount=5; // N segments: N-1 inner partials, final broker TP
input double InpPartialPercent=10; // Percent of original volume
input int InpTrailStartPoints=1000;
input int InpTrailExtendPoints=1000;
input int InpMaxTPExtensions=3;
input int InpTrailDistancePoints=600;

input group "Drawdown entries"
input int InpDDStepPoints=200;
input int InpMaxDDEntries=2;
input double InpWorstMinProfit=0; // Profit+swap+allocated entry costs must exceed this

input group "Survival"
input bool InpEnableSurvival=true;
input double InpSurvivalMinProfit=0; // Realized plus floating basket P/L; excludes future exit costs

input group "Chart"
input bool InpDarkTheme=true;
input int InpDrawBars=250;
input color InpEmaColor=C'80,170,255';
input color InpHmaColor=C'255,167,38';

// One basket per direction, including its DD tickets. Independent TP per ticket.
// Separation is observed on closed bars only. Earlier separation qualifies the
// following bars until a signal is consumed (including a rejected/blocked signal).
// After that a fresh earlier separation is required. No arbitrary expiry.
// The signal bar cannot establish its own separation qualification.
// State is in memory; start a fresh tester pass. Do not attach over existing trades.
CTrade tr;
int emaHandle=INVALID_HANDLE;
datetime lastBar=0;
bool separated=false;
string status="Waiting for earlier MA separation";

struct TicketState
{
 ulong ticket,id;
 double entry,original,initialTP;
 int dir,partials,extensions;
 bool trailing;
};
TicketState states[];
struct Basket
{
 bool active,closing;
 int dir,dd;
 double lot,anchorSL,lastFill;
 datetime start;
};
Basket buys,sells;

bool Our(ulong t)
{
 return PositionSelectByTicket(t) && PositionGetString(POSITION_SYMBOL)==_Symbol &&
        (ulong)PositionGetInteger(POSITION_MAGIC)==InpMagic;
}
int Count(int d)
{
 int n=0;
 for(int i=0;i<PositionsTotal();i++)
 {
  ulong t=PositionGetTicket(i);
  if(Our(t) && ((PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?1:-1)==d) n++;
 }
 return n;
}
bool Executed()
{
 uint r=tr.ResultRetcode();
 return r==TRADE_RETCODE_DONE || r==TRADE_RETCODE_DONE_PARTIAL;
}
double Price(double p)
{
 double s=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
 return NormalizeDouble(s>0?MathRound(p/s)*s:p,_Digits);
}
double Volume(double v)
{
 double s=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
 if(s<=0) return 0;
 return NormalizeDouble(MathFloor(v/s+1e-8)*s,8);
}
bool StopsValid(int d,double sl,double tp,bool modification=false)
{
 double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID),ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
 long level=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
 if(modification) level=MathMax(level,SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL));
 double gap=(level+1)*_Point;
 if(d==1) return (sl==0 || bid-sl>=gap) && (tp==0 || tp-bid>=gap);
 return (sl==0 || sl-ask>=gap) && (tp==0 || ask-tp>=gap);
}
bool Modify(ulong t,double sl,double tp)
{
 if(!Our(t)) return false;
 int d=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
 sl=Price(sl); tp=Price(tp);
 if(!StopsValid(d,sl,tp,true)) return false;
 if(MathAbs(PositionGetDouble(POSITION_SL)-sl)<_Point*0.1 &&
    MathAbs(PositionGetDouble(POSITION_TP)-tp)<_Point*0.1) return true;
 if(tr.PositionModify(t,sl,tp) && Executed()) return true;
 PrintFormat("Modify #%I64u: %s",t,tr.ResultRetcodeDescription());
 return false;
}
int Index(ulong t)
{
 for(int i=0;i<ArraySize(states);i++) if(states[i].ticket==t) return i;
 return -1;
}
void Sync()
{
 for(int i=ArraySize(states)-1;i>=0;i--)
 {
  if(Our(states[i].ticket)) continue;
  for(int j=i;j<ArraySize(states)-1;j++) states[j]=states[j+1];
  ArrayResize(states,ArraySize(states)-1);
 }
 for(int i=0;i<PositionsTotal();i++)
 {
  ulong t=PositionGetTicket(i);
  if(!Our(t) || Index(t)>=0) continue;
  int n=ArraySize(states); ArrayResize(states,n+1);
  states[n].ticket=t;
  states[n].id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
  states[n].entry=PositionGetDouble(POSITION_PRICE_OPEN);
  states[n].original=PositionGetDouble(POSITION_VOLUME);
  states[n].initialTP=PositionGetDouble(POSITION_TP);
  states[n].dir=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
  states[n].partials=0; states[n].extensions=0; states[n].trailing=false;
 }
}

// History costs are needed only for worst/survival decisions, not for MA signals.
double EntryCosts(ulong id)
{
 double c=0;
 if(!HistorySelectByPosition(id)) return 0;
 for(int i=0;i<HistoryDealsTotal();i++)
 {
  ulong t=HistoryDealGetTicket(i);
  if(HistoryDealGetInteger(t,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;
  c+=HistoryDealGetDouble(t,DEAL_COMMISSION)+HistoryDealGetDouble(t,DEAL_FEE);
 }
 return c;
}
double TicketNet(int i)
{
 if(!Our(states[i].ticket)) return 0;
 double vol=PositionGetDouble(POSITION_VOLUME);
 double net=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
 return net+EntryCosts(states[i].id)*vol/states[i].original;
}
double BasketNet(Basket &b)
{
 double net=0;
 if(HistorySelect(b.start,TimeCurrent()))
 {
  for(int i=0;i<HistoryDealsTotal();i++)
  {
   ulong t=HistoryDealGetTicket(i);
   if(HistoryDealGetString(t,DEAL_SYMBOL)!=_Symbol ||
      (ulong)HistoryDealGetInteger(t,DEAL_MAGIC)!=InpMagic) continue;
   ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(t,DEAL_TYPE);
   ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(t,DEAL_ENTRY);
   if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL) continue;
   int direction=(type==DEAL_TYPE_BUY?1:-1);
   if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY) direction=-direction;
   if(direction!=b.dir) continue;
   net+=HistoryDealGetDouble(t,DEAL_PROFIT)+HistoryDealGetDouble(t,DEAL_SWAP)+
        HistoryDealGetDouble(t,DEAL_COMMISSION)+HistoryDealGetDouble(t,DEAL_FEE);
  }
 }
 for(int i=0;i<PositionsTotal();i++)
 {
  ulong t=PositionGetTicket(i);
  if(!Our(t)) continue;
  int d=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
  if(d==b.dir) net+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
 }
 return net;
}
bool Send(Basket &b,bool dd)
{
 double v=dd?b.lot:Volume(InpLot);
 if(v<SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN) || v>SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX)) return false;
 double q=SymbolInfoDouble(_Symbol,b.dir==1?SYMBOL_ASK:SYMBOL_BID);
 double sl=dd?b.anchorSL:Price(q-b.dir*InpSLPoints*_Point);
 double tp=Price(q+b.dir*InpTPPoints*_Point);
 if(!StopsValid(b.dir,sl,tp)) return false;
 string comment=StringFormat("HE|%s|%s",b.dir==1?"B":"S",dd?"DD":"MAIN");
 bool ok=b.dir==1?tr.Buy(v,_Symbol,0,sl,tp,comment):tr.Sell(v,_Symbol,0,sl,tp,comment);
 if(!ok || !Executed())
 {
  Print("Entry failed: ",tr.ResultRetcodeDescription()); return false;
 }
 b.lastFill=tr.ResultPrice();
 if(b.lastFill<=0) b.lastFill=q;
 if(!dd)
 {
  b.active=true; b.closing=false; b.dd=0; b.lot=v; b.anchorSL=sl; b.start=TimeCurrent();
 }
 else b.dd++;
 Sync();
 PrintFormat("%s %s fill %.8f DD count %d",b.dir==1?"BUY":"SELL",dd?"DD":"MAIN",b.lastFill,b.dd);
 return true;
}
void CloseBasket(Basket &b)
{
 for(int i=PositionsTotal()-1;i>=0;i--)
 {
  ulong t=PositionGetTicket(i);
  if(!Our(t)) continue;
  int d=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
  if(d==b.dir && (!tr.PositionClose(t) || !Executed()))
   Print("Basket close failed: ",tr.ResultRetcodeDescription());
 }
}
void ManageTicket(int i)
{
 if(!Our(states[i].ticket)) return;
 ulong t=states[i].ticket;
 int d=states[i].dir;
 double q=SymbolInfoDouble(_Symbol,d==1?SYMBOL_BID:SYMBOL_ASK);
 double gain=d*(q-states[i].entry)/_Point;
 if(InpBreakEvenPoints>0 && gain>=InpBreakEvenPoints)
 {
  double be=Price(states[i].entry+d*InpBreakEvenOffsetPoints*_Point);
  double sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
  if(sl==0 || d*(be-sl)>_Point*0.1) Modify(t,be,tp);
 }
 if(gain>=InpTrailStartPoints) states[i].trailing=true;
 if(states[i].trailing)
 {
  while(states[i].extensions<InpMaxTPExtensions &&
        gain>=InpTrailStartPoints+states[i].extensions*InpTrailExtendPoints)
  {
   if(!Our(t)) return;
   double tp=Price(states[i].initialTP+d*(states[i].extensions+1)*InpTrailExtendPoints*_Point);
   if(!Modify(t,PositionGetDouble(POSITION_SL),tp)) break;
   states[i].extensions++;
  }
  if(!Our(t)) return;
  double sl=Price(q-d*InpTrailDistancePoints*_Point),old=PositionGetDouble(POSITION_SL);
  if(old==0 || d*(sl-old)>_Point*0.1) Modify(t,sl,PositionGetDouble(POSITION_TP));
  return; // No partials after trailing activates
 }
 double distance=d*(states[i].initialTP-states[i].entry)/_Point;
 if(distance<=0 || InpPartialPercent<=0) return;
 for(int k=states[i].partials+1;k<InpPartialCount;k++)
 {
  if(gain+1e-8<distance*k/InpPartialCount) break;
  if(!Our(t)) return;
  double vol=PositionGetDouble(POSITION_VOLUME),min=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
  double piece=Volume(states[i].original*InpPartialPercent/100.0);
  if(piece<min || Volume(vol-piece)<min)
  {
   states[i].partials=k;
   PrintFormat("Partial #%d on %I64u skipped: broker volume minimum",k,t); continue;
  }
  if(!tr.PositionClosePartial(t,piece) || !Executed()) break;
  states[i].partials=k;
  PrintFormat("Partial #%d on %I64u closed %.8f",k,t,piece);
 }
}
void Manage(Basket &b)
{
 if(!b.active) return;
 if(Count(b.dir)==0) { b.active=false; b.closing=false; return; }
 if(b.closing) { CloseBasket(b); return; }
 if(InpEnableSurvival && InpMaxDDEntries>0 && b.dd>=InpMaxDDEntries && BasketNet(b)>=InpSurvivalMinProfit)
 {
  b.closing=true; CloseBasket(b); return;
 }
 ulong newest=0; long stamp=-1;
 for(int i=0;i<PositionsTotal();i++)
 {
  ulong t=PositionGetTicket(i);
  if(!Our(t)) continue;
  int d=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
  if(d!=b.dir) continue;
  long s=PositionGetInteger(POSITION_TIME_MSC);
  if(s>stamp || (s==stamp && t>newest)) { stamp=s; newest=t; }
 }
 if(b.dd>0)
 {
  for(int i=0;i<ArraySize(states);i++)
  {
   if(states[i].dir!=b.dir || states[i].ticket==newest || !Our(states[i].ticket)) continue;
   if(TicketNet(i)>InpWorstMinProfit)
    if(tr.PositionClose(states[i].ticket) && Executed()) Print("Closed profitable older entry ",states[i].ticket);
  }
 }
 for(int i=0;i<ArraySize(states);i++) if(states[i].dir==b.dir) ManageTicket(i);
 if(Count(b.dir)==0) return;
 if(b.dd>=InpMaxDDEntries || InpDDStepPoints<=0) return;
 double q=SymbolInfoDouble(_Symbol,b.dir==1?SYMBOL_BID:SYMBOL_ASK);
 if(-b.dir*(q-b.lastFill)/_Point>=InpDDStepPoints) Send(b,true);
}

double Applied(MqlRates &r)
{
 switch(InpMaPrice)
 {
  case PRICE_OPEN:return r.open;
  case PRICE_HIGH:return r.high;
  case PRICE_LOW:return r.low;
  case PRICE_MEDIAN:return (r.high+r.low)/2;
  case PRICE_TYPICAL:return (r.high+r.low+r.close)/3;
  case PRICE_WEIGHTED:return (r.high+r.low+2*r.close)/4;
  default:return r.close;
 }
}
double WMA(double &p[],int shift,int n)
{
 double sum=0,w=0;
 for(int j=0;j<n;j++) { sum+=p[shift+j]*(n-j); w+=n-j; }
 return sum/w;
}
double HMA(double &p[],int shift)
{
 int half=MathMax(1,InpHmaPeriod/2),root=MathMax(1,(int)MathRound(MathSqrt(InpHmaPeriod)));
 double sum=0,w=0;
 for(int j=0;j<root;j++)
 {
  sum+=(2*WMA(p,shift+j,half)-WMA(p,shift+j,InpHmaPeriod))*(root-j); w+=root-j;
 }
 return sum/w;
}
bool Doji(MqlRates &r)
{
 double range=r.high-r.low;
 return range<=0 || MathAbs(r.close-r.open)<=range*InpDojiBodyMaxPercent/100;
}
bool Rejection(MqlRates &r,int d)
{
 if(Doji(r)) return false;
 double range=r.high-r.low,body=MathAbs(r.close-r.open);
 double upper=r.high-MathMax(r.open,r.close),lower=MathMin(r.open,r.close)-r.low;
 if(d*(r.close-r.open)<=0) return false;
 double main=d==1?lower:upper,other=d==1?upper:lower;
 bool end=d==1?r.close>=r.low+range*0.67:r.close<=r.low+range*0.33;
 return end && main>=2*body && (other<=body || main>=2*other);
}
bool Engulf(MqlRates &r,MqlRates &prev,int d)
{
 if(Doji(r)) return false;
 if(d==1) return r.close>r.open && prev.close<prev.open && r.open<=prev.close && r.close>=prev.open;
 return r.close<r.open && prev.close>prev.open && r.open>=prev.close && r.close<=prev.open;
}
void Entry(int d,string reason)
{
 if(Count(d)>0) { status="Signal blocked: direction already active"; return; }
 bool ok=d==1?Send(buys,false):Send(sells,false);
 status=(ok?"Entered ":"Entry rejected ")+(d==1?"BUY: ":"SELL: ")+reason;
 Print(status);
}
void Signals(MqlRates &r[],double &e[],double &p[])
{
 double h1=HMA(p,1),h2=HMA(p,2);
 // 'separated' only contains observations from bars BEFORE bar 1.
 bool qualified=separated;
 int d=0; string reason="";
 bool crossUp=h2<=e[2] && h1>e[1];
 bool crossDown=h2>=e[2] && h1<e[1];
 if(crossUp) { d=1; reason="HMA crosses ABOVE EMA"; }
 else if(crossDown) { d=-1; reason="HMA crosses BELOW EMA"; }
 else if(InpEnableEMAPatternEntries)
 {
  bool bullWick=r[1].low<e[1] && MathMin(r[1].open,r[1].close)>e[1] && r[1].close>r[1].open;
  bool bearWick=r[1].high>e[1] && MathMax(r[1].open,r[1].close)<e[1] && r[1].close<r[1].open;
  bool bullEng=r[2].close<e[2] && r[1].close>e[1] && Engulf(r[1],r[2],1);
  bool bearEng=r[2].close>e[2] && r[1].close<e[1] && Engulf(r[1],r[2],-1);
  if(bullEng || (bullWick && (!InpUseWickPatterns || Rejection(r[1],1))))
   { d=1; reason=bullEng?"Bullish engulfing back above EMA":"Bullish EMA wick rejection"; }
  else if(bearEng || (bearWick && (!InpUseWickPatterns || Rejection(r[1],-1))))
   { d=-1; reason=bearEng?"Bearish engulfing back below EMA":"Bearish EMA wick rejection"; }
 }
 if(d!=0)
 {
  double gap=MathAbs(r[1].close-e[1])/_Point;
  if(!qualified) status="Signal rejected: no earlier HMA/EMA separation";
  else if(gap>InpMaximumSignalCloseDistancePoints+1e-8)
   status=StringFormat("Signal rejected: close %.1f points from EMA",gap);
  else Entry(d,reason);
  // Consume the setup; never defer a too-fast/blocked signal to another bar.
  separated=false;
 }
 // This bar can only qualify a FUTURE signal, never itself.
 if(MathAbs(h1-e[1])/_Point+1e-8>=InpMinimumMASeparationPoints) separated=true;
}
void Theme()
{
 if(!InpDarkTheme) return;
 ChartSetInteger(0,CHART_MODE,CHART_CANDLES);
 ChartSetInteger(0,CHART_SHOW_GRID,false);
 ChartSetInteger(0,CHART_COLOR_BACKGROUND,C'14,16,22');
 ChartSetInteger(0,CHART_COLOR_FOREGROUND,C'176,184,196');
 ChartSetInteger(0,CHART_COLOR_CHART_UP,C'38,166,154');
 ChartSetInteger(0,CHART_COLOR_CANDLE_BULL,C'38,166,154');
 ChartSetInteger(0,CHART_COLOR_CHART_DOWN,C'239,83,80');
 ChartSetInteger(0,CHART_COLOR_CANDLE_BEAR,C'239,83,80');
}
void Segment(string name,datetime a,double x,datetime b,double y,color c)
{
 if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_TREND,0,a,x,b,y);
 else { ObjectMove(0,name,0,a,x); ObjectMove(0,name,1,b,y); }
 ObjectSetInteger(0,name,OBJPROP_COLOR,c);
 ObjectSetInteger(0,name,OBJPROP_WIDTH,2);
 ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
 ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false);
 ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
 ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}
void Draw(MqlRates &r[],double &e[],double &p[])
{
 for(int i=1;i<InpDrawBars;i++)
 {
  Segment("HE_E_"+IntegerToString(i),r[i].time,e[i],r[i-1].time,e[i-1],InpEmaColor);
  Segment("HE_H_"+IntegerToString(i),r[i].time,HMA(p,i),r[i-1].time,HMA(p,i-1),InpHmaColor);
 }
 ChartRedraw();
}
int OnInit()
{
 if(InpEmaPeriod<2 || InpHmaPeriod<2 || InpMinimumMASeparationPoints<=0 ||
    InpMaximumSignalCloseDistancePoints<0 || InpSLPoints<=0 || InpTPPoints<=0 ||
    InpLot<=0 || InpPartialCount<1 || InpPartialPercent<0 || InpPartialPercent>100 ||
    InpTrailStartPoints<=0 || InpTrailExtendPoints<=0 || InpMaxTPExtensions<0 ||
    InpTrailDistancePoints<=0 || InpMaxDDEntries<0 || InpDDStepPoints<=0 ||
    InpBreakEvenPoints<0 || InpBreakEvenOffsetPoints<0 || InpDrawBars<3 ||
    InpDojiBodyMaxPercent<0 || InpDojiBodyMaxPercent>=100) return INIT_PARAMETERS_INCORRECT;
 if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
 { Print("Hedging account required"); return INIT_FAILED; }
 if(Count(1)>0 || Count(-1)>0)
 { Print("Start flat: this EA version does not recover state of an existing basket."); return INIT_FAILED; }
 buys.dir=1; sells.dir=-1;
 tr.SetExpertMagicNumber(InpMagic);
 tr.SetDeviationInPoints(InpSlippagePoints);
 tr.SetTypeFillingBySymbol(_Symbol);
 tr.SetAsyncMode(false);
 emaHandle=iMA(_Symbol,PERIOD_CURRENT,InpEmaPeriod,0,MODE_EMA,InpMaPrice);
 if(emaHandle==INVALID_HANDLE) return INIT_FAILED;
 Theme(); return INIT_SUCCEEDED;
}
void OnTick()
{
 Sync(); Manage(buys); Manage(sells); Sync();
 datetime bar=iTime(_Symbol,PERIOD_CURRENT,0);
 if(bar>0 && bar!=lastBar)
 {
  int root=MathMax(1,(int)MathRound(MathSqrt(InpHmaPeriod)));
  int need=InpDrawBars+InpHmaPeriod+root+5;
  MqlRates r[]; double e[],p[];
  ArraySetAsSeries(r,true); ArraySetAsSeries(e,true); ArraySetAsSeries(p,true);
  if(CopyRates(_Symbol,PERIOD_CURRENT,0,need,r)==need && CopyBuffer(emaHandle,0,0,need,e)==need)
  {
   ArrayResize(p,need);
   for(int i=0;i<need;i++) p[i]=Applied(r[i]);
   if(lastBar==0)
   {
    // Seed only the immediately preceding closed bar; no stale signals at attach.
    separated=MathAbs(HMA(p,1)-e[1])/_Point>=InpMinimumMASeparationPoints;
   }
   else Signals(r,e,p);
   lastBar=bar;
   Theme(); Draw(r,e,p);
  }
 }
 Comment(StringFormat("HMA/EMA v1.05\nEarlier separation armed: %s\n%s\nBUY %d DD %d | SELL %d DD %d",
  separated?"yes":"no",status,Count(1),buys.dd,Count(-1),sells.dd));
}
void OnDeinit(const int reason)
{
 if(emaHandle!=INVALID_HANDLE) IndicatorRelease(emaHandle);
 ObjectsDeleteAll(0,"HE_"); Comment("");
}
