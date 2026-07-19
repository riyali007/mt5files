#ifndef ADVTP_PARTIAL_MANAGER_MQH
#define ADVTP_PARTIAL_MANAGER_MQH

bool IsPartialTriggerReached(const TradeState &state,const double target_price)
{
   if(state.position_type == POSITION_TYPE_BUY)
      return(g_Bid >= target_price);

   if(state.position_type == POSITION_TYPE_SELL)
      return(g_Ask <= target_price);

   return(false);
}

double GetPartialRequestedVolume(const TradeState &state,const int partial_index)
{
   double percent = (partial_index == 0 ? InpFirstPartialPercent : InpSubsequentPartialPercent);
   return(state.original_volume * percent / 100.0);
}

double GetSafePartialCloseVolume(const TradeState &state,const int partial_index)
{
   if(partial_index < 0 || partial_index >= state.partial_count)
      return(0.0);

   double requested = GetPartialRequestedVolume(state,partial_index);
   double normalized = NormalizeVolumeDown(state.symbol,requested);

   double min_volume = SymbolInfoDouble(state.symbol,SYMBOL_VOLUME_MIN);
   double remaining_after = state.current_volume - normalized;

   if(normalized <= 0.0)
      return(0.0);

   if(remaining_after < min_volume)
   {
      normalized = NormalizeVolumeDown(state.symbol,state.current_volume - min_volume);

      if(normalized <= 0.0)
         return(0.0);
   }

   return(normalized);
}

bool SendPartialCloseRequest(const ulong ticket,const double volume,const string reason)
{
   if(ticket == 0 || volume <= 0.0)
      return(false);

   if(!PositionSelectByTicket(ticket))
   {
      LogError("PARTIAL","Ticket #" + (string)ticket + " no longer exists");
      return(false);
   }

   string symbol = PositionGetString(POSITION_SYMBOL);
   long position_type = PositionGetInteger(POSITION_TYPE);

   MqlTick tick;
   if(!SymbolInfoTick(symbol,tick))
   {
      LogError("PARTIAL","No tick available for " + symbol);
      return(false);
   }

   MqlTradeRequest request;
   MqlTradeResult result;

   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_DEAL;
   request.position = ticket;
   request.magic = InpMagicNumber;
   request.symbol = symbol;
   request.volume = volume;
   request.deviation = InpDeviationPoints;
   request.type = (position_type == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
   request.price = 0.0;
   request.type_filling = GetSymbolFillingType(symbol);
   request.comment = APP_SHORT_NAME + "_Partial_" + reason;

   ResetLastError();

   bool sent = OrderSend(request,result);
   int terminal_error = GetLastError();

   LogInfo("PARTIAL",
           "Ticket #" + (string)ticket +
           " request=" + DoubleToString(volume,2) +
           " sent=" + (sent ? "true" : "false") +
           " terminal_error=" + IntegerToString(terminal_error) +
           " retcode=" + IntegerToString((int)result.retcode) +
           " comment=" + result.comment);

   if(!sent || !IsTradeRetcodeSuccessful(result.retcode))
   {
      LogError("PARTIAL",
               "Ticket #" + (string)ticket +
               " rejected. Retcode=" + IntegerToString((int)result.retcode) +
               " comment=" + result.comment);
      return(false);
   }

   return(true);
}

void EvaluateTicketPartials(const int index)
{
   if(index < 0 || index >= ArraySize(g_TradeStates))
      return;

   if(!g_HasManagedTrades)
      return;

   TradeState state = g_TradeStates[index];

   if(state.pending_action != ATP_ACTION_NONE)
      return;

   if(!PositionSelectByTicket(state.ticket))
      return;

   state.current_volume = PositionGetDouble(POSITION_VOLUME);
   g_TradeStates[index].current_volume = state.current_volume;

   for(int partial_index=0; partial_index<state.partial_count; partial_index++)
   {
      if(state.partial_done[partial_index])
         continue;

      if(partial_index >= ArraySize(state.partial_prices))
         continue;

      double target_price = state.partial_prices[partial_index];

      if(!IsPartialTriggerReached(state,target_price))
         continue;

      double close_volume = GetSafePartialCloseVolume(state,partial_index);

      if(close_volume <= 0.0)
      {
         LogError("PARTIAL",
                  "Ticket #" + (string)state.ticket +
                  " TP" + IntegerToString(partial_index+1) +
                  " skipped: invalid close volume");
         return;
      }

      g_TradeStates[index].pending_action = ATP_ACTION_PARTIAL_PENDING;
      g_TradeStates[index].pending_partial_index = partial_index;
      g_TradeStates[index].pending_volume_before = state.current_volume;
      g_TradeStates[index].pending_expected_close = close_volume;

      if(!SendPartialCloseRequest(state.ticket,close_volume,"TP"+IntegerToString(partial_index+1)))
      {
         g_TradeStates[index].pending_action = ATP_ACTION_NONE;
         g_TradeStates[index].pending_partial_index = -1;
         g_TradeStates[index].pending_volume_before = 0.0;
         g_TradeStates[index].pending_expected_close = 0.0;
      }

      return;
   }
}

void EvaluateAllPartials()
{
   if(!g_HasManagedTrades)
      return;

   for(int i=0; i<ArraySize(g_TradeStates); i++)
      EvaluateTicketPartials(i);
}

void ConfirmPendingPartialActions()
{
   for(int i=ArraySize(g_TradeStates)-1; i>=0; i--)
   {
      if(g_TradeStates[i].pending_action != ATP_ACTION_PARTIAL_PENDING)
         continue;

      ulong ticket = g_TradeStates[i].ticket;

      if(!PositionSelectByTicket(ticket))
      {
         LogInfo("PARTIAL","Ticket #" + (string)ticket + " closed while partial request was pending");
         g_TradeStates[i].pending_action = ATP_ACTION_NONE;
         continue;
      }

      double current_volume = PositionGetDouble(POSITION_VOLUME);
      double previous_volume = g_TradeStates[i].pending_volume_before;
      double expected_close = g_TradeStates[i].pending_expected_close;
      double tolerance = SymbolInfoDouble(g_TradeStates[i].symbol,SYMBOL_VOLUME_STEP) / 2.0;

      if(current_volume < previous_volume - tolerance)
      {
         int partial_index = g_TradeStates[i].pending_partial_index;

         if(partial_index >= 0 && partial_index < g_TradeStates[i].partial_count)
            g_TradeStates[i].partial_done[partial_index] = true;

         g_TradeStates[i].current_volume = current_volume;
         g_TradeStates[i].pending_action = ATP_ACTION_NONE;
         g_TradeStates[i].pending_partial_index = -1;
         g_TradeStates[i].pending_volume_before = 0.0;
         g_TradeStates[i].pending_expected_close = 0.0;

         LogInfo("PARTIAL",
                 "Ticket #" + (string)ticket +
                 " TP" + IntegerToString(partial_index+1) +
                 " confirmed. Closed=" + DoubleToString(previous_volume-current_volume,2) +
                 " expected=" + DoubleToString(expected_close,2) +
                 " remaining=" + DoubleToString(current_volume,2));

         g_PanelDirty = true;
         PersistTradeState(i);
         
         if(partial_index >= 0)
            JournalPartialConfirmed(i,partial_index,previous_volume-current_volume,current_volume);
         else
            JournalManagedTradeEvent(i,
                                     "PARTIAL",
                                     "Manual partial closed=" + DoubleToString(previous_volume-current_volume,2) +
                                     " remaining=" + DoubleToString(current_volume,2),
                                     "MANUAL",
                                     previous_volume-current_volume);
      }
   }
}

#endif