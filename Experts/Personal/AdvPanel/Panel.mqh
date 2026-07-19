//+------------------------------------------------------------------+
//|                                                    Panel.mqh     |
//+------------------------------------------------------------------+
#include <Controls\Dialog.mqh>
#include <Controls\Button.mqh>
#include <Controls\Edit.mqh>
#include <Controls\Label.mqh>
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include "Defines.mqh"
#include "Inputs.mqh" // Ensure InpLimitGapPoints is defined here

// --- NEW ID ---
#define ID_BTN_LIMIT_MODE 803

class CAdvancePanel : public CAppDialog
  {
private:
   // --- UI ELEMENTS ---
   CLabel            m_lbl_balance;
   CLabel            m_lbl_pnl;
   CButton           m_btn_mode;
   CLabel            m_lbl_risk; CEdit m_edit_risk; CLabel m_lbl_calc_lot;
   CLabel            m_lbl_prc;  CEdit m_edit_prc;
   CLabel            m_lbl_sl;   CEdit m_edit_sl;
   CLabel            m_lbl_tp;   CEdit m_edit_tp;
   // Risk/Reward Info Label
   CLabel            m_lbl_rr_info;
   
   CButton           m_btn_preview;
   CButton           m_btn_limit_mode;
   // NEW: Limit Toggle Button
   
   CButton           m_btn_buy;
   CButton           m_btn_sell;
   CButton           m_btn_execute;
   CButton           m_btn_toggle;
   CButton           m_btn_close;
   CLabel            m_lbl_part_lot;
   CEdit             m_edit_part_lot;
   CButton           m_btn_take_partial;
   CButton           m_btn_set_be;
   CButton           m_btn_export;
   CButton           m_btn_partials[3];
   // AI Controls
   CButton           m_btn_ai_scan;
   CButton           m_btn_ai_auto;
   CLabel            m_lbl_ai_status;
   CButton           m_lbl_ai_result;
   // --- NEW LOGGING SYSTEM ---
   CLabel            m_log_rows[10];
   // 10 Visible Log Rows
   CButton           m_btn_log_prev;
   // Back Button
   CButton           m_btn_log_next;
   // Forward Button
   string            m_log_history[];
   // Array to store full log history
   int               m_scroll_idx;
   // Current scroll position

   // --- STATE ---
   bool              m_is_pending_mode;
   long              m_selected_ticket;
   bool              m_is_preview_on;
   bool              m_is_limit_entry;
   // NEW: Track Limit Mode
   ENUM_DIR_STATE    m_selected_dir;
   // Settings Storage
   double            m_p_dist[3];
   double            m_p_vol[3];
   color             c_bg_edit, c_txt_main, c_txt_edit, c_btn_gray;
   int               m_gap_y, m_row_h;
public:
   CAdvancePanel() 
     { 
      m_gap_y = 5;
      m_row_h = 25; 
      m_is_pending_mode = false; 
      m_selected_ticket = 0;
      m_is_preview_on = false;
      m_is_limit_entry = false;
      // Default Off
      m_selected_dir  = DIR_BUY;
      for(int i=0; i<3; i++) { m_p_dist[i]=0; m_p_vol[i]=0;
      }

      c_txt_main  = clrBlack;
      c_bg_edit   = clrLightGray;
      c_txt_edit  = clrBlack;
      c_btn_gray  = clrSilver;
      // Initialize Log History
      ArrayResize(m_log_history, 0);
      m_scroll_idx = 0;
     }
   ~CAdvancePanel() {}

   void SetPartialConfig(double d1, double d2, double d3,
                         double v1, double v2, double v3)
     {
      m_p_dist[0]=d1;
      m_p_dist[1]=d2; m_p_dist[2]=d3;
      m_p_vol[0]=v1;  m_p_vol[1]=v2;  m_p_vol[2]=v3;
     }
     
   // --- AI Methods ---
   bool IsAIScanEnabled() { return (m_btn_ai_scan.ColorBackground() == CLR_AI_ON);
     }
   bool IsAutoExecEnabled() { return (m_btn_ai_auto.ColorBackground() == CLR_AI_AUTO_ON);
     }
   
   void UpdateAIStatus(string text) { m_lbl_ai_status.Text(text);
     }
   
   void ShowSignalResult(int direction, double price) {
      if(direction == 1) {
         m_lbl_ai_result.Text("BUY SIGNAL @ " + DoubleToString(price, _Digits));
         m_lbl_ai_result.ColorBackground(clrGreen);
         m_lbl_ai_result.Color(clrWhite);
      } else if(direction == -1) {
         m_lbl_ai_result.Text("SELL SIGNAL @ " + DoubleToString(price, _Digits));
         m_lbl_ai_result.ColorBackground(clrRed);
         m_lbl_ai_result.Color(clrWhite);
      } else {
         m_lbl_ai_result.Text("NO SIGNAL");
         m_lbl_ai_result.ColorBackground(c_btn_gray);
         m_lbl_ai_result.Color(clrBlack);
      }
   }
   
   // --- UPDATED: LOGGING LOGIC ---
   
   // 1. Add Message, Split if needed, Auto-scroll
   void AddAILog(string msg) {
      string time = TimeToString(TimeCurrent(), TIME_SECONDS);
      string prefix = "[" + StringSubstr(time, 9, 8) + "] ";
      string fullMsg = msg;
      
      int maxLen = 42;
      // Maximum characters per line
      int textLen = StringLen(fullMsg);
      int offset = 0;
      if(textLen <= maxLen) {
         AddToHistory(fullMsg);
      } else {
         // Split long messages
         while(offset < textLen) {
            int count = maxLen;
            if(offset + count > textLen) count = textLen - offset;
            string chunk = StringSubstr(fullMsg, offset, count);
            AddToHistory(chunk);
            offset += count;
         }
      }
      ScrollToBottom();
     }

   // 2. Helper to push to history array
   void AddToHistory(string line) {
      int size = ArraySize(m_log_history);
      ArrayResize(m_log_history, size + 1);
      m_log_history[size] = line;
   }

   // 3. Auto-scroll to newest
   void ScrollToBottom() {
      int total = ArraySize(m_log_history);
      if(total <= 10) m_scroll_idx = 0;
      else m_scroll_idx = total - 10;
      UpdateLogDisplay();
     }

   // 4. Update the visible labels based on scroll index
   void UpdateLogDisplay() {
      int total = ArraySize(m_log_history);
      for(int i=0; i<10; i++) {
         int dataIdx = m_scroll_idx + i;
         if(dataIdx >= 0 && dataIdx < total) {
            m_log_rows[i].Text(m_log_history[dataIdx]);
         } else {
            m_log_rows[i].Text("");
         }
      }
   }
   
   // 5. Button Click Handlers
   void OnClickLogPrev() {
      if(m_scroll_idx > 0) {
         m_scroll_idx--;
         UpdateLogDisplay();
      }
   }

   void OnClickLogNext() {
      int total = ArraySize(m_log_history);
      if(m_scroll_idx < total - 10) {
         m_scroll_idx++; 
         UpdateLogDisplay();
      }
   }

   // --- PERSISTENCE ---
   void SaveState() {
      string pfx = "AP_V7_" + IntegerToString(ChartID()) + "_";
      GlobalVariableSet(pfx + "Risk", StringToDouble(m_edit_risk.Text())); 
      GlobalVariableSet(pfx + "Mode", (double)m_is_pending_mode);
      GlobalVariableSet(pfx + "Dir", (double)m_selected_dir);
      GlobalVariableSet(pfx + "Limit", (double)m_is_limit_entry);
      // Save Limit State
     }

   void LoadState() {
      string pfx = "AP_V7_" + IntegerToString(ChartID()) + "_";
      if(GlobalVariableCheck(pfx + "Risk")) m_edit_risk.Text(DoubleToString(GlobalVariableGet(pfx + "Risk"), 2));
      if(GlobalVariableCheck(pfx + "Mode")) m_is_pending_mode = (bool)GlobalVariableGet(pfx + "Mode");
      if(GlobalVariableCheck(pfx + "Dir")) m_selected_dir = (ENUM_DIR_STATE)GlobalVariableGet(pfx + "Dir");
      if(GlobalVariableCheck(pfx + "Limit")) {
         m_is_limit_entry = (bool)GlobalVariableGet(pfx + "Limit");
         UpdateLimitBtnState();
      }
      
      UpdateModeState(); 
      UpdateDirButtons();
      UpdateRiskReward();
      if(m_is_preview_on) UpdatePreview();
     }

   // --- CREATE ---
   virtual bool Create(const long chart, const string name, const int subwin, const int x1, const int y1)
     {
      if(!CAppDialog::Create(chart, name, subwin, x1, y1, x1+PANEL_WIDTH, y1+PANEL_HEIGHT)) return(false);
      int y = 5;
      
      // 0. ACCOUNT INFO
      CreateLabel(m_lbl_balance, "Bal: ...", 901, 10, y);
      CreateLabel(m_lbl_pnl, "PnL: ...", 902, 130, y);
      y += 20;
      
      // 1. MODE
      if(!CreateButton(m_btn_mode, "MARKET MODE", ID_BTN_MODE, 10, y, PANEL_WIDTH-20, clrTeal, clrWhite)) return false;
      y += m_row_h + m_gap_y + 5; 

      // 2. INPUTS
      CreateLabel(m_lbl_risk, "Risk ($)", ID_EDIT_RISK+1000, 10, y);
      if(!CreateEdit(m_edit_risk, "50", ID_EDIT_RISK, 80, y, 70)) return false; 
      if(!CreateLabel(m_lbl_calc_lot, "Lot: 0.00", 999, 160, y+5)) return false; 
      m_lbl_calc_lot.FontSize(8); m_lbl_calc_lot.Color(clrGray);
      y += m_row_h + m_gap_y;

      // RISK/REWARD INFO
      if(!CreateLabel(m_lbl_rr_info, "Risk: $0 | Gain: $0", 998, 10, y)) return false;
      m_lbl_rr_info.Color(clrDarkBlue); m_lbl_rr_info.FontSize(8);
      y += m_row_h + m_gap_y;

      CreateInputRow(m_lbl_prc, m_edit_prc, "Entry Prc", "0.0000", ID_EDIT_PRICE, y);
      CreateInputRow(m_lbl_sl, m_edit_sl, "SL (%)", InpDefSL, ID_EDIT_SL_PCT, y); // Default from Inputs
      CreateInputRow(m_lbl_tp, m_edit_tp, "TP (%)", InpDefTP, ID_EDIT_TP_PCT, y);
      // Default from Inputs
      
      y += 5;
      // 3. EXECUTION
      // Split row for Preview and Limit Toggle (60% / 40%)
      int w_prev = (int)((PANEL_WIDTH - 25) * 0.6);
      int w_limit = (int)((PANEL_WIDTH - 25) * 0.4);
      
      if(!CreateButton(m_btn_preview, "PREVIEW", ID_BTN_PREVIEW, 10, y, w_prev, c_btn_gray, clrBlack)) return false;
      if(!CreateButton(m_btn_limit_mode, "LIMIT: OFF", ID_BTN_LIMIT_MODE, 10+w_prev+5, y, w_limit, c_btn_gray, clrBlack)) return false;
      y += m_row_h + m_gap_y;

      int w = (PANEL_WIDTH - 30) / 2;
      if(!CreateButton(m_btn_buy, "BUY", ID_BTN_BUY, 10, y, w, clrGreen, clrWhite)) return false;
      if(!CreateButton(m_btn_sell, "SELL", ID_BTN_SELL, 10+w+10, y, w, c_btn_gray, clrBlack)) return false;
      y += m_row_h + m_gap_y;
      
      if(!CreateButton(m_btn_execute, "PLACE ORDER", ID_BTN_EXECUTE, 10, y, PANEL_WIDTH-20, clrNavy, clrWhite)) return false;
      y += m_row_h + m_gap_y + 10;

      // 4. MANAGEMENT
      if(!CreateButton(m_btn_toggle, "TARGET: ALL", ID_BTN_TOGGLE, 10, y, PANEL_WIDTH-20, c_btn_gray, clrWhite)) return false;
      y += m_row_h + m_gap_y;
      if(!CreateButton(m_btn_close, "CLOSE TARGET", ID_BTN_CLOSE, 10, y, PANEL_WIDTH-20, clrCrimson, clrWhite)) return false;
      y += m_row_h + m_gap_y + 10;
      
      CreateInputRow(m_lbl_part_lot, m_edit_part_lot, "Partial %", "20", ID_EDIT_PART_LOT, y);
      if(!CreateButton(m_btn_take_partial, "TAKE PARTIAL %", ID_BTN_TAKE_PART, 10, y, PANEL_WIDTH-20, C'200,100,0', clrWhite)) return false;
      y += m_row_h + m_gap_y;
      if(!CreateButton(m_btn_set_be, "SET BE (Profit Only)", ID_BTN_SET_BE, 10, y, PANEL_WIDTH-20, clrDodgerBlue, clrWhite)) return false;
      y += m_row_h + m_gap_y + 5;
      if(!CreateButton(m_btn_export, "EXPORT CSV", ID_BTN_EXPORT, 10, y, PANEL_WIDTH-20, clrDarkSlateGray, clrWhite)) return false;
      y += m_row_h + m_gap_y + 10;
      // 5. PARTIAL INFO
      for(int i=0; i<3; i++) {
         if(!CreateButton(m_btn_partials[i], "P"+(string)(i+1)+": ...", ID_BTN_P1+i, 10, y, PANEL_WIDTH-20, c_btn_gray, clrWhite)) return false;
         m_btn_partials[i].ColorBackground(CLR_BTN_PARTIAL);
         y += 26; 
      }
      y += 10;
      // 6. AI CONTROLS
      int w2 = (PANEL_WIDTH - 25) / 2;
      if(!CreateButton(m_btn_ai_scan, "AI SIGNAL: OFF", ID_BTN_AI_SCAN, 10, y, w2, CLR_AI_OFF, clrWhite)) return false;
      if(!CreateButton(m_btn_ai_auto, "AUTO EXEC: OFF", ID_BTN_AI_AUTO, 10+w2+5, y, w2, CLR_BTN_OFF, clrBlack)) return false;
      y += m_row_h + 5;
      if(!CreateLabel(m_lbl_ai_status, "Standby", ID_LBL_AI_STATUS, 10, y)) return false;
      y += 15;
      // --- MODIFIED AI RESULT & NAV BUTTONS ---
      // Resize result button to make room for nav buttons
      int resW = PANEL_WIDTH - 75;
      if(!CreateButton(m_lbl_ai_result, "NO SIGNAL", ID_LBL_AI_RESULT, 10, y, resW, c_btn_gray, clrBlack)) return false;
      // Create Back/Next Buttons
      if(!CreateButton(m_btn_log_prev, "<", ID_BTN_LOG_PREV, 10+resW+5, y, 25, clrGray, clrWhite)) return false;
      if(!CreateButton(m_btn_log_next, ">", ID_BTN_LOG_NEXT, 10+resW+30+2, y, 25, clrGray, clrWhite)) return false;
      
      y += m_row_h + 5;
      // 7. AI LOG BOX (Visible Rows)
      for(int i=0; i<10; i++) {
         if(!m_log_rows[i].Create(0, Name()+"_log_"+(string)i, 0, 10, y, PANEL_WIDTH-10, y+14)) return false;
         m_log_rows[i].Color(clrBlack);
         m_log_rows[i].FontSize(8);
         m_log_rows[i].Text("");
         Add(m_log_rows[i]);
         y += 13;
      }
      
      UpdateModeState();
      UpdateDirButtons();
      UpdateRiskReward();
      return(true);
     }

   // --- EVENT MAP ---
   EVENT_MAP_BEGIN(CAdvancePanel)
      ON_EVENT(ON_CLICK, m_btn_mode, OnClickMode)
      ON_EVENT(ON_CLICK, m_btn_buy, OnClickBuyToggle)
      ON_EVENT(ON_CLICK, m_btn_sell, OnClickSellToggle)
      ON_EVENT(ON_CLICK, m_btn_preview, OnClickPreview)
      ON_EVENT(ON_CLICK, m_btn_execute, OnClickExecute)
      ON_EVENT(ON_CLICK, m_btn_toggle, OnClickToggle)
      ON_EVENT(ON_CLICK, m_btn_close, OnClickClose)
      ON_EVENT(ON_CLICK, m_btn_take_partial, OnClickTakePartial)
      ON_EVENT(ON_CLICK, m_btn_set_be, OnClickSetBE)
      ON_EVENT(ON_CLICK, m_btn_export, OnClickExport)
      
      // Limit Toggle Event
      ON_EVENT(ON_CLICK, m_btn_limit_mode, OnClickLimitMode)
 
      ON_EVENT(ON_CLICK, m_btn_ai_scan, OnClickAIScan)
      ON_EVENT(ON_CLICK, m_btn_ai_auto, OnClickAIAuto)
      
      // NEW EVENTS
      ON_EVENT(ON_CLICK, m_btn_log_prev, OnClickLogPrev)
      ON_EVENT(ON_CLICK, m_btn_log_next, OnClickLogNext)
      
      ON_EVENT(ON_CLICK, m_btn_partials[0], OnClickP1)
      ON_EVENT(ON_CLICK, m_btn_partials[1], OnClickP2)
      ON_EVENT(ON_CLICK, m_btn_partials[2], OnClickP3)
      
      ON_EVENT(ON_END_EDIT, m_edit_risk, OnChangeInput)
      ON_EVENT(ON_END_EDIT, m_edit_prc, OnChangeInput)
   
      ON_EVENT(ON_END_EDIT, m_edit_sl, OnChangeInput)
      ON_EVENT(ON_END_EDIT, m_edit_tp, OnChangeInput)
   EVENT_MAP_END(CAppDialog)
   
   // --- LOGIC ---
   
   // NEW: Toggle Limit Logic
   void OnClickLimitMode() {
      m_is_limit_entry = !m_is_limit_entry;
      UpdateLimitBtnState();
      if(m_is_preview_on) UpdatePreview(); // Update preview if on
      UpdateRiskReward();
      // Update calculations
      SaveState();
   }
   
   void UpdateLimitBtnState() {
      if(m_is_limit_entry) {
         m_btn_limit_mode.Text("LIMIT: ON");
         m_btn_limit_mode.ColorBackground(clrOrange);
         m_btn_limit_mode.Color(clrWhite);
      } else {
         m_btn_limit_mode.Text("LIMIT: OFF");
         m_btn_limit_mode.ColorBackground(c_btn_gray);
         m_btn_limit_mode.Color(clrBlack);
      }
   }
   
   void UpdateRiskReward() {
      double riskUSD = StringToDouble(m_edit_risk.Text());
      double sl_pct = StringToDouble(m_edit_sl.Text());
      double tp_pct = StringToDouble(m_edit_tp.Text());
      double entry = StringToDouble(m_edit_prc.Text());
      
      if(!m_is_pending_mode) {
         if(m_selected_dir == DIR_BUY) entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         else                          entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         
         // Apply Gap Logic when Limit Mode is ON
         if(m_is_limit_entry) {
             double gap = InpLimitGapPoints * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
             if(m_selected_dir == DIR_BUY) entry = SymbolInfoDouble(_Symbol, SYMBOL_BID) - gap;
             else                          entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + gap;
         }
      }
      
      if(entry <= 0 || sl_pct <= 0) {
         m_lbl_rr_info.Text("Invalid Entry/SL");
         return;
      }

      double lot = CalculateLotSize(riskUSD, sl_pct, entry);
      m_lbl_calc_lot.Text("Lot: " + DoubleToString(lot, 2));
      // Calculate Potential Gain
      double distTP_price = entry * (tp_pct / 100.0);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      
      double gainUSD = 0;
      if(tickSize > 0 && tickVal > 0) {
         gainUSD = (distTP_price / tickSize) * tickVal * lot;
      }
      
      m_lbl_rr_info.Text("Risk: $" + DoubleToString(riskUSD, 2) + " | Gain: $" + DoubleToString(gainUSD, 2));
   }
   
   void OnChangeInput() { 
      UpdateRiskReward(); 
      if(m_is_preview_on) UpdatePreview(); 
      SaveState();
   }

   void OnClickPreview() {
      m_is_preview_on = !m_is_preview_on;
      if(m_is_preview_on) {
         m_btn_preview.ColorBackground(CLR_BTN_ON_PREV);
         m_btn_preview.Color(clrWhite);
         UpdatePreview();
         UpdateRiskReward();
      } else {
         m_btn_preview.ColorBackground(c_btn_gray);
         m_btn_preview.Color(clrBlack);
         ObjectsDeleteAll(0, PREFIX_PREVIEW);
      }
   }

   void OnClickAIScan() {
      bool isOn = (m_btn_ai_scan.ColorBackground() == CLR_AI_ON);
      if(isOn) {
         m_btn_ai_scan.Text("AI SIGNAL: OFF");
         m_btn_ai_scan.ColorBackground(CLR_AI_OFF);
         m_btn_ai_scan.Color(clrWhite);
         UpdateAIStatus("Stopped");
         AddAILog("AI Scanning Stopped.");
      } else {
         m_btn_ai_scan.Text("AI SIGNAL: ON");
         m_btn_ai_scan.ColorBackground(CLR_AI_ON);
         m_btn_ai_scan.Color(clrBlack);
         UpdateAIStatus("Initializing...");
         AddAILog("AI Scanning Started.");
      }
      EventChartCustom(0, ID_BTN_AI_SCAN, 0, 0, "");
   }
   
   void OnClickAIAuto() {
      bool isOn = (m_btn_ai_auto.ColorBackground() == CLR_AI_AUTO_ON);
      if(isOn) {
         m_btn_ai_auto.Text("AUTO EXEC: OFF");
         m_btn_ai_auto.ColorBackground(CLR_BTN_OFF);
         m_btn_ai_auto.Color(clrBlack);
         AddAILog("Auto Execution DISABLED.");
      } else {
         m_btn_ai_auto.Text("AUTO EXEC: ON");
         m_btn_ai_auto.ColorBackground(CLR_AI_AUTO_ON);
         m_btn_ai_auto.Color(clrWhite);
         AddAILog("Auto Execution ENABLED.");
      }
   }

   void OnClickSetBE() {
      if(m_selected_ticket != 0) {
         if(!SetBEForTicket((ulong)m_selected_ticket)) Print("SetBE Failed for selected ticket.");
      }
      else {
         int total = PositionsTotal();
         int count = 0;
         for(int i=total-1; i>=0; i--) {
            if(SetBEForTicket(PositionGetTicket(i))) count++;
      }
         Print("Set BE attempted on all. Success count: ", count);
      }
   }
   
   bool SetBEForTicket(ulong ticket) {
      if(!PositionSelectByTicket(ticket)) return false;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) return false;
      
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      int type = (int)PositionGetInteger(POSITION_TYPE);
      if(MathAbs(curSL - open) < point * 2 && curSL != 0) return true; 
      
      bool canMove = false;
      long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      double stopDist = stopsLevel * point;
      if(type == POSITION_TYPE_BUY) { if(bid > open + stopDist) canMove = true;
      } 
      else { if(ask < open - stopDist) canMove = true;
      }
      
      if(!canMove) {
         Print("Cannot Set BE for Ticket ", ticket, ". Profit must > StopsLevel.");
         return false;
      }
      
      CTrade trade;
      trade.SetExpertMagicNumber(PositionGetInteger(POSITION_MAGIC));
      return trade.PositionModify(ticket, open, curTP);
   }

   void UpdatePreview() {
      ObjectsDeleteAll(0, PREFIX_PREVIEW);
      if(!m_is_preview_on) return;
      double risk = StringToDouble(m_edit_risk.Text());
      double sl_pct = StringToDouble(m_edit_sl.Text());
      double tp_pct = StringToDouble(m_edit_tp.Text());
      double entry = StringToDouble(m_edit_prc.Text());
      
      if(!m_is_pending_mode) {
         if(m_selected_dir == DIR_BUY) entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         else                          entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         
         // Apply Gap Logic for Preview
         if(m_is_limit_entry) {
             double gap = InpLimitGapPoints * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
             if(m_selected_dir == DIR_BUY) entry = SymbolInfoDouble(_Symbol, SYMBOL_BID) - gap;
             else                          entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + gap;
         }
      }

      double lot = CalculateLotSize(risk, sl_pct, entry);
      m_lbl_calc_lot.Text("Lot: " + DoubleToString(lot, 2));
      double priceSL = 0, priceTP = 0;
      if(m_selected_dir == DIR_BUY) {
         priceSL = entry * (1.0 - (sl_pct/100.0));
         priceTP = entry * (1.0 + (tp_pct/100.0));
      } else {
         priceSL = entry * (1.0 + (sl_pct/100.0));
         priceTP = entry * (1.0 - (tp_pct/100.0));
      }
      
      m_lbl_sl.Text("SL (" + DoubleToString(priceSL, _Digits) + ")");
      m_lbl_tp.Text("TP (" + DoubleToString(priceTP, _Digits) + ")");

      DrawLine(PREFIX_PREVIEW + "ENTRY", entry, clrGray, "Entry");
      DrawLine(PREFIX_PREVIEW + "SL", priceSL, clrRed, "SL");
      DrawLine(PREFIX_PREVIEW + "TP", priceTP, clrGreen, "TP");

      for(int i=0; i<3; i++) {
         if(m_p_dist[i] <= 0) continue;
         double pPrice = 0;
         if(m_selected_dir == DIR_BUY) pPrice = entry * (1.0 + (m_p_dist[i]/100.0));
         else                          pPrice = entry * (1.0 - (m_p_dist[i]/100.0));
         DrawLine(PREFIX_PREVIEW + "P" + (string)(i+1), pPrice, clrDodgerBlue, "P" + (string)(i+1), STYLE_DOT); 
      }
      ChartRedraw(0);
     }
   
   void OnClickP1() { ManualPartial(0); }
   void OnClickP2() { ManualPartial(1);
     }
   void OnClickP3() { ManualPartial(2); }
   
   void ManualPartial(int idx) {
      if(m_selected_ticket==0) return;
      double pct = m_p_vol[idx];
      ClosePct((ulong)m_selected_ticket, pct);
      string gv = "GV_" + (string)m_selected_ticket + "_P" + (string)(idx+1) + "_DONE";
      GlobalVariableSet(gv, 1.0);
     }

   void UpdatePartialInfo(string p1, string p2, string p3) { 
      m_btn_partials[0].Text(p1);
      m_btn_partials[1].Text(p2); 
      m_btn_partials[2].Text(p3);
     }
   
   void ClearPartialLabels() { 
       for(int i=0; i<3; i++) m_btn_partials[i].Text("P"+(string)(i+1)+": ...");
     }

   // --- HELPERS ---
   void DrawLine(string name, double price, color clr, string text, ENUM_LINE_STYLE style=STYLE_SOLID) {
      if(ObjectFind(0, name) < 0) {
         ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
         ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      }
      ObjectSetInteger(0, name, OBJPROP_STYLE, style);
      ObjectSetDouble(0, name, OBJPROP_PRICE, price);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
     }

   double CalculateLotSize(double risk, double sl_pct, double entryPrice) {
      if(risk <= 0 || sl_pct <= 0 || entryPrice <= 0) return 0.0;
      double distPrice = entryPrice * (sl_pct / 100.0);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tickSize == 0 || tickVal == 0) return 0.0;
      double lossPerLot = (distPrice / tickSize) * tickVal;
      if(lossPerLot == 0) return 0.0;
      double lots = risk / lossPerLot;
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      lots = MathFloor(lots/step) * step;
      if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) lots = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      if(lots > SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX)) lots = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      return lots;
     }

   bool CreateButton(CButton &btn, string text, int id, int x, int y, int w, color bg, color txt) { if(!btn.Create(0, Name()+"_"+(string)id, 0, x, y, x+w, y+m_row_h)) return false;
      btn.Text(text); btn.ColorBackground(bg); btn.Color(txt); Add(btn); return true; }
   bool CreateLabel(CLabel &lbl, string text, int id, int x, int y) { if(!lbl.Create(0, Name()+"_lbl_"+(string)id, 0, x, y, x+80, y+m_row_h)) return false;
      lbl.Text(text); lbl.Color(clrBlack); Add(lbl); return true; }
   bool CreateEdit(CEdit &edt, string text, int id, int x, int y, int w) { if(!edt.Create(0, Name()+"_"+(string)id, 0, x, y, x+w, y+m_row_h)) return false;
      edt.Text(text); edt.ColorBackground(c_bg_edit); edt.Color(c_txt_edit); Add(edt); return true; }
   void CreateInputRow(CLabel &lbl, CEdit &edt, string label_txt, string val, int id, int &y) { CreateLabel(lbl, label_txt, id+1000, 10, y);
      CreateEdit(edt, val, id, 100, y, 120); y += m_row_h + m_gap_y; }
   long GetSelectedTicket() { return m_selected_ticket;
     }
   
   void OnClickMode() { m_is_pending_mode = !m_is_pending_mode; UpdateModeState(); UpdateRiskReward(); SaveState();
     }
   void OnClickClose() {
      CTrade trade;
      if(m_selected_ticket == 0) { for(int i=PositionsTotal()-1; i>=0; i--) trade.PositionClose(PositionGetTicket(i)); }
      else { if(trade.PositionClose((ulong)m_selected_ticket)) { m_selected_ticket=0;
      UpdateToggleDisplay(); } }
   }
   void UpdateModeState() { 
      if(m_is_pending_mode) { 
         m_btn_mode.Text("PENDING MODE");
         m_btn_mode.ColorBackground(CLR_BTN_PENDING); 
         m_edit_prc.ReadOnly(false); m_edit_prc.ColorBackground(c_bg_edit); 
      } else { 
         m_btn_mode.Text("MARKET MODE"); m_btn_mode.ColorBackground(CLR_BTN_MARKET); 
         m_edit_prc.ReadOnly(true); m_edit_prc.ColorBackground(c_btn_gray);
         UpdateMarketPrice(); 
      }
   }
   void UpdateMarketPrice() { 
      if(!m_is_pending_mode) { 
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         m_edit_prc.Text(DoubleToString(bid, _Digits)); 
         if(m_is_preview_on) UpdatePreview(); 
      }
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      m_lbl_balance.Text("Bal: $" + DoubleToString(bal, 2));
     }
   void UpdatePnL(double profit) {
      m_lbl_pnl.Text("PnL: $" + DoubleToString(profit, 2));
      if(profit >= 0) m_lbl_pnl.Color(clrGreen); else m_lbl_pnl.Color(clrRed);
   }
   void OnClickExport() { 
      if(!HistorySelect(0, TimeCurrent())) return;
      string filename = "TradingJournal.csv";
      int handle = FileOpen(filename, FILE_WRITE|FILE_CSV|FILE_ANSI, ",");
      if(handle != INVALID_HANDLE) {
         FileWrite(handle, "Time", "Ticket", "Symbol", "Type", "Volume", "Price", "Profit", "Comment");
         int total = HistoryDealsTotal();
         for(int i=0; i<total; i++) {
             ulong t = HistoryDealGetTicket(i);
             if(t>0) FileWrite(handle, HistoryDealGetInteger(t, DEAL_TIME), t, HistoryDealGetString(t, DEAL_SYMBOL), HistoryDealGetInteger(t, DEAL_TYPE), HistoryDealGetDouble(t, DEAL_VOLUME), HistoryDealGetDouble(t, DEAL_PRICE), HistoryDealGetDouble(t, DEAL_PROFIT), HistoryDealGetString(t, DEAL_COMMENT));
         }
         FileClose(handle);
         Print("Exported.");
      }
   }
   void OnClickToggle() { 
      int total = PositionsTotal();
      if(total == 0) { m_selected_ticket = 0; }
      else if(m_selected_ticket == 0) { m_selected_ticket = PositionGetTicket(0);
      }
      else {
         int idx = -1;
         for(int i=0; i<total; i++) if(PositionGetTicket(i) == m_selected_ticket) { idx=i; break;
         }
         if(idx == total-1 || idx==-1) m_selected_ticket=0;
         else m_selected_ticket = PositionGetTicket(idx+1);
      }
      UpdateToggleDisplay();
   }
   void UpdateToggleDisplay() {
      if(m_selected_ticket == 0) { m_btn_toggle.Text("TARGET: ALL");
      ClearPartialLabels(); }
      else m_btn_toggle.Text("TARGET: " + (string)m_selected_ticket);
     }
   void OnClickTakePartial() {
      double pct = StringToDouble(m_edit_part_lot.Text());
      if(pct <= 0) return;
      if(m_selected_ticket != 0) ClosePct((ulong)m_selected_ticket, pct);
      else {
         for(int i=PositionsTotal()-1; i>=0; i--) {
            ulong t = PositionGetTicket(i);
            if(PositionSelectByTicket(t)) {
               if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
               if(PositionGetDouble(POSITION_PROFIT) <= 0) continue; 
               ClosePct(t, pct);
            }
         }
      }
      SaveState();
     }
   void ClosePct(ulong t, double pct) {
      if(!PositionSelectByTicket(t)) return;
      double vol = PositionGetDouble(POSITION_VOLUME);
      double target = vol * (pct/100.0);
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      target = MathFloor(target/step)*step;
      if(target < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) target = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      CTrade tr; tr.PositionClosePartial(t, target);
     }
   void OnClickBuyToggle() { m_selected_dir = DIR_BUY; UpdateDirButtons(); if(m_is_preview_on) UpdatePreview(); UpdateRiskReward();
     }
   void OnClickSellToggle() { m_selected_dir = DIR_SELL; UpdateDirButtons(); if(m_is_preview_on) UpdatePreview(); UpdateRiskReward();
     }
   void UpdateDirButtons() {
      if(m_selected_dir == DIR_BUY) { m_btn_buy.ColorBackground(clrGreen); m_btn_buy.Color(clrWhite); m_btn_sell.ColorBackground(c_btn_gray); m_btn_sell.Color(clrBlack); m_edit_sl.Color(clrRed);
      m_edit_tp.Color(clrGreen); }
      else { m_btn_buy.ColorBackground(c_btn_gray); m_btn_buy.Color(clrBlack); m_btn_sell.ColorBackground(clrRed); m_btn_sell.Color(clrWhite); m_edit_sl.Color(clrRed); m_edit_tp.Color(clrGreen);
      }
   }
   void OnClickExecute() { 
      if(m_selected_dir == DIR_NONE) return;
      double risk = StringToDouble(m_edit_risk.Text());
      double sl_pct = StringToDouble(m_edit_sl.Text());
      double tp_pct = StringToDouble(m_edit_tp.Text());
      CTrade trade;
      double sl=0, tp=0, entry=0;
      double lot = 0;
      
      // Determine Entry Price
      if(m_is_pending_mode) { 
          entry = StringToDouble(m_edit_prc.Text());
      } 
      else {
         // MARKET MODE (Standard or Limit-Entry)
         if(m_is_limit_entry) {
             // GAP LOGIC: Calculate entry point away from market
             double gap = InpLimitGapPoints * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
             
             if(m_selected_dir == DIR_BUY) {
                 // Buy Limit must be below Bid to be valid. We place it at Bid - Gap.
                 entry = SymbolInfoDouble(_Symbol, SYMBOL_BID) - gap;
             }
             else {
                 // Sell Limit must be above Ask to be valid. We place it at Ask + Gap.
                 entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + gap;
             }
             entry = NormalizeDouble(entry, _Digits);
         } else {
             // Standard Market Execution
             if(m_selected_dir == DIR_BUY) entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
             else                          entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         }
      }
      
      lot = CalculateLotSize(risk, sl_pct, entry);
      if(lot <= 0) { Print("Invalid Lot"); return; }
      
      if(m_selected_dir == DIR_BUY) {
         sl = entry * (1.0 - (sl_pct/100.0));
         tp = entry * (1.0 + (tp_pct/100.0));
      } else {
         sl = entry * (1.0 + (sl_pct/100.0));
         tp = entry * (1.0 - (tp_pct/100.0));
      }
      
      // EXECUTION LOGIC
      if(m_is_pending_mode) {
         // Manual Pending
         if(m_selected_dir == DIR_BUY) {
             if(entry < SymbolInfoDouble(_Symbol, SYMBOL_ASK)) trade.BuyLimit(lot, entry, _Symbol, sl, tp);
             else trade.BuyStop(lot, entry, _Symbol, sl, tp);
         } else {
             if(entry > SymbolInfoDouble(_Symbol, SYMBOL_BID)) trade.SellLimit(lot, entry, _Symbol, sl, tp);
             else trade.SellStop(lot, entry, _Symbol, sl, tp);
         }
      } 
      else {
         // Market Mode Context
         if(m_is_limit_entry) {
             // LIMIT ENTRY ON: Send Limit Order with Gap
             if(m_selected_dir == DIR_BUY) {
                 trade.BuyLimit(lot, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "Panel Limit Entry");
             } else {
                 trade.SellLimit(lot, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "Panel Limit Entry");
             }
         } else {
             // STANDARD MARKET EXECUTION
             if(m_selected_dir == DIR_BUY) trade.Buy(lot, _Symbol, entry, sl, tp, "Panel Buy");
             else trade.Sell(lot, _Symbol, entry, sl, tp, "Panel Sell");
         }
      }
      
      if(m_is_preview_on) ObjectsDeleteAll(0, PREFIX_PREVIEW);
      SaveState();
   }
   void ShowParsedSignal(string text) {
      // 1. Clean up newlines for easier searching
      string work = text;
      StringReplace(work, "\n", " ");
      StringReplace(work, "\r", " ");
      
      // 2. Define the keys to look for
      string kAction = "Action:";
      string kEntry  = "Entry:";
      string kSL     = "Stop Loss:";
      string kTP     = "Take Profit:";
      string kReason = "Reason:";
      // 3. Find positions of keys
      int pAction = StringFind(work, kAction);
      int pEntry  = StringFind(work, kEntry);
      int pSL     = StringFind(work, kSL);
      int pTP     = StringFind(work, kTP);
      int pReason = StringFind(work, kReason);
      // 4. Fallback: If format is wrong, just log raw text
      if(pAction < 0 || pEntry < 0) {
         AddAILog("Raw: " + StringSubstr(text, 0, 40) + "...");
         return;
      }
      
      // 5. Extract Values using helper
      string vAction = GetStrBetween(work, pAction, pEntry, kAction);
      string vEntry  = GetStrBetween(work, pEntry, pSL, kEntry);
      string vSL     = GetStrBetween(work, pSL, pTP, kSL);
      string vTP     = GetStrBetween(work, pTP, pReason, kTP);
      
      string vReason = "";
      if(pReason >= 0) {
         vReason = StringSubstr(work, pReason + StringLen(kReason));
         StringTrimLeft(vReason); StringTrimRight(vReason);
      }
      
      // 6. Push to Log History (Formatted as Labels)
      string time = TimeToString(TimeCurrent(), TIME_SECONDS);
      AddToHistory("------------------------------");
      AddToHistory("SIGNAL DETAILS:");
      AddToHistory("ACT : " + vAction);
      AddToHistory("ENT : " + vEntry);
      AddToHistory("SL  : " + vSL);
      AddToHistory("TP  : " + vTP);
      
      // 7. Handle 'Reason' (Split it using AddAILog logic without timestamp)
      string prefix = "RSN : ";
      string fullReason = prefix + vReason;
      
      // Reuse splitting logic manually to avoid double timestamps
      int maxLen = 42;
      int textLen = StringLen(fullReason);
      int offset = 0;
      while(offset < textLen) {
         int count = maxLen;
         if(offset + count > textLen) count = textLen - offset;
         AddToHistory(StringSubstr(fullReason, offset, count));
         offset += count;
      }
      
      AddToHistory("------------------------------");
      ScrollToBottom();
     }

   // Helper to extract text between two indices
   string GetStrBetween(string text, int startIdx, int endIdx, string key) {
      if(startIdx < 0) return "";
      int valStart = startIdx + StringLen(key);
      int len = -1;
      // If endIdx is valid and comes after start, calculate length
      if(endIdx > valStart) len = endIdx - valStart;
      string res = StringSubstr(text, valStart, len);
      StringTrimLeft(res); StringTrimRight(res);
      return res;
   }
  };