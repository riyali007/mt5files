#ifndef ADVTP_PERSISTENCE_MQH
#define ADVTP_PERSISTENCE_MQH

string GetPersistPrefix(const ulong ticket)
{
   return("ATP_" + IntegerToString(InpMagicNumber) + "_" + _Symbol + "_" + (string)ticket + "_");
}

void PersistTradeState(const int index)
{
   if(!InpPersistPartialState)
      return;

   if(index < 0 || index >= ArraySize(g_TradeStates))
      return;

   TradeState state = g_TradeStates[index];
   string p = GetPersistPrefix(state.ticket);

   GlobalVariableSet(p+"exists",1.0);
   GlobalVariableSet(p+"orig_vol",state.original_volume);
   GlobalVariableSet(p+"partial_count",(double)state.partial_count);
   GlobalVariableSet(p+"be_applied",state.be_applied ? 1.0 : 0.0);
   GlobalVariableSet(p+"trail_active",state.trailing_stop_active ? 1.0 : 0.0);
   GlobalVariableSet(p+"is_external",state.is_external ? 1.0 : 0.0);
   GlobalVariableSet(p+"is_adopted",state.is_adopted ? 1.0 : 0.0);

   for(int i=0; i<state.partial_count; i++)
   {
      GlobalVariableSet(p+"pd_"+IntegerToString(i),state.partial_done[i] ? 1.0 : 0.0);

      if(i < ArraySize(state.partial_prices))
         GlobalVariableSet(p+"pp_"+IntegerToString(i),state.partial_prices[i]);
   }

   g_TradeStates[index].last_persist_time = TimeCurrent();
}

bool LoadPersistedTradeState(const ulong ticket,TradeState &state)
{
   if(!InpPersistPartialState)
      return(false);

   string p = GetPersistPrefix(ticket);

   if(!GlobalVariableCheck(p+"exists"))
      return(false);

   state.original_volume = GlobalVariableGet(p+"orig_vol");
   state.partial_count = (int)GlobalVariableGet(p+"partial_count");
   state.be_applied = (GlobalVariableGet(p+"be_applied") > 0.5);
   state.trailing_stop_active = (GlobalVariableCheck(p+"trail_active") && GlobalVariableGet(p+"trail_active") > 0.5);
   state.is_external = (GlobalVariableGet(p+"is_external") > 0.5);
   state.is_adopted = (GlobalVariableGet(p+"is_adopted") > 0.5);
   state.recovered_from_storage = true;

   if(state.partial_count < 0)
      state.partial_count = 0;

   if(state.partial_count > 5)
      state.partial_count = 5;

   ArrayResize(state.partial_done,state.partial_count);
   ArrayResize(state.partial_prices,state.partial_count);

   for(int i=0; i<state.partial_count; i++)
   {
      state.partial_done[i] = (GlobalVariableGet(p+"pd_"+IntegerToString(i)) > 0.5);
      state.partial_prices[i] = GlobalVariableGet(p+"pp_"+IntegerToString(i));
   }

   return(true);
}

void DeletePersistedTradeState(const ulong ticket)
{
   string p = GetPersistPrefix(ticket);
   string keys[] =
   {
      "exists","orig_vol","partial_count","be_applied","trail_active","is_external","is_adopted"
   };

   for(int i=0; i<ArraySize(keys); i++)
   {
      string name = p + keys[i];
      if(GlobalVariableCheck(name))
         GlobalVariableDel(name);
   }

   for(int i=0; i<5; i++)
   {
      string pd = p + "pd_" + IntegerToString(i);
      string pp = p + "pp_" + IntegerToString(i);

      if(GlobalVariableCheck(pd))
         GlobalVariableDel(pd);

      if(GlobalVariableCheck(pp))
         GlobalVariableDel(pp);
   }
}

void BuildPartialPlanFromEntryTP(TradeState &state)
{
   ArrayResize(state.partial_done,state.partial_count);
   ArrayInitialize(state.partial_done,false);
   ArrayResize(state.partial_prices,state.partial_count);

   if(state.partial_count <= 0 || state.take_profit <= 0.0 || state.entry_price <= 0.0)
      return;

   int direction = (state.position_type == POSITION_TYPE_BUY ? 1 : -1);
   double total_distance = MathAbs(state.take_profit - state.entry_price);

   for(int p=0; p<state.partial_count; p++)
   {
      double fraction = (double)(p+1) / (double)(state.partial_count+1);
      state.partial_prices[p] = NormalizeDouble(state.entry_price + direction * total_distance * fraction,_Digits);
   }
}

#endif