//+------------------------------------------------------------------+
//| SnapBackEA.mq5 - fade (or follow) sudden price shocks, M1 data    |
//|                                                                    |
//| Same rules as snapback_test.py:                                    |
//|  shock = |close[t]-close[t-N]| >= K * typical,                     |
//|  typical = average |close[j]-close[j-N]| over the L minutes        |
//|            that end N minutes before the shock window             |
//|  FADE trades against the shock, FOLLOW trades with it.             |
//|  Entry at the first tick of the next M1 bar. TP and SL are set on  |
//|  the order. A trade still open after InpHoldMinutes is closed.     |
//|                                                                    |
//| PROTOTYPE: only run it live after snapback_test.py shows a real    |
//| edge on your own data and the strategy tester agrees with it.      |
//+------------------------------------------------------------------+
#property copyright "SnapBack EA prototype"
#property version   "1.00"
#include <Trade\Trade.mqh>

enum ENUM_SB_MODE { SB_FADE = 0, SB_FOLLOW = 1 };

input group "Signal"
input ENUM_SB_MODE InpMode        = SB_FADE;  // Fade the shock or follow it
input int    InpShockMinutes      = 5;        // N: shock window, minutes
input double InpShockK            = 3.0;      // k: shock size in multiples of the typical move
input int    InpLookbackMin       = 1440;     // L: minutes used for the typical move
input int    InpCooldownMin       = 15;       // minutes between accepted signals

input group "Exit"
input int    InpTPPoints          = 150;      // Take profit, points
input int    InpSLPoints          = 700;      // Stop loss, points
input int    InpHoldMinutes       = 240;      // Close a trade after this many minutes

input group "Risk"
input double InpLot               = 0.01;     // Fixed lot
input double InpRiskPct           = 0.0;      // Risk % of equity per trade at the stop (0 = use the fixed lot)
input int    InpMaxOpen           = 1;        // Max open trades (hedging accounts only; netting uses 1)
input int    InpMaxSpread         = 0;        // Skip signals when the spread is above this many points (0 = off)
input double InpDailyLossPct      = 3.0;      // Stop opening trades for the day after this equity loss % (0 = off)
input long   InpMagic             = 20261017; // Magic number

input group "Log"
input bool   InpLog               = true;     // Write CSV log (entries and exits)
input bool   InpLogCommon         = false;    // Use the common files folder

CTrade   g_trade;
datetime g_lastBar     = 0;
datetime g_lastSignal  = 0;
int      g_dayKey      = -1;
double   g_dayStartEq  = 0.0;
bool     g_dayBlocked  = false;
bool     g_hedging     = true;

//--------------------------------------------------------------------
string LogName() { return "SnapBack_" + _Symbol + "_" + IntegerToString(InpMagic) + ".csv"; }

void LogRow(const string line)
{
   if(!InpLog || MQLInfoInteger(MQL_OPTIMIZATION)) return;
   int flags = FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE;
   if(InpLogCommon) flags |= FILE_COMMON;
   const int h = FileOpen(LogName(), flags);
   if(h == INVALID_HANDLE) return;
   if(FileSize(h) == 0) FileWriteString(h, "event,time,position_id,side,z,price,sl,tp,spread_pts,net_money,net_points,reason\r\n");
   FileSeek(h, 0, SEEK_END);
   FileWriteString(h, line + "\r\n");
   FileClose(h);
}

//--------------------------------------------------------------------
int OpenCount()
{
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionGetTicket(i) == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic) c++;
   }
   return c;
}

bool HasOppositePosition(const int dir)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionGetTicket(i) == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      const bool isBuy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      if((dir > 0 && !isBuy) || (dir < 0 && isBuy)) return true;
   }
   return false;
}

double RoundLot(const double v)
{
   const double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   const double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double r = (step > 0.0) ? MathFloor(v / step + 1e-9) * step : v;
   r = MathMax(vmin, MathMin(vmax, r));
   return NormalizeDouble(r, 8);
}

double CalcLot()
{
   if(InpRiskPct <= 0.0) return RoundLot(InpLot);
   const double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   const double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickSize <= 0.0 || tickVal <= 0.0) return RoundLot(InpLot);
   const double lossPerLot = (InpSLPoints * _Point / tickSize) * tickVal;
   if(lossPerLot <= 0.0) return RoundLot(InpLot);
   const double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPct / 100.0;
   return RoundLot(riskMoney / lossPerLot);
}

//--------------------------------------------------------------------
void UpdateDay()
{
   MqlDateTime d;
   TimeToStruct(TimeCurrent(), d);
   const int key = d.year * 1000 + d.day_of_year;
   if(key != g_dayKey) {
      g_dayKey = key;
      g_dayStartEq = AccountInfoDouble(ACCOUNT_EQUITY);
      g_dayBlocked = false;
   }
   if(!g_dayBlocked && InpDailyLossPct > 0.0 && g_dayStartEq > 0.0 &&
      AccountInfoDouble(ACCOUNT_EQUITY) < g_dayStartEq * (1.0 - InpDailyLossPct / 100.0)) {
      g_dayBlocked = true;
      PrintFormat("Daily loss limit reached (%.1f%%): no new trades until tomorrow.", InpDailyLossPct);
   }
}

void ManageHold()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      const ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      const datetime ot = (datetime)PositionGetInteger(POSITION_TIME);
      if(TimeCurrent() - ot >= (datetime)(InpHoldMinutes * 60)) {
         g_trade.SetTypeFillingBySymbol(_Symbol);
         if(g_trade.PositionClose(tk)) PrintFormat("Time exit: #%I64u closed after %d minutes.", tk, InpHoldMinutes);
      }
   }
}

//--------------------------------------------------------------------
void OpenTrade(const int dir, const double z)
{
   if(g_dayBlocked) return;
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0) return;
   const double spreadPts = (ask - bid) / _Point;
   if(InpMaxSpread > 0 && spreadPts > InpMaxSpread) { PrintFormat("Signal skipped: spread %.0f pts.", spreadPts); return; }
   const int maxOpen = g_hedging ? MathMax(1, InpMaxOpen) : 1;
   if(OpenCount() >= maxOpen) return;
   if(!g_hedging && HasOppositePosition(dir)) return;           // netting: an opposite fill would close the open position
   const double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(InpTPPoints * _Point <= minDist || InpSLPoints * _Point <= minDist) { Print("Signal skipped: TP/SL inside the broker's minimum stop distance."); return; }
   const double price = (dir > 0) ? ask : bid;
   const double sl = NormalizeDouble((dir > 0) ? price - InpSLPoints * _Point : price + InpSLPoints * _Point, _Digits);
   const double tp = NormalizeDouble((dir > 0) ? price + InpTPPoints * _Point : price - InpTPPoints * _Point, _Digits);
   const double lot = CalcLot();
   if(lot <= 0.0) return;
   double margin = 0.0;
   if(OrderCalcMargin(dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, lot, price, margin) && margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE)) {
      Print("Signal skipped: not enough free margin."); return;
   }
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(30);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   const bool ok = (dir > 0) ? g_trade.Buy(lot, _Symbol, price, sl, tp, "SNAP") : g_trade.Sell(lot, _Symbol, price, sl, tp, "SNAP");
   const uint rc = g_trade.ResultRetcode();
   if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED)) {
      long pid = 0;
      const ulong deal = g_trade.ResultDeal();
      if(deal > 0 && HistoryDealSelect(deal)) pid = HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      PrintFormat("ENTRY %s %.2f lots at %s | z %.2f | SL %s TP %s | spread %.0f pts", dir > 0 ? "BUY" : "SELL", lot,
                  DoubleToString(price, _Digits), z, DoubleToString(sl, _Digits), DoubleToString(tp, _Digits), spreadPts);
      LogRow(StringFormat("ENTRY,%s,%I64d,%s,%.2f,%s,%s,%s,%.0f,,,",
             TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), pid, dir > 0 ? "BUY" : "SELL", z,
             DoubleToString(price, _Digits), DoubleToString(sl, _Digits), DoubleToString(tp, _Digits), spreadPts));
   } else
      PrintFormat("Order failed: retcode %u %s", rc, g_trade.ResultRetcodeDescription());
}

//--------------------------------------------------------------------
// Called once per new M1 bar. Bar 1 is the bar that just closed (the signal bar).
void CheckSignal()
{
   const int N = InpShockMinutes, L = InpLookbackMin;
   const int count = L + 2 * N + 2;
   double c[];
   ArraySetAsSeries(c, false);                                  // c[0] oldest ... c[count-1] = closed bar (shift 1)
   if(CopyClose(_Symbol, PERIOD_M1, 1, count, c) != count) return;
   const int t = count - 1;
   const double r = c[t] - c[t - N];
   double sum = 0.0;
   for(int j = t - N - L + 1; j <= t - N; j++) sum += MathAbs(c[j] - c[j - N]);
   const double typical = sum / L;
   if(typical <= 0.0) return;
   const double z = MathAbs(r) / typical;
   if(z < InpShockK) return;
   const datetime sigTime = iTime(_Symbol, PERIOD_M1, 1);
   if(g_lastSignal != 0 && (sigTime - g_lastSignal) < (datetime)(InpCooldownMin * 60)) return;
   int dir = 0;
   if(r > 0.0) dir = (InpMode == SB_FADE) ? -1 : 1;
   else if(r < 0.0) dir = (InpMode == SB_FADE) ? 1 : -1;
   if(dir == 0) return;
   g_lastSignal = sigTime;                                      // accepted signal (same as the Python test)
   OpenTrade(dir, z);
}

//--------------------------------------------------------------------
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(!InpLog || trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   const ulong dk = trans.deal;
   if(dk == 0 || !HistoryDealSelect(dk)) return;
   if(HistoryDealGetString(dk, DEAL_SYMBOL) != _Symbol || HistoryDealGetInteger(dk, DEAL_MAGIC) != InpMagic) return;
   const ENUM_DEAL_ENTRY e = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dk, DEAL_ENTRY);
   if(e != DEAL_ENTRY_OUT && e != DEAL_ENTRY_OUT_BY) return;
   const long pid = HistoryDealGetInteger(dk, DEAL_POSITION_ID);
   const ENUM_DEAL_REASON rs = (ENUM_DEAL_REASON)HistoryDealGetInteger(dk, DEAL_REASON);
   const string why = (rs == DEAL_REASON_TP) ? "TP" : (rs == DEAL_REASON_SL) ? "SL" : (rs == DEAL_REASON_CLIENT || rs == DEAL_REASON_EXPERT) ? "TIME_OR_MANUAL" : "OTHER";
   const double money = HistoryDealGetDouble(dk, DEAL_PROFIT) + HistoryDealGetDouble(dk, DEAL_SWAP) + HistoryDealGetDouble(dk, DEAL_COMMISSION);
   const double exitPx = HistoryDealGetDouble(dk, DEAL_PRICE);
   double entryPx = 0.0;
   bool wasBuy = ((ENUM_DEAL_TYPE)HistoryDealGetInteger(dk, DEAL_TYPE) == DEAL_TYPE_SELL);   // an OUT deal of a BUY is a SELL deal
   if(HistorySelectByPosition(pid)) {
      for(int d = 0; d < HistoryDealsTotal(); d++) {
         const ulong k2 = HistoryDealGetTicket(d);
         if(k2 != 0 && (ENUM_DEAL_ENTRY)HistoryDealGetInteger(k2, DEAL_ENTRY) == DEAL_ENTRY_IN) entryPx = HistoryDealGetDouble(k2, DEAL_PRICE);
      }
   }
   const double pts = (entryPx > 0.0) ? (wasBuy ? (exitPx - entryPx) : (entryPx - exitPx)) / _Point : 0.0;
   LogRow(StringFormat("EXIT,%s,%I64d,%s,,%s,,,,%.2f,%.0f,%s",
          TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), pid, wasBuy ? "BUY" : "SELL",
          DoubleToString(exitPx, _Digits), money, pts, why));
}

//--------------------------------------------------------------------
int OnInit()
{
   if(InpShockMinutes < 1 || InpLookbackMin < 60 || InpShockK <= 0.0 || InpTPPoints <= 0 || InpSLPoints <= 0 || InpHoldMinutes < 1)
      return INIT_PARAMETERS_INCORRECT;
   const ENUM_ACCOUNT_MARGIN_MODE mm = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   g_hedging = (mm == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
   if(!g_hedging && InpMaxOpen > 1) Print("NETTING account: trades merge into one position, so only 1 trade at a time is used.");
   g_lastBar = 0; g_lastSignal = 0; g_dayKey = -1; g_dayBlocked = false;
   return INIT_SUCCEEDED;
}

void OnTick()
{
   UpdateDay();
   ManageHold();
   const datetime bt = iTime(_Symbol, PERIOD_M1, 0);
   if(bt == 0 || bt == g_lastBar) return;
   g_lastBar = bt;
   CheckSignal();
}
