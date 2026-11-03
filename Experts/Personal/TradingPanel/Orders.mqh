#ifndef TM_ORDERS_MQH
#define TM_ORDERS_MQH
#include "Closer.mqh"
#include "Rules.mqh"

struct TMOrderReq
  { bool isBuy; bool isLimit; double lot; double riskPct; double slPts; double tpPts; double limitPrice; int partials; int ddCount; };


double TMTickSize(){ double t=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE); return t>0?t:_Point; }
double TMNormPrice(const double p){ double t=TMTickSize(); return NormalizeDouble(MathRound(p/t)*t,_Digits); }
double TMMoneyPerLotPerPoint(){ return SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE)*(_Point/TMTickSize()); }

double TMNormVol(double v)
  {
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN), mx=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   v=TMFloorToStep(v,step);
   return NormalizeDouble(MathMin(mx,MathMax(mn,v)),8);
  }
double TMLotFromRisk(const double riskPct,const double slPts)
  {
   double per=slPts*TMMoneyPerLotPerPoint();
   if(per<=0) return 0;
   return TMNormVol(AccountInfoDouble(ACCOUNT_EQUITY)*riskPct/100.0/per);
  }
double TMRiskPctFromLot(const double lot,const double slPts)
  {
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   return eq>0 ? lot*slPts*TMMoneyPerLotPerPoint()/eq*100.0 : 0;
  }
// F6: sum of lot x SL distance in money over main + DD entries
double TMGroupRiskMoney(const double lot,const double slPts,const int ddCount)
  { return (ddCount+1)*lot*slPts*TMMoneyPerLotPerPoint(); }

int TMStopsPts()
  { return (int)MathMax(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL)); }
bool TMSLValid(const bool isBuy,const double sl)
  {
   double m=TMStopsPts()*_Point;
   return isBuy ? sl<=SymbolInfoDouble(_Symbol,SYMBOL_BID)-m : sl>=SymbolInfoDouble(_Symbol,SYMBOL_ASK)+m;
  }
double TMClampTP(const bool isBuy,const double tp)
  {
   double m=TMStopsPts()*_Point;
   if(isBuy) return NormalizeDouble(MathMax(tp,SymbolInfoDouble(_Symbol,SYMBOL_ASK)+m),_Digits);
   return NormalizeDouble(MathMin(tp,SymbolInfoDouble(_Symbol,SYMBOL_BID)-m),_Digits);
  }

int TMCountManaged()
  {
   int c=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong t=PositionGetTicket(i);
      if(t==0) continue;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol && PositionGetInteger(POSITION_MAGIC)==g_cfg.magic) c++;
     }
   return c;
  }

long TMNewGroupId(){ static long seq=0; seq++; return (long)TimeCurrent()*1000+(seq%1000); }

// ---------- plans (F2) ----------
void TMPrecreatePlan(const ulong posId,const long gid,const bool isMain,const double tp,const double vol,const int partials)
  {
   TMPlan p; ZeroMemory(p);
   p.posId=posId; p.groupId=gid; p.isMain=isMain; p.origTP=tp; p.origVolume=vol;
   p.partialCount=partials; p.mainPct=g_cfg.mainPartialPct; p.rollingPct=g_cfg.rollingPartialPct;
   p.bePoints=g_cfg.bePoints; p.beOffset=g_cfg.beOffset; p.created=TimeCurrent();
   TMAddPlan(p);
  }

double TMEntryCommission(const ulong posId,double &entryVol)
  {
   double c=0; entryVol=0;
   if(!HistorySelectByPosition(posId)) return 0;
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
     {
      ulong d=HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(d,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;
      c+=HistoryDealGetDouble(d,DEAL_COMMISSION);
      entryVol+=HistoryDealGetDouble(d,DEAL_VOLUME);
     }
   return c;
  }

// Call with the position selected. Creates the plan on first sight, registers the fill once.
int TMEnsurePlan(const ulong posId)
  {
   int i=TMFindPlan(posId);
   if(i<0)
     {
      TMPlan p; ZeroMemory(p);
      p.posId=posId; p.origTP=PositionGetDouble(POSITION_TP); p.origVolume=PositionGetDouble(POSITION_VOLUME);
      p.partialCount=g_cfg.defaultPartials; p.mainPct=g_cfg.mainPartialPct; p.rollingPct=g_cfg.rollingPartialPct;
      p.bePoints=g_cfg.bePoints; p.beOffset=g_cfg.beOffset; p.isMain=true; p.created=TimeCurrent();
      string parts[];
      if(StringSplit(PositionGetString(POSITION_COMMENT),'|',parts)==3 && parts[0]=="TM3")   // fallback only
        { p.groupId=(long)StringToInteger(parts[1]); p.isMain=(parts[2]=="M"); }
      i=TMAddPlan(p);
     }
   if(g_plans[i].lastFill==0)
     {
      double ev; double c=TMEntryCommission(posId,ev);
      g_plans[i].entryCommission=c;
      if(ev>0) g_plans[i].origVolume=MathMax(g_plans[i].origVolume,ev);
      g_plans[i].lastFill=(datetime)PositionGetInteger(POSITION_TIME);
      if(!g_plans[i].isMain && g_plans[i].groupId!=0)
        {
         int g=TMGroupGet(g_plans[i].groupId);
         g_groups[g].ddFills++;
         PrintFormat("DD FILL ticket=%I64u group=%I64d fills=%d",posId,g_plans[i].groupId,g_groups[g].ddFills);
        }
      datetime ft=g_plans[i].lastFill;                 // real fill time of the position
      if(ft>g_lastFillTime && SecondsSince(ft)<60) g_lastFillTime=ft;
      g_stateDirty=true;
     }
   return i;
  }

bool TMCancelPending(const ulong ticket,const string reason)
  {
   bool ok=g_trade.OrderDelete(ticket);
   if(ok) PrintFormat("CANCEL PENDING ticket=%I64u reason=%s",ticket,reason);
   return ok;
  }
// Cancels every pending order of one group (this symbol + magic). Collect first, then delete.
int TMCancelGroupPending(const long gid,const string reason)
  {
   if(gid==0) return 0;
   ulong ord[];
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong o=OrderGetTicket(i);
      if(o==0 || OrderGetString(ORDER_SYMBOL)!=_Symbol || OrderGetInteger(ORDER_MAGIC)!=g_cfg.magic) continue;
      int pi=TMFindPlan(o);
      if(pi<0 || g_plans[pi].groupId!=gid) continue;
      int k=ArraySize(ord); ArrayResize(ord,k+1); ord[k]=o;
     }
   int done=0;
   for(int i=0;i<ArraySize(ord);i++) if(TMCancelPending(ord[i],reason)) done++;
   return done;
  }

bool TMGroupBEDone(const long gid)
  {
   for(int i=ArraySize(g_plans)-1;i>=0;i--)
      if(g_plans[i].groupId==gid && g_plans[i].beDone) return true;
   return false;
  }

// ---------- order entry (F1, F6) ----------
bool TMSendOrder(TMOrderReq &r)
  {
   if(TMCountManaged()>=g_cfg.maxOpenTrades)
     { Alert("Order refused: managed positions >= max open trades (",g_cfg.maxOpenTrades,")"); return false; }

   int ddc=(r.ddCount>0) ? r.ddCount : g_cfg.ddCount;     // panel value if set, otherwise the setting
   bool dd=g_cfg.ddOn && ddc>0;
   if(dd && (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     { Alert("DD entries refused: account is not hedging"); return false; }

   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK), bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   bool isLimit=r.isLimit; double lp=r.limitPrice;
   if(g_cfg.inverse && !isLimit)
     { isLimit=true; lp=r.isBuy ? ask-g_cfg.inverseOffset*_Point : bid+g_cfg.inverseOffset*_Point; }
   double price=isLimit ? TMNormPrice(lp) : (r.isBuy?ask:bid);
   if(isLimit && ((r.isBuy && price>=ask) || (!r.isBuy && price<=bid)))
     { Alert("Limit price on wrong side of market"); return false; }

   double lot=(r.riskPct>0 && r.slPts>0) ? TMLotFromRisk(r.riskPct,r.slPts) : TMNormVol(r.lot);
   if(lot<=0){ Alert("Invalid lot"); return false; }

   double risk=dd ? TMGroupRiskMoney(lot,r.slPts,ddc) : lot*r.slPts*TMMoneyPerLotPerPoint();
   double limitMoney=AccountInfoDouble(ACCOUNT_EQUITY)*g_cfg.maxGroupRiskPct/100.0;
   if(dd && risk>limitMoney)
     { Alert(StringFormat("Group risk %.2f exceeds limit %.2f (%.1f%% of equity). Nothing sent.",risk,limitMoney,g_cfg.maxGroupRiskPct)); return false; }
   PrintFormat("Order check: lot=%.2f total risk=%.2f%s",lot,risk,dd?StringFormat(" (DD risk = %d x main)",ddc+1):"");

   double sl=r.slPts>0 ? TMNormPrice(r.isBuy?price-r.slPts*_Point:price+r.slPts*_Point) : 0;
   double tp=r.tpPts>0 ? TMNormPrice(r.isBuy?price+r.tpPts*_Point:price-r.tpPts*_Point) : 0;
   long gid=TMNewGroupId();
   string cm="TM3|"+(string)gid+"|M";

   bool ok;
   if(!isLimit) ok=r.isBuy ? g_trade.Buy(lot,_Symbol,0,sl,tp,cm) : g_trade.Sell(lot,_Symbol,0,sl,tp,cm);
   else         ok=r.isBuy ? g_trade.BuyLimit(lot,price,_Symbol,sl,tp,ORDER_TIME_GTC,0,cm)
                           : g_trade.SellLimit(lot,price,_Symbol,sl,tp,ORDER_TIME_GTC,0,cm);
   if(!ok)
     { PrintFormat("Main order failed rc=%u %s",g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription()); return false; }

   ulong posId=g_trade.ResultOrder();
   if(!isLimit)
     { ulong d=g_trade.ResultDeal(); if(d>0 && HistoryDealSelect(d)) posId=(ulong)HistoryDealGetInteger(d,DEAL_POSITION_ID); }
   TMPrecreatePlan(posId,dd?gid:0,true,tp,lot,r.partials);

   if(dd)
     {
      double sp=g_cfg.ddAutoSpacing ? TMAutoSpacingPts(r.slPts,ddc,_Point,TMTickSize()) : g_cfg.ddSpacing;
      string dcm="TM3|"+(string)gid+"|D";
      for(int k=1;k<=ddc;k++)
        {
         double dp=TMNormPrice(r.isBuy ? price-k*sp*_Point : price+k*sp*_Point);
         double dsl=0;
         if(r.slPts>0) dsl=g_cfg.ddSameSL ? sl : TMNormPrice(r.isBuy?dp-r.slPts*_Point:dp+r.slPts*_Point);
         double dtp=r.tpPts>0 ? TMNormPrice(r.isBuy?dp+r.tpPts*_Point:dp-r.tpPts*_Point) : 0;
         bool dok=r.isBuy ? g_trade.BuyLimit(lot,dp,_Symbol,dsl,dtp,ORDER_TIME_GTC,0,dcm)
                          : g_trade.SellLimit(lot,dp,_Symbol,dsl,dtp,ORDER_TIME_GTC,0,dcm);
         if(dok) { TMPrecreatePlan(g_trade.ResultOrder(),gid,false,dtp,lot,r.partials);
                   PrintFormat("DD LIMIT #%d price=%s sl=%s tp=%s lot=%.2f",k,DoubleToString(dp,_Digits),DoubleToString(dsl,_Digits),DoubleToString(dtp,_Digits),lot); }
         else PrintFormat("DD limit #%d failed rc=%u %s",k,g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription());
        }
     }
   TMSaveState(true);
   return true;
  }

// Panel "Partials" edit: update the count on every open position / pending order of this EA.
// partialsTaken is never touched, so taken partials are not repeated.
int TMApplyPartialCount(const int n)
  {
   int changed=0;
   for(int i=ArraySize(g_plans)-1;i>=0;i--)
     {
      ulong id=g_plans[i].posId;
      bool ours=false;
      if(PositionSelectByTicket(id))
         ours=(PositionGetString(POSITION_SYMBOL)==_Symbol && PositionGetInteger(POSITION_MAGIC)==g_cfg.magic);
      else if(OrderSelect(id))
         ours=(OrderGetString(ORDER_SYMBOL)==_Symbol && OrderGetInteger(ORDER_MAGIC)==g_cfg.magic);
      if(!ours || g_plans[i].partialCount==n) continue;
      g_plans[i].partialCount=n;
      changed++;
     }
   if(changed>0)
     {
      g_stateDirty=true; TMSaveState(true);
      PrintFormat("PARTIAL COUNT set to %d on %d plan(s), taken partials kept",n,changed);
     }
   return changed;
  }
#endif