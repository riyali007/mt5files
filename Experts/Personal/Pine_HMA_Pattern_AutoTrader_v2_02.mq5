#property strict
#property version "2.02"
#include <Trade/Trade.mqh>
// Active Pine conditions only: BUY C2-C7, SELL C2-C9 (completed candles).
// Signal thresholds are RAW PRICE units; SL/TP/BE/trail/DD/survival distances are broker POINTS.
// Hedging account, start flat. Runtime state is not restart-persistent.
enum ENUM_SURVIVAL_MODE
{
 SURVIVAL_AVG_PRICE=0, // Close when exit price returns to basket average entry (+offset)
 SURVIVAL_NET_PL=1     // Close when realized + floating basket P/L >= threshold
};
input group "Pine signal parameters"
input int InpHmaLength=34;
input int InpEmaLength=233;
input double InpHmaTenBarDifference=3.0;
input double InpMaximumEngulfBody=3.0;
input double InpMinimumEndWick=0.1;
input double InpFourBarDifference=2.0;
input double InpBuyC7Difference=5.0;
input bool InpLogSignals=true;
input ulong InpMagic=2026101402;
input int InpSlippagePoints=30;
input group "Orders and BE"
input double InpLot=0.10;
input int InpSLPoints=700;
input int InpTPPoints=1400;
input int InpBreakEvenPoints=200;
input int InpBreakEvenOffsetPoints=0;
input group "Partials and trailing"
input int InpPartialCount=5;
input double InpPartialPercent=10;
input int InpTrailStartPoints=1000;
input int InpTrailExtendPoints=1000;
input int InpMaxTPExtensions=3;
input int InpTrailDistancePoints=600;
input group "DD entries"
input int InpDDStepPoints=200;
input int InpMaxDDEntries=2;
input double InpWorstMinProfit=0;
input group "Survival mode"
input bool InpEnableSurvival=true;
input ENUM_SURVIVAL_MODE InpSurvivalMode=SURVIVAL_AVG_PRICE;
input int InpSurvivalOffsetPoints=0;   // Average-price mode: points beyond average entry (covers costs)
input double InpSurvivalMinProfit=0;   // Net P/L mode threshold
input group "Visuals"
input bool InpDarkTheme=true;
input bool InpShowHMA=true;
input bool InpShowEMA=true;
input bool InpShowSignals=true;
input int InpDrawBars=250;
input int InpRetainedLabels=200;
input color InpBuyColor=clrLime;
input color InpSellColor=clrRed;
input color InpEMAColor=clrWhite;

CTrade trade;
int emaHandle=INVALID_HANDLE;
datetime lastBar=0,lastWarning=0;
string status="Waiting for closed bar";
struct State { ulong ticket,id; int dir,partial,extension; double entry,original,tp; bool trailing; };
State states[];
struct Basket { int dir,dd; bool active,closing,armedLogged; double lot,sl,lastFill; datetime start; };
Basket buys,sells;
string labels[];

bool Our(ulong t){return PositionSelectByTicket(t)&&PositionGetString(POSITION_SYMBOL)==_Symbol&&(ulong)PositionGetInteger(POSITION_MAGIC)==InpMagic;}
int Dir(){return PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;}
int Count(int d){int n=0;for(int i=0;i<PositionsTotal();i++){ulong t=PositionGetTicket(i);if(Our(t)&&Dir()==d)n++;}return n;}
bool Done(){uint r=trade.ResultRetcode();return r==TRADE_RETCODE_DONE||r==TRADE_RETCODE_DONE_PARTIAL;}
double Price(double x){double step=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);return NormalizeDouble(step>0?MathRound(x/step)*step:x,_Digits);}
double NormVolume(double x){double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);return step>0?NormalizeDouble(MathFloor(x/step+1e-8)*step,8):0;}
void Report(string x){status=x;Print(x);}
bool Stops(int d,double sl,double tp,bool modify=false)
{
 long n=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
 if(modify)n=MathMax(n,SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL));
 double gap=(n+1)*_Point,q=SymbolInfoDouble(_Symbol,d==1?SYMBOL_BID:SYMBOL_ASK);
 return(sl==0||d*(q-sl)>=gap)&&(tp==0||d*(tp-q)>=gap);
}
bool Modify(ulong t,double sl,double tp)
{
 if(!Our(t))return false;sl=Price(sl);tp=Price(tp);
 if(!Stops(Dir(),sl,tp,true))return false;
 if(MathAbs(PositionGetDouble(POSITION_SL)-sl)<_Point*0.1&&MathAbs(PositionGetDouble(POSITION_TP)-tp)<_Point*0.1)return true;
 if(trade.PositionModify(t,sl,tp)&&Done())return true;
 PrintFormat("Modify %I64u rejected: %s",t,trade.ResultRetcodeDescription());return false;
}
int Find(ulong t){for(int i=0;i<ArraySize(states);i++)if(states[i].ticket==t)return i;return -1;}
void Sync()
{
 for(int i=ArraySize(states)-1;i>=0;i--)if(!Our(states[i].ticket))
 {for(int j=i;j<ArraySize(states)-1;j++)states[j]=states[j+1];ArrayResize(states,ArraySize(states)-1);}
 for(int i=0;i<PositionsTotal();i++)
 {
  ulong t=PositionGetTicket(i);if(!Our(t)||Find(t)>=0)continue;
  int n=ArraySize(states);ArrayResize(states,n+1);
  states[n].ticket=t;states[n].id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);states[n].dir=Dir();
  states[n].entry=PositionGetDouble(POSITION_PRICE_OPEN);states[n].original=PositionGetDouble(POSITION_VOLUME);
  states[n].tp=PositionGetDouble(POSITION_TP);states[n].partial=0;states[n].extension=0;states[n].trailing=false;
 }
}
double EntryCosts(ulong id)
{
 double x=0;if(!HistorySelectByPosition(id))return 0;
 for(int i=0;i<HistoryDealsTotal();i++){ulong t=HistoryDealGetTicket(i);if(HistoryDealGetInteger(t,DEAL_ENTRY)==DEAL_ENTRY_IN)x+=HistoryDealGetDouble(t,DEAL_COMMISSION)+HistoryDealGetDouble(t,DEAL_FEE);}
 return x;
}
double TicketNet(int i)
{
 if(!Our(states[i].ticket))return 0;
 double x=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP),v=PositionGetDouble(POSITION_VOLUME);
 return x+EntryCosts(states[i].id)*v/states[i].original;
}
double BasketNet(Basket &b)
{
 double x=0;
 if(HistorySelect(b.start-1,TimeCurrent()+1))for(int i=0;i<HistoryDealsTotal();i++)
 {
  ulong t=HistoryDealGetTicket(i);
  if(HistoryDealGetString(t,DEAL_SYMBOL)!=_Symbol||(ulong)HistoryDealGetInteger(t,DEAL_MAGIC)!=InpMagic)continue;
  long ty=HistoryDealGetInteger(t,DEAL_TYPE),en=HistoryDealGetInteger(t,DEAL_ENTRY);
  if(ty!=DEAL_TYPE_BUY&&ty!=DEAL_TYPE_SELL)continue;
  int d=ty==DEAL_TYPE_BUY?1:-1;if(en==DEAL_ENTRY_OUT||en==DEAL_ENTRY_OUT_BY)d=-d;
  if(d==b.dir)x+=HistoryDealGetDouble(t,DEAL_PROFIT)+HistoryDealGetDouble(t,DEAL_SWAP)+HistoryDealGetDouble(t,DEAL_COMMISSION)+HistoryDealGetDouble(t,DEAL_FEE);
 }
 for(int i=0;i<PositionsTotal();i++){ulong t=PositionGetTicket(i);if(Our(t)&&Dir()==b.dir)x+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);}
 return x;
}
double AverageOpen(int d,double &vol)
{
 double sum=0;vol=0;
 for(int i=0;i<PositionsTotal();i++)
 {
  ulong t=PositionGetTicket(i);if(!Our(t)||Dir()!=d)continue;
  double v=PositionGetDouble(POSITION_VOLUME);sum+=PositionGetDouble(POSITION_PRICE_OPEN)*v;vol+=v;
 }
 return vol>0?sum/vol:0;
}
bool Send(Basket &b,bool dd)
{
 double lot=dd?b.lot:NormVolume(InpLot),q=SymbolInfoDouble(_Symbol,b.dir==1?SYMBOL_ASK:SYMBOL_BID);
 if(lot<SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN)||lot>SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX)){Report("Entry rejected: lot outside broker limits");return false;}
 double sl=dd?b.sl:Price(q-b.dir*InpSLPoints*_Point),tp=Price(q+b.dir*InpTPPoints*_Point);
 if(!Stops(b.dir,sl,tp)){Report("Entry rejected: invalid SL/TP distances");return false;}
 string c=StringFormat("PC|%s|%s",b.dir==1?"B":"S",dd?"DD":"MAIN");
 bool ok=b.dir==1?trade.Buy(lot,_Symbol,0,sl,tp,c):trade.Sell(lot,_Symbol,0,sl,tp,c);
 if(!ok||!Done()){Report("Entry rejected: "+trade.ResultRetcodeDescription());return false;}
 b.lastFill=trade.ResultPrice();if(b.lastFill<=0)b.lastFill=q;
 if(dd){b.dd++;PrintFormat("%s DD entry %d/%d filled at %s",b.dir==1?"BUY":"SELL",b.dd,InpMaxDDEntries,DoubleToString(b.lastFill,_Digits));}
 else{b.active=true;b.closing=false;b.armedLogged=false;b.dd=0;b.lot=lot;b.sl=sl;b.start=TimeCurrent();}
 Sync();return true;
}
void CloseBasket(Basket &b)
{
 for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(Our(t)&&Dir()==b.dir)if(!trade.PositionClose(t)||!Done())Print("Basket close rejected: ",trade.ResultRetcodeDescription());}
}
void SurvivalLine(Basket &b,bool show,double price)
{
 string n=b.dir==1?"PC_SURV_B":"PC_SURV_S";
 if(MQLInfoInteger(MQL_TESTER)&&!MQLInfoInteger(MQL_VISUAL_MODE))return;
 if(!show){ObjectDelete(0,n);return;}
 if(ObjectFind(0,n)<0)ObjectCreate(0,n,OBJ_HLINE,0,0,price);else ObjectSetDouble(0,n,OBJPROP_PRICE,price);
 ObjectSetInteger(0,n,OBJPROP_COLOR,clrGold);ObjectSetInteger(0,n,OBJPROP_STYLE,STYLE_DASH);ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
}
bool Survival(Basket &b)
{
 bool armed=InpEnableSurvival&&InpMaxDDEntries>0&&b.dd>=InpMaxDDEntries;
 if(!armed){SurvivalLine(b,false,0);return false;}
 double vol=0,avg=AverageOpen(b.dir,vol);
 if(vol<=0)return false;
 double target=Price(avg+b.dir*InpSurvivalOffsetPoints*_Point);
 if(!b.armedLogged)
 {
  b.armedLogged=true;
  PrintFormat("SURVIVAL ARMED %s: %d DD entries used, average entry %s, target %s",b.dir==1?"BUY":"SELL",b.dd,DoubleToString(avg,_Digits),DoubleToString(target,_Digits));
 }
 bool avgMode=InpSurvivalMode==SURVIVAL_AVG_PRICE;
 SurvivalLine(b,avgMode,target);
 double exitPrice=SymbolInfoDouble(_Symbol,b.dir==1?SYMBOL_BID:SYMBOL_ASK);
 bool hit=avgMode?(b.dir*(exitPrice-target)>=0):(BasketNet(b)>=InpSurvivalMinProfit);
 if(hit)
  PrintFormat("SURVIVAL CLOSE %s: exit %s target %s net %.2f",b.dir==1?"BUY":"SELL",DoubleToString(exitPrice,_Digits),DoubleToString(target,_Digits),BasketNet(b));
 return hit;
}
void ManageTicket(int i)
{
 if(!Our(states[i].ticket))return;
 ulong t=states[i].ticket;int d=states[i].dir;
 double q=SymbolInfoDouble(_Symbol,d==1?SYMBOL_BID:SYMBOL_ASK),gain=d*(q-states[i].entry)/_Point;
 if(InpBreakEvenPoints>0&&gain>=InpBreakEvenPoints)
 {
  double be=Price(states[i].entry+d*InpBreakEvenOffsetPoints*_Point),sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
  if(sl==0||d*(be-sl)>_Point*0.1)Modify(t,be,tp);
 }
 if(gain>=InpTrailStartPoints)states[i].trailing=true;
 if(states[i].trailing)
 {
  while(states[i].extension<InpMaxTPExtensions&&gain>=InpTrailStartPoints+states[i].extension*InpTrailExtendPoints)
  {
   if(!Our(t))return;
   double tp=Price(states[i].tp+d*(states[i].extension+1)*InpTrailExtendPoints*_Point);
   if(!Modify(t,PositionGetDouble(POSITION_SL),tp))break;states[i].extension++;
  }
  if(!Our(t))return;
  double sl=Price(q-d*InpTrailDistancePoints*_Point),old=PositionGetDouble(POSITION_SL);
  if(old==0||d*(sl-old)>_Point*0.1)Modify(t,sl,PositionGetDouble(POSITION_TP));return;
 }
 double distance=d*(states[i].tp-states[i].entry)/_Point;if(distance<=0||InpPartialPercent<=0)return;
 for(int k=states[i].partial+1;k<InpPartialCount;k++)
 {
  if(gain+1e-8<distance*k/InpPartialCount)break;if(!Our(t))return;
  double v=PositionGetDouble(POSITION_VOLUME),min=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),piece=NormVolume(states[i].original*InpPartialPercent/100);
  if(piece<min||NormVolume(v-piece)<min){states[i].partial=k;Print("Partial skipped: broker volume minimum on ",t);continue;}
  if(!trade.PositionClosePartial(t,piece)||!Done())break;
  states[i].partial=k;PrintFormat("Partial %d ticket %I64u lots %.8f",k,t,piece);
 }
}
void Manage(Basket &b)
{
 if(!b.active)return;
 if(Count(b.dir)==0){b.active=false;b.closing=false;SurvivalLine(b,false,0);return;}
 if(b.closing){CloseBasket(b);return;}
 if(Survival(b)){b.closing=true;CloseBasket(b);return;}
 ulong newest=0;long stamp=-1;
 for(int i=0;i<PositionsTotal();i++){ulong t=PositionGetTicket(i);if(!Our(t)||Dir()!=b.dir)continue;long tm=PositionGetInteger(POSITION_TIME_MSC);if(tm>stamp||(tm==stamp&&t>newest)){stamp=tm;newest=t;}}
 if(b.dd>0)for(int i=0;i<ArraySize(states);i++)
 {
  if(states[i].dir!=b.dir||states[i].ticket==newest||!Our(states[i].ticket))continue;
  if(TicketNet(i)>InpWorstMinProfit)if(!trade.PositionClose(states[i].ticket)||!Done())Print("Older close rejected: ",trade.ResultRetcodeDescription());
 }
 for(int i=0;i<ArraySize(states);i++)if(states[i].dir==b.dir)ManageTicket(i);
 if(Count(b.dir)==0||b.dd>=InpMaxDDEntries)return;
 double q=SymbolInfoDouble(_Symbol,b.dir==1?SYMBOL_BID:SYMBOL_ASK);
 if(-b.dir*(q-b.lastFill)/_Point>=InpDDStepPoints)Send(b,true);
}
int Root(){return MathMax(1,(int)MathRound(MathSqrt(InpHmaLength)));}
double WMA(MqlRates &r[],int shift,int n){double x=0,w=0;for(int j=0;j<n;j++){x+=r[shift+j].close*(n-j);w+=n-j;}return x/w;}
double HMA(MqlRates &r[],int shift)
{
 int half=MathMax(1,InpHmaLength/2),root=Root();double x=0,w=0;
 for(int j=0;j<root;j++){x+=(2*WMA(r,shift+j,half)-WMA(r,shift+j,InpHmaLength))*(root-j);w+=root-j;}return x/w;
}
bool IsRed(MqlRates &r[],int i){return r[i].close<r[i].open;}
bool IsGreen(MqlRates &r[],int i){return r[i].close>r[i].open;}
bool Bull(MqlRates &r[],int i){return r[i].close-r[i].open>r[i+1].open-r[i+1].close&&r[i+1].open>r[i+1].close;}
bool Bear(MqlRates &r[],int i){return r[i].open-r[i].close>r[i+1].close-r[i+1].open&&r[i+1].open<r[i+1].close;}
void Tag(MqlRates &c,int d,string name)
{
 if(!InpShowSignals)return;
 if(MQLInfoInteger(MQL_TESTER)&&!MQLInfoInteger(MQL_VISUAL_MODE))return;
 string key=StringFormat("PC_SIG_%d_%I64d",d,(long)c.time);
 double y=d==1?c.low:c.high;
 if(ObjectFind(0,key)<0)ObjectCreate(0,key,OBJ_TEXT,0,c.time,y);
 ObjectSetString(0,key,OBJPROP_TEXT,StringFormat("%s %s (%s)",d==1?"BUY":"SELL",name,DoubleToString(c.close,_Digits)));
 ObjectSetInteger(0,key,OBJPROP_COLOR,d==1?InpBuyColor:InpSellColor);
 ObjectSetInteger(0,key,OBJPROP_ANCHOR,d==1?ANCHOR_LEFT_UPPER:ANCHOR_LEFT_LOWER);
 ObjectSetInteger(0,key,OBJPROP_FONTSIZE,8);ObjectSetInteger(0,key,OBJPROP_SELECTABLE,false);
 int n=ArraySize(labels);ArrayResize(labels,n+1);labels[n]=key;
 if(ArraySize(labels)>InpRetainedLabels){ObjectDelete(0,labels[0]);for(int i=0;i<ArraySize(labels)-1;i++)labels[i]=labels[i+1];ArrayResize(labels,ArraySize(labels)-1);}
}
void Act(int d,string name,MqlRates &c)
{
 Tag(c,d,name);
 if(InpLogSignals)PrintFormat("%s %s %s close=%s",TimeToString(c.time),d==1?"BUY":"SELL",name,DoubleToString(c.close,_Digits));
 if(Count(d)>0){status=name+": directional basket already active";return;}
 bool ok=d==1?Send(buys,false):Send(sells,false);
 if(ok)status=(d==1?"BUY ":"SELL ")+name+" entered";
}
void Signals(MqlRates &r[])
{
 int k=1;double h=HMA(r,k),h10=HMA(r,k+10),diff=h10-h;
 double o=r[k].open,c=r[k].close,hi=r[k].high,lo=r[k].low;
 bool bu[8],se[10];ArrayInitialize(bu,false);ArrayInitialize(se,false);
 bu[2]=o<h&&c>h&&Bull(r,k)&&IsRed(r,k+1)&&diff>InpHmaTenBarDifference&&c-o<InpMaximumEngulfBody&&r[k+1].close<h&&r[k+1].high<c&&r[k+2].high<c;
 bu[3]=IsRed(r,k+2)&&IsGreen(r,k+1)&&IsGreen(r,k)&&o<h&&c>h&&diff>InpHmaTenBarDifference&&hi-c>InpMinimumEndWick;
 bu[4]=lo<h&&c>h&&o>h&&hi>h&&diff>InpHmaTenBarDifference&&Bull(r,k)&&hi-c>InpMinimumEndWick;
 bu[5]=lo<h&&c>h&&o>h&&hi>h&&diff>InpHmaTenBarDifference&&hi-c>InpMinimumEndWick&&h-r[k+4].close>InpFourBarDifference;
 bu[6]=IsRed(r,k+3)&&IsGreen(r,k+2)&&IsGreen(r,k+1)&&IsGreen(r,k)&&o<h&&c>h&&h-r[k+4].close>InpFourBarDifference;
 bu[7]=IsRed(r,k+2)&&IsGreen(r,k+1)&&IsGreen(r,k)&&o<h&&c>h&&h-r[k+2].close>InpBuyC7Difference;
 se[2]=o>h&&c<h&&Bear(r,k)&&IsGreen(r,k+1)&&diff<-InpHmaTenBarDifference&&o-c<InpMaximumEngulfBody&&r[k+1].close>h&&r[k+1].low<c&&r[k+2].low<c;
 se[3]=IsGreen(r,k+2)&&IsRed(r,k+1)&&IsRed(r,k)&&o>h&&c<h&&diff<-InpHmaTenBarDifference&&c-lo>InpMinimumEndWick;
 se[4]=hi>h&&c<h&&o<h&&lo<h&&diff<-InpHmaTenBarDifference&&Bear(r,k)&&c-lo>InpMinimumEndWick;
 se[5]=hi>h&&c<h&&o<h&&lo<h&&diff<-InpHmaTenBarDifference&&c-lo>InpMinimumEndWick&&r[k+4].close-h>InpFourBarDifference;
 se[6]=IsGreen(r,k+2)&&IsGreen(r,k+1)&&IsRed(r,k)&&r[k+2].open>o&&Bear(r,k)&&o>h&&c<h&&diff<-InpHmaTenBarDifference;
 se[7]=IsRed(r,k+2)&&IsRed(r,k+1)&&IsGreen(r,k)&&c<h&&hi>h&&diff<-InpHmaTenBarDifference;
 se[8]=IsRed(r,k+3)&&IsRed(r,k+2)&&IsGreen(r,k+1)&&IsRed(r,k)&&r[k+2].high>o&&Bear(r,k)&&c<h&&hi>h&&diff<-InpHmaTenBarDifference;
 se[9]=IsRed(r,k+2)&&IsGreen(r,k+1)&&IsRed(r,k)&&c<h&&hi>h&&o>h&&hi>r[k+1].high&&diff<-InpHmaTenBarDifference;
 string bn="",sn="";
 for(int j=2;j<=7;j++)if(bu[j])bn="buyC"+IntegerToString(j);
 for(int j=2;j<=9;j++)if(se[j])sn="sellC"+IntegerToString(j);
 if(bn!="")Act(1,bn,r[k]);
 if(sn!="")Act(-1,sn,r[k]);
}
void Theme()
{
 if(!InpDarkTheme)return;
 ChartSetInteger(0,CHART_MODE,CHART_CANDLES);ChartSetInteger(0,CHART_SHOW_GRID,false);
 ChartSetInteger(0,CHART_COLOR_BACKGROUND,C'14,16,22');ChartSetInteger(0,CHART_COLOR_FOREGROUND,C'176,184,196');
 ChartSetInteger(0,CHART_COLOR_CHART_UP,C'38,166,154');ChartSetInteger(0,CHART_COLOR_CANDLE_BULL,C'38,166,154');
 ChartSetInteger(0,CHART_COLOR_CHART_DOWN,C'239,83,80');ChartSetInteger(0,CHART_COLOR_CANDLE_BEAR,C'239,83,80');
}
void Seg(string name,datetime a,double x,datetime b,double y,color col)
{
 if(ObjectFind(0,name)<0)ObjectCreate(0,name,OBJ_TREND,0,a,x,b,y);else{ObjectMove(0,name,0,a,x);ObjectMove(0,name,1,b,y);}
 ObjectSetInteger(0,name,OBJPROP_COLOR,col);ObjectSetInteger(0,name,OBJPROP_WIDTH,2);ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false);ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
}
void Draw()
{
 if(MQLInfoInteger(MQL_TESTER)&&!MQLInfoInteger(MQL_VISUAL_MODE))return;
 int base=InpHmaLength+Root()+2,shown=MathMin(InpDrawBars,Bars(_Symbol,PERIOD_CURRENT)-base);
 if(shown<3)return;
 MqlRates r[];ArraySetAsSeries(r,true);if(CopyRates(_Symbol,PERIOD_CURRENT,0,shown+base,r)!=shown+base)return;
 double e[];ArraySetAsSeries(e,true);bool haveEMA=InpShowEMA&&CopyBuffer(emaHandle,0,0,shown,e)==shown;
 for(int i=1;i<shown;i++)
 {
  if(InpShowHMA){double h=HMA(r,i),h0=HMA(r,i-1);Seg("PC_H_"+IntegerToString(i),r[i].time,h,r[i-1].time,h0,r[i-1].close>=h0?InpBuyColor:InpSellColor);}
  if(haveEMA)Seg("PC_E_"+IntegerToString(i),r[i].time,e[i],r[i-1].time,e[i-1],InpEMAColor);
 }
 ChartRedraw();
}
int OnInit()
{
 if(InpHmaLength<2||InpEmaLength<2||InpLot<=0||InpSLPoints<=0||InpTPPoints<=0||InpBreakEvenPoints<0||InpBreakEvenOffsetPoints<0||InpPartialCount<1||InpPartialPercent<0||InpPartialPercent>100||InpTrailStartPoints<=0||InpTrailExtendPoints<=0||InpTrailDistancePoints<=0||InpMaxTPExtensions<0||InpDDStepPoints<=0||InpMaxDDEntries<0||InpSurvivalOffsetPoints<0||InpDrawBars<3||InpRetainedLabels<1)return INIT_PARAMETERS_INCORRECT;
 if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING){Print("Hedging account required");return INIT_FAILED;}
 if(Count(1)>0||Count(-1)>0){Print("Start flat: restart recovery unsupported");return INIT_FAILED;}
 buys.dir=1;sells.dir=-1;trade.SetExpertMagicNumber(InpMagic);trade.SetDeviationInPoints(InpSlippagePoints);trade.SetTypeFillingBySymbol(_Symbol);trade.SetAsyncMode(false);
 emaHandle=iMA(_Symbol,PERIOD_CURRENT,InpEmaLength,0,MODE_EMA,PRICE_CLOSE);if(emaHandle==INVALID_HANDLE)return INIT_FAILED;
 Theme();return INIT_SUCCEEDED;
}
void OnTick()
{
 Sync();Manage(buys);Manage(sells);Sync();
 datetime bar=iTime(_Symbol,PERIOD_CURRENT,0);
 if(bar>0&&bar!=lastBar)
 {
  int need=InpHmaLength+Root()+15;MqlRates r[];ArraySetAsSeries(r,true);
  if(CopyRates(_Symbol,PERIOD_CURRENT,0,need,r)==need)
  {
   if(lastBar!=0)Signals(r);
   lastBar=bar;Theme();Draw();
  }
  else if(TimeCurrent()-lastWarning>=60){lastWarning=TimeCurrent();Report("Waiting for HMA price history");}
 }
 Comment(StringFormat("Pine HMA Pattern EA v2.02\n%s\nBUY %d DD %d/%d | SELL %d DD %d/%d\nSurvival: %s",status,Count(1),buys.dd,InpMaxDDEntries,Count(-1),sells.dd,InpMaxDDEntries,InpEnableSurvival?(InpSurvivalMode==SURVIVAL_AVG_PRICE?"average price":"net P/L"):"off"));
}
void OnDeinit(const int reason){if(emaHandle!=INVALID_HANDLE)IndicatorRelease(emaHandle);ObjectsDeleteAll(0,"PC_");Comment("");}
