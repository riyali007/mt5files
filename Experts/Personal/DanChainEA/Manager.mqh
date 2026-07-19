//+------------------------------------------------------------------+
//|                                                      Manager.mqh |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include "Defines.mqh"
#include "Panel.mqh"

// Struct to track TP levels for OPEN TRADES managed by EA
struct ActiveTrade {
   long ticket;
   double entry;
   double tp1;
   double tp2;
   double tp3;
   bool tp1_hit;
   bool tp2_hit;
   bool tp3_hit;
};

class CManager {
private:
   CTrade         m_trade;
   CPositionInfo  m_pos;
   
   int            m_handle;
   double         m_buf_buy[];
   double         m_buf_sell[];
   
   bool           m_vis_active;
   
   ActiveTrade    m_active_trades[]; // Array to track custom TPs

public:
   CManager();
   ~CManager();
   
   void  OnInit();
   void  OnTick(CMyPanel &panel);
   
   void  PlaceOrder(CMyPanel &panel);
   void  ToggleVisualize(CMyPanel &panel);
   void  TakeSelectedPartial(CMyPanel &panel);
   void  SetSelectedBE(CMyPanel &panel);
   void  CloseSelected(CMyPanel &panel);
   
   void  DrawLines(string suffix, double entry, double sl, double tp1, double tp2, double tp3, double tp4, color clr);
   void  CleanVisuals();
   
   // New Methods for Tracking
   void  ManagePositions(CMyPanel &panel);
   void  RegisterTrade(long ticket, double price, int dir);
   void  DrawOpenTradeLines(long ticket, double entry, double tp1, double tp2, double tp3, int dir);
   
private:
   void  UpdateVisualizeLines(CMyPanel &panel);
};

CManager::CManager() : m_vis_active(false), m_handle(INVALID_HANDLE) {}
CManager::~CManager() {}

void CManager::OnInit() {
   m_trade.SetExpertMagicNumber(InpMagicNumber);
   m_trade.SetDeviationInPoints(InpSlippage);
   
   // Load FULL Indicator
   m_handle = iCustom(_Symbol, PERIOD_CURRENT, "DonchianSignal", InpRange); 
   if(m_handle != INVALID_HANDLE) ChartIndicatorAdd(0, 0, m_handle);
   
   ObjectsDeleteAll(0, PREFIX + "VIS");
   ObjectsDeleteAll(0, PREFIX + "OPEN_");
}

void CManager::OnTick(CMyPanel &panel) {
   // 1. Read Signals from Indicator (Buffer 3=Buy, 4=Sell)
   if(m_handle != INVALID_HANDLE) {
      if(CopyBuffer(m_handle, 3, 0, 2, m_buf_buy) > 0 && CopyBuffer(m_handle, 4, 0, 2, m_buf_sell) > 0) {
         if(m_buf_buy[0] != EMPTY_VALUE) panel.SetSignal("BUY SIGNAL", clrGreen);
         else if(m_buf_sell[0] != EMPTY_VALUE) panel.SetSignal("SELL SIGNAL", clrRed);
         else panel.SetSignal("NO SIGNAL", clrGray);
      }
   }
   
   // 2. Market Price Update
   if(panel.IsMarket()) {
      int dir = panel.GetDirection();
      double price = (dir == -1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      panel.SetPrice(price);
   }
   
   // 3. Visualization
   if(m_vis_active) UpdateVisualizeLines(panel);
   
   // 4. MANAGE TRADES (Auto Partial / BE / Lines)
   ManagePositions(panel);
}

void CManager::PlaceOrder(CMyPanel &panel) {
   int dir = panel.GetDirection();
   if(dir == 0) { Alert("Select BUY or SELL first!"); return; }
   
   double vol = panel.GetLot();
   double sl_pts = panel.GetSL();
   double price = panel.GetPrice(); 
   if(price <= 0) { Alert("Invalid Price"); return; }
   
   double sl = 0;
   if(sl_pts > 0) sl = (dir == 1) ? price - (sl_pts*_Point) : price + (sl_pts*_Point);
   else           sl = (dir == 1) ? price - (price*InpSLPercent/100) : price + (price*InpSLPercent/100);
   
   // Hard TP is TP4
   double tp_hard = (dir == 1) ? price*(1+InpTP4/100) : price*(1-InpTP4/100);
   
   bool res = false;
   if(panel.IsMarket()) {
      if(dir == 1) res = m_trade.Buy(vol, _Symbol, price, sl, tp_hard, "DT EA");
      else         res = m_trade.Sell(vol, _Symbol, price, sl, tp_hard, "DT EA");
   } else {
      double current = SymbolInfoDouble(_Symbol, SYMBOL_BID); 
      ENUM_ORDER_TYPE type;
      if(dir == 1) type = (price < current) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_BUY_STOP;
      else         type = (price > current) ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_SELL_STOP;
      res = m_trade.OrderOpen(_Symbol, type, vol, 0, price, sl, tp_hard, ORDER_TIME_GTC, 0, "DT EA Pending");
   }
   
   if(res) {
      m_vis_active = false; CleanVisuals(); PlaySound("ok.wav");
      // Note: We register trade in ManagePositions loop automatically when it appears
      panel.CyclePosition(1); 
   } else Alert("Order Failed: ", GetLastError());
}

void CManager::RegisterTrade(long ticket, double price, int dir) {
   int s = ArraySize(m_active_trades);
   ArrayResize(m_active_trades, s+1);
   m_active_trades[s].ticket = ticket; 
   m_active_trades[s].entry = price;
   
   // Calculate Virtual TPs based on inputs
   m_active_trades[s].tp1 = (dir==1) ? price*(1+InpTP1/100) : price*(1-InpTP1/100);
   m_active_trades[s].tp2 = (dir==1) ? price*(1+InpTP2/100) : price*(1-InpTP2/100);
   m_active_trades[s].tp3 = (dir==1) ? price*(1+InpTP3/100) : price*(1-InpTP3/100);
   
   m_active_trades[s].tp1_hit = false;
   m_active_trades[s].tp2_hit = false;
   m_active_trades[s].tp3_hit = false;
}

void CManager::ManagePositions(CMyPanel &panel) {
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(m_pos.SelectByIndex(i)) {
         if(m_pos.Symbol() == _Symbol && m_pos.Magic() == InpMagicNumber) {
            long t = m_pos.Ticket();
            
            // 1. Ensure Tracked
            int idx = -1;
            for(int k=0; k<ArraySize(m_active_trades); k++) { if(m_active_trades[k].ticket == t) { idx=k; break; } }
            
            if(idx == -1) {
               RegisterTrade(t, m_pos.PriceOpen(), (m_pos.PositionType()==POSITION_TYPE_BUY?1:-1));
               idx = ArraySize(m_active_trades)-1;
            }
            
            // 2. Draw Lines (Virtual TPs)
            DrawOpenTradeLines(t, m_pos.PriceOpen(), m_active_trades[idx].tp1, m_active_trades[idx].tp2, m_active_trades[idx].tp3, (m_pos.PositionType()==POSITION_TYPE_BUY?1:-1));
            
            // 3. Check Price Hits
            double cur = m_pos.PriceCurrent();
            int dir = (m_pos.PositionType()==POSITION_TYPE_BUY?1:-1);
            double vol = m_pos.Volume();
            
            // TP1
            bool hit1 = (dir==1 && cur >= m_active_trades[idx].tp1) || (dir==-1 && cur <= m_active_trades[idx].tp1);
            if(hit1 && !m_active_trades[idx].tp1_hit && vol > 0.01) {
               m_active_trades[idx].tp1_hit = true;
               // Take 25% Partial (Hardcoded or use another input if needed, using 25% for auto)
               double part = NormalizeDouble(vol * 0.25, 2); 
               if(part < 0.01) part = 0.01;
               m_trade.PositionClosePartial(t, part);
               if(InpSLToBe >= 1) m_trade.PositionModify(t, m_pos.PriceOpen(), m_pos.TakeProfit()); // BE
               PlaySound("coins.wav");
            }
            
            // TP2
            bool hit2 = (dir==1 && cur >= m_active_trades[idx].tp2) || (dir==-1 && cur <= m_active_trades[idx].tp2);
            if(hit2 && !m_active_trades[idx].tp2_hit && vol > 0.01) {
               m_active_trades[idx].tp2_hit = true;
               double part = NormalizeDouble(vol * 0.25, 2); 
               if(part < 0.01) part = 0.01;
               m_trade.PositionClosePartial(t, part);
               PlaySound("coins.wav");
            }
         }
      }
   }
}

void CManager::DrawOpenTradeLines(long ticket, double entry, double tp1, double tp2, double tp3, int dir) {
   string s = (string)ticket;
   color c = (dir==1)?clrGreen:clrRed;
   
   string n1=PREFIX+"OPEN_"+s+"_TP1";
   if(ObjectFind(0,n1)<0) { ObjectCreate(0,n1,OBJ_HLINE,0,0,0); ObjectSetInteger(0,n1,OBJPROP_COLOR,clrGray); ObjectSetInteger(0,n1,OBJPROP_STYLE,STYLE_DOT); }
   ObjectSetDouble(0,n1,OBJPROP_PRICE,tp1);
   
   string n2=PREFIX+"OPEN_"+s+"_TP2";
   if(ObjectFind(0,n2)<0) { ObjectCreate(0,n2,OBJ_HLINE,0,0,0); ObjectSetInteger(0,n2,OBJPROP_COLOR,clrGray); ObjectSetInteger(0,n2,OBJPROP_STYLE,STYLE_DOT); }
   ObjectSetDouble(0,n2,OBJPROP_PRICE,tp2);
   
   string n3=PREFIX+"OPEN_"+s+"_TP3";
   if(ObjectFind(0,n3)<0) { ObjectCreate(0,n3,OBJ_HLINE,0,0,0); ObjectSetInteger(0,n3,OBJPROP_COLOR,clrGray); ObjectSetInteger(0,n3,OBJPROP_STYLE,STYLE_DOT); }
   ObjectSetDouble(0,n3,OBJPROP_PRICE,tp3);
}

void CManager::TakeSelectedPartial(CMyPanel &panel) {
   long ticket = panel.GetSelectedTicket();
   if(ticket <= 0) { Alert("No Position Selected!"); return; }
   
   if(m_pos.SelectByTicket(ticket)) {
      double vol = m_pos.Volume();
      double pct = panel.GetPartialPercent(); 
      double part_vol = NormalizeDouble(vol * (pct / 100.0), 2);
      
      if(part_vol < 0.01) part_vol = 0.01;
      if(part_vol >= vol) part_vol = vol;
      
      if(m_trade.PositionClosePartial(ticket, part_vol)) {
          PlaySound("coins.wav");
          panel.RefreshPositions();
      }
   }
}

void CManager::SetSelectedBE(CMyPanel &panel) {
   long ticket = panel.GetSelectedTicket();
   if(ticket > 0 && m_pos.SelectByTicket(ticket)) {
       m_trade.PositionModify(ticket, m_pos.PriceOpen(), m_pos.TakeProfit());
       PlaySound("ok.wav");
   }
}

void CManager::CloseSelected(CMyPanel &panel) {
   long ticket = panel.GetSelectedTicket();
   if(ticket > 0) {
       m_trade.PositionClose(ticket);
       panel.CyclePosition(1);
   }
}

void CManager::ToggleVisualize(CMyPanel &panel) {
   int dir = panel.GetDirection();
   if(dir == 0) { Alert("Select BUY or SELL first!"); return; }
   if(!m_vis_active) m_vis_active = true;
   else { m_vis_active = false; CleanVisuals(); }
   ChartRedraw();
}

void CManager::UpdateVisualizeLines(CMyPanel &panel) {
   int dir = panel.GetDirection();
   if(dir == 0) return;
   double price = panel.GetPrice(); if(price <= 0) return;
   double sl_pts = panel.GetSL();
   double sl = (sl_pts > 0) ? ((dir == 1) ? price - sl_pts*_Point : price + sl_pts*_Point) 
                            : ((dir == 1) ? price - (price*InpSLPercent/100) : price + (price*InpSLPercent/100));
   
   double tp1 = (dir==1)? price*(1+InpTP1/100) : price*(1-InpTP1/100);
   double tp2 = (dir==1)? price*(1+InpTP2/100) : price*(1-InpTP2/100);
   double tp3 = (dir==1)? price*(1+InpTP3/100) : price*(1-InpTP3/100);
   double tp4 = (dir==1)? price*(1+InpTP4/100) : price*(1-InpTP4/100);
   
   DrawLines("VIS", price, sl, tp1, tp2, tp3, tp4, (dir==1)?clrGreen:clrRed);
}

void CManager::DrawLines(string suffix, double entry, double sl, double tp1, double tp2, double tp3, double tp4, color clr) {
   string names[] = {"_Ent", "_SL", "_TP1", "_TP2", "_TP3", "_TP4"};
   double prices[] = {entry, sl, tp1, tp2, tp3, tp4};
   for(int i=0; i<6; i++) {
      string obj = PREFIX + suffix + names[i];
      if(ObjectFind(0, obj) < 0) {
         ObjectCreate(0, obj, OBJ_HLINE, 0, 0, 0);
         ObjectSetInteger(0, obj, OBJPROP_COLOR, (i==0)?clr:clrGray);
         ObjectSetInteger(0, obj, OBJPROP_WIDTH, (i==0)?2:1);
      }
      ObjectSetDouble(0, obj, OBJPROP_PRICE, prices[i]);
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
   }
   ChartRedraw();
}

void CManager::CleanVisuals() { ObjectsDeleteAll(0, PREFIX + "VIS"); }
