//+------------------------------------------------------------------+
//|                                                HAE_Symbol.mqh    |
//|  HMA Active EA  v0.1                                              |
//|  File 2/10 - symbol cache, price / volume maths, market checks.   |
//|                                                                   |
//|  Static symbol properties are read ONCE (HaeSymInit) and the      |
//|  broker levels (stops / freeze) are refreshed once per new bar    |
//|  (HaeSymRefresh), so per-tick code never calls SymbolInfo* for    |
//|  them.                                                            |
//+------------------------------------------------------------------+
#ifndef HAE_SYMBOL_MQH
#define HAE_SYMBOL_MQH

#include "HAE_Defines.mqh"

struct SHaeSym
{
   string name;
   double point;
   int    digits;
   double tickSize;
   double volMin;
   double volMax;
   double volStep;
   int    volDigits;
   double stopsDist;    // SYMBOL_TRADE_STOPS_LEVEL in price units
   double freezeDist;   // SYMBOL_TRADE_FREEZE_LEVEL in price units
};

SHaeSym Sym;

//+------------------------------------------------------------------+
//| Init / refresh                                                    |
//+------------------------------------------------------------------+
int HaeCalcVolDigits(double step)
{
   int d = 0;
   while(d < 8 && MathAbs(step - MathRound(step)) > 1e-9) { step *= 10.0; d++; }
   return d;
}

void HaeSymRefresh()
{
   Sym.stopsDist  = (double)SymbolInfoInteger(Sym.name, SYMBOL_TRADE_STOPS_LEVEL)  * Sym.point;
   Sym.freezeDist = (double)SymbolInfoInteger(Sym.name, SYMBOL_TRADE_FREEZE_LEVEL) * Sym.point;
}

bool HaeSymInit()
{
   Sym.name     = _Symbol;
   Sym.point    = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   Sym.digits   = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   Sym.tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   Sym.volMin   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   Sym.volMax   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   Sym.volStep  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(Sym.point <= 0.0) Sym.point = _Point;
   if(Sym.point <= 0.0) return false;
   if(Sym.volStep <= 0.0) Sym.volStep = 0.01;
   if(Sym.volMin  <= 0.0) Sym.volMin  = Sym.volStep;
   if(Sym.volMax  <= 0.0) Sym.volMax  = 1000.0;
   Sym.volDigits = HaeCalcVolDigits(Sym.volStep);

   HaeSymRefresh();
   return true;
}

//+------------------------------------------------------------------+
//| Prices                                                            |
//+------------------------------------------------------------------+
double HaeBid() { return SymbolInfoDouble(Sym.name, SYMBOL_BID); }
double HaeAsk() { return SymbolInfoDouble(Sym.name, SYMBOL_ASK); }

double HaePts(const double points)          { return points * Sym.point; }         // points -> price distance
double HaeToPts(const double priceDist)     { return priceDist / Sym.point; }      // price distance -> points

double HaeNormPrice(const double p)
{
   if(Sym.tickSize <= 0.0) return NormalizeDouble(p, Sym.digits);
   return NormalizeDouble(MathRound(p / Sym.tickSize) * Sym.tickSize, Sym.digits);
}

string HaePx(const double p) { return DoubleToString(p, Sym.digits); }

//+------------------------------------------------------------------+
//| Volume                                                            |
//+------------------------------------------------------------------+
// Rounds DOWN to the volume step. Returns 0 when below min lot.
// Values above max lot are clamped to max lot.
double HaeRoundVolDown(const double v)
{
   if(v <= 0.0) return 0.0;
   double r = NormalizeDouble(MathFloor(v / Sym.volStep + 1e-9) * Sym.volStep, Sym.volDigits);
   if(r > Sym.volMax) r = NormalizeDouble(MathFloor(Sym.volMax / Sym.volStep + 1e-9) * Sym.volStep, Sym.volDigits);
   if(r < Sym.volMin - 1e-12) return 0.0;
   return r;
}

//+------------------------------------------------------------------+
//| Broker levels                                                     |
//+------------------------------------------------------------------+
// True when `level` is inside the freeze zone (cannot be modified now)
bool HaeFrozen(const double level, const double bid, const double ask)
{
   if(Sym.freezeDist <= 0.0 || level <= 0.0) return false;
   return (MathAbs(level - bid) <= Sym.freezeDist || MathAbs(level - ask) <= Sym.freezeDist);
}

// True when a stop for a position of this side is far enough from the market
bool HaeStopDistOk(const bool isBuy, const double stop, const double bid, const double ask)
{
   if(stop <= 0.0) return true;
   return isBuy ? (bid - stop > Sym.stopsDist) : (stop - ask > Sym.stopsDist);
}

// True when a take-profit for a position of this side is far enough from the market
bool HaeTakeDistOk(const bool isBuy, const double take, const double bid, const double ask)
{
   if(take <= 0.0) return true;
   return isBuy ? (take - bid > Sym.stopsDist) : (ask - take > Sym.stopsDist);
}

//+------------------------------------------------------------------+
//| Market checks                                                     |
//+------------------------------------------------------------------+
double HaeSpreadPts(const double bid, const double ask)
{
   return HaeToPts(ask - bid);
}

bool HaeSpreadOk(const double bid, const double ask)
{
   if(Cfg.maxSpreadPts <= 0) return true;
   return (HaeSpreadPts(bid, ask) <= (double)Cfg.maxSpreadPts + 1e-9);
}

// Free-margin check before opening. If the terminal cannot evaluate it, do not block.
bool HaeMarginOk(const bool isBuy, const double vol, const double price, const string what)
{
   double margin = 0.0;
   if(!OrderCalcMargin(isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, Sym.name, vol, price, margin)) return true;
   const double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(margin > freeMargin) {
      PrintFormat("%s skipped: required margin %.2f > free margin %.2f.", what, margin, freeMargin);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Lot sizing                                                        |
//+------------------------------------------------------------------+
// Money lost by 1.0 lot moving from `entry` to `sl` (positive number), 0 if unknown
double HaeLossPerLot(const bool isBuy, const double entry, const double sl)
{
   if(entry <= 0.0 || sl <= 0.0) return 0.0;
   double pnl = 0.0;
   if(!OrderCalcProfit(isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, Sym.name, 1.0, entry, sl, pnl)) return 0.0;
   return MathAbs(pnl);
}

// Volume for the configured lot mode. Returns 0 when the trade must be skipped.
double HaeCalcVolume(const bool isBuy, const double entry, const double sl)
{
   if(Cfg.lotMode == LOTM_FIXED) {
      const double v = HaeRoundVolDown(Cfg.lot);
      if(v <= 0.0) PrintFormat("Lot %.2f is below the broker minimum %.2f.", Cfg.lot, Sym.volMin);
      return v;
   }

   const double perLot = HaeLossPerLot(isBuy, entry, sl);
   if(perLot <= 0.0) {
      Print("Risk sizing: cannot evaluate SL loss (no SL or no tick value) - trade skipped.");
      return 0.0;
   }
   const double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * Cfg.riskPct / 100.0;
   const double v = HaeRoundVolDown(riskMoney / perLot);
   if(v <= 0.0)
      PrintFormat("Risk sizing: %.2f risk / %.2f per lot = below min lot %.2f - trade skipped.",
                  riskMoney, perLot, Sym.volMin);
   return v;
}

//+------------------------------------------------------------------+
//| Ownership                                                         |
//+------------------------------------------------------------------+
bool HaeOwnedPositionSelected()
{
   return (PositionGetString(POSITION_SYMBOL) == Sym.name && PositionGetInteger(POSITION_MAGIC) == Cfg.magic);
}

bool HaeSelectedIsBuy()
{
   return ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
}

#endif // HAE_SYMBOL_MQH
//+------------------------------------------------------------------+
