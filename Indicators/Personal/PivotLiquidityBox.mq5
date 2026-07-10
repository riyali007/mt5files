//+------------------------------------------------------------------+
//|                                     MTFWickBoxes_Indicator.mq5   |
//|                                  Converted to Clean Indicator    |
//|                                                Version 2.65      |
//+------------------------------------------------------------------+
#property copyright "MTF Wick Boxes Indicator v2.65"
#property version   "2.65"
#property strict
#property indicator_chart_window
#property indicator_plots 0 // No standard buffers, we use graphical objects

// --- Indicator Inputs ---
input ENUM_TIMEFRAMES HigherTimeframe = PERIOD_M15; // HTF Timeframe
input int PivotLeftBars = 5; // Pivot Left Bars
input int PivotRightBars = 5; // Pivot Right Bars
input int MaxBoxesPerType = 10; // Max Boxes per Type
input int WickOffsetPercent = 50; // Offset of the wick
input double MinimumWickSize = 0.5; // Minimum Wick Before Taking full candle
input int RemoveBrokenAfterMinutes = 30; // Remove broken after minutes
input bool UseFullCandle = false; // Use Full Candle

// --- Colors ---
input color SellZoneColor = C'242,54,69'; // Sell Zone (High Wick) Color
input color BuyZoneColor = C'8,153,129'; // Buy Zone (Low Wick) Color
input color MitigatedZoneColor = C'128,128,128'; // Mitigated Zone Color
input color BoxBorderColor = C'204,204,204'; // Box Border Color
input color MitigatedBorderColor = C'128,128,128'; // Mitigated Border Color

// --- Alerts & Labels ---
input bool EnableSoundAlerts = true; // Enable Level Sound Alerts
input string AlertSoundTop = "alert.wav"; // Alert Sound File (Top Level)
input string AlertSoundMid = "tick.wav"; // Alert Sound File (Mid Level)
input string AlertSoundBottom = "timeout.wav"; // Alert Sound File (Bottom Level)
input bool ShowZoneLabels = true; // Show Zone Values Text
input color SellLabelColor = clrWhite; // Sell Zone Text Color
input color BuyLabelColor = clrWhite; // Buy Zone Text Color

// --- Structures ---
struct PivotBox { 
    string boxName; 
    string lineName; 
    string textName;
    double top; 
    double bottom; 
    double mid; 
    datetime startTime; 
    bool isHigh; 
    bool isBroken; 
    datetime brokenAt; 
    bool alertTop;
    bool alertMid;
    bool alertBottom;
};

// --- Global Variables ---
PivotBox PivotHighBoxes[];
PivotBox PivotLowBoxes[];
datetime LastHTFProcessedTime = 0;
datetime LastBarProcessedTime = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit() {
    ArrayResize(PivotHighBoxes, 0); 
    ArrayResize(PivotLowBoxes, 0);
    
    // Historical Scan (Capped to 5000 bars to prevent instant-load freezing)
    int totalBars = iBars(_Symbol, HigherTimeframe);
    int limit = MathMin(totalBars - PivotLeftBars - 1, 5000);
    
    for(int i = limit; i >= PivotRightBars; i--) { 
        if(IsPivotHighBox(i)) AddPivotBox(i, true); 
        if(IsPivotLowBox(i)) AddPivotBox(i, false); 
    }
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    for(int i = 0; i < ArraySize(PivotHighBoxes); i++) { 
        ObjectDelete(0, PivotHighBoxes[i].boxName); 
        ObjectDelete(0, PivotHighBoxes[i].lineName); 
        ObjectDelete(0, PivotHighBoxes[i].textName); 
    }
    for(int i = 0; i < ArraySize(PivotLowBoxes); i++) { 
        ObjectDelete(0, PivotLowBoxes[i].boxName); 
        ObjectDelete(0, PivotLowBoxes[i].lineName); 
        ObjectDelete(0, PivotLowBoxes[i].textName); 
    }
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
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
                const int &spread[]) {
                
    // Check for new Pivot points on the Higher Timeframe
    datetime currHTF = iTime(_Symbol, HigherTimeframe, PivotRightBars);
    if(currHTF != LastHTFProcessedTime && LastHTFProcessedTime != 0) { 
        if(IsPivotHighBox(PivotRightBars)) AddPivotBox(PivotRightBars, true); 
        if(IsPivotLowBox(PivotRightBars)) AddPivotBox(PivotRightBars, false); 
    }
    LastHTFProcessedTime = currHTF;
    
    // Check current timeframe for box mitigation and extension
    datetime currBar = iTime(_Symbol, PERIOD_CURRENT, 0);
    if(currBar != LastBarProcessedTime && LastBarProcessedTime != 0) {
        double c = iClose(_Symbol, PERIOD_CURRENT, 1); 
        double h = iHigh(_Symbol, PERIOD_CURRENT, 1);
        double l = iLow(_Symbol, PERIOD_CURRENT, 1);
        datetime t = iTime(_Symbol, PERIOD_CURRENT, 1); 
        
        // --- Process Sell Boxes (High Pivots) ---
        for(int i = 0; i < ArraySize(PivotHighBoxes); i++) {
            if(!PivotHighBoxes[i].isBroken) {
                if(c > PivotHighBoxes[i].top) { 
                    // Box Broken
                    PivotHighBoxes[i].isBroken = true; 
                    PivotHighBoxes[i].brokenAt = t; 
                    ObjectSetInteger(0, PivotHighBoxes[i].boxName, OBJPROP_BGCOLOR, MitigatedZoneColor); 
                    ObjectSetInteger(0, PivotHighBoxes[i].boxName, OBJPROP_COLOR, MitigatedBorderColor); 
                    ObjectSetInteger(0, PivotHighBoxes[i].boxName, OBJPROP_TIME, 1, t); 
                    
                    // DELETE the mid line and text when mitigated
                    ObjectDelete(0, PivotHighBoxes[i].lineName);
                    ObjectDelete(0, PivotHighBoxes[i].textName);
                } else if(EnableSoundAlerts) {
                    // Check Sound Alerts (Price goes above level but closes below)
                    if(!PivotHighBoxes[i].alertBottom && h > PivotHighBoxes[i].bottom && c < PivotHighBoxes[i].bottom) {
                        PivotHighBoxes[i].alertBottom = true; PlaySound(AlertSoundBottom);
                    }
                    if(!PivotHighBoxes[i].alertMid && h > PivotHighBoxes[i].mid && c < PivotHighBoxes[i].mid) {
                        PivotHighBoxes[i].alertMid = true; PlaySound(AlertSoundMid);
                    }
                    if(!PivotHighBoxes[i].alertTop && h > PivotHighBoxes[i].top && c < PivotHighBoxes[i].top) {
                        PivotHighBoxes[i].alertTop = true; PlaySound(AlertSoundTop);
                    }
                }
            }
        }
        
        // --- Process Buy Boxes (Low Pivots) ---
        for(int i = 0; i < ArraySize(PivotLowBoxes); i++) {
            if(!PivotLowBoxes[i].isBroken) {
                if(c < PivotLowBoxes[i].bottom) { 
                    // Box Broken
                    PivotLowBoxes[i].isBroken = true; 
                    PivotLowBoxes[i].brokenAt = t; 
                    ObjectSetInteger(0, PivotLowBoxes[i].boxName, OBJPROP_BGCOLOR, MitigatedZoneColor); 
                    ObjectSetInteger(0, PivotLowBoxes[i].boxName, OBJPROP_COLOR, MitigatedBorderColor); 
                    ObjectSetInteger(0, PivotLowBoxes[i].boxName, OBJPROP_TIME, 1, t); 
                    
                    // DELETE the mid line and text when mitigated
                    ObjectDelete(0, PivotLowBoxes[i].lineName);
                    ObjectDelete(0, PivotLowBoxes[i].textName);
                } else if(EnableSoundAlerts) {
                    // Check Sound Alerts (Price goes below level but closes above)
                    if(!PivotLowBoxes[i].alertTop && l < PivotLowBoxes[i].top && c > PivotLowBoxes[i].top) {
                        PivotLowBoxes[i].alertTop = true; PlaySound(AlertSoundTop);
                    }
                    if(!PivotLowBoxes[i].alertMid && l < PivotLowBoxes[i].mid && c > PivotLowBoxes[i].mid) {
                        PivotLowBoxes[i].alertMid = true; PlaySound(AlertSoundMid);
                    }
                    if(!PivotLowBoxes[i].alertBottom && l < PivotLowBoxes[i].bottom && c > PivotLowBoxes[i].bottom) {
                        PivotLowBoxes[i].alertBottom = true; PlaySound(AlertSoundBottom);
                    }
                }
            }
        }
    }
    LastBarProcessedTime = currBar;
    
    return(rates_total);
}

//+------------------------------------------------------------------+
//| Pivot Checks                                                     |
//+------------------------------------------------------------------+
bool IsPivotHighBox(int shift) {
    double p = iHigh(_Symbol, HigherTimeframe, shift);
    for(int i = 1; i <= PivotLeftBars; i++) if(iHigh(_Symbol, HigherTimeframe, shift + i) > p) return false;
    for(int i = 1; i <= PivotRightBars; i++) if(iHigh(_Symbol, HigherTimeframe, shift - i) >= p) return false;
    return true;
}

bool IsPivotLowBox(int shift) {
    double p = iLow(_Symbol, HigherTimeframe, shift);
    for(int i = 1; i <= PivotLeftBars; i++) if(iLow(_Symbol, HigherTimeframe, shift + i) < p) return false;
    for(int i = 1; i <= PivotRightBars; i++) if(iLow(_Symbol, HigherTimeframe, shift - i) <= p) return false;
    return true;
}

//+------------------------------------------------------------------+
//| Box Calculation & Management                                     |
//+------------------------------------------------------------------+
void AddPivotBox(int shift, bool isHigh) {
    double pTop = 0, pBottom = 0; 
    datetime pTime = iTime(_Symbol, HigherTimeframe, shift); 
    int currentTFShift = iBarShift(_Symbol, PERIOD_CURRENT, pTime);
    
    if(isHigh) {
        pTop = iHigh(_Symbol, HigherTimeframe, shift); 
        pBottom = UseFullCandle ? iLow(_Symbol, HigherTimeframe, shift) : MathMax(iOpen(_Symbol, HigherTimeframe, shift), iClose(_Symbol, HigherTimeframe, shift)); 
        double r = pTop - pBottom;
        
        if(r < MinimumWickSize) pBottom = iLow(_Symbol, HigherTimeframe, shift); 
        r = pTop - pBottom; 
        double off = r * (WickOffsetPercent / 100.0); 
        pTop += off; pBottom += off;
        
        PivotBox pb; 
        pb.isHigh = true; pb.top = pTop; pb.bottom = pBottom; pb.mid = (pTop + pBottom) / 2.0; 
        pb.startTime = pTime; pb.isBroken = false; pb.brokenAt = 0; 
        pb.boxName = "PHBOX_" + IntegerToString(pTime); pb.lineName = "PHLINE_" + IntegerToString(pTime);
        pb.textName = "PHTEXT_" + IntegerToString(pTime);
        pb.alertTop = false; pb.alertMid = false; pb.alertBottom = false;
        
        for(int j = currentTFShift - 1; j >= 1; j--) { 
            if(iClose(_Symbol, PERIOD_CURRENT, j) > pTop) { pb.isBroken = true; pb.brokenAt = iTime(_Symbol, PERIOD_CURRENT, j); break; } 
        }
        
        int size = ArraySize(PivotHighBoxes); 
        if(size >= MaxBoxesPerType) { 
            ObjectDelete(0, PivotHighBoxes[0].boxName); ObjectDelete(0, PivotHighBoxes[0].lineName); ObjectDelete(0, PivotHighBoxes[0].textName);
            for(int k = 0; k < size - 1; k++) PivotHighBoxes[k] = PivotHighBoxes[k + 1]; 
            ArrayResize(PivotHighBoxes, size); PivotHighBoxes[size - 1] = pb; 
        } else { 
            ArrayResize(PivotHighBoxes, size + 1); PivotHighBoxes[size] = pb; 
        }
        DrawBox(PivotHighBoxes[ArraySize(PivotHighBoxes) - 1]);
        
    } else {
        pTop = UseFullCandle ? iHigh(_Symbol, HigherTimeframe, shift) : MathMin(iOpen(_Symbol, HigherTimeframe, shift), iClose(_Symbol, HigherTimeframe, shift)); 
        pBottom = iLow(_Symbol, HigherTimeframe, shift); 
        double r = pTop - pBottom;
        
        if(r < MinimumWickSize) pTop = iHigh(_Symbol, HigherTimeframe, shift); 
        r = pTop - pBottom; 
        double off = r * (WickOffsetPercent / 100.0); 
        pTop -= off; pBottom -= off;
        
        PivotBox pb; 
        pb.isHigh = false; pb.top = pTop; pb.bottom = pBottom; pb.mid = (pTop + pBottom) / 2.0; 
        pb.startTime = pTime; pb.isBroken = false; pb.brokenAt = 0; 
        pb.boxName = "PLBOX_" + IntegerToString(pTime); pb.lineName = "PLLINE_" + IntegerToString(pTime);
        pb.textName = "PLTEXT_" + IntegerToString(pTime);
        pb.alertTop = false; pb.alertMid = false; pb.alertBottom = false;
        
        for(int j = currentTFShift - 1; j >= 1; j--) { 
            if(iClose(_Symbol, PERIOD_CURRENT, j) < pBottom) { pb.isBroken = true; pb.brokenAt = iTime(_Symbol, PERIOD_CURRENT, j); break; } 
        }
        
        int size = ArraySize(PivotLowBoxes); 
        if(size >= MaxBoxesPerType) { 
            ObjectDelete(0, PivotLowBoxes[0].boxName); ObjectDelete(0, PivotLowBoxes[0].lineName); ObjectDelete(0, PivotLowBoxes[0].textName);
            for(int k = 0; k < size - 1; k++) PivotLowBoxes[k] = PivotLowBoxes[k + 1]; 
            ArrayResize(PivotLowBoxes, size); PivotLowBoxes[size - 1] = pb; 
        } else { 
            ArrayResize(PivotLowBoxes, size + 1); PivotLowBoxes[size] = pb; 
        }
        DrawBox(PivotLowBoxes[ArraySize(PivotLowBoxes) - 1]);
    }
}

//+------------------------------------------------------------------+
//| Box & Label Drawing Function                                     |
//+------------------------------------------------------------------+
void DrawBox(PivotBox &pb) {
    color activeColor = pb.isBroken ? MitigatedZoneColor : (pb.isHigh ? SellZoneColor : BuyZoneColor); 
    color borderColor = pb.isBroken ? MitigatedBorderColor : (pb.isHigh ? SellZoneColor : BuyZoneColor); 
    color textColor = pb.isBroken ? MitigatedBorderColor : (pb.isHigh ? SellLabelColor : BuyLabelColor);
    
    // Performance fix: Project unbroken boxes 10 years into the future instead of constantly updating them
    datetime endTime = pb.isBroken ? pb.brokenAt : TimeCurrent() + PeriodSeconds(PERIOD_D1) * 3650; 
    
    // Draw Box
    ObjectCreate(0, pb.boxName, OBJ_RECTANGLE, 0, pb.startTime, pb.top, endTime, pb.bottom); 
    ObjectSetInteger(0, pb.boxName, OBJPROP_COLOR, borderColor); 
    ObjectSetInteger(0, pb.boxName, OBJPROP_BGCOLOR, activeColor); 
    ObjectSetInteger(0, pb.boxName, OBJPROP_FILL, true); 
    ObjectSetInteger(0, pb.boxName, OBJPROP_BACK, true);
    
    // Draw Midline
    ObjectCreate(0, pb.lineName, OBJ_TREND, 0, pb.startTime, pb.mid, endTime, pb.mid); 
    ObjectSetInteger(0, pb.lineName, OBJPROP_COLOR, pb.isBroken ? MitigatedBorderColor : clrWhite); 
    ObjectSetInteger(0, pb.lineName, OBJPROP_STYLE, STYLE_DASH); 
    ObjectSetInteger(0, pb.lineName, OBJPROP_RAY_RIGHT, false);
    
    // Draw Zone Value Label
    if(ShowZoneLabels) {
        string zonePrefix = pb.isHigh ? "Sell Zone (" : "Buy Zone (";
        string labelText = zonePrefix + DoubleToString(pb.bottom, _Digits) + " - " + DoubleToString(pb.top, _Digits) + ")";
        ObjectCreate(0, pb.textName, OBJ_TEXT, 0, pb.startTime, pb.isHigh ? pb.top : pb.bottom);
        ObjectSetString(0, pb.textName, OBJPROP_TEXT, labelText);
        ObjectSetInteger(0, pb.textName, OBJPROP_COLOR, textColor);
        ObjectSetInteger(0, pb.textName, OBJPROP_ANCHOR, pb.isHigh ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER);
        ObjectSetInteger(0, pb.textName, OBJPROP_BACK, false);
        ObjectSetInteger(0, pb.textName, OBJPROP_FONTSIZE, 9);
    }
}