//+------------------------------------------------------------------+
//|                                                  VWAP_Session.mq5 |
//|            Session VWAP — Asia / London / NY / NY Extended        |
//|            v1.1 — Production Ready                                |
//+------------------------------------------------------------------+
#property copyright   "Riy Tech"
#property link        ""
#property version     "1.10"
#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots   8

#property indicator_label1  "Asia VWAP"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrOrange
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

#property indicator_label2  "Asia +1s"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrange
#property indicator_style2  STYLE_DOT
#property indicator_width2  1

#property indicator_label3  "London VWAP"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrDodgerBlue
#property indicator_style3  STYLE_SOLID
#property indicator_width3  2

#property indicator_label4  "London +1s"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrDodgerBlue
#property indicator_style4  STYLE_DOT
#property indicator_width4  1

#property indicator_label5  "NY VWAP"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrMediumSeaGreen
#property indicator_style5  STYLE_SOLID
#property indicator_width5  2

#property indicator_label6  "NY +1s"
#property indicator_type6   DRAW_LINE
#property indicator_color6  clrMediumSeaGreen
#property indicator_style6  STYLE_DOT
#property indicator_width6  1

#property indicator_label7  "NY Ext VWAP"
#property indicator_type7   DRAW_LINE
#property indicator_color7  clrViolet
#property indicator_style7  STYLE_SOLID
#property indicator_width7  2

#property indicator_label8  "NY Ext +1s"
#property indicator_type8   DRAW_LINE
#property indicator_color8  clrViolet
#property indicator_style8  STYLE_DOT
#property indicator_width8  1

//+------------------------------------------------------------------+
//| INPUTS                                                            |
//+------------------------------------------------------------------+
input group "=== Server Time Offset ==="
input int  InpServerUTCOffset = 1;      // Server UTC Offset (e.g. 1 = UTC+1)

input group "=== Session Hours in UTC ==="
input int  InpAsiaOpenUTC    = 0;       // Asia Open  (UTC)
input int  InpAsiaCloseUTC   = 8;       // Asia Close (UTC)
input int  InpLondonOpenUTC  = 8;       // London Open  (UTC)
input int  InpLondonCloseUTC = 16;      // London Close (UTC)
input int  InpNYOpenUTC      = 13;      // NY Open  (UTC)
input int  InpNYCloseUTC     = 21;      // NY Close (UTC)
input int  InpNYExtOpenUTC   = 21;      // NY Extended Open  (UTC)
input int  InpNYExtCloseUTC  = 24;      // NY Extended Close (UTC, 24 = midnight)

input group "=== Visibility ==="
input bool InpShowAsia       = true;
input bool InpShowLondon     = true;
input bool InpShowNY         = true;
input bool InpShowNYExt      = false;
input bool InpShowBands      = true;

input group "=== VWAP Extension ==="
input bool InpExtendVWAP     = true;    // Extend VWAP to current bar

input group "=== Labels ==="
input bool InpShowLabels     = true;
input int  InpFontSize       = 9;
input bool InpShowPrice      = true;

//+------------------------------------------------------------------+
//| BUFFERS                                                           |
//+------------------------------------------------------------------+
double BufAsiaVWAP[],  BufAsiaBand[];
double BufLonVWAP[],   BufLonBand[];
double BufNYVWAP[],    BufNYBand[];
double BufExtVWAP[],   BufExtBand[];

string g_Prefix     = "VWAP_LBL_";

// Label cache — parallel plain arrays (safe in MQL5)
string g_CacheName[1024];
double g_CachePrice[1024];
int    g_CacheCount = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BufAsiaVWAP, INDICATOR_DATA);
   SetIndexBuffer(1, BufAsiaBand, INDICATOR_DATA);
   SetIndexBuffer(2, BufLonVWAP,  INDICATOR_DATA);
   SetIndexBuffer(3, BufLonBand,  INDICATOR_DATA);
   SetIndexBuffer(4, BufNYVWAP,   INDICATOR_DATA);
   SetIndexBuffer(5, BufNYBand,   INDICATOR_DATA);
   SetIndexBuffer(6, BufExtVWAP,  INDICATOR_DATA);
   SetIndexBuffer(7, BufExtBand,  INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_LINE_COLOR, clrOrange);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, clrOrange);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, clrDodgerBlue);
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, clrDodgerBlue);
   PlotIndexSetInteger(4, PLOT_LINE_COLOR, clrMediumSeaGreen);
   PlotIndexSetInteger(5, PLOT_LINE_COLOR, clrMediumSeaGreen);
   PlotIndexSetInteger(6, PLOT_LINE_COLOR, clrViolet);
   PlotIndexSetInteger(7, PLOT_LINE_COLOR, clrViolet);

   if(!InpShowBands)
   {
      PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_NONE);
      PlotIndexSetInteger(3, PLOT_DRAW_TYPE, DRAW_NONE);
      PlotIndexSetInteger(5, PLOT_DRAW_TYPE, DRAW_NONE);
      PlotIndexSetInteger(7, PLOT_DRAW_TYPE, DRAW_NONE);
   }
   if(!InpShowAsia)
   { PlotIndexSetInteger(0,PLOT_DRAW_TYPE,DRAW_NONE); PlotIndexSetInteger(1,PLOT_DRAW_TYPE,DRAW_NONE); }
   if(!InpShowLondon)
   { PlotIndexSetInteger(2,PLOT_DRAW_TYPE,DRAW_NONE); PlotIndexSetInteger(3,PLOT_DRAW_TYPE,DRAW_NONE); }
   if(!InpShowNY)
   { PlotIndexSetInteger(4,PLOT_DRAW_TYPE,DRAW_NONE); PlotIndexSetInteger(5,PLOT_DRAW_TYPE,DRAW_NONE); }
   if(!InpShowNYExt)
   { PlotIndexSetInteger(6,PLOT_DRAW_TYPE,DRAW_NONE); PlotIndexSetInteger(7,PLOT_DRAW_TYPE,DRAW_NONE); }

   for(int i = 0; i < 8; i++)
      PlotIndexSetDouble(i, PLOT_EMPTY_VALUE, 0.0);

   IndicatorSetString(INDICATOR_SHORTNAME,
      StringFormat("VWAP Sessions v1.1 [Server UTC%+d]", InpServerUTCOffset));

   PurgeLabelObjects();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { PurgeLabelObjects(); }

//+------------------------------------------------------------------+
void PurgeLabelObjects()
{
   int total = ObjectsTotal(0, 0, OBJ_TEXT);
   for(int i = total - 1; i >= 0; i--)
   {
      string n = ObjectName(0, i, 0, OBJ_TEXT);
      if(StringFind(n, g_Prefix) == 0)
         ObjectDelete(0, n);
   }
   for(int i = 0; i < 1024; i++)
   {
      g_CacheName[i]  = "";
      g_CachePrice[i] = 0.0;
   }
   g_CacheCount = 0;
}

//+------------------------------------------------------------------+
int BarUTCHour(datetime serverTime)
{
   MqlDateTime dt;
   TimeToStruct(serverTime, dt);
   int utcHour = dt.hour - InpServerUTCOffset;
   return ((utcHour % 24) + 24) % 24;
}

bool InRange(int utcHour, int openUTC, int closeUTC)
{
   if(openUTC == closeUTC) return false;
   int c = (closeUTC >= 24) ? 24 : closeUTC;
   if(openUTC < c)
      return (utcHour >= openUTC && utcHour < c);
   return (utcHour >= openUTC || utcHour < c);
}

int GetMask(datetime serverTime)
{
   int h = BarUTCHour(serverTime);
   int m = 0;
   if(InpShowAsia   && InRange(h, InpAsiaOpenUTC,   InpAsiaCloseUTC))   m |= 1;
   if(InpShowLondon && InRange(h, InpLondonOpenUTC, InpLondonCloseUTC)) m |= 2;
   if(InpShowNY     && InRange(h, InpNYOpenUTC,     InpNYCloseUTC))     m |= 4;
   if(InpShowNYExt  && InRange(h, InpNYExtOpenUTC,  InpNYExtCloseUTC))  m |= 8;
   return m;
}

double CalcBand(double tpv, double vol, double tpv2, double vwap)
{
   if(!InpShowBands || vol <= 0.0) return 0.0;
   double var = (tpv2 / vol) - (vwap * vwap);
   return vwap + MathSqrt(MathMax(var, 0.0));
}

//+------------------------------------------------------------------+
// Standard label — placed at session close edge only
// Anti-flicker: only updates chart object when price changes
//+------------------------------------------------------------------+
void PlaceLabel(const string   name,
                const datetime t,
                const double   price,
                const string   text,
                const color    clr)
{
   if(!InpShowLabels) return;

   int idx = -1;
   for(int i = 0; i < g_CacheCount; i++)
      if(g_CacheName[i] == name) { idx = i; break; }

   bool priceChanged = (idx < 0) || (MathAbs(g_CachePrice[idx] - price) > 1e-10);

   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   InpFontSize);
      ObjectSetString (0, name, OBJPROP_FONT,       "Arial Bold");
      ObjectSetInteger(0, name, OBJPROP_ANCHOR,     ANCHOR_LEFT);
      ObjectSetInteger(0, name, OBJPROP_BACK,       false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
      ObjectSetString (0, name, OBJPROP_TEXT,       text);
      priceChanged = true;
   }
   else if(priceChanged)
   {
      ObjectMove(0, name, 0, t, price);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
   }

   if(priceChanged)
   {
      if(idx < 0 && g_CacheCount < 1024) idx = g_CacheCount++;
      if(idx >= 0) { g_CacheName[idx] = name; g_CachePrice[idx] = price; }
   }
}

//+------------------------------------------------------------------+
// Extension label — always advances time to stay at the right edge
// Only redraws text when price changes (anti-flicker)
//+------------------------------------------------------------------+
void PlaceLabelExt(const string   name,
                   const datetime t,
                   const double   price,
                   const string   text,
                   const color    clr)
{
   if(!InpShowLabels) return;

   int idx = -1;
   for(int i = 0; i < g_CacheCount; i++)
      if(g_CacheName[i] == name) { idx = i; break; }

   bool priceChanged = (idx < 0) || (MathAbs(g_CachePrice[idx] - price) > 1e-10);

   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   InpFontSize);
      ObjectSetString (0, name, OBJPROP_FONT,       "Arial Bold");
      ObjectSetInteger(0, name, OBJPROP_ANCHOR,     ANCHOR_LEFT);
      ObjectSetInteger(0, name, OBJPROP_BACK,       false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
      ObjectSetString (0, name, OBJPROP_TEXT,       text);
      priceChanged = true;
   }
   else
   {
      // Always move time forward so label stays at right edge
      ObjectMove(0, name, 0, t, price);
      if(priceChanged)
         ObjectSetString(0, name, OBJPROP_TEXT, text);
   }

   if(priceChanged)
   {
      if(idx < 0 && g_CacheCount < 1024) idx = g_CacheCount++;
      if(idx >= 0) { g_CacheName[idx] = name; g_CachePrice[idx] = price; }
   }
}

string LabelText(const string sess, double vwap)
{
   return InpShowPrice ? StringFormat("%s  %.5f", sess, vwap) : sess;
}

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
   if(rates_total < 2) return 0;

   if(prev_calculated == 0)
      PurgeLabelObjects();

   int start = (prev_calculated > 1) ? prev_calculated - 1 : 0;

   double asiaTPV=0, asiaVol=0, asiaTPV2=0;
   double lonTPV=0,  lonVol=0,  lonTPV2=0;
   double nyTPV=0,   nyVol=0,   nyTPV2=0;
   double extTPV=0,  extVol=0,  extTPV2=0;
   int    prevMask=0;
   int    asiaID=0, lonID=0, nyID=0, extID=0;

   // Last known VWAP and band for extension
   double lastAsiaVWAP=0, lastAsiaBand=0;
   double lastLonVWAP=0,  lastLonBand=0;
   double lastNYVWAP=0,   lastNYBand=0;
   double lastExtVWAP=0,  lastExtBand=0;

   // Rebuild state before `start`
   if(start > 0)
   {
      int refMask  = GetMask(time[start]);
      int scanFrom = start;
      for(int k = start - 1; k >= 0; k--)
      {
         if((GetMask(time[k]) & refMask) == 0) { scanFrom = k + 1; break; }
         if(k == 0) scanFrom = 0;
      }

      int pm = 0;
      for(int k = 0; k < scanFrom; k++)
      {
         int m = GetMask(time[k]);
         if((m&1) && !(pm&1)) asiaID++;
         if((m&2) && !(pm&2)) lonID++;
         if((m&4) && !(pm&4)) nyID++;
         if((m&8) && !(pm&8)) extID++;
         pm = m;
      }

      int pm2 = 0;
      for(int k = 0; k < start; k++)
      {
         int m = GetMask(time[k]);
         double tp  = (high[k]+low[k]+close[k])/3.0;
         double vol = (double)tick_volume[k]; if(vol<=0) vol=1;

         if(k >= scanFrom)
         {
            if((m&1) && !(pm2&1)) { asiaTPV=0; asiaVol=0; asiaTPV2=0; asiaID++; }
            if((m&2) && !(pm2&2)) { lonTPV=0;  lonVol=0;  lonTPV2=0;  lonID++;  }
            if((m&4) && !(pm2&4)) { nyTPV=0;   nyVol=0;   nyTPV2=0;   nyID++;   }
            if((m&8) && !(pm2&8)) { extTPV=0;  extVol=0;  extTPV2=0;  extID++;  }

            if(m&1){ asiaTPV+=tp*vol; asiaVol+=vol; asiaTPV2+=tp*tp*vol; }
            if(m&2){ lonTPV+=tp*vol;  lonVol+=vol;  lonTPV2+=tp*tp*vol;  }
            if(m&4){ nyTPV+=tp*vol;   nyVol+=vol;   nyTPV2+=tp*tp*vol;   }
            if(m&8){ extTPV+=tp*vol;  extVol+=vol;  extTPV2+=tp*tp*vol;  }
         }

         if((m&1) && asiaVol>0) { lastAsiaVWAP=asiaTPV/asiaVol; lastAsiaBand=CalcBand(asiaTPV,asiaVol,asiaTPV2,lastAsiaVWAP); }
         if((m&2) && lonVol>0)  { lastLonVWAP=lonTPV/lonVol;    lastLonBand=CalcBand(lonTPV,lonVol,lonTPV2,lastLonVWAP);     }
         if((m&4) && nyVol>0)   { lastNYVWAP=nyTPV/nyVol;       lastNYBand=CalcBand(nyTPV,nyVol,nyTPV2,lastNYVWAP);         }
         if((m&8) && extVol>0)  { lastExtVWAP=extTPV/extVol;    lastExtBand=CalcBand(extTPV,extVol,extTPV2,lastExtVWAP);    }

         pm2 = m;
      }
      prevMask = pm2;
   }

   // Main loop
   for(int i = start; i < rates_total; i++)
   {
      int  mask    = GetMask(time[i]);
      bool isLast  = (i == rates_total - 1);
      int  nxtMask = isLast ? 0 : GetMask(time[i+1]);
      datetime edgeTime = time[i] + PeriodSeconds();

      double tp  = (high[i]+low[i]+close[i])/3.0;
      double vol = (double)tick_volume[i]; if(vol<=0) vol=1;

      //--- ASIA ---
      if(mask & 1)
      {
         if(!(prevMask & 1)) { asiaTPV=0; asiaVol=0; asiaTPV2=0; asiaID++; }
         asiaTPV+=tp*vol; asiaVol+=vol; asiaTPV2+=tp*tp*vol;
         double vwap     = asiaTPV/asiaVol;
         double band     = CalcBand(asiaTPV,asiaVol,asiaTPV2,vwap);
         BufAsiaVWAP[i] = vwap;
         BufAsiaBand[i] = band;
         lastAsiaVWAP   = vwap;
         lastAsiaBand   = band;
         // Label at session close edge
         if(!(nxtMask & 1))
            PlaceLabel(StringFormat("%sAsia_%d",g_Prefix,asiaID),
               edgeTime, vwap, LabelText("Asia VWAP",vwap), clrOrange);
      }
      else
      {
         if(InpExtendVWAP && lastAsiaVWAP > 0.0)
         {
            BufAsiaVWAP[i] = lastAsiaVWAP;
            BufAsiaBand[i] = lastAsiaBand;
            // Label follows the extension to the current bar
            if(isLast)
               PlaceLabelExt(StringFormat("%sAsia_%d",g_Prefix,asiaID),
                  edgeTime, lastAsiaVWAP, LabelText("Asia VWAP",lastAsiaVWAP), clrOrange);
         }
         else { BufAsiaVWAP[i]=0.0; BufAsiaBand[i]=0.0; }
      }

      //--- LONDON ---
      if(mask & 2)
      {
         if(!(prevMask & 2)) { lonTPV=0; lonVol=0; lonTPV2=0; lonID++; }
         lonTPV+=tp*vol; lonVol+=vol; lonTPV2+=tp*tp*vol;
         double vwap    = lonTPV/lonVol;
         double band    = CalcBand(lonTPV,lonVol,lonTPV2,vwap);
         BufLonVWAP[i] = vwap;
         BufLonBand[i] = band;
         lastLonVWAP   = vwap;
         lastLonBand   = band;
         if(!(nxtMask & 2))
            PlaceLabel(StringFormat("%sLon_%d",g_Prefix,lonID),
               edgeTime, vwap, LabelText("London VWAP",vwap), clrDodgerBlue);
      }
      else
      {
         if(InpExtendVWAP && lastLonVWAP > 0.0)
         {
            BufLonVWAP[i] = lastLonVWAP;
            BufLonBand[i] = lastLonBand;
            if(isLast)
               PlaceLabelExt(StringFormat("%sLon_%d",g_Prefix,lonID),
                  edgeTime, lastLonVWAP, LabelText("London VWAP",lastLonVWAP), clrDodgerBlue);
         }
         else { BufLonVWAP[i]=0.0; BufLonBand[i]=0.0; }
      }

      //--- NEW YORK ---
      if(mask & 4)
      {
         if(!(prevMask & 4)) { nyTPV=0; nyVol=0; nyTPV2=0; nyID++; }
         nyTPV+=tp*vol; nyVol+=vol; nyTPV2+=tp*tp*vol;
         double vwap   = nyTPV/nyVol;
         double band   = CalcBand(nyTPV,nyVol,nyTPV2,vwap);
         BufNYVWAP[i] = vwap;
         BufNYBand[i] = band;
         lastNYVWAP   = vwap;
         lastNYBand   = band;
         if(!(nxtMask & 4))
            PlaceLabel(StringFormat("%sNY_%d",g_Prefix,nyID),
               edgeTime, vwap, LabelText("NY VWAP",vwap), clrMediumSeaGreen);
      }
      else
      {
         if(InpExtendVWAP && lastNYVWAP > 0.0)
         {
            BufNYVWAP[i] = lastNYVWAP;
            BufNYBand[i] = lastNYBand;
            if(isLast)
               PlaceLabelExt(StringFormat("%sNY_%d",g_Prefix,nyID),
                  edgeTime, lastNYVWAP, LabelText("NY VWAP",lastNYVWAP), clrMediumSeaGreen);
         }
         else { BufNYVWAP[i]=0.0; BufNYBand[i]=0.0; }
      }

      //--- NY EXTENDED ---
      if(mask & 8)
      {
         if(!(prevMask & 8)) { extTPV=0; extVol=0; extTPV2=0; extID++; }
         extTPV+=tp*vol; extVol+=vol; extTPV2+=tp*tp*vol;
         double vwap   = extTPV/extVol;
         double band   = CalcBand(extTPV,extVol,extTPV2,vwap);
         BufExtVWAP[i] = vwap;
         BufExtBand[i] = band;
         lastExtVWAP   = vwap;
         lastExtBand   = band;
         if(!(nxtMask & 8))
            PlaceLabel(StringFormat("%sExt_%d",g_Prefix,extID),
               edgeTime, vwap, LabelText("NY Ext VWAP",vwap), clrViolet);
      }
      else
      {
         if(InpExtendVWAP && lastExtVWAP > 0.0)
         {
            BufExtVWAP[i] = lastExtVWAP;
            BufExtBand[i] = lastExtBand;
            if(isLast)
               PlaceLabelExt(StringFormat("%sExt_%d",g_Prefix,extID),
                  edgeTime, lastExtVWAP, LabelText("NY Ext VWAP",lastExtVWAP), clrViolet);
         }
         else { BufExtVWAP[i]=0.0; BufExtBand[i]=0.0; }
      }

      prevMask = mask;
   }

   ChartRedraw(0);
   return rates_total;
}
//+------------------------------------------------------------------+