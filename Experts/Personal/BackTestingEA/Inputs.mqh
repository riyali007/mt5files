//+------------------------------------------------------------------+
//|  Inputs.mqh  —  All input parameters for BacktestORB EA         |
//+------------------------------------------------------------------+
#ifndef INPUTS_MQH
#define INPUTS_MQH

//=== BACKTEST BRIDGE INPUTS ====================================
input double InpLotSize       = 0.10;
input int    InpSL            = 200;
input int    InpTotalTP       = 400;
input int    InpTPLevels      = 3;
input int    InpDeviation     = 50;
input string InpPipeName      = "\\\\.\\pipe\\AIVBacktest";

input bool   InpAutoPartials  = true;
input int    InpBEAfterLevel  = 1;
input int    InpBEOffsetPts   = 5;

input color  InpBearBoxColor     = C'234,84,85';
input color  InpBullBoxColor     = C'0,188,168';
input int    InpBoxOpacity       = 15;
input int    InpMinCandlesInBox  = 2;
input int    InpCandleLookback   = 20;

input ENUM_TIMEFRAMES InpPivotTimeframe   = PERIOD_M15;
input int             InpPivotLeftBars    = 5;
input int             InpPivotRightBars   = 5;
input int             InpPivotMaxLookback = 200;
input color           InpPivotHighColor   = C'234,84,85';
input color           InpPivotLowColor    = C'0,188,168';
input int             InpPivotLineWidth   = 2;
input ENUM_LINE_STYLE InpPivotLineStyle   = STYLE_SOLID;

//=== ORB INPUTS ================================================
input group "ORB — Time Settings"
input int    InpTimeOffset       = 0;

input group "ORB — Standard Sessions"
input bool   InpAsiaOn           = true;
input string InpAsiaTime         = "2000-0200";
input bool   InpLondonOn         = true;
input string InpLondonTime       = "0300-0800";
input bool   InpNYOn             = true;
input string InpNYTime           = "0930-1600";

input group "ORB — Custom Sessions"
input bool   InpCust1On          = false;
input string InpCust1Name        = "CUSTOM1";
input string InpCust1Time        = "1200-1400";
input bool   InpCust2On          = false;
input string InpCust2Name        = "CUSTOM2";
input string InpCust2Time        = "1800-2000";
input bool   InpCust3On          = false;
input string InpCust3Name        = "CUSTOM3";
input string InpCust3Time        = "2200-2300";

input group "ORB — Opening Range Settings"
input ENUM_TIMEFRAMES InpORBTimeframe = PERIOD_M30;

input group "ORB — RSI Filter"
input bool            InpUseRsiMaFilter = true;
input int             InpRsiPeriod      = 14;
input int             InpRsiMaPeriod    = 14;
input ENUM_MA_METHOD  InpRsiMaMethod    = MODE_SMA;

input group "ORB — Hammer Candle"
input bool   InpRequireHammer    = true;
input double InpHammerBodyPct    = 0.5;

input group "ORB — Signal Mode"
input bool   InpUseBCC           = false;

input group "ORB — Breakout Visuals"
input bool   InpShowBreakoutArrows = true;
input int    InpBuyArrowCode       = 233;
input int    InpSellArrowCode      = 234;
input color  InpBuyArrowColor      = clrLime;
input color  InpSellArrowColor     = clrRed;
input bool   InpShowPriceLabels    = true;
input bool   InpPlaySound          = false;
input string InpSoundFile          = "alert.wav";

input group "ORB — File Logging"
input bool   InpEnableFileLog    = false;
input string InpSignalFileName   = "ORB_Signals.txt";

input group "ORB — Visual Settings"
input color  InpBoxBgColor       = C'40,40,40';
input color  InpBoxBorder        = clrGray;
input color  InpBullColor        = clrGreen;
input color  InpBearColor        = clrRed;

input group "ORB — Spread Settings"
input bool            InpShowSpread   = true;
input color           InpSpreadColor  = clrOrange;
input ENUM_LINE_STYLE InpSpreadStyle  = STYLE_DOT;

input group "ORB — SMC Configuration"
input bool   InpUseSMC           = false;
input bool   InpShowFVG          = false;
input bool   InpShowOB           = false;
input bool   InpShowDead         = false;
input int    InpMaxHistory       = 2000;
input int    InpMaxVisible       = 50;

input group "ORB — FVG Colors"
input color  InpColor_FVG_Supp   = C'0,60,0';
input color  InpColor_FVG_Res    = C'60,0,0';
input color  InpColor_IFVG_Supp  = C'0,100,100';
input color  InpColor_IFVG_Res   = C'100,0,100';

input group "ORB — OB Colors"
input color  InpColor_OB_Supp    = C'0,50,0';
input color  InpColor_OB_Res     = C'50,0,0';
input color  InpColor_BB_Supp    = C'0,40,40';
input color  InpColor_BB_Res     = C'40,0,40';

#endif // INPUTS_MQH
