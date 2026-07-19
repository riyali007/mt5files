//+------------------------------------------------------------------+
//|  BacktestORB_EA.mq5                                             |
//|  BacktestBridge v3.0 + ORB SMC Strategy (Visual Only)          |
//|  Combines: AIV Manual Backtesting Panel + Riy ORB SMC EA       |
//|  ORB: No auto-trading, no TP/SL from ORB side.                 |
//|  Trades are placed manually via WPF panel (BUY/SELL commands). |
//+------------------------------------------------------------------+
#property copyright "Riy Ali / AIV"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include "Inputs.mqh"
#include "Structs.mqh"
#include "BridgeLogic.mqh"
#include "ORBLogic.mqh"

//=== BRIDGE BAR TIME (separate from ORB bar time) =============
datetime g_bridgeLastBarTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
    // ── Bridge init ──────────────────────────────────────────
    g_lotSize      = InpLotSize;
    g_sl           = InpSL;
    g_totalTP      = InpTotalTP;
    g_tpLevels     = InpTPLevels;
    g_deviation    = InpDeviation;
    g_beAfterLevel = InpBEAfterLevel;
    g_beOffsetPts  = InpBEOffsetPts;

    g_trade.SetExpertMagicNumber(202600);
    g_trade.SetDeviationInPoints(g_deviation);
    g_trade.SetTypeFilling(ORDER_FILLING_IOC);
    g_sym.Name(_Symbol);

    ArrayInitialize(g_lastPivotHighs,     0);
    ArrayInitialize(g_lastPivotLows,      0);
    ArrayInitialize(g_lastPivotHighTimes, 0);
    ArrayInitialize(g_lastPivotLowTimes,  0);

    // ── ORB init ─────────────────────────────────────────────
    if(!ORB_Init()) return INIT_FAILED;

    // ── Theme ────────────────────────────────────────────────
    ApplyDarkTheme();

    // ── Timer (live mode only) ───────────────────────────────
    bool inTester = (bool)MQLInfoInteger(MQL_TESTER);
    if(!inTester) EventSetMillisecondTimer(50);

    Print("BacktestORB EA v1.00 initialized");
    Print("TradePacket size=",       sizeof(TradePacket),       " expected=81");
    Print("TradeResultPacket size=", sizeof(TradeResultPacket), " expected=77");
    Print("CommandPacket size=",     sizeof(CommandPacket),     " expected=89");

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    ORB_Deinit();
    RemoveAllLines();
    RestoreDefaultTheme();

    string name = "AIV_CandleTimer";
    ObjectDelete(0, name);

    if(g_pipeHandle != INVALID_HANDLE) {
        FileClose(g_pipeHandle);
        g_pipeHandle = INVALID_HANDLE;
    }

    bool inTester = (bool)MQLInfoInteger(MQL_TESTER);
    if(!inTester) EventKillTimer();
}

//+------------------------------------------------------------------+
// Strategy Tester mode: OnTick drives everything
void OnTick()
{
    bool inTester = (bool)MQLInfoInteger(MQL_TESTER);
    if(!inTester) return;

    g_sym.RefreshRates();
    CheckPartials();
    UpdateCandleTimer();

    // ── ORB: scan on new bar ───────────────────────────────
    datetime orbBarTime = iTime(_Symbol, _Period, 0);
    if(orbBarTime != g_orbLastBarTime) {
        g_orbLastBarTime = orbBarTime;
        ORB_OnNewBar();
    }

    // ── Bridge: pattern detect on new bar ─────────────────
    datetime bridgeBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
    if(bridgeBarTime != g_bridgeLastBarTime) {
        g_bridgeLastBarTime = bridgeBarTime;
        DetectPatterns();
    }

    // ── Pivot lines ───────────────────────────────────────
    UpdatePivotLines();

    // ── Pipe throttle ─────────────────────────────────────
    uint now = GetTickCount();
    if((now - g_lastTick) < 50) return;
    g_lastTick = now;

    ProcessPipe();
}

//+------------------------------------------------------------------+
// Live / Visual mode: Timer drives everything
void OnTimer()
{
    bool inTester = (bool)MQLInfoInteger(MQL_TESTER);
    if(inTester) return;

    g_sym.RefreshRates();
    CheckPartials();
    UpdateCandleTimer();

    // ── ORB: scan on new bar ───────────────────────────────
    datetime orbBarTime = iTime(_Symbol, _Period, 0);
    if(orbBarTime != g_orbLastBarTime) {
        g_orbLastBarTime = orbBarTime;
        ORB_OnNewBar();
    }

    // ── Bridge: pattern detect on new bar ─────────────────
    datetime bridgeBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
    if(bridgeBarTime != g_bridgeLastBarTime) {
        g_bridgeLastBarTime = bridgeBarTime;
        DetectPatterns();
    }

    UpdatePivotLines();
    ProcessPipe();
}
