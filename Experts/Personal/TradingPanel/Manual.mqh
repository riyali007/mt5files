#ifndef TM_MANUAL_MQH
#define TM_MANUAL_MQH
#include "Orders.mqh"

int TMCollectManaged(ulong &out[])
  {
   ArrayResize(out,0);
   for(int i=0;i<PositionsTotal();i++)
     {
      ulong t=PositionGetTicket(i);
      if(t==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol || PositionGetInteger(POSITION_MAGIC)!=g_cfg.magic) continue;
      int k=ArraySize(out); ArrayResize(out,k+1); out[k]=t;
     }
   return ArraySize(out);
  }

bool TMManualCloseSelected(const ulong t)
  {
   if(t==0 || !PositionSelectByTicket(t)) return false;
   double net=TMNetAfterExit(t);
   bool ok=TMManualClose(t);
   PrintFormat("MANUALLY_CLOSED ticket=%I64u net=%.2f ok=%s",t,net,ok?"yes":"no");
   return ok;
  }

bool TMManualPartialPct(const ulong t,const double pct)
  {
   if(t==0 || !PositionSelectByTicket(t)) return false;
   double vol=PositionGetDouble(POSITION_VOLUME);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP), mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double v=TMFloorToStep(vol*pct/100.0,step);
   if(v<mn || v>=vol){ Alert(StringFormat("Partial %.1f%% of %.2f gives invalid volume %.2f",pct,vol,v)); return false; }
   bool ok=TMManualPartial(t,v);
   PrintFormat("MANUAL PARTIAL ticket=%I64u vol=%.2f of %.2f ok=%s",t,v,vol,ok?"yes":"no");
   return ok;
  }

// AC8.3: managed positions (loss allowed) + this EA's pending orders (symbol + magic only)
void TMManualCloseAll()
  {
   ulong pos[]; TMCollectManaged(pos);
   for(int i=0;i<ArraySize(pos);i++) TMManualCloseSelected(pos[i]);
   ulong ord[];
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong o=OrderGetTicket(i);
      if(o==0 || OrderGetString(ORDER_SYMBOL)!=_Symbol || OrderGetInteger(ORDER_MAGIC)!=g_cfg.magic) continue;
      int k=ArraySize(ord); ArrayResize(ord,k+1); ord[k]=o;
     }
   for(int i=0;i<ArraySize(ord);i++) TMCancelPending(ord[i],"Close All");
  }

// F13: SL of every managed position -> open price of the latest position; then cancel pendings.
void TMManualBEAllLatest()
  {
   ulong pos[]; int n=TMCollectManaged(pos);
   if(n==0) return;
   long latestMsc=-1; double target=0;
   for(int i=0;i<n;i++)
     {
      PositionSelectByTicket(pos[i]);
      long ms=PositionGetInteger(POSITION_TIME_MSC);
      if(ms>latestMsc){ latestMsc=ms; target=PositionGetDouble(POSITION_PRICE_OPEN); }
     }
   target=TMNormPrice(target);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID), ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   for(int i=0;i<n;i++)
     {
      if(!PositionSelectByTicket(pos[i])) continue;
      bool buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      double oldSL=PositionGetDouble(POSITION_SL), tp=PositionGetDouble(POSITION_TP);
      if((buy && target>=bid) || (!buy && target<=ask))
        { PrintFormat("BE ALL LATEST skipped (wrong side of market) ticket=%I64u target=%s",pos[i],DoubleToString(target,_Digits)); continue; }
      if(!TMSLValid(buy,target))
        { PrintFormat("BE ALL LATEST skipped (stops level) ticket=%I64u target=%s",pos[i],DoubleToString(target,_Digits)); continue; }
      if(g_trade.PositionModify(pos[i],target,tp))
         PrintFormat("BE ALL LATEST ticket=%I64u oldSL=%s newSL=%s",pos[i],DoubleToString(oldSL,_Digits),DoubleToString(target,_Digits));
      else PrintFormat("BE ALL LATEST failed ticket=%I64u rc=%u",pos[i],g_trade.ResultRetcode());
     }
   ulong ord[];
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong o=OrderGetTicket(i);
      if(o==0 || OrderGetString(ORDER_SYMBOL)!=_Symbol || OrderGetInteger(ORDER_MAGIC)!=g_cfg.magic) continue;
      int k=ArraySize(ord); ArrayResize(ord,k+1); ord[k]=o;
     }
   for(int i=0;i<ArraySize(ord);i++) TMCancelPending(ord[i],"BE All Latest");
  }

// F13: deals for this symbol + magic, common folder
void TMExportDealsCsv()
  {
   string fn="TM3_Deals_"+_Symbol+".csv";
   int h=FileOpen(fn,FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(h==INVALID_HANDLE){ Alert("CSV export failed: ",GetLastError()); return; }
   FileWrite(h,"ticket","time","type","volume","price","SL","TP","profit","commission","swap","comment");
   int rows=0;
   if(HistorySelect(0,TimeCurrent()+86400))
      for(int i=0;i<HistoryDealsTotal();i++)
        {
         ulong d=HistoryDealGetTicket(i);
         if(d==0 || HistoryDealGetString(d,DEAL_SYMBOL)!=_Symbol || HistoryDealGetInteger(d,DEAL_MAGIC)!=g_cfg.magic) continue;
         string cm=HistoryDealGetString(d,DEAL_COMMENT); StringReplace(cm,",",";");
         FileWrite(h,(string)d,TimeToString((datetime)HistoryDealGetInteger(d,DEAL_TIME),TIME_DATE|TIME_SECONDS),
                   EnumToString((ENUM_DEAL_TYPE)HistoryDealGetInteger(d,DEAL_TYPE)),
                   DoubleToString(HistoryDealGetDouble(d,DEAL_VOLUME),2),
                   DoubleToString(HistoryDealGetDouble(d,DEAL_PRICE),_Digits),
                   DoubleToString(HistoryDealGetDouble(d,DEAL_SL),_Digits),
                   DoubleToString(HistoryDealGetDouble(d,DEAL_TP),_Digits),
                   DoubleToString(HistoryDealGetDouble(d,DEAL_PROFIT),2),
                   DoubleToString(HistoryDealGetDouble(d,DEAL_COMMISSION),2),
                   DoubleToString(HistoryDealGetDouble(d,DEAL_SWAP),2),cm);
         rows++;
        }
   FileClose(h);
   PrintFormat("CSV exported: %s (%d deals) in the common Files folder",fn,rows);
  }
#endif