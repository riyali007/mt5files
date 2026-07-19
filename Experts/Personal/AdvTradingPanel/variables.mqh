#ifndef ADVTP_VARIABLES_MQH
#define ADVTP_VARIABLES_MQH

#define APP_NAME "Advanced Trade Manager Pro"
#define APP_SHORT_NAME "ATP"
#define APP_VERSION "1.01"
#define PANEL_PREFIX "ATP_"

#define OBJ_BG PANEL_PREFIX + "BG"
#define OBJ_TITLE PANEL_PREFIX + "Title"
#define OBJ_STATUS PANEL_PREFIX + "Status"
#define OBJ_MKT PANEL_PREFIX + "BtnMkt"
#define OBJ_LIM PANEL_PREFIX + "BtnLim"
#define OBJ_PRICE PANEL_PREFIX + "EditPrice"
#define OBJ_BUY PANEL_PREFIX + "BtnBuy"
#define OBJ_SELL PANEL_PREFIX + "BtnSell"
#define OBJ_LOT PANEL_PREFIX + "EditLot"
#define OBJ_SLPTS PANEL_PREFIX + "EditSL"
#define OBJ_SLPRICE PANEL_PREFIX + "EditSLPrc"
#define OBJ_TPPTS PANEL_PREFIX + "EditTP"
#define OBJ_TPPRICE PANEL_PREFIX + "EditTPPrc"
#define OBJ_PARTS PANEL_PREFIX + "EditPart"
#define OBJ_PARTLINE PANEL_PREFIX + "PTLLine"
#define OBJ_RISK PANEL_PREFIX + "ValRisk"
#define OBJ_REWARD PANEL_PREFIX + "ValRew"
#define OBJ_VISUALIZE PANEL_PREFIX + "BtnVis"
#define OBJ_MESSAGE PANEL_PREFIX + "Message"
#define OBJ_SEL_PREV PANEL_PREFIX + "BtnSelPrev"
#define OBJ_SEL_NEXT PANEL_PREFIX + "BtnSelNext"
#define OBJ_SELECTED PANEL_PREFIX + "LblSelected"
#define OBJ_MANPART PANEL_PREFIX + "EditManPart"
#define OBJ_PARTIAL_SEL PANEL_PREFIX + "BtnPartSel"
#define OBJ_BE_SEL PANEL_PREFIX + "BtnBESel"
#define OBJ_DEV_TOGGLE PANEL_PREFIX + "BtnDevToggle"
#define OBJ_DEV_TP1 PANEL_PREFIX + "BtnDevTP1"
#define OBJ_DEV_NEXT PANEL_PREFIX + "BtnDevNext"
#define OBJ_DEV_BE PANEL_PREFIX + "BtnDevBE"
#define OBJ_DEV_STATUS PANEL_PREFIX + "LblDevStatus"
#define OBJ_CLOSE_SEL PANEL_PREFIX + "BtnCloseSel"
#define OBJ_CLOSE_ALL PANEL_PREFIX + "BtnCloseAll"
#define OBJ_ADOPT_SEL PANEL_PREFIX + "BtnAdoptSel"
#define OBJ_EXT_STATUS PANEL_PREFIX + "LblExtStatus"
#define OBJ_EXT_PREV PANEL_PREFIX + "BtnExtPrev"
#define OBJ_EXT_NEXT PANEL_PREFIX + "BtnExtNext"

#define PLAN_PREFIX PANEL_PREFIX + "PLAN_"

enum ENUM_ATP_ACTION_STATE
{
   ATP_ACTION_NONE = 0,
   ATP_ACTION_PARTIAL_PENDING,
   ATP_ACTION_BE_PENDING,
   ATP_ACTION_CLOSE_PENDING,
   ATP_ACTION_TRAILING_STOP_PENDING
};

enum ENUM_ATP_ORDER_MODE
{
   ATP_ORDER_MARKET = 0,
   ATP_ORDER_LIMIT = 1
};

struct TradeState
{
   ulong ticket;
   string symbol;
   long position_type;
   double original_volume;
   double current_volume;
   double entry_price;
   double stop_loss;
   double take_profit;
   datetime open_time;
   int partial_count;
   bool partial_done[];
   double partial_prices[];
   int pending_partial_index;
   double pending_volume_before;
   double pending_expected_close;
   bool be_applied;
   double pending_be_price;
   
   bool trailing_stop_active;
   double pending_trailing_stop_price;
   bool is_external;
   bool is_adopted;
   bool recovered_from_storage;
   datetime last_persist_time;
   
   ENUM_ATP_ACTION_STATE pending_action;
};

struct TradePlan
{
   bool valid;
   ENUM_ATP_ORDER_MODE mode;
   ENUM_ORDER_TYPE order_type;
   string symbol;
   double volume;
   double entry;
   double sl;
   double tp;
   int sl_points;
   int tp_points;
   int partial_count;
   double partial_prices[];
   double risk_money;
   double reward_money;
};

// Deferred BREAKEVEN journal/webhook (avoid clashing with PARTIAL WebRequest)
#define ATP_MAX_DEFERRED_BE 16

struct DeferredBEJournal
{
   bool     active;
   datetime due_time;
   ulong    ticket;
   int      state_index;   // may go stale; ticket is source of truth
   double   be_price;
   string   source;
};

DeferredBEJournal g_DeferredBEJournals[];

TradeState g_TradeStates[];
TradePlan g_CurrentPlan;

bool g_HasManagedTrades = false;
bool g_PanelDirty = true;
bool g_RegistryDirty = false;
bool g_IsHedgingAccount = false;
bool g_PreviewVisible = false;
bool g_IsEditingPrice = false;

ENUM_ATP_ORDER_MODE g_OrderMode = ATP_ORDER_MARKET;
ENUM_ORDER_TYPE g_PlanDirection = ORDER_TYPE_BUY;

double g_Bid = 0.0;
double g_Ask = 0.0;
double g_PlanPrice = 0.0;
double g_PlanLot = 0.0;
int g_PlanSLPoints = 0;
int g_PlanTPPoints = 0;
int g_PlanPartialCount = 0;

ulong g_LastFastRunMs = 0;
ulong g_LastSlowRunMs = 0;
ulong g_LastRegistryReconcileMs = 0;

ulong g_SelectedTicket = 0;
int g_SelectedTicketIndex = -1;
double g_ManualPartialPercent = 0.0;
bool g_DeveloperTestMode = false;
int g_PanelScreenshotShiftX = 0;
bool g_PanelMovedForScreenshot = false;

ulong g_DetectedExternalTickets[];
int g_SelectedExternalIndex = -1;
ulong g_SelectedExternalTicket = 0;
string g_LastExternalAlertKey = "";

bool g_N8nWebhookReady = false;
datetime g_N8nLastFailureLogTime = 0;

#endif