#ifndef TM_PANEL_MQH
#define TM_PANEL_MQH
#include "Orders.mqh"
#include "Manual.mqh"

#define PN        "TM3_"
#define PN_LINE   "TM3_PL_"
#define PN_VIZ    "TM3_V_"
#define P_W       304
#define P_PITCH   22
#define P_TOPROWS 14
#define P_LISTMAX 12
#define P_MAXPART 8
#define P_MAXDD   10

struct TMPObj  { string name; int x,row,w,h,lr; };
struct TMLine  { ulong id; int k; string name; };

TMPObj g_po[];
TMLine g_lines[];
ulong  g_lineIds[];
ENUM_BASE_CORNER g_pcorner=CORNER_LEFT_UPPER;
int    g_pox=10, g_poy=20;
bool   g_pLimit=false, g_pViz=false, g_pAdopt=false, g_pDirty=false, g_pReset=false;
int    g_pRows=0, g_pCount=0;
ulong  g_pSel=0, g_pTick[P_LISTMAX];
ulong  g_pLastRefresh=0, g_pFreeze=0;
string g_pCache[P_LISTMAX];
double g_dLot=0.1, g_dRisk=0, g_dSL=0, g_dTP=0, g_dPart=0, g_dDD=0;   // values from the EA settings

#define C_BG     C'24,27,33'
#define C_FIELD  C'46,52,64'
#define C_TEXT   C'220,224,230'
#define C_BTN    C'58,88,150'
#define C_OFF    C'62,66,78'
#define C_BUY    C'30,120,70'
#define C_SELL   C'160,50,50'

bool PRight(){ return g_pcorner==CORNER_RIGHT_UPPER || g_pcorner==CORNER_RIGHT_LOWER; }
bool PBottom(){ return g_pcorner==CORNER_LEFT_LOWER || g_pcorner==CORNER_RIGHT_LOWER; }
int  PHeight(){ return 8+(P_TOPROWS+MathMax(0,g_pRows))*P_PITCH; }

// ---------- cheap, change-only property writers ----------
bool PSet(const string nm,const string t)
  {
   string n=PN+nm;
   if(ObjectGetString(0,n,OBJPROP_TEXT)==t) return false;
   ObjectSetString(0,n,OBJPROP_TEXT,t); g_pDirty=true; return true;
  }
void PSetCol(const string nm,const color c)
  { string n=PN+nm; if((color)ObjectGetInteger(0,n,OBJPROP_COLOR)!=c){ ObjectSetInteger(0,n,OBJPROP_COLOR,c); g_pDirty=true; } }
void PSetBg(const string nm,const color c)
  { string n=PN+nm; if((color)ObjectGetInteger(0,n,OBJPROP_BGCOLOR)!=c){ ObjectSetInteger(0,n,OBJPROP_BGCOLOR,c); g_pDirty=true; } }
void PFlush(){ if(g_pDirty){ ChartRedraw(); g_pDirty=false; } }
double PGetD(const string nm){ return StringToDouble(ObjectGetString(0,PN+nm,OBJPROP_TEXT)); }

// ---------- object creation (skipped when adopting an existing panel) ----------
void PReg(const string nm,const int x,const int row,const int w,const int h,const int lr)
  {
   int k=ArraySize(g_po); ArrayResize(g_po,k+1);
   g_po[k].name=PN+nm; g_po[k].x=x; g_po[k].row=row; g_po[k].w=w; g_po[k].h=h; g_po[k].lr=lr;
  }
bool PBase(const ENUM_OBJECT type,const string n,const int w,const int h)
  {
   if(g_pAdopt && ObjectFind(0,n)>=0) return false;
   if(ObjectFind(0,n)>=0) ObjectDelete(0,n);
   ObjectCreate(0,n,type,0,0,0);
   ObjectSetInteger(0,n,OBJPROP_CORNER,g_pcorner);
   ObjectSetInteger(0,n,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,n,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,n,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,n,OBJPROP_BACK,false);
   ObjectSetInteger(0,n,OBJPROP_ZORDER,type==OBJ_RECTANGLE_LABEL?9999:10000);   // clicks win over indicator objects
   ObjectSetInteger(0,n,OBJPROP_FONTSIZE,9);
   ObjectSetString(0,n,OBJPROP_FONT,"Consolas");
   return true;
  }
void PLabel(const string nm,const int x,const int row,const int w,const string text,const int lr=-1)
  {
   string n=PN+nm;
   if(PBase(OBJ_EDIT,n,w,20))
     {
      ObjectSetString(0,n,OBJPROP_TEXT,text);
      ObjectSetInteger(0,n,OBJPROP_READONLY,true);
      ObjectSetInteger(0,n,OBJPROP_BGCOLOR,C_BG); ObjectSetInteger(0,n,OBJPROP_BORDER_COLOR,C_BG);
      ObjectSetInteger(0,n,OBJPROP_COLOR,C_TEXT);
     }
   PReg(nm,x,row,w,20,lr);
  }
void PField(const string nm,const int x,const int row,const int w,const string text)
  {
   string n=PN+nm;
   if(PBase(OBJ_EDIT,n,w,20))
     {
      ObjectSetString(0,n,OBJPROP_TEXT,text);
      ObjectSetInteger(0,n,OBJPROP_ALIGN,ALIGN_RIGHT);
      ObjectSetInteger(0,n,OBJPROP_BGCOLOR,C_FIELD); ObjectSetInteger(0,n,OBJPROP_BORDER_COLOR,C_BTN);
      ObjectSetInteger(0,n,OBJPROP_COLOR,clrWhite);
     }
   PReg(nm,x,row,w,20,-1);
  }
void PButton(const string nm,const int x,const int row,const int w,const string text,const color bg)
  {
   string n=PN+nm;
   if(PBase(OBJ_BUTTON,n,w,20))
     {
      ObjectSetString(0,n,OBJPROP_TEXT,text);
      ObjectSetInteger(0,n,OBJPROP_BGCOLOR,bg); ObjectSetInteger(0,n,OBJPROP_COLOR,clrWhite);
     }
   PReg(nm,x,row,w,20,-1);
  }

int PVolDigits()
  {
   double s=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP); int d=0;
   while(d<8 && MathAbs(s*MathPow(10,d)-MathRound(s*MathPow(10,d)))>1e-9) d++;
   return d;
  }

void PDeleteObjects(const bool includeLines)
  {
   for(int i=ObjectsTotal(0)-1;i>=0;i--)
     {
      string nm=ObjectName(0,i);
      if(StringFind(nm,PN)!=0) continue;
      if(!includeLines && StringFind(nm,PN_LINE)==0) continue;
      ObjectDelete(0,nm);
     }
  }

// ---------- layout ----------
void PLayout()
  {
   int ph=PHeight();
   string bg=PN+"bg";
   ObjectSetInteger(0,bg,OBJPROP_YSIZE,ph);
   ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,g_pox); ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,g_poy);
   for(int i=0;i<ArraySize(g_po);i++)
     {
      int top=4+g_po[i].row*P_PITCH;
      int xd=PRight()? P_W-(g_po[i].x+g_po[i].w) : g_po[i].x;
      int yd=PBottom()? ph-(top+g_po[i].h) : top;
      ObjectSetInteger(0,g_po[i].name,OBJPROP_XDISTANCE,g_pox+xd);
      ObjectSetInteger(0,g_po[i].name,OBJPROP_YDISTANCE,g_poy+yd);
      bool vis=(g_po[i].lr<0) || (g_po[i].lr<g_pRows);
      ObjectSetInteger(0,g_po[i].name,OBJPROP_TIMEFRAMES,vis?OBJ_ALL_PERIODS:OBJ_NO_PERIODS);
     }
   g_pDirty=true;
  }

// ---------- saved values: >0 -> global variable, <=0 -> EA settings ----------
string PGV(const string k){ return StringFormat("TM3_%I64d_%s_%s",g_cfg.magic,_Symbol,k); }
double PSaved(const string k){ return GlobalVariableCheck(PGV(k)) ? GlobalVariableGet(PGV(k)) : 0; }
double PEff(const string k,const double def){ double g=PSaved(k); return g>0 ? g : def; }
void PCommit(const string k,const double v)
  { if(v>0) GlobalVariableSet(PGV(k),v); else GlobalVariableDel(PGV(k)); }

// ---------- price / points / risk links ----------
double PRefPrice(const bool buy)
  {
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK), bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(g_pLimit){ double lp=PGetD("px"); return lp>0 ? lp : (buy?ask:bid); }
   if(g_cfg.inverse) return buy ? ask-g_cfg.inverseOffset*_Point : bid+g_cfg.inverseOffset*_Point;
   return buy?ask:bid;
  }
double PPriceFromPts(const bool buy,const bool sl,const double pts)
  { double ref=PRefPrice(buy); bool minus=(buy==sl); return TMNormPrice(minus? ref-pts*_Point : ref+pts*_Point); }
double PPtsFromPrice(const bool buy,const bool sl,const double price)
  { double ref=PRefPrice(buy); bool minus=(buy==sl); return MathRound(minus? (ref-price)/_Point : (price-ref)/_Point); }

void PSyncPrices()   // SL/TP price fields show the BUY-side prices
  {
   double s=PGetD("slp"), t=PGetD("tpp");
   PSet("slx", s>0 ? DoubleToString(PPriceFromPts(true,true,s),_Digits) : "0");
   PSet("tpx", t>0 ? DoubleToString(PPriceFromPts(true,false,t),_Digits) : "0");
  }
void PUpdateRiskField(){ PSet("risk",DoubleToString(TMRiskPctFromLot(PGetD("lot"),PGetD("slp")),2)); }

void PUpdateRiskLabel()
  {
   double lot=PGetD("lot"), slp=PGetD("slp");
   int ddc=(int)PGetD("dd");
   bool dd=g_cfg.ddOn && ddc>0;
   double money=TMGroupRiskMoney(lot,slp,dd?ddc:0);
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double pct=eq>0? money/eq*100.0 : 0;
   PSet("grisk",StringFormat("Risk %.2f %s (%d entr.) %.2f%%/%.1f%%",money,AccountInfoString(ACCOUNT_CURRENCY),dd?ddc+1:1,pct,g_cfg.maxGroupRiskPct));
   PSetCol("grisk",(dd && pct>g_cfg.maxGroupRiskPct)?clrTomato:C_TEXT);
  }

// Applies the rule for lot / SL / TP / partials / DD entries: saved value if > 0, else the EA setting
void PApplyDefaults()
  {
   double sl=PEff("slp",g_dSL), tp=PEff("tpp",g_dTP), par=PEff("par",g_dPart), dd=PEff("dd",g_dDD);
   double lot=PSaved("lot");
   if(lot<=0) lot=(g_dRisk>0 && sl>0) ? TMLotFromRisk(g_dRisk,sl) : g_dLot;
   lot=TMNormVol(lot>0?lot:g_dLot);
   PSet("slp",DoubleToString(sl,0)); PSet("tpp",DoubleToString(tp,0));
   PSet("par",DoubleToString(par,0)); PSet("dd",DoubleToString(dd,0));
   PSet("lot",DoubleToString(lot,PVolDigits()));
   PUpdateRiskField(); PSyncPrices();
  }

void PApplyType()
  {
   PSetBg("mkt",g_pLimit?C_OFF:C_BTN);
   PSetBg("lmt",g_pLimit?C_BTN:C_OFF);
   PSet("l_px",g_pLimit?"Limit px":"Mkt px");
   ObjectSetInteger(0,PN+"px",OBJPROP_READONLY,!g_pLimit);    // market price is live and read-only
   PSyncPrices();
  }

// Market mode: live ask in the price field. Limit mode: left alone. Frozen while a field is being edited.
void PUpdateQuote()
  {
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID), ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   PSet("quote",StringFormat("Bid %s Spr %d",DoubleToString(bid,_Digits),(int)MathRound((ask-bid)/_Point)));
   if(g_pLimit || GetTickCount64()<g_pFreeze) return;
   if(PSet("px",DoubleToString(ask,_Digits))) PSyncPrices();
  }

// ---------- visualize: both sides, live, temporary ----------
void PVizPut(const string nm,const double price,const color c,const ENUM_LINE_STYLE st,const string txt)
  {
   string n=PN_VIZ+nm;
   if(ObjectFind(0,n)<0)
     {
      ObjectCreate(0,n,OBJ_HLINE,0,0,price);
      ObjectSetInteger(0,n,OBJPROP_COLOR,c); ObjectSetInteger(0,n,OBJPROP_STYLE,st);
      ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false); ObjectSetInteger(0,n,OBJPROP_HIDDEN,true);
      ObjectSetString(0,n,OBJPROP_TEXT,txt);
      g_pDirty=true; return;
     }
   if(MathAbs(ObjectGetDouble(0,n,OBJPROP_PRICE)-price)>_Point/2){ ObjectSetDouble(0,n,OBJPROP_PRICE,price); g_pDirty=true; }
   if(ObjectGetString(0,n,OBJPROP_TEXT)!=txt){ ObjectSetString(0,n,OBJPROP_TEXT,txt); g_pDirty=true; }
  }
void PVizDel(const string nm){ string n=PN_VIZ+nm; if(ObjectFind(0,n)>=0){ ObjectDelete(0,n); g_pDirty=true; } }

void PVizSide(const bool buy)
  {
   string s=buy?"B":"S", side=buy?"BUY":"SELL";
   double entry=TMNormPrice(PRefPrice(buy)), sp=PGetD("slp"), tpPts=PGetD("tpp");
   int np=(int)MathMin(P_MAXPART,MathMax(0,PGetD("par")));
   string tag=side;
   if(g_pLimit)
     {
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK), bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      if((buy && entry>=ask) || (!buy && entry<=bid)) tag+=" (invalid limit)";
     }
   PVizPut("e"+s,entry,buy?clrDodgerBlue:clrOrchid,STYLE_SOLID,tag+" ENTRY");
   if(sp>0) PVizPut("sl"+s,PPriceFromPts(buy,true,sp),buy?clrTomato:clrSalmon,STYLE_SOLID,side+" SL");
   else     PVizDel("sl"+s);
   double tp=0;
   if(tpPts>0){ tp=PPriceFromPts(buy,false,tpPts); PVizPut("tp"+s,tp,buy?clrLimeGreen:clrSeaGreen,STYLE_SOLID,side+" TP"); }
   else PVizDel("tp"+s);
   for(int k=1;k<=P_MAXPART;k++)
     {
      if(tp>0 && k<=np) PVizPut("p"+s+(string)k,TMNormPrice(entry+(tp-entry)*k/(np+1)),buy?clrOrange:clrGold,STYLE_DOT,side+" PARTIAL "+(string)k);
      else PVizDel("p"+s+(string)k);
     }
  }
void PVizApplyButton()
  {
   PSet("viz",g_pViz?"VISUALIZE: ON":"VISUALIZE");
   PSetBg("viz",g_pViz?C'150,110,30':C'90,90,110');
  }
void PVizUpdate(){ if(g_pViz){ PVizSide(true); PVizSide(false); } }
void PVizClear(){ ObjectsDeleteAll(0,PN_VIZ); g_pViz=false; PVizApplyButton(); g_pDirty=true; }
void TMPanelVizTick(){ if(g_pViz){ PVizUpdate(); PFlush(); } }

// ---------- partial level lines: planted once, tracked by reference ----------
bool PLineKnown(const ulong id)
  { for(int i=ArraySize(g_lineIds)-1;i>=0;i--) if(g_lineIds[i]==id) return true; return false; }
void PLineKnownAdd(const ulong id)
  { if(PLineKnown(id)) return; int n=ArraySize(g_lineIds); ArrayResize(g_lineIds,n+1); g_lineIds[n]=id; }
void PLineAdd(const ulong id,const int k,const string nm)
  { int n=ArraySize(g_lines); ArrayResize(g_lines,n+1); g_lines[n].id=id; g_lines[n].k=k; g_lines[n].name=nm; }

void PLinesAdopt()
  {
   ArrayResize(g_lines,0); ArrayResize(g_lineIds,0);
   for(int i=ObjectsTotal(0,0,OBJ_HLINE)-1;i>=0;i--)
     {
      string nm=ObjectName(0,i,0,OBJ_HLINE);
      if(StringFind(nm,PN_LINE)!=0) continue;
      string p[]; if(StringSplit(nm,'_',p)<4) continue;
      PLineAdd((ulong)StringToInteger(p[2]),(int)StringToInteger(p[3]),nm); PLineKnownAdd((ulong)StringToInteger(p[2]));
     }
  }
void PLinesReset()   // only when the partial count is changed on purpose
  {
   for(int i=ArraySize(g_lines)-1;i>=0;i--) ObjectDelete(0,g_lines[i].name);
   ArrayResize(g_lines,0); ArrayResize(g_lineIds,0); g_pDirty=true;
  }
void PLineDraw(const ulong id,const int k,const double price,const ulong ticket)
  {
   string nm=StringFormat("%s%I64u_%d",PN_LINE,id,k);
   if(ObjectFind(0,nm)<0)
     {
      ObjectCreate(0,nm,OBJ_HLINE,0,0,price);
      ObjectSetInteger(0,nm,OBJPROP_COLOR,clrDeepSkyBlue); ObjectSetInteger(0,nm,OBJPROP_STYLE,STYLE_DOT);
      ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false); ObjectSetInteger(0,nm,OBJPROP_HIDDEN,true);
      ObjectSetString(0,nm,OBJPROP_TEXT,StringFormat("P%d #%I64u",k,ticket));
      g_pDirty=true;
     }
   PLineAdd(id,k,nm);
  }
void PLinesSync()
  {
   for(int i=ArraySize(g_lines)-1;i>=0;i--)
     {
      int pi=TMFindPlan(g_lines[i].id);
      bool gone=!PositionSelectByTicket(g_lines[i].id);
      bool taken=(pi>=0 && g_plans[pi].partialsTaken>=g_lines[i].k);
      if(!gone && !taken) continue;
      ObjectDelete(0,g_lines[i].name); g_pDirty=true;
      int last=ArraySize(g_lines)-1;
      if(i!=last) g_lines[i]=g_lines[last];
      ArrayResize(g_lines,last);
     }
   for(int i=ArraySize(g_lineIds)-1;i>=0;i--)
      if(!PositionSelectByTicket(g_lineIds[i]))
        { int last=ArraySize(g_lineIds)-1; g_lineIds[i]=g_lineIds[last]; ArrayResize(g_lineIds,last); }

   ulong pos[]; int n=TMCollectManaged(pos);
   for(int i=0;i<n;i++)
     {
      if(!PositionSelectByTicket(pos[i])) continue;
      ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      if(PLineKnown(id)) continue;
      int pi=TMFindPlan(id); if(pi<0) continue;
      PLineKnownAdd(id);
      if(g_plans[pi].origTP<=0) continue;
      double open=PositionGetDouble(POSITION_PRICE_OPEN);
      for(int k=g_plans[pi].partialsTaken+1;k<=g_plans[pi].partialCount;k++)
         PLineDraw(id,k,TMNormPrice(open+(g_plans[pi].origTP-open)*k/(g_plans[pi].partialCount+1)),pos[i]);
     }
  }

// ---------- refresh: >= 500 ms apart, redraws the chart only if something changed ----------
void TMPanelRefresh(const bool force=false)
  {
   ulong now=GetTickCount64();
   if(!force && now-g_pLastRefresh<500) return;
   g_pLastRefresh=now;

   ulong pos[]; int n=TMCollectManaged(pos);
   g_pCount=n;
   int rows=MathMin(n,P_LISTMAX);
   bool selOk=false;
   for(int i=0;i<n;i++) if(pos[i]==g_pSel) selOk=true;
   if(!selOk) g_pSel=(n>0)? pos[0] : 0;
   if(rows!=g_pRows){ g_pRows=rows; PLayout(); }

   for(int r=0;r<P_LISTMAX;r++)
     {
      string txt=""; color col=C_TEXT;
      if(r<rows)
        {
         PositionSelectByTicket(pos[r]);
         bool buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
         double vol=PositionGetDouble(POSITION_VOLUME);
         double net=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
         int pi=TMFindPlan((ulong)PositionGetInteger(POSITION_IDENTIFIER));
         if(pi>=0 && g_plans[pi].origVolume>0) net+=g_plans[pi].entryCommission*MathMin(1.0,vol/g_plans[pi].origVolume);
         g_pTick[r]=pos[r];
         txt=StringFormat("%s %I64u %-4s %6.2f %10.2f",pos[r]==g_pSel?">":" ",pos[r],buy?"BUY":"SELL",vol,net);
         col=net>0?clrLimeGreen:(net<0?clrTomato:C_TEXT);
        }
      if(txt!=g_pCache[r])
        {
         g_pCache[r]=txt; string on=PN+"row"+(string)r;
         ObjectSetString(0,on,OBJPROP_TEXT,txt); ObjectSetInteger(0,on,OBJPROP_COLOR,col); g_pDirty=true;
        }
     }
   PSet("hdr",StringFormat("Positions: %d   Selected: %I64u",n,g_pSel));
   PUpdateQuote();
   PUpdateRiskLabel();
   if(TMAllow("plines",2)) PLinesSync();
   PFlush();
  }

// ---------- create (once) / adopt / destroy ----------
void TMPanelCreate(const ENUM_BASE_CORNER corner,const double lot,const double riskPct,const int slPts,const int tpPts,
                   const int partials,const int ddCount)
  {
   ChartSetInteger(0,CHART_EVENT_OBJECT_CREATE,false);     // no object-creation events needed
   g_pcorner=corner; ArrayResize(g_po,0);
   g_dLot=lot; g_dRisk=riskPct; g_dSL=slPts; g_dTP=tpPts; g_dPart=partials; g_dDD=ddCount;
   if(g_pReset) GlobalVariablesDeleteAll(PGV(""));

   string bg=PN+"bg", stamp=TM_BUILD+"|"+(string)(int)corner;
   g_pAdopt=(ObjectFind(0,bg)>=0 && ObjectGetString(0,bg,OBJPROP_TOOLTIP)==stamp);   // same build + corner: reuse objects
   if(!g_pAdopt) PDeleteObjects(false);
   PLinesAdopt();
   ObjectsDeleteAll(0,PN_VIZ); g_pViz=false;

   if(PBase(OBJ_RECTANGLE_LABEL,bg,P_W,100))
     {
      ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,C_BG); ObjectSetInteger(0,bg,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      ObjectSetInteger(0,bg,OBJPROP_BORDER_COLOR,C_BTN);
      ObjectSetString(0,bg,OBJPROP_TOOLTIP,stamp);
     }
   g_pLimit=(PSaved("limit")>0.5);

   PLabel("title",4,0,296,"Trading Manager Pro  "+TM_BUILD);
   PButton("mkt",4,1,146,"MARKET",C_BTN);   PButton("lmt",154,1,146,"LIMIT",C_OFF);
   PLabel("l_lot",4,2,68,"Lot");         PField("lot",74,2,76,"0");
   PLabel("l_risk",154,2,68,"Risk %");   PField("risk",224,2,76,"0");
   PLabel("l_slp",4,3,68,"SL pts");      PField("slp",74,3,76,"0");
   PLabel("l_slx",154,3,68,"SL px(B)");  PField("slx",224,3,76,"0");
   PLabel("l_tpp",4,4,68,"TP pts");      PField("tpp",74,4,76,"0");
   PLabel("l_tpx",154,4,68,"TP px(B)");  PField("tpx",224,4,76,"0");
   PLabel("l_par",4,5,68,"Partials");    PField("par",74,5,76,"0");
   PLabel("l_dd",154,5,68,"DD entr.");   PField("dd",224,5,76,"0");
   PLabel("l_px",4,6,68,"Mkt px");       PField("px",74,6,76,"0");
   PLabel("quote",154,6,146,"");
   PLabel("grisk",4,7,296,"");
   PButton("buy",4,8,146,"BUY",C_BUY);   PButton("sell",154,8,146,"SELL",C_SELL);
   PButton("viz",4,9,296,"VISUALIZE",C'90,90,110');
   PLabel("hdr",4,10,296,"Positions");
   PButton("prev",4,11,60,"< Prev",C'70,70,90');  PButton("next",68,11,60,"Next >",C'70,70,90');
   PField("pct",132,11,50,"20");  PLabel("l_pct",186,11,20,"%");
   PButton("part",210,11,90,"Partial",C'150,110,30');
   PButton("csel",4,12,70,"Close Sel",C_SELL); PButton("call",78,12,70,"Close All",C_SELL);
   PButton("beall",152,12,80,"BE Latest",C_BUY); PButton("csv",236,12,64,"CSV",C'90,90,110');
   PLabel("status",4,13,296,"Ready");
   for(int r=0;r<P_LISTMAX;r++) { g_pCache[r]="~"; PLabel("row"+(string)r,4,P_TOPROWS+r,296,"",r); }

   g_pRows=g_pAdopt ? -1 : 0;             // adopted: force one layout pass on the first refresh
   if(!g_pAdopt) PLayout();
   if(!g_pAdopt) PSet("pct",DoubleToString(PEff("pct",20),0));
   PApplyDefaults(); PApplyType(); PVizApplyButton();
   TMPanelRefresh(true);
  }

void TMPanelDestroy(const int reason)
  {
   ObjectsDeleteAll(0,PN_VIZ);
   if(reason==REASON_REMOVE) { PDeleteObjects(true); ChartRedraw(); }   // otherwise the panel stays and is adopted
  }

void PStatus(const string s){ PSet("status",s); }

// ---------- events ----------
bool PIsField(const string nm)
  { return nm=="lot"||nm=="risk"||nm=="slp"||nm=="slx"||nm=="tpp"||nm=="tpx"||nm=="par"||nm=="dd"||nm=="px"||nm=="pct"; }

void PHandleEdit(const string nm)
  {
   double v=PGetD(nm);
   if(nm=="lot")       { PCommit("lot",v>0?TMNormVol(v):0); PApplyDefaults(); }
   else if(nm=="risk") { double s=PGetD("slp"); if(s>0 && v>0) PCommit("lot",TMLotFromRisk(v,s)); PApplyDefaults(); }
   else if(nm=="slp")  { PCommit("slp",v>0?MathRound(v):0); PApplyDefaults(); }
   else if(nm=="slx")  { double p=v>0?PPtsFromPrice(true,true,v):0; PCommit("slp",p>0?p:0); PApplyDefaults(); }
   else if(nm=="tpp")  { PCommit("tpp",v>0?MathRound(v):0); PApplyDefaults(); }
   else if(nm=="tpx")  { double p=v>0?PPtsFromPrice(true,false,v):0; PCommit("tpp",p>0?p:0); PApplyDefaults(); }
   else if(nm=="par")
     {
      PCommit("par",v>0?MathMin(P_MAXPART,MathRound(v)):0); PApplyDefaults();
      if(TMApplyPartialCount((int)PGetD("par"))>0)    // open trades follow; taken partials are kept
        { PLinesReset(); PLinesSync(); PStatus("Partials updated on open trades"); }
     }
   else if(nm=="dd")   { PCommit("dd",v>0?MathMin(P_MAXDD,MathRound(v)):0); PApplyDefaults(); }
   else if(nm=="pct")  { PCommit("pct",v>0?v:0); if(v<=0) PSet("pct","20"); }
   else if(nm=="px")   { PSyncPrices(); }
   g_pFreeze=0;
   PUpdateRiskLabel();
   PVizUpdate();
  }

void PSend(const bool buy)
  {
   TMOrderReq r; ZeroMemory(r);
   r.isBuy=buy; r.isLimit=g_pLimit; r.lot=PGetD("lot"); r.riskPct=0;
   r.slPts=PGetD("slp"); r.tpPts=PGetD("tpp"); r.limitPrice=PGetD("px");
   r.partials=(int)PGetD("par"); r.ddCount=(int)PGetD("dd");
   if(r.lot<=0){ Alert("Lot is 0. Enter a lot size first."); return; }
   if(g_pLimit && r.limitPrice<=0){ Alert("Enter a limit price first"); return; }
   bool ok=TMSendOrder(r);
   PStatus(ok?(buy?"Buy sent":"Sell sent"):"Order refused, see Experts log");
   if(ok) PVizClear();
  }

void TMPanelEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   if(StringFind(sparam,PN)!=0) return;
   string nm=StringSubstr(sparam,StringLen(PN));
   if(id==CHARTEVENT_OBJECT_ENDEDIT) { PHandleEdit(nm); PFlush(); return; }
   if(id!=CHARTEVENT_OBJECT_CLICK) return;
   if(PIsField(nm)){ g_pFreeze=GetTickCount64()+20000; return; }        // hold live updates while typing
   if(ObjectGetInteger(0,sparam,OBJPROP_TYPE)==OBJ_BUTTON){ ObjectSetInteger(0,sparam,OBJPROP_STATE,false); g_pDirty=true; }

   if(nm=="mkt")
     {
      g_pLimit=false; GlobalVariableDel(PGV("limit")); PApplyType(); g_pFreeze=0; TMPanelRefresh(true); PVizUpdate();
     }
   else if(nm=="lmt")
     {
      g_pLimit=true; GlobalVariableSet(PGV("limit"),1);
      PSet("px",DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_ASK),_Digits));   // current market price as the base
      PApplyType(); PVizUpdate();
     }
   else if(nm=="buy")  PSend(true);
   else if(nm=="sell") PSend(false);
   else if(nm=="viz")
     {
      if(g_pViz) PVizClear();
      else { g_pViz=true; PVizApplyButton(); PVizUpdate(); }
     }
   else if(nm=="prev" || nm=="next")
     {
      int idx=-1; for(int i=0;i<g_pRows;i++) if(g_pTick[i]==g_pSel) idx=i;
      if(g_pRows>0){ idx=(nm=="next")? (idx+1)%g_pRows : (idx<=0? g_pRows-1 : idx-1); g_pSel=g_pTick[idx]; }
      TMPanelRefresh(true); return;
     }
   else if(nm=="part") { PStatus(TMManualPartialPct(g_pSel,PGetD("pct"))?"Partial sent":"Partial failed"); TMPanelRefresh(true); return; }
   else if(nm=="csel") { PStatus(TMManualCloseSelected(g_pSel)?"Closed selected":"Close failed"); TMPanelRefresh(true); return; }
   else if(nm=="call")
     {
      if(MessageBox("Close ALL managed positions (also at a loss) and delete this EA's pending orders?","Close All",MB_YESNO|MB_ICONWARNING)==IDYES)
        { TMManualCloseAll(); PStatus("Close All done"); }
      TMPanelRefresh(true); return;
     }
   else if(nm=="beall") { TMManualBEAllLatest(); PStatus("BE All Latest done, see log"); TMPanelRefresh(true); return; }
   else if(nm=="csv")   { TMExportDealsCsv(); PStatus("CSV exported"); }
   PFlush();
  }
#endif