#ifndef ADVTP_BREAKEVEN_MANAGER_MQH
#define ADVTP_BREAKEVEN_MANAGER_MQH

double GetStrictBEPrice(const TradeState &state)
{
   double offset = InpBEOffsetPoints * _Point;

   if(state.position_type == POSITION_TYPE_BUY)
      return(NormalizeDouble(state.entry_price + offset,_Digits));

   return(NormalizeDouble(state.entry_price - offset,_Digits));
}

bool IsStopImprovement(const TradeState &state,const double proposed_sl)
{
   if(state.position_type == POSITION_TYPE_BUY)
   {
      if(state.stop_loss <= 0.0)
         return(true);

      return(proposed_sl > state.stop_loss + (_Point * 0.1));
   }

   if(state.stop_loss <= 0.0)
      return(true);

   return(proposed_sl < state.stop_loss - (_Point * 0.1));
}

bool IsStrictBEPriceCurrentlyValid(const TradeState &state,const double proposed_sl,string &reason)
{
   reason = "";

   MqlTick tick;

   if(!SymbolInfoTick(state.symbol,tick))
   {
      reason = "No live tick";
      return(false);
   }

   int stops_level_points = (int)SymbolInfoInteger(state.symbol,SYMBOL_TRADE_STOPS_LEVEL);
   int freeze_level_points = (int)SymbolInfoInteger(state.symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   double min_distance = MathMax(stops_level_points,freeze_level_points) * _Point;

   if(state.position_type == POSITION_TYPE_BUY)
   {
      if(proposed_sl >= tick.bid)
      {
         reason = "BE SL is at/above current Bid";
         return(false);
      }

      if(min_distance > 0.0 && (tick.bid - proposed_sl) < min_distance)
      {
         reason = "BE SL is inside broker stop/freeze distance";
         return(false);
      }

      return(true);
   }

   if(proposed_sl <= tick.ask)
   {
      reason = "BE SL is at/below current Ask";
      return(false);
   }

   if(min_distance > 0.0 && (proposed_sl - tick.ask) < min_distance)
   {
      reason = "BE SL is inside broker stop/freeze distance";
      return(false);
   }

   return(true);
}

bool SendBERequest(const int index,const string source)
{
   if(index < 0 || index >= ArraySize(g_TradeStates))
      return(false);

   TradeState state = g_TradeStates[index];

   if(state.pending_action != ATP_ACTION_NONE)
      return(false);

   if(!PositionSelectByTicket(state.ticket))
      return(false);

   state.stop_loss = PositionGetDouble(POSITION_SL);
   state.take_profit = PositionGetDouble(POSITION_TP);
   g_TradeStates[index].stop_loss = state.stop_loss;
   g_TradeStates[index].take_profit = state.take_profit;

   double be_price = GetStrictBEPrice(state);

   if(!IsStopImprovement(state,be_price))
   {
      g_TradeStates[index].be_applied = true;
      PersistTradeState(index);
      JournalBreakevenConfirmed(index,state.stop_loss);
   
      LogInfo("BE","Ticket #" + (string)state.ticket + " already protected at/better than BE");
      return(true);
   }

   string reason;

   if(!IsStrictBEPriceCurrentlyValid(state,be_price,reason))
   {
      LogDebug("BE","Ticket #" + (string)state.ticket + " waiting: " + reason);
      return(false);
   }

   MqlTradeRequest request;
   MqlTradeResult result;

   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_SLTP;
   request.position = state.ticket;
   request.symbol = state.symbol;
   request.sl = be_price;
   request.tp = state.take_profit;
   request.magic = InpMagicNumber;

   ResetLastError();

   bool sent = OrderSend(request,result);
   int terminal_error = GetLastError();

   LogInfo("BE",
           "Ticket #" + (string)state.ticket +
           " source=" + source +
           " target=" + DoubleToString(be_price,_Digits) +
           " sent=" + (sent ? "true" : "false") +
           " terminal_error=" + IntegerToString(terminal_error) +
           " retcode=" + IntegerToString((int)result.retcode) +
           " comment=" + result.comment);

   if(!sent || !IsTradeRetcodeSuccessful(result.retcode))
   {
      LogError("BE",
               "Ticket #" + (string)state.ticket +
               " rejected. Retcode=" + IntegerToString((int)result.retcode) +
               " comment=" + result.comment);
      return(false);
   }

   g_TradeStates[index].pending_action = ATP_ACTION_BE_PENDING;
   g_TradeStates[index].pending_be_price = be_price;
   return(true);
}

bool HasCompletedBETriggerPartial(const TradeState &state)
{
   if(InpBETriggerPartial <= 0)
      return(false);

   int trigger_index = InpBETriggerPartial - 1;

   if(trigger_index < 0 || trigger_index >= state.partial_count)
      return(false);

   return(state.partial_done[trigger_index]);
}

void EvaluateAutomaticBE()
{
   if(InpBETriggerPartial <= 0 || !g_HasManagedTrades)
      return;

   for(int i=0; i<ArraySize(g_TradeStates); i++)
   {
      if(g_TradeStates[i].be_applied)
         continue;

      if(g_TradeStates[i].pending_action != ATP_ACTION_NONE)
         continue;

      if(!HasCompletedBETriggerPartial(g_TradeStates[i]))
         continue;

      SendBERequest(i,"AUTO");
   }
}

void ConfirmPendingBEActions()
{
   for(int i=0; i<ArraySize(g_TradeStates); i++)
   {
      if(g_TradeStates[i].pending_action != ATP_ACTION_BE_PENDING)
         continue;

      ulong ticket = g_TradeStates[i].ticket;

      if(!PositionSelectByTicket(ticket))
         continue;

      double actual_sl = PositionGetDouble(POSITION_SL);
      double target_sl = g_TradeStates[i].pending_be_price;
      double tolerance = MathMax(_Point * 5.0, _Point * 0.5);
      
      bool confirmed = false;
      
      // Exact/near target match
      if(actual_sl > 0.0 && MathAbs(actual_sl - target_sl) <= tolerance)
         confirmed = true;
      
      // Broker may normalize slightly; still accept clear one-way improvement toward BE
      if(!confirmed && actual_sl > 0.0 && target_sl > 0.0)
      {
         if(g_TradeStates[i].position_type == POSITION_TYPE_BUY)
         {
            if(actual_sl >= target_sl - tolerance)
               confirmed = true;
         }
         else if(g_TradeStates[i].position_type == POSITION_TYPE_SELL)
         {
            if(actual_sl <= target_sl + tolerance)
               confirmed = true;
         }
      }
      
      if(confirmed)
      {
         g_TradeStates[i].stop_loss = actual_sl;
         g_TradeStates[i].be_applied = true;
         g_TradeStates[i].pending_action = ATP_ACTION_NONE;
         g_TradeStates[i].pending_be_price = 0.0;
         g_PanelDirty = true;
      
         PersistTradeState(i);
         JournalBreakevenConfirmed(i,actual_sl);
      
         LogInfo("BE",
                 "Ticket #" + (string)ticket +
                 " confirmed at " + DoubleToString(actual_sl,_Digits) +
                 " target=" + DoubleToString(target_sl,_Digits));
      }
      else
      {
         // Clear stale pending if broker moved SL elsewhere or rejected silently
         LogDebug("BE",
                  "Ticket #" + (string)ticket +
                  " pending BE not confirmed yet. actual=" + DoubleToString(actual_sl,_Digits) +
                  " target=" + DoubleToString(target_sl,_Digits));
      }
   }
}

#endif