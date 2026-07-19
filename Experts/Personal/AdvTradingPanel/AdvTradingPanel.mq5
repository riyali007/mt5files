#property strict
#property version   "1.01"
#property description "Advanced Trade Manager Pro v1.0 - Stage 3A Order Entry Panel"

#include "inputs.mqh"
#include "variables.mqh"
#include "logger.mqh"
#include "account_functions.mqh"
#include "trade_plan.mqh"
#include "order_entry.mqh"
#include "persistence.mqh"
#include "external_manager.mqh"
#include "state_registry.mqh"
#include "position_visuals.mqh"
#include "partial_manager.mqh"
#include "position_selector.mqh"
#include "breakeven_manager.mqh"
#include "trailing_stop_manager.mqh"
#include "trade_screenshot.mqh"
#include "n8n_webhook.mqh"
#include "trade_journal.mqh"
#include "manual_actions.mqh"
#include "close_manager.mqh"
#include "external_manager.mqh"
#include "developer_test.mqh"
#include "scheduler.mqh"
#include "panel_shell.mqh"

int OnInit()
{
   ResetLastError();

   if(!ValidateHedgingAccount())
      return(INIT_FAILED);

   InitializeRuntimeState();
   InitializeLogger();
   LogSymbolTradingSettings(_Symbol);
   InitializeN8nWebhook();
   InitializeTradePlan();
   InitializePanelShell();

   ReconcileManagedPositions("OnInit");
   InitializeTradeJournal();
   ProcessExternalMonitoring();
   RefreshAllManagedPositionVisuals();
   RefreshManagedTradeFlags();
   UpdatePanelShell(true);

   if(!EventSetMillisecondTimer(InpTimerIntervalMs))
   {
      LogError("INIT","EventSetMillisecondTimer failed. Error=" + IntegerToString(GetLastError()));
      DestroyPanelShell();
      return(INIT_FAILED);
   }

   LogInfo("INIT",APP_NAME + " v" + APP_VERSION + " initialized");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteAllManagedPositionVisuals();
   DestroyPanelShell();
   LogInfo("DEINIT","EA removed. Reason=" + IntegerToString(reason));
}

void OnTick()
{
   UpdateLiveMarketData();
   RunFastScheduler();
}

void OnTimer()
{
   RunSlowScheduler();
}

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   HandlePanelShellEvent(id,lparam,dparam,sparam);
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   HandleTradeTransaction(trans,request,result);
}