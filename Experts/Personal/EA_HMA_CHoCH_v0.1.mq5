//+------------------------------------------------------------------+
//| EA_HMA_CHoCH_v1.4.mq5                                            |
//| HMA + CHoCH, market structure (body/wick), choppy-market filter, |
//| limit order placed right after the CHoCH body candle closes,     |
//| DD basket, basket break-even, survival mode, trading session,    |
//| cooldown after stop loss, black theme, input audit + diagnostics.|
//| Requires compiled HMA.ex5 in MQL5\Indicators                     |
//+------------------------------------------------------------------+
#property version   "1.40"
#property strict
#include <Trade\Trade.mqh>

enum ENUM_RECOVERY_ACTION
{
   RECOVERY_CLOSE_ENTRY,          // Close the entry
   RECOVERY_MOVE_SL_TO_ENTRY      // Move that entry's stop loss to its entry (+offset)
};

enum ENUM_RETEST_ENTRY_MODE
{
   ENTRY_LIMIT_ORDER_AT_CHOCH_LEVEL,     // Pending limit order at the exact CHoCH level (placed when the CHoCH candle closes)
   ENTRY_AFTER_REJECTION_CANDLE_CLOSE,   // Enter at market after a retest candle closes back on the break side
   ENTRY_ON_FIRST_TOUCH                  // Enter at market on the first tick inside the retest zone
};

enum ENUM_STRUCTURE_BREAK_MODE
{
   STRUCTURE_BREAK_BY_BODY_CLOSE,   // Break counts when a candle closes beyond the level
   STRUCTURE_BREAK_BY_WICK          // Break counts when a candle's high/low goes beyond the level
};

enum ENUM_SESSION_TIME_REFERENCE
{
   SESSION_TIME_BROKER_SERVER,   // Broker server time (also used by the Strategy Tester)
   SESSION_TIME_LOCAL_PC,        // Local computer time
   SESSION_TIME_GMT              // GMT
};

enum ENUM_CHOP_FILTER_MODE
{
   CHOP_FILTER_OFF,                    // No choppy-market filter
   CHOP_FILTER_REQUIRE_BOS,            // Trend must have at least N BoS before its reversal CHoCH is traded
   CHOP_FILTER_REQUIRE_MIN_DISTANCE,   // CHoCH level must be far enough from the previous CHoCH level
   CHOP_FILTER_REQUIRE_BOTH            // Both conditions must pass
};

input group "HMA indicator"
input string InpHmaIndicatorFileName = "HMA";
input int    InpHmaPeriodBars        = 14;
input ENUM_APPLIED_PRICE InpHmaAppliedPrice = PRICE_CLOSE;
input color  InpHmaLineColor         = clrDodgerBlue;

input group "First CHoCH detection (HMA based)"
input int    InpChochLookbackBars              = 20;   // candles scanned for the leg and its swing
input int    InpSwingConfirmBarsEachSide       = 2;    // bars each side that confirm the CHoCH swing
input int    InpMaxBarsFromHmaCrossToBreak     = 5;    // HMA cross must be within this many bars of the break (0 = same candle)

input group "Market structure (second CHoCH onward)"
input bool   InpEnableMarketStructure          = true;
input ENUM_STRUCTURE_BREAK_MODE InpStructureBreakMode = STRUCTURE_BREAK_BY_BODY_CLOSE;
input int    InpStructureSwingBarsEachSide     = 2;    // fractal strength for structure swings
input double InpLocationThresholdPercent       = 50;   // bearish CHoCH valid if price >= this % of range; bullish if <= 100 - this %
input int    InpStructureMaxBars               = 300;  // range cap and stale-structure reset
input bool   InpRequireHmaSideForStructureChoch = true; // valid CHoCH must close on the correct side of the HMA

input group "Choppy market filter (second CHoCH onward)"
input ENUM_CHOP_FILTER_MODE InpChopFilterMode              = CHOP_FILTER_REQUIRE_BOS;
input int    InpChopMinBosCount                            = 1;     // used by REQUIRE_BOS / REQUIRE_BOTH
input double InpChopMinDistanceFromPreviousChochPoints     = 1400;  // used by REQUIRE_MIN_DISTANCE / REQUIRE_BOTH

input group "Entry mode"
input ENUM_RETEST_ENTRY_MODE InpRetestEntryMode = ENTRY_LIMIT_ORDER_AT_CHOCH_LEVEL;
input int    InpRetestWindowBars                = 3;   // candles after the CHoCH candle during which the setup stays alive
input bool   InpTakeEntryWhenCloseBackThroughLevel = true; // body-close CHoCH: a close back through the level does not cancel the setup

input group "Alternative entry modes (IGNORED in limit-order mode)"
input double InpRetestApproachDistancePoints    = 0;   // rejection / first-touch: distance from the level that counts as a retest
input bool   InpRequireRejectionCandleDirection = false; // rejection mode only: buy candle must close above its open (sell: below)

input group "Position management"
input double InpOrderLotSize                          = 0.5;
input double InpStopLossDistanceFromEntryPoints       = 700;   // main entry only; DD entries share this SL price
input double InpFinalPartialDistanceFromEntryPoints   = 1400;  // distance of the last partial (no server TP is set)
input int    InpPartialCloseCount                     = 7;
input double InpPartialClosePercentOfRemainingLots    = 10.0;
input double InpTrailingStopDistanceBehindPricePoints = 800;
input double InpTrailingStopMinPriceAdvancePoints     = 1000; // price must advance this far before SL moves again

input group "Basket break-even"
input double InpBasketBreakEvenActivationProfitPoints      = 200; // best position's profit that triggers it
input double InpBasketBreakEvenOffsetBeyondBestEntryPoints = 0;   // SL = best entry +/- this offset

input group "Drawdown (DD) entries"
input bool   InpEnableDrawdownEntries                 = true;
input double InpDrawdownEntrySpacingPoints            = 150;  // adverse move from last entry that adds a DD entry
input int    InpMaxDrawdownEntriesPerBasket           = 3;
input double InpRecoveryTriggerProfitPoints           = 100;  // profit on a DD-marked entry that triggers recovery
input ENUM_RECOVERY_ACTION InpRecoveryAction          = RECOVERY_CLOSE_ENTRY;
input double InpRecoveryStopOffsetBeyondEntryPoints   = 0;    // only used when the recovery action moves the SL

input group "Survival mode"
input bool   InpEnableSurvivalMode                          = true;
input int    InpSurvivalTriggerDrawdownEntryNumber          = 2;   // survival starts when this DD entry opens
input double InpSurvivalCloseOffsetBeyondAverageEntryPoints = 0;   // close all at average entry +/- this offset

input group "Cooldown after stop loss"
input bool   InpEnableCooldownAfterStopLoss         = true;
input int    InpCooldownMinutes                     = 15;
input bool   InpCooldownOnlyWhenStopLossHitAtLoss   = true;   // ignore break-even / trailing stops that closed in profit
input bool   InpCooldownBlocksBothDirections        = true;   // false: only the stopped direction is blocked

input group "Trading session"
input bool   InpUseTradingSession               = true;
input ENUM_SESSION_TIME_REFERENCE InpSessionTimeReference = SESSION_TIME_BROKER_SERVER;
input int    InpSessionStartHour                = 2;
input int    InpSessionStartMinute              = 0;
input int    InpSessionEndHour                  = 22;
input int    InpSessionEndMinute                = 0;
input bool   InpCloseAllPositionsAtSessionEnd   = false;

input group "Execution and diagnostics"
input int    InpMaxSlippagePoints   = 30;     // market orders only (pending orders ignore it)
input long   InpMagicNumber         = 770011;
input bool   InpLogSetupDiagnostics = true;   // log why a CHoCH candidate was not armed / why a limit was not placed

input group "Chart theme"
input bool   InpApplyBlackTheme   = true;
input color  InpBullCandleColor   = C'38,166,154';   // teal
input color  InpBearCandleColor   = C'239,83,80';    // red

struct SSignal
{
   bool     isActive;
   bool     entryConfirmed;     // rejection mode only
   bool     bodyCloseBreak;     // true when the CHoCH was confirmed by a candle body close
   double   levelPrice;
   datetime levelBarTime;
   datetime breakBarTime;
   int      barsAlive;
   string   lineName;
   string   labelName;
   // pending limit order (ENTRY_LIMIT_ORDER_AT_CHOCH_LEVEL)
   ulong    pendingOrderTicket;
   string   pendingBasketName;
   datetime limitPlacedTime;
   datetime lastLimitAttemptTime;
   string   lastLimitStatus;
   int      limitFailures;
   bool     limitGivenUp;
};

struct SBasket
{
   bool   isActive;
   string basketName;
   double lastEntryPrice;
   double sharedStopLossPrice;
   int    drawdownEntriesOpened;
   bool   breakEvenApplied;
   bool   survivalMode;
};

struct SPositionState
{
   ulong  ticket;
   bool   isBuy;
   int    partialsDone;
   bool   trailingActive;
   double trailReferencePrice;
   bool   markedAsDrawdownEntry;
   bool   recoveryHandled;
};

CTrade          tradeExecutor;
int             hmaIndicatorHandle = INVALID_HANDLE;
SSignal         buySignal, sellSignal;
SBasket         buyBasket, sellBasket;
SPositionState  positionStates[];
datetime        lastBarOpenTime = 0;
datetime        lastOrderAttemptTime = 0;
datetime        buyCooldownUntilTime = 0;
datetime        sellCooldownUntilTime = 0;
double          pointSize;

// Market structure state
int      structureTrend = 0;            // +1 uptrend, -1 downtrend, 0 unknown
datetime structureStartTime = 0;        // time of the first CHoCH
datetime trendStartTime = 0;            // time of the CHoCH that started the current trend
double   structureExtremePrice = 0;     // uptrend: highest swing high; downtrend: lowest swing low
datetime structureExtremeTime = 0;
datetime lastBosExtremeTime = 0;        // extreme already used for a BoS
double   structureOriginPrice = 0;      // protected level used until a swing forms
double   previousChochLevelPrice = 0;   // level of the CHoCH that started the current trend
int      bosCount = 0;                  // BoS marked in the current trend

const string OBJECT_PREFIX = "CHOCH_";

//+------------------------------------------------------------------+
void ApplyBlackChartTheme()
{
   long chartId = ChartID();
   ChartSetInteger(chartId, CHART_MODE, CHART_CANDLES);
   ChartSetInteger(chartId, CHART_COLOR_BACKGROUND,   C'14,14,14');
   ChartSetInteger(chartId, CHART_COLOR_FOREGROUND,   C'200,200,200');
   ChartSetInteger(chartId, CHART_COLOR_GRID,         C'28,28,28');
   ChartSetInteger(chartId, CHART_COLOR_CHART_UP,     InpBullCandleColor);
   ChartSetInteger(chartId, CHART_COLOR_CHART_DOWN,   InpBearCandleColor);
   ChartSetInteger(chartId, CHART_COLOR_CANDLE_BULL,  InpBullCandleColor);
   ChartSetInteger(chartId, CHART_COLOR_CANDLE_BEAR,  InpBearCandleColor);
   ChartSetInteger(chartId, CHART_COLOR_CHART_LINE,   C'200,200,200');
   ChartSetInteger(chartId, CHART_COLOR_VOLUME,       C'90,90,90');
   ChartSetInteger(chartId, CHART_COLOR_BID,          C'90,90,90');
   ChartSetInteger(chartId, CHART_COLOR_ASK,          C'90,90,90');
   ChartSetInteger(chartId, CHART_COLOR_LAST,         C'90,90,90');
   ChartSetInteger(chartId, CHART_COLOR_STOP_LEVEL,   C'120,40,40');
   ChartSetInteger(chartId, CHART_SHOW_GRID,          true);
   ChartSetInteger(chartId, CHART_SHOW_VOLUMES,       false);
   ChartRedraw(chartId);
}

//+------------------------------------------------------------------+
bool IsInsideTradingSession()
{
   if(!InpUseTradingSession) return true;

   datetime referenceTime = TimeCurrent();
   if(InpSessionTimeReference == SESSION_TIME_LOCAL_PC) referenceTime = TimeLocal();
   if(InpSessionTimeReference == SESSION_TIME_GMT)      referenceTime = TimeGMT();

   MqlDateTime timeParts;
   TimeToStruct(referenceTime, timeParts);
   int minuteOfDay  = timeParts.hour * 60 + timeParts.min;
   int startMinute  = InpSessionStartHour * 60 + InpSessionStartMinute;
   int endMinute    = InpSessionEndHour * 60 + InpSessionEndMinute;

   if(startMinute == endMinute) return true;                             // treated as 24h
   if(startMinute < endMinute)  return (minuteOfDay >= startMinute && minuteOfDay < endMinute);
   return (minuteOfDay >= startMinute || minuteOfDay < endMinute);      // window crosses midnight
}

bool IsInCooldown(bool isBuySide)
{
   if(!InpEnableCooldownAfterStopLoss) return false;
   return TimeCurrent() < (isBuySide ? buyCooldownUntilTime : sellCooldownUntilTime);
}

bool IsBasketInSurvivalMode(bool isBuySide)
{
   return isBuySide ? (buyBasket.isActive && buyBasket.survivalMode)
                    : (sellBasket.isActive && sellBasket.survivalMode);
}

//+------------------------------------------------------------------+
// Prints which inputs are inactive with the current settings and warns about
// combinations that can never work.
void PrintInputAudit()
{
   Print("================ INPUT AUDIT ================");
   PrintFormat("Entry mode: %s", EnumToString(InpRetestEntryMode));

   if(InpRetestEntryMode == ENTRY_LIMIT_ORDER_AT_CHOCH_LEVEL)
      Print("Ignored in limit-order mode: InpRetestApproachDistancePoints, InpRequireRejectionCandleDirection.");
   else if(InpRetestEntryMode == ENTRY_ON_FIRST_TOUCH)
      Print("Ignored in first-touch mode: InpRequireRejectionCandleDirection.");

   if(!InpEnableMarketStructure)
      Print("Market structure is OFF: structure, location and choppy-filter inputs are ignored (every CHoCH comes from the HMA rules).");
   else if(InpChopFilterMode == CHOP_FILTER_OFF)
      Print("Choppy filter is OFF: InpChopMinBosCount and InpChopMinDistanceFromPreviousChochPoints are ignored.");
   else if(InpChopFilterMode == CHOP_FILTER_REQUIRE_BOS)
      Print("Choppy filter = REQUIRE_BOS: InpChopMinDistanceFromPreviousChochPoints is ignored.");
   else if(InpChopFilterMode == CHOP_FILTER_REQUIRE_MIN_DISTANCE)
      Print("Choppy filter = REQUIRE_MIN_DISTANCE: InpChopMinBosCount is ignored.");

   if(!InpEnableDrawdownEntries)
      Print("DD entries are OFF: DD spacing, max DD entries, recovery and survival inputs are ignored.");
   else
   {
      if(InpRecoveryAction == RECOVERY_CLOSE_ENTRY)
         Print("InpRecoveryStopOffsetBeyondEntryPoints is ignored (recovery action closes the entry).");
      if(!InpEnableSurvivalMode)
         Print("Survival mode is OFF: InpSurvivalTriggerDrawdownEntryNumber and InpSurvivalCloseOffsetBeyondAverageEntryPoints are ignored.");
      else if(InpSurvivalTriggerDrawdownEntryNumber > InpMaxDrawdownEntriesPerBasket)
         Print("WARNING: survival trigger number is above the max DD entries, survival mode can never start.");

      double minStopPoints = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      if(InpDrawdownEntrySpacingPoints > 0)
      {
         int reachable = (int)MathFloor((InpStopLossDistanceFromEntryPoints - minStopPoints - 1.0) / InpDrawdownEntrySpacingPoints);
         if(reachable < InpMaxDrawdownEntriesPerBasket)
            PrintFormat("WARNING: only %d DD entries fit between the entry and the shared SL (spacing %.0f, SL %.0f). Later ones are skipped.",
                        MathMax(reachable, 0), InpDrawdownEntrySpacingPoints, InpStopLossDistanceFromEntryPoints);
      }
   }

   if(!InpEnableCooldownAfterStopLoss)
      Print("Cooldown is OFF: cooldown minutes / loss-only / both-directions inputs are ignored.");
   if(!InpUseTradingSession)
      Print("Trading session is OFF: session time inputs and InpCloseAllPositionsAtSessionEnd are ignored.");
   Print("InpMaxSlippagePoints applies to market orders only; pending limit orders ignore it.");
   Print("=============================================");
}

//+------------------------------------------------------------------+
int OnInit()
{
   if(InpSwingConfirmBarsEachSide < 1 || InpStructureSwingBarsEachSide < 1 ||
      InpChochLookbackBars < 2 * InpSwingConfirmBarsEachSide + 3 ||
      InpRetestWindowBars < 1 || InpMaxBarsFromHmaCrossToBreak < 0 ||
      InpStructureMaxBars < 30 || InpPartialCloseCount < 1 ||
      InpCooldownMinutes < 0 || InpSurvivalTriggerDrawdownEntryNumber < 1 ||
      InpChopMinBosCount < 0 || InpChopMinDistanceFromPreviousChochPoints < 0)
   { Print("Invalid inputs"); return INIT_PARAMETERS_INCORRECT; }

   pointSize = _Point;
   tradeExecutor.SetExpertMagicNumber(InpMagicNumber);
   tradeExecutor.SetDeviationInPoints(InpMaxSlippagePoints);
   tradeExecutor.SetTypeFillingBySymbol(_Symbol);

   hmaIndicatorHandle = iCustom(_Symbol, _Period, InpHmaIndicatorFileName,
                                InpHmaPeriodBars, InpHmaAppliedPrice, InpHmaLineColor);
   if(hmaIndicatorHandle == INVALID_HANDLE)
   { Print("HMA handle failed: ", GetLastError()); return INIT_FAILED; }

   buySignal.isActive = false;  sellSignal.isActive = false;
   buySignal.pendingOrderTicket = 0;  sellSignal.pendingOrderTicket = 0;
   buyBasket.isActive = false;  sellBasket.isActive = false;
   structureTrend = 0;

   if(InpApplyBlackTheme) ApplyBlackChartTheme();
   PrintInputAudit();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   DeletePendingLimitOrder(buySignal);
   DeletePendingLimitOrder(sellSignal);
   if(hmaIndicatorHandle != INVALID_HANDLE) IndicatorRelease(hmaIndicatorHandle);
   ObjectsDeleteAll(0, OBJECT_PREFIX);
}

//+------------------------------------------------------------------+
void OnTick()
{
   UpdateBasketLifecycle();
   CheckPendingLimitFills();

   if(InpUseTradingSession && InpCloseAllPositionsAtSessionEnd && !IsInsideTradingSession())
      CloseAllOurPositions();

   datetime currentBarOpenTime = iTime(_Symbol, _Period, 0);
   if(currentBarOpenTime != lastBarOpenTime)
   {
      lastBarOpenTime = currentBarOpenTime;
      HandleNewBar();
   }

   CheckRetestEntries();
   ManagePendingLimitOrder(buySignal, true);
   ManagePendingLimitOrder(sellSignal, false);
   CheckDrawdownEntries();
   ManageSurvivalMode(buyBasket, true);
   ManageSurvivalMode(sellBasket, false);
   ManageBasketBreakEven(buyBasket, true);
   ManageBasketBreakEven(sellBasket, false);
   ManageOpenPositions();
}

//+------------------------------------------------------------------+
// Cooldown: a stop-loss exit starts the cooldown timer
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &transaction,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(!InpEnableCooldownAfterStopLoss) return;
   if(transaction.type != TRADE_TRANSACTION_DEAL_ADD) return;

   ulong dealTicket = transaction.deal;
   if(dealTicket == 0 || !HistoryDealSelect(dealTicket)) return;
   if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != InpMagicNumber) return;
   if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol) return;
   if(HistoryDealGetInteger(dealTicket, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;
   if(HistoryDealGetInteger(dealTicket, DEAL_REASON) != DEAL_REASON_SL) return;

   double netResult = HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
                    + HistoryDealGetDouble(dealTicket, DEAL_SWAP)
                    + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
   if(InpCooldownOnlyWhenStopLossHitAtLoss && netResult >= 0) return;

   // a SELL deal closes a BUY position and vice versa
   bool closedBuyPosition = (HistoryDealGetInteger(dealTicket, DEAL_TYPE) == DEAL_TYPE_SELL);
   datetime cooldownEnd = TimeCurrent() + (datetime)(InpCooldownMinutes * 60);

   if(InpCooldownBlocksBothDirections || closedBuyPosition)
      if(cooldownEnd > buyCooldownUntilTime) buyCooldownUntilTime = cooldownEnd;
   if(InpCooldownBlocksBothDirections || !closedBuyPosition)
      if(cooldownEnd > sellCooldownUntilTime) sellCooldownUntilTime = cooldownEnd;

   PrintFormat("Stop loss hit on a %s position (net %.2f). Cooldown until %s",
               closedBuyPosition ? "buy" : "sell", netResult, TimeToString(cooldownEnd, TIME_DATE | TIME_MINUTES));
}

//+------------------------------------------------------------------+
bool CanSendOrderNow()
{
   if(TimeCurrent() - lastOrderAttemptTime < 5) return false;
   lastOrderAttemptTime = TimeCurrent();
   return true;
}

void UpdateBasketLifecycle()
{
   if(buyBasket.isActive && !HasOpenPosition(POSITION_TYPE_BUY))
   {
      PrintFormat("Buy basket %s closed: all positions are flat. New CHoCH signal required.", buyBasket.basketName);
      buyBasket.isActive = false;
   }
   if(sellBasket.isActive && !HasOpenPosition(POSITION_TYPE_SELL))
   {
      PrintFormat("Sell basket %s closed: all positions are flat. New CHoCH signal required.", sellBasket.basketName);
      sellBasket.isActive = false;
   }
}

void CloseAllOurPositions()
{
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      ulong ticket = PositionGetTicket(index);
      if(IsOurPosition(ticket)) tradeExecutor.PositionClose(ticket);
   }
}

void CloseBasketPositions(long positionType)
{
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      ulong ticket = PositionGetTicket(index);
      if(IsOurPosition(ticket, positionType)) tradeExecutor.PositionClose(ticket);
   }
}

void InitializeBasket(SBasket &basket, const string basketName, double fillPrice, double stopLossPrice)
{
   basket.isActive = true;
   basket.basketName = basketName;
   basket.lastEntryPrice = fillPrice;
   basket.sharedStopLossPrice = stopLossPrice;
   basket.drawdownEntriesOpened = 0;
   basket.breakEvenApplied = false;
   basket.survivalMode = false;
}

//+------------------------------------------------------------------+
// Chart marking
//+------------------------------------------------------------------+
void DrawStructureMark(const string tag, datetime time1, double price, datetime time2,
                       const string text, color markColor)
{
   string lineName  = OBJECT_PREFIX + tag + "_LINE_"  + IntegerToString((long)time2);
   string labelName = OBJECT_PREFIX + tag + "_LABEL_" + IntegerToString((long)time2);
   ObjectDelete(0, lineName);
   ObjectDelete(0, labelName);

   ObjectCreate(0, lineName, OBJ_TREND, 0, time1, price, time2, price);
   ObjectSetInteger(0, lineName, OBJPROP_COLOR, markColor);
   ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false);

   ObjectCreate(0, labelName, OBJ_TEXT, 0, time1, price);
   ObjectSetString(0, labelName, OBJPROP_TEXT, text);
   ObjectSetInteger(0, labelName, OBJPROP_COLOR, markColor);
   ObjectSetInteger(0, labelName, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
}

//+------------------------------------------------------------------+
// Signal lifecycle
//+------------------------------------------------------------------+
void ArmSignal(SSignal &signal, bool isBuySide, double levelPrice, datetime levelBarTime,
               const string labelText, bool bodyCloseBreak)
{
   DeletePendingLimitOrder(signal);

   signal.isActive = true;
   signal.entryConfirmed = false;
   signal.bodyCloseBreak = bodyCloseBreak;
   signal.levelPrice = levelPrice;
   signal.levelBarTime = levelBarTime;
   signal.breakBarTime = iTime(_Symbol, _Period, 1);
   signal.barsAlive = 0;
   signal.pendingOrderTicket = 0;
   signal.pendingBasketName = "";
   signal.limitPlacedTime = 0;
   signal.lastLimitAttemptTime = 0;
   signal.lastLimitStatus = "";
   signal.limitFailures = 0;
   signal.limitGivenUp = false;

   string sideTag = isBuySide ? "B_" : "S_";
   signal.lineName  = OBJECT_PREFIX + sideTag + "LINE_"  + IntegerToString((long)signal.breakBarTime);
   signal.labelName = OBJECT_PREFIX + sideTag + "LABEL_" + IntegerToString((long)signal.breakBarTime);

   datetime lineEndTime = signal.breakBarTime + (datetime)(PeriodSeconds() * (InpRetestWindowBars + 1));
   color lineColor = isBuySide ? clrLime : clrRed;

   ObjectCreate(0, signal.lineName, OBJ_TREND, 0, levelBarTime, levelPrice, lineEndTime, levelPrice);
   ObjectSetInteger(0, signal.lineName, OBJPROP_COLOR, lineColor);
   ObjectSetInteger(0, signal.lineName, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, signal.lineName, OBJPROP_RAY_RIGHT, false);

   ObjectCreate(0, signal.labelName, OBJ_TEXT, 0, levelBarTime, levelPrice);
   ObjectSetString(0, signal.labelName, OBJPROP_TEXT, labelText);
   ObjectSetInteger(0, signal.labelName, OBJPROP_COLOR, lineColor);
   ObjectSetInteger(0, signal.labelName, OBJPROP_ANCHOR, isBuySide ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);

   PrintFormat("CHoCH confirmed (%s) at level %s, label: %s", isBuySide ? "buy" : "sell",
               DoubleToString(levelPrice, _Digits), labelText);

   // limit-order mode: place the order immediately, right after the CHoCH candle has closed
   if(InpRetestEntryMode == ENTRY_LIMIT_ORDER_AT_CHOCH_LEVEL)
      TryPlaceLimitOrder(signal, isBuySide);
}

// invalidReason = "" -> setup was used (entry taken); otherwise it stays on chart in grey
void CancelSignal(SSignal &signal, const string invalidReason)
{
   DeletePendingLimitOrder(signal);
   if(invalidReason != "")
   {
      ObjectSetInteger(0, signal.lineName, OBJPROP_COLOR, clrGray);
      ObjectSetInteger(0, signal.labelName, OBJPROP_COLOR, clrGray);
      ObjectSetString(0, signal.labelName, OBJPROP_TEXT, "CHoCH invalid: " + invalidReason);
      PrintFormat("CHoCH setup invalid: %s", invalidReason);
   }
   signal.isActive = false;
   signal.entryConfirmed = false;
}

// Runs once per new bar. Candle 1 (just closed) is candle number barsAlive after the CHoCH candle.
void ProcessSignalOnNewBar(SSignal &signal, bool isBuySide)
{
   if(!signal.isActive) return;
   signal.entryConfirmed = false;
   signal.barsAlive++;

   double candleOpen  = iOpen(_Symbol, _Period, 1);
   double candleHigh  = iHigh(_Symbol, _Period, 1);
   double candleLow   = iLow(_Symbol, _Period, 1);
   double candleClose = iClose(_Symbol, _Period, 1);
   double approachDistance = InpRetestApproachDistancePoints * pointSize;
   bool   limitMode = (InpRetestEntryMode == ENTRY_LIMIT_ORDER_AT_CHOCH_LEVEL);

   bool closedBackThroughLevel = isBuySide ? (candleClose < signal.levelPrice)
                                           : (candleClose > signal.levelPrice);
   bool closeBackCountsAsRetest = (InpTakeEntryWhenCloseBackThroughLevel && signal.bodyCloseBreak);

   if(closedBackThroughLevel)
   {
      if(!closeBackCountsAsRetest)
      { CancelSignal(signal, "closed back through level"); return; }

      if(limitMode)
      {
         // the limit order sits at the level and stays alive until the window ends
         if(signal.barsAlive >= InpRetestWindowBars)
            CancelSignal(signal, "limit order not filled within " + IntegerToString(InpRetestWindowBars) + " candles");
         return;
      }

      PrintFormat("Close back through level counted as retest (%s)", isBuySide ? "buy" : "sell");
      if(InpRetestEntryMode == ENTRY_AFTER_REJECTION_CANDLE_CLOSE)
      {
         signal.entryConfirmed = true;   // market entry on the first tick of the new bar
         return;
      }
      // first-touch mode: price is already beyond the zone, the tick check enters immediately
      if(signal.barsAlive > InpRetestWindowBars)
         CancelSignal(signal, "no entry within " + IntegerToString(InpRetestWindowBars) + " candles");
      return;
   }

   if(InpRetestEntryMode == ENTRY_AFTER_REJECTION_CANDLE_CLOSE)
   {
      bool touchedRetestZone = isBuySide ? (candleLow  <= signal.levelPrice + approachDistance)
                                         : (candleHigh >= signal.levelPrice - approachDistance);
      bool directionOk = !InpRequireRejectionCandleDirection ||
                         (isBuySide ? candleClose > candleOpen : candleClose < candleOpen);
      if(touchedRetestZone && directionOk)
      {
         signal.entryConfirmed = true;     // market entry on the first tick of the new bar
         return;
      }
   }

   if(signal.barsAlive >= InpRetestWindowBars)
   {
      if(limitMode)
         CancelSignal(signal, "limit order not filled within " + IntegerToString(InpRetestWindowBars) + " candles");
      else
         CancelSignal(signal, "no retest within " + IntegerToString(InpRetestWindowBars) + " candles");
   }
}

//+------------------------------------------------------------------+
// Pending limit order at the exact CHoCH level
//+------------------------------------------------------------------+
void LogLimitStatus(SSignal &signal, const string statusText)
{
   if(!InpLogSetupDiagnostics) return;
   if(signal.lastLimitStatus == statusText) return;       // log each distinct status once
   signal.lastLimitStatus = statusText;
   Print("Limit order: ", statusText);
}

void DeletePendingLimitOrder(SSignal &signal)
{
   if(signal.pendingOrderTicket == 0) return;
   if(OrderSelect(signal.pendingOrderTicket))
   {
      if(!tradeExecutor.OrderDelete(signal.pendingOrderTicket))
         PrintFormat("Failed to delete pending order %I64u: %s", signal.pendingOrderTicket,
                     tradeExecutor.ResultRetcodeDescription());
   }
   signal.pendingOrderTicket = 0;
}

// Sends a limit order; tries RETURN, then IOC, then FOK filling (brokers differ for pending orders).
bool SendPendingLimit(bool isBuySide, double volume, double price, double stopLoss, const string orderComment)
{
   ENUM_ORDER_TYPE_FILLING fillingModes[3];
   fillingModes[0] = ORDER_FILLING_RETURN;
   fillingModes[1] = ORDER_FILLING_IOC;
   fillingModes[2] = ORDER_FILLING_FOK;

   bool placed = false;
   for(int modeIndex = 0; modeIndex < 3; modeIndex++)
   {
      tradeExecutor.SetTypeFilling(fillingModes[modeIndex]);
      bool sent = isBuySide
         ? tradeExecutor.BuyLimit(volume, price, _Symbol, stopLoss, 0, ORDER_TIME_GTC, 0, orderComment)
         : tradeExecutor.SellLimit(volume, price, _Symbol, stopLoss, 0, ORDER_TIME_GTC, 0, orderComment);
      uint resultCode = tradeExecutor.ResultRetcode();
      if(sent && (resultCode == TRADE_RETCODE_DONE || resultCode == TRADE_RETCODE_PLACED))
      { placed = true; break; }
      if(resultCode != TRADE_RETCODE_INVALID_FILL) break;   // only retry another filling mode for that error
   }
   tradeExecutor.SetTypeFillingBySymbol(_Symbol);
   return placed;
}

// Called right after the CHoCH candle closes and then on every tick until the order exists.
bool TryPlaceLimitOrder(SSignal &signal, bool isBuySide)
{
   if(!signal.isActive || signal.pendingOrderTicket != 0 || signal.limitGivenUp) return false;
   if(TimeCurrent() - signal.lastLimitAttemptTime < 2) return false;     // spacing between failed attempts

   if(!IsInsideTradingSession())
   { LogLimitStatus(signal, "waiting: outside trading session"); return false; }
   if(IsInCooldown(isBuySide))
   { LogLimitStatus(signal, "waiting: cooldown after stop loss"); return false; }

   bool basketAlreadyActive = isBuySide ? buyBasket.isActive : sellBasket.isActive;
   long positionType = isBuySide ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   if(basketAlreadyActive || HasOpenPosition(positionType))
   { CancelSignal(signal, ""); return false; }

   double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double levelPrice = NormalizeDouble(signal.levelPrice, _Digits);
   double minPendingDistance = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * pointSize + pointSize;

   // price already at or through the level: a limit order there is impossible, the retest has happened
   if(isBuySide && askPrice <= levelPrice)
   { LogLimitStatus(signal, "price already at/through the level -> market entry"); TryOpenMainEntry(true); return false; }
   if(!isBuySide && bidPrice >= levelPrice)
   { LogLimitStatus(signal, "price already at/through the level -> market entry"); TryOpenMainEntry(false); return false; }

   double distanceToLevel = isBuySide ? (askPrice - levelPrice) : (levelPrice - bidPrice);
   if(distanceToLevel <= minPendingDistance)
   {
      LogLimitStatus(signal, StringFormat("waiting: price is %.0f pts from the level, broker minimum is %.0f pts",
                                          distanceToLevel / pointSize, minPendingDistance / pointSize));
      return false;
   }

   string basketName = "BSK" + IntegerToString((long)(TimeCurrent() % 1000000));
   string orderComment = basketName + "-MAIN";
   double lotSize = NormalizeVolume(InpOrderLotSize);
   double stopLossPrice = NormalizeDouble(isBuySide ? levelPrice - InpStopLossDistanceFromEntryPoints * pointSize
                                                    : levelPrice + InpStopLossDistanceFromEntryPoints * pointSize, _Digits);

   signal.lastLimitAttemptTime = TimeCurrent();
   if(!SendPendingLimit(isBuySide, lotSize, levelPrice, stopLossPrice, orderComment))
   {
      signal.limitFailures++;
      PrintFormat("Limit order FAILED (attempt %d): %d %s | level %s, ask %s, bid %s, SL %s, lots %.2f",
                  signal.limitFailures, tradeExecutor.ResultRetcode(), tradeExecutor.ResultRetcodeDescription(),
                  DoubleToString(levelPrice, _Digits), DoubleToString(askPrice, _Digits),
                  DoubleToString(bidPrice, _Digits), DoubleToString(stopLossPrice, _Digits), lotSize);
      if(signal.limitFailures >= 5)
      {
         signal.limitGivenUp = true;
         Print("Limit order: giving up after 5 failed attempts for this setup.");
      }
      return false;
   }

   signal.pendingOrderTicket = tradeExecutor.ResultOrder();
   signal.pendingBasketName = basketName;
   signal.limitPlacedTime = TimeCurrent();
   signal.lastLimitStatus = "placed";
   PrintFormat("%s LIMIT PLACED at %s (order %I64u, SL %s, lots %.2f)", isBuySide ? "Buy" : "Sell",
               DoubleToString(levelPrice, _Digits), signal.pendingOrderTicket,
               DoubleToString(stopLossPrice, _Digits), lotSize);
   return true;
}

void ManagePendingLimitOrder(SSignal &signal, bool isBuySide)
{
   if(InpRetestEntryMode != ENTRY_LIMIT_ORDER_AT_CHOCH_LEVEL) return;
   if(!signal.isActive) return;

   if(signal.pendingOrderTicket != 0)
   {
      // a live order is kept only while trading is allowed
      if(!IsInsideTradingSession())
         CancelSignal(signal, "outside trading session");
      else if(IsInCooldown(isBuySide))
         CancelSignal(signal, "cooldown after stop loss");
      return;
   }

   TryPlaceLimitOrder(signal, isBuySide);       // retry until the order exists
}

void CheckPendingLimitFills()
{
   CheckPendingLimitFill(buySignal, true);
   CheckPendingLimitFill(sellSignal, false);
}

void CheckPendingLimitFill(SSignal &signal, bool isBuySide)
{
   if(!signal.isActive || signal.pendingOrderTicket == 0) return;
   if(OrderSelect(signal.pendingOrderTicket)) return;          // still pending

   // the order is gone: filled, or removed outside the EA
   long positionType = isBuySide ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   string basketName = signal.pendingBasketName;
   ulong  filledTicket = 0;
   datetime newestOpenTime = 0;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      ulong ticket = PositionGetTicket(index);
      if(!IsOurPosition(ticket, positionType)) continue;
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      bool commentMatches = (StringFind(PositionGetString(POSITION_COMMENT), basketName) >= 0);
      if(!commentMatches && openTime < signal.limitPlacedTime) continue;
      if(filledTicket == 0 || openTime >= newestOpenTime) { filledTicket = ticket; newestOpenTime = openTime; }
   }

   signal.pendingOrderTicket = 0;
   if(filledTicket == 0)
   {
      signal.limitGivenUp = true;
      Print("Pending limit order disappeared without a fill. Not re-placing it for this setup.");
      return;
   }

   AddPositionState(filledTicket);
   PositionSelectByTicket(filledTicket);
   double fillPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double correctedStopLoss = NormalizeDouble(isBuySide ? fillPrice - InpStopLossDistanceFromEntryPoints * pointSize
                                                        : fillPrice + InpStopLossDistanceFromEntryPoints * pointSize, _Digits);
   if(MathAbs(correctedStopLoss - PositionGetDouble(POSITION_SL)) > pointSize / 2)
      tradeExecutor.PositionModify(filledTicket, correctedStopLoss, 0);

   InitializeBasket(isBuySide ? buyBasket : sellBasket, basketName, fillPrice, correctedStopLoss);
   CancelSignal(signal, "");
   PrintFormat("LIMIT FILLED: basket %s at %s", basketName, DoubleToString(fillPrice, _Digits));
}

//+------------------------------------------------------------------+
// First CHoCH detection (HMA based)
//+------------------------------------------------------------------+
// Bullish: lowest low in window, then the nearest swing high older than that low.
bool FindBullishChochLevel(const double &highPrices[], const double &lowPrices[],
                           double &levelPrice, int &levelBarShift, double &legExtremePrice)
{
   int    lowestLowShift = -1;
   double lowestLowPrice = DBL_MAX;
   for(int barShift = 2; barShift <= InpChochLookbackBars + 1; barShift++)
      if(lowPrices[barShift] < lowestLowPrice) { lowestLowPrice = lowPrices[barShift]; lowestLowShift = barShift; }
   if(lowestLowShift < 0) return false;

   int firstShift = MathMax(lowestLowShift + 1, InpSwingConfirmBarsEachSide + 2);
   for(int barShift = firstShift; barShift <= InpChochLookbackBars + 1; barShift++)
   {
      bool isSwingHigh = true;
      for(int offset = 1; offset <= InpSwingConfirmBarsEachSide && isSwingHigh; offset++)
         if(highPrices[barShift - offset] >= highPrices[barShift] || highPrices[barShift + offset] > highPrices[barShift])
            isSwingHigh = false;
      if(isSwingHigh)
      { levelBarShift = barShift; levelPrice = highPrices[barShift]; legExtremePrice = lowestLowPrice; return true; }
   }
   return false;
}

// Bearish: highest high in window, then the nearest swing low older than that high.
bool FindBearishChochLevel(const double &highPrices[], const double &lowPrices[],
                           double &levelPrice, int &levelBarShift, double &legExtremePrice)
{
   int    highestHighShift = -1;
   double highestHighPrice = -DBL_MAX;
   for(int barShift = 2; barShift <= InpChochLookbackBars + 1; barShift++)
      if(highPrices[barShift] > highestHighPrice) { highestHighPrice = highPrices[barShift]; highestHighShift = barShift; }
   if(highestHighShift < 0) return false;

   int firstShift = MathMax(highestHighShift + 1, InpSwingConfirmBarsEachSide + 2);
   for(int barShift = firstShift; barShift <= InpChochLookbackBars + 1; barShift++)
   {
      bool isSwingLow = true;
      for(int offset = 1; offset <= InpSwingConfirmBarsEachSide && isSwingLow; offset++)
         if(lowPrices[barShift - offset] <= lowPrices[barShift] || lowPrices[barShift + offset] < lowPrices[barShift])
            isSwingLow = false;
      if(isSwingLow)
      { levelBarShift = barShift; levelPrice = lowPrices[barShift]; legExtremePrice = highestHighPrice; return true; }
   }
   return false;
}

bool LevelAlreadyBrokenByClose(bool isBuySide, double levelPrice, int levelBarShift, const double &closePrices[])
{
   for(int barShift = 2; barShift < levelBarShift; barShift++)
   {
      if(isBuySide  && closePrices[barShift] > levelPrice) return true;
      if(!isBuySide && closePrices[barShift] < levelPrice) return true;
   }
   return false;
}

// hmaValues[i] is the HMA at bar shift i+1; closePrices[i] is the close at bar shift i
bool CrossedHmaRecently(bool isBuySide, const double &closePrices[], const double &hmaValues[])
{
   for(int crossShift = 1; crossShift <= InpMaxBarsFromHmaCrossToBreak + 1; crossShift++)
   {
      double closeNow  = closePrices[crossShift];
      double closePrev = closePrices[crossShift + 1];
      double hmaNow    = hmaValues[crossShift - 1];
      double hmaPrev   = hmaValues[crossShift];
      if(isBuySide  && closeNow > hmaNow && closePrev <= hmaPrev) return true;
      if(!isBuySide && closeNow < hmaNow && closePrev >= hmaPrev) return true;
   }
   return false;
}

void StartStructure(bool isBullish, double levelPrice, datetime levelTime, double legExtremePrice)
{
   structureTrend = isBullish ? 1 : -1;
   structureStartTime = iTime(_Symbol, _Period, 1);
   trendStartTime = structureStartTime;
   structureExtremePrice = levelPrice;
   structureExtremeTime = levelTime;
   lastBosExtremeTime = levelTime;
   structureOriginPrice = legExtremePrice;
   previousChochLevelPrice = levelPrice;
   bosCount = 0;
   PrintFormat("Structure started: first %s CHoCH at level %s", isBullish ? "bullish" : "bearish",
               DoubleToString(levelPrice, _Digits));
}

void LogSetupDiagnostic(bool isBuySide, double levelPrice, bool isFirstBreak, bool closeOnHmaSide, bool crossedHma)
{
   if(!InpLogSetupDiagnostics) return;
   string problems = "";
   if(!isFirstBreak)   problems += " [level was already broken by an earlier close]";
   if(!closeOnHmaSide) problems += " [close is not on the correct side of the HMA]";
   if(!crossedHma)     problems += StringFormat(" [no HMA cross within %d bars of the break]", InpMaxBarsFromHmaCrossToBreak);
   PrintFormat("%s break candle beyond %s NOT armed:%s", isBuySide ? "Bullish" : "Bearish",
               DoubleToString(levelPrice, _Digits), problems);
}

void DetectFirstChoch(const double &highPrices[], const double &lowPrices[], const double &closePrices[],
                      const double &hmaValues[], bool buySideFree, bool sellSideFree)
{
   double breakCandleClose = closePrices[1];
   double levelPrice, legExtremePrice;
   int levelBarShift;

   if(FindBullishChochLevel(highPrices, lowPrices, levelPrice, levelBarShift, legExtremePrice))
   {
      if(breakCandleClose > levelPrice)                                   // body closed above the level
      {
         bool isFirstBreak  = !LevelAlreadyBrokenByClose(true, levelPrice, levelBarShift, closePrices);
         bool closeAboveHma = (breakCandleClose > hmaValues[0]);
         bool crossedHma    = CrossedHmaRecently(true, closePrices, hmaValues);
         if(isFirstBreak && closeAboveHma && crossedHma)
         {
            datetime levelTime = iTime(_Symbol, _Period, levelBarShift);
            if(InpEnableMarketStructure) StartStructure(true, levelPrice, levelTime, legExtremePrice);
            if(buySideFree)
            {
               if(buySignal.isActive) CancelSignal(buySignal, "replaced by newer CHoCH");
               ArmSignal(buySignal, true, levelPrice, levelTime, "CHoCH", true);
            }
            else if(InpLogSetupDiagnostics)
               Print("Bullish CHoCH confirmed but the buy side is not free (session / cooldown / open basket).");
            return;
         }
         LogSetupDiagnostic(true, levelPrice, isFirstBreak, closeAboveHma, crossedHma);
      }
   }

   if(FindBearishChochLevel(highPrices, lowPrices, levelPrice, levelBarShift, legExtremePrice))
   {
      if(breakCandleClose < levelPrice)                                   // body closed below the level
      {
         bool isFirstBreak  = !LevelAlreadyBrokenByClose(false, levelPrice, levelBarShift, closePrices);
         bool closeBelowHma = (breakCandleClose < hmaValues[0]);
         bool crossedHma    = CrossedHmaRecently(false, closePrices, hmaValues);
         if(isFirstBreak && closeBelowHma && crossedHma)
         {
            datetime levelTime = iTime(_Symbol, _Period, levelBarShift);
            if(InpEnableMarketStructure) StartStructure(false, levelPrice, levelTime, legExtremePrice);
            if(sellSideFree)
            {
               if(sellSignal.isActive) CancelSignal(sellSignal, "replaced by newer CHoCH");
               ArmSignal(sellSignal, false, levelPrice, levelTime, "CHoCH", true);
            }
            else if(InpLogSetupDiagnostics)
               Print("Bearish CHoCH confirmed but the sell side is not free (session / cooldown / open basket).");
            return;
         }
         LogSetupDiagnostic(false, levelPrice, isFirstBreak, closeBelowHma, crossedHma);
      }
   }
}

//+------------------------------------------------------------------+
// Market structure tracking (after the first CHoCH)
//+------------------------------------------------------------------+
bool IsStructureSwing(bool isHigh, int barShift, const double &prices[])
{
   for(int offset = 1; offset <= InpStructureSwingBarsEachSide; offset++)
   {
      if(isHigh)
      {
         if(prices[barShift - offset] >= prices[barShift] || prices[barShift + offset] > prices[barShift]) return false;
      }
      else
      {
         if(prices[barShift - offset] <= prices[barShift] || prices[barShift + offset] < prices[barShift]) return false;
      }
   }
   return true;
}

// Most recent confirmed swing between fromShift and toShift (smaller shift = more recent)
bool FindLatestStructureSwing(bool isHigh, int fromShift, int toShift, const double &prices[], int &swingShift)
{
   for(int barShift = fromShift; barShift <= toShift; barShift++)
      if(IsStructureSwing(isHigh, barShift, prices)) { swingShift = barShift; return true; }
   return false;
}

// Position of price inside the structure range: 0 = lowest peak, 100 = highest peak
double LocationPercentInRange(double price, const double &highPrices[], const double &lowPrices[])
{
   int startShift = iBarShift(_Symbol, _Period, structureStartTime, false);
   if(startShift < 1) startShift = 1;
   int lastShift = MathMin(MathMin(startShift, InpStructureMaxBars), ArraySize(highPrices) - 1);

   double rangeHigh = -DBL_MAX, rangeLow = DBL_MAX;
   for(int barShift = 1; barShift <= lastShift; barShift++)
   {
      if(highPrices[barShift] > rangeHigh) rangeHigh = highPrices[barShift];
      if(lowPrices[barShift]  < rangeLow)  rangeLow  = lowPrices[barShift];
   }
   double rangeSize = rangeHigh - rangeLow;
   if(rangeSize <= 0) return 50.0;
   return (price - rangeLow) / rangeSize * 100.0;
}

// breakAbove = true: test a break above the level; false: test a break below it.
// Uses candle 1 (the candle that just closed).
bool HasStructureBreak(bool breakAbove, double levelPrice,
                       const double &highPrices[], const double &lowPrices[], const double &closePrices[])
{
   if(InpStructureBreakMode == STRUCTURE_BREAK_BY_WICK)
      return breakAbove ? (highPrices[1] > levelPrice) : (lowPrices[1] < levelPrice);
   return breakAbove ? (closePrices[1] > levelPrice) : (closePrices[1] < levelPrice);
}

void HandleStructureChoch(bool newIsBullish, double levelPrice, datetime levelTime,
                          const double &highPrices[], const double &lowPrices[], const double &closePrices[],
                          const double &hmaValues[], bool buySideFree, bool sellSideFree)
{
   double breakClose = closePrices[1];
   datetime breakTime = iTime(_Symbol, _Period, 1);
   double locationPercent = LocationPercentInRange(breakClose, highPrices, lowPrices);

   bool locationValid = newIsBullish ? (locationPercent <= 100.0 - InpLocationThresholdPercent)
                                     : (locationPercent >= InpLocationThresholdPercent);
   bool hmaSideValid  = !InpRequireHmaSideForStructureChoch ||
                        (newIsBullish ? breakClose > hmaValues[0] : breakClose < hmaValues[0]);
   // a side is only blocked by session, cooldown or an open basket/position; a pending older signal is replaced
   bool sideFree      = newIsBullish ? buySideFree : sellSideFree;

   // choppy-market filter: BoS count of the trend that this CHoCH ends, and distance from the previous CHoCH level
   int    bosInEndedTrend = bosCount;
   double distanceFromPreviousChochPoints = MathAbs(levelPrice - previousChochLevelPrice) / pointSize;
   bool   hasEnoughBos      = (bosInEndedTrend >= InpChopMinBosCount);
   bool   hasEnoughDistance = (distanceFromPreviousChochPoints >= InpChopMinDistanceFromPreviousChochPoints);
   bool   chopValid = true;
   switch(InpChopFilterMode)
   {
      case CHOP_FILTER_REQUIRE_BOS:            chopValid = hasEnoughBos; break;
      case CHOP_FILTER_REQUIRE_MIN_DISTANCE:   chopValid = hasEnoughDistance; break;
      case CHOP_FILTER_REQUIRE_BOTH:           chopValid = (hasEnoughBos && hasEnoughDistance); break;
      default:                                 chopValid = true; break;
   }

   string rangeText = StringFormat("%.0f%% of range", locationPercent);
   string sideText  = newIsBullish ? "bull" : "bear";

   if(locationValid && chopValid && hmaSideValid && sideFree)
   {
      if(newIsBullish && buySignal.isActive)   CancelSignal(buySignal, "replaced by newer CHoCH");
      if(!newIsBullish && sellSignal.isActive) CancelSignal(sellSignal, "replaced by newer CHoCH");
      ArmSignal(newIsBullish ? buySignal : sellSignal, newIsBullish, levelPrice, levelTime,
                "CHoCH " + sideText + " (" + rangeText + ", " + IntegerToString(bosInEndedTrend) + " BoS)",
                (InpStructureBreakMode == STRUCTURE_BREAK_BY_BODY_CLOSE));
   }
   else
   {
      string busyText = "open position on this side";
      if(!IsInsideTradingSession())                 busyText = "outside trading session";
      else if(IsInCooldown(newIsBullish))           busyText = "cooldown after stop loss";
      else if(newIsBullish && buyBasket.isActive)   busyText = "buy basket " + buyBasket.basketName + " still open";
      else if(!newIsBullish && sellBasket.isActive) busyText = "sell basket " + sellBasket.basketName + " still open";

      string chopText = StringFormat("choppy: %d BoS, %.0f pts from previous CHoCH",
                                     bosInEndedTrend, distanceFromPreviousChochPoints);
      string reason = !locationValid ? "weak location"
                    : (!chopValid    ? chopText
                    : (!hmaSideValid ? "HMA side" : busyText));
      DrawStructureMark("CHOCHW", levelTime, levelPrice, breakTime,
                        "CHoCH " + sideText + " not traded: " + reason + " (" + rangeText + ")", clrGray);
      PrintFormat("Structure CHoCH %s not traded: %s (%s)", sideText, reason, rangeText);
   }

   // always flip the trend; the old structural extreme becomes the protected origin
   double oldExtremePrice = structureExtremePrice;
   structureTrend = newIsBullish ? 1 : -1;
   trendStartTime = breakTime;
   structureExtremePrice = levelPrice;
   structureExtremeTime = levelTime;
   lastBosExtremeTime = levelTime;
   structureOriginPrice = oldExtremePrice;
   previousChochLevelPrice = levelPrice;
   bosCount = 0;
}

void UpdateMarketStructure(const double &highPrices[], const double &lowPrices[], const double &closePrices[],
                           const double &hmaValues[], bool buySideFree, bool sellSideFree)
{
   int trendStartShift = iBarShift(_Symbol, _Period, trendStartTime, false);
   if(trendStartShift < 0 || trendStartShift > InpStructureMaxBars)
   {
      Print("Structure reset: no trend change within ", InpStructureMaxBars, " bars.");
      structureTrend = 0;
      return;
   }

   bool isUptrend = (structureTrend > 0);
   int  maxUsableShift = ArraySize(highPrices) - InpStructureSwingBarsEachSide - 2;
   int  lastShift = MathMin(trendStartShift - 1, maxUsableShift);
   int  firstShift = InpStructureSwingBarsEachSide + 1;

   // protected level: latest swing against the trend since the trend started (else the origin)
   double protectedPrice = structureOriginPrice;
   datetime protectedTime = trendStartTime;
   int protectedShift;
   bool foundProtected = isUptrend ? FindLatestStructureSwing(false, firstShift, lastShift, lowPrices, protectedShift)
                                   : FindLatestStructureSwing(true,  firstShift, lastShift, highPrices, protectedShift);
   if(foundProtected)
   {
      protectedPrice = isUptrend ? lowPrices[protectedShift] : highPrices[protectedShift];
      protectedTime  = iTime(_Symbol, _Period, protectedShift);
   }

   // structural extreme: best swing in the trend direction since the trend started
   for(int barShift = firstShift; barShift <= lastShift; barShift++)
   {
      if(isUptrend && IsStructureSwing(true, barShift, highPrices) && highPrices[barShift] > structureExtremePrice)
      { structureExtremePrice = highPrices[barShift]; structureExtremeTime = iTime(_Symbol, _Period, barShift); }
      if(!isUptrend && IsStructureSwing(false, barShift, lowPrices) && lowPrices[barShift] < structureExtremePrice)
      { structureExtremePrice = lowPrices[barShift]; structureExtremeTime = iTime(_Symbol, _Period, barShift); }
   }

   datetime breakTime = iTime(_Symbol, _Period, 1);
   string modeTag = (InpStructureBreakMode == STRUCTURE_BREAK_BY_WICK) ? " (wick)" : "";

   // 1) CHoCH against the trend: break of the protected level
   //    uptrend -> break below the protected low; downtrend -> break above the protected high
   bool brokeProtected = HasStructureBreak(!isUptrend, protectedPrice, highPrices, lowPrices, closePrices);
   if(brokeProtected)
   {
      HandleStructureChoch(!isUptrend, protectedPrice, protectedTime,
                           highPrices, lowPrices, closePrices, hmaValues, buySideFree, sellSideFree);
      return;
   }

   // 2) BoS in the trend direction: break of the structural extreme, once per extreme
   bool brokeExtreme = HasStructureBreak(isUptrend, structureExtremePrice, highPrices, lowPrices, closePrices);
   if(brokeExtreme && structureExtremeTime != lastBosExtremeTime)
   {
      lastBosExtremeTime = structureExtremeTime;
      bosCount++;
      DrawStructureMark("BOS", structureExtremeTime, structureExtremePrice, breakTime,
                        StringFormat("BoS %d%s", bosCount, modeTag), isUptrend ? clrDodgerBlue : clrOrange);
      PrintFormat("BoS %d marked at %s%s", bosCount, DoubleToString(structureExtremePrice, _Digits), modeTag);
   }
}

//+------------------------------------------------------------------+
void HandleNewBar()
{
   ProcessSignalOnNewBar(buySignal, true);
   ProcessSignalOnNewBar(sellSignal, false);

   bool sessionOpen  = IsInsideTradingSession();
   bool buyCooldown  = IsInCooldown(true);
   bool sellCooldown = IsInCooldown(false);
   bool buySideFree  = (sessionOpen && !buyCooldown  && !buyBasket.isActive  && !HasOpenPosition(POSITION_TYPE_BUY));
   bool sellSideFree = (sessionOpen && !sellCooldown && !sellBasket.isActive && !HasOpenPosition(POSITION_TYPE_SELL));

   if(!buySideFree && buySignal.isActive)
      CancelSignal(buySignal, !sessionOpen ? "outside trading session" : (buyCooldown ? "cooldown after stop loss" : ""));
   if(!sellSideFree && sellSignal.isActive)
      CancelSignal(sellSignal, !sessionOpen ? "outside trading session" : (sellCooldown ? "cooldown after stop loss" : ""));
   if(!InpEnableMarketStructure && !buySideFree && !sellSideFree) return;

   int hmaBarsRequired = InpMaxBarsFromHmaCrossToBreak + 2;
   double hmaValues[];   // hmaValues[0] = HMA at shift 1
   ArraySetAsSeries(hmaValues, true);
   if(CopyBuffer(hmaIndicatorHandle, 0, 1, hmaBarsRequired, hmaValues) < hmaBarsRequired) return;

   int barsRequired = MathMax(InpChochLookbackBars + InpSwingConfirmBarsEachSide + 3,
                      MathMax(InpMaxBarsFromHmaCrossToBreak + 4,
                              InpStructureMaxBars + InpStructureSwingBarsEachSide + 5));
   double highPrices[], lowPrices[], closePrices[];
   ArraySetAsSeries(highPrices, true);
   ArraySetAsSeries(lowPrices, true);
   ArraySetAsSeries(closePrices, true);
   if(CopyHigh(_Symbol, _Period, 0, barsRequired, highPrices) < barsRequired) return;
   if(CopyLow(_Symbol, _Period, 0, barsRequired, lowPrices) < barsRequired) return;
   if(CopyClose(_Symbol, _Period, 0, barsRequired, closePrices) < barsRequired) return;

   if(InpEnableMarketStructure && structureTrend != 0)
      UpdateMarketStructure(highPrices, lowPrices, closePrices, hmaValues, buySideFree, sellSideFree);
   else
      DetectFirstChoch(highPrices, lowPrices, closePrices, hmaValues, buySideFree, sellSideFree);
}

//+------------------------------------------------------------------+
void CheckRetestEntries()
{
   if(InpRetestEntryMode == ENTRY_LIMIT_ORDER_AT_CHOCH_LEVEL) return;   // the pending limit order does the work

   if(InpRetestEntryMode == ENTRY_AFTER_REJECTION_CANDLE_CLOSE)
   {
      if(buySignal.isActive  && buySignal.entryConfirmed)  TryOpenMainEntry(true);
      if(sellSignal.isActive && sellSignal.entryConfirmed) TryOpenMainEntry(false);
      return;
   }

   double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double approachDistance = InpRetestApproachDistancePoints * pointSize;
   if(buySignal.isActive && askPrice <= buySignal.levelPrice + approachDistance)
      TryOpenMainEntry(true);
   if(sellSignal.isActive && bidPrice >= sellSignal.levelPrice - approachDistance)
      TryOpenMainEntry(false);
}

void TryOpenMainEntry(bool isBuySide)
{
   if(!IsInsideTradingSession() || IsInCooldown(isBuySide)) return;

   bool basketAlreadyActive = isBuySide ? buyBasket.isActive : sellBasket.isActive;
   long positionType = isBuySide ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   if(basketAlreadyActive || HasOpenPosition(positionType))
   {
      if(isBuySide) CancelSignal(buySignal, "");
      else          CancelSignal(sellSignal, "");
      return;
   }
   if(!CanSendOrderNow()) return;

   string basketName = "BSK" + IntegerToString((long)(TimeCurrent() % 1000000));
   ulong  newTicket;
   double fillPrice, appliedStopLossPrice;
   if(!OpenMarketPosition(isBuySide, basketName + "-MAIN", 0.0, newTicket, fillPrice, appliedStopLossPrice)) return;

   if(isBuySide)
   {
      CancelSignal(buySignal, "");
      InitializeBasket(buyBasket, basketName, fillPrice, appliedStopLossPrice);
   }
   else
   {
      CancelSignal(sellSignal, "");
      InitializeBasket(sellBasket, basketName, fillPrice, appliedStopLossPrice);
   }
}

//+------------------------------------------------------------------+
// requestedStopLossPrice = 0 -> SL computed from the fill (main entry)
// requestedStopLossPrice > 0 -> SL used as given (DD entry shares the basket SL)
bool OpenMarketPosition(bool isBuySide, const string orderComment, double requestedStopLossPrice,
                        ulong &newTicket, double &fillPrice, double &appliedStopLossPrice)
{
   newTicket = 0;
   fillPrice = 0;
   appliedStopLossPrice = 0;

   double lotSize      = NormalizeVolume(InpOrderLotSize);
   double askPrice     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bidPrice     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double requestPrice = isBuySide ? askPrice : bidPrice;
   bool   useSharedStop = (requestedStopLossPrice > 0);

   double stopLossPrice = useSharedStop
      ? NormalizeDouble(requestedStopLossPrice, _Digits)
      : NormalizeDouble(isBuySide ? requestPrice - InpStopLossDistanceFromEntryPoints * pointSize
                                  : requestPrice + InpStopLossDistanceFromEntryPoints * pointSize, _Digits);

   bool orderSent = isBuySide ? tradeExecutor.Buy(lotSize, _Symbol, 0, stopLossPrice, 0, orderComment)
                              : tradeExecutor.Sell(lotSize, _Symbol, 0, stopLossPrice, 0, orderComment);
   uint resultCode = tradeExecutor.ResultRetcode();
   if(!orderSent || (resultCode != TRADE_RETCODE_DONE && resultCode != TRADE_RETCODE_PLACED))
   {
      PrintFormat("Open failed (%s): %d %s", orderComment, resultCode, tradeExecutor.ResultRetcodeDescription());
      return false;
   }

   ENUM_POSITION_TYPE positionType = isBuySide ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   long newestOpenTimeMsc = 0;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      ulong ticket = PositionGetTicket(index);
      if(!IsOurPosition(ticket, positionType)) continue;
      long openTimeMsc = PositionGetInteger(POSITION_TIME_MSC);
      if(newTicket == 0 || openTimeMsc >= newestOpenTimeMsc)
      { newTicket = ticket; newestOpenTimeMsc = openTimeMsc; }
   }
   if(newTicket == 0) return false;

   AddPositionState(newTicket);
   PositionSelectByTicket(newTicket);
   fillPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   appliedStopLossPrice = stopLossPrice;

   if(!useSharedStop)   // main entry: SL exactly N points from the real fill price
   {
      double correctedStopLoss = NormalizeDouble(isBuySide ? fillPrice - InpStopLossDistanceFromEntryPoints * pointSize
                                                           : fillPrice + InpStopLossDistanceFromEntryPoints * pointSize, _Digits);
      if(MathAbs(correctedStopLoss - PositionGetDouble(POSITION_SL)) > pointSize / 2)
         tradeExecutor.PositionModify(newTicket, correctedStopLoss, 0);
      appliedStopLossPrice = correctedStopLoss;
   }
   return true;
}

//+------------------------------------------------------------------+
void CheckDrawdownEntries()
{
   if(!InpEnableDrawdownEntries) return;
   ProcessBasketDrawdown(buyBasket, true);
   ProcessBasketDrawdown(sellBasket, false);
}

void ProcessBasketDrawdown(SBasket &basket, bool isBuySide)
{
   if(!basket.isActive) return;
   if(!IsInsideTradingSession()) return;
   if(basket.survivalMode) return;                                       // survival mode: no more DD entries
   if(basket.breakEvenApplied) return;                                   // no new entries after basket break-even
   if(basket.drawdownEntriesOpened >= InpMaxDrawdownEntriesPerBasket) return;

   double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double adverseMovePoints = isBuySide ? (basket.lastEntryPrice - askPrice) / pointSize
                                        : (bidPrice - basket.lastEntryPrice) / pointSize;
   if(adverseMovePoints < InpDrawdownEntrySpacingPoints) return;

   double minStopDistancePoints = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double distanceToSharedStopPoints = isBuySide ? (askPrice - basket.sharedStopLossPrice) / pointSize
                                                 : (basket.sharedStopLossPrice - bidPrice) / pointSize;
   if(distanceToSharedStopPoints <= minStopDistancePoints) return;      // too close to the shared SL

   if(!CanSendOrderNow()) return;

   string entryComment = basket.basketName + "-DD" + IntegerToString(basket.drawdownEntriesOpened + 1);
   ulong  newTicket;
   double fillPrice, appliedStopLossPrice;
   if(!OpenMarketPosition(isBuySide, entryComment, basket.sharedStopLossPrice,
                          newTicket, fillPrice, appliedStopLossPrice)) return;

   basket.drawdownEntriesOpened++;
   basket.lastEntryPrice = fillPrice;

   for(int stateIndex = 0; stateIndex < ArraySize(positionStates); stateIndex++)
      if(positionStates[stateIndex].isBuy == isBuySide && positionStates[stateIndex].ticket != newTicket)
         positionStates[stateIndex].markedAsDrawdownEntry = true;

   if(InpEnableSurvivalMode && basket.drawdownEntriesOpened >= InpSurvivalTriggerDrawdownEntryNumber)
   {
      basket.survivalMode = true;
      PrintFormat("Basket %s: DD entry %d opened -> SURVIVAL MODE. Closing all at break-even.",
                  basket.basketName, basket.drawdownEntriesOpened);
   }
}

//+------------------------------------------------------------------+
// Survival mode: close the whole basket when price returns to the basket's
// volume-weighted average entry price (plus/minus an optional offset).
void ManageSurvivalMode(SBasket &basket, bool isBuySide)
{
   if(!basket.isActive || !basket.survivalMode) return;

   long positionType = isBuySide ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   double totalVolume = 0, weightedPriceSum = 0;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      ulong ticket = PositionGetTicket(index);
      if(!IsOurPosition(ticket, positionType)) continue;
      double volume = PositionGetDouble(POSITION_VOLUME);
      totalVolume += volume;
      weightedPriceSum += PositionGetDouble(POSITION_PRICE_OPEN) * volume;
   }
   if(totalVolume <= 0) return;

   double averageEntryPrice = weightedPriceSum / totalVolume;
   double closeTargetPrice = isBuySide ? averageEntryPrice + InpSurvivalCloseOffsetBeyondAverageEntryPoints * pointSize
                                       : averageEntryPrice - InpSurvivalCloseOffsetBeyondAverageEntryPoints * pointSize;
   double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   bool targetReached = isBuySide ? (bidPrice >= closeTargetPrice) : (askPrice <= closeTargetPrice);
   if(!targetReached) return;

   PrintFormat("Basket %s: survival target reached (average entry %s). Closing all positions.",
               basket.basketName, DoubleToString(averageEntryPrice, _Digits));
   CloseBasketPositions(positionType);
}

//+------------------------------------------------------------------+
// Basket break-even: when the best position reaches the activation profit,
// every position in the basket gets its SL moved to the best position's entry price.
void ManageBasketBreakEven(SBasket &basket, bool isBuySide)
{
   if(!basket.isActive || basket.breakEvenApplied || basket.survivalMode) return;

   long positionType = isBuySide ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double bestProfitPoints = -DBL_MAX;
   double bestEntryPrice = 0;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      ulong ticket = PositionGetTicket(index);
      if(!IsOurPosition(ticket, positionType)) continue;
      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double profitPoints = isBuySide ? (bidPrice - entryPrice) / pointSize
                                      : (entryPrice - askPrice) / pointSize;
      if(profitPoints > bestProfitPoints) { bestProfitPoints = profitPoints; bestEntryPrice = entryPrice; }
   }
   if(bestEntryPrice == 0 || bestProfitPoints < InpBasketBreakEvenActivationProfitPoints) return;

   double breakEvenStopPrice = NormalizeDouble(isBuySide
      ? bestEntryPrice + InpBasketBreakEvenOffsetBeyondBestEntryPoints * pointSize
      : bestEntryPrice - InpBasketBreakEvenOffsetBeyondBestEntryPoints * pointSize, _Digits);

   bool allPositionsUpdated = true;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      ulong ticket = PositionGetTicket(index);
      if(!IsOurPosition(ticket, positionType)) continue;
      double currentStopLossPrice = PositionGetDouble(POSITION_SL);
      if(!IsStopLossImprovement(currentStopLossPrice, breakEvenStopPrice, isBuySide)) continue;
      if(!ModifyStopLoss(ticket, breakEvenStopPrice, isBuySide)) allPositionsUpdated = false;
   }

   basket.sharedStopLossPrice = breakEvenStopPrice;
   if(allPositionsUpdated)
   {
      basket.breakEvenApplied = true;
      PrintFormat("Basket %s: break-even applied at %s", basket.basketName, DoubleToString(breakEvenStopPrice, _Digits));
   }
}

//+------------------------------------------------------------------+
bool IsOurPosition(ulong ticket, long requiredPositionType = -1)
{
   if(ticket == 0 || !PositionSelectByTicket(ticket)) return false;
   if(PositionGetString(POSITION_SYMBOL) != _Symbol) return false;
   if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) return false;
   if(requiredPositionType >= 0 && PositionGetInteger(POSITION_TYPE) != requiredPositionType) return false;
   return true;
}

bool HasOpenPosition(long positionType)
{
   for(int index = PositionsTotal() - 1; index >= 0; index--)
      if(IsOurPosition(PositionGetTicket(index), positionType)) return true;
   return false;
}

int FindPositionStateIndex(ulong ticket)
{
   for(int index = 0; index < ArraySize(positionStates); index++)
      if(positionStates[index].ticket == ticket) return index;
   return -1;
}

int AddPositionState(ulong ticket)
{
   int newIndex = ArraySize(positionStates);
   ArrayResize(positionStates, newIndex + 1);
   positionStates[newIndex].ticket = ticket;
   positionStates[newIndex].isBuy = (PositionSelectByTicket(ticket) &&
                                     PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   positionStates[newIndex].partialsDone = 0;
   positionStates[newIndex].trailingActive = false;
   positionStates[newIndex].trailReferencePrice = 0;
   positionStates[newIndex].markedAsDrawdownEntry = false;
   positionStates[newIndex].recoveryHandled = false;
   return newIndex;
}

//+------------------------------------------------------------------+
double VolumeStep() { return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP); }
double VolumeMin()  { return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN); }
double VolumeMax()  { return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX); }

double RoundVolumeDown(double volume)
{
   double step = VolumeStep();
   int volumeDigits = (int)MathMax(0, MathRound(-MathLog10(step)));
   return NormalizeDouble(MathFloor(volume / step + 1e-9) * step, volumeDigits);
}

double NormalizeVolume(double volume)
{
   volume = RoundVolumeDown(volume);
   if(volume < VolumeMin()) volume = VolumeMin();
   if(volume > VolumeMax()) volume = VolumeMax();
   return volume;
}

//+------------------------------------------------------------------+
bool ModifyStopLoss(ulong ticket, double newStopLossPrice, bool isBuySide)
{
   double minStopDistance = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * pointSize;
   double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   newStopLossPrice = NormalizeDouble(newStopLossPrice, _Digits);
   if(isBuySide  && newStopLossPrice > bidPrice - minStopDistance) return false;
   if(!isBuySide && newStopLossPrice < askPrice + minStopDistance) return false;
   return tradeExecutor.PositionModify(ticket, newStopLossPrice, 0);
}

bool IsStopLossImprovement(double currentStopLossPrice, double newStopLossPrice, bool isBuySide)
{
   if(currentStopLossPrice == 0) return true;
   return isBuySide ? newStopLossPrice > currentStopLossPrice + pointSize / 2
                    : newStopLossPrice < currentStopLossPrice - pointSize / 2;
}

//+------------------------------------------------------------------+
bool ExecutePartialClose(ulong ticket, SPositionState &state)
{
   if(!PositionSelectByTicket(ticket)) return false;
   double currentLots = PositionGetDouble(POSITION_VOLUME);
   double closeLots   = RoundVolumeDown(currentLots * InpPartialClosePercentOfRemainingLots / 100.0);
   if(closeLots < VolumeMin()) closeLots = VolumeMin();

   if(currentLots - closeLots < VolumeMin() - 1e-9)   // would leave less than min lot: skip this step
   { state.partialsDone++; return true; }

   if(!tradeExecutor.PositionClosePartial(ticket, closeLots))
   { Print("Partial failed: ", tradeExecutor.ResultRetcodeDescription()); return false; }

   state.partialsDone++;
   return true;
}

//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      ulong ticket = PositionGetTicket(index);
      if(!IsOurPosition(ticket)) continue;
      int stateIndex = FindPositionStateIndex(ticket);
      if(stateIndex < 0) stateIndex = AddPositionState(ticket);
      ManageSinglePosition(ticket, positionStates[stateIndex]);
   }

   for(int stateIndex = ArraySize(positionStates) - 1; stateIndex >= 0; stateIndex--)
   {
      if(PositionSelectByTicket(positionStates[stateIndex].ticket)) continue;
      for(int shiftIndex = stateIndex; shiftIndex < ArraySize(positionStates) - 1; shiftIndex++)
         positionStates[shiftIndex] = positionStates[shiftIndex + 1];
      ArrayResize(positionStates, ArraySize(positionStates) - 1);
   }
}

void ManageSinglePosition(ulong ticket, SPositionState &state)
{
   if(!PositionSelectByTicket(ticket)) return;
   bool   isBuySide  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);

   // survival mode: no partials, trailing or recovery; the basket waits for break-even
   if(IsBasketInSurvivalMode(isBuySide)) return;

   double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double bidPrice   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double askPrice   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double exitPrice  = isBuySide ? bidPrice : askPrice;
   double currentProfitPoints = isBuySide ? (bidPrice - entryPrice) / pointSize
                                          : (entryPrice - askPrice) / pointSize;

   if(InpEnableDrawdownEntries && state.markedAsDrawdownEntry && !state.recoveryHandled &&
      currentProfitPoints >= InpRecoveryTriggerProfitPoints)
   {
      if(InpRecoveryAction == RECOVERY_CLOSE_ENTRY)
      {
         if(tradeExecutor.PositionClose(ticket)) state.recoveryHandled = true;
         return;
      }
      double recoveryStopPrice = isBuySide ? entryPrice + InpRecoveryStopOffsetBeyondEntryPoints * pointSize
                                           : entryPrice - InpRecoveryStopOffsetBeyondEntryPoints * pointSize;
      if(!IsStopLossImprovement(PositionGetDouble(POSITION_SL), recoveryStopPrice, isBuySide))
         state.recoveryHandled = true;
      else if(ModifyStopLoss(ticket, recoveryStopPrice, isBuySide))
         state.recoveryHandled = true;
   }

   double partialSpacingPoints = InpFinalPartialDistanceFromEntryPoints / InpPartialCloseCount;
   while(state.partialsDone < InpPartialCloseCount &&
         currentProfitPoints >= (state.partialsDone + 1) * partialSpacingPoints)
   {
      if(!ExecutePartialClose(ticket, state)) break;
      if(!PositionSelectByTicket(ticket)) return;
   }

   if(state.partialsDone >= InpPartialCloseCount && !state.trailingActive)
   {
      state.trailingActive = true;
      state.trailReferencePrice = exitPrice;
      double initialTrailStopPrice = isBuySide ? bidPrice - InpTrailingStopDistanceBehindPricePoints * pointSize
                                               : askPrice + InpTrailingStopDistanceBehindPricePoints * pointSize;
      if(IsStopLossImprovement(PositionGetDouble(POSITION_SL), initialTrailStopPrice, isBuySide))
         ModifyStopLoss(ticket, initialTrailStopPrice, isBuySide);
      return;
   }

   if(state.trailingActive)
   {
      double priceAdvancePoints = isBuySide ? (bidPrice - state.trailReferencePrice) / pointSize
                                            : (state.trailReferencePrice - askPrice) / pointSize;
      if(priceAdvancePoints >= InpTrailingStopMinPriceAdvancePoints)
      {
         double newTrailStopPrice = isBuySide ? bidPrice - InpTrailingStopDistanceBehindPricePoints * pointSize
                                              : askPrice + InpTrailingStopDistanceBehindPricePoints * pointSize;
         if(IsStopLossImprovement(PositionGetDouble(POSITION_SL), newTrailStopPrice, isBuySide)
            && ModifyStopLoss(ticket, newTrailStopPrice, isBuySide))
            state.trailReferencePrice = exitPrice;
      }
   }
}
