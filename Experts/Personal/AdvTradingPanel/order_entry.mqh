#ifndef ADVTP_ORDER_ENTRY_MQH
#define ADVTP_ORDER_ENTRY_MQH

ENUM_ORDER_TYPE_FILLING GetSymbolFillingType(const string symbol)
{
   long filling_flags = SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);

   if((filling_flags & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return(ORDER_FILLING_IOC);

   if((filling_flags & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return(ORDER_FILLING_FOK);

   return(ORDER_FILLING_RETURN);
}

bool HasSupportedMarketFillingMode(const string symbol)
{
   long execution_mode = SymbolInfoInteger(symbol,SYMBOL_TRADE_EXEMODE);
   long filling_flags = SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);

   if(execution_mode != SYMBOL_TRADE_EXECUTION_MARKET)
      return(true);

   bool supports_fok = ((filling_flags & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK);
   bool supports_ioc = ((filling_flags & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC);

   if(supports_fok || supports_ioc)
      return(true);

   LogError("ORDER","No valid market filling mode for " + symbol);
   return(false);
}

bool IsTradeRetcodeSuccessful(const uint retcode)
{
   return(retcode == TRADE_RETCODE_DONE ||
          retcode == TRADE_RETCODE_PLACED ||
          retcode == TRADE_RETCODE_DONE_PARTIAL);
}

bool IsSymbolTradeReady(const string symbol,string &reason)
{
   reason = "";

   if(!SymbolSelect(symbol,true))
   {
      reason = "SymbolSelect failed";
      return(false);
   }

   long trade_mode = SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE);

   if(trade_mode == SYMBOL_TRADE_MODE_DISABLED)
   {
      reason = "Trading disabled for symbol";
      return(false);
   }

   return(true);
}

bool ValidateStops(const string symbol,const ENUM_ORDER_TYPE order_type,const double entry,const double sl,const double tp,string &reason)
{
   reason = "";

   double point = SymbolInfoDouble(symbol,SYMBOL_POINT);
   int stops_level = (int)SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL);
   double min_distance = stops_level * point;
   bool is_buy = (order_type == ORDER_TYPE_BUY || order_type == ORDER_TYPE_BUY_LIMIT);
   bool is_sell = (order_type == ORDER_TYPE_SELL || order_type == ORDER_TYPE_SELL_LIMIT);

   if(sl > 0.0)
   {
      if(is_buy && sl >= entry)
      {
         reason = "Buy SL must be below entry";
         return(false);
      }

      if(is_sell && sl <= entry)
      {
         reason = "Sell SL must be above entry";
         return(false);
      }

      if(min_distance > 0.0 && MathAbs(entry-sl) < min_distance)
      {
         reason = "SL too close for broker stop level";
         return(false);
      }
   }

   if(tp > 0.0)
   {
      if(is_buy && tp <= entry)
      {
         reason = "Buy TP must be above entry";
         return(false);
      }

      if(is_sell && tp >= entry)
      {
         reason = "Sell TP must be below entry";
         return(false);
      }

      if(min_distance > 0.0 && MathAbs(entry-tp) < min_distance)
      {
         reason = "TP too close for broker stop level";
         return(false);
      }
   }

   return(true);
}

bool SendRequest(MqlTradeRequest &request,const string action_name)
{
   MqlTradeResult result;
   ZeroMemory(result);

   ResetLastError();

   bool sent = OrderSend(request,result);
   int terminal_error = GetLastError();

   LogInfo("ORDER",
           action_name +
           " sent=" + (sent ? "true" : "false") +
           " terminal_error=" + IntegerToString(terminal_error) +
           " retcode=" + IntegerToString((int)result.retcode) +
           " comment=" + result.comment);

   if(!sent || !IsTradeRetcodeSuccessful(result.retcode))
   {
      LogError("ORDER",
               action_name +
               " failed. Retcode=" + IntegerToString((int)result.retcode) +
               " Comment=" + result.comment);
      return(false);
   }

   return(true);
}

bool ExecuteTradePlan(const TradePlan &plan)
{
   if(!plan.valid)
   {
      LogError("ORDER","Trade plan is invalid");
      return(false);
   }

   string reason;

   if(!IsSymbolTradeReady(plan.symbol,reason))
   {
      LogError("ORDER","Blocked: " + reason);
      return(false);
   }

   MqlTradeRequest request;
   ZeroMemory(request);

   request.magic = InpMagicNumber;
   request.symbol = plan.symbol;
   request.volume = plan.volume;
   request.sl = plan.sl;
   request.tp = plan.tp;
   request.deviation = InpDeviationPoints;
   request.comment = APP_SHORT_NAME + "_Plan";

   string action_name = "";

   if(plan.mode == ATP_ORDER_MARKET)
   {
      if(!HasSupportedMarketFillingMode(plan.symbol))
         return(false);

      request.action = TRADE_ACTION_DEAL;
      request.type = plan.order_type;
      request.price = 0.0;
      request.type_filling = GetSymbolFillingType(plan.symbol);

      action_name = (plan.order_type == ORDER_TYPE_BUY ? "MARKET BUY" : "MARKET SELL");
   }
   else
   {
      request.action = TRADE_ACTION_PENDING;
      request.type = (plan.order_type == ORDER_TYPE_BUY ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT);
      request.price = plan.entry;
      request.type_filling = ORDER_FILLING_RETURN;
      request.type_time = ORDER_TIME_GTC;

      action_name = (plan.order_type == ORDER_TYPE_BUY ? "BUY LIMIT" : "SELL LIMIT");
   }

   bool success = SendRequest(request,action_name);

   if(success)
   {
      g_PlanDirection = plan.order_type;
      DeletePlanObjects();
      g_PreviewVisible = false;
      g_PanelDirty = true;
   }

   return(success);
}

#endif