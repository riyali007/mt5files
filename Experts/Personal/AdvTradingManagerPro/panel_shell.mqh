// panel_shell.mqh
#include <ChartObjects\ChartObjectsBmpButtons.mqh>
#include <ChartObjects\ChartObjectsLines.mqh>
#include "ui_commands.mqh"

class CPanel {
private:
    string m_tp_line_name;

public:
    CPanel() {
        m_tp_line_name = "ATP_Visual_TP";
    }
    
    // Called inside the EA's OnChartEvent
    void ProcessChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
        
        // 1. Detect if the user dragged our TP line
        if(id == CHARTEVENT_OBJECT_DRAG) {
            if(sparam == m_tp_line_name) {
                double new_tp_price = ObjectGetDouble(0, m_tp_line_name, OBJPROP_PRICE);
                
                // Broadcast: Command ID, Ticket (lparam), New Price (dparam), Target String (sparam)
                // Assuming ticket 0 means "apply to active trade for this chart's symbol"
                EventChartCustom(UI_CMD_TP_DRAGGED, 0, new_tp_price, m_tp_line_name);
            }
        }
        
        // 2. Detect if user clicked a button to update the partial count
        if(id == CHARTEVENT_OBJECT_CLICK) {
            if(sparam == "Btn_UpdatePartials") {
                // Read the integer from an edit box on the chart
                long new_count = StringToInteger(ObjectGetString(0, "Edit_PartialCount", OBJPROP_TEXT));
                EventChartCustom(UI_CMD_UPDATE_PARTIALS, new_count, 0.0, "");
            }
        }
    }
    
    void UpdateVisualTP(double price) {
        ObjectSetDouble(0, m_tp_line_name, OBJPROP_PRICE, price);
    }
};