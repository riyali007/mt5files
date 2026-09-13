//+------------------------------------------------------------------+
//|                                                  ForexReplay.mq5 |
//|                        Professional Forex Replay Simulator       |
//| Clean UI, BE Config, Worst SL, No Closed History & Fix TF P#     |
//| v5.70 - Added DrawDown (DD) Limit Entries + auto-cancel on first |
//|         partial. Everything else is unchanged from the working  |
//|         v5.60 baseline.                                          |
//+------------------------------------------------------------------+
#property copyright "ForexReplay"
#property version   "5.70"
#property strict

//--- Simulation Start Mode
enum ENUM_START_MODE
{
   START_MODE_EXACT_DATETIME = 0, // Exact Date & Time (Calendar Mode)
   START_MODE_DAYS_AGO       = 1  // Relative (Days Ago)
};

input group "=== Simulation Start Mode ==="
input ENUM_START_MODE InpStartMode      = START_MODE_EXACT_DATETIME; // Starting Mode
input datetime         InpExactStartTime= D'2026.06.16 07:00:00';     // Replay Start Time (e.g. 07:00)
input bool             InpUseSwedishTime= true;                       // Input is Swedish Time (converts to Broker time)
input int              InpWarmupDays    = 20;                         // History buffer before start date (warmup)

input group "=== Relative Mode Inputs (if Mode = Days Ago) ==="
input int InpDaysBack  = 80;
input int InpStartAgo  = 60;

input group "=== Execution & Trading Defaults ==="
input int    InpTimerMs     = 100;
input double InpBalance0    = 10000.0;
input double InpLots0       = 0.45;
input double InpRiskPct0    = 2.0;
input int    InpSL0         = 600;
input int    InpTP0         = 1200;
input int    InpSpeed0      = 1;
input int    InpPartials0   = 4;
input int    InpBEAfter0    = 1;  // Default Partial step to move SL to BE (e.g. 1 = after Partial 1)

input group "=== DrawDown Entries ==="
input bool InpEnableDDEntries         = true;  // Enable auto DrawDown Limit Orders
input int  InpDD_OrderCount           = 2;     // Number of additional Limit Orders
input int  InpDD_Spacing              = 200;   // Spacing between DD entries (points)
input bool InpDD_SameSL               = true;  // Use same SL price for all DD entries
input bool InpDD_CancelOnFirstPartial = true;  // Cancel remaining DD limit orders on first partial hit

input group "=== Compact Journaling Screenshots ==="
input bool InpJournal = true;   // Enable CSV logging & Entry Screenshots
input int  InpShotW   = 960;    // Compact Capture Width (px)
input int  InpShotH   = 540;    // Compact Capture Height (px)

#define TPL_NAME     "ForexReplayAuto"
#define SIM_GROUP    "Simulators"
#define SIM_PREF     "SIM."
#define UI           "FR_"
#define JOURNAL_DIR  "ForexReplayJournal"
#define JOURNAL_CSV  "ForexReplayJournal\\journal.csv"
#define STATE_CSV    "ForexReplayJournal\\positions_state.csv"

// Panel Layout Coordinates
#define PANEL_X 12
#define PANEL_Y 30
#define PANEL_W 270
#define ROW_H   24
#define GAP     4

// Color Palette
#define CLR_PANEL_BG      C'28,28,30'
#define CLR_INPUT_BG      C'38,38,42'
#define CLR_BORDER        C'55,55,62'
#define CLR_BLUE_ACTIVE   C'0,122,255'
#define CLR_TAB_INACT     C'48,48,54'
#define CLR_BUY_GREEN     C'34,197,94'
#define CLR_SELL_RED      C'239,68,68'
#define CLR_PARTIAL_YEL   C'161,128,0'
#define CLR_BE_TEAL       C'13,110,110'
#define CLR_CLOSE_SEL     C'180,75,20'
#define CLR_CLOSE_ALL     C'255,0,0'
#define CLR_BTN_GRAY      C'70,70,78'
#define CLR_TEXT_MUTED    C'160,160,170'
#define CLR_TEXT_GREEN    C'34,197,94'
#define CLR_TEXT_RED      C'239,68,68'

#define MAX_PARTIALS 10

enum ENUM_SIDE { SIDE_BUY = 1, SIDE_SELL = -1 };

struct SimPos
{
   ulong       ticket;
   ulong       group_id;      // Links a main entry with its DD (drawdown) sibling limit orders
   ENUM_SIDE   side;
   double      lots;
   double      orig_lots;
   double      price;
   double      sl;
   double      orig_sl;
   double      tp;
   datetime    open_time;
   datetime    close_time;
   double      close_price;
   double      pnl;
   bool        open;
   bool        is_pending;    // true while this is an untriggered DD limit order
   bool        is_dd_entry;   // true for the auto DrawDown limit orders (not the primary entry)
   int         partials;
   int         be_after;
   int         next_partial;
   double      plevels[MAX_PARTIALS];
   bool        be_done;
   bool        shot_on_open_done;
   string      open_shot_file;
};

// Global Replay State
bool     g_is_sim   = false;
bool     g_playing  = false;
datetime g_from = 0, g_to = 0, g_cursor = 0;
int      g_sub_sec  = 0;
double   g_balance = 0, g_equity = 0, g_peak = 0, g_maxdd = 0, g_closed_pnl = 0;
string   g_source = "", g_sim = "";
MqlRates g_m1[];
int      g_m1_n = 0;
SimPos   g_pos[];
ulong    g_next = 1;
ulong    g_next_group = 1;
int      g_speed = 1;
int      g_wins = 0, g_losses = 0;

// Panel-Specific State Variables
int  g_selected_idx    = -1;
bool g_worst_sl_active = false;

// Forward declarations
int      InitLauncher();
int      InitReplay();
void     StartSimFromLauncher();
datetime ResolveBrokerTime(const datetime userLocalTime);
bool     EnsureSymbol(const string sim, const string origin);
bool     SeedToCursor(const string sim, const string origin, const datetime from, const datetime until);
bool     LoadReplayM1();
void     BuildLauncher();
void     LayoutLauncher();
void     BuildModernControlPanel();
void     UpdateModernPanelData();
void     RecalculateRiskFromLot(bool fromLot);
bool     AdvanceStep();
bool     AdvanceOneSecond();
bool     AdvanceOneFullBar();
double   InterpolatePrice(const MqlRates &bar, const int sec);
int      FindBar(const datetime t);
double   SpreadPx();
void     OpenVirt(const ENUM_SIDE side);
void     CreateSimPos(ENUM_SIDE side, double lots, double entry, double sl, double tp, int partials, int be_after_cfg, bool is_pending, ulong group_id, bool is_dd_entry);
void     CancelRemainingDDOrders(const ulong group_id);
void     CheckPartialsAndStops(const double highPrice, const double lowPrice);
void     CheckWorstSL(const double live_bid, const double live_ask);
void     MoveSlToBreakeven(const int i);
void     PartialClose(const int i, const double price, const double closeLots, const int legIndex);
void     ExecuteManualPartialPercent(const double pct);
void     CloseAll(const string reason);
void     CloseOne(const int i, const double price, const string reason);
double   MoneyPnl(const ENUM_SIDE side, const double entry, const double exit, const double lots);
void     MarkToMarket();
string   Tag(const ulong ticket, const string suffix);
void     DrawOrder(const int i);
void     RedrawAllOpenOrders();
void     OrderLine(const string name, const datetime from, const double price, const color col, const string text);
void     RedrawSlLine(const int i);
void     DeleteAllPositionObjects(const ulong ticket);
void     CleanAllClosedTradeObjects();
void     InitJournal();
string   CaptureChartScreenshot(const ulong ticket);
void     JournalRow(const string event, const int i, const double price, const double pnl, const string reason, const string shot);
void     JournalOpen(const int i);
void     JournalPartial(const int i, const double price, const int legIndex, const double lots, const double pnl);
void     JournalClose(const int i, const string reason);
void     SaveFullSessionState();
bool     LoadFullSessionState();
void     ReadEdits();
double   EditNum(const string name);
int      CountOpen();
int      CountClosed();
void     CreateUIRect(const string name, int x, int y, int w, int h, color bg, color border = CLR_BORDER);
void     CreateUIBtn(const string name, int x, int y, int w, int h, string text, color bg, color txtCol = clrWhite, int fSize = 8);
void     CreateUIEdit(const string name, int x, int y, int w, int h, string text, int fSize = 8, int align = ALIGN_CENTER);
void     CreateUILabel(const string name, int x, int y, string text, color col = CLR_TEXT_MUTED, int fSize = 8);

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   g_is_sim = (bool)SymbolInfoInteger(_Symbol, SYMBOL_CUSTOM) && StringFind(_Symbol, SIM_PREF) == 0;
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, false);

   if(g_is_sim)
      return InitReplay();
   return InitLauncher();
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();

   if(g_is_sim && (reason == REASON_CHARTCHANGE || reason == REASON_TEMPLATE || reason == REASON_PARAMETERS))
   {
      SaveFullSessionState();
   }
   else if(reason == REASON_REMOVE || reason == REASON_CHARTCLOSE)
   {
      FileDelete(STATE_CSV);
   }

   ObjectsDeleteAll(0, UI);
   Comment("");
}

//+------------------------------------------------------------------+
//| Expert timer function                                            |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(!g_is_sim)
   {
      LayoutLauncher();
      return;
   }

   if(g_playing)
   {
      for(int i = 0; i < g_speed; i++)
      {
         if(!AdvanceStep())
         {
            g_playing = false;
            ObjectSetString(0, UI + "BTN_PLAY", OBJPROP_TEXT, "Play");
            ObjectSetInteger(0, UI + "BTN_PLAY", OBJPROP_BGCOLOR, CLR_BUY_GREEN);
            break;
         }
      }
   }

   MarkToMarket();
   UpdateModernPanelData();
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| ChartEvent function                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == UI + "START")
      {
         StartSimFromLauncher();
         return;
      }
      if(!g_is_sim) return;

      // Order Actions
      if(sparam == UI + "BTN_BUY")
      {
         ReadEdits();
         OpenVirt(SIDE_BUY);
         UpdateModernPanelData();
         ChartRedraw(0);
         return;
      }
      if(sparam == UI + "BTN_SELL")
      {
         ReadEdits();
         OpenVirt(SIDE_SELL);
         UpdateModernPanelData();
         ChartRedraw(0);
         return;
      }

      // Replay Navigation
      if(sparam == UI + "BTN_PLAY")
      {
         g_playing = !g_playing;
         ObjectSetString(0, UI + "BTN_PLAY", OBJPROP_TEXT, g_playing ? "Pause" : "Play");
         ObjectSetInteger(0, UI + "BTN_PLAY", OBJPROP_BGCOLOR, g_playing ? CLR_PARTIAL_YEL : CLR_BUY_GREEN);
         ReadEdits();
         return;
      }
      if(sparam == UI + "BTN_STEP")
      {
         AdvanceStep();
         MarkToMarket();
         UpdateModernPanelData();
         ChartRedraw(0);
         return;
      }
      if(sparam == UI + "BTN_SPDM")
      {
         g_speed = MathMax(1, g_speed - 1);
         ObjectSetString(0, UI + "ED_SPEED", OBJPROP_TEXT, IntegerToString(g_speed));
         return;
      }
      if(sparam == UI + "BTN_SPDP")
      {
         g_speed = MathMin(100, g_speed + 1);
         ObjectSetString(0, UI + "ED_SPEED", OBJPROP_TEXT, IntegerToString(g_speed));
         return;
      }

      // Trade Selector Prev / Next
      if(sparam == UI + "SEL_PREV" || sparam == UI + "SEL_NEXT")
      {
         int openCount = CountOpen();
         if(openCount == 0)
         {
            g_selected_idx = -1;
         }
         else
         {
            int total = ArraySize(g_pos);
            int step  = (sparam == UI + "SEL_NEXT") ? 1 : -1;
            int start = (g_selected_idx < 0) ? 0 : g_selected_idx + step;

            for(int k = 0; k < total; k++)
            {
               int check = (start + k * step + total * 10) % total;
               if(g_pos[check].open && !g_pos[check].is_pending)
               {
                  g_selected_idx = check;
                  break;
               }
            }
         }
         UpdateModernPanelData();
         return;
      }

      // Selected Position Actions
      if(sparam == UI + "BTN_PARTIAL_SEL")
      {
         double pct = EditNum(UI + "ED_PARTIAL_PCT");
         if(pct <= 0) pct = 20.0;
         ExecuteManualPartialPercent(pct);
         UpdateModernPanelData();
         ChartRedraw(0);
         return;
      }
      if(sparam == UI + "BTN_BE_SEL")
      {
         if(g_selected_idx >= 0 && g_selected_idx < ArraySize(g_pos) && g_pos[g_selected_idx].open && !g_pos[g_selected_idx].is_pending)
         {
            MoveSlToBreakeven(g_selected_idx);
            UpdateModernPanelData();
            ChartRedraw(0);
         }
         return;
      }
      if(sparam == UI + "BTN_CLOSE_SEL")
      {
         if(g_selected_idx >= 0 && g_selected_idx < ArraySize(g_pos) && g_pos[g_selected_idx].open && !g_pos[g_selected_idx].is_pending)
         {
            int cur_idx = FindBar(g_cursor);
            double px = (g_pos[g_selected_idx].side == SIDE_BUY ? g_m1[cur_idx].close : g_m1[cur_idx].close + SpreadPx());
            CloseOne(g_selected_idx, px, "manual_sel");
            UpdateModernPanelData();
            ChartRedraw(0);
         }
         return;
      }
      if(sparam == UI + "BTN_CLOSE_ALL")
      {
         CloseAll("manual_all");
         UpdateModernPanelData();
         ChartRedraw(0);
         return;
      }

      // Worst SL Toggle
      if(sparam == UI + "BTN_WORST_SL")
      {
         g_worst_sl_active = !g_worst_sl_active;
         ObjectSetString(0, UI + "BTN_WORST_SL", OBJPROP_TEXT, "Worst SL: " + (g_worst_sl_active ? "ON" : "OFF"));
         ObjectSetInteger(0, UI + "BTN_WORST_SL", OBJPROP_BGCOLOR, g_worst_sl_active ? CLR_BUY_GREEN : CLR_BTN_GRAY);
         return;
      }
   }

   if(id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      if(sparam == UI + "ED_LOT")
         RecalculateRiskFromLot(true);
      if(sparam == UI + "ED_RISK_PCT")
         RecalculateRiskFromLot(false);
      if(sparam == UI + "ED_SL_PTS" || sparam == UI + "ED_TP_PTS" || sparam == UI + "ED_PARTIALS" || sparam == UI + "ED_BE_AFTER")
         UpdateModernPanelData();
   }
}

//+------------------------------------------------------------------+
//| Swedish Local Time Conversion                                    |
//+------------------------------------------------------------------+
datetime ResolveBrokerTime(const datetime userLocalTime)
{
   if(!InpUseSwedishTime)
      return userLocalTime;

   datetime serverNow = TimeCurrent();
   datetime localNow  = TimeLocal();
   int offsetSec = (int)(serverNow - localNow);

   datetime brokerTarget = userLocalTime + offsetSec;
   return brokerTarget;
}

//+------------------------------------------------------------------+
//| Launcher Initialization                                           |
//+------------------------------------------------------------------+
int InitLauncher()
{
   BuildLauncher();
   EventSetMillisecondTimer(250);
   return INIT_SUCCEEDED;
}

void BuildLauncher()
{
   CreateUIBtn(UI + "START", 0, 0, 260, 44, "START SIMULATION", CLR_BLUE_ACTIVE, clrWhite, 11);
   ObjectSetInteger(0, UI + "START", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   LayoutLauncher();
}

void LayoutLauncher()
{
   int w = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   if(w <= 0 || h <= 0) return;

   int bw = 260, bh = 44;
   ObjectSetInteger(0, UI + "START", OBJPROP_XDISTANCE, (w - bw) / 2);
   ObjectSetInteger(0, UI + "START", OBJPROP_YDISTANCE, (h - bh) / 2);
}

//+------------------------------------------------------------------+
//| Start Simulation Trigger                                          |
//+------------------------------------------------------------------+
void StartSimFromLauncher()
{
   g_to = TimeCurrent();

   if(InpStartMode == START_MODE_EXACT_DATETIME)
   {
      datetime targetBrokerTime = ResolveBrokerTime(InpExactStartTime);
      if(targetBrokerTime >= g_to)
      {
         Alert("InpExactStartTime must be before current time.");
         return;
      }
      g_cursor = targetBrokerTime;
      g_from   = g_cursor - (datetime)MathMax(1, InpWarmupDays) * 86400;
   }
   else
   {
      if(InpStartAgo >= InpDaysBack)
      {
         Alert("InpDaysBack must be greater than InpStartAgo.");
         return;
      }
      g_from   = g_to - (datetime)InpDaysBack * 86400;
      g_cursor = g_to - (datetime)InpStartAgo * 86400;
   }

   g_source   = _Symbol;
   g_sim      = SIM_PREF + _Symbol;
   g_balance  = InpBalance0;
   g_sub_sec  = 0;

   if(!EnsureSymbol(g_sim, g_source)) return;
   if(!SeedToCursor(g_sim, g_source, g_from, g_cursor)) return;
   SaveFullSessionState();

   ChartSaveTemplate(0, TPL_NAME);
   long id = ChartOpen(g_sim, _Period);
   if(id == 0)
   {
      Alert("ChartOpen failed. Error: ", GetLastError());
      return;
   }

   ChartSetInteger(id, CHART_AUTOSCROLL, true);
   ChartSetInteger(id, CHART_SHIFT, true);
   ChartSetInteger(id, CHART_MODE, CHART_CANDLES);

   if(!ChartApplyTemplate(id, TPL_NAME))
      Print("Template apply notice: ", GetLastError(), ". Ensure ForexReplay is attached to the SIM chart.");
}

//+------------------------------------------------------------------+
//| Custom Symbol Setup                                               |
//+------------------------------------------------------------------+
bool EnsureSymbol(const string sim, const string origin)
{
   if(!(bool)SymbolInfoInteger(sim, SYMBOL_EXIST))
   {
      if(!CustomSymbolCreate(sim, SIM_GROUP, origin))
      {
         Alert("Could not create ", sim, ". Error: ", GetLastError());
         return false;
      }
   }

   CustomSymbolSetInteger(sim, SYMBOL_TRADE_MODE, SYMBOL_TRADE_MODE_DISABLED);
   CustomSymbolSetInteger(sim, SYMBOL_SPREAD_FLOAT, false);
   CustomSymbolSetInteger(sim, SYMBOL_SPREAD, MathMax(1, (int)SymbolInfoInteger(origin, SYMBOL_SPREAD)));
   CustomSymbolSetDouble(sim, SYMBOL_POINT, SymbolInfoDouble(origin, SYMBOL_POINT));
   CustomSymbolSetInteger(sim, SYMBOL_DIGITS, SymbolInfoInteger(origin, SYMBOL_DIGITS));
   CustomSymbolSetDouble(sim, SYMBOL_TRADE_TICK_SIZE, SymbolInfoDouble(origin, SYMBOL_TRADE_TICK_SIZE));
   CustomSymbolSetDouble(sim, SYMBOL_TRADE_TICK_VALUE, SymbolInfoDouble(origin, SYMBOL_TRADE_TICK_VALUE));
   CustomSymbolSetDouble(sim, SYMBOL_TRADE_CONTRACT_SIZE, SymbolInfoDouble(origin, SYMBOL_TRADE_CONTRACT_SIZE));
   CustomSymbolSetString(sim, SYMBOL_DESCRIPTION, "Replay " + origin);

   if(!SymbolSelect(sim, true))
   {
      Alert("Could not select ", sim, ". Error: ", GetLastError());
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Seed Initial History                                              |
//+------------------------------------------------------------------+
bool SeedToCursor(const string sim, const string origin, const datetime from, const datetime until)
{
   MqlRates rates[];
   int n = CopyRates(origin, PERIOD_M1, from, until, rates);
   if(n <= 0)
   {
      Alert("No M1 history on ", origin, ". Open an M1 chart, scroll back to load history, then try again.");
      return false;
   }

   CustomRatesDelete(sim, 0, LONG_MAX);
   CustomTicksDelete(sim, 0, LONG_MAX);

   if(CustomRatesReplace(sim, from, until, rates) < 0)
   {
      Alert("CustomRatesReplace failed. Error: ", GetLastError());
      return false;
   }

   MqlTick ticks[];
   ArrayResize(ticks, n);
   double pt = SymbolInfoDouble(origin, SYMBOL_POINT);
   int spread = MathMax(1, (int)SymbolInfoInteger(origin, SYMBOL_SPREAD));
   double spd_val = spread * pt;

   for(int i = 0; i < n; i++)
   {
      ticks[i].time     = rates[i].time + 59;
      ticks[i].time_msc = (long)ticks[i].time * 1000;
      ticks[i].bid      = rates[i].close;
      ticks[i].ask      = rates[i].close + spd_val;
      ticks[i].last     = rates[i].close;
      ticks[i].volume   = rates[i].tick_volume;
      ticks[i].flags    = TICK_FLAG_BID | TICK_FLAG_ASK | TICK_FLAG_LAST | TICK_FLAG_VOLUME;
   }

   CustomTicksAdd(sim, ticks);
   return true;
}

//+------------------------------------------------------------------+
//| Replay Mode Initialization                                        |
//+------------------------------------------------------------------+
int InitReplay()
{
   if(!LoadFullSessionState())
   {
      g_sim     = _Symbol;
      g_source  = StringSubstr(_Symbol, StringLen(SIM_PREF));
      g_to      = TimeCurrent();
      g_from    = g_to - (datetime)InpDaysBack * 86400;
      g_cursor  = g_to - (datetime)InpStartAgo * 86400;
      g_balance = InpBalance0;
      g_speed   = InpSpeed0;
   }

   if(!LoadReplayM1())
   {
      Alert("Failed to load full M1 replay source rates from ", g_source);
      return INIT_FAILED;
   }

   g_equity = g_balance;
   if(g_peak <= 0) g_peak = g_balance;

   BuildModernControlPanel();
   CleanAllClosedTradeObjects();
   RedrawAllOpenOrders();
   UpdateModernPanelData();
   InitJournal();

   EventSetMillisecondTimer(MathMax(20, InpTimerMs));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Load M1 dataset for continuous playback                           |
//+------------------------------------------------------------------+
bool LoadReplayM1()
{
   ArrayFree(g_m1);
   g_m1_n = CopyRates(g_source, PERIOD_M1, g_from, g_to, g_m1);
   return (g_m1_n > 0);
}

//+------------------------------------------------------------------+
//| Build Left Middle-Docked Trading & Replay Panel                   |
//+------------------------------------------------------------------+
void BuildModernControlPanel()
{
   int y = PANEL_Y;
   int x = PANEL_X;
   int w = PANEL_W;
   int halfW = (w - GAP) / 2;

   // 1. Panel Background
   CreateUIRect(UI + "BG", x - 4, y - 4, w + 8, 490, CLR_PANEL_BG, CLR_BORDER);

   // 2. Replay Transport Header
   CreateUIBtn(UI + "BTN_PLAY", x, y, 64, ROW_H, "Play", CLR_BUY_GREEN, clrWhite, 8);
   CreateUIBtn(UI + "BTN_STEP", x + 68, y, 64, ROW_H, "Step", CLR_BLUE_ACTIVE, clrWhite, 8);
   CreateUIBtn(UI + "BTN_SPDM", x + 136, y, 26, ROW_H, "-", CLR_INPUT_BG, clrWhite, 8);
   CreateUIEdit(UI + "ED_SPEED", x + 164, y, 36, ROW_H, IntegerToString(g_speed), 8);
   CreateUIBtn(UI + "BTN_SPDP", x + 202, y, 26, ROW_H, "+", CLR_INPUT_BG, clrWhite, 8);
   CreateUILabel(UI + "LBL_SPD_IND", x + 232, y + 6, "x", CLR_TEXT_MUTED, 8);
   y += ROW_H + GAP + 2;

   // 3. BUY & SELL Buttons
   CreateUIBtn(UI + "BTN_BUY", x, y, halfW, ROW_H + 4, "BUY", CLR_BUY_GREEN, clrWhite, 9);
   CreateUIBtn(UI + "BTN_SELL", x + halfW + GAP, y, halfW, ROW_H + 4, "SELL", CLR_SELL_RED, clrWhite, 9);
   y += ROW_H + GAP + 6;

   // 4. Lot and Risk%
   CreateUILabel(UI + "LBL_LOT", x, y + 4, "Lot:", CLR_TEXT_MUTED, 8);
   CreateUIEdit(UI + "ED_LOT", x + 40, y, 70, ROW_H, DoubleToString(InpLots0, 2));
   CreateUILabel(UI + "LBL_RISK", x + 124, y + 4, "Risk%:", CLR_TEXT_MUTED, 8);
   CreateUIEdit(UI + "ED_RISK_PCT", x + 176, y, w - 176, ROW_H, DoubleToString(InpRiskPct0, 2));
   y += ROW_H + GAP;

   // 5. SL pts & Price Preview
   CreateUILabel(UI + "LBL_SL_PTS", x, y + 4, "SL pts:", CLR_TEXT_MUTED, 8);
   CreateUIEdit(UI + "ED_SL_PTS", x + 50, y, 60, ROW_H, IntegerToString(InpSL0));
   CreateUILabel(UI + "LBL_SL_PRC", x + 120, y + 4, "Prc:", CLR_TEXT_MUTED, 8);
   CreateUIEdit(UI + "ED_SL_PRC", x + 150, y, w - 150, ROW_H, "0.00", 8);
   y += ROW_H + GAP;

   // 6. TP pts & Price Preview
   CreateUILabel(UI + "LBL_TP_PTS", x, y + 4, "TP pts:", CLR_TEXT_MUTED, 8);
   CreateUIEdit(UI + "ED_TP_PTS", x + 50, y, 60, ROW_H, IntegerToString(InpTP0));
   CreateUILabel(UI + "LBL_TP_PRC", x + 120, y + 4, "Prc:", CLR_TEXT_MUTED, 8);
   CreateUIEdit(UI + "ED_TP_PRC", x + 150, y, w - 150, ROW_H, "0.00", 8);
   y += ROW_H + GAP;

   // 7. Partials Count and BE After Partial configuration
   CreateUILabel(UI + "LBL_PARTIALS", x, y + 4, "Partials #:", CLR_TEXT_MUTED, 8);
   CreateUIEdit(UI + "ED_PARTIALS", x + 68, y, 46, ROW_H, IntegerToString(InpPartials0));
   CreateUILabel(UI + "LBL_BE_AFTER", x + 122, y + 4, "BE After P#:", CLR_TEXT_MUTED, 8);
   CreateUIEdit(UI + "ED_BE_AFTER", x + 204, y, w - 204, ROW_H, IntegerToString(InpBEAfter0));
   y += ROW_H + GAP;

   // 8. Partials Breakdown Preview Tag
   CreateUIEdit(UI + "ED_PARTIALS_PREVIEW", x, y, w, 20, "TP1:25 | TP2:50 | TP3:75 | TP4:100", 7, ALIGN_CENTER);
   ObjectSetInteger(0, UI + "ED_PARTIALS_PREVIEW", OBJPROP_READONLY, true);
   ObjectSetInteger(0, UI + "ED_PARTIALS_PREVIEW", OBJPROP_COLOR, CLR_TEXT_MUTED);
   y += 20 + GAP;

   // 9. Risk $ and Profit $
   CreateUILabel(UI + "LBL_RISK_TITLE", x, y + 2, "Risk:", CLR_TEXT_MUTED, 8);
   CreateUILabel(UI + "LBL_RISK_VAL", x + 38, y + 2, "$0.00", CLR_TEXT_RED, 8);
   CreateUILabel(UI + "LBL_PROFIT_TITLE", x + 130, y + 2, "Profit:", CLR_TEXT_MUTED, 8);
   CreateUILabel(UI + "LBL_PROFIT_VAL", x + 172, y + 2, "$0.00", CLR_TEXT_GREEN, 8);
   y += ROW_H;

   // 10. Trade Selector
   CreateUILabel(UI + "LBL_SELECTOR_TITLE", x, y + 2, "Trade Selector:", CLR_TEXT_MUTED, 8);
   y += 18;
   CreateUIBtn(UI + "SEL_PREV", x, y, 36, ROW_H, "<", CLR_INPUT_BG, clrWhite, 8);
   CreateUIEdit(UI + "ED_SEL_DISPLAY", x + 40, y, w - 80, ROW_H, "Selected: none", 8);
   ObjectSetInteger(0, UI + "ED_SEL_DISPLAY", OBJPROP_READONLY, true);
   CreateUIBtn(UI + "SEL_NEXT", x + w - 36, y, 36, ROW_H, ">", CLR_INPUT_BG, clrWhite, 8);
   y += ROW_H + GAP;

   // 11. Partial % (SEL)
   CreateUIEdit(UI + "ED_PARTIAL_PCT", x, y, 50, ROW_H, "20", 8);
   CreateUIBtn(UI + "BTN_PARTIAL_SEL", x + 54, y, w - 54, ROW_H, "PARTIAL % (SEL)", CLR_PARTIAL_YEL, clrWhite, 8);
   y += ROW_H + GAP;

   // 12. BE (SEL) & CLOSE (SEL)
   CreateUIBtn(UI + "BTN_BE_SEL", x, y, halfW, ROW_H, "BE (SEL)", CLR_BE_TEAL, clrWhite, 8);
   CreateUIBtn(UI + "BTN_CLOSE_SEL", x + halfW + GAP, y, halfW, ROW_H, "CLOSE (SEL)", CLR_CLOSE_SEL, clrWhite, 8);
   y += ROW_H + GAP;

   // 13. CLOSE ALL
   CreateUIBtn(UI + "BTN_CLOSE_ALL", x, y, w, ROW_H + 2, "CLOSE ALL", CLR_CLOSE_ALL, clrWhite, 9);
   y += ROW_H + GAP + 4;

   // 14. Worst SL Button
   CreateUIBtn(UI + "BTN_WORST_SL", x, y, w, ROW_H, "Worst SL: OFF", CLR_BTN_GRAY, clrWhite, 8);
   y += ROW_H + GAP + 6;

   // 15. Dynamic Stats Dashboard Section
   CreateUILabel(UI + "LBL_OPEN_TITLE", x, y, "Open Positions:", CLR_TEXT_MUTED, 8);
   y += 18;
   CreateUILabel(UI + "LBL_DASH_1", x, y, "No open positions", clrWhite, 8); y += 15;
   CreateUILabel(UI + "LBL_DASH_2", x, y, "", clrWhite, 8); y += 15;
   CreateUILabel(UI + "LBL_DASH_3", x, y, "", clrWhite, 8); y += 15;
   CreateUILabel(UI + "LBL_DASH_4", x, y, "", clrWhite, 8);
}

//+------------------------------------------------------------------+
//| Update Dynamic Metrics and Colorized Stats                       |
//+------------------------------------------------------------------+
void UpdateModernPanelData()
{
   int cur_idx = FindBar(g_cursor);
   double cur_bid = (cur_idx >= 0) ? g_m1[cur_idx].close : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spd_val = SpreadPx();
   double cur_ask = cur_bid + spd_val;

   int sl_pts = (int)EditNum(UI + "ED_SL_PTS");
   int tp_pts = (int)EditNum(UI + "ED_TP_PTS");
   double lot = EditNum(UI + "ED_LOT");

   double sl_prc = cur_ask - sl_pts * _Point;
   double tp_prc = cur_ask + tp_pts * _Point;
   ObjectSetString(0, UI + "ED_SL_PRC", OBJPROP_TEXT, DoubleToString(sl_prc, _Digits));
   ObjectSetString(0, UI + "ED_TP_PRC", OBJPROP_TEXT, DoubleToString(tp_prc, _Digits));

   // Calculate Risk $ and Profit $
   double contract = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   if(contract <= 0) contract = 100000;
   double risk_usd = sl_pts * _Point * contract * lot;
   double prof_usd = tp_pts * _Point * contract * lot;
   ObjectSetString(0, UI + "LBL_RISK_VAL", OBJPROP_TEXT, StringFormat("$%.2f", risk_usd));
   ObjectSetString(0, UI + "LBL_PROFIT_VAL", OBJPROP_TEXT, StringFormat("$%.2f", prof_usd));

   // Partials text
   int parts = (int)EditNum(UI + "ED_PARTIALS");
   if(parts > 0)
   {
      string pStr = "";
      for(int k = 1; k <= parts; k++)
      {
         int pctVal = (int)MathRound(((double)k / parts) * 100);
         pStr += StringFormat("TP%d:%d%s", k, pctVal, (k < parts ? " | " : ""));
      }
      ObjectSetString(0, UI + "ED_PARTIALS_PREVIEW", OBJPROP_TEXT, pStr);
   }

   // Update Trade Selector Label
   int openCount = CountOpen();
   if(openCount == 0 || g_selected_idx < 0 || g_selected_idx >= ArraySize(g_pos) || !g_pos[g_selected_idx].open || g_pos[g_selected_idx].is_pending)
   {
      g_selected_idx = -1;
      ObjectSetString(0, UI + "ED_SEL_DISPLAY", OBJPROP_TEXT, "Selected: none");
   }
   else
   {
      ObjectSetString(0, UI + "ED_SEL_DISPLAY", OBJPROP_TEXT, StringFormat("Selected: #%I64u", g_pos[g_selected_idx].ticket));
   }

   // Colorized Dynamic Stats Display
   double floating = g_equity - g_balance;
   if(openCount == 0)
   {
      ObjectSetString(0, UI + "LBL_DASH_1", OBJPROP_TEXT, "No open positions");
      ObjectSetInteger(0, UI + "LBL_DASH_1", OBJPROP_COLOR, clrWhite);
   }
   else
   {
      ObjectSetString(0, UI + "LBL_DASH_1", OBJPROP_TEXT, StringFormat("Active: %d pos | Float: %s$%.2f", openCount, floating >= 0 ? "+" : "", floating));
      ObjectSetInteger(0, UI + "LBL_DASH_1", OBJPROP_COLOR, floating > 0.0001 ? CLR_TEXT_GREEN : (floating < -0.0001 ? CLR_TEXT_RED : clrWhite));
   }

   // Row 2: Bal & Equity
   ObjectSetString(0, UI + "LBL_DASH_2", OBJPROP_TEXT, StringFormat("Bal: $%.2f | Eq: $%.2f", g_balance, g_equity));
   ObjectSetInteger(0, UI + "LBL_DASH_2", OBJPROP_COLOR, g_equity > g_balance ? CLR_TEXT_GREEN : (g_equity < g_balance ? CLR_TEXT_RED : clrWhite));

   // Row 3: Closed / Realized PnL & WinRate
   if(openCount == 0)
   {
      double wr = (g_wins + g_losses > 0) ? (100.0 * g_wins / (g_wins + g_losses)) : 0.0;
      ObjectSetString(0, UI + "LBL_DASH_3", OBJPROP_TEXT, StringFormat("Closed P/L: $%.2f | WR: %.1f%%", g_closed_pnl, wr));
   }
   else
   {
      ObjectSetString(0, UI + "LBL_DASH_3", OBJPROP_TEXT, StringFormat("Realized: $%.2f | W/L: %d/%d", g_closed_pnl, g_wins, g_losses));
   }
   ObjectSetInteger(0, UI + "LBL_DASH_3", OBJPROP_COLOR, g_closed_pnl > 0.0001 ? CLR_TEXT_GREEN : (g_closed_pnl < -0.0001 ? CLR_TEXT_RED : clrWhite));

   // Row 4: Replay Time
   ObjectSetString(0, UI + "LBL_DASH_4", OBJPROP_TEXT, StringFormat("Time: %s", TimeToString(g_cursor + g_sub_sec, TIME_DATE|TIME_MINUTES)));
   ObjectSetInteger(0, UI + "LBL_DASH_4", OBJPROP_COLOR, CLR_TEXT_MUTED);
}

//+------------------------------------------------------------------+
//| Recalculate Lot Size from Risk% or Vice Versa                    |
//+------------------------------------------------------------------+
void RecalculateRiskFromLot(bool fromLot)
{
   int sl_pts = (int)EditNum(UI + "ED_SL_PTS");
   if(sl_pts <= 0) sl_pts = 600;
   double contract = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   if(contract <= 0) contract = 100000;

   if(fromLot)
   {
      double lot = EditNum(UI + "ED_LOT");
      double risk_usd = sl_pts * _Point * contract * lot;
      double risk_pct = (g_balance > 0) ? (risk_usd / g_balance) * 100.0 : 2.0;
      ObjectSetString(0, UI + "ED_RISK_PCT", OBJPROP_TEXT, DoubleToString(risk_pct, 2));
   }
   else
   {
      double risk_pct = EditNum(UI + "ED_RISK_PCT");
      double risk_usd = g_balance * (risk_pct / 100.0);
      double lot = risk_usd / (sl_pts * _Point * contract);
      lot = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), MathRound(lot * 100.0) / 100.0);
      ObjectSetString(0, UI + "ED_LOT", OBJPROP_TEXT, DoubleToString(lot, 2));
   }
   UpdateModernPanelData();
}

//+------------------------------------------------------------------+
//| Adaptive Step                                                     |
//+------------------------------------------------------------------+
bool AdvanceStep()
{
   ENUM_TIMEFRAMES p = _Period;
   if(p == PERIOD_M1 || p == PERIOD_M2 || p == PERIOD_M3 || p == PERIOD_M4 || p == PERIOD_M5)
      return AdvanceOneSecond();
   else
      return AdvanceOneFullBar();
}

//+------------------------------------------------------------------+
//| Advance Replay by 1 Second                                        |
//+------------------------------------------------------------------+
bool AdvanceOneSecond()
{
   int idx = FindBar(g_cursor);
   if(idx < 0)
   {
      idx = 0;
      g_cursor = g_m1[0].time;
      g_sub_sec = 0;
   }

   if(g_sub_sec >= 59)
   {
      if(idx + 1 >= g_m1_n) return false;
      idx++;
      g_cursor = g_m1[idx].time;
      g_sub_sec = 0;
   }
   else
   {
      g_sub_sec++;
   }

   MqlRates cur_m1 = g_m1[idx];
   double live_price = InterpolatePrice(cur_m1, g_sub_sec);

   MqlRates cur_bar[1];
   cur_bar[0].time = cur_m1.time;
   cur_bar[0].open = cur_m1.open;

   bool isBull = (cur_m1.close >= cur_m1.open);
   double p1 = isBull ? cur_m1.low : cur_m1.high;

   if(g_sub_sec <= 20)
   {
      cur_bar[0].high = MathMax(cur_m1.open, live_price);
      cur_bar[0].low  = MathMin(cur_m1.open, live_price);
   }
   else if(g_sub_sec <= 40)
   {
      cur_bar[0].high = MathMax(cur_m1.open, MathMax(p1, live_price));
      cur_bar[0].low  = MathMin(cur_m1.open, MathMin(p1, live_price));
   }
   else
   {
      cur_bar[0].high = cur_m1.high;
      cur_bar[0].low  = cur_m1.low;
   }

   cur_bar[0].close       = live_price;
   cur_bar[0].tick_volume = MathMax(1, (long)((cur_m1.tick_volume * (g_sub_sec + 1)) / 60));
   cur_bar[0].spread      = cur_m1.spread;
   cur_bar[0].real_volume = cur_m1.real_volume;

   if(CustomRatesUpdate(_Symbol, cur_bar) < 0)
   {
      Print("CustomRatesUpdate error: ", GetLastError());
      return false;
   }

   MqlTick tick[1];
   double spd_val = SpreadPx();
   tick[0].time     = cur_m1.time + g_sub_sec;
   tick[0].time_msc = (long)tick[0].time * 1000;
   tick[0].bid      = live_price;
   tick[0].ask      = live_price + spd_val;
   tick[0].last     = live_price;
   tick[0].volume   = cur_bar[0].tick_volume;
   tick[0].flags    = TICK_FLAG_BID | TICK_FLAG_ASK | TICK_FLAG_LAST | TICK_FLAG_VOLUME;
   CustomTicksAdd(_Symbol, tick);

   CheckPartialsAndStops(live_price, live_price);
   if(g_worst_sl_active)
      CheckWorstSL(tick[0].bid, tick[0].ask);

   return true;
}

//+------------------------------------------------------------------+
//| Intra-bar Price Interpolation for 0..59 seconds                  |
//+------------------------------------------------------------------+
double InterpolatePrice(const MqlRates &bar, const int sec)
{
   if(sec <= 0)  return bar.open;
   if(sec >= 59) return bar.close;

   bool isBull = (bar.close >= bar.open);
   double p0 = bar.open;
   double p1 = isBull ? bar.low  : bar.high;
   double p2 = isBull ? bar.high : bar.low;
   double p3 = bar.close;

   if(sec <= 20)
   {
      double t = (double)sec / 20.0;
      return p0 + (p1 - p0) * t;
   }
   else if(sec <= 40)
   {
      double t = (double)(sec - 20) / 20.0;
      return p1 + (p2 - p1) * t;
   }
   else
   {
      double t = (double)(sec - 40) / 19.0;
      return p2 + (p3 - p2) * t;
   }
}

//+------------------------------------------------------------------+
//| Advance Replay by 1 Full M1 Bar                                   |
//+------------------------------------------------------------------+
bool AdvanceOneFullBar()
{
   int idx = FindBar(g_cursor);
   if(idx < 0 || idx + 1 >= g_m1_n) return false;

   MqlRates one[1];
   one[0] = g_m1[idx + 1];
   g_cursor  = one[0].time;
   g_sub_sec = 59;

   if(CustomRatesUpdate(_Symbol, one) < 0)
   {
      Print("CustomRatesUpdate error: ", GetLastError());
      return false;
   }

   MqlTick subTicks[4];
   double spd_val = SpreadPx();
   bool isBull = (one[0].close >= one[0].open);

   double prices[4];
   prices[0] = one[0].open;
   prices[1] = isBull ? one[0].low  : one[0].high;
   prices[2] = isBull ? one[0].high : one[0].low;
   prices[3] = one[0].close;

   for(int k = 0; k < 4; k++)
   {
      subTicks[k].time     = one[0].time + (k * 15);
      subTicks[k].time_msc = (long)subTicks[k].time * 1000;
      subTicks[k].bid      = prices[k];
      subTicks[k].ask      = prices[k] + spd_val;
      subTicks[k].last     = prices[k];
      subTicks[k].volume   = MathMax(1, one[0].tick_volume / 4);
      subTicks[k].flags    = TICK_FLAG_BID | TICK_FLAG_ASK | TICK_FLAG_LAST | TICK_FLAG_VOLUME;
   }

   CustomTicksAdd(_Symbol, subTicks);
   CheckPartialsAndStops(one[0].high, one[0].low);
   if(g_worst_sl_active)
      CheckWorstSL(subTicks[3].bid, subTicks[3].ask);

   return true;
}

//+------------------------------------------------------------------+
//| Binary search bar matching cursor time                            |
//+------------------------------------------------------------------+
int FindBar(const datetime t)
{
   int lo = 0, hi = g_m1_n - 1, ans = -1;
   while(lo <= hi)
   {
      int mid = (lo + hi) >> 1;
      if(g_m1[mid].time <= t) { ans = mid; lo = mid + 1; }
      else hi = mid - 1;
   }
   return ans;
}

//+------------------------------------------------------------------+
//| Spread in price units                                              |
//+------------------------------------------------------------------+
double SpreadPx()
{
   return (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
}

//+------------------------------------------------------------------+
//| Execute Virtual Position Entry & DrawDown Entries                 |
//+------------------------------------------------------------------+
void OpenVirt(const ENUM_SIDE side)
{
   MqlTick t;
   if(!SymbolInfoTick(_Symbol, t)) return;

   int cur_idx = FindBar(g_cursor);
   if(cur_idx >= 0)
   {
      double spd_val = SpreadPx();
      double live_price = InterpolatePrice(g_m1[cur_idx], g_sub_sec);
      t.bid  = live_price;
      t.ask  = t.bid + spd_val;
      t.last = t.bid;
   }

   double lot_min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(lot_min <= 0) lot_min = 0.01;
   double lots = MathMax(lot_min, EditNum(UI + "ED_LOT"));
   int slpts = (int)MathMax(0, EditNum(UI + "ED_SL_PTS"));
   int tppts = (int)MathMax(0, EditNum(UI + "ED_TP_PTS"));
   int partials = (int)MathMax(0, MathMin(MAX_PARTIALS, EditNum(UI + "ED_PARTIALS")));
   int be_after_cfg= (int)MathMax(1, EditNum(UI + "ED_BE_AFTER"));

   double entry = (side == SIDE_BUY ? t.ask : t.bid);

   double sl = 0, tp = 0;
   if(slpts > 0) sl = (side == SIDE_BUY ? entry - slpts * _Point : entry + slpts * _Point);
   if(tppts > 0) tp = (side == SIDE_BUY ? entry + tppts * _Point : entry - tppts * _Point);

   ulong group_id = g_next_group++;

   // 1. Create the primary active execution (identical to the original behavior)
   CreateSimPos(side, lots, entry, sl, tp, partials, be_after_cfg, false, group_id, false);

   // 2. Queue the additional DrawDown limit orders (Pending), tagged with the
   //    same group_id so they can be identified and cancelled together once
   //    the main entry reaches its first partial target.
   if(InpEnableDDEntries && InpDD_OrderCount > 0)
   {
      for(int k = 1; k <= InpDD_OrderCount; k++)
      {
         double p_dd = (side == SIDE_BUY) ? entry - (k * InpDD_Spacing * _Point) : entry + (k * InpDD_Spacing * _Point);
         double sl_dd = 0;

         if(InpDD_SameSL)
         {
            sl_dd = sl;
         }
         else
         {
            sl_dd = (slpts > 0) ? ((side == SIDE_BUY) ? p_dd - slpts * _Point : p_dd + slpts * _Point) : 0;
         }

         double tp_dd = (tppts > 0) ? ((side == SIDE_BUY) ? p_dd + tppts * _Point : p_dd - tppts * _Point) : 0;

         CreateSimPos(side, lots, p_dd, sl_dd, tp_dd, partials, be_after_cfg, true, group_id, true);
      }
   }

   SaveFullSessionState();
}

//+------------------------------------------------------------------+
//| Create a single position record (main entry OR a DD limit order) |
//+------------------------------------------------------------------+
void CreateSimPos(ENUM_SIDE side, double lots, double entry, double sl, double tp, int partials, int be_after_cfg, bool is_pending, ulong group_id, bool is_dd_entry)
{
   if(partials > 0 && tp == 0)
      partials = 0;

   int n = ArraySize(g_pos);
   ArrayResize(g_pos, n + 1);

   g_pos[n].ticket            = g_next++;
   g_pos[n].group_id          = group_id;
   g_pos[n].side              = side;
   g_pos[n].lots              = lots;
   g_pos[n].orig_lots         = lots;
   g_pos[n].price             = entry;
   g_pos[n].sl                = sl;
   g_pos[n].orig_sl           = sl;
   g_pos[n].tp                = tp;
   g_pos[n].open_time         = g_cursor + g_sub_sec;
   g_pos[n].close_time        = 0;
   g_pos[n].close_price       = 0;
   g_pos[n].pnl               = 0;
   g_pos[n].open              = true;
   g_pos[n].is_pending        = is_pending;
   g_pos[n].is_dd_entry       = is_dd_entry;
   g_pos[n].partials          = partials;
   g_pos[n].be_after          = (partials > 0) ? MathMin(partials, be_after_cfg) : 1;
   g_pos[n].next_partial      = 1;
   g_pos[n].be_done           = false;
   g_pos[n].shot_on_open_done = false;
   g_pos[n].open_shot_file    = "";

   ArrayInitialize(g_pos[n].plevels, 0.0);
   if(partials > 0)
   {
      double dist = (tp - entry);
      for(int k = 1; k <= partials; k++)
         g_pos[n].plevels[k - 1] = entry + dist * ((double)k / partials);
   }

   DrawOrder(n);

   // Only journal + select the primary execution immediately. Pending DD limit
   // orders get journaled once they actually trigger (see CheckPartialsAndStops).
   if(!is_pending)
   {
      g_selected_idx = n;
      JournalOpen(n);
   }
}

//+------------------------------------------------------------------+
//| Cancel remaining pending DD limit orders for a trade group        |
//| Called once the main entry hits its first partial target - the   |
//| DD entries are no longer needed once price has moved into profit.|
//+------------------------------------------------------------------+
void CancelRemainingDDOrders(const ulong group_id)
{
   for(int i = 0; i < ArraySize(g_pos); i++)
   {
      if(!g_pos[i].open) continue;
      if(!g_pos[i].is_pending) continue;
      if(!g_pos[i].is_dd_entry) continue;
      if(g_pos[i].group_id != group_id) continue;

      g_pos[i].open = false;
      DeleteAllPositionObjects(g_pos[i].ticket);
      JournalRow("CANCEL", i, g_pos[i].price, 0.0, "dd_cancel_on_first_partial", "");
   }
}

//+------------------------------------------------------------------+
//| Multi-Trade Worst SL Logic (Only moves worst entry to BE if green)
//+------------------------------------------------------------------+
void CheckWorstSL(const double live_bid, const double live_ask)
{
   int buyCount = 0;
   int sellCount = 0;
   int worstBuy = -1;
   int worstSell = -1;
   double worstBuyPnl = DBL_MAX;
   double worstSellPnl = DBL_MAX;

   // Evaluate each individual open trade's floating PnL (pending DD limit
   // orders are skipped - they are not live positions yet)
   for(int i = 0; i < ArraySize(g_pos); i++)
   {
      if(!g_pos[i].open || g_pos[i].is_pending) continue;

      double cur = (g_pos[i].side == SIDE_BUY ? live_bid : live_ask);
      double pnl = MoneyPnl(g_pos[i].side, g_pos[i].price, cur, g_pos[i].lots);

      if(g_pos[i].side == SIDE_BUY)
      {
         buyCount++;
         if(pnl < worstBuyPnl)
         {
            worstBuyPnl = pnl;
            worstBuy = i;
         }
      }
      else
      {
         sellCount++;
         if(pnl < worstSellPnl)
         {
            worstSellPnl = pnl;
            worstSell = i;
         }
      }
   }

   // If multiple BUY entries exist, only move the worst BUY to BE if that specific entry is green
   if(buyCount > 1 && worstBuy >= 0 && worstBuyPnl > 0.0001 && !g_pos[worstBuy].be_done)
   {
      MoveSlToBreakeven(worstBuy);
      SaveFullSessionState();
   }

   // If multiple SELL entries exist, only move the worst SELL to BE if that specific entry is green
   if(sellCount > 1 && worstSell >= 0 && worstSellPnl > 0.0001 && !g_pos[worstSell].be_done)
   {
      MoveSlToBreakeven(worstSell);
      SaveFullSessionState();
   }
}

//+------------------------------------------------------------------+
//| Evaluate stops, targets, and partials (Auto SL to BE on Partials)|
//+------------------------------------------------------------------+
void CheckPartialsAndStops(const double highPrice, const double lowPrice)
{
   for(int i = 0; i < ArraySize(g_pos); i++)
   {
      if(!g_pos[i].open) continue;

      // Pending DrawDown limit order evaluation - check if price reached the
      // limit price and, if so, turn it into a live position.
      if(g_pos[i].is_pending)
      {
         bool triggered = false;
         if(g_pos[i].side == SIDE_BUY  && lowPrice  <= g_pos[i].price) triggered = true;
         if(g_pos[i].side == SIDE_SELL && highPrice >= g_pos[i].price) triggered = true;

         if(triggered)
         {
            g_pos[i].is_pending = false;
            g_pos[i].open_time  = g_cursor + g_sub_sec;
            DeleteAllPositionObjects(g_pos[i].ticket); // clear pending visual layout
            DrawOrder(i);      // Redraw as an active/live trade
            JournalOpen(i);    // Journal the live execution
            SaveFullSessionState();
         }
         continue; // Prevent checking SL/TP on the exact same tick it triggered
      }

      bool firstPartialJustHit = false;

      while(g_pos[i].open && g_pos[i].partials > 0 && g_pos[i].next_partial <= g_pos[i].partials)
      {
         int k = g_pos[i].next_partial;
         double lvl = g_pos[i].plevels[k - 1];
         bool hit = (g_pos[i].side == SIDE_BUY ? highPrice >= lvl : lowPrice <= lvl);
         if(!hit) break;

         double closeLots = (k == g_pos[i].partials)
                             ? g_pos[i].lots
                             : MathMin(g_pos[i].lots, g_pos[i].orig_lots / g_pos[i].partials);

         if(k == 1) firstPartialJustHit = true;

         PartialClose(i, lvl, closeLots, k);

         // Auto SL to BE trigger once reaching configured be_after partial step
         if(g_pos[i].be_after > 0 && k >= g_pos[i].be_after && !g_pos[i].be_done && g_pos[i].open)
            MoveSlToBreakeven(i);

         g_pos[i].next_partial++;
      }

      // Requirement: as soon as price hits the FIRST partial of the main entry,
      // automatically cancel all remaining (not yet triggered) DD limit orders
      // that belong to the same trade group.
      if(firstPartialJustHit && InpDD_CancelOnFirstPartial && !g_pos[i].is_dd_entry)
      {
         CancelRemainingDDOrders(g_pos[i].group_id);
      }

      if(!g_pos[i].open) continue;

      if(g_pos[i].side == SIDE_BUY)
      {
         if(g_pos[i].sl > 0 && lowPrice <= g_pos[i].sl)
         {
            CloseOne(i, g_pos[i].sl, g_pos[i].be_done ? "BE" : "SL");
            continue;
         }
      }
      else
      {
         if(g_pos[i].sl > 0 && highPrice >= g_pos[i].sl)
         {
            CloseOne(i, g_pos[i].sl, g_pos[i].be_done ? "BE" : "SL");
            continue;
         }
      }

      if(g_pos[i].tp > 0 && g_pos[i].partials == 0)
      {
         if(g_pos[i].side == SIDE_BUY && highPrice >= g_pos[i].tp)
         {
            CloseOne(i, g_pos[i].tp, "TP");
            continue;
         }
         if(g_pos[i].side == SIDE_SELL && lowPrice <= g_pos[i].tp)
         {
            CloseOne(i, g_pos[i].tp, "TP");
            continue;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Breakeven SL Adjustment                                            |
//+------------------------------------------------------------------+
void MoveSlToBreakeven(const int i)
{
   g_pos[i].sl = g_pos[i].price;
   g_pos[i].be_done = true;
   RedrawSlLine(i);
}

//+------------------------------------------------------------------+
//| Execute Partial Close                                              |
//+------------------------------------------------------------------+
void PartialClose(const int i, const double price, const double closeLots, const int legIndex)
{
   double lots = MathMin(closeLots, g_pos[i].lots);
   if(lots <= 0) return;

   double pnl = MoneyPnl(g_pos[i].side, g_pos[i].price, price, lots);
   g_pos[i].lots -= lots;
   g_pos[i].pnl += pnl;
   g_balance += pnl;
   g_closed_pnl += pnl;

   // Remove the partial line that was just reached
   ObjectDelete(0, Tag(g_pos[i].ticket, "P" + IntegerToString(legIndex)));
   JournalPartial(i, price, legIndex, lots, pnl);

   if(g_pos[i].lots <= 0.0000001)
   {
      g_pos[i].open = false;
      g_pos[i].close_price = price;
      g_pos[i].close_time = g_cursor + g_sub_sec;
      if(g_pos[i].pnl >= 0) g_wins++; else g_losses++;
      JournalClose(i, "TP");
      DeleteAllPositionObjects(g_pos[i].ticket);
   }

   if(g_equity > g_peak) g_peak = g_equity;
   double dd = g_peak - g_equity;
   if(dd > g_maxdd) g_maxdd = dd;
   SaveFullSessionState();
}

//+------------------------------------------------------------------+
//| Execute Manual Partial Percentage on Selected Position            |
//+------------------------------------------------------------------+
void ExecuteManualPartialPercent(const double pct)
{
   if(g_selected_idx < 0 || g_selected_idx >= ArraySize(g_pos) || !g_pos[g_selected_idx].open || g_pos[g_selected_idx].is_pending)
      return;

   double closeLots = g_pos[g_selected_idx].lots * (pct / 100.0);
   closeLots = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), MathRound(closeLots * 100.0) / 100.0);

   int cur_idx = FindBar(g_cursor);
   double px = (g_pos[g_selected_idx].side == SIDE_BUY ? g_m1[cur_idx].close : g_m1[cur_idx].close + SpreadPx());

   bool  wasFirst = (g_pos[g_selected_idx].next_partial == 1);
   ulong gid       = g_pos[g_selected_idx].group_id;
   bool  isDd      = g_pos[g_selected_idx].is_dd_entry;

   PartialClose(g_selected_idx, px, closeLots, g_pos[g_selected_idx].next_partial++);

   if(wasFirst && InpDD_CancelOnFirstPartial && !isDd)
      CancelRemainingDDOrders(gid);
}

//+------------------------------------------------------------------+
//| Close all open simulator positions (cancels pending DD orders too)|
//+------------------------------------------------------------------+
void CloseAll(const string reason)
{
   MqlTick t;
   if(!SymbolInfoTick(_Symbol, t)) return;

   int cur_idx = FindBar(g_cursor);
   if(cur_idx >= 0)
   {
      double spd_val = SpreadPx();
      double live_price = InterpolatePrice(g_m1[cur_idx], g_sub_sec);
      t.bid = live_price;
      t.ask = t.bid + spd_val;
   }

   for(int i = 0; i < ArraySize(g_pos); i++)
   {
      if(!g_pos[i].open) continue;

      if(g_pos[i].is_pending)
      {
         g_pos[i].open = false;
         DeleteAllPositionObjects(g_pos[i].ticket);
         continue;
      }

      double px = (g_pos[i].side == SIDE_BUY ? t.bid : t.ask);
      CloseOne(i, px, reason);
   }
}

//+------------------------------------------------------------------+
//| Close single position (Removes all chart visuals completely)      |
//+------------------------------------------------------------------+
void CloseOne(const int i, const double price, const string reason)
{
   if(!g_pos[i].open) return;

   double pnl = MoneyPnl(g_pos[i].side, g_pos[i].price, price, g_pos[i].lots);
   g_pos[i].open = false;
   g_pos[i].close_price = price;
   g_pos[i].close_time = g_cursor + g_sub_sec;
   g_pos[i].pnl += pnl;
   g_balance += pnl;
   g_closed_pnl += pnl;

   if(g_pos[i].pnl >= 0) g_wins++; else g_losses++;

   JournalClose(i, reason);
   DeleteAllPositionObjects(g_pos[i].ticket);

   if(g_equity > g_peak) g_peak = g_equity;
   double dd = g_peak - g_equity;
   if(dd > g_maxdd) g_maxdd = dd;
   SaveFullSessionState();
}

//+------------------------------------------------------------------+
//| Monetary PnL Calculation                                           |
//+------------------------------------------------------------------+
double MoneyPnl(const ENUM_SIDE side, const double entry, const double exit, const double lots)
{
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(ts <= 0) ts = _Point;
   if(tv <= 0) tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE) * ts;
   return ((exit - entry) / ts) * tv * lots * (int)side;
}

//+------------------------------------------------------------------+
//| Mark To Market Floating Equity                                     |
//+------------------------------------------------------------------+
void MarkToMarket()
{
   MqlTick t;
   if(!SymbolInfoTick(_Symbol, t)) return;

   int cur_idx = FindBar(g_cursor);
   if(cur_idx >= 0)
   {
      double spd_val = SpreadPx();
      double live_price = InterpolatePrice(g_m1[cur_idx], g_sub_sec);
      t.bid = live_price;
      t.ask = t.bid + spd_val;
   }

   double floating = 0;
   for(int i = 0; i < ArraySize(g_pos); i++)
   {
      if(!g_pos[i].open || g_pos[i].is_pending) continue;
      double cur = (g_pos[i].side == SIDE_BUY ? t.bid : t.ask);
      floating += MoneyPnl(g_pos[i].side, g_pos[i].price, cur, g_pos[i].lots);
   }

   g_equity = g_balance + floating;
   if(g_equity > g_peak) g_peak = g_equity;
   double dd = g_peak - g_equity;
   if(dd > g_maxdd) g_maxdd = dd;
}

//+------------------------------------------------------------------+
//| Object Tag Helper                                                  |
//+------------------------------------------------------------------+
string Tag(const ulong ticket, const string suffix)
{
   return UI + "ORD_" + IntegerToString((long)ticket) + "_" + suffix;
}

//+------------------------------------------------------------------+
//| Remove all chart objects created for a specific ticket            |
//+------------------------------------------------------------------+
void DeleteAllPositionObjects(const ulong ticket)
{
   string prefix = UI + "ORD_" + IntegerToString((long)ticket) + "_";

   // Exact named deletion
   ObjectDelete(0, prefix + "IN");
   ObjectDelete(0, prefix + "PENDING");
   ObjectDelete(0, prefix + "LABEL");
   ObjectDelete(0, prefix + "SL");
   ObjectDelete(0, prefix + "TP");
   ObjectDelete(0, prefix + "OUT");
   ObjectDelete(0, prefix + "SEG");

   for(int k = 1; k <= MAX_PARTIALS; k++)
   {
      ObjectDelete(0, prefix + "P" + IntegerToString(k));
      ObjectDelete(0, prefix + "PX" + IntegerToString(k));
   }

   // Full prefix cleanup scan across chart
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, prefix) == 0)
         ObjectDelete(0, name);
   }
}

//+------------------------------------------------------------------+
//| Remove any residual objects of closed trades from the chart       |
//+------------------------------------------------------------------+
void CleanAllClosedTradeObjects()
{
   for(int i = 0; i < ArraySize(g_pos); i++)
   {
      if(!g_pos[i].open)
         DeleteAllPositionObjects(g_pos[i].ticket);
   }
}

//+------------------------------------------------------------------+
//| Recreate Graphical Orders for currently OPEN positions only       |
//+------------------------------------------------------------------+
void RedrawAllOpenOrders()
{
   for(int i = 0; i < ArraySize(g_pos); i++)
   {
      if(g_pos[i].open)
         DrawOrder(i);
      else
         DeleteAllPositionObjects(g_pos[i].ticket);
   }
}

//+------------------------------------------------------------------+
//| Chart Order Graphics (Handles Active AND Pending DrawDowns)       |
//+------------------------------------------------------------------+
void DrawOrder(const int i)
{
   if(!g_pos[i].open) return;

   color col = (g_pos[i].side == SIDE_BUY ? CLR_BUY_GREEN : CLR_SELL_RED);

   if(g_pos[i].is_pending)
   {
      string label = Tag(g_pos[i].ticket, "LABEL");
      ObjectCreate(0, label, OBJ_TEXT, 0, g_pos[i].open_time, g_pos[i].price);
      ObjectSetString(0, label, OBJPROP_TEXT, StringFormat(" LIMIT #%I64u %s %.2f", g_pos[i].ticket, g_pos[i].side == SIDE_BUY ? "BUY" : "SELL", g_pos[i].orig_lots));
      ObjectSetInteger(0, label, OBJPROP_COLOR, clrDarkGray);
      ObjectSetInteger(0, label, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, label, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);

      OrderLine(Tag(g_pos[i].ticket, "PENDING"), g_pos[i].open_time, g_pos[i].price, clrDarkGray, "LIMIT");
      if(g_pos[i].sl > 0) OrderLine(Tag(g_pos[i].ticket, "SL"), g_pos[i].open_time, g_pos[i].sl, clrDarkGray, "L_SL");
      if(g_pos[i].tp > 0) OrderLine(Tag(g_pos[i].ticket, "TP"), g_pos[i].open_time, g_pos[i].tp, clrDarkGray, "L_TP");
      return;
   }

   string a = Tag(g_pos[i].ticket, "IN");
   ObjectCreate(0, a, OBJ_ARROW, 0, g_pos[i].open_time, g_pos[i].price);
   ObjectSetInteger(0, a, OBJPROP_ARROWCODE, g_pos[i].side == SIDE_BUY ? 233 : 234);
   ObjectSetInteger(0, a, OBJPROP_COLOR, col);
   ObjectSetInteger(0, a, OBJPROP_WIDTH, 2);

   string label = Tag(g_pos[i].ticket, "LABEL");
   ObjectCreate(0, label, OBJ_TEXT, 0, g_pos[i].open_time, g_pos[i].price);
   ObjectSetString(0, label, OBJPROP_TEXT, StringFormat(" #%I64u %s %.2f", g_pos[i].ticket, g_pos[i].side == SIDE_BUY ? "BUY" : "SELL", g_pos[i].orig_lots));
   ObjectSetInteger(0, label, OBJPROP_COLOR, col);
   ObjectSetInteger(0, label, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, label, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);

   if(g_pos[i].sl > 0) RedrawSlLine(i);

   if(g_pos[i].partials > 0)
   {
      // Clean up any lines for already-executed partials
      for(int k = 1; k < g_pos[i].next_partial; k++)
      {
         ObjectDelete(0, Tag(g_pos[i].ticket, "P" + IntegerToString(k)));
      }

      // Draw ONLY remaining pending partial levels
      for(int k = g_pos[i].next_partial; k <= g_pos[i].partials; k++)
      {
         string pl = Tag(g_pos[i].ticket, "P" + IntegerToString(k));
         double lvl = g_pos[i].plevels[k - 1];
         color pcol = (k == g_pos[i].partials ? CLR_BUY_GREEN : CLR_PARTIAL_YEL);
         OrderLine(pl, g_pos[i].open_time, lvl, pcol, (k == g_pos[i].partials ? "TP" : StringFormat("P%d", k)));
      }
   }
   else if(g_pos[i].tp > 0)
   {
      OrderLine(Tag(g_pos[i].ticket, "TP"), g_pos[i].open_time, g_pos[i].tp, CLR_BUY_GREEN, "TP");
   }
}

void OrderLine(const string name, const datetime from, const double price, const color col, const string text)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_TREND, 0, from, price, from + PeriodSeconds() * 80, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, text + " " + DoubleToString(price, _Digits));
}

void RedrawSlLine(const int i)
{
   string name = Tag(g_pos[i].ticket, "SL");
   color col = (g_pos[i].be_done ? CLR_BE_TEAL : CLR_SELL_RED);
   string text = (g_pos[i].be_done ? "BE" : "SL");
   OrderLine(name, g_pos[i].open_time, g_pos[i].sl, col, text);
}

//+------------------------------------------------------------------+
//| Trade Journaling Initialization                                    |
//+------------------------------------------------------------------+
void InitJournal()
{
   if(!InpJournal) return;
   FolderCreate(JOURNAL_DIR);
   if(!FileIsExist(JOURNAL_CSV))
   {
      int h = FileOpen(JOURNAL_CSV, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
      if(h != INVALID_HANDLE)
      {
         FileWrite(h, "event", "ticket", "symbol", "side", "lots", "orig_lots",
                   "entry", "sl", "orig_sl", "tp", "price", "pnl", "balance_after",
                   "equity_after", "reason", "sim_time", "open_screenshot_link");
         FileClose(h);
      }
   }
}

//+------------------------------------------------------------------+
//| Compact Native Chart Screenshot Capture                            |
//+------------------------------------------------------------------+
string CaptureChartScreenshot(const ulong ticket)
{
   if(!InpJournal) return "";

   datetime full_t = g_cursor + g_sub_sec;
   MqlDateTime dt; TimeToStruct(full_t, dt);

   string rel_path = StringFormat("%s\\%s_%I64u_OPEN_%04d%02d%02d_%02d%02d%02d.png",
                                   JOURNAL_DIR, _Symbol, ticket,
                                   dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec);

   int sw = (InpShotW > 0 ? InpShotW : 960);
   int sh = (InpShotH > 0 ? InpShotH : 540);

   if(ChartScreenShot(0, rel_path, sw, sh))
      return rel_path;

   return "";
}

//+------------------------------------------------------------------+
//| Journal Row Writing                                                |
//+------------------------------------------------------------------+
void JournalRow(const string event, const int i, const double price, const double pnl, const string reason, const string shot)
{
   if(!InpJournal) return;
   int h = FileOpen(JOURNAL_CSV, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(h == INVALID_HANDLE) return;
   FileSeek(h, 0, SEEK_END);
   FileWrite(h, event,
             IntegerToString((long)g_pos[i].ticket),
             _Symbol,
             g_pos[i].side == SIDE_BUY ? "BUY" : "SELL",
             DoubleToString(g_pos[i].lots, 2),
             DoubleToString(g_pos[i].orig_lots, 2),
             DoubleToString(g_pos[i].price, _Digits),
             DoubleToString(g_pos[i].sl, _Digits),
             DoubleToString(g_pos[i].orig_sl, _Digits),
             DoubleToString(g_pos[i].tp, _Digits),
             DoubleToString(price, _Digits),
             DoubleToString(pnl, 2),
             DoubleToString(g_balance, 2),
             DoubleToString(g_equity, 2),
             reason,
             TimeToString(g_cursor + g_sub_sec, TIME_DATE | TIME_SECONDS),
             shot);
   FileClose(h);
}

void JournalOpen(const int i)
{
   string shot = CaptureChartScreenshot(g_pos[i].ticket);
   g_pos[i].open_shot_file = shot;
   g_pos[i].shot_on_open_done = true;
   JournalRow("OPEN", i, g_pos[i].price, 0.0, "open", shot);
}

void JournalPartial(const int i, const double price, const int legIndex, const double lots, const double pnl)
{
   JournalRow("PARTIAL", i, price, pnl, StringFormat("leg %d/%d, %.2f lots", legIndex, g_pos[i].partials, lots), g_pos[i].open_shot_file);
}

void JournalClose(const int i, const string reason)
{
   JournalRow("CLOSE", i, g_pos[i].close_price, g_pos[i].pnl, reason, g_pos[i].open_shot_file);
}

int CountOpen()
{
   int n = 0;
   for(int i = 0; i < ArraySize(g_pos); i++)
      if(g_pos[i].open && !g_pos[i].is_pending) n++;
   return n;
}

int CountClosed()
{
   int n = 0;
   for(int i = 0; i < ArraySize(g_pos); i++)
      if(!g_pos[i].open) n++;
   return n;
}

//+------------------------------------------------------------------+
//| Full Session State Persistence across Timeframe Changes           |
//+------------------------------------------------------------------+
void SaveFullSessionState()
{
   GlobalVariableSet("FR_FROM", (double)g_from);
   GlobalVariableSet("FR_TO", (double)g_to);
   GlobalVariableSet("FR_CUR", (double)g_cursor);
   GlobalVariableSet("FR_SUBSEC", (double)g_sub_sec);
   GlobalVariableSet("FR_BAL", g_balance);
   GlobalVariableSet("FR_EQ", g_equity);
   GlobalVariableSet("FR_PEAK", g_peak);
   GlobalVariableSet("FR_MDD", g_maxdd);
   GlobalVariableSet("FR_CPNL", g_closed_pnl);
   GlobalVariableSet("FR_SPD", (double)g_speed);
   GlobalVariableSet("FR_PLAY", g_playing ? 1.0 : 0.0);
   GlobalVariableSet("FR_NEXT", (double)g_next);
   GlobalVariableSet("FR_NEXTGRP", (double)g_next_group);
   GlobalVariableSet("FR_WINS", (double)g_wins);
   GlobalVariableSet("FR_LOSS", (double)g_losses);

   int h = FileOpen(STATE_CSV, FILE_WRITE | FILE_CSV | FILE_ANSI, ';');
   if(h != INVALID_HANDLE)
   {
      int posCount = ArraySize(g_pos);
      FileWrite(h, posCount);
      for(int i = 0; i < posCount; i++)
      {
         string plevelsStr = "";
         for(int k = 0; k < MAX_PARTIALS; k++)
            plevelsStr += DoubleToString(g_pos[i].plevels[k], _Digits) + (k < MAX_PARTIALS - 1 ? "," : "");

         FileWrite(h,
                   IntegerToString((long)g_pos[i].ticket),
                   IntegerToString((long)g_pos[i].group_id),
                   (int)g_pos[i].side,
                   DoubleToString(g_pos[i].lots, 4),
                   DoubleToString(g_pos[i].orig_lots, 4),
                   DoubleToString(g_pos[i].price, _Digits),
                   DoubleToString(g_pos[i].sl, _Digits),
                   DoubleToString(g_pos[i].orig_sl, _Digits),
                   DoubleToString(g_pos[i].tp, _Digits),
                   (long)g_pos[i].open_time,
                   (long)g_pos[i].close_time,
                   DoubleToString(g_pos[i].close_price, _Digits),
                   DoubleToString(g_pos[i].pnl, 2),
                   g_pos[i].open ? 1 : 0,
                   g_pos[i].is_dd_entry ? 1 : 0,
                   g_pos[i].partials,
                   g_pos[i].be_after,
                   g_pos[i].next_partial,
                   plevelsStr,
                   g_pos[i].be_done ? 1 : 0,
                   g_pos[i].shot_on_open_done ? 1 : 0,
                   g_pos[i].open_shot_file,
                   g_pos[i].is_pending ? 1 : 0);
      }
      FileClose(h);
   }
}

bool LoadFullSessionState()
{
   if(!GlobalVariableCheck("FR_FROM")) return false;

   g_from = (datetime)GlobalVariableGet("FR_FROM");
   g_to = (datetime)GlobalVariableGet("FR_TO");
   g_cursor = (datetime)GlobalVariableGet("FR_CUR");
   g_sub_sec = (int)GlobalVariableGet("FR_SUBSEC");
   g_balance = GlobalVariableGet("FR_BAL");
   g_equity = GlobalVariableGet("FR_EQ");
   g_peak = GlobalVariableGet("FR_PEAK");
   g_maxdd = GlobalVariableGet("FR_MDD");
   g_closed_pnl = GlobalVariableGet("FR_CPNL");
   g_speed = (int)GlobalVariableGet("FR_SPD");
   g_playing = (GlobalVariableGet("FR_PLAY") > 0.5);
   g_next = (ulong)GlobalVariableGet("FR_NEXT");
   g_next_group = GlobalVariableCheck("FR_NEXTGRP") ? (ulong)GlobalVariableGet("FR_NEXTGRP") : 1;
   g_wins = (int)GlobalVariableGet("FR_WINS");
   g_losses = (int)GlobalVariableGet("FR_LOSS");

   g_sim = _Symbol;
   g_source = StringSubstr(_Symbol, StringLen(SIM_PREF));

   if(FileIsExist(STATE_CSV))
   {
      int h = FileOpen(STATE_CSV, FILE_READ | FILE_CSV | FILE_ANSI, ';');
      if(h != INVALID_HANDLE)
      {
         int posCount = (int)StringToInteger(FileReadString(h));
         ArrayResize(g_pos, posCount);
         for(int i = 0; i < posCount; i++)
         {
            g_pos[i].ticket = (ulong)StringToInteger(FileReadString(h));
            g_pos[i].group_id = (ulong)StringToInteger(FileReadString(h));
            g_pos[i].side = (ENUM_SIDE)StringToInteger(FileReadString(h));
            g_pos[i].lots = StringToDouble(FileReadString(h));
            g_pos[i].orig_lots = StringToDouble(FileReadString(h));
            g_pos[i].price = StringToDouble(FileReadString(h));
            g_pos[i].sl = StringToDouble(FileReadString(h));
            g_pos[i].orig_sl = StringToDouble(FileReadString(h));
            g_pos[i].tp = StringToDouble(FileReadString(h));
            g_pos[i].open_time = (datetime)StringToInteger(FileReadString(h));
            g_pos[i].close_time = (datetime)StringToInteger(FileReadString(h));
            g_pos[i].close_price= StringToDouble(FileReadString(h));
            g_pos[i].pnl = StringToDouble(FileReadString(h));
            g_pos[i].open = (StringToInteger(FileReadString(h)) == 1);
            g_pos[i].is_dd_entry = (StringToInteger(FileReadString(h)) == 1);
            g_pos[i].partials = (int)StringToInteger(FileReadString(h));
            g_pos[i].be_after = (int)StringToInteger(FileReadString(h));
            g_pos[i].next_partial = (int)StringToInteger(FileReadString(h));

            string plevelsStr = FileReadString(h);
            string splittedLevels[];
            StringSplit(plevelsStr, ',', splittedLevels);
            for(int k = 0; k < MAX_PARTIALS; k++)
            {
               if(k < ArraySize(splittedLevels))
                  g_pos[i].plevels[k] = StringToDouble(splittedLevels[k]);
               else
                  g_pos[i].plevels[k] = 0.0;
            }

            g_pos[i].be_done = (StringToInteger(FileReadString(h)) == 1);
            g_pos[i].shot_on_open_done = (StringToInteger(FileReadString(h)) == 1);
            g_pos[i].open_shot_file = FileReadString(h);
            g_pos[i].is_pending = (StringToInteger(FileReadString(h)) == 1);
         }
         FileClose(h);
      }
   }
   return true;
}

//+------------------------------------------------------------------+
//| UI Graphic Object Helpers                                          |
//+------------------------------------------------------------------+
void CreateUIRect(const string name, int x, int y, int w, int h, color bg, color border)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 0);
}

void CreateUIBtn(const string name, int x, int y, int w, int h, string text, color bg, color txtCol, int fSize)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, txtCol);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fSize);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 10);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI");
}

void CreateUIEdit(const string name, int x, int y, int w, int h, string text, int fSize, int align)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, CLR_INPUT_BG);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, CLR_BORDER);
   ObjectSetInteger(0, name, OBJPROP_ALIGN, align);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fSize);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 10);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI");
}

void CreateUILabel(const string name, int x, int y, string text, color col, int fSize)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fSize);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 10);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI");
}

void ReadEdits()
{
   if(g_is_sim) g_speed = (int)MathMax(1, EditNum(UI + "ED_SPEED"));
}

double EditNum(const string name)
{
   return StringToDouble(ObjectGetString(0, name, OBJPROP_TEXT));
}
//+------------------------------------------------------------------+