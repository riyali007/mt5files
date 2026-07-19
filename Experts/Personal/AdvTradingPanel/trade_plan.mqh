#ifndef ADVTP_TRADE_PLAN_MQH
#define ADVTP_TRADE_PLAN_MQH

void InitializeTradePlan()
{
   g_OrderMode = ATP_ORDER_MARKET;
   g_PlanDirection = ORDER_TYPE_BUY;
   g_PlanLot = InpDefaultLot;
   g_PlanSLPoints = InpDefaultSLPoints;
   g_PlanTPPoints = InpDefaultTPPoints;
   g_PlanPartialCount = MathMax(1,MathMin(5,InpDefaultPartialCount));
   g_PlanPrice = 0.0;
   g_PreviewVisible = false;
   g_IsEditingPrice = false;
   g_CurrentPlan.valid = false;
}

double GetPlanEntryPrice(const ENUM_ORDER_TYPE direction)
{
   if(g_OrderMode == ATP_ORDER_LIMIT && g_PlanPrice > 0.0)
      return(g_PlanPrice);

   if(direction == ORDER_TYPE_BUY)
      return(g_Ask);

   return(g_Bid);
}

double GetSLPrice(const ENUM_ORDER_TYPE direction,const double entry,const int points)
{
   if(direction == ORDER_TYPE_BUY)
      return(NormalizeDouble(entry - points * _Point,_Digits));

   return(NormalizeDouble(entry + points * _Point,_Digits));
}

double GetTPPrice(const ENUM_ORDER_TYPE direction,const double entry,const int points)
{
   if(direction == ORDER_TYPE_BUY)
      return(NormalizeDouble(entry + points * _Point,_Digits));

   return(NormalizeDouble(entry - points * _Point,_Digits));
}

void CalculatePlanMoney(TradePlan &plan)
{
   plan.risk_money = 0.0;
   plan.reward_money = 0.0;

   if(plan.volume <= 0.0 || plan.entry <= 0.0)
      return;

   double profit = 0.0;

   if(OrderCalcProfit(plan.order_type,plan.symbol,plan.volume,plan.entry,plan.sl,profit))
      plan.risk_money = MathAbs(profit);

   profit = 0.0;

   if(OrderCalcProfit(plan.order_type,plan.symbol,plan.volume,plan.entry,plan.tp,profit))
      plan.reward_money = MathAbs(profit);
}

void CalculatePartialPrices(TradePlan &plan)
{
   ArrayResize(plan.partial_prices,plan.partial_count);

   double total_distance = MathAbs(plan.tp - plan.entry);
   int direction = (plan.order_type == ORDER_TYPE_BUY ? 1 : -1);

   for(int i=0; i<plan.partial_count; i++)
   {
      double fraction = (double)(i + 1) / (double)(plan.partial_count + 1);
      plan.partial_prices[i] = NormalizeDouble(plan.entry + direction * total_distance * fraction,_Digits);
   }
}

bool BuildTradePlan(const ENUM_ORDER_TYPE direction,TradePlan &plan,string &reason)
{
   reason = "";
   ZeroMemory(plan);

   if(direction != ORDER_TYPE_BUY && direction != ORDER_TYPE_SELL)
   {
      reason = "Unsupported direction";
      return(false);
   }

   MqlTick tick;

   if(!SymbolInfoTick(_Symbol,tick))
   {
      reason = "No market tick available";
      return(false);
   }

   if(g_PlanLot <= 0.0)
   {
      reason = "Lot must be greater than zero";
      return(false);
   }

   if(g_PlanSLPoints <= 0 || g_PlanTPPoints <= 0)
   {
      reason = "SL and TP points must be greater than zero";
      return(false);
   }

   if(g_PlanPartialCount < 1 || g_PlanPartialCount > 5)
   {
      reason = "Partial count must be 1 to 5";
      return(false);
   }

   plan.mode = g_OrderMode;
   plan.order_type = direction;
   plan.symbol = _Symbol;
   plan.volume = NormalizeVolumeDown(_Symbol,g_PlanLot);
   plan.entry = GetPlanEntryPrice(direction);
   plan.sl_points = g_PlanSLPoints;
   plan.tp_points = g_PlanTPPoints;
   plan.partial_count = g_PlanPartialCount;

   if(plan.volume <= 0.0)
   {
      reason = "Lot is below broker minimum or invalid step";
      return(false);
   }

   if(g_OrderMode == ATP_ORDER_LIMIT)
   {
      if(plan.entry <= 0.0)
      {
         reason = "Enter a valid limit price";
         return(false);
      }

      if(direction == ORDER_TYPE_BUY && plan.entry >= tick.ask)
      {
         reason = "Buy Limit must be below current Ask";
         return(false);
      }

      if(direction == ORDER_TYPE_SELL && plan.entry <= tick.bid)
      {
         reason = "Sell Limit must be above current Bid";
         return(false);
      }
   }

   plan.sl = GetSLPrice(direction,plan.entry,plan.sl_points);
   plan.tp = GetTPPrice(direction,plan.entry,plan.tp_points);

   if(!ValidateStops(_Symbol,direction,plan.entry,plan.sl,plan.tp,reason))
      return(false);

   CalculatePartialPrices(plan);
   CalculatePlanMoney(plan);
   plan.valid = true;
   return(true);
}

void RefreshCurrentPlan()
{
   string reason;

   if(BuildTradePlan(g_PlanDirection,g_CurrentPlan,reason))
      return;

   g_CurrentPlan.valid = false;
}

string GetPartialSummary(const TradePlan &plan)
{
   if(!plan.valid)
      return("TP levels: unavailable");

   string text = "";

   for(int i=0; i<plan.partial_count; i++)
   {
      int points = (int)MathRound(MathAbs(plan.partial_prices[i] - plan.entry) / _Point);

      if(i > 0)
         text += " | ";

      text += "TP" + IntegerToString(i+1) + ":" + IntegerToString(points);
   }

   return(text);
}

#endif