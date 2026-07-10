//+------------------------------------------------------------------+
//|                                    Donchain Turtle EA v1.mq5    |
//|                      Based on Donchain Signal v5 Indicator      |
//|                         With Trading Panel & Order Management    |
//+------------------------------------------------------------------+
#property copyright "Converted to EA - Professional MT5 Developer"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 7
#property indicator_plots   3

//--- Plot 1: Middle Line
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1
#property indicator_label1  "Middle"

//--- Plot 2: Upper Line
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrGreen
#property indicator_label2  "Upper"

//--- Plot 3: Lower Line
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrRed
#property indicator_label3  "Lower"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

CTrade trade;
CPositionInfo posInfo;
COrderInfo ordInfo;

//--- Inputs ---
input group "===== Strategy Settings ====="
input int      InpRange        = 11;       // Donchian Period
input double   InpSLPercent    = 2.0;      // Stop Loss %
input int      InpSLToBe       = 2;        // Put Stop Loss to BE After TP (0-4)
input string   InpCloseAfter   = "Never";  // Close Trade After Hit (Never, TP1-TP4)

input group "===== Take Profit Settings (%) ====="
input double   InpTP1          = 2.0;      // TP1 %
input double   InpTP2          = 4.0;      // TP2 %
input double   InpTP3          = 6.0;      // TP3 %
input double   InpTP4          = 10.0;     // TP4 %

input group "===== Entry Logic ====="
input bool     InpUseSLParams  = false;    // Use SL as Entry (Limit Order)

input group "===== Display Options ====="
input bool     InpShowUp       = true;     // Show Upper Line
input bool     InpShowMid      = true;     // Show Middle Line
input bool     InpShowLow      = true;     // Show Lower Line
input bool     InpShowEntry    = true;     // Show Entry Arrows
input bool     InpShowSL       = true;     // Show SL Line/Label
input bool     InpShowTP1      = true;     // Show TP1 Line/Label
input bool     InpShowTP2      = true;     // Show TP2 Line/Label
input bool     InpShowTP3      = true;     // Show TP3 Line/Label
input bool     InpShowTP4      = true;     // Show TP4 Line/Label

input group "===== Filters & Cooldown ====="
input int      InpCoolBars     = 5;        // Cooldown Bars

input group "===== Visuals & History ====="
input int      InpMaxTrades    = 10;       // Max Simultaneous Active Trades
input ENUM_LINE_STYLE InpTPStyle = STYLE_DASH; // TP Line Style
input color    InpColSL        = clrRed;   // SL Color
input color    InpColTPDef     = C'192,192,192'; // TP Default (Ghost Gray)
input color    InpColHit       = clrGreen; // TP Hit Color
input color    InpColWait      = clrYellow;// Pending Entry Color
input color    InpColBuyArr    = clrDarkGreen; // Buy Arrow Color
input color    InpColSellArr   = clrDarkRed;   // Sell Arrow Color
input int      InpMaxHistory   = 1000;     // Max Bars to Simulate

input group "===== Trading Settings ====="
input double   InpDefaultLot   = 0.1;      // Default Lot Size
input int      InpMagicNumber  = 123456;   // Magic Number
input int      InpSlippage     = 10;       // Slippage in Points
input double   InpPartialProfit = 50.0;   // Take Partial at Profit ($)

input group "===== Panel Settings ====="
input int      InpPanelX       = 20;       // Panel X Position
input int      InpPanelY       = 30;       // Panel Y Position
input color    InpPanelBG      = C'40,40,40'; // Panel Background Color
input color    InpButtonBuy    = clrGreen; // Buy Button Color
input color    InpButtonSell   = clrRed;   // Sell Button Color

//--- Indicator Buffers
double BufMid[];   // Buffer 0 (Plot 1)
double BufUp[];    // Buffer 1 (Plot 2)
double BufLow[];   // Buffer 2 (Plot 3)

// Calculation Buffers (Hidden)
double BufUps[];   // Buffer 3
double BufDns[];   // Buffer 4
double BufBC[];    // Buffer 5
double BufSC[];    // Buffer 6

// Panel GUI Objects
string panelName = "DT_Panel";
string btnMarketPending = "DT_BtnMP";
string editLot = "DT_EditLot";
string editSL = "DT_EditSL";
string editTP = "DT_EditTP";
string editPendingPrice = "DT_EditPending";
string btnBuy = "DT_BtnBuy";
string btnSell = "DT_BtnSell";
string btnVisualize = "DT_BtnVis";
string btnPartial = "DT_BtnPartial";
string btnBreakEven = "DT_BtnBE";
string lblLot = "DT_LblLot";
string lblSL = "DT_LblSL";
string lblTP = "DT_LblTP";
string lblPendingPrice = "DT_LblPending";
string lblInfo = "DT_LblInfo";

// Panel State
bool isMarketOrder = true;  // true = Market, false = Pending
double currentLot = 0.1;
double currentSL = 0;
double currentTP = 0;
double pendingPrice = 0;
bool visualizeMode = false;
int currentVisualizeType = 0; // 1=Buy, -1=Sell

struct VisualizeLine {
   string obj_entry;
   string obj_sl;
   string obj_tp1;
   string obj_tp2;
   string obj_tp3;
   string obj_tp4;
   string lbl_entry;
   string lbl_sl;
   string lbl_tp1;
   string lbl_tp2;
   string lbl_tp3;
   string lbl_tp4;
   bool active;
   int type; // 1=Buy, -1=Sell
};

VisualizeLine visLine;

struct TradeVisual {
   ulong ticket;
   int dir; 
   double entry_price;
   double sl;
   double tp1; 
   double tp2; 
   double tp3; 
   double tp4;
   bool active;
   bool tp1_hit; 
   bool tp2_hit; 
   bool tp3_hit; 
   bool any_hit;
   string obj_sl;  
   string obj_tp1; 
   string obj_tp2; 
   string obj_tp3; 
   string obj_tp4;
   string lbl_sl;  
   string lbl_tp1; 
   string lbl_tp2; 
   string lbl_tp3; 
   string lbl_tp4; 
   string arrow_entry;
};

TradeVisual tradeVisuals[];
int global_id_counter = 0;

struct TradeState {
   ulong ticket;
   bool tp1_closed;
   bool tp2_closed;
   bool tp3_closed;
   bool be_moved;
};

TradeState tradeStates[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Set up indicator buffers
   SetIndexBuffer(0, BufMid, INDICATOR_DATA);
   SetIndexBuffer(1, BufUp, INDICATOR_DATA);
   SetIndexBuffer(2, BufLow, INDICATOR_DATA);
   
   SetIndexBuffer(3, BufUps, INDICATOR_CALCULATIONS);
   SetIndexBuffer(4, BufDns, INDICATOR_CALCULATIONS);
   SetIndexBuffer(5, BufBC, INDICATOR_CALCULATIONS);
   SetIndexBuffer(6, BufSC, INDICATOR_CALCULATIONS);

   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, InpRange);
   PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, InpRange); 
   PlotIndexSetInteger(2, PLOT_DRAW_BEGIN, InpRange);

   // Apply Individual Visibility for Main Indicator Lines
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, InpShowMid ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(1, PLOT_DRAW_TYPE, InpShowUp  ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(2, PLOT_DRAW_TYPE, InpShowLow ? DRAW_LINE : DRAW_NONE);

   // Set magic number
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   if(!trade.SetTypeFillingBySymbol(_Symbol))
      trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   // Initialize states
   ArrayResize(tradeStates, 0);
   ArrayResize(tradeVisuals, 0);
   visLine.active = false;
   
   currentLot = InpDefaultLot;
   
   // Initialize panel
   CreateTradingPanel();
   
   // Start event timer
   EventSetTimer(1);
   
   Print("Donchian Turtle EA initialized successfully");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteTradingPanel();
   DeleteVisualizeObjects();
   ObjectsDeleteAll(0, "DS_");
   Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Update visualize lines if in market mode
   if(visLine.active && isMarketOrder)
   {
      UpdateVisualizeForMarket();
   }
   
   // Manage open positions
   ManagePositions();
   
   // Update trade visuals
   UpdateTradeVisuals();
   
   // Update panel info
   UpdatePanelInfo();
}

//+------------------------------------------------------------------+
//| OnCalculate for Indicator                                        |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   
   ArraySetAsSeries(BufMid, true);
   ArraySetAsSeries(BufUp, true);
   ArraySetAsSeries(BufLow, true);
   
   ArraySetAsSeries(BufUps, true);
   ArraySetAsSeries(BufDns, true);
   ArraySetAsSeries(BufBC, true);
   ArraySetAsSeries(BufSC, true);

   int limit = rates_total - prev_calculated;
   if(prev_calculated == 0) {
      limit = rates_total - 1;
   }
   
   for(int i = limit; i >= 0; i--)
   {
      if(i >= rates_total - InpRange) continue; 

      int highest_idx = iHighest(NULL, 0, MODE_HIGH, InpRange, i);
      int lowest_idx  = iLowest(NULL, 0, MODE_LOW, InpRange, i);
      
      double h = high[highest_idx];
      double l = low[lowest_idx];
      double m = (h + l) / 2.0;
      
      BufUp[i]    = h; 
      BufLow[i]   = l; 
      BufMid[i]   = m;

      double prev_ups = (i < rates_total - 1) ? BufUps[i+1] : 0.0;
      double prev_dns = (i < rates_total - 1) ? BufDns[i+1] : 0.0;
      
      double ups = (high[i] == h) ? low[i] : prev_ups;
      double dns = (low[i] == l) ? high[i] : prev_dns;
      
      if(ups == 0) ups = low[i];
      if(dns == 0) dns = high[i];
      
      BufUps[i] = ups;
      BufDns[i] = dns;
      
      bool buy_cond = (close[i] > dns && close[i+1] <= dns) && (close[i] < m);
      bool sell_cond = (close[i] < ups && close[i+1] >= ups) && (close[i] > m);
      
      double prev_bc = (i < rates_total - 1) ? BufBC[i+1] : 0.0;
      double prev_sc = (i < rates_total - 1) ? BufSC[i+1] : 0.0;
      
      double bc = 0;
      if(ups == prev_ups && buy_cond) bc = prev_bc + 1;
      else if(dns == high[i]) bc = 0;
      else bc = prev_bc;
      
      double sc = 0;
      if(dns == prev_dns && sell_cond) sc = prev_sc + 1;
      else if(ups == low[i]) sc = 0;
      else sc = prev_sc;
      
      BufBC[i] = bc;
      BufSC[i] = sc;
   }
   
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Timer function                                                    |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Periodic checks
}

//+------------------------------------------------------------------+
//| ChartEvent function                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == btnMarketPending)
      {
         isMarketOrder = !isMarketOrder;
         ObjectSetString(0, btnMarketPending, OBJPROP_TEXT, isMarketOrder ? "MARKET" : "PENDING");
         ObjectSetInteger(0, btnMarketPending, OBJPROP_BGCOLOR, isMarketOrder ? clrBlue : clrOrange);
         ObjectSetInteger(0, btnMarketPending, OBJPROP_STATE, false);
         
         // Show/hide pending price input
         ObjectSetInteger(0, lblPendingPrice, OBJPROP_TIMEFRAMES, isMarketOrder ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);
         ObjectSetInteger(0, editPendingPrice, OBJPROP_TIMEFRAMES, isMarketOrder ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);
         
         ChartRedraw();
      }
      else if(sparam == btnBuy)
      {
         ExecuteTrade(ORDER_TYPE_BUY);
         ObjectSetInteger(0, btnBuy, OBJPROP_STATE, false);
      }
      else if(sparam == btnSell)
      {
         ExecuteTrade(ORDER_TYPE_SELL);
         ObjectSetInteger(0, btnSell, OBJPROP_STATE, false);
      }
      else if(sparam == btnVisualize)
      {
         ToggleVisualize();
         ObjectSetInteger(0, btnVisualize, OBJPROP_STATE, false);
      }
      else if(sparam == btnPartial)
      {
         TakePartialProfit();
         ObjectSetInteger(0, btnPartial, OBJPROP_STATE, false);
      }
      else if(sparam == btnBreakEven)
      {
         MoveToBreakEven();
         ObjectSetInteger(0, btnBreakEven, OBJPROP_STATE, false);
      }
      
      ChartRedraw();
   }
   else if(id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      if(sparam == editLot)
      {
         currentLot = StringToDouble(ObjectGetString(0, editLot, OBJPROP_TEXT));
         if(currentLot < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
            currentLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      }
      else if(sparam == editSL)
      {
         currentSL = StringToDouble(ObjectGetString(0, editSL, OBJPROP_TEXT));
      }
      else if(sparam == editTP)
      {
         currentTP = StringToDouble(ObjectGetString(0, editTP, OBJPROP_TEXT));
      }
      else if(sparam == editPendingPrice)
      {
         pendingPrice = StringToDouble(ObjectGetString(0, editPendingPrice, OBJPROP_TEXT));
      }
   }
}

//+------------------------------------------------------------------+
//| Create Trading Panel                                             |
//+------------------------------------------------------------------+
void CreateTradingPanel()
{
   int x = InpPanelX;
   int y = InpPanelY;
   int width = 220;
   int btnHeight = 30;
   int editWidth = 80;
   int spacing = 5;
   
   // Main Panel Background
   ObjectCreate(0, panelName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, panelName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, panelName, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, panelName, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, panelName, OBJPROP_YSIZE, 420);
   ObjectSetInteger(0, panelName, OBJPROP_BGCOLOR, InpPanelBG);
   ObjectSetInteger(0, panelName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, panelName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, panelName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, panelName, OBJPROP_HIDDEN, true);
   
   int yOffset = y + 10;
   
   // Title Label
   CreateLabel("DT_Title", x + 10, yOffset, "DONCHIAN TURTLE EA", clrWhite, 10, ANCHOR_LEFT_UPPER);
   yOffset += 25;
   
   // Market/Pending Button
   CreateButton(btnMarketPending, x + 10, yOffset, width - 20, btnHeight, "MARKET", clrBlue, clrWhite);
   yOffset += btnHeight + spacing;
   
   // Lot Size
   CreateLabel(lblLot, x + 10, yOffset + 5, "Lot Size:", clrWhite, 9, ANCHOR_LEFT_UPPER);
   CreateEdit(editLot, x + 120, yOffset, editWidth, 25, DoubleToString(currentLot, 2));
   yOffset += 30;
   
   // Stop Loss
   CreateLabel(lblSL, x + 10, yOffset + 5, "SL (pips):", clrWhite, 9, ANCHOR_LEFT_UPPER);
   CreateEdit(editSL, x + 120, yOffset, editWidth, 25, "0");
   yOffset += 30;
   
   // Take Profit
   CreateLabel(lblTP, x + 10, yOffset + 5, "TP (pips):", clrWhite, 9, ANCHOR_LEFT_UPPER);
   CreateEdit(editTP, x + 120, yOffset, editWidth, 25, "0");
   yOffset += 30;
   
   // Pending Price (hidden by default)
   CreateLabel(lblPendingPrice, x + 10, yOffset + 5, "Price:", clrWhite, 9, ANCHOR_LEFT_UPPER);
   CreateEdit(editPendingPrice, x + 120, yOffset, editWidth, 25, "0");
   ObjectSetInteger(0, lblPendingPrice, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
   ObjectSetInteger(0, editPendingPrice, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
   yOffset += 30;
   
   // Buy Button
   CreateButton(btnBuy, x + 10, yOffset, (width - 25) / 2, btnHeight, "BUY", InpButtonBuy, clrWhite);
   
   // Sell Button
   CreateButton(btnSell, x + 10 + (width - 25) / 2 + 5, yOffset, (width - 25) / 2, btnHeight, "SELL", InpButtonSell, clrWhite);
   yOffset += btnHeight + spacing;
   
   // Visualize Button
   CreateButton(btnVisualize, x + 10, yOffset, width - 20, btnHeight, "VISUALIZE BUY", clrDarkBlue, clrWhite);
   yOffset += btnHeight + spacing;
   
   // Partial Button
   CreateButton(btnPartial, x + 10, yOffset, width - 20, btnHeight, "TAKE PARTIAL", clrDarkGoldenrod, clrWhite);
   yOffset += btnHeight + spacing;
   
   // Break Even Button
   CreateButton(btnBreakEven, x + 10, yOffset, width - 20, btnHeight, "SET SL TO BE", clrDarkGray, clrWhite);
   yOffset += btnHeight + spacing;
   
   // Info Label
   CreateLabel(lblInfo, x + 10, yOffset, "Info: Ready", clrLightGray, 8, ANCHOR_LEFT_UPPER);
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Delete Trading Panel                                             |
//+------------------------------------------------------------------+
void DeleteTradingPanel()
{
   ObjectDelete(0, panelName);
   ObjectDelete(0, "DT_Title");
   ObjectDelete(0, btnMarketPending);
   ObjectDelete(0, editLot);
   ObjectDelete(0, editSL);
   ObjectDelete(0, editTP);
   ObjectDelete(0, editPendingPrice);
   ObjectDelete(0, btnBuy);
   ObjectDelete(0, btnSell);
   ObjectDelete(0, btnVisualize);
   ObjectDelete(0, btnPartial);
   ObjectDelete(0, btnBreakEven);
   ObjectDelete(0, lblLot);
   ObjectDelete(0, lblSL);
   ObjectDelete(0, lblTP);
   ObjectDelete(0, lblPendingPrice);
   ObjectDelete(0, lblInfo);
}

//+------------------------------------------------------------------+
//| Create Button                                                     |
//+------------------------------------------------------------------+
void CreateButton(string name, int x, int y, int width, int height, string text, color bgColor, color txtColor)
{
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, txtColor);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| Create Label                                                      |
//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string text, color clr, int fontSize, ENUM_ANCHOR_POINT anchor)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| Create Edit Box                                                  |
//+------------------------------------------------------------------+
void CreateEdit(string name, int x, int y, int width, int height, string text)
{
   ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrBlack);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrGray);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, name, OBJPROP_ALIGN, ALIGN_CENTER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| Update Panel Info                                                |
//+------------------------------------------------------------------+
void UpdatePanelInfo()
{
   int totalPos = 0;
   double totalProfit = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber)
         {
            totalPos++;
            totalProfit += posInfo.Profit() + posInfo.Swap() + posInfo.Commission();
         }
      }
   }
   
   string info = StringFormat("Positions: %d | P/L: $%.2f", totalPos, totalProfit);
   ObjectSetString(0, lblInfo, OBJPROP_TEXT, info);
}

//+------------------------------------------------------------------+
//| Toggle Visualize                                                 |
//+------------------------------------------------------------------+
void ToggleVisualize()
{
   if(!visLine.active)
   {
      // Toggle between Buy and Sell visualization
      if(currentVisualizeType == 0 || currentVisualizeType == -1)
      {
         currentVisualizeType = 1; // Buy
         VisualizeOrder(1);
         ObjectSetString(0, btnVisualize, OBJPROP_TEXT, "VISUALIZE SELL");
         ObjectSetInteger(0, btnVisualize, OBJPROP_BGCOLOR, clrDarkGreen);
      }
      else
      {
         currentVisualizeType = -1; // Sell
         VisualizeOrder(-1);
         ObjectSetString(0, btnVisualize, OBJPROP_TEXT, "HIDE VISUALIZE");
         ObjectSetInteger(0, btnVisualize, OBJPROP_BGCOLOR, clrDarkRed);
      }
   }
   else
   {
      // Hide visualization
      DeleteVisualizeObjects();
      currentVisualizeType = 0;
      ObjectSetString(0, btnVisualize, OBJPROP_TEXT, "VISUALIZE BUY");
      ObjectSetInteger(0, btnVisualize, OBJPROP_BGCOLOR, clrDarkBlue);
   }
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Execute Trade                                                     |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE orderType)
{
   double price = 0;
   double sl = 0;
   double tp = 0;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   int dir = (orderType == ORDER_TYPE_BUY || orderType == ORDER_TYPE_BUY_LIMIT) ? 1 : -1;
   
   // Calculate SL and TP based on strategy
   if(isMarketOrder)
   {
      // Market Order
      if(dir == 1)
      {
         price = ask;
         
         // Use manual SL if provided, otherwise use strategy %
         if(currentSL > 0)
            sl = price - currentSL * point * 10; // Convert pips to price
         else
            sl = price - (price * InpSLPercent / 100);
            
         // Calculate TP levels (we'll use TP1 as main TP for traditional orders)
         if(currentTP > 0)
            tp = price + currentTP * point * 10;
         else
            tp = price + (price * InpTP1 / 100);
      }
      else
      {
         price = bid;
         
         if(currentSL > 0)
            sl = price + currentSL * point * 10;
         else
            sl = price + (price * InpSLPercent / 100);
            
         if(currentTP > 0)
            tp = price - currentTP * point * 10;
         else
            tp = price - (price * InpTP1 / 100);
      }
      
      sl = NormalizeDouble(sl, digits);
      tp = NormalizeDouble(tp, digits);
      
      bool result = false;
      
      if(dir == 1)
         result = trade.Buy(currentLot, _Symbol, 0, sl, tp, "Donchian Turtle Buy");
      else
         result = trade.Sell(currentLot, _Symbol, 0, sl, tp, "Donchian Turtle Sell");
         
      if(result)
      {
         ulong ticket = trade.ResultOrder();
         Print("Market order executed successfully. Ticket: ", ticket);
         
         // Create visual trade tracking
         CreateTradeVisual(ticket, dir, price, sl, tp);
         
         AddTradeState(ticket);
         PlaySound("alert.wav");
         
         // Clear visualization after placing order
         DeleteVisualizeObjects();
         currentVisualizeType = 0;
         ObjectSetString(0, btnVisualize, OBJPROP_TEXT, "VISUALIZE BUY");
         ObjectSetInteger(0, btnVisualize, OBJPROP_BGCOLOR, clrDarkBlue);
      }
      else
      {
         Print("Market order failed. Error: ", GetLastError());
      }
   }
   else
   {
      // Pending Order - use specified price
      if(pendingPrice <= 0)
      {
         Print("Please specify a pending order price");
         return;
      }
      
      ENUM_ORDER_TYPE pendingType;
      price = NormalizeDouble(pendingPrice, digits);
      
      if(dir == 1)
      {
         // Buy Limit
         pendingType = ORDER_TYPE_BUY_LIMIT;
         
         if(currentSL > 0)
            sl = price - currentSL * point * 10;
         else
            sl = price - (price * InpSLPercent / 100);
            
         if(currentTP > 0)
            tp = price + currentTP * point * 10;
         else
            tp = price + (price * InpTP1 / 100);
      }
      else
      {
         // Sell Limit
         pendingType = ORDER_TYPE_SELL_LIMIT;
         
         if(currentSL > 0)
            sl = price + currentSL * point * 10;
         else
            sl = price + (price * InpSLPercent / 100);
            
         if(currentTP > 0)
            tp = price - currentTP * point * 10;
         else
            tp = price - (price * InpTP1 / 100);
      }
      
      sl = NormalizeDouble(sl, digits);
      tp = NormalizeDouble(tp, digits);
      
      bool result = trade.OrderOpen(_Symbol, pendingType, currentLot, 0, price, sl, tp, 
                               ORDER_TIME_GTC, 0, "Donchian Turtle Pending");
                               
      if(result)
      {
         Print("Pending order placed successfully at ", price);
         PlaySound("alert.wav");
         
         // Clear visualization
         DeleteVisualizeObjects();
         currentVisualizeType = 0;
         ObjectSetString(0, btnVisualize, OBJPROP_TEXT, "VISUALIZE BUY");
         ObjectSetInteger(0, btnVisualize, OBJPROP_BGCOLOR, clrDarkBlue);
      }
      else
      {
         Print("Pending order failed. Error: ", GetLastError());
      }
   }
}

//+------------------------------------------------------------------+
//| Visualize Order Before Placing                                   |
//+------------------------------------------------------------------+
void VisualizeOrder(int type)
{
   DeleteVisualizeObjects();
   
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   datetime currentTime = TimeCurrent();
   datetime futureTime = currentTime + PeriodSeconds() * 50;
   
   double entryPrice;
   
   // Determine entry price based on mode
   if(isMarketOrder)
   {
      // Market mode - use current price
      entryPrice = (type == 1) ? ask : bid;
   }
   else
   {
      // Pending mode - use specified price
      if(pendingPrice > 0)
         entryPrice = pendingPrice;
      else
      {
         Print("Please specify pending order price first");
         return;
      }
   }
   
   double sl, tp1, tp2, tp3, tp4;
   
   // Calculate levels based on direction
   if(type == 1) // Buy
   {
      if(currentSL > 0)
         sl = entryPrice - currentSL * SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
      else
         sl = entryPrice - (entryPrice * InpSLPercent / 100);
         
      tp1 = entryPrice + (entryPrice * InpTP1 / 100);
      tp2 = entryPrice + (entryPrice * InpTP2 / 100);
      tp3 = entryPrice + (entryPrice * InpTP3 / 100);
      tp4 = entryPrice + (entryPrice * InpTP4 / 100);
   }
   else // Sell
   {
      if(currentSL > 0)
         sl = entryPrice + currentSL * SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
      else
         sl = entryPrice + (entryPrice * InpSLPercent / 100);
         
      tp1 = entryPrice - (entryPrice * InpTP1 / 100);
      tp2 = entryPrice - (entryPrice * InpTP2 / 100);
      tp3 = entryPrice - (entryPrice * InpTP3 / 100);
      tp4 = entryPrice - (entryPrice * InpTP4 / 100);
   }
   
   // Create visualization lines
   visLine.obj_entry = "VIS_Entry";
   visLine.obj_sl = "VIS_SL";
   visLine.obj_tp1 = "VIS_TP1";
   visLine.obj_tp2 = "VIS_TP2";
   visLine.obj_tp3 = "VIS_TP3";
   visLine.obj_tp4 = "VIS_TP4";
   
   visLine.lbl_entry = "VIS_LBL_Entry";
   visLine.lbl_sl = "VIS_LBL_SL";
   visLine.lbl_tp1 = "VIS_LBL_TP1";
   visLine.lbl_tp2 = "VIS_LBL_TP2";
   visLine.lbl_tp3 = "VIS_LBL_TP3";
   visLine.lbl_tp4 = "VIS_LBL_TP4";
   
   visLine.type = type;
   
   CreateTrendLine(visLine.obj_entry, currentTime, entryPrice, futureTime, entryPrice, type==1?clrBlue:clrOrange, STYLE_SOLID, 2);
   CreateTrendLine(visLine.obj_sl, currentTime, sl, futureTime, sl, InpColSL, STYLE_DASH, 1);
   
   if(InpShowTP1) CreateTrendLine(visLine.obj_tp1, currentTime, tp1, futureTime, tp1, InpColTPDef, InpTPStyle, 1);
   if(InpShowTP2) CreateTrendLine(visLine.obj_tp2, currentTime, tp2, futureTime, tp2, InpColTPDef, InpTPStyle, 1);
   if(InpShowTP3) CreateTrendLine(visLine.obj_tp3, currentTime, tp3, futureTime, tp3, InpColTPDef, InpTPStyle, 1);
   if(InpShowTP4) CreateTrendLine(visLine.obj_tp4, currentTime, tp4, futureTime, tp4, InpColTPDef, InpTPStyle, 1);
   
   // Create labels
   ObjectCreate(0, visLine.lbl_entry, OBJ_TEXT, 0, currentTime, entryPrice);
   ObjectSetString(0, visLine.lbl_entry, OBJPROP_TEXT, "Entry: " + DoubleToString(entryPrice, digits));
   ObjectSetInteger(0, visLine.lbl_entry, OBJPROP_COLOR, type==1?clrBlue:clrOrange);
   ObjectSetInteger(0, visLine.lbl_entry, OBJPROP_FONTSIZE, 8);
   
   ObjectCreate(0, visLine.lbl_sl, OBJ_TEXT, 0, currentTime, sl);
   ObjectSetString(0, visLine.lbl_sl, OBJPROP_TEXT, "SL: " + DoubleToString(sl, digits));
   ObjectSetInteger(0, visLine.lbl_sl, OBJPROP_COLOR, InpColSL);
   ObjectSetInteger(0, visLine.lbl_sl, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, visLine.lbl_sl, OBJPROP_ANCHOR, type==1?ANCHOR_UPPER:ANCHOR_LOWER);
   
   if(InpShowTP1)
   {
      ObjectCreate(0, visLine.lbl_tp1, OBJ_TEXT, 0, currentTime, tp1);
      ObjectSetString(0, visLine.lbl_tp1, OBJPROP_TEXT, "TP1: " + DoubleToString(tp1, digits));
      ObjectSetInteger(0, visLine.lbl_tp1, OBJPROP_COLOR, InpColTPDef);
      ObjectSetInteger(0, visLine.lbl_tp1, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, visLine.lbl_tp1, OBJPROP_ANCHOR, type==1?ANCHOR_LOWER:ANCHOR_UPPER);
   }
   
   if(InpShowTP2)
   {
      ObjectCreate(0, visLine.lbl_tp2, OBJ_TEXT, 0, currentTime, tp2);
      ObjectSetString(0, visLine.lbl_tp2, OBJPROP_TEXT, "TP2: " + DoubleToString(tp2, digits));
      ObjectSetInteger(0, visLine.lbl_tp2, OBJPROP_COLOR, InpColTPDef);
      ObjectSetInteger(0, visLine.lbl_tp2, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, visLine.lbl_tp2, OBJPROP_ANCHOR, type==1?ANCHOR_LOWER:ANCHOR_UPPER);
   }
   
   if(InpShowTP3)
   {
      ObjectCreate(0, visLine.lbl_tp3, OBJ_TEXT, 0, currentTime, tp3);
      ObjectSetString(0, visLine.lbl_tp3, OBJPROP_TEXT, "TP3: " + DoubleToString(tp3, digits));
      ObjectSetInteger(0, visLine.lbl_tp3, OBJPROP_COLOR, InpColTPDef);
      ObjectSetInteger(0, visLine.lbl_tp3, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, visLine.lbl_tp3, OBJPROP_ANCHOR, type==1?ANCHOR_LOWER:ANCHOR_UPPER);
   }
   
   if(InpShowTP4)
   {
      ObjectCreate(0, visLine.lbl_tp4, OBJ_TEXT, 0, currentTime, tp4);
      ObjectSetString(0, visLine.lbl_tp4, OBJPROP_TEXT, "TP4: " + DoubleToString(tp4, digits));
      ObjectSetInteger(0, visLine.lbl_tp4, OBJPROP_COLOR, InpColTPDef);
      ObjectSetInteger(0, visLine.lbl_tp4, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, visLine.lbl_tp4, OBJPROP_ANCHOR, type==1?ANCHOR_LOWER:ANCHOR_UPPER);
   }
   
   visLine.active = true;
   
   Print("Order visualization created for ", type==1?"BUY":"SELL");
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Update Visualize Lines for Market Mode                          |
//+------------------------------------------------------------------+
void UpdateVisualizeForMarket()
{
   if(!visLine.active) return;
   
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   datetime currentTime = TimeCurrent();
   datetime futureTime = currentTime + PeriodSeconds() * 50;
   
   double entryPrice = (visLine.type == 1) ? ask : bid;
   double sl, tp1, tp2, tp3, tp4;
   
   // Recalculate levels
   if(visLine.type == 1) // Buy
   {
      if(currentSL > 0)
         sl = entryPrice - currentSL * SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
      else
         sl = entryPrice - (entryPrice * InpSLPercent / 100);
         
      tp1 = entryPrice + (entryPrice * InpTP1 / 100);
      tp2 = entryPrice + (entryPrice * InpTP2 / 100);
      tp3 = entryPrice + (entryPrice * InpTP3 / 100);
      tp4 = entryPrice + (entryPrice * InpTP4 / 100);
   }
   else // Sell
   {
      if(currentSL > 0)
         sl = entryPrice + currentSL * SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
      else
         sl = entryPrice + (entryPrice * InpSLPercent / 100);
         
      tp1 = entryPrice - (entryPrice * InpTP1 / 100);
      tp2 = entryPrice - (entryPrice * InpTP2 / 100);
      tp3 = entryPrice - (entryPrice * InpTP3 / 100);
      tp4 = entryPrice - (entryPrice * InpTP4 / 100);
   }
   
   // Update line prices
   ObjectMove(0, visLine.obj_entry, 0, currentTime, entryPrice);
   ObjectMove(0, visLine.obj_entry, 1, futureTime, entryPrice);
   
   ObjectMove(0, visLine.obj_sl, 0, currentTime, sl);
   ObjectMove(0, visLine.obj_sl, 1, futureTime, sl);
   
   if(InpShowTP1)
   {
      ObjectMove(0, visLine.obj_tp1, 0, currentTime, tp1);
      ObjectMove(0, visLine.obj_tp1, 1, futureTime, tp1);
   }
   
   if(InpShowTP2)
   {
      ObjectMove(0, visLine.obj_tp2, 0, currentTime, tp2);
      ObjectMove(0, visLine.obj_tp2, 1, futureTime, tp2);
   }
   
   if(InpShowTP3)
   {
      ObjectMove(0, visLine.obj_tp3, 0, currentTime, tp3);
      ObjectMove(0, visLine.obj_tp3, 1, futureTime, tp3);
   }
   
   if(InpShowTP4)
   {
      ObjectMove(0, visLine.obj_tp4, 0, currentTime, tp4);
      ObjectMove(0, visLine.obj_tp4, 1, futureTime, tp4);
   }
   
   // Update labels
   ObjectMove(0, visLine.lbl_entry, 0, currentTime, entryPrice);
   ObjectSetString(0, visLine.lbl_entry, OBJPROP_TEXT, "Entry: " + DoubleToString(entryPrice, digits));
   
   ObjectMove(0, visLine.lbl_sl, 0, currentTime, sl);
   ObjectSetString(0, visLine.lbl_sl, OBJPROP_TEXT, "SL: " + DoubleToString(sl, digits));
   
   if(InpShowTP1)
   {
      ObjectMove(0, visLine.lbl_tp1, 0, currentTime, tp1);
      ObjectSetString(0, visLine.lbl_tp1, OBJPROP_TEXT, "TP1: " + DoubleToString(tp1, digits));
   }
   
   if(InpShowTP2)
   {
      ObjectMove(0, visLine.lbl_tp2, 0, currentTime, tp2);
      ObjectSetString(0, visLine.lbl_tp2, OBJPROP_TEXT, "TP2: " + DoubleToString(tp2, digits));
   }
   
   if(InpShowTP3)
   {
      ObjectMove(0, visLine.lbl_tp3, 0, currentTime, tp3);
      ObjectSetString(0, visLine.lbl_tp3, OBJPROP_TEXT, "TP3: " + DoubleToString(tp3, digits));
   }
   
   if(InpShowTP4)
   {
      ObjectMove(0, visLine.lbl_tp4, 0, currentTime, tp4);
      ObjectSetString(0, visLine.lbl_tp4, OBJPROP_TEXT, "TP4: " + DoubleToString(tp4, digits));
   }
}

//+------------------------------------------------------------------+
//| Delete Visualize Objects                                         |
//+------------------------------------------------------------------+
void DeleteVisualizeObjects()
{
   if(visLine.active)
   {
      ObjectDelete(0, visLine.obj_entry);
      ObjectDelete(0, visLine.obj_sl);
      ObjectDelete(0, visLine.obj_tp1);
      ObjectDelete(0, visLine.obj_tp2);
      ObjectDelete(0, visLine.obj_tp3);
      ObjectDelete(0, visLine.obj_tp4);
      ObjectDelete(0, visLine.lbl_entry);
      ObjectDelete(0, visLine.lbl_sl);
      ObjectDelete(0, visLine.lbl_tp1);
      ObjectDelete(0, visLine.lbl_tp2);
      ObjectDelete(0, visLine.lbl_tp3);
      ObjectDelete(0, visLine.lbl_tp4);
      visLine.active = false;
   }
}

//+------------------------------------------------------------------+
//| Create Trend Line                                                |
//+------------------------------------------------------------------+
void CreateTrendLine(string name, datetime t1, double p1, datetime t2, double p2, color clr, ENUM_LINE_STYLE style, int width)
{
   ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
}

//+------------------------------------------------------------------+
//| Create Trade Visual (like indicator)                            |
//+------------------------------------------------------------------+
void CreateTradeVisual(ulong ticket, int dir, double entry, double sl, double initial_tp)
{
   global_id_counter++;
   string pfx = "DS_" + IntegerToString(global_id_counter);
   
   int size = ArraySize(tradeVisuals);
   ArrayResize(tradeVisuals, size + 1);
   
   TradeVisual tv;
   tv.ticket = ticket;
   tv.dir = dir;
   tv.entry_price = entry;
   tv.sl = sl;
   
   // Calculate all TP levels
   if(dir == 1)
   {
      tv.tp1 = entry + (entry * InpTP1 / 100);
      tv.tp2 = entry + (entry * InpTP2 / 100);
      tv.tp3 = entry + (entry * InpTP3 / 100);
      tv.tp4 = entry + (entry * InpTP4 / 100);
   }
   else
   {
      tv.tp1 = entry - (entry * InpTP1 / 100);
      tv.tp2 = entry - (entry * InpTP2 / 100);
      tv.tp3 = entry - (entry * InpTP3 / 100);
      tv.tp4 = entry - (entry * InpTP4 / 100);
   }
   
   tv.active = true;
   tv.tp1_hit = false;
   tv.tp2_hit = false;
   tv.tp3_hit = false;
   tv.any_hit = false;
   
   datetime currentTime = TimeCurrent();
   datetime futureTime = currentTime + PeriodSeconds() * 50;
   
   // Create objects
   tv.obj_sl = pfx + "_sl";
   tv.obj_tp1 = pfx + "_t1";
   tv.obj_tp2 = pfx + "_t2";
   tv.obj_tp3 = pfx + "_t3";
   tv.obj_tp4 = pfx + "_t4";
   
   tv.lbl_sl = pfx + "_lsl";
   tv.lbl_tp1 = pfx + "_lt1";
   tv.lbl_tp2 = pfx + "_lt2";
   tv.lbl_tp3 = pfx + "_lt3";
   tv.lbl_tp4 = pfx + "_lt4";
   
   tv.arrow_entry = pfx + "_arr";
   
   if(InpShowSL)
   {
      CreateTrendLine(tv.obj_sl, currentTime, sl, futureTime, sl, InpColSL, STYLE_DASH, 1);
      
      ObjectCreate(0, tv.lbl_sl, OBJ_TEXT, 0, currentTime, sl);
      ObjectSetString(0, tv.lbl_sl, OBJPROP_TEXT, "SL");
      ObjectSetInteger(0, tv.lbl_sl, OBJPROP_COLOR, InpColSL);
      ObjectSetInteger(0, tv.lbl_sl, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, tv.lbl_sl, OBJPROP_ANCHOR, dir==1?ANCHOR_UPPER:ANCHOR_LOWER);
   }
   
   if(InpShowTP1)
   {
      CreateTrendLine(tv.obj_tp1, currentTime, tv.tp1, futureTime, tv.tp1, InpColTPDef, InpTPStyle, 1);
      
      ObjectCreate(0, tv.lbl_tp1, OBJ_TEXT, 0, currentTime, tv.tp1);
      ObjectSetString(0, tv.lbl_tp1, OBJPROP_TEXT, "TP1");
      ObjectSetInteger(0, tv.lbl_tp1, OBJPROP_COLOR, InpColTPDef);
      ObjectSetInteger(0, tv.lbl_tp1, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, tv.lbl_tp1, OBJPROP_ANCHOR, dir==1?ANCHOR_LOWER:ANCHOR_UPPER);
   }
   
   if(InpShowTP2)
   {
      CreateTrendLine(tv.obj_tp2, currentTime, tv.tp2, futureTime, tv.tp2, InpColTPDef, InpTPStyle, 1);
      
      ObjectCreate(0, tv.lbl_tp2, OBJ_TEXT, 0, currentTime, tv.tp2);
      ObjectSetString(0, tv.lbl_tp2, OBJPROP_TEXT, "TP2");
      ObjectSetInteger(0, tv.lbl_tp2, OBJPROP_COLOR, InpColTPDef);
      ObjectSetInteger(0, tv.lbl_tp2, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, tv.lbl_tp2, OBJPROP_ANCHOR, dir==1?ANCHOR_LOWER:ANCHOR_UPPER);
   }
   
   if(InpShowTP3)
   {
      CreateTrendLine(tv.obj_tp3, currentTime, tv.tp3, futureTime, tv.tp3, InpColTPDef, InpTPStyle, 1);
      
      ObjectCreate(0, tv.lbl_tp3, OBJ_TEXT, 0, currentTime, tv.tp3);
      ObjectSetString(0, tv.lbl_tp3, OBJPROP_TEXT, "TP3");
      ObjectSetInteger(0, tv.lbl_tp3, OBJPROP_COLOR, InpColTPDef);
      ObjectSetInteger(0, tv.lbl_tp3, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, tv.lbl_tp3, OBJPROP_ANCHOR, dir==1?ANCHOR_LOWER:ANCHOR_UPPER);
   }
   
   if(InpShowTP4)
   {
      CreateTrendLine(tv.obj_tp4, currentTime, tv.tp4, futureTime, tv.tp4, InpColTPDef, InpTPStyle, 1);
      
      ObjectCreate(0, tv.lbl_tp4, OBJ_TEXT, 0, currentTime, tv.tp4);
      ObjectSetString(0, tv.lbl_tp4, OBJPROP_TEXT, "TP4");
      ObjectSetInteger(0, tv.lbl_tp4, OBJPROP_COLOR, InpColTPDef);
      ObjectSetInteger(0, tv.lbl_tp4, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, tv.lbl_tp4, OBJPROP_ANCHOR, dir==1?ANCHOR_LOWER:ANCHOR_UPPER);
   }
   
   // Create entry arrow
   if(InpShowEntry)
   {
      ENUM_OBJECT arrType = (dir == 1) ? OBJ_ARROW_BUY : OBJ_ARROW_SELL;
      double arrPrice = entry;
      
      ObjectCreate(0, tv.arrow_entry, arrType, 0, currentTime, arrPrice);
      ObjectSetInteger(0, tv.arrow_entry, OBJPROP_COLOR, dir==1?InpColBuyArr:InpColSellArr);
      ObjectSetInteger(0, tv.arrow_entry, OBJPROP_WIDTH, 2);
   }
   
   tradeVisuals[size] = tv;
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Update Trade Visuals                                             |
//+------------------------------------------------------------------+
void UpdateTradeVisuals()
{
   datetime currentTime = TimeCurrent();
   datetime futureTime = currentTime + PeriodSeconds() * 50;
   
   for(int i = ArraySize(tradeVisuals) - 1; i >= 0; i--)
   {
      if(!tradeVisuals[i].active) continue;
      
      // Check if position still exists
      bool posExists = false;
      for(int j = 0; j < PositionsTotal(); j++)
      {
         if(posInfo.SelectByIndex(j))
         {
            if(posInfo.Ticket() == tradeVisuals[i].ticket)
            {
               posExists = true;
               
               // Update line positions to extend to current time
               if(ObjectFind(0, tradeVisuals[i].obj_sl) >= 0)
                  ObjectMove(0, tradeVisuals[i].obj_sl, 1, futureTime, tradeVisuals[i].sl);
                  
               if(ObjectFind(0, tradeVisuals[i].obj_tp1) >= 0)
                  ObjectMove(0, tradeVisuals[i].obj_tp1, 1, futureTime, tradeVisuals[i].tp1);
                  
               if(ObjectFind(0, tradeVisuals[i].obj_tp2) >= 0)
                  ObjectMove(0, tradeVisuals[i].obj_tp2, 1, futureTime, tradeVisuals[i].tp2);
                  
               if(ObjectFind(0, tradeVisuals[i].obj_tp3) >= 0)
                  ObjectMove(0, tradeVisuals[i].obj_tp3, 1, futureTime, tradeVisuals[i].tp3);
                  
               if(ObjectFind(0, tradeVisuals[i].obj_tp4) >= 0)
                  ObjectMove(0, tradeVisuals[i].obj_tp4, 1, futureTime, tradeVisuals[i].tp4);
               
               // Check TP hits
               double currentPrice = posInfo.PriceCurrent();
               
               if(tradeVisuals[i].dir == 1) // Buy
               {
                  if(currentPrice >= tradeVisuals[i].tp1 && !tradeVisuals[i].tp1_hit)
                  {
                     tradeVisuals[i].tp1_hit = true;
                     tradeVisuals[i].any_hit = true;
                     MarkTPHit(tradeVisuals[i].obj_tp1, tradeVisuals[i].lbl_tp1, "TP1", tradeVisuals[i].tp1);
                  }
                  if(currentPrice >= tradeVisuals[i].tp2 && !tradeVisuals[i].tp2_hit)
                  {
                     tradeVisuals[i].tp2_hit = true;
                     MarkTPHit(tradeVisuals[i].obj_tp2, tradeVisuals[i].lbl_tp2, "TP2", tradeVisuals[i].tp2);
                  }
                  if(currentPrice >= tradeVisuals[i].tp3 && !tradeVisuals[i].tp3_hit)
                  {
                     tradeVisuals[i].tp3_hit = true;
                     MarkTPHit(tradeVisuals[i].obj_tp3, tradeVisuals[i].lbl_tp3, "TP3", tradeVisuals[i].tp3);
                  }
               }
               else // Sell
               {
                  if(currentPrice <= tradeVisuals[i].tp1 && !tradeVisuals[i].tp1_hit)
                  {
                     tradeVisuals[i].tp1_hit = true;
                     tradeVisuals[i].any_hit = true;
                     MarkTPHit(tradeVisuals[i].obj_tp1, tradeVisuals[i].lbl_tp1, "TP1", tradeVisuals[i].tp1);
                  }
                  if(currentPrice <= tradeVisuals[i].tp2 && !tradeVisuals[i].tp2_hit)
                  {
                     tradeVisuals[i].tp2_hit = true;
                     MarkTPHit(tradeVisuals[i].obj_tp2, tradeVisuals[i].lbl_tp2, "TP2", tradeVisuals[i].tp2);
                  }
                  if(currentPrice <= tradeVisuals[i].tp3 && !tradeVisuals[i].tp3_hit)
                  {
                     tradeVisuals[i].tp3_hit = true;
                     MarkTPHit(tradeVisuals[i].obj_tp3, tradeVisuals[i].lbl_tp3, "TP3", tradeVisuals[i].tp3);
                  }
               }
               
               break;
            }
         }
      }
      
      if(!posExists)
      {
         tradeVisuals[i].active = false;
      }
   }
}

//+------------------------------------------------------------------+
//| Mark TP Hit                                                       |
//+------------------------------------------------------------------+
void MarkTPHit(string objLine, string objLabel, string text, double price)
{
   if(ObjectFind(0, objLine) >= 0)
   {
      ObjectSetInteger(0, objLine, OBJPROP_COLOR, InpColHit);
      ObjectSetInteger(0, objLine, OBJPROP_STYLE, InpTPStyle);
   }
   
   if(ObjectFind(0, objLabel) >= 0)
   {
      ObjectSetInteger(0, objLabel, OBJPROP_COLOR, InpColHit);
      ObjectSetString(0, objLabel, OBJPROP_TEXT, text + ": " + DoubleToString(price, _Digits));
   }
}

//+------------------------------------------------------------------+
//| Take Partial Profit                                              |
//+------------------------------------------------------------------+
void TakePartialProfit()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber)
         {
            double profit = posInfo.Profit() + posInfo.Swap() + posInfo.Commission();
            
            // Check if profit target reached
            if(profit >= InpPartialProfit)
            {
               double currentVol = posInfo.Volume();
               double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
               double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
               
               // Close 50% of position
               double closeVol = MathFloor((currentVol * 0.5) / volStep) * volStep;
               
               if(closeVol >= minVol && (currentVol - closeVol) >= minVol)
               {
                  ulong ticket = posInfo.Ticket();
                  if(trade.PositionClosePartial(ticket, closeVol))
                  {
                     Print("Partial close executed on ticket ", ticket, ". Closed volume: ", closeVol);
                     PlaySound("alert.wav");
                  }
                  else
                  {
                     Print("Partial close failed. Error: ", GetLastError());
                  }
               }
               else
               {
                  Print("Cannot partial close - volume constraints");
               }
            }
            else
            {
               Print("Profit $", profit, " has not reached target $", InpPartialProfit);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Move Stop Loss to Break Even                                     |
//+------------------------------------------------------------------+
void MoveToBreakEven()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber)
         {
            double entryPrice = posInfo.PriceOpen();
            double currentSL = posInfo.StopLoss();
            ulong ticket = posInfo.Ticket();
            
            // Check if already at BE
            if(MathAbs(currentSL - entryPrice) < SymbolInfoDouble(_Symbol, SYMBOL_POINT))
            {
               Print("Position ", ticket, " already at break even");
               continue;
            }
            
            // Move to BE
            if(trade.PositionModify(ticket, entryPrice, posInfo.TakeProfit()))
            {
               Print("Stop loss moved to break even for ticket ", ticket);
               
               // Update state
               for(int j = 0; j < ArraySize(tradeStates); j++)
               {
                  if(tradeStates[j].ticket == ticket)
                  {
                     tradeStates[j].be_moved = true;
                     break;
                  }
               }
               
               // Update visual
               for(int k = 0; k < ArraySize(tradeVisuals); k++)
               {
                  if(tradeVisuals[k].ticket == ticket)
                  {
                     tradeVisuals[k].sl = entryPrice;
                     
                     // Update SL line
                     if(ObjectFind(0, tradeVisuals[k].obj_sl) >= 0)
                     {
                        ObjectMove(0, tradeVisuals[k].obj_sl, 0, 0, entryPrice);
                        ObjectMove(0, tradeVisuals[k].obj_sl, 1, 0, entryPrice);
                        ObjectSetInteger(0, tradeVisuals[k].obj_sl, OBJPROP_COLOR, clrGray);
                     }
                     
                     if(ObjectFind(0, tradeVisuals[k].lbl_sl) >= 0)
                     {
                        ObjectMove(0, tradeVisuals[k].lbl_sl, 0, 0, entryPrice);
                        ObjectSetString(0, tradeVisuals[k].lbl_sl, OBJPROP_TEXT, "SL: BE");
                        ObjectSetInteger(0, tradeVisuals[k].lbl_sl, OBJPROP_COLOR, clrGray);
                     }
                     break;
                  }
               }
               
               PlaySound("alert.wav");
            }
            else
            {
               Print("Failed to move SL to BE. Error: ", GetLastError());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage Open Positions                                            |
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber)
         {
            ulong ticket = posInfo.Ticket();
            double profit = posInfo.Profit() + posInfo.Swap() + posInfo.Commission();
            double entryPrice = posInfo.PriceOpen();
            double currentPrice = posInfo.PriceCurrent();
            
            // Find trade state
            int stateIdx = FindTradeState(ticket);
            if(stateIdx == -1) continue;
            
            // Calculate TP levels
            double tp1, tp2, tp3, tp4;
            
            if(posInfo.Type() == POSITION_TYPE_BUY)
            {
               tp1 = entryPrice + (entryPrice * InpTP1 / 100);
               tp2 = entryPrice + (entryPrice * InpTP2 / 100);
               tp3 = entryPrice + (entryPrice * InpTP3 / 100);
               tp4 = entryPrice + (entryPrice * InpTP4 / 100);
               
               // Check TP levels
               if(currentPrice >= tp1 && !tradeStates[stateIdx].tp1_closed)
               {
                  // TP1 hit - move to BE if configured
                  if(InpSLToBe == 1 && !tradeStates[stateIdx].be_moved)
                  {
                     trade.PositionModify(ticket, entryPrice, posInfo.TakeProfit());
                     tradeStates[stateIdx].be_moved = true;
                     Print("TP1 hit - SL moved to BE for ticket ", ticket);
                  }
                  tradeStates[stateIdx].tp1_closed = true;
               }
               
               if(currentPrice >= tp2 && !tradeStates[stateIdx].tp2_closed)
               {
                  if(InpSLToBe == 2 && !tradeStates[stateIdx].be_moved)
                  {
                     trade.PositionModify(ticket, entryPrice, posInfo.TakeProfit());
                     tradeStates[stateIdx].be_moved = true;
                     Print("TP2 hit - SL moved to BE for ticket ", ticket);
                  }
                  tradeStates[stateIdx].tp2_closed = true;
               }
               
               if(currentPrice >= tp3 && !tradeStates[stateIdx].tp3_closed)
               {
                  if(InpSLToBe == 3 && !tradeStates[stateIdx].be_moved)
                  {
                     trade.PositionModify(ticket, entryPrice, posInfo.TakeProfit());
                     tradeStates[stateIdx].be_moved = true;
                     Print("TP3 hit - SL moved to BE for ticket ", ticket);
                  }
                  tradeStates[stateIdx].tp3_closed = true;
               }
            }
            else // SELL
            {
               tp1 = entryPrice - (entryPrice * InpTP1 / 100);
               tp2 = entryPrice - (entryPrice * InpTP2 / 100);
               tp3 = entryPrice - (entryPrice * InpTP3 / 100);
               tp4 = entryPrice - (entryPrice * InpTP4 / 100);
               
               if(currentPrice <= tp1 && !tradeStates[stateIdx].tp1_closed)
               {
                  if(InpSLToBe == 1 && !tradeStates[stateIdx].be_moved)
                  {
                     trade.PositionModify(ticket, entryPrice, posInfo.TakeProfit());
                     tradeStates[stateIdx].be_moved = true;
                     Print("TP1 hit - SL moved to BE for ticket ", ticket);
                  }
                  tradeStates[stateIdx].tp1_closed = true;
               }
               
               if(currentPrice <= tp2 && !tradeStates[stateIdx].tp2_closed)
               {
                  if(InpSLToBe == 2 && !tradeStates[stateIdx].be_moved)
                  {
                     trade.PositionModify(ticket, entryPrice, posInfo.TakeProfit());
                     tradeStates[stateIdx].be_moved = true;
                     Print("TP2 hit - SL moved to BE for ticket ", ticket);
                  }
                  tradeStates[stateIdx].tp2_closed = true;
               }
               
               if(currentPrice <= tp3 && !tradeStates[stateIdx].tp3_closed)
               {
                  if(InpSLToBe == 3 && !tradeStates[stateIdx].be_moved)
                  {
                     trade.PositionModify(ticket, entryPrice, posInfo.TakeProfit());
                     tradeStates[stateIdx].be_moved = true;
                     Print("TP3 hit - SL moved to BE for ticket ", ticket);
                  }
                  tradeStates[stateIdx].tp3_closed = true;
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Add Trade State                                                  |
//+------------------------------------------------------------------+
void AddTradeState(ulong ticket)
{
   int size = ArraySize(tradeStates);
   ArrayResize(tradeStates, size + 1);
   
   tradeStates[size].ticket = ticket;
   tradeStates[size].tp1_closed = false;
   tradeStates[size].tp2_closed = false;
   tradeStates[size].tp3_closed = false;
   tradeStates[size].be_moved = false;
}

//+------------------------------------------------------------------+
//| Find Trade State                                                 |
//+------------------------------------------------------------------+
int FindTradeState(ulong ticket)
{
   for(int i = 0; i < ArraySize(tradeStates); i++)
   {
      if(tradeStates[i].ticket == ticket)
         return i;
   }
   
   // If not found, add it
   AddTradeState(ticket);
   return ArraySize(tradeStates) - 1;
}

//+------------------------------------------------------------------+
