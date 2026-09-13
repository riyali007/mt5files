//+------------------------------------------------------------------+
//|                                        SessionVolumeProfile.mq5   |
//|  Draws a horizontal Volume Profile (POC / VAH / VAL) for the     |
//|  N most recent trading sessions, using chart objects.            |
//+------------------------------------------------------------------+
#property copyright "Educational example"
#property indicator_chart_window
#property indicator_buffers 0
#property strict

//--- Inputs
input int    InpSessionStartHour   = 0;      // Session start hour (server time)
input int    InpSessionStartMinute = 0;      // Session start minute
input int    InpSessionEndHour     = 23;     // Session end hour
input int    InpSessionEndMinute   = 59;     // Session end minute
input double InpRowHeightPoints    = 100;    // Row (bucket) height, in points
input double InpValueAreaPercent   = 70.0;   // Value Area target %
input int    InpSessionsToShow     = 3;      // How many past sessions to draw
input bool   InpUseRealVolume      = false;  // Use real volume (if available)
input bool   InpExtendUntilMitigated = true; // Extend POC/VAH/VAL forward until mitigated
input int    InpMaxExtensionSessions = 2;    // Max sessions to extend forward (cap)
input color  InpProfileColor       = clrSkyBlue;
input color  InpPOCColor           = clrRed;
input color  InpVAColor            = clrGoldenrod;
input string InpObjPrefix          = "SVP_";

datetime g_lastBarTime = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   IndicatorSetString(INDICATOR_SHORTNAME, "Session Volume Profile");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, InpObjPrefix);
  }

//+------------------------------------------------------------------+
//| Compute [start,end] datetime for the session "sessionsBack" days |
//| ago (0 = today / most recent session).                           |
//+------------------------------------------------------------------+
bool GetSessionBounds(const int sessionsBack, datetime &sessStart, datetime &sessEnd)
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime dayStart = StructToTime(dt) - sessionsBack * 86400;

   MqlDateTime dtStart, dtEnd;
   TimeToStruct(dayStart, dtStart);
   dtStart.hour = InpSessionStartHour;
   dtStart.min  = InpSessionStartMinute;
   dtStart.sec  = 0;
   sessStart = StructToTime(dtStart);

   TimeToStruct(dayStart, dtEnd);
   dtEnd.hour = InpSessionEndHour;
   dtEnd.min  = InpSessionEndMinute;
   dtEnd.sec  = 0;
   sessEnd = StructToTime(dtEnd);

   if(sessEnd <= sessStart)
      sessEnd += 86400; // session crosses midnight

   return(true);
  }

//+------------------------------------------------------------------+
//| Draw a horizontal level line (POC / VAH / VAL) across a session   |
//+------------------------------------------------------------------+
void DrawLevelLine(const string name, const datetime t1, const datetime t2,
                    const double price, const color clr, const ENUM_LINE_STYLE style)
  {
   ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
  }

//+------------------------------------------------------------------+
//| Find when price first trades through "level" after searchStart,  |
//| searching no further than searchCap. Returns the mitigation time |
//| if found, otherwise returns min(searchCap, current time) so the  |
//| line simply extends up to "now" (and further on later ticks)     |
//| until either mitigated or the cap is reached.                    |
//+------------------------------------------------------------------+
datetime FindLineEndTime(const double level, const datetime searchStart, const datetime searchCap)
  {
   datetime effectiveEnd = (datetime)MathMin((double)searchCap, (double)TimeCurrent());
   if(effectiveEnd <= searchStart)
      return(searchStart);

   int barShiftNear = iBarShift(_Symbol, _Period, effectiveEnd, false); // closer to now
   int barShiftFar  = iBarShift(_Symbol, _Period, searchStart, false);  // closer to searchStart
   if(barShiftNear < 0 || barShiftFar < 0 || barShiftFar < barShiftNear)
      return(effectiveEnd);

   int total = barShiftFar - barShiftNear + 1;
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, _Period, barShiftNear, total, rates);
   if(copied <= 0)
      return(effectiveEnd);

   // Scan forward in time (oldest -> newest) for the first bar that trades through the level
   for(int i = copied - 1; i >= 0; i--)
     {
      if(rates[i].low <= level && rates[i].high >= level)
         return(rates[i].time);
     }

   return(effectiveEnd); // not mitigated yet within the allowed window
  }

//+------------------------------------------------------------------+
//| Build the price/volume histogram for one session and draw it     |
//+------------------------------------------------------------------+
void BuildAndDrawProfile(const datetime sessStart, const datetime sessEnd, const int sessionIndex)
  {
   int barEnd   = iBarShift(_Symbol, _Period, sessStart, false);          // older bar
   int barStart = iBarShift(_Symbol, _Period, MathMin(sessEnd, TimeCurrent()), false); // newer bar
   if(barEnd < 0 || barStart < 0 || barEnd < barStart)
      return;

   int total = barEnd - barStart + 1;
   if(total <= 0)
      return;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, _Period, barStart, total, rates);
   if(copied <= 0)
      return;

   //--- session high/low
   double sessionHigh = -DBL_MAX, sessionLow = DBL_MAX;
   for(int i = 0; i < copied; i++)
     {
      if(rates[i].high > sessionHigh) sessionHigh = rates[i].high;
      if(rates[i].low  < sessionLow)  sessionLow  = rates[i].low;
     }
   if(sessionHigh <= sessionLow)
      return;

   double rowSize = MathMax(InpRowHeightPoints * _Point, _Point);
   int numRows = (int)MathRound((sessionHigh - sessionLow) / rowSize) + 1;
   if(numRows <= 0)
      return;

   double volAtRow[];
   ArrayResize(volAtRow, numRows);
   ArrayInitialize(volAtRow, 0.0);

   //--- distribute each bar's volume across the rows it spans
   for(int i = 0; i < copied; i++)
     {
      double vol = InpUseRealVolume ? (double)rates[i].real_volume
                                     : (double)rates[i].tick_volume;
      int rowLo = (int)MathFloor((rates[i].low  - sessionLow) / rowSize);
      int rowHi = (int)MathFloor((rates[i].high - sessionLow) / rowSize);
      rowLo = MathMax(rowLo, 0);
      rowHi = MathMin(rowHi, numRows - 1);
      if(rowHi < rowLo) rowHi = rowLo;

      int span = rowHi - rowLo + 1;
      double volPerRow = vol / span;
      for(int r = rowLo; r <= rowHi; r++)
         volAtRow[r] += volPerRow;
     }

   //--- POC
   int pocIdx = ArrayMaximum(volAtRow);
   double totalVolume = 0;
   for(int r = 0; r < numRows; r++) totalVolume += volAtRow[r];
   if(totalVolume <= 0)
      return;

   //--- Value Area expansion from POC
   int vaLowIdx = pocIdx, vaHighIdx = pocIdx;
   double vaVolume = volAtRow[pocIdx];
   double targetVolume = totalVolume * InpValueAreaPercent / 100.0;

   while(vaVolume < targetVolume && (vaLowIdx > 0 || vaHighIdx < numRows - 1))
     {
      double volBelow = (vaLowIdx > 0)            ? volAtRow[vaLowIdx - 1] : -1;
      double volAbove = (vaHighIdx < numRows - 1)  ? volAtRow[vaHighIdx + 1] : -1;

      if(volAbove >= volBelow)
        {
         vaHighIdx++;
         vaVolume += volAbove;
        }
      else
        {
         vaLowIdx--;
         vaVolume += volBelow;
        }
     }

   double poc = sessionLow + (pocIdx + 0.5) * rowSize;
   double vah = sessionLow + (vaHighIdx + 1) * rowSize;
   double val = sessionLow + vaLowIdx * rowSize;

   //--- base end of each line = end of its own session (or "now" if session still running)
   datetime naturalEnd = (datetime)MathMin((double)sessEnd, (double)TimeCurrent());

   datetime pocEnd = naturalEnd;
   datetime vahEnd = naturalEnd;
   datetime valEnd = naturalEnd;

   if(InpExtendUntilMitigated)
     {
      datetime sessionDuration = sessEnd - sessStart;
      datetime extensionCap = sessEnd + (datetime)((long)InpMaxExtensionSessions * (long)sessionDuration);

      pocEnd = FindLineEndTime(poc, naturalEnd, extensionCap);
      vahEnd = FindLineEndTime(vah, naturalEnd, extensionCap);
      valEnd = FindLineEndTime(val, naturalEnd, extensionCap);
     }

   //--- POC / VAH / VAL lines (extended forward until mitigated, if enabled)
   DrawLevelLine(InpObjPrefix + "POC_" + IntegerToString(sessionIndex), sessStart, pocEnd, poc, InpPOCColor, STYLE_SOLID);
   DrawLevelLine(InpObjPrefix + "VAH_" + IntegerToString(sessionIndex), sessStart, vahEnd, vah, InpVAColor, STYLE_DASH);
   DrawLevelLine(InpObjPrefix + "VAL_" + IntegerToString(sessionIndex), sessStart, valEnd, val, InpVAColor, STYLE_DASH);

   //--- session High/Low markers (kept within the session itself, no box)
   DrawLevelLine(InpObjPrefix + "HIGH_" + IntegerToString(sessionIndex), sessStart, sessEnd, sessionHigh, InpProfileColor, STYLE_DOT);
   DrawLevelLine(InpObjPrefix + "LOW_"  + IntegerToString(sessionIndex), sessStart, sessEnd, sessionLow,  InpProfileColor, STYLE_DOT);
  }

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
   if(rates_total <= 0)
      return(0);

   // Rebuild only once per new bar to save resources
   if(time[rates_total - 1] == g_lastBarTime)
      return(rates_total);
   g_lastBarTime = time[rates_total - 1];

   ObjectsDeleteAll(0, InpObjPrefix);

   for(int s = 0; s < InpSessionsToShow; s++)
     {
      datetime sessStart, sessEnd;
      GetSessionBounds(s, sessStart, sessEnd);
      BuildAndDrawProfile(sessStart, sessEnd, s);
     }

   ChartRedraw(0);
   return(rates_total);
  }
//+------------------------------------------------------------------+