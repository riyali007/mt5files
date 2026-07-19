//+------------------------------------------------------------------+
//|                                                   DonchianEA.mq5 |
//+------------------------------------------------------------------+
#property copyright "Professional MT5 Developer"
#property version   "1.03"

#include "Defines.mqh"
#include "Panel.mqh"
#include "Manager.mqh"

CMyPanel  ExtPanel;
CManager  ExtManager;

int OnInit()
{
   ExtManager.OnInit();
   if(!ExtPanel.Create(0, "DonchianPanel", 0, 20, 20, 260, 500)) return(INIT_FAILED);
   ExtPanel.Run();
   ExtPanel.CyclePosition(0); // Init text
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   ExtPanel.Destroy();
   ExtManager.CleanVisuals();
   ObjectsDeleteAll(0, "DT_EA_");
}

void OnTick()
{
   ExtManager.OnTick(ExtPanel);
   // Force update position list title to see count
   string txt = "Positions (" + IntegerToString(PositionsTotal()) + ")";
   ExtPanel.SetInfo(txt);
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   ExtPanel.OnEvent(id, lparam, dparam, sparam);
   
   if(id == CHARTEVENT_OBJECT_CLICK) {
      if(StringFind(sparam, "BtnMode") >= 0) { ExtPanel.ToggleMode(); ChartRedraw(); }
      else if(StringFind(sparam, "BtnBuy") >= 0) { ExtPanel.SelectDirection(1); ChartRedraw(); }
      else if(StringFind(sparam, "BtnSell") >= 0) { ExtPanel.SelectDirection(-1); ChartRedraw(); }
      else if(StringFind(sparam, "BtnVis") >= 0) { ExtManager.ToggleVisualize(ExtPanel); }
      else if(StringFind(sparam, "BtnPlace") >= 0) { ExtManager.PlaceOrder(ExtPanel); }
      // Position Toggles
      else if(StringFind(sparam, "BtnPrev") >= 0) { ExtPanel.CyclePosition(-1); }
      else if(StringFind(sparam, "BtnNext") >= 0) { ExtPanel.CyclePosition(1); }
      // Management
      else if(StringFind(sparam, "BtnDoPart") >= 0) { ExtManager.TakeSelectedPartial(ExtPanel); }
      else if(StringFind(sparam, "BtnDoBE") >= 0) { ExtManager.SetSelectedBE(ExtPanel); }
      else if(StringFind(sparam, "BtnClose") >= 0) { ExtManager.CloseSelected(ExtPanel); }
   }
}
