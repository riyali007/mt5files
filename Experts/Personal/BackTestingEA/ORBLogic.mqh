//+------------------------------------------------------------------+
//|  ORBLogic.mqh  —  ORB session/signal/SMC/draw (no auto-trade)   |
//+------------------------------------------------------------------+
#ifndef ORBLOGIC_MQH
#define ORBLOGIC_MQH

#include "Inputs.mqh"
#include "Structs.mqh"

//=== ORB GLOBALS ===============================================
int      g_orbMins        = 30;
int      g_hRSI           = INVALID_HANDLE;
datetime g_lastAlertTime  = 0;
datetime g_orbLastBarTime = 0;

double   g_orbHigh[];
double   g_orbLow[];
double   g_orbActive[];
double   g_sessHigh[];
double   g_sessLow[];
double   g_sessStart[];
double   g_breakUp[];
double   g_breakDn[];

SessionTimes asiaSess, londonSess, nySess;
SessionTimes cust1Sess, cust2Sess, cust3Sess;

CSMCZone g_activeZones[];

//=== FORWARD DECLARATIONS =====================================
void   ParseSession(string timeStr, SessionTimes &sess);
bool   IsInSession(datetime time, SessionTimes &sess, int offset);
void   DrawBox(string name, datetime t1, double p1, datetime t2, double p2, color border, color bg, int style, bool fill=true);
void   DrawLine(string name, datetime t1, double p1, datetime t2, double p2, color clr, int style);
void   DrawLabel(string name, datetime t, double p, string text, color clr, int anchor, int fontSize=8);
void   DrawArrow(string name, datetime t, double p, int arrowCode, color clr);
void   ProcessSMC(const double &open[], const double &high[], const double &low[], const double &close[], const datetime &time[], int total);
bool   IsHammerBull(double o, double h, double l, double c, double upperLevel);
bool   IsHammerBear(double o, double h, double l, double c, double lowerLevel);
bool   IsBodyCloseBull(double o, double h, double l, double c, double upperLevel);
bool   IsBodyCloseBear(double o, double h, double l, double c, double lowerLevel);
bool   CheckRsiMaDirection(int shift, bool isBullish);
double CalculateRsiMA(const double &rsiArray[], int period, ENUM_MA_METHOD method);
void   SaveSignalToFile(string signalType, double entry, datetime signalTime);
string ORB_TimeframeToString(ENUM_TIMEFRAMES tf);

//=== ORB INIT/DEINIT ==========================================
bool ORB_Init()
{
    ParseSession(InpAsiaTime,   asiaSess);
    ParseSession(InpLondonTime, londonSess);
    ParseSession(InpNYTime,     nySess);
    ParseSession(InpCust1Time,  cust1Sess);
    ParseSession(InpCust2Time,  cust2Sess);
    ParseSession(InpCust3Time,  cust3Sess);

    g_orbMins = PeriodSeconds(InpORBTimeframe) / 60;
    if(g_orbMins == 0) g_orbMins = 30;

    g_hRSI = iRSI(_Symbol, _Period, InpRsiPeriod, PRICE_CLOSE);
    if(g_hRSI == INVALID_HANDLE) {
        Print("ORB ERROR: Failed to create RSI handle");
        return false;
    }
    ObjectsDeleteAll(0, "RIY_");
    Print("ORB Logic v1.0 | RSI filter=", InpUseRsiMaFilter,
          " | Mode=", InpUseBCC ? "BCC" : "Hammer");
    return true;
}

void ORB_Deinit()
{
    if(g_hRSI != INVALID_HANDLE) { IndicatorRelease(g_hRSI); g_hRSI = INVALID_HANDLE; }
    ObjectsDeleteAll(0, "RIY_");
}

//=== MAIN ORB SCAN (call on new bar) ==========================
void ORB_OnNewBar()
{
    int total = iBars(_Symbol, _Period);
    if(total < 10) return;

    int limit = MathMin(total, InpMaxHistory + 10);

    double  open[];  ArraySetAsSeries(open,  true); CopyOpen (_Symbol,_Period,0,limit,open);
    double  high[];  ArraySetAsSeries(high,  true); CopyHigh (_Symbol,_Period,0,limit,high);
    double  low[];   ArraySetAsSeries(low,   true); CopyLow  (_Symbol,_Period,0,limit,low);
    double  close[]; ArraySetAsSeries(close, true); CopyClose(_Symbol,_Period,0,limit,close);
    datetime time[]; ArraySetAsSeries(time,  true); CopyTime (_Symbol,_Period,0,limit,time);
    int     sprd[];  ArraySetAsSeries(sprd,  true); CopySpread(_Symbol,_Period,0,limit,sprd);

    ArrayResize(g_sessHigh,  limit); ArraySetAsSeries(g_sessHigh,  true);
    ArrayResize(g_sessLow,   limit); ArraySetAsSeries(g_sessLow,   true);
    ArrayResize(g_orbHigh,   limit); ArraySetAsSeries(g_orbHigh,   true);
    ArrayResize(g_orbLow,    limit); ArraySetAsSeries(g_orbLow,    true);
    ArrayResize(g_orbActive, limit); ArraySetAsSeries(g_orbActive, true);
    ArrayResize(g_breakUp,   limit); ArraySetAsSeries(g_breakUp,   true);
    ArrayResize(g_breakDn,   limit); ArraySetAsSeries(g_breakDn,   true);
    ArrayResize(g_sessStart, limit); ArraySetAsSeries(g_sessStart, true);

    ArrayInitialize(g_sessHigh,  0); ArrayInitialize(g_sessLow,   0);
    ArrayInitialize(g_orbHigh,   0); ArrayInitialize(g_orbLow,    0);
    ArrayInitialize(g_orbActive, 0); ArrayInitialize(g_breakUp,   0);
    ArrayInitialize(g_breakDn,   0); ArrayInitialize(g_sessStart, 0);

    for(int i = limit - 1; i >= 0; i--)
    {
        bool isAsia   = InpAsiaOn   && IsInSession(time[i], asiaSess,   InpTimeOffset);
        bool isLondon = InpLondonOn && IsInSession(time[i], londonSess, InpTimeOffset);
        bool isNY     = InpNYOn     && IsInSession(time[i], nySess,     InpTimeOffset);
        bool isCust1  = InpCust1On  && IsInSession(time[i], cust1Sess,  InpTimeOffset);
        bool isCust2  = InpCust2On  && IsInSession(time[i], cust2Sess,  InpTimeOffset);
        bool isCust3  = InpCust3On  && IsInSession(time[i], cust3Sess,  InpTimeOffset);

        bool prevAsia   = (i<limit-1)?(InpAsiaOn   && IsInSession(time[i+1],asiaSess,  InpTimeOffset)):false;
        bool prevLondon = (i<limit-1)?(InpLondonOn && IsInSession(time[i+1],londonSess,InpTimeOffset)):false;
        bool prevNY     = (i<limit-1)?(InpNYOn     && IsInSession(time[i+1],nySess,    InpTimeOffset)):false;
        bool prevCust1  = (i<limit-1)?(InpCust1On  && IsInSession(time[i+1],cust1Sess, InpTimeOffset)):false;
        bool prevCust2  = (i<limit-1)?(InpCust2On  && IsInSession(time[i+1],cust2Sess, InpTimeOffset)):false;
        bool prevCust3  = (i<limit-1)?(InpCust3On  && IsInSession(time[i+1],cust3Sess, InpTimeOffset)):false;

        bool newSess = (isAsia&&!prevAsia)||(isLondon&&!prevLondon)||(isNY&&!prevNY)||
                       (isCust1&&!prevCust1)||(isCust2&&!prevCust2)||(isCust3&&!prevCust3);

        string currentSessName = "";
        if(isAsia)        currentSessName = "ASIA";
        else if(isLondon) currentSessName = "LONDON";
        else if(isNY)     currentSessName = "NY";
        else if(isCust1)  currentSessName = InpCust1Name;
        else if(isCust2)  currentSessName = InpCust2Name;
        else if(isCust3)  currentSessName = InpCust3Name;

        double mySessHigh = high[i], mySessLow = low[i];
        double myOrbHigh  = high[i], myOrbLow  = low[i];

        if(newSess) {
            g_sessStart[i] = (double)time[i];
            mySessHigh = high[i]; mySessLow = low[i];
            myOrbHigh  = high[i]; myOrbLow  = low[i];
        }
        else if(isAsia || isLondon || isNY || isCust1 || isCust2 || isCust3) {
            if(i < limit-1) g_sessStart[i] = g_sessStart[i+1];
            if(i < limit-1 && g_sessHigh[i+1] != 0.0) {
                mySessHigh = MathMax(g_sessHigh[i+1], high[i]);
                mySessLow  = MathMin(g_sessLow[i+1],  low[i]);
                int dur = (int)(time[i] - (datetime)g_sessStart[i]) / 60;
                if(dur < g_orbMins) {
                    myOrbHigh = MathMax(g_orbHigh[i+1], high[i]);
                    myOrbLow  = MathMin(g_orbLow[i+1],  low[i]);
                } else {
                    myOrbHigh = g_orbHigh[i+1];
                    myOrbLow  = g_orbLow[i+1];
                }
            }
        }
        else {
            if(i < limit-1) {
                g_sessStart[i] = g_sessStart[i+1];
                mySessHigh = g_sessHigh[i+1]; mySessLow = g_sessLow[i+1];
                myOrbHigh  = g_orbHigh[i+1];  myOrbLow  = g_orbLow[i+1];
            }
        }

        g_sessHigh[i] = mySessHigh; g_sessLow[i] = mySessLow;
        g_orbHigh[i]  = myOrbHigh;  g_orbLow[i]  = myOrbLow;

        datetime sessStart   = (datetime)g_sessStart[i];
        int durationMins     = (sessStart > 0) ? (int)(time[i] - sessStart) / 60 : 9999;
        bool isOrbActive     = (sessStart > 0) && (durationMins < g_orbMins);
        g_orbActive[i]       = isOrbActive ? 1.0 : 0.0;

        int prevDurMins = 9999;
        if(i < limit-1 && g_sessStart[i+1] == (double)sessStart)
            prevDurMins = (int)(time[i+1] - sessStart) / 60;
        bool orbFinished = (sessStart > 0) && (durationMins >= g_orbMins) && (prevDurMins < g_orbMins);

        // Signal detection on bar[1] (confirmed closed candle)
        bool breakUp = false, breakDn = false;

        if(i == 1 && !isOrbActive && sessStart > 0)
        {
            bool bullSignal = InpUseBCC
                ? IsBodyCloseBull(open[i], high[i], low[i], close[i], g_orbHigh[i])
                : IsHammerBull(open[i], high[i], low[i], close[i], g_orbHigh[i]);

            if(bullSignal && CheckRsiMaDirection(i, true) && time[i] != g_lastAlertTime) {
                breakUp = true;
                if(InpPlaySound) PlaySound(InpSoundFile);
                SaveSignalToFile("Buy", close[i], time[i]);
                g_lastAlertTime = time[i];
            }

            bool bearSignal = InpUseBCC
                ? IsBodyCloseBear(open[i], high[i], low[i], close[i], g_orbLow[i])
                : IsHammerBear(open[i], high[i], low[i], close[i], g_orbLow[i]);

            if(bearSignal && CheckRsiMaDirection(i, false) && time[i] != g_lastAlertTime) {
                breakDn = true;
                if(InpPlaySound) PlaySound(InpSoundFile);
                SaveSignalToFile("Sell", close[i], time[i]);
                g_lastAlertTime = time[i];
            }
        }

        g_breakUp[i] = breakUp ? 1.0 : 0.0;
        g_breakDn[i] = breakDn ? 1.0 : 0.0;

        // ── Drawing (skip deep history) ──
        if(i > 1000) continue;

        string suffix         = IntegerToString(sessStart);
        double currentSpreadV = sprd[i] * _Point;

        if(isOrbActive)
            DrawBox("RIY_ORBBox_"+suffix, sessStart, g_orbHigh[i], time[i], g_orbLow[i], InpBoxBorder, InpBoxBgColor, STYLE_DOT);

        if(sessStart > 0) {
            DrawLine("RIY_SessHigh_"+suffix, sessStart, g_sessHigh[i], time[i], g_sessHigh[i], clrGray, STYLE_DASH);
            DrawLine("RIY_SessLow_"+suffix,  sessStart, g_sessLow[i],  time[i], g_sessLow[i],  clrGray, STYLE_DASH);
            DrawLabel("RIY_LblHigh_"+suffix, time[i], g_sessHigh[i], currentSessName+" HIGH", clrGray, ANCHOR_LEFT);
            DrawLabel("RIY_LblLow_"+suffix,  time[i], g_sessLow[i],  currentSessName+" LOW",  clrGray, ANCHOR_LEFT);
        }

        if(orbFinished || (sessStart > 0 && durationMins >= g_orbMins)) {
            DrawLine("RIY_ORBLineH_"+suffix, sessStart, g_orbHigh[i], time[i], g_orbHigh[i], InpBullColor, STYLE_SOLID);
            DrawLine("RIY_ORBLineL_"+suffix, sessStart, g_orbLow[i],  time[i], g_orbLow[i],  InpBearColor, STYLE_SOLID);
            if(InpShowSpread) {
                DrawLine("RIY_SpreadH_"+suffix, sessStart, g_orbHigh[i]+currentSpreadV, time[i], g_orbHigh[i]+currentSpreadV, InpSpreadColor, InpSpreadStyle);
                DrawLine("RIY_SpreadL_"+suffix, sessStart, g_orbLow[i]-currentSpreadV,  time[i], g_orbLow[i]-currentSpreadV,  InpSpreadColor, InpSpreadStyle);
            }
        }

        if(breakUp && InpShowBreakoutArrows) {
            DrawArrow("RIY_Arrow_"+IntegerToString(time[i]), time[i], low[i], InpBuyArrowCode, InpBuyArrowColor);
            if(InpShowPriceLabels)
                DrawLabel("RIY_Price_"+IntegerToString(time[i]), time[i], low[i],
                          "Buy ("+DoubleToString(close[i],_Digits)+")", clrWhite, ANCHOR_TOP, 9);
        }
        if(breakDn && InpShowBreakoutArrows) {
            DrawArrow("RIY_Arrow_"+IntegerToString(time[i]), time[i], high[i], InpSellArrowCode, InpSellArrowColor);
            if(InpShowPriceLabels)
                DrawLabel("RIY_Price_"+IntegerToString(time[i]), time[i], high[i],
                          "Sell ("+DoubleToString(close[i],_Digits)+")", clrWhite, ANCHOR_BOTTOM, 9);
        }
    }

    if(InpUseSMC) ProcessSMC(open, high, low, close, time, limit);
    ChartRedraw();
}

//=== SESSION PARSER ===========================================
void ParseSession(string timeStr, SessionTimes &sess)
{
    int dashPos = StringFind(timeStr, "-");
    if(dashPos < 0) return;
    string startStr = StringSubstr(timeStr, 0, dashPos);
    string endStr   = StringSubstr(timeStr, dashPos + 1);
    sess.startHour = (int)StringToInteger(StringSubstr(startStr, 0, 2));
    sess.startMin  = (int)StringToInteger(StringSubstr(startStr, 2, 2));
    sess.endHour   = (int)StringToInteger(StringSubstr(endStr, 0, 2));
    sess.endMin    = (int)StringToInteger(StringSubstr(endStr, 2, 2));
    int sTotal = sess.startHour * 60 + sess.startMin;
    int eTotal = sess.endHour   * 60 + sess.endMin;
    sess.crossesMidnight = (eTotal <= sTotal);
}

bool IsInSession(datetime time, SessionTimes &sess, int offset)
{
    MqlDateTime dt;
    TimeToStruct(time + offset * 3600, dt);
    int cur = dt.hour * 60 + dt.min;
    int s   = sess.startHour * 60 + sess.startMin;
    int e   = sess.endHour   * 60 + sess.endMin;
    if(sess.crossesMidnight) return (cur >= s || cur < e);
    return (cur >= s && cur < e);
}

//=== SIGNAL HELPERS ===========================================
bool IsHammerBull(double o, double h, double l, double c, double upperLevel)
{
    if(!InpRequireHammer) return true;
    if(!(o > upperLevel && c > upperLevel && l <= upperLevel)) return false;
    double range = h - l;
    if(range <= 0) return false;
    return (MathAbs(c-o)/range <= InpHammerBodyPct);
}

bool IsHammerBear(double o, double h, double l, double c, double lowerLevel)
{
    if(!InpRequireHammer) return true;
    if(!(o < lowerLevel && c < lowerLevel && h >= lowerLevel)) return false;
    double range = h - l;
    if(range <= 0) return false;
    return (MathAbs(c-o)/range <= InpHammerBodyPct);
}

bool IsBodyCloseBull(double o, double h, double l, double c, double upperLevel)
{
    return (o <= upperLevel && c > upperLevel);
}

bool IsBodyCloseBear(double o, double h, double l, double c, double lowerLevel)
{
    return (o >= lowerLevel && c < lowerLevel);
}

double CalculateRsiMA(const double &rsiArray[], int period, ENUM_MA_METHOD method)
{
    if(period <= 0) return 0.0;
    double sum = 0.0;
    switch(method) {
        case MODE_SMA:
            for(int i=0;i<period;i++) sum+=rsiArray[i];
            return sum/period;
        case MODE_EMA: {
            double ema = rsiArray[period-1];
            double mul = 2.0/(period+1.0);
            for(int i=period-2;i>=0;i--) ema=(rsiArray[i]-ema)*mul+ema;
            return ema; }
        case MODE_SMMA:
            for(int i=0;i<period;i++) sum+=rsiArray[i];
            return sum/period;
        case MODE_LWMA: {
            double wsum=0;
            for(int i=0;i<period;i++){int w=period-i;sum+=rsiArray[i]*w;wsum+=w;}
            return sum/wsum; }
    }
    return 0.0;
}

bool CheckRsiMaDirection(int shift, bool isBullish)
{
    if(!InpUseRsiMaFilter) return true;
    double rsiValues[];
    ArraySetAsSeries(rsiValues, true);
    int req = MathMax(InpRsiPeriod, InpRsiMaPeriod) + shift + 10;
    if(CopyBuffer(g_hRSI, 0, shift, req, rsiValues) <= InpRsiMaPeriod) return true;
    double rsiMA  = CalculateRsiMA(rsiValues, InpRsiMaPeriod, InpRsiMaMethod);
    double curRSI = rsiValues[0];
    return isBullish ? (curRSI > rsiMA) : (curRSI < rsiMA);
}

//=== FILE LOGGING =============================================
string ORB_TimeframeToString(ENUM_TIMEFRAMES tf)
{
    switch(tf) {
        case PERIOD_M1:  return "M1";  case PERIOD_M5:  return "M5";
        case PERIOD_M15: return "M15"; case PERIOD_M30: return "M30";
        case PERIOD_H1:  return "H1";  case PERIOD_H4:  return "H4";
        case PERIOD_D1:  return "D1";  case PERIOD_W1:  return "W1";
        case PERIOD_MN1: return "MN1"; default: return "UNKNOWN";
    }
}

void SaveSignalToFile(string signalType, double entry, datetime signalTime)
{
    if(!InpEnableFileLog) return;
    string json = StringFormat(
        "{\"symbol\":\"%s\",\"timeFrame\":\"%s\",\"signalType\":\"%s\","
        "\"entry\":%.5f,\"dateTime\":\"%s\"}",
        _Symbol, ORB_TimeframeToString(_Period), signalType,
        entry,
        TimeToString(signalTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS)
    );
    int fh = FileOpen(InpSignalFileName, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
    if(fh == INVALID_HANDLE) { Print("ORB ERROR: Cannot open signal file"); return; }
    FileSeek(fh, 0, SEEK_END);
    FileWriteString(fh, json + "\n");
    FileClose(fh);
    Print("ORB Signal: ", signalType, " @ ", DoubleToString(entry, _Digits));
}

//=== SMC PROCESSING ===========================================
void ProcessSMC(const double &open[], const double &high[], const double &low[],
                const double &close[], const datetime &time[], int total)
{
    ArrayResize(g_activeZones, 0);
    int startIdx = MathMin(InpMaxHistory, total-3);

    for(int i = startIdx; i >= 0; i--)
    {
        double fvgTop=0, fvgBot=0; int fvgType=0;

        if(InpShowFVG) {
            if(low[i] > high[i+2])      { fvgTop=low[i];   fvgBot=high[i+2]; fvgType= 1; }
            else if(high[i] < low[i+2]) { fvgTop=low[i+2]; fvgBot=high[i];   fvgType=-1; }

            if(fvgType != 0) {
                double orbH = g_orbHigh[i], orbL = g_orbLow[i];
                bool inside = (orbH>0 && orbL>0) && (fvgBot>=orbL && fvgTop<=orbH);
                if(inside) {
                    CSMCZone z;
                    z.mode=0; z.origType=fvgType; z.currType=fvgType;
                    z.top=fvgTop; z.bottom=fvgBot;
                    z.tStart=time[i+2]; z.tEnd=time[i];
                    z.name="RIY_SMC_FVG_"+IntegerToString(time[i]);
                    int s=ArraySize(g_activeZones); ArrayResize(g_activeZones,s+1);
                    g_activeZones[s]=z;
                }
            }
        }

        if(InpShowOB && fvgType!=0) {
            bool obBull = (fvgType==1  && close[i+2] < open[i+2]);
            bool obBear = (fvgType==-1 && close[i+2] > open[i+2]);
            if(obBull || obBear) {
                CSMCZone ob;
                ob.mode=1; ob.origType=fvgType; ob.currType=fvgType;
                ob.top=high[i+2]; ob.bottom=low[i+2];
                ob.tStart=time[i+2]; ob.tEnd=time[i];
                ob.name="RIY_SMC_OB_"+IntegerToString(time[i+2]);
                int s=ArraySize(g_activeZones); ArrayResize(g_activeZones,s+1);
                g_activeZones[s]=ob;
            }
        }

        // Mitigation check
        for(int k=0; k<ArraySize(g_activeZones); k++) {
            if(g_activeZones[k].state == STATE_DEAD) continue;
            bool bullZone = (g_activeZones[k].currType == 1);
            bool mitigated = bullZone
                ? (low[i]  <= g_activeZones[k].top)
                : (high[i] >= g_activeZones[k].bottom);
            if(mitigated) {
                g_activeZones[k].tEnd = time[i];
                bool inverted = bullZone
                    ? (close[i] < g_activeZones[k].bottom)
                    : (close[i] > g_activeZones[k].top);
                g_activeZones[k].state    = inverted ? STATE_INVERTED : STATE_MITIGATED;
                g_activeZones[k].currType = inverted ? -g_activeZones[k].origType : g_activeZones[k].currType;
            }
        }
    }

    // Prune dead/excess zones
    int visible = 0;
    for(int k = ArraySize(g_activeZones)-1; k >= 0; k--) {
        if(!InpShowDead && g_activeZones[k].state == STATE_DEAD) continue;
        if(visible >= InpMaxVisible) { g_activeZones[k].state = STATE_DEAD; continue; }
        visible++;

        CSMCZone z = g_activeZones[k];
        color zClr;
        if(z.mode == 0) { // FVG
            if(z.state == STATE_MITIGATED || z.state == STATE_INVERTED)
                zClr = (z.currType==1) ? InpColor_IFVG_Supp : InpColor_IFVG_Res;
            else
                zClr = (z.origType==1) ? InpColor_FVG_Supp : InpColor_FVG_Res;
        } else { // OB
            if(z.state == STATE_MITIGATED || z.state == STATE_INVERTED)
                zClr = (z.currType==1) ? InpColor_BB_Supp : InpColor_BB_Res;
            else
                zClr = (z.origType==1) ? InpColor_OB_Supp : InpColor_OB_Res;
        }
        DrawBox(z.name, z.tStart, z.top, z.tEnd, z.bottom, zClr, zClr, STYLE_SOLID, true);
    }
}

//=== DRAWING HELPERS ==========================================
void DrawBox(string name, datetime t1, double p1, datetime t2, double p2,
             color border, color bg, int style, bool fill=true)
{
    if(ObjectFind(0, name) < 0)
        ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
    ObjectSetInteger(0, name, OBJPROP_TIME,  0, t1);
    ObjectSetDouble (0, name, OBJPROP_PRICE, 0, p1);
    ObjectSetInteger(0, name, OBJPROP_TIME,  1, t2);
    ObjectSetDouble (0, name, OBJPROP_PRICE, 1, p2);
    ObjectSetInteger(0, name, OBJPROP_COLOR,   border);
    ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
    ObjectSetInteger(0, name, OBJPROP_STYLE,   style);
    ObjectSetInteger(0, name, OBJPROP_FILL,    fill);
    ObjectSetInteger(0, name, OBJPROP_BACK,    true);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void DrawLine(string name, datetime t1, double p1, datetime t2, double p2,
              color clr, int style)
{
    if(ObjectFind(0, name) < 0)
        ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
    ObjectSetInteger(0, name, OBJPROP_TIME,  0, t1);
    ObjectSetDouble (0, name, OBJPROP_PRICE, 0, p1);
    ObjectSetInteger(0, name, OBJPROP_TIME,  1, t2);
    ObjectSetDouble (0, name, OBJPROP_PRICE, 1, p2);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_STYLE, style);
    ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
    ObjectSetInteger(0, name, OBJPROP_BACK,  true);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void DrawLabel(string name, datetime t, double p, string text, color clr,
               int anchor, int fontSize=8)
{
    if(ObjectFind(0, name) < 0)
        ObjectCreate(0, name, OBJ_TEXT, 0, t, p);
    ObjectSetInteger(0, name, OBJPROP_TIME,  t);
    ObjectSetDouble (0, name, OBJPROP_PRICE, p);
    ObjectSetString (0, name, OBJPROP_TEXT,  text);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
    ObjectSetInteger(0, name, OBJPROP_BACK, true);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void DrawArrow(string name, datetime t, double p, int arrowCode, color clr)
{
    if(ObjectFind(0, name) < 0)
        ObjectCreate(0, name, OBJ_ARROW, 0, t, p);
    ObjectSetInteger(0, name, OBJPROP_TIME,      t);
    ObjectSetDouble (0, name, OBJPROP_PRICE,     p);
    ObjectSetInteger(0, name, OBJPROP_ARROWCODE, arrowCode);
    ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
    ObjectSetInteger(0, name, OBJPROP_WIDTH,     2);
    ObjectSetInteger(0, name, OBJPROP_BACK,      false);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

#endif // ORBLOGIC_MQH
