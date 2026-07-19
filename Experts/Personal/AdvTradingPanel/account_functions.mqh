#ifndef ADVTP_ACCOUNT_FUNCTIONS_MQH
#define ADVTP_ACCOUNT_FUNCTIONS_MQH

bool ValidateHedgingAccount()
{
   ENUM_ACCOUNT_MARGIN_MODE margin_mode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   g_IsHedgingAccount = (margin_mode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);

   if(InpAllowOnlyHedgingAccounts && !g_IsHedgingAccount)
   {
      Alert(APP_NAME + ": This EA requires an MT5 hedging account.");
      Print("[ATP][ERROR][ACCOUNT] Hedging account required. Current margin mode=", IntegerToString((int)margin_mode));
      return(false);
   }

   return(true);
}

bool IsManagedPosition(const ulong ticket)
{
   if(ticket == 0 || !PositionSelectByTicket(ticket))
      return(false);

   long magic = PositionGetInteger(POSITION_MAGIC);
   return((ulong)magic == InpMagicNumber);
}

double NormalizeVolumeDown(const string symbol,const double requested_volume)
{
   double min_volume = SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double max_volume = SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);

   if(step <= 0.0 || requested_volume < min_volume)
      return(0.0);

   double normalized = MathFloor((requested_volume + 1e-10) / step) * step;
   normalized = MathMin(normalized,max_volume);

   int volume_digits = 0;
   double test_step = step;
   while(test_step < 1.0 && volume_digits < 8)
   {
      test_step *= 10.0;
      volume_digits++;
   }

   return(NormalizeDouble(normalized,volume_digits));
}

void LogSymbolTradingSettings(const string symbol)
{
   long trade_mode = SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE);
   long execution_mode = SymbolInfoInteger(symbol,SYMBOL_TRADE_EXEMODE);
   long filling_mode = SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);
   long stops_level = SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freeze_level = SymbolInfoInteger(symbol,SYMBOL_TRADE_FREEZE_LEVEL);

   LogInfo("SYMBOL",
           symbol +
           " TradeMode=" + IntegerToString((int)trade_mode) +
           " ExecutionMode=" + IntegerToString((int)execution_mode) +
           " FillingFlags=" + IntegerToString((int)filling_mode) +
           " StopsLevel=" + IntegerToString((int)stops_level) +
           " FreezeLevel=" + IntegerToString((int)freeze_level) +
           " VolMin=" + DoubleToString(SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN),2) +
           " VolStep=" + DoubleToString(SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP),2));
}
#endif