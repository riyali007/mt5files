//+------------------------------------------------------------------+
//| HMA_HTF_EA.mq5 - HTF Hull MA drawn on chart (no indicators used) |
//+------------------------------------------------------------------+
#property copyright "Riy Ali"
#property version   "2.00"
#property strict

#include <Trade/Trade.mqh>

input group "HMA (HTF)"
input ENUM_TIMEFRAMES    InpHTF          = PERIOD_H1;
input int                InpPeriod       = 14;
input ENUM_APPLIED_PRICE InpPrice        = PRICE_CLOSE;
input color              InpHmaUpColor   = clrAqua;
input color              InpHmaDnColor   = clrOrange;
input int                InpLineWidth    = 2;
input int                InpDrawBars     = 300;     // HTF bars drawn

input group "Chart theme"
input bool   InpApplyBlackTheme   = true;
input color  InpBullCandleColor   = C'38,166,154';   // teal
input color  InpBearCandleColor   = C'239,83,80';    // red

input group "Trading"
input bool   InpTradeEnabled = true;
input double InpRiskPercent  = 1.0;
input int    InpATRPeriod    = 14;      // ATR computed internally on HTF
input double InpSL_ATR       = 2.0;
input double InpTP_ATR       = 3.0;     // 0 = no TP
input int    InpMaxSpread    = 50;      // points, 0 = off
input bool   InpCloseOnFlip  = true;
input long   InpMagic        = 20261002;

#define PFX "HMAHTF_"

CTrade   trade;
datetime g_lastHtfBar = 0;
datetime g_lastChartBar = 0;

//+------------------------------------------------------------------+
void ApplyTheme()
{
   long id = 0;
   ChartSetInteger(id, CHART_MODE, CHART_CANDLES);
   ChartSetInteger(id, CHART_COLOR_BACKGROUND,  clrBlack);
   ChartSetInteger(id, CHART_COLOR_FOREGROUND,  clrSilver);
   ChartSetInteger(id, CHART_COLOR_GRID,        C'30,30,30');
   ChartSetInteger(id, CHART_SHOW_GRID,         false);
   ChartSetInteger(id, CHART_COLOR_CHART_UP,    InpBullCandleColor);
   ChartSetInteger(id, CHART_COLOR_CHART_DOWN,  InpBearCandleColor);
   ChartSetInteger(id, CHART_COLOR_CHART_LINE,  clrSilver);
   ChartSetInteger(id, CHART_COLOR_CANDLE_BULL, InpBullCandleColor);
   ChartSetInteger(id, CHART_COLOR_CANDLE_BEAR, InpBearCandleColor);
   ChartSetInteger(id, CHART_COLOR_VOLUME,      clrDimGray);
   ChartSetInteger(id, CHART_COLOR_BID,         clrDimGray);
   ChartSetInteger(id, CHART_COLOR_ASK,         clrDimGray);
   ChartSetInteger(id, CHART_COLOR_LAST,        clrDimGray);
   ChartSetInteger(id, CHART_COLOR_STOP_LEVEL,  InpBearCandleColor);
   ChartRedraw(id);
}

//+------------------------------------------------------------------+
double PriceOf(const MqlRates &r)
{
   switch(InpPrice)
   {
      case PRICE_OPEN:     return r.open;
      case PRICE_HIGH:     return r.high;
      case PRICE_LOW:      return r.low;
      case PRICE_MEDIAN:   return (r.high + r.low) / 2.0;
      case PRICE_TYPICAL:  return (r.high + r.low + r.close) / 3.0;
      case PRICE_WEIGHTED: return (r.high + r.low + 2.0 * r.close) / 4.0;
   }
   return r.close;
}

// WMA at index k (chronological arrays, oldest first)
double WMAat(const double &a[], int k, int p)
{
   double s = 0, w = 0;
   for(int j = 0; j < p; j++)
   {
      double wt = p - j;
      s += a[k - j] * wt;
      w += wt;
   }
   return s / w;
}

// Compute HMA for all bars. Returns count of rates; hma[] chronological, EMPTY_VALUE where not ready
int ComputeHMA(MqlRates &rates[], double &hma[], int &firstValid)
{
   int need  = InpDrawBars + InpPeriod * 2 + 10;
   int n     = CopyRates(_Symbol, InpHTF, 0, need, rates);
   if(n < InpPeriod * 2) return 0;

   int half = (int)MathFloor(InpPeriod / 2.0);
   int sq   = (int)MathFloor(MathSqrt(InpPeriod));
   if(half < 1) half = 1;
   if(sq < 1)   sq = 1;

   double px[], raw[];
   ArrayResize(px, n);
   ArrayResize(raw, n);
   ArrayResize(hma, n);
   for(int i = 0; i < n; i++) { px[i] = PriceOf(rates[i]); raw[i] = EMPTY_VALUE; hma[i] = EMPTY_VALUE; }

   for(int k = InpPeriod - 1; k < n; k++)
      raw[k] = 2.0 * WMAat(px, k, half) - WMAat(px, k, InpPeriod);

   firstValid = InpPeriod - 1 + sq - 1;
   for(int k = firstValid; k < n; k++)
      hma[k] = WMAat(raw, k, sq);
   return n;
}

//+------------------------------------------------------------------+
void DrawSegment(string name, datetime t1, double p1, datetime t2, double p2, color clr)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_RAY_LEFT,  false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, InpLineWidth);
   }
   ObjectSetInteger(0, name, OBJPROP_TIME,  0, t1);
   ObjectSetDouble (0, name, OBJPROP_PRICE, 0, p1);
   ObjectSetInteger(0, name, OBJPROP_TIME,  1, t2);
   ObjectSetDouble (0, name, OBJPROP_PRICE, 1, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

void DrawHMA(bool fullReset)
{
   MqlRates rates[];
   double hma[];
   int first = 0;
   int n = ComputeHMA(rates, hma, first);
   if(n == 0) return;

   if(fullReset) ObjectsDeleteAll(0, PFX);

   int start = MathMax(first + 1, n - InpDrawBars);
   for(int k = start; k < n; k++)
   {
      if(hma[k] == EMPTY_VALUE || hma[k-1] == EMPTY_VALUE) continue;
      color clr = (hma[k] >= hma[k-1]) ? InpHmaUpColor : InpHmaDnColor;
      DrawSegment(PFX + IntegerToString((long)rates[k].time), rates[k-1].time, hma[k-1], rates[k].time, hma[k], clr);
   }
   // extend latest value to the current time so the line reaches the live edge
   color lc = (hma[n-1] >= hma[n-2]) ? InpHmaUpColor : InpHmaDnColor;
   DrawSegment(PFX + "live", rates[n-1].time, hma[n-1], TimeCurrent() + PeriodSeconds(_Period), hma[n-1], lc);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
// +1 up-flip, -1 down-flip on closed HTF bars. rates[n-1] is forming.
int GetSignal(double &atr)
{
   MqlRates rates[];
   double hma[];
   int first = 0;
   int n = ComputeHMA(rates, hma, first);
   if(n < InpPeriod * 2 + 5) return 0;
   double a = hma[n-2], b = hma[n-3], c = hma[n-4];
   if(a == EMPTY_VALUE || b == EMPTY_VALUE || c == EMPTY_VALUE) return 0;

   double s = 0;
   int cnt = 0;
   for(int i = n - 2; i > n - 2 - InpATRPeriod && i > 0; i--)
   {
      double tr = MathMax(rates[i].high - rates[i].low,
                  MathMax(MathAbs(rates[i].high - rates[i-1].close),
                          MathAbs(rates[i].low  - rates[i-1].close)));
      s += tr; cnt++;
   }
   atr = cnt > 0 ? s / cnt : 0;

   bool upNow = a > b, upPrev = b > c;
   if(upNow && !upPrev)  return  1;
   if(!upNow && upPrev)  return -1;
   return 0;
}

bool HasPosition(long &type)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      type = PositionGetInteger(POSITION_TYPE);
      return true;
   }
   return false;
}

void ClosePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      trade.PositionClose(t);
   }
}

double CalcLots(double slDist)
{
   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double tickVal   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double step      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(slDist <= 0 || tickVal <= 0 || tickSize <= 0) return minLot;
   double lots = MathFloor(riskMoney / (slDist / tickSize * tickVal) / step) * step;
   return MathMin(maxLot, MathMax(minLot, lots));
}

//+------------------------------------------------------------------+
int OnInit()
{
   if(InpPeriod < 2) return INIT_PARAMETERS_INCORRECT;
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);
   if(InpApplyBlackTheme) ApplyTheme();
   DrawHMA(true);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, PFX);
   ChartRedraw(0);
}

void OnTick()
{
   datetime htfBar   = iTime(_Symbol, InpHTF, 0);
   datetime chartBar = iTime(_Symbol, _Period, 0);
   if(htfBar == 0 || chartBar == 0) return;

   bool newHtf   = (htfBar != g_lastHtfBar);
   bool newChart = (chartBar != g_lastChartBar);
   if(newHtf || newChart)
   {
      DrawHMA(newHtf);
      g_lastChartBar = chartBar;
   }
   if(!newHtf) return;
   g_lastHtfBar = htfBar;

   if(!InpTradeEnabled) return;
   double atr = 0;
   int sig = GetSignal(atr);
   if(sig == 0 || atr <= 0) return;

   long ptype;
   if(HasPosition(ptype))
   {
      bool opposite = (sig > 0 && ptype == POSITION_TYPE_SELL) || (sig < 0 && ptype == POSITION_TYPE_BUY);
      if(opposite && InpCloseOnFlip) ClosePositions();
      else return;
   }
   if(InpMaxSpread > 0 && SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpread) return;

   double slDist = atr * InpSL_ATR, tpDist = atr * InpTP_ATR;
   double lots = CalcLots(slDist);
   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(sig > 0)
   {
      double p = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      trade.Buy(lots, _Symbol, p, NormalizeDouble(p - slDist, dg),
                InpTP_ATR > 0 ? NormalizeDouble(p + tpDist, dg) : 0, "HMA HTF");
   }
   else
   {
      double p = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      trade.Sell(lots, _Symbol, p, NormalizeDouble(p + slDist, dg),
                 InpTP_ATR > 0 ? NormalizeDouble(p - tpDist, dg) : 0, "HMA HTF");
   }
}
//+------------------------------------------------------------------+
