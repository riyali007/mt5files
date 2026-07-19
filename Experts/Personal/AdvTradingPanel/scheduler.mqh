#ifndef ADVTP_SCHEDULER_MQH
#define ADVTP_SCHEDULER_MQH

void UpdateLiveMarketData()
{
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol,tick))
      return;

   bool changed = false;

   if(tick.bid != g_Bid)
   {
      g_Bid = tick.bid;
      changed = true;
   }

   if(tick.ask != g_Ask)
   {
      g_Ask = tick.ask;
      changed = true;
   }

   if(changed)
      g_PanelDirty = true;
}

void RunFastScheduler()
{
   g_LastFastRunMs = GetTickCount();

   if(!g_HasManagedTrades)
      return;

   EvaluateAllPartials();
   EvaluateAutomaticBE();
   EvaluateAllTrailingStops();
   
}
void RunSlowScheduler()
{
   g_LastSlowRunMs = GetTickCount();

   if(g_RegistryDirty || (GetTickCount() - g_LastRegistryReconcileMs >= 1000))
   {
      g_RegistryDirty = false;
      ReconcileManagedPositions("Timer");
   }

   UpdatePanelShell(false);
   ProcessExternalMonitoring();

   // Stage 7 will process the non-blocking n8n journal queue here.
}

#endif