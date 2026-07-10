//+------------------------------------------------------------------+
//|                                     Riy_Professional_ORB_SMC.mq5 |
//|                                      Converted from Pine Script  |
//|                         Fixed: Flicker, FVG Start, Smart Logic   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Gemini AI"
#property link      "https://www.mql5.com"
#property version   "6.00"
#property indicator_chart_window
#property indicator_buffers 8 
#property indicator_plots   0
#property indicator_type1   DRAW_NONE

// --- INPUTS ---
input group "Time Settings"
input int    InpTimeOffset    = 0;         // Server Time Offset (Hours)

input group "Standard Sessions"
input bool   InpAsiaOn        = true;      // Show Asia Session
input string InpAsiaTime      = "2000-0200"; // Asia Session (HHMM-HHMM)
input bool   InpLondonOn      = true;      // Show London Session
input string InpLondonTime    = "0300-0800"; // London Session (HHMM-HHMM)
input bool   InpNYOn          = true;      // Show NY Session
input string InpNYTime        = "0930-1600"; // NY Session (HHMM-HHMM)

input group "Custom Sessions"
input bool   InpCust1On       = false;     // Show Custom Session 1
input string InpCust1Name     = "CUSTOM1"; // Custom 1 Name
input string InpCust1Time     = "1200-1400"; // Custom 1 Time (HHMM-HHMM)
input bool   InpCust2On       = false;     // Show Custom Session 2
input string InpCust2Name     = "CUSTOM2"; // Custom 2 Name
input string InpCust2Time     = "1800-2000"; // Custom 2 Time (HHMM-HHMM)
input bool   InpCust3On       = false;     // Show Custom Session 3
input string InpCust3Name     = "CUSTOM3"; // Custom 3 Name
input string InpCust3Time     = "2200-2300"; // Custom 3 Time (HHMM-HHMM)

input group "Opening Range Settings"
input ENUM_TIMEFRAMES InpORBTimeframe = PERIOD_M30; // ORB Period (Range Duration)

input group "Visual Settings"
input bool   InpShowBreakOuts = false;     // Show Breakout text?
input color  InpBoxBgColor    = C'40,40,40'; // ORB Box Color (Dark Gray)
input color  InpBoxBorder     = clrGray;   // ORB Border Color
input color  InpBullColor     = clrGreen;  // ORB Bullish Line
input color  InpBearColor     = clrRed;    // ORB Bearish Line

input group "Spread Settings"
input bool   InpShowSpread    = true;            // Show Spread Lines?
input color  InpSpreadColor   = clrOrange;       // Spread Line Color
input ENUM_LINE_STYLE InpSpreadStyle = STYLE_DOT; // Spread Line Style

input group "SMC Configuration"
input bool   InpUseSMC        = true;      // Master SMC Switch
input bool   InpShowFVG       = true;      // Show Fair Value Gaps
input bool   InpShowOB        = true;      // Show Order Blocks
input bool   InpShowDead      = false;     // Show Dead/Killed Zones?
input int    InpMaxHistory    = 2000;      // Max Bars to Scan
input int    InpMaxVisible    = 50;        // Max Active Zones

input group "FVG Colors (Dark Mode)"
// Colors lightened slightly to ensure visibility on black backgrounds
input color  InpColor_FVG_Supp = C'0,60,0';      // Bull FVG (Dark Green)
input color  InpColor_FVG_Res  = C'60,0,0';      // Bear FVG (Dark Red)
input color  InpColor_IFVG_Supp = C'0,100,100';  // IFVG Support (Cyan-ish)
input color  InpColor_IFVG_Res  = C'100,0,100';  // IFVG Resistance (Magenta-ish)

input group "OB Colors (Dark Mode)"
input color  InpColor_OB_Supp  = C'0,50,0';      // Bull OB (Darker Green)
input color  InpColor_OB_Res   = C'50,0,0';      // Bear OB (Darker Red)
input color  InpColor_BB_Supp  = C'0,40,40';     // Breaker Support 
input color  InpColor_BB_Res   = C'40,0,40';     // Breaker Resistance 

// --- BUFFERS ---
double BufferSessHigh[];
double BufferSessLow[];
double BufferOrbHigh[];
double BufferOrbLow[];
double BufferOrbActive[];
double BufferBreakUp[];
double BufferBreakDn[];
double BufferSessStart[];

// --- STRUCTURES ---
struct SessionTimes {
    int startHour;
    int startMin;
    int endHour;
    int endMin;
    bool crossesMidnight;
};

enum ZoneState {
    STATE_FRESH,
    STATE_MITIGATED, // Touched by wick but holding
    STATE_INVERTED,  // Broken by Close (Flipped)
    STATE_DEAD       // Killed by Close after inversion
};

class CSMCZone {
public:
    string   name;
    datetime tStart;
    datetime tEnd;
    double   top;
    double   bottom;
    int      origType; // 1=Bull, -1=Bear (Original Direction)
    int      currType; // 1=Support, -1=Resistance (Current Role)
    int      mode;     // 0=FVG, 1=OB
    ZoneState state;
    
    CSMCZone() { state = STATE_FRESH; }
};

// --- GLOBALS ---
SessionTimes asiaSess, londonSess, nySess;
SessionTimes cust1Sess, cust2Sess, cust3Sess;
int g_orbMins = 30; 
CSMCZone activeZones[]; 

// --- FORWARD DECLARATIONS ---
void ParseSession(string timeStr, SessionTimes &sess);
bool IsInSession(datetime time, SessionTimes &sess, int offset);
void DrawBox(string name, datetime t1, double p1, datetime t2, double p2, color border, color bg, int style, bool fill=true);
void DrawLine(string name, datetime t1, double p1, datetime t2, double p2, color clr, int style);
void DrawLabel(string name, datetime t, double p, string text, color clr, int anchor);
void ProcessSMC(const double &open[], const double &high[], const double &low[], const double &close[], const datetime &time[], int total);

//+------------------------------------------------------------------+
//| Custom Initialization                                            |
//+------------------------------------------------------------------+
int OnInit() {
    SetIndexBuffer(0, BufferSessHigh, INDICATOR_CALCULATIONS);
    SetIndexBuffer(1, BufferSessLow, INDICATOR_CALCULATIONS);
    SetIndexBuffer(2, BufferOrbHigh, INDICATOR_CALCULATIONS);
    SetIndexBuffer(3, BufferOrbLow, INDICATOR_CALCULATIONS);
    SetIndexBuffer(4, BufferOrbActive, INDICATOR_CALCULATIONS);
    SetIndexBuffer(5, BufferBreakUp, INDICATOR_CALCULATIONS);
    SetIndexBuffer(6, BufferBreakDn, INDICATOR_CALCULATIONS);
    SetIndexBuffer(7, BufferSessStart, INDICATOR_CALCULATIONS);

    ParseSession(InpAsiaTime, asiaSess);
    ParseSession(InpLondonTime, londonSess);
    ParseSession(InpNYTime, nySess);
    ParseSession(InpCust1Time, cust1Sess);
    ParseSession(InpCust2Time, cust2Sess);
    ParseSession(InpCust3Time, cust3Sess);

    g_orbMins = PeriodSeconds(InpORBTimeframe) / 60;
    if(g_orbMins == 0) g_orbMins = 30; 
    
    // Clear graphics only on init
    ObjectsDeleteAll(0, "RIY_");
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom Deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    ObjectsDeleteAll(0, "RIY_");
}

//+------------------------------------------------------------------+
//| Calculation Function                                             |
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

    // Set Series
    ArraySetAsSeries(time, true);
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(spread, true);
    
    ArraySetAsSeries(BufferSessHigh, true);
    ArraySetAsSeries(BufferSessLow, true);
    ArraySetAsSeries(BufferOrbHigh, true);
    ArraySetAsSeries(BufferOrbLow, true);
    ArraySetAsSeries(BufferOrbActive, true);
    ArraySetAsSeries(BufferBreakUp, true);
    ArraySetAsSeries(BufferBreakDn, true);
    ArraySetAsSeries(BufferSessStart, true);

    int limit = prev_calculated == 0 ? rates_total - 1 : rates_total - prev_calculated;

    // --- STANDARD ORB LOOP ---
    for (int i = limit; i >= 0; i--) {
        bool isAsia   = InpAsiaOn   && IsInSession(time[i], asiaSess, InpTimeOffset);
        bool isLondon = InpLondonOn && IsInSession(time[i], londonSess, InpTimeOffset);
        bool isNY     = InpNYOn     && IsInSession(time[i], nySess, InpTimeOffset);
        bool isCust1  = InpCust1On  && IsInSession(time[i], cust1Sess, InpTimeOffset);
        bool isCust2  = InpCust2On  && IsInSession(time[i], cust2Sess, InpTimeOffset);
        bool isCust3  = InpCust3On  && IsInSession(time[i], cust3Sess, InpTimeOffset);
        bool prevAsia   = (i < rates_total - 1) ? (InpAsiaOn   && IsInSession(time[i+1], asiaSess, InpTimeOffset)) : false;
        bool prevLondon = (i < rates_total - 1) ? (InpLondonOn && IsInSession(time[i+1], londonSess, InpTimeOffset)) : false;
        bool prevNY     = (i < rates_total - 1) ? (InpNYOn     && IsInSession(time[i+1], nySess, InpTimeOffset)) : false;
        bool prevCust1  = (i < rates_total - 1) ? (InpCust1On  && IsInSession(time[i+1], cust1Sess, InpTimeOffset)) : false;
        bool prevCust2  = (i < rates_total - 1) ? (InpCust2On  && IsInSession(time[i+1], cust2Sess, InpTimeOffset)) : false;
        bool prevCust3  = (i < rates_total - 1) ? (InpCust3On  && IsInSession(time[i+1], cust3Sess, InpTimeOffset)) : false;
        bool newAsia   = isAsia   && !prevAsia;
        bool newLondon = isLondon && !prevLondon;
        bool newNY     = isNY     && !prevNY;
        bool newCust1  = isCust1  && !prevCust1;
        bool newCust2  = isCust2  && !prevCust2;
        bool newCust3  = isCust3  && !prevCust3;

        bool newSess   = newAsia || newLondon || newNY || newCust1 || newCust2 || newCust3;

        string currentSessName = "";
        if(isAsia)        currentSessName = "ASIA";
        else if(isLondon) currentSessName = "LONDON";
        else if(isNY)     currentSessName = "NY";
        else if(isCust1)  currentSessName = InpCust1Name;
        else if(isCust2)  currentSessName = InpCust2Name;
        else if(isCust3)  currentSessName = InpCust3Name;

        double mySessHigh = high[i];
        double mySessLow  = low[i];
        double myOrbHigh  = high[i];
        double myOrbLow   = low[i];
        
        if(newSess) {
            BufferSessStart[i] = (double)time[i];
            mySessHigh = high[i];
            mySessLow  = low[i];
            myOrbHigh  = high[i];
            myOrbLow   = low[i];
        } else if(isAsia || isLondon || isNY || isCust1 || isCust2 || isCust3) {
            if(i < rates_total - 1) BufferSessStart[i] = BufferSessStart[i+1];
            if (i < rates_total - 1 && BufferSessHigh[i+1] != 0.0) {
                mySessHigh = MathMax(BufferSessHigh[i+1], high[i]);
                mySessLow  = MathMin(BufferSessLow[i+1], low[i]);
                
                int dur = (int)(time[i] - (datetime)BufferSessStart[i])/60;
                if(dur < g_orbMins) {
                   myOrbHigh = MathMax(BufferOrbHigh[i+1], high[i]);
                   myOrbLow  = MathMin(BufferOrbLow[i+1], low[i]);
                } else {
                   myOrbHigh = BufferOrbHigh[i+1];
                   myOrbLow  = BufferOrbLow[i+1];
                }
            }
        } else {
            if (i < rates_total - 1) {
                BufferSessStart[i] = BufferSessStart[i+1];
                mySessHigh = BufferSessHigh[i+1];
                mySessLow  = BufferSessLow[i+1];
                myOrbHigh  = BufferOrbHigh[i+1];
                myOrbLow   = BufferOrbLow[i+1];
            } else {
                BufferSessStart[i] = 0;
            }
        }
        
        datetime sessStart = (datetime)BufferSessStart[i];
        int durationMins = 0;
        if(sessStart > 0) durationMins = (int)(time[i] - sessStart) / 60;
        bool isOrbActive = (sessStart > 0) && (durationMins < g_orbMins);
        BufferOrbActive[i] = isOrbActive ? 1.0 : 0.0;

        int prevDurationMins = 9999;
        if(i < rates_total - 1 && BufferSessStart[i+1] == (double)sessStart) {
             prevDurationMins = (int)(time[i+1] - sessStart) / 60;
        }
        bool orbFinished = (sessStart > 0) && (durationMins >= g_orbMins) && (prevDurationMins < g_orbMins);
        
        BufferSessHigh[i] = mySessHigh;
        BufferSessLow[i]  = mySessLow;
        BufferOrbHigh[i]  = myOrbHigh;
        BufferOrbLow[i]   = myOrbLow;

        bool breakUp = false;
        bool breakDn = false;
        
        if (i < rates_total - 1) {
            if (close[i] > BufferOrbHigh[i] && close[i+1] <= BufferOrbHigh[i] && !isOrbActive && sessStart > 0) breakUp = true;
            if (close[i] < BufferOrbLow[i] && close[i+1] >= BufferOrbLow[i] && !isOrbActive && sessStart > 0) breakDn = true;
        }
        BufferBreakUp[i] = breakUp ? 1.0 : 0.0;
        BufferBreakDn[i] = breakDn ? 1.0 : 0.0;

        // DRAWING
        if (i > 1000) continue;
        string suffix = IntegerToString(sessStart); 
        double currentSpreadVal = spread[i] * _Point;

        if (isOrbActive) {
            string boxName = "RIY_ORBBox_" + suffix;
            DrawBox(boxName, sessStart, BufferOrbHigh[i], time[i], BufferOrbLow[i], InpBoxBorder, InpBoxBgColor, STYLE_DOT);
        }

        if (sessStart > 0) {
            string lineHighName = "RIY_SessHigh_" + suffix;
            string lineLowName  = "RIY_SessLow_" + suffix;
            string lblHighName  = "RIY_LblHigh_" + suffix;
            string lblLowName   = "RIY_LblLow_" + suffix;

            datetime endDrawTime = time[i];
            DrawLine(lineHighName, sessStart, BufferSessHigh[i], endDrawTime, BufferSessHigh[i], clrGray, STYLE_DASH);
            DrawLine(lineLowName, sessStart, BufferSessLow[i], endDrawTime, BufferSessLow[i], clrGray, STYLE_DASH);
            DrawLabel(lblHighName, endDrawTime, BufferSessHigh[i], currentSessName + " HIGH", clrGray, ANCHOR_LEFT);
            DrawLabel(lblLowName, endDrawTime, BufferSessLow[i], currentSessName + " LOW", clrGray, ANCHOR_LEFT);
        }

        if (orbFinished || (sessStart > 0 && durationMins >= g_orbMins)) {
            string orbLineHigh = "RIY_ORBLineH_" + suffix;
            string orbLineLow  = "RIY_ORBLineL_" + suffix;
            DrawLine(orbLineHigh, sessStart, BufferOrbHigh[i], time[i], BufferOrbHigh[i], InpBullColor, STYLE_SOLID);
            DrawLine(orbLineLow, sessStart, BufferOrbLow[i], time[i], BufferOrbLow[i], InpBearColor, STYLE_SOLID);

            if(InpShowSpread) {
                string spreadLineH = "RIY_SpreadH_" + suffix;
                string spreadLineL = "RIY_SpreadL_" + suffix;
                double spreadHigh = BufferOrbHigh[i] + currentSpreadVal;
                double spreadLow  = BufferOrbLow[i]  - currentSpreadVal;
                DrawLine(spreadLineH, sessStart, spreadHigh, time[i], spreadHigh, InpSpreadColor, InpSpreadStyle);
                DrawLine(spreadLineL, sessStart, spreadLow,  time[i], spreadLow,  InpSpreadColor, InpSpreadStyle);
            }
        }

        if (breakUp && InpShowBreakOuts) DrawLabel("RIY_BrkUp_" + IntegerToString(time[i]), time[i], high[i], "BREAK UP", InpBullColor, ANCHOR_BOTTOM);
        if (breakDn && InpShowBreakOuts) DrawLabel("RIY_BrkDn_" + IntegerToString(time[i]), time[i], low[i], "BREAK DOWN", InpBearColor, ANCHOR_TOP);
    }

    // --- SMC PROCESSING (FVG / OB) ---
    if(InpUseSMC) ProcessSMC(open, high, low, close, time, rates_total);
    
    return(rates_total);
}

//+------------------------------------------------------------------+
//| SMC Logic Implementation                                         |
//+------------------------------------------------------------------+
void ProcessSMC(const double &open[], const double &high[], const double &low[], const double &close[], const datetime &time[], int total) {
    
    // We clear array and re-simulate to ensure state consistency without complex persistence bugs
    // However, we DO NOT delete objects. We update them.
    ArrayResize(activeZones, 0);

    int startIdx = InpMaxHistory;
    if(startIdx >= total - 2) startIdx = total - 3;
    
    // Iterate from PAST to PRESENT to build lifecycle
    for(int i = startIdx; i >= 0; i--) {

        // A. DETECT FVG
        double fvgTop = 0, fvgBot = 0;
        int fvgType = 0; // 0=None, 1=Bull, -1=Bear
        
        if(InpShowFVG) {
            // Bull FVG (Gap Up)
            if(low[i] > high[i+2]) {
                 fvgTop = low[i];      // Upper Limit of Gap
                 fvgBot = high[i+2];   // Lower Limit of Gap
                 fvgType = 1;
            }
            // Bear FVG (Gap Down)
            else if(high[i] < low[i+2]) {
                 fvgTop = low[i+2];    // Upper Limit of Gap
                 fvgBot = high[i];     // Lower Limit of Gap
                 fvgType = -1;
            }

            if(fvgType != 0) {
                CSMCZone newZone;
                newZone.mode = 0; // FVG
                newZone.origType = fvgType;
                newZone.currType = fvgType; 
                newZone.top  = fvgTop;
                newZone.bottom = fvgBot;
                // FIX: FVG Start from i+2 (1st Candle) instead of i (3rd Candle)
                newZone.tStart = time[i+2]; 
                newZone.tEnd = time[i];
                newZone.name = "RIY_SMC_FVG_" + IntegerToString(time[i]);
                
                int s = ArraySize(activeZones);
                ArrayResize(activeZones, s+1);
                activeZones[s] = newZone;
            }
        }

        // B. DETECT OB
        if(InpShowOB && fvgType != 0) { 
            // Bull FVG -> Down Candle before it (i+2) is Bull OB
            if(fvgType == 1) { 
                if(close[i+2] < open[i+2]) { 
                    CSMCZone ob;
                    ob.mode = 1; // OB
                    ob.origType = 1; // Bull OB
                    ob.currType = 1;
                    ob.top  = high[i+2];
                    ob.bottom = low[i+2];
                    ob.tStart = time[i+2];
                    ob.tEnd = time[i];
                    ob.name = "RIY_SMC_OB_" + IntegerToString(time[i+2]);
                    int s = ArraySize(activeZones);
                    ArrayResize(activeZones, s+1);
                    activeZones[s] = ob;
                }
            }
            // Bear FVG -> Up Candle before it (i+2) is Bear OB
            else if(fvgType == -1) { 
                 if(close[i+2] > open[i+2]) { 
                    CSMCZone ob;
                    ob.mode = 1; // OB
                    ob.origType = -1; // Bear OB
                    ob.currType = -1;
                    ob.top  = high[i+2];
                    ob.bottom = low[i+2];
                    ob.tStart = time[i+2];
                    ob.tEnd = time[i];
                    ob.name = "RIY_SMC_OB_" + IntegerToString(time[i+2]);
                    int s = ArraySize(activeZones);
                    ArrayResize(activeZones, s+1);
                    activeZones[s] = ob;
                }
            }
        }

        // C. MANAGE EXISTING ZONES (LIFECYCLE)
        for(int k = 0; k < ArraySize(activeZones); k++) {
            if(activeZones[k].state == STATE_DEAD) continue;
            
            // Skip check if we are on the creation bar or older
            if(activeZones[k].tStart >= time[i]) continue;
            
            // Only update until current time
            if(time[i] < activeZones[k].tStart) continue; 

            double cHigh = high[i];
            double cLow  = low[i];
            double cClose = close[i];
            
            // ------------------------------------------
            // LOGIC FOR BULLISH ZONES (Support)
            // ------------------------------------------
            if(activeZones[k].currType == 1) {
                // If we are currently Support
                // Check for Inversion (Body Close Below)
                if(cClose < activeZones[k].bottom) {
                    if(activeZones[k].state != STATE_INVERTED) {
                        // FLIP TO RESISTANCE
                        activeZones[k].state = STATE_INVERTED;
                        activeZones[k].currType = -1; 
                        activeZones[k].name += "_INV";
                    } else {
                        // ALREADY INVERTED -> Check for DEAD
                        // It was flipped to resistance, now price closed ABOVE it (invalidating resistance)
                        // Wait... if it flipped to Resistance, it expects price to stay BELOW.
                        // So if price closes back ABOVE top, it is DEAD.
                        // OR if it continues down? 
                        // User request: "wait for BCC to close above or below the zone then stop continuing"
                        // Since it is now Resistance (Bearish), if close > top, it is killed.
                        // Also, if it continues plummeting away, it's fine.
                    }
                }
                else if(cLow < activeZones[k].top) {
                    if(activeZones[k].state == STATE_FRESH) activeZones[k].state = STATE_MITIGATED;
                }
            }
            // ------------------------------------------
            // LOGIC FOR BEARISH ZONES (Resistance)
            // ------------------------------------------
            else if(activeZones[k].currType == -1) {
                // If we are currently Resistance
                // Check for Inversion (Body Close Above)
                if(cClose > activeZones[k].top) {
                    if(activeZones[k].state != STATE_INVERTED) {
                        // FLIP TO SUPPORT
                        activeZones[k].state = STATE_INVERTED;
                        activeZones[k].currType = 1; 
                        activeZones[k].name += "_INV";
                    } else {
                        // ALREADY INVERTED
                    }
                }
                else if(cHigh > activeZones[k].bottom) {
                    if(activeZones[k].state == STATE_FRESH) activeZones[k].state = STATE_MITIGATED;
                }
            }

            // ------------------------------------------
            // DEAD CHECK (Specific User Request)
            // ------------------------------------------
            if(activeZones[k].state == STATE_INVERTED) {
                // "wait for BCC to close above or below the zone then stop continuing them"
                // If price leaves the zone completely, we kill it.
                if(cClose > activeZones[k].top || cClose < activeZones[k].bottom) {
                    activeZones[k].state = STATE_DEAD;
                }
            }
            
            // Extend if not dead
            if(activeZones[k].state != STATE_DEAD) {
                activeZones[k].tEnd = time[i];
            }
        }
    }

    // D. DRAW VISIBLE ZONES
    int drawnCount = 0;
    // Iterate Backwards (Newest Created First)
    for(int k = ArraySize(activeZones)-1; k >= 0; k--) {
        // Hide Dead zones unless requested
        if(activeZones[k].state == STATE_DEAD && !InpShowDead) continue;
        if(drawnCount >= InpMaxVisible) break;

        color bgClr = clrNONE;
        
        // --- COLOR LOGIC (Based on CURRENT Role) ---
        if(activeZones[k].mode == 0) { // FVG
             if(activeZones[k].currType == 1) { // Support 
                 if(activeZones[k].state == STATE_INVERTED) bgClr = InpColor_IFVG_Supp; 
                 else bgClr = InpColor_FVG_Supp;
             } else { // Resistance 
                 if(activeZones[k].state == STATE_INVERTED) bgClr = InpColor_IFVG_Res;
                 else bgClr = InpColor_FVG_Res;
             }
        } else { // OB
             if(activeZones[k].currType == 1) { // Support
                 if(activeZones[k].state == STATE_INVERTED) bgClr = InpColor_BB_Supp;
                 else bgClr = InpColor_OB_Supp;
             } else { // Resistance
                 if(activeZones[k].state == STATE_INVERTED) bgClr = InpColor_BB_Res;
                 else bgClr = InpColor_OB_Res;
             }
        }

        DrawBox(activeZones[k].name, activeZones[k].tStart, activeZones[k].top, activeZones[k].tEnd, activeZones[k].bottom, bgClr, bgClr, STYLE_SOLID, true);
        drawnCount++;
    }
}

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
void ParseSession(string timeStr, SessionTimes &sess) {
    string startStr = StringSubstr(timeStr, 0, 4);
    string endStr   = StringSubstr(timeStr, 5, 4);
    sess.startHour = (int)StringToInteger(StringSubstr(startStr, 0, 2));
    sess.startMin  = (int)StringToInteger(StringSubstr(startStr, 2, 2));
    sess.endHour   = (int)StringToInteger(StringSubstr(endStr, 0, 2));
    sess.endMin    = (int)StringToInteger(StringSubstr(endStr, 2, 2));
    int startRaw = sess.startHour * 60 + sess.startMin;
    int endRaw   = sess.endHour * 60 + sess.endMin;
    sess.crossesMidnight = (endRaw < startRaw);
}

bool IsInSession(datetime time, SessionTimes &sess, int offset) {
    MqlDateTime dt;
    TimeToStruct(time + (offset * 3600), dt);
    int currentRaw = dt.hour * 60 + dt.min;
    int startRaw   = sess.startHour * 60 + sess.startMin;
    int endRaw     = sess.endHour * 60 + sess.endMin;
    if (!sess.crossesMidnight) return (currentRaw >= startRaw && currentRaw < endRaw);
    else return (currentRaw >= startRaw || currentRaw < endRaw);
}

void DrawBox(string name, datetime t1, double p1, datetime t2, double p2, color border, color bg, int style, bool fill=true) {
    // OPTIMIZATION: Check if object exists first to avoid flickering
    if (ObjectFind(0, name) < 0) {
        ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
        ObjectSetInteger(0, name, OBJPROP_COLOR, border);
        ObjectSetInteger(0, name, OBJPROP_STYLE, style);
        ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
        ObjectSetInteger(0, name, OBJPROP_BACK, true);
        ObjectSetInteger(0, name, OBJPROP_FILL, fill);
    } else {
        // Just update properties
        ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
        ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
        ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
        ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
        ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg); // Update color if state changed
    }
}

void DrawLine(string name, datetime t1, double p1, datetime t2, double p2, color clr, int style) {
    if (ObjectFind(0, name) < 0) {
        ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
        ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
    } else {
        ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
        ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
        ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
        ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
    }
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_STYLE, style);
}

void DrawLabel(string name, datetime t, double p, string text, color clr, int anchor) {
    if (ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_TEXT, 0, t, p);
    else {
        ObjectSetInteger(0, name, OBJPROP_TIME, t);
        ObjectSetDouble(0, name, OBJPROP_PRICE, p);
    }
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
}