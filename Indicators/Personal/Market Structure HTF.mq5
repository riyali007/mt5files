//+------------------------------------------------------------------+
//|                                    MTF_MarketStructure.mq5       |
//+------------------------------------------------------------------+
#property copyright "Professional MT5 Developer"
#property link      ""
#property version   "2.30"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//--- Timeframe Settings
input group "=== Timeframe Settings ==="
input ENUM_TIMEFRAMES HTF1_Period = PERIOD_M5;
input ENUM_TIMEFRAMES HTF2_Period = PERIOD_M15;
input ENUM_TIMEFRAMES HTF3_Period = PERIOD_H1;
input bool ShowHTF1 = true;
input bool ShowHTF2 = true;
input bool ShowHTF3 = true;

//--- Structure Detection Settings
input group "=== Structure Detection Settings ==="
input int  HTF1_SwingStrength = 13;
input int  HTF2_SwingStrength = 8;
input int  HTF3_SwingStrength = 5;
input bool ShowSwingHighLow   = true;
input bool ShowStructureLabels= true;
input bool ShowStructureLines = true;

//--- Visual Settings
input group "=== Visual Settings ==="
input color HTF1_Color = clrDodgerBlue;
input color HTF2_Color = clrLimeGreen;
input color HTF3_Color = clrGold;
input int   LabelFontSize = 8;

//--- Label Offset Settings
input group "=== Label Offset Settings ==="
input int HTF1_LabelOffset = 30;
input int HTF2_LabelOffset = 20;
input int HTF3_LabelOffset = 10;

//--- Liquidity Box Settings
input group "=== Liquidity Box Settings ==="
input bool ShowHTF1_LiquidityBoxes = true;
input bool ShowHTF2_LiquidityBoxes = true;
input bool ShowHTF3_LiquidityBoxes = true;
input int  MaxLiquidityBoxes       = 20;
input color LiquidityBoxColor      = clrDarkSlateGray;
input color SweptLiquidityColor    = C'25,25,25';
input int  HTF1_LiquidityOffset    = 5;      // HTF1 Liquidity Box Offset (points from wick)
input int  HTF2_LiquidityOffset    = 5;      // HTF2 Liquidity Box Offset (points from wick)
input int  HTF3_LiquidityOffset    = 5;      // HTF3 Liquidity Box Offset (points from wick)
input int  DefaultLiquidityHeight  = 50;     // Default Liquidity Box Height (points)
input int  MinLiquidityWickSize    = 30;     // Minimum wick size (points)
input int  MaxLiquidityWickSize    = 300;    // Maximum wick size (points)
input int  LiquidityBoxWidth       = 10;     // Liquidity Box Width (bars)
input int  LiquidityBoxTransparency= 70;     // Box Transparency (0-100, lower = more visible)

//--- Structures
struct SwingPoint
{
   datetime time;
   double   price;
   double   wickHigh;       // High of the candle
   double   wickLow;        // Low of the candle
   double   candleOpen;     // Open of the candle
   double   candleClose;    // Close of the candle
   int      type;           // 1 = High, -1 = Low
   int      barIndex;
   string   label;          // HH, HL, LH, LL
   bool     liquiditySwept;
   datetime sweptTime;
   bool     hasValidLiquidity; // Whether liquidity box should be drawn
};

//--- Global arrays
SwingPoint htf1Swings[];
SwingPoint htf2Swings[];
SwingPoint htf3Swings[];

//--- Timing
datetime lastHTF1Bar = 0;
datetime lastHTF2Bar = 0;
datetime lastHTF3Bar = 0;
datetime lastChartBar= 0;

string indicatorPrefix = "MTF_MS_";

//+------------------------------------------------------------------+
int OnInit()
{
   if(HTF1_Period < Period() && ShowHTF1)
      Print("Warning: HTF1 is lower than current TF");
   if(HTF2_Period < Period() && ShowHTF2)
      Print("Warning: HTF2 is lower than current TF");
   if(HTF3_Period < Period() && ShowHTF3)
      Print("Warning: HTF3 is lower than current TF");
   return(INIT_SUCCEEDED);
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
   datetime currentChartBar = iTime(_Symbol, Period(), 0);
   datetime currentHTF1Bar  = iTime(_Symbol, HTF1_Period, 0);
   datetime currentHTF2Bar  = iTime(_Symbol, HTF2_Period, 0);
   datetime currentHTF3Bar  = iTime(_Symbol, HTF3_Period, 0);

   bool needsUpdate = false;
   bool htf1Updated = false, htf2Updated = false, htf3Updated = false;

   if(currentChartBar != lastChartBar)
   {
      needsUpdate  = true;
      lastChartBar = currentChartBar;
   }
   if(ShowHTF1 && currentHTF1Bar != lastHTF1Bar)
   {
      needsUpdate = true; htf1Updated = true; lastHTF1Bar = currentHTF1Bar;
   }
   if(ShowHTF2 && currentHTF2Bar != lastHTF2Bar)
   {
      needsUpdate = true; htf2Updated = true; lastHTF2Bar = currentHTF2Bar;
   }
   if(ShowHTF3 && currentHTF3Bar != lastHTF3Bar)
   {
      needsUpdate = true; htf3Updated = true; lastHTF3Bar = currentHTF3Bar;
   }

   if(needsUpdate)
   {
      string tf1Name = GetTimeframeString(HTF1_Period);
      string tf2Name = GetTimeframeString(HTF2_Period);
      string tf3Name = GetTimeframeString(HTF3_Period);

      // HTF1
      if(ShowHTF1 && (htf1Updated || prev_calculated == 0))
      {
         RemoveTimeframeObjects(tf1Name);
         ArrayResize(htf1Swings,0);
         DetectStructure(HTF1_Period,htf1Swings,
                         tf1Name,HTF1_Color,HTF1_SwingStrength,
                         HTF1_LiquidityOffset,HTF1_LabelOffset,
                         ShowHTF1_LiquidityBoxes);
      }
      else if(ShowHTF1)
      {
         CheckLiquiditySweeps(htf1Swings,HTF1_LiquidityOffset);
         UpdateLiquidityBoxes(htf1Swings,tf1Name,HTF1_LiquidityOffset,ShowHTF1_LiquidityBoxes);
      }

      // HTF2
      if(ShowHTF2 && (htf2Updated || prev_calculated == 0))
      {
         RemoveTimeframeObjects(tf2Name);
         ArrayResize(htf2Swings,0);
         DetectStructure(HTF2_Period,htf2Swings,
                         tf2Name,HTF2_Color,HTF2_SwingStrength,
                         HTF2_LiquidityOffset,HTF2_LabelOffset,
                         ShowHTF2_LiquidityBoxes);
      }
      else if(ShowHTF2)
      {
         CheckLiquiditySweeps(htf2Swings,HTF2_LiquidityOffset);
         UpdateLiquidityBoxes(htf2Swings,tf2Name,HTF2_LiquidityOffset,ShowHTF2_LiquidityBoxes);
      }

      // HTF3
      if(ShowHTF3 && (htf3Updated || prev_calculated == 0))
      {
         RemoveTimeframeObjects(tf3Name);
         ArrayResize(htf3Swings,0);
         DetectStructure(HTF3_Period,htf3Swings,
                         tf3Name,HTF3_Color,HTF3_SwingStrength,
                         HTF3_LiquidityOffset,HTF3_LabelOffset,
                         ShowHTF3_LiquidityBoxes);
      }
      else if(ShowHTF3)
      {
         CheckLiquiditySweeps(htf3Swings,HTF3_LiquidityOffset);
         UpdateLiquidityBoxes(htf3Swings,tf3Name,HTF3_LiquidityOffset,ShowHTF3_LiquidityBoxes);
      }
   }

   return(rates_total);
}

//+------------------------------------------------------------------+
string GetTimeframeString(ENUM_TIMEFRAMES tf)
{
   if(tf==PERIOD_CURRENT) tf=Period();
   switch(tf)
   {
      case PERIOD_M1:  return "1Min";
      case PERIOD_M2:  return "2Min";
      case PERIOD_M3:  return "3Min";
      case PERIOD_M4:  return "4Min";
      case PERIOD_M5:  return "5Min";
      case PERIOD_M6:  return "6Min";
      case PERIOD_M10: return "10Min";
      case PERIOD_M12: return "12Min";
      case PERIOD_M15: return "15Min";
      case PERIOD_M20: return "20Min";
      case PERIOD_M30: return "30Min";
      case PERIOD_H1:  return "1H";
      case PERIOD_H2:  return "2H";
      case PERIOD_H3:  return "3H";
      case PERIOD_H4:  return "4H";
      case PERIOD_H6:  return "6H";
      case PERIOD_H8:  return "8H";
      case PERIOD_H12: return "12H";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
      default:         return "Unknown";
   }
}

//+------------------------------------------------------------------+
double CalculateValidWickSize(double wickSize)
{
   double wickPoints = wickSize / _Point;
   
   // If wick is less than minimum, use default height
   if(wickPoints < MinLiquidityWickSize)
      return DefaultLiquidityHeight * _Point;
   
   // If wick is more than maximum, cap it
   if(wickPoints > MaxLiquidityWickSize)
      return MaxLiquidityWickSize * _Point;
   
   // Otherwise return actual wick size
   return wickSize;
}

//+------------------------------------------------------------------+
void DetectStructure(ENUM_TIMEFRAMES tf,
                     SwingPoint &swings[],
                     string tfName,
                     color lineColor,
                     int swingStrength,
                     int liquidityOffset,
                     int labelOffset,
                     bool showLiqBoxes)
{
   int barsToAnalyze = 500;

   for(int i=barsToAnalyze; i>=swingStrength; i--)
   {
      if(IsSwingHigh(tf,i,swingStrength))
      {
         SwingPoint sp;
         sp.time      = iTime(_Symbol,tf,i);
         sp.price     = iHigh(_Symbol,tf,i);
         sp.wickHigh  = iHigh(_Symbol,tf,i);
         sp.wickLow   = iLow(_Symbol,tf,i);
         sp.candleOpen= iOpen(_Symbol,tf,i);
         sp.candleClose=iClose(_Symbol,tf,i);
         sp.type      = 1;
         sp.barIndex  = i;
         sp.label     = "";
         sp.liquiditySwept=false;
         sp.sweptTime =0;
         
         double bodyTop = MathMax(sp.candleOpen, sp.candleClose);
         double topWick = sp.wickHigh - bodyTop;
         double validWick = CalculateValidWickSize(topWick);
         sp.hasValidLiquidity = true;
         
         int sz=ArraySize(swings); ArrayResize(swings,sz+1); swings[sz]=sp;
      }
      if(IsSwingLow(tf,i,swingStrength))
      {
         SwingPoint sp;
         sp.time      = iTime(_Symbol,tf,i);
         sp.price     = iLow(_Symbol,tf,i);
         sp.wickHigh  = iHigh(_Symbol,tf,i);
         sp.wickLow   = iLow(_Symbol,tf,i);
         sp.candleOpen= iOpen(_Symbol,tf,i);
         sp.candleClose=iClose(_Symbol,tf,i);
         sp.type      = -1;
         sp.barIndex  = i;
         sp.label     = "";
         sp.liquiditySwept=false;
         sp.sweptTime =0;
         
         double bodyBottom = MathMin(sp.candleOpen, sp.candleClose);
         double bottomWick = bodyBottom - sp.wickLow;
         double validWick = CalculateValidWickSize(bottomWick);
         sp.hasValidLiquidity = true;
         
         int sz=ArraySize(swings); ArrayResize(swings,sz+1); swings[sz]=sp;
      }
   }

   SortSwingsByTime(swings);
   LabelSwings(swings);
   CheckLiquiditySweeps(swings,liquidityOffset);
   DrawStructure(swings,tfName,lineColor,liquidityOffset,labelOffset,showLiqBoxes);
}

//+------------------------------------------------------------------+
void CheckLiquiditySweeps(SwingPoint &swings[], int liquidityOffset)
{
   int size=ArraySize(swings);
   for(int i=0;i<size;i++)
   {
      if(swings[i].liquiditySwept || !swings[i].hasValidLiquidity) continue;

      double boxTop, boxBottom;
      
      if(swings[i].type==1)
      {
         double bodyTop = MathMax(swings[i].candleOpen, swings[i].candleClose);
         double topWick = swings[i].wickHigh - bodyTop;
         double validWick = CalculateValidWickSize(topWick);
         
         boxBottom = swings[i].wickHigh + liquidityOffset * _Point;
         boxTop    = boxBottom + validWick;
      }
      else
      {
         double bodyBottom = MathMin(swings[i].candleOpen, swings[i].candleClose);
         double bottomWick = bodyBottom - swings[i].wickLow;
         double validWick = CalculateValidWickSize(bottomWick);
         
         boxTop    = swings[i].wickLow - liquidityOffset * _Point;
         boxBottom = boxTop - validWick;
      }

      int startBar=iBarShift(_Symbol,Period(),swings[i].time);
      for(int bar=startBar; bar>=0; bar--)
      {
         double bh=iHigh(_Symbol,Period(),bar);
         double bl=iLow(_Symbol,Period(),bar);
         datetime bt=iTime(_Symbol,Period(),bar);

         if(bh >= MathMin(boxTop,boxBottom) && bl <= MathMax(boxTop,boxBottom))
         {
            swings[i].liquiditySwept=true;
            swings[i].sweptTime=bt;
            break;
         }
      }
   }
}

void UpdateLiquidityBoxes(SwingPoint &swings[], string tfName, int liquidityOffset, bool showLiqBoxes)
{
   if(!showLiqBoxes) return;
   int size=ArraySize(swings);
   int start=MathMax(0,size-MaxLiquidityBoxes);
   for(int i=start;i<size;i++)
      if(swings[i].hasValidLiquidity)
         DrawLiquidityBox(swings[i],tfName,i,liquidityOffset);
}

//+------------------------------------------------------------------+
bool IsSwingHigh(ENUM_TIMEFRAMES tf, int bar, int strength)
{
   double c=iHigh(_Symbol,tf,bar);
   for(int i=1;i<=strength;i++)
      if(iHigh(_Symbol,tf,bar+i)>=c || iHigh(_Symbol,tf,bar-i)>=c) return false;
   return true;
}

bool IsSwingLow(ENUM_TIMEFRAMES tf, int bar, int strength)
{
   double c=iLow(_Symbol,tf,bar);
   for(int i=1;i<=strength;i++)
      if(iLow(_Symbol,tf,bar+i)<=c || iLow(_Symbol,tf,bar-i)<=c) return false;
   return true;
}

//+------------------------------------------------------------------+
void SortSwingsByTime(SwingPoint &swings[])
{
   int size=ArraySize(swings);
   for(int i=0;i<size-1;i++)
      for(int j=i+1;j<size;j++)
         if(swings[i].time>swings[j].time)
         {
            SwingPoint t=swings[i];
            swings[i]=swings[j];
            swings[j]=t;
         }
}

void LabelSwings(SwingPoint &swings[])
{
   int size=ArraySize(swings); if(size<2) return;
   double lastHigh=-1,lastLow=-1;
   for(int i=0;i<size;i++)
   {
      if(swings[i].type==1)
      {
         if(lastHigh>0) swings[i].label = (swings[i].price>lastHigh ? "HH":"LH");
         else           swings[i].label = "HH";
         lastHigh=swings[i].price;
      }
      else
      {
         if(lastLow>0)  swings[i].label = (swings[i].price>lastLow ? "HL":"LL");
         else           swings[i].label = "LL";
         lastLow=swings[i].price;
      }
   }
}

//+------------------------------------------------------------------+
void DrawStructure(SwingPoint &swings[], string tfName, color lineColor,
                   int liquidityOffset, int labelOffset, bool showLiqBoxes)
{
   int size=ArraySize(swings);
   int start=MathMax(0,size-MaxLiquidityBoxes);

   for(int i=0;i<size;i++)
   {
      if(ShowSwingHighLow)
      {
         string objName=indicatorPrefix+tfName+"_P_"+IntegerToString(i);
         if(ObjectCreate(0,objName,OBJ_ARROW,0,swings[i].time,swings[i].price))
         {
            ObjectSetInteger(0,objName,OBJPROP_ARROWCODE,swings[i].type==1?234:233);
            ObjectSetInteger(0,objName,OBJPROP_COLOR,lineColor);
            ObjectSetInteger(0,objName,OBJPROP_WIDTH,2);
            ObjectSetInteger(0,objName,OBJPROP_BACK,true);
         }
      }

      if(ShowStructureLabels && swings[i].label!="")
      {
         string lbl=indicatorPrefix+tfName+"_L_"+IntegerToString(i);
         double lp=(swings[i].type==1)?
                   swings[i].price+labelOffset*_Point:
                   swings[i].price-labelOffset*_Point;
         if(ObjectCreate(0,lbl,OBJ_TEXT,0,swings[i].time,lp))
         {
            ObjectSetString(0,lbl,OBJPROP_TEXT,tfName+" "+swings[i].label);
            ObjectSetInteger(0,lbl,OBJPROP_FONTSIZE,LabelFontSize);
            ObjectSetInteger(0,lbl,OBJPROP_COLOR,lineColor);
            ObjectSetInteger(0,lbl,OBJPROP_ANCHOR,swings[i].type==1?ANCHOR_BOTTOM:ANCHOR_TOP);
         }
      }

      if(showLiqBoxes && i>=start && swings[i].hasValidLiquidity)
         DrawLiquidityBox(swings[i],tfName,i,liquidityOffset);

      if(ShowStructureLines && i>0)
      {
         string ln=indicatorPrefix+tfName+"_S_"+IntegerToString(i);
         if(ObjectCreate(0,ln,OBJ_TREND,0,
                         swings[i-1].time,swings[i-1].price,
                         swings[i].time,  swings[i].price))
         {
            ObjectSetInteger(0,ln,OBJPROP_COLOR,lineColor);
            ObjectSetInteger(0,ln,OBJPROP_WIDTH,1);
            ObjectSetInteger(0,ln,OBJPROP_STYLE,STYLE_SOLID);
            ObjectSetInteger(0,ln,OBJPROP_RAY_RIGHT,false);
            ObjectSetInteger(0,ln,OBJPROP_BACK,true);
         }
      }
   }
}

//+------------------------------------------------------------------+
void DrawLiquidityBox(SwingPoint &swing, string tfName, int index, int liquidityOffset)
{
   string boxName=indicatorPrefix+tfName+"_LB_"+IntegerToString(index);

   datetime t1=swing.time;
   datetime t2=swing.liquiditySwept ?
               swing.sweptTime :
               swing.time+PeriodSeconds(Period())*LiquidityBoxWidth;

   double p1, p2;
   
   if(swing.type==1)
   {
      double bodyTop = MathMax(swing.candleOpen, swing.candleClose);
      double topWick = swing.wickHigh - bodyTop;
      double validWick = CalculateValidWickSize(topWick);
      
      p1 = swing.wickHigh + liquidityOffset * _Point;
      p2 = p1 + validWick;
   }
   else
   {
      double bodyBottom = MathMin(swing.candleOpen, swing.candleClose);
      double bottomWick = bodyBottom - swing.wickLow;
      double validWick = CalculateValidWickSize(bottomWick);
      
      p1 = swing.wickLow - liquidityOffset * _Point;
      p2 = p1 - validWick;
   }

   color baseColor = swing.liquiditySwept ? SweptLiquidityColor : LiquidityBoxColor;
   
   // Calculate alpha transparency (0=opaque, 255=fully transparent)
   int alpha = (int)((LiquidityBoxTransparency / 100.0) * 255);
   
   // Extract RGB components
   int r = (int)(baseColor & 0xFF);
   int g = (int)((baseColor >> 8) & 0xFF);
   int b = (int)((baseColor >> 16) & 0xFF);
   
   // Create color with transparency in ARGB format
   color transparentColor = (color)((alpha << 24) | (r << 16) | (g << 8) | b);

   if(ObjectFind(0,boxName)>=0)
   {
      ObjectSetInteger(0,boxName,OBJPROP_TIME,0,t1);
      ObjectSetDouble(0,boxName,OBJPROP_PRICE,0,p1);
      ObjectSetInteger(0,boxName,OBJPROP_TIME,1,t2);
      ObjectSetDouble(0,boxName,OBJPROP_PRICE,1,p2);
      ObjectSetInteger(0,boxName,OBJPROP_COLOR,baseColor);
      ObjectSetInteger(0,boxName,OBJPROP_BGCOLOR,transparentColor);
   }
   else if(ObjectCreate(0,boxName,OBJ_RECTANGLE,0,t1,p1,t2,p2))
   {
      ObjectSetInteger(0,boxName,OBJPROP_COLOR,baseColor);
      ObjectSetInteger(0,boxName,OBJPROP_BGCOLOR,transparentColor);
      ObjectSetInteger(0,boxName,OBJPROP_STYLE,STYLE_SOLID);
      ObjectSetInteger(0,boxName,OBJPROP_WIDTH,1);
      ObjectSetInteger(0,boxName,OBJPROP_FILL,true);
      ObjectSetInteger(0,boxName,OBJPROP_BACK,true);
   }
}

//+------------------------------------------------------------------+
void RemoveTimeframeObjects(string tfName)
{
   int total=ObjectsTotal(0);
   for(int i=total-1;i>=0;i--)
   {
      string name=ObjectName(0,i);
      if(StringFind(name,indicatorPrefix+tfName)>=0)
         ObjectDelete(0,name);
   }
}

void RemoveOldObjects()
{
   int total=ObjectsTotal(0);
   for(int i=total-1;i>=0;i--)
   {
      string name=ObjectName(0,i);
      if(StringFind(name,indicatorPrefix)>=0)
         ObjectDelete(0,name);
   }
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   RemoveOldObjects();
}
//+------------------------------------------------------------------+
