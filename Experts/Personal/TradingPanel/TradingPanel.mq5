#property strict
#property version "1.20"
#include "Log.mqh"
#include "Config.mqh"
#include "State.mqh"
#include "Closer.mqh"
#include "Rules.mqh"
#include "Orders.mqh"
#include "Manual.mqh"
#include "Panel.mqh"

input group "Order defaults"
input double InpLot=0.10;               // Lot size used when the panel value is 0 (panel values above 0 are remembered)
input double InpRiskPct=0.0;            // Risk % used to size the lot when no lot is saved (0 = use the lot above)
input int    InpSL_Points=500;          // SL points used when the panel SL is 0 (0 = no SL)
input int    InpTP_Points=1000;         // TP points used when the panel TP is 0 (0 = no TP)
input bool   InpInverse=false;          // Inverse mode: Market orders become Limit orders at the offset below
input int    InpInverseOffset=50;       // Inverse mode: Buy Limit at ask - offset, Sell Limit at bid + offset (points)
input int    InpMaxOpenTrades=10;       // Refuse new orders when this many managed positions are open
input long   InpMagic=234567;           // Magic number that identifies this EA's positions and orders
input bool   InpSounds=true;            // Reserved for order sounds (not wired yet)
input ENUM_BASE_CORNER InpPanelCorner=CORNER_LEFT_UPPER; // Chart corner where the panel is docked
input bool   InpResetPanelValues=false; // Set true for ONE attach to discard remembered panel values and use the settings

input group "Drawdown (DD) entries"
input bool   InpEnableDDEntries=false;  // Place extra pending limits against the trade when the main order is sent
input int    InpDD_OrderCount=2;        // DD entries used when the panel value is 0 (needs DD enabled above)
input bool   InpDD_AutoSpacing=true;    // Auto spacing = SL points / (count + 1); off = use fixed spacing below
input int    InpDD_Spacing=200;         // Fixed distance in points between DD limits (when auto spacing is off)
input bool   InpDD_SameSL=true;         // All DD entries share the main SL price; off = each uses its own price - SL points
input double InpMaxGroupRiskPct=3.0;    // Block the whole grid if total group risk exceeds this % of equity
input int    InpFillLockoutSec=10;      // Seconds after ANY fill (incl. DD fill) with no automatic close or SL/TP change

input group "Partial take profit"
input double InpMainPartialVol=40;      // Partial 1 closes this % of the current volume
input double InpRollingPartialVol=20;   // Partials 2..N each close this % of the current volume
input int    InpDefaultPartials=3;      // Partials used when the panel value is 0 (saved with each trade)

input group "Break-even (points only)"
input int    InpBE_Points=300;          // Move SL to break-even when profit reaches this many points (0 = BE off); also cancels the basket's remaining limits
input int    InpBE_Offset=0;            // SL is placed this many points beyond the open price (buy: above, sell: below)

input group "Worst entries (DD basket)"
input bool   InpCloseWorstWhenGreen=true; // In a DD basket with 2+ open entries, close each older entry as soon as it turns green; the latest entry keeps running
input int    InpGreenMinPts=0;            // An entry counts as green when net profit after exit cost is > 0 AND it is at least this many points in favor

input group "Trailing stop"
input bool   InpTrailEnable=false;      // Enable trailing stop (SL only tightens, never loosens)
input int    InpTrailingStart=1000;     // Trailing begins when profit reaches this many points
input int    InpTrailingStep=600;       // SL is kept this many points behind the current price

struct TMPos { ulong ticket,id; bool buy; double open,sl,tp,vol,pts,net; long msc; int pi; };
TMPos g_pos[];

ulong g_beArmed[];      // positions that already reached their BE trigger (in memory)
bool TMBEArmed(const ulong id){ for(int i=ArraySize(g_beArmed)-1;i>=0;i--) if(g_beArmed[i]==id) return true; return false; }
void TMBEArmedAdd(const ulong id){ if(TMBEArmed(id)) return; int n=ArraySize(g_beArmed); ArrayResize(g_beArmed,n+1); g_beArmed[n]=id; }

void TMBuildConfig()
  {
   g_cfg.magic=InpMagic;
   g_cfg.disableAutomation=false;
   g_cfg.exitMode=EXIT_AUTO; g_cfg.exitCostManual=0;
   g_cfg.maxOpenTrades=InpMaxOpenTrades; g_cfg.inverse=InpInverse; g_cfg.inverseOffset=InpInverseOffset;
   g_cfg.fillLockoutSec=InpFillLockoutSec;
   g_cfg.mainPartialPct=InpMainPartialVol; g_cfg.rollingPartialPct=InpRollingPartialVol; g_cfg.defaultPartials=InpDefaultPartials;
   g_cfg.bePoints=InpBE_Points; g_cfg.beOffset=InpBE_Offset;
   g_cfg.trailOn=InpTrailEnable; g_cfg.trailStart=InpTrailingStart; g_cfg.trailStep=InpTrailingStep;
   g_cfg.runnerOn=false;
   g_cfg.handlerOn=InpCloseWorstWhenGreen; g_cfg.handlerPts=InpGreenMinPts;
   g_cfg.worstSLtoBE=false; g_cfg.exemptMain=false;
   g_cfg.ddOn=InpEnableDDEntries; g_cfg.ddCount=InpDD_OrderCount; g_cfg.ddAutoSpacing=InpDD_AutoSpacing;
   g_cfg.ddSpacing=InpDD_Spacing; g_cfg.ddSameSL=InpDD_SameSL; g_cfg.maxGroupRiskPct=InpMaxGroupRiskPct;
   g_cfg.survOn=false;
  }

int OnInit()
  {
   g_initTime=TimeCurrent();
   TMBuildConfig();
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(30);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   TMLoadState();                         // GR4: never closes or resets anything
   Comment(TM_BUILD,"  |  ",_Symbol);
   PrintFormat("%s start. lot=%.2f risk%%=%.2f SL=%d TP=%d inverse=%s/%d maxTrades=%d magic=%I64d lockout=%ds",TM_BUILD,InpLot,InpRiskPct,
               InpSL_Points,InpTP_Points,InpInverse?"on":"off",InpInverseOffset,InpMaxOpenTrades,InpMagic,InpFillLockoutSec);
   PrintFormat("Partials %g/%g n=%d | BE %d+%d | Trail %s %d/%d | Worst-green %s minPts=%d",InpMainPartialVol,InpRollingPartialVol,
               InpDefaultPartials,InpBE_Points,InpBE_Offset,InpTrailEnable?"on":"off",InpTrailingStart,InpTrailingStep,
               InpCloseWorstWhenGreen?"on":"off",InpGreenMinPts);
   PrintFormat("DD %s count=%d auto=%s spacing=%d sameSL=%s maxGroupRisk=%.1f%%",InpEnableDDEntries?"on":"off",InpDD_OrderCount,
               InpDD_AutoSpacing?"on":"off",InpDD_Spacing,InpDD_SameSL?"on":"off",InpMaxGroupRiskPct);
   if(InpEnableDDEntries) PrintFormat("WARNING: DD risk = (count+1) x main = %d x main",InpDD_OrderCount+1);
   g_pReset=InpResetPanelValues;
   TMPanelCreate(InpPanelCorner,InpLot,InpRiskPct,InpSL_Points,InpTP_Points,InpDefaultPartials,InpDD_OrderCount);
   EventSetMillisecondTimer(500);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(reason!=REASON_REMOVE) TMSaveState(true);   // F3
   TMPanelDestroy(reason);
  }

// One snapshot per tick; Rules never touch the trade API
int TMSnapshot()
  {
   int n=0, total=PositionsTotal();
   ArrayResize(g_pos,total);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID), ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   for(int i=0;i<total;i++)
     {
      ulong t=PositionGetTicket(i);
      if(t==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol || PositionGetInteger(POSITION_MAGIC)!=g_cfg.magic) continue;
      TMPos p;
      p.ticket=t; p.id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      p.buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      p.open=PositionGetDouble(POSITION_PRICE_OPEN); p.sl=PositionGetDouble(POSITION_SL);
      p.tp=PositionGetDouble(POSITION_TP); p.vol=PositionGetDouble(POSITION_VOLUME);
      p.msc=PositionGetInteger(POSITION_TIME_MSC);
      p.pi=TMEnsurePlan(p.id);
      p.pts=(p.buy? bid-p.open : p.open-ask)/_Point;
      p.net=TMNetAfterExit(t);
      g_pos[n++]=p;
     }
   ArrayResize(g_pos,n);
   return n;
  }

void TMManage()
  {
   int n=TMSnapshot();
   if(n==0) return;
   if(TMFillLocked()) return;            // GR5: a fill never triggers any automatic action
   bool warm=(SecondsSince(g_initTime)>=3 && SecondsSince(g_lastFillTime)>=3);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP), minv=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID), ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   for(int i=0;i<n;i++)                  // red history (persisted)
     {
      bool green=(g_pos[i].net>0 && g_pos[i].pts>=g_cfg.handlerPts);
      if(!green && !g_plans[g_pos[i].pi].redEver){ g_plans[g_pos[i].pi].redEver=true; g_stateDirty=true; }
     }

   for(int i=0;i<n;i++)
     {
      int pi=g_pos[i].pi; ulong tk=g_pos[i].ticket; bool buy=g_pos[i].buy;
      string ids=(string)g_pos[i].id;

      // F5 break-even: independent of partials, latched once reached, cancels the basket's limits at trigger
      if(g_plans[pi].bePoints>0 && !g_plans[pi].beDone)
        {
         bool armed=TMBEArmed(g_pos[i].id);
         if(!armed && g_pos[i].pts>=g_plans[pi].bePoints)
           {
            armed=true; TMBEArmedAdd(g_pos[i].id);
            PrintFormat("BE TRIGGER ticket=%I64u pts=%.0f >= %.0f",tk,g_pos[i].pts,g_plans[pi].bePoints);
            TMCancelGroupPending(g_plans[pi].groupId,"BE reached");
           }
         if(armed)
           {
            bool better;
            double t=TMBETarget(buy,g_pos[i].open,g_pos[i].sl,g_plans[pi],MathMax(g_pos[i].pts,g_plans[pi].bePoints),_Point,_Digits,better);
            if(better)
              { g_plans[pi].beDone=true; g_stateDirty=true;
                PrintFormat("BE done (SL already better) ticket=%I64u sl=%s",tk,DoubleToString(g_pos[i].sl,_Digits)); }
            else if(t>0)
              {
               if(!TMSLValid(buy,t))
                  TMLogThrottled("BE"+ids,30,StringFormat("BE skipped (stops level) ticket=%I64u target=%s bid=%s ask=%s stops=%d",
                                 tk,DoubleToString(t,_Digits),DoubleToString(bid,_Digits),DoubleToString(ask,_Digits),TMStopsPts()));
               else if(TMAllow("BEm"+ids,1) && TMModify(tk,t,g_pos[i].tp,"BE PLAN"))
                 { g_plans[pi].beDone=true; g_stateDirty=true;
                   PrintFormat("BE ticket=%I64u old=%s new=%s",tk,DoubleToString(g_pos[i].sl,_Digits),DoubleToString(t,_Digits)); }
              }
           }
        }

      // F4 partial (plan-triggered); never moves SL, never blocks BE
      if(TMPartialDue(g_plans[pi],g_pos[i].open,g_pos[i].pts,_Point) && TMAllow("P"+ids,1))
        {
         int k=g_plans[pi].partialsTaken+1;
         double v=TMPartialVolume(g_pos[i].vol,k==1,g_plans[pi].mainPct,g_plans[pi].rollingPct,step,minv);
         if(v<=0)
           { PrintFormat("PARTIAL skipped (volume) ticket=%I64u level=%d net=%.2f",tk,k,g_pos[i].net);
             g_plans[pi].partialsTaken=k; g_stateDirty=true; }
         else if(g_pos[i].net<=0)
            TMLogThrottled("PN"+ids,10,StringFormat("PARTIAL skipped (net<=0) ticket=%I64u level=%d net=%.2f",tk,k,g_pos[i].net));
         else if(TMGateClose(tk,"PARTIAL PLAN "+(string)k,v))
           { g_plans[pi].partialsTaken=k; g_stateDirty=true; TMSaveState(true); }
        }

      if(!warm) continue;

      // F10 trailing
      if(g_cfg.trailOn)
        {
         double px=buy?bid:ask;
         double tt=TMTrailTarget(buy,px,g_pos[i].sl,g_pos[i].pts,g_cfg.trailStart,g_cfg.trailStep,_Point,_Digits);
         if(tt>0 && TMSLValid(buy,tt) && TMAllow("TR"+ids,1)) TMModify(tk,tt,g_pos[i].tp,"TRAIL");
        }
     }

   // Worst entries: in a DD basket close every older entry once green, keep the latest running
   if(g_cfg.handlerOn && warm)
      for(int i=0;i<n;i++)
        {
         int pi=g_pos[i].pi; long gid=g_plans[pi].groupId;
         if(gid==0) continue;
         int cnt=0, latest=-1;
         for(int j=0;j<n;j++)
           {
            if(g_plans[g_pos[j].pi].groupId!=gid) continue;
            cnt++;
            if(latest<0 || g_pos[j].msc>g_pos[latest].msc) latest=j;
           }
         if(cnt<2 || i==latest) continue;
         bool green=(g_pos[i].net>0 && g_pos[i].pts>=g_cfg.handlerPts);
         if(green && g_plans[pi].redEver)
           { if(TMAllow("WC"+(string)g_pos[i].id,1)) TMGateClose(g_pos[i].ticket,"WORST GREEN"); }
         else
            TMLogThrottled("HOLD"+(string)g_pos[i].id,30,
               StringFormat("HOLD ticket=%I64u reason=older entry not green pts=%.0f net=%.2f",g_pos[i].ticket,g_pos[i].pts,g_pos[i].net));
        }
  }

// Remove plans for finished positions; cancel orphaned DD limits; save state
void TMHousekeeping()
  {
   for(int i=ArraySize(g_beArmed)-1;i>=0;i--)
      if(!PositionSelectByTicket(g_beArmed[i]))
        { int last=ArraySize(g_beArmed)-1; g_beArmed[i]=g_beArmed[last]; ArrayResize(g_beArmed,last); }

   for(int i=ArraySize(g_plans)-1;i>=0;i--)
     {
      if(SecondsSince(g_plans[i].created)<10) continue;
      ulong id=g_plans[i].posId;
      if(PositionSelectByTicket(id) || OrderSelect(id)) continue;
      TMRemovePlan(id);
     }
   ulong pend[];
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong o=OrderGetTicket(i);
      if(o==0 || OrderGetString(ORDER_SYMBOL)!=_Symbol || OrderGetInteger(ORDER_MAGIC)!=g_cfg.magic) continue;
      int k=ArraySize(pend); ArrayResize(pend,k+1); pend[k]=o;
     }
   for(int i=0;i<ArraySize(pend);i++)
     {
      int pi=TMFindPlan(pend[i]);
      if(pi<0 || g_plans[pi].isMain || g_plans[pi].groupId==0 || SecondsSince(g_plans[pi].created)<10) continue;
      long gid=g_plans[pi].groupId; bool alive=false;
      if(TMGroupBEDone(gid)) { TMCancelPending(pend[i],"BE already done in group"); continue; }
      for(int j=0;j<ArraySize(g_plans) && !alive;j++)
        {
         if(g_plans[j].groupId!=gid || g_plans[j].posId==pend[i]) continue;
         if(g_plans[j].lastFill!=0 ? PositionSelectByTicket(g_plans[j].posId) : (g_plans[j].isMain && OrderSelect(g_plans[j].posId)))
            alive=true;
        }
      if(!alive) TMCancelPending(pend[i],"group has no open entries");
     }
   if(TMAllow("save",1)) TMSaveState();
  }

void OnTick(){ TMManage(); }

void OnTimer()
  {
   if(TMAllow("hk",1)) TMHousekeeping();
   TMPanelVizTick();
   TMPanelRefresh();
  }

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  { TMPanelEvent(id,lparam,dparam,sparam); }

// Deal audit: every fill and exit with reason, magic and comment (identifies who closed a position)
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
  {
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD || trans.deal==0 || !HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=_Symbol) return;
   long entry=HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   if(entry!=DEAL_ENTRY_IN && entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY && entry!=DEAL_ENTRY_INOUT) return;
   PrintFormat("DEAL AUDIT %s deal=%I64u pos=%I64d magic=%I64d reason=%s vol=%.2f price=%s profit=%.2f comment='%s'",
               entry==DEAL_ENTRY_IN?"IN":"OUT",trans.deal,
               HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID),HistoryDealGetInteger(trans.deal,DEAL_MAGIC),
               EnumToString((ENUM_DEAL_REASON)HistoryDealGetInteger(trans.deal,DEAL_REASON)),
               HistoryDealGetDouble(trans.deal,DEAL_VOLUME),
               DoubleToString(HistoryDealGetDouble(trans.deal,DEAL_PRICE),_Digits),
               HistoryDealGetDouble(trans.deal,DEAL_PROFIT),HistoryDealGetString(trans.deal,DEAL_COMMENT));
  }