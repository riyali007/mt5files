#ifndef TM_CLOSER_MQH
#define TM_CLOSER_MQH
#include <Trade/Trade.mqh>
#include "Log.mqh"
#include "Config.mqh"
#include "State.mqh"

CTrade g_trade;

bool TMFillLocked()
  { return g_lastFillTime>0 && SecondsSince(g_lastFillTime)<g_cfg.fillLockoutSec; }
// Net after estimated exit cost. Commission comes from the plan (deal commission at entry).
double TMNetAfterExit(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket)) return -DBL_MAX;
   double vol=PositionGetDouble(POSITION_VOLUME);
   double net=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
   int i=TMFindPlan((ulong)PositionGetInteger(POSITION_IDENTIFIER));
   double comm=0;
   if(i>=0 && g_plans[i].origVolume>0)
      comm=g_plans[i].entryCommission*MathMin(1.0,vol/g_plans[i].origVolume);   // negative
   net+=comm;
   switch(g_cfg.exitMode)
     {
      case EXIT_AUTO:   net+=comm; break;                      // mirror entry cost
      case EXIT_MANUAL: net-=MathAbs(g_cfg.exitCostManual)*vol; break;
      default: break;
     }
   return net;
  }

// GR1/GR2/F8: the only automatic close path. volume<=0 closes fully.
bool TMGateClose(const ulong ticket,const string reason,const double volume=0.0)
  {
   if(g_cfg.disableAutomation){ TMLogThrottled("DA"+(string)ticket,60,"HOLD automation disabled ticket="+(string)ticket); return false; }
    if(TMFillLocked()){ TMLogThrottled("FL"+(string)ticket,5,StringFormat("HOLD fill lockout ticket=%I64u reason=%s",ticket,reason)); return false; }
   if(SecondsSince(g_initTime)<3 && StringFind(reason,"PLAN")<0) return false;   // GR7
   double net=TMNetAfterExit(ticket);
   if(net<=0.0)
     {
      TMLogThrottled("BL"+(string)ticket+reason,1,
         StringFormat("BLOCKED auto close ticket=%I64u reason=%s net=%.2f",ticket,reason,net));
      return false;
     }
   bool ok=(volume>0.0)? g_trade.PositionClosePartial(ticket,volume) : g_trade.PositionClose(ticket);
   if(ok) TMLog(volume>0.0?"PARTIAL":"AUTO CLOSE",ticket,reason,net);
   else   PrintFormat("Close failed ticket=%I64u rc=%u %s",ticket,g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription());
   return ok;
  }

// F9 group close (not wired yet)
int TMGateGroupClose(const ulong &tickets[],const bool allowRed,const string reason)
  {
   double total=0; int n=ArraySize(tickets);
   for(int i=0;i<n;i++) total+=TMNetAfterExit(tickets[i]);
   if(total<g_cfg.survMinProfit) return 0;
   int closed=0;
   for(int i=0;i<n;i++)
     {
      double net=TMNetAfterExit(tickets[i]);
      if(net>0.0){ if(TMGateClose(tickets[i],reason)) closed++; }
      else if(allowRed)
        {
         if(g_trade.PositionClose(tickets[i])) { closed++; TMLog("AUTO CLOSE",tickets[i],"group, red ticket",net); }
        }
      else TMLogThrottled("BLG"+(string)tickets[i],1,StringFormat("BLOCKED auto close ticket=%I64u reason=%s net=%.2f",tickets[i],reason,net));
     }
   return closed;
  }

// Manual paths bypass the gate
bool TMManualClose(const ulong ticket){ return g_trade.PositionClose(ticket); }
bool TMManualPartial(const ulong ticket,const double vol){ return g_trade.PositionClosePartial(ticket,vol); }

// Modifier for automatic SL/TP changes
bool TMModify(const ulong ticket,const double sl,const double tp,const string reason)
  {
   if(g_cfg.disableAutomation) return false;
   if(TMFillLocked()) return false;
   if(SecondsSince(g_initTime)<3 && StringFind(reason,"PLAN")<0) return false;   // GR7
   bool ok=g_trade.PositionModify(ticket,sl,tp);
   if(ok) TMLog("MODIFY",ticket,reason,TMNetAfterExit(ticket));
   return ok;
  }
#endif