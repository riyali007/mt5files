//+------------------------------------------------------------------+
//|                                             Riyali_Pattern_EA.mq5|
//|                                            Translated from Pine v6|
//+------------------------------------------------------------------+
#property copyright "Translated by Gemini"
#property version   "1.30"

#include <Trade\Trade.mqh>

//--- Inputs
sinput string  grp_mt = "--- Multi-Timeframe Settings ---";
input bool     UseHigherTF = false;        // Set to FALSE for standard testing first
input ENUM_TIMEFRAMES HigherTF = PERIOD_H4; 

sinput string  grp_strategy = "--- Strategy Parameters ---";
input double   RiskPercent = 1.0;          
input bool     UseStopLoss = true;
input double   StopLossPercent = 2.0;      
input bool     UseTakeProfit = true;
input double   TakeProfitPercent = 4.0;    

sinput string  grp_filters = "--- Filters ---";
input int      RsiLength = 14;             
// IMPORTANT: Use 0.0010 for Forex, use 1.0 for Stocks/Crypto
input double   MinDojiBodySize = 0.0010;   // Doji Max Body (in actual price)
input double   MinCandleBodySize = 0.0020; // Min Body for Signals (in actual price)

input ulong    MagicNumber = 123456;       

//--- Global Variables
CTrade         trade;
int            rsiHandle;
double         rsiBuffer[];
datetime       lastBarTime;

int OnInit()
{
    trade.SetExpertMagicNumber(MagicNumber);
    ENUM_TIMEFRAMES activeTF = UseHigherTF ? HigherTF : _Period;
    rsiHandle = iRSI(_Symbol, activeTF, RsiLength, PRICE_CLOSE);
    
    if(rsiHandle == INVALID_HANDLE) return(INIT_FAILED);
    ArraySetAsSeries(rsiBuffer, true);
    
    // Draw initial test label so you know it's working
    DrawLabel("EA STARTED HERE", iTime(_Symbol, _Period, 0), iLow(_Symbol, _Period, 0), clrYellow, true);
    return(INIT_SUCCEEDED);
}

void DrawLabel(string text, datetime time, double price, color clr, bool isBuy)
{
    string objName = "Label_" + TimeToString(time) + "_" + text;
    ObjectCreate(0, objName, OBJ_TEXT, 0, time, price);
    ObjectSetString(0, objName, OBJPROP_TEXT, text);
    ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(0, objName, OBJPROP_ANCHOR, isBuy ? ANCHOR_TOP : ANCHOR_BOTTOM);
}

void OnTick()
{
    datetime currentBarTime = iTime(_Symbol, _Period, 0);
    if(currentBarTime == lastBarTime || currentBarTime == 0) return; 
    lastBarTime = currentBarTime; 
    
    ENUM_TIMEFRAMES tf = UseHigherTF ? HigherTF : _Period;
    if(CopyBuffer(rsiHandle, 0, 0, 5, rsiBuffer) <= 0) return;

    // -- Live Dashboard --
    string dashboard = "=== EA IS RUNNING ===\n";
    dashboard += "Timeframe Checked: " + EnumToString(tf) + "\n";
    dashboard += StringFormat("Candle 1 Body Size: %.5f\n", GetBody(1, tf));
    dashboard += StringFormat("Is Candle 1 a Doji? %s\n", IsDoji(1, tf) ? "YES (Signals Blocked)" : "NO (Valid)");
    dashboard += StringFormat("Candle 1 RSI: %.2f\n", rsiBuffer[1]);
    Comment(dashboard); // Prints to top-left of chart

    // Sell Patterns 
    bool sellC1 = IsBull(3, tf) && IsBull(2, tf) && IsBear(1, tf) && !IsDoji(3, tf) && !IsDoji(2, tf) && !IsDoji(1, tf);
    bool sellC2 = IsBull(4, tf) && IsBull(3, tf) && IsBull(2, tf) && IsBear(1, tf) && !IsDoji(2, tf) && !IsDoji(1, tf) && 
                  (C(1, tf) >= L(2, tf)) && (GetBody(1, tf) > MinCandleBodySize) && (GetUpperWick(1, tf) > 0);
    bool sellC3 = IsEngulfing(1, tf) && IsBear(1, tf) && IsBull(2, tf) && (GetBody(1, tf) > MinCandleBodySize * 2) && 
                  (rsiBuffer[1] >= 60 || rsiBuffer[2] >= 65) && (GetUpperWick(1, tf) > 0);
    bool sellC4 = IsBull(3, tf) && IsBull(2, tf) && IsBear(1, tf) && (GetBody(1, tf) > MinCandleBodySize * 2) && 
                  (rsiBuffer[1] >= 70 || rsiBuffer[2] >= 70) && (GetUpperWick(1, tf) > 0);

    // Buy Patterns
    bool buyC1 = IsBear(3, tf) && IsBear(2, tf) && IsBull(1, tf) && !IsDoji(3, tf) && !IsDoji(2, tf) && !IsDoji(1, tf);
    bool buyC2 = IsBear(4, tf) && IsBear(3, tf) && IsBear(2, tf) && IsBull(1, tf) && !IsDoji(2, tf) && !IsDoji(1, tf) && 
                 (C(1, tf) <= H(2, tf)) && (GetBody(1, tf) > MinCandleBodySize) && (GetLowerWick(1, tf) > 0);
    bool buyC3 = IsEngulfing(1, tf) && IsBull(1, tf) && IsBear(2, tf) && (GetBody(1, tf) > MinCandleBodySize * 2) && 
                 (rsiBuffer[1] <= 40 || rsiBuffer[2] <= 35) && (GetLowerWick(1, tf) > 0);
    bool buyC4 = IsBear(3, tf) && IsBear(2, tf) && IsBull(1, tf) && (GetBody(1, tf) > MinCandleBodySize * 2) && 
                 (rsiBuffer[1] <= 30 || rsiBuffer[2] <= 25) && (GetLowerWick(1, tf) > 0);

    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    datetime drawTime = iTime(_Symbol, tf, 1); 

    // --- DRAW LABELS ---
    string labelText = "";
    double buySL = UseStopLoss ? NormalizeDouble(L(2, tf) * (1 - StopLossPercent / 100.0), _Digits) : 0;
    if(buyC4) labelText = "BUY 4"; else if(buyC3) labelText = "BUY 3"; else if(buyC2) labelText = "BUY 2"; else if(buyC1) labelText = "BUY 1";
    if(labelText != "") DrawLabel(labelText, drawTime, L(1, tf) - (100 * _Point), clrLimeGreen, true);
    
    labelText = "";
    double sellSL = UseStopLoss ? NormalizeDouble(H(2, tf) * (1 + StopLossPercent / 100.0), _Digits) : 0;
    if(sellC4) labelText = "SELL 4"; else if(sellC3) labelText = "SELL 3"; else if(sellC2) labelText = "SELL 2"; else if(sellC1) labelText = "SELL 1";
    if(labelText != "") DrawLabel(labelText, drawTime, H(1, tf) + (100 * _Point), clrRed, false);

    // --- EXECUTION ---
    bool longSignal = (buyC1 || buyC2 || buyC3 || buyC4);
    bool shortSignal = (sellC1 || sellC2 || sellC3 || sellC4);

    if(!longSignal && !shortSignal) return; 
    if(PositionsTotal() > 0) return; 
    
    if(longSignal) {
        double tp = UseTakeProfit ? NormalizeDouble(ask * (1 + TakeProfitPercent / 100.0), _Digits) : 0;
        trade.Buy(0.01, _Symbol, ask, buySL, tp, "Pattern Buy");
    }
    else if(shortSignal) {
        double tp = UseTakeProfit ? NormalizeDouble(bid * (1 - TakeProfitPercent / 100.0), _Digits) : 0;
        trade.Sell(0.01, _Symbol, bid, sellSL, tp, "Pattern Sell");
    }
}

//+------------------------------------------------------------------+
//| Candlestick Math                                                 |
//+------------------------------------------------------------------+
double O(int i, ENUM_TIMEFRAMES tf) { return iOpen(_Symbol, tf, i); }
double C(int i, ENUM_TIMEFRAMES tf) { return iClose(_Symbol, tf, i); }
double H(int i, ENUM_TIMEFRAMES tf) { return iHigh(_Symbol, tf, i); }
double L(int i, ENUM_TIMEFRAMES tf) { return iLow(_Symbol, tf, i); }
bool IsBull(int i, ENUM_TIMEFRAMES tf) { return C(i, tf) > O(i, tf); }
bool IsBear(int i, ENUM_TIMEFRAMES tf) { return C(i, tf) < O(i, tf); }
double GetBody(int i, ENUM_TIMEFRAMES tf) { return MathMax(O(i, tf), C(i, tf)) - MathMin(O(i, tf), C(i, tf)); }
double GetFullCandle(int i, ENUM_TIMEFRAMES tf) { return H(i, tf) - L(i, tf); }
bool IsDoji(int i, ENUM_TIMEFRAMES tf) { return GetBody(i, tf) < MinDojiBodySize; }
bool IsEngulfing(int i, ENUM_TIMEFRAMES tf) { return GetFullCandle(i, tf) > GetFullCandle(i+1, tf); }
double GetUpperWick(int i, ENUM_TIMEFRAMES tf) { return H(i, tf) - MathMax(C(i, tf), O(i, tf)); }
double GetLowerWick(int i, ENUM_TIMEFRAMES tf) { return MathMin(C(i, tf), O(i, tf)) - L(i, tf); }