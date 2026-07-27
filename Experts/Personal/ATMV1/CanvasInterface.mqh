//+------------------------------------------------------------------+
//|                                             CanvasInterface.mqh |
//|                                              Trade Manager V1.01 |
//+------------------------------------------------------------------+
#include <Canvas\Canvas.mqh>
#include "GUIDefinitions.mqh"

enum ENUM_GUI_ACTION
{
    ACTION_NONE = 0,
    ACTION_MARKET,
    ACTION_LIMIT,
    ACTION_MARKET_BUY,
    ACTION_MARKET_SELL,
    ACTION_VISUALIZE,
    ACTION_PREV_TRADE,
    ACTION_NEXT_TRADE,
    ACTION_PARTIAL_CLOSE,
    ACTION_MOVE_BE,
    ACTION_CLOSE_SELECTED,
    ACTION_CLOSE_ALL,
    ACTION_ADOPT_EXTERNAL
};

class CAdvancedGUI
{
private:
    CCanvas           m_canvas;
    string            m_name;
    int               m_x;
    int               m_y;

public:
                      CAdvancedGUI();
                     ~CAdvancedGUI();
    
    bool              Create(string name, int x, int y);
    void              Destroy();
    void              RenderEngine();
    void              InitializeInputs();
    string            GetInputValue(string obj_name);
    ENUM_GUI_ACTION   HandleClick(int click_x, int click_y);
    
    // Movement and Dynamic Updates
    void              Move(int new_x, int new_y);
    void              UpdateRiskRewardText(double risk_money, double profit_money);

private:
    void              DrawBackground();
    void              DrawHeaders();
    void              DrawExecutionBlock();
    void              DrawManagementBlock();
    
    void              DrawButton(int x, int y, int w, int h, uint bg_color, string text);
    void              DrawInputBox(int x, int y, int w, int h, string label, string value, int label_width=50);
    
    void              CreateNativeInput(string obj_name, int x, int y, int w, int h, string default_text);
    void              RemoveNativeInputs();
    void              UpdateNativeInputPositions();
    bool              IsInside(int x, int y, int btn_x, int btn_y, int btn_w, int btn_h);
};

CAdvancedGUI::CAdvancedGUI() : m_name("TradeManagerCanvas"), m_x(0), m_y(0) {}
CAdvancedGUI::~CAdvancedGUI() { Destroy(); }

bool CAdvancedGUI::Create(string name, int x, int y)
{
    m_name = name;
    m_x = x;
    m_y = y;
    
    if(!m_canvas.CreateBitmapLabel(m_name, m_x, m_y, GUI_WIDTH, GUI_HEIGHT, COLOR_FORMAT_ARGB_NORMALIZE)) return false;
    
    m_canvas.FontSet("Arial", 14, FW_NORMAL);
    RenderEngine();
    return true;
}

void CAdvancedGUI::Destroy()
{
    RemoveNativeInputs();
    m_canvas.Destroy();
}

void CAdvancedGUI::RenderEngine()
{
    m_canvas.Erase(COLOR_BG);
    DrawBackground();
    DrawHeaders();
    DrawExecutionBlock();
    DrawManagementBlock();
    m_canvas.Update();
}

void CAdvancedGUI::DrawBackground()
{
    m_canvas.Rectangle(0, 0, GUI_WIDTH-1, GUI_HEIGHT-1, ColorToARGB(clrDarkGray));
}

void CAdvancedGUI::DrawHeaders()
{
    m_canvas.TextOut(5, 5, "Advanced Trade Manager Pro v1.01", COLOR_TEXT_CYAN);
    m_canvas.TextOut(5, 25, "HEDGING | Engine: IDLE", COLOR_TEXT_YELLOW);
}

void CAdvancedGUI::DrawExecutionBlock()
{
    DrawButton(5, 45, 140, 25, COLOR_BTN_MARKET, "MARKET");
    DrawButton(150, 45, 145, 25, COLOR_BTN_LIMIT, "LIMIT");
    DrawInputBox(5, 75, 290, 25, "Price:", "");
    DrawButton(5, 105, 140, 25, COLOR_BTN_BUY, "BUY");
    DrawButton(150, 105, 145, 25, COLOR_BTN_SELL, "SELL");
    DrawInputBox(5, 135, 290, 25, "Lot:", "", 50);
    
    m_canvas.TextOut(5, 170, "SL pts:", COLOR_TEXT_GREY);
    m_canvas.FillRectangle(60, 165, 140, 190, COLOR_PANEL_BG);
    
    m_canvas.TextOut(150, 170, "Prc:", COLOR_TEXT_GREY);
    m_canvas.FillRectangle(180, 165, 295, 190, COLOR_PANEL_BG);
    
    m_canvas.TextOut(5, 200, "TP pts:", COLOR_TEXT_GREY);
    m_canvas.FillRectangle(60, 195, 140, 220, COLOR_PANEL_BG);
    
    m_canvas.TextOut(150, 200, "Prc:", COLOR_TEXT_GREY);
    m_canvas.FillRectangle(180, 195, 295, 220, COLOR_PANEL_BG);

    m_canvas.TextOut(5, 230, "Partials #:", COLOR_TEXT_GREY);
    m_canvas.FillRectangle(80, 225, 295, 250, COLOR_PANEL_BG);
    
    // Initial Risk / Profit Labels
    UpdateRiskRewardText(350.00, 700.00); 
    
    DrawButton(5, 285, 290, 25, COLOR_BTN_VISUALIZE, "VISUALIZE");
}

void CAdvancedGUI::DrawManagementBlock()
{
    m_canvas.TextOut(5, 320, "Trade Selector:", COLOR_TEXT_CYAN);
    m_canvas.TextOut(110, 320, "Ready", COLOR_TEXT_WHITE);
    
    DrawButton(5, 350, 30, 25, COLOR_PANEL_BG, "<");
    m_canvas.TextOut(45, 355, "Selected: none", COLOR_TEXT_YELLOW);
    DrawButton(265, 350, 30, 25, COLOR_PANEL_BG, ">");
    
    m_canvas.TextOut(5, 385, "Manual %:", COLOR_TEXT_GREY);
    m_canvas.FillRectangle(75, 380, 145, 405, COLOR_PANEL_BG);
    DrawButton(150, 380, 145, 25, COLOR_BTN_PARTIAL, "PARTIAL % (SEL)");
    
    DrawButton(5, 410, 290, 25, COLOR_BTN_BE, "BE (SEL)");
    DrawButton(5, 440, 290, 25, COLOR_BTN_CLOSE, "CLOSE (SEL)");
    DrawButton(5, 470, 290, 25, COLOR_BTN_CLOSEALL, "CLOSE ALL - THIS SYMBOL");
    
    m_canvas.TextOut(5, 505, "Unmanaged external: none", COLOR_TEXT_GREY);
    DrawButton(5, 525, 50, 25, COLOR_PANEL_BG, "Prev");
    DrawButton(60, 525, 180, 25, COLOR_BTN_ADOPT, "ADOPT SELECTED EXTERNAL");
    DrawButton(245, 525, 50, 25, COLOR_PANEL_BG, "Next");
}

void CAdvancedGUI::UpdateRiskRewardText(double risk_money, double profit_money)
{
    // Clear just the area where the text goes to avoid flickering the whole canvas
    m_canvas.FillRectangle(40, 260, 140, 280, COLOR_BG);
    m_canvas.FillRectangle(200, 260, 295, 280, COLOR_BG);
    
    m_canvas.TextOut(5, 260, "Risk:", COLOR_TEXT_GREY);
    m_canvas.TextOut(40, 260, "$" + DoubleToString(risk_money, 2), COLOR_TEXT_RED);
    
    m_canvas.TextOut(150, 260, "Profit:", COLOR_TEXT_GREY);
    m_canvas.TextOut(200, 260, "$" + DoubleToString(profit_money, 2), COLOR_TEXT_GREEN);
    
    m_canvas.Update();
}

void CAdvancedGUI::DrawButton(int x, int y, int w, int h, uint bg_color, string text)
{
    m_canvas.FillRectangle(x, y, x+w, y+h, bg_color);
    m_canvas.Rectangle(x, y, x+w, y+h, ColorToARGB(clrBlack)); 
    
    int txt_w = 0, txt_h = 0;
    m_canvas.TextSize(text, txt_w, txt_h);
    m_canvas.TextOut(x + (w - txt_w) / 2, y + (h - txt_h) / 2, text, COLOR_TEXT_WHITE);
}

void CAdvancedGUI::DrawInputBox(int x, int y, int w, int h, string label, string value, int label_width=50)
{
    m_canvas.TextOut(x, y + 5, label, COLOR_TEXT_GREY);
    m_canvas.FillRectangle(x + label_width, y, x + w, y + h, COLOR_PANEL_BG);
    m_canvas.Rectangle(x + label_width, y, x + w, y + h, ColorToARGB(clrWhite)); 
}

void CAdvancedGUI::InitializeInputs()
{
    CreateNativeInput("inp_price", m_x + 55, m_y + 75, 240, 25, "4093.41");
    CreateNativeInput("inp_lot", m_x + 55, m_y + 135, 240, 25, "0.50");
    CreateNativeInput("inp_sl_pts", m_x + 60, m_y + 165, 80, 25, "700");
    CreateNativeInput("inp_sl_prc", m_x + 180, m_y + 165, 115, 25, "4086.41");
    CreateNativeInput("inp_tp_pts", m_x + 60, m_y + 195, 80, 25, "1400");
    CreateNativeInput("inp_tp_prc", m_x + 180, m_y + 195, 115, 25, "4107.41");
    CreateNativeInput("inp_partials", m_x + 80, m_y + 225, 215, 25, "2");
    CreateNativeInput("inp_manual_pct", m_x + 75, m_y + 380, 70, 25, "10.0");
    ChartRedraw();
}

void CAdvancedGUI::CreateNativeInput(string obj_name, int x, int y, int w, int h, string default_text)
{
    ObjectCreate(0, obj_name, OBJ_EDIT, 0, 0, 0);
    ObjectSetInteger(0, obj_name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, obj_name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, obj_name, OBJPROP_XSIZE, w);
    ObjectSetInteger(0, obj_name, OBJPROP_YSIZE, h);
    ObjectSetInteger(0, obj_name, OBJPROP_BGCOLOR, C'50,50,50');
    ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clrWhite);
    ObjectSetInteger(0, obj_name, OBJPROP_BORDER_COLOR, C'50,50,50');
    ObjectSetInteger(0, obj_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetString(0, obj_name, OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, obj_name, OBJPROP_FONTSIZE, 10);
    ObjectSetString(0, obj_name, OBJPROP_TEXT, default_text);
    ObjectSetInteger(0, obj_name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, obj_name, OBJPROP_HIDDEN, true);
}

void CAdvancedGUI::RemoveNativeInputs() { ObjectsDeleteAll(0, "inp_"); }
string CAdvancedGUI::GetInputValue(string obj_name) { return ObjectGetString(0, obj_name, OBJPROP_TEXT); }

void CAdvancedGUI::Move(int new_x, int new_y)
{
    if(m_x == new_x && m_y == new_y) return; 
    m_x = new_x;
    m_y = new_y;
    ObjectSetInteger(0, m_name, OBJPROP_XDISTANCE, m_x);
    ObjectSetInteger(0, m_name, OBJPROP_YDISTANCE, m_y);
    UpdateNativeInputPositions();
}

void CAdvancedGUI::UpdateNativeInputPositions()
{
    ObjectSetInteger(0, "inp_price", OBJPROP_XDISTANCE, m_x + 55);
    ObjectSetInteger(0, "inp_price", OBJPROP_YDISTANCE, m_y + 75);
    ObjectSetInteger(0, "inp_lot", OBJPROP_XDISTANCE, m_x + 55);
    ObjectSetInteger(0, "inp_lot", OBJPROP_YDISTANCE, m_y + 135);
    ObjectSetInteger(0, "inp_sl_pts", OBJPROP_XDISTANCE, m_x + 60);
    ObjectSetInteger(0, "inp_sl_pts", OBJPROP_YDISTANCE, m_y + 165);
    ObjectSetInteger(0, "inp_sl_prc", OBJPROP_XDISTANCE, m_x + 180);
    ObjectSetInteger(0, "inp_sl_prc", OBJPROP_YDISTANCE, m_y + 165);
    ObjectSetInteger(0, "inp_tp_pts", OBJPROP_XDISTANCE, m_x + 60);
    ObjectSetInteger(0, "inp_tp_pts", OBJPROP_YDISTANCE, m_y + 195);
    ObjectSetInteger(0, "inp_tp_prc", OBJPROP_XDISTANCE, m_x + 180);
    ObjectSetInteger(0, "inp_tp_prc", OBJPROP_YDISTANCE, m_y + 195);
    ObjectSetInteger(0, "inp_partials", OBJPROP_XDISTANCE, m_x + 80);
    ObjectSetInteger(0, "inp_partials", OBJPROP_YDISTANCE, m_y + 225);
    ObjectSetInteger(0, "inp_manual_pct", OBJPROP_XDISTANCE, m_x + 75);
    ObjectSetInteger(0, "inp_manual_pct", OBJPROP_YDISTANCE, m_y + 380);
    ChartRedraw();
}

bool CAdvancedGUI::IsInside(int x, int y, int btn_x, int btn_y, int btn_w, int btn_h)
{
    int rel_x = x - m_x;
    int rel_y = y - m_y;
    return (rel_x >= btn_x && rel_x <= (btn_x + btn_w) && rel_y >= btn_y && rel_y <= (btn_y + btn_h));
}

ENUM_GUI_ACTION CAdvancedGUI::HandleClick(int click_x, int click_y)
{
    if(IsInside(click_x, click_y, 5, 45, 140, 25)) return ACTION_MARKET;
    if(IsInside(click_x, click_y, 150, 45, 145, 25)) return ACTION_LIMIT;
    if(IsInside(click_x, click_y, 5, 105, 140, 25)) return ACTION_MARKET_BUY;
    if(IsInside(click_x, click_y, 150, 105, 145, 25)) return ACTION_MARKET_SELL;
    if(IsInside(click_x, click_y, 5, 285, 290, 25)) return ACTION_VISUALIZE;

    if(IsInside(click_x, click_y, 5, 350, 30, 25)) return ACTION_PREV_TRADE; 
    if(IsInside(click_x, click_y, 265, 350, 30, 25)) return ACTION_NEXT_TRADE; 
    if(IsInside(click_x, click_y, 150, 380, 145, 25)) return ACTION_PARTIAL_CLOSE;
    if(IsInside(click_x, click_y, 5, 410, 290, 25)) return ACTION_MOVE_BE;
    if(IsInside(click_x, click_y, 5, 440, 290, 25)) return ACTION_CLOSE_SELECTED;
    if(IsInside(click_x, click_y, 5, 470, 290, 25)) return ACTION_CLOSE_ALL;
    if(IsInside(click_x, click_y, 60, 525, 180, 25)) return ACTION_ADOPT_EXTERNAL;

    return ACTION_NONE;
}