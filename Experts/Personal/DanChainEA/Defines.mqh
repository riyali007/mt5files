//+------------------------------------------------------------------+
//|                                                      Defines.mqh |
//+------------------------------------------------------------------+
#property copyright "Professional MT5 Developer"

input group "===== Strategy Settings ====="
input int      InpRange        = 20;       
input double   InpSLPercent    = 2.0;      
input int      InpSLToBe       = 2;        
input string   InpCloseAfter   = "Never";  

input group "===== Take Profit Settings (%) ====="
input double   InpTP1          = 2.0;      
input double   InpTP2          = 4.0;      
input double   InpTP3          = 6.0;      
input double   InpTP4          = 10.0;     

input group "===== Visuals ====="
input bool     InpShowEntry    = true;     
input bool     InpShowLines    = true;     
input color    InpColBuy       = clrGreen; 
input color    InpColSell      = clrRed;
input color    InpColTP        = clrGray;

input group "===== Trading Settings ====="
input double   InpDefaultLot   = 0.1;      
input int      InpMagicNumber  = 123456;   
input int      InpSlippage     = 10;       
input double   InpDefaultPartial = 50.0;   

enum ENUM_EXECUTION_MODE {
   MODE_MARKET,
   MODE_PENDING
};

#define PREFIX "DT_EA_"
