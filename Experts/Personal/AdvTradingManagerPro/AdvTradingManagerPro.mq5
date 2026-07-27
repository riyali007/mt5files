// AdvTradingManagerPro.mq5

// 1. Include the class definitions FIRST
#include "panel_shell.mqh"
#include "trade_manager.mqh"

// 2. Declare the global pointers
CPanel*         ExtPanel;
CTradeManager*  ExtTradeManager;

// 3. EA Initialization
int OnInit() {
    ExtPanel = new CPanel();
    ExtTradeManager = new CTradeManager(123456); // Set your magic number here
    ExtTradeManager.RecoverOpenPositions();
    
    return(INIT_SUCCEEDED);
}

// 4. EA De-initialization (Clean up memory)
void OnDeinit(const int reason) {
    if(ExtPanel != NULL) delete ExtPanel;
    if(ExtTradeManager != NULL) delete ExtTradeManager;
}

// 5. Chart Event Routing
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam) {
                      
    // Let the panel process raw clicks and drags
    if(ExtPanel != NULL) {
        ExtPanel.ProcessChartEvent(id, lparam, dparam, sparam);
    }
    
    // Let the Trade Manager process custom commands broadcasted by the panel
    if(ExtTradeManager != NULL && id >= CHARTEVENT_CUSTOM) {
        ExtTradeManager.OnUICommand(id, lparam, dparam, sparam);
    }
}