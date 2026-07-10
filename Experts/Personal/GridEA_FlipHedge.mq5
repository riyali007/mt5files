//+------------------------------------------------------------------+
//|  GridEA_FlipHedge.mq5                                            |
//|  Flip-Hedge Grid EA for MetaTrader 5                             |
//|  Places OCO Buy Stop + Sell Stop each new candle.                |
//|  When one side fills, cancels the other.                         |
//|  If price reverses past 2x grid step, flips direction.           |
//+------------------------------------------------------------------+
#property copyright "GridEA FlipHedge"
#property version   "2.00"

#include <Trade\Trade.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\PositionInfo.mqh>

//--- Inputs
input group "=== Grid ==="
input double InpLot           = 0.01;  // Lot size
input int    InpGridPips      = 15;    // Grid step (pips from candle close)
input int    InpTPPips        = 15;    // Take profit (pips)
input int    InpFlipBonusPips = 10;    // Extra TP pips added after flip
input bool   InpUseATR        = true;  // Use ATR for grid step
input int    InpATRPeriod     = 14;    // ATR period
input double InpATRMult       = 0.8;   // ATR multiplier

input group "=== Risk ==="
input double InpMaxDDPct  = 15.0; // Max drawdown % to close all
input int    InpMaxFlips  = 2;    // Max flips before giving up

input group "=== RSI Filter ==="
input bool InpUseRSI    = true; // Enable RSI filter
input int  InpRSIPeriod = 14;   // RSI period
input int  InpRSIOB     = 65;   // Overbought level (skip buys)
input int  InpRSIOS     = 35;   // Oversold level (skip sells)

input group "=== Trend Filter ==="
input bool           InpUseTrend = false;    // Enable MA trend filter
input int            InpMAPeriod = 50;       // MA period
input ENUM_MA_METHOD InpMAMethod = MODE_EMA; // MA method

input group "=== Session ==="
input bool InpUseSession  = true; // Enable session filter
input int  InpSessionFrom = 7;    // Start hour (server time)
input int  InpSessionTo   = 20;   // End hour (server time)

input group "=== EA ==="
input int InpMagic = 111002; // Magic number

//--- Objects
CTrade        g_trade;
COrderInfo    g_order;
CPositionInfo g_pos;

//--- Indicator handles
int g_hRSI;
int g_hMA;
int g_hATR;

//--- State
double   g_pip;
double   g_step;
double   g_startEquity;
datetime g_lastBar    = 0;
bool     g_active     = false;
int      g_flips      = 0;
ulong    g_ticketBuy  = 0;
ulong    g_ticketSell = 0;
bool     g_buyFilled  = false;
bool     g_sellFilled = false;

//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(10);

   g_pip = _Point;
   if(_Digits == 5 || _Digits == 3)
      g_pip = _Point * 10;

   g_startEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   g_hRSI = iRSI(_Symbol, PERIOD_CURRENT, InpRSIPeriod, PRICE_CLOSE);
   g_hMA  = iMA(_Symbol, PERIOD_CURRENT, InpMAPeriod, 0, InpMAMethod, PRICE_CLOSE);
   g_hATR = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);

   if(g_hRSI == INVALID_HANDLE || g_hMA == INVALID_HANDLE || g_hATR == INVALID_HANDLE)
   {
      Print("ERROR: Indicator handle creation failed.");
      return INIT_FAILED;
   }

   Print("GridEA FlipHedge v2.00 ready. Magic=", InpMagic);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(g_hRSI);
   IndicatorRelease(g_hMA);
   IndicatorRelease(g_hATR);
}

//+------------------------------------------------------------------+
void OnTick()
{
   //--- Drawdown guard
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_startEquity > 0)
   {
      double dd = (g_startEquity - equity) / g_startEquity * 100.0;
      if(dd >= InpMaxDDPct)
      {
         Print("Drawdown limit hit (", DoubleToString(dd,2), "%). Closing all.");
         CloseAll();
         return;
      }
   }

   //--- ATR for step size
   double atrBuf[1];
   if(CopyBuffer(g_hATR, 0, 1, 1, atrBuf) == 1)
      g_step = InpUseATR ? NormalizeDouble(atrBuf[0] * InpATRMult, _Digits)
                         : InpGridPips * g_pip;
   else
      g_step = InpGridPips * g_pip;

   //--- If a cycle is running, manage it
   if(g_active)
   {
      ManageCycle();
      return;
   }

   //--- New bar check
   datetime bar0 = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(bar0 == g_lastBar) return;
   g_lastBar = bar0;

   //--- Session filter
   if(InpUseSession)
   {
      MqlDateTime mdt;
      TimeToStruct(TimeCurrent(), mdt);
      if(mdt.hour < InpSessionFrom || mdt.hour >= InpSessionTo) return;
   }

   //--- Read indicators from previous closed bar
   double rsiBuf[1], maBuf[1];
   if(CopyBuffer(g_hRSI, 0, 1, 1, rsiBuf) != 1) return;
   if(CopyBuffer(g_hMA,  0, 1, 1, maBuf)  != 1) return;

   double rsi   = rsiBuf[0];
   double ma    = maBuf[0];
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);

   bool canBuy  = true;
   bool canSell = true;

   if(InpUseRSI)
   {
      if(rsi >= InpRSIOB) canBuy  = false;
      if(rsi <= InpRSIOS) canSell = false;
   }
   if(InpUseTrend)
   {
      if(close < ma) canBuy  = false;
      if(close > ma) canSell = false;
   }

   if(!canBuy && !canSell) return;

   //--- Place pending orders
   double tpDist    = InpTPPips * g_pip;
   double buyEntry  = NormalizeDouble(close + g_step, _Digits);
   double sellEntry = NormalizeDouble(close - g_step, _Digits);
   double buyTP     = NormalizeDouble(buyEntry  + tpDist, _Digits);
   double sellTP    = NormalizeDouble(sellEntry - tpDist, _Digits);

   g_ticketBuy  = 0;
   g_ticketSell = 0;
   g_flips      = 0;
   g_buyFilled  = false;
   g_sellFilled = false;

   if(canBuy)
      if(g_trade.BuyStop(InpLot, buyEntry, _Symbol, 0.0, buyTP, ORDER_TIME_GTC, 0, "FG_Buy"))
         g_ticketBuy = g_trade.ResultOrder();

   if(canSell)
      if(g_trade.SellStop(InpLot, sellEntry, _Symbol, 0.0, sellTP, ORDER_TIME_GTC, 0, "FG_Sell"))
         g_ticketSell = g_trade.ResultOrder();

   if(g_ticketBuy > 0 || g_ticketSell > 0)
      g_active = true;
}

//+------------------------------------------------------------------+
void ManageCycle()
{
   bool buyPending  = IsOrderPending(g_ticketBuy);
   bool sellPending = IsOrderPending(g_ticketSell);
   bool buyPos      = IsPositionOpen(g_ticketBuy);
   bool sellPos     = IsPositionOpen(g_ticketSell);

   //--- Both gone — cycle complete
   if(!buyPending && !sellPending && !buyPos && !sellPos)
   {
      ResetCycle();
      return;
   }

   //--- Buy filled → cancel sell pending (OCO)
   if(buyPos && sellPending)
   {
      g_trade.OrderDelete(g_ticketSell);
      g_ticketSell = 0;
      g_buyFilled  = true;
      return;
   }

   //--- Sell filled → cancel buy pending (OCO)
   if(sellPos && buyPending)
   {
      g_trade.OrderDelete(g_ticketBuy);
      g_ticketBuy  = 0;
      g_sellFilled = true;
      return;
   }

   //--- Active buy — check flip condition
   if(buyPos && !sellPending && !sellPos)
   {
      double openPrice = GetPositionOpen(g_ticketBuy);
      double flipLevel = NormalizeDouble(openPrice - g_step * 2.0, _Digits);
      double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      if(bid <= flipLevel)
      {
         if(g_flips >= InpMaxFlips)
         {
            Print("Max flips reached. Closing buy.");
            g_trade.PositionClose(g_ticketBuy);
            ResetCycle();
            return;
         }

         g_flips++;
         g_trade.PositionClose(g_ticketBuy);
         g_ticketBuy = 0;

         double bonusDist = (InpTPPips + InpFlipBonusPips + InpGridPips) * g_pip;
         double newTP     = NormalizeDouble(bid - bonusDist, _Digits);

         if(g_trade.Sell(InpLot, _Symbol, 0.0, newTP, "FG_SellFlip"))
         {
            g_ticketSell = g_trade.ResultOrder();
            g_sellFilled = true;
            Print("FLIP ", g_flips, ": Buy closed → Sell opened. TP=", DoubleToString(newTP,_Digits));
         }
         else
            ResetCycle();
      }
   }

   //--- Active sell — check flip condition
   if(sellPos && !buyPending && !buyPos)
   {
      double openPrice = GetPositionOpen(g_ticketSell);
      double flipLevel = NormalizeDouble(openPrice + g_step * 2.0, _Digits);
      double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(ask >= flipLevel)
      {
         if(g_flips >= InpMaxFlips)
         {
            Print("Max flips reached. Closing sell.");
            g_trade.PositionClose(g_ticketSell);
            ResetCycle();
            return;
         }

         g_flips++;
         g_trade.PositionClose(g_ticketSell);
         g_ticketSell = 0;

         double bonusDist = (InpTPPips + InpFlipBonusPips + InpGridPips) * g_pip;
         double newTP     = NormalizeDouble(ask + bonusDist, _Digits);

         if(g_trade.Buy(InpLot, _Symbol, 0.0, newTP, "FG_BuyFlip"))
         {
            g_ticketBuy = g_trade.ResultOrder();
            g_buyFilled = true;
            Print("FLIP ", g_flips, ": Sell closed → Buy opened. TP=", DoubleToString(newTP,_Digits));
         }
         else
            ResetCycle();
      }
   }
}

//+------------------------------------------------------------------+
void ResetCycle()
{
   g_active     = false;
   g_ticketBuy  = 0;
   g_ticketSell = 0;
   g_flips      = 0;
   g_buyFilled  = false;
   g_sellFilled = false;
}

//+------------------------------------------------------------------+
void CloseAll()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(g_pos.SelectByIndex(i))
         if(g_pos.Magic() == InpMagic && g_pos.Symbol() == _Symbol)
            g_trade.PositionClose(g_pos.Ticket());

   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(g_order.SelectByIndex(i))
         if(g_order.Magic() == InpMagic && g_order.Symbol() == _Symbol)
            g_trade.OrderDelete(g_order.Ticket());

   ResetCycle();
}

//+------------------------------------------------------------------+
bool IsOrderPending(ulong ticket)
{
   if(ticket == 0) return false;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(g_order.SelectByIndex(i) && g_order.Ticket() == ticket)
         return true;
   return false;
}

//+------------------------------------------------------------------+
bool IsPositionOpen(ulong ticket)
{
   if(ticket == 0) return false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(g_pos.SelectByIndex(i) && g_pos.Ticket() == ticket)
         return true;
   return false;
}

//+------------------------------------------------------------------+
double GetPositionOpen(ulong ticket)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(g_pos.SelectByIndex(i) && g_pos.Ticket() == ticket)
         return g_pos.PriceOpen();
   return 0.0;
}
//+------------------------------------------------------------------+
