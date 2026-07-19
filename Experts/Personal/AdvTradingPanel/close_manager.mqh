#ifndef ADVTP_CLOSE_MANAGER_MQH
#define ADVTP_CLOSE_MANAGER_MQH

bool SendClosePositionRequest(const int index,const string source)
{
   if(index < 0 || index >= ArraySize(g_TradeStates))
      return(false);

   TradeState state = g_TradeStates[index];

   if(state.pending_action != ATP_ACTION_NONE)
   {
      LogDebug("CLOSE","Ticket #" + (string)state.ticket + " already has pending action");
      return(false);
   }

   if(!PositionSelectByTicket(state.ticket))
   {
      SetPanelMessage("Position no longer exists",clrTomato);
      return(false);
   }

   MqlTick tick;

   if(!SymbolInfoTick(state.symbol,tick))
   {
      SetPanelMessage("No market tick for close",clrTomato);
      return(false);
   }

   double volume = PositionGetDouble(POSITION_VOLUME);
   long position_type = PositionGetInteger(POSITION_TYPE);

   if(volume <= 0.0)
   {
      SetPanelMessage("Invalid current position volume",clrTomato);
      return(false);
   }

   MqlTradeRequest request;
   MqlTradeResult result;

   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_DEAL;
   request.position = state.ticket;
   request.magic = InpMagicNumber;
   request.symbol = state.symbol;
   request.volume = volume;
   request.type = (position_type == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
   request.price = 0.0;
   request.deviation = InpDeviationPoints;
   request.comment = APP_SHORT_NAME + "_Close_" + source;
   
   if(!HasSupportedMarketFillingMode(state.symbol))
   {
      g_TradeStates[index].pending_action = ATP_ACTION_NONE;
      SetPanelMessage("No valid filling mode for close",clrTomato);
      return(false);
   }
   
   request.type_filling = GetSymbolFillingType(state.symbol);
   

   g_TradeStates[index].pending_action = ATP_ACTION_CLOSE_PENDING;

   ResetLastError();

   bool sent = OrderSend(request,result);
   int terminal_error = GetLastError();

   LogInfo("CLOSE",
           "Ticket #" + (string)state.ticket +
           " source=" + source +
           " volume=" + DoubleToString(volume,2) +
           " sent=" + (sent ? "true" : "false") +
           " terminal_error=" + IntegerToString(terminal_error) +
           " retcode=" + IntegerToString((int)result.retcode) +
           " comment=" + result.comment);

   if(!sent || !IsTradeRetcodeSuccessful(result.retcode))
   {
      g_TradeStates[index].pending_action = ATP_ACTION_NONE;
   
      LogError("CLOSE",
               "Ticket #" + (string)state.ticket +
               " rejected. Retcode=" + IntegerToString((int)result.retcode) +
               " comment=" + result.comment);
   
      return(false);
   }
   
   // Journal immediately on accepted close request (pending full removal)
   JournalManagedTradeEvent(index,
                            "CLOSE_REQUEST",
                            "Close request accepted source=" + source,
                            source,
                            volume);
   
   return(true);
}

bool CloseSelectedPosition()
{
   EnsureSelectedTicket();

   if(g_SelectedTicketIndex < 0)
   {
      SetPanelMessage("No selected trade",clrTomato);
      return(false);
   }

   if(SendClosePositionRequest(g_SelectedTicketIndex,"SELECTED"))
   {
      SetPanelMessage("Close selected request sent",clrLimeGreen);
      return(true);
   }

   SetPanelMessage("Close selected rejected - see Experts",clrTomato);
   return(false);
}

bool IsManagedCurrentSymbolPendingOrder(const ulong ticket)
{
   if(ticket == 0 || !OrderSelect(ticket))
      return(false);

   string symbol = OrderGetString(ORDER_SYMBOL);
   long magic = OrderGetInteger(ORDER_MAGIC);

   return(symbol == _Symbol && (ulong)magic == InpMagicNumber);
}

bool SendDeletePendingOrderRequest(const ulong order_ticket)
{
   MqlTradeRequest request;
   MqlTradeResult result;

   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_REMOVE;
   request.order = order_ticket;

   ResetLastError();

   bool sent = OrderSend(request,result);
   int terminal_error = GetLastError();

   LogInfo("CLOSE",
           "Delete pending #" + (string)order_ticket +
           " sent=" + (sent ? "true" : "false") +
           " terminal_error=" + IntegerToString(terminal_error) +
           " retcode=" + IntegerToString((int)result.retcode) +
           " comment=" + result.comment);

   if(!sent || !IsTradeRetcodeSuccessful(result.retcode))
   {
      LogError("CLOSE",
               "Delete pending #" + (string)order_ticket +
               " rejected. Retcode=" + IntegerToString((int)result.retcode) +
               " comment=" + result.comment);

      return(false);
   }

   return(true);
}

int DeleteAllManagedPendingOrdersCurrentSymbol()
{
   int removed_requests = 0;

   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong order_ticket = OrderGetTicket(i);

      if(!IsManagedCurrentSymbolPendingOrder(order_ticket))
         continue;

      if(SendDeletePendingOrderRequest(order_ticket))
         removed_requests++;
   }

   return(removed_requests);
}

int CloseAllManagedPositionsCurrentSymbol()
{
   int close_requests = 0;

   for(int i=ArraySize(g_TradeStates)-1; i>=0; i--)
   {
      if(g_TradeStates[i].symbol != _Symbol)
         continue;

      if(SendClosePositionRequest(i,"CLOSE_ALL"))
         close_requests++;
   }

   return(close_requests);
}

bool CloseAllManagedCurrentSymbol()
{
   int pending_removed = DeleteAllManagedPendingOrdersCurrentSymbol();
   int position_closes = CloseAllManagedPositionsCurrentSymbol();

   if(pending_removed == 0 && position_closes == 0)
   {
      SetPanelMessage("No managed trades/orders on " + _Symbol,clrGold);
      return(false);
   }

   SetPanelMessage("Close All sent: " +
                   IntegerToString(position_closes) + " positions, " +
                   IntegerToString(pending_removed) + " pending",clrLimeGreen);

   LogInfo("CLOSE",
           "CLOSE ALL " + _Symbol +
           " position requests=" + IntegerToString(position_closes) +
           " pending delete requests=" + IntegerToString(pending_removed));

   return(true);
}

#endif