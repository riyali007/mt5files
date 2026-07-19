#ifndef ADVTP_BASKET_MANAGER_MQH
#define ADVTP_BASKET_MANAGER_MQH

// Money -> points using symbol tick value (account currency per tick)
double BasketMoneyToPoints(const string symbol,const double money)
{
   if(symbol == "" || money == 0.0)
      return(0.0);

   double tick_size  = SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE);
   double point      = SymbolInfoDouble(symbol,SYMBOL_POINT);

   if(tick_size <= 0.0 || tick_value <= 0.0 || point <= 0.0)
      return(0.0);

   // money / (tick_value per lot at 1.0) scaled by volume is handled by caller via OrderCalcProfit
   // Here: 1.0 account currency -> how many points for 1.0 lot reference is NOT used.
   // We convert a P/L already computed for the real volume:
   // points = money / (tick_value/tick_size) / point * point wait:
   // value_per_point_for_that_deal ≈ money / price_distance_in_points when distance known.
   // Prefer: points = money / (tick_value * (point/tick_size)) but that is per 1 lot.
   // OrderCalcProfit already used real volume, so:
   // money ≈ lots * (price_move/tick_size) * tick_value
   // points_move = price_move/point
   // => money = lots * (points_move*point/tick_size) * tick_value
   // => points_move = money * tick_size / (lots * tick_value * point)
   // We don't have lots here alone for conversion of aggregate money without lots.
   // Simpler approach used below: convert each ticket P/L with its own volume.

   double value_per_point_1lot = tick_value * (point / tick_size);
   if(value_per_point_1lot <= 0.0)
      return(0.0);

   // Fallback unused for aggregates — see BasketTicketProfitPoints
   return(money / value_per_point_1lot);
}

double BasketTicketProfitMoney(const TradeState &state)
{
   if(state.current_volume <= 0.0 || state.entry_price <= 0.0)
      return(0.0);

   MqlTick tick;
   if(!SymbolInfoTick(state.symbol,tick))
      return(0.0);

   double exit_price = (state.position_type == POSITION_TYPE_BUY ? tick.bid : tick.ask);

   ENUM_ORDER_TYPE order_type =
      (state.position_type == POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);

   double profit = 0.0;
   if(!OrderCalcProfit(order_type,state.symbol,state.current_volume,
                       state.entry_price,exit_price,profit))
      return(0.0);

   return(profit);
}

// Floating P/L of one ticket expressed in points (price distance * direction sense)
double BasketTicketProfitPoints(const TradeState &state)
{
   if(state.current_volume <= 0.0 || state.entry_price <= 0.0)
      return(0.0);

   MqlTick tick;
   if(!SymbolInfoTick(state.symbol,tick))
      return(0.0);

   double exit_price = (state.position_type == POSITION_TYPE_BUY ? tick.bid : tick.ask);
   double point = SymbolInfoDouble(state.symbol,SYMBOL_POINT);
   if(point <= 0.0)
      point = _Point;

   double raw_points = 0.0;
   if(state.position_type == POSITION_TYPE_BUY)
      raw_points = (exit_price - state.entry_price) / point;
   else
      raw_points = (state.entry_price - exit_price) / point;

   return(raw_points);
}

bool BasketTicketEligible(const TradeState &state)
{
   if(state.symbol != _Symbol)
      return(false);

   if(state.pending_action != ATP_ACTION_NONE)
      return(false);

   // BE applied (manual or engine) — exclude from basket math and close selection
   if(state.be_applied)
      return(false);

   if(!InpBasketIncludeExternal && (state.is_external || state.is_adopted))
      return(false);

   if(!PositionSelectByTicket(state.ticket))
      return(false);

   return(true);
}

// Returns index of worst eligible ticket for side, or -1
// BUY  -> highest entry
// SELL -> lowest entry
int FindWorstBasketIndex(const long position_type)
{
   int worst_index = -1;
   double worst_entry = 0.0;

   for(int i=0; i<ArraySize(g_TradeStates); i++)
   {
      if(!BasketTicketEligible(g_TradeStates[i]))
         continue;

      if(g_TradeStates[i].position_type != position_type)
         continue;

      double entry = g_TradeStates[i].entry_price;

      if(worst_index < 0)
      {
         worst_index = i;
         worst_entry = entry;
         continue;
      }

      bool is_worse = false;

      if(position_type == POSITION_TYPE_BUY)
         is_worse = (entry > worst_entry + (_Point * 0.1));
      else
         is_worse = (entry < worst_entry - (_Point * 0.1));

      // Tie-break: larger volume, then higher ticket
      if(!is_worse && MathAbs(entry - worst_entry) <= (_Point * 0.1))
      {
         if(g_TradeStates[i].current_volume > g_TradeStates[worst_index].current_volume + 1e-8)
            is_worse = true;
         else if(MathAbs(g_TradeStates[i].current_volume - g_TradeStates[worst_index].current_volume) <= 1e-8 &&
                 g_TradeStates[i].ticket > g_TradeStates[worst_index].ticket)
            is_worse = true;
      }

      if(is_worse)
      {
         worst_index = i;
         worst_entry = entry;
      }
   }

   return(worst_index);
}

int CountBasketEligibleSide(const long position_type)
{
   int count = 0;

   for(int i=0; i<ArraySize(g_TradeStates); i++)
   {
      if(!BasketTicketEligible(g_TradeStates[i]))
         continue;

      if(g_TradeStates[i].position_type != position_type)
         continue;

      count++;
   }

   return(count);
}

// Sum floating points of eligible same-side tickets EXCLUDING worst_index
double BasketGoodPointsExcluding(const long position_type,const int worst_index)
{
   double sum = 0.0;

   for(int i=0; i<ArraySize(g_TradeStates); i++)
   {
      if(i == worst_index)
         continue;

      if(!BasketTicketEligible(g_TradeStates[i]))
         continue;

      if(g_TradeStates[i].position_type != position_type)
         continue;

      sum += BasketTicketProfitPoints(g_TradeStates[i]);
   }

   return(sum);
}

bool IsBasketWorstReadyToClose(const int worst_index,string &reason)
{
   reason = "";

   if(worst_index < 0 || worst_index >= ArraySize(g_TradeStates))
   {
      reason = "invalid worst index";
      return(false);
   }

   TradeState worst = g_TradeStates[worst_index];

   // Refresh live volume/entry
   if(!PositionSelectByTicket(worst.ticket))
   {
      reason = "worst position gone";
      return(false);
   }

   g_TradeStates[worst_index].current_volume = PositionGetDouble(POSITION_VOLUME);
   g_TradeStates[worst_index].entry_price    = PositionGetDouble(POSITION_PRICE_OPEN);
   g_TradeStates[worst_index].stop_loss      = PositionGetDouble(POSITION_SL);
   g_TradeStates[worst_index].take_profit    = PositionGetDouble(POSITION_TP);
   worst = g_TradeStates[worst_index];

   double worst_points = BasketTicketProfitPoints(worst);

   // Must be green
   if(worst_points < (double)InpBasketMinWorstProfitPoints)
   {
      reason = "worst not green yet pts=" + DoubleToString(worst_points,1) +
               " need>=" + IntegerToString(InpBasketMinWorstProfitPoints);
      return(false);
   }

   // Option 2 cover: good points must cover worst loss magnitude + buffer
   // When worst is already green, "loss" is 0 — cover check becomes good_points >= buffer
   if(InpBasketRequireCover)
   {
      double good_points = BasketGoodPointsExcluding(worst.position_type,worst_index);
      double cover_need  = 0.0;

      if(worst_points < 0.0)
         cover_need = MathAbs(worst_points);

      cover_need += (double)InpBasketCoverBufferPoints;

      if(good_points + 1e-6 < cover_need)
      {
         reason = "cover insufficient good_pts=" + DoubleToString(good_points,1) +
                  " need>=" + DoubleToString(cover_need,1);
         return(false);
      }
   }

   return(true);
}

bool TryCloseBasketWorstForSide(const long position_type)
{
   int group_size = CountBasketEligibleSide(position_type);

   if(group_size < InpBasketMinGroupSize)
      return(false);

   int worst_index = FindWorstBasketIndex(position_type);
   if(worst_index < 0)
      return(false);

   string reason;
   if(!IsBasketWorstReadyToClose(worst_index,reason))
   {
      LogDebug("BASKET",
               (position_type == POSITION_TYPE_BUY ? "BUY" : "SELL") +
               " wait: " + reason +
               " worst=#" + (string)g_TradeStates[worst_index].ticket);
      return(false);
   }

   TradeState worst = g_TradeStates[worst_index];
   double worst_pts = BasketTicketProfitPoints(worst);
   double good_pts  = BasketGoodPointsExcluding(position_type,worst_index);

   LogInfo("BASKET",
           "Closing worst " + (position_type == POSITION_TYPE_BUY ? "BUY" : "SELL") +
           " #" + (string)worst.ticket +
           " entry=" + DoubleToString(worst.entry_price,_Digits) +
           " pts=" + DoubleToString(worst_pts,1) +
           " good_pts=" + DoubleToString(good_pts,1));

   // Reuse existing close pipeline (pending + journal on confirm)
   if(!SendClosePositionRequest(worst_index,"BASKET_WORST"))
   {
      LogError("BASKET","Close rejected for #" + (string)worst.ticket);
      return(false);
   }

   // Enrich close request journal note is already CLOSE_REQUEST from close_manager.
   // Final CLOSE comes from ConfirmPendingClose / RemoveTradeStateAt.
   SetPanelMessage(
      "Basket closed worst #" + (string)worst.ticket +
      " (" + DoubleToString(worst_pts,1) + " pts)",
      clrLimeGreen);

   return(true);
}

void EvaluateBasketWorstClose()
{
   if(!InpEnableBasketWorstClose)
      return;

   if(!g_HasManagedTrades)
      return;

   if(InpBasketMinGroupSize < 2)
      return;

   // One close max per fast pulse total (not one per side) — cascade next ticks
   if(TryCloseBasketWorstForSide(POSITION_TYPE_BUY))
      return;

   TryCloseBasketWorstForSide(POSITION_TYPE_SELL);
}

#endif