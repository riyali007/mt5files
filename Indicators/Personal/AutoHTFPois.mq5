//+------------------------------------------------------------------+
//|                               Auto_Indi_SMC_MTF_Structure_v4.3.mq5|
//+------------------------------------------------------------------+
#property copyright "Senior Trading Systems Architect"
#property link      ""
#property version   "4.30"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

//--- Plot Bullish CHoCH/BOS Signal
#property indicator_label1  "Bullish Break"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLimeGreen
#property indicator_width1  2

//--- Plot Bearish CHoCH/BOS Signal
#property indicator_label2  "Bearish Break"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  2

//--- Inputs
sinput string         Settings = "--- MTF Market Structure Settings ---";
input ENUM_TIMEFRAMES InpHTF = PERIOD_H1;         // Structure Timeframe (HTF)
input ENUM_TIMEFRAMES InpHTF_OB = PERIOD_M15;     // Order Block Timeframe (LTF OB)
input int             InpMaxLookback = 3000;      // Max Historical LTF Candles
input int             InpPivotLeft = 5;           // HTF Pivot Left Strength
input int             InpPivotRight = 5;          // HTF Pivot Right Strength

sinput string         ExtraHTF_Settings = "--- 2 Extra HTF High/Low Settings ---";
input bool            InpShowExtraHTF = true;     // Show Previous HTF High/Lows
input ENUM_TIMEFRAMES InpExtraHTF1 = PERIOD_D1;   // Extra HTF 1 (e.g., Daily)
input ENUM_TIMEFRAMES InpExtraHTF2 = PERIOD_W1;   // Extra HTF 2 (e.g., Weekly)
input color           ClrExtraHTF1 = clrOrange;   // HTF 1 Line Color
input color           ClrExtraHTF2 = clrMagenta;  // HTF 2 Line Color

sinput string         Mitigation_Settings = "--- OB Mitigation Settings ---";
input int             InpGrayOutMinutes = 20;     // Minutes to keep OB/LQ boxes after mitigation

sinput string         Text_Settings = "--- Text & Alignment Settings ---";
input int             InpFontSize = 10;           // Text Font Size
input ENUM_ANCHOR_POINT InpBullTextAnchor = ANCHOR_LEFT_LOWER; // Bullish Text Anchor
input ENUM_ANCHOR_POINT InpBearTextAnchor = ANCHOR_LEFT_UPPER; // Bearish Text Anchor

sinput string         Visuals = "--- Visual Settings ---";
input color           ClrStructure = clrDimGray;  // HTF ZigZag Structure Color
input color           ClrPivotHigh = clrCrimson;  // HTF Pivot High Line Color
input color           ClrPivotLow = clrMediumSeaGreen; // HTF Pivot Low Line Color
input color           ClrBearOB = clrMidnightBlue;// Bearish OB Color
input color           ClrBearLQ = clrMaroon;      // Bearish Liquidity Box Color
input color           ClrBullOB = clrDarkSlateGray;// Bullish OB Color
input color           ClrBullLQ = clrDarkGreen;   // Bullish Liquidity Box Color
input color           ClriFVG = clrIndigo;        // iFVG Color
input color           ClrMitigated = clrDarkGray; // Grayed out mitigated color 

//--- Buffers
double BullBuffer[];
double BearBuffer[];

//--- Structs
struct HTFPivot {
   int      type;          
   double   price;         
   datetime pivotTime;     
   datetime confirmTime;   
};
HTFPivot pivots[];

struct ActivePOI {
   int      type;          
   datetime spawnTime;
   
   double   obTop, obBottom, obMid;
   double   lqTop, lqBottom, lqMid;
   
   bool     hasIFVG;
   double   ifvgTop, ifvgBottom;
   
   string   id;
   
   bool     obMitigated;
   datetime obMitigateTime;
   bool     obDeleted;
   
   bool     lqMitigated;
   datetime lqMitigateTime;
   bool     lqDeleted;
   
   bool     ifvgMitigated;
   datetime ifvgMitigateTime;
   bool     ifvgDeleted;
};
ActivePOI pois[];

//--- Global State Variables
double   g_actPH = 0;
double   g_actPL = 0;
string   g_namePH = "";
string   g_namePL = "";
int      g_trend = 0;      

datetime g_last_handled_pivot_time = 0;
datetime g_last_confirmed_PH_time = 0;
double   g_last_confirmed_PH_price = 0;
datetime g_last_confirmed_PL_time = 0;
double   g_last_confirmed_PL_price = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, BullBuffer, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_ARROW, 233); 
   SetIndexBuffer(1, BearBuffer, INDICATOR_DATA);
   PlotIndexSetInteger(1, PLOT_ARROW, 234); 
   
   ArrayInitialize(BullBuffer, EMPTY_VALUE);
   ArrayInitialize(BearBuffer, EMPTY_VALUE);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, "SMC_");
  }

//+------------------------------------------------------------------+
//| Visual Helpers                                                   |
//+------------------------------------------------------------------+
void DrawZigZag(string name, datetime t1, double p1, datetime t2, double p2)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, name, OBJPROP_COLOR, ClrStructure);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
     }
  }

void DrawLine(string name, datetime t1, double price, color clr, int style=STYLE_DASH)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t1, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, style);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
     }
  }

void DrawRay(string name, datetime t1, double price, color clr, string text)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t1 + 3600, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);

      string lblName = name + "_txt";
      ObjectCreate(0, lblName, OBJ_TEXT, 0, t1, price);
      ObjectSetString(0, lblName, OBJPROP_TEXT, text);
      ObjectSetInteger(0, lblName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, lblName, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0, lblName, OBJPROP_FONTSIZE, InpFontSize);
     }
   else
     {
      ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 1, price);

      string lblName = name + "_txt";
      ObjectSetInteger(0, lblName, OBJPROP_TIME, 0, t1);
      ObjectSetDouble(0, lblName, OBJPROP_PRICE, 0, price);
     }
  }

void DrawBox(string name, datetime t1, double p1, datetime t2, double p2, color clr)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
     }
   else
     {
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2); 
     }
  }

void DrawLabel(string name, datetime t, double p, string text, color clr, ENUM_ANCHOR_POINT anchor)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_TEXT, 0, t, p);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpFontSize);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
     }
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p);
  }

//+------------------------------------------------------------------+
//| POI (Order Block & iFVG) Creation Logic                          |
//+------------------------------------------------------------------+
void CreatePOI(int type, datetime originTime, datetime chochTime)
  {
   MqlRates obRates[];
   ArraySetAsSeries(obRates, false); 
   int copied = CopyRates(_Symbol, InpHTF_OB, originTime, originTime + PeriodSeconds(InpHTF), obRates);
   
   if(copied <= 0) return;
   
   double obTop = 0, obBottom = 0;
   
   if(type == -1) // Bearish
     {
      double maxH = -1; int maxIdx = -1;
      for(int i=0; i<copied; i++) if(obRates[i].high > maxH) { maxH = obRates[i].high; maxIdx = i; }
      if(maxIdx == -1) return;
      obTop = obRates[maxIdx].high;
      obBottom = obRates[maxIdx].low;
     }
   else // Bullish
     {
      double minL = 9999999; int minIdx = -1;
      for(int i=0; i<copied; i++) if(obRates[i].low < minL) { minL = obRates[i].low; minIdx = i; }
      if(minIdx == -1) return;
      obTop = obRates[minIdx].high;
      obBottom = obRates[minIdx].low;
     }

   // Overlap Check (Rule 7)
   for(int i=ArraySize(pois)-1; i>=0; i--)
     {
      if(pois[i].type == type && !pois[i].obDeleted)
        {
         if(obBottom <= pois[i].obTop && obTop >= pois[i].obBottom)
           {
            ObjectDelete(0, "SMC_OB_" + pois[i].id);
            ObjectDelete(0, "SMC_OBM_" + pois[i].id);
            ObjectDelete(0, "SMC_OBTXT_" + pois[i].id);
            ObjectDelete(0, "SMC_LQ_" + pois[i].id);
            ObjectDelete(0, "SMC_LQM_" + pois[i].id);
            ObjectDelete(0, "SMC_iFVG_" + pois[i].id);
            ObjectDelete(0, "SMC_iFVGTXT_" + pois[i].id);
            ArrayRemove(pois, i, 1);
           }
        }
     }

   // Construct New POI
   int sz = ArraySize(pois);
   ArrayResize(pois, sz + 1);
   
   pois[sz].type = type;
   pois[sz].spawnTime = chochTime; 
   pois[sz].id = IntegerToString(originTime) + "_" + IntegerToString(sz);
   
   pois[sz].obTop = obTop;
   pois[sz].obBottom = obBottom;
   pois[sz].obMid = (obTop + obBottom) / 2.0;
   
   double height = obTop - obBottom;
   if(type == -1) {
      pois[sz].lqBottom = obTop;
      pois[sz].lqTop = obTop + height;
   } else {
      pois[sz].lqTop = obBottom;
      pois[sz].lqBottom = obBottom - height;
   }
   pois[sz].lqMid = (pois[sz].lqTop + pois[sz].lqBottom) / 2.0;
   
   pois[sz].obMitigated = false; pois[sz].obDeleted = false;
   pois[sz].lqMitigated = false; pois[sz].lqDeleted = false;
   pois[sz].ifvgMitigated = false; pois[sz].ifvgDeleted = true; 
   pois[sz].hasIFVG = false;

   // Rule 6: Scan for iFVG
   MqlRates legRates[];
   ArraySetAsSeries(legRates, false);
   if(CopyRates(_Symbol, InpHTF_OB, originTime, chochTime, legRates) > 3)
     {
      if(type == -1) 
        {
         for(int i=0; i<ArraySize(legRates)-2; i++)
           {
            if(legRates[i].high < legRates[i+2].low) 
              {
               double fTop = legRates[i+2].low;
               double fBot = legRates[i].high;
               for(int j=i+2; j<ArraySize(legRates); j++)
                 {
                  if(legRates[j].close < fBot) 
                    {
                     pois[sz].hasIFVG = true;
                     pois[sz].ifvgTop = fTop;
                     pois[sz].ifvgBottom = fBot;
                     pois[sz].ifvgDeleted = false;
                     break;
                    }
                 }
               if(pois[sz].hasIFVG) break; 
              }
           }
        }
      else 
        {
         for(int i=0; i<ArraySize(legRates)-2; i++)
           {
            if(legRates[i].low > legRates[i+2].high) 
              {
               double fTop = legRates[i].low;
               double fBot = legRates[i+2].high;
               for(int j=i+2; j<ArraySize(legRates); j++)
                 {
                  if(legRates[j].close > fTop) 
                    {
                     pois[sz].hasIFVG = true;
                     pois[sz].ifvgTop = fTop;
                     pois[sz].ifvgBottom = fBot;
                     pois[sz].ifvgDeleted = false;
                     break;
                    }
                 }
               if(pois[sz].hasIFVG) break;
              }
           }
        }
     }
}

//+------------------------------------------------------------------+
//| Manage Active POIs (Extend, Mitigate, Delete)                    |
//+------------------------------------------------------------------+
void ProcessPOIs(datetime t, double c, double h, double l, bool isClosed)
  {
   for(int i=ArraySize(pois)-1; i>=0; i--)
     {
      string id = pois[i].id;
      color obClr = (pois[i].type == -1) ? ClrBearOB : ClrBullOB;
      color lqClr = (pois[i].type == -1) ? ClrBearLQ : ClrBullLQ;
      string zoneTxt = (pois[i].type == -1) ? "Sell Zone" : "Buy Zone";
      zoneTxt += " (" + DoubleToString(pois[i].obBottom, _Digits) + " - " + DoubleToString(pois[i].obTop, _Digits) + ")";

      // OB Logic
      if(!pois[i].obDeleted)
        {
         if(!pois[i].obMitigated)
           {
            if(isClosed && c <= pois[i].obTop && c >= pois[i].obBottom)
              {
               pois[i].obMitigated = true;
               pois[i].obMitigateTime = t;
               ObjectSetInteger(0, "SMC_OB_" + id, OBJPROP_COLOR, ClrMitigated);
               ObjectSetInteger(0, "SMC_OBTXT_" + id, OBJPROP_COLOR, ClrMitigated); 
              }
            else
              {
               DrawBox("SMC_OB_" + id, pois[i].spawnTime, pois[i].obTop, t, pois[i].obBottom, obClr);
               DrawLine("SMC_OBM_" + id, pois[i].spawnTime, pois[i].obMid, clrSilver, STYLE_DOT);
               ObjectSetInteger(0, "SMC_OBM_" + id, OBJPROP_TIME, 1, t); 
               
               double txtPrice = (pois[i].type == -1) ? pois[i].obBottom : pois[i].obTop;
               ENUM_ANCHOR_POINT anc = (pois[i].type == -1) ? InpBearTextAnchor : InpBullTextAnchor;
               DrawLabel("SMC_OBTXT_" + id, pois[i].spawnTime, txtPrice, zoneTxt, obClr, anc);
              }
           }
         else 
           {
            if(t >= pois[i].obMitigateTime + (InpGrayOutMinutes * 60))
              {
               ObjectDelete(0, "SMC_OB_" + id);
               ObjectDelete(0, "SMC_OBM_" + id);
               ObjectDelete(0, "SMC_OBTXT_" + id);
               pois[i].obDeleted = true;
              }
            else
              {
               ObjectSetInteger(0, "SMC_OB_" + id, OBJPROP_TIME, 1, t);
               ObjectSetInteger(0, "SMC_OBM_" + id, OBJPROP_TIME, 1, t);
              }
           }
        }

      // Liquidity Box Logic
      if(!pois[i].lqDeleted)
        {
         if(!pois[i].lqMitigated)
           {
            bool lqTapped = (pois[i].type == -1) ? (h >= pois[i].lqMid) : (l <= pois[i].lqMid);
            if(lqTapped)
              {
               pois[i].lqMitigated = true;
               pois[i].lqMitigateTime = t;
               ObjectSetInteger(0, "SMC_LQ_" + id, OBJPROP_COLOR, ClrMitigated);
              }
            else
              {
               DrawBox("SMC_LQ_" + id, pois[i].spawnTime, pois[i].lqTop, t, pois[i].lqBottom, lqClr);
               DrawLine("SMC_LQM_" + id, pois[i].spawnTime, pois[i].lqMid, clrSilver, STYLE_DOT);
               ObjectSetInteger(0, "SMC_LQM_" + id, OBJPROP_TIME, 1, t);
              }
           }
         else
           {
            if(t >= pois[i].lqMitigateTime + (InpGrayOutMinutes * 60))
              {
               ObjectDelete(0, "SMC_LQ_" + id);
               ObjectDelete(0, "SMC_LQM_" + id);
               pois[i].lqDeleted = true;
              }
            else
              {
               ObjectSetInteger(0, "SMC_LQ_" + id, OBJPROP_TIME, 1, t);
               ObjectSetInteger(0, "SMC_LQM_" + id, OBJPROP_TIME, 1, t);
              }
           }
        }

      // iFVG Logic 
      if(pois[i].hasIFVG && !pois[i].ifvgDeleted)
        {
         if(!pois[i].ifvgMitigated)
           {
            if(isClosed && c <= pois[i].ifvgTop && c >= pois[i].ifvgBottom)
              {
               pois[i].ifvgMitigated = true;
               pois[i].ifvgDeleted = true; 
               ObjectDelete(0, "SMC_iFVG_" + id);
               ObjectDelete(0, "SMC_iFVGTXT_" + id);
              }
            else
              {
               DrawBox("SMC_iFVG_" + id, pois[i].spawnTime, pois[i].ifvgTop, t, pois[i].ifvgBottom, ClriFVG);
               double txtPrice = (pois[i].type == -1) ? pois[i].ifvgBottom : pois[i].ifvgTop;
               ENUM_ANCHOR_POINT anc = (pois[i].type == -1) ? InpBearTextAnchor : InpBullTextAnchor;
               DrawLabel("SMC_iFVGTXT_" + id, pois[i].spawnTime, txtPrice, "iFVG", ClriFVG, anc);
              }
           }
        }

      if(pois[i].obDeleted && pois[i].lqDeleted && pois[i].ifvgDeleted)
        {
         ArrayRemove(pois, i, 1);
        }
     }
  }

//+------------------------------------------------------------------+
//| Strict Alternating Swing Logic                                   |
//+------------------------------------------------------------------+
void FilterPivots(MqlRates &htf[])
  {
   ArrayResize(pivots, 0);
   int lastType = 0; double lastExtreme = 0; datetime lastTime = 0;
   
   struct RawPivot { int type; double price; datetime time; };
   RawPivot raw[];
   
   for(int k = ArraySize(htf) - InpPivotLeft - 1; k >= InpPivotRight; k--)
     {
      bool isHigh = true;
      for(int j = 1; j <= InpPivotLeft; j++) if(htf[k+j].high >= htf[k].high) isHigh = false;
      for(int j = 1; j <= InpPivotRight; j++) if(htf[k-j].high >= htf[k].high) isHigh = false;
      if(isHigh) { int sz = ArraySize(raw); ArrayResize(raw, sz + 1); raw[sz].type = 1; raw[sz].price = htf[k].high; raw[sz].time = htf[k].time; }

      bool isLow = true;
      for(int j = 1; j <= InpPivotLeft; j++) if(htf[k+j].low <= htf[k].low) isLow = false;
      for(int j = 1; j <= InpPivotRight; j++) if(htf[k-j].low <= htf[k].low) isLow = false;
      if(isLow) { int sz = ArraySize(raw); ArrayResize(raw, sz + 1); raw[sz].type = -1; raw[sz].price = htf[k].low; raw[sz].time = htf[k].time; }
     }

   for(int i = 0; i < ArraySize(raw); i++)
     {
      if(lastType == 0) { lastType = raw[i].type; lastExtreme = raw[i].price; lastTime = raw[i].time; continue; }
      if(raw[i].type == lastType)
        {
         if((lastType == 1 && raw[i].price > lastExtreme) || (lastType == -1 && raw[i].price < lastExtreme))
           {
            lastExtreme = raw[i].price; lastTime = raw[i].time;
            int sz = ArraySize(pivots);
            if(sz > 0 && pivots[sz-1].type == lastType) { pivots[sz-1].price = lastExtreme; pivots[sz-1].pivotTime = lastTime; }
           }
        }
      else
        {
         int sz = ArraySize(pivots);
         if(sz == 0 || pivots[sz-1].pivotTime != lastTime)
           {
            ArrayResize(pivots, sz + 1);
            pivots[sz].type = lastType; pivots[sz].price = lastExtreme; pivots[sz].pivotTime = lastTime;
            int confirmIdx = iBarShift(_Symbol, InpHTF, lastTime) - InpPivotRight;
            if(confirmIdx >= 0) pivots[sz].confirmTime = iTime(_Symbol, InpHTF, confirmIdx) + PeriodSeconds(InpHTF);
           }
         lastType = raw[i].type; lastExtreme = raw[i].price; lastTime = raw[i].time;
        }
     }
   if(lastType != 0)
     {
      int sz = ArraySize(pivots); ArrayResize(pivots, sz + 1);
      pivots[sz].type = lastType; pivots[sz].price = lastExtreme; pivots[sz].pivotTime = lastTime;
      int confirmIdx = iBarShift(_Symbol, InpHTF, lastTime) - InpPivotRight;
      if(confirmIdx >= 0) pivots[sz].confirmTime = iTime(_Symbol, InpHTF, confirmIdx) + PeriodSeconds(InpHTF);
     }
  }

//+------------------------------------------------------------------+
//| Main Indicator Iteration                                         |
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
   ArraySetAsSeries(time, true); ArraySetAsSeries(high, true); ArraySetAsSeries(low, true); ArraySetAsSeries(close, true);
   int limit = rates_total - prev_calculated;

   if (prev_calculated == 0)
     {
      limit = MathMin(InpMaxLookback, rates_total - 2);
      ObjectsDeleteAll(0, "SMC_");
      ArrayInitialize(BullBuffer, EMPTY_VALUE); ArrayInitialize(BearBuffer, EMPTY_VALUE);
      ArrayResize(pois, 0);
      g_actPH = 0; g_actPL = 0; g_trend = 0; 
      g_last_handled_pivot_time = 0;
      g_last_confirmed_PH_time = 0; g_last_confirmed_PL_time = 0;
     }

   int htfBarsNeeded = (InpMaxLookback * PeriodSeconds(PERIOD_CURRENT) / PeriodSeconds(InpHTF)) + 200;
   MqlRates htf[]; ArraySetAsSeries(htf, true);
   if(CopyRates(_Symbol, InpHTF, 0, htfBarsNeeded, htf) < InpPivotLeft + InpPivotRight + 1) return prev_calculated;
   
   FilterPivots(htf);

   if (limit < 0) limit = 0;

   for (int i = limit; i >= 0; i--)
     {
      datetime t = time[i];

      // 1. Activate newly confirmed pivots sequentially
      for(int p = 0; p < ArraySize(pivots); p++)
        {
         if(pivots[p].confirmTime <= t && pivots[p].pivotTime > g_last_handled_pivot_time)
           {
            if(pivots[p].type == 1) 
              {
               g_actPH = pivots[p].price;
               g_last_confirmed_PH_time = pivots[p].pivotTime;
               g_last_confirmed_PH_price = pivots[p].price;
               g_namePH = "SMC_PH_" + IntegerToString(pivots[p].pivotTime);
               DrawLine(g_namePH, pivots[p].pivotTime, g_actPH, ClrPivotHigh);
              }
            else 
              {
               g_actPL = pivots[p].price;
               g_last_confirmed_PL_time = pivots[p].pivotTime;
               g_last_confirmed_PL_price = pivots[p].price;
               g_namePL = "SMC_PL_" + IntegerToString(pivots[p].pivotTime);
               DrawLine(g_namePL, pivots[p].pivotTime, g_actPL, ClrPivotLow);
              }
            g_last_handled_pivot_time = pivots[p].pivotTime;
           }
        }

      if(g_actPH > 0) ObjectSetInteger(0, g_namePH, OBJPROP_TIME, 1, t);
      if(g_actPL > 0) ObjectSetInteger(0, g_namePL, OBJPROP_TIME, 1, t);

      // 2. Evaluate structural breaks ONLY on closed candles
      if (i > 0)
        {
         if(g_actPH > 0 && close[i] > g_actPH)
           {
            BullBuffer[i] = low[i] - (15 * _Point);
            string label = (g_trend <= 0) ? "HTF CHoCH" : "HTF BOS";
            DrawLabel("SMC_LBL_" + IntegerToString(t), t, high[i] + (10 * _Point), label, clrLimeGreen, InpBullTextAnchor);
            
            if(g_trend <= 0 && g_last_confirmed_PL_time != 0) 
               CreatePOI(1, g_last_confirmed_PL_time, t); 
               
            g_actPH = 0; g_trend = 1;
           }
           
         if(g_actPL > 0 && close[i] < g_actPL)
           {
            BearBuffer[i] = high[i] + (15 * _Point);
            string label = (g_trend >= 0) ? "HTF CHoCH" : "HTF BOS";
            DrawLabel("SMC_LBL_" + IntegerToString(t), t, low[i] - (10 * _Point), label, clrRed, InpBearTextAnchor);
            
            if(g_trend >= 0 && g_last_confirmed_PH_time != 0) 
               CreatePOI(-1, g_last_confirmed_PH_time, t); 
               
            g_actPL = 0; g_trend = -1;
           }
        }

      // 3. Process mitigations
      bool isClosedCandle = (i > 0);
      ProcessPOIs(t, close[i], high[i], low[i], isClosedCandle);
      
      // 4. Draw 2 Extra HTF High/Lows (Evaluated dynamically at the live edge or end of loop)
      if(InpShowExtraHTF && i == 0)
        {
         datetime start1 = iTime(_Symbol, InpExtraHTF1, 0);
         double h1 = iHigh(_Symbol, InpExtraHTF1, 1);
         double l1 = iLow(_Symbol, InpExtraHTF1, 1);
         
         if(start1 > 0 && h1 > 0 && l1 > 0)
           {
            DrawRay("SMC_EHTF1_H", start1, h1, ClrExtraHTF1, EnumToString(InpExtraHTF1) + " Prev High");
            DrawRay("SMC_EHTF1_L", start1, l1, ClrExtraHTF1, EnumToString(InpExtraHTF1) + " Prev Low");
           }
           
         datetime start2 = iTime(_Symbol, InpExtraHTF2, 0);
         double h2 = iHigh(_Symbol, InpExtraHTF2, 1);
         double l2 = iLow(_Symbol, InpExtraHTF2, 1);
         
         if(start2 > 0 && h2 > 0 && l2 > 0)
           {
            DrawRay("SMC_EHTF2_H", start2, h2, ClrExtraHTF2, EnumToString(InpExtraHTF2) + " Prev High");
            DrawRay("SMC_EHTF2_L", start2, l2, ClrExtraHTF2, EnumToString(InpExtraHTF2) + " Prev Low");
           }
        }
     }

   return rates_total;
  }
//+------------------------------------------------------------------+