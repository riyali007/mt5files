//+------------------------------------------------------------------+
//|                                              CPanelUI.mqh         |
//|                  Advance Trade Manager Pro V1.0 - Panel Skeleton  |
//+------------------------------------------------------------------+
#include <Controls\Dialog.mqh>
#include <Controls\Button.mqh>
#include <Controls\Edit.mqh>
#include <Controls\Label.mqh>

#define PANEL_WIDTH   260
#define PANEL_HEIGHT  620
#define MAX_POSROWS   30

//--- Color palette matching Advance Trade Manager Pro V1.0 reference UI
#define CLR_PANEL_BG     C'27,33,48'
#define CLR_TAB_ACTIVE   C'28,110,110'
#define CLR_TAB_INACTIVE C'46,52,68'
#define CLR_BUY          C'30,138,76'
#define CLR_SELL         C'192,57,43'
#define CLR_FIELD_BG     C'35,40,56'
#define CLR_TEXT_WHITE   clrWhite
#define CLR_TEXT_GRAY    C'190,196,206'
#define CLR_RISK_RED     C'231,76,60'
#define CLR_REW_GREEN    C'46,204,113'
#define CLR_NEUTRAL_BTN  C'58,64,80'
#define CLR_PARTIAL_OLV  C'125,123,30'
#define CLR_CLOSESEL_ORG C'212,121,31'
#define CLR_CLOSEALL_RED C'225,59,59'
#define CLR_EXPORT_GRN   C'30,138,76'
#define CLR_AUTORISK_OFF C'122,31,31'
#define CLR_HANDLER_ON   C'30,138,76'

//+------------------------------------------------------------------+
class CPanelUI : public CAppDialog
{
private:
   // --- Mode / Price
   CButton  m_btnMkt, m_btnLim;
   CEdit    m_editPrice;

   // --- Buy/Sell
   CButton  m_btnBuy, m_btnSell;
   CEdit    m_editLot;

   // --- SL/TP
   CEdit    m_editSL, m_editSL_Prc;
   CEdit    m_editTP, m_editTP_Prc;
   CEdit    m_editPart;
   CLabel   m_lblPTL;              // PTL_Line
   CLabel   m_valRisk, m_valRew;

   CButton  m_btnVis;

   // --- Manual partial / BE / Close
   CEdit    m_editManPart;
   CButton  m_btnPart;
   CButton  m_btnBE;
   CButton  m_btnCloseSel;
   CButton  m_btnCloseAll;

   // --- Export / Inverse / AutoRisk / Basket
   CButton  m_btnExport;
   CButton  m_btnInverse;
   CButton  m_btnAutoRisk;
   CButton  m_btnBasket;
   CEdit    m_editGreenPts;

   // --- Trade Selector
   CLabel   m_lblSelHdr;
   CButton  m_btnSelPrev, m_btnSelNext;
   CLabel   m_lblSelected;

   // --- Open Positions list (dynamic)
   CLabel   m_posRows[MAX_POSROWS];
   int      m_posRowCount;

   bool CreateControl(CWndObj &ctrl, const string name, int x1,int y1,int x2,int y2,
                       string text=NULL, color bg=CLR_FIELD_BG, color fg=CLR_TEXT_WHITE);
   void ColorBackgroundAll(const color clr);

public:
   CPanelUI(void){ m_posRowCount=0; }
   ~CPanelUI(void){}

   virtual bool Create(const long chart, const string name, const int subwin,
                        const int x1, const int y1, const int x2, const int y2);
   bool BuildLayout(void);
   void RefreshPositionList(const ulong &tickets[], const string &rowText[], int count,
                             int selectedIndex);
   virtual bool OnEvent(const int id, const long &lparam, const double &dparam,
                         const string &sparam);

   // Bindable callbacks — wired to modules in later steps
   void OnClickBuy(void)        { EventChartCustom(0, 1001, 0, 0, "BUY_CLICK"); }
   void OnClickSell(void)       { EventChartCustom(0, 1002, 0, 0, "SELL_CLICK"); }
   void OnClickCloseSel(void)   { EventChartCustom(0, 1003, 0, 0, "CLOSE_SEL"); }
   void OnClickCloseAll(void)   { EventChartCustom(0, 1004, 0, 0, "CLOSE_ALL"); }
   void OnClickPart(void)       { EventChartCustom(0, 1005, 0, 0, "PARTIAL_CLICK"); }
   void OnClickBE(void)         { EventChartCustom(0, 1006, 0, 0, "BE_CLICK"); }
   void OnClickSelNext(void)    { EventChartCustom(0, 1007, 0, 0, "SEL_NEXT"); }
   void OnClickSelPrev(void)    { EventChartCustom(0, 1008, 0, 0, "SEL_PREV"); }
   void OnClickExport(void)     { EventChartCustom(0, 1009, 0, 0, "EXPORT_CSV"); }
   void OnClickInverse(void)    { EventChartCustom(0, 1010, 0, 0, "TOGGLE_INV"); }
   void OnClickAutoRisk(void)   { EventChartCustom(0, 1011, 0, 0, "TOGGLE_AUTORISK"); }
   void OnClickBasket(void)     { EventChartCustom(0, 1012, 0, 0, "TOGGLE_BASKET"); }
   void OnClickVis(void)        { EventChartCustom(0, 1013, 0, 0, "VISUALIZE"); }
};

//+------------------------------------------------------------------+
bool CPanelUI::CreateControl(CWndObj &ctrl, const string name, int x1,int y1,int x2,int y2,
                              string text=NULL, color bg=CLR_FIELD_BG, color fg=CLR_TEXT_WHITE)
{
   if(!ctrl.Create(m_chart_id, m_name+name, m_subwin, x1,y1,x2,y2)) return false;
   if(text!=NULL) ctrl.Text(text);
   ctrl.ColorBackground(bg);
   ctrl.Color(fg);
   Add(ctrl);
   ObjectSetInteger(m_chart_id, m_name+name, OBJPROP_COLOR, fg);
   return true;
}

//+------------------------------------------------------------------+
bool CPanelUI::Create(const long chart, const string name, const int subwin,
                       const int x1, const int y1, const int x2, const int y2)
{
   if(!CAppDialog::Create(chart, name, subwin, x1, y1, x1+PANEL_WIDTH, y1+PANEL_HEIGHT))
      return false;

   ColorBackgroundAll(CLR_PANEL_BG);

   return BuildLayout();
}
void CPanelUI::ColorBackgroundAll(const color clr)
{
   ObjectSetInteger(m_chart_id, m_name+"Back",        OBJPROP_BGCOLOR, clr);
   ObjectSetInteger(m_chart_id, m_name+"Back",        OBJPROP_COLOR,   clr);
   ObjectSetInteger(m_chart_id, m_name+"Client",       OBJPROP_BGCOLOR, clr);
   ObjectSetInteger(m_chart_id, m_name+"Client",       OBJPROP_COLOR,   clr);
   ObjectSetInteger(m_chart_id, m_name+"WhiteBorder",  OBJPROP_BGCOLOR, clr);
   ObjectSetInteger(m_chart_id, m_name+"WhiteBorder",  OBJPROP_COLOR,   clr);
   ChartRedraw();
}
//+------------------------------------------------------------------+
bool CPanelUI::BuildLayout(void)
{
   int y = 30, rowH = 26, gap = 6;

   if(!CreateControl(m_btnMkt,"Btn_Mkt",10,y,125,y+rowH,"MARKET",CLR_TAB_ACTIVE,CLR_TEXT_WHITE)) return false;
   if(!CreateControl(m_btnLim,"Btn_Lim",130,y,245,y+rowH,"LIMIT",CLR_TAB_INACTIVE,CLR_TEXT_GRAY)) return false;
   y += rowH+gap;

   if(!CreateControl(m_editPrice,"Edit_Price",10,y,245,y+rowH,"0.00000",CLR_FIELD_BG,CLR_TEXT_WHITE)) return false;
   y += rowH+gap;

   if(!CreateControl(m_btnBuy,"Btn_Buy",10,y,125,y+rowH,"BUY",CLR_BUY,CLR_TEXT_WHITE))   return false;
   if(!CreateControl(m_btnSell,"Btn_Sell",130,y,245,y+rowH,"SELL",CLR_SELL,CLR_TEXT_WHITE)) return false;
   y += rowH+gap;

   if(!CreateControl(m_editLot,"Edit_Lot",10,y,245,y+rowH,"0.30",CLR_FIELD_BG,CLR_TEXT_WHITE)) return false;
   y += rowH+gap;

   if(!CreateControl(m_editSL,"Edit_SL",10,y,110,y+rowH,"700",CLR_FIELD_BG,CLR_TEXT_WHITE))       return false;
   if(!CreateControl(m_editSL_Prc,"Edit_SL_Prc",115,y,245,y+rowH,NULL,CLR_FIELD_BG,CLR_TEXT_WHITE)) return false;
   y += rowH+gap;

   if(!CreateControl(m_editTP,"Edit_TP",10,y,110,y+rowH,"1500",CLR_FIELD_BG,CLR_TEXT_WHITE))      return false;
   if(!CreateControl(m_editTP_Prc,"Edit_TP_Prc",115,y,245,y+rowH,NULL,CLR_FIELD_BG,CLR_TEXT_WHITE)) return false;
   y += rowH+gap;

   if(!CreateControl(m_editPart,"Edit_Part",10,y,60,y+rowH,"2",CLR_FIELD_BG,CLR_TEXT_WHITE))      return false;
   if(!CreateControl(m_lblPTL,"PTL_Line",65,y,245,y+rowH,"TP1:500|TP2:1000",CLR_FIELD_BG,CLR_TEXT_WHITE)) return false;
   y += rowH+gap;

   if(!CreateControl(m_valRisk,"Val_Risk",10,y,125,y+rowH,"$0.00",CLR_PANEL_BG,CLR_RISK_RED))   return false;
   if(!CreateControl(m_valRew,"Val_Rew",130,y,245,y+rowH,"$0.00",CLR_PANEL_BG,CLR_REW_GREEN))    return false;
   y += rowH+gap;

   if(!CreateControl(m_btnVis,"Btn_Vis",10,y,245,y+rowH,"VISUALIZE",CLR_NEUTRAL_BTN,CLR_TEXT_WHITE)) return false;
   y += rowH+gap*2;

   if(!CreateControl(m_lblSelHdr,"Lbl_SelHdr",10,y,245,y+rowH,"Trade Selector:",CLR_PANEL_BG,CLR_TEXT_WHITE)) return false;
   y += rowH+gap;
   if(!CreateControl(m_btnSelPrev,"Btn_SelPrev",10,y,50,y+rowH,"<",CLR_NEUTRAL_BTN,CLR_TEXT_WHITE))  return false;
   if(!CreateControl(m_lblSelected,"Lbl_Selected",55,y,195,y+rowH,"Selected: none",CLR_PANEL_BG,CLR_TEXT_WHITE)) return false;
   if(!CreateControl(m_btnSelNext,"Btn_SelNext",200,y,245,y+rowH,">",CLR_NEUTRAL_BTN,CLR_TEXT_WHITE)) return false;
   y += rowH+gap;

   if(!CreateControl(m_editManPart,"Edit_ManPart",10,y,110,y+rowH,"20",CLR_FIELD_BG,CLR_TEXT_WHITE)) return false;
   if(!CreateControl(m_btnPart,"Btn_Part",115,y,245,y+rowH,"PARTIAL % (SEL)",CLR_PARTIAL_OLV,CLR_TEXT_WHITE)) return false;
   y += rowH+gap;

   if(!CreateControl(m_btnBE,"Btn_BE",10,y,125,y+rowH,"BE (SEL)",CLR_BUY,CLR_TEXT_WHITE)) return false;
   if(!CreateControl(m_btnCloseSel,"Btn_CloseSel",130,y,245,y+rowH,"CLOSE (SEL)",CLR_CLOSESEL_ORG,CLR_TEXT_WHITE)) return false;
   y += rowH+gap;

   if(!CreateControl(m_btnCloseAll,"Btn_CloseAll",10,y,245,y+rowH,"CLOSE ALL",CLR_CLOSEALL_RED,CLR_TEXT_WHITE)) return false;
   y += rowH+gap;

   if(!CreateControl(m_btnExport,"Btn_Export",10,y,125,y+rowH,"EXPORT CSV",CLR_EXPORT_GRN,CLR_TEXT_WHITE)) return false;
   if(!CreateControl(m_btnInverse,"Btn_Inverse",130,y,245,y+rowH,"INV: OFF",CLR_TAB_INACTIVE,CLR_TEXT_GRAY)) return false;
   y += rowH+gap;

   if(!CreateControl(m_btnAutoRisk,"Btn_AutoRisk",10,y,125,y+rowH,"Auto Risk: OFF",CLR_AUTORISK_OFF,CLR_TEXT_GRAY)) return false;
   if(!CreateControl(m_btnBasket,"Btn_Basket",130,y,245,y+rowH,"Handler: ON",CLR_HANDLER_ON,CLR_TEXT_WHITE)) return false;
   y += rowH+gap;

   if(!CreateControl(m_editGreenPts,"Edit_GreenPts",10,y,245,y+rowH,"50",CLR_FIELD_BG,CLR_TEXT_WHITE)) return false;

   return true;
}

//+------------------------------------------------------------------+
void CPanelUI::RefreshPositionList(const ulong &tickets[], const string &rowText[],
                                    int count, int selectedIndex)
{
   int y = m_rect.bottom - 20;
   for(int i=0;i<count && i<MAX_POSROWS;i++)
   {
      string name = "PosRow_"+(string)tickets[i];

      if(ObjectFind(m_chart_id, m_name+name) < 0)
         CreateControl(m_posRows[i], name, 10, y, 245, y+20, rowText[i], CLR_PANEL_BG, CLR_TEXT_WHITE);
      else
         m_posRows[i].Text(rowText[i]);

      color rowColor = (i==selectedIndex) ? clrYellow : CLR_TEXT_WHITE;
      m_posRows[i].Color(rowColor);
      ObjectSetInteger(m_chart_id, m_name+name, OBJPROP_COLOR, rowColor);
      y += 22;
   }
   m_posRowCount = count;
   ChartRedraw();
}

//+------------------------------------------------------------------+
bool CPanelUI::OnEvent(const int id, const long &lparam, const double &dparam,
                        const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == m_btnBuy.Name())        { OnClickBuy(); return true; }
      if(sparam == m_btnSell.Name())       { OnClickSell(); return true; }
      if(sparam == m_btnCloseSel.Name())   { OnClickCloseSel(); return true; }
      if(sparam == m_btnCloseAll.Name())   { OnClickCloseAll(); return true; }
      if(sparam == m_btnPart.Name())       { OnClickPart(); return true; }
      if(sparam == m_btnBE.Name())         { OnClickBE(); return true; }
      if(sparam == m_btnSelNext.Name())    { OnClickSelNext(); return true; }
      if(sparam == m_btnSelPrev.Name())    { OnClickSelPrev(); return true; }
      if(sparam == m_btnExport.Name())     { OnClickExport(); return true; }
      if(sparam == m_btnInverse.Name())    { OnClickInverse(); return true; }
      if(sparam == m_btnAutoRisk.Name())   { OnClickAutoRisk(); return true; }
      if(sparam == m_btnBasket.Name())     { OnClickBasket(); return true; }
      if(sparam == m_btnVis.Name())        { OnClickVis(); return true; }
   }
   return CAppDialog::OnEvent(id, lparam, dparam, sparam);
}