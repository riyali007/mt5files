//+------------------------------------------------------------------+
//|  Structs.mqh  —  All structs, enums, packet & state types       |
//+------------------------------------------------------------------+
#ifndef STRUCTS_MQH
#define STRUCTS_MQH

//=== PIPE PACKET CONSTANTS =====================================
#define PKT_TICK          1
#define PKT_TRADE         2
#define PKT_POSITIONS     3
#define PKT_LOG           4
#define PKT_STATUS        5
#define PKT_TRADE_RESULT  6

//=== COMMAND CONSTANTS =========================================
#define CMD_NONE          0
#define CMD_START         1
#define CMD_PAUSE         2
#define CMD_RESUME        3
#define CMD_BUY           4
#define CMD_SELL          5
#define CMD_CLOSE         6
#define CMD_CLOSE_ALL     7
#define CMD_SET_PARAMS    8
#define CMD_SET_SL_BE     9
#define CMD_TAKE_PARTIAL  10
#define PIPE_TIMEOUT_MS   3000
#define CMD_DRAW_HLINE    11
#define CMD_DRAW_TLINE    12
#define CMD_DRAW_RAY      13
#define CMD_CLEAR_DRAWINGS 14
#define CMD_PREVIEW_LIMIT  15
#define CMD_PLACE_LIMIT    16
#define CMD_CANCEL_PREVIEW 17
#define CMD_CANCEL_LIMIT   18

//=== PIPE PACKETS ==============================================
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
    uchar  PacketType;
    ulong  Ticket;
    int    PositionType;
    double Volume;
    double OpenPrice;
    double CurrentPrice;
    double SL;
    double TP;
    double Profit;
    char   Symbol[20];
};

struct PositionsCountPacket {
    uchar PacketType;
    int   Count;
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
    uchar PacketType;
    char  Message[200];
};

struct CommandPacket {
    uchar  CmdType;
    double LotSize;
    int    SL;
    int    TotalTP;
    int    TPLevels;
    int    DevPoints;
    ulong  TicketToClose;
    int    BEAfterLevel;
    int    BEOffsetPoints;
    double PartialPercent;
    double DrawPrice1;
    double DrawPrice2;
    int    DrawColor;
    int    DrawStyle;
    int    DrawWidth;
    double LimitPrice;
    int    OrderDirection;
};

struct TradeResultPacket {
    uchar  PacketType;
    ulong  Ticket;
    int    TradeType;
    double EntryPrice;
    double ExitPrice;
    double Volume;
    double Profit;
    double SL;
    double TP;
    uchar  HitSL;
    uchar  HitTP;
    uchar  IsPartial;
    uchar  BEWasSet;
    char   Symbol[20];
};

//=== PARTIAL TRADE STATE =======================================
struct PartialState {
    ulong  Ticket;
    int    LevelsHit;
    bool   BESet;
    double EntryPrice;
    int    PositionType;
    double OriginalVolume;
};

//=== ORB STRUCTS & ENUMS =======================================
struct SessionTimes {
    int  startHour, startMin, endHour, endMin;
    bool crossesMidnight;
};

enum ZoneState { STATE_FRESH, STATE_MITIGATED, STATE_INVERTED, STATE_DEAD };

class CSMCZone {
public:
    string    name;
    datetime  tStart, tEnd;
    double    top, bottom;
    int       origType, currType, mode;
    ZoneState state;
    CSMCZone() { state = STATE_FRESH; }
};

#endif // STRUCTS_MQH
