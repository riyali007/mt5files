#property copyright "Riy"
#property version   "1.00"

#include <Trade/Trade.mqh>
#include <RiyPatterns.mqh>

input ENUM_TIMEFRAMES InpSignalTF=PERIOD_H4;
input int InpRSILength=14;
input double InpDojiPoints=100.0;
input double InpMinBody1Points=100.0;
input double InpMinBody2Points=200.0;
input double InpRiskPercent=1.0;
input double InpMaxExposurePercent=50.0;
input bool InpUseStopLoss=true;
input double InpStopLossPercent=2.0;
input bool InpUseTakeProfit=true;
input double InpTakeProfitPercent=4.0;
input bool InpLongOnly=false;
input bool InpShortOnly=false;
input bool InpCloseReverse=true;
input long InpMagic=26072801;
input int InpMaxSpreadPoints=0;
input int InpDeviationPoints=20;

CTrade trade;
CRiyPatterns patterns;
int rsiHandle=INVALID_HANDLE;
datetime lastClosedSignalBar=0;

bool ToRiyBar(const MqlRates &r,RiyBar &b)
{
   b.open=r.open; b.high=r.high; b.low=r.low; b.close=r.close;
   return true;
}

double NormalizeVolume(double lots)
{
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   lots=MathFloor(lots/step)*step;
   lots=MathMax(minLot,MathMin(maxLot,lots));
   return NormalizeDouble(lots,2);
}

double CalculateLots(const double entry,const double sl)
{
   if(sl<=0.0 || entry<=0.0) return 0.0;
   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double tickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickSize<=0.0 || tickValue<=0.0) return 0.0;
   double riskMoney=AccountInfoDouble(ACCOUNT_EQUITY)*InpRiskPercent/100.0;
   double lossPerLot=MathAbs(entry-sl)/tickSize*tickValue;
   if(lossPerLot<=0.0) return 0.0;
   double lots=riskMoney/lossPerLot;
   double contract=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE);
   double maxLots=(AccountInfoDouble(ACCOUNT_EQUITY)*InpMaxExposurePercent/100.0)/(entry*contract);
   if(maxLots>0.0) lots=MathMin(lots,maxLots);
   return NormalizeVolume(lots);
}

bool HasOurPosition(ENUM_POSITION_TYPE &type)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol && PositionGetInteger(POSITION_MAGIC)==InpMagic)
      {
         type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         return true;
      }
   }
   return false;
}

bool StopsValid(const double entry,const double sl,const double tp)
{
   int minStops=(int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   double minDist=minStops*_Point;
   if(sl>0.0 && MathAbs(entry-sl)<minDist) return false;
   if(tp>0.0 && MathAbs(entry-tp)<minDist) return false;
   return true;
}

void ProcessSignal()
{
   MqlRates rates[]; double rsi[];
   ArraySetAsSeries(rates,true); ArraySetAsSeries(rsi,true);
   if(CopyRates(_Symbol,InpSignalTF,1,5,rates)<5) return;
   if(CopyBuffer(rsiHandle,0,1,5,rsi)<5) return;
   if(rates[0].time==lastClosedSignalBar) return;
   lastClosedSignalBar=rates[0].time;

   RiyBar b0,b1,b2,b3;
   ToRiyBar(rates[0],b0); ToRiyBar(rates[1],b1); ToRiyBar(rates[2],b2); ToRiyBar(rates[3],b3);
   RiySignal s=patterns.Detect(b0,b1,b2,b3,rsi[0],rsi[1]);
   if(s==RIY_NONE) return;
   bool wantBuy=(s>0);
   if((wantBuy && InpShortOnly) || (!wantBuy && InpLongOnly)) return;

   if(InpMaxSpreadPoints>0)
   {
      MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;
      if((tick.ask-tick.bid)/_Point>InpMaxSpreadPoints) return;
   }

   ENUM_POSITION_TYPE ptype;
   if(HasOurPosition(ptype))
   {
      bool same=(wantBuy && ptype==POSITION_TYPE_BUY) || (!wantBuy && ptype==POSITION_TYPE_SELL);
      if(same || !InpCloseReverse) return;
      if(!trade.PositionClose(_Symbol)) { Print("Reverse close failed: ",trade.ResultRetcodeDescription()); return; }
   }

   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;
   double entry=wantBuy ? tick.ask : tick.bid;
   double sl=0.0,tp=0.0;
   if(InpUseStopLoss) sl=wantBuy ? rates[1].low*(1.0-InpStopLossPercent/100.0) : rates[1].high*(1.0+InpStopLossPercent/100.0);
   if(InpUseTakeProfit) tp=wantBuy ? entry*(1.0+InpTakeProfitPercent/100.0) : entry*(1.0-InpTakeProfitPercent/100.0);
   sl=sl>0.0 ? NormalizeDouble(sl,_Digits) : 0.0;
   tp=tp>0.0 ? NormalizeDouble(tp,_Digits) : 0.0;
   if(!StopsValid(entry,sl,tp)) { Print("Signal ignored: SL/TP violates broker stops level"); return; }
   double lots=CalculateLots(entry,sl);
   if(lots<=0.0) { Print("Signal ignored: volume calculation returned zero"); return; }

   string comment=StringFormat("RiyPattern %d RSI %.1f",(int)s,rsi[0]);
   bool ok=wantBuy ? trade.Buy(lots,_Symbol,0.0,sl,tp,comment) : trade.Sell(lots,_Symbol,0.0,sl,tp,comment);
   if(!ok) Print("Trade failed: ",trade.ResultRetcode()," ",trade.ResultRetcodeDescription());
}

int OnInit()
{
   if(InpLongOnly && InpShortOnly) return INIT_PARAMETERS_INCORRECT;
   patterns.Configure(_Point,InpDojiPoints,InpMinBody1Points,InpMinBody2Points);
   rsiHandle=iRSI(_Symbol,InpSignalTF,InpRSILength,PRICE_CLOSE);
   if(rsiHandle==INVALID_HANDLE) return INIT_FAILED;
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(rsiHandle!=INVALID_HANDLE) IndicatorRelease(rsiHandle);
}

void OnTick()
{
   ProcessSignal();
}
