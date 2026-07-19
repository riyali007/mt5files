#ifndef ADVTP_STATE_REGISTRY_MQH
#define ADVTP_STATE_REGISTRY_MQH

void ConfirmPendingPartialActions();
void ConfirmPendingBEActions();
void RefreshAllManagedPositionVisuals();
void DeletePositionVisuals(const ulong ticket);
void EnsureSelectedTicket();
void PersistTradeState(const int index);
void DeletePersistedTradeState(const ulong ticket);
bool LoadPersistedTradeState(const ulong ticket,TradeState &state);
void BuildPartialPlanFromEntryTP(TradeState &state);
void ProcessExternalMonitoring();
void ConfirmPendingTrailingStopActions();
void EvaluateAllTrailingStops();
void JournalPartialConfirmed(const int index,const int partial_index,const double closed_volume,const double remaining_volume);
void JournalBreakevenConfirmed(const int index,const double be_price);
void JournalTrailingStopConfirmed(const int index,const double trail_price);
void JournalAdoption(const int index,const string source);
void JournalPositionOpenIfPossible(const ulong ticket,const string source);
void JournalCloseEvent(const ulong ticket,const string symbol,const string side,const double volume,const double price,const double profit,const string note,const string source);
void JournalManagedTradeEvent(const int index,const string event_name,const string note,const string source,const double volume_override = -1.0,const double price_override = -1.0,const double profit_override = 0.0);


void InitializeRuntimeState()
{
   ArrayResize(g_TradeStates,0);
   g_HasManagedTrades = false;
   g_PanelDirty = true;
   g_RegistryDirty = false;
   g_Bid = 0.0;
   g_Ask = 0.0;
}

int FindTradeStateIndex(const ulong ticket)
{
   for(int i=0; i<ArraySize(g_TradeStates); i++)
      if(g_TradeStates[i].ticket == ticket)
         return(i);

   return(-1);
}

bool RegisterManagedPosition(const ulong ticket)
{
   if(ticket == 0 || !PositionSelectByTicket(ticket))
      return(false);

   if(IsTicketManaged(ticket))
      return(true);

   string symbol = PositionGetString(POSITION_SYMBOL);
   long magic = PositionGetInteger(POSITION_MAGIC);

   if(symbol != _Symbol || (ulong)magic != InpMagicNumber)
      return(false);

   TradeState state;
   ZeroMemory(state);

   state.ticket = ticket;
   state.symbol = symbol;
   state.position_type = PositionGetInteger(POSITION_TYPE);
   state.current_volume = PositionGetDouble(POSITION_VOLUME);
   state.entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
   state.stop_loss = PositionGetDouble(POSITION_SL);
   state.take_profit = PositionGetDouble(POSITION_TP);
   state.open_time = (datetime)PositionGetInteger(POSITION_TIME);
   state.is_external = false;
   state.is_adopted = false;
   state.recovered_from_storage = false;
   state.pending_action = ATP_ACTION_NONE;
   state.pending_partial_index = -1;
   state.pending_volume_before = 0.0;
   state.pending_expected_close = 0.0;
   state.pending_be_price = 0.0;
   state.trailing_stop_active = false;
   state.pending_trailing_stop_price = 0.0;
   state.be_applied = false;

   TradeState stored;
   ZeroMemory(stored);

   if(InpRestoreManagedTradesOnInit && LoadPersistedTradeState(ticket,stored))
   {
      state.original_volume = (stored.original_volume > 0.0 ? stored.original_volume : state.current_volume);
      state.partial_count = stored.partial_count;
      state.be_applied = stored.be_applied;
      state.is_external = stored.is_external;
      state.is_adopted = stored.is_adopted;
      state.recovered_from_storage = true;

      ArrayResize(state.partial_done,state.partial_count);
      ArrayResize(state.partial_prices,state.partial_count);

      bool prices_ok = true;

      for(int i=0; i<state.partial_count; i++)
      {
         state.partial_done[i] = stored.partial_done[i];
         state.partial_prices[i] = stored.partial_prices[i];

         if(state.partial_prices[i] <= 0.0)
            prices_ok = false;
      }

      if(!prices_ok)
         BuildPartialPlanFromEntryTP(state);
   }
   else
   {
      state.original_volume = state.current_volume;
      state.partial_count = MathMax(1,MathMin(5,g_PlanPartialCount));

      if(state.take_profit <= 0.0)
         state.partial_count = 0;

      BuildPartialPlanFromEntryTP(state);
   }

   int size = ArraySize(g_TradeStates);
   ArrayResize(g_TradeStates,size+1);
   g_TradeStates[size] = state;
   PersistTradeState(size);
   
   if(!state.recovered_from_storage)
      JournalPositionOpenIfPossible(ticket,"REGISTER");

   LogInfo("REGISTRY","Registered #" + (string)ticket +
           (state.recovered_from_storage ? " [restored]" : " [new]"));

   return(true);
}

void RemoveTradeStateAt(const int index)
{
   int total = ArraySize(g_TradeStates);
   if(index < 0 || index >= total)
      return;

   ulong ticket = g_TradeStates[index].ticket;

   for(int i=index; i<total-1; i++)
      g_TradeStates[i] = g_TradeStates[i+1];
   
   string close_side = "UNKNOWN";
   string close_symbol = _Symbol;
   double close_volume = 0.0;
   double close_price = 0.0;
   
   for(int rs=0; rs<ArraySize(g_TradeStates); rs++)
   {
      if(g_TradeStates[rs].ticket != ticket)
         continue;
   
      close_side = (g_TradeStates[rs].position_type == POSITION_TYPE_BUY ? "BUY" : "SELL");
      close_symbol = g_TradeStates[rs].symbol;
      close_volume = g_TradeStates[rs].current_volume;
      close_price = g_TradeStates[rs].entry_price;
      break;
   }
   
   JournalCloseEvent(ticket,
                     close_symbol,
                     close_side,
                     close_volume,
                     close_price,
                     0.0,
                     "Position removed from management",
                     "RECONCILE");
   
   DeletePersistedTradeState(ticket);
   DeletePositionVisuals(ticket);
   
   ArrayResize(g_TradeStates,total-1);
   g_PanelDirty = true;

   LogInfo("REGISTRY", "Removed ticket #" + (string)ticket);
}

void RefreshTradeStateFromBroker(const int index)
{
   if(index < 0 || index >= ArraySize(g_TradeStates))
      return;

   ulong ticket = g_TradeStates[index].ticket;

   if(!PositionSelectByTicket(ticket))
   {
      RemoveTradeStateAt(index);
      return;
   }

   g_TradeStates[index].current_volume = PositionGetDouble(POSITION_VOLUME);
   g_TradeStates[index].stop_loss = PositionGetDouble(POSITION_SL);
   g_TradeStates[index].take_profit = PositionGetDouble(POSITION_TP);
   g_TradeStates[index].position_type = PositionGetInteger(POSITION_TYPE);
}

void ReconcileManagedPositions(const string source)
{
   // 1) Snapshot currently managed adopted/external tickets so magic-mismatch does not drop them
   ulong keep_adopted[];
   ArrayResize(keep_adopted,0);

   for(int i=0; i<ArraySize(g_TradeStates); i++)
   {
      if(g_TradeStates[i].is_adopted || g_TradeStates[i].is_external)
      {
         int n = ArraySize(keep_adopted);
         ArrayResize(keep_adopted,n+1);
         keep_adopted[n] = g_TradeStates[i].ticket;
      }
   }

   // 2) Remove managed entries whose broker position is gone
   for(int i=ArraySize(g_TradeStates)-1; i>=0; i--)
   {
      ulong ticket = g_TradeStates[i].ticket;

      if(!PositionSelectByTicket(ticket))
      {
         DeletePersistedTradeState(ticket);
         DeletePositionVisuals(ticket);
         // remove array slot (use your existing RemoveTradeStateAt if present)
         for(int j=i; j<ArraySize(g_TradeStates)-1; j++)
            g_TradeStates[j] = g_TradeStates[j+1];
         ArrayResize(g_TradeStates,ArraySize(g_TradeStates)-1);
      }
   }

   // 3) Register EA-magic positions on current symbol
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      long magic = PositionGetInteger(POSITION_MAGIC);

      if(symbol != _Symbol)
         continue;

      if((ulong)magic == InpMagicNumber)
         RegisterManagedPosition(ticket);
   }

   // 4) Re-adopt/keep external managed tickets that still exist
   for(int k=0; k<ArraySize(keep_adopted); k++)
   {
      ulong ticket = keep_adopted[k];

      if(!PositionSelectByTicket(ticket))
         continue;

      if(IsTicketManaged(ticket))
      {
         // refresh live fields only
         for(int m=0; m<ArraySize(g_TradeStates); m++)
         {
            if(g_TradeStates[m].ticket != ticket)
               continue;

            g_TradeStates[m].current_volume = PositionGetDouble(POSITION_VOLUME);
            g_TradeStates[m].stop_loss = PositionGetDouble(POSITION_SL);
            g_TradeStates[m].take_profit = PositionGetDouble(POSITION_TP);
            g_TradeStates[m].position_type = PositionGetInteger(POSITION_TYPE);
            g_TradeStates[m].entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
            
            break;
         }
         continue;
      }

      // Was managed as external, still open, but dropped — restore adoption
      AdoptExternalTicket(ticket,"RECONCILE_RESTORE");
   }

   RefreshManagedTradeFlags();
   EnsureSelectedTicket();
   ProcessExternalMonitoring();

   if(source == "OnInit" || source == "OnTradeTransaction")
      LogDebug("REGISTRY","Reconciled from " + source + ". Managed=" + IntegerToString(ArraySize(g_TradeStates)));
}

void RefreshManagedTradeFlags()
{
   g_HasManagedTrades = (ArraySize(g_TradeStates) > 0);
}

void HandleTradeTransaction(const MqlTradeTransaction &trans,
                            const MqlTradeRequest &request,
                            const MqlTradeResult &result)
{
   g_RegistryDirty = true;
   g_PanelDirty = true;

   LogDebug("TX", "type=" + IntegerToString((int)trans.type) +
            " deal=" + (string)trans.deal +
            " position=" + (string)trans.position +
            " order=" + (string)trans.order);

   ReconcileManagedPositions("OnTradeTransaction");
   RefreshAllManagedPositionVisuals();
   ConfirmPendingPartialActions();
   ConfirmPendingBEActions();
   ConfirmPendingTrailingStopActions();
   ConfirmPendingCloseActions();
   ProcessExternalMonitoring();
}
void ConfirmPendingCloseActions()
{
   for(int i=ArraySize(g_TradeStates)-1; i>=0; i--)
   {
      if(g_TradeStates[i].pending_action != ATP_ACTION_CLOSE_PENDING)
         continue;

      ulong ticket = g_TradeStates[i].ticket;

      // Position still open -> close not finished
      if(PositionSelectByTicket(ticket))
         continue;

      string side = (g_TradeStates[i].position_type == POSITION_TYPE_BUY ? "BUY" : "SELL");
      string symbol = g_TradeStates[i].symbol;
      double volume = g_TradeStates[i].current_volume;
      double price = g_TradeStates[i].entry_price;

      JournalCloseEvent(ticket,
                        symbol,
                        side,
                        volume,
                        price,
                        0.0,
                        "Position fully closed",
                        "CLOSE_CONFIRM");

      DeletePersistedTradeState(ticket);
      DeletePositionVisuals(ticket);

      // remove state slot
      for(int j=i; j<ArraySize(g_TradeStates)-1; j++)
         g_TradeStates[j] = g_TradeStates[j+1];
      ArrayResize(g_TradeStates,ArraySize(g_TradeStates)-1);

      g_PanelDirty = true;

      LogInfo("CLOSE","Ticket #" + (string)ticket + " close confirmed and journaled");
   }

   RefreshManagedTradeFlags();
   EnsureSelectedTicket();
}
#endif