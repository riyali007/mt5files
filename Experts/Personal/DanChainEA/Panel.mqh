//+------------------------------------------------------------------+
//|                                                        Panel.mqh |
//+------------------------------------------------------------------+
#include <Controls\Dialog.mqh>
#include <Controls\Button.mqh>
#include <Controls\Edit.mqh>
#include <Controls\Label.mqh>
#include "Defines.mqh"

class CMyPanel : public CAppDialog {
private:
   CButton m_btn_mode;
   
   CLabel  m_lbl_lot;    CEdit m_edit_lot;
   CLabel  m_lbl_sl;     CEdit m_edit_sl;
   CLabel  m_lbl_price;  CEdit m_edit_price;
   
   CButton m_btn_buy;
   CButton m_btn_sell;
   CButton m_btn_place;
   CButton m_btn_vis;
   
   CLabel  m_lbl_signal; 
   
   CLabel  m_lbl_pos_title;
   CButton m_btn_prev;
   CButton m_btn_next;
   CLabel  m_lbl_selected_pos; 
   
   CLabel    m_lbl_part;   CEdit m_edit_part;
   CButton   m_btn_partial;
   CButton   m_btn_be;
   CButton   m_btn_close;
   CLabel    m_lbl_info;

   bool      m_is_market;
   int       m_selected_dir;
   long      m_selected_ticket; 

public:
   CMyPanel() : m_is_market(true), m_selected_dir(0), m_selected_ticket(0) {}
   ~CMyPanel() {}

   virtual bool Create(const long chart, const string name, const int subwin, const int x1, const int y1, const int x2, const int y2);
   virtual bool OnEvent(const int id, const long &lparam, const double &dparam, const string &sparam);

   bool IsMarket()     { return m_is_market; }
   int  GetDirection() { return m_selected_dir; }
   double GetLot()     { return StringToDouble(m_edit_lot.Text()); }
   double GetSL()      { return StringToDouble(m_edit_sl.Text()); }
   double GetPrice()   { return StringToDouble(m_edit_price.Text()); }
   
   // THIS FUNCTION WAS MISSING
   double GetPartialPercent() { return StringToDouble(m_edit_part.Text()); }
   
   long GetSelectedTicket() { return m_selected_ticket; }
   
   void SetInfo(string text) { m_lbl_info.Text(text); }
   void SetSignal(string text, color clr);
   void SetPrice(double price);
   void UpdateSelectedPosText();
   
   void ToggleMode();
   void SelectDirection(int dir); 
   void CyclePosition(int step); 
   void RefreshPositions();      
};

bool CMyPanel::Create(const long chart, const string name, const int subwin, const int x1, const int y1, const int x2, const int y2) {
   if(!CAppDialog::Create(chart, name, subwin, x1, y1, x2, y2)) return false;
   
   int y = 5; int w = ClientAreaWidth(); int gap = 25;
   
   // Signal
   if(!m_lbl_signal.Create(chart, name+"Sig", subwin, 10, y, w-10, y+20)) return false;
   m_lbl_signal.Text("NO SIGNAL"); m_lbl_signal.Color(clrGray); Add(m_lbl_signal); y += 25;

   // Mode
   if(!m_btn_mode.Create(chart, name+"BtnMode", subwin, 10, y, w-10, y+gap)) return false;
   m_btn_mode.Text("MODE: MARKET"); m_btn_mode.ColorBackground(clrRoyalBlue); Add(m_btn_mode); y += 30;

   // Inputs
   if(!m_lbl_lot.Create(chart, name+"LblLot", subwin, 10, y+5, 50, y+20)) return false;
   m_lbl_lot.Text("Lot:"); Add(m_lbl_lot);
   if(!m_edit_lot.Create(chart, name+"EditLot", subwin, 55, y, w-10, y+20)) return false;
   m_edit_lot.Text(DoubleToString(InpDefaultLot, 2)); Add(m_edit_lot); y += gap;

   if(!m_lbl_sl.Create(chart, name+"LblSL", subwin, 10, y+5, 50, y+20)) return false;
   m_lbl_sl.Text("SL:"); Add(m_lbl_sl);
   if(!m_edit_sl.Create(chart, name+"EditSL", subwin, 55, y, w-10, y+20)) return false;
   m_edit_sl.Text("0"); Add(m_edit_sl); y += gap;
   
   if(!m_lbl_price.Create(chart, name+"LblPrc", subwin, 10, y+5, 50, y+20)) return false;
   m_lbl_price.Text("Price:"); Add(m_lbl_price);
   if(!m_edit_price.Create(chart, name+"EditPrc", subwin, 55, y, w-10, y+20)) return false;
   m_edit_price.Text("0.00000"); m_edit_price.ReadOnly(true); m_edit_price.ColorBackground(clrLightGray); Add(m_edit_price); y += 30;

   // Buttons
   if(!m_btn_buy.Create(chart, name+"BtnBuy", subwin, 10, y, (w/2)-2, y+gap)) return false;
   m_btn_buy.Text("BUY"); m_btn_buy.ColorBackground(clrGray); Add(m_btn_buy);
   if(!m_btn_sell.Create(chart, name+"BtnSell", subwin, (w/2)+2, y, w-10, y+gap)) return false;
   m_btn_sell.Text("SELL"); m_btn_sell.ColorBackground(clrGray); Add(m_btn_sell); y += 30;
   
   if(!m_btn_place.Create(chart, name+"BtnPlace", subwin, 10, y, (w/2)-2, y+gap)) return false;
   m_btn_place.Text("Place"); m_btn_place.ColorBackground(clrGoldenrod); Add(m_btn_place);
   if(!m_btn_vis.Create(chart, name+"BtnVis", subwin, (w/2)+2, y, w-10, y+gap)) return false;
   m_btn_vis.Text("Visualize"); Add(m_btn_vis); y += 35;

   // Positions Toggle
   if(!m_lbl_pos_title.Create(chart, name+"LblPosT", subwin, 10, y, w-10, y+15)) return false;
   m_lbl_pos_title.Text("--- Positions ---"); Add(m_lbl_pos_title); y+=20;
   
   if(!m_btn_prev.Create(chart, name+"BtnPrev", subwin, 10, y, 40, y+20)) return false;
   m_btn_prev.Text("<<"); Add(m_btn_prev);
   
   if(!m_lbl_selected_pos.Create(chart, name+"LblSelPos", subwin, 45, y+3, w-45, y+20)) return false;
   m_lbl_selected_pos.Text("None"); Add(m_lbl_selected_pos);
   
   if(!m_btn_next.Create(chart, name+"BtnNext", subwin, w-40, y, w-10, y+20)) return false;
   m_btn_next.Text(">>"); Add(m_btn_next); y += 25;
   
   // Actions
   if(!m_lbl_part.Create(chart, name+"LblPart", subwin, 10, y+5, 80, y+20)) return false;
   m_lbl_part.Text("Partial ($):"); Add(m_lbl_part);
   if(!m_edit_part.Create(chart, name+"EditPart", subwin, 85, y, w-10, y+20)) return false;
   m_edit_part.Text(DoubleToString(InpDefaultPartial, 2)); Add(m_edit_part); y += 25;

   if(!m_btn_partial.Create(chart, name+"BtnDoPart", subwin, 10, y, (w/2)-2, y+gap)) return false;
   m_btn_partial.Text("Partial"); Add(m_btn_partial);
   if(!m_btn_be.Create(chart, name+"BtnDoBE", subwin, (w/2)+2, y, w-10, y+gap)) return false;
   m_btn_be.Text("Set BE"); Add(m_btn_be); y += gap + 2;
   
   if(!m_btn_close.Create(chart, name+"BtnClose", subwin, 10, y, w-10, y+gap)) return false;
   m_btn_close.Text("Close Selected"); m_btn_close.ColorBackground(clrDarkRed); m_btn_close.Color(clrWhite); Add(m_btn_close); y += 30;

   if(!m_lbl_info.Create(chart, name+"LblInfo", subwin, 10, y, w-10, y+20)) return false;
   m_lbl_info.Text("Ready"); Add(m_lbl_info);

   return true;
}

void CMyPanel::SetSignal(string text, color clr) {
   m_lbl_signal.Text(text);
   m_lbl_signal.Color(clr);
}

void CMyPanel::UpdateSelectedPosText() {
   if(m_selected_ticket == 0) {
      m_lbl_selected_pos.Text("None");
   } else {
      if(PositionSelectByTicket(m_selected_ticket)) {
         string type = (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY) ? "BUY" : "SELL";
         double vol = PositionGetDouble(POSITION_VOLUME);
         m_lbl_selected_pos.Text((string)m_selected_ticket + " " + type + " " + DoubleToString(vol,2));
      } else {
         m_lbl_selected_pos.Text("Closed/Invalid");
         m_selected_ticket = 0;
      }
   }
}

void CMyPanel::CyclePosition(int step) {
   int total = PositionsTotal();
   if(total == 0) {
      m_selected_ticket = 0;
      UpdateSelectedPosText();
      return;
   }
   
   // Create a simple list of tickets
   long tickets[];
   int count = 0;
   for(int i=0; i<total; i++) {
      ulong t = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
         ArrayResize(tickets, count+1);
         tickets[count] = t;
         count++;
      }
   }
   
   if(count == 0) { m_selected_ticket = 0; UpdateSelectedPosText(); return; }
   
   // Find current index
   int current_idx = -1;
   for(int i=0; i<count; i++) {
      if(tickets[i] == m_selected_ticket) {
         current_idx = i;
         break;
      }
   }
   
   // Move index
   int next_idx = 0;
   if(current_idx == -1) next_idx = 0;
   else {
      next_idx = current_idx + step;
      if(next_idx >= count) next_idx = 0;
      if(next_idx < 0) next_idx = count - 1;
   }
   
   m_selected_ticket = tickets[next_idx];
   UpdateSelectedPosText();
}

void CMyPanel::RefreshPositions() {
   // Just triggers a UI update to verify current ticket is still valid
   UpdateSelectedPosText();
}

void CMyPanel::ToggleMode() {
   m_is_market = !m_is_market;
   if(m_is_market) { m_btn_mode.Text("MODE: MARKET"); m_btn_mode.ColorBackground(clrRoyalBlue); m_edit_price.ReadOnly(true); m_edit_price.ColorBackground(clrLightGray); } 
   else { m_btn_mode.Text("MODE: PENDING"); m_btn_mode.ColorBackground(clrOrange); m_edit_price.ReadOnly(false); m_edit_price.ColorBackground(clrWhite); }
}

void CMyPanel::SetPrice(double price) { if(m_is_market) m_edit_price.Text(DoubleToString(price, _Digits)); }
void CMyPanel::SelectDirection(int dir) {
   m_selected_dir = dir;
   m_btn_buy.ColorBackground(clrGray); m_btn_sell.ColorBackground(clrGray);
   if(dir == 1) m_btn_buy.ColorBackground(clrGreen);
   if(dir == -1) m_btn_sell.ColorBackground(clrRed);
}
bool CMyPanel::OnEvent(const int id, const long &lparam, const double &dparam, const string &sparam) { return CAppDialog::OnEvent(id, lparam, dparam, sparam); }
