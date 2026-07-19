#ifndef ADVTP_TRADE_JOURNAL_MQH
#define ADVTP_TRADE_JOURNAL_MQH

bool g_TradeJournalHeaderReady = false;

int GetTradeJournalFileFlags()
{
   int flags = FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE;

   if(InpTradeJournalCsvInCommonFolder)
      flags |= FILE_COMMON;

   return(flags);
}

bool EnsureTradeJournalHeader()
{
   if(!InpEnableTradeJournalCsv)
      return(false);

   if(g_TradeJournalHeaderReady)
      return(true);

   int handle = FileOpen(InpTradeJournalCsvFileName,GetTradeJournalFileFlags(),',');

   if(handle == INVALID_HANDLE)
   {
      LogError("JOURNAL",
               "Cannot open journal file '" + InpTradeJournalCsvFileName +
               "'. Error=" + IntegerToString(GetLastError()));
      return(false);
   }

   if(FileSize(handle) == 0)
   {
      FileWrite(handle,
                "timestamp",
                "event",
                "ticket",
                "symbol",
                "side",
                "volume",
                "price",
                "sl",
                "tp",
                "profit",
                "note",
                "magic",
                "source",
                "screenshot_file");
   }

   FileClose(handle);
   g_TradeJournalHeaderReady = true;
   return(true);
}

// Realized (or mark-to-market) P/L in account currency for journal/JSON.
// BUY  = long  from entry -> exit_price
// SELL = short from entry -> exit_price
double CalculateJournalProfit(const string symbol,
                              const long position_type,
                              const double volume,
                              const double entry_price,
                              const double exit_price)
{
   if(volume <= 0.0 || entry_price <= 0.0 || exit_price <= 0.0)
      return(0.0);

   if(symbol == "")
      return(0.0);

   ENUM_ORDER_TYPE order_type =
      (position_type == POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);

   double profit = 0.0;

   if(!OrderCalcProfit(order_type,symbol,volume,entry_price,exit_price,profit))
   {
      LogDebug("JOURNAL",
               "OrderCalcProfit failed symbol=" + symbol +
               " vol=" + DoubleToString(volume,2) +
               " entry=" + DoubleToString(entry_price,_Digits) +
               " exit=" + DoubleToString(exit_price,_Digits));
      return(0.0);
   }

   return(NormalizeDouble(profit,2));
}

double CalculateJournalProfitFromSide(const string symbol,
                                      const string side,
                                      const double volume,
                                      const double entry_price,
                                      const double exit_price)
{
   long position_type = POSITION_TYPE_BUY;

   if(side == "SELL")
      position_type = POSITION_TYPE_SELL;

   return(CalculateJournalProfit(symbol,position_type,volume,entry_price,exit_price));
}

string TradeJournalSideText(const long position_type)
{
   if(position_type == POSITION_TYPE_BUY)
      return("BUY");

   if(position_type == POSITION_TYPE_SELL)
      return("SELL");

   return("UNKNOWN");
}

void WriteTradeJournalEvent(const string event_name,
                            const ulong ticket,
                            const string symbol,
                            const string side,
                            const double volume,
                            const double price,
                            const double sl,
                            const double tp,
                            const double profit,
                            const string note,
                            const string source,
                            const string screenshot_file = "")
{
   // CSV and webhook are independent — one must not block the other
   bool csv_ok = false;

   if(InpEnableTradeJournalCsv)
   {
      if(EnsureTradeJournalHeader())
      {
         int handle = FileOpen(InpTradeJournalCsvFileName,GetTradeJournalFileFlags(),',');

         if(handle == INVALID_HANDLE)
         {
            LogError("JOURNAL",
                     "Write failed for event '" + event_name +
                     "'. Error=" + IntegerToString(GetLastError()));
         }
         else
         {
            FileSeek(handle,0,SEEK_END);

            FileWrite(handle,
                      TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
                      event_name,
                      (string)ticket,
                      symbol,
                      side,
                      DoubleToString(volume,2),
                      DoubleToString(price,_Digits),
                      DoubleToString(sl,_Digits),
                      DoubleToString(tp,_Digits),
                      DoubleToString(profit,2),
                      note,
                      (string)InpMagicNumber,
                      source,
                      screenshot_file);

            FileClose(handle);
            csv_ok = true;
         }
      }
   }

   LogDebug("JOURNAL",
            event_name + " ticket #" + (string)ticket +
            " source=" + source +
            " profit=" + DoubleToString(profit,2) +
            " csv=" + (csv_ok ? "ok" : "skip"));

   // Always attempt webhook when enabled (even if CSV off/failed)
   SendN8nJournalEvent(event_name,
                       ticket,
                       symbol,
                       side,
                       volume,
                       price,
                       sl,
                       tp,
                       profit,
                       note,
                       source,
                       screenshot_file);
}
void JournalManagedTradeEvent(const int index,
                              const string event_name,
                              const string note,
                              const string source,
                              const double volume_override = -1.0,
                              const double price_override = -1.0,
                              const double profit_override = 0.0)
{
   if(index < 0 || index >= ArraySize(g_TradeStates))
      return;

   TradeState state = g_TradeStates[index];

   double volume = (volume_override >= 0.0 ? volume_override : state.current_volume);

   MqlTick tick;
   double price = state.entry_price;
   if(price_override >= 0.0)
      price = price_override;
   else if(SymbolInfoTick(state.symbol,tick))
      price = (state.position_type == POSITION_TYPE_BUY ? tick.bid : tick.ask);

   double sl_out = 0.0;
   double tp_out = 0.0;

   // Only OPEN/ADOPT keep SL/TP. Lifecycle events send current price only.
   if(event_name == "OPEN" || event_name == "ADOPT")
   {
      sl_out = state.stop_loss;
      tp_out = state.take_profit;
      if(price_override < 0.0)
         price = state.entry_price;
   }

   WriteTradeJournalEvent(event_name,
                          state.ticket,
                          state.symbol,
                          TradeJournalSideText(state.position_type),
                          volume,
                          price,
                          sl_out,
                          tp_out,
                          profit_override,
                          note,
                          source,
                          "");
}

void JournalPositionOpenIfPossible(const ulong ticket,const string source)
{
   if(!InpEnableTradeJournalCsv && !InpEnableN8nWebhook)
      return;

   if(!PositionSelectByTicket(ticket))
      return;

   string screenshot_file = CaptureTradeOpenScreenshot(ticket);

   WriteTradeJournalEvent("OPEN",
                          ticket,
                          PositionGetString(POSITION_SYMBOL),
                          TradeJournalSideText(PositionGetInteger(POSITION_TYPE)),
                          PositionGetDouble(POSITION_VOLUME),
                          PositionGetDouble(POSITION_PRICE_OPEN),
                          PositionGetDouble(POSITION_SL),
                          PositionGetDouble(POSITION_TP),
                          0.0,
                          "Position registered",
                          source,
                          screenshot_file);
}

void JournalPartialConfirmed(const int index,
                             const int partial_index,
                             const double closed_volume,
                             const double remaining_volume)
{
   // Need at least one sink enabled
   if(!InpTradeJournalLogPartials)
      return;

   if(!InpEnableTradeJournalCsv && !InpEnableN8nWebhook)
      return;

   if(index < 0 || index >= ArraySize(g_TradeStates))
      return;

   TradeState state = g_TradeStates[index];

   MqlTick tick;
   double current_price = state.entry_price;
   if(SymbolInfoTick(state.symbol,tick))
      current_price = (state.position_type == POSITION_TYPE_BUY ? tick.bid : tick.ask);

   double profit = CalculateJournalProfit(state.symbol,
                                          state.position_type,
                                          closed_volume,
                                          state.entry_price,
                                          current_price);

   string note = "TP" + IntegerToString(partial_index + 1) +
                 " closed=" + DoubleToString(closed_volume,2) +
                 " remaining=" + DoubleToString(remaining_volume,2) +
                 " pnl=" + DoubleToString(profit,2);

   WriteTradeJournalEvent("PARTIAL",
                          state.ticket,
                          state.symbol,
                          TradeJournalSideText(state.position_type),
                          closed_volume,
                          current_price,
                          0.0,
                          0.0,
                          profit,
                          note,
                          "ENGINE",
                          "");
}

void JournalBreakevenConfirmed(const int index,const double be_price)
{
   if(!InpTradeJournalLogBreakeven)
      return;

   if(index < 0 || index >= ArraySize(g_TradeStates))
      return;

   TradeState state = g_TradeStates[index];

   MqlTick tick;
   double current_price = state.entry_price;
   if(SymbolInfoTick(state.symbol,tick))
      current_price = (state.position_type == POSITION_TYPE_BUY ? tick.bid : tick.ask);

   // BE is protection only — do not calculate or send P/L
   WriteTradeJournalEvent("BREAKEVEN",
                          state.ticket,
                          state.symbol,
                          TradeJournalSideText(state.position_type),
                          state.current_volume,
                          current_price,
                          be_price,
                          state.take_profit,
                          0.0,
                          "BE SL=" + DoubleToString(be_price,_Digits),
                          "ENGINE",
                          "");
}

void JournalTrailingStopConfirmed(const int index,const double trail_price)
{
   if(!InpTradeJournalLogTrailingStop)
      return;

   if(index < 0 || index >= ArraySize(g_TradeStates))
      return;

   TradeState state = g_TradeStates[index];

   MqlTick tick;
   double current_price = state.entry_price;
   if(SymbolInfoTick(state.symbol,tick))
      current_price = (state.position_type == POSITION_TYPE_BUY ? tick.bid : tick.ask);

   double profit = CalculateJournalProfit(state.symbol,
                                          state.position_type,
                                          state.current_volume,
                                          state.entry_price,
                                          current_price);

   WriteTradeJournalEvent("TRAIL_STOP",
                          state.ticket,
                          state.symbol,
                          TradeJournalSideText(state.position_type),
                          state.current_volume,
                          current_price,
                          trail_price,
                          state.take_profit,
                          profit,
                          "Trail SL=" + DoubleToString(trail_price,_Digits) +
                          " float_pnl=" + DoubleToString(profit,2),
                          "ENGINE",
                          "");
}

void JournalAdoption(const int index,const string source)
{
   if(!InpTradeJournalLogAdoption)
      return;

   JournalManagedTradeEvent(index,
                            "ADOPT",
                            "External trade adopted",
                            source);
}

void JournalCloseEvent(const ulong ticket,
                       const string symbol,
                       const string side,
                       const double volume,
                       const double price,
                       const double profit,
                       const string note,
                       const string source)
{
   if(!InpTradeJournalLogClose)
      return;

   MqlTick tick;
   double current_price = price;
   if(SymbolInfoTick(symbol,tick))
   {
      if(side == "BUY")
         current_price = tick.bid;
      else if(side == "SELL")
         current_price = tick.ask;
      else
         current_price = tick.bid;
   }

   // Prefer caller profit if already set; otherwise compute from entry->exit.
   // Callers often pass entry as `price` and 0 profit — recover entry from price
   // when it still looks like an entry, and use live tick as exit.
   double pnl = profit;
   double entry_for_calc = price;

   if(MathAbs(pnl) < 0.0000001)
   {
      // If price looked like entry and tick is exit, use that pair
      if(entry_for_calc > 0.0 && current_price > 0.0 && volume > 0.0)
         pnl = CalculateJournalProfitFromSide(symbol,side,volume,entry_for_calc,current_price);
   }

   string note_out = note;
   if(StringFind(note_out,"pnl=") < 0)
      note_out = note + " pnl=" + DoubleToString(pnl,2);

   WriteTradeJournalEvent("CLOSE",
                          ticket,
                          symbol,
                          side,
                          volume,
                          current_price,
                          0.0,
                          0.0,
                          pnl,
                          note_out,
                          source,
                          "");
}

void JournalSLTPUpdate(const int index,
                       const double old_sl,
                       const double old_tp,
                       const double new_sl,
                       const double new_tp)
{
   if(index < 0 || index >= ArraySize(g_TradeStates))
      return;

   TradeState state = g_TradeStates[index];

   MqlTick tick;
   double current_price = state.entry_price;
   if(SymbolInfoTick(state.symbol,tick))
      current_price = (state.position_type == POSITION_TYPE_BUY ? tick.bid : tick.ask);

   // Floating P/L on full remaining volume after SL/TP edit
   double profit = CalculateJournalProfit(state.symbol,
                                          state.position_type,
                                          state.current_volume,
                                          state.entry_price,
                                          current_price);

   string note = "SL " + DoubleToString(old_sl,_Digits) + "->" + DoubleToString(new_sl,_Digits) +
                 " | TP " + DoubleToString(old_tp,_Digits) + "->" + DoubleToString(new_tp,_Digits) +
                 " | float_pnl=" + DoubleToString(profit,2);

   WriteTradeJournalEvent("SLTP_UPDATE",
                          state.ticket,
                          state.symbol,
                          TradeJournalSideText(state.position_type),
                          state.current_volume,
                          current_price,
                          new_sl,
                          new_tp,
                          profit,
                          note,
                          "MANUAL_OR_BROKER",
                          "");
}

bool InitializeTradeJournal()
{
   g_TradeJournalHeaderReady = false;

   if(!InpEnableTradeJournalCsv)
   {
      LogInfo("JOURNAL","CSV journal disabled");
      return(true);
   }

   if(EnsureTradeJournalHeader())
   {
      LogInfo("JOURNAL",
              "CSV journal ready: " + InpTradeJournalCsvFileName +
              (InpTradeJournalCsvInCommonFolder ? " [COMMON]" : " [TERMINAL]"));
      return(true);
   }

   return(false);
}

#endif