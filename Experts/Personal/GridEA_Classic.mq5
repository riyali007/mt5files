//+------------------------------------------------------------------+
//|  GridEA_Classic.mq5                                              |
//|  Classic Neutral Grid EA — Symmetric Buy/Sell Limit Orders        |
//|  Both directions placed at fixed intervals above & below price    |
//|  Includes: RSI Filter, ATR Step, Trend Filter (MA), Max DD Stop  |
//+------------------------------------------------------------------+
#property copyright "Grid EA — Classic Variant"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\PositionInfo.mqh>

CTrade         trade;
COrderInfo     orderInfo;
CPositionInfo  posInfo;

//--- Input Parameters
input group "=== Grid Settings ==="
input double   InpLotSize        = 0.01;    // Lot size per order
input int      InpGridStep       = 20;      // Grid step in pips
input int      InpMaxOrders      = 10;      // Max total open orders (buy+sell)
input int      InpTakeProfitPips = 20;      // Take profit in pips
input bool     InpUseATRStep     = true;    // Use ATR-based grid step (overrides fixed step)
input int      InpATRPeriod      = 14;      // ATR period
input double   InpATRMultiplier  = 1.0;     // ATR multiplier for grid step

input group "=== Risk Management ==="
input double   InpMaxDrawdownPct = 20.0;    // Max drawdown % before closing all orders
input int      InpMaxFlips       = 2;       // Max consecutive flips before pausing (not used in Classic)

input group "=== RSI Filter ==="
input bool     InpUseRSIFilter   = true;    // Enable RSI filter
input int      InpRSIPeriod      = 14;      // RSI period
input int      InpRSIOverbought  = 70;      // RSI overbought — suppress buy orders above this
input int      InpRSIOversold    = 30;      // RSI oversold — suppress sell orders below this

input group "=== Trend Filter ==="
input bool     InpUseTrendFilter = true;    // Enable MA trend filter
input int      InpMAPeriod       = 50;      // MA period for trend detection
input ENUM_MA_METHOD InpMAMethod = MODE_EMA; // MA method

input group "=== Session Filter ==="
input bool     InpUseSession     = true;    // Only trade during active sessions
input int      InpSessionStart   = 7;       // Session start hour (server time)
input int      InpSessionEnd     = 20;      // Session end hour (server time)

input group "=== EA Identity ==="
input int      InpMagicNumber    = 111001;  // Magic number

//--- Global Variables
double   pipValue;
double   gridStepPrice;
int      rsiHandle, maHandle, atrHandle;
double   initialEquity;
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);

   pipValue      = _Point * ((_Digits == 5 || _Digits == 3) ? 10 : 1);
   initialEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   rsiHandle = iRSI(_Symbol, PERIOD_CURRENT, InpRSIPeriod, PRICE_CLOSE);
   maHandle  = iMA(_Symbol, PERIOD_CURRENT, InpMAPeriod, 0, InpMAMethod, PRICE_CLOSE);
   atrHandle = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);

   if(rsiHandle == INVALID_HANDLE || maHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create indicator handles.");
      return INIT_FAILED;
   }

   Print("GridEA Classic initialized. Magic=", InpMagicNumber);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(rsiHandle);
   IndicatorRelease(maHandle);
   IndicatorRelease(atrHandle);
}

//+------------------------------------------------------------------+
void OnTick()
{
   //--- Check global drawdown stop
   if(CheckDrawdown()) return;

   //--- Only act on new bar
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBar == lastBarTime) return;
   lastBarTime = currentBar;

   //--- Session filter
   if(InpUseSession)
   {
      int hour = TimeHour(TimeCurrent());
      if(hour < InpSessionStart || hour >= InpSessionEnd) return;
   }

   //--- Get indicator values
   double rsi[], ma[], atr[];
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(ma,  true);
   ArraySetAsSeries(atr, true);

   if(CopyBuffer(rsiHandle, 0, 1, 1, rsi) <= 0) return;
   if(CopyBuffer(maHandle,  0, 1, 1, ma)  <= 0) return;
   if(CopyBuffer(atrHandle, 0, 1, 1, atr) <= 0) return;

   double currentRSI = rsi[0];
   double currentMA  = ma[0];
   double currentATR = atr[0];
   double closePrice = iClose(_Symbol, PERIOD_CURRENT, 1);
   double ask        = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid        = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   //--- Calculate dynamic grid step
   if(InpUseATRStep)
      gridStepPrice = NormalizeDouble(currentATR * InpATRMultiplier, _Digits);
   else
      gridStepPrice = InpGridStep * pipValue;

   double tpDistance = InpTakeProfitPips * pipValue;

   //--- Count existing orders by this EA
   int buyOrders  = CountOrders(ORDER_TYPE_BUY_STOP)  + CountPositions(POSITION_TYPE_BUY);
   int sellOrders = CountOrders(ORDER_TYPE_SELL_STOP) + CountPositions(POSITION_TYPE_SELL);
   int totalOrders = buyOrders + sellOrders;

   if(totalOrders >= InpMaxOrders) return;

   //--- RSI Filter
   bool canBuy  = true;
   bool canSell = true;
   if(InpUseRSIFilter)
   {
      if(currentRSI > InpRSIOverbought) canBuy  = false; // overbought — skip buy
      if(currentRSI < InpRSIOversold)   canSell = false; // oversold — skip sell
   }

   //--- Trend Filter
   if(InpUseTrendFilter)
   {
      if(closePrice < currentMA) canBuy  = false; // below MA — skip buy
      if(closePrice > currentMA) canSell = false; // above MA — skip sell
   }

   //--- Place Buy Stop above close
   if(canBuy && buyOrders < (InpMaxOrders / 2))
   {
      double buyEntry = NormalizeDouble(closePrice + gridStepPrice, _Digits);
      double buyTP    = NormalizeDouble(buyEntry + tpDistance, _Digits);

      if(!OrderExists(ORDER_TYPE_BUY_STOP, buyEntry))
         trade.BuyStop(InpLotSize, buyEntry, _Symbol, 0, buyTP, ORDER_TIME_GTC, 0, "Grid_Buy");
   }

   //--- Place Sell Stop below close
   if(canSell && sellOrders < (InpMaxOrders / 2))
   {
      double sellEntry = NormalizeDouble(closePrice - gridStepPrice, _Digits);
      double sellTP    = NormalizeDouble(sellEntry - tpDistance, _Digits);

      if(!OrderExists(ORDER_TYPE_SELL_STOP, sellEntry))
         trade.SellStop(InpLotSize, sellEntry, _Symbol, 0, sellTP, ORDER_TIME_GTC, 0, "Grid_Sell");
   }
}

//+------------------------------------------------------------------+
bool CheckDrawdown()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double drawdownPct   = ((initialEquity - currentEquity) / initialEquity) * 100.0;

   if(drawdownPct >= InpMaxDrawdownPct)
   {
      Print("MAX DRAWDOWN REACHED (", DoubleToString(drawdownPct, 2), "%). Closing all EA orders.");
      CloseAllEAOrders();
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void CloseAllEAOrders()
{
   // Close all positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
         if(posInfo.Magic() == InpMagicNumber && posInfo.Symbol() == _Symbol)
            trade.PositionClose(posInfo.Ticket());
   }
   // Delete all pending orders
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(orderInfo.SelectByIndex(i))
         if(orderInfo.Magic() == InpMagicNumber && orderInfo.Symbol() == _Symbol)
            trade.OrderDelete(orderInfo.Ticket());
   }
}

//+------------------------------------------------------------------+
int CountOrders(ENUM_ORDER_TYPE type)
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(orderInfo.SelectByIndex(i))
         if(orderInfo.Magic() == InpMagicNumber && orderInfo.Symbol() == _Symbol && orderInfo.OrderType() == type)
            count++;
   }
   return count;
}

//+------------------------------------------------------------------+
int CountPositions(ENUM_POSITION_TYPE type)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
         if(posInfo.Magic() == InpMagicNumber && posInfo.Symbol() == _Symbol && posInfo.PositionType() == type)
            count++;
   }
   return count;
}

//+------------------------------------------------------------------+
bool OrderExists(ENUM_ORDER_TYPE type, double price)
{
   double tolerance = gridStepPrice * 0.3;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(orderInfo.SelectByIndex(i))
         if(orderInfo.Magic() == InpMagicNumber && orderInfo.Symbol() == _Symbol)
            if(orderInfo.OrderType() == type && MathAbs(orderInfo.PriceOpen() - price) < tolerance)
               return true;
   }
   return false;
}

//+------------------------------------------------------------------+
int TimeHour(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return dt.hour;
}
//+------------------------------------------------------------------+