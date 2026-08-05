//+------------------------------------------------------------------+
//|                           AutoTrader_MultiMA_V14_ProdV3.2.mq5    |
//|                         Production Ready Code Version 3.2        |
//+------------------------------------------------------------------+
#property copyright "Your Name"
#property link      ""
#property version   "3.20"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//--- Enums
enum ENUM_CUSTOM_MA { MA_SMA, MA_EMA, MA_WMA, MA_VWMA, MA_RMA, MA_HMA };
enum ENUM_SIGNAL_LOGIC { SIGNAL_BREAKOUT_2CANDLE, SIGNAL_TOUCH_REJECT_1CANDLE, SIGNAL_EITHER, SIGNAL_BOTH };

//--- Inputs
sinput string   Grp1 = "--- Signal MA Settings ---";
input ENUM_CUSTOM_MA   InpMAType           = MA_VWMA;                 
input int              InpMAPeriod         = 20;                      
input ENUM_SIGNAL_LOGIC InpSignalLogic     = SIGNAL_BREAKOUT_2CANDLE; 

sinput string   Grp2 = "--- RSI Filters (Current & HTF) ---";
input bool           InpUseRSI            = true;                    
input int            InpRSIPeriod         = 14;                      
input bool           InpUseHTFRSI         = true;                    
input ENUM_TIMEFRAMES InpHTF              = PERIOD_H1;               
input int            InpHTFRSIPeriod      = 14;                      
input double         InpRSIBuyLevel       = 40.0;                    
input double         InpRSISellLevel      = 60.0;                    

sinput string   Grp3 = "--- Trade & Risk Settings ---";
input double         InpRiskPercent       = 1.0;                     
input int            InpSLBufferPts       = 20;                      
input double         InpRR                = 1.5;                     

sinput string   Grp4 = "--- Drawdown Recovery Logic ---";
input bool           InpUseDrawdownLogic  = true;                    // Enable Drawdown Recovery
input int            InpDrawdownDistance  = 200;                     // Distance to open new trade (Points)
input int            InpMaxDrawdownTrades = 3;                       // Max open trades per direction

sinput string   Grp5 = "--- Partials & BE Management ---";
input int            InpPartialsCount     = 5;                       
input double         InpFirstPartialPct   = 20.0;                    
input double         InpRestPartialPct    = 10.0;                    
input int            InpBEAfterPartial    = 1;                       

sinput string   Grp6 = "--- Trailing Stop (Infinite Run) ---";
input bool           InpUseTrailing       = true;                    
input int            InpTrailAfterPartial = 2;                       
input int            InpTrailDistancePts  = 50;                      
input int            InpTrailStepPts      = 10;                      

sinput string   Grp7 = "--- Permitted Session Timings ---";
input bool           InpUseSession1      = true;                    
input string         InpSession1_Start   = "08:00";                 
input string         InpSession1_End     = "12:00";                 
input bool           InpUseSession2      = true;                    
input string         InpSession2_Start   = "13:00";                 
input string         InpSession2_End     = "17:00";                 
input bool           InpUseSession3      = false;                   
input string         InpSession3_Start   = "18:00";                 
input string         InpSession3_End     = "22:00";                 

sinput string   Grp8 = "--- Notifications & Misc ---";
input bool           InpSendPushAlert    = true;                    
input int            InpMagicNumber      = 777777;                  

//--- Trading Objects
CTrade         m_trade;
CPositionInfo  m_position;
CSymbolInfo    m_symbol;

int            h_rsi     = INVALID_HANDLE;
int            h_rsi_htf = INVALID_HANDLE;

enum ENUM_SIGNAL_STATE { STATE_NONE, STATE_BREAKOUT_BUY, STATE_BREAKOUT_SELL };
ENUM_SIGNAL_STATE m_current_state = STATE_NONE;
double            m_breakout_extreme = 0.0; 
datetime          m_last_bar_time = 0;

//--- Multi-Trade Data Structures
struct PartialLevel { double price; double volume_to_close; bool hit; };
struct STradeData { ulong ticket; long type; PartialLevel partials[]; };
STradeData m_active_trades[];

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   m_symbol.Name(_Symbol); m_symbol.RefreshRates();
   m_trade.SetExpertMagicNumber(InpMagicNumber);
   ChartSetInteger(0, CHART_SHOW_OBJECT_DESCR, true); 
   if(InpUseRSI) h_rsi = iRSI(_Symbol, _Period, InpRSIPeriod, PRICE_CLOSE);
   if(InpUseHTFRSI) h_rsi_htf = iRSI(_Symbol, InpHTF, InpHTFRSIPeriod, PRICE_CLOSE);
   ObjectsDeleteAll(0, -1, -1);
   ArrayResize(m_active_trades, 0);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, -1, -1);
   if(h_rsi != INVALID_HANDLE) IndicatorRelease(h_rsi);
   if(h_rsi_htf != INVALID_HANDLE) IndicatorRelease(h_rsi_htf);
  }

//+------------------------------------------------------------------+
//| Main Tick                                                        |
//+------------------------------------------------------------------+
void OnTick()
  {
   m_symbol.RefreshRates();
   ManageActiveTrades();
   DrawVisualMA();
   
   datetime current_time = iTime(_Symbol, _Period, 0);
   if(current_time != m_last_bar_time && m_last_bar_time != 0)
     {
      if(IsTradingAllowed()) ProcessBarCloseLogic();
      else m_current_state = STATE_NONE; 
     }
     
   ChartRedraw();
   m_last_bar_time = current_time;
  }

//+------------------------------------------------------------------+
//| Core Signal & Initial Entry (Bar Close)                          |
//+------------------------------------------------------------------+
void ProcessBarCloseLogic()
  {
   int buys = 0, sells = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(m_position.SelectByIndex(i) && m_position.Symbol() == _Symbol && m_position.Magic() == InpMagicNumber) {
         if(m_position.PositionType() == POSITION_TYPE_BUY) buys++;
         else sells++;
      }
   }
   
   // Initial entry signals are only valid if we have ZERO trades in that direction
   bool can_buy = (buys == 0);
   bool can_sell = (sells == 0);
   
   if(!can_buy && !can_sell) { m_current_state = STATE_NONE; return; }

   double ma1 = GetCustomMA(1), close1 = iClose(_Symbol, _Period, 1), open1 = iOpen(_Symbol, _Period, 1), low1 = iLow(_Symbol, _Period, 1), high1 = iHigh(_Symbol, _Period, 1);
   bool rsi_buy_ok = true, rsi_sell_ok = true;
   
   if(InpUseRSI) {
      double rsi_arr[1]; if(CopyBuffer(h_rsi, 0, 1, 1, rsi_arr) > 0) {
         if(rsi_arr[0] >= InpRSIBuyLevel) rsi_buy_ok = false;
         if(rsi_arr[0] <= InpRSISellLevel) rsi_sell_ok = false;
      }
   }
   if(InpUseHTFRSI) {
      double rsi_htf_arr[1]; datetime t1 = iTime(_Symbol, _Period, 1); int shift_htf = iBarShift(_Symbol, InpHTF, t1);
      if(shift_htf >= 0 && CopyBuffer(h_rsi_htf, 0, shift_htf, 1, rsi_htf_arr) > 0) {
         if(rsi_htf_arr[0] >= InpRSIBuyLevel) rsi_buy_ok = false;
         if(rsi_htf_arr[0] <= InpRSISellLevel) rsi_sell_ok = false;
      }
   }

   bool cond1_buy_breakout = (open1 < ma1 && close1 > ma1), cond1_sell_breakout = (open1 > ma1 && close1 < ma1);
   bool cond2_buy_rejection = (low1 < ma1 && close1 > ma1), cond2_sell_rejection = (high1 > ma1 && close1 < ma1);
   bool trigger_buy_state = false, trigger_sell_state = false;

   if(InpSignalLogic == SIGNAL_BREAKOUT_2CANDLE) { trigger_buy_state = cond1_buy_breakout; trigger_sell_state = cond1_sell_breakout; } 
   else if(InpSignalLogic == SIGNAL_EITHER) { trigger_buy_state = cond1_buy_breakout || cond2_buy_rejection; trigger_sell_state = cond1_sell_breakout || cond2_sell_rejection; } 
   else if(InpSignalLogic == SIGNAL_BOTH) { trigger_buy_state = (cond1_buy_breakout && cond2_buy_rejection); trigger_sell_state = (cond1_sell_breakout && cond2_sell_rejection); }
     
   trigger_buy_state &= (rsi_buy_ok && can_buy); cond2_buy_rejection &= (rsi_buy_ok && can_buy);
   trigger_sell_state &= (rsi_sell_ok && can_sell); cond2_sell_rejection &= (rsi_sell_ok && can_sell);

   if(m_current_state == STATE_BREAKOUT_BUY && !can_buy) m_current_state = STATE_NONE;
   if(m_current_state == STATE_BREAKOUT_SELL && !can_sell) m_current_state = STATE_NONE;

   if(InpSignalLogic == SIGNAL_TOUCH_REJECT_1CANDLE || InpSignalLogic == SIGNAL_EITHER) {
      if(cond2_buy_rejection) { m_breakout_extreme = low1; ExecuteTrade(ORDER_TYPE_BUY); return; }
      if(cond2_sell_rejection) { m_breakout_extreme = high1; ExecuteTrade(ORDER_TYPE_SELL); return; }
      if(InpSignalLogic == SIGNAL_TOUCH_REJECT_1CANDLE) return;
   }

   if(m_current_state == STATE_NONE) {
      if(trigger_buy_state) { m_current_state = STATE_BREAKOUT_BUY; m_breakout_extreme = low1; }
      else if(trigger_sell_state) { m_current_state = STATE_BREAKOUT_SELL; m_breakout_extreme = high1; }
   }
   else if(m_current_state == STATE_BREAKOUT_BUY) {
      if(close1 > ma1 && rsi_buy_ok && can_buy) { ExecuteTrade(ORDER_TYPE_BUY); m_current_state = STATE_NONE; }
      else { if(trigger_sell_state) { m_current_state = STATE_BREAKOUT_SELL; m_breakout_extreme = high1; } else m_current_state = STATE_NONE; }
   }
   else if(m_current_state == STATE_BREAKOUT_SELL) {
      if(close1 < ma1 && rsi_sell_ok && can_sell) { ExecuteTrade(ORDER_TYPE_SELL); m_current_state = STATE_NONE; }
      else { if(trigger_buy_state) { m_current_state = STATE_BREAKOUT_BUY; m_breakout_extreme = low1; } else m_current_state = STATE_NONE; }
   }
  }

//+------------------------------------------------------------------+
//| Trade Execution                                                  |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type)
  {
   m_symbol.RefreshRates();
   double entry_price = (type == ORDER_TYPE_BUY) ? m_symbol.Ask() : m_symbol.Bid();
   double sl = (type == ORDER_TYPE_BUY) ? (m_breakout_extreme - InpSLBufferPts * _Point) : (m_breakout_extreme + InpSLBufferPts * _Point);
      
   double risk_dist = MathAbs(entry_price - sl);
   if(risk_dist <= 0) return;
   
   double full_tp = (type == ORDER_TYPE_BUY) ? (entry_price + risk_dist * InpRR) : (entry_price - risk_dist * InpRR);
      
   double tick_val = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double risk_money = AccountInfoDouble(ACCOUNT_BALANCE) * (InpRiskPercent / 100.0);
   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double total_lots = MathFloor((risk_money / ((risk_dist / tick_size) * tick_val)) / lot_step) * lot_step;
   
   if(total_lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) return;
   
   bool result = (type == ORDER_TYPE_BUY) ? m_trade.Buy(total_lots, _Symbol, entry_price, sl, full_tp, "AutoTrader Entry")
                                          : m_trade.Sell(total_lots, _Symbol, entry_price, sl, full_tp, "AutoTrader Entry");
      
   if(result && InpSendPushAlert) {
      string dir = (type == ORDER_TYPE_BUY) ? "BUY" : "SELL";
      SendNotification("AutoTrader: " + dir + " on " + _Symbol + " | Entry: " + DoubleToString(entry_price, _Digits));
   }
  }

//+------------------------------------------------------------------+
//| Drawdown Recovery & Advanced Multi-Trade Management              |
//+------------------------------------------------------------------+
void ManageActiveTrades()
  {
   double bid = m_symbol.Bid(), ask = m_symbol.Ask();
   
   // Track Active Positions
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(m_position.SelectByIndex(i) && m_position.Symbol() == _Symbol && m_position.Magic() == InpMagicNumber) {
         ulong tkt = m_position.Ticket(); bool found = false;
         for(int j = 0; j < ArraySize(m_active_trades); j++) { if(m_active_trades[j].ticket == tkt) { found = true; break; } }
         if(!found) {
            int sz = ArraySize(m_active_trades); ArrayResize(m_active_trades, sz + 1);
            m_active_trades[sz].ticket = tkt; m_active_trades[sz].type = m_position.PositionType();
            CalculatePartials(sz, m_position.PriceOpen(), m_position.TakeProfit(), m_position.Volume());
         }
      }
   }
     
   // Clean up closed
   for(int j = ArraySize(m_active_trades) - 1; j >= 0; j--) {
      if(!PositionSelectByTicket(m_active_trades[j].ticket)) {
         DeleteTradeVisuals(m_active_trades[j].ticket);
         ArrayRemove(m_active_trades, j, 1);
      }
   }

   // --- STEP 1: Identify "Best" and "Worst" trades per direction ---
   int buys = 0, sells = 0;
   double best_buy_price = 999999.0, best_sell_price = 0.0;
   ulong best_buy_ticket = 0, best_sell_ticket = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(m_position.SelectByIndex(i) && m_position.Symbol() == _Symbol && m_position.Magic() == InpMagicNumber) {
         if(m_position.PositionType() == POSITION_TYPE_BUY) {
            buys++;
            if(m_position.PriceOpen() < best_buy_price) { best_buy_price = m_position.PriceOpen(); best_buy_ticket = m_position.Ticket(); }
         } else {
            sells++;
            if(m_position.PriceOpen() > best_sell_price) { best_sell_price = m_position.PriceOpen(); best_sell_ticket = m_position.Ticket(); }
         }
      }
   }

   // --- STEP 2: Drawdown Trigger Logic (Averaging in) ---
   // FIX: Only evaluate and execute drawdown trades during permitted session hours
   if(InpUseDrawdownLogic && IsTradingAllowed()) {
      if(buys > 0 && buys < InpMaxDrawdownTrades) {
         if(ask <= best_buy_price - (InpDrawdownDistance * _Point)) {
            m_breakout_extreme = iLow(_Symbol, _Period, 1); 
            ExecuteTrade(ORDER_TYPE_BUY); 
         }
      }
      if(sells > 0 && sells < InpMaxDrawdownTrades) {
         if(bid >= best_sell_price + (InpDrawdownDistance * _Point)) {
            m_breakout_extreme = iHigh(_Symbol, _Period, 1); 
            ExecuteTrade(ORDER_TYPE_SELL); 
         }
      }
   }

   // --- STEP 3: Process Logic (Exit Worst at BE / Manage Best) ---
   for(int j = 0; j < ArraySize(m_active_trades); j++) {
      if(PositionSelectByTicket(m_active_trades[j].ticket)) {
         long type = m_active_trades[j].type; ulong tkt = m_active_trades[j].ticket;
         double entry = m_position.PriceOpen(), current_sl = m_position.StopLoss(), current_tp = m_position.TakeProfit();
         
         bool is_best = (type == POSITION_TYPE_BUY && tkt == best_buy_ticket) || (type == POSITION_TYPE_SELL && tkt == best_sell_ticket);

         // Logic for "Worst" Positions (Close instantly when net profit > 0)
         if(!is_best) {
            double net_profit = m_position.Profit() + m_position.Swap() + m_position.Commission();
            if(net_profit > 0) {
               m_trade.PositionClose(tkt);
            }
            continue; // Skip partials/trailing for worst positions
         }

         // Logic for "Best" Positions (Full Partials and Trailing)
         int partials_hit_count = 0;
         for(int p = 0; p < InpPartialsCount; p++) {
            if(m_active_trades[j].partials[p].hit) { partials_hit_count++; continue; }
            
            bool hit = false;
            if(type == POSITION_TYPE_BUY && bid >= m_active_trades[j].partials[p].price) hit = true;
            if(type == POSITION_TYPE_SELL && ask <= m_active_trades[j].partials[p].price) hit = true;
            
            if(hit) {
               m_active_trades[j].partials[p].hit = true; partials_hit_count++;
               if(m_position.Volume() > m_active_trades[j].partials[p].volume_to_close) {
                  m_trade.PositionClosePartial(tkt, m_active_trades[j].partials[p].volume_to_close);
                  ObjectDelete(0, "TradeVis_" + IntegerToString(tkt) + "_Partial_" + IntegerToString(p + 1));
               }
               if(partials_hit_count == InpBEAfterPartial) {
                  if(type == POSITION_TYPE_BUY && current_sl < entry) { m_trade.PositionModify(tkt, entry, current_tp); current_sl = entry; }
                  if(type == POSITION_TYPE_SELL && current_sl > entry) { m_trade.PositionModify(tkt, entry, current_tp); current_sl = entry; }
               }
            }
         }
           
         if(InpUseTrailing && partials_hit_count >= InpTrailAfterPartial) {
            if(current_tp != 0.0) { m_trade.PositionModify(tkt, current_sl, 0.0); ObjectDelete(0, "TradeVis_" + IntegerToString(tkt) + "_TP"); }
            double new_sl = 0;
            if(type == POSITION_TYPE_BUY) {
               new_sl = bid - (InpTrailDistancePts * _Point);
               if(new_sl > current_sl + (InpTrailStepPts * _Point)) m_trade.PositionModify(tkt, new_sl, 0.0);
            } else if(type == POSITION_TYPE_SELL) {
               new_sl = ask + (InpTrailDistancePts * _Point);
               if(new_sl < current_sl - (InpTrailStepPts * _Point) || current_sl == 0) m_trade.PositionModify(tkt, new_sl, 0.0);
            }
         }
         
         // Keep visuals updated for best trade
         DrawTradeVisuals(tkt, type, entry, current_sl, current_tp);
      }
   }
  }

void CalculatePartials(int trade_idx, double entry, double full_tp, double total_vol)
  {
   ArrayResize(m_active_trades[trade_idx].partials, InpPartialsCount);
   if(full_tp == 0) return; // Prevent division issues if no TP
   double step_dist = (full_tp - entry) / (InpPartialsCount + 1);
   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   for(int i = 0; i < InpPartialsCount; i++) {
      m_active_trades[trade_idx].partials[i].hit = false;
      m_active_trades[trade_idx].partials[i].price = entry + (step_dist * (i + 1));
      double pct = (i == 0) ? InpFirstPartialPct : InpRestPartialPct;
      m_active_trades[trade_idx].partials[i].volume_to_close = MathFloor((total_vol * (pct / 100.0)) / lot_step) * lot_step;
      if(m_active_trades[trade_idx].partials[i].volume_to_close < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
         m_active_trades[trade_idx].partials[i].volume_to_close = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         
      DrawPartialVisual(m_active_trades[trade_idx].ticket, m_active_trades[trade_idx].partials[i].price, i + 1);
   }
  }

//+------------------------------------------------------------------+
//| Chart Visuals Engine                                             |
//+------------------------------------------------------------------+
void DrawTradeVisuals(ulong tkt, long type, double entry, double sl, double tp)
  {
   string t = IntegerToString(tkt);
   CreateLine("TradeVis_" + t + "_Entry", entry, clrYellow, "Entry");
   CreateLine("TradeVis_" + t + "_SL", sl, clrRed, "SL");
   if(tp > 0) CreateLine("TradeVis_" + t + "_TP", tp, clrLime, "Full TP");
  }

void DrawPartialVisual(ulong tkt, double price, int index)
  {
   CreateLine("TradeVis_" + IntegerToString(tkt) + "_Partial_" + IntegerToString(index), price, clrDeepSkyBlue, "TP " + IntegerToString(index), STYLE_DASH);
  }

void DeleteTradeVisuals(ulong tkt)
  {
   string t = IntegerToString(tkt);
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--) {
      string name = ObjectName(0, i);
      if(StringFind(name, "TradeVis_" + t) == 0) ObjectDelete(0, name);
   }
  }

void CreateLine(string name, double price, color col, string label, int style = STYLE_SOLID)
  {
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   else ObjectMove(0, name, 0, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col); ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetString(0, name, OBJPROP_TEXT, " " + label); ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
  }

//+------------------------------------------------------------------+
//| Custom Moving Average & Utilities Engine                         |
//+------------------------------------------------------------------+
double GetCustomMA(int shift) { switch(InpMAType) { case MA_SMA: return iCustomSMA(shift); case MA_EMA: return iCustomEMA(shift); case MA_WMA: return iCustomWMA(shift); case MA_VWMA: return iCustomVWMA(shift); case MA_RMA: return iCustomRMA(shift); case MA_HMA: return iCustomHMA(shift); } return 0.0; }
double iCustomSMA(int shift) { double sum = 0; for(int i=0; i<InpMAPeriod; i++) sum+=iClose(_Symbol,_Period,shift+i); return sum/InpMAPeriod; }
double iCustomWMA(int shift) { double sum=0, ws=0; for(int i=0; i<InpMAPeriod; i++) { int w=InpMAPeriod-i; sum+=iClose(_Symbol,_Period,shift+i)*w; ws+=w; } return sum/ws; }
double iCustomVWMA(int shift) { double scv=0, sv=0; long vol[]; double clo[]; CopyTickVolume(_Symbol,_Period,shift,InpMAPeriod,vol); CopyClose(_Symbol,_Period,shift,InpMAPeriod,clo); ArraySetAsSeries(vol,true); ArraySetAsSeries(clo,true); for(int i=0; i<InpMAPeriod; i++) { scv+=clo[i]*vol[i]; sv+=vol[i]; } return (sv>0)?(scv/sv):clo[0]; }
double iCustomEMA(int shift) { int h=iMA(_Symbol,_Period,InpMAPeriod,0,MODE_EMA,PRICE_CLOSE); double buf[1]; CopyBuffer(h,0,shift,1,buf); IndicatorRelease(h); return buf[0]; }
double iCustomRMA(int shift) { int h=iMA(_Symbol,_Period,InpMAPeriod,0,MODE_SMMA,PRICE_CLOSE); double buf[1]; CopyBuffer(h,0,shift,1,buf); IndicatorRelease(h); return buf[0]; }
double iCustomHMA(int shift) { int half=(int)MathFloor(InpMAPeriod/2.0), sq=(int)MathFloor(MathSqrt(InpMAPeriod)); double sum=0, ws=0; for(int i=0; i<sq; i++) { int w=sq-i; double wh=CalcWMA_Internal(shift+i,half), wf=CalcWMA_Internal(shift+i,InpMAPeriod), raw=(2.0*wh)-wf; sum+=raw*w; ws+=w; } return sum/ws; }
double CalcWMA_Internal(int shift, int period) { double sum=0, ws=0; for(int i=0; i<period; i++) { int w=period-i; sum+=iClose(_Symbol,_Period,shift+i)*w; ws+=w; } return sum/ws; }

bool IsTradingAllowed() { MqlDateTime dt; TimeToStruct(TimeCurrent(), dt); int mins = dt.hour*60+dt.min; return ((InpUseSession1 && IsTimeInSession(mins,InpSession1_Start,InpSession1_End)) || (InpUseSession2 && IsTimeInSession(mins,InpSession2_Start,InpSession2_End)) || (InpUseSession3 && IsTimeInSession(mins,InpSession3_Start,InpSession3_End))); }
bool IsTimeInSession(int mins, string start_str, string end_str) { int sm = ParseTimeStr(start_str), em = ParseTimeStr(end_str); if(sm<=em) return (mins>=sm && mins<=em); return (mins>=sm || mins<=em); }
int ParseTimeStr(string time_str) { string arr[]; StringSplit(time_str, ':', arr); if(ArraySize(arr)==2) return (int)StringToInteger(arr[0])*60+(int)StringToInteger(arr[1]); return 0; }

void DrawVisualMA() { string pfx="CustomMA_"; for(int i=0; i<50; i++) { string nm=pfx+IntegerToString(i); datetime t1=iTime(_Symbol,_Period,i), t2=iTime(_Symbol,_Period,i+1); double v1=GetCustomMA(i), v2=GetCustomMA(i+1); if(ObjectFind(0,nm)<0) ObjectCreate(0,nm,OBJ_TREND,0,t2,v2,t1,v1); else { ObjectSetInteger(0,nm,OBJPROP_TIME,0,t2); ObjectSetDouble(0,nm,OBJPROP_PRICE,0,v2); ObjectSetInteger(0,nm,OBJPROP_TIME,1,t1); ObjectSetDouble(0,nm,OBJPROP_PRICE,1,v1); } ObjectSetInteger(0,nm,OBJPROP_COLOR,clrDodgerBlue); ObjectSetInteger(0,nm,OBJPROP_WIDTH,2); ObjectSetInteger(0,nm,OBJPROP_RAY_RIGHT,false); ObjectSetInteger(0,nm,OBJPROP_BACK,true); } string rt=""; if(InpUseRSI) { double ra[1]; if(CopyBuffer(h_rsi,0,0,1,ra)>0) rt+="RSI: "+DoubleToString(ra[0],1); } if(InpUseHTFRSI) { double rha[1]; if(CopyBuffer(h_rsi_htf,0,0,1,rha)>0) { if(rt!="") rt+=", "; rt+="HTF: "+DoubleToString(rha[0],1); } } string ln=pfx+"Label"; if(rt!="") { datetime t0=iTime(_Symbol,_Period,0); double v0=GetCustomMA(0); if(ObjectFind(0,ln)<0) ObjectCreate(0,ln,OBJ_TEXT,0,t0,v0); else { ObjectSetInteger(0,ln,OBJPROP_TIME,t0); ObjectSetDouble(0,ln,OBJPROP_PRICE,v0); } ObjectSetString(0,ln,OBJPROP_TEXT,"  ◄ "+rt); ObjectSetInteger(0,ln,OBJPROP_COLOR,clrWhite); ObjectSetInteger(0,ln,OBJPROP_FONTSIZE,10); ObjectSetInteger(0,ln,OBJPROP_BACK,false); } else ObjectDelete(0,ln); }
//+------------------------------------------------------------------+