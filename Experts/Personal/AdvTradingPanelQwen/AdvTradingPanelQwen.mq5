//+------------------------------------------------------------------+
//|                                          AdvTradingPanel.mq5      |
//|                        Advanced Trade Manager Pro V1.0            |
//|                        Module 1: Core Panel Skeleton               |
//+------------------------------------------------------------------+
#property copyright "Riy Ali"
#property version   "1.00"
#property strict

#include "CPanelUI.mqh"

input ENUM_BASE_CORNER InpPanelCorner = CORNER_LEFT_UPPER;

CPanelUI ExtPanel;

//+------------------------------------------------------------------+
int OnInit()
{
   int x1 = 20, y1 = 20;

   long chartWidth  = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   long chartHeight = ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);

   if(InpPanelCorner == CORNER_RIGHT_UPPER || InpPanelCorner == CORNER_RIGHT_LOWER)
      x1 = (int)chartWidth - PANEL_WIDTH - 20;

   if(InpPanelCorner == CORNER_LEFT_LOWER || InpPanelCorner == CORNER_RIGHT_LOWER)
      y1 = (int)chartHeight - PANEL_HEIGHT - 40;

   if(!ExtPanel.Create(0, "AdvTradeMgrPro", 0, x1, y1, x1+PANEL_WIDTH, y1+PANEL_HEIGHT))
   {
      Print("AdvTradeMgrPro: panel Create() failed");
      return(INIT_FAILED);
   }

   ExtPanel.Run();
   EventSetTimer(1);

   ChartRedraw();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   ExtPanel.Destroy();
}

//+------------------------------------------------------------------+
void OnTick()
{
   // Reserved for Step 2: Order Engine / price-driven logic
}

//+------------------------------------------------------------------+
void OnTimer()
{
   // Reserved for Step 3+: Risk/Partial/BE/Basket module Update() calls
}

//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                   const long &lparam,
                   const double &dparam,
                   const string &sparam)
{
   ExtPanel.ChartEvent(id, lparam, dparam, sparam);

   if(id == CHARTEVENT_CUSTOM+1001) Print("BUY_CLICK received");
   if(id == CHARTEVENT_CUSTOM+1002) Print("SELL_CLICK received");
   if(id == CHARTEVENT_CUSTOM+1003) Print("CLOSE_SEL received");
   if(id == CHARTEVENT_CUSTOM+1004) Print("CLOSE_ALL received");
   if(id == CHARTEVENT_CUSTOM+1005) Print("PARTIAL_CLICK received");
   if(id == CHARTEVENT_CUSTOM+1006) Print("BE_CLICK received");
   if(id == CHARTEVENT_CUSTOM+1007) Print("SEL_NEXT received");
   if(id == CHARTEVENT_CUSTOM+1008) Print("SEL_PREV received");
   if(id == CHARTEVENT_CUSTOM+1009) Print("EXPORT_CSV received");
   if(id == CHARTEVENT_CUSTOM+1010) Print("TOGGLE_INV received");
   if(id == CHARTEVENT_CUSTOM+1011) Print("TOGGLE_AUTORISK received");
   if(id == CHARTEVENT_CUSTOM+1012) Print("TOGGLE_BASKET received");
   if(id == CHARTEVENT_CUSTOM+1013) Print("VISUALIZE received");
}