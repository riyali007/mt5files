//+------------------------------------------------------------------+
//|                                                PriceLineInfo.mq5 |
//|                                     Advanced Price Line Display  |
//|               Updated: Restored Net P/L + Pips (Complete Info)   |
//+------------------------------------------------------------------+
#property copyright "YourName"
#property link      "https://www.mql5.com"
#property version   "1.40"
#property indicator_chart_window

//--- ENUMS
enum ENUM_INFO_LOCATION
{
   LOC_PRICE_LINE,      // Float with Price Line
   LOC_TOP_LEFT,        // Fixed: Top Left
   LOC_TOP_RIGHT,       // Fixed: Top Right
   LOC_BOTTOM_LEFT,     // Fixed: Bottom Left
   LOC_BOTTOM_RIGHT,    // Fixed: Bottom Right
   LOC_BOTTOM_CENTER,   // Fixed: Bottom Center
   LOC_CENTER_SCREEN    // Fixed: Middle of Screen
};

//--- INPUTS
input group "--- Visual Settings ---"
input color          InpColorCurrent   = clrOrange;      // Color: Current Time
input color          InpColorHTF       = clrDeepSkyBlue; // Color: HTF Times
input color          InpColorInfo      = clrWhite;       // Color: General Text
input color          InpColorWin       = clrLimeGreen;   // Color: Profits/Wins
input color          InpColorLoss      = clrRed;         // Color: Losses
input int            InpFontSize       = 9;              // Font Size

input group "--- Line Settings ---"
input bool           InpShowBidLine    = true;           // Show Custom Bid Line
input color          InpColorBidLine   = clrDarkGray;    // Color: Bid Line (Price Line)
input ENUM_LINE_STYLE InpStyleBidLine  = STYLE_SOLID;    // Style: Bid Line
input bool           InpShowMidLine    = true;           // Show Mid Price Line
input color          InpColorMidLine   = clrBlue;        // Color: Mid Line ((Ask+Bid)/2)
input ENUM_LINE_STYLE InpStyleMidLine  = STYLE_DOT;      // Style: Mid Line

input bool           InpShowStats      = true;           // Show PnL Stats
input bool           InpShowPrice1     = true;           // Show HTF 1 Price 
input bool           InpShowPrice2     = true;           // Show HTF 2 Price 

input group "--- Positioning ---"
input ENUM_INFO_LOCATION InpLocation   = LOC_PRICE_LINE; // Location of Info Block
input int            InpEdgeGap        = 50;             // Gap from Edge (X)
input int            InpVertGap        = 20;             // Gap from Top/Bottom (Y)
input int            InpSpreadGap      = 20;             // Gap between columns (Price Line mode)
input int            InpTimeWidth      = 85;             // Width of Time Column (Price Line mode)

input group "--- Timeframes ---"
input ENUM_TIMEFRAMES InpHTF1          = PERIOD_H1;      // Higher Timeframe 1
input ENUM_TIMEFRAMES InpHTF2          = PERIOD_H4;      // Higher Timeframe 2

//--- GLOBAL VARIABLES
string obj_prefix    = "PLI_";
string lbl_curr      = obj_prefix + "Curr";        
string lbl_htf1      = obj_prefix + "HTF1";        
string lbl_htf2      = obj_prefix + "HTF2";        
// Re-purposed labels for Stats
string lbl_stat1     = obj_prefix + "Stat1"; // Total PnL + Pips
string lbl_stat2     = obj_prefix + "Stat2"; // Wins + Net Profit + Pips
string lbl_stat3     = obj_prefix + "Stat3"; // Losses + Net Loss + Pips
// Lines
string line_bid      = obj_prefix + "LineBid";
string line_mid      = obj_prefix + "LineMid";      

// Struct to hold calculated values
struct DayStats {
   double total_pnl;
   double total_pips;
   
   int    wins;
   double net_profit; // Total $ gained from winners
   double win_pips;
   
   int    losses;
   double net_loss;   // Total $ lost from losers
   double loss_pips;
};

DayStats current_stats;

// Arrays to group deals by Position ID
ulong  unique_pos_ids[];
double unique_pos_pnl[];
double unique_pos_pips[];

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   CreateLabel(lbl_curr, InpColorCurrent);
   CreateLabel(lbl_htf1, InpColorHTF);
   CreateLabel(lbl_htf2, InpColorHTF);
   
   CreateLabel(lbl_stat1, InpColorInfo);
   CreateLabel(lbl_stat2, InpColorInfo);
   CreateLabel(lbl_stat3, InpColorInfo);

   if(InpShowBidLine) UpdateHLine(line_bid, 0, InpColorBidLine, InpStyleBidLine);
   if(InpShowMidLine) UpdateHLine(line_mid, 0, InpColorMidLine, InpStyleMidLine);

   EventSetTimer(1); 
   UpdateDisplay();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, obj_prefix);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Events                                                           |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
{
   UpdateDisplay();
   return(rates_total);
}

void OnTimer()
{
   UpdateDisplay();
}

//+------------------------------------------------------------------+
//| Helper: Find index of Position ID in array                       |
//+------------------------------------------------------------------+
int GetPositionIndex(ulong id)
{
   int size = ArraySize(unique_pos_ids);
   for(int i = 0; i < size; i++)
   {
      if(unique_pos_ids[i] == id) return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Logic: Calculate PnL & Pips for Today (Aggregated by Position)   |
//+------------------------------------------------------------------+
void CalculateDayStats()
{
   current_stats.total_pnl = 0;
   current_stats.total_pips = 0;
   current_stats.wins = 0;
   current_stats.net_profit = 0;
   current_stats.win_pips = 0;
   current_stats.losses = 0;
   current_stats.net_loss = 0;
   current_stats.loss_pips = 0;
   
   ArrayFree(unique_pos_ids);
   ArrayFree(unique_pos_pnl);
   ArrayFree(unique_pos_pips);

   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   int digits        = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   if(tick_value == 0) return;

   datetime start_day = iTime(_Symbol, PERIOD_D1, 0);
   
   if(HistorySelect(start_day, TimeCurrent()))
   {
      int deals = HistoryDealsTotal();
      
      for(int i = 0; i < deals; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         long entry   = HistoryDealGetInteger(ticket, DEAL_ENTRY);
         
         if(entry == DEAL_ENTRY_IN) continue; 
         
         ulong pos_id  = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
         double swap   = HistoryDealGetDouble(ticket, DEAL_SWAP);
         double comm   = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         double vol    = HistoryDealGetDouble(ticket, DEAL_VOLUME);
         
         double total_money = profit + swap + comm;
         
         // Calculate Pips
         double deal_points = 0;
         if(vol > 0) deal_points = profit / (vol * tick_value); 
         
         double deal_pips = deal_points;
         if(digits == 3 || digits == 5) deal_pips /= 10.0;
         
         // Aggregate by Position
         int idx = GetPositionIndex(pos_id);
         
         if(idx == -1) // New
         {
            int s = ArraySize(unique_pos_ids);
            ArrayResize(unique_pos_ids, s + 1);
            ArrayResize(unique_pos_pnl, s + 1);
            ArrayResize(unique_pos_pips, s + 1);
            
            unique_pos_ids[s]  = pos_id;
            unique_pos_pnl[s]  = total_money;
            unique_pos_pips[s] = deal_pips;
         }
         else // Partial
         {
            unique_pos_pnl[idx]  += total_money;
            unique_pos_pips[idx] += deal_pips;
         }
         
         current_stats.total_pnl += total_money;
      }
      
      // Classify Wins vs Losses
      int unique_count = ArraySize(unique_pos_ids);
      for(int i = 0; i < unique_count; i++)
      {
         double final_pnl  = unique_pos_pnl[i];
         double final_pips = unique_pos_pips[i]/10;
         
         current_stats.total_pips += final_pips;

         if(final_pnl >= 0) {
            current_stats.wins++;
            current_stats.net_profit += final_pnl;
            current_stats.win_pips += final_pips;
         }
         else {
            current_stats.losses++;
            current_stats.net_loss += final_pnl;
            current_stats.loss_pips += final_pips;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Main Display Logic                                               |
//+------------------------------------------------------------------+
void UpdateDisplay()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   if(InpShowBidLine) UpdateHLine(line_bid, bid, InpColorBidLine, InpStyleBidLine);
   double mid_price = (ask + bid) / 2.0;
   if(InpShowMidLine) UpdateHLine(line_mid, mid_price, InpColorMidLine, InpStyleMidLine);
   
   string txt_curr = TimeframeToString(Period()) + ": " + GetTimeLeft(Period());
   string txt_htf1 = TimeframeToString(InpHTF1) + ": " + GetTimeLeft(InpHTF1);
   string txt_htf2 = TimeframeToString(InpHTF2) + ": " + GetTimeLeft(InpHTF2);

   CalculateDayStats();

   // Format Stats Strings
   string txt_stat1 = "PnL: " + DoubleToString(current_stats.total_pnl, 2) + " (" + DoubleToString(current_stats.total_pips, 1) + " pips)";
   
   string txt_stat2 = "W: " + IntegerToString(current_stats.wins) + 
                      " | NP: " + DoubleToString(current_stats.net_profit, 2) + 
                      " (" + DoubleToString(current_stats.win_pips, 1) + " pips)";
                      
   string txt_stat3 = "L: " + IntegerToString(current_stats.losses) + 
                      " | NL: " + DoubleToString(current_stats.net_loss, 2) + 
                      " (" + DoubleToString(current_stats.loss_pips, 1) + " pips)";
   
   color color_pnl = (current_stats.total_pnl >= 0) ? InpColorWin : InpColorLoss;

   int x = 0, y_line = 0;
   if(ChartTimePriceToXY(0, 0, TimeCurrent(), bid, x, y_line)) 
   {
      int step_y = InpFontSize + 4;
      int x_line = InpEdgeGap;
      
      if(InpShowPrice2) MoveLabel(lbl_htf2, x_line, y_line - (step_y * 2) - 15, txt_htf2, CORNER_RIGHT_UPPER, ANCHOR_RIGHT_UPPER, InpColorHTF);
      if(InpShowPrice1) MoveLabel(lbl_htf1, x_line, y_line - step_y - 15, txt_htf1, CORNER_RIGHT_UPPER, ANCHOR_RIGHT_UPPER, InpColorHTF);
      MoveLabel(lbl_curr, x_line, y_line + 15, txt_curr, CORNER_RIGHT_UPPER, ANCHOR_RIGHT_UPPER, InpColorCurrent);
   }

   if(InpShowStats)
   {
      if(InpLocation == LOC_PRICE_LINE)
      {
         if(y_line > 0) 
         {
            int step_y = InpFontSize + 4;
            int x_right = InpEdgeGap;
            int x_left  = InpEdgeGap + InpTimeWidth + InpSpreadGap;
            
            MoveLabel(lbl_stat1, x_left, y_line - step_y - 5, txt_stat1, CORNER_RIGHT_UPPER, ANCHOR_RIGHT_UPPER, color_pnl);
            MoveLabel(lbl_stat2, x_left, y_line + 15, txt_stat2, CORNER_RIGHT_UPPER, ANCHOR_RIGHT_UPPER, InpColorWin);
            MoveLabel(lbl_stat3, x_right, y_line + 15 + step_y, txt_stat3, CORNER_RIGHT_UPPER, ANCHOR_RIGHT_UPPER, InpColorLoss);
         }
      }
      else
      {
         ENUM_BASE_CORNER corner = CORNER_LEFT_UPPER;
         ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_UPPER;
         int x_base = InpEdgeGap;
         int y_base = InpVertGap;
         int step = InpFontSize + 4;
         long chart_w = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
         bool stack_upwards = false; 

         switch(InpLocation)
         {
            case LOC_TOP_LEFT: corner = CORNER_LEFT_UPPER; anchor = ANCHOR_LEFT_UPPER; break;
            case LOC_TOP_RIGHT: corner = CORNER_RIGHT_UPPER; anchor = ANCHOR_RIGHT_UPPER; break;
            case LOC_BOTTOM_LEFT: corner = CORNER_LEFT_LOWER; anchor = ANCHOR_LEFT_LOWER; stack_upwards = true; break;
            case LOC_BOTTOM_RIGHT: corner = CORNER_RIGHT_LOWER; anchor = ANCHOR_RIGHT_LOWER; stack_upwards = true; break;
            case LOC_BOTTOM_CENTER: corner = CORNER_LEFT_LOWER; anchor = ANCHOR_LOWER; x_base = (int)chart_w / 2; stack_upwards = true; break;
            case LOC_CENTER_SCREEN: corner = CORNER_LEFT_UPPER; anchor = ANCHOR_CENTER; x_base = (int)chart_w / 2; y_base = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS) / 2; break;
         }

         if(stack_upwards)
         {
            MoveLabel(lbl_stat3, x_base, y_base, txt_stat3, corner, anchor, InpColorLoss);
            MoveLabel(lbl_stat2, x_base, y_base + step, txt_stat2, corner, anchor, InpColorWin);
            MoveLabel(lbl_stat1, x_base, y_base + (step*2), txt_stat1, corner, anchor, color_pnl);
         }
         else
         {
            MoveLabel(lbl_stat1, x_base, y_base, txt_stat1, corner, anchor, color_pnl);
            MoveLabel(lbl_stat2, x_base, y_base + step, txt_stat2, corner, anchor, InpColorWin);
            MoveLabel(lbl_stat3, x_base, y_base + (step*2), txt_stat3, corner, anchor, InpColorLoss);
         }
      }
   }
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
string GetTimeLeft(ENUM_TIMEFRAMES tf)
{
   datetime time_current = TimeCurrent();
   datetime bar_start = iTime(_Symbol, tf, 0);
   int period_seconds = PeriodSeconds(tf);
   if(period_seconds == 0) return "--:--:--";
   datetime bar_end = bar_start + period_seconds;
   long diff = bar_end - time_current;
   if(diff < 0) diff = 0;
   return StringFormat("%02d:%02d:%02d", diff/3600, (diff%3600)/60, (diff%3600)%60);
}

string TimeframeToString(ENUM_TIMEFRAMES tf)
{
   string tf_str = EnumToString(tf);
   return StringSubstr(tf_str, 7);
}

void CreateLabel(string name, color clr)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER); 
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER); 
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpFontSize);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas"); 
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
}

void MoveLabel(string name, int x, int y, string text, ENUM_BASE_CORNER corner, ENUM_ANCHOR_POINT anchor, color clr)
{
   ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

void UpdateHLine(string name, double price, color clr, ENUM_LINE_STYLE style)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, style);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, false); 
      ObjectSetString(0, name, OBJPROP_TOOLTIP, name);
   }
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
}
//+------------------------------------------------------------------+