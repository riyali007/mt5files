//+------------------------------------------------------------------+
//|  BacktestBridge Core (Simulator Bridge ONLY)                     |
//|  Bridge between MT5 Strategy Tester and WPF Control Panel        |
//+------------------------------------------------------------------+
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//--- Input Parameters
input ulong  InpMagicNumber   = 202600; // Magic Number (Change to clear tester cache)
input string InpPipeName      = "\\\\.\\pipe\\AIVBacktest";
input double InpLotSize       = 0.50;
input int    InpSL            = 200;
input int    InpTotalTP       = 400;
input int    InpTPLevels      = 3;
input int    InpDeviation     = 50;

// ── Bridge Partial TP + BE settings 
input bool   InpAutoPartials  = true;
input int    InpBEAfterLevel  = 1;
input int    InpBEOffsetPts   = 5;

// ── TM3 Advanced Trade Management (EA Side Only) ──
input group "TM3 Volume & Trailing Settings"
input double InpMainPartialVol    = 40.0; // 1st Partial % of current volume
input double InpRollingPartialVol = 20.0; // Subsequent Partials % of current volume
input bool   InpUseTrailingStop   = false;
input int    InpTrailingStart     = 150;
input int    InpTrailingStep      = 50;

//--- Packet Type Constants (uchar)
#define PKT_TICK          1
#define PKT_TRADE         2
#define PKT_POSITIONS     3
#define PKT_LOG           4
#define PKT_STATUS        5
#define PKT_TRADE_RESULT  6

//--- Command Type Constants (uchar)
#define CMD_NONE             0
#define CMD_START            1
#define CMD_PAUSE            2
#define CMD_RESUME           3
#define CMD_BUY              4
#define CMD_SELL             5
#define CMD_CLOSE            6
#define CMD_CLOSE_ALL        7
#define CMD_SET_PARAMS       8
#define CMD_SET_SL_BE        9
#define CMD_TAKE_PARTIAL     10
#define PIPE_TIMEOUT_MS      3000

#define CMD_DRAW_HLINE       11
#define CMD_DRAW_TLINE       12
#define CMD_DRAW_RAY         13
#define CMD_CLEAR_DRAWINGS   14
#define CMD_PREVIEW_LIMIT    15
#define CMD_PLACE_LIMIT      16
#define CMD_CANCEL_PREVIEW   17
#define CMD_CANCEL_LIMIT     18

//--- Structs
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
    uchar    PacketType;
    ulong    Ticket;
    int      PositionType;
    double   Volume;
    double   OpenPrice;
    double   CurrentPrice;
    double   SL;
    double   TP;
    double   Profit;
    char     Symbol[20];
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
    int    DevPoints;
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
    double   LimitPrice;
    int      OrderDirection;
};

struct PartialState {
    ulong  Ticket;
    int    LevelsHit;
    bool   BESet;
    double EntryPrice;
    int    PositionType;
    double OriginalVolume;
};

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
    char     Symbol[20];
};

//--- Global Objects & State Variables
CTrade       g_trade;
CSymbolInfo  g_sym;
PartialState g_partials[];
int          g_pipeHandle  = INVALID_HANDLE;
bool         g_isPaused    = true;
double       g_lotSize;
int          g_sl;
int          g_totalTP;
int          g_tpLevels;
int          g_deviation;
uint         g_lastTick    = 0;
int          g_beAfterLevel;
int          g_beOffsetPts;
uint         g_lastReplyTime = 0;
bool         g_previewActive    = false;
int          g_previewDirection = 0;
double       g_previewLotSize   = 0;
int          g_previewSL        = 0;
int          g_previewTP        = 0;
int          g_drawCounter      = 0;

//+------------------------------------------------------------------+
int OnInit() {
    g_lotSize      = InpLotSize;
    g_sl           = InpSL;
    g_totalTP      = InpTotalTP;
    g_tpLevels     = InpTPLevels;
    g_deviation    = InpDeviation;
    g_beAfterLevel = InpBEAfterLevel;
    g_beOffsetPts  = InpBEOffsetPts;

    g_trade.SetExpertMagicNumber(InpMagicNumber);
    g_trade.SetDeviationInPoints(g_deviation);
    g_trade.SetTypeFilling(ORDER_FILLING_IOC);
    g_sym.Name(_Symbol);

    bool inTester = (bool)MQLInfoInteger(MQL_TESTER);
    if(!inTester) EventSetMillisecondTimer(50);
    Print("Bridge initialized. Pipe: ", InpPipeName, " | Magic: ", InpMagicNumber);
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    RemoveAllLines();
    if(g_pipeHandle != INVALID_HANDLE) {
        FileClose(g_pipeHandle);
        g_pipeHandle = INVALID_HANDLE;
    }
    bool inTester = (bool)MQLInfoInteger(MQL_TESTER);
    if(!inTester) EventKillTimer();
}

//+------------------------------------------------------------------+
void OnTick() {
    bool inTester = (bool)MQLInfoInteger(MQL_TESTER);
    if(!inTester) return;

    g_sym.RefreshRates();
    
    // Core Trade Management
    CheckPartials();
    ManageTrailingStop();

    uint now = GetTickCount();
    if((now - g_lastTick) < 50) return;
    g_lastTick = now;

    ProcessPipe();
}

//+------------------------------------------------------------------+
void OnTimer() {
    bool inTester = (bool)MQLInfoInteger(MQL_TESTER);
    if(inTester) return;

    g_sym.RefreshRates();
    
    // Core Trade Management
    CheckPartials();
    ManageTrailingStop();
    
    ProcessPipe();
}

//+------------------------------------------------------------------+
// CORE TM3 TRAILING STOP LOGIC
//+------------------------------------------------------------------+
double NormaliseSL(double price) {
    double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    if(tick > 0) price = MathRound(price / tick) * tick;
    return price;
}

void ManageTrailingStop() {
    if(!InpUseTrailingStop) return;

    for(int i = ArraySize(g_partials) - 1; i >= 0; i--) {
        ulong ticket = g_partials[i].Ticket;
        CPositionInfo pos;
        if(!pos.SelectByTicket(ticket)) continue;

        double open   = pos.PriceOpen();
        double curSL  = pos.StopLoss();
        double curTP  = pos.TakeProfit();
        double pt     = _Point;
        bool   isBuy  = (pos.PositionType() == POSITION_TYPE_BUY);

        if(isBuy) {
            double bid = g_sym.Bid();
            double profit = bid - open;
            if(profit < InpTrailingStart * pt) continue;

            double target = NormaliseSL(bid - InpTrailingStep * pt);
            if(curSL <= 0 || target > curSL + pt)
                g_trade.PositionModify(ticket, target, curTP);
        } else {
            double ask = g_sym.Ask();
            double profit = open - ask;
            if(profit < InpTrailingStart * pt) continue;

            double target = NormaliseSL(ask + InpTrailingStep * pt);
            if(curSL <= 0 || target < curSL - pt)
                g_trade.PositionModify(ticket, target, curTP);
        }
    }
}


//+------------------------------------------------------------------+
// COMMUNICATION & COMMAND PROCESSING
//+------------------------------------------------------------------+
void ProcessPipe() {
    if(g_pipeHandle == INVALID_HANDLE) {
        g_pipeHandle = FileOpen(InpPipeName, FILE_READ | FILE_WRITE | FILE_BIN | FILE_ANSI);
        if(g_pipeHandle == INVALID_HANDLE) return;
        Print("WPF Connected.");
        g_lastReplyTime = GetTickCount();
        SendStatus();
        return;
    }

    if(GetTickCount() - g_lastReplyTime > PIPE_TIMEOUT_MS) {
        FileClose(g_pipeHandle);
        g_pipeHandle = INVALID_HANDLE;
        return;
    }

    SendTickData();
    CommandPacket cmd;
    uint read = FileReadStruct(g_pipeHandle, cmd);
    if(read != sizeof(CommandPacket)) {
        FileClose(g_pipeHandle);
        g_pipeHandle = INVALID_HANDLE;
        return;
    }

    g_lastReplyTime = GetTickCount();
    if(cmd.CmdType != CMD_NONE) {
        ProcessCommand(cmd);
    }
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
    pkt.Spread     = (double)g_sym.Spread(); 
    pkt.OpenPL     = openPL;
    pkt.Balance    = AccountInfoDouble(ACCOUNT_BALANCE);
    pkt.Equity     = AccountInfoDouble(ACCOUNT_EQUITY);
    pkt.ServerTime = (long)TimeCurrent();
    FileWriteStruct(g_pipeHandle, pkt);
}

//+------------------------------------------------------------------+
void SendPositions() {
    PositionsCountPacket cntPkt;
    cntPkt.PacketType = PKT_POSITIONS; cntPkt.Count = PositionsTotal();
    FileWriteStruct(g_pipeHandle, cntPkt);
    for(int i = 0; i < PositionsTotal(); i++) {
        CPositionInfo pos;
        if(!pos.SelectByIndex(i)) continue;
        TradePacket pkt; pkt.PacketType = PKT_TRADE; pkt.Ticket = pos.Ticket();
        ENUM_POSITION_TYPE posType = pos.PositionType();
        pkt.PositionType = (posType == POSITION_TYPE_BUY) ? 0 : 1;
        pkt.Volume = pos.Volume(); pkt.OpenPrice = pos.PriceOpen(); pkt.CurrentPrice = pos.PriceCurrent();
        pkt.SL = pos.StopLoss(); pkt.TP = pos.TakeProfit();
        pkt.Profit = pos.Profit();
        int symLen = StringLen(pos.Symbol()); if(symLen > 19) symLen = 19;
        for(int c = 0; c < symLen; c++) pkt.Symbol[c] = (char)StringGetCharacter(pos.Symbol(), c);
        pkt.Symbol[symLen] = 0;
        FileWriteStruct(g_pipeHandle, pkt);
    }
}

//+------------------------------------------------------------------+
void SendStatus() {
    StatusPacket spkt; 
    spkt.PacketType = PKT_STATUS; 
    spkt.IsPaused = g_isPaused ? 1 : 0;
    spkt.LotSize = g_lotSize; 
    spkt.SL = g_sl; 
    spkt.TotalTP = g_totalTP; 
    spkt.TPLevels = g_tpLevels; 
    spkt.DevPoints = g_deviation;
    FileWriteStruct(g_pipeHandle, spkt); 
    FileFlush(g_pipeHandle);
    
    CommandPacket reply;
    FileReadStruct(g_pipeHandle, reply);
}

//+------------------------------------------------------------------+
void WriteLog(string msg) {
    Print(msg); 
    if(g_pipeHandle == INVALID_HANDLE) return;
    LogPacket lpkt; 
    lpkt.PacketType = PKT_LOG;
    int len = StringLen(msg); 
    if(len > 199) len = 199;
    for(int i = 0; i < len; i++) lpkt.Message[i] = (char)StringGetCharacter(msg, i);
    lpkt.Message[len] = 0; 
    FileWriteStruct(g_pipeHandle, lpkt); 
    FileFlush(g_pipeHandle);
    
    CommandPacket reply;
    FileReadStruct(g_pipeHandle, reply);
}

//+------------------------------------------------------------------+
void ProcessCommand(CommandPacket &cmd) {
    int cmdType = (int)cmd.CmdType; 
    if(cmdType == CMD_NONE) return;
    if(cmd.LotSize > 0) g_lotSize = cmd.LotSize;
    if(cmd.SL > 0) g_sl = cmd.SL;
    if(cmd.TotalTP > 0) g_totalTP = cmd.TotalTP;
    if(cmd.TPLevels > 0) g_tpLevels = cmd.TPLevels;
    if(cmd.DevPoints > 0) g_deviation = cmd.DevPoints;
    if(cmd.BEAfterLevel > 0) g_beAfterLevel = cmd.BEAfterLevel;
    if(cmd.BEOffsetPoints > 0) g_beOffsetPts = cmd.BEOffsetPoints;
    
    g_trade.SetDeviationInPoints(g_deviation);

    if(cmdType == CMD_START) { g_isPaused = false; WriteLog("Backtest STARTED"); SendStatus(); }
    else if(cmdType == CMD_PAUSE) { g_isPaused = true; WriteLog("Backtest PAUSED"); SendStatus(); }
    else if(cmdType == CMD_RESUME) { g_isPaused = false; WriteLog("Backtest RESUMED"); SendStatus(); }
    else if(cmdType == CMD_BUY) { if(!g_isPaused) ExecuteBuy(); else WriteLog("Cannot BUY - EA is paused"); }
    else if(cmdType == CMD_SELL) { if(!g_isPaused) ExecuteSell(); else WriteLog("Cannot SELL - EA is paused"); }
    else if(cmdType == CMD_CLOSE) { ClosePositionByTicket(cmd.TicketToClose); }
    else if(cmdType == CMD_CLOSE_ALL) { CloseAllPositions(); }
    else if(cmdType == CMD_SET_PARAMS) { SendStatus(); }
    else if(cmdType == CMD_SET_SL_BE) {
        if(cmd.TicketToClose > 0) ManualSetBE(cmd.TicketToClose, cmd.BEOffsetPoints);
        else { for(int i=0; i<PositionsTotal(); i++) { CPositionInfo pos; if(pos.SelectByIndex(i)) ManualSetBE(pos.Ticket(), cmd.BEOffsetPoints); } }
    }
    else if(cmdType == CMD_TAKE_PARTIAL) {
        double pct = cmd.PartialPercent;
        if(pct <= 0 || pct > 100) pct = 50.0;
        if(cmd.TicketToClose > 0) ManualPartialClose(cmd.TicketToClose, pct);
        else { for(int i=PositionsTotal()-1; i>=0; i--) { CPositionInfo pos; if(pos.SelectByIndex(i)) ManualPartialClose(pos.Ticket(), pct); } }
    }
    else if(cmdType == CMD_DRAW_HLINE) { DrawFreeHLine(cmd.DrawPrice1, cmd.DrawColor, cmd.DrawStyle, cmd.DrawWidth); }
    else if(cmdType == CMD_DRAW_TLINE) { DrawFreeTLine(cmd.DrawPrice1, cmd.DrawPrice2, cmd.DrawColor, cmd.DrawStyle, cmd.DrawWidth); }
    else if(cmdType == CMD_CLEAR_DRAWINGS) { ClearFreeDrawings(); }
    else if(cmdType == CMD_PREVIEW_LIMIT) { DrawLimitPreview(cmd.LimitPrice, cmd.OrderDirection, cmd.LotSize > 0 ? cmd.LotSize : g_lotSize, cmd.SL > 0 ? cmd.SL : g_sl, cmd.TotalTP > 0 ? cmd.TotalTP  : g_totalTP); }
    else if(cmdType == CMD_PLACE_LIMIT) { PlaceLimitOrder(); }
    else if(cmdType == CMD_CANCEL_PREVIEW) { CancelPreview(); }
    else if(cmdType == CMD_CANCEL_LIMIT) { CancelLimitOrder(cmd.TicketToClose); }
}

//+------------------------------------------------------------------+
// TRADE EXECUTION
//+------------------------------------------------------------------+
void ExecuteBuy() {
    if(!IsMarketOpen()) return;
    g_sym.RefreshRates(); double ask = g_sym.Ask();
    double slPrice = NormalizeDouble(ask - g_sl * _Point, _Digits);
    double tpPrice = NormalizeDouble(ask + g_totalTP * _Point, _Digits);

    if(g_trade.Buy(g_lotSize, _Symbol, ask, slPrice, tpPrice, "AIV_BUY")) {
        ulong ticket = g_trade.ResultOrder();
        WriteLog("BUY OK #" + IntegerToString(ticket) + " Lot=" + DoubleToString(g_lotSize, 2) + " @ " + DoubleToString(ask, _Digits));
        DrawPartialLines(ticket, POSITION_TYPE_BUY, ask);
        RegisterPosition(ticket, POSITION_TYPE_BUY, ask, g_lotSize);
    } else { WriteLog("BUY failed [" + IntegerToString(g_trade.ResultRetcode()) + "]: " + g_trade.ResultComment()); }
}

void ExecuteSell() {
    if(!IsMarketOpen()) return;
    g_sym.RefreshRates(); double bid = g_sym.Bid();
    double slPrice = NormalizeDouble(bid + g_sl * _Point, _Digits);
    double tpPrice = NormalizeDouble(bid - g_totalTP * _Point, _Digits);
    
    if(g_trade.Sell(g_lotSize, _Symbol, bid, slPrice, tpPrice, "AIV_SELL")) {
        ulong ticket = g_trade.ResultOrder();
        WriteLog("SELL OK #" + IntegerToString(ticket) + " Lot=" + DoubleToString(g_lotSize, 2) + " @ " + DoubleToString(bid, _Digits));
        DrawPartialLines(ticket, POSITION_TYPE_SELL, bid);
        RegisterPosition(ticket, POSITION_TYPE_SELL, bid, g_lotSize);
    } else { WriteLog("SELL failed [" + IntegerToString(g_trade.ResultRetcode()) + "]: " + g_trade.ResultComment()); }
}

void ClosePositionByTicket(ulong ticket) {
    CPositionInfo pos; if(pos.SelectByTicket(ticket)) {
        if(g_trade.PositionClose(ticket, g_deviation)) { WriteLog("Closed #" + IntegerToString(ticket));
        RemovePartialLines(ticket); UnregisterPosition(ticket); }
    }
}

void CloseAllPositions() {
    for(int i = PositionsTotal() - 1; i >= 0; i--) { 
        CPositionInfo pos;
        if(pos.SelectByIndex(i)) { 
            ulong ticket = pos.Ticket();
            if(g_trade.PositionClose(ticket, g_deviation)) { 
                RemovePartialLines(ticket);
                UnregisterPosition(ticket); 
            } 
        } 
    }
}

bool IsMarketOpen() {
    datetime now = TimeCurrent();
    MqlTick lastTick; if(!SymbolInfoTick(_Symbol, lastTick)) return false;
    ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
    if(tradeMode == SYMBOL_TRADE_MODE_DISABLED || tradeMode == SYMBOL_TRADE_MODE_CLOSEONLY) return false;
    double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point; if(spread > 50 * _Point) return false;
    return true;
}

//+------------------------------------------------------------------+
// CHART VISUALIZATIONS (Lines and Previews)
//+------------------------------------------------------------------+
void DrawPartialLines(ulong ticket, int posType, double entryPrice) {
    if(g_tpLevels < 1) return;
    double direction = (posType == POSITION_TYPE_BUY) ? 1.0 : -1.0;
    
    // Matched to TM3 Math (Divide by g_tpLevels + 1)
    double tpStep = (double)g_totalTP / (g_tpLevels + 1);
    
    for(int i = 1; i <= g_tpLevels; i++) {
        double tpPrice = NormalizeDouble(entryPrice + direction * tpStep * i * _Point, _Digits);
        string name = "AIV_TP_" + IntegerToString(ticket) + "_" + IntegerToString(i); 
        int pct = (i == 1) ? (int)InpMainPartialVol : (int)InpRollingPartialVol;
        string label = "TP" + IntegerToString(i) + " +" + IntegerToString((int)(tpStep * i)) + " pts (" + IntegerToString(pct) + "%)";
        
        ObjectDelete(0, name); ObjectCreate(0, name, OBJ_HLINE, 0, 0, tpPrice); ObjectSetInteger(0, name, OBJPROP_COLOR, clrLimeGreen);
        ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH); ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true); ObjectSetInteger(0, name, OBJPROP_BACK, true); ObjectSetString(0, name, OBJPROP_TEXT, label);
    }
    string slName = "AIV_SL_" + IntegerToString(ticket);
    double slPrice = NormalizeDouble(entryPrice - direction * g_sl * _Point, _Digits);
    ObjectDelete(0, slName); ObjectCreate(0, slName, OBJ_HLINE, 0, 0, slPrice);
    ObjectSetInteger(0, slName, OBJPROP_COLOR, clrTomato);
    ObjectSetInteger(0, slName, OBJPROP_STYLE, STYLE_DASH); ObjectSetInteger(0, slName, OBJPROP_WIDTH, 2); ObjectSetInteger(0, slName, OBJPROP_SELECTABLE, true); ObjectSetInteger(0, slName, OBJPROP_BACK, true);
    ObjectSetString(0, slName, OBJPROP_TEXT, "SL  -" + IntegerToString(g_sl) + " pts");
    string entryName = "AIV_ENTRY_" + IntegerToString(ticket); ObjectDelete(0, entryName);
    ObjectCreate(0, entryName, OBJ_HLINE, 0, 0, entryPrice);
    ObjectSetInteger(0, entryName, OBJPROP_COLOR, clrDodgerBlue); ObjectSetInteger(0, entryName, OBJPROP_STYLE, STYLE_DOT); ObjectSetInteger(0, entryName, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, entryName, OBJPROP_SELECTABLE, false); ObjectSetInteger(0, entryName, OBJPROP_BACK, true); ObjectSetString(0, entryName, OBJPROP_TEXT, "ENTRY @ " + DoubleToString(entryPrice, _Digits)); ChartRedraw(0);
}

void RemovePartialLines(ulong ticket) {
    for(int i = 1; i <= 20; i++) { ObjectDelete(0, "AIV_TP_" + IntegerToString(ticket) + "_" + IntegerToString(i)); }
    ObjectDelete(0, "AIV_SL_" + IntegerToString(ticket)); ObjectDelete(0, "AIV_ENTRY_" + IntegerToString(ticket)); ChartRedraw(0);
}

void RemoveAllLines() {
    int total = ObjectsTotal(0);
    for(int i = total - 1; i >= 0; i--) { 
        string name = ObjectName(0, i);
        if(StringFind(name, "AIV_") == 0) ObjectDelete(0, name); 
    } 
    ChartRedraw(0);
}

void DrawFreeHLine(double price, int colorVal, int styleVal, int widthVal) { g_drawCounter++; string name = "AIV_DRAW_" + IntegerToString(g_drawCounter); ObjectDelete(0, name);
    ObjectCreate(0, name, OBJ_HLINE, 0, 0, price); ObjectSetInteger(0, name, OBJPROP_COLOR, (color)colorVal);
    ObjectSetInteger(0, name, OBJPROP_STYLE, (styleVal == 1) ? STYLE_DASH : (styleVal == 2) ? STYLE_DOT : STYLE_SOLID); ObjectSetInteger(0, name, OBJPROP_WIDTH, widthVal);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true); ChartRedraw(0); }

void DrawFreeTLine(double price1, double price2, int colorVal, int styleVal, int widthVal) { g_drawCounter++;
    string name = "AIV_DRAW_" + IntegerToString(g_drawCounter); datetime t1 = iTime(_Symbol, PERIOD_CURRENT, 10); datetime t2 = iTime(_Symbol, PERIOD_CURRENT, 0); ObjectDelete(0, name);
    ObjectCreate(0, name, OBJ_TREND, 0, t1, price1, t2, price2); ObjectSetInteger(0, name, OBJPROP_COLOR, (color)colorVal);
    ObjectSetInteger(0, name, OBJPROP_STYLE, (styleVal == 1) ? STYLE_DASH : (styleVal == 2) ? STYLE_DOT : STYLE_SOLID); ObjectSetInteger(0, name, OBJPROP_WIDTH, widthVal);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true); ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true); ChartRedraw(0); }

void ClearFreeDrawings() { int total = ObjectsTotal(0);
    for(int i = total - 1; i >= 0; i--) { string name = ObjectName(0, i);
    if(StringFind(name, "AIV_DRAW_") == 0) ObjectDelete(0, name); } g_drawCounter = 0; ChartRedraw(0);
}

void DrawLimitPreview(double limitPrice, int direction, double lotSize, int slPts, int tpPts) {
    g_previewActive = true;
    g_previewDirection = direction; g_previewLotSize = lotSize; g_previewSL = slPts; g_previewTP = tpPts;
    double dir = (direction == 0) ? 1.0 : -1.0; double slPrice = NormalizeDouble(limitPrice - dir * slPts * _Point, _Digits);
    double tpPrice = NormalizeDouble(limitPrice + dir * tpPts * _Point, _Digits); color entryCol = (direction == 0) ? C'30,144,255' : C'255,100,100';
    ObjectDelete(0, "AIV_PRV_ENTRY"); ObjectCreate(0, "AIV_PRV_ENTRY", OBJ_HLINE, 0, 0, limitPrice); ObjectSetInteger(0, "AIV_PRV_ENTRY", OBJPROP_COLOR, entryCol); ObjectSetInteger(0, "AIV_PRV_ENTRY", OBJPROP_WIDTH, 2);
    ObjectSetInteger(0, "AIV_PRV_ENTRY", OBJPROP_SELECTABLE, true); ObjectSetString(0, "AIV_PRV_ENTRY", OBJPROP_TEXT, "LIMIT " + DoubleToString(lotSize, 2) + " @ " + DoubleToString(limitPrice, _Digits));
    ObjectDelete(0, "AIV_PRV_SL"); ObjectCreate(0, "AIV_PRV_SL", OBJ_HLINE, 0, 0, slPrice); ObjectSetInteger(0, "AIV_PRV_SL", OBJPROP_COLOR, C'234,84,85'); ObjectSetInteger(0, "AIV_PRV_SL", OBJPROP_STYLE, STYLE_DASH); ObjectSetInteger(0, "AIV_PRV_SL", OBJPROP_WIDTH, 2);
    ObjectSetInteger(0, "AIV_PRV_SL", OBJPROP_SELECTABLE, true);
    ObjectDelete(0, "AIV_PRV_TP"); ObjectCreate(0, "AIV_PRV_TP", OBJ_HLINE, 0, 0, tpPrice); ObjectSetInteger(0, "AIV_PRV_TP", OBJPROP_COLOR, C'0,188,168'); ObjectSetInteger(0, "AIV_PRV_TP", OBJPROP_STYLE, STYLE_DASH);
    ObjectSetInteger(0, "AIV_PRV_TP", OBJPROP_WIDTH, 2); ObjectSetInteger(0, "AIV_PRV_TP", OBJPROP_SELECTABLE, true); ChartRedraw(0);
}

void PlaceLimitOrder() {
    if(!g_previewActive) return;
    double entryPrice = NormalizeDouble(ObjectGetDouble(0, "AIV_PRV_ENTRY", OBJPROP_PRICE), _Digits);
    double slPrice = NormalizeDouble(ObjectGetDouble(0, "AIV_PRV_SL", OBJPROP_PRICE), _Digits);
    double tpPrice = NormalizeDouble(ObjectGetDouble(0, "AIV_PRV_TP", OBJPROP_PRICE), _Digits);
    
    if(entryPrice <= 0 || slPrice <= 0 || tpPrice <= 0 || g_previewLotSize <= 0) return;
    g_sym.RefreshRates(); ENUM_ORDER_TYPE orderType;
    if(g_previewDirection == 0) orderType = (entryPrice < g_sym.Ask()) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_BUY_STOP;
    else orderType = (entryPrice > g_sym.Bid()) ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_SELL_STOP;
    
    CancelPreview();
    
    MqlTradeRequest req = {}; 
    MqlTradeResult res = {};
    req.action = TRADE_ACTION_PENDING; 
    req.symbol = _Symbol; 
    req.volume = g_previewLotSize; 
    req.price = entryPrice; 
    req.sl = slPrice; 
    req.tp = tpPrice;
    req.type = orderType; 
    req.deviation = g_deviation; 
    req.magic = InpMagicNumber; 
    req.type_filling = ORDER_FILLING_RETURN;
    req.type_time = ORDER_TIME_GTC;
    
    if(OrderSend(req, res)) DrawConfirmedLimitLines(res.order, entryPrice, slPrice, tpPrice, g_previewDirection);
}

void DrawConfirmedLimitLines(ulong orderTicket, double entryPrice, double slPrice, double tpPrice, int direction) {
    color entryCol = (direction == 0) ? C'30,144,255' : C'255,100,100'; string prefix = "AIV_LMT_" + IntegerToString(orderTicket);
    ObjectDelete(0, prefix + "_E");
    ObjectCreate(0, prefix + "_E", OBJ_HLINE, 0, 0, entryPrice); ObjectSetInteger(0, prefix + "_E", OBJPROP_COLOR, entryCol); ObjectSetInteger(0, prefix + "_E", OBJPROP_STYLE, STYLE_DOT);
    ObjectSetInteger(0, prefix + "_E", OBJPROP_WIDTH, 2);
    ObjectDelete(0, prefix + "_S"); ObjectCreate(0, prefix + "_S", OBJ_HLINE, 0, 0, slPrice);
    ObjectSetInteger(0, prefix + "_S", OBJPROP_COLOR, C'234,84,85'); ObjectSetInteger(0, prefix + "_S", OBJPROP_STYLE, STYLE_DOT);
    ObjectDelete(0, prefix + "_T");
    ObjectCreate(0, prefix + "_T", OBJ_HLINE, 0, 0, tpPrice); ObjectSetInteger(0, prefix + "_T", OBJPROP_COLOR, C'0,188,168'); ObjectSetInteger(0, prefix + "_T", OBJPROP_STYLE, STYLE_DOT);
    ChartRedraw(0);
}

void CancelPreview() { ObjectDelete(0, "AIV_PRV_ENTRY"); ObjectDelete(0, "AIV_PRV_SL"); ObjectDelete(0, "AIV_PRV_TP"); g_previewActive = false; ChartRedraw(0); }

void CancelLimitOrder(ulong ticket) { 
    if(ticket > 0) { 
        if(g_trade.OrderDelete(ticket)) { 
            ObjectDelete(0, "AIV_LMT_" + IntegerToString(ticket) + "_E");
            ObjectDelete(0, "AIV_LMT_" + IntegerToString(ticket) + "_S"); 
            ObjectDelete(0, "AIV_LMT_" + IntegerToString(ticket) + "_T");
        } 
    } else { 
        for(int i = OrdersTotal() - 1; i >= 0; i--) { 
            ulong t = OrderGetTicket(i);
            if(t > 0 && OrderGetInteger(ORDER_MAGIC) == InpMagicNumber) { 
                if(g_trade.OrderDelete(t)) { 
                    ObjectDelete(0, "AIV_LMT_" + IntegerToString(t) + "_E");
                    ObjectDelete(0, "AIV_LMT_" + IntegerToString(t) + "_S"); 
                    ObjectDelete(0, "AIV_LMT_" + IntegerToString(t) + "_T");
                } 
            } 
        } 
    } 
    ChartRedraw(0);
}

//+------------------------------------------------------------------+
// CORE TM3 PARTIALS AND BREAK-EVEN LOGIC
//+------------------------------------------------------------------+
void RegisterPosition(ulong ticket, int posType, double entryPrice, double volume) {
    int size = ArraySize(g_partials);
    ArrayResize(g_partials, size + 1);
    g_partials[size].Ticket = ticket; g_partials[size].LevelsHit = 0; g_partials[size].BESet = false;
    g_partials[size].EntryPrice = entryPrice; g_partials[size].PositionType = posType;
    g_partials[size].OriginalVolume = volume;
}

void UnregisterPosition(ulong ticket) {
    int size = ArraySize(g_partials);
    for(int i = 0; i < size; i++) { 
        if(g_partials[i].Ticket == ticket) { 
            for(int j = i; j < size - 1; j++) { g_partials[j] = g_partials[j + 1]; } 
            ArrayResize(g_partials, size - 1); 
            return;
        } 
    }
}

int FindPartialIndex(ulong ticket) { 
    for(int i = 0; i < ArraySize(g_partials); i++) { 
        if(g_partials[i].Ticket == ticket) return i;
    } 
    return -1; 
}

void CheckPartials() {
    if(!InpAutoPartials || ArraySize(g_partials) == 0) return;
    
    for(int i = ArraySize(g_partials) - 1; i >= 0; i--) {
        PartialState ps = g_partials[i];
        CPositionInfo pos; 
        
        if(!pos.SelectByTicket(ps.Ticket)) { 
            UnregisterPosition(ps.Ticket); 
            RemovePartialLines(ps.Ticket); 
            continue; 
        }

        double currentPrice = (ps.PositionType == POSITION_TYPE_BUY) ? g_sym.Bid() : g_sym.Ask();
        double direction = (ps.PositionType == POSITION_TYPE_BUY) ? 1.0 : -1.0;
        
        double posTP = pos.TakeProfit(); 
        double totalTPprice = (posTP > 0) ? MathAbs(posTP - ps.EntryPrice) : g_totalTP * _Point;
        
        // TM3 Step Math: Divide by (Levels + 1)
        double tpStep = (g_tpLevels > 0) ? totalTPprice / (g_tpLevels + 1) : totalTPprice;
        
        int nextPartial = ps.LevelsHit + 1;
        
        if(nextPartial <= g_tpLevels) {
            double tpPrice = NormalizeDouble(ps.EntryPrice + direction * tpStep * nextPartial, _Digits);
            bool levelHit = (ps.PositionType == POSITION_TYPE_BUY) ? (currentPrice >= tpPrice) : (currentPrice <= tpPrice);
            
            if(levelHit) {
                // TM3 Volume Logic
                double pct = (nextPartial == 1) ? InpMainPartialVol : InpRollingPartialVol;
                double closeVol = NormalizeDouble(pos.Volume() * (pct * 0.01), 2);
                
                double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN); 
                double stepVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
                
                closeVol = MathFloor(closeVol / stepVol) * stepVol; 
                if(closeVol < minVol) closeVol = minVol; 
                if(closeVol >= pos.Volume()) closeVol = pos.Volume();
                
                if(g_trade.PositionClosePartial(ps.Ticket, closeVol, g_deviation)) {
                    g_partials[i].LevelsHit = nextPartial;
                    WriteLog("Partial TP" + IntegerToString(nextPartial) + " closed " + DoubleToString(closeVol, 2));
                    
                    ObjectDelete(0, "AIV_TP_" + IntegerToString(ps.Ticket) + "_" + IntegerToString(nextPartial)); 
                    ChartRedraw(0);
                    
                    // TM3 Break-Even Logic
                    if(g_beAfterLevel > 0 && nextPartial == g_beAfterLevel && !ps.BESet) {
                        // Re-select position to get fresh SL/TP
                        if(pos.SelectByTicket(ps.Ticket)) {
                            double bePrice = NormalizeDouble(ps.EntryPrice + direction * g_beOffsetPts * _Point, _Digits);
                            double freshSL = pos.StopLoss();
                            
                            // Check if target BE is better than current SL
                            bool better = (ps.PositionType == POSITION_TYPE_BUY) ? (bePrice > freshSL) : (freshSL == 0 || bePrice < freshSL);
                            
                            if(better) {
                                if(g_trade.PositionModify(ps.Ticket, bePrice, pos.TakeProfit())) {
                                    g_partials[i].BESet = true;
                                    WriteLog("SL → BE");
                                    string slName = "AIV_SL_" + IntegerToString(ps.Ticket); 
                                    ObjectSetDouble(0, slName, OBJPROP_PRICE, bePrice); 
                                    ObjectSetString(0, slName, OBJPROP_TEXT, "BE SL");
                                    ObjectSetInteger(0, slName, OBJPROP_COLOR, clrGold); 
                                    ChartRedraw(0);
                                }
                            } else {
                                g_partials[i].BESet = true; // Mark set even if SL is already better
                            }
                        }
                    }
                }
            }
        }
    }
}

void ManualSetBE(ulong ticket, int offsetPts) {
    CPositionInfo pos;
    if(!pos.SelectByTicket(ticket)) return;
    int idx = FindPartialIndex(ticket); int useOffset = (offsetPts > 0) ? offsetPts : g_beOffsetPts;
    double direction = (pos.PositionType() == POSITION_TYPE_BUY) ? 1.0 : -1.0;
    double entryPrice = (idx >= 0) ? g_partials[idx].EntryPrice : pos.PriceOpen();
    double bePrice = NormalizeDouble(entryPrice + direction * useOffset * _Point, _Digits);
    
    if(g_trade.PositionModify(ticket, bePrice, pos.TakeProfit())) {
        if(idx >= 0) g_partials[idx].BESet = true;
        string slName = "AIV_SL_" + IntegerToString(ticket);
        if(ObjectFind(0, slName) >= 0) { ObjectSetDouble(0, slName, OBJPROP_PRICE, bePrice); ObjectSetString(0, slName, OBJPROP_TEXT, "BE SL");
        ObjectSetInteger(0, slName, OBJPROP_COLOR, clrGold); ChartRedraw(0); }
    }
}

void ManualPartialClose(ulong ticket, double pct) {
    CPositionInfo pos;
    if(!pos.SelectByTicket(ticket)) return;
    double closeVol = NormalizeDouble(pos.Volume() * pct / 100.0, 2); double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double stepVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    closeVol = MathFloor(closeVol / stepVol) * stepVol; if(closeVol < minVol) closeVol = minVol;
    if(closeVol >= pos.Volume()) closeVol = pos.Volume();
    g_trade.PositionClosePartial(ticket, closeVol, g_deviation);
}

//+------------------------------------------------------------------+
// DEAL HISTORY TRACKING
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result) {
    if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
    ulong dealTicket = trans.deal; if(dealTicket == 0 || !HistoryDealSelect(dealTicket)) return;
    ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
    
    if(dealEntry == DEAL_ENTRY_IN) {
        ulong posTicket = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
        double fillPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE); double fillVol = HistoryDealGetDouble(dealTicket, DEAL_VOLUME); int dealType = (int)HistoryDealGetInteger(dealTicket, DEAL_TYPE);
        int existingIdx = FindPartialIndex(posTicket);
        
        if(existingIdx < 0) {
            int posType = (dealType == DEAL_TYPE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL; RegisterPosition(posTicket, posType, fillPrice, fillVol); DrawPartialLines(posTicket, posType, fillPrice);
            string prefix = "AIV_LMT_" + IntegerToString(posTicket); ObjectDelete(0, prefix + "_E");
            ObjectDelete(0, prefix + "_S"); ObjectDelete(0, prefix + "_T"); ChartRedraw(0);
        }
        return;
    }
    
    if(dealEntry != DEAL_ENTRY_OUT || g_pipeHandle == INVALID_HANDLE) return;
    ulong posTicket = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
    int idx = FindPartialIndex(posTicket); bool positionStillOpen = false;
    for(int i = 0; i < PositionsTotal(); i++) { CPositionInfo pos;
        if(pos.SelectByIndex(i) && pos.Ticket() == posTicket) { positionStillOpen = true; break; } }
        
    TradeResultPacket pkt; pkt.PacketType = PKT_TRADE_RESULT;
    pkt.Ticket = posTicket; pkt.TradeType = (int)HistoryDealGetInteger(dealTicket, DEAL_TYPE); pkt.ExitPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE); pkt.Volume = HistoryDealGetDouble(dealTicket, DEAL_VOLUME); pkt.Profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
    pkt.BEWasSet = (idx >= 0 && g_partials[idx].BESet) ? 1 : 0; pkt.IsPartial = positionStillOpen ? 1 : 0;
    pkt.EntryPrice = (idx >= 0) ? g_partials[idx].EntryPrice : pkt.ExitPrice; pkt.HitSL = 0; pkt.HitTP = 0;
    double dealSL = 0, dealTP = 0;
    
    if(HistoryDealSelect(dealTicket)) { ulong orderTicket = HistoryDealGetInteger(dealTicket, DEAL_ORDER); if(HistoryOrderSelect(orderTicket)) { dealSL = HistoryOrderGetDouble(orderTicket, ORDER_SL);
        dealTP = HistoryOrderGetDouble(orderTicket, ORDER_TP); } }
    if(dealTP > 0 && MathAbs(pkt.ExitPrice - dealTP) <= _Point * 5) pkt.HitTP = 1;
    if(dealSL > 0 && MathAbs(pkt.ExitPrice - dealSL) <= _Point * 5) pkt.HitSL = 1;
    int symLen = StringLen(_Symbol);
    if(symLen > 19) symLen = 19; for(int i = 0; i < symLen; i++) pkt.Symbol[i] = (char)StringGetCharacter(_Symbol, i);
    pkt.Symbol[symLen] = 0;
    FileWriteStruct(g_pipeHandle, pkt); FileFlush(g_pipeHandle);
    
    if(!positionStillOpen) { UnregisterPosition(posTicket); RemovePartialLines(posTicket); }
}

//+------------------------------------------------------------------+
// CHART DRAG AND DROP EVENTS
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
    if(id != CHARTEVENT_OBJECT_DRAG) return;
    string objName = sparam;
    
    if(StringFind(objName, "AIV_SL_") == 0) {
        ulong ticket = (ulong)StringToInteger(StringSubstr(objName, 7));
        double newSL = NormalizeDouble(ObjectGetDouble(0, objName, OBJPROP_PRICE), _Digits);
        CPositionInfo pos; if(pos.SelectByTicket(ticket)) { if(g_trade.PositionModify(ticket, newSL, pos.TakeProfit())) { int idx = FindPartialIndex(ticket);
            double entry = (idx >= 0) ? g_partials[idx].EntryPrice : pos.PriceOpen(); int newSlPts = (int)(MathAbs(newSL - entry) / _Point);
            ObjectSetString(0, objName, OBJPROP_TEXT, "SL  -" + IntegerToString(newSlPts) + " pts"); ChartRedraw(0); } else { ObjectSetDouble(0, objName, OBJPROP_PRICE, pos.StopLoss()); ChartRedraw(0);
        } } return;
    }
    
    if(StringFind(objName, "AIV_TP_") == 0) {
        string remainder = StringSubstr(objName, 7);
        int sepPos = StringFind(remainder, "_"); if(sepPos < 0) return;
        ulong ticket = (ulong)StringToInteger(StringSubstr(remainder, 0, sepPos));
        int level = (int)StringToInteger(StringSubstr(remainder, sepPos + 1)); double newTP = NormalizeDouble(ObjectGetDouble(0, objName, OBJPROP_PRICE), _Digits);
        CPositionInfo pos;
        if(pos.SelectByTicket(ticket)) { if(level == g_tpLevels) { if(g_trade.PositionModify(ticket, pos.StopLoss(), newTP)) { int idx = FindPartialIndex(ticket);
            double entry = (idx >= 0) ? g_partials[idx].EntryPrice : pos.PriceOpen(); int newTpPts = (int)(MathAbs(newTP - entry) / _Point);
            ObjectSetString(0, objName, OBJPROP_TEXT, "TP" + IntegerToString(level) + " +" + IntegerToString(newTpPts) + " pts"); ChartRedraw(0);
        } else { ObjectSetDouble(0, objName, OBJPROP_PRICE, pos.TakeProfit()); ChartRedraw(0); } } else { int idx = FindPartialIndex(ticket);
            double entry = (idx >= 0) ? g_partials[idx].EntryPrice : pos.PriceOpen(); int newTpPts = (int)(MathAbs(newTP - entry) / _Point);
            ObjectSetString(0, objName, OBJPROP_TEXT, "TP" + IntegerToString(level) + " +" + IntegerToString(newTpPts) + " pts (visual)"); ChartRedraw(0); } } return;
    }
}