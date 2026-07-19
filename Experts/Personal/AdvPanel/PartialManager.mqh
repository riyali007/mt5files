//+------------------------------------------------------------------+
//|                                            PartialManager.mqh    |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include "Defines.mqh"

class CPartialManager
  {
private:
   CTrade            m_trade;
   CPositionInfo     m_position;
   
   // Storage for settings
   double            m_dist_pct[5];
   int               m_dist_pnt[5];
   double            m_vol[5];
   
   int               m_sl_trigger_idx;   
   int               m_trail_trigger_idx;
   int               m_trail_dist;
   int               m_trail_step;

   SPartialRequest   m_activePartials[]; 

   // --- UTILITIES ---
   void CreateLine(string name, double price, color clr, string label) {
      if(ObjectFind(0, name) < 0) {
         ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
         ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
         ObjectSetInteger(0, name, OBJPROP_ZORDER, 0); 
      }
      ObjectSetString(0, name, OBJPROP_TEXT, label);
      ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   }

   void RemoveLine(string name) { ObjectDelete(0, name); }
   
   void DrawSLLabel(ulong ticket, double sl_price, double profit, color clr) {
      string name = "AP_SL_" + (string)ticket;
      if(sl_price <= 0) { ObjectDelete(0, name); return; }
      if(ObjectFind(0, name) < 0) {
         ObjectCreate(0, name, OBJ_TEXT, 0, 0, 0); 
         ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
         ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
         ObjectSetInteger(0, name, OBJPROP_ZORDER, 0); 
      }
      datetime time = iTime(_Symbol, PERIOD_CURRENT, 0);
      ObjectSetString(0, name, OBJPROP_TEXT, "SL P/L: $" + DoubleToString(profit, 2));
      ObjectSetDouble(0, name, OBJPROP_PRICE, sl_price);
      ObjectSetInteger(0, name, OBJPROP_TIME, time);
   }
   
   void RemoveSLLabel(ulong ticket) { ObjectDelete(0, "AP_SL_" + (string)ticket); }

   bool IsPartialDone(ulong ticket, int partial_id) {
      string gv_name = "PM_" + (string)ticket + "_P" + (string)partial_id;
      return GlobalVariableCheck(gv_name);
   }

   void MarkPartialDone(ulong ticket, int partial_id) {
      string gv_name = "PM_" + (string)ticket + "_P" + (string)partial_id;
      GlobalVariableSet(gv_name, 1.0); 
   }

   void ClearTradeMemory(ulong ticket) {
      for(int i=1; i<=5; i++) {
         string gv_name = "PM_" + (string)ticket + "_P" + (string)i;
         if(GlobalVariableCheck(gv_name)) GlobalVariableDel(gv_name);
      }
   }

public:
   CPartialManager(double p1pct, double p2pct, double p3pct, double p4pct, double p5pct,
                   int p1pnt, int p2pnt, int p3pnt, int p4pnt, int p5pnt,
                   double p1v, double p2v, double p3v, double p4v, double p5v,
                   int slAt, int trailAt, int trailDist, int trailStep)
     {
      m_dist_pct[0]=p1pct; m_dist_pct[1]=p2pct; m_dist_pct[2]=p3pct; m_dist_pct[3]=p4pct; m_dist_pct[4]=p5pct;
      m_dist_pnt[0]=p1pnt; m_dist_pnt[1]=p2pnt; m_dist_pnt[2]=p3pnt; m_dist_pnt[3]=p4pnt; m_dist_pnt[4]=p5pnt;
      m_vol[0]=p1v; m_vol[1]=p2v; m_vol[2]=p3v; m_vol[3]=p4v; m_vol[4]=p5v;
      m_sl_trigger_idx = slAt; m_trail_trigger_idx = trailAt; m_trail_dist = trailDist; m_trail_step = trailStep;
     }

   void OnTickLogic(int defaultSL, int defaultTP, ENUM_PARTIAL_MODE mode) {
      SyncOpenPositions(defaultSL, defaultTP, mode);
      CheckExecution();
      if(m_trail_trigger_idx > 0) ManageTrailingStop();
      ManageSLLabels();
   }

   void SyncOpenPositions(int defaultSL, int defaultTP, ENUM_PARTIAL_MODE mode) {
      for(int i=ArraySize(m_activePartials)-1; i>=0; i--) {
         if(!m_position.SelectByTicket(m_activePartials[i].transactionId)) {
            RemoveLine(m_activePartials[i].partialLineId);
            RemoveSLLabel(m_activePartials[i].transactionId); 
            ClearTradeMemory(m_activePartials[i].transactionId);
            ArrayRemove(m_activePartials, i, 1);
         }
      }
      for(int i=PositionsTotal()-1; i>=0; i--) {
         if(m_position.SelectByIndex(i)) {
            ulong ticket = m_position.Ticket();
            CheckAndApplySLTP(ticket, defaultSL, defaultTP); 
            bool isRegistered = false;
            for(int j=0; j<ArraySize(m_activePartials); j++)
               if(m_activePartials[j].transactionId == ticket) { isRegistered = true; break; }
            if(!isRegistered) RegisterNewTrade(ticket, mode);
         }
      }
   }

   void RegisterNewTrade(ulong ticket, ENUM_PARTIAL_MODE mode) {
      if(!m_position.SelectByTicket(ticket)) return;
      double openPrice = m_position.PriceOpen();
      double point     = SymbolInfoDouble(m_position.Symbol(), SYMBOL_POINT);
      int    digits    = (int)SymbolInfoInteger(m_position.Symbol(), SYMBOL_DIGITS);
      int    dir       = (m_position.PositionType() == POSITION_TYPE_BUY) ? 1 : -1;
      color  clr       = (dir == 1) ? COLOR_BUY_PARTIAL : COLOR_SELL_PARTIAL;

      for(int j=0; j<5; j++) {
         if(m_vol[j] <= 0) continue;
         if(IsPartialDone(ticket, j+1)) continue; 

         double targetPrice = 0;
         if(mode == MODE_POINTS) {
            if(m_dist_pnt[j] <= 0) continue; 
            targetPrice = openPrice + (m_dist_pnt[j] * point * dir);
         } else {
            double tpDist = MathAbs(m_position.TakeProfit() - openPrice);
            if(tpDist <= 0 || m_dist_pct[j] <= 0) continue;
            targetPrice = openPrice + ((tpDist * (m_dist_pct[j]/100.0)) * dir);
         }

         SPartialRequest req;
         req.transactionId = ticket;
         req.partialId     = j + 1;
         req.partialLineId = PREFIX_LINE + (string)ticket + "_" + (string)(j+1);
         req.partialPrice  = targetPrice;
         req.partialVolPct = m_vol[j];
         req.isTaken       = false;
         req.type          = m_position.PositionType();

         string label = StringFormat("P%d #%d @ %.*f", req.partialId, ticket, digits, targetPrice);
         CreateLine(req.partialLineId, targetPrice, clr, label);

         int s = ArraySize(m_activePartials);
         ArrayResize(m_activePartials, s + 1);
         m_activePartials[s] = req;
      }
   }

   void CheckExecution() {
      for(int i=0; i<ArraySize(m_activePartials); i++) {
         if(m_activePartials[i].isTaken) continue;
         if(!m_position.SelectByTicket(m_activePartials[i].transactionId)) continue;
         
         double currentPrice = (m_activePartials[i].type == POSITION_TYPE_BUY) ? 
                               SymbolInfoDouble(m_position.Symbol(), SYMBOL_BID) : 
                               SymbolInfoDouble(m_position.Symbol(), SYMBOL_ASK);
         bool trigger = false;
         if(m_activePartials[i].type == POSITION_TYPE_BUY  && currentPrice >= m_activePartials[i].partialPrice) trigger = true;
         if(m_activePartials[i].type == POSITION_TYPE_SELL && currentPrice <= m_activePartials[i].partialPrice) trigger = true;
         if(trigger) ExecutePartialClose(i);
      }
   }

   void ExecutePartialClose(int index) {
      ulong ticket = m_activePartials[index].transactionId;
      int   pId    = m_activePartials[index].partialId;
      if(m_position.SelectByTicket(ticket)) {
         double closeVol = m_position.Volume() * (m_activePartials[index].partialVolPct / 100.0);
         double step = SymbolInfoDouble(m_position.Symbol(), SYMBOL_VOLUME_STEP);
         double min  = SymbolInfoDouble(m_position.Symbol(), SYMBOL_VOLUME_MIN);
         closeVol = MathFloor(closeVol/step) * step;
         if(closeVol < min) closeVol = min;
         if(m_trade.PositionClosePartial(ticket, closeVol)) {
            Print("Partial ", pId, " DONE.");
            m_activePartials[index].isTaken = true;
            MarkPartialDone(ticket, pId);
            RemoveLine(m_activePartials[index].partialLineId);
            if(m_sl_trigger_idx > 0 && pId >= m_sl_trigger_idx) MoveSLToEntry(ticket);
         }
      }
   }

   void MoveSLToEntry(ulong ticket) {
      if(!m_position.SelectByTicket(ticket)) return;
      double openPrice = m_position.PriceOpen();
      double currentSL = m_position.StopLoss();
      double currentTP = m_position.TakeProfit();
      bool shouldModify = false;
      if(m_position.PositionType() == POSITION_TYPE_BUY) { if(currentSL < openPrice) shouldModify = true; }
      else { if(currentSL > openPrice || currentSL == 0) shouldModify = true; }
      if(shouldModify) m_trade.PositionModify(ticket, openPrice, currentTP);
   }

   void ManageTrailingStop() {
      for(int i=PositionsTotal()-1; i>=0; i--) {
         if(m_position.SelectByIndex(i)) {
            ulong t = m_position.Ticket();
            if(IsPartialDone(t, m_trail_trigger_idx)) ApplyTrailing(t);
         }
      }
   }
     
   void ManageSLLabels() {
      for(int i=PositionsTotal()-1; i>=0; i--) {
         if(m_position.SelectByIndex(i)) {
            ulong ticket = m_position.Ticket();
            double sl = m_position.StopLoss();
            if(sl > 0) {
               double openPrice = m_position.PriceOpen();
               double profit = 0;
               if(OrderCalcProfit((ENUM_ORDER_TYPE)m_position.PositionType(), m_position.Symbol(), m_position.Volume(), openPrice, sl, profit)) {
                  color c = (profit >= 0) ? clrLime : clrRed;
                  DrawSLLabel(ticket, sl, profit, c);
               }
            }
         }
      }
   }

   void ApplyTrailing(ulong ticket) {
      if(!m_position.SelectByTicket(ticket)) return;
      double point = SymbolInfoDouble(m_position.Symbol(), SYMBOL_POINT);
      double sl    = m_position.StopLoss();
      double tp    = m_position.TakeProfit();
      double bid   = SymbolInfoDouble(m_position.Symbol(), SYMBOL_BID);
      double ask   = SymbolInfoDouble(m_position.Symbol(), SYMBOL_ASK);
      double dist  = m_trail_dist * point;
      double step  = m_trail_step * point;
      if(m_position.PositionType() == POSITION_TYPE_BUY) {
         double newSL = bid - dist;
         if(newSL > sl + step) m_trade.PositionModify(ticket, newSL, tp);
      } else {
         double newSL = ask + dist;
         if(newSL < sl - step || sl == 0) m_trade.PositionModify(ticket, newSL, tp);
      }
   }

   void CheckAndApplySLTP(ulong ticket, int sl_points, int tp_points) {
        if(!m_position.SelectByTicket(ticket)) return;
        double sl = m_position.StopLoss();
        double tp = m_position.TakeProfit();
        if(sl!=0 && tp!=0) return;
        double pt = SymbolInfoDouble(m_position.Symbol(), SYMBOL_POINT);
        double open = m_position.PriceOpen();
        double nSL=sl, nTP=tp;
        if(m_position.PositionType()==POSITION_TYPE_BUY) {
           if(sl==0) nSL = open - sl_points*pt;
           if(tp==0) nTP = open + tp_points*pt;
        } else {
           if(sl==0) nSL = open + sl_points*pt;
           if(tp==0) nTP = open - tp_points*pt;
        }
        m_trade.PositionModify(ticket, nSL, nTP);
   }
     
   string GetPartialStatus(ulong ticket, int partial_index_1to5) {
      if(IsPartialDone(ticket, partial_index_1to5)) return "DONE";

      for(int i=0; i<ArraySize(m_activePartials); i++) {
         if(m_activePartials[i].transactionId == ticket && m_activePartials[i].partialId == partial_index_1to5) {
            
            // --- NEW: CALCULATE ESTIMATED PROFIT IN DOLLARS ---
            double partialVol = 0;
            if(m_position.SelectByTicket(ticket)) {
                double currentVol = m_position.Volume();
                partialVol = currentVol * (m_activePartials[i].partialVolPct / 100.0);
            }
            
            double profit = 0;
            double open = m_position.PriceOpen();
            double target = m_activePartials[i].partialPrice;
            OrderCalcProfit((ENUM_ORDER_TYPE)m_activePartials[i].type, _Symbol, partialVol, open, target, profit);
            // --------------------------------------------------
            
            return DoubleToString(target, _Digits) + " ($" + DoubleToString(profit, 2) + ")";
         }
      }
      return "---";
   }
  };