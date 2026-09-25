//+------------------------------------------------------------------+
//| Riy_CHoCH_SingleTF_AutoTrader_v18.mq5                             |
//| Single-timeframe CHoCH/BOS structure auto-trader.                 |
//| Adds BE-Reentry: 2nd chance at the same entry after a BE stop-out.|
//+------------------------------------------------------------------+
#property copyright "Riy Ali"
#property version   "20.00"
#property strict

#include <Trade\Trade.mqh>

//================================= INPUTS ===================================
input group "Structure Timeframe"
input bool     Tf1_On    = true;
input ENUM_TIMEFRAMES Tf1_Val = PERIOD_M5;
input color    Tf1_Col   = clrGray;

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
input bool     EnableRealOrders    = true;
input double   LotSize             = 0.10;
input ulong    MagicNumber         = 20260913;
input int      SlippagePoints      = 30;
input bool     ClosePartialsOnTP   = true;
input int      MinStopBufferPoints = 5;
input int      TpAttachDelaySec    = 1;

input group "Trailing Stop (after 2nd-last TP)"
input double   TrailPoints = 1000;

input group "Position Persistence"
input bool     CloseOnOppositeCHoCH = false;

input group "DD Entries (drawdown-triggered averaging, shared SL)"
input bool     EnableDDEntries = true;
input double   DDStepPoints    = 500;
input int      MaxDDEntries    = 2;

input group "Worst-Entry Cutoff (every chain member except the newest)"
input bool     EnableWorstEntryCutoff   = true;
input double   WorstEntryProfitTrigger  = 2.0;
input bool     VerboseChainLogging      = true;

input group "BE Re-Entry (2nd chance at same entry after BE stop-out)"
input bool     EnableBEReentry = true;
input int      MaxBEReentries  = 1;   // per original entry level, capped generation depth

input group "Trading Session Filter (server/broker time)"
input bool     EnableSessionFilter = true;
input int      SessionStartHour    = 2;
input int      SessionStartMinute  = 0;
input int      SessionEndHour      = 22;
input int      SessionEndMinute    = 0;

input group "Structure History Seeding"
input int      StructureLookbackBars = 500;

input group "Dashboard Settings"
input bool     ShowDash = true;
enum DASH_POS { DASH_TOP_RIGHT, DASH_TOP_LEFT, DASH_BOTTOM_RIGHT, DASH_BOTTOM_LEFT };
input DASH_POS DashPos  = DASH_TOP_RIGHT;

//================================= GLOBALS ===================================
CTrade trade;
double PointValue;
double g_volStep, g_minVol;

struct Trade
  {
   bool     isWaiting, isActive, isBull, isClosed, isSLHit, isSLtoBE, isBEHit;
   int      partialsHit;
   int      effectivePartials;
   bool     tpLadderAttached;
   datetime tpAttachAfter;
   string   entryLineName, slLineName;
   string   tpLineNames[];
   double   tpPrices[];
   double   entry, sl;
   ENUM_TIMEFRAMES tf;
   datetime creationBarTime;
   long     creationSeq;
   bool     isBreakoutEntry, isFvgEntry;
   ulong    realTicket;
   double   realVolumeOrig;
   bool     isTrailing;
   double   trailExtreme;
   int      ddChainIdx;
   bool     isDDEntry;
   int      beReentryGeneration; // NEW: 0 for an original trade, increments each BE-reentry spawn
  };
Trade trades[];
long g_tradeSeqCounter = 0;

// NEW: watch created when a trade closes via TRUE breakeven. No trade exists yet -- we wait for a
// candle to CLOSE back beyond the same entry price in the original favorable direction, then open
// a fresh trade at that same level (full normal construction: own SL/TP/partial ladder).
struct BEWatch
  {
   bool     isBull;
   double   entryPrice;
   ENUM_TIMEFRAMES tf;
   int      generation;
  };
BEWatch g_beWatches[];

struct DDChain
  {
   bool     isBull;
   double   sharedSL;
   double   lastEntryPrice;
   int      count;
   ENUM_TIMEFRAMES tf;
  };
DDChain g_ddChains[];

struct OB { string boxName; double top, bottom; bool isBull, isBroken; };
OB ob_list[];

struct StructState
  {
   string lTopName, lBtmName;
   double topPrice, btmPrice;
   datetime topTime, btmTime;
   int trend;
   bool topBroken, btmBroken, hasTop, hasBtm;
  };
StructState st1;

double g_last_ph = 0, g_last_pl = 0;
datetime g_last_ph_time = 0, g_last_pl_time = 0;
bool g_have_last_ph = false, g_have_last_pl = false;
long g_objCounter = 0;
string g_dashName = "RiyDash_";
datetime g_lastBarTf1 = 0;
datetime g_lastBarChart = 0;

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

int ComputeEffectivePartials(double lotSize)
  {
   int maxByVolume = (int)MathFloor(lotSize / g_minVol + 1e-8);
   if(maxByVolume < 1) maxByVolume = 1;
   int eff = MathMin(NumPartials, maxByVolume);
   if(eff < NumPartials)
      Print("RiyCHoCH: WARNING -- lot=", DoubleToString(lotSize,2), " cannot be split into ",
            NumPartials, " partials on this symbol (min volume=", DoubleToString(g_minVol,2),
            "). Using ", eff, " partial(s) instead.");
   return eff;
  }

bool IsWithinTradingSession()
  {
   if(!EnableSessionFilter) return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int nowMinutes   = dt.hour*60 + dt.min;
   int startMinutes = SessionStartHour*60 + SessionStartMinute;
   int endMinutes   = SessionEndHour*60 + SessionEndMinute;
   if(startMinutes <= endMinutes)
      return (nowMinutes >= startMinutes && nowMinutes < endMinutes);
   else
      return (nowMinutes >= startMinutes || nowMinutes < endMinutes);
  }

//================================= DRAWING HELPERS ===================================

string DrawTrendLine(datetime t1, double p1, datetime t2, double p2, color col, int width, ENUM_LINE_STYLE style, string prefix)
  {
   string name = UniqueName(prefix);
   ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
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

void SetLineStyle(string name, ENUM_LINE_STYLE style) { if(ObjectFind(0, name) >= 0) ObjectSetInteger(0, name, OBJPROP_STYLE, style); }
void SetLineColor(string name, color col)             { if(ObjectFind(0, name) >= 0) ObjectSetInteger(0, name, OBJPROP_COLOR, col); }
void DeleteObj(string name)                            { if(name != "" && ObjectFind(0, name) >= 0) ObjectDelete(0, name); }

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
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   return name;
  }

void SetBoxRight(string name, datetime t2) { if(ObjectFind(0, name) >= 0) { double p2 = ObjectGetDouble(0, name, OBJPROP_PRICE, 1); ObjectMove(0, name, 1, t2, p2); } }
void SetBoxColor(string name, color bg)    { if(ObjectFind(0, name) >= 0) ObjectSetInteger(0, name, OBJPROP_COLOR, bg); }

int GetRGB(color c, int ch) { int v=(int)c; if(ch==0) return v&0xFF; if(ch==1) return (v>>8)&0xFF; return (v>>16)&0xFF; }
color ColorWithAlpha(color base, int alphaPct)
  {
   double t = alphaPct/100.0;
   return (color)((int)(GetRGB(base,2)*(1.0-t))<<16 | (int)(GetRGB(base,1)*(1.0-t))<<8 | (int)(GetRGB(base,0)*(1.0-t)));
  }

//================================= PIVOT DETECTION ===================================

bool GetPivot(ENUM_TIMEFRAMES tf, int len, bool wantHigh, double &pivotPrice, datetime &pivotTime)
  {
   int need = len*2+3;
   MqlRates rates[];
   int copied = CopyRates(_Symbol, tf, 1, need, rates);
   if(copied < need) return false;
   int idx = copied-1-len;
   if(idx-len < 0 || idx+len >= copied) return false;
   double val = wantHigh ? rates[idx].high : rates[idx].low;
   for(int k=1; k<=len; k++)
     {
      if(wantHigh) { if(rates[idx-k].high >= val || rates[idx+k].high >= val) return false; }
      else         { if(rates[idx-k].low  <= val || rates[idx+k].low  <= val) return false; }
     }
   pivotPrice = val; pivotTime = rates[idx].time;
   return true;
  }

bool GetHtfLiveClose(ENUM_TIMEFRAMES tf, double &liveClose, double &prevClose, datetime &liveTime)
  {
   MqlRates r[];
   int copied = CopyRates(_Symbol, tf, 0, 3, r);
   if(copied < 2) return false;
   liveClose = r[copied-1].close; prevClose = r[copied-2].close; liveTime = r[copied-1].time;
   return true;
  }

bool IsPivotHighAt(const MqlRates &rates[], int idx, int len)
  {
   if(idx-len < 0 || idx+len >= ArraySize(rates)) return false;
   double val = rates[idx].high;
   for(int k=1; k<=len; k++)
      if(rates[idx-k].high >= val || rates[idx+k].high >= val) return false;
   return true;
  }
bool IsPivotLowAt(const MqlRates &rates[], int idx, int len)
  {
   if(idx-len < 0 || idx+len >= ArraySize(rates)) return false;
   double val = rates[idx].low;
   for(int k=1; k<=len; k++)
      if(rates[idx-k].low <= val || rates[idx+k].low <= val) return false;
   return true;
  }

//================================= STRUCTURE HISTORY SEEDING ===================================

void InitializeStructureFromHistory(StructState &st, ENUM_TIMEFRAMES tf, bool tf_on, color col, int lookback)
  {
   ZeroMemory(st);
   st.trend = 0;

   int need = lookback + PivotLength*2 + 3;
   MqlRates rates[];
   int copied = CopyRates(_Symbol, tf, 1, need, rates);
   if(copied < PivotLength*2 + 3)
     {
      Print("RiyCHoCH: not enough history on ", TfLabel(tf), " to seed structure (need ", PivotLength*2+3, ", got ", copied, ").");
      return;
     }

   int startIdx = MathMax(PivotLength, copied - lookback);

   for(int i = startIdx; i < copied; i++)
     {
      int cand = i - PivotLength;
      if(cand >= 0)
        {
         if(IsPivotHighAt(rates, cand, PivotLength))
           {
            st.topPrice = rates[cand].high;
            st.topTime  = rates[cand].time;
            st.topBroken = false;
            st.hasTop = true;
           }
         if(IsPivotLowAt(rates, cand, PivotLength))
           {
            st.btmPrice = rates[cand].low;
            st.btmTime  = rates[cand].time;
            st.btmBroken = false;
            st.hasBtm = true;
           }
        }

      if(i < 1) continue;
      double c = rates[i].close, c1 = rates[i-1].close;

      if(st.hasTop && !st.topBroken && c > st.topPrice && c1 <= st.topPrice)
        {
         st.topBroken = true;
         st.trend = 1;
        }
      if(st.hasBtm && !st.btmBroken && c < st.btmPrice && c1 >= st.btmPrice)
        {
         st.btmBroken = true;
         st.trend = -1;
        }
     }

   if(!tf_on) return;

   datetime latestTime = rates[copied-1].time;
   if(st.hasTop && !st.topBroken)
      st.lTopName = DrawTrendLine(st.topTime, st.topPrice, latestTime, st.topPrice, col, LineWidth, STYLE_SOLID, "top");
   if(st.hasBtm && !st.btmBroken)
      st.lBtmName = DrawTrendLine(st.btmTime, st.btmPrice, latestTime, st.btmPrice, col, LineWidth, STYLE_SOLID, "btm");

   Print("RiyCHoCH: structure seeded from ", copied, " bars of ", TfLabel(tf), " history -- trend=", st.trend);
  }

//================================= REAL ORDER EXECUTION ===================================

bool TicketAlreadyTracked(ulong ticket)
  {
   for(int i = 0; i < ArraySize(trades); i++)
      if(trades[i].realTicket == ticket) return true;
   return false;
  }

ulong FindUntrackedPosition()
  {
   ulong best = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber) continue;
      if(TicketAlreadyTracked(ticket)) continue;
      if(ticket > best) best = ticket;
     }
   return best;
  }

void EnforceMinStopDistance(bool isBull, double refPrice, double &sl, double &tp)
  {
   long minPts = MathMax(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
                          SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL)) + MinStopBufferPoints;
   double minDist = minPts * PointValue;
   if(minDist <= 0) return;
   int dir = isBull ? 1 : -1;
   if((refPrice - sl) * dir < minDist) sl = refPrice - dir*minDist;
   if(tp > 0 && (tp - refPrice) * dir < minDist) tp = refPrice + dir*minDist;
  }

bool SelectPos(ulong ticket) { return ticket != 0 && PositionSelectByTicket(ticket); }

bool OpenRealPositionEx(Trade &t, double lotSize)
  {
   if(!EnableRealOrders) return false;
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);

   double refPrice = t.isBull ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = t.sl;
   double tp = 0.0;
   EnforceMinStopDistance(t.isBull, refPrice, sl, tp);

   string cmt = t.isDDEntry ? "RiyCHoCH-DD" : (t.beReentryGeneration > 0 ? "RiyCHoCH-BEReentry" : "RiyCHoCH");
   bool ok = t.isBull ? trade.Buy(lotSize, _Symbol, 0.0, sl, 0.0, cmt)
                       : trade.Sell(lotSize, _Symbol, 0.0, sl, 0.0, cmt);

   if(!ok)
     {
      Print("RiyCHoCH: order FAILED entry=", DoubleToString(t.entry,_Digits),
            " sl=", DoubleToString(sl,_Digits),
            " retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      return false;
     }

   ulong ticket = FindUntrackedPosition();
   if(ticket == 0)
     {
      Print("RiyCHoCH: order filled but position ticket could not be resolved -- treating as failed.");
      return false;
     }
   t.realTicket        = ticket;
   t.realVolumeOrig    = lotSize;
   t.effectivePartials = ComputeEffectivePartials(lotSize);
   t.tpLadderAttached  = false;
   t.tpAttachAfter     = TimeCurrent() + TpAttachDelaySec;

   if(SelectPos(t.realTicket))
      t.entry = PositionGetDouble(POSITION_PRICE_OPEN);

   Print("RiyCHoCH: opened ticket=", ticket, " vol=", DoubleToString(lotSize,2),
         " entry(real)=", DoubleToString(t.entry,_Digits),
         t.isDDEntry ? " [DD entry]" : (t.beReentryGeneration > 0 ? " [BE re-entry]" : ""));
   return true;
  }

bool OpenRealPosition(Trade &t) { return OpenRealPositionEx(t, LotSize); }

void AttachTpLadder(Trade &t, datetime curTime)
  {
   if(t.tpLadderAttached) return;
   if(TimeCurrent() < t.tpAttachAfter) return;
   if(EnableRealOrders && !SelectPos(t.realTicket)) { t.isClosed = true; return; }

   double slDist = MathAbs(t.entry - t.sl);
   int dir = t.isBull ? 1 : -1;
   double step = (slDist*TpRR)/NumPartials;

   ArrayResize(t.tpPrices, NumPartials);
   ArrayResize(t.tpLineNames, NumPartials);
   for(int i = 1; i <= NumPartials; i++)
     {
      t.tpPrices[i-1] = t.entry + dir*step*i;
      t.tpLineNames[i-1] = DrawTrendLine(curTime, t.tpPrices[i-1], curTime, t.tpPrices[i-1], clrGreen, LineWidth, STYLE_DASH, "tp");
     }

   if(EnableRealOrders)
     {
      double finalTp = t.tpPrices[NumPartials-1];
      if(!trade.PositionModify(t.realTicket, PositionGetDouble(POSITION_SL), finalTp))
         Print("RiyCHoCH: AttachTpLadder PositionModify FAILED ticket=", t.realTicket,
               " retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
     }

   t.tpLadderAttached = true;
  }

void CloseRealPosition(Trade &t)
  {
   if(!EnableRealOrders || t.realTicket == 0) return;
   if(SelectPos(t.realTicket))
     {
      if(!trade.PositionClose(t.realTicket, SlippagePoints))
         Print("RiyCHoCH: CLOSE FAILED ticket=", t.realTicket, " retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
     }
   t.realTicket = 0;
  }

bool PartialCloseRealPosition(Trade &t)
  {
   if(!EnableRealOrders) return true;
   if(!SelectPos(t.realTicket))
     {
      t.isClosed = true;
      return false;
     }

   double curVol = PositionGetDouble(POSITION_VOLUME);
   int remaining = t.effectivePartials - t.partialsHit;
   if(remaining <= 1)
     {
      bool ok = trade.PositionClosePartial(t.realTicket, curVol, SlippagePoints);
      if(!ok) Print("RiyCHoCH: FINAL partial-close FAILED ticket=", t.realTicket, " retcode=", trade.ResultRetcode());
      return ok;
     }

   double lots = MathFloor((t.realVolumeOrig / t.effectivePartials) / g_volStep) * g_volStep;
   if(lots < g_minVol) lots = g_minVol;
   if(lots >= curVol - g_minVol/2.0) lots = curVol;

   bool ok = trade.PositionClosePartial(t.realTicket, lots, SlippagePoints);
   if(!ok) Print("RiyCHoCH: partial-close FAILED ticket=", t.realTicket, " lots=", DoubleToString(lots,2),
                  " curVol=", DoubleToString(curVol,2), " retcode=", trade.ResultRetcode());
   return ok;
  }

bool MoveRealSLToBE(Trade &t)
  {
   if(!EnableRealOrders || !SelectPos(t.realTicket)) return true;
   bool ok = trade.PositionModify(t.realTicket, t.entry, PositionGetDouble(POSITION_TP));
   if(!ok) Print("RiyCHoCH: MoveRealSLToBE FAILED ticket=", t.realTicket, " retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   return ok;
  }
bool RemoveRealTP(Trade &t)
  {
   if(!EnableRealOrders || !SelectPos(t.realTicket)) return true;
   bool ok = trade.PositionModify(t.realTicket, PositionGetDouble(POSITION_SL), 0.0);
   if(!ok) Print("RiyCHoCH: RemoveRealTP FAILED ticket=", t.realTicket, " retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   return ok;
  }
bool UpdateRealSL(Trade &t, double newSl)
  {
   if(!EnableRealOrders || !SelectPos(t.realTicket)) return true;
   bool ok = trade.PositionModify(t.realTicket, newSl, PositionGetDouble(POSITION_TP));
   if(!ok) Print("RiyCHoCH: UpdateRealSL FAILED ticket=", t.realTicket, " retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   return ok;
  }

//================================= BE RE-ENTRY (2nd chance at same entry) ===================================
// When a trade closes via TRUE breakeven (isBEHit), and BE re-entry is enabled and this trade's
// generation hasn't hit the cap, arm a watch at its exact entry price. The instant a candle CLOSES
// back beyond that price in the original favorable direction, a brand new trade is opened at that
// SAME entry price -- using the identical construction pipeline as any other trade (own SL via
// SlPoints, own TP ladder via the normal deferred AttachTpLadder path, real-fill-price correction).

void AddBEWatch(const Trade &t)
  {
   if(!EnableBEReentry) return;
   if(t.beReentryGeneration >= MaxBEReentries) return;
   BEWatch w;
   w.isBull = t.isBull;
   w.entryPrice = t.entry;
   w.tf = t.tf;
   w.generation = t.beReentryGeneration + 1;
   int n = ArraySize(g_beWatches);
   ArrayResize(g_beWatches, n+1);
   g_beWatches[n] = w;
   Print("RiyCHoCH: BE re-entry watch armed at entry=", DoubleToString(w.entryPrice,_Digits),
         " (", w.isBull ? "bull" : "bear", ") generation=", w.generation, "/", MaxBEReentries);
  }

bool BuildBEReentryTrade(bool isBull, double entryPrice, ENUM_TIMEFRAMES tf, int generation, datetime curTime, Trade &outTrade)
  {
   double slDist = SlPoints * PointValue;
   int dir = isBull ? 1 : -1;

   Trade t;
   ZeroMemory(t);
   t.isWaiting = false;
   t.isActive  = false;
   t.isBull    = isBull;
   t.entry     = entryPrice;
   t.sl        = entryPrice - dir*slDist;
   t.tf        = tf;
   t.creationBarTime = curTime;
   g_tradeSeqCounter++;
   t.creationSeq = g_tradeSeqCounter;
   t.isBreakoutEntry = true;
   t.trailExtreme = entryPrice;
   t.effectivePartials = NumPartials;
   t.tpLadderAttached = false;
   t.tpAttachAfter = 0;
   t.ddChainIdx = CreateDDChainForward(isBull, t.sl, entryPrice, tf); // gets its own independent DD chain, same as any fresh trade
   t.beReentryGeneration = generation;

   t.entryLineName = DrawTrendLine(curTime, entryPrice, curTime, entryPrice, clrAqua, LineWidth, STYLE_SOLID, "entry");
   t.slLineName    = DrawTrendLine(curTime, t.sl, curTime, t.sl, clrRed, LineWidth, STYLE_DASH, "sl");

   if(EnableRealOrders)
     {
      bool opened = OpenRealPosition(t);
      t.isActive  = opened;
      t.isWaiting = !opened;
     }
   else t.isActive = true;

   outTrade = t;
   return true;
  }

void ProcessBEWatches(double curClose, datetime curTime, Trade &newTrades[])
  {
   for(int i = ArraySize(g_beWatches)-1; i >= 0; i--)
     {
      BEWatch w = g_beWatches[i];
      int dir = w.isBull ? 1 : -1;
      bool closedBeyond = (curClose - w.entryPrice) * dir > 0;

      if(closedBeyond)
        {
         Print("RiyCHoCH: BE re-entry triggered -- candle closed beyond entry=", DoubleToString(w.entryPrice,_Digits),
               " (", w.isBull ? "bull" : "bear", "), opening 2nd-chance trade.");
         Trade nt;
         if(BuildBEReentryTrade(w.isBull, w.entryPrice, w.tf, w.generation, curTime, nt))
           { int sz = ArraySize(newTrades); ArrayResize(newTrades, sz+1); newTrades[sz] = nt; }

         int sz2 = ArraySize(g_beWatches);
         for(int k = i; k < sz2-1; k++) g_beWatches[k] = g_beWatches[k+1];
         ArrayResize(g_beWatches, sz2-1);
        }
     }
  }

//================================= WORST-ENTRY CUTOFF ===================================

void CheckWorstEntryCutoff()
  {
   if(!EnableWorstEntryCutoff || !EnableRealOrders) return;

   for(int c = 0; c < ArraySize(g_ddChains); c++)
     {
      if(g_ddChains[c].count < 1) continue;

      long newestSeq = -1;
      int newestIdx = -1;
      int openCountInChain = 0;
      for(int i = 0; i < ArraySize(trades); i++)
        {
         if(trades[i].ddChainIdx != c) continue;
         if(trades[i].isClosed || !trades[i].isActive) continue;
         openCountInChain++;
         if(trades[i].creationSeq > newestSeq) { newestSeq = trades[i].creationSeq; newestIdx = i; }
        }
      if(newestIdx < 0) continue;

      if(VerboseChainLogging)
         Print("RiyCHoCH: chain#", c, " open members=", openCountInChain,
               " newestIdx=", newestIdx, " newestSeq=", newestSeq, " (exempt from cutoff)");

      for(int i = 0; i < ArraySize(trades); i++)
        {
         if(trades[i].ddChainIdx != c) continue;
         if(i == newestIdx) continue;
         if(trades[i].isClosed || !trades[i].isActive) continue;
         if(trades[i].realTicket == 0) continue;

         if(!PositionSelectByTicket(trades[i].realTicket))
           {
            trades[i].isClosed = true;
            continue;
           }

         double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

         if(profit >= WorstEntryProfitTrigger)
           {
            if(trade.PositionClose(trades[i].realTicket, SlippagePoints))
              {
               Print("RiyCHoCH: worst-entry cutoff CLOSED chain#", c, " idx=", i, " ticket=", trades[i].realTicket,
                     " profit=", DoubleToString(profit,2));
               trades[i].isClosed = true;
               trades[i].realTicket = 0;
               DeleteObj(trades[i].slLineName); trades[i].slLineName = "";
               DeleteObj(trades[i].entryLineName);
               for(int j = 0; j < ArraySize(trades[i].tpLineNames); j++) DeleteObj(trades[i].tpLineNames[j]);
              }
            else
               Print("RiyCHoCH: worst-entry cutoff CLOSE FAILED chain#", c, " ticket=", trades[i].realTicket,
                     " retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
           }
        }
     }
  }

//================================= DD ENTRIES (drawdown-triggered averaging) ===================================

void CheckDDEntries(Trade &newTrades[], datetime curTime)
  {
   if(!EnableDDEntries) return;
   if(!IsWithinTradingSession()) return;

   for(int i = 0; i < ArraySize(trades); i++)
     {
      Trade t = trades[i];
      if(t.isClosed || !t.isActive || t.ddChainIdx < 0) continue;
      if(t.ddChainIdx >= ArraySize(g_ddChains)) continue;

      DDChain ch = g_ddChains[t.ddChainIdx];
      if(ch.count >= MaxDDEntries) continue;

      double curPrice = t.isBull ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      int dir = t.isBull ? 1 : -1;
      double moveAgainst = (ch.lastEntryPrice - curPrice) * dir;

      if(moveAgainst < DDStepPoints * PointValue) continue;

      Trade dd;
      ZeroMemory(dd);
      dd.isBull = t.isBull;
      dd.entry  = curPrice;
      dd.sl     = ch.sharedSL;
      dd.tf     = t.tf;
      dd.creationBarTime = curTime;
      g_tradeSeqCounter++;
      dd.creationSeq = g_tradeSeqCounter;
      dd.isBreakoutEntry = true;
      dd.isDDEntry = true;
      dd.ddChainIdx = t.ddChainIdx;
      dd.trailExtreme = dd.entry;
      dd.effectivePartials = NumPartials;
      dd.tpLadderAttached = false;
      dd.tpAttachAfter = 0;

      dd.entryLineName = DrawTrendLine(curTime, dd.entry, curTime, dd.entry, clrMagenta, LineWidth, STYLE_SOLID, "ddentry");
      dd.slLineName    = DrawTrendLine(curTime, dd.sl, curTime, dd.sl, clrRed, LineWidth, STYLE_DASH, "sl");

      if(EnableRealOrders)
        {
         bool opened = OpenRealPosition(dd);
         dd.isActive = opened;
        }
      else dd.isActive = true;

      if(dd.isActive)
        {
         int sz = ArraySize(newTrades);
         ArrayResize(newTrades, sz+1);
         newTrades[sz] = dd;

         g_ddChains[t.ddChainIdx].count++;
         g_ddChains[t.ddChainIdx].lastEntryPrice = dd.entry;
         Print("RiyCHoCH: DD entry #", g_ddChains[t.ddChainIdx].count, " added at ", DoubleToString(dd.entry,_Digits),
               " sl(shared)=", DoubleToString(dd.sl,_Digits), " lot=", DoubleToString(LotSize,2));
        }
     }
  }

int CreateDDChainForward(bool isBull, double sharedSL, double entryPrice, ENUM_TIMEFRAMES tf); // fwd decl for BE-reentry builder above

int CreateDDChainForward(bool isBull, double sharedSL, double entryPrice, ENUM_TIMEFRAMES tf)
  {
   DDChain ch;
   ch.isBull = isBull;
   ch.sharedSL = sharedSL;
   ch.lastEntryPrice = entryPrice;
   ch.count = 0;
   ch.tf = tf;
   int n = ArraySize(g_ddChains);
   ArrayResize(g_ddChains, n+1);
   g_ddChains[n] = ch;
   return n;
  }

//================================= TRADE BUILDERS ===================================

bool BuildChochTrade(bool isBull, double structPrice, datetime structTime, datetime curTime, double curClose, const MqlRates &rBars[], Trade &outTrade)
  {
   if(!IsWithinTradingSession()) return false;

   double slDist = SlPoints * PointValue;
   int dir = isBull ? 1 : -1;
   bool is_breakout = (EntryType == ENTRY_BREAKOUT_CANDLE);
   bool is_retest    = (EntryType == ENTRY_BREAKOUT_RETEST);
   bool is_fvg       = (EntryType == ENTRY_CHOCH_FVG);

   double trade_entry = is_breakout ? curClose : structPrice;
   bool valid = true;

   if(is_fvg)
     {
      valid = false;
      int total = ArraySize(rBars);
      for(int j = 0; j <= 10 && j+2 < total; j++)
        {
         if(isBull && rBars[j].low > rBars[j+2].high)   { trade_entry = rBars[j+2].high; valid = true; break; }
         if(!isBull && rBars[j].high < rBars[j+2].low)  { trade_entry = rBars[j+2].low;  valid = true; break; }
        }
     }
   if(!valid) return false;

   Trade t;
   ZeroMemory(t);
   t.isWaiting = !is_breakout;
   t.isActive  = is_breakout;
   t.isBull    = isBull;
   t.entry     = trade_entry;
   t.sl        = trade_entry - dir*slDist;
   t.creationBarTime = curTime;
   g_tradeSeqCounter++;
   t.creationSeq = g_tradeSeqCounter;
   t.isBreakoutEntry = is_breakout;
   t.isFvgEntry = is_fvg;
   t.trailExtreme = trade_entry;
   t.effectivePartials = NumPartials;
   t.tpLadderAttached = false;
   t.tpAttachAfter = 0;
   t.ddChainIdx = CreateDDChainForward(isBull, t.sl, trade_entry, Tf1_Val);
   t.beReentryGeneration = 0;

   if(is_breakout)      t.entryLineName = DrawTrendLine(curTime, trade_entry, curTime, trade_entry, clrYellow, LineWidth, STYLE_SOLID, "entry");
   else if(is_retest)   t.entryLineName = DrawTrendLine(structTime, structPrice, curTime, structPrice, clrOrange, LineWidth, STYLE_SOLID, "retest");
   else                 t.entryLineName = DrawTrendLine(curTime, trade_entry, curTime+PeriodSeconds()*5, trade_entry, clrYellow, LineWidth, STYLE_DOT, "entryfvg");

   t.slLineName = DrawTrendLine(curTime, t.sl, curTime, t.sl, clrRed, LineWidth, STYLE_DASH, "sl");

   if(is_breakout && EnableRealOrders)
     {
      bool opened = OpenRealPosition(t);
      t.isActive  = opened;
      t.isWaiting = !opened;
     }

   outTrade = t;
   return true;
  }

//================================= STRUCTURE PROCESSING (single timeframe, LIVE) ===================================

void ProcessStructure(bool tf_on, ENUM_TIMEFRAMES tf, color col, StructState &st, bool newHtfBar,
                       Trade &newTrades[], bool &bull_ch, bool &bear_ch)
  {
   bull_ch = false; bear_ch = false;
   double liveClose, prevClose; datetime liveTime;
   if(!GetHtfLiveClose(tf, liveClose, prevClose, liveTime)) return;

   if(newHtfBar)
     {
      double p_h, p_l; datetime t_h, t_l;
      if(GetPivot(tf, PivotLength, true, p_h, t_h))
        {
         st.topPrice = p_h; st.topTime = t_h; st.topBroken = false; st.hasTop = true;
         if(tf_on) { DeleteObj(st.lTopName); st.lTopName = DrawTrendLine(t_h, p_h, liveTime, p_h, col, LineWidth, STYLE_SOLID, "top"); }
        }
      if(GetPivot(tf, PivotLength, false, p_l, t_l))
        {
         st.btmPrice = p_l; st.btmTime = t_l; st.btmBroken = false; st.hasBtm = true;
         if(tf_on) { DeleteObj(st.lBtmName); st.lBtmName = DrawTrendLine(t_l, p_l, liveTime, p_l, col, LineWidth, STYLE_SOLID, "btm"); }
        }
     }
   if(!tf_on) return;

   if(st.hasTop && !st.topBroken && st.lTopName == "")
      st.lTopName = DrawTrendLine(st.topTime, st.topPrice, liveTime, st.topPrice, col, LineWidth, STYLE_SOLID, "top");
   if(st.hasBtm && !st.btmBroken && st.lBtmName == "")
      st.lBtmName = DrawTrendLine(st.btmTime, st.btmPrice, liveTime, st.btmPrice, col, LineWidth, STYLE_SOLID, "btm");

   MqlRates rBars[];
   CopyRates(_Symbol, PERIOD_CURRENT, 0, 20, rBars);
   ArraySetAsSeries(rBars, true);

   if(st.hasTop && st.lTopName != "" && !st.topBroken)
     {
      SetLineX2(st.lTopName, liveTime + PeriodSeconds(PERIOD_CURRENT)*5);
      if(liveClose > st.topPrice && prevClose <= st.topPrice)
        {
         SetLineStyle(st.lTopName, STYLE_DASH);
         st.topBroken = true;
         bool is_bos = (st.trend >= 0);
         string tag = is_bos ? "BOS" : ("CHoCH ("+DoubleToString(st.topPrice,_Digits)+")");
         string finalTxt = tag+" "+TfLabel(tf);
         if((is_bos && ShowBOS) || (!is_bos && ShowCH))
            DrawLabel(st.topTime, st.topPrice, finalTxt, is_bos?ColBosBull:ColChBull, true, LblSizeBrk);
         if(!is_bos)
           {
            bull_ch = true;
            Trade nt;
            if(BuildChochTrade(true, st.topPrice, st.topTime, liveTime, liveClose, rBars, nt))
              { nt.tf = tf; int sz=ArraySize(newTrades); ArrayResize(newTrades, sz+1); newTrades[sz]=nt; }
           }
         st.trend = 1;
        }
     }

   if(st.hasBtm && st.lBtmName != "" && !st.btmBroken)
     {
      SetLineX2(st.lBtmName, liveTime + PeriodSeconds(PERIOD_CURRENT)*5);
      if(liveClose < st.btmPrice && prevClose >= st.btmPrice)
        {
         SetLineStyle(st.lBtmName, STYLE_DASH);
         st.btmBroken = true;
         bool is_bos = (st.trend <= 0);
         string tag = is_bos ? "BOS" : "CHoCH";
         string finalTxt = tag+" "+TfLabel(tf);
         if((is_bos && ShowBOS) || (!is_bos && ShowCH))
            DrawLabel(st.btmTime, st.btmPrice, finalTxt, is_bos?ColBosBear:ColChBear, false, LblSizeBrk);
         if(!is_bos)
           {
            bear_ch = true;
            Trade nt;
            if(BuildChochTrade(false, st.btmPrice, st.btmTime, liveTime, liveClose, rBars, nt))
              { nt.tf = tf; int sz=ArraySize(newTrades); ArrayResize(newTrades, sz+1); newTrades[sz]=nt; }
           }
         st.trend = -1;
        }
     }
  }

//================================= TRAILING STOP ===================================

void ActivateTrailing(Trade &t, double curPriceRef)
  {
   if(NumPartials < 2 || t.isTrailing) return;
   int lastIdx = NumPartials-1;
   if(lastIdx < ArraySize(t.tpLineNames)) DeleteObj(t.tpLineNames[lastIdx]);
   RemoveRealTP(t);
   t.isTrailing = true;
   t.trailExtreme = curPriceRef;
   int dir = t.isBull ? 1 : -1;
   double newSl = t.trailExtreme - dir*(TrailPoints*PointValue);
   if((newSl - t.sl)*dir > 0) t.sl = newSl;
   if(t.slLineName != "") SetLinePrice(t.slLineName, t.sl);
   else t.slLineName = DrawTrendLine(TimeCurrent(), t.sl, TimeCurrent(), t.sl, clrRed, LineWidth, STYLE_DASH, "sl");
   UpdateRealSL(t, t.sl);
  }

void ApplyTrailingStop(Trade &t, double curHigh, double curLow)
  {
   if(!t.isTrailing || !t.isActive || t.isClosed) return;
   int dir = t.isBull ? 1 : -1;
   double extremeNow = t.isBull ? curHigh : curLow;
   if((extremeNow - t.trailExtreme)*dir <= 0) return;
   t.trailExtreme = extremeNow;
   double newSl = t.trailExtreme - dir*(TrailPoints*PointValue);
   if((newSl - t.sl)*dir <= 0) return;
   t.sl = newSl;
   if(t.slLineName != "") SetLinePrice(t.slLineName, t.sl);
   UpdateRealSL(t, t.sl);
  }

//================================= TP HIT HANDLER ===================================

void ProcessOneTpHit(Trade &t, datetime curTime, double curHigh, double curLow)
  {
   SetLineColor(t.tpLineNames[t.partialsHit], clrGreen);
   SetLineX2(t.tpLineNames[t.partialsHit], curTime);

   if(ClosePartialsOnTP)
     {
      bool ok = PartialCloseRealPosition(t);
      if(t.isClosed) return;
      if(!ok) return;
     }

   t.partialsHit++;
   if(t.partialsHit == TpSLtoBE)
     {
      t.isSLtoBE = true;
      t.sl = t.entry;
      DeleteObj(t.slLineName);
      t.slLineName = "";
      MoveRealSLToBE(t);
     }
   if(NumPartials >= 2 && t.partialsHit == NumPartials-1 && !t.isTrailing)
      ActivateTrailing(t, t.isBull ? curHigh : curLow);
  }

//================================= UNIFIED TRADE UPDATE (single timeframe) ===================================

void UpdateOneTrade(Trade &t, bool bull_ch1, bool bear_ch1, double curHigh, double curLow, double curClose, datetime curTime)
  {
   int dir = t.isBull ? 1 : -1;
   double extremeFav = t.isBull ? curHigh : curLow;
   double extremeAdv  = t.isBull ? curLow  : curHigh;

   if(CloseOnOppositeCHoCH)
     {
      bool opp = t.isBull ? bear_ch1 : bull_ch1;
      if(opp)
        {
         t.isClosed = true; t.isActive = false;
         CloseRealPosition(t);
         DeleteObj(t.slLineName); t.slLineName = "";
         for(int j = 0; j < ArraySize(t.tpLineNames); j++) if(j >= t.partialsHit) DeleteObj(t.tpLineNames[j]);
         return;
        }
     }

   if(t.isWaiting && !t.isActive && t.isFvgEntry)
      SetLineX2(t.entryLineName, curTime + PeriodSeconds(PERIOD_CURRENT)*5);

   if(t.isWaiting && !t.isActive && curTime > t.creationBarTime && (curClose - t.entry)*dir <= 0)
     {
      if(EnableRealOrders)
        {
         if(OpenRealPosition(t)) { t.isWaiting = false; t.isActive = true; SetLineColor(t.entryLineName, clrYellow); }
        }
      else { t.isWaiting = false; t.isActive = true; SetLineColor(t.entryLineName, clrYellow); }
      return;
     }

   if(!t.isActive) return;

   if(EnableRealOrders && t.realTicket != 0 && !SelectPos(t.realTicket))
     {
      t.isClosed = true;
      DeleteObj(t.slLineName); t.slLineName = "";
      for(int j = 0; j < ArraySize(t.tpLineNames); j++) if(j >= t.partialsHit) DeleteObj(t.tpLineNames[j]);
      return;
     }

   if(t.isBreakoutEntry || t.isFvgEntry) SetLineX2(t.entryLineName, curTime);

   if(!t.tpLadderAttached)
      AttachTpLadder(t, curTime);

   if(t.isTrailing) ApplyTrailingStop(t, curHigh, curLow);

   bool slHit = (extremeAdv - t.sl) * dir <= 0;
   if(slHit)
     {
      t.isClosed = true;
      t.isSLHit = true;
      if(t.isSLtoBE)
        {
         t.isBEHit = true;
         AddBEWatch(t); // NEW: arm the 2nd-chance watch at this trade's entry price
        }
      SetLineX2(t.slLineName, curTime);
      CloseRealPosition(t);
      for(int j = 0; j < ArraySize(t.tpLineNames); j++) if(j >= t.partialsHit) DeleteObj(t.tpLineNames[j]);
      return;
     }

   if(!t.tpLadderAttached) return;

   int cap = MathMin(ArraySize(t.tpPrices), t.effectivePartials);
   while(!t.isTrailing && !t.isClosed && t.partialsHit < cap
         && (extremeFav - t.tpPrices[t.partialsHit]) * dir >= 0)
     {
      ProcessOneTpHit(t, curTime, curHigh, curLow);
     }
  }

void UpdateTrades(bool bull_ch1, bool bear_ch1, double curHigh, double curLow, double curClose, datetime curTime)
  {
   for(int i = ArraySize(trades)-1; i >= 0; i--)
     {
      if(trades[i].isClosed) continue;
      UpdateOneTrade(trades[i], bull_ch1, bear_ch1, curHigh, curLow, curClose, curTime);
     }
  }

//================================= ORDER BLOCKS ===================================

void ProcessOrderBlocks(double curClose, double curClose1, double curHigh, double curLow, datetime curTime)
  {
   double p_h, p_l; datetime t_h, t_l;
   if(GetPivot(PERIOD_CURRENT, PivotLength, true, p_h, t_h))  { g_last_ph = p_h; g_last_ph_time = t_h; g_have_last_ph = true; }
   if(GetPivot(PERIOD_CURRENT, PivotLength, false, p_l, t_l)) { g_last_pl = p_l; g_last_pl_time = t_l; g_have_last_pl = true; }

   MqlRates rBars[];
   CopyRates(_Symbol, PERIOD_CURRENT, 0, 500, rBars);
   ArraySetAsSeries(rBars, true);

   if(g_have_last_ph && ShowOB && curClose > g_last_ph && curClose1 <= g_last_ph && g_have_last_pl)
     {
      int shift = iBarShift(_Symbol, PERIOD_CURRENT, g_last_pl_time, true);
      if(shift >= 0 && shift < ArraySize(rBars))
        {
         string b = DrawBox(g_last_pl_time, rBars[shift].high, curTime, rBars[shift].low, ColorWithAlpha(clrGreen,85));
         OB ob; ob.boxName=b; ob.top=rBars[shift].high; ob.bottom=rBars[shift].low; ob.isBull=true; ob.isBroken=false;
         int n=ArraySize(ob_list); ArrayResize(ob_list,n+1);
         for(int k=n;k>0;k--) ob_list[k]=ob_list[k-1];
         ob_list[0]=ob;
        }
     }
   if(g_have_last_pl && ShowOB && curClose < g_last_pl && curClose1 >= g_last_pl && g_have_last_ph)
     {
      int shift = iBarShift(_Symbol, PERIOD_CURRENT, g_last_ph_time, true);
      if(shift >= 0 && shift < ArraySize(rBars))
        {
         string b = DrawBox(g_last_ph_time, rBars[shift].high, curTime, rBars[shift].low, ColorWithAlpha(clrRed,85));
         OB ob; ob.boxName=b; ob.top=rBars[shift].high; ob.bottom=rBars[shift].low; ob.isBull=false; ob.isBroken=false;
         int n=ArraySize(ob_list); ArrayResize(ob_list,n+1);
         for(int k=n;k>0;k--) ob_list[k]=ob_list[k-1];
         ob_list[0]=ob;
        }
     }
   if(ArraySize(ob_list) > ObLimit) { DeleteObj(ob_list[ArraySize(ob_list)-1].boxName); ArrayResize(ob_list, ArraySize(ob_list)-1); }

   for(int i = ArraySize(ob_list)-1; i >= 0; i--)
     {
      SetBoxRight(ob_list[i].boxName, curTime + PeriodSeconds(PERIOD_CURRENT)*5);
      bool del = false;
      if(ob_list[i].isBull)
        {
         if(curClose < ob_list[i].bottom) { if(ShowBB) { ob_list[i].isBroken=true; SetBoxColor(ob_list[i].boxName, ColorWithAlpha(clrRed,90)); } else del=true; }
         else if(RemoveMit && !ob_list[i].isBroken && curLow <= ob_list[i].top) del = true;
        }
      else
        {
         if(curClose > ob_list[i].top) { if(ShowBB) { ob_list[i].isBroken=true; SetBoxColor(ob_list[i].boxName, ColorWithAlpha(clrGreen,90)); } else del=true; }
         else if(RemoveMit && !ob_list[i].isBroken && curHigh >= ob_list[i].bottom) del = true;
        }
      if(del)
        {
         DeleteObj(ob_list[i].boxName);
         int sz=ArraySize(ob_list);
         for(int k=i;k<sz-1;k++) ob_list[k]=ob_list[k+1];
         ArrayResize(ob_list, sz-1);
        }
     }
  }

//================================= DASHBOARD ===================================

void UpdateDashboard()
  {
   if(!ShowDash) return;
   int exec_=0, act=0, tp1=0, full=0, sl=0, be=0, dd=0, ber=0;
   for(int i=0;i<ArraySize(trades);i++)
     {
      Trade t = trades[i];
      if(t.isActive||t.isClosed) exec_++;
      if(t.isActive) act++;
      if(t.partialsHit>=1) tp1++;
      if(t.partialsHit==NumPartials) full++;
      if(t.isSLHit) sl++;
      if(t.isBEHit) be++;
      if(t.isDDEntry) dd++;
      if(t.beReentryGeneration>0) ber++;
     }
   int corner;
   switch(DashPos)
     {
      case DASH_TOP_LEFT: corner=CORNER_LEFT_UPPER; break;
      case DASH_BOTTOM_RIGHT: corner=CORNER_RIGHT_LOWER; break;
      case DASH_BOTTOM_LEFT: corner=CORNER_LEFT_LOWER; break;
      default: corner=CORNER_RIGHT_UPPER;
     }
   string sessionStatus = IsWithinTradingSession() ? "OPEN" : "CLOSED";
   string rows[10][2] = { {"Metrics","Value"}, {"Session",sessionStatus}, {"Total Executed",IntegerToString(exec_)},
     {"Currently Active",IntegerToString(act)}, {"Hit at least TP1",IntegerToString(tp1)},
     {"Full TP Hit",IntegerToString(full)}, {"SL Hit",IntegerToString(sl)},
     {"BE Hit",IntegerToString(be)}, {"DD Entries",IntegerToString(dd)}, {"BE Re-Entries",IntegerToString(ber)} };
   color colA[10] = {clrWhite, (IsWithinTradingSession()?clrLime:clrRed), clrWhite,clrWhite,clrLime,clrLime,clrRed,clrYellow,clrMagenta,clrAqua};
   for(int r=0;r<10;r++)
      for(int c=0;c<2;c++)
        {
         string name = g_dashName+IntegerToString(r)+"_"+IntegerToString(c);
         if(ObjectFind(0,name)<0)
           {
            ObjectCreate(0,name,OBJ_LABEL,0,0,0);
            ObjectSetInteger(0,name,OBJPROP_CORNER,corner);
            ObjectSetInteger(0,name,OBJPROP_XDISTANCE,10+c*110);
            ObjectSetInteger(0,name,OBJPROP_YDISTANCE,10+r*18);
            ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
            ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
           }
         ObjectSetString(0,name,OBJPROP_TEXT,rows[r][c]);
         ObjectSetInteger(0,name,OBJPROP_COLOR, r==0?clrWhite:colA[r]);
        }
  }

//================================= NEW-BAR DETECTION ===================================

bool IsNewBar(ENUM_TIMEFRAMES tf, datetime &lastStored)
  {
   datetime t = (datetime)SeriesInfoInteger(_Symbol, tf, SERIES_LASTBAR_DATE);
   if(t != lastStored) { lastStored = t; return true; }
   return false;
  }

//================================= EXPERT LIFECYCLE ===================================

int OnInit()
  {
   PointValue = _Point;
   g_volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   g_minVol  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(g_volStep <= 0) g_volStep = 0.01;
   if(g_minVol  <= 0) g_minVol  = 0.01;

   ComputeEffectivePartials(LotSize);

   ArrayResize(trades,0);
   ArrayResize(ob_list,0);
   ArrayResize(g_ddChains,0);
   ArrayResize(g_beWatches,0);
   g_tradeSeqCounter = 0;
   g_dashName = "RiyDash_"+IntegerToString((int)MagicNumber)+"_";

   InitializeStructureFromHistory(st1, Tf1_Val, Tf1_On, Tf1_Col, StructureLookbackBars);

   Print("RiyCHoCH: session filter ", EnableSessionFilter ? "ENABLED" : "disabled",
         " window=", SessionStartHour, ":", SessionStartMinute, " - ", SessionEndHour, ":", SessionEndMinute,
         " (server time) -- currently ", IsWithinTradingSession() ? "OPEN" : "CLOSED");

   EventSetTimer(1);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   string prefixes[] = {"lbl","top","btm","entry","ddentry","retest","sl","tp","ob"};
   for(int i=0;i<ArraySize(prefixes);i++) ObjectsDeleteAll(0, prefixes[i]);
   ObjectsDeleteAll(0, g_dashName);
  }

void OnTimer() { RunLogic(); }
void OnTick()  { RunLogic(); }

void RunLogic()
  {
   MqlRates curBar[];
   if(CopyRates(_Symbol, PERIOD_CURRENT, 0, 2, curBar) < 2) return;
   double curClose=curBar[1].close, curClose1=curBar[0].close, curHigh=curBar[1].high, curLow=curBar[1].low;
   datetime curTime = curBar[1].time;

   Trade nt1[], ddNew[], beNew[];
   bool bull1=false, bear1=false;

   bool isNew1 = IsNewBar(Tf1_Val, g_lastBarTf1);
   bool isNewChart = IsNewBar(PERIOD_CURRENT, g_lastBarChart);

   ProcessStructure(Tf1_On, Tf1_Val, Tf1_Col, st1, isNew1, nt1, bull1, bear1);

   for(int i=0;i<ArraySize(nt1);i++) { int n=ArraySize(trades); ArrayResize(trades,n+1); trades[n]=nt1[i]; }

   UpdateTrades(bull1, bear1, curHigh, curLow, curClose, curTime);

   CheckDDEntries(ddNew, curTime);
   for(int i=0;i<ArraySize(ddNew);i++) { int n=ArraySize(trades); ArrayResize(trades,n+1); trades[n]=ddNew[i]; }

   ProcessBEWatches(curClose, curTime, beNew);
   for(int i=0;i<ArraySize(beNew);i++) { int n=ArraySize(trades); ArrayResize(trades,n+1); trades[n]=beNew[i]; }

   CheckWorstEntryCutoff();

   if(isNewChart)
      ProcessOrderBlocks(curClose, curClose1, curHigh, curLow, curTime);

   UpdateDashboard();
   ChartRedraw(0);
  }
//+------------------------------------------------------------------+