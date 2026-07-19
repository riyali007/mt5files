#ifndef ADVTP_DEVELOPER_TEST_MQH
#define ADVTP_DEVELOPER_TEST_MQH

bool IsDeveloperTestAllowed()
{
   if(!InpShowDeveloperControls)
   {
      SetPanelMessage("Developer controls are hidden in EA Inputs",clrTomato);
      return(false);
   }
   
   if(!InpEnableDeveloperTestMode)
   {
      SetPanelMessage("Enable Developer Test Mode in EA Inputs first",clrTomato);
      return(false);
   }
   if(!g_DeveloperTestMode)
   {
      SetPanelMessage("DEV MODE is OFF - click DEV MODE: OFF",clrTomato);
      return(false);
   }

   if(!g_HasManagedTrades)
   {
      SetPanelMessage("No managed trades available",clrTomato);
      return(false);
   }

   EnsureSelectedTicket();

   if(g_SelectedTicketIndex < 0)
   {
      SetPanelMessage("No selected ticket",clrTomato);
      return(false);
   }

   return(true);
}

int GetNextIncompletePartialIndex(const TradeState &state)
{
   for(int i=0; i<state.partial_count; i++)
   {
      if(!state.partial_done[i])
         return(i);
   }

   return(-1);
}

bool ForcePartialForSelectedTicket(const int requested_index)
{
   if(!IsDeveloperTestAllowed())
      return(false);

   int state_index = g_SelectedTicketIndex;
   TradeState state = g_TradeStates[state_index];

   if(state.pending_action != ATP_ACTION_NONE)
   {
      SetPanelMessage("Selected ticket has a pending action",clrTomato);
      return(false);
   }

   if(!PositionSelectByTicket(state.ticket))
   {
      SetPanelMessage("Selected ticket no longer exists",clrTomato);
      return(false);
   }

   int partial_index = requested_index;

   if(partial_index < 0)
      partial_index = GetNextIncompletePartialIndex(state);

   if(partial_index < 0 || partial_index >= state.partial_count)
   {
      SetPanelMessage("No incomplete partial remains",clrGold);
      return(false);
   }

   if(state.partial_done[partial_index])
   {
      SetPanelMessage("TP" + IntegerToString(partial_index+1) + " is already complete",clrGold);
      return(false);
   }

   state.current_volume = PositionGetDouble(POSITION_VOLUME);
   g_TradeStates[state_index].current_volume = state.current_volume;

   double close_volume = GetSafePartialCloseVolume(state,partial_index);

   if(close_volume <= 0.0)
   {
      SetPanelMessage("Cannot calculate valid partial volume",clrTomato);
      return(false);
   }

   g_TradeStates[state_index].pending_action = ATP_ACTION_PARTIAL_PENDING;
   g_TradeStates[state_index].pending_partial_index = partial_index;
   g_TradeStates[state_index].pending_volume_before = state.current_volume;
   g_TradeStates[state_index].pending_expected_close = close_volume;

   LogInfo("DEV",
           "Forcing TP" + IntegerToString(partial_index+1) +
           " on ticket #" + (string)state.ticket +
           ", close volume=" + DoubleToString(close_volume,2));

   if(!SendPartialCloseRequest(state.ticket,close_volume,"DEV_TP"+IntegerToString(partial_index+1)))
   {
      g_TradeStates[state_index].pending_action = ATP_ACTION_NONE;
      g_TradeStates[state_index].pending_partial_index = -1;
      g_TradeStates[state_index].pending_volume_before = 0.0;
      g_TradeStates[state_index].pending_expected_close = 0.0;

      SetPanelMessage("DEV TP request rejected",clrTomato);
      return(false);
   }

   SetPanelMessage("DEV TP" + IntegerToString(partial_index+1) + " request sent",clrLimeGreen);
   return(true);
}

bool ForceBEForSelectedTicket()
{
   if(!IsDeveloperTestAllowed())
      return(false);

   int state_index = g_SelectedTicketIndex;

   if(g_TradeStates[state_index].pending_action != ATP_ACTION_NONE)
   {
      SetPanelMessage("Selected ticket has a pending action",clrTomato);
      return(false);
   }

   LogInfo("DEV","Forcing BE attempt on ticket #" + (string)g_TradeStates[state_index].ticket);

   if(!SendBERequest(state_index,"DEV"))
   {
      SetPanelMessage("DEV BE waiting/rejected - see Experts",clrTomato);
      return(false);
   }

   SetPanelMessage("DEV BE request sent",clrLimeGreen);
   return(true);
}

void ToggleDeveloperTestMode()
{
   if(!InpEnableDeveloperTestMode)
   {
      g_DeveloperTestMode = false;
      SetPanelMessage("Enable Developer Test Mode in EA Inputs first",clrTomato);
      g_PanelDirty = true;
      return;
   }

   g_DeveloperTestMode = !g_DeveloperTestMode;

   if(g_DeveloperTestMode)
      SetPanelMessage("DEV MODE ON - real trade actions enabled",clrTomato);
   else
      SetPanelMessage("DEV MODE OFF",clrSilver);

   g_PanelDirty = true;

   LogInfo("DEV","Developer Test Mode=" + (g_DeveloperTestMode ? "ON" : "OFF"));
}

#endif