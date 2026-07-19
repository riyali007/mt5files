#ifndef ADVTP_TRAILING_STOP_MANAGER_MQH
#define ADVTP_TRAILING_STOP_MANAGER_MQH

bool IsTrailingStopConfigurationValid()
{
   if(!InpEnableTrailingStop)
      return(false);

   if(InpTrailingStopStartPoints <= 0)
   {
      LogError("TRAIL","Trailing start points must be greater than zero");
      return(false);
   }

   if(InpTrailingStopDistancePoints <= 0)
   {
      LogError("TRAIL","Trailing distance points must be greater than zero");
      return(false);
   }

   if(InpTrailingStopStepPoints <= 0)
   {
      LogError("TRAIL","Trailing step points must be greater than zero");
      return(false);
   }

   return(true);
}

bool IsTrailingStopCandidateValid(const TradeState &state,
                                  const double proposed_sl,
                                  string &reason)
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
   double minimum_distance = MathMax(stops_level_points,freeze_level_points) * _Point;

   if(state.position_type == POSITION_TYPE_BUY)
   {
      if(proposed_sl >= tick.bid)
      {
         reason = "Candidate SL is at/above Bid";
         return(false);
      }

      if(minimum_distance > 0.0 && (tick.bid - proposed_sl) < minimum_distance)
      {
         reason = "Candidate SL inside broker stop/freeze distance";
         return(false);
      }

      return(true);
   }

   if(state.position_type == POSITION_TYPE_SELL)
   {
      if(proposed_sl <= tick.ask)
      {
         reason = "Candidate SL is at/below Ask";
         return(false);
      }

      if(minimum_distance > 0.0 && (proposed_sl - tick.ask) < minimum_distance)
      {
         reason = "Candidate SL inside broker stop/freeze distance";
         return(false);
      }

      return(true);
   }

   reason = "Unsupported position direction";
   return(false);
}

bool IsTrailingStopImprovement(const TradeState &state,
                               const double proposed_sl)
{
   double minimum_step = InpTrailingStopStepPoints * _Point;

   if(state.position_type == POSITION_TYPE_BUY)
   {
      if(state.stop_loss <= 0.0)
         return(true);

      return(proposed_sl >= state.stop_loss + minimum_step);
   }

   if(state.position_type == POSITION_TYPE_SELL)
   {
      if(state.stop_loss <= 0.0)
         return(true);

      return(proposed_sl <= state.stop_loss - minimum_step);
   }

   return(false);
}

bool SendTrailingStopRequest(const int index,const double new_sl)
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

   if(!IsTrailingStopImprovement(state,new_sl))
      return(false);

   string reason;

   if(!IsTrailingStopCandidateValid(state,new_sl,reason))
   {
      LogDebug("TRAIL",
               "Ticket #" + (string)state.ticket +
               " waiting: " + reason);
      return(false);
   }

   MqlTradeRequest request;
   MqlTradeResult result;

   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_SLTP;
   request.position = state.ticket;
   request.symbol = state.symbol;
   request.sl = new_sl;
   request.tp = state.take_profit;
   request.magic = InpMagicNumber;

   ResetLastError();

   bool sent = OrderSend(request,result);
   int terminal_error = GetLastError();

   LogInfo("TRAIL",
           "Ticket #" + (string)state.ticket +
           " target=" + DoubleToString(new_sl,_Digits) +
           " sent=" + (sent ? "true" : "false") +
           " terminal_error=" + IntegerToString(terminal_error) +
           " retcode=" + IntegerToString((int)result.retcode) +
           " comment=" + result.comment);

   if(!sent || !IsTradeRetcodeSuccessful(result.retcode))
   {
      LogError("TRAIL",
               "Ticket #" + (string)state.ticket +
               " rejected. Retcode=" + IntegerToString((int)result.retcode) +
               " comment=" + result.comment);

      return(false);
   }

   g_TradeStates[index].pending_action = ATP_ACTION_TRAILING_STOP_PENDING;
   g_TradeStates[index].pending_trailing_stop_price = new_sl;
   return(true);
}

void EvaluateTrailingStopForTicket(const int index)
{
   if(index < 0 || index >= ArraySize(g_TradeStates))
      return;

   if(!InpEnableTrailingStop)
      return;

   if(g_TradeStates[index].pending_action != ATP_ACTION_NONE)
      return;

   if(!PositionSelectByTicket(g_TradeStates[index].ticket))
      return;

   TradeState state = g_TradeStates[index];

   state.current_volume = PositionGetDouble(POSITION_VOLUME);
   state.entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
   state.stop_loss = PositionGetDouble(POSITION_SL);
   state.take_profit = PositionGetDouble(POSITION_TP);
   state.position_type = PositionGetInteger(POSITION_TYPE);

   g_TradeStates[index].current_volume = state.current_volume;
   g_TradeStates[index].entry_price = state.entry_price;
   g_TradeStates[index].stop_loss = state.stop_loss;
   g_TradeStates[index].take_profit = state.take_profit;
   g_TradeStates[index].position_type = state.position_type;

   MqlTick tick;

   if(!SymbolInfoTick(state.symbol,tick))
      return;

   double start_distance = InpTrailingStopStartPoints * _Point;
   double trail_distance = InpTrailingStopDistancePoints * _Point;
   double candidate_sl = 0.0;
   bool activated = false;

   if(state.position_type == POSITION_TYPE_BUY)
   {
      activated = (tick.bid >= state.entry_price + start_distance);

      if(activated)
         candidate_sl = NormalizeDouble(tick.bid - trail_distance,_Digits);
   }
   else if(state.position_type == POSITION_TYPE_SELL)
   {
      activated = (tick.ask <= state.entry_price - start_distance);

      if(activated)
         candidate_sl = NormalizeDouble(tick.ask + trail_distance,_Digits);
   }

   if(!activated)
      return;

   g_TradeStates[index].trailing_stop_active = true;

   if(candidate_sl <= 0.0)
      return;

   SendTrailingStopRequest(index,candidate_sl);
}

void EvaluateAllTrailingStops()
{
   if(!IsTrailingStopConfigurationValid())
      return;

   if(!g_HasManagedTrades)
      return;

   for(int i=0; i<ArraySize(g_TradeStates); i++)
      EvaluateTrailingStopForTicket(i);
}

void ConfirmPendingTrailingStopActions()
{
   for(int i=0; i<ArraySize(g_TradeStates); i++)
   {
      if(g_TradeStates[i].pending_action != ATP_ACTION_TRAILING_STOP_PENDING)
         continue;

      ulong ticket = g_TradeStates[i].ticket;

      if(!PositionSelectByTicket(ticket))
         continue;

      double actual_sl = PositionGetDouble(POSITION_SL);
      double target_sl = g_TradeStates[i].pending_trailing_stop_price;
      double tolerance = _Point * 0.5;

      if(MathAbs(actual_sl-target_sl) <= tolerance)
      {
         g_TradeStates[i].stop_loss = actual_sl;
         g_TradeStates[i].trailing_stop_active = true;
         g_TradeStates[i].pending_action = ATP_ACTION_NONE;
         g_TradeStates[i].pending_trailing_stop_price = 0.0;
         g_PanelDirty = true;
         
         PersistTradeState(i);
         JournalTrailingStopConfirmed(i,actual_sl);
         
         LogInfo("TRAIL",
                 "Ticket #" + (string)ticket +
                 " confirmed at " + DoubleToString(actual_sl,_Digits));
      }
   }
}

#endif