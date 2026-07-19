//+------------------------------------------------------------------+
//|                                                      Defines.mqh |
//+------------------------------------------------------------------+
#property strict

#define PANEL_WIDTH     260
#define PANEL_HEIGHT    850 
#define PREFIX_PREVIEW  "PREV_"

// --- IDS ---
#define ID_BTN_MODE      101
#define ID_BTN_BUY       102
#define ID_BTN_SELL      103
#define ID_BTN_TOGGLE    104
#define ID_BTN_CLOSE     105

#define ID_EDIT_RISK     106 
#define ID_EDIT_PRICE    107
#define ID_EDIT_SL_PCT   108 
#define ID_EDIT_TP_PCT   109 
#define ID_EDIT_PART_LOT 115 

#define ID_BTN_TAKE_PART 116
#define ID_BTN_SET_BE    117
#define ID_BTN_EXPORT    118 

// --- NEW IDs for Log Navigation ---
#define ID_BTN_LOG_PREV  801
#define ID_BTN_LOG_NEXT  802


// Partial Buttons
#define ID_BTN_P1        119
#define ID_BTN_P2        120
#define ID_BTN_P3        121

#define ID_BTN_PREVIEW   128 
#define ID_BTN_EXECUTE   129 

// AI Controls
#define ID_BTN_AI_SCAN   130 
#define ID_BTN_AI_AUTO   131 
#define ID_LBL_AI_STATUS 132 
#define ID_LBL_AI_RESULT 133 

// Log Row Bases
#define ID_LOG_ROW_BASE  200  // Small Status Log
#define ID_RAW_ROW_BASE  300  // NEW: Large Raw Log Rows

// Colors
#define CLR_BTN_MARKET  clrTeal
#define CLR_BTN_PENDING clrRoyalBlue
#define CLR_BG_EDIT     clrWhite
#define CLR_TXT_EDIT    clrBlack
#define CLR_BTN_PARTIAL C'0,100,200'
#define CLR_BTN_OFF     clrLightGray 
#define CLR_BTN_ON_PREV C'255,140,0'

#define CLR_PART_BUY    C'135,206,250' 
#define CLR_PART_SELL   C'255,140,0'   

#define CLR_AI_ON        clrLimeGreen
#define CLR_AI_OFF       clrRed
#define CLR_AI_AUTO_ON   clrDodgerBlue

// --- ENUMS ---
enum ENUM_DIR_STATE { DIR_NONE=0, DIR_BUY=1, DIR_SELL=2 };
enum ENUM_TRAIL_MODE { TRAIL_NONE=0, TRAIL_HARD_ONLY=1, TRAIL_TICK_ONLY=2, TRAIL_HYBRID=3 };
enum ENUM_PARTIAL_MODE { MODE_PERCENT=0, MODE_POINTS=1 };

enum ENUM_AI_PROVIDER {
   PROVIDER_GEMINI = 0,       
   PROVIDER_OPENROUTER = 1,   
   PROVIDER_OLLAMA = 2        
};

struct SPartialRequest
  {
   ulong    transactionId;
   int      partialId;
   string   partialLineId;
   double   targetPrice;   
   double   volPercent;    
   bool     isTaken;
   ENUM_POSITION_TYPE type;
  };