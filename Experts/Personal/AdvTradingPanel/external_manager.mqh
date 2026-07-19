#ifndef ADVTP_EXTERNAL_MANAGER_MQH
#define ADVTP_EXTERNAL_MANAGER_MQH

bool IsTicketManaged(const ulong ticket)
{
   for(int i=0; i<ArraySize(g_TradeStates); i++)
   {
      if(g_TradeStates[i].ticket == ticket)
         return(true);
   }

   return(false);
}

bool IsExternalCandidate(const ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return(false);

   string symbol = PositionGetString(POSITION_SYMBOL);
   long magic = PositionGetInteger(POSITION_MAGIC);

   if(symbol != _Symbol)
      return(false);

   if((ulong)magic == InpMagicNumber)
      return(false);

   return(true);
}

void RefreshDetectedExternals()
{
   ArrayResize(g_DetectedExternalTickets,0);

   if(!InpMonitorExternal)
   {
      g_SelectedExternalTicket = 0;
      g_SelectedExternalIndex = -1;
      return;
   }

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(!IsExternalCandidate(ticket))
         continue;

      if(IsTicketManaged(ticket))
         continue;

      int size = ArraySize(g_DetectedExternalTickets);
      ArrayResize(g_DetectedExternalTickets,size+1);
      g_DetectedExternalTickets[size] = ticket;
   }

   g_SelectedExternalIndex = -1;

   if(g_SelectedExternalTicket != 0)
   {
      for(int j=0; j<ArraySize(g_DetectedExternalTickets); j++)
      {
         if(g_DetectedExternalTickets[j] == g_SelectedExternalTicket)
         {
            g_SelectedExternalIndex = j;
            break;
         }
      }
   }

   if(g_SelectedExternalIndex < 0)
   {
      if(ArraySize(g_DetectedExternalTickets) > 0)
      {
         g_SelectedExternalIndex = 0;
         g_SelectedExternalTicket = g_DetectedExternalTickets[0];
      }
      else
      {
         g_SelectedExternalTicket = 0;
      }
   }
}

string GetExternalStatusText()
{
   int count = ArraySize(g_DetectedExternalTickets);

   if(!InpMonitorExternal)
      return("External monitor: OFF");

   if(count <= 0)
      return("External: none");

   return("External: " + IntegerToString(count) +
          " | SEL #" + (string)g_SelectedExternalTicket);
}

void MaybeAlertExternal()
{
   if(!InpExternalAlerts)
      return;

   int count = ArraySize(g_DetectedExternalTickets);

   if(count <= 0)
   {
      g_LastExternalAlertKey = "";
      return;
   }

   string key = "";

   for(int i=0; i<count; i++)
      key += (string)g_DetectedExternalTickets[i] + ",";

   if(key == g_LastExternalAlertKey)
      return;

   g_LastExternalAlertKey = key;

   string msg = APP_SHORT_NAME + ": external trade(s) detected on " + _Symbol +
                " count=" + IntegerToString(count);

   LogInfo("EXTERNAL",msg);
   Alert(msg);
   SetPanelMessage("External trade detected",clrGold);
}

bool ApplyDefaultStopsIfNeeded(const ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return(false);

   string symbol = PositionGetString(POSITION_SYMBOL);
   long type = PositionGetInteger(POSITION_TYPE);
   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl = PositionGetDouble(POSITION_SL);
   double tp = PositionGetDouble(POSITION_TP);

   bool need_sl = (sl <= 0.0);
   bool need_tp = (tp <= 0.0);

   if(InpOverwriteExternalSLTP)
   {
      need_sl = true;
      need_tp = true;
   }

   if(!need_sl && !need_tp)
      return(true);

   if(!InpAutoApplyDefaultSLTP && !InpOverwriteExternalSLTP)
      return(true);

   ENUM_ORDER_TYPE order_type = (type == POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   double new_sl = sl;
   double new_tp = tp;

   if(need_sl)
      new_sl = GetSLPrice(order_type,entry,InpDefaultSLPoints);

   if(need_tp)
      new_tp = GetTPPrice(order_type,entry,InpDefaultTPPoints);

   string reason;

   if(!ValidateStops(symbol,order_type,entry,new_sl,new_tp,reason))
   {
      LogError("EXTERNAL","Cannot apply default SL/TP: " + reason);
      return(false);
   }

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.symbol = symbol;
   request.sl = new_sl;
   request.tp = new_tp;
   request.magic = InpMagicNumber;

   ResetLastError();

   bool sent = OrderSend(request,result);

   LogInfo("EXTERNAL",
           "Apply SL/TP ticket #" + (string)ticket +
           " sent=" + (sent ? "true" : "false") +
           " retcode=" + IntegerToString((int)result.retcode) +
           " comment=" + result.comment);

   return(sent && IsTradeRetcodeSuccessful(result.retcode));
}

bool AdoptExternalTicket(const ulong ticket,const string source)
{
   if(ticket == 0 || !PositionSelectByTicket(ticket))
   {
      SetPanelMessage("External ticket missing",clrTomato);
      return(false);
   }

   if(IsTicketManaged(ticket))
   {
      SetPanelMessage("Ticket already managed",clrGold);
      return(false);
   }

   if(!IsExternalCandidate(ticket))
   {
      SetPanelMessage("Ticket is not an external candidate",clrTomato);
      return(false);
   }

   ApplyDefaultStopsIfNeeded(ticket);

   if(!PositionSelectByTicket(ticket))
      return(false);

   TradeState state;
   ZeroMemory(state);

   state.ticket = ticket;
   state.symbol = PositionGetString(POSITION_SYMBOL);
   state.position_type = PositionGetInteger(POSITION_TYPE);
   state.current_volume = PositionGetDouble(POSITION_VOLUME);
   state.original_volume = state.current_volume;
   state.entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
   state.stop_loss = PositionGetDouble(POSITION_SL);
   state.take_profit = PositionGetDouble(POSITION_TP);
   state.open_time = (datetime)PositionGetInteger(POSITION_TIME);
   state.is_external = true;
   state.is_adopted = true;
   state.recovered_from_storage = false;
   state.be_applied = false;
   state.pending_be_price = 0.0;
   state.trailing_stop_active = false;
   state.pending_trailing_stop_price = 0.0;
   state.pending_action = ATP_ACTION_NONE;
   state.pending_partial_index = -1;
   state.pending_volume_before = 0.0;
   state.pending_expected_close = 0.0;

   TradeState stored;
   ZeroMemory(stored);

   if(LoadPersistedTradeState(ticket,stored))
   {
      if(stored.original_volume > 0.0)
         state.original_volume = stored.original_volume;

      state.partial_count = stored.partial_count;
      state.be_applied = stored.be_applied;
      ArrayResize(state.partial_done,stored.partial_count);
      ArrayResize(state.partial_prices,stored.partial_count);

      for(int i=0; i<stored.partial_count; i++)
      {
         state.partial_done[i] = stored.partial_done[i];
         state.partial_prices[i] = stored.partial_prices[i];
      }

      state.recovered_from_storage = true;
   }
   else
   {
      state.partial_count = MathMax(1,MathMin(5,g_PlanPartialCount));

      // Option A: if no TP yet, still keep count; rebuild after default SL/TP apply
      if(state.take_profit <= 0.0)
      {
         // try once more from broker after defaults
         if(PositionSelectByTicket(ticket))
            state.take_profit = PositionGetDouble(POSITION_TP);
      }
      
      if(state.take_profit <= 0.0)
      {
         state.partial_count = 0;
         ArrayResize(state.partial_done,0);
         ArrayResize(state.partial_prices,0);
         LogInfo("EXTERNAL","Ticket #" + (string)ticket + " adopted without TP; partials disabled until TP exists");
      }
      else
      {
         BuildPartialPlanFromEntryTP(state);
         LogInfo("EXTERNAL","Ticket #" + (string)ticket +
                 " partials=" + IntegerToString(state.partial_count) +
                 " TP=" + DoubleToString(state.take_profit,_Digits));
      }
   }

   int size = ArraySize(g_TradeStates);
   ArrayResize(g_TradeStates,size+1);
   g_TradeStates[size] = state;
   
   PersistTradeState(size);
   JournalAdoption(size,source);
   RefreshManagedTradeFlags();
   
   g_SelectedTicket = ticket;
   RefreshSelectedTicket();
   EnsureSelectedTicket();
   
   // Force partial plan if TP exists but prices missing
   if(g_TradeStates[size].partial_count > 0)
   {
      bool missing = false;
      for(int p=0; p<g_TradeStates[size].partial_count; p++)
      {
         if(p >= ArraySize(g_TradeStates[size].partial_prices) ||
            g_TradeStates[size].partial_prices[p] <= 0.0)
         {
            missing = true;
            break;
         }
      }
      if(missing)
         BuildPartialPlanFromEntryTP(g_TradeStates[size]);
   }
   
   DrawManagedPositionVisuals(size);
   RefreshAllManagedPositionVisuals();
   g_PanelDirty = true;
   g_RegistryDirty = false;

   LogInfo("EXTERNAL","Adopted ticket #" + (string)ticket + " source=" + source);
   SetPanelMessage("Adopted external #" + (string)ticket,clrLimeGreen);
   return(true);
}

void AutoAdoptDetectedExternals()
{
   if(!InpAutoAdoptExternal)
      return;

   for(int i=0; i<ArraySize(g_DetectedExternalTickets); i++)
      AdoptExternalTicket(g_DetectedExternalTickets[i],"AUTO");
}

bool AdoptSelectedExternal()
{
   RefreshDetectedExternals();

   if(g_SelectedExternalTicket == 0)
   {
      SetPanelMessage("No external trade selected",clrTomato);
      return(false);
   }

   return(AdoptExternalTicket(g_SelectedExternalTicket,"MANUAL"));
}

void SelectRelativeExternal(const int direction)
{
   RefreshDetectedExternals();

   int total = ArraySize(g_DetectedExternalTickets);

   if(total <= 0)
   {
      g_SelectedExternalTicket = 0;
      g_SelectedExternalIndex = -1;
      g_PanelDirty = true;
      return;
   }

   int next = g_SelectedExternalIndex + direction;

   if(next < 0)
      next = total - 1;

   if(next >= total)
      next = 0;

   g_SelectedExternalIndex = next;
   g_SelectedExternalTicket = g_DetectedExternalTickets[next];
   g_PanelDirty = true;
}

void ProcessExternalMonitoring()
{
   if(!InpMonitorExternal)
      return;

   RefreshDetectedExternals();
   MaybeAlertExternal();
   AutoAdoptDetectedExternals();
}

#endif