// managed_position.mqh
#include <Object.mqh>
#include <Arrays\ArrayObj.mqh>
// Add to managed_position.mqh
#include <Trade\Trade.mqh>

#include "partial_level.mqh"

class CManagedPosition : public CObject {
private:
    ulong       m_ticket;
    string      m_symbol;
    int         m_type; // POSITION_TYPE_BUY or POSITION_TYPE_SELL
    double      m_original_volume;
    double      m_current_volume;
    bool        m_be_activated;
    bool        m_ts_activated;
    CArrayObj   m_partials; // Holds CPartialLevel objects

public:
    CManagedPosition(ulong ticket, string symbol, int type, double original_vol) {
        m_ticket = ticket;
        m_symbol = symbol;
        m_type = type;
        m_original_volume = original_vol;
        m_current_volume = original_vol;
        m_be_activated = false;
        m_ts_activated = false;
    }
    
    ~CManagedPosition() { 
        m_partials.Clear(); // Automatically deletes CPartialLevel objects
    }

    ulong   Ticket() const         { return m_ticket; }
    int     Type() const           { return m_type; }
    double  OriginalVol() const    { return m_original_volume; }
    
    void    AddPartial(double price, double volume) {
        m_partials.Add(new CPartialLevel(price, volume));
    }
    
    // Stubs for Stage 3 execution logic
    void    CheckPartials();
    void    CheckBreakeven();
    void    RebuildRemainingPartials(double new_tp, int new_count);
    void    SyncWithBroker();
};
// Additions to managed_position.mqh

// Call this whenever a partial is taken or BE is activated
void CManagedPosition::SaveState(ulong magic) {
    string base_name = "ATP_" + IntegerToString(magic) + "_" + IntegerToString(m_ticket) + "_";
    
    GlobalVariableSet(base_name + "OrigVol", m_original_volume);
    GlobalVariableSet(base_name + "CurrVol", m_current_volume);
    GlobalVariableSet(base_name + "BE", m_be_activated ? 1.0 : 0.0);
    GlobalVariableSet(base_name + "TS", m_ts_activated ? 1.0 : 0.0);
}

// Call this during OnInit() when recovering open trades
bool CManagedPosition::LoadState(ulong magic) {
    string base_name = "ATP_" + IntegerToString(magic) + "_" + IntegerToString(m_ticket) + "_";
    
    if(!GlobalVariableCheck(base_name + "OrigVol")) return false; // Not managed by ATP
    
    m_original_volume = GlobalVariableGet(base_name + "OrigVol");
    m_current_volume  = GlobalVariableGet(base_name + "CurrVol");
    m_be_activated    = (GlobalVariableGet(base_name + "BE") == 1.0);
    m_ts_activated    = (GlobalVariableGet(base_name + "TS") == 1.0);
    
    return true;
}

// Call this when the trade fully closes to clean up terminal memory
void CManagedPosition::DeleteState(ulong magic) {
    string base_name = "ATP_" + IntegerToString(magic) + "_" + IntegerToString(m_ticket) + "_";
    GlobalVariableDel(base_name + "OrigVol");
    GlobalVariableDel(base_name + "CurrVol");
    GlobalVariableDel(base_name + "BE");
    GlobalVariableDel(base_name + "TS");
}
// Add to managed_position.mqh

// Called when a closing deal happens on this ticket
void CManagedPosition::SyncWithBroker() {
    if(PositionSelectByTicket(m_ticket)) {
        double new_volume = PositionGetDouble(POSITION_VOLUME);
        
        // Find if this new volume matches a partial drop
        double volume_dropped = NormalizeDouble(m_current_volume - new_volume, 2);
        
        if(volume_dropped > 0) {
            // Find the closest untaken partial and mark it as taken
            for(int i = 0; i < m_partials.Total(); i++) {
                CPartialLevel* p_level = m_partials.At(i);
                if(p_level != NULL && !p_level.IsTaken()) {
                    // We assume the first untaken one in the list triggered
                    p_level.MarkAsTaken();
                    Print("Partial Fill Confirmed. Level ", i+1, " marked as taken.");
                    break;
                }
            }
            m_current_volume = new_volume;
        }
    }
}

void CManagedPosition::CheckPartials() {
    if(!PositionSelectByTicket(m_ticket)) return;
    
    double current_price = (m_type == POSITION_TYPE_BUY) ? SymbolInfoDouble(m_symbol, SYMBOL_BID) : SymbolInfoDouble(m_symbol, SYMBOL_ASK);
    CTrade trade;
    
    for(int i = 0; i < m_partials.Total(); i++) {
        CPartialLevel* p_level = m_partials.At(i);
        
        if(p_level != NULL && !p_level.IsTaken()) {
            bool condition_met = false;
            if(m_type == POSITION_TYPE_BUY && current_price >= p_level.Price()) condition_met = true;
            if(m_type == POSITION_TYPE_SELL && current_price <= p_level.Price()) condition_met = true;
            
            if(condition_met) {
                // Get broker lot step
                double vol_step = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
                double min_lot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
                
                // Calculate and normalize lot size to close
                double lots_to_close = MathRound(p_level.Volume() / vol_step) * vol_step;
                
                // Safety check: Don't close if it leaves less than min lot size
                if((m_current_volume - lots_to_close) < min_lot) {
                    lots_to_close = m_current_volume; // Close it entirely
                }
                
                if(lots_to_close >= min_lot) {
                    if(trade.PositionClosePartial(m_ticket, lots_to_close)) {
                        Print("Sent Partial Close Request for Ticket: ", m_ticket, " Volume: ", lots_to_close);
                        // We do NOT mark it as taken here. We wait for OnTradeTransaction to call SyncWithBroker.
                        // This prevents race conditions!
                    } else {
                        Print("Failed to send partial close request. Error: ", GetLastError());
                    }
                }
                return; // Only process one partial per tick to avoid spamming the broker
            }
        }
    }
}
// Add to managed_position.mqh

void CManagedPosition::RebuildRemainingPartials(double new_final_tp, int new_total_count) {
    if(!PositionSelectByTicket(m_ticket)) return;
    
    int taken_count = 0;
    
    // Count how many are already taken
    for(int i = 0; i < m_partials.Total(); i++) {
        CPartialLevel* p_level = m_partials.At(i);
        if(p_level != NULL && p_level.IsTaken()) taken_count++;
    }
    
    int remaining_slots = new_total_count - taken_count;
    if(remaining_slots <= 0) return; // All partials are already done
    
    // Remove the old untaken partials from the array
    for(int i = m_partials.Total() - 1; i >= 0; i--) {
        CPartialLevel* p_level = m_partials.At(i);
        if(p_level != NULL && !p_level.IsTaken()) {
            m_partials.Delete(i);
        }
    }
    
    // Calculate new spacing based on current price and new final TP
    double current_price = (m_type == POSITION_TYPE_BUY) ? SymbolInfoDouble(m_symbol, SYMBOL_BID) : SymbolInfoDouble(m_symbol, SYMBOL_ASK);
    double distance = new_final_tp - current_price;
    double step_distance = distance / (remaining_slots + 1); // +1 because final slot is the actual TP
    
    // Calculate remaining volume allocation
    double vol_step = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
    double vol_per_slot = m_current_volume / (remaining_slots + 1);
    double normalized_vol_per_slot = MathRound(vol_per_slot / vol_step) * vol_step;
    
    // Add new pending partials
    for(int i = 1; i <= remaining_slots; i++) {
        double p_price = current_price + (step_distance * i);
        AddPartial(p_price, normalized_vol_per_slot);
    }
    Print("Rebuilt remaining ", remaining_slots, " partial targets.");
}

// Add to managed_position.mqh

void CManagedPosition::CheckBreakeven(double trigger_points, double offset_points) {
    if(m_be_activated) return; // Skip if already at Breakeven
    if(!PositionSelectByTicket(m_ticket)) return;
    
    double current_price = (m_type == POSITION_TYPE_BUY) ? SymbolInfoDouble(m_symbol, SYMBOL_BID) : SymbolInfoDouble(m_symbol, SYMBOL_ASK);
    double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
    double current_sl = PositionGetDouble(POSITION_SL);
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    
    bool trigger_hit = false;
    double new_sl = 0;
    
    if(m_type == POSITION_TYPE_BUY) {
        if(current_price >= open_price + (trigger_points * point)) {
            new_sl = open_price + (offset_points * point);
            // Verify new SL is actually an improvement before modifying
            if(current_sl == 0 || new_sl > current_sl) trigger_hit = true;
        }
    } else if(m_type == POSITION_TYPE_SELL) {
        if(current_price <= open_price - (trigger_points * point)) {
            new_sl = open_price - (offset_points * point);
            // Verify new SL is actually an improvement before modifying
            if(current_sl == 0 || new_sl < current_sl) trigger_hit = true;
        }
    }
    
    if(trigger_hit) {
        CTrade trade;
        if(trade.PositionModify(m_ticket, new_sl, PositionGetDouble(POSITION_TP))) {
            Print("Breakeven activated for ticket: ", m_ticket, " | New SL: ", new_sl);
            m_be_activated = true; 
            // In the CTradeManager OnTick Price Check loop, you would call SaveState() after this returns true
        }
    }
}

// Add to managed_position.mqh

void CManagedPosition::CheckTrailingStop(double trail_trigger_points, double trail_step_points, double trail_distance_points) {
    if(!PositionSelectByTicket(m_ticket)) return;
    
    double current_price = (m_type == POSITION_TYPE_BUY) ? SymbolInfoDouble(m_symbol, SYMBOL_BID) : SymbolInfoDouble(m_symbol, SYMBOL_ASK);
    double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
    double current_sl = PositionGetDouble(POSITION_SL);
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    double stop_level = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
    
    bool modify_needed = false;
    double new_sl = 0;
    
    if(m_type == POSITION_TYPE_BUY) {
        // Check if we reached the trigger to start trailing
        if(current_price >= open_price + (trail_trigger_points * point)) {
            new_sl = current_price - (trail_distance_points * point);
            
            // Only move if the new SL is higher than the current SL by at least the trail step + stop level
            if(current_sl == 0 || new_sl >= current_sl + (trail_step_points * point) + stop_level) {
                modify_needed = true;
            }
        }
    } else if(m_type == POSITION_TYPE_SELL) {
        // Check if we reached the trigger to start trailing
        if(current_price <= open_price - (trail_trigger_points * point)) {
            new_sl = current_price + (trail_distance_points * point);
            
            // Only move if the new SL is lower than the current SL by at least the trail step + stop level
            if(current_sl == 0 || new_sl <= current_sl - (trail_step_points * point) - stop_level) {
                modify_needed = true;
            }
        }
    }
    
    if(modify_needed) {
        CTrade trade;
        if(trade.PositionModify(m_ticket, new_sl, PositionGetDouble(POSITION_TP))) {
            m_ts_activated = true; // Mark that trailing is actively managing this position
        }
    }
}