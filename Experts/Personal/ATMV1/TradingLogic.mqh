//+------------------------------------------------------------------+
//|                                                TradingLogic.mqh |
//|                                              Trade Manager V1.01 |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

// Structure to hold virtual partial targets for a trade
struct STradePartials
{
    ulong  ticket;
    int    total_partials;
    int    partials_hit;
    double target_prices[10];   // Supports up to 10 partial levels
    double target_volumes[10];
};

class CTradingEngine
{
private:
    CTrade            m_trade;
    CPositionInfo     m_position;
    CSymbolInfo       m_symbol;
    ulong             m_magic_number;
    ulong             m_selected_ticket; 
    
    STradePartials    m_tracked_partials[]; // Array to track active virtual partials

public:
                      CTradingEngine();
                     ~CTradingEngine();

    void              Init(ulong magic_number);
    void              SetSelectedTicket(ulong ticket);
    ulong             GetSelectedTicket();

    // Execution Methods
    bool              ExecuteMarketOrder(ENUM_ORDER_TYPE type, double volume, double sl_points, double tp_points, int num_partials);
    
    // Management Methods
    bool              MoveToBreakEven(ulong ticket = 0);
    bool              ClosePartial(double percent, ulong ticket = 0);
    bool              CloseSelected();
    bool              CloseAllSymbol();
    ulong             AdoptNextExternalTrade();
    
    // Virtual Engine Methods
    void              CheckVirtualPartials(); // To be called in OnTick()

private:
    double            CalculatePriceFromPoints(ENUM_ORDER_TYPE type, double open_price, double points);
    void              RegisterVirtualPartials(ulong ticket, ENUM_ORDER_TYPE type, double open_price, double initial_volume, double max_tp_points, int num_partials);
    void              RemoveTrackedPartial(ulong ticket);
};

//+------------------------------------------------------------------+
//| Constructor & Init                                               |
//+------------------------------------------------------------------+
CTradingEngine::CTradingEngine() : m_selected_ticket(0), m_magic_number(123456) {}
CTradingEngine::~CTradingEngine() {}

void CTradingEngine::Init(ulong magic_number)
{
    m_magic_number = magic_number;
    m_trade.SetExpertMagicNumber(m_magic_number);
    m_trade.SetDeviationInPoints(10); 
    m_symbol.Name(Symbol());
}

void CTradingEngine::SetSelectedTicket(ulong ticket) { m_selected_ticket = ticket; }
ulong CTradingEngine::GetSelectedTicket() { return m_selected_ticket; }

//+------------------------------------------------------------------+
//| Execute Market Order (Now supports partial registration)         |
//+------------------------------------------------------------------+
bool CTradingEngine::ExecuteMarketOrder(ENUM_ORDER_TYPE type, double volume, double sl_points, double tp_points, int num_partials)
{
    m_symbol.RefreshRates();
    double price = (type == ORDER_TYPE_BUY) ? m_symbol.Ask() : m_symbol.Bid();
    double sl = 0, tp = 0;

    if(sl_points > 0) sl = CalculatePriceFromPoints(type, price, -sl_points);
    // If we have partials, the physical TP is the final target (TP_Max)
    if(tp_points > 0) tp = CalculatePriceFromPoints(type, price, tp_points); 

    bool result = false;
    if(type == ORDER_TYPE_BUY)
        result = m_trade.Buy(volume, Symbol(), price, sl, tp, "ATM Pro Entry");
    else
        result = m_trade.Sell(volume, Symbol(), price, sl, tp, "ATM Pro Entry");

    if(result)
    {
        ulong ticket = m_trade.ResultOrder();
        m_selected_ticket = ticket; 
        
        // Register virtual partials if user requested more than 1
        if(num_partials > 1 && tp_points > 0)
        {
            RegisterVirtualPartials(ticket, type, price, volume, tp_points, num_partials);
        }
    }
    return result;
}

//+------------------------------------------------------------------+
//| Register the stepped partial targets internally                  |
//+------------------------------------------------------------------+
void CTradingEngine::RegisterVirtualPartials(ulong ticket, ENUM_ORDER_TYPE type, double open_price, double initial_volume, double max_tp_points, int num_partials)
{
    if(num_partials > 10) num_partials = 10; // Cap at 10 to prevent array overflow
    
    int size = ArraySize(m_tracked_partials);
    ArrayResize(m_tracked_partials, size + 1);
    
    m_tracked_partials[size].ticket = ticket;
    m_tracked_partials[size].total_partials = num_partials;
    m_tracked_partials[size].partials_hit = 0;
    
    // Calculate equal volume splits and equal point spacing
    double step_points = max_tp_points / num_partials;
    double vol_per_partial = initial_volume / num_partials;
    
    // Normalize volume to broker step
    double step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    vol_per_partial = MathRound(vol_per_partial / step) * step;

    for(int i = 0; i < num_partials; i++)
    {
        double target_pts = step_points * (i + 1);
        m_tracked_partials[size].target_prices[i] = CalculatePriceFromPoints(type, open_price, target_pts);
        
        // The last partial closes whatever is remaining, others close the calculated chunk
        if(i == num_partials - 1) 
            m_tracked_partials[size].target_volumes[i] = -1; // -1 means "close remainder"
        else
            m_tracked_partials[size].target_volumes[i] = vol_per_partial;
            
        Print("Registered TP", i+1, " at ", m_tracked_partials[size].target_prices[i], " Vol: ", vol_per_partial);
    }
}

//+------------------------------------------------------------------+
//| Check Virtual Partials (CALLED IN OnTick)                        |
//+------------------------------------------------------------------+
void CTradingEngine::CheckVirtualPartials()
{
    int total_tracked = ArraySize(m_tracked_partials);
    if(total_tracked == 0) return;

    m_symbol.RefreshRates();
    double current_bid = m_symbol.Bid();
    double current_ask = m_symbol.Ask();

    for(int i = total_tracked - 1; i >= 0; i--)
    {
        ulong ticket = m_tracked_partials[i].ticket;
        
        // If position is closed manually/by SL, remove it from tracking
        if(!m_position.SelectByTicket(ticket))
        {
            RemoveTrackedPartial(ticket);
            continue;
        }

        int next_target = m_tracked_partials[i].partials_hit;
        if(next_target >= m_tracked_partials[i].total_partials) continue; // All hit
        
        double target_price = m_tracked_partials[i].target_prices[next_target];
        ENUM_POSITION_TYPE pos_type = m_position.PositionType();
        
        bool hit = false;
        if(pos_type == POSITION_TYPE_BUY && current_bid >= target_price) hit = true;
        if(pos_type == POSITION_TYPE_SELL && current_ask <= target_price) hit = true;

        if(hit)
        {
            double vol_to_close = m_tracked_partials[i].target_volumes[next_target];
            if(vol_to_close == -1) // It's the final TP
            {
                m_trade.PositionClose(ticket);
                RemoveTrackedPartial(ticket);
            }
            else
            {
                // Calculate percentage based on current remaining volume
                double current_vol = m_position.Volume();
                double pct = (vol_to_close / current_vol) * 100.0;
                
                if(ClosePartial(pct, ticket))
                {
                    m_tracked_partials[i].partials_hit++;
                    // Optional: Automatically move to BE after TP1 is hit
                    if(m_tracked_partials[i].partials_hit == 1) MoveToBreakEven(ticket);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Management Implementations (Updated to accept specific tickets)  |
//+------------------------------------------------------------------+
bool CTradingEngine::MoveToBreakEven(ulong ticket = 0)
{
    ulong t = (ticket > 0) ? ticket : m_selected_ticket;
    if(t == 0) return false;

    if(m_position.SelectByTicket(t))
    {
        double open_price = m_position.PriceOpen();
        double current_sl = m_position.StopLoss();
        
        if(m_position.PositionType() == POSITION_TYPE_BUY && current_sl >= open_price) return false;
        if(m_position.PositionType() == POSITION_TYPE_SELL && (current_sl <= open_price && current_sl > 0)) return false;

        return m_trade.PositionModify(t, open_price, m_position.TakeProfit());
    }
    return false;
}

bool CTradingEngine::ClosePartial(double percent, ulong ticket = 0)
{
    ulong t = (ticket > 0) ? ticket : m_selected_ticket;
    if(t == 0 || percent <= 0 || percent > 100) return false;

    if(m_position.SelectByTicket(t))
    {
        double current_volume = m_position.Volume();
        double volume_to_close = current_volume * (percent / 100.0);
        double step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
        volume_to_close = MathRound(volume_to_close / step) * step;

        double min_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
        if(volume_to_close < min_lot) volume_to_close = min_lot;
        if(volume_to_close >= current_volume) return m_trade.PositionClose(t);

        return m_trade.PositionClosePartial(t, volume_to_close);
    }
    return false;
}

bool CTradingEngine::CloseSelected()
{
    if(m_selected_ticket == 0) return false;
    bool result = m_trade.PositionClose(m_selected_ticket);
    if(result) 
    {
        RemoveTrackedPartial(m_selected_ticket);
        m_selected_ticket = 0; 
    }
    return result;
}

bool CTradingEngine::CloseAllSymbol()
{
    bool success = true;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(m_position.SelectByIndex(i))
        {
            if(m_position.Symbol() == Symbol())
            {
                if(m_trade.PositionClose(m_position.Ticket()))
                {
                    RemoveTrackedPartial(m_position.Ticket());
                }
                else success = false;
            }
        }
    }
    m_selected_ticket = 0;
    return success;
}

ulong CTradingEngine::AdoptNextExternalTrade()
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(m_position.SelectByIndex(i))
        {
            if(m_position.Symbol() == Symbol() && m_position.Magic() == 0)
            {
                m_selected_ticket = m_position.Ticket();
                return m_selected_ticket;
            }
        }
    }
    return 0;
}

void CTradingEngine::RemoveTrackedPartial(ulong ticket)
{
    int size = ArraySize(m_tracked_partials);
    for(int i = 0; i < size; i++)
    {
        if(m_tracked_partials[i].ticket == ticket)
        {
            // Swap with last element and resize to delete
            m_tracked_partials[i] = m_tracked_partials[size - 1];
            ArrayResize(m_tracked_partials, size - 1);
            break;
        }
    }
}

double CTradingEngine::CalculatePriceFromPoints(ENUM_ORDER_TYPE type, double open_price, double points)
{
    double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    if(type == ORDER_TYPE_BUY) return open_price + (points * point);
    else if(type == ORDER_TYPE_SELL) return open_price - (points * point);
    return 0.0;
}