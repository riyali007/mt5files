//+------------------------------------------------------------------+
//|  BridgeLogic.mqh  —  Pipe, trade execution, partials, drawing   |
//+------------------------------------------------------------------+
#ifndef BRIDGELOGIC_MQH
#define BRIDGELOGIC_MQH

#include "Inputs.mqh"
#include "Structs.mqh"
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//=== GLOBALS ==================================================
CTrade      g_trade;
CSymbolInfo g_sym;

int    g_pipeHandle   = INVALID_HANDLE;
bool   g_isPaused     = true;
double g_lotSize;
int    g_sl;
int    g_totalTP;
int    g_tpLevels;
int    g_deviation;
uint   g_lastTick     = 0;
int    g_beAfterLevel;
int    g_beOffsetPts;
uint   g_lastReplyTime = 0;

PartialState g_partials[];

double   g_lastPivotHighs[2];
double   g_lastPivotLows[2];
datetime g_lastPivotHighTimes[2];
datetime g_lastPivotLowTimes[2];
datetime g_lastPivotBarTime = 0;

bool   g_previewActive    = false;
int    g_previewDirection = 0;
double g_previewLotSize   = 0;
int    g_previewSL        = 0;
int    g_previewTP        = 0;

int    g_patternCounter   = 0;
int    g_lastPatternBar   = 0;

//=== FORWARD DECLARATIONS =====================================
void WriteLog(string msg);
void SendStatus();
void DrawPartialLines(ulong ticket, int posType, double entryPrice);
void RemovePartialLines(ulong ticket);
void RegisterPosition(ulong ticket, int posType, double entryPrice, double volume);
void UnregisterPosition(ulong ticket);
int  FindPartialIndex(ulong ticket);
void ExecuteBuy();
void ExecuteSell();
void ClosePositionByTicket(ulong ticket);
void CloseAllPositions();
void ManualSetBE(ulong ticket, int offsetPts);
void ManualPartialClose(ulong ticket, double pct);
bool IsMarketOpen();
void SendTickData();
void SendPositions();
void ProcessCommand(CommandPacket &cmd);
void DrawFreeHLine(double price, int drawColor, int drawStyle, int drawWidth);
void DrawFreeTLine(double price1, double price2, int drawColor, int drawStyle, int drawWidth);
void ClearFreeDrawings();
void DrawLimitPreview(double limitPrice, int direction, double lot, int sl, int tp);
void PlaceLimitOrder();
void CancelPreview();
void CancelLimitOrder(ulong ticket);
void RemoveAllLines();
void ApplyDarkTheme();
void RestoreDefaultTheme();
void UpdateCandleTimer();
void UpdatePivotLines();
void DetectPatterns();

//=== PIPE =====================================================
void ProcessPipe()
{
    if(g_pipeHandle == INVALID_HANDLE) {
        g_pipeHandle = FileOpen(InpPipeName,
            FILE_READ | FILE_WRITE | FILE_BIN | FILE_ANSI);
        if(g_pipeHandle == INVALID_HANDLE) return;
        Print("WPF Connected.");
        g_lastReplyTime = GetTickCount();
        SendStatus();
        return;
    }

    if(GetTickCount() - g_lastReplyTime > PIPE_TIMEOUT_MS) {
        Print("Pipe timeout — reconnecting.");
        FileClose(g_pipeHandle);
        g_pipeHandle = INVALID_HANDLE;
        return;
    }

    SendTickData();

    CommandPacket cmd;
    uint read = FileReadStruct(g_pipeHandle, cmd);
    if(read != sizeof(CommandPacket)) {
        Print("Bad cmd read=", read, " expected=", sizeof(CommandPacket), " — reconnecting.");
        FileClose(g_pipeHandle);
        g_pipeHandle = INVALID_HANDLE;
        return;
    }

    g_lastReplyTime = GetTickCount();
    if(cmd.CmdType != CMD_NONE) ProcessCommand(cmd);

    SendPositions();
    FileFlush(g_pipeHandle);
}

void SendTickData()
{
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

void SendPositions()
{
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
        ENUM_POSITION_TYPE posType = pos.PositionType();
        pkt.PositionType = (posType == POSITION_TYPE_BUY) ? 0 : 1;
        pkt.Volume       = pos.Volume();
        pkt.OpenPrice    = pos.PriceOpen();
        pkt.CurrentPrice = pos.PriceCurrent();
        pkt.SL           = pos.StopLoss();
        pkt.TP           = pos.TakeProfit();
        pkt.Profit       = pos.Profit();
        int symLen = StringLen(pos.Symbol());
        if(symLen > 19) symLen = 19;
        for(int c = 0; c < symLen; c++)
            pkt.Symbol[c] = (char)StringGetCharacter(pos.Symbol(), c);
        pkt.Symbol[symLen] = 0;
        FileWriteStruct(g_pipeHandle, pkt);
    }
}

void SendStatus()
{
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
    Print("SendStatus reply read=", read, " expected=", sizeof(CommandPacket));
}

void WriteLog(string msg)
{
    Print(msg);
    if(g_pipeHandle == INVALID_HANDLE) return;
    LogPacket lpkt;
    lpkt.PacketType = PKT_LOG;
    int len = StringLen(msg);
    if(len > 199) len = 199;
    for(int i = 0; i < len; i++)
        lpkt.Message[i] = (char)StringGetCharacter(msg, i);
    lpkt.Message[len] = 0;
    FileWriteStruct(g_pipeHandle, lpkt);
    FileFlush(g_pipeHandle);
    CommandPacket reply;
    FileReadStruct(g_pipeHandle, reply);
}

//=== COMMAND HANDLER ==========================================
void ProcessCommand(CommandPacket &cmd)
{
    int cmdType = (int)cmd.CmdType;
    if(cmdType == CMD_NONE) return;

    if(cmd.LotSize        > 0)  g_lotSize      = cmd.LotSize;
    if(cmd.SL             > 0)  g_sl           = cmd.SL;
    if(cmd.TotalTP        > 0)  g_totalTP      = cmd.TotalTP;
    if(cmd.TPLevels       > 0)  g_tpLevels     = cmd.TPLevels;
    if(cmd.DevPoints      > 0)  g_deviation    = cmd.DevPoints;
    if(cmd.BEAfterLevel   > 0)  g_beAfterLevel = cmd.BEAfterLevel;
    if(cmd.BEOffsetPoints > 0)  g_beOffsetPts  = cmd.BEOffsetPoints;
    g_trade.SetDeviationInPoints(g_deviation);

    if(cmdType == CMD_START)       { g_isPaused = false; WriteLog("Backtest STARTED");  SendStatus(); }
    else if(cmdType == CMD_PAUSE)  { g_isPaused = true;  WriteLog("Backtest PAUSED");   SendStatus(); }
    else if(cmdType == CMD_RESUME) { g_isPaused = false; WriteLog("Backtest RESUMED");  SendStatus(); }
    else if(cmdType == CMD_BUY)    { if(!g_isPaused) ExecuteBuy();  else WriteLog("Cannot BUY - EA is paused");  }
    else if(cmdType == CMD_SELL)   { if(!g_isPaused) ExecuteSell(); else WriteLog("Cannot SELL - EA is paused"); }
    else if(cmdType == CMD_CLOSE)     ClosePositionByTicket(cmd.TicketToClose);
    else if(cmdType == CMD_CLOSE_ALL) CloseAllPositions();
    else if(cmdType == CMD_SET_PARAMS) {
        WriteLog("Params updated: Lot=" + DoubleToString(g_lotSize,2) +
                 " SL=" + IntegerToString(g_sl) +
                 " TP=" + IntegerToString(g_totalTP) +
                 " Levels=" + IntegerToString(g_tpLevels));
        SendStatus();
    }
    else if(cmdType == CMD_SET_SL_BE) {
        if(cmd.TicketToClose > 0) ManualSetBE(cmd.TicketToClose, cmd.BEOffsetPoints);
        else {
            for(int i=0; i<PositionsTotal(); i++) {
                CPositionInfo pos;
                if(pos.SelectByIndex(i)) ManualSetBE(pos.Ticket(), cmd.BEOffsetPoints);
            }
        }
    }
    else if(cmdType == CMD_TAKE_PARTIAL) {
        double pct = cmd.PartialPercent;
        if(pct <= 0 || pct > 100) pct = 50.0;
        if(cmd.TicketToClose > 0) ManualPartialClose(cmd.TicketToClose, pct);
        else {
            for(int i=PositionsTotal()-1; i>=0; i--) {
                CPositionInfo pos;
                if(pos.SelectByIndex(i)) ManualPartialClose(pos.Ticket(), pct);
            }
        }
    }
    else if(cmdType == CMD_DRAW_HLINE)     DrawFreeHLine(cmd.DrawPrice1, cmd.DrawColor, cmd.DrawStyle, cmd.DrawWidth);
    else if(cmdType == CMD_DRAW_TLINE)     DrawFreeTLine(cmd.DrawPrice1, cmd.DrawPrice2, cmd.DrawColor, cmd.DrawStyle, cmd.DrawWidth);
    else if(cmdType == CMD_CLEAR_DRAWINGS) ClearFreeDrawings();
    else if(cmdType == CMD_PREVIEW_LIMIT)
        DrawLimitPreview(cmd.LimitPrice, cmd.OrderDirection,
                         cmd.LotSize>0?cmd.LotSize:g_lotSize,
                         cmd.SL>0?cmd.SL:g_sl,
                         cmd.TotalTP>0?cmd.TotalTP:g_totalTP);
    else if(cmdType == CMD_PLACE_LIMIT)    PlaceLimitOrder();
    else if(cmdType == CMD_CANCEL_PREVIEW) CancelPreview();
    else if(cmdType == CMD_CANCEL_LIMIT)   CancelLimitOrder(cmd.TicketToClose);
}

//=== TRADE EXECUTION ==========================================
bool IsMarketOpen()
{
    MqlTick lastTick;
    if(!SymbolInfoTick(_Symbol, lastTick)) return false;
    ENUM_SYMBOL_TRADE_MODE tradeMode =
        (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
    if(tradeMode == SYMBOL_TRADE_MODE_DISABLED)  { WriteLog("Market DISABLED for " + _Symbol); return false; }
    if(tradeMode == SYMBOL_TRADE_MODE_CLOSEONLY) { WriteLog("Market CLOSE ONLY for " + _Symbol); return false; }
    double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
    if(spread > 50 * _Point) { WriteLog("Spread too wide: " + DoubleToString(spread/_Point,0) + " pts"); return false; }
    return true;
}

void ExecuteBuy()
{
    if(!IsMarketOpen()) { WriteLog("BUY skipped - market closed"); return; }
    g_sym.RefreshRates();
    double ask     = g_sym.Ask();
    double slPrice = NormalizeDouble(ask - g_sl      * _Point, _Digits);
    double tpPrice = NormalizeDouble(ask + g_totalTP * _Point, _Digits);
    if(g_trade.Buy(g_lotSize, _Symbol, ask, slPrice, tpPrice, "AIV_BUY")) {
        ulong ticket = g_trade.ResultOrder();
        WriteLog("BUY OK #" + IntegerToString(ticket) + " Lot=" + DoubleToString(g_lotSize,2) + " @ " + DoubleToString(ask,_Digits));
        DrawPartialLines(ticket, POSITION_TYPE_BUY, ask);
        RegisterPosition(ticket, POSITION_TYPE_BUY, ask, g_lotSize);
    } else {
        WriteLog("BUY failed [" + IntegerToString(g_trade.ResultRetcode()) + "]: " + g_trade.ResultComment());
    }
}

void ExecuteSell()
{
    if(!IsMarketOpen()) { WriteLog("SELL skipped - market closed"); return; }
    g_sym.RefreshRates();
    double bid     = g_sym.Bid();
    double slPrice = NormalizeDouble(bid + g_sl      * _Point, _Digits);
    double tpPrice = NormalizeDouble(bid - g_totalTP * _Point, _Digits);
    if(g_trade.Sell(g_lotSize, _Symbol, bid, slPrice, tpPrice, "AIV_SELL")) {
        ulong ticket = g_trade.ResultOrder();
        WriteLog("SELL OK #" + IntegerToString(ticket) + " Lot=" + DoubleToString(g_lotSize,2) + " @ " + DoubleToString(bid,_Digits));
        DrawPartialLines(ticket, POSITION_TYPE_SELL, bid);
        RegisterPosition(ticket, POSITION_TYPE_SELL, bid, g_lotSize);
    } else {
        WriteLog("SELL failed [" + IntegerToString(g_trade.ResultRetcode()) + "]: " + g_trade.ResultComment());
    }
}

void ClosePositionByTicket(ulong ticket)
{
    CPositionInfo pos;
    if(pos.SelectByTicket(ticket)) {
        if(g_trade.PositionClose(ticket, g_deviation)) {
            WriteLog("Closed #" + IntegerToString(ticket));
            RemovePartialLines(ticket);
            UnregisterPosition(ticket);
        } else {
            WriteLog("Close failed #" + IntegerToString(ticket) +
                     " [" + IntegerToString(g_trade.ResultRetcode()) + "]");
        }
    }
}

void CloseAllPositions()
{
    for(int i=PositionsTotal()-1; i>=0; i--) {
        CPositionInfo pos;
        if(pos.SelectByIndex(i)) {
            ulong ticket = pos.Ticket();
            if(g_trade.PositionClose(ticket, g_deviation)) {
                RemovePartialLines(ticket);
                UnregisterPosition(ticket);
            }
        }
    }
    WriteLog("All positions closed.");
}

//=== PARTIALS =================================================
void RegisterPosition(ulong ticket, int posType, double entryPrice, double volume)
{
    int size = ArraySize(g_partials);
    ArrayResize(g_partials, size+1);
    g_partials[size].Ticket         = ticket;
    g_partials[size].LevelsHit      = 0;
    g_partials[size].BESet          = false;
    g_partials[size].EntryPrice     = entryPrice;
    g_partials[size].PositionType   = posType;
    g_partials[size].OriginalVolume = volume;
    Print("Registered position #", ticket, " Vol=", volume);
}

void UnregisterPosition(ulong ticket)
{
    int size = ArraySize(g_partials);
    for(int i=0; i<size; i++) {
        if(g_partials[i].Ticket == ticket) {
            for(int j=i; j<size-1; j++) g_partials[j] = g_partials[j+1];
            ArrayResize(g_partials, size-1);
            return;
        }
    }
}

int FindPartialIndex(ulong ticket)
{
    for(int i=0; i<ArraySize(g_partials); i++)
        if(g_partials[i].Ticket == ticket) return i;
    return -1;
}

void CheckPartials()
{
    if(!InpAutoPartials) return;
    if(ArraySize(g_partials) == 0) return;

    for(int i=ArraySize(g_partials)-1; i>=0; i--) {
        PartialState ps = g_partials[i];
        CPositionInfo pos;
        if(!pos.SelectByTicket(ps.Ticket)) {
            UnregisterPosition(ps.Ticket);
            RemovePartialLines(ps.Ticket);
            continue;
        }
        double currentPrice = (ps.PositionType == POSITION_TYPE_BUY) ? g_sym.Bid() : g_sym.Ask();
        double posTP        = pos.TakeProfit();
        double totalTPprice = (posTP > 0) ? MathAbs(posTP - ps.EntryPrice) : g_totalTP * _Point;
        double tpStep       = (g_tpLevels > 0) ? totalTPprice / g_tpLevels : totalTPprice;
        double direction    = (ps.PositionType == POSITION_TYPE_BUY) ? 1.0 : -1.0;

        for(int lvl=ps.LevelsHit+1; lvl<=g_tpLevels; lvl++) {
            double tpPrice = NormalizeDouble(ps.EntryPrice + direction * tpStep * lvl, _Digits);
            bool levelHit  = (ps.PositionType == POSITION_TYPE_BUY) ? (currentPrice >= tpPrice) : (currentPrice <= tpPrice);
            if(levelHit) {
                int    pct      = 100 / g_tpLevels;
                double closeVol = NormalizeDouble(ps.OriginalVolume * pct / 100.0, 2);
                double minVol   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
                double stepVol  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
                closeVol = MathFloor(closeVol / stepVol) * stepVol;
                if(closeVol < minVol)         closeVol = minVol;
                if(closeVol >= pos.Volume())  closeVol = pos.Volume();

                if(g_trade.PositionClosePartial(ps.Ticket, closeVol, g_deviation)) {
                    g_partials[i].LevelsHit = lvl;
                    WriteLog("Partial TP" + IntegerToString(lvl) + " hit #" + IntegerToString(ps.Ticket) +
                             " closed " + DoubleToString(closeVol,2) + " @ " + DoubleToString(currentPrice,_Digits));
                    string lineName = "AIV_TP_" + IntegerToString(ps.Ticket) + "_" + IntegerToString(lvl);
                    ObjectDelete(0, lineName);
                    ChartRedraw(0);

                    if(!ps.BESet && lvl >= g_beAfterLevel) {
                        double bePrice = NormalizeDouble(ps.EntryPrice + direction * g_beOffsetPts * _Point, _Digits);
                        if(g_trade.PositionModify(ps.Ticket, bePrice, pos.TakeProfit())) {
                            g_partials[i].BESet = true;
                            WriteLog("SL to BE #" + IntegerToString(ps.Ticket) + " @ " + DoubleToString(bePrice,_Digits));
                            string slName = "AIV_SL_" + IntegerToString(ps.Ticket);
                            ObjectSetDouble (0, slName, OBJPROP_PRICE, bePrice);
                            ObjectSetString (0, slName, OBJPROP_TEXT,  "BE SL");
                            ObjectSetInteger(0, slName, OBJPROP_COLOR, clrGold);
                            ChartRedraw(0);
                        }
                    }
                } else {
                    WriteLog("Partial close failed TP" + IntegerToString(lvl) +
                             " [" + IntegerToString(g_trade.ResultRetcode()) + "]: " + g_trade.ResultComment());
                }
                break;
            }
        }
    }
}

void ManualSetBE(ulong ticket, int offsetPts)
{
    CPositionInfo pos;
    if(!pos.SelectByTicket(ticket)) { WriteLog("BE failed: ticket #" + IntegerToString(ticket) + " not found"); return; }
    int    idx       = FindPartialIndex(ticket);
    int    useOffset = (offsetPts > 0) ? offsetPts : g_beOffsetPts;
    double direction = (pos.PositionType() == POSITION_TYPE_BUY) ? 1.0 : -1.0;
    double entryPrice = (idx >= 0) ? g_partials[idx].EntryPrice : pos.PriceOpen();
    double bePrice    = NormalizeDouble(entryPrice + direction * useOffset * _Point, _Digits);
    if(g_trade.PositionModify(ticket, bePrice, pos.TakeProfit())) {
        if(idx >= 0) g_partials[idx].BESet = true;
        WriteLog("Manual BE set #" + IntegerToString(ticket) + " SL to " + DoubleToString(bePrice,_Digits));
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

void ManualPartialClose(ulong ticket, double pct)
{
    CPositionInfo pos;
    if(!pos.SelectByTicket(ticket)) { WriteLog("Partial failed: #" + IntegerToString(ticket) + " not found"); return; }
    double closeVol = NormalizeDouble(pos.Volume() * pct / 100.0, 2);
    double minVol   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double stepVol  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    closeVol = MathFloor(closeVol / stepVol) * stepVol;
    if(closeVol < minVol)        closeVol = minVol;
    if(closeVol >= pos.Volume()) closeVol = pos.Volume();
    if(g_trade.PositionClosePartial(ticket, closeVol, g_deviation))
        WriteLog("Manual partial #" + IntegerToString(ticket) + " closed " + DoubleToString(closeVol,2));
    else
        WriteLog("Manual partial failed #" + IntegerToString(ticket) +
                 " [" + IntegerToString(g_trade.ResultRetcode()) + "]");
}

//=== LIMIT ORDERS =============================================
void DrawLimitPreview(double limitPrice, int direction, double lot, int sl, int tp)
{
    g_previewActive    = true;
    g_previewDirection = direction;
    g_previewLotSize   = lot;
    g_previewSL        = sl;
    g_previewTP        = tp;

    double dir = (direction == 0) ? 1.0 : -1.0;
    double slPrice  = NormalizeDouble(limitPrice - dir * sl * _Point, _Digits);
    double tpPrice  = NormalizeDouble(limitPrice + dir * tp * _Point, _Digits);

    string prefix = "AIV_PREV_";
    ObjectDelete(0, prefix+"ENTRY");
    ObjectDelete(0, prefix+"SL");
    ObjectDelete(0, prefix+"TP");

    ObjectCreate(0, prefix+"ENTRY", OBJ_HLINE, 0, 0, limitPrice);
    ObjectSetInteger(0, prefix+"ENTRY", OBJPROP_COLOR, clrDodgerBlue);
    ObjectSetInteger(0, prefix+"ENTRY", OBJPROP_STYLE, STYLE_DASH);
    ObjectSetString (0, prefix+"ENTRY", OBJPROP_TEXT,  (direction==0?"Buy":"Sell")+" Limit @ " + DoubleToString(limitPrice,_Digits));

    ObjectCreate(0, prefix+"SL", OBJ_HLINE, 0, 0, slPrice);
    ObjectSetInteger(0, prefix+"SL", OBJPROP_COLOR, clrTomato);
    ObjectSetInteger(0, prefix+"SL", OBJPROP_STYLE, STYLE_DOT);
    ObjectSetString (0, prefix+"SL", OBJPROP_TEXT,  "Preview SL");

    ObjectCreate(0, prefix+"TP", OBJ_HLINE, 0, 0, tpPrice);
    ObjectSetInteger(0, prefix+"TP", OBJPROP_COLOR, clrLimeGreen);
    ObjectSetInteger(0, prefix+"TP", OBJPROP_STYLE, STYLE_DOT);
    ObjectSetString (0, prefix+"TP", OBJPROP_TEXT,  "Preview TP");

    ChartRedraw(0);
}

void CancelPreview()
{
    g_previewActive = false;
    ObjectDelete(0, "AIV_PREV_ENTRY");
    ObjectDelete(0, "AIV_PREV_SL");
    ObjectDelete(0, "AIV_PREV_TP");
    ChartRedraw(0);
}

void PlaceLimitOrder()
{
    if(!g_previewActive) { WriteLog("No active preview to place"); return; }
    double limitPrice = 0;
    if(ObjectFind(0, "AIV_PREV_ENTRY") >= 0)
        limitPrice = ObjectGetDouble(0, "AIV_PREV_ENTRY", OBJPROP_PRICE);
    if(limitPrice <= 0) { WriteLog("Preview price not found"); return; }

    double dir      = (g_previewDirection == 0) ? 1.0 : -1.0;
    double slPrice  = NormalizeDouble(limitPrice - dir * g_previewSL * _Point, _Digits);
    double tpPrice  = NormalizeDouble(limitPrice + dir * g_previewTP * _Point, _Digits);
    MqlTradeRequest req = {};
    MqlTradeResult  res = {};
    req.action   = TRADE_ACTION_PENDING;
    req.symbol   = _Symbol;
    req.volume   = g_previewLotSize > 0 ? g_previewLotSize : g_lotSize;
    req.price    = limitPrice;
    req.sl       = slPrice;
    req.tp       = tpPrice;
    req.type     = (g_previewDirection == 0) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
    req.type_filling = ORDER_FILLING_RETURN;
    req.magic    = 202600;
    req.comment  = "AIV_LIMIT";
    if(OrderSend(req, res))
        WriteLog("Limit placed #" + IntegerToString(res.order) + " @ " + DoubleToString(limitPrice,_Digits));
    else
        WriteLog("Limit failed [" + IntegerToString(res.retcode) + "]");
    CancelPreview();
}

void CancelLimitOrder(ulong ticket)
{
    if(ticket > 0) {
        if(OrderDelete(ticket))
            WriteLog("Limit #" + IntegerToString(ticket) + " cancelled");
        else
            WriteLog("Cancel limit failed #" + IntegerToString(ticket));
    } else {
        for(int i=OrdersTotal()-1; i>=0; i--) {
            ulong t = OrderGetTicket(i);
            if(t > 0) OrderDelete(t);
        }
        WriteLog("All pending orders cancelled");
    }
}

//=== DRAWING UTILITIES ========================================
void DrawFreeHLine(double price, int drawColor, int drawStyle, int drawWidth)
{
    string name = "AIV_FREE_H_" + IntegerToString((int)(price*100000));
    ObjectDelete(0, name);
    ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
    ObjectSetInteger(0, name, OBJPROP_COLOR, (color)drawColor);
    ObjectSetInteger(0, name, OBJPROP_STYLE, drawStyle);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, drawWidth);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
    ChartRedraw(0);
}

void DrawFreeTLine(double price1, double price2, int drawColor, int drawStyle, int drawWidth)
{
    string name = "AIV_FREE_T_" + IntegerToString(TimeCurrent());
    ObjectDelete(0, name);
    datetime t1 = iTime(_Symbol, _Period, 5);
    datetime t2 = iTime(_Symbol, _Period, 0);
    ObjectCreate(0, name, OBJ_TREND, 0, t1, price1, t2, price2);
    ObjectSetInteger(0, name, OBJPROP_COLOR, (color)drawColor);
    ObjectSetInteger(0, name, OBJPROP_STYLE, drawStyle);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, drawWidth);
    ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
    ChartRedraw(0);
}

void ClearFreeDrawings()
{
    int total = ObjectsTotal(0);
    for(int i=total-1; i>=0; i--) {
        string name = ObjectName(0, i);
        if(StringFind(name, "AIV_FREE_") == 0) ObjectDelete(0, name);
    }
    ChartRedraw(0);
}

void DrawPartialLines(ulong ticket, int posType, double entryPrice)
{
    if(g_tpLevels < 1) return;
    double direction = (posType == POSITION_TYPE_BUY) ? 1.0 : -1.0;

    for(int i=1; i<=g_tpLevels; i++) {
        double tpStep  = (double)g_totalTP / g_tpLevels;
        double tpPrice = NormalizeDouble(entryPrice + direction * tpStep * i * _Point, _Digits);
        string name    = "AIV_TP_" + IntegerToString(ticket) + "_" + IntegerToString(i);
        int    pct     = 100 / g_tpLevels;
        string label   = "TP" + IntegerToString(i) + "  +" + IntegerToString((int)(tpStep*i)) + " pts (" + IntegerToString(pct) + "%)";
        ObjectDelete(0, name);
        ObjectCreate(0, name, OBJ_HLINE, 0, 0, tpPrice);
        ObjectSetInteger(0, name, OBJPROP_COLOR,      clrLimeGreen);
        ObjectSetInteger(0, name, OBJPROP_STYLE,      STYLE_DASH);
        ObjectSetInteger(0, name, OBJPROP_WIDTH,      1);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
        ObjectSetInteger(0, name, OBJPROP_BACK,       true);
        ObjectSetString (0, name, OBJPROP_TEXT,       label);
    }

    string slName  = "AIV_SL_" + IntegerToString(ticket);
    double slPrice = NormalizeDouble(entryPrice - direction * g_sl * _Point, _Digits);
    ObjectDelete(0, slName);
    ObjectCreate(0, slName, OBJ_HLINE, 0, 0, slPrice);
    ObjectSetInteger(0, slName, OBJPROP_COLOR,      clrTomato);
    ObjectSetInteger(0, slName, OBJPROP_STYLE,      STYLE_DASH);
    ObjectSetInteger(0, slName, OBJPROP_WIDTH,      2);
    ObjectSetInteger(0, slName, OBJPROP_SELECTABLE, true);
    ObjectSetInteger(0, slName, OBJPROP_BACK,       true);
    ObjectSetString (0, slName, OBJPROP_TEXT,       "SL  -" + IntegerToString(g_sl) + " pts");

    string entryName = "AIV_ENTRY_" + IntegerToString(ticket);
    ObjectDelete(0, entryName);
    ObjectCreate(0, entryName, OBJ_HLINE, 0, 0, entryPrice);
    ObjectSetInteger(0, entryName, OBJPROP_COLOR,      clrDodgerBlue);
    ObjectSetInteger(0, entryName, OBJPROP_STYLE,      STYLE_DOT);
    ObjectSetInteger(0, entryName, OBJPROP_WIDTH,      1);
    ObjectSetInteger(0, entryName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, entryName, OBJPROP_BACK,       true);
    ObjectSetString (0, entryName, OBJPROP_TEXT,       "ENTRY @ " + DoubleToString(entryPrice, _Digits));
    ChartRedraw(0);
}

void RemovePartialLines(ulong ticket)
{
    for(int i=1; i<=5; i++)
        ObjectDelete(0, "AIV_TP_" + IntegerToString(ticket) + "_" + IntegerToString(i));
    ObjectDelete(0, "AIV_SL_"    + IntegerToString(ticket));
    ObjectDelete(0, "AIV_ENTRY_" + IntegerToString(ticket));
    ChartRedraw(0);
}

void RemoveAllLines()
{
    int total = ObjectsTotal(0);
    for(int i=total-1; i>=0; i--) {
        string name = ObjectName(0, i);
        if(StringFind(name, "AIV_") == 0) ObjectDelete(0, name);
    }
    ChartRedraw(0);
}

//=== CHART THEME =============================================
void ApplyDarkTheme()
{
    long chart = ChartID();
    ChartSetInteger(chart, CHART_COLOR_BACKGROUND,  clrBlack);
    ChartSetInteger(chart, CHART_COLOR_FOREGROUND,  C'180,180,180');
    ChartSetInteger(chart, CHART_COLOR_CANDLE_BULL, C'0,188,168');
    ChartSetInteger(chart, CHART_COLOR_CANDLE_BEAR, C'234,84,85');
    ChartSetInteger(chart, CHART_COLOR_CHART_UP,    C'0,188,168');
    ChartSetInteger(chart, CHART_COLOR_CHART_DOWN,  C'234,84,85');
    ChartSetInteger(chart, CHART_COLOR_CHART_LINE,  C'0,188,168');
    ChartSetInteger(chart, CHART_SHOW_GRID,         false);
    ChartSetInteger(chart, CHART_COLOR_VOLUME,      C'0,120,100');
    ChartSetInteger(chart, CHART_SHOW_VOLUMES,      false);
    ChartSetInteger(chart, CHART_SHOW_ASK_LINE,     true);
    ChartSetInteger(chart, CHART_COLOR_ASK,         C'0,188,168');
    ChartSetInteger(chart, CHART_COLOR_BID,         C'234,84,85');
    ChartSetInteger(chart, CHART_COLOR_STOP_LEVEL,  C'255,160,0');
    ChartSetInteger(chart, CHART_COLOR_LAST,        C'100,100,100');
    ChartSetInteger(chart, CHART_SHOW_OHLC,         false);
    ChartSetInteger(chart, CHART_SHOW_BID_LINE,     true);
    ChartSetInteger(chart, CHART_SHOW_PERIOD_SEP,   false);
    ChartSetInteger(chart, CHART_MODE,              CHART_CANDLES);
    ChartSetInteger(chart, CHART_AUTOSCROLL,        true);
    ChartSetInteger(chart, CHART_SHIFT,             true);
    ChartRedraw(chart);
    Print("Dark theme applied.");
}

void RestoreDefaultTheme()
{
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

//=== CANDLE TIMER DISPLAY =====================================
void UpdateCandleTimer()
{
    datetime barTime  = iTime(_Symbol, _Period, 0);
    int      barSecs  = PeriodSeconds(_Period);
    datetime nextBar  = barTime + barSecs;
    int      secsLeft = (int)(nextBar - TimeCurrent());
    if(secsLeft < 0) secsLeft = 0;
    int m = secsLeft / 60;
    int s = secsLeft % 60;
    string label = StringFormat("Next bar: %02d:%02d", m, s);
    string name  = "AIV_CandleTimer";
    if(ObjectFind(0, name) < 0) {
        ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_RIGHT_UPPER);
        ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 10);
        ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 20);
        ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  10);
    }
    ObjectSetString (0, name, OBJPROP_TEXT,  label);
    ObjectSetInteger(0, name, OBJPROP_COLOR, C'180,180,180');
    ChartRedraw(0);
}

//=== PIVOT LINES ==============================================
void UpdatePivotLines()
{
    datetime pivotBarTime = iTime(_Symbol, InpPivotTimeframe, 0);
    if(pivotBarTime == g_lastPivotBarTime) return;
    g_lastPivotBarTime = pivotBarTime;

    int total = iBars(_Symbol, InpPivotTimeframe);
    int limit = MathMin(total, InpPivotMaxLookback + InpPivotRightBars + 5);

    double high[], low[];
    datetime time[];
    ArraySetAsSeries(high, true); CopyHigh(_Symbol, InpPivotTimeframe, 0, limit, high);
    ArraySetAsSeries(low,  true); CopyLow (_Symbol, InpPivotTimeframe, 0, limit, low);
    ArraySetAsSeries(time, true); CopyTime(_Symbol, InpPivotTimeframe, 0, limit, time);

    // Clear old pivot lines
    int obj = ObjectsTotal(0);
    for(int i=obj-1; i>=0; i--) {
        string n = ObjectName(0, i);
        if(StringFind(n, "AIV_PH_") == 0 || StringFind(n, "AIV_PL_") == 0) ObjectDelete(0, n);
    }

    int pivHCount = 0, pivLCount = 0;

    for(int i = InpPivotRightBars; i < limit - InpPivotLeftBars && (pivHCount < 2 || pivLCount < 2); i++)
    {
        // Pivot High
        if(pivHCount < 2) {
            bool isHigh = true;
            for(int l=1; l<=InpPivotLeftBars;  l++) if(high[i] <= high[i+l]) { isHigh=false; break; }
            if(isHigh)
                for(int r=1; r<=InpPivotRightBars; r++) if(high[i] <= high[i-r]) { isHigh=false; break; }
            if(isHigh) {
                g_lastPivotHighs[pivHCount]      = high[i];
                g_lastPivotHighTimes[pivHCount]  = time[i];
                string name = "AIV_PH_" + IntegerToString(pivHCount);
                ObjectCreate(0, name, OBJ_TREND, 0, time[i], high[i], time[0], high[i]);
                ObjectSetInteger(0, name, OBJPROP_COLOR,     InpPivotHighColor);
                ObjectSetInteger(0, name, OBJPROP_STYLE,     InpPivotLineStyle);
                ObjectSetInteger(0, name, OBJPROP_WIDTH,     InpPivotLineWidth);
                ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
                ObjectSetInteger(0, name, OBJPROP_SELECTABLE,false);
                ObjectSetString (0, name, OBJPROP_TEXT,      "PH " + DoubleToString(high[i],_Digits));
                pivHCount++;
            }
        }
        // Pivot Low
        if(pivLCount < 2) {
            bool isLow = true;
            for(int l=1; l<=InpPivotLeftBars;  l++) if(low[i] >= low[i+l]) { isLow=false; break; }
            if(isLow)
                for(int r=1; r<=InpPivotRightBars; r++) if(low[i] >= low[i-r]) { isLow=false; break; }
            if(isLow) {
                g_lastPivotLows[pivLCount]      = low[i];
                g_lastPivotLowTimes[pivLCount]  = time[i];
                string name = "AIV_PL_" + IntegerToString(pivLCount);
                ObjectCreate(0, name, OBJ_TREND, 0, time[i], low[i], time[0], low[i]);
                ObjectSetInteger(0, name, OBJPROP_COLOR,     InpPivotLowColor);
                ObjectSetInteger(0, name, OBJPROP_STYLE,     InpPivotLineStyle);
                ObjectSetInteger(0, name, OBJPROP_WIDTH,     InpPivotLineWidth);
                ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
                ObjectSetInteger(0, name, OBJPROP_SELECTABLE,false);
                ObjectSetString (0, name, OBJPROP_TEXT,      "PL " + DoubleToString(low[i],_Digits));
                pivLCount++;
            }
        }
    }
    ChartRedraw(0);
}

//=== PATTERN DETECTION ========================================
void DetectPatterns()
{
    int total = iBars(_Symbol, _Period);
    if(total < InpCandleLookback + 5) return;

    double high[], low[], open[], close[];
    datetime time[];
    ArraySetAsSeries(high,  true); CopyHigh (_Symbol,_Period,0,InpCandleLookback+5,high);
    ArraySetAsSeries(low,   true); CopyLow  (_Symbol,_Period,0,InpCandleLookback+5,low);
    ArraySetAsSeries(open,  true); CopyOpen (_Symbol,_Period,0,InpCandleLookback+5,open);
    ArraySetAsSeries(close, true); CopyClose(_Symbol,_Period,0,InpCandleLookback+5,close);
    ArraySetAsSeries(time,  true); CopyTime (_Symbol,_Period,0,InpCandleLookback+5,time);

    // Reference bar = bar[1] (last closed candle)
    int ref = 1;
    if(ref >= total) return;

    double boxHigh = high[ref];
    double boxLow  = low[ref];

    // Expand box to include nearby candles
    for(int i=ref; i<=ref+2 && i<InpCandleLookback; i++) {
        boxHigh = MathMax(boxHigh, high[i]);
        boxLow  = MathMin(boxLow,  low[i]);
    }

    // Count candles inside box in lookback window
    int candlesInside = 0;
    for(int i=ref+1; i<InpCandleLookback && i<total; i++) {
        if(high[i] <= boxHigh && low[i] >= boxLow) candlesInside++;
    }
    if(candlesInside < InpMinCandlesInBox) return;
    if(g_lastPatternBar == (int)time[ref]) return;

    // Determine bias from close direction
    bool isBull = (close[ref] >= open[ref]);
    color boxColor = isBull ? InpBullBoxColor : InpBearBoxColor;

    string name = "AIV_PAT_" + IntegerToString(time[ref]);
    if(ObjectFind(0, name) < 0) {
        ObjectCreate(0, name, OBJ_RECTANGLE, 0, time[ref+2], boxHigh, time[ref], boxLow);
        ObjectSetInteger(0, name, OBJPROP_COLOR,      boxColor);
        ObjectSetInteger(0, name, OBJPROP_BGCOLOR,    boxColor);
        ObjectSetInteger(0, name, OBJPROP_STYLE,      STYLE_SOLID);
        ObjectSetInteger(0, name, OBJPROP_FILL,       true);
        ObjectSetInteger(0, name, OBJPROP_BACK,       true);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, name, OBJPROP_WIDTH,      1);
        g_lastPatternBar = (int)time[ref];
        g_patternCounter++;
        Print("Pattern #", g_patternCounter, " | ", isBull?"Bull":"Bear",
              " | Box [", DoubleToString(boxLow,_Digits), " - ", DoubleToString(boxHigh,_Digits), "]");
    }
    ChartRedraw(0);
}

#endif // BRIDGELOGIC_MQH
