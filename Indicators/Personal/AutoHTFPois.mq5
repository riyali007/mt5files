//+------------------------------------------------------------------+
//|                                                AutoHTFPois.mq5   |
//|      HTF-Cached SMC Structure — Recalculates ONLY on HTF Close   |
//+------------------------------------------------------------------+
#property copyright "Senior Trading Systems Architect"
#property link      ""
#property version   "8.00"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

#property indicator_label1 "Bullish Break"
#property indicator_type1  DRAW_ARROW
#property indicator_color1 clrLimeGreen
#property indicator_width1 2

#property indicator_label2 "Bearish Break"
#property indicator_type2  DRAW_ARROW
#property indicator_color2 clrRed
#property indicator_width2 2

sinput string Settings = "--- MTF Market Structure Settings ---";
input ENUM_TIMEFRAMES InpHTF = PERIOD_H1;
input ENUM_TIMEFRAMES InpHTF_OB = PERIOD_M15;
input int InpMaxLookback = 1500;
input int InpPivotLeft = 5;
input int InpPivotRight = 5;

sinput string ExtraHTF_Settings = "--- 2 Extra HTF High/Low Settings ---";
input bool InpShowExtraHTF = true;
input ENUM_TIMEFRAMES InpExtraHTF1 = PERIOD_D1;
input ENUM_TIMEFRAMES InpExtraHTF2 = PERIOD_W1;
input color ClrExtraHTF1 = clrOrange;
input color ClrExtraHTF2 = clrMagenta;

sinput string Mitigation_Settings = "--- OB Mitigation Settings ---";
input int InpGrayOutMinutes = 20;

sinput string Text_Settings = "--- Text & Alignment Settings ---";
input int InpFontSize = 10;
input ENUM_ANCHOR_POINT InpBullTextAnchor = ANCHOR_LEFT_LOWER;
input ENUM_ANCHOR_POINT InpBearTextAnchor = ANCHOR_LEFT_UPPER;

sinput string Visuals = "--- Visual Settings ---";
input color ClrStructure = clrDimGray;
input color ClrPivotHigh = clrCrimson;
input color ClrPivotLow = clrMediumSeaGreen;
input color ClrBearOB = clrMidnightBlue;
input color ClrBearLQ = clrMaroon;
input color ClrBullOB = clrDarkSlateGray;
input color ClrBullLQ = clrDarkGreen;
input color ClriFVG = clrIndigo;
input color ClrMitigated = clrDarkGray;

sinput string Perf_Settings = "--- Performance ---";
input int InpMaxActivePOIs = 12;

double BullBuffer[];
double BearBuffer[];

struct HTFPivot { int type; double price; datetime pivotTime; datetime confirmTime; };

struct ActivePOI {
   int type;
   datetime spawnTime;
   double obTop, obBottom, obMid;
   double lqTop, lqBottom, lqMid;
   bool hasIFVG;
   double ifvgTop, ifvgBottom;
   string id;
   bool obMitigated; datetime obMitigateTime; bool obDeleted;
   bool lqMitigated; datetime lqMitigateTime; bool lqDeleted;
   bool ifvgMitigated; datetime ifvgMitigateTime; bool ifvgDeleted;
   datetime lastExtendedTime;
};

HTFPivot pivots[];
ActivePOI pois[];

double   g_actPH = 0, g_actPL = 0;
string   g_namePH = "", g_namePL = "";
int      g_trend = 0;

datetime g_last_handled_pivot_time = 0;
datetime g_last_confirmed_PH_time = 0;
double   g_last_confirmed_PH_price = 0;
datetime g_last_confirmed_PL_time = 0;
double   g_last_confirmed_PL_price = 0;

datetime g_last_bar1_time = 0;
datetime g_last_recalc_htf_time = 0;   // HTF bar-open-time of the last completed structural recalculation
string   g_source_sym = "";
datetime g_last_live_extend_time = 0;

string   g_cache_key = "";              // Unique key: symbol + HTF settings (independent of chart TF)
string   g_gv_htf_time = "";             // GlobalVariable name storing last recalculated HTF bar time
string   g_gv_trend    = "";
string   g_gv_ph_time  = "";
string   g_gv_ph_price = "";
string   g_gv_pl_time  = "";
string   g_gv_pl_price = "";
string   g_gv_last_pivot = "";
string   g_obj_prefix  = "";             // Object name prefix, unique per cache key so multiple HTF settings can coexist

//+------------------------------------------------------------------+
string GetSourceSymbol()
{
   if(StringFind(_Symbol, "SIM.") == 0) return StringSubstr(_Symbol, 4);
   return _Symbol;
}

// Builds a cache identity independent of chart's visible timeframe (PERIOD_CURRENT).
void BuildCacheKey()
{
   g_cache_key = g_source_sym + "_" + EnumToString(InpHTF) + "_" + EnumToString(InpHTF_OB) + "_" +
                 IntegerToString(InpPivotLeft) + "_" + IntegerToString(InpPivotRight);

   g_obj_prefix   = "SMC_" + g_cache_key + "_";
   g_gv_htf_time  = "SMCCache_" + g_cache_key + "_htftime";
   g_gv_trend     = "SMCCache_" + g_cache_key + "_trend";
   g_gv_ph_time   = "SMCCache_" + g_cache_key + "_phtime";
   g_gv_ph_price  = "SMCCache_" + g_cache_key + "_phprice";
   g_gv_pl_time   = "SMCCache_" + g_cache_key + "_pltime";
   g_gv_pl_price  = "SMCCache_" + g_cache_key + "_plprice";
   g_gv_last_pivot= "SMCCache_" + g_cache_key + "_lastpivot";
}

int OnInit()
{
   g_source_sym = GetSourceSymbol();
   BuildCacheKey();

   SetIndexBuffer(0, BullBuffer, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   SetIndexBuffer(1, BearBuffer, INDICATOR_DATA);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);
   ArrayInitialize(BullBuffer, EMPTY_VALUE);
   ArrayInitialize(BearBuffer, EMPTY_VALUE);

   g_last_bar1_time = 0;
   g_last_live_extend_time = 0;

   // Restore cached HTF recalculation state (survives chart timeframe switches within this terminal session)
   if(GlobalVariableCheck(g_gv_htf_time))
   {
      g_last_recalc_htf_time  = (datetime)GlobalVariableGet(g_gv_htf_time);
      g_trend                 = (int)GlobalVariableGet(g_gv_trend);
      g_last_confirmed_PH_time  = (datetime)GlobalVariableGet(g_gv_ph_time);
      g_last_confirmed_PH_price = GlobalVariableGet(g_gv_ph_price);
      g_last_confirmed_PL_time  = (datetime)GlobalVariableGet(g_gv_pl_time);
      g_last_confirmed_PL_price = GlobalVariableGet(g_gv_pl_price);
      g_last_handled_pivot_time = (datetime)GlobalVariableGet(g_gv_last_pivot);

      g_actPH = (g_trend <= 0) ? g_last_confirmed_PH_price : 0;
      g_actPL = (g_trend >= 0) ? g_last_confirmed_PL_price : 0;
      g_namePH = g_obj_prefix + "PH_" + IntegerToString(g_last_confirmed_PH_time);
      g_namePL = g_obj_prefix + "PL_" + IntegerToString(g_last_confirmed_PL_time);
   }
   else
   {
      g_last_recalc_htf_time = 0; // no cache yet -> forces one full build on first OnCalculate
   }

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   // Never delete cached objects on TF switch, template reload, or recompile — only on manual removal.
   if(reason == REASON_REMOVE)
      ObjectsDeleteAll(0, g_obj_prefix);
}

void PersistCacheState()
{
   GlobalVariableSet(g_gv_htf_time, (double)g_last_recalc_htf_time);
   GlobalVariableSet(g_gv_trend, (double)g_trend);
   GlobalVariableSet(g_gv_ph_time, (double)g_last_confirmed_PH_time);
   GlobalVariableSet(g_gv_ph_price, g_last_confirmed_PH_price);
   GlobalVariableSet(g_gv_pl_time, (double)g_last_confirmed_PL_time);
   GlobalVariableSet(g_gv_pl_price, g_last_confirmed_PL_price);
   GlobalVariableSet(g_gv_last_pivot, (double)g_last_handled_pivot_time);
}

//+------------------------------------------------------------------+
//| Visual Helpers                                                   |
//+------------------------------------------------------------------+
void DrawLine(string name, datetime t1, double price, color clr, int style=STYLE_DASH)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t1, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, style);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
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
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);

      string lblName = name + "_txt";
      ObjectCreate(0, lblName, OBJ_TEXT, 0, t1, price);
      ObjectSetString(0, lblName, OBJPROP_TEXT, text);
      ObjectSetInteger(0, lblName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, lblName, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0, lblName, OBJPROP_FONTSIZE, InpFontSize);
      ObjectSetInteger(0, lblName, OBJPROP_SELECTABLE, false);
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
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
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
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p);
}

void DeletePOIObjects(string id)
{
   ObjectDelete(0, g_obj_prefix + "OB_" + id);
   ObjectDelete(0, g_obj_prefix + "OBM_" + id);
   ObjectDelete(0, g_obj_prefix + "OBTXT_" + id);
   ObjectDelete(0, g_obj_prefix + "LQ_" + id);
   ObjectDelete(0, g_obj_prefix + "LQM_" + id);
   ObjectDelete(0, g_obj_prefix + "iFVG_" + id);
   ObjectDelete(0, g_obj_prefix + "iFVGTXT_" + id);
}

//+------------------------------------------------------------------+
//| POI Creation                                                      |
//+------------------------------------------------------------------+
void CreatePOI(int type, datetime originTime, datetime chochTime)
{
   MqlRates obRates[];
   ArraySetAsSeries(obRates, false);
   int copied = CopyRates(g_source_sym, InpHTF_OB, originTime, originTime + PeriodSeconds(InpHTF), obRates);
   if(copied <= 0) return;

   double obTop = 0, obBottom = 0;
   if(type == -1)
   {
      double maxH = -1; int maxIdx = -1;
      for(int i=0; i<copied; i++) { if(obRates[i].high > maxH) { maxH = obRates[i].high; maxIdx = i; } }
      if(maxIdx == -1) return;
      obTop = obRates[maxIdx].high; obBottom = obRates[maxIdx].low;
   }
   else
   {
      double minL = 999999999; int minIdx = -1;
      for(int i=0; i<copied; i++) { if(obRates[i].low < minL) { minL = obRates[i].low; minIdx = i; } }
      if(minIdx == -1) return;
      obTop = obRates[minIdx].high; obBottom = obRates[minIdx].low;
   }

   for(int i = ArraySize(pois)-1; i >= 0; i--)
   {
      if(pois[i].type == type && !pois[i].obDeleted)
      {
         if(obBottom <= pois[i].obTop && obTop >= pois[i].obBottom)
         {
            DeletePOIObjects(pois[i].id);
            ArrayRemove(pois, i, 1);
         }
      }
   }

   if(ArraySize(pois) >= InpMaxActivePOIs)
   {
      DeletePOIObjects(pois[0].id);
      ArrayRemove(pois, 0, 1);
   }

   int sz = ArraySize(pois);
   ArrayResize(pois, sz + 1);
   pois[sz].type = type;
   pois[sz].spawnTime = chochTime;
   pois[sz].id = IntegerToString(originTime) + "_" + IntegerToString(sz) + "_" + IntegerToString(GetTickCount());
   pois[sz].obTop = obTop;
   pois[sz].obBottom = obBottom;
   pois[sz].obMid = (obTop + obBottom) / 2.0;

   double height = obTop - obBottom;
   if(type == -1) { pois[sz].lqBottom = obTop; pois[sz].lqTop = obTop + height; }
   else            { pois[sz].lqTop = obBottom; pois[sz].lqBottom = obBottom - height; }
   pois[sz].lqMid = (pois[sz].lqTop + pois[sz].lqBottom) / 2.0;

   pois[sz].obMitigated = false; pois[sz].obDeleted = false;
   pois[sz].lqMitigated = false; pois[sz].lqDeleted = false;
   pois[sz].ifvgMitigated = false; pois[sz].ifvgDeleted = true;
   pois[sz].hasIFVG = false;
   pois[sz].lastExtendedTime = 0;

   MqlRates legRates[];
   ArraySetAsSeries(legRates, false);
   int legCopied = CopyRates(g_source_sym, InpHTF_OB, originTime, chochTime, legRates);
   if(legCopied > 3)
   {
      if(type == -1)
      {
         for(int i=0; i < legCopied - 2; i++)
         {
            if(legRates[i].low > legRates[i+2].high)
            {
               double fTop = legRates[i].low, fBot = legRates[i+2].high;
               for(int j=i+2; j < legCopied; j++)
               {
                  if(legRates[j].close > fTop)
                  { pois[sz].hasIFVG = true; pois[sz].ifvgTop = fTop; pois[sz].ifvgBottom = fBot; pois[sz].ifvgDeleted = false; break; }
               }
               if(pois[sz].hasIFVG) break;
            }
         }
      }
      else
      {
         for(int i=0; i < legCopied - 2; i++)
         {
            if(legRates[i].high < legRates[i+2].low)
            {
               double fBot = legRates[i].high, fTop = legRates[i+2].low;
               for(int j=i+2; j < legCopied; j++)
               {
                  if(legRates[j].close < fBot)
                  { pois[sz].hasIFVG = true; pois[sz].ifvgTop = fTop; pois[sz].ifvgBottom = fBot; pois[sz].ifvgDeleted = false; break; }
               }
               if(pois[sz].hasIFVG) break;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
void EvaluatePOIMitigation(datetime t, double c, double h, double l, bool isClosed)
{
   for(int i=ArraySize(pois)-1; i>=0; i--)
   {
      if(!pois[i].obDeleted && !pois[i].obMitigated)
      {
         if(isClosed && c <= pois[i].obTop && c >= pois[i].obBottom)
         {
            pois[i].obMitigated = true;
            pois[i].obMitigateTime = t;
            ObjectSetInteger(0, g_obj_prefix + "OB_" + pois[i].id, OBJPROP_COLOR, ClrMitigated);
            ObjectSetInteger(0, g_obj_prefix + "OBTXT_" + pois[i].id, OBJPROP_COLOR, ClrMitigated);
         }
      }
      else if(pois[i].obMitigated && !pois[i].obDeleted)
      {
         if(t >= pois[i].obMitigateTime + (InpGrayOutMinutes * 60))
         {
            ObjectDelete(0, g_obj_prefix + "OB_" + pois[i].id);
            ObjectDelete(0, g_obj_prefix + "OBM_" + pois[i].id);
            ObjectDelete(0, g_obj_prefix + "OBTXT_" + pois[i].id);
            pois[i].obDeleted = true;
         }
      }

      if(!pois[i].lqDeleted && !pois[i].lqMitigated)
      {
         bool lqTapped = (pois[i].type == -1) ? (h >= pois[i].lqMid) : (l <= pois[i].lqMid);
         if(lqTapped)
         {
            pois[i].lqMitigated = true;
            pois[i].lqMitigateTime = t;
            ObjectSetInteger(0, g_obj_prefix + "LQ_" + pois[i].id, OBJPROP_COLOR, ClrMitigated);
         }
      }
      else if(pois[i].lqMitigated && !pois[i].lqDeleted)
      {
         if(t >= pois[i].lqMitigateTime + (InpGrayOutMinutes * 60))
         {
            ObjectDelete(0, g_obj_prefix + "LQ_" + pois[i].id);
            ObjectDelete(0, g_obj_prefix + "LQM_" + pois[i].id);
            pois[i].lqDeleted = true;
         }
      }

      if(pois[i].hasIFVG && !pois[i].ifvgDeleted && !pois[i].ifvgMitigated)
      {
         if(isClosed && c <= pois[i].ifvgTop && c >= pois[i].ifvgBottom)
         {
            pois[i].ifvgMitigated = true;
            pois[i].ifvgDeleted = true;
            ObjectDelete(0, g_obj_prefix + "iFVG_" + pois[i].id);
            ObjectDelete(0, g_obj_prefix + "iFVGTXT_" + pois[i].id);
         }
      }

      if(pois[i].obDeleted && pois[i].lqDeleted && pois[i].ifvgDeleted)
         ArrayRemove(pois, i, 1);
   }
}

void DrawActivePOIs(datetime t)
{
   for(int i=ArraySize(pois)-1; i>=0; i--)
   {
      if(pois[i].lastExtendedTime == t) continue;
      color obClr = (pois[i].type == -1) ? ClrBearOB : ClrBullOB;
      color lqClr = (pois[i].type == -1) ? ClrBearLQ : ClrBullLQ;

      if(!pois[i].obDeleted)
      {
         if(!pois[i].obMitigated)
         {
            string zoneTxt = (pois[i].type == -1) ? "Sell Zone" : "Buy Zone";
            zoneTxt += " (" + DoubleToString(pois[i].obBottom, _Digits) + " - " + DoubleToString(pois[i].obTop, _Digits) + ")";
            DrawBox(g_obj_prefix + "OB_" + pois[i].id, pois[i].spawnTime, pois[i].obTop, t, pois[i].obBottom, obClr);
            DrawLine(g_obj_prefix + "OBM_" + pois[i].id, pois[i].spawnTime, pois[i].obMid, clrSilver, STYLE_DOT);
            ObjectSetInteger(0, g_obj_prefix + "OBM_" + pois[i].id, OBJPROP_TIME, 1, t);
            double txtPrice = (pois[i].type == -1) ? pois[i].obBottom : pois[i].obTop;
            ENUM_ANCHOR_POINT anc = (pois[i].type == -1) ? InpBearTextAnchor : InpBullTextAnchor;
            DrawLabel(g_obj_prefix + "OBTXT_" + pois[i].id, pois[i].spawnTime, txtPrice, zoneTxt, obClr, anc);
         }
         else
         {
            ObjectSetInteger(0, g_obj_prefix + "OB_" + pois[i].id, OBJPROP_TIME, 1, t);
            ObjectSetInteger(0, g_obj_prefix + "OBM_" + pois[i].id, OBJPROP_TIME, 1, t);
         }
      }

      if(!pois[i].lqDeleted)
      {
         if(!pois[i].lqMitigated)
         {
            DrawBox(g_obj_prefix + "LQ_" + pois[i].id, pois[i].spawnTime, pois[i].lqTop, t, pois[i].lqBottom, lqClr);
            DrawLine(g_obj_prefix + "LQM_" + pois[i].id, pois[i].spawnTime, pois[i].lqMid, clrSilver, STYLE_DOT);
            ObjectSetInteger(0, g_obj_prefix + "LQM_" + pois[i].id, OBJPROP_TIME, 1, t);
         }
         else
         {
            ObjectSetInteger(0, g_obj_prefix + "LQ_" + pois[i].id, OBJPROP_TIME, 1, t);
            ObjectSetInteger(0, g_obj_prefix + "LQM_" + pois[i].id, OBJPROP_TIME, 1, t);
         }
      }

      if(pois[i].hasIFVG && !pois[i].ifvgDeleted && !pois[i].ifvgMitigated)
      {
         DrawBox(g_obj_prefix + "iFVG_" + pois[i].id, pois[i].spawnTime, pois[i].ifvgTop, t, pois[i].ifvgBottom, ClriFVG);
         double txtPrice = (pois[i].type == -1) ? pois[i].ifvgBottom : pois[i].ifvgTop;
         ENUM_ANCHOR_POINT anc = (pois[i].type == -1) ? InpBearTextAnchor : InpBullTextAnchor;
         DrawLabel(g_obj_prefix + "iFVGTXT_" + pois[i].id, pois[i].spawnTime, txtPrice, "iFVG", ClriFVG, anc);
      }

      pois[i].lastExtendedTime = t;
   }
}

//+------------------------------------------------------------------+
void FilterPivots(MqlRates &htf[])
{
   ArrayResize(pivots, 0);
   int lastType = 0; double lastExtreme = 0; datetime lastTime = 0;
   struct RawPivot { int type; double price; datetime time; };
   RawPivot raw[];

   int htfSize = ArraySize(htf);
   for(int k = htfSize - InpPivotLeft - 1; k >= InpPivotRight; k--)
   {
      bool isHigh = true;
      for(int j = 1; j <= InpPivotLeft; j++) if(htf[k+j].high >= htf[k].high) { isHigh = false; break; }
      if(isHigh) for(int j = 1; j <= InpPivotRight; j++) if(htf[k-j].high >= htf[k].high) { isHigh = false; break; }
      if(isHigh) { int sz = ArraySize(raw); ArrayResize(raw, sz + 1); raw[sz].type = 1; raw[sz].price = htf[k].high; raw[sz].time = htf[k].time; }

      bool isLow = true;
      for(int j = 1; j <= InpPivotLeft; j++) if(htf[k+j].low <= htf[k].low) { isLow = false; break; }
      if(isLow) for(int j = 1; j <= InpPivotRight; j++) if(htf[k-j].low <= htf[k].low) { isLow = false; break; }
      if(isLow) { int sz = ArraySize(raw); ArrayResize(raw, sz + 1); raw[sz].type = -1; raw[sz].price = htf[k].low; raw[sz].time = htf[k].time; }
   }

   int rawSize = ArraySize(raw);
   for(int i = 0; i < rawSize; i++)
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
            pivots[sz].confirmTime = lastTime + (InpPivotRight + 1) * PeriodSeconds(InpHTF);
         }
         lastType = raw[i].type; lastExtreme = raw[i].price; lastTime = raw[i].time;
      }
   }
   if(lastType != 0)
   {
      int sz = ArraySize(pivots); ArrayResize(pivots, sz + 1);
      pivots[sz].type = lastType; pivots[sz].price = lastExtreme; pivots[sz].pivotTime = lastTime;
      pivots[sz].confirmTime = lastTime + (InpPivotRight + 1) * PeriodSeconds(InpHTF);
   }
}

//+------------------------------------------------------------------+
//| Full rebuild — runs ONLY when no valid cache exists for this key |
//+------------------------------------------------------------------+
void RecalculateFull(const datetime &time[], const double &high[], const double &low[], const double &close[], int count, datetime currentSimTime)
{
   ObjectsDeleteAll(0, g_obj_prefix);
   ArrayInitialize(BullBuffer, EMPTY_VALUE);
   ArrayInitialize(BearBuffer, EMPTY_VALUE);
   ArrayResize(pois, 0);

   g_actPH = 0; g_actPL = 0; g_trend = 0;
   g_last_handled_pivot_time = 0;
   g_last_confirmed_PH_time = 0; g_last_confirmed_PL_time = 0;

   int htfBarsNeeded = (InpMaxLookback * PeriodSeconds(PERIOD_CURRENT) / PeriodSeconds(InpHTF)) + 200;
   MqlRates htf[];
   ArraySetAsSeries(htf, true);
   int copiedHTF = CopyRates(g_source_sym, InpHTF, currentSimTime, htfBarsNeeded, htf);
   if(copiedHTF < InpPivotLeft + InpPivotRight + 1) return;

   FilterPivots(htf);

   for(int i = count; i >= 1; i--)
   {
      datetime t = time[i];
      for(int p = 0; p < ArraySize(pivots); p++)
      {
         if(pivots[p].confirmTime <= t && pivots[p].pivotTime > g_last_handled_pivot_time)
         {
            if(pivots[p].type == 1)
            {
               g_actPH = pivots[p].price;
               g_last_confirmed_PH_time = pivots[p].pivotTime;
               g_last_confirmed_PH_price = pivots[p].price;
               g_namePH = g_obj_prefix + "PH_" + IntegerToString(pivots[p].pivotTime);
            }
            else
            {
               g_actPL = pivots[p].price;
               g_last_confirmed_PL_time = pivots[p].pivotTime;
               g_last_confirmed_PL_price = pivots[p].price;
               g_namePL = g_obj_prefix + "PL_" + IntegerToString(pivots[p].pivotTime);
            }
            g_last_handled_pivot_time = pivots[p].pivotTime;
         }
      }

      if(g_actPH > 0 && close[i] > g_actPH)
      {
         BullBuffer[i] = low[i] - (15 * _Point);
         if(g_trend <= 0 && g_last_confirmed_PL_time != 0) CreatePOI(1, g_last_confirmed_PL_time, t);
         g_actPH = 0; g_trend = 1;
      }
      if(g_actPL > 0 && close[i] < g_actPL)
      {
         BearBuffer[i] = high[i] + (15 * _Point);
         if(g_trend >= 0 && g_last_confirmed_PH_time != 0) CreatePOI(-1, g_last_confirmed_PH_time, t);
         g_actPL = 0; g_trend = -1;
      }

      EvaluatePOIMitigation(t, close[i], high[i], low[i], true);
   }

   if(g_actPH > 0) { DrawLine(g_namePH, g_last_confirmed_PH_time, g_actPH, ClrPivotHigh); ObjectSetInteger(0, g_namePH, OBJPROP_TIME, 1, time[0]); }
   if(g_actPL > 0) { DrawLine(g_namePL, g_last_confirmed_PL_time, g_actPL, ClrPivotLow); ObjectSetInteger(0, g_namePL, OBJPROP_TIME, 1, time[0]); }

   DrawActivePOIs(time[0]);

   datetime htfBarTimeNow = currentSimTime - (currentSimTime % PeriodSeconds(InpHTF));
   g_last_recalc_htf_time = htfBarTimeNow;
   PersistCacheState();
}

//+------------------------------------------------------------------+
void UpdateExtraHTF(datetime currentSimTime)
{
   if(!InpShowExtraHTF) return;
   MqlRates r1[];
   if(CopyRates(g_source_sym, InpExtraHTF1, currentSimTime, 2, r1) >= 2)
   {
      DrawRay(g_obj_prefix + "EHTF1_H", r1[1].time, r1[0].high, ClrExtraHTF1, EnumToString(InpExtraHTF1) + " Prev High");
      DrawRay(g_obj_prefix + "EHTF1_L", r1[1].time, r1[0].low,  ClrExtraHTF1, EnumToString(InpExtraHTF1) + " Prev Low");
   }
   MqlRates r2[];
   if(CopyRates(g_source_sym, InpExtraHTF2, currentSimTime, 2, r2) >= 2)
   {
      DrawRay(g_obj_prefix + "EHTF2_H", r2[1].time, r2[0].high, ClrExtraHTF2, EnumToString(InpExtraHTF2) + " Prev High");
      DrawRay(g_obj_prefix + "EHTF2_L", r2[1].time, r2[0].low,  ClrExtraHTF2, EnumToString(InpExtraHTF2) + " Prev Low");
   }
}

//+------------------------------------------------------------------+
//| Main OnCalculate                                                  |
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
   if(rates_total < InpPivotLeft + InpPivotRight + 2) return 0;

   ArraySetAsSeries(time, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   datetime currentSimTime = time[0];
   datetime htfBarTime = currentSimTime - (currentSimTime % PeriodSeconds(InpHTF));

   bool haveExistingObjects = (ObjectFind(0, g_namePH) >= 0) || (ObjectFind(0, g_namePL) >= 0) || (ArraySize(pois) > 0);

   // CASE A: True first-ever build for this cache key (no GlobalVariable, no cached objects, no PH/PL yet)
   if(g_last_recalc_htf_time == 0)
   {
      int limit = MathMin(InpMaxLookback, rates_total - 2);
      RecalculateFull(time, high, low, close, limit, currentSimTime);
      g_last_bar1_time = time[1];
      UpdateExtraHTF(currentSimTime);
      return rates_total;
   }

   // CASE B: Indicator reloaded (e.g. chart TF switch) but a valid cache already exists for this HTF bar.
   // Objects are still sitting on the chart (they were never deleted) — just resume live processing,
   // no recompute, no redraw. This is the "cached objects regardless of chart TF" behavior.
   if(prev_calculated == 0 && htfBarTime == g_last_recalc_htf_time && haveExistingObjects)
   {
      g_last_bar1_time = time[1];
      // still make sure the pivot line/extra-HTF rays reach the current right edge
      if(g_actPH > 0) ObjectSetInteger(0, g_namePH, OBJPROP_TIME, 1, time[0]);
      if(g_actPL > 0) ObjectSetInteger(0, g_namePL, OBJPROP_TIME, 1, time[0]);
      DrawActivePOIs(time[0]);
      UpdateExtraHTF(currentSimTime);
      return rates_total;
   }

   // CASE C: A genuine new HTF bar has completed since our cached recalculation -> recompute now.
   if(htfBarTime != g_last_recalc_htf_time)
   {
      int limit = MathMin(InpMaxLookback, rates_total - 2);
      RecalculateFull(time, high, low, close, limit, currentSimTime);
      g_last_bar1_time = time[1];
      UpdateExtraHTF(currentSimTime);
      return rates_total;
   }

   // CASE D: Normal incremental tick/bar processing within the same HTF bar (fast path, no recompute)
   if(time[1] != g_last_bar1_time)
   {
      datetime t1 = time[1];
      for(int p = 0; p < ArraySize(pivots); p++)
      {
         if(pivots[p].confirmTime <= t1 && pivots[p].pivotTime > g_last_handled_pivot_time)
         {
            if(pivots[p].type == 1)
            {
               g_actPH = pivots[p].price;
               g_last_confirmed_PH_time = pivots[p].pivotTime;
               g_last_confirmed_PH_price = pivots[p].price;
               g_namePH = g_obj_prefix + "PH_" + IntegerToString(pivots[p].pivotTime);
               DrawLine(g_namePH, pivots[p].pivotTime, g_actPH, ClrPivotHigh);
            }
            else
            {
               g_actPL = pivots[p].price;
               g_last_confirmed_PL_time = pivots[p].pivotTime;
               g_last_confirmed_PL_price = pivots[p].price;
               g_namePL = g_obj_prefix + "PL_" + IntegerToString(pivots[p].pivotTime);
               DrawLine(g_namePL, pivots[p].pivotTime, g_actPL, ClrPivotLow);
            }
            g_last_handled_pivot_time = pivots[p].pivotTime;
         }
      }

      if(g_actPH > 0) ObjectSetInteger(0, g_namePH, OBJPROP_TIME, 1, t1);
      if(g_actPL > 0) ObjectSetInteger(0, g_namePL, OBJPROP_TIME, 1, t1);

      if(g_actPH > 0 && close[1] > g_actPH)
      {
         BullBuffer[1] = low[1] - (15 * _Point);
         string label = (g_trend <= 0) ? "HTF CHoCH" : "HTF BOS";
         DrawLabel(g_obj_prefix + "LBL_" + IntegerToString(t1), t1, high[1] + (10 * _Point), label, clrLimeGreen, InpBullTextAnchor);
         if(g_trend <= 0 && g_last_confirmed_PL_time != 0) CreatePOI(1, g_last_confirmed_PL_time, t1);
         g_actPH = 0; g_trend = 1;
      }

      if(g_actPL > 0 && close[1] < g_actPL)
      {
         BearBuffer[1] = high[1] + (15 * _Point);
         string label = (g_trend >= 0) ? "HTF CHoCH" : "HTF BOS";
         DrawLabel(g_obj_prefix + "LBL_" + IntegerToString(t1), t1, low[1] - (10 * _Point), label, clrRed, InpBearTextAnchor);
         if(g_trend >= 0 && g_last_confirmed_PH_time != 0) CreatePOI(-1, g_last_confirmed_PH_time, t1);
         g_actPL = 0; g_trend = -1;
      }

      EvaluatePOIMitigation(t1, close[1], high[1], low[1], true);
      PersistCacheState();

      g_last_bar1_time = time[1];
   }

   datetime t0 = time[0];
   if(t0 != g_last_live_extend_time)
   {
      if(g_actPH > 0) ObjectSetInteger(0, g_namePH, OBJPROP_TIME, 1, t0);
      if(g_actPL > 0) ObjectSetInteger(0, g_namePL, OBJPROP_TIME, 1, t0);

      EvaluatePOIMitigation(t0, close[0], high[0], low[0], false);
      DrawActivePOIs(t0);

      g_last_live_extend_time = t0;
   }

   return rates_total;
}
//+------------------------------------------------------------------+