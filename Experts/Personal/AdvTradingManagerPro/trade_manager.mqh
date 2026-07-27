// trade_manager.mqh
#include "position_collection.mqh"
#include "ui_commands.mqh"

class CTradeManager {
private:
    CPositionCollection m_positions;
    ulong               m_magic;

public:
    CTradeManager(ulong magic) : m_magic(magic) {}
    ~CTradeManager() {}

    // 1. Called in OnInit() to recover state
    void RecoverOpenPositions() {
        for(int i = PositionsTotal() - 1; i >= 0; i--) {
            ulong ticket = PositionGetTicket(i);
            if(PositionGetInteger(POSITION_MAGIC) == m_magic) {
                // If it already exists in our collection, skip
                if(m_positions.FindByTicket(ticket) != NULL) continue;
                
                string sym = PositionGetString(POSITION_SYMBOL);
                int type = (int)PositionGetInteger(POSITION_TYPE);
                double vol = PositionGetDouble(POSITION_VOLUME);
                
                CManagedPosition* pos = new CManagedPosition(ticket, sym, type, vol);
                
                // Try to load historical state (if it survives a timeframe change)
                if(!pos.LoadState(m_magic)) {
                    pos.SaveState(m_magic); // Save initial state if new
                }
                m_positions.AddPosition(pos);
            }
        }
    }

    // 2. Main Event Router - Hook this into EA's OnTradeTransaction
    void OnTransaction(const MqlTradeTransaction &trans, 
                       const MqlTradeRequest &request, 
                       const MqlTradeResult &result) {
        
        // Handle new trades entering the market
        if(trans.type == TRADE_TRANSACTION_HISTORY_ADD || trans.type == TRADE_TRANSACTION_DEAL_ADD) {
            if(PositionSelectByTicket(trans.position)) {
                RecoverOpenPositions(); // Safely syncs new positions
            }
        }
        
        // Handle positions closing or partial closures
        if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal_type != DEAL_TYPE_BUY && trans.deal_type != DEAL_TYPE_SELL) {
            // Deal is closing a position (partially or fully)
            if(!PositionSelectByTicket(trans.position)) {
                // Position no longer exists -> Fully Closed
                CManagedPosition* pos = m_positions.FindByTicket(trans.position);
                if(pos != NULL) {
                    pos.DeleteState(m_magic);
                    m_positions.DeleteByTicket(trans.position);
                }
            } else {
                // Position still exists -> Partial Close occurred
                CManagedPosition* pos = m_positions.FindByTicket(trans.position);
                if(pos != NULL) {
                    pos.SyncWithBroker(); // Stub from Stage 1: updates volume and marks partial as taken
                    pos.SaveState(m_magic);
                }
            }
        }
    }

    // 3. Called in OnTick() ONLY for price-based triggers (not state syncs)
    void OnTickPriceChecks() {
        for(int i = 0; i < m_positions.Total(); i++) {
            CManagedPosition* pos = m_positions.GetByIndex(i); // FIXED HERE
            if(pos != NULL) {
                pos.CheckPartials();
                pos.CheckBreakeven(150, 10); // Example: Trigger at 150 points, Offset +10 points
            }
        }
    }
};

// Add this function to CTradeManager
void CTradeManager::OnUICommand(const int id, const long &lparam, const double &dparam, const string &sparam) {
    
    int cmd = id - CHARTEVENT_CUSTOM;
    
    if(cmd == UI_CMD_TP_DRAGGED) {
        double new_tp = dparam; 
        
        for(int i = 0; i < m_positions.Total(); i++) {
            CManagedPosition* pos = m_positions.GetByIndex(i); // FIXED HERE
            if(pos != NULL) {
                int current_desired_count = 3; 
                Print("UI Event: Rebuilding partials due to visual TP drag.");
                pos.RebuildRemainingPartials(new_tp, current_desired_count);
                
                CTrade trade;
                trade.PositionModify(pos.Ticket(), PositionGetDouble(POSITION_SL), new_tp);
            }
        }
    }
    
    if(cmd == UI_CMD_UPDATE_PARTIALS) {
        int new_count = (int)lparam;
        
        for(int i = 0; i < m_positions.Total(); i++) {
            CManagedPosition* pos = m_positions.GetByIndex(i); // FIXED HERE
            if(pos != NULL) {
                double current_tp = PositionGetDouble(POSITION_TP);
                Print("UI Event: Rebuilding partials due to count change.");
                pos.RebuildRemainingPartials(current_tp, new_count);
            }
        }
    }
}