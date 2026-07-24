//+------------------------------------------------------------------+
//|                                              TradeManager_v1.mq5 |
//|                                              Trade Manager V1.01 |
//+------------------------------------------------------------------+
#property copyright "MQL5 Developer"
#property link      ""
#property version   "1.01"

#include "CanvasInterface.mqh"
#include "JournalingEngine.mqh"
#include "TradingLogic.mqh" 

//--- Enumerations for User Inputs
enum ENUM_PANEL_CORNER
{
    CORNER_TL = 0, // Top Left
    CORNER_TR = 1, // Top Right
    CORNER_BL = 2, // Bottom Left
    CORNER_BR = 3  // Bottom Right
};

//--- User Inputs
input group "=== GUI Settings ==="
input ENUM_PANEL_CORNER InpPanelCorner = CORNER_TR; // Panel Position
input int               InpPaddingX    = 20;        // X Padding (Pixels)
input int               InpPaddingY    = 20;        // Y Padding (Pixels)
input string            InpWebhookURL  = "https://your-n8n-instance.com/webhook/trade-event"; // Webhook URL

//--- Global Variables
CAdvancedGUI    GUI;
CAsyncWebhook   Journal;
CTradingEngine  TradeEngine;

//+------------------------------------------------------------------+
//| Helper: Calculate Exact X/Y Based on Chart Size                  |
//+------------------------------------------------------------------+
void CalculatePanelPosition(int &out_x, int &out_y)
{
    int chart_width = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
    int chart_height = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);

    switch(InpPanelCorner)
    {
        case CORNER_TL:
            out_x = InpPaddingX;
            out_y = InpPaddingY;
            break;
        case CORNER_TR:
            out_x = chart_width - GUI_WIDTH - InpPaddingX;
            out_y = InpPaddingY;
            break;
        case CORNER_BL:
            out_x = InpPaddingX;
            out_y = chart_height - GUI_HEIGHT - InpPaddingY;
            break;
        case CORNER_BR:
            out_x = chart_width - GUI_WIDTH - InpPaddingX;
            out_y = chart_height - GUI_HEIGHT - InpPaddingY;
            break;
    }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    int start_x, start_y;
    CalculatePanelPosition(start_x, start_y);
    
    if(!GUI.Create("TradeManagerCanvas", start_x, start_y))
    {
        Print("Error: Could not create Canvas GUI.");
        return INIT_FAILED;
    }

    GUI.InitializeInputs();
    Journal.Init(InpWebhookURL);
    TradeEngine.Init(80085);
    
    EventSetMillisecondTimer(500); 
    Print("Advanced Trade Manager Pro v1.01 Initialized Successfully.");
    return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
    EventKillTimer();
    GUI.Destroy();
}

void OnTick() {
   // This constantly checks if current price has hit any of our Virtual TP levels
    TradeEngine.CheckVirtualPartials();
}
void OnTimer() { Journal.ProcessTimer(); }

//+------------------------------------------------------------------+
//| Chart Event handler (For GUI Interactions)                       |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
    // --- 0. Handle Chart Resizing (Keep Panel Pinned) ---
    if(id == CHARTEVENT_CHART_CHANGE)
    {
        int new_x, new_y;
        CalculatePanelPosition(new_x, new_y);
        GUI.Move(new_x, new_y);
    }

    // --- 1. Handle Canvas Button Clicks ---
    if(id == CHARTEVENT_CLICK)
    {
        int x = (int)lparam;
        int y = (int)dparam;
        
        ENUM_GUI_ACTION action = GUI.HandleClick(x, y);
        
        switch(action)
        {
            case ACTION_MARKET_BUY:
            {
                double lot_size = StringToDouble(GUI.GetInputValue("inp_lot"));
                double sl_pts = StringToDouble(GUI.GetInputValue("inp_sl_pts"));
                double tp_pts = StringToDouble(GUI.GetInputValue("inp_tp_pts"));
                int num_partials = (int)StringToInteger(GUI.GetInputValue("inp_partials")); // NEW
                
                TradeEngine.ExecuteMarketOrder(ORDER_TYPE_BUY, lot_size, sl_pts, tp_pts, num_partials);
                break;
            }
            case ACTION_MARKET_SELL:
            {
                double lot_size = StringToDouble(GUI.GetInputValue("inp_lot"));
                double sl_pts = StringToDouble(GUI.GetInputValue("inp_sl_pts"));
                double tp_pts = StringToDouble(GUI.GetInputValue("inp_tp_pts"));
                int num_partials = (int)StringToInteger(GUI.GetInputValue("inp_partials")); // NEW
                
                TradeEngine.ExecuteMarketOrder(ORDER_TYPE_SELL, lot_size, sl_pts, tp_pts, num_partials);
                break;
            }
            case ACTION_MOVE_BE:         TradeEngine.MoveToBreakEven(); break;
            case ACTION_CLOSE_SELECTED:  TradeEngine.CloseSelected(); break;
            case ACTION_CLOSE_ALL:       TradeEngine.CloseAllSymbol(); break;
            case ACTION_ADOPT_EXTERNAL:  TradeEngine.AdoptNextExternalTrade(); break;
            case ACTION_PARTIAL_CLOSE:
            {
                double partial_pct = StringToDouble(GUI.GetInputValue("inp_manual_pct"));
                TradeEngine.ClosePartial(partial_pct);
                break;
            }
            default: break;
        }
    }
    
    // --- 2. Handle User Input Changes (Dynamic Risk/Reward Updates) ---
    if(id == CHARTEVENT_OBJECT_ENDEDIT)
    {
        if(sparam == "inp_lot" || sparam == "inp_sl_pts" || sparam == "inp_tp_pts")
        {
            double lot = StringToDouble(GUI.GetInputValue("inp_lot"));
            double sl = StringToDouble(GUI.GetInputValue("inp_sl_pts"));
            double tp = StringToDouble(GUI.GetInputValue("inp_tp_pts"));
            
            double tick_value = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
            double tick_size = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
            double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
            
            if(tick_size > 0)
            {
                double risk_money = lot * (sl * point / tick_size) * tick_value;
                double profit_money = lot * (tp * point / tick_size) * tick_value;
                
                // Update the text dynamically on the Canvas
                GUI.UpdateRiskRewardText(risk_money, profit_money);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Trade Transaction Event (Journaling Trigger)                     |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
{
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
    {
        long deal_entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
        long deal_reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
        
        if(deal_entry == DEAL_ENTRY_IN)
        {
            Journal.PushEvent(EV_OPEN_ENTRY, trans.deal, 0.0);
        }
        else if(deal_entry == DEAL_ENTRY_OUT)
        {
            double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
            
            if(deal_reason == DEAL_REASON_SL)
            {
                if(profit < 0.0) Journal.PushEvent(EV_SL_HIT, trans.deal, profit);
                else Journal.PushEvent(EV_BE_HIT, trans.deal, profit);
            }
            else if (deal_reason == DEAL_REASON_TP || deal_reason == DEAL_REASON_CLIENT) 
            {
                Journal.PushEvent(EV_PARTIAL_HIT, trans.deal, profit);
            }
        }
    }
}