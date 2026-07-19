#ifndef ADVTP_POSITION_SELECTOR_MQH
#define ADVTP_POSITION_SELECTOR_MQH

void RefreshSelectedTicket()
{
   g_SelectedTicketIndex = -1;

   if(g_SelectedTicket == 0)
      return;

   for(int i=0; i<ArraySize(g_TradeStates); i++)
   {
      if(g_TradeStates[i].ticket == g_SelectedTicket)
      {
         g_SelectedTicketIndex = i;
         return;
      }
   }

   g_SelectedTicket = 0;
}

void EnsureSelectedTicket()
{
   RefreshSelectedTicket();

   if(g_SelectedTicketIndex >= 0)
      return;

   if(ArraySize(g_TradeStates) <= 0)
      return;

   g_SelectedTicketIndex = 0;
   g_SelectedTicket = g_TradeStates[0].ticket;
}

void SelectRelativeTicket(const int direction)
{
   int total = ArraySize(g_TradeStates);

   if(total <= 0)
   {
      g_SelectedTicket = 0;
      g_SelectedTicketIndex = -1;
      g_PanelDirty = true;
      return;
   }

   EnsureSelectedTicket();

   int next_index = g_SelectedTicketIndex + direction;

   if(next_index < 0)
      next_index = total - 1;

   if(next_index >= total)
      next_index = 0;

   g_SelectedTicketIndex = next_index;
   g_SelectedTicket = g_TradeStates[next_index].ticket;
   g_PanelDirty = true;

   LogInfo("SELECT","Selected ticket #" + (string)g_SelectedTicket);
}

string GetSelectedTicketText()
{
   EnsureSelectedTicket();

   if(g_SelectedTicketIndex < 0)
      return("Selected: none");

   TradeState state = g_TradeStates[g_SelectedTicketIndex];

   string side = (state.position_type == POSITION_TYPE_BUY ? "BUY" : "SELL");

   return("Selected: #" + (string)state.ticket +
          " " + side +
          " " + DoubleToString(state.current_volume,2));
}

#endif