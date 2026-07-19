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
   if(!InpEnableTradeJournalCsv)
      return;

   if(!EnsureTradeJournalHeader())
      return;

   int handle = FileOpen(InpTradeJournalCsvFileName,GetTradeJournalFileFlags(),',');

   if(handle == INVALID_HANDLE)
   {
      LogError("JOURNAL",
               "Write failed for event '" + event_name +
               "'. Error=" + IntegerToString(GetLastError()));
      return;
   }

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
   
   LogDebug("JOURNAL", event_name + " ticket #" + (string)ticket + " source=" + source);
   
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
   double price = (price_override >= 0.0 ? price_override : state.entry_price);

   WriteTradeJournalEvent(event_name,
                          state.ticket,
                          state.symbol,
                          TradeJournalSideText(state.position_type),
                          volume,
                          price,
                          state.stop_loss,
                          state.take_profit,
                          profit_override,
                          note,
                          source);
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
   if(!InpTradeJournalLogPartials)
      return;

   string note = "TP" + IntegerToString(partial_index + 1) +
                 " closed=" + DoubleToString(closed_volume,2) +
                 " remaining=" + DoubleToString(remaining_volume,2);

   JournalManagedTradeEvent(index,
                            "PARTIAL",
                            note,
                            "ENGINE",
                            closed_volume);
}

void JournalBreakevenConfirmed(const int index,const double be_price)
{
   if(!InpTradeJournalLogBreakeven)
      return;

   JournalManagedTradeEvent(index,
                            "BREAKEVEN",
                            "SL moved to " + DoubleToString(be_price,_Digits),
                            "ENGINE",
                            -1.0,
                            be_price);
}

void JournalTrailingStopConfirmed(const int index,const double trail_price)
{
   if(!InpTradeJournalLogTrailingStop)
      return;

   JournalManagedTradeEvent(index,
                            "TRAIL_STOP",
                            "SL trailed to " + DoubleToString(trail_price,_Digits),
                            "ENGINE",
                            -1.0,
                            trail_price);
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

   WriteTradeJournalEvent("CLOSE",
                          ticket,
                          symbol,
                          side,
                          volume,
                          price,
                          0.0,
                          0.0,
                          profit,
                          note,
                          source);
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