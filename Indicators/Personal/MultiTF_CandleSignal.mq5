//+------------------------------------------------------------------+
//|  MultiTF_CandleSignals_v14.mq5                                   |
//|  EXACT restore of v6 — only version number changed               |
//|  Author: Riy Tech                                                |
//+------------------------------------------------------------------+
#property copyright   "Riy Tech"
#property link        "https://riytech.se"
#property version     "14.00"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

#property indicator_label1  "Sell Signal"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrRed
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

#property indicator_label2  "Buy Signal"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrLime
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input bool            InpEnableSellC1 = true;        // Enable Sell Condition 1
input bool            InpEnableSellC2 = true;        // Enable Sell Condition 2
input bool            InpEnableSellC3 = true;        // Enable Sell Condition 3
input bool            InpEnableSellC4 = true;        // Enable Sell Condition 4
input bool            InpEnableBuyC1  = true;        // Enable Buy Condition 1
input bool            InpEnableBuyC2  = true;        // Enable Buy Condition 2
input bool            InpEnableBuyC3  = true;        // Enable Buy Condition 3
input bool            InpEnableBuyC4  = true;        // Enable Buy Condition 4
input int             InpRSI_Period   = 14;          // RSI Period
input ENUM_APPLIED_PRICE InpRSI_Price = PRICE_CLOSE; // RSI Applied Price
input double          InpDojiRatio    = 0.1;         // Doji Body/Range Ratio (0.0–1.0)
input double          InpArrowOffset  = 5.0;         // Arrow offset in points
input int             InpFontSize     = 8;           // Label font size

//+------------------------------------------------------------------+
//| Buffers                                                          |
//+------------------------------------------------------------------+
double SellBuffer[];
double BuyBuffer[];

int g_rsi_handle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   
   SetIndexBuffer(0, SellBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, BuyBuffer,  INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_ARROW, 234);
   PlotIndexSetInteger(1, PLOT_ARROW, 233);
   PlotIndexSetDouble (0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble (1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetInteger(0, PLOT_ARROW_SHIFT, -15);
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT,  15);

   g_rsi_handle = iRSI(_Symbol, PERIOD_CURRENT, InpRSI_Period, InpRSI_Price);
   if(g_rsi_handle == INVALID_HANDLE)
      Print("WARNING: Could not create RSI handle.");

   IndicatorSetString(INDICATOR_SHORTNAME, "Candle Patterns v14");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Deinit                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_rsi_handle != INVALID_HANDLE) IndicatorRelease(g_rsi_handle);
   int total = ObjectsTotal(0, 0, OBJ_TEXT);
   for(int i = total-1; i >= 0; i--)
   {
      string n = ObjectName(0, i, 0, OBJ_TEXT);
      if(StringFind(n, "CPv14_") == 0) ObjectDelete(0, n);
   }
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Label helper                                                     |
//+------------------------------------------------------------------+
void SetLabel(const string name, const datetime t, const double price,
              const string text, const color clr, const bool isSell)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   InpFontSize);
      ObjectSetString (0, name, OBJPROP_FONT,       "Arial Bold");
      ObjectSetInteger(0, name, OBJPROP_ANCHOR,     isSell ? ANCHOR_LOWER : ANCHOR_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   }
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void RemoveLabel(const string name)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
}

//+------------------------------------------------------------------+
//| RSI helper                                                       |
//+------------------------------------------------------------------+
double GetRSI(int shift)
{
   if(g_rsi_handle == INVALID_HANDLE) return EMPTY_VALUE;
   double buf[1];
   if(CopyBuffer(g_rsi_handle, 0, shift, 1, buf) <= 0) return EMPTY_VALUE;
   return buf[0];
}

//+------------------------------------------------------------------+
//| Pattern helpers                                                  |
//+------------------------------------------------------------------+
bool isBull(const double &o[], const double &c[], int i)
{ return c[i] > o[i]; }

bool isBear(const double &o[], const double &c[], int i)
{ return c[i] < o[i]; }

bool isDoji(const double &o[], const double &h[], const double &l[],
            const double &c[], int i)
{
   double r = h[i]-l[i];
   if(r <= 0) return true;
   return MathAbs(c[i]-o[i])/r <= InpDojiRatio;
}

bool isEngulfing(const double &o[], const double &h[], const double &l[],
                 const double &c[], int i)
{
   if(i+1 >= ArraySize(o)) return false;
   double o0=o[i],c0=c[i],o1=o[i+1],c1=c[i+1];
   if(c1<o1 && c0>o0 && o0<=c1 && c0>=o1) return true;
   if(c1>o1 && c0<o0 && o0>=c1 && c0<=o1) return true;
   return false;
}

double getBody(const double &o[], const double &c[], int i)
{ return MathAbs(c[i]-o[i])/_Point; }

double getUpperWick(const double &o[], const double &h[], const double &c[], int i)
{ return (h[i]-MathMax(o[i],c[i]))/_Point; }

double getLowerWick(const double &o[], const double &l[], const double &c[], int i)
{ return (MathMin(o[i],c[i])-l[i])/_Point; }

//+------------------------------------------------------------------+
//| Process a single bar — identical to v6                           |
//+------------------------------------------------------------------+
void ProcessBar(int i,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const int       rates_total)
{
   double offset   = InpArrowOffset * _Point;
   string baseKey  = "CPv14_" + IntegerToString((long)time[i]);
   string sellName = baseKey + "_S";
   string buyName  = baseKey + "_B";

   SellBuffer[i] = EMPTY_VALUE;
   BuyBuffer[i]  = EMPTY_VALUE;
   RemoveLabel(sellName);
   RemoveLabel(buyName);

   if(i+4 >= rates_total) return;

   int s0=i, s1=i+1, s2=i+2, s3=i+3;
   string sellLabel = "";
   string buyLabel  = "";

   // SELL — last enabled match wins
   if(InpEnableSellC1 &&
      isBull(open,close,s2) && isBull(open,close,s1) && isBear(open,close,s0)
      && !isDoji(open,high,low,close,s2) && !isDoji(open,high,low,close,s1)
      && !isDoji(open,high,low,close,s0))
         sellLabel = "SC1";

   if(InpEnableSellC2 &&
      isBull(open,close,s3) && isBull(open,close,s2) && isBull(open,close,s1)
      && isBear(open,close,s0)
      && !isDoji(open,high,low,close,s1) && !isDoji(open,high,low,close,s0)
      && close[s0] >= low[s1]
      && getBody(open,close,s0) > 1.0 && getUpperWick(open,high,close,s0) > 0.0)
         sellLabel = "SC2";

   if(InpEnableSellC3 &&
      isEngulfing(open,high,low,close,s0) && isBear(open,close,s0) && isBull(open,close,s1)
      && getBody(open,close,s0) > 2.0 && getUpperWick(open,high,close,s0) > 0.0)
         sellLabel = "SC3";

   if(InpEnableSellC4 &&
      isBull(open,close,s2) && isBull(open,close,s1) && isBear(open,close,s0)
      && getBody(open,close,s0) > 2.0 && getUpperWick(open,high,close,s0) > 0.0)
         sellLabel = "SC4";

   // BUY — last enabled match wins
   if(InpEnableBuyC1 &&
      isBear(open,close,s2) && isBear(open,close,s1) && isBull(open,close,s0)
      && !isDoji(open,high,low,close,s2) && !isDoji(open,high,low,close,s1)
      && !isDoji(open,high,low,close,s0))
         buyLabel = "BC1";

   if(InpEnableBuyC2 &&
      isBear(open,close,s3) && isBear(open,close,s2) && isBear(open,close,s1)
      && isBull(open,close,s0)
      && !isDoji(open,high,low,close,s1) && !isDoji(open,high,low,close,s0)
      && close[s0] <= high[s1]
      && getBody(open,close,s0) > 1.0 && getLowerWick(open,low,close,s0) > 0.0)
         buyLabel = "BC2";

   if(InpEnableBuyC3 &&
      isEngulfing(open,high,low,close,s0) && isBull(open,close,s0) && isBear(open,close,s1)
      && getBody(open,close,s0) > 2.0 && getLowerWick(open,low,close,s0) > 0.0)
         buyLabel = "BC3";

   if(InpEnableBuyC4 &&
      isBear(open,close,s2) && isBear(open,close,s1) && isBull(open,close,s0)
      && getBody(open,close,s0) > 2.0 && getLowerWick(open,low,close,s0) > 0.0)
         buyLabel = "BC4";

   // RSI reference
   double rsiVal = GetRSI(i);
   string rsiStr = (rsiVal != EMPTY_VALUE) ? "  RSI:"+DoubleToString(rsiVal,1) : "";

   // Draw
   if(sellLabel != "")
   {
      double ap = high[i] + offset;
      SellBuffer[i] = ap;
      SetLabel(sellName, time[i], ap+offset*1.5, sellLabel+rsiStr, clrRed, true);
   }
   if(buyLabel != "")
   {
      double ap = low[i] - offset;
      BuyBuffer[i] = ap;
      SetLabel(buyName, time[i], ap-offset*1.5, buyLabel+rsiStr, clrLime, false);
   }
}

//+------------------------------------------------------------------+
//| OnCalculate — identical logic to v6                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
{

   // Check if a new bar has just opened
   // On the first tick of a new bar, rates_total will be > prev_calculated
   if(rates_total > prev_calculated) 
   {
      // Calculate starting index (current bar - 50)
      int start = (rates_total - 1) - 50;
      if(start < 0) start = 0; 

      // This loop now runs ONLY once per bar
      for(int i = start; i < rates_total; i++)
      {
         if(rates_total < 5) return 0;

         int start = (prev_calculated == 0) ? rates_total - 1 : 1;
         
         for(int i = start; i >= 0; i--)
            ProcessBar(i, time, open, high, low, close, rates_total);
      
         ChartRedraw();
       }
   }

   // Always return rates_total so prev_calculated updates for the next tick
   return(rates_total);

}
//+------------------------------------------------------------------+
