//+------------------------------------------------------------------+
//|                                              GUIDefinitions.mqh |
//|                                              Trade Manager V1.01 |
//+------------------------------------------------------------------+
#property copyright "MQL5 Developer"
#property link      ""

//--- Canvas Dimensions
#define GUI_WIDTH  300
#define GUI_HEIGHT 540

//--- Theme Colors (Converted to ARGB for Canvas)
#define COLOR_BG            ColorToARGB(clrBlack, 255)
#define COLOR_PANEL_BG      ColorToARGB(C'50,50,50', 255) // Dark grey for input backgrounds
#define COLOR_TEXT_CYAN     ColorToARGB(clrCyan, 255)
#define COLOR_TEXT_YELLOW   ColorToARGB(clrYellow, 255)
#define COLOR_TEXT_WHITE    ColorToARGB(clrWhite, 255)
#define COLOR_TEXT_GREY     ColorToARGB(clrLightGray, 255)
#define COLOR_TEXT_GREEN    ColorToARGB(C'76,175,80', 255) // Profit Green
#define COLOR_TEXT_RED      ColorToARGB(C'244,67,54', 255) // Risk Red

//--- Button Colors
#define COLOR_BTN_MARKET    ColorToARGB(C'33,150,243', 255) // Blue
#define COLOR_BTN_LIMIT     ColorToARGB(C'117,117,117', 255) // Grey
#define COLOR_BTN_BUY       ColorToARGB(C'0,150,0', 255)     // Green
#define COLOR_BTN_SELL      ColorToARGB(C'244,67,54', 255)   // Red
#define COLOR_BTN_VISUALIZE ColorToARGB(C'117,117,117', 255) // Grey
#define COLOR_BTN_PARTIAL   ColorToARGB(C'158,157,36', 255)  // Olive
#define COLOR_BTN_BE        ColorToARGB(C'0,151,167', 255)   // Teal/Cyan
#define COLOR_BTN_CLOSE     ColorToARGB(C'191,54,12', 255)   // Brown/Orange
#define COLOR_BTN_CLOSEALL  ColorToARGB(C'211,47,47', 255)   // Bright Red
#define COLOR_BTN_ADOPT     ColorToARGB(C'255,143,0', 255)   // Orange