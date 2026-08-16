//+------------------------------------------------------------------+
//|                                     Auto_EA_Grid_Master_Twist.mq5|
//+------------------------------------------------------------------+
#property copyright "Senior Trading Systems Architect"
#property link      ""
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- Enums for Grid Configuration
enum ENUM_GRID_MODE {
   GRID_BUY_ONLY,       // Single-Directional (Buy)
   GRID_SELL_ONLY,      // Single-Directional (Sell)
   GRID_BIDIRECTIONAL   // Hedged (Buy & Sell Simultaneously)
};

enum ENUM_SPACING_MODE {
   SPACING_FIXED,       // Fixed Pips
   SPACING_ATR          // Dynamic ATR Volatility
};

enum ENUM_LOT_MODE {
   LOT_FIXED,           // Fixed Lot Size for all levels
   LOT_MARTINGALE       // Multiplier per grid level
};

//--- Inputs
sinput string         Grid_Settings = "--- Grid Core Settings ---";
input ENUM_GRID_MODE  InpInitialGridMode = GRID_BUY_ONLY; // Initial Grid Direction
input ENUM_SPACING_MODE InpSpacingMode = SPACING_FIXED;   // Grid Spacing Method
input int             InpSpacingPoints = 200;             // Fixed Spacing (Points)
input int             InpATR_Period = 14;                 // ATR Period (If SPACING_ATR)

sinput string         Lot_Settings = "--- Sizing & Martingale ---";
input ENUM_LOT_MODE   InpLotMode = LOT_FIXED;             // Lot Sizing Mode
input double          InpInitialLot = 0.01;               // Initial Lot Size
input double          InpMartingaleMult = 2.0;            // Martingale Multiplier
input double          InpMaxLotSize = 5.0;                // Maximum Allowed Lot Size

sinput string         Risk_Settings = "--- Trade & Risk Limits ---";
input int             InpMaxLevels = 5;                   // Max Open Levels (Per Direction)
input int             InpTakeProfitPoints = 300;          // Take Profit (Points per trade)
input int             InpStopLossPoints = 1000;           // Stop Loss (Points per trade)
input double          InpEquityHardStop = 0.0;            // Hard Equity Stop (0 = Disabled, e.g. 10000 = Close all if equity drops below 10k)

sinput string         Twist_Settings = "--- The Switch Twist ---";
input bool            InpEnableTwist = true;              // Enable Direction Switch on Consecutive Losses
input int             InpConsecutiveLosses = 2;           // Number of Consecutive Losses to trigger Switch

//--- Global Variables
CTrade         trade;
int            handleATR;
ulong          magicNumber = 999111;
ENUM_GRID_MODE g_currentMode;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(magicNumber);
   g_currentMode = InpInitialGridMode;
   
   if(InpSpacingMode == SPACING_ATR)
     {
      handleATR = iATR(_Symbol, PERIOD_CURRENT, InpATR_Period);
      if(handleATR == INVALID_HANDLE) { Print("Failed to load ATR"); return INIT_FAILED; }
     }
     
   if(InpStopLossPoints == 0 && InpEnableTwist)
     {
      Print("WARNING: The Twist requires trades to hit Stop Loss to register losses. Consider setting InpStopLossPoints > 0.");
     }

   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(InpSpacingMode == SPACING_ATR) IndicatorRelease(handleATR);
  }

//+------------------------------------------------------------------+
//| Helper: Normalize Lot Size                                       |
//+------------------------------------------------------------------+
double GetNormalizedLot(double rawLot)
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   double lot = MathFloor(rawLot / step) * step;
   if(lot < min) lot = min;
   if(lot > max) lot = max;
   if(lot > InpMaxLotSize) lot = InpMaxLotSize;
   
   return lot;
  }

//+------------------------------------------------------------------+
//| Helper: Calculate Current Grid Spacing                           |
//+------------------------------------------------------------------+
double GetGridSpacing()
  {
   if(InpSpacingMode == SPACING_FIXED)
     {
      return InpSpacingPoints * _Point;
     }
   else // ATR Mode
     {
      double atr[1];
      if(CopyBuffer(handleATR, 0, 1, 1, atr) > 0)
         return atr[0];
      return InpSpacingPoints * _Point; // Fallback
     }
  }

//+------------------------------------------------------------------+
//| Helper: Check Equity Protector                                   |
//+------------------------------------------------------------------+
void CheckEquityProtector()
  {
   if(InpEquityHardStop > 0.0)
     {
      if(AccountInfoDouble(ACCOUNT_EQUITY) <= InpEquityHardStop)
        {
         Print("EQUITY PROTECTOR TRIGGERED! Closing all trades.");
         for(int i = PositionsTotal()-1; i>=0; i--)
           {
            ulong ticket = PositionGetTicket(i);
            if(PositionGetInteger(POSITION_MAGIC) == magicNumber)
               trade.PositionClose(ticket);
           }
         ExpertRemove(); // Shut down the EA to prevent further damage
        }
     }
  }

//+------------------------------------------------------------------+
//| THE TWIST: Check History for Consecutive Losses                  |
//+------------------------------------------------------------------+
void CheckTwistLogic()
  {
   if(!InpEnableTwist) return;
   
   int buyLosses = 0;
   int sellLosses = 0;
   bool buyDone = false;
   bool sellDone = false;
   
   HistorySelect(0, TimeCurrent());
   int totalDeals = HistoryDealsTotal();
   
   // Loop backwards through closed deals
   for(int i = totalDeals - 1; i >= 0; i--)
     {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != magicNumber) continue;
      
      // We only care about deals that closed a position (Entry Out)
      if(HistoryDealGetInteger(dealTicket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      
      double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
      long dealType = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
      
      // A DEAL_TYPE_SELL closing a position means a BUY trade was closed
      if(dealType == DEAL_TYPE_SELL && !buyDone)
        {
         if(profit < 0) buyLosses++; 
         else buyDone = true; // Win breaks the losing streak
        }
        
      // A DEAL_TYPE_BUY closing a position means a SELL trade was closed
      if(dealType == DEAL_TYPE_BUY && !sellDone)
        {
         if(profit < 0) sellLosses++; 
         else sellDone = true; // Win breaks the losing streak
        }
        
      if(buyDone && sellDone) break;
     }

   // Execute The Twist
   if(buyLosses >= InpConsecutiveLosses && g_currentMode != GRID_SELL_ONLY)
     {
      Print("TWIST: ", InpConsecutiveLosses, " Buy Losses in a row. Switching Grid to SELL_ONLY.");
      g_currentMode = GRID_SELL_ONLY;
     }
   else if(sellLosses >= InpConsecutiveLosses && g_currentMode != GRID_BUY_ONLY)
     {
      Print("TWIST: ", InpConsecutiveLosses, " Sell Losses in a row. Switching Grid to BUY_ONLY.");
      g_currentMode = GRID_BUY_ONLY;
     }
  }

//+------------------------------------------------------------------+
//| Main Grid Mechanics                                              |
//+------------------------------------------------------------------+
void OnTick()
  {
   CheckEquityProtector();
   CheckTwistLogic();
   
   int buyCount = 0;
   int sellCount = 0;
   double lowestBuy = 9999999;
   double highestSell = 0;
   
   // 1. Analyze current active grid levels
   for(int i=0; i<PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetInteger(POSITION_MAGIC) == magicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         long type = PositionGetInteger(POSITION_TYPE);
         
         if(type == POSITION_TYPE_BUY)
           {
            buyCount++;
            if(openPrice < lowestBuy) lowestBuy = openPrice;
           }
         else if(type == POSITION_TYPE_SELL)
           {
            sellCount++;
            if(openPrice > highestSell) highestSell = openPrice;
           }
        }
     }
     
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spacing = GetGridSpacing();
   
   // 2. Process BUY Grid
   if(g_currentMode == GRID_BUY_ONLY || g_currentMode == GRID_BIDIRECTIONAL)
     {
      if(buyCount == 0)
        {
         // Open initial level
         double sl = (InpStopLossPoints > 0) ? ask - (InpStopLossPoints * _Point) : 0;
         double tp = (InpTakeProfitPoints > 0) ? ask + (InpTakeProfitPoints * _Point) : 0;
         trade.Buy(GetNormalizedLot(InpInitialLot), _Symbol, ask, sl, tp, "Grid Buy Base");
        }
      else if(buyCount < InpMaxLevels)
        {
         // Price dropped by 'spacing', time to buy the dip
         if(ask <= lowestBuy - spacing)
           {
            double targetLot = InpInitialLot;
            if(InpLotMode == LOT_MARTINGALE) targetLot = InpInitialLot * MathPow(InpMartingaleMult, buyCount);
            
            double sl = (InpStopLossPoints > 0) ? ask - (InpStopLossPoints * _Point) : 0;
            double tp = (InpTakeProfitPoints > 0) ? ask + (InpTakeProfitPoints * _Point) : 0;
            trade.Buy(GetNormalizedLot(targetLot), _Symbol, ask, sl, tp, "Grid Buy Level " + IntegerToString(buyCount));
           }
        }
     }
     
   // 3. Process SELL Grid
   if(g_currentMode == GRID_SELL_ONLY || g_currentMode == GRID_BIDIRECTIONAL)
     {
      if(sellCount == 0)
        {
         // Open initial level
         double sl = (InpStopLossPoints > 0) ? bid + (InpStopLossPoints * _Point) : 0;
         double tp = (InpTakeProfitPoints > 0) ? bid - (InpTakeProfitPoints * _Point) : 0;
         trade.Sell(GetNormalizedLot(InpInitialLot), _Symbol, bid, sl, tp, "Grid Sell Base");
        }
      else if(sellCount < InpMaxLevels)
        {
         // Price rose by 'spacing', time to sell the rally
         if(bid >= highestSell + spacing)
           {
            double targetLot = InpInitialLot;
            if(InpLotMode == LOT_MARTINGALE) targetLot = InpInitialLot * MathPow(InpMartingaleMult, sellCount);
            
            double sl = (InpStopLossPoints > 0) ? bid + (InpStopLossPoints * _Point) : 0;
            double tp = (InpTakeProfitPoints > 0) ? bid - (InpTakeProfitPoints * _Point) : 0;
            trade.Sell(GetNormalizedLot(targetLot), _Symbol, bid, sl, tp, "Grid Sell Level " + IntegerToString(sellCount));
           }
        }
     }
  }
//+------------------------------------------------------------------+