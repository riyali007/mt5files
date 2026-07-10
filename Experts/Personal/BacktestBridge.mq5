//+------------------------------------------------------------------+
//|  BacktestBridge.mq5 - AIV Manual Backtesting Panel v3.0         |
//|  Bridge between MT5 Strategy Tester and WPF Control Panel       |
//+------------------------------------------------------------------+
#property copyright "AIV"
#property version   "3.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//--- Input Parameters
input double InpLotSize    = 0.10;
input int    InpSL         = 200;
input int    InpTotalTP    = 400;
input int    InpTPLevels   = 3;
input int    InpDeviation  = 50;
input string InpPipeName   = "\\\\.\\pipe\\AIVBacktest";

// ── Partial TP + BE settings ──────────────────────────────────────
input bool   InpAutoPartials  = true;   // Enable auto partial closes
input int    InpBEAfterLevel  = 1;      // Move SL to BE after which TP level hit (1-5)
input int    InpBEOffsetPts   = 5;      // Extra points above/below entry for BE SL

// ── Pattern Detection Settings ────────────────────────────────────
input color InpBearBoxColor     = C'234,84,85';   // Bearish box color
input color InpBullBoxColor     = C'0,188,168';   // Bullish box color
input int   InpBoxOpacity       = 15;             // Fill opacity 0-255 (visual only)
input int   InpMinCandlesInBox  = 2;              // Min candles inside box to confirm (2-3)
input int   InpCandleLookback   = 20;             // How many bars back to check for candles inside box

// ── Pivot High/Low Settings ───────────────────────────────────────
input ENUM_TIMEFRAMES InpPivotTimeframe  = PERIOD_M15;  // Timeframe for pivot detection
input int             InpPivotLeftBars   = 5;          // Bars to left of pivot
input int             InpPivotRightBars  = 5;          // Bars to right of pivot
input int             InpPivotMaxLookback = 200;       // Max bars to scan for pivots
input color           InpPivotHighColor  = C'234,84,85';  // Pivot High line color
input color           InpPivotLowColor   = C'0,188,168';  // Pivot Low line color
input int             InpPivotLineWidth  = 2;          // Line width 1-5
input ENUM_LINE_STYLE InpPivotLineStyle  = STYLE_SOLID; // Line style


//--- Packet Type Constants (uchar)
#define PKT_TICK       1
#define PKT_TRADE      2
#define PKT_POSITIONS  3
#define PKT_LOG        4
#define PKT_STATUS     5
#define PKT_TRADE_RESULT  6


//--- Command Type Constants (uchar)
#define CMD_NONE       0
#define CMD_START      1
#define CMD_PAUSE      2
#define CMD_RESUME     3
#define CMD_BUY        4
#define CMD_SELL       5
#define CMD_CLOSE      6
#define CMD_CLOSE_ALL  7
#define CMD_SET_PARAMS 8
#define CMD_SET_SL_BE    9
#define CMD_TAKE_PARTIAL 10
#define PIPE_TIMEOUT_MS 3000  // reconnect if no reply in 3 seconds
// ── New drawing commands ──────────────────────────────────────
#define CMD_DRAW_HLINE     11
#define CMD_DRAW_TLINE     12
#define CMD_DRAW_RAY       13
#define CMD_CLEAR_DRAWINGS 14
#define CMD_PREVIEW_LIMIT   15
#define CMD_PLACE_LIMIT     16
#define CMD_CANCEL_PREVIEW  17
#define CMD_CANCEL_LIMIT  18



//--- Structs (no #pragma pack needed — MQL5 structs are sequential by default)
struct TickPacket {
    uchar  PacketType;
    double Bid;
    double Ask;
    double Spread;
    double OpenPL;
    double Balance;
    double Equity;
    long   ServerTime;
};

struct TradePacket {
    uchar    PacketType;    // 1 byte
    ulong    Ticket;        // 8 bytes
    int      PositionType;  // 4 bytes
    double   Volume;        // 8 bytes
    double   OpenPrice;     // 8 bytes
    double   CurrentPrice;  // 8 bytes
    double   SL;            // 8 bytes
    double   TP;            // 8 bytes
    double   Profit;        // 8 bytes
    char     Symbol[20];    // 20 bytes
                            // Total = 81 bytes ✓
};

struct PositionsCountPacket {
    uchar  PacketType;
    int    Count;
};

struct StatusPacket {
    uchar  PacketType;
    uchar  IsPaused;
    double LotSize;
    int    SL;
    int    TotalTP;
    int    TPLevels;
    int    DevPoints;      // renamed from Deviation to avoid CTrade conflict
};

struct LogPacket {
    uchar  PacketType;
    char   Message[200];
};

struct CommandPacket {
    uchar    CmdType;
    double   LotSize;
    int      SL;
    int      TotalTP;
    int      TPLevels;
    int      DevPoints;
    ulong    TicketToClose;
    int      BEAfterLevel;
    int      BEOffsetPoints;
    double   PartialPercent;
    double   DrawPrice1;
    double   DrawPrice2;
    int      DrawColor;
    int      DrawStyle;
    int      DrawWidth;
    double   LimitPrice;       // ← new
    int      OrderDirection;   // ← new: 0=BuyLimit 1=SellLimit
                               // Total = 89 bytes
};

// Track which partial levels have been hit per ticket
struct PartialState {
    ulong  Ticket;
    int    LevelsHit;        // how many TP levels already closed
    bool   BESet;            // has SL been moved to BE
    double EntryPrice;
    int    PositionType;     // POSITION_TYPE_BUY or POSITION_TYPE_SELL
    double OriginalVolume;   // volume at entry
};

PartialState g_partials[];   // dynamic array of open position states

struct TradeResultPacket {
    uchar    PacketType;
    ulong    Ticket;
    int      TradeType;
    double   EntryPrice;
    double   ExitPrice;
    double   Volume;
    double   Profit;
    double   SL;
    double   TP;
    uchar    HitSL;
    uchar    HitTP;
    uchar    IsPartial;
    uchar    BEWasSet;
    // ← datetime EntryTime / ExitTime REMOVED
    char     Symbol[20];
    // Total = 77 bytes
};



//--- Global Objects (declared after structs)
CTrade      g_trade;
CSymbolInfo g_sym;

//--- Global State Variables
int    g_pipeHandle  = INVALID_HANDLE;
bool   g_isPaused    = true;
double g_lotSize;
int    g_sl;
int    g_totalTP;
int    g_tpLevels;
int    g_deviation;
uint   g_lastTick    = 0;
// After the input declarations, add:
int g_beAfterLevel = InpBEAfterLevel;   // runtime configurable from WPF
int g_beOffsetPts  = InpBEOffsetPts;    // runtime configurable from WPF
uint g_lastReplyTime = 0;


// Add this global at the top with other globals:
datetime g_lastBarTime = 0;
int g_patternCounter = 0;
int g_lastPatternBar = 0;

// ── Pivot tracking globals ────────────────────────────────────────
double   g_lastPivotHighs[2];   // last 2 pivot high prices
double   g_lastPivotLows[2];    // last 2 pivot low prices
datetime g_lastPivotHighTimes[2];
datetime g_lastPivotLowTimes[2];
datetime g_lastPivotBarTime = 0; // throttle — only recalc on new bar

// ── Preview state ─────────────────────────────────────────────────
bool   g_previewActive    = false;
int    g_previewDirection = 0;      // 0=BuyLimit 1=SellLimit
double g_previewLotSize   = 0;
int    g_previewSL        = 0;
int    g_previewTP        = 0;


//+------------------------------------------------------------------+
int OnInit() {
    g_lotSize   = InpLotSize;
    g_sl        = InpSL;
    g_totalTP   = InpTotalTP;
    g_tpLevels  = InpTPLevels;
    g_deviation = InpDeviation;

    g_trade.SetExpertMagicNumber(202600);
    g_trade.SetDeviationInPoints(g_deviation);
    g_trade.SetTypeFilling(ORDER_FILLING_IOC);
    g_sym.Name(_Symbol);

    ApplyDarkTheme(); // ← add this
    // Add inside OnInit() after existing initializations:
    ArrayInitialize(g_lastPivotHighs,      0);
    ArrayInitialize(g_lastPivotLows,       0);
    ArrayInitialize(g_lastPivotHighTimes,  0);
    ArrayInitialize(g_lastPivotLowTimes,   0);


    bool inTester = (bool)MQLInfoInteger(MQL_TESTER);
    if(!inTester) EventSetMillisecondTimer(50);

    Print("BacktestBridge v3.0 initialized. Pipe: ", InpPipeName);
    Print("TradePacket size=", sizeof(TradePacket)," expected=81");
    Print("TradeResultPacket size=", sizeof(TradeResultPacket)," expected=77");
    Print("CommandPacket size=", sizeof(CommandPacket), " expected=89");


    return INIT_SUCCEEDED;
}


//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    RemoveAllLines();
    RestoreDefaultTheme(); // ← restore on EA remove

    if(g_pipeHandle != INVALID_HANDLE) {
        FileClose(g_pipeHandle);
        g_pipeHandle = INVALID_HANDLE;
    }
    bool inTester = (bool)MQLInfoInteger(MQL_TESTER);
    if(!inTester) EventKillTimer();
}


//+------------------------------------------------------------------+
// Strategy Tester: OnTick drives everything (OnTimer unreliable in tester)

void OnTick() {
    bool inTester = (bool)MQLInfoInteger(MQL_TESTER);
    if(!inTester) return;

    g_sym.RefreshRates();
    CheckPartials();
    UpdateCandleTimer();

    // ── Per new bar on CURRENT timeframe ──────────────────────
    datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
    if(currentBarTime != g_lastBarTime) {
        g_lastBarTime = currentBarTime;
        DetectPatterns();
    }

    // ── Per new bar on PIVOT timeframe ────────────────────────
    UpdatePivotLines(); // internally throttled to pivot TF bar open

    // ── Pipe cycle throttle ───────────────────────────────────
    uint now = GetTickCount();
    if((now - g_lastTick) < 50) return;
    g_lastTick = now;

    ProcessPipe();
}



//+------------------------------------------------------------------+
// Live/Visual mode: Timer drives everything
void OnTimer() {
    bool inTester = (bool)MQLInfoInteger(MQL_TESTER);
    if(inTester) return;

    g_sym.RefreshRates();
    UpdateCandleTimer();
    UpdatePivotLines();
    ProcessPipe();
}


//+------------------------------------------------------------------+
void ProcessPipe() {
    if(g_pipeHandle == INVALID_HANDLE) {
        g_pipeHandle = FileOpen(InpPipeName,
            FILE_READ | FILE_WRITE | FILE_BIN | FILE_ANSI);
        if(g_pipeHandle == INVALID_HANDLE) return;
        Print("WPF Connected.");
        g_lastReplyTime = GetTickCount();
        SendStatus();
        return;
    }

    // ── Timeout guard ──────────────────────────────────────────
    if(GetTickCount() - g_lastReplyTime > PIPE_TIMEOUT_MS) {
        Print("Pipe timeout — reconnecting.");
        FileClose(g_pipeHandle);
        g_pipeHandle = INVALID_HANDLE;
        return;
    }

    // ── Step 1: Send tick data ─────────────────────────────────
    SendTickData();

    // ── Step 2: Read command reply IMMEDIATELY after tick ──────
    // This is the ONLY read. Happens every cycle. Always unblocks.
    CommandPacket cmd;
    uint read = FileReadStruct(g_pipeHandle, cmd);

      if(read != sizeof(CommandPacket)) {
          Print("Bad cmd read=", read,
                " expected=", sizeof(CommandPacket),
                " — reconnecting.");
          FileClose(g_pipeHandle);
          g_pipeHandle = INVALID_HANDLE;
          return;
      }


    g_lastReplyTime = GetTickCount();

    // ── Step 3: Execute command if any ────────────────────────
    if(cmd.CmdType != CMD_NONE) {
        Print("CMD: ", (int)cmd.CmdType);
        ProcessCommand(cmd);
    }

    // ── Step 4: Send positions AFTER command exchange ──────────
    // Positions are extra data — sent after the handshake completes
    SendPositions();
    FileFlush(g_pipeHandle);
}


//+------------------------------------------------------------------+
void SendTickData() {
    double openPL = 0.0;
    for(int i = 0; i < PositionsTotal(); i++) {
        CPositionInfo pos;
        if(pos.SelectByIndex(i)) openPL += pos.Profit();
    }

    TickPacket pkt;
    pkt.PacketType = PKT_TICK;
    pkt.Bid        = g_sym.Bid();
    pkt.Ask        = g_sym.Ask();
    pkt.Spread     = (double)g_sym.Spread(); // send in points, not price
    pkt.OpenPL     = openPL;
    pkt.Balance    = AccountInfoDouble(ACCOUNT_BALANCE);
    pkt.Equity     = AccountInfoDouble(ACCOUNT_EQUITY);
    pkt.ServerTime = (long)TimeCurrent();

    FileWriteStruct(g_pipeHandle, pkt);
}

//+------------------------------------------------------------------+
void SendPositions() {
    PositionsCountPacket cntPkt;
    cntPkt.PacketType = PKT_POSITIONS;
    cntPkt.Count      = PositionsTotal();
    FileWriteStruct(g_pipeHandle, cntPkt);

    for(int i = 0; i < PositionsTotal(); i++) {
        CPositionInfo pos;
        if(!pos.SelectByIndex(i)) continue;

        TradePacket pkt;
        pkt.PacketType   = PKT_TRADE;
        pkt.Ticket       = pos.Ticket();

        // Explicit cast — 0=BUY, 1=SELL
        ENUM_POSITION_TYPE posType = pos.PositionType();
        pkt.PositionType = (posType == POSITION_TYPE_BUY) ? 0 : 1;

        pkt.Volume       = pos.Volume();
        pkt.OpenPrice    = pos.PriceOpen();
        pkt.CurrentPrice = pos.PriceCurrent();
        pkt.SL           = pos.StopLoss();
        pkt.TP           = pos.TakeProfit();
        pkt.Profit       = pos.Profit();

        // Safe symbol copy
        int symLen = StringLen(pos.Symbol());
        if(symLen > 19) symLen = 19;
        for(int c = 0; c < symLen; c++)
            pkt.Symbol[c] = (char)StringGetCharacter(pos.Symbol(), c);
        pkt.Symbol[symLen] = 0;

        FileWriteStruct(g_pipeHandle, pkt);
    }
}


//+------------------------------------------------------------------+
void SendStatus() {
    StatusPacket spkt;
    spkt.PacketType = PKT_STATUS;
    spkt.IsPaused   = g_isPaused ? 1 : 0;
    spkt.LotSize    = g_lotSize;
    spkt.SL         = g_sl;
    spkt.TotalTP    = g_totalTP;
    spkt.TPLevels   = g_tpLevels;
    spkt.DevPoints  = g_deviation;
    FileWriteStruct(g_pipeHandle, spkt);
    FileFlush(g_pipeHandle);

    CommandPacket reply;
    uint read = FileReadStruct(g_pipeHandle, reply);
    Print("SendStatus reply read=", read,
          " expected=", sizeof(CommandPacket));
}



//+------------------------------------------------------------------+
void WriteLog(string msg) {
    Print(msg); // always goes to MT5 Journal correctly
    if(g_pipeHandle == INVALID_HANDLE) return;

    LogPacket lpkt;
    lpkt.PacketType = PKT_LOG;

    // Safe ASCII copy — avoids all encoding issues
    int len = StringLen(msg);
    if(len > 199) len = 199;
    for(int i = 0; i < len; i++) {
        lpkt.Message[i] = (char)StringGetCharacter(msg, i);
    }
    lpkt.Message[len] = 0; // null terminate

    FileWriteStruct(g_pipeHandle, lpkt);
    FileFlush(g_pipeHandle);

    // Consume the immediate C# heartbeat reply to keep pipe in sync
    CommandPacket reply;
    FileReadStruct(g_pipeHandle, reply);
}


//+------------------------------------------------------------------+
void ProcessCommand(CommandPacket &cmd) {
    int cmdType = (int)cmd.CmdType;
    if(cmdType == CMD_NONE) return;

    Print("CMD type=",  cmdType,
          " Lot=",      cmd.LotSize,
          " SL=",       cmd.SL,
          " TP=",       cmd.TotalTP,
          " Levels=",   cmd.TPLevels,
          " Dev=",      cmd.DevPoints,
          " BELevel=",  cmd.BEAfterLevel,
          " BEOffset=", cmd.BEOffsetPoints,
          " Partial%=", cmd.PartialPercent,
          " Ticket=",   cmd.TicketToClose);

    // Always update globals from every command that carries params
    // so globals stay in sync for auto-partials and BE
    if(cmd.LotSize        > 0)  g_lotSize     = cmd.LotSize;
    if(cmd.SL             > 0)  g_sl          = cmd.SL;
    if(cmd.TotalTP        > 0)  g_totalTP     = cmd.TotalTP;
    if(cmd.TPLevels       > 0)  g_tpLevels    = cmd.TPLevels;
    if(cmd.DevPoints      > 0)  g_deviation   = cmd.DevPoints;
    if(cmd.BEAfterLevel   > 0)  g_beAfterLevel = cmd.BEAfterLevel;
    if(cmd.BEOffsetPoints > 0)  g_beOffsetPts = cmd.BEOffsetPoints;

    g_trade.SetDeviationInPoints(g_deviation);

    if(cmdType == CMD_START) {
        g_isPaused = false;
        WriteLog("Backtest STARTED");
        SendStatus();
    }
    else if(cmdType == CMD_PAUSE) {
        g_isPaused = true;
        WriteLog("Backtest PAUSED");
        SendStatus();
    }
    else if(cmdType == CMD_RESUME) {
        g_isPaused = false;
        WriteLog("Backtest RESUMED");
        SendStatus();
    }
    else if(cmdType == CMD_BUY) {
        if(!g_isPaused)
            ExecuteBuy();
        else
            WriteLog("Cannot BUY - EA is paused");
    }
    else if(cmdType == CMD_SELL) {
        if(!g_isPaused)
            ExecuteSell();
        else
            WriteLog("Cannot SELL - EA is paused");
    }
    else if(cmdType == CMD_CLOSE) {
        ClosePositionByTicket(cmd.TicketToClose);
    }
    else if(cmdType == CMD_CLOSE_ALL) {
        CloseAllPositions();
    }
    else if(cmdType == CMD_SET_PARAMS) {
        WriteLog("Params updated: Lot=" + DoubleToString(g_lotSize, 2) +
                 " SL="    + IntegerToString(g_sl) +
                 " TP="    + IntegerToString(g_totalTP) +
                 " Levels="+ IntegerToString(g_tpLevels));
        SendStatus();
    }
    else if(cmdType == CMD_SET_SL_BE) {
        if(cmd.TicketToClose > 0)
            ManualSetBE(cmd.TicketToClose, cmd.BEOffsetPoints);
        else {
            for(int i = 0; i < PositionsTotal(); i++) {
                CPositionInfo pos;
                if(pos.SelectByIndex(i))
                    ManualSetBE(pos.Ticket(), cmd.BEOffsetPoints);
            }
        }
    }
    else if(cmdType == CMD_TAKE_PARTIAL) {
        double pct = cmd.PartialPercent;
        if(pct <= 0 || pct > 100) pct = 50.0;
        if(cmd.TicketToClose > 0)
            ManualPartialClose(cmd.TicketToClose, pct);
        else {
            for(int i = PositionsTotal() - 1; i >= 0; i--) {
                CPositionInfo pos;
                if(pos.SelectByIndex(i))
                    ManualPartialClose(pos.Ticket(), pct);
            }
        }
    }
    else if(cmdType == CMD_DRAW_HLINE) {
       DrawFreeHLine(cmd.DrawPrice1, cmd.DrawColor,
                     cmd.DrawStyle, cmd.DrawWidth);
      }
      else if(cmdType == CMD_DRAW_TLINE) {
          DrawFreeTLine(cmd.DrawPrice1, cmd.DrawPrice2,
                        cmd.DrawColor, cmd.DrawStyle, cmd.DrawWidth);
      }
      else if(cmdType == CMD_CLEAR_DRAWINGS) {
          ClearFreeDrawings();
      }
    else if(cmdType == CMD_PREVIEW_LIMIT) {
          DrawLimitPreview(cmd.LimitPrice,
                           cmd.OrderDirection,
                           cmd.LotSize > 0 ? cmd.LotSize : g_lotSize,
                           cmd.SL      > 0 ? cmd.SL      : g_sl,
                           cmd.TotalTP > 0 ? cmd.TotalTP  : g_totalTP);
    }
    else if(cmdType == CMD_PLACE_LIMIT) {
        PlaceLimitOrder();
    }
    else if(cmdType == CMD_CANCEL_PREVIEW) {
        CancelPreview();
    }
    else if(cmdType == CMD_CANCEL_LIMIT) {
      CancelLimitOrder(cmd.TicketToClose); // 0 = cancel all
    }


}


//+------------------------------------------------------------------+
void ExecuteBuy() {
    if(!IsMarketOpen()) {
        WriteLog("BUY skipped - market closed");
        return;
    }

    g_sym.RefreshRates();
    double ask     = g_sym.Ask();
    double slPrice = NormalizeDouble(ask - g_sl      * _Point, _Digits);
    double tpPrice = NormalizeDouble(ask + g_totalTP * _Point, _Digits);

    // Log EXACTLY what we are about to send
    Print("ExecuteBuy: g_lotSize=", g_lotSize,
          " g_sl=",                 g_sl,
          " g_totalTP=",            g_totalTP,
          " ask=",                  ask,
          " slPrice=",              slPrice,
          " tpPrice=",              tpPrice);

    if(g_trade.Buy(g_lotSize, _Symbol, ask, slPrice, tpPrice, "AIV_BUY")) {
        ulong ticket = g_trade.ResultOrder();
        WriteLog("BUY OK #" + IntegerToString(ticket) +
                 " Lot="   + DoubleToString(g_lotSize, 2) +
                 " @ "     + DoubleToString(ask, _Digits));
        DrawPartialLines(ticket, POSITION_TYPE_BUY, ask);
        RegisterPosition(ticket, POSITION_TYPE_BUY, ask, g_lotSize);
    } else {
        WriteLog("BUY failed [" +
                 IntegerToString(g_trade.ResultRetcode()) + "]: " +
                 g_trade.ResultComment());
    }
}

void ExecuteSell() {
    if(!IsMarketOpen()) {
        WriteLog("SELL skipped - market closed");
        return;
    }

    g_sym.RefreshRates();
    double bid     = g_sym.Bid();
    double slPrice = NormalizeDouble(bid + g_sl      * _Point, _Digits);
    double tpPrice = NormalizeDouble(bid - g_totalTP * _Point, _Digits);

    Print("ExecuteSell: g_lotSize=", g_lotSize,
          " g_sl=",                  g_sl,
          " g_totalTP=",             g_totalTP,
          " bid=",                   bid,
          " slPrice=",               slPrice,
          " tpPrice=",               tpPrice);

    if(g_trade.Sell(g_lotSize, _Symbol, bid, slPrice, tpPrice, "AIV_SELL")) {
        ulong ticket = g_trade.ResultOrder();
        WriteLog("SELL OK #" + IntegerToString(ticket) +
                 " Lot="    + DoubleToString(g_lotSize, 2) +
                 " @ "      + DoubleToString(bid, _Digits));
        DrawPartialLines(ticket, POSITION_TYPE_SELL, bid);
        RegisterPosition(ticket, POSITION_TYPE_SELL, bid, g_lotSize);
    } else {
        WriteLog("SELL failed [" +
                 IntegerToString(g_trade.ResultRetcode()) + "]: " +
                 g_trade.ResultComment());
    }
}



//+------------------------------------------------------------------+
void ClosePositionByTicket(ulong ticket) {
    CPositionInfo pos;
    if(pos.SelectByTicket(ticket)) {
        if(g_trade.PositionClose(ticket, g_deviation)) {
            WriteLog("Closed #" + IntegerToString(ticket));
            RemovePartialLines(ticket);
            UnregisterPosition(ticket); // ← unregister
        } else {
            WriteLog("Close failed #" + IntegerToString(ticket) +
                     " [" + IntegerToString(g_trade.ResultRetcode()) + "]");
        }
    }
}

void CloseAllPositions() {
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        CPositionInfo pos;
        if(pos.SelectByIndex(i)) {
            ulong ticket = pos.Ticket();
            if(g_trade.PositionClose(ticket, g_deviation)) {
                RemovePartialLines(ticket);
                UnregisterPosition(ticket); // ← unregister
            }
        }
    }
    WriteLog("All positions closed.");
}

//+------------------------------------------------------------------+


// Add this helper function
bool IsMarketOpen() {
    // Check if trading is allowed right now for this symbol
    datetime now = TimeCurrent();
    
    MqlTick lastTick;
    if(!SymbolInfoTick(_Symbol, lastTick)) return false;
    
    // Check symbol trade mode
    ENUM_SYMBOL_TRADE_MODE tradeMode = 
        (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
    
    if(tradeMode == SYMBOL_TRADE_MODE_DISABLED) {
        WriteLog("Market DISABLED for " + _Symbol);
        return false;
    }
    if(tradeMode == SYMBOL_TRADE_MODE_CLOSEONLY) {
        WriteLog("Market CLOSE ONLY for " + _Symbol);
        return false;
    }
    
    // Check if spread is abnormal (another sign market is closed)
    double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
    if(spread > 50 * _Point) {
        WriteLog("Spread too wide - market likely closed: " + 
                 DoubleToString(spread / _Point, 0) + " pts");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
// Draw partial TP lines for an open position
//+------------------------------------------------------------------+

void DrawPartialLines(ulong ticket, int posType, double entryPrice) {
    if(g_tpLevels < 1) return;

    double direction = (posType == POSITION_TYPE_BUY) ? 1.0 : -1.0;

    // ── TP level lines ────────────────────────────────────────
    for(int i = 1; i <= g_tpLevels; i++) {
        double tpStep  = (double)g_totalTP / g_tpLevels;
        double tpPrice = NormalizeDouble(
            entryPrice + direction * tpStep * i * _Point, _Digits
        );
        string name  = "AIV_TP_" + IntegerToString(ticket) +
                       "_"       + IntegerToString(i);
        int    pct   = 100 / g_tpLevels;
        string label = "TP" + IntegerToString(i) +
                       "  +" + IntegerToString((int)(tpStep * i)) +
                       " pts (" + IntegerToString(pct) + "%)";

        ObjectDelete(0, name);
        ObjectCreate(0, name, OBJ_HLINE, 0, 0, tpPrice);
        ObjectSetInteger(0, name, OBJPROP_COLOR,      clrLimeGreen);
        ObjectSetInteger(0, name, OBJPROP_STYLE,      STYLE_DASH);
        ObjectSetInteger(0, name, OBJPROP_WIDTH,      1);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);  // ← draggable
        ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
        ObjectSetInteger(0, name, OBJPROP_BACK,       true);
        ObjectSetString (0, name, OBJPROP_TEXT,       label);
        ObjectSetString (0, name, OBJPROP_TOOLTIP,    "Drag to move TP" +
                         IntegerToString(i));
    }

    // ── SL line — draggable ───────────────────────────────────
    string slName  = "AIV_SL_" + IntegerToString(ticket);
    double slPrice = NormalizeDouble(
        entryPrice - direction * g_sl * _Point, _Digits
    );
    ObjectDelete(0, slName);
    ObjectCreate(0, slName, OBJ_HLINE, 0, 0, slPrice);
    ObjectSetInteger(0, slName, OBJPROP_COLOR,      clrTomato);
    ObjectSetInteger(0, slName, OBJPROP_STYLE,      STYLE_DASH);
    ObjectSetInteger(0, slName, OBJPROP_WIDTH,      2);       // thicker = easier to grab
    ObjectSetInteger(0, slName, OBJPROP_SELECTABLE, true);    // ← draggable
    ObjectSetInteger(0, slName, OBJPROP_SELECTED,   false);
    ObjectSetInteger(0, slName, OBJPROP_BACK,       true);
    ObjectSetString (0, slName, OBJPROP_TEXT,       "SL  -" +
                     IntegerToString(g_sl) + " pts");
    ObjectSetString (0, slName, OBJPROP_TOOLTIP,    "Drag to move Stop Loss");

    // ── Entry line — NOT draggable ────────────────────────────
    string entryName = "AIV_ENTRY_" + IntegerToString(ticket);
    ObjectDelete(0, entryName);
    ObjectCreate(0, entryName, OBJ_HLINE, 0, 0, entryPrice);
    ObjectSetInteger(0, entryName, OBJPROP_COLOR,      clrDodgerBlue);
    ObjectSetInteger(0, entryName, OBJPROP_STYLE,      STYLE_DOT);
    ObjectSetInteger(0, entryName, OBJPROP_WIDTH,      1);
    ObjectSetInteger(0, entryName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, entryName, OBJPROP_BACK,       true);
    ObjectSetString (0, entryName, OBJPROP_TEXT,       "ENTRY @ " +
                     DoubleToString(entryPrice, _Digits));

    ChartRedraw(0);
}
//+------------------------------------------------------------------+
// Remove all lines for a specific ticket
//+------------------------------------------------------------------+
void RemovePartialLines(ulong ticket) {
    for(int i = 1; i <= 5; i++) {
        string lineName = "AIV_TP_" + IntegerToString(ticket) +
                          "_" + IntegerToString(i);
        ObjectDelete(0, lineName);
    }
    ObjectDelete(0, "AIV_SL_"    + IntegerToString(ticket));
    ObjectDelete(0, "AIV_ENTRY_" + IntegerToString(ticket));
    ChartRedraw(0);
}

//+------------------------------------------------------------------+
// Remove ALL AIV lines (called on deinit)
//+------------------------------------------------------------------+
void RemoveAllLines() {
    int total = ObjectsTotal(0);
    for(int i = total - 1; i >= 0; i--) {
        string name = ObjectName(0, i);
        if(StringFind(name, "AIV_") == 0)
            ObjectDelete(0, name);
    }
    ChartRedraw(0);
}
//+------------------------------------------------------------------+
// Apply dark theme to MT5 chart — matches attached image exactly
//+------------------------------------------------------------------+
void ApplyDarkTheme() {
    long chart = ChartID();

    // ── Background ────────────────────────────────────────────────
    ChartSetInteger(chart, CHART_COLOR_BACKGROUND,    clrBlack);
    ChartSetInteger(chart, CHART_COLOR_FOREGROUND,    C'180,180,180'); // axis text

    // ── Candle colors ─────────────────────────────────────────────
    ChartSetInteger(chart, CHART_COLOR_CANDLE_BULL,   C'0,188,168');   // teal  (bullish body)
    ChartSetInteger(chart, CHART_COLOR_CANDLE_BEAR,   C'234,84,85');   // coral (bearish body)
    ChartSetInteger(chart, CHART_COLOR_CHART_UP,      C'0,188,168');   // teal  (bullish wick)
    ChartSetInteger(chart, CHART_COLOR_CHART_DOWN,    C'234,84,85');   // coral (bearish wick)

    // ── Chart line (if line mode used) ────────────────────────────
    ChartSetInteger(chart, CHART_COLOR_CHART_LINE,    C'0,188,168');

    // ── Grid — remove it ─────────────────────────────────────────
    ChartSetInteger(chart, CHART_SHOW_GRID,           false);

    // ── Volume bars ───────────────────────────────────────────────
    ChartSetInteger(chart, CHART_COLOR_VOLUME,        C'0,120,100');
    ChartSetInteger(chart, CHART_SHOW_VOLUMES,        false); // hide by default

    // ── Ask line ──────────────────────────────────────────────────
    ChartSetInteger(chart, CHART_SHOW_ASK_LINE,       true);
    ChartSetInteger(chart, CHART_COLOR_ASK,           C'0,188,168');

    // ── Bid line ──────────────────────────────────────────────────
    ChartSetInteger(chart, CHART_COLOR_BID,           C'234,84,85');

    // ── Stop levels ───────────────────────────────────────────────
    ChartSetInteger(chart, CHART_COLOR_STOP_LEVEL,    C'255,160,0');

    // ── Crosshair / mouse line ────────────────────────────────────
    ChartSetInteger(chart, CHART_COLOR_LAST,          C'100,100,100');

    // ── No border ─────────────────────────────────────────────────
    ChartSetInteger(chart, CHART_SHOW_OHLC,           false);
    ChartSetInteger(chart, CHART_SHOW_BID_LINE,       true);
    ChartSetInteger(chart, CHART_SHOW_PERIOD_SEP,     false); // no period separators

    // ── Candle chart mode ─────────────────────────────────────────
    ChartSetInteger(chart, CHART_MODE,                CHART_CANDLES);

    // ── Scroll & zoom ─────────────────────────────────────────────
    ChartSetInteger(chart, CHART_AUTOSCROLL,          true);
    ChartSetInteger(chart, CHART_SHIFT,               true); // right margin

    // ── Sub-window colors (indicators) ───────────────────────────
    ChartSetInteger(chart, CHART_COLOR_BACKGROUND,    clrBlack);

    ChartRedraw(chart);
    Print("Dark theme applied.");
}

//+------------------------------------------------------------------+
// Restore default MT5 theme on EA removal
//+------------------------------------------------------------------+
void RestoreDefaultTheme() {
    long chart = ChartID();

    ChartSetInteger(chart, CHART_COLOR_BACKGROUND,  clrWhite);
    ChartSetInteger(chart, CHART_COLOR_FOREGROUND,  clrBlack);
    ChartSetInteger(chart, CHART_COLOR_CANDLE_BULL, clrWhite);
    ChartSetInteger(chart, CHART_COLOR_CANDLE_BEAR, clrBlack);
    ChartSetInteger(chart, CHART_COLOR_CHART_UP,    clrBlack);
    ChartSetInteger(chart, CHART_COLOR_CHART_DOWN,  clrBlack);
    ChartSetInteger(chart, CHART_SHOW_GRID,         true);
    ChartSetInteger(chart, CHART_SHOW_PERIOD_SEP,   true);
    ChartSetInteger(chart, CHART_SHOW_ASK_LINE,     true);

    ChartRedraw(chart);
}
//+------------------------------------------------------------------+
// Register a new position for partial tracking
//+------------------------------------------------------------------+
void RegisterPosition(ulong ticket, int posType,
                      double entryPrice, double volume) {
    int size = ArraySize(g_partials);
    ArrayResize(g_partials, size + 1);
    g_partials[size].Ticket        = ticket;
    g_partials[size].LevelsHit     = 0;
    g_partials[size].BESet         = false;
    g_partials[size].EntryPrice    = entryPrice;
    g_partials[size].PositionType  = posType;
    g_partials[size].OriginalVolume = volume;
    Print("Registered position #", ticket,
          " for partial tracking. Vol=", volume);
}

//+------------------------------------------------------------------+
// Remove a position from tracking (on close)
//+------------------------------------------------------------------+
void UnregisterPosition(ulong ticket) {
    int size = ArraySize(g_partials);
    for(int i = 0; i < size; i++) {
        if(g_partials[i].Ticket == ticket) {
            // Shift array left
            for(int j = i; j < size - 1; j++) {
                g_partials[j] = g_partials[j + 1];
            }
            ArrayResize(g_partials, size - 1);
            return;
        }
    }
}

//+------------------------------------------------------------------+
// Find partial state index by ticket
//+------------------------------------------------------------------+
int FindPartialIndex(ulong ticket) {
    for(int i = 0; i < ArraySize(g_partials); i++) {
        if(g_partials[i].Ticket == ticket) return i;
    }
    return -1;
}

//+------------------------------------------------------------------+
// Core: Check and execute partial closes + BE on every tick
//+------------------------------------------------------------------+
void CheckPartials() {
    if(!InpAutoPartials) return;
    if(ArraySize(g_partials) == 0) return;

    for(int i = ArraySize(g_partials) - 1; i >= 0; i--) {
        PartialState ps = g_partials[i];

        CPositionInfo pos;
        if(!pos.SelectByTicket(ps.Ticket)) {
            UnregisterPosition(ps.Ticket);
            RemovePartialLines(ps.Ticket);
            continue;
        }

        double currentPrice = (ps.PositionType == POSITION_TYPE_BUY)
            ? g_sym.Bid()
            : g_sym.Ask();

        // ── Use actual position TP to derive step if available ──
        double posTP    = pos.TakeProfit();
        double totalTPprice = (posTP > 0)
            ? MathAbs(posTP - ps.EntryPrice)   // actual TP distance in price
            : g_totalTP * _Point;              // fallback to global setting

        double tpStep = (g_tpLevels > 0)
            ? totalTPprice / g_tpLevels
            : totalTPprice;

        double direction = (ps.PositionType == POSITION_TYPE_BUY) ? 1.0 : -1.0;

        for(int lvl = ps.LevelsHit + 1; lvl <= g_tpLevels; lvl++) {
            double tpPrice = NormalizeDouble(
                ps.EntryPrice + direction * tpStep * lvl, _Digits
            );

            bool levelHit = (ps.PositionType == POSITION_TYPE_BUY)
                ? (currentPrice >= tpPrice)
                : (currentPrice <= tpPrice);

            if(levelHit) {
                int    pct      = 100 / g_tpLevels;
                double closeVol = NormalizeDouble(
                    ps.OriginalVolume * pct / 100.0, 2);
                double minVol   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
                double stepVol  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

                closeVol = MathFloor(closeVol / stepVol) * stepVol;
                if(closeVol < minVol)      closeVol = minVol;
                if(closeVol >= pos.Volume()) closeVol = pos.Volume();

                if(g_trade.PositionClosePartial(ps.Ticket, closeVol, g_deviation)) {
                    g_partials[i].LevelsHit = lvl;
                    WriteLog("Partial TP" + IntegerToString(lvl) +
                             " hit #"     + IntegerToString(ps.Ticket) +
                             " closed "   + DoubleToString(closeVol, 2) +
                             " @ "        + DoubleToString(currentPrice, _Digits));

                    string lineName = "AIV_TP_" + IntegerToString(ps.Ticket) +
                                      "_"       + IntegerToString(lvl);
                    ObjectDelete(0, lineName);
                    ChartRedraw(0);

                    // Move SL to BE after configured level
                    if(!ps.BESet && lvl >= g_beAfterLevel) {
                        double bePrice = NormalizeDouble(
                            ps.EntryPrice + direction * g_beOffsetPts * _Point,
                            _Digits);

                        if(g_trade.PositionModify(ps.Ticket,
                                                  bePrice,
                                                  pos.TakeProfit())) {
                            g_partials[i].BESet = true;
                            WriteLog("SL → BE #" + IntegerToString(ps.Ticket) +
                                     " @ " + DoubleToString(bePrice, _Digits));

                            string slName = "AIV_SL_" + IntegerToString(ps.Ticket);
                            ObjectSetDouble (0, slName, OBJPROP_PRICE, bePrice);
                            ObjectSetString (0, slName, OBJPROP_TEXT,  "BE SL");
                            ObjectSetInteger(0, slName, OBJPROP_COLOR, clrGold);
                            ChartRedraw(0);
                        }
                    }
                } else {
                    WriteLog("Partial close failed TP" +
                             IntegerToString(lvl) + " [" +
                             IntegerToString(g_trade.ResultRetcode()) +
                             "]: " + g_trade.ResultComment());
                }
                break;
            }
        }
    }
}


//+------------------------------------------------------------------+
// Manually move SL to Breakeven for a ticket
//+------------------------------------------------------------------+
void ManualSetBE(ulong ticket, int offsetPts) {
    CPositionInfo pos;
    if(!pos.SelectByTicket(ticket)) {
        WriteLog("BE failed: ticket #" + IntegerToString(ticket) + " not found");
        return;
    }

    int    idx      = FindPartialIndex(ticket);
    int    useOffset = (offsetPts > 0) ? offsetPts : g_beOffsetPts;
    double direction = (pos.PositionType() == POSITION_TYPE_BUY) ? 1.0 : -1.0;

    double entryPrice = (idx >= 0)
        ? g_partials[idx].EntryPrice
        : pos.PriceOpen();

    double bePrice = NormalizeDouble(
        entryPrice + direction * useOffset * _Point, _Digits
    );

    if(g_trade.PositionModify(ticket, bePrice, pos.TakeProfit())) {
        if(idx >= 0) g_partials[idx].BESet = true;

        WriteLog("Manual BE set #" + IntegerToString(ticket) +
                 " SL → " + DoubleToString(bePrice, _Digits));

        // Update SL line to gold
        string slName = "AIV_SL_" + IntegerToString(ticket);
        if(ObjectFind(0, slName) >= 0) {
            ObjectSetDouble (0, slName, OBJPROP_PRICE, bePrice);
            ObjectSetString (0, slName, OBJPROP_TEXT,  "BE SL");
            ObjectSetInteger(0, slName, OBJPROP_COLOR, clrGold);
            ChartRedraw(0);
        }
    } else {
        WriteLog("Manual BE failed #" + IntegerToString(ticket) +
                 " [" + IntegerToString(g_trade.ResultRetcode()) + "]");
    }
}

//+------------------------------------------------------------------+
// Manually close X% of a position
//+------------------------------------------------------------------+
void ManualPartialClose(ulong ticket, double pct) {
    CPositionInfo pos;
    if(!pos.SelectByTicket(ticket)) {
        WriteLog("Partial failed: ticket #" +
                 IntegerToString(ticket) + " not found");
        return;
    }

    double closeVol = NormalizeDouble(pos.Volume() * pct / 100.0, 2);
    double minVol   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double stepVol  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

    // Round to nearest volume step
    closeVol = MathFloor(closeVol / stepVol) * stepVol;
    if(closeVol < minVol) closeVol = minVol;
    if(closeVol >= pos.Volume()) closeVol = pos.Volume();

    if(g_trade.PositionClosePartial(ticket, closeVol, g_deviation)) {
        WriteLog("Manual partial " + DoubleToString(pct, 0) + "% → " +
                 DoubleToString(closeVol, 2) + " lots closed #" +
                 IntegerToString(ticket));
    } else {
        WriteLog("Manual partial failed #" + IntegerToString(ticket) +
                 " [" + IntegerToString(g_trade.ResultRetcode()) + "]");
    }
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
    if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

    ulong dealTicket = trans.deal;
    if(dealTicket == 0) return;
    if(!HistoryDealSelect(dealTicket)) return;

    ENUM_DEAL_ENTRY dealEntry =
        (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);

    // ── DEAL_ENTRY_IN — position just opened ──────────────────────
    // This fires for both market orders AND filled pending orders
    if(dealEntry == DEAL_ENTRY_IN)
    {
        ulong  posTicket = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
        double fillPrice = HistoryDealGetDouble (dealTicket, DEAL_PRICE);
        double fillVol   = HistoryDealGetDouble (dealTicket, DEAL_VOLUME);
        int    dealType  = (int)HistoryDealGetInteger(dealTicket, DEAL_TYPE);

        // Check if this was from a pending order (limit/stop)
        // by checking if reason is ORDER_REASON_* pending type
        ENUM_DEAL_REASON reason =
            (ENUM_DEAL_REASON)HistoryDealGetInteger(dealTicket, DEAL_REASON);

        bool fromPending = (reason == DEAL_REASON_SL  ||
                            reason == DEAL_REASON_TP  ||
                            reason == DEAL_REASON_SO  ||
                            reason == DEAL_REASON_CLIENT ||
                            reason == DEAL_REASON_MOBILE ||
                            reason == DEAL_REASON_WEB    ||
                            reason == DEAL_REASON_EXPERT);

        // Check if already registered (market order registers in ExecuteBuy/Sell)
        int existingIdx = FindPartialIndex(posTicket);

        if(existingIdx < 0)
        {
            // Not yet registered — this came from a pending order fill
            int posType = (dealType == DEAL_TYPE_BUY)
                          ? POSITION_TYPE_BUY
                          : POSITION_TYPE_SELL;

            // Register for partial tracking
            RegisterPosition(posTicket, posType, fillPrice, fillVol);

            // Draw SL/TP/entry lines on chart
            DrawPartialLines(posTicket, posType, fillPrice);

            // Remove confirmed limit order lines (dotted ones)
            string prefix = "AIV_LMT_" + IntegerToString(posTicket);
            ObjectDelete(0, prefix + "_E");
            ObjectDelete(0, prefix + "_S");
            ObjectDelete(0, prefix + "_T");
            ChartRedraw(0);

            WriteLog("LIMIT ORDER FILLED #" + IntegerToString(posTicket) +
                     "  " + ((posType == POSITION_TYPE_BUY) ? "BUY" : "SELL") +
                     " @ " + DoubleToString(fillPrice, _Digits) +
                     "  Vol=" + DoubleToString(fillVol, 2) +
                     "  → Partials activated");
        }

        return; // done with ENTRY_IN
    }

    // ── DEAL_ENTRY_OUT — position close (existing logic below) ────
    if(dealEntry != DEAL_ENTRY_OUT) return;

    if(g_pipeHandle == INVALID_HANDLE) return;

    ulong posTicket = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
    int   idx       = FindPartialIndex(posTicket);

    bool positionStillOpen = false;
    for(int i = 0; i < PositionsTotal(); i++) {
        CPositionInfo pos;
        if(pos.SelectByIndex(i) && pos.Ticket() == posTicket) {
            positionStillOpen = true;
            break;
        }
    }

    TradeResultPacket pkt;
    pkt.PacketType  = PKT_TRADE_RESULT;
    pkt.Ticket      = posTicket;
    pkt.TradeType   = (int)HistoryDealGetInteger(dealTicket, DEAL_TYPE);
    pkt.ExitPrice   = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
    pkt.Volume      = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
    pkt.Profit      = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
    pkt.BEWasSet    = (idx >= 0 && g_partials[idx].BESet) ? 1 : 0;
    pkt.IsPartial   = positionStillOpen ? 1 : 0;
    pkt.EntryPrice  = (idx >= 0) ? g_partials[idx].EntryPrice : pkt.ExitPrice;
    pkt.HitSL       = 0;
    pkt.HitTP       = 0;

    double dealSL = 0, dealTP = 0;
    if(HistoryDealSelect(dealTicket)) {
        ulong orderTicket = HistoryDealGetInteger(dealTicket, DEAL_ORDER);
        if(HistoryOrderSelect(orderTicket)) {
            dealSL = HistoryOrderGetDouble(orderTicket, ORDER_SL);
            dealTP = HistoryOrderGetDouble(orderTicket, ORDER_TP);
        }
    }

    if(dealTP > 0 && MathAbs(pkt.ExitPrice - dealTP) <= _Point * 5)
        pkt.HitTP = 1;
    if(dealSL > 0 && MathAbs(pkt.ExitPrice - dealSL) <= _Point * 5)
        pkt.HitSL = 1;

    int symLen = StringLen(_Symbol);
    if(symLen > 19) symLen = 19;
    for(int i = 0; i < symLen; i++)
        pkt.Symbol[i] = (char)StringGetCharacter(_Symbol, i);
    pkt.Symbol[symLen] = 0;

    FileWriteStruct(g_pipeHandle, pkt);
    FileFlush(g_pipeHandle);

    Print("TradeResult: Ticket=", posTicket,
          " Profit=",             pkt.Profit,
          " IsPartial=",          (int)pkt.IsPartial,
          " Vol=",                pkt.Volume,
          " PositionStillOpen=",  positionStillOpen);

    if(!positionStillOpen) {
        UnregisterPosition(posTicket);
        RemovePartialLines(posTicket);
    }
}


void OnChartEvent(const int     id,
                  const long   &lparam,
                  const double &dparam,
                  const string &sparam)
{
    // CHARTEVENT_OBJECT_DRAG fires when user finishes dragging a line
    if(id != CHARTEVENT_OBJECT_DRAG) return;

    string objName = sparam;

    // ── Check if it is one of our SL lines ────────────────────
    if(StringFind(objName, "AIV_SL_") == 0) {
        string ticketStr = StringSubstr(objName, 7);
        ulong  ticket    = (ulong)StringToInteger(ticketStr);
        double newSL     = ObjectGetDouble(0, objName, OBJPROP_PRICE);
        newSL            = NormalizeDouble(newSL, _Digits);

        CPositionInfo pos;
        if(pos.SelectByTicket(ticket)) {
            if(g_trade.PositionModify(ticket, newSL, pos.TakeProfit())) {
                // Calculate new SL in points for display
                int idx = FindPartialIndex(ticket);
                double entry = (idx >= 0)
                    ? g_partials[idx].EntryPrice
                    : pos.PriceOpen();
                int newSlPts = (int)(MathAbs(newSL - entry) / _Point);

                ObjectSetString(0, objName, OBJPROP_TEXT,
                    "SL  -" + IntegerToString(newSlPts) + " pts");
                ChartRedraw(0);

                WriteLog("SL moved to " + DoubleToString(newSL, _Digits) +
                         " (" + IntegerToString(newSlPts) + " pts) #" +
                         IntegerToString(ticket));
            } else {
                // Revert line to actual SL if modify failed
                ObjectSetDouble(0, objName, OBJPROP_PRICE, pos.StopLoss());
                ChartRedraw(0);
                WriteLog("SL drag failed [" +
                         IntegerToString(g_trade.ResultRetcode()) + "]: " +
                         g_trade.ResultComment());
            }
        }
        return;
    }

    // ── Check if it is one of our TP lines ────────────────────
    if(StringFind(objName, "AIV_TP_") == 0) {
        // Parse ticket and level from name: AIV_TP_{ticket}_{level}
        string remainder = StringSubstr(objName, 7);
        int    sepPos    = StringFind(remainder, "_");
        if(sepPos < 0) return;

        ulong  ticket    = (ulong)StringToInteger(
                               StringSubstr(remainder, 0, sepPos));
        int    level     = (int)StringToInteger(
                               StringSubstr(remainder, sepPos + 1));
        double newTP     = ObjectGetDouble(0, objName, OBJPROP_PRICE);
        newTP            = NormalizeDouble(newTP, _Digits);

        CPositionInfo pos;
        if(pos.SelectByTicket(ticket)) {
            // For TP1 drag: only move the final TP if only 1 level
            // For all others: move the actual position TP (last level)
            double posTP = pos.TakeProfit();
            if(level == g_tpLevels) {
                // Moving the last TP level = move position TP
                if(g_trade.PositionModify(ticket, pos.StopLoss(), newTP)) {
                    int idx = FindPartialIndex(ticket);
                    double entry = (idx >= 0)
                        ? g_partials[idx].EntryPrice
                        : pos.PriceOpen();
                    int newTpPts = (int)(MathAbs(newTP - entry) / _Point);

                    ObjectSetString(0, objName, OBJPROP_TEXT,
                        "TP" + IntegerToString(level) +
                        "  +" + IntegerToString(newTpPts) + " pts");
                    ChartRedraw(0);
                    WriteLog("TP" + IntegerToString(level) +
                             " moved to " + DoubleToString(newTP, _Digits) +
                             " #" + IntegerToString(ticket));
                } else {
                    // Revert
                    ObjectSetDouble(0, objName, OBJPROP_PRICE, posTP);
                    ChartRedraw(0);
                    WriteLog("TP drag failed [" +
                             IntegerToString(g_trade.ResultRetcode()) + "]");
                }
            } else {
                // Moving intermediate TP level — just visual, update partial price
                int idx = FindPartialIndex(ticket);
                double entry = (idx >= 0)
                    ? g_partials[idx].EntryPrice
                    : pos.PriceOpen();
                int newTpPts = (int)(MathAbs(newTP - entry) / _Point);
                ObjectSetString(0, objName, OBJPROP_TEXT,
                    "TP" + IntegerToString(level) +
                    "  +" + IntegerToString(newTpPts) + " pts (visual)");
                ChartRedraw(0);
                WriteLog("TP" + IntegerToString(level) +
                         " visual target moved to " +
                         DoubleToString(newTP, _Digits));
            }
        }
        return;
    }
}

// Counter for unique names
int g_drawCounter = 0;

void DrawFreeHLine(double price, int colorVal,
                   int styleVal, int widthVal)
{
    g_drawCounter++;
    string name  = "AIV_DRAW_" + IntegerToString(g_drawCounter);
    color  clr   = (color)colorVal;
    ENUM_LINE_STYLE ls = (styleVal == 1) ? STYLE_DASH
                       : (styleVal == 2) ? STYLE_DOT
                       : STYLE_SOLID;

    ObjectDelete(0, name);
    ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
    ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
    ObjectSetInteger(0, name, OBJPROP_STYLE,      ls);
    ObjectSetInteger(0, name, OBJPROP_WIDTH,      widthVal);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
    ObjectSetInteger(0, name, OBJPROP_BACK,       false);
    ObjectSetString (0, name, OBJPROP_TEXT,
        "H: " + DoubleToString(price, _Digits));
    ChartRedraw(0);
    WriteLog("HLine drawn @ " + DoubleToString(price, _Digits));
}

void DrawFreeTLine(double price1, double price2,
                   int colorVal, int styleVal, int widthVal)
{
    g_drawCounter++;
    string name = "AIV_DRAW_" + IntegerToString(g_drawCounter);
    color  clr  = (color)colorVal;
    ENUM_LINE_STYLE ls = (styleVal == 1) ? STYLE_DASH
                       : (styleVal == 2) ? STYLE_DOT
                       : STYLE_SOLID;

    // Use current time and 50 bars ahead for the two points
    datetime t1 = iTime(_Symbol, PERIOD_CURRENT, 10);
    datetime t2 = iTime(_Symbol, PERIOD_CURRENT, 0);

    ObjectDelete(0, name);
    ObjectCreate(0, name, OBJ_TREND, 0, t1, price1, t2, price2);
    ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
    ObjectSetInteger(0, name, OBJPROP_STYLE,      ls);
    ObjectSetInteger(0, name, OBJPROP_WIDTH,      widthVal);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
    ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT,  true);
    ObjectSetInteger(0, name, OBJPROP_BACK,       false);
    ChartRedraw(0);
    WriteLog("TLine drawn");
}

void ClearFreeDrawings() {
    int total = ObjectsTotal(0);
    for(int i = total - 1; i >= 0; i--) {
        string name = ObjectName(0, i);
        if(StringFind(name, "AIV_DRAW_") == 0)
            ObjectDelete(0, name);
    }
    g_drawCounter = 0;
    ChartRedraw(0);
    WriteLog("All drawings cleared.");
}
//+------------------------------------------------------------------+
// Pattern Detection — called every new bar from OnTick
//+------------------------------------------------------------------+

bool IsBullish(int shift) {
    return iClose(_Symbol, PERIOD_CURRENT, shift) >
           iOpen (_Symbol, PERIOD_CURRENT, shift);
}

bool IsBearish(int shift) {
    return iClose(_Symbol, PERIOD_CURRENT, shift) <
           iOpen (_Symbol, PERIOD_CURRENT, shift);
}

double BodyHigh(int shift) {
    return MathMax(iOpen (_Symbol, PERIOD_CURRENT, shift),
                   iClose(_Symbol, PERIOD_CURRENT, shift));
}

double BodyLow(int shift) {
    return MathMin(iOpen (_Symbol, PERIOD_CURRENT, shift),
                   iClose(_Symbol, PERIOD_CURRENT, shift));
}


//+------------------------------------------------------------------+
// Draw a rectangle range box between two datetimes and two prices
//+------------------------------------------------------------------+
void DrawRangeBox(datetime t1, datetime t2,
                  double highPrice, double lowPrice,
                  color boxColor, string label)
{
    g_patternCounter++;
    string name = "AIV_PAT_" + IntegerToString(g_patternCounter);

    ObjectDelete(0, name);
    ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, highPrice, t2, lowPrice);
    ObjectSetInteger(0, name, OBJPROP_COLOR,      boxColor);
    ObjectSetInteger(0, name, OBJPROP_STYLE,      STYLE_SOLID);
    ObjectSetInteger(0, name, OBJPROP_WIDTH,      1);
    ObjectSetInteger(0, name, OBJPROP_BACK,       true);   // behind candles
    ObjectSetInteger(0, name, OBJPROP_FILL,       true);   // filled rectangle
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetString (0, name, OBJPROP_TEXT,       label);
    ObjectSetString (0, name, OBJPROP_TOOLTIP,    label);

    // Filled rectangles need low opacity — use color with alpha via ColorToARGB
    // MQL5 doesn't support alpha on OBJ_RECTANGLE directly,
    // so we draw a second border-only rect on top for clarity
    string borderName = name + "_B";
    ObjectDelete(0, borderName);
    ObjectCreate(0, borderName, OBJ_RECTANGLE, 0, t1, highPrice, t2, lowPrice);
    ObjectSetInteger(0, borderName, OBJPROP_COLOR,      boxColor);
    ObjectSetInteger(0, borderName, OBJPROP_STYLE,      STYLE_SOLID);
    ObjectSetInteger(0, borderName, OBJPROP_WIDTH,      2);
    ObjectSetInteger(0, borderName, OBJPROP_BACK,       false);
    ObjectSetInteger(0, borderName, OBJPROP_FILL,       false);
    ObjectSetInteger(0, borderName, OBJPROP_SELECTABLE, false);

    ChartRedraw(0);
    Print("Pattern box drawn: ", label,
          " High=", DoubleToString(highPrice, _Digits),
          " Low=",  DoubleToString(lowPrice,  _Digits));
}

//+------------------------------------------------------------------+
// Detect patterns on the last completed 3 candles
// Call this once per new bar (shift=1 is last completed candle)
//+------------------------------------------------------------------+
void DetectPatterns() {
    int bars = iBars(_Symbol, PERIOD_CURRENT);
    if(bars < 4) return;

    int currentBar = bars;
    if(currentBar == g_lastPatternBar) return;
    g_lastPatternBar = currentBar;

    int c1 = 1; // engulfing candle (newest completed)
    int c2 = 2; // previous candle  (engulfed)
    int c3 = 3; // first candle of pattern

    double c1BodyHigh = BodyHigh(c1);
    double c1BodyLow  = BodyLow (c1);
    double c2BodyHigh = BodyHigh(c2);
    double c2BodyLow  = BodyLow (c2);
    double c3BodyHigh = BodyHigh(c3);
    double c3BodyLow  = BodyLow (c3);

    // ── Shared box range calculation ──────────────────────────
    double boxHigh = MathMax(iHigh(_Symbol, PERIOD_CURRENT, c3),
                     MathMax(iHigh(_Symbol, PERIOD_CURRENT, c2),
                             iHigh(_Symbol, PERIOD_CURRENT, c1)));
    double boxLow  = MathMin(iLow (_Symbol, PERIOD_CURRENT, c3),
                     MathMin(iLow (_Symbol, PERIOD_CURRENT, c2),
                             iLow (_Symbol, PERIOD_CURRENT, c1)));

    datetime t1 = iTime(_Symbol, PERIOD_CURRENT, c3);
    datetime t2 = iTime(_Symbol, PERIOD_CURRENT, c1)
                  + PeriodSeconds(PERIOD_CURRENT);

    // ─────────────────────────────────────────────────────────
    // PATTERN A: Green + Green + Bearish Engulfing Red
    // ─────────────────────────────────────────────────────────
    if(IsBullish(c3) && IsBullish(c2) && IsBearish(c1))
    {
        bool engulfsC2 = (iOpen (_Symbol, PERIOD_CURRENT, c1) >= c2BodyHigh) &&
                         (iClose(_Symbol, PERIOD_CURRENT, c1) <= c2BodyLow);

        bool doesNotEngulfC3 = !(iOpen (_Symbol, PERIOD_CURRENT, c1) >= c3BodyHigh &&
                                  iClose(_Symbol, PERIOD_CURRENT, c1) <= c3BodyLow);

        if(engulfsC2 && doesNotEngulfC3)
        {
            // ── Count candles inside box (excluding c1,c2,c3) ─
            int insideCount = CountCandlesInsideBox(boxHigh, boxLow, c1, c3);

            WriteLog("BEAR pattern found — candles inside box: " +
                     IntegerToString(insideCount) +
                     " (need " + IntegerToString(InpMinCandlesInBox) + ")");

            if(insideCount >= InpMinCandlesInBox)
            {
                DrawRangeBox(t1, t2, boxHigh, boxLow,
                             InpBearBoxColor,
                             "BEAR ENGULF [" + IntegerToString(insideCount) +
                             " inside]  H=" + DoubleToString(boxHigh, _Digits) +
                             "  L="         + DoubleToString(boxLow,  _Digits));

                WriteLog("BEARISH ENGULF CONFIRMED @ " +
                         TimeToString(iTime(_Symbol, PERIOD_CURRENT, c1)) +
                         "  Inside=" + IntegerToString(insideCount) +
                         "  Box "    + DoubleToString(boxHigh, _Digits) +
                         " → "       + DoubleToString(boxLow,  _Digits));
            }
            else
            {
                WriteLog("BEARISH pattern skipped — only " +
                         IntegerToString(insideCount) +
                         " candles inside box, need " +
                         IntegerToString(InpMinCandlesInBox));
            }
        }
    }

    // ─────────────────────────────────────────────────────────
    // PATTERN B: Red + Red + Bullish Engulfing Green
    // ─────────────────────────────────────────────────────────
    if(IsBearish(c3) && IsBearish(c2) && IsBullish(c1))
    {
        bool engulfsC2 = (iClose(_Symbol, PERIOD_CURRENT, c1) >= c2BodyHigh) &&
                         (iOpen (_Symbol, PERIOD_CURRENT, c1) <= c2BodyLow);

        bool doesNotEngulfC3 = !(iClose(_Symbol, PERIOD_CURRENT, c1) >= c3BodyHigh &&
                                  iOpen (_Symbol, PERIOD_CURRENT, c1) <= c3BodyLow);

        if(engulfsC2 && doesNotEngulfC3)
        {
            int insideCount = CountCandlesInsideBox(boxHigh, boxLow, c1, c3);

            WriteLog("BULL pattern found — candles inside box: " +
                     IntegerToString(insideCount) +
                     " (need " + IntegerToString(InpMinCandlesInBox) + ")");

            if(insideCount >= InpMinCandlesInBox)
            {
                DrawRangeBox(t1, t2, boxHigh, boxLow,
                             InpBullBoxColor,
                             "BULL ENGULF [" + IntegerToString(insideCount) +
                             " inside]  H=" + DoubleToString(boxHigh, _Digits) +
                             "  L="         + DoubleToString(boxLow,  _Digits));

                WriteLog("BULLISH ENGULF CONFIRMED @ " +
                         TimeToString(iTime(_Symbol, PERIOD_CURRENT, c1)) +
                         "  Inside=" + IntegerToString(insideCount) +
                         "  Box "    + DoubleToString(boxHigh, _Digits) +
                         " → "       + DoubleToString(boxLow,  _Digits));
            }
            else
            {
                WriteLog("BULLISH pattern skipped — only " +
                         IntegerToString(insideCount) +
                         " candles inside box, need " +
                         IntegerToString(InpMinCandlesInBox));
            }
        }
    }
}


//+------------------------------------------------------------------+
// Draw/update candle countdown timer on chart
//+------------------------------------------------------------------+
void UpdateCandleTimer() {
    datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
    int      periodSecs     = PeriodSeconds(PERIOD_CURRENT);
    datetime nextBarTime    = currentBarTime + periodSecs;
    datetime serverTime     = TimeCurrent();
    int      secsLeft       = (int)(nextBarTime - serverTime);

    if(secsLeft < 0) secsLeft = 0;

    // Format as MM:SS or HH:MM:SS depending on timeframe
    string timeStr;
    if(secsLeft >= 3600) {
        int h = secsLeft / 3600;
        int m = (secsLeft % 3600) / 60;
        int s = secsLeft % 60;
        timeStr = StringFormat("%02d:%02d:%02d", h, m, s);
    } else {
        int m = secsLeft / 60;
        int s = secsLeft % 60;
        timeStr = StringFormat("%02d:%02d", m, s);
    }

    // Color shifts from green → yellow → red as time runs out
    double pct = (periodSecs > 0)
                 ? (double)secsLeft / periodSecs
                 : 0;

    color timerColor;
    if(pct > 0.5)       timerColor = C'0,188,168';   // teal  — plenty of time
    else if(pct > 0.2)  timerColor = C'255,200,0';   // yellow — getting close
    else                timerColor = C'234,84,85';    // red   — almost closed

    string objName = "AIV_CANDLE_TIMER";

    if(ObjectFind(0, objName) < 0) {
        // Create label on first call
        ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, objName, OBJPROP_CORNER,    CORNER_RIGHT_UPPER);
        ObjectSetInteger(0, objName, OBJPROP_ANCHOR,    ANCHOR_RIGHT_UPPER);
        ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, 10);
        ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, 28);
        ObjectSetInteger(0, objName, OBJPROP_BACK,      false);
        ObjectSetInteger(0, objName, OBJPROP_SELECTABLE,false);
        ObjectSetInteger(0, objName, OBJPROP_HIDDEN,    true);
    }

    ObjectSetString (0, objName, OBJPROP_TEXT,      "⏱ " + timeStr);
    ObjectSetInteger(0, objName, OBJPROP_COLOR,     timerColor);
    ObjectSetInteger(0, objName, OBJPROP_FONTSIZE,  11);
    ObjectSetString (0, objName, OBJPROP_FONT,      "Consolas");

    // Also show current bar open/close info next to timer
    string infoName = "AIV_CANDLE_INFO";
    if(ObjectFind(0, infoName) < 0) {
        ObjectCreate(0, infoName, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, infoName, OBJPROP_CORNER,    CORNER_RIGHT_UPPER);
        ObjectSetInteger(0, infoName, OBJPROP_ANCHOR,    ANCHOR_RIGHT_UPPER);
        ObjectSetInteger(0, infoName, OBJPROP_XDISTANCE, 10);
        ObjectSetInteger(0, infoName, OBJPROP_YDISTANCE, 46);
        ObjectSetInteger(0, infoName, OBJPROP_BACK,      false);
        ObjectSetInteger(0, infoName, OBJPROP_SELECTABLE,false);
        ObjectSetInteger(0, infoName, OBJPROP_HIDDEN,    true);
    }

    double barOpen  = iOpen (_Symbol, PERIOD_CURRENT, 0);
    double barHigh  = iHigh (_Symbol, PERIOD_CURRENT, 0);
    double barLow   = iLow  (_Symbol, PERIOD_CURRENT, 0);
    double barClose = iClose(_Symbol, PERIOD_CURRENT, 0);
    double barMove  = barClose - barOpen;

    string moveStr  = StringFormat("%+.0f pts", barMove / _Point);
    color  moveCol  = (barMove >= 0) ? C'0,188,168' : C'234,84,85';
    string candleInfo = StringFormat("O:%.2f  H:%.2f  L:%.2f  C:%.2f  %s",
                                     barOpen, barHigh, barLow,
                                     barClose, moveStr);

    ObjectSetString (0, infoName, OBJPROP_TEXT,    candleInfo);
    ObjectSetInteger(0, infoName, OBJPROP_COLOR,   moveCol);
    ObjectSetInteger(0, infoName, OBJPROP_FONTSIZE, 9);
    ObjectSetString (0, infoName, OBJPROP_FONT,    "Consolas");

    ChartRedraw(0);
}
//+------------------------------------------------------------------+
// Count how many candles fit entirely inside the box range
// A candle is "inside" if its HIGH <= boxHigh AND LOW >= boxLow
// Excludes the 3 pattern candles themselves (shifts 1,2,3)
//+------------------------------------------------------------------+
int CountCandlesInsideBox(double boxHigh, double boxLow,
                          int excludeFrom, int excludeTo)
{
    int count = 0;
    int lookback = InpCandleLookback + excludeTo;

    for(int i = excludeTo + 1; i <= lookback; i++) {
        double hi = iHigh(_Symbol, PERIOD_CURRENT, i);
        double lo = iLow (_Symbol, PERIOD_CURRENT, i);

        // Skip invalid bars
        if(hi <= 0 || lo <= 0) continue;

        // Candle fully inside box range
        if(hi <= boxHigh && lo >= boxLow)
            count++;
    }
    return count;
}

//+------------------------------------------------------------------+
// Check if bar at 'shift' on pivot timeframe is a Pivot High
// A pivot high: highest high among left+right bars centered on shift
//+------------------------------------------------------------------+
bool IsPivotHigh(int shift) {
    double centerHigh = iHigh(_Symbol, InpPivotTimeframe, shift);
    if(centerHigh <= 0) return false;

    // Check left bars
    for(int i = 1; i <= InpPivotLeftBars; i++) {
        if(iHigh(_Symbol, InpPivotTimeframe, shift + i) >= centerHigh)
            return false;
    }
    // Check right bars (must already be confirmed — shift > right bars)
    for(int i = 1; i <= InpPivotRightBars; i++) {
        if(iHigh(_Symbol, InpPivotTimeframe, shift - i) >= centerHigh)
            return false;
    }
    return true;
}

//+------------------------------------------------------------------+
// Check if bar at 'shift' on pivot timeframe is a Pivot Low
//+------------------------------------------------------------------+
bool IsPivotLow(int shift) {
    double centerLow = iLow(_Symbol, InpPivotTimeframe, shift);
    if(centerLow <= 0) return false;

    for(int i = 1; i <= InpPivotLeftBars; i++) {
        if(iLow(_Symbol, InpPivotTimeframe, shift + i) <= centerLow)
            return false;
    }
    for(int i = 1; i <= InpPivotRightBars; i++) {
        if(iLow(_Symbol, InpPivotTimeframe, shift - i) <= centerLow)
            return false;
    }
    return true;
}

//+------------------------------------------------------------------+
// Draw a horizontal ray from pivot point extending to the right
//+------------------------------------------------------------------+
void DrawPivotLine(string name, datetime pivotTime,
                   double price, color lineColor,
                   string label)
{
    // Extend line from pivot bar to far right (current time + buffer)
    datetime endTime = TimeCurrent() + PeriodSeconds(InpPivotTimeframe) * 50;

    ObjectDelete(0, name);
    ObjectCreate(0, name, OBJ_TREND, 0,
                 pivotTime, price,
                 endTime,   price);

    ObjectSetInteger(0, name, OBJPROP_COLOR,      lineColor);
    ObjectSetInteger(0, name, OBJPROP_STYLE,      InpPivotLineStyle);
    ObjectSetInteger(0, name, OBJPROP_WIDTH,      InpPivotLineWidth);
    ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT,  true);
    ObjectSetInteger(0, name, OBJPROP_RAY_LEFT,   false);
    ObjectSetInteger(0, name, OBJPROP_BACK,       false);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_HIDDEN,     false);
    ObjectSetString (0, name, OBJPROP_TEXT,       label);
    ObjectSetString (0, name, OBJPROP_TOOLTIP,    label);

    // Small price label at the right end
    string lblName = name + "_LBL";
    ObjectDelete(0, lblName);
    ObjectCreate(0, lblName, OBJ_TEXT, 0, endTime, price);
    ObjectSetString (0, lblName, OBJPROP_TEXT,      label);
    ObjectSetInteger(0, lblName, OBJPROP_COLOR,     lineColor);
    ObjectSetInteger(0, lblName, OBJPROP_FONTSIZE,  8);
    ObjectSetString (0, lblName, OBJPROP_FONT,      "Consolas");
    ObjectSetInteger(0, lblName, OBJPROP_ANCHOR,    ANCHOR_LEFT);
    ObjectSetInteger(0, lblName, OBJPROP_BACK,      false);
    ObjectSetInteger(0, lblName, OBJPROP_SELECTABLE,false);
    ObjectSetInteger(0, lblName, OBJPROP_HIDDEN,    true);
}

//+------------------------------------------------------------------+
// Remove all pivot lines and labels
//+------------------------------------------------------------------+
void RemovePivotLines() {
    int total = ObjectsTotal(0);
    for(int i = total - 1; i >= 0; i--) {
        string name = ObjectName(0, i);
        if(StringFind(name, "AIV_PH_") == 0 ||
           StringFind(name, "AIV_PL_") == 0)
            ObjectDelete(0, name);
    }
    ChartRedraw(0);
}

//+------------------------------------------------------------------+
// Main pivot scan — finds last 2 pivot highs and last 2 pivot lows
// on InpPivotTimeframe, draws lines for each
//+------------------------------------------------------------------+
void UpdatePivotLines() {
    // Only recalculate once per new bar on the PIVOT timeframe
    datetime currentPivotBar = iTime(_Symbol, InpPivotTimeframe, 0);
    if(currentPivotBar == g_lastPivotBarTime) return;
    g_lastPivotBarTime = currentPivotBar;

    int totalBars = iBars(_Symbol, InpPivotTimeframe);
    if(totalBars < InpPivotMaxLookback) return;

    // Minimum shift needed so right bars are confirmed
    int minShift = InpPivotRightBars + 1;
    int maxShift = InpPivotMaxLookback - InpPivotLeftBars;

    // ── Scan for last 2 pivot highs ───────────────────────────
    int highsFound = 0;
    for(int i = minShift; i <= maxShift && highsFound < 2; i++) {
        if(IsPivotHigh(i)) {
            g_lastPivotHighs[highsFound]     = iHigh(_Symbol, InpPivotTimeframe, i);
            g_lastPivotHighTimes[highsFound] = iTime(_Symbol, InpPivotTimeframe, i);
            highsFound++;
        }
    }

    // ── Scan for last 2 pivot lows ────────────────────────────
    int lowsFound = 0;
    for(int i = minShift; i <= maxShift && lowsFound < 2; i++) {
        if(IsPivotLow(i)) {
            g_lastPivotLows[lowsFound]     = iLow (_Symbol, InpPivotTimeframe, i);
            g_lastPivotLowTimes[lowsFound] = iTime(_Symbol, InpPivotTimeframe, i);
            lowsFound++;
        }
    }

    // ── Remove old pivot lines before redrawing ───────────────
    RemovePivotLines();

    // ── Draw pivot high lines ─────────────────────────────────
    string tfStr = EnumToString(InpPivotTimeframe);
    for(int i = 0; i < highsFound; i++) {
        string name  = "AIV_PH_" + IntegerToString(i + 1);
        string rank  = (i == 0) ? "PH1" : "PH2";  // PH1 = most recent
        string label = rank + " " + tfStr +
                       "  " + DoubleToString(g_lastPivotHighs[i], _Digits);

        // Most recent pivot = full opacity, older = slightly thinner
        int width = (i == 0) ? InpPivotLineWidth : MathMax(1, InpPivotLineWidth - 1);

        DrawPivotLine(name,
                      g_lastPivotHighTimes[i],
                      g_lastPivotHighs[i],
                      InpPivotHighColor,
                      label);

        // Adjust width for older pivot
        ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
        if(i == 1) ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);

        Print("PH", i+1, " @ ", DoubleToString(g_lastPivotHighs[i], _Digits),
              "  Time=", TimeToString(g_lastPivotHighTimes[i]));
    }

    // ── Draw pivot low lines ──────────────────────────────────
    for(int i = 0; i < lowsFound; i++) {
        string name  = "AIV_PL_" + IntegerToString(i + 1);
        string rank  = (i == 0) ? "PL1" : "PL2";
        string label = rank + " " + tfStr +
                       "  " + DoubleToString(g_lastPivotLows[i], _Digits);

        int width = (i == 0) ? InpPivotLineWidth : MathMax(1, InpPivotLineWidth - 1);

        DrawPivotLine(name,
                      g_lastPivotLowTimes[i],
                      g_lastPivotLows[i],
                      InpPivotLowColor,
                      label);

        ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
        if(i == 1) ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);

        Print("PL", i+1, " @ ", DoubleToString(g_lastPivotLows[i], _Digits),
              "  Time=", TimeToString(g_lastPivotLowTimes[i]));
    }

    ChartRedraw(0);
}

//+------------------------------------------------------------------+
// Draw preview lines for a pending limit order
// All 3 lines are DRAGGABLE so user can adjust before placing
//+------------------------------------------------------------------+
void DrawLimitPreview(double limitPrice, int direction,
                      double lotSize, int slPts, int tpPts)
{
    g_previewActive    = true;
    g_previewDirection = direction;
    g_previewLotSize   = lotSize;
    g_previewSL        = slPts;
    g_previewTP        = tpPts;

    double dir      = (direction == 0) ? 1.0 : -1.0;  // 0=buy 1=sell
    double slPrice  = NormalizeDouble(limitPrice - dir * slPts * _Point, _Digits);
    double tpPrice  = NormalizeDouble(limitPrice + dir * tpPts * _Point, _Digits);

    color entryCol  = (direction == 0) ? C'30,144,255' : C'255,100,100';
    g_sym.RefreshRates();
    double ask = g_sym.Ask();
    double bid = g_sym.Bid();

    // Determine actual order type for display
    string dirStr;
    if(direction == 0)
        dirStr = (limitPrice < ask) ? "BUY LIMIT" : "BUY STOP";
    else
        dirStr = (limitPrice > bid) ? "SELL LIMIT" : "SELL STOP";

    // ── Entry line ────────────────────────────────────────────
    string entryName = "AIV_PRV_ENTRY";
    ObjectDelete(0, entryName);
    ObjectCreate(0, entryName, OBJ_HLINE, 0, 0, limitPrice);
    ObjectSetInteger(0, entryName, OBJPROP_COLOR,       entryCol);
    ObjectSetInteger(0, entryName, OBJPROP_STYLE,       STYLE_SOLID);
    ObjectSetInteger(0, entryName, OBJPROP_WIDTH,       2);
    ObjectSetInteger(0, entryName, OBJPROP_SELECTABLE,  true);
    ObjectSetInteger(0, entryName, OBJPROP_BACK,        false);
    ObjectSetString (0, entryName, OBJPROP_TEXT,
        "⚡ " + dirStr + "  " + DoubleToString(lotSize, 2) + " lot" +
        "  @ " + DoubleToString(limitPrice, _Digits) +
        "  [DRAG TO ADJUST — click PLACE to confirm]");
    ObjectSetString (0, entryName, OBJPROP_TOOLTIP,
        "Drag to set entry price. Click PLACE in panel when ready.");

    // ── SL line ───────────────────────────────────────────────
    string slName = "AIV_PRV_SL";
    ObjectDelete(0, slName);
    ObjectCreate(0, slName, OBJ_HLINE, 0, 0, slPrice);
    ObjectSetInteger(0, slName, OBJPROP_COLOR,      C'234,84,85');
    ObjectSetInteger(0, slName, OBJPROP_STYLE,      STYLE_DASH);
    ObjectSetInteger(0, slName, OBJPROP_WIDTH,      2);
    ObjectSetInteger(0, slName, OBJPROP_SELECTABLE, true);
    ObjectSetInteger(0, slName, OBJPROP_BACK,       false);
    ObjectSetString (0, slName, OBJPROP_TEXT,
        "SL  -" + IntegerToString(slPts) + " pts" +
        "  @ " + DoubleToString(slPrice, _Digits));
    ObjectSetString (0, slName, OBJPROP_TOOLTIP, "Drag to adjust Stop Loss");

    // ── TP line ───────────────────────────────────────────────
    string tpName = "AIV_PRV_TP";
    ObjectDelete(0, tpName);
    ObjectCreate(0, tpName, OBJ_HLINE, 0, 0, tpPrice);
    ObjectSetInteger(0, tpName, OBJPROP_COLOR,      C'0,188,168');
    ObjectSetInteger(0, tpName, OBJPROP_STYLE,      STYLE_DASH);
    ObjectSetInteger(0, tpName, OBJPROP_WIDTH,      2);
    ObjectSetInteger(0, tpName, OBJPROP_SELECTABLE, true);
    ObjectSetInteger(0, tpName, OBJPROP_BACK,       false);
    ObjectSetString (0, tpName, OBJPROP_TEXT,
        "TP  +" + IntegerToString(tpPts) + " pts" +
        "  @ " + DoubleToString(tpPrice, _Digits));
    ObjectSetString (0, tpName, OBJPROP_TOOLTIP, "Drag to adjust Take Profit");

    // ── Risk label ────────────────────────────────────────────
    string riskName = "AIV_PRV_RISK";
    ObjectDelete(0, riskName);
    ObjectCreate(0, riskName, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, riskName, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
    ObjectSetInteger(0, riskName, OBJPROP_XDISTANCE,  10);
    ObjectSetInteger(0, riskName, OBJPROP_YDISTANCE,  50);
    ObjectSetInteger(0, riskName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, riskName, OBJPROP_BACK,       false);
    ObjectSetString (0, riskName, OBJPROP_FONT,       "Consolas");
    ObjectSetInteger(0, riskName, OBJPROP_FONTSIZE,   10);
    ObjectSetInteger(0, riskName, OBJPROP_COLOR,      C'255,200,0');
    ObjectSetString (0, riskName, OBJPROP_TEXT,
        "PENDING " + dirStr +
        "  Lot=" + DoubleToString(lotSize, 2) +
        "  Entry=" + DoubleToString(limitPrice, _Digits) +
        "  SL=" + IntegerToString(slPts) + "pts" +
        "  TP=" + IntegerToString(tpPts) + "pts" +
        "  — Drag lines to adjust, then click PLACE");

    ChartRedraw(0);
    WriteLog("PREVIEW: " + dirStr +
             " Lot="   + DoubleToString(lotSize, 2) +
             " Entry=" + DoubleToString(limitPrice, _Digits) +
             " SL="    + DoubleToString(slPrice,    _Digits) +
             " TP="    + DoubleToString(tpPrice,    _Digits));
}

//+------------------------------------------------------------------+
// Read current preview line positions (user may have dragged them)
// and place the actual pending limit order
//+------------------------------------------------------------------+
void PlaceLimitOrder() {
    if(!g_previewActive) {
        WriteLog("PLACE failed: no preview active");
        return;
    }

    // Read line positions
    double entryPrice = ObjectGetDouble(0, "AIV_PRV_ENTRY", OBJPROP_PRICE);
    double slPrice    = ObjectGetDouble(0, "AIV_PRV_SL",    OBJPROP_PRICE);
    double tpPrice    = ObjectGetDouble(0, "AIV_PRV_TP",    OBJPROP_PRICE);

    Print("PlaceLimitOrder: entry=",  entryPrice,
          " sl=",                     slPrice,
          " tp=",                     tpPrice,
          " lot=",                    g_previewLotSize,
          " dir=",                    g_previewDirection);

    // Validate prices
    if(entryPrice <= 0) {
        WriteLog("PLACE failed: entry price = 0. Was preview drawn?");
        return;
    }
    if(slPrice <= 0) {
        WriteLog("PLACE failed: SL price = 0");
        return;
    }
    if(tpPrice <= 0) {
        WriteLog("PLACE failed: TP price = 0");
        return;
    }
    if(g_previewLotSize <= 0) {
        WriteLog("PLACE failed: lot size = 0");
        return;
    }

    entryPrice = NormalizeDouble(entryPrice, _Digits);
    slPrice    = NormalizeDouble(slPrice,    _Digits);
    tpPrice    = NormalizeDouble(tpPrice,    _Digits);

      g_sym.RefreshRates();
      double ask = g_sym.Ask();
      double bid = g_sym.Bid();
      
      ENUM_ORDER_TYPE orderType;
      
      if(g_previewDirection == 0) {
          // BUY direction — auto pick Limit vs Stop based on price
          if(entryPrice < ask) {
              orderType = ORDER_TYPE_BUY_LIMIT;
              Print("Auto-selected: BUY LIMIT (entry below Ask)");
          } else {
              orderType = ORDER_TYPE_BUY_STOP;
              Print("Auto-selected: BUY STOP (entry above Ask)");
          }
      } else {
          // SELL direction — auto pick Limit vs Stop based on price
          if(entryPrice > bid) {
              orderType = ORDER_TYPE_SELL_LIMIT;
              Print("Auto-selected: SELL LIMIT (entry above Bid)");
          } else {
              orderType = ORDER_TYPE_SELL_STOP;
              Print("Auto-selected: SELL STOP (entry below Bid)");
          }
      }

    // Validate SL direction
    if(g_previewDirection == 0 && slPrice >= entryPrice) {
        WriteLog("PLACE failed: BuyLimit SL=" +
                 DoubleToString(slPrice, _Digits) +
                 " must be below Entry=" +
                 DoubleToString(entryPrice, _Digits));
        return;
    }
    if(g_previewDirection == 1 && slPrice <= entryPrice) {
        WriteLog("PLACE failed: SellLimit SL=" +
                 DoubleToString(slPrice, _Digits) +
                 " must be above Entry=" +
                 DoubleToString(entryPrice, _Digits));
        return;
    }

    // Validate TP direction
    if(g_previewDirection == 0 && tpPrice <= entryPrice) {
        WriteLog("PLACE failed: BuyLimit TP=" +
                 DoubleToString(tpPrice, _Digits) +
                 " must be above Entry=" +
                 DoubleToString(entryPrice, _Digits));
        return;
    }
    if(g_previewDirection == 1 && tpPrice >= entryPrice) {
        WriteLog("PLACE failed: SellLimit TP=" +
                 DoubleToString(tpPrice, _Digits) +
                 " must be below Entry=" +
                 DoubleToString(entryPrice, _Digits));
        return;
    }

    // Remove preview before placing
    CancelPreview();

    // Place the order
    MqlTradeRequest req = {};
    MqlTradeResult  res = {};

    req.action       = TRADE_ACTION_PENDING;
    req.symbol       = _Symbol;
    req.volume       = g_previewLotSize;
    req.price        = entryPrice;
    req.sl           = slPrice;
    req.tp           = tpPrice;
    req.type         = orderType;
    req.deviation    = g_deviation;
    req.magic        = 202600;
    req.comment      = "AIV_LIMIT";
    req.type_filling = ORDER_FILLING_RETURN; // ← changed from IOC
    req.type_time    = ORDER_TIME_GTC;

    Print("OrderSend: action=PENDING type=", EnumToString(orderType),
          " vol=",   req.volume,
          " price=", req.price,
          " sl=",    req.sl,
          " tp=",    req.tp,
          " fill=",  EnumToString(req.type_filling));

    bool sent = OrderSend(req, res);

    Print("OrderSend result: sent=", sent,
          " retcode=", res.retcode,
          " order=",   res.order,
          " comment=", res.comment);

    if(sent && (res.retcode == TRADE_RETCODE_DONE ||
                res.retcode == TRADE_RETCODE_PLACED)) {
        WriteLog("LIMIT ORDER #" + IntegerToString(res.order) +
                 " PLACED: " +
                 ((g_previewDirection == 0) ? "BUY" : "SELL") +
                 " LIMIT @ " + DoubleToString(entryPrice, _Digits) +
                 "  Lot="    + DoubleToString(g_previewLotSize, 2) +
                 "  SL="     + DoubleToString(slPrice,    _Digits) +
                 "  TP="     + DoubleToString(tpPrice,    _Digits));

        DrawConfirmedLimitLines(res.order, entryPrice,
                                slPrice, tpPrice,
                                g_previewDirection);
    } else {
        WriteLog("LIMIT ORDER FAILED retcode=" +
                 IntegerToString(res.retcode) +
                 " (" + GetRetcodeDescription(res.retcode) + ")" +
                 " comment=" + res.comment);

        // Restore preview so user can try again
        DrawLimitPreview(entryPrice, g_previewDirection,
                         g_previewLotSize, g_previewSL, g_previewTP);
    }
}

//+------------------------------------------------------------------+
// Human readable retcode descriptions
//+------------------------------------------------------------------+
string GetRetcodeDescription(uint retcode) {
    switch(retcode) {
        case 10004: return "Requote";
        case 10006: return "Request rejected";
        case 10007: return "Request cancelled by trader";
        case 10008: return "Order placed";
        case 10009: return "Request completed";
        case 10010: return "Only part of request completed";
        case 10011: return "Request processing error";
        case 10012: return "Request cancelled by timeout";
        case 10013: return "Invalid request";
        case 10014: return "Invalid volume";
        case 10015: return "Invalid price";
        case 10016: return "Invalid SL or TP";
        case 10017: return "Trade disabled";
        case 10018: return "Market closed";
        case 10019: return "Insufficient funds";
        case 10020: return "Prices changed";
        case 10021: return "No quotes to process request";
        case 10022: return "Invalid order expiration";
        case 10023: return "Order state changed";
        case 10024: return "Too many requests";
        case 10025: return "No changes in request";
        case 10026: return "Autotrading disabled by server";
        case 10027: return "Autotrading disabled by client";
        case 10028: return "Request locked for processing";
        case 10029: return "Order or position frozen";
        case 10030: return "Invalid order fill type";
        case 10031: return "No connection with trade server";
        case 10032: return "Operation allowed only for live accounts";
        case 10033: return "Pending orders limit reached";
        case 10034: return "Order volume limit reached";
        case 10035: return "Incorrect or prohibited order type";
        case 10036: return "Position with specified ID already closed";
        case 10038: return "Close volume > open volume";
        case 10039: return "Close order already exists";
        default:    return "Unknown retcode " + IntegerToString(retcode);
    }
}


//+------------------------------------------------------------------+
// Draw confirmed (placed) limit order lines — locked, not draggable
//+------------------------------------------------------------------+
void DrawConfirmedLimitLines(ulong orderTicket, double entryPrice,
                             double slPrice, double tpPrice, int direction)
{
    color entryCol = (direction == 0) ? C'30,144,255' : C'255,100,100';
    string prefix  = "AIV_LMT_" + IntegerToString(orderTicket);
    string dirStr  = (direction == 0) ? "BUY LMT" : "SELL LMT";

    // Entry line
    string eName = prefix + "_E";
    ObjectDelete(0, eName);
    ObjectCreate(0, eName, OBJ_HLINE, 0, 0, entryPrice);
    ObjectSetInteger(0, eName, OBJPROP_COLOR,      entryCol);
    ObjectSetInteger(0, eName, OBJPROP_STYLE,      STYLE_DOT);
    ObjectSetInteger(0, eName, OBJPROP_WIDTH,      2);
    ObjectSetInteger(0, eName, OBJPROP_SELECTABLE, false);
    ObjectSetString (0, eName, OBJPROP_TEXT,
        dirStr + " #" + IntegerToString(orderTicket) +
        " @ " + DoubleToString(entryPrice, _Digits));

    // SL line
    string sName = prefix + "_S";
    ObjectDelete(0, sName);
    ObjectCreate(0, sName, OBJ_HLINE, 0, 0, slPrice);
    ObjectSetInteger(0, sName, OBJPROP_COLOR,      C'234,84,85');
    ObjectSetInteger(0, sName, OBJPROP_STYLE,      STYLE_DOT);
    ObjectSetInteger(0, sName, OBJPROP_WIDTH,      1);
    ObjectSetInteger(0, sName, OBJPROP_SELECTABLE, false);
    ObjectSetString (0, sName, OBJPROP_TEXT,       "SL @ " +
        DoubleToString(slPrice, _Digits));

    // TP line
    string tName = prefix + "_T";
    ObjectDelete(0, tName);
    ObjectCreate(0, tName, OBJ_HLINE, 0, 0, tpPrice);
    ObjectSetInteger(0, tName, OBJPROP_COLOR,      C'0,188,168');
    ObjectSetInteger(0, tName, OBJPROP_STYLE,      STYLE_DOT);
    ObjectSetInteger(0, tName, OBJPROP_WIDTH,      1);
    ObjectSetInteger(0, tName, OBJPROP_SELECTABLE, false);
    ObjectSetString (0, tName, OBJPROP_TEXT,       "TP @ " +
        DoubleToString(tpPrice, _Digits));

    ChartRedraw(0);
}

//+------------------------------------------------------------------+
// Remove all preview lines and reset state
//+------------------------------------------------------------------+
void CancelPreview() {
    ObjectDelete(0, "AIV_PRV_ENTRY");
    ObjectDelete(0, "AIV_PRV_SL");
    ObjectDelete(0, "AIV_PRV_TP");
    ObjectDelete(0, "AIV_PRV_RISK");
    g_previewActive = false;
    ChartRedraw(0);
    WriteLog("Preview cancelled.");
}

//+------------------------------------------------------------------+
// Cancel a specific pending order by ticket
// Pass ticket=0 to cancel ALL pending orders
//+------------------------------------------------------------------+
void CancelLimitOrder(ulong ticket) {
    if(ticket > 0) {
        // Cancel specific order
        if(g_trade.OrderDelete(ticket)) {
            WriteLog("Pending order #" + IntegerToString(ticket) + " cancelled.");

            string prefix = "AIV_LMT_" + IntegerToString(ticket);
            ObjectDelete(0, prefix + "_E");
            ObjectDelete(0, prefix + "_S");
            ObjectDelete(0, prefix + "_T");
            ChartRedraw(0);
        } else {
            WriteLog("Cancel failed #" + IntegerToString(ticket) +
                     " [" + IntegerToString(g_trade.ResultRetcode()) + "]: " +
                     g_trade.ResultComment());
        }
        return;
    }

    // Cancel ALL pending orders (magic=202600 only)
    int total = OrdersTotal();
    if(total == 0) {
        WriteLog("No pending orders to cancel.");
        return;
    }

    int cancelled = 0;
    for(int i = total - 1; i >= 0; i--) {
        ulong t = OrderGetTicket(i);
        if(t == 0) continue;

        // Only cancel orders placed by this EA
        if(OrderGetInteger(ORDER_MAGIC) != 202600) continue;

        if(g_trade.OrderDelete(t)) {
            cancelled++;
            WriteLog("Cancelled #" + IntegerToString(t));

            string prefix = "AIV_LMT_" + IntegerToString(t);
            ObjectDelete(0, prefix + "_E");
            ObjectDelete(0, prefix + "_S");
            ObjectDelete(0, prefix + "_T");
        } else {
            WriteLog("Cancel failed #" + IntegerToString(t) +
                     " [" + IntegerToString(g_trade.ResultRetcode()) + "]: " +
                     g_trade.ResultComment());
        }
    }

    ChartRedraw(0);
    WriteLog("Cancelled " + IntegerToString(cancelled) +
             " of " + IntegerToString(total) + " pending orders.");
}
