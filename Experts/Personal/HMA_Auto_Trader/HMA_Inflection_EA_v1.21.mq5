//+------------------------------------------------------------------+
//|                                             HMA_Inflection_EA.mq5|
//|                                  Copyright 2026, Riy Ali / MQL5  |
//+------------------------------------------------------------------+
#property copyright "Riy Ali"
#property link      "https://www.mql5.com"
#property version   "1.21"
#property strict

//--- Inputs
input group "=== HMA Settings ==="
input int                InpHmaPeriod         = 21;          // HMA Period
input ENUM_APPLIED_PRICE InpAppliedPrice      = PRICE_CLOSE; // Applied Price
input int                InpBarsToProcess     = 500;         // Historical Bars to Calculate & Draw
input color              InpHmaUpColor        = clrLimeGreen;// HMA Slope Up Color
input color              InpHmaDownColor      = clrTomato;   // HMA Slope Down Color
input int                InpHmaWidth          = 2;           // HMA Line Width

input group "=== Inflection Line & Distance ==="
input int                InpMinDistancePoints = 800;         // Min Distance between Inflections (Points)
input int                InpOffsetPoints      = 100;         // Offset added to Inflection Line (Points)

input group "=== Inflection Line Styling ==="
input color              InpBullLineColor     = clrAqua;     // Active Bullish Line (Valley + Offset)
input color              InpBearLineColor     = clrOrangeRed;// Active Bearish Line (Peak - Offset)
input color              InpMitigatedColor    = clrDimGray;  // Mitigated Line Color
input int                InpLineWidth         = 2;           // Active Line Width
input ENUM_LINE_STYLE    InpActiveStyle       = STYLE_SOLID; // Active Line Style
input ENUM_LINE_STYLE    InpMitigatedStyle    = STYLE_DOT;   // Mitigated Line Style

//--- Tracking Structures
enum ENUM_INFLECTION_TYPE
{
   INFLECTION_NONE,
   INFLECTION_PEAK,    // Bearish turn
   INFLECTION_VALLEY   // Bullish turn
};

struct SInflectionLine
{
   string               name;
   ENUM_INFLECTION_TYPE type;
   double               rawPrice;       // Raw HMA price at pivot
   double               lineLevel;      // Level with offset
   datetime             startTime;      // Pivot bar time
   datetime             endTime;        // Mitigation bar time or current bar
   bool                 isMitigated;    // True when price has touched/crossed
};

// State arrays & markers
SInflectionLine  activeLines[];
double           lastValidRawPrice    = 0.0;
bool             hasFirstInflection   = false;
datetime         lastProcessedBarTime = 0;

// Object Prefixes
#define HMA_PREFIX   "HMA_Seg_"
#define LINE_PREFIX  "HMA_Infl_"

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   ArrayResize(activeLines, 0);
   lastValidRawPrice    = 0.0;
   hasFirstInflection   = false;
   lastProcessedBarTime = 0;

   // Purge existing drawings
   ObjectsDeleteAll(0, HMA_PREFIX);
   ObjectsDeleteAll(0, LINE_PREFIX);

   // Perform full historical back-calculation and line drawing
   ProcessHistoricalData();
   ChartRedraw(0);

   Print("HMA Inflection EA v1.21 initialized successfully. Visual tracking ready.");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, HMA_PREFIX);
   ObjectsDeleteAll(0, LINE_PREFIX);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Helper: Calculate Linear Weighted Moving Average (WMA) on Array  |
//+------------------------------------------------------------------+
double CalculateWMA(const double &arr[], int startIdx, int period)
{
   double sum = 0.0;
   int weightSum = 0;
   for(int i = 0; i < period; i++)
   {
      int weight = period - i;
      sum += arr[startIdx + i] * weight;
      weightSum += weight;
   }
   return (weightSum > 0) ? (sum / weightSum) : 0.0;
}

//+------------------------------------------------------------------+
//| Compute entire HMA series efficiently into an array              |
//| hmaValues[0] is shift 0, hmaValues[1] is shift 1, etc.           |
//+------------------------------------------------------------------+
bool CalculateHmaSeries(int totalBarsNeeded, double &hmaValues[])
{
   int halfPeriod = InpHmaPeriod / 2;
   int sqrtPeriod = (int)MathFloor(MathSqrt((double)InpHmaPeriod));
   if(halfPeriod < 1) halfPeriod = 1;
   if(sqrtPeriod < 1) sqrtPeriod = 1;

   int priceBarsNeeded = totalBarsNeeded + InpHmaPeriod + sqrtPeriod + 10;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, _Period, 0, priceBarsNeeded, rates);
   if(copied < priceBarsNeeded)
   {
      PrintFormat("Insufficient bars: copied %d of %d requested.", copied, priceBarsNeeded);
      return false;
   }

   double prices[];
   ArrayResize(prices, copied);
   for(int i = 0; i < copied; i++)
   {
      switch(InpAppliedPrice)
      {
         case PRICE_OPEN:     prices[i] = rates[i].open; break;
         case PRICE_HIGH:     prices[i] = rates[i].high; break;
         case PRICE_LOW:      prices[i] = rates[i].low; break;
         case PRICE_MEDIAN:   prices[i] = (rates[i].high + rates[i].low) / 2.0; break;
         case PRICE_TYPICAL:  prices[i] = (rates[i].high + rates[i].low + rates[i].close) / 3.0; break;
         case PRICE_WEIGHTED: prices[i] = (rates[i].high + rates[i].low + 2.0 * rates[i].close) / 4.0; break;
         default:             prices[i] = rates[i].close; break;
      }
   }

   // Compute raw HMA intermediate series = 2 * WMA(half) - WMA(full)
   int rawCount = totalBarsNeeded + sqrtPeriod;
   double rawHMA[];
   ArrayResize(rawHMA, rawCount);
   for(int i = 0; i < rawCount; i++)
   {
      double wmaHalf = CalculateWMA(prices, i, halfPeriod);
      double wmaFull = CalculateWMA(prices, i, InpHmaPeriod);
      rawHMA[i] = (2.0 * wmaHalf) - wmaFull;
   }

   // Final smoothing: WMA(rawHMA, sqrtPeriod)
   ArrayResize(hmaValues, totalBarsNeeded);
   for(int i = 0; i < totalBarsNeeded; i++)
   {
      hmaValues[i] = CalculateWMA(rawHMA, i, sqrtPeriod);
   }

   return true;
}

//+------------------------------------------------------------------+
//| Helper: Draw a single HMA segment between bar i and bar i-1      |
//+------------------------------------------------------------------+
void DrawHMASegment(datetime t1, double p1, datetime t2, double p2, int barIdx)
{
   string name = HMA_PREFIX + IntegerToString(barIdx);
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   else
   {
      ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
   }

   color segColor = (p2 >= p1) ? InpHmaUpColor : InpHmaDownColor;
   ObjectSetInteger(0, name, OBJPROP_COLOR, segColor);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, InpHmaWidth);
}

//+------------------------------------------------------------------+
//| Render horizontal inflection line bounded by mitigation          |
//+------------------------------------------------------------------+
void RenderInflectionLine(const SInflectionLine &infLine)
{
   if(ObjectFind(0, infLine.name) < 0)
   {
      ObjectCreate(0, infLine.name, OBJ_TREND, 0, infLine.startTime, infLine.lineLevel, infLine.endTime, infLine.lineLevel);
      ObjectSetInteger(0, infLine.name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, infLine.name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, infLine.name, OBJPROP_HIDDEN, false);
   }
   else
   {
      ObjectSetInteger(0, infLine.name, OBJPROP_TIME, 1, infLine.endTime);
      ObjectSetDouble(0, infLine.name, OBJPROP_PRICE, 1, infLine.lineLevel);
   }

   if(infLine.isMitigated)
   {
      ObjectSetInteger(0, infLine.name, OBJPROP_COLOR, InpMitigatedColor);
      ObjectSetInteger(0, infLine.name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, infLine.name, OBJPROP_STYLE, InpMitigatedStyle);
   }
   else
   {
      color clr = (infLine.type == INFLECTION_VALLEY) ? InpBullLineColor : InpBearLineColor;
      ObjectSetInteger(0, infLine.name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, infLine.name, OBJPROP_WIDTH, InpLineWidth);
      ObjectSetInteger(0, infLine.name, OBJPROP_STYLE, InpActiveStyle);
   }
}

//+------------------------------------------------------------------+
//| Process history to plot HMA segments & detect prior inflections  |
//+------------------------------------------------------------------+
void ProcessHistoricalData()
{
   int totalBars = MathMin(InpBarsToProcess, iBars(_Symbol, _Period) - 20);
   if(totalBars < 10) return;

   double hma[];
   if(!CalculateHmaSeries(totalBars, hma)) return;

   // 1. Draw all historical HMA trend segments
   for(int i = totalBars - 1; i >= 1; i--)
   {
      datetime t1 = iTime(_Symbol, _Period, i);
      datetime t2 = iTime(_Symbol, _Period, i - 1);
      DrawHMASegment(t1, hma[i], t2, hma[i - 1], i);
   }

   // 2. Scan historical bars forward (oldest to newest) for inflection points
   for(int i = totalBars - 3; i >= 1; i--)
   {
      double hPrev = hma[i + 1];
      double hCurr = hma[i];
      double hNext = hma[i - 1];

      ENUM_INFLECTION_TYPE detected = INFLECTION_NONE;
      if(hCurr < hPrev && hCurr < hNext)
         detected = INFLECTION_VALLEY;
      else if(hCurr > hPrev && hCurr > hNext)
         detected = INFLECTION_PEAK;

      if(detected != INFLECTION_NONE)
      {
         double rawPrice = hCurr;
         bool isValidDistance = false;

         if(!hasFirstInflection)
         {
            isValidDistance = true;
         }
         else
         {
            double diffPoints = MathAbs(rawPrice - lastValidRawPrice) / _Point;
            if(diffPoints >= InpMinDistancePoints)
               isValidDistance = true;
         }

         if(isValidDistance)
         {
            datetime pivotTime = iTime(_Symbol, _Period, i);
            double offsetVal = InpOffsetPoints * _Point;
            double lineLevel = (detected == INFLECTION_VALLEY) ? (rawPrice + offsetVal) : (rawPrice - offsetVal);

            hasFirstInflection = true;
            lastValidRawPrice  = rawPrice;

            int idx = ArraySize(activeLines);
            ArrayResize(activeLines, idx + 1);

            activeLines[idx].name        = LINE_PREFIX + TimeToString(pivotTime, TIME_DATE|TIME_MINUTES);
            activeLines[idx].type        = detected;
            activeLines[idx].rawPrice    = rawPrice;
            activeLines[idx].lineLevel   = lineLevel;
            activeLines[idx].startTime   = pivotTime;
            activeLines[idx].endTime     = pivotTime;
            activeLines[idx].isMitigated = false;

            // Check if subsequent historical candles (from i-1 down to 0) mitigated this line
            for(int k = i - 1; k >= 0; k--)
            {
               datetime barTime = iTime(_Symbol, _Period, k);
               activeLines[idx].endTime = barTime;

               if(detected == INFLECTION_VALLEY && iLow(_Symbol, _Period, k) <= lineLevel)
               {
                  activeLines[idx].isMitigated = true;
                  break;
               }
               else if(detected == INFLECTION_PEAK && iHigh(_Symbol, _Period, k) >= lineLevel)
               {
                  activeLines[idx].isMitigated = true;
                  break;
               }
            }

            RenderInflectionLine(activeLines[idx]);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check open inflection lines against bar 0 for live mitigation    |
//+------------------------------------------------------------------+
void UpdateMitigationAndExtendLive(datetime currentBarTime)
{
   double high0 = iHigh(_Symbol, _Period, 0);
   double low0  = iLow(_Symbol, _Period, 0);

   int total = ArraySize(activeLines);
   for(int i = 0; i < total; i++)
   {
      if(activeLines[i].isMitigated) continue;

      bool mitigated = false;
      if(activeLines[i].type == INFLECTION_VALLEY && low0 <= activeLines[i].lineLevel)
         mitigated = true;
      else if(activeLines[i].type == INFLECTION_PEAK && high0 >= activeLines[i].lineLevel)
         mitigated = true;

      activeLines[i].endTime = currentBarTime;
      if(mitigated)
         activeLines[i].isMitigated = true;

      RenderInflectionLine(activeLines[i]);
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime t0 = iTime(_Symbol, _Period, 0);

   // Extend active lines to the current live bar
   UpdateMitigationAndExtendLive(t0);

   // Only check new inflection points upon new completed candle
   if(t0 == lastProcessedBarTime)
   {
      // Keep bar 0 HMA segment live
      double hmaLive[];
      if(CalculateHmaSeries(2, hmaLive))
      {
         datetime t1 = iTime(_Symbol, _Period, 1);
         DrawHMASegment(t1, hmaLive[1], t0, hmaLive[0], 0);
      }
      return;
   }

   // Bar close inspection
   double hma[];
   if(!CalculateHmaSeries(5, hma)) return;

   datetime t1 = iTime(_Symbol, _Period, 1);
   datetime t2 = iTime(_Symbol, _Period, 2);

   // Lock bar 1 segment
   DrawHMASegment(t2, hma[2], t1, hma[1], 1);

   // Check if bar 2 was an inflection pivot confirmed by bar 1
   ENUM_INFLECTION_TYPE detected = INFLECTION_NONE;
   if(hma[2] < hma[3] && hma[2] < hma[1])
      detected = INFLECTION_VALLEY;
   else if(hma[2] > hma[3] && hma[2] > hma[1])
      detected = INFLECTION_PEAK;

   if(detected != INFLECTION_NONE)
   {
      double rawPrice = hma[2];
      bool isValidDistance = false;

      if(!hasFirstInflection)
      {
         isValidDistance = true;
      }
      else
      {
         double diffPoints = MathAbs(rawPrice - lastValidRawPrice) / _Point;
         if(diffPoints >= InpMinDistancePoints)
            isValidDistance = true;
      }

      if(isValidDistance)
      {
         datetime pivotTime = t2;
         double offsetVal   = InpOffsetPoints * _Point;
         double lineLevel   = (detected == INFLECTION_VALLEY) ? (rawPrice + offsetVal) : (rawPrice - offsetVal);

         hasFirstInflection = true;
         lastValidRawPrice  = rawPrice;

         int idx = ArraySize(activeLines);
         ArrayResize(activeLines, idx + 1);

         activeLines[idx].name        = LINE_PREFIX + TimeToString(pivotTime, TIME_DATE|TIME_MINUTES);
         activeLines[idx].type        = detected;
         activeLines[idx].rawPrice    = rawPrice;
         activeLines[idx].lineLevel   = lineLevel;
         activeLines[idx].startTime   = pivotTime;
         activeLines[idx].endTime     = t0;
         activeLines[idx].isMitigated = false;

         RenderInflectionLine(activeLines[idx]);

         PrintFormat("v1.21: Valid %s inflection plotted at %s | Raw HMA: %.5f | Offset Level: %.5f",
                     (detected == INFLECTION_VALLEY ? "Valley" : "Peak"),
                     TimeToString(pivotTime), rawPrice, lineLevel);
      }
   }

   lastProcessedBarTime = t0;
   ChartRedraw(0);
}
//+------------------------------------------------------------------+
