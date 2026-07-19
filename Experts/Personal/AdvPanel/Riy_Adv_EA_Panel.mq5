//+------------------------------------------------------------------+
//|                                                   AdvancedEA.mq5 |
//+------------------------------------------------------------------+
#property version   "5.90"
#include "Manager.mqh"
#include "Panel.mqh"
#include "Inputs.mqh"     
#include "AI_Handler.mqh" 

CPartialManager *ptrManager;
CAdvancePanel   *ptrPanel;
CAIHandler      *ptrAI;    

datetime lastAICheck = 0;
bool     aiScanEnabled = false; 

int OnInit()
  {
   ObjectsDeleteAll(0, "AdvancePanel");
   ObjectsDeleteAll(0, "PL_"); ObjectsDeleteAll(0, PREFIX_PREVIEW);
   
   ptrManager = new CPartialManager(
      Inp_P1_Percent, Inp_P2_Percent, Inp_P3_Percent, 
      Inp_P1_Vol, Inp_P2_Vol, Inp_P3_Vol,
      InpAutoBE_At_Partial, InpTrail_Start_At_Partial,
      InpTrailMode, InpTrailHardDist, InpTrailStep, InpTrailTickDist,
      InpUseBidForBuy,    // <--- Param 13
      InpUseAskForSell    // <--- Param 14
   );
   
   ptrPanel = new CAdvancePanel();
   ptrPanel.SetPartialConfig(
      Inp_P1_Percent, Inp_P2_Percent, Inp_P3_Percent,
      Inp_P1_Vol, Inp_P2_Vol, Inp_P3_Vol
   );
   
   ptrAI = new CAIHandler();
   // UPDATED: Passing Provider, BaseURL, etc.
   ptrAI.Init(InpAI_Provider, InpAI_ApiKey, InpAI_Model, InpAI_BaseUrl, InpAI_Prompt, InpAI_MaxDailyLoss, InpAI_MaxTrades);
   ptrAI.SetMTASettings(InpAI_MTA_Count, InpAI_MTA_TF1, InpAI_MTA_TF2, InpAI_MTA_TF3);
   
   if(!ptrPanel.Create(0, "AdvancePanel", 0, 50, 50)) return(INIT_FAILED);
   
   ptrPanel.LoadState();
   aiScanEnabled = ptrPanel.IsAIScanEnabled(); 
   ptrPanel.Run();

   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(CheckPointer(ptrManager)==POINTER_DYNAMIC) delete ptrManager;
   if(CheckPointer(ptrPanel)==POINTER_DYNAMIC) { ptrPanel.SaveState(); ptrPanel.Destroy(reason); delete ptrPanel; }
   if(CheckPointer(ptrAI)==POINTER_DYNAMIC) delete ptrAI; 
   ObjectsDeleteAll(0, "PL_");
   ObjectsDeleteAll(0, PREFIX_PREVIEW);
  }

void OnTick()
  {
   if(CheckPointer(ptrManager)) ptrManager.OnTickLogic();
   
   if(CheckPointer(ptrPanel)) {
      ptrPanel.UpdateMarketPrice();
      long t = ptrPanel.GetSelectedTicket();
      double pnl = 0;
      if(t>0 && PositionSelectByTicket(t)) pnl=PositionGetDouble(POSITION_PROFIT);
      ptrPanel.UpdatePnL(pnl);
      
      if(t>0) {
          ptrPanel.UpdatePartialInfo(
            "P1: " + ptrManager.GetStatus(t, 1),
            "P2: " + ptrManager.GetStatus(t, 2),
            "P3: " + ptrManager.GetStatus(t, 3)
          );
      }
      
      // Update Timer Status
      aiScanEnabled = ptrPanel.IsAIScanEnabled();
      if(aiScanEnabled) {
         int timeLeft = InpAI_Interval - (int)(TimeCurrent()-lastAICheck);
         if(timeLeft < 0) timeLeft = 0;
         ptrPanel.UpdateAIStatus("Active (Scan " + IntegerToString(timeLeft) + "s)");
      }
      else ptrPanel.UpdateAIStatus("Stopped");
   }

   // --- AI SCAN LOGIC ---
   if(aiScanEnabled && TimeCurrent() - lastAICheck >= InpAI_Interval) {
      
      int totalTrades = PositionsTotal();
      if(totalTrades >= 2) {
         if(CheckPointer(ptrPanel)) ptrPanel.UpdateAIStatus("Limit Reached");
         lastAICheck = TimeCurrent(); 
         return; 
      }

      if(CheckPointer(ptrPanel)) { 
         ptrPanel.UpdateAIStatus("Analyzing..."); 
         ptrPanel.AddAILog("Scanning " + _Symbol + "...");
         ChartRedraw(); 
      }
      
      lastAICheck = TimeCurrent();
      string reasoning = "";
      int decision = ptrAI.GetTradeDecision(reasoning); 
      
      if(CheckPointer(ptrPanel)) {
         if(decision != 0) {
            double currentPrice = (decision==1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
            
            // 1. Show the main visual signal (Green/Red box)
            ptrPanel.ShowSignalResult(decision, currentPrice);
            
            // 2. PARSE AND DISPLAY DETAILS IN LOGS [UPDATED]
            // We pass the FULL 'reasoning' string so the panel can extract Entry, SL, TP
            ptrPanel.ShowParsedSignal(reasoning);

            Print("AI Signal: ", (decision==1?"BUY":"SELL"), " | ", reasoning);
            
            if(ptrPanel.IsAutoExecEnabled()) {
               ptrPanel.AddAILog("Auto-Executing...");
               ExecuteAITrade(decision);
            } else {
               ptrPanel.AddAILog("Waiting for Manual Action.");
            }
            
         } else {
             // HOLD or Error
             if(StringFind(reasoning, "Error") >= 0) ptrPanel.AddAILog("ERR: " + reasoning);
             else ptrPanel.AddAILog("HOLD: " + StringSubstr(reasoning, 0, 150));
         }
         ptrPanel.UpdateAIStatus("Wait..."); 
         ChartRedraw();
      }
   }
  }

void ExecuteAITrade(int direction) {
   CTrade trade;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entry = (direction == 1) ? ask : bid;
   
   double slDist = entry * 0.005; 
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lot = 0.01;
   
   if(tickSize > 0 && tickVal > 0) {
       double lossPerLot = (slDist / tickSize) * tickVal;
       if(lossPerLot > 0) lot = InpAI_RiskPerTrade / lossPerLot;
   }
   
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot/step) * step;
   if(lot < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   
   if(direction == 1) trade.Buy(lot, _Symbol, 0, 0, 0, "AI Auto Trade");
   else               trade.Sell(lot, _Symbol, 0, 0, 0, "AI Auto Trade");
}

void OnChartEvent(const int id, const long &l, const double &d, const string &s)
  {
   if(CheckPointer(ptrPanel)) ptrPanel.ChartEvent(id, l, d, s);
   if(id == CHARTEVENT_CUSTOM+ID_BTN_AI_SCAN) {
      aiScanEnabled = ptrPanel.IsAIScanEnabled();
      if(aiScanEnabled) lastAICheck = 0; 
   }
  }