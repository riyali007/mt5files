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
void SyncManagedStopsAndPartials();
void JournalSLTPUpdate(const int index,const double old_sl,const double old_tp,const double new_sl,const double new_tp);
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
   ArrayResize(g_DeferredBEJournals, 0);
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
      int max_parts = MathMax(1, InpMaxPartialCount);
      state.partial_count = MathMax(1, MathMin(max_parts, g_PlanPartialCount));

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

   // Capture journal fields BEFORE shifting the array out
   ulong  ticket       = g_TradeStates[index].ticket;
   string close_side   = (g_TradeStates[index].position_type == POSITION_TYPE_BUY ? "BUY" : "SELL");
   string close_symbol = g_TradeStates[index].symbol;
   double close_volume = g_TradeStates[index].current_volume;
   double close_price  = g_TradeStates[index].entry_price;
   double close_sl     = g_TradeStates[index].stop_loss;
   string close_note   = "Position closed";

   if(g_TradeStates[index].be_applied)
      close_note = "Position closed (BE/protected SL)";
   else if(close_sl > 0.0)
      close_note = "Position closed (SL/TP/broker)";

      // Snapshot full state for close sound classification
   TradeState close_state = g_TradeStates[index];

   MqlTick close_tick;
   double exit_price = close_state.entry_price;
   if(SymbolInfoTick(close_state.symbol,close_tick))
      exit_price = (close_state.position_type == POSITION_TYPE_BUY ? close_tick.bid : close_tick.ask);

   JournalCloseEvent(ticket,
                     close_symbol,
                     close_side,
                     close_volume,
                     close_price,
                     0.0,
                     close_note,
                     "ENGINE_CLOSE");
                     
   SoundOnManagedClose(close_state,exit_price);

   DeletePersistedTradeState(ticket);
   DeletePositionVisuals(ticket);

   for(int i=index; i<total-1; i++)
      g_TradeStates[i] = g_TradeStates[i+1];

   ArrayResize(g_TradeStates,total-1);
   g_PanelDirty = true;
   RefreshManagedTradeFlags();
   EnsureSelectedTicket();

   LogInfo("REGISTRY", "Removed ticket #" + (string)ticket + " (" + close_note + ")");
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

   // 2) Remove managed entries whose broker position is gone (journals SL/BE/TP closes)
   for(int i=ArraySize(g_TradeStates)-1; i>=0; i--)
   {
      ulong ticket = g_TradeStates[i].ticket;

      if(!PositionSelectByTicket(ticket))
         RemoveTradeStateAt(i);
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
// Detect manual/broker SL/TP changes, rebuild remaining partial ladder, journal + redraw
void SyncManagedStopsAndPartials()
{
   if(!g_HasManagedTrades)
      return;

   const double tol = _Point * 0.5;

   for(int i=0; i<ArraySize(g_TradeStates); i++)
   {
      if(g_TradeStates[i].pending_action != ATP_ACTION_NONE)
         continue;

      if(!PositionSelectByTicket(g_TradeStates[i].ticket))
         continue;

      double live_sl  = PositionGetDouble(POSITION_SL);
      double live_tp  = PositionGetDouble(POSITION_TP);
      double live_vol = PositionGetDouble(POSITION_VOLUME);

      double old_sl = g_TradeStates[i].stop_loss;
      double old_tp = g_TradeStates[i].take_profit;

      bool sl_changed = (MathAbs(live_sl - old_sl) > tol);
      bool tp_changed = (MathAbs(live_tp - old_tp) > tol);

      if(!sl_changed && !tp_changed)
      {
         g_TradeStates[i].current_volume = live_vol;
         continue;
      }

      g_TradeStates[i].current_volume = live_vol;
      g_TradeStates[i].stop_loss      = live_sl;
      g_TradeStates[i].take_profit    = live_tp;
      g_TradeStates[i].entry_price    = PositionGetDouble(POSITION_PRICE_OPEN);
      g_TradeStates[i].position_type  = PositionGetInteger(POSITION_TYPE);

      // Rebuild incomplete partial levels from new final TP (keep completed ones)
      if(tp_changed)
      {
         if(live_tp <= 0.0)
         {
            for(int p=0; p<g_TradeStates[i].partial_count; p++)
            {
               if(!g_TradeStates[i].partial_done[p])
                  g_TradeStates[i].partial_prices[p] = 0.0;
            }
         }
         else
         {
            int direction = (g_TradeStates[i].position_type == POSITION_TYPE_BUY ? 1 : -1);
            double total_distance = MathAbs(live_tp - g_TradeStates[i].entry_price);

            if(g_TradeStates[i].partial_count <= 0)
            {
               g_TradeStates[i].partial_count = MathMax(1,MathMin(5,g_PlanPartialCount));
               ArrayResize(g_TradeStates[i].partial_done,g_TradeStates[i].partial_count);
               ArrayInitialize(g_TradeStates[i].partial_done,false);
               ArrayResize(g_TradeStates[i].partial_prices,g_TradeStates[i].partial_count);
            }

            for(int p=0; p<g_TradeStates[i].partial_count; p++)
            {
               if(g_TradeStates[i].partial_done[p])
                  continue;

               double fraction = (double)(p+1) / (double)(g_TradeStates[i].partial_count+1);
               g_TradeStates[i].partial_prices[p] = NormalizeDouble(
                  g_TradeStates[i].entry_price + direction * total_distance * fraction,_Digits);
            }
         }
      }

      PersistTradeState(i);
      DrawManagedPositionVisuals(i);
      JournalSLTPUpdate(i,old_sl,old_tp,live_sl,live_tp);

      g_PanelDirty = true;

      LogInfo("SYNC",
              "Ticket #" + (string)g_TradeStates[i].ticket +
              " SL/TP updated. SL " + DoubleToString(old_sl,_Digits) +
              "->" + DoubleToString(live_sl,_Digits) +
              " TP " + DoubleToString(old_tp,_Digits) +
              "->" + DoubleToString(live_tp,_Digits) +
              (tp_changed ? " [partials rebuilt]" : ""));
   }
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
   SyncManagedStopsAndPartials();
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