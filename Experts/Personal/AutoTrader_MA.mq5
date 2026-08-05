//+------------------------------------------------------------------+
//|                                                AutoTrader_MA.mq5 |
//+------------------------------------------------------------------+
#property copyright "Your Name"
#property version   "1.12"

#property tester_indicator "HMA.ex5"
#property tester_indicator "MVWAP.ex5"

#include <Trade\Trade.mqh>

enum ENUM_CUSTOM_MA_TYPE
  {
   CUSTOM_EMA = 1,
   CUSTOM_WMA = 2,
   CUSTOM_HMA = 3,
   CUSTOM_VWAP = 4
  };

enum ENUM_INITIAL_SL
  {
   SL_NONE = 0,               // No Hard Stop Loss
   SL_FIXED_POINTS = 1,       // Fixed Stop Loss in Points
   SL_CROSSOVER_CANDLE = 2,   // SL at High/Low of Crossover Candle
   SL_MA_LEVEL = 3            // SL placed at MA Level
  };

enum ENUM_TRAILING_MA
  {
   TRAIL_MA1 = 1, // Follow MA 1 (Fast)
   TRAIL_MA2 = 2, // Follow MA 2 (Entry)
   TRAIL_MA3 = 3  // Follow MA 3 (Exit)
  };

input string               InpTradeSettings  = "=== Trade Settings ===";
input double               InpLotSize        = 0.10;
input ulong                InpMagicNumber    = 123456;

input string               InpMAPartialSet   = "=== MA Cross Partials ===";
input int                  InpMaxMAPartials  = 1;             // Max Number of MA Partials (e.g., 1-20)
input double               InpMAPartialPct   = 50.0;          // % of Initial Lot Size to close per MA Cross

input string               InpRRPartialSet   = "=== Risk-to-Reward Partials ===";
input bool                 InpUseRRPartials  = true;          // Enable RR Partials
input int                  InpMaxRRPartials  = 3;             // Max Number of RR Partials (e.g., 1-20)
input double               InpRRTarget       = 1.0;           // First RR Target (e.g. 1.0 = 1R Target)
input double               InpRRTargetStep   = 1.0;           // Distance to Next RR Target (e.g. +1.0R for next)
input double               InpRRPartialPct   = 30.0;          // % of Initial Lot Size to close per RR Target

input string               InpSLSettings     = "=== Initial Stop Loss ===";
input ENUM_INITIAL_SL      InpInitialSL      = SL_MA_LEVEL;  
input int                  InpSLPoints       = 150;           
input int                  InpSLCandleBuffer = 20;            

input string               InpTrailSettings  = "=== Trailing SL Settings ===";
input bool                 InpUseTrailingSL  = false;         
input ENUM_TRAILING_MA     InpTrailingMA     = TRAIL_MA2;     
input int                  InpTrailingDist   = 50;            

input string               InpBESettings     = "=== Break Even Settings ===";
input bool                 InpUseBreakEven   = true;          
input int                  InpBEActivation   = 100;           
input int                  InpBEBuffer       = 10;            

input string               InpFilterSettings = "=== Filter Settings ===";
input int                  InpMinMADistance  = 20;            

input string               InpTimeSettings   = "=== Timeframe Settings ===";
input ENUM_TIMEFRAMES      InpHTF            = PERIOD_M5;         

input string               InpMASettings     = "=== MA Settings ===";
input ENUM_CUSTOM_MA_TYPE  InpMAType         = CUSTOM_EMA;        
input int                  InpMA1_Period     = 9;                 
input int                  InpMA2_Period     = 21;                
input int                  InpMA3_Period     = 50;                

input string               InpColorSettings  = "=== Color Settings ===";
input color                InpColorMA1       = clrLime;           
input color                InpColorMA2       = clrRed;            
input color                InpColorMA3       = clrDeepSkyBlue;    

CTrade         trade;
int            handle_MA1, handle_MA2, handle_MA3;

bool           block_buy = false;
bool           block_sell = false;

//--- Internal Trade Memory
struct STradeMemory
  {
   ulong  ticket;
   double entry_price;
   double initial_sl;
   int    ma_partials_taken;
   int    rr_partials_taken;
  };
STradeMemory ActiveTrades[];

//+------------------------------------------------------------------+
//| Memory & Drawing Helpers                                         |
//+------------------------------------------------------------------+
int FindTradeInMemory(ulong ticket)
  {
   for(int i = 0; i < ArraySize(ActiveTrades); i++) if(ActiveTrades[i].ticket == ticket) return i;
   return -1;
  }

void DrawMALabel(string obj_name, datetime time, double price, color clr, string text)
  {
   if(ObjectFind(0, obj_name) < 0)
     {
      ObjectCreate(0, obj_name, OBJ_TEXT, 0, time, price);
      ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, obj_name, OBJPROP_FONTSIZE, 10);
      ObjectSetString(0, obj_name, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, obj_name, OBJPROP_ANCHOR, ANCHOR_LEFT);
     }
   else ObjectMove(0, obj_name, 0, time, price);
   ObjectSetString(0, obj_name, OBJPROP_TEXT, text);
  }

void DrawTradeLevel(string base_name, datetime time, double price, color clr, ENUM_LINE_STYLE style, string text)
  {
   string line_name = "RR_" + base_name + "_Line";
   string text_name = "RR_" + base_name + "_Text";

   if(ObjectFind(0, line_name) < 0)
     {
      ObjectCreate(0, line_name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, line_name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, line_name, OBJPROP_STYLE, style);
      ObjectSetInteger(0, line_name, OBJPROP_WIDTH, 1);
     }
   else ObjectMove(0, line_name, 0, 0, price);

   if(ObjectFind(0, text_name) < 0)
     {
      ObjectCreate(0, text_name, OBJ_TEXT, 0, time, price);
      ObjectSetInteger(0, text_name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, text_name, OBJPROP_FONTSIZE, 10);
      ObjectSetString(0, text_name, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, text_name, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
     }
   else ObjectMove(0, text_name, 0, time, price);
   
   ObjectSetString(0, text_name, OBJPROP_TEXT, text);
  }

void CleanTradeLevels()
  {
   ObjectDelete(0, "RR_Entry_Line");     ObjectDelete(0, "RR_Entry_Text");
   ObjectDelete(0, "RR_CurrentSL_Line"); ObjectDelete(0, "RR_CurrentSL_Text");
   ObjectDelete(0, "RR_InitialSL_Line"); ObjectDelete(0, "RR_InitialSL_Text");
   ObjectDelete(0, "RR_TP_Line");        ObjectDelete(0, "RR_TP_Text");
  }

//+------------------------------------------------------------------+
//| EA Initialization                                                |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);
   ArrayResize(ActiveTrades, 0);
   
   if(InpMAType == CUSTOM_EMA)
     {
      handle_MA1 = iMA(_Symbol, InpHTF, InpMA1_Period, 0, MODE_EMA, PRICE_CLOSE);
      handle_MA2 = iMA(_Symbol, InpHTF, InpMA2_Period, 0, MODE_EMA, PRICE_CLOSE);
      handle_MA3 = iMA(_Symbol, InpHTF, InpMA3_Period, 0, MODE_EMA, PRICE_CLOSE);
     }
   else if(InpMAType == CUSTOM_WMA)
     {
      handle_MA1 = iMA(_Symbol, InpHTF, InpMA1_Period, 0, MODE_LWMA, PRICE_CLOSE);
      handle_MA2 = iMA(_Symbol, InpHTF, InpMA2_Period, 0, MODE_LWMA, PRICE_CLOSE);
      handle_MA3 = iMA(_Symbol, InpHTF, InpMA3_Period, 0, MODE_LWMA, PRICE_CLOSE);
     }
   else if(InpMAType == CUSTOM_HMA)
     {
      handle_MA1 = iCustom(_Symbol, InpHTF, "HMA", InpMA1_Period, PRICE_CLOSE, InpColorMA1);
      handle_MA2 = iCustom(_Symbol, InpHTF, "HMA", InpMA2_Period, PRICE_CLOSE, InpColorMA2);
      handle_MA3 = iCustom(_Symbol, InpHTF, "HMA", InpMA3_Period, PRICE_CLOSE, InpColorMA3);
     }
   else if(InpMAType == CUSTOM_VWAP)
     {
      handle_MA1 = iCustom(_Symbol, InpHTF, "MVWAP", InpMA1_Period, InpColorMA1);
      handle_MA2 = iCustom(_Symbol, InpHTF, "MVWAP", InpMA2_Period, InpColorMA2);
      handle_MA3 = iCustom(_Symbol, InpHTF, "MVWAP", InpMA3_Period, InpColorMA3);
     }

   if(handle_MA1 == INVALID_HANDLE || handle_MA2 == INVALID_HANDLE || handle_MA3 == INVALID_HANDLE) return(INIT_FAILED);
   
   if(!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE))
     {
      if(InpHTF == _Period) 
        {
         ChartIndicatorAdd(0, 0, handle_MA1);
         ChartIndicatorAdd(0, 0, handle_MA2);
         ChartIndicatorAdd(0, 0, handle_MA3);
        }
     }
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   IndicatorRelease(handle_MA1);
   IndicatorRelease(handle_MA2);
   IndicatorRelease(handle_MA3);
   ObjectDelete(0, "Label_MA1");
   ObjectDelete(0, "Label_MA2");
   ObjectDelete(0, "Label_MA3");
   CleanTradeLevels();
  }

void OnTick()
  {
   datetime current_time = iTime(_Symbol, _Period, 0);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   double MA1[], MA2[], MA3[];
   ArraySetAsSeries(MA1, true); ArraySetAsSeries(MA2, true); ArraySetAsSeries(MA3, true);
   
   if(CopyBuffer(handle_MA1, 0, 0, 3, MA1) <= 0) return;
   if(CopyBuffer(handle_MA2, 0, 0, 3, MA2) <= 0) return;
   if(CopyBuffer(handle_MA3, 0, 0, 3, MA3) <= 0) return;

   //--- 1. VISUAL MA LABELS
   if(!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE))
     {
      DrawMALabel("Label_MA1", current_time, MA1[0], InpColorMA1, " ◄ MA1 (Fast)");
      DrawMALabel("Label_MA2", current_time, MA2[0], InpColorMA2, " ◄ MA2 (Entry)");
      DrawMALabel("Label_MA3", current_time, MA3[0], InpColorMA3, " ◄ MA3 (Exit)");
     }

   //--- 2. SYNC TRADE MEMORY
   for(int i = ArraySize(ActiveTrades) - 1; i >= 0; i--)
     {
      if(!PositionSelectByTicket(ActiveTrades[i].ticket)) ArrayRemove(ActiveTrades, i, 1);
     }
     
   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong tkt = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
        {
         if(FindTradeInMemory(tkt) < 0)
           {
            STradeMemory new_trade;
            new_trade.ticket = tkt;
            new_trade.entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
            new_trade.initial_sl = PositionGetDouble(POSITION_SL);
            new_trade.ma_partials_taken = 0;
            new_trade.rr_partials_taken = 0;
            
            ArrayResize(ActiveTrades, ArraySize(ActiveTrades) + 1);
            ActiveTrades[ArraySize(ActiveTrades) - 1] = new_trade;
           }
        }
     }

   //--- 3. VISUAL HUD: DYNAMIC RR LEVELS ON CHART
   if(PositionsTotal() > 0 && ArraySize(ActiveTrades) > 0)
     {
      ulong ticket = ActiveTrades[0].ticket;
      if(PositionSelectByTicket(ticket))
        {
         long pos_type = PositionGetInteger(POSITION_TYPE);
         double entry = ActiveTrades[0].entry_price;
         double init_sl = ActiveTrades[0].initial_sl;
         double curr_sl = PositionGetDouble(POSITION_SL);
         
         datetime future_time = current_time + (PeriodSeconds(_Period) * 3); 

         DrawTradeLevel("Entry", future_time, entry, clrSilver, STYLE_SOLID, " ◄ Entry");
         
         if(curr_sl > 0) DrawTradeLevel("CurrentSL", future_time, curr_sl, clrRed, STYLE_SOLID, " ◄ Current SL");
            
         if(init_sl > 0)
           {
            DrawTradeLevel("InitialSL", future_time, init_sl, clrDarkRed, STYLE_DOT, " ◄ Initial SL (Risk)");
            
            if(InpUseRRPartials && ActiveTrades[0].rr_partials_taken < InpMaxRRPartials)
              {
               double risk = MathAbs(entry - init_sl);
               double curr_target_multiplier = InpRRTarget + (ActiveTrades[0].rr_partials_taken * InpRRTargetStep);
               double target_price = (pos_type == POSITION_TYPE_BUY) ? (entry + (risk * curr_target_multiplier)) : (entry - (risk * curr_target_multiplier));
               
               DrawTradeLevel("TP", future_time, target_price, clrLimeGreen, STYLE_SOLID, " ◄ Next RR Target (" + DoubleToString(curr_target_multiplier, 1) + "R)");
              }
            else ObjectDelete(0, "RR_TP_Line"); 
           }
        }
     }
   else CleanTradeLevels(); 

   //--- 4. BREAK EVEN & TRAILING SL MANAGEMENT
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
        {
         long pos_type = PositionGetInteger(POSITION_TYPE);
         double entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
         double current_sl = PositionGetDouble(POSITION_SL);
         double current_tp = PositionGetDouble(POSITION_TP);
         double new_sl = current_sl;

         if(InpUseBreakEven)
           {
            if(pos_type == POSITION_TYPE_BUY && bid >= entry_price + (InpBEActivation * _Point))
              {
               double be_sl = entry_price + (InpBEBuffer * _Point);
               if(new_sl < be_sl) new_sl = be_sl;
              }
            else if(pos_type == POSITION_TYPE_SELL && ask <= entry_price - (InpBEActivation * _Point))
              {
               double be_sl = entry_price - (InpBEBuffer * _Point);
               if(new_sl > be_sl || new_sl == 0) new_sl = be_sl;
              }
           }

         if(InpUseTrailingSL) 
           {
            double trail_ma_value = 0;
            if(InpTrailingMA == TRAIL_MA1) trail_ma_value = MA1[0];
            else if(InpTrailingMA == TRAIL_MA2) trail_ma_value = MA2[0];
            else if(InpTrailingMA == TRAIL_MA3) trail_ma_value = MA3[0];

            if(pos_type == POSITION_TYPE_BUY)
              {
               double ma_sl = trail_ma_value - (InpTrailingDist * _Point);
               if(new_sl < ma_sl) new_sl = ma_sl; 
              }
            else if(pos_type == POSITION_TYPE_SELL)
              {
               double ma_sl = trail_ma_value + (InpTrailingDist * _Point);
               if(new_sl > ma_sl || new_sl == 0) new_sl = ma_sl; 
              }
           }

         new_sl = NormalizeDouble(new_sl, _Digits);
         if(pos_type == POSITION_TYPE_BUY && new_sl > current_sl + (2 * _Point)) trade.PositionModify(ticket, new_sl, current_tp);
         else if(pos_type == POSITION_TYPE_SELL && (new_sl < current_sl - (2 * _Point) || (current_sl == 0 && new_sl > 0))) trade.PositionModify(ticket, new_sl, current_tp);
        }
     }

   //--- 5. CALCULATE ON NEW BAR CROSSOVERS
   static datetime last_time = 0;
   bool MA1_x_up_MA2 = false, MA1_x_dn_MA2 = false;
   bool MA1_x_up_MA3 = false, MA1_x_dn_MA3 = false;
   bool new_bar = false;

   if(current_time != last_time) 
     {
      new_bar = true;
      last_time = current_time;
      
      MA1_x_up_MA2 = (MA1[1] > MA2[1] && MA1[2] <= MA2[2]);
      MA1_x_dn_MA2 = (MA1[1] < MA2[1] && MA1[2] >= MA2[2]);
      MA1_x_up_MA3 = (MA1[1] > MA3[1] && MA1[2] <= MA3[2]);
      MA1_x_dn_MA3 = (MA1[1] < MA3[1] && MA1[2] >= MA3[2]);
     }

   double min_vol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double step_vol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   //--- 6. MANAGE CLOSES & MULTI-PARTIALS
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
        {
         long pos_type = PositionGetInteger(POSITION_TYPE);
         double current_vol = PositionGetDouble(POSITION_VOLUME);
         
         int mem_idx = FindTradeInMemory(ticket);
         if(mem_idx < 0) continue; 

         // MA Exit
         if(new_bar)
           {
            if((pos_type == POSITION_TYPE_BUY && MA1_x_dn_MA3) || (pos_type == POSITION_TYPE_SELL && MA1_x_up_MA3))
              {
               if(trade.PositionClose(ticket))
                 {
                  if(pos_type == POSITION_TYPE_BUY) block_buy = true;
                  else block_sell = true;
                 }
               continue; 
              }
           }

         double target_ma_partial = MathFloor(NormalizeDouble(InpLotSize * (InpMAPartialPct / 100.0), 2) / step_vol) * step_vol; 
         if(target_ma_partial < min_vol) target_ma_partial = min_vol; 
         
         double target_rr_partial = MathFloor(NormalizeDouble(InpLotSize * (InpRRPartialPct / 100.0), 2) / step_vol) * step_vol; 
         if(target_rr_partial < min_vol) target_rr_partial = min_vol; 

         if(new_bar && ActiveTrades[mem_idx].ma_partials_taken < InpMaxMAPartials)
           {
            bool trigger_ma = (pos_type == POSITION_TYPE_BUY && MA1_x_dn_MA2) || (pos_type == POSITION_TYPE_SELL && MA1_x_up_MA2);
            if(trigger_ma && current_vol >= min_vol) 
              {
               double vol_to_close = (target_ma_partial >= current_vol) ? current_vol : target_ma_partial;
               if(trade.PositionClosePartial(ticket, vol_to_close)) ActiveTrades[mem_idx].ma_partials_taken++;
              }
           }

         if(InpUseRRPartials && ActiveTrades[mem_idx].rr_partials_taken < InpMaxRRPartials && ActiveTrades[mem_idx].initial_sl > 0)
           {
            double risk = MathAbs(ActiveTrades[mem_idx].entry_price - ActiveTrades[mem_idx].initial_sl);
            double curr_target_multiplier = InpRRTarget + (ActiveTrades[mem_idx].rr_partials_taken * InpRRTargetStep);
            
            bool trigger_rr = false;
            if(pos_type == POSITION_TYPE_BUY && bid >= ActiveTrades[mem_idx].entry_price + (risk * curr_target_multiplier)) trigger_rr = true;
            else if(pos_type == POSITION_TYPE_SELL && ask <= ActiveTrades[mem_idx].entry_price - (risk * curr_target_multiplier)) trigger_rr = true;
            
            if(trigger_rr && current_vol >= min_vol)
              {
               double vol_to_close = (target_rr_partial >= current_vol) ? current_vol : target_rr_partial;
               if(trade.PositionClosePartial(ticket, vol_to_close)) ActiveTrades[mem_idx].rr_partials_taken++;
              }
           }
        }
     }

   //--- 7. ENTRIES & RESET LOGIC
   if(new_bar)
     {
      if(block_buy && MA1[1] > MA3[1] && MA2[1] > MA3[1]) block_buy = false;
      if(block_sell && MA1[1] < MA3[1] && MA2[1] < MA3[1]) block_sell = false;

      double max_ma = MathMax(MA1[1], MathMax(MA2[1], MA3[1]));
      double min_ma = MathMin(MA1[1], MathMin(MA2[1], MA3[1]));
      bool MAs_too_close = ((max_ma - min_ma) / _Point) < InpMinMADistance;

      if(PositionsTotal() == 0 && !MAs_too_close)
        {
         // Fetch Price Data for Retest Logic
         double close[], low[], high[];
         ArraySetAsSeries(close, true); ArraySetAsSeries(low, true); ArraySetAsSeries(high, true);
         
         if(CopyClose(_Symbol, _Period, 0, 3, close) <= 0) return;
         if(CopyLow(_Symbol, _Period, 0, 3, low) <= 0) return;
         if(CopyHigh(_Symbol, _Period, 0, 3, high) <= 0) return;

         // --- BUY LOGIC ---
         // 1. Crossover: MA1 crosses MA2 UP, and BOTH are above MA3
         bool buy_cross = MA1_x_up_MA2 && (MA1[1] > MA3[1]) && (MA2[1] > MA3[1]);
         
         // 2. Retest: Price touched/dropped below MA2, then closed ABOVE MA2, and is ABOVE MA3
         bool buy_retest = (low[1] <= MA2[1] || close[2] < MA2[2]) && (close[1] > MA2[1]) && (close[1] > MA3[1]) && (MA2[1] > MA3[1]);
         
         bool buy_signal = (buy_cross || buy_retest) && !block_buy;

         // --- SELL LOGIC ---
         // 1. Crossover: MA1 crosses MA2 DOWN, and BOTH are below MA3
         bool sell_cross = MA1_x_dn_MA2 && (MA1[1] < MA3[1]) && (MA2[1] < MA3[1]);
         
         // 2. Retest: Price touched/rose above MA2, then closed BELOW MA2, and is BELOW MA3
         bool sell_retest = (high[1] >= MA2[1] || close[2] > MA2[2]) && (close[1] < MA2[1]) && (close[1] < MA3[1]) && (MA2[1] < MA3[1]);
         
         bool sell_signal = (sell_cross || sell_retest) && !block_sell;

         double initial_sl = 0;

         // --- EXECUTE ENTRIES ---
         if(buy_signal)
           {
            if(InpInitialSL == SL_FIXED_POINTS) initial_sl = ask - (InpSLPoints * _Point);
            else if(InpInitialSL == SL_CROSSOVER_CANDLE) initial_sl = low[1] - (InpSLCandleBuffer * _Point);
            else if(InpInitialSL == SL_MA_LEVEL)
              {
               if(InpTrailingMA == TRAIL_MA1) initial_sl = MA1[1] - (InpTrailingDist * _Point);
               else if(InpTrailingMA == TRAIL_MA2) initial_sl = MA2[1] - (InpTrailingDist * _Point);
               else if(InpTrailingMA == TRAIL_MA3) initial_sl = MA3[1] - (InpTrailingDist * _Point);
              }
            
            initial_sl = NormalizeDouble(initial_sl, _Digits);
            trade.Buy(InpLotSize, _Symbol, ask, initial_sl, 0);
           }
         else if(sell_signal)
           {
            if(InpInitialSL == SL_FIXED_POINTS) initial_sl = bid + (InpSLPoints * _Point);
            else if(InpInitialSL == SL_CROSSOVER_CANDLE) initial_sl = high[1] + (InpSLCandleBuffer * _Point);
            else if(InpInitialSL == SL_MA_LEVEL)
              {
               if(InpTrailingMA == TRAIL_MA1) initial_sl = MA1[1] + (InpTrailingDist * _Point);
               else if(InpTrailingMA == TRAIL_MA2) initial_sl = MA2[1] + (InpTrailingDist * _Point);
               else if(InpTrailingMA == TRAIL_MA3) initial_sl = MA3[1] + (InpTrailingDist * _Point);
              }
              
            if(initial_sl == 0) initial_sl = 0; 
            else initial_sl = NormalizeDouble(initial_sl, _Digits);
            
            trade.Sell(InpLotSize, _Symbol, bid, initial_sl, 0);
           }
        }
     }
  }
//+------------------------------------------------------------------+