// ui_commands.mqh

enum ENUM_UI_COMMAND {
    UI_CMD_UPDATE_PARTIALS = 1,   // User changed the partial count in the panel
    UI_CMD_TP_DRAGGED = 2,        // User dragged the visual TP line on the chart
    UI_CMD_MANUAL_PARTIAL = 3,    // User clicked a "Close X%" button
    UI_CMD_CLOSE_ALL = 4          // User clicked panic close
};

// Helper macro to calculate the actual event ID
#define EVENT_ID(cmd) (CHARTEVENT_CUSTOM + cmd)