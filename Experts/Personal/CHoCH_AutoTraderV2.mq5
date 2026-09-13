//+------------------------------------------------------------------+
//|              Riy_CHoCH_MTF_AutoTrader_Production.mq5              |
//|  100% behavioral clone of Pine Script v6 indicator:               |
//|  "Riy - Professional MTF Market Structure [Matrix V8]"            |
//|                                                                    |
//|  PRODUCTION COPY (v3) - based on v2 (fixed CHoCH break detection   |
//|  + real CTrade execution). ONLY ADDITION in this version:          |
//|                                                                    |
//|    When the 2nd-to-last TP (index NumPartials-2) is hit, the final |
//|    TP (index NumPartials-1) is removed (line deleted, real TP      |
//|    cancelled) and the trade switches to a trailing stop loss with  |
//|    a fixed distance (TrailPoints input, default 1000 points).      |
//|                                                                    |
//|  No existing logic was modified -- this is purely additive.        |
//|  All v2 behavior (structure drawing, CHoCH/BOS detection, order    |
//|  blocks, dashboard, real order execution) is untouched.            |
//+------------------------------------------------------------------+
#property copyright "Riy Ali"
#property version   "3.00"
#property strict

#include <Trade\Trade.mqh>

//================================= INPUTS ===================================
input group "Timeframe 1 (Short Term)"
input bool     Tf1_On    = true;
input ENUM_TIMEFRAMES Tf1_Val = PERIOD_M5;
input color    Tf1_Col   = clrGray;

input group "Timeframe 2 (Medium Term)"
input bool     Tf2_On    = true;
input ENUM_TIMEFRAMES Tf2_Val = PERIOD_M15;
input color    Tf2_Col   = clrBlue;

input group "Timeframe 3 (Long Term)"
input bool     Tf3_On    = true;
input ENUM_TIMEFRAMES Tf3_Val = PERIOD_H1;
input color    Tf3_Col   = clrBlack;

input group "Visual Settings"
input int      LineWidth = 1;

input group "BOS / CHoCH Settings"
input bool     ShowBOS       = true;
input bool     ShowCH        = true;
input int      LblSizeBrk    = 7;
input color    ColBosBull    = clrGreen;
input color    ColBosBear    = clrRed;
input color    ColChBull     = C'0,255,136';
input color    ColChBear     = C'255,0,128';

input group "Order Block / Breaker Settings"
input bool     ShowOB      = true;
input bool     ShowBB      = true;
input int      ObLimit     = 5;
input bool     RemoveMit   = true;
input int      PivotLength = 5;

input group "Trade Management"
enum ENTRY_TYPE { ENTRY_BREAKOUT_CANDLE, ENTRY_BREAKOUT_RETEST, ENTRY_CHOCH_FVG };
input ENTRY_TYPE EntryType   = ENTRY_BREAKOUT_CANDLE;
input double     SlPoints    = 700;
input double     TpRR        = 2.0;
input int        NumPartials = 4;
input int        TpSLtoBE    = 1;

input group "Trade Execution (LIVE ORDERS)"
input bool     EnableRealOrders = true;
input double   LotSize          = 0.10;
input ulong    MagicNumber      = 20260913;
input int      SlippagePoints   = 30;
input bool     ClosePartialsOnTP = true;
input double   PartialClosePct   = 25.0;

input group "Trailing Stop (NEW - after 2nd-last TP)"
input double   TrailPoints = 1000;    // trailing distance in points, applied after 2nd-last TP hit

input group "Dashboard Settings"
input bool     ShowDash = true;
enum DASH_POS { DASH_TOP_RIGHT, DASH_TOP_LEFT, DASH_BOTTOM_RIGHT, DASH_BOTTOM_LEFT };
input DASH_POS DashPos  = DASH_TOP_RIGHT;

//================================= GLOBALS ===================================
CTrade trade;
double PointValue;

struct Trade
  {
   bool     isWaiting;
   bool     isActive;
   bool     isBull;
   bool     isClosed;
   bool     isSLHit;
   bool     isSLtoBE;
   bool     isBEHit;
   int      partialsHit;
   string   entryLineName;
   string   slLineName;
   string   tpLineNames[];
   double   tpPrices[];
   double   entry;
   double   sl;
   ENUM_TIMEFRAMES tf;
   datetime creationBarTime;
   bool     isBreakoutEntry;
   bool     isFvgEntry;
   ulong    realTicket;
   double   realVolumeOrig;
   bool     isTrailing;        // NEW: true once 2nd-last TP hit and final TP removed
   double   trailExtreme;      // NEW: best favorable price seen since trailing started
  };

Trade trades[];

struct OB
  {
   string   boxName;
   double   top;
   double   bottom;
   bool     isBull;
   bool     isBroken;
  };
OB ob_list[];

struct StructState
  {
   string   lTopName;
   string   lBtmName;
   double   topPrice;
   double   btmPrice;
   datetime topTime;
   datetime btmTime;
   int      trend;
   bool     topBroken;
   bool     btmBroken;
   bool     hasTop;
   bool     hasBtm;
   datetime lastHtfBarTime;
   double   htfPrevClose;
   double   htfPrevPrevClose_unused;
  };

StructState st1, st2, st3;

double  g_last_ph = 0;
double  g_last_pl = 0;
datetime g_last_ph_time = 0;
datetime g_last_pl_time = 0;
bool     g_have_last_ph = false;
bool     g_have_last_pl = false;

long g_objCounter = 0;
string g_dashName = "RiyDash_";

//================================= UTILITIES ===================================

string UniqueName(string prefix)
  {
   g_objCounter++;
   return StringFormat("%s_%d_%I64d", prefix, (int)g_objCounter, (long)TimeLocal());
  }

string TfLabel(ENUM_TIMEFRAMES tf)
  {
   switch(tf)
     {
      case PERIOD_M1:  return "1";
      case PERIOD_M5:  return "5";
      case PERIOD_M15: return "15";
      case PERIOD_M30: return "30";
      case PERIOD_H1:  return "60";
      case PERIOD_H4:  return "240";
      case PERIOD_D1:  return "1D";
      case PERIOD_W1:  return "1W";
      case PERIOD_MN1: return "1M";
     }
   return EnumToString(tf);
  }

//================================= OBJECT DRAWING HELPERS ===================================

string DrawTrendLine(datetime t1, double p1, datetime t2, double p2, color col, int width, ENUM_LINE_STYLE style, string prefix)
  {
   string name = UniqueName(prefix);
   ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   return name;
  }

void SetLineX2(string name, datetime t2)
  {
   if(ObjectFind(0, name) < 0) return;
   double p2 = ObjectGetDouble(0, name, OBJPROP_PRICE, 1);
   ObjectMove(0, name, 1, t2, p2);
  }

void SetLinePrice(string name, double price)
  {
   if(ObjectFind(0, name) < 0) return;
   datetime t1 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
   datetime t2 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 1);
   ObjectMove(0, name, 0, t1, price);
   ObjectMove(0, name, 1, t2, price);
  }

void SetLineStyle(string name, ENUM_LINE_STYLE style)
  {
   if(ObjectFind(0, name) < 0) return;
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
  }

void SetLineColor(string name, color col)
  {
   if(ObjectFind(0, name) < 0) return;
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
  }

void DeleteObj(string name)
  {
   if(name != "" && ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);
  }

string DrawLabel(datetime t, double price, string text, color col, bool below, int fontSize)
  {
   string name = UniqueName("lbl");
   ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, below ? ANCHOR_TOP : ANCHOR_BOTTOM);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   return name;
  }

string DrawBox(datetime t1, double p1, datetime t2, double p2, color bg)
  {
   string name = UniqueName("ob");
   ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   return name;
  }

void SetBoxRight(string name, datetime t2)
  {
   if(ObjectFind(0, name) < 0) return;
   double p2 = ObjectGetDouble(0, name, OBJPROP_PRICE, 1);
   ObjectMove(0, name, 1, t2, p2);
  }

void SetBoxColor(string name, color bg)
  {
   if(ObjectFind(0, name) < 0) return;
   ObjectSetInteger(0, name, OBJPROP_COLOR, bg);
  }

int GetRGB(color c, int channel)
  {
   int v = (int)c;
   if(channel == 0) return v & 0xFF;
   if(channel == 1) return (v >> 8) & 0xFF;
   return (v >> 16) & 0xFF;
  }

color ColorWithAlpha(color base, int alphaPct)
  {
   double t = alphaPct / 100.0;
   int r = (int)(GetRGB(base, 0) * (1.0 - t));
   int g = (int)(GetRGB(base, 1) * (1.0 - t));
   int b = (int)(GetRGB(base, 2) * (1.0 - t));
   return (color)((b << 16) | (g << 8) | r);
  }

//================================= PIVOT DETECTION ===================================

bool GetPivot(ENUM_TIMEFRAMES tf, int len, bool wantHigh, double &pivotPrice, datetime &pivotTime)
  {
   int need = len * 2 + 3;
   MqlRates rates[];
   int copied = CopyRates(_Symbol, tf, 1, need, rates);
   if(copied < need) return false;
   int pivotIdx = copied - 1 - len;
   if(pivotIdx - len < 0 || pivotIdx + len >= copied) return false;

   double pivotVal = wantHigh ? rates[pivotIdx].high : rates[pivotIdx].low;
   for(int k = 1; k <= len; k++)
     {
      if(wantHigh)
        {
         if(rates[pivotIdx - k].high >= pivotVal || rates[pivotIdx + k].high >= pivotVal) return false;
        }
      else
        {
         if(rates[pivotIdx - k].low <= pivotVal || rates[pivotIdx + k].low <= pivotVal) return false;
        }
     }
   pivotPrice = pivotVal;
   pivotTime  = rates[pivotIdx].time;
   return true;
  }

bool GetHtfLiveClose(ENUM_TIMEFRAMES tf, double &liveClose, double &prevClose, datetime &liveTime)
  {
   MqlRates r[];
   int copied = CopyRates(_Symbol, tf, 0, 3, r);
   if(copied < 2) return false;
   liveClose = r[copied - 1].close;
   prevClose = r[copied - 2].close;
   liveTime  = r[copied - 1].time;
   return true;
  }

//================================= TRADE HELPERS ===================================

int PushTrade(Trade &t)
  {
   int n = ArraySize(trades);
   ArrayResize(trades, n + 1);
   trades[n] = t;
   return n;
  }

double SlDistance() { return SlPoints * PointValue; }

//------------------------------------------------------------------
// REAL ORDER EXECUTION
//------------------------------------------------------------------
bool OpenRealPosition(Trade &t)
  {
   if(!EnableRealOrders) return false;
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   double sl = t.sl;
   double tp = (ArraySize(t.tpPrices) > 0) ? t.tpPrices[ArraySize(t.tpPrices) - 1] : 0.0;

   bool ok;
   if(t.isBull)
      ok = trade.Buy(LotSize, _Symbol, 0.0, sl, tp, "RiyCHoCH-Bull");
   else
      ok = trade.Sell(LotSize, _Symbol, 0.0, sl, tp, "RiyCHoCH-Bear");

   if(ok)
     {
      t.realTicket = trade.ResultOrder();
      if(PositionSelectByTicket(t.realTicket) || PositionSelect(_Symbol))
        {
         t.realTicket = PositionGetInteger(POSITION_TICKET);
        }
      t.realVolumeOrig = LotSize;
      return true;
     }
   Print("RiyCHoCH: order failed, retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   return false;
  }

void CloseRealPosition(Trade &t)
  {
   if(!EnableRealOrders || t.realTicket == 0) return;
   if(PositionSelectByTicket(t.realTicket))
      trade.PositionClose(t.realTicket, SlippagePoints);
   t.realTicket = 0;
  }

void PartialCloseRealPosition(Trade &t)
  {
   if(!EnableRealOrders || t.realTicket == 0) return;
   if(!PositionSelectByTicket(t.realTicket)) return;
   double curVol = PositionGetDouble(POSITION_VOLUME);
   double lots = t.realVolumeOrig / (double)NumPartials;
   double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minVol   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   lots = MathFloor(lots / volStep) * volStep;
   if(lots < minVol) lots = minVol;
   if(lots >= curVol) { CloseRealPosition(t); return; }
   trade.PositionClosePartial(t.realTicket, lots, SlippagePoints);
  }

void MoveRealSLToBE(Trade &t)
  {
   if(!EnableRealOrders || t.realTicket == 0) return;
   if(!PositionSelectByTicket(t.realTicket)) return;
   double curTp = PositionGetDouble(POSITION_TP);
   trade.PositionModify(t.realTicket, t.entry, curTp);
  }

// --- NEW: cancels the real position's fixed TP (sets TP to 0) so trailing stop takes over ---
void RemoveRealTP(Trade &t)
  {
   if(!EnableRealOrders || t.realTicket == 0) return;
   if(!PositionSelectByTicket(t.realTicket)) return;
   double curSl = PositionGetDouble(POSITION_SL);
   trade.PositionModify(t.realTicket, curSl, 0.0);
  }

// --- NEW: updates the real position's SL to the trailing value ---
void UpdateRealSL(Trade &t, double newSl)
  {
   if(!EnableRealOrders || t.realTicket == 0) return;
   if(!PositionSelectByTicket(t.realTicket)) return;
   double curTp = PositionGetDouble(POSITION_TP);
   trade.PositionModify(t.realTicket, newSl, curTp);
  }

// Mirrors Trade.new(...) construction including CHoCH-FVG retest scan.
bool BuildChochTrade(bool isBull, double structPrice, datetime structTime, string structLineName,
                      datetime curTime, double curClose, const MqlRates &rBars[], Trade &outTrade)
  {
   double slDist = SlDistance();
   bool is_breakout = (EntryType == ENTRY_BREAKOUT_CANDLE);
   bool is_retest    = (EntryType == ENTRY_BREAKOUT_RETEST);
   bool is_fvg       = (EntryType == ENTRY_CHOCH_FVG);

   double trade_entry = is_breakout ? curClose : structPrice;
   bool valid_trade = true;

   if(is_fvg)
     {
      valid_trade = false;
      int total = ArraySize(rBars);
      for(int j = 0; j <= 10 && j + 2 < total; j++)
        {
         if(isBull)
           {
            if(rBars[j].low > rBars[j + 2].high)
              {
               trade_entry = rBars[j + 2].high;
               valid_trade = true;
               break;
              }
           }
         else
           {
            if(rBars[j].high < rBars[j + 2].low)
              {
               trade_entry = rBars[j + 2].low;
               valid_trade = true;
               break;
              }
           }
        }
     }

   if(!valid_trade) return false;

   Trade t;
   ZeroMemory(t);
   t.isWaiting        = !is_breakout;
   t.isActive         = is_breakout;
   t.isBull           = isBull;
   t.isClosed         = false;
   t.isSLHit          = false;
   t.isSLtoBE         = false;
   t.isBEHit          = false;
   t.partialsHit      = 0;
   t.entry            = trade_entry;
   t.sl               = isBull ? (trade_entry - slDist) : (trade_entry + slDist);
   t.creationBarTime  = curTime;
   t.isBreakoutEntry  = is_breakout;
   t.isFvgEntry       = is_fvg;
   t.realTicket       = 0;
   t.realVolumeOrig   = 0;
   t.isTrailing        = false;   // NEW
   t.trailExtreme       = trade_entry; // NEW

   if(is_breakout)
      t.entryLineName = DrawTrendLine(curTime, trade_entry, curTime, trade_entry, clrYellow, LineWidth, STYLE_SOLID, "entry");
   else if(is_retest)
      t.entryLineName = structLineName;
   else
      t.entryLineName = DrawTrendLine(curTime, trade_entry, curTime + PeriodSeconds() * 5, trade_entry, clrYellow, LineWidth, STYLE_DOT, "entryfvg");

   t.slLineName = DrawTrendLine(curTime, t.sl, curTime, t.sl, clrRed, LineWidth, STYLE_DASH, "sl");

   double step = (slDist * TpRR) / (double)NumPartials;
   ArrayResize(t.tpPrices, NumPartials);
   ArrayResize(t.tpLineNames, NumPartials);
   for(int i = 1; i <= NumPartials; i++)
     {
      double p = isBull ? (trade_entry + step * i) : (trade_entry - step * i);
      t.tpPrices[i - 1] = p;
      t.tpLineNames[i - 1] = DrawTrendLine(curTime, p, curTime, p, clrGreen, LineWidth, STYLE_DASH, "tp");
     }

   if(is_breakout)
      OpenRealPosition(t);

   outTrade = t;
   return true;
  }

//================================= STRUCTURE PROCESSING (per timeframe) ===================================

void ProcessStructure(bool tf_on, ENUM_TIMEFRAMES tf, color col, StructState &st, bool newHtfBar,
                       Trade &newTrades[], bool &bull_ch, bool &bear_ch)
  {
   bull_ch = false;
   bear_ch = false;

   double liveClose, prevClose;
   datetime liveTime;
   if(!GetHtfLiveClose(tf, liveClose, prevClose, liveTime)) return;

   if(newHtfBar)
     {
      double p_h, p_l;
      datetime t_h, t_l;
      bool got_h = GetPivot(tf, PivotLength, true,  p_h, t_h);
      bool got_l = GetPivot(tf, PivotLength, false, p_l, t_l);

      if(got_h)
        {
         st.topPrice  = p_h;
         st.topTime   = t_h;
         st.topBroken = false;
         st.hasTop    = true;
         if(tf_on)
           {
            DeleteObj(st.lTopName);
            st.lTopName = DrawTrendLine(t_h, p_h, liveTime, p_h, col, LineWidth, STYLE_SOLID, "top");
           }
        }
      if(got_l)
        {
         st.btmPrice  = p_l;
         st.btmTime   = t_l;
         st.btmBroken = false;
         st.hasBtm    = true;
         if(tf_on)
           {
            DeleteObj(st.lBtmName);
            st.lBtmName = DrawTrendLine(t_l, p_l, liveTime, p_l, col, LineWidth, STYLE_SOLID, "btm");
           }
        }
     }

   if(!tf_on) return;

   MqlRates rBars[];
   CopyRates(_Symbol, PERIOD_CURRENT, 0, 20, rBars);
   ArraySetAsSeries(rBars, true);

   if(st.hasTop && st.lTopName != "" && !st.topBroken)
     {
      SetLineX2(st.lTopName, liveTime + PeriodSeconds(PERIOD_CURRENT) * 5);
      if(liveClose > st.topPrice && prevClose <= st.topPrice)
        {
         SetLineStyle(st.lTopName, STYLE_DASH);
         st.topBroken = true;
         bool is_bos = (st.trend == 1) || (st.trend == 0);
         string tag = is_bos ? "BOS" : ("CHoCH (" + DoubleToString(st.topPrice, _Digits) + ")");
         color txtCol = is_bos ? ColBosBull : ColChBull;
         string finalTxt = tag + " " + TfLabel(tf);
         if((is_bos && ShowBOS) || (!is_bos && ShowCH))
            DrawLabel(st.topTime, st.topPrice, finalTxt, txtCol, true, LblSizeBrk);

         if(!is_bos)
           {
            bull_ch = true;
            Trade nt;
            if(BuildChochTrade(true, st.topPrice, st.topTime, st.lTopName, liveTime, liveClose, rBars, nt))
              {
               nt.tf = tf;
               int sz = ArraySize(newTrades);
               ArrayResize(newTrades, sz + 1);
               newTrades[sz] = nt;
              }
           }
         st.trend = 1;
        }
     }

   if(st.hasBtm && st.lBtmName != "" && !st.btmBroken)
     {
      SetLineX2(st.lBtmName, liveTime + PeriodSeconds(PERIOD_CURRENT) * 5);
      if(liveClose < st.btmPrice && prevClose >= st.btmPrice)
        {
         SetLineStyle(st.lBtmName, STYLE_DASH);
         st.btmBroken = true;
         bool is_bos = (st.trend == -1) || (st.trend == 0);
         string tag = is_bos ? "BOS" : "CHoCH";
         color txtCol = is_bos ? ColBosBear : ColChBear;
         string finalTxt = tag + " " + TfLabel(tf);
         if((is_bos && ShowBOS) || (!is_bos && ShowCH))
            DrawLabel(st.btmTime, st.btmPrice, finalTxt, txtCol, false, LblSizeBrk);

         if(!is_bos)
           {
            bear_ch = true;
            Trade nt;
            if(BuildChochTrade(false, st.btmPrice, st.btmTime, st.lBtmName, liveTime, liveClose, rBars, nt))
              {
               nt.tf = tf;
               int sz = ArraySize(newTrades);
               ArrayResize(newTrades, sz + 1);
               newTrades[sz] = nt;
              }
           }
         st.trend = -1;
        }
     }
  }

//================================= NEW: TRAILING STOP HELPERS ===================================
// Fixed-distance trailing stop, activated only after the 2nd-to-last TP has been hit and the
// final TP has been removed. Never loosens the stop -- only tightens it in the trade's favor.

void ActivateTrailing(Trade &t, double curPriceRef)
  {
   if(NumPartials < 2) return;      // "2nd last" undefined for a single partial -- guard, no-op
   if(t.isTrailing) return;

   int lastIdx = NumPartials - 1;
   // Remove the final TP (line + real order TP)
   if(lastIdx >= 0 && lastIdx < ArraySize(t.tpLineNames))
      DeleteObj(t.tpLineNames[lastIdx]);
   RemoveRealTP(t);

   t.isTrailing   = true;
   t.trailExtreme = curPriceRef;

   double trailDist = TrailPoints * PointValue;
   double newSl = t.isBull ? (t.trailExtreme - trailDist) : (t.trailExtreme + trailDist);

   // Only tighten, never loosen, relative to current sl (matches "trailing" semantics)
   if(t.isBull && newSl > t.sl) { t.sl = newSl; }
   else if(!t.isBull && newSl < t.sl) { t.sl = newSl; }

   if(t.slLineName != "")
      SetLinePrice(t.slLineName, t.sl);
   else
      t.slLineName = DrawTrendLine(TimeCurrent(), t.sl, TimeCurrent(), t.sl, clrRed, LineWidth, STYLE_DASH, "sl");

   UpdateRealSL(t, t.sl);
  }

void ApplyTrailingStop(Trade &t, double curHigh, double curLow)
  {
   if(!t.isTrailing || !t.isActive || t.isClosed) return;

   double trailDist = TrailPoints * PointValue;

   if(t.isBull)
     {
      if(curHigh > t.trailExtreme)
        {
         t.trailExtreme = curHigh;
         double newSl = t.trailExtreme - trailDist;
         if(newSl > t.sl)
           {
            t.sl = newSl;
            if(t.slLineName != "") SetLinePrice(t.slLineName, t.sl);
            UpdateRealSL(t, t.sl);
           }
        }
     }
   else
     {
      if(curLow < t.trailExtreme)
        {
         t.trailExtreme = curLow;
         double newSl = t.trailExtreme + trailDist;
         if(newSl < t.sl)
           {
            t.sl = newSl;
            if(t.slLineName != "") SetLinePrice(t.slLineName, t.sl);
            UpdateRealSL(t, t.sl);
           }
        }
     }
  }

//================================= TRADE LIFECYCLE UPDATE ===================================
// UNCHANGED existing logic, with additive trailing-activation/trailing-apply calls inserted
// exactly at the points needed (marked "NEW" below). No existing branch was altered.

void UpdateTrades(bool bull_ch1, bool bear_ch1, bool bull_ch2, bool bear_ch2, bool bull_ch3, bool bear_ch3,
                   double curHigh, double curLow, datetime curTime)
  {
   for(int i = ArraySize(trades) - 1; i >= 0; i--)
     {
      Trade t;
      t = trades[i];
      if(t.isClosed) { trades[i] = t; continue; }

      bool should_close = false;
      if(t.tf == Tf1_Val) { if(t.isBull && bear_ch1) should_close = true; if(!t.isBull && bull_ch1) should_close = true; }
      if(t.tf == Tf2_Val) { if(t.isBull && bear_ch2) should_close = true; if(!t.isBull && bull_ch2) should_close = true; }
      if(t.tf == Tf3_Val) { if(t.isBull && bear_ch3) should_close = true; if(!t.isBull && bull_ch3) should_close = true; }

      if(should_close)
        {
         t.isClosed = true;
         t.isActive = false;
         CloseRealPosition(t);
         DeleteObj(t.slLineName);
         t.slLineName = "";
         for(int j = 0; j < ArraySize(t.tpLineNames); j++)
            if(j >= t.partialsHit) DeleteObj(t.tpLineNames[j]);
         trades[i] = t;
         continue;
        }

      if(t.isWaiting && !t.isActive && t.isFvgEntry)
         SetLineX2(t.entryLineName, curTime + PeriodSeconds(PERIOD_CURRENT) * 5);

      if(t.isBull)
        {
         if(t.isWaiting && !t.isActive && curTime > t.creationBarTime && curLow <= t.entry)
           {
            t.isWaiting = false;
            t.isActive = true;
            SetLineColor(t.entryLineName, clrYellow);
            OpenRealPosition(t);
           }
         else if(t.isActive)
           {
            if(t.isBreakoutEntry || t.isFvgEntry)
               SetLineX2(t.entryLineName, curTime);

            // NEW: advance trailing stop (if active) before the SL check, using this bar's extremes
            if(t.isTrailing)
               ApplyTrailingStop(t, curHigh, curLow);

            if(curLow <= t.sl)
              {
               t.isClosed = true;
               if(t.isSLtoBE)
                  t.isBEHit = true;
               else
                 {
                  t.isSLHit = true;
                  SetLineX2(t.slLineName, curTime);
                  CloseRealPosition(t);
                 }
               for(int j = 0; j < ArraySize(t.tpLineNames); j++)
                  if(j >= t.partialsHit) DeleteObj(t.tpLineNames[j]);
              }
            else
              {
               // NEW: once trailing is active, the fixed-TP ladder no longer applies (last TP removed);
               // skip the standard next_tp check entirely for this trade.
               if(!t.isTrailing && ArraySize(t.tpPrices) > 0 && t.partialsHit < ArraySize(t.tpPrices))
                 {
                  double next_tp = t.tpPrices[t.partialsHit];
                  if(curHigh >= next_tp)
                    {
                     SetLineColor(t.tpLineNames[t.partialsHit], clrGreen);
                     SetLineX2(t.tpLineNames[t.partialsHit], curTime);
                     if(ClosePartialsOnTP) PartialCloseRealPosition(t);
                     t.partialsHit++;
                     if(t.partialsHit == TpSLtoBE)
                       {
                        t.isSLtoBE = true;
                        t.sl = t.entry;
                        DeleteObj(t.slLineName);
                        t.slLineName = "";
                        MoveRealSLToBE(t);
                       }
                     // NEW: 2nd-to-last TP just hit -> remove final TP, switch to trailing stop
                     if(NumPartials >= 2 && t.partialsHit == (NumPartials - 1) && !t.isTrailing)
                        ActivateTrailing(t, curHigh);
                    }
                 }
              }
           }
        }
      else
        {
         if(t.isWaiting && !t.isActive && curTime > t.creationBarTime && curHigh >= t.entry)
           {
            t.isWaiting = false;
            t.isActive = true;
            SetLineColor(t.entryLineName, clrYellow);
            OpenRealPosition(t);
           }
         else if(t.isActive)
           {
            if(t.isBreakoutEntry || t.isFvgEntry)
               SetLineX2(t.entryLineName, curTime);

            // NEW: advance trailing stop (if active) before the SL check
            if(t.isTrailing)
               ApplyTrailingStop(t, curHigh, curLow);

            if(curHigh >= t.sl)
              {
               t.isClosed = true;
               if(t.isSLtoBE)
                  t.isBEHit = true;
               else
                 {
                  t.isSLHit = true;
                  SetLineX2(t.slLineName, curTime);
                  CloseRealPosition(t);
                 }
               for(int j = 0; j < ArraySize(t.tpLineNames); j++)
                  if(j >= t.partialsHit) DeleteObj(t.tpLineNames[j]);
              }
            else
              {
               if(!t.isTrailing && ArraySize(t.tpPrices) > 0 && t.partialsHit < ArraySize(t.tpPrices))
                 {
                  double next_tp = t.tpPrices[t.partialsHit];
                  if(curLow <= next_tp)
                    {
                     SetLineColor(t.tpLineNames[t.partialsHit], clrGreen);
                     SetLineX2(t.tpLineNames[t.partialsHit], curTime);
                     if(ClosePartialsOnTP) PartialCloseRealPosition(t);
                     t.partialsHit++;
                     if(t.partialsHit == TpSLtoBE)
                       {
                        t.isSLtoBE = true;
                        t.sl = t.entry;
                        DeleteObj(t.slLineName);
                        t.slLineName = "";
                        MoveRealSLToBE(t);
                       }
                     // NEW: 2nd-to-last TP just hit -> remove final TP, switch to trailing stop
                     if(NumPartials >= 2 && t.partialsHit == (NumPartials - 1) && !t.isTrailing)
                        ActivateTrailing(t, curLow);
                    }
                 }
              }
           }
        }
      trades[i] = t;
     }
  }

//================================= ORDER BLOCK LOGIC ===================================

void ProcessOrderBlocks(double curClose, double curClose1, double curHigh, double curLow, datetime curTime)
  {
   double p_h, p_l;
   datetime t_h, t_l;
   bool got_h = GetPivot(PERIOD_CURRENT, PivotLength, true,  p_h, t_h);
   bool got_l = GetPivot(PERIOD_CURRENT, PivotLength, false, p_l, t_l);

   if(got_h) { g_last_ph = p_h; g_last_ph_time = t_h; g_have_last_ph = true; }
   if(got_l) { g_last_pl = p_l; g_last_pl_time = t_l; g_have_last_pl = true; }

   MqlRates rBars[];
   CopyRates(_Symbol, PERIOD_CURRENT, 0, 500, rBars);
   ArraySetAsSeries(rBars, true);

   if(g_have_last_ph && ShowOB && curClose > g_last_ph && curClose1 <= g_last_ph)
     {
      int shift = iBarShift(_Symbol, PERIOD_CURRENT, g_last_pl_time, true);
      if(g_have_last_pl && shift >= 0 && shift < ArraySize(rBars))
        {
         double ob_top = rBars[shift].high;
         double ob_btm = rBars[shift].low;
         string boxName = DrawBox(g_last_pl_time, ob_top, curTime, ob_btm, ColorWithAlpha(clrGreen, 85));
         OB ob; ob.boxName = boxName; ob.top = ob_top; ob.bottom = ob_btm; ob.isBull = true; ob.isBroken = false;
         int n = ArraySize(ob_list);
         ArrayResize(ob_list, n + 1);
         for(int k = n; k > 0; k--) ob_list[k] = ob_list[k - 1];
         ob_list[0] = ob;
        }
     }

   if(g_have_last_pl && ShowOB && curClose < g_last_pl && curClose1 >= g_last_pl)
     {
      int shift = iBarShift(_Symbol, PERIOD_CURRENT, g_last_ph_time, true);
      if(g_have_last_ph && shift >= 0 && shift < ArraySize(rBars))
        {
         double ob_top = rBars[shift].high;
         double ob_btm = rBars[shift].low;
         string boxName = DrawBox(g_last_ph_time, ob_top, curTime, ob_btm, ColorWithAlpha(clrRed, 85));
         OB ob; ob.boxName = boxName; ob.top = ob_top; ob.bottom = ob_btm; ob.isBull = false; ob.isBroken = false;
         int n = ArraySize(ob_list);
         ArrayResize(ob_list, n + 1);
         for(int k = n; k > 0; k--) ob_list[k] = ob_list[k - 1];
         ob_list[0] = ob;
        }
     }

   if(ArraySize(ob_list) > ObLimit)
     {
      int last = ArraySize(ob_list) - 1;
      DeleteObj(ob_list[last].boxName);
      ArrayResize(ob_list, last);
     }

   for(int i = ArraySize(ob_list) - 1; i >= 0; i--)
     {
      SetBoxRight(ob_list[i].boxName, curTime + PeriodSeconds(PERIOD_CURRENT) * 5);
      bool delete_me = false;
      if(ob_list[i].isBull)
        {
         if(curClose < ob_list[i].bottom)
           {
            if(ShowBB) { ob_list[i].isBroken = true; SetBoxColor(ob_list[i].boxName, ColorWithAlpha(clrRed, 90)); }
            else delete_me = true;
           }
         else if(RemoveMit && !ob_list[i].isBroken && curLow <= ob_list[i].top)
            delete_me = true;
        }
      else
        {
         if(curClose > ob_list[i].top)
           {
            if(ShowBB) { ob_list[i].isBroken = true; SetBoxColor(ob_list[i].boxName, ColorWithAlpha(clrGreen, 90)); }
            else delete_me = true;
           }
         else if(RemoveMit && !ob_list[i].isBroken && curHigh >= ob_list[i].bottom)
            delete_me = true;
        }

      if(delete_me)
        {
         DeleteObj(ob_list[i].boxName);
         int sz = ArraySize(ob_list);
         for(int k = i; k < sz - 1; k++) ob_list[k] = ob_list[k + 1];
         ArrayResize(ob_list, sz - 1);
        }
     }
  }

//================================= DASHBOARD ===================================

void UpdateDashboard()
  {
   if(!ShowDash) return;

   int total_executed = 0, total_active = 0, total_tp1 = 0, total_full_tp = 0, total_sl = 0, total_be = 0;
   for(int i = 0; i < ArraySize(trades); i++)
     {
      Trade t = trades[i];
      if(t.isActive || t.isClosed) total_executed++;
      if(t.isActive) total_active++;
      if(t.partialsHit >= 1) total_tp1++;
      if(t.partialsHit == NumPartials) total_full_tp++;
      if(t.isSLHit) total_sl++;
      if(t.isBEHit) total_be++;
     }

   int corner;
   switch(DashPos)
     {
      case DASH_TOP_LEFT:     corner = CORNER_LEFT_UPPER;  break;
      case DASH_BOTTOM_RIGHT: corner = CORNER_RIGHT_LOWER; break;
      case DASH_BOTTOM_LEFT:  corner = CORNER_LEFT_LOWER;  break;
      default:                corner = CORNER_RIGHT_UPPER; break;
     }

   string rows[7][2] =
     {
      {"Metrics",           "Value"},
      {"Total Executed",    IntegerToString(total_executed)},
      {"Currently Active",  IntegerToString(total_active)},
      {"Hit at least TP1",  IntegerToString(total_tp1)},
      {"Full TP Hit",       IntegerToString(total_full_tp)},
      {"SL Hit",             IntegerToString(total_sl)},
      {"BE Hit",             IntegerToString(total_be)}
     };
   color colA[7] = {clrWhite, clrWhite, clrWhite, clrLime, clrLime, clrRed, clrYellow};

   int rowH = 18, colW = 110;
   for(int r = 0; r < 7; r++)
     {
      for(int c = 0; c < 2; c++)
        {
         string name = g_dashName + IntegerToString(r) + "_" + IntegerToString(c);
         if(ObjectFind(0, name) < 0)
           {
            ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
            ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
            ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 10 + c * colW);
            ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 10 + r * rowH);
            ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
            ObjectSetString(0, name, OBJPROP_FONT, "Arial");
            ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
           }
         ObjectSetString(0, name, OBJPROP_TEXT, rows[r][c]);
         ObjectSetInteger(0, name, OBJPROP_COLOR, r == 0 ? clrWhite : colA[r]);
        }
     }
  }

//================================= NEW HTF-BAR DETECTION ===================================
datetime g_lastBarTf1 = 0, g_lastBarTf2 = 0, g_lastBarTf3 = 0;

bool IsNewBar(ENUM_TIMEFRAMES tf, datetime &lastStored)
  {
   datetime t = (datetime)SeriesInfoInteger(_Symbol, tf, SERIES_LASTBAR_DATE);
   if(t != lastStored)
     {
      lastStored = t;
      return true;
     }
   return false;
  }

//================================= EXPERT LIFECYCLE ===================================

int OnInit()
  {
   PointValue = _Point;
   ArrayResize(trades, 0);
   ArrayResize(ob_list, 0);
   g_dashName = "RiyDash_" + IntegerToString((int)MagicNumber) + "_";
   ZeroMemory(st1); ZeroMemory(st2); ZeroMemory(st3);
   st1.trend = 0; st2.trend = 0; st3.trend = 0;
   EventSetTimer(1);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   ObjectsDeleteAll(0, "lbl");
   ObjectsDeleteAll(0, "top");
   ObjectsDeleteAll(0, "btm");
   ObjectsDeleteAll(0, "entry");
   ObjectsDeleteAll(0, "sl");
   ObjectsDeleteAll(0, "tp");
   ObjectsDeleteAll(0, "ob");
   ObjectsDeleteAll(0, g_dashName);
  }

void OnTimer() { RunLogic(); }
void OnTick()  { RunLogic(); }

void RunLogic()
  {
   MqlRates curBar[];
   if(CopyRates(_Symbol, PERIOD_CURRENT, 0, 2, curBar) < 2) return;
   double curClose  = curBar[1].close;
   double curClose1 = curBar[0].close;
   double curHigh   = curBar[1].high;
   double curLow    = curBar[1].low;
   datetime curTime = curBar[1].time;

   Trade newTrades1[], newTrades2[], newTrades3[];
   bool bull_ch1 = false, bear_ch1 = false;
   bool bull_ch2 = false, bear_ch2 = false;
   bool bull_ch3 = false, bear_ch3 = false;

   bool isNew1 = IsNewBar(Tf1_Val, g_lastBarTf1);
   bool isNew2 = IsNewBar(Tf2_Val, g_lastBarTf2);
   bool isNew3 = IsNewBar(Tf3_Val, g_lastBarTf3);

   ProcessStructure(Tf1_On, Tf1_Val, Tf1_Col, st1, isNew1, newTrades1, bull_ch1, bear_ch1);
   ProcessStructure(Tf2_On, Tf2_Val, Tf2_Col, st2, isNew2, newTrades2, bull_ch2, bear_ch2);
   ProcessStructure(Tf3_On, Tf3_Val, Tf3_Col, st3, isNew3, newTrades3, bull_ch3, bear_ch3);

   for(int i = 0; i < ArraySize(newTrades1); i++) PushTrade(newTrades1[i]);
   for(int i = 0; i < ArraySize(newTrades2); i++) PushTrade(newTrades2[i]);
   for(int i = 0; i < ArraySize(newTrades3); i++) PushTrade(newTrades3[i]);

   UpdateTrades(bull_ch1, bear_ch1, bull_ch2, bear_ch2, bull_ch3, bear_ch3, curHigh, curLow, curTime);

   ProcessOrderBlocks(curClose, curClose1, curHigh, curLow, curTime);

   UpdateDashboard();

   ChartRedraw(0);
  }
//+------------------------------------------------------------------+