#ifndef ADVTP_MANUAL_ACTIONS_MQH
#define ADVTP_MANUAL_ACTIONS_MQH

bool ExecuteManualPartialSelected()
{
   EnsureSelectedTicket();

   if(g_SelectedTicketIndex < 0)
   {
      SetPanelMessage("No selected trade",clrTomato);
      return(false);
   }

   double percent = g_ManualPartialPercent;

   if(percent <= 0.0 || percent >= 100.0)
   {
      SetPanelMessage("Manual partial must be >0 and <100",clrTomato);
      return(false);
   }

   TradeState state = g_TradeStates[g_SelectedTicketIndex];

   if(state.pending_action != ATP_ACTION_NONE)
   {
      SetPanelMessage("Selected trade has pending action",clrTomato);
      return(false);
   }

   if(!PositionSelectByTicket(state.ticket))
   {
      SetPanelMessage("Selected trade no longer exists",clrTomato);
      return(false);
   }

   state.current_volume = PositionGetDouble(POSITION_VOLUME);
   g_TradeStates[g_SelectedTicketIndex].current_volume = state.current_volume;

   double requested = state.current_volume * percent / 100.0;
   double close_volume = NormalizeVolumeDown(state.symbol,requested);
   double min_volume = SymbolInfoDouble(state.symbol,SYMBOL_VOLUME_MIN);

   if(close_volume <= 0.0 || (state.current_volume - close_volume) < min_volume)
   {
      SetPanelMessage("Manual partial leaves invalid runner",clrTomato);
      return(false);
   }

   g_TradeStates[g_SelectedTicketIndex].pending_action = ATP_ACTION_PARTIAL_PENDING;
   g_TradeStates[g_SelectedTicketIndex].pending_partial_index = -1;
   g_TradeStates[g_SelectedTicketIndex].pending_volume_before = state.current_volume;
   g_TradeStates[g_SelectedTicketIndex].pending_expected_close = close_volume;

   if(!SendPartialCloseRequest(state.ticket,close_volume,"MANUAL"))
   {
      g_TradeStates[g_SelectedTicketIndex].pending_action = ATP_ACTION_NONE;
      g_TradeStates[g_SelectedTicketIndex].pending_partial_index = -1;
      g_TradeStates[g_SelectedTicketIndex].pending_volume_before = 0.0;
      g_TradeStates[g_SelectedTicketIndex].pending_expected_close = 0.0;
      SetPanelMessage("Manual partial rejected",clrTomato);
      return(false);
   }

   SetPanelMessage("Manual partial request sent",clrLimeGreen);
   return(true);
}

bool ExecuteManualBESelected()
{
   EnsureSelectedTicket();

   if(g_SelectedTicketIndex < 0)
   {
      SetPanelMessage("No selected trade",clrTomato);
      return(false);
   }

   if(SendBERequest(g_SelectedTicketIndex,"MANUAL"))
   {
      SetPanelMessage("BE request sent",clrLimeGreen);
      return(true);
   }

   SetPanelMessage("BE waiting/rejected - see Experts",clrTomato);
   return(false);
}

#endif