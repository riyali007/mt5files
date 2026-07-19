//+------------------------------------------------------------------+
//|                                                   Guardrails.mqh |
//+------------------------------------------------------------------+
#property strict

class CGuardrails
  {
private:
   double   m_max_daily_loss_amount;
   int      m_max_daily_trades;
   int      m_max_concurrent_trades;
   double   m_max_spread_points;
   
   // State
   double   m_start_balance;
   int      m_trades_today_count;
   int      m_day_of_year;

   // --- HELPER FOR MQL5 DATE COMPATIBILITY ---
   int GetDayOfYear(datetime time)
     {
      MqlDateTime dt;
      TimeToStruct(time, dt);
      return dt.day_of_year;
     }

public:
   CGuardrails(double maxLoss, int maxDailyTrades, int maxConcTrades, double maxSpread)
     {
      m_max_daily_loss_amount = maxLoss;
      m_max_daily_trades      = maxDailyTrades;
      m_max_concurrent_trades = maxConcTrades;
      m_max_spread_points     = maxSpread;
      
      m_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      
      // FIX: Use helper function instead of undeclared TimeDayOfYear
      m_day_of_year = GetDayOfYear(TimeCurrent());
      m_trades_today_count = 0;
     }

   bool IsSafeToTrade(string &reason)
     {
      // FIX: Check for new day using helper
      int current_day = GetDayOfYear(TimeCurrent());
      
      if(current_day != m_day_of_year) {
         m_day_of_year = current_day;
         m_trades_today_count = 0;
         m_start_balance = AccountInfoDouble(ACCOUNT_BALANCE); // Reset daily baseline
      }

      // 2. Check Spread
      if(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > m_max_spread_points) {
         reason = "Spread too high";
         return false;
      }

      // 3. Check Max Trades
      if(m_trades_today_count >= m_max_daily_trades) {
         reason = "Max daily trades reached";
         return false;
      }

      // 4. Check Concurrent Positions
      if(PositionsTotal() >= m_max_concurrent_trades) {
         reason = "Max concurrent trades reached";
         return false;
      }

      // 5. Check Drawdown
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(currentEquity < (m_start_balance - m_max_daily_loss_amount)) {
         reason = "Daily Loss Limit Hit";
         return false;
      }

      return true;
     }

   void RegisterTrade()
     {
      m_trades_today_count++;
   }
   
   string GetStatus() {
      return "Trades: " + (string)m_trades_today_count + "/" + (string)m_max_daily_trades;
   }
  };