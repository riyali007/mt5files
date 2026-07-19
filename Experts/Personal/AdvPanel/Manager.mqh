//+------------------------------------------------------------------+
//|                                                  Manager.mqh     |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include "Defines.mqh"

class CPartialManager
  {
private:
   CTrade            m_trade;
   CPositionInfo     m_position;
   
   // Settings
   double            m_part_pct_dist[3];
   double            m_part_vol_pct[3];

   int               m_be_trigger_idx;
   int               m_trail_start_idx;
   
   ENUM_TRAIL_MODE   m_trail_mode;
   double            m_trail_hard_pct;
   double            m_trail_step_pct;
   double            m_trail_tick_pct;  

   // Granular Price Trigger Settings
   bool              m_trigger_bid_for_buy; 
   bool              m_trigger_ask_for_sell;

   SPartialRequest   m_activePartials[];

public:
   // Updated Constructor
   CPartialManager(double p1_d, double p2_d, double p3_d,
                   double p1_v, double p2_v, double p3_v,
                   int beTrigger, int trailStartTrigger,
                   ENUM_TRAIL_MODE tMode, double tHardPct, double tStepPct, double tTickPct,
                   bool useBidForBuy = true,  
                   bool useAskForSell = true) 
     {
      m_part_pct_dist[0]=p1_d; m_part_pct_dist[1]=p2_d; m_part_pct_dist[2]=p3_d;
      m_part_vol_pct[0]=p1_v;  m_part_vol_pct[1]=p2_v;  m_part_vol_pct[2]=p3_v;
      
      m_be_trigger_idx = beTrigger;        
      m_trail_start_idx = trailStartTrigger; 
      
      m_trail_mode = tMode;
      m_trail_hard_pct = tHardPct;
      m_trail_step_pct = tStepPct;
      m_trail_tick_pct = tTickPct;
      
      m_trigger_bid_for_buy = useBidForBuy;
      m_trigger_ask_for_sell = useAskForSell;
     }

   void OnTickLogic() {
      SyncPositions();
      CheckPartials();
      CheckTrailing();
      UpdateVisuals(); 
   }

   string GetStatus(ulong t, int pid) {
      if(IsPartialDone(t, pid)) return "DONE";
      double target = GetSavedTarget(t, pid);
      if(target == 0) return "---";
      return DoubleToString(target, _Digits);
   }

private:
   // --- INTERNAL HELPERS ---
   void CreateLine(string name, double price, color clr, string label) {
      if(ObjectFind(0, name) < 0) {
         ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
         ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      }
      ObjectSetString(0, name, OBJPROP_TEXT, label);
      ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   }

   string GetGVName(ulong ticket, int pid, string suffix) { return "GV_" + (string)ticket + "_P" + (string)pid + "_" + suffix; }
   bool IsRegistered(ulong ticket) { return GlobalVariableCheck("GV_" + (string)ticket + "_INIT"); }
   bool IsPartialDone(ulong ticket, int pid) { return (GlobalVariableGet(GetGVName(ticket, pid, "DONE")) == 1.0); }
   double GetSavedTarget(ulong ticket, int pid) { return GlobalVariableGet(GetGVName(ticket, pid, "PRC")); }
   void SaveTarget(ulong ticket, int pid, double price) { GlobalVariableSet(GetGVName(ticket, pid, "PRC"), price); }
   void MarkDone(ulong ticket, int pid) { GlobalVariableSet(GetGVName(ticket, pid, "DONE"), 1.0); }
   
   void CleanUp(ulong ticket) {
      GlobalVariableDel("GV_" + (string)ticket + "_INIT");
      GlobalVariableDel("GV_" + (string)ticket + "_CFG_SIG");
      GlobalVariableDel("GV_" + (string)ticket + "_TS_HIGH");
      for(int i=1; i<=3; i++) {
         GlobalVariableDel(GetGVName(ticket, i, "PRC"));
         GlobalVariableDel(GetGVName(ticket, i, "DONE"));
         ObjectDelete(0, "PL_" + (string)ticket + "_" + (string)i);
      }
      ObjectDelete(0, "LBL_SL_" + (string)ticket);
      ObjectDelete(0, "LBL_TP_" + (string)ticket);
   }

   double CalculateConfigSignature() {
      double sum = 0;
      for(int i=0; i<3; i++) {
         sum += m_part_pct_dist[i] * (i+1);
         sum += m_part_vol_pct[i];
      }
      return sum;
   }

   void UpdateVisuals() {
      for(int i=PositionsTotal()-1; i>=0; i--) {
         if(m_position.SelectByIndex(i)) {
            if(m_position.Symbol() != _Symbol) continue;
            ulong t = m_position.Ticket();
            
            for(int j=0; j<ArraySize(m_activePartials); j++) {
               if(m_activePartials[j].transactionId == t && !m_activePartials[j].isTaken) {
                  double pPnL = 0;
                  OrderCalcProfit((ENUM_ORDER_TYPE)m_activePartials[j].type, _Symbol, 0.01, m_position.PriceOpen(), m_activePartials[j].targetPrice, pPnL);
                  string txt = "P" + (string)m_activePartials[j].partialId + " Tgt";
                  CreateLine(m_activePartials[j].partialLineId, m_activePartials[j].targetPrice, clrDodgerBlue, txt);
               }
            }
         }
      }
   }

   void SyncPositions() {
      // Remove closed
      for(int i=ArraySize(m_activePartials)-1; i>=0; i--) {
         if(!m_position.SelectByTicket(m_activePartials[i].transactionId)) {
            CleanUp(m_activePartials[i].transactionId);
            ArrayRemove(m_activePartials, i, 1);
         }
      }
      // Add New
      for(int i=PositionsTotal()-1; i>=0; i--) {
         if(m_position.SelectByIndex(i)) {
            if(m_position.Symbol() != _Symbol) continue;
            ulong t = m_position.Ticket();
            bool active = false;
            for(int k=0; k<ArraySize(m_activePartials); k++) if(m_activePartials[k].transactionId == t) { active=true; break; }
            if(!active) LoadOrRegisterTrade(t);
         }
      }
   }

   void LoadOrRegisterTrade(ulong ticket) {
      if(!m_position.SelectByTicket(ticket)) return;
      double open = m_position.PriceOpen();
      int type = (int)m_position.PositionType();
      double currentSig = CalculateConfigSignature();
      double savedSig   = GlobalVariableGet("GV_" + (string)ticket + "_CFG_SIG");

      if(!IsRegistered(ticket) || currentSig != savedSig) {
         CleanUp(ticket);
         GlobalVariableSet("GV_" + (string)ticket + "_INIT", 1.0);
         GlobalVariableSet("GV_" + (string)ticket + "_CFG_SIG", currentSig);
         
         for(int i=0; i<3; i++) { 
            if(m_part_vol_pct[i] <= 0 || m_part_pct_dist[i] <= 0) continue;
            double target = 0;
            double dist = open * (m_part_pct_dist[i]/100.0);
            
            if(type == POSITION_TYPE_BUY) target = open + dist;
            else                          target = open - dist;
            
            SaveTarget(ticket, i+1, target);
         }
      }
      
      // Load
      for(int i=0; i<3; i++) {
         double target = GetSavedTarget(ticket, i+1);
         if(target == 0 || IsPartialDone(ticket, i+1)) continue; 
         
         SPartialRequest req;
         req.transactionId = ticket;
         req.partialId = i+1;
         req.partialLineId = "PL_" + (string)ticket + "_" + (string)(i+1);
         req.targetPrice = target;
         req.volPercent = m_part_vol_pct[i];
         req.isTaken = false;
         req.type = (ENUM_POSITION_TYPE)type;
         
         int s = ArraySize(m_activePartials);
         ArrayResize(m_activePartials, s+1);
         m_activePartials[s] = req;
      }
   }

   void CheckPartials() {
      for(int i=0; i<ArraySize(m_activePartials); i++) {
         if(m_activePartials[i].isTaken) continue;
         if(!m_position.SelectByTicket(m_activePartials[i].transactionId)) continue;
         
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double mid = (bid + ask) / 2.0;

         // --- NEW TRIGGER LOGIC (FIXED) ---
         double triggerPrice = 0.0;
         
         if(m_activePartials[i].type == POSITION_TYPE_BUY) {
             // For BUY: User wants "Buying Price" (ASK) if setting is true
             triggerPrice = (m_trigger_bid_for_buy) ? ask : mid;
         } 
         else {
             // For SELL: User wants "Selling Price" (BID) if setting is true
             triggerPrice = (m_trigger_ask_for_sell) ? bid : mid;
         }
         // -------------------------

         bool hit = false;
         if(m_activePartials[i].type==POSITION_TYPE_BUY && triggerPrice >= m_activePartials[i].targetPrice) hit=true;
         if(m_activePartials[i].type==POSITION_TYPE_SELL && triggerPrice <= m_activePartials[i].targetPrice) hit=true;
         
         if(hit) {
            double vol = m_position.Volume() * (m_activePartials[i].volPercent / 100.0);
            double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
            vol = MathFloor(vol/step)*step;
            if(vol < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) vol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            
            if(m_trade.PositionClosePartial(m_activePartials[i].transactionId, vol)) {
               MarkDone(m_activePartials[i].transactionId, m_activePartials[i].partialId);
               ObjectDelete(0, m_activePartials[i].partialLineId);
               m_activePartials[i].isTaken = true;
               if(m_be_trigger_idx > 0 && m_activePartials[i].partialId >= m_be_trigger_idx) MoveSLToEntry(m_activePartials[i].transactionId);
            }
         }
      }
   }

   void MoveSLToEntry(ulong ticket) {
      if(!m_position.SelectByTicket(ticket)) return;
      double open = m_position.PriceOpen();
      double sl = m_position.StopLoss();
      double tp = m_position.TakeProfit();
      bool modify = false;
      if(m_position.PositionType() == POSITION_TYPE_BUY) { if(sl < open) modify = true; } 
      else { if(sl == 0 || sl > open) modify = true; }
      if(modify) m_trade.PositionModify(ticket, open, tp);
   }

   void CheckTrailing() {
      if(m_trail_mode == TRAIL_NONE) return;
      
      for(int i=PositionsTotal()-1; i>=0; i--) {
         if(m_position.SelectByIndex(i)) {
            if(m_position.Symbol() != _Symbol) continue; 
            
            ulong t = m_position.Ticket();
            
            if(m_trail_start_idx > 0) {
               if(!IsPartialDone(t, m_trail_start_idx)) continue;
            }
            
            string gvHigh = "GV_" + (string)t + "_TS_HIGH";
            double currentPrice = (m_position.PositionType()==POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double maxPrice = GlobalVariableGet(gvHigh);
            
            bool update = false;
            if(m_position.PositionType()==POSITION_TYPE_BUY) {
               if(maxPrice == 0 || currentPrice > maxPrice) { maxPrice = currentPrice; update=true; }
            } else {
               if(maxPrice == 0 || currentPrice < maxPrice) { maxPrice = currentPrice; update=true; }
            }
            if(update) GlobalVariableSet(gvHigh, maxPrice);
            
            double virtualSL = 0;
            if(m_trail_mode == TRAIL_TICK_ONLY || m_trail_mode == TRAIL_HYBRID) {
               if(m_position.PositionType()==POSITION_TYPE_BUY) 
                  virtualSL = maxPrice * (1.0 - (m_trail_tick_pct/100.0));
               else 
                  virtualSL = maxPrice * (1.0 + (m_trail_tick_pct/100.0));
            }

            double hardSL = m_position.StopLoss();
            double open = m_position.PriceOpen();
            double stepDist = open * (m_trail_step_pct/100.0);
            
            if(m_trail_mode == TRAIL_HARD_ONLY || m_trail_mode == TRAIL_HYBRID) {
               if(m_position.PositionType()==POSITION_TYPE_BUY) {
                  if(virtualSL == 0) virtualSL = maxPrice * (1.0 - (m_trail_hard_pct/100.0));
                  if(virtualSL > hardSL + stepDist) m_trade.PositionModify(t, virtualSL, m_position.TakeProfit());
               } 
               else { 
                  if(virtualSL == 0) virtualSL = maxPrice * (1.0 + (m_trail_hard_pct/100.0));
                  if(hardSL == 0 || virtualSL < hardSL - stepDist) m_trade.PositionModify(t, virtualSL, m_position.TakeProfit());
               }
            }
         }
      }
   }
  };