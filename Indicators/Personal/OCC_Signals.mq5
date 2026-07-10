//+------------------------------------------------------------------+
//|  SAIYAN OCC  —  MT5 Indicator                                    |
//|  Converted from PineScript v5  (v6_1_23  2023.10.13)            |
//+------------------------------------------------------------------+
#property copyright   "SAIYAN OCC"
#property version     "6.1.23"
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   1

// Only one visible plot: Long/Short arrows
#property indicator_label1  "Signal"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrDeepSkyBlue
#property indicator_width1  3

//+------------------------------------------------------------------+
//|  INPUTS                                                          |
//+------------------------------------------------------------------+
input group            "═══ Performance ═══"
input int              InpMaxBars          = 1000;
input bool             InpLimitBars        = true;

input group            "═══ NON REPAINT ═══"
input ENUM_TIMEFRAMES  InpHTF              = PERIOD_M15;
input int              InpIntRes           = 8;

input group            "═══ MA Settings ═══"
input string           InpBasisType        = "ALMA";
input int              InpBasisLen         = 2;
input int              InpOffsetSigma      = 5;
input double           InpOffsetALMA       = 0.85;
input int              InpDelayOffset      = 0;

input group            "═══ Settings ═══"
input int              InpSwingLength      = 10;
input int              InpHistoryKeep      = 20;
input double           InpBoxWidth         = 2.5;

input group            "═══ Risk Management ═══"
input double           InpTP1Lvl           = 1.0;
input double           InpTP1Qty           = 50.0;
input double           InpTP2Lvl           = 1.5;
input double           InpTP2Qty           = 30.0;
input double           InpTP3Lvl           = 2.0;
input double           InpTP3Qty           = 20.0;
input double           InpSLLvl            = 0.5;

input group            "═══ SR Levels ═══"
input bool             InpEnableSR         = false;
input color            InpColorSup         = clrDarkGreen;
input color            InpColorRes         = clrDarkRed;
input int              InpStrengthSR       = 2;
input string           InpLineStyleSR      = "Dotted";
input int              InpSRLineWidth      = 2;
input bool             InpUseZones         = true;
input bool             InpExpandSR         = true;

input group            "═══ Visual Settings ═══"
input color            InpSupplyColor      = clrDarkRed;
input color            InpSupplyOutline    = clrFireBrick;
input color            InpDemandColor      = clrDarkSlateGray;
input color            InpDemandOutline    = clrSteelBlue;
input color            InpBOSColor         = clrGold;
input color            InpPOIColor         = clrWhite;
input color            InpSwingColor       = clrSilver;

input group            "═══ Visibility Toggles ═══"
input bool             InpShowEntryLine    = true;
input bool             InpShowTPLines      = true;
input bool             InpShowSLLine       = true;
input bool             InpShowLongSignals  = true;
input bool             InpShowShortSignals = true;
input bool             InpShowTPLabels     = true;
input bool             InpShowSupply       = true;
input bool             InpShowDemand       = true;
input bool             InpShowBOSMarkers   = true;
input bool             InpShowSRLines      = true;
input bool             InpShowPALabels     = false;
input bool             InpAlertLabels      = true;

//+------------------------------------------------------------------+
//|  BUFFERS  (internal only — no visible plots)                     |
//+------------------------------------------------------------------+
double BufAlmaClose[];   // 0 — internal
double BufAlmaOpen[];    // 1 — internal
double BufSignal[];      // 2 — arrow plot (long+short combined)

//+------------------------------------------------------------------+
//|  HTF CACHE                                                       |
//+------------------------------------------------------------------+
double   g_htfAlmaClose[];
double   g_htfAlmaOpen[];
datetime g_htfTime[];
int      g_htfTotal = 0;

//+------------------------------------------------------------------+
//|  STATE MACHINE                                                   |
//+------------------------------------------------------------------+
double   g_condition   = 0.0;
double   g_entryPrice  = 0.0;
double   g_slLine      = 0.0;
double   g_tp1Line     = 0.0;
double   g_tp2Line     = 0.0;
double   g_tp3Line     = 0.0;
bool     g_lastIsLong  = true;

int      g_objCount    = 0;

//+------------------------------------------------------------------+
//|  PERSISTENT HLINE NAMES                                         |
//+------------------------------------------------------------------+
string g_nameEntry  = "";
string g_nameTP1    = "";
string g_nameTP2    = "";
string g_nameTP3    = "";
string g_nameSL     = "";
string g_nameEntLbl = "";
string g_nameTP1Lbl = "";
string g_nameTP2Lbl = "";
string g_nameTP3Lbl = "";
string g_nameSLLbl  = "";

//+------------------------------------------------------------------+
//|  SUPPLY/DEMAND                                                   |
//+------------------------------------------------------------------+
struct SDZone { double top,bottom; datetime startTime; int id; bool active,isBOS; };
SDZone g_supplyZones[];
SDZone g_demandZones[];
double g_srLevels[];
double g_srHighest=0.0, g_srLowest=0.0;

//════════════════════════════════════════════════════════════════════
//  MATH
//════════════════════════════════════════════════════════════════════
double ALMA(const double &src[],int idx,int len,double offset,double sigma)
{
    if(idx<len-1) return 0.0;
    double m=offset*(len-1),s=(double)len/sigma,norm=0,sum=0;
    for(int i=0;i<len;i++){double w=MathExp(-((i-m)*(i-m))/(2*s*s));sum+=w*src[idx-(len-1-i)];norm+=w;}
    return norm!=0?sum/norm:0;
}
double TEMA(const double &src[],int idx,int len)
{
    if(idx<3) return src[idx];
    double k=2.0/(len+1),e1=src[0],e2=src[0],e3=src[0];
    for(int i=1;i<=idx;i++){e1=src[i]*k+e1*(1-k);e2=e1*k+e2*(1-k);e3=e2*k+e3*(1-k);}
    return 3*e1-3*e2+e3;
}
double HullMA(const double &src[],int idx,int len)
{
    if(idx<len) return src[idx];
    int half=len/2; double wH=0,wF=0,mH=0,mF=0;
    for(int i=0;i<half&&idx-i>=0;i++){mH+=(half-i)*src[idx-i];wH+=(half-i);}
    for(int i=0;i<len&&idx-i>=0;i++){mF+=(len-i)*src[idx-i];wF+=(len-i);}
    return (wH==0||wF==0)?src[idx]:2*(mH/wH)-(mF/wF);
}
double Variant(const double &src[],int idx,int len,int offSig,double offALMA,string type)
{
    if(type=="ALMA")   return ALMA(src,idx,len,offALMA,(double)offSig);
    if(type=="TEMA")   return TEMA(src,idx,len);
    if(type=="HullMA") return HullMA(src,idx,len);
    double s=0;int c=0;for(int i=0;i<len&&idx-i>=0;i++){s+=src[idx-i];c++;}return c>0?s/c:src[idx];
}
void BuildATR(const double &h[],const double &l[],const double &c[],double &dst[],int total,int period)
{
    if(total<2) return;
    dst[0]=h[0]-l[0]; double sum=0;
    for(int i=1;i<MathMin(period+1,total);i++){double tr=MathMax(h[i]-l[i],MathMax(MathAbs(h[i]-c[i-1]),MathAbs(l[i]-c[i-1])));sum+=tr;dst[i]=sum/i;}
    if(total<=period) return; dst[period]=sum/period;
    for(int i=period+1;i<total;i++){double tr=MathMax(h[i]-l[i],MathMax(MathAbs(h[i]-c[i-1]),MathAbs(l[i]-c[i-1])));dst[i]=(dst[i-1]*(period-1)+tr)/period;}
}
bool IsPivotHigh(const double &h[],int idx,int left,int right,double &val)
{
    if(idx<left+right) return false;
    int c=idx-right; val=h[c];
    for(int i=c-left;i<=c+right;i++) if(i!=c&&h[i]>=val) return false;
    return true;
}
bool IsPivotLow(const double &l[],int idx,int left,int right,double &val)
{
    if(idx<left+right) return false;
    int c=idx-right; val=l[c];
    for(int i=c-left;i<=c+right;i++) if(i!=c&&l[i]<=val) return false;
    return true;
}
int HTFIndex(datetime t)
{
    int lo=0,hi=g_htfTotal-1,res=-1;
    while(lo<=hi){int mid=(lo+hi)/2;if(g_htfTime[mid]<=t){res=mid;lo=mid+1;}else hi=mid-1;}
    return res;
}
bool LoadHTF()
{
    MqlRates rates[];
    int total=CopyRates(_Symbol,InpHTF,0,3000,rates);
    if(total<InpBasisLen+2) return false;
    ArrayResize(g_htfAlmaClose,total); ArrayResize(g_htfAlmaOpen,total); ArrayResize(g_htfTime,total);
    double htfC[],htfO[]; ArrayResize(htfC,total); ArrayResize(htfO,total);
    for(int i=0;i<total;i++){g_htfTime[i]=rates[i].time;htfC[i]=rates[i].close;htfO[i]=rates[i].open;}
    for(int i=0;i<total;i++)
    {
        int si=MathMax(0,i-InpDelayOffset);
        g_htfAlmaClose[i]=Variant(htfC,si,InpBasisLen,InpOffsetSigma,InpOffsetALMA,InpBasisType);
        g_htfAlmaOpen[i] =Variant(htfO,si,InpBasisLen,InpOffsetSigma,InpOffsetALMA,InpBasisType);
    }
    g_htfTotal=total; return true;
}

//════════════════════════════════════════════════════════════════════
//  OBJECT HELPERS
//════════════════════════════════════════════════════════════════════
string ObjName(string prefix){g_objCount++;return prefix+IntegerToString(g_objCount);}
void   ObjDel(string &n){if(n!=""){ObjectDelete(0,n);n="";}}


void ObjText(string name,string txt,datetime t,double price,color clr,
             int sz=9,ENUM_ANCHOR_POINT anchor=ANCHOR_LEFT_LOWER)
{
    if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
    ObjectCreate(0,name,OBJ_TEXT,0,t,price);
    ObjectSetString(0,name,OBJPROP_TEXT,txt);
    ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
    ObjectSetInteger(0,name,OBJPROP_FONTSIZE,sz);
    ObjectSetString(0,name,OBJPROP_FONT,"Arial");
    ObjectSetInteger(0,name,OBJPROP_ANCHOR,anchor);
    ObjectSetInteger(0,name,OBJPROP_BACK,false);
    ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
}
void ObjArrow(string name,int code,datetime t,double price,color clr,int width=3,bool anchorTop=true)
{
    if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
    ObjectCreate(0,name,OBJ_ARROW,0,t,price);
    ObjectSetInteger(0,name,OBJPROP_ARROWCODE,code);
    ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
    ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
    ObjectSetInteger(0,name,OBJPROP_ANCHOR,anchorTop?ANCHOR_TOP:ANCHOR_BOTTOM);
    ObjectSetInteger(0,name,OBJPROP_BACK,false);
    ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
}
void ObjTrend(string name,double price,datetime t1,datetime t2,color clr,ENUM_LINE_STYLE sty,int width,bool ray=false)
{
    if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
    ObjectCreate(0,name,OBJ_TREND,0,t1,price,t2,price);
    ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
    ObjectSetInteger(0,name,OBJPROP_STYLE,sty);
    ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
    ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,ray);
    ObjectSetDouble(0,name,OBJPROP_PRICE,0,price);
    ObjectSetDouble(0,name,OBJPROP_PRICE,1,price);
    ObjectSetInteger(0,name,OBJPROP_BACK,false);
    ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
}
void ObjRect(string name,double top,double bottom,datetime t1,datetime t2,color fill,color border)
{
    if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
    ObjectCreate(0,name,OBJ_RECTANGLE,0,t1,top,t2,bottom);
    ObjectSetInteger(0,name,OBJPROP_COLOR,border);
    ObjectSetInteger(0,name,OBJPROP_BGCOLOR,fill);
    ObjectSetInteger(0,name,OBJPROP_FILL,true);
    ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
    ObjectSetInteger(0,name,OBJPROP_BACK,true);
    ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
}
ENUM_LINE_STYLE SRStyle(){if(InpLineStyleSR=="Solid")return STYLE_SOLID;if(InpLineStyleSR=="Dashed")return STYLE_DASH;return STYLE_DOT;}

//════════════════════════════════════════════════════════════════════
//  TP/SL PANEL — pure OBJ_HLINE, deleted on close/new signal
//════════════════════════════════════════════════════════════════════
void HideTPSLPanel()
{
    ObjDel(g_nameEntry); ObjDel(g_nameTP1); ObjDel(g_nameTP2); ObjDel(g_nameTP3); ObjDel(g_nameSL);
    ObjDel(g_nameEntLbl); ObjDel(g_nameTP1Lbl); ObjDel(g_nameTP2Lbl); ObjDel(g_nameTP3Lbl); ObjDel(g_nameSLLbl);
}

// Stores entry time so lines can be drawn from signal bar
datetime g_panelEntryTime = 0;

void DrawTPSLPanel(datetime entryTime)
{
    HideTPSLPanel();
    g_panelEntryTime = entryTime;

    datetime t2  = entryTime + PeriodSeconds(PERIOD_CURRENT)*500;
    datetime lbl = t2 + PeriodSeconds(PERIOD_CURRENT)*2;

    g_nameEntry=ObjName("LN_E"); g_nameTP1=ObjName("LN_1");
    g_nameTP2=ObjName("LN_2");   g_nameTP3=ObjName("LN_3"); g_nameSL=ObjName("LN_S");

    if(InpShowEntryLine) ObjTrend(g_nameEntry, g_entryPrice, entryTime, t2, clrRoyalBlue,       STYLE_SOLID, 1, false);
    if(InpShowTPLines)   ObjTrend(g_nameTP1,   g_tp1Line,   entryTime, t2, clrLimeGreen,        STYLE_DASH,  1, false);
    if(InpShowTPLines)   ObjTrend(g_nameTP2,   g_tp2Line,   entryTime, t2, clrMediumSeaGreen,   STYLE_DASH,  1, false);
    if(InpShowTPLines)   ObjTrend(g_nameTP3,   g_tp3Line,   entryTime, t2, clrDarkGreen,        STYLE_DASH,  1, false);
    if(InpShowSLLine)    ObjTrend(g_nameSL,    g_slLine,    entryTime, t2, clrCrimson,          STYLE_DASH,  1, false);

    g_nameEntLbl=ObjName("LB_E"); g_nameTP1Lbl=ObjName("LB_1");
    g_nameTP2Lbl=ObjName("LB_2"); g_nameTP3Lbl=ObjName("LB_3"); g_nameSLLbl=ObjName("LB_S");

    if(InpShowEntryLine) ObjText(g_nameEntLbl,"Entry: "+DoubleToString(g_entryPrice,_Digits),lbl,g_entryPrice,clrRoyalBlue,    8);
    if(InpShowTPLines)   ObjText(g_nameTP1Lbl,"TP1: "  +DoubleToString(g_tp1Line,  _Digits),lbl,g_tp1Line,   clrLimeGreen,    8);
    if(InpShowTPLines)   ObjText(g_nameTP2Lbl,"TP2: "  +DoubleToString(g_tp2Line,  _Digits),lbl,g_tp2Line,   clrMediumSeaGreen,8);
    if(InpShowTPLines)   ObjText(g_nameTP3Lbl,"TP3: "  +DoubleToString(g_tp3Line,  _Digits),lbl,g_tp3Line,   clrDarkGreen,    8);
    if(InpShowSLLine)    ObjText(g_nameSLLbl, "SL: "   +DoubleToString(g_slLine,   _Digits),lbl,g_slLine,    clrCrimson,      8);
}

//════════════════════════════════════════════════════════════════════
//  SIGNAL ARROW
//════════════════════════════════════════════════════════════════════
void DrawSignal(bool isLong,datetime t,double price,double atr)
{
    if(!InpAlertLabels) return;
    if(isLong  && !InpShowLongSignals)  return;
    if(!isLong && !InpShowShortSignals) return;
    double arrowPx=isLong?price-atr*0.5:price+atr*0.5;
    double textPx =isLong?price-atr*0.9:price+atr*0.9;
    ObjArrow(ObjName(isLong?"AL":"AS"),isLong?233:234,t,arrowPx,
             isLong?clrDeepSkyBlue:clrDeepPink,3,isLong);
    ObjText(ObjName(isLong?"TL":"TS"),isLong?"▲ Long":"▼ Short",t,textPx,
            isLong?clrDeepSkyBlue:clrDeepPink,9,
            isLong?ANCHOR_LEFT_UPPER:ANCHOR_LEFT_LOWER);
}

void DrawEventLabel(string txt,datetime t,double price,color clr)
{
    if(!InpAlertLabels||!InpShowTPLabels) return;
    ObjText(ObjName("EV"),txt,t,price,clr,8,ANCHOR_LEFT_LOWER);
}

void DrawSwingLabel(string txt,datetime t,double price,bool isHigh)
{
    if(!InpShowPALabels) return;
    ObjText(ObjName("SW"),txt,t,price,InpSwingColor,8,
            isHigh?ANCHOR_LEFT_LOWER:ANCHOR_LEFT_UPPER);
}

//════════════════════════════════════════════════════════════════════
//  SUPPLY / DEMAND
//════════════════════════════════════════════════════════════════════
bool ZoneOverlaps(SDZone &zones[],double newPOI,double atr)
{
    for(int i=0;i<ArraySize(zones);i++)
        if(zones[i].active&&MathAbs(newPOI-(zones[i].top+zones[i].bottom)/2.0)<atr*2.0) return true;
    return false;
}
void DeleteZoneObj(int id)
{
    string s=IntegerToString(id);
    ObjectDelete(0,"SDZ"+s);ObjectDelete(0,"SDZT"+s);ObjectDelete(0,"SDZP"+s);ObjectDelete(0,"SDZL"+s);
}
void DrawZoneObjects(int id,double top,double bottom,datetime t,bool isSupply)
{
    datetime t2=TimeCurrent()+PeriodSeconds(PERIOD_CURRENT)*300;
    string s=IntegerToString(id);
    ObjRect("SDZ"+s,top,bottom,t,t2,isSupply?InpSupplyColor:InpDemandColor,isSupply?InpSupplyOutline:InpDemandOutline);
    datetime tMid=(datetime)(((long)t+(long)t2)/2);
    double pMid=(top+bottom)/2.0;
    ObjText("SDZT"+s,isSupply?"SUPPLY":"DEMAND",tMid,pMid,InpPOIColor,8,ANCHOR_LEFT_LOWER);
    ObjTrend("SDZP"+s,pMid,t,t2,clrGray,STYLE_DOT,1,false);
    ObjText("SDZL"+s,"POI",t,pMid,InpPOIColor,7,ANCHOR_LEFT_LOWER);
}
void ExtendZoneObj(int id)
{
    string rn="SDZ"+IntegerToString(id);
    if(ObjectFind(0,rn)<0) return;
    datetime t2=TimeCurrent()+PeriodSeconds(PERIOD_CURRENT)*300;
    ObjectSetInteger(0,rn,OBJPROP_TIME,1,t2);
    string pn="SDZP"+IntegerToString(id);
    if(ObjectFind(0,pn)>=0) ObjectSetInteger(0,pn,OBJPROP_TIME,1,t2);
}
void AddZone(SDZone &zones[],double top,double bottom,datetime t,bool isSupply,double atr)
{
    if(isSupply&&!InpShowSupply)   return;
    if(!isSupply&&!InpShowDemand)  return;
    if(ZoneOverlaps(zones,(top+bottom)/2.0,atr)) return;
    int active=0;
    for(int i=0;i<ArraySize(zones);i++) if(zones[i].active) active++;
    if(active>=InpHistoryKeep)
        for(int i=0;i<ArraySize(zones);i++) if(zones[i].active){DeleteZoneObj(zones[i].id);zones[i].active=false;break;}
    int idx=ArraySize(zones); ArrayResize(zones,idx+1);
    zones[idx].top=top; zones[idx].bottom=bottom; zones[idx].startTime=t;
    zones[idx].id=++g_objCount; zones[idx].active=true; zones[idx].isBOS=false;
    DrawZoneObjects(zones[idx].id,top,bottom,t,isSupply);
}
void CheckBOS(SDZone &zones[],double closePrice,datetime t,bool isSupply)
{
    // BOS visuals removed — only deactivate the zone on break
    for(int i=0;i<ArraySize(zones);i++)
    {
        if(!zones[i].active||zones[i].isBOS) continue;
        bool broken=isSupply?closePrice>=zones[i].top:closePrice<=zones[i].bottom;
        if(!broken) continue;
        DeleteZoneObj(zones[i].id);
        zones[i].isBOS=true; zones[i].active=false;
    }
}

//════════════════════════════════════════════════════════════════════
//  SR LEVELS
//════════════════════════════════════════════════════════════════════
void BuildSRLevels(const double &high[],const double &low[],int total,int curIdx)
{
    int rb=10,prd=284,channelW=10;
    double prdhighest=-DBL_MAX,prdlowest=DBL_MAX;
    for(int i=MathMax(0,curIdx-prd);i<=curIdx;i++){if(high[i]>prdhighest)prdhighest=high[i];if(low[i]<prdlowest)prdlowest=low[i];}
    g_srHighest=prdhighest; g_srLowest=prdlowest;
    double cwidth=(prdhighest-prdlowest)*channelW/100.0;
    int countpp=0; bool aas[41]; for(int i=0;i<41;i++) aas[i]=true;
    ArrayResize(g_srLevels,21); for(int i=0;i<21;i++) g_srLevels[i]=0.0;
    for(int x=0;x<=prd&&x<=curIdx;x++)
    {
        double ph=0,pl=0;
        bool hasPH=IsPivotHigh(high,curIdx-x,rb,rb,ph);
        bool hasPL=IsPivotLow(low,curIdx-x,rb,rb,pl);
        if(!hasPH&&!hasPL) continue;
        countpp++; if(countpp>40) break; if(!aas[countpp]) continue;
        double pivVal=hasPH?high[curIdx-x]:low[curIdx-x];
        double upl=pivVal+cwidth,dnl=pivVal-cwidth;
        int tpoint=0; bool tmp[41]; for(int i=0;i<41;i++) tmp[i]=true; int cnt=0;
        for(int xx=0;xx<=prd&&xx<=curIdx;xx++)
        {
            double pph=0,ppl=0;
            bool hPH=IsPivotHigh(high,curIdx-xx,rb,rb,pph);
            bool hPL=IsPivotLow(low,curIdx-xx,rb,rb,ppl);
            if(!hPH&&!hPL) continue;
            cnt++; if(cnt>40) break; if(!aas[cnt]) continue;
            bool chg=false;
            if(hPH&&high[curIdx-xx]>=dnl&&high[curIdx-xx]<=upl){tpoint++;chg=true;}
            if(hPL&&low[curIdx-xx]>=dnl&&low[curIdx-xx]<=upl){tpoint++;chg=true;}
            if(chg&&cnt<41) tmp[cnt]=false;
        }
        if(tpoint>=InpStrengthSR){for(int g=0;g<41;g++) if(!tmp[g]) aas[g]=false;if(countpp<21) g_srLevels[countpp]=pivVal;}
    }
}
void RedrawSRLines(const double &close[],int curIdx,datetime t1,datetime t2)
{
    ObjectsDeleteAll(0,"SR_");
    if(!InpEnableSR||!InpShowSRLines) return;
    double zonePerc=(g_srHighest-g_srLowest)*2.0/100.0;
    ENUM_LINE_STYLE sty=SRStyle();
    color hiCol=close[curIdx]>=g_srHighest?InpColorSup:InpColorRes;
    color loCol=close[curIdx]>=g_srLowest?InpColorSup:InpColorRes;
    ObjTrend(ObjName("SR_H"),g_srHighest,t1,t2,hiCol,sty,InpSRLineWidth,InpExpandSR);
    ObjTrend(ObjName("SR_L"),g_srLowest, t1,t2,loCol,sty,InpSRLineWidth,InpExpandSR);
    ObjText(ObjName("SR_HT"),"High: "+DoubleToString(g_srHighest,_Digits),t2,g_srHighest,hiCol,7);
    ObjText(ObjName("SR_LT"),"Low: " +DoubleToString(g_srLowest, _Digits),t2,g_srLowest, loCol,7);
    for(int i=0;i<21;i++)
    {
        if(g_srLevels[i]==0.0) continue;
        color col=close[curIdx]>=g_srLevels[i]?InpColorSup:InpColorRes;
        ObjTrend(ObjName("SR_"),g_srLevels[i],t1,t2,col,sty,InpSRLineWidth,InpExpandSR);
        ObjText(ObjName("SR_T"),DoubleToString(NormalizeDouble(g_srLevels[i],_Digits),_Digits),t2,g_srLevels[i],col,7);
        if(InpUseZones) ObjRect(ObjName("SR_Z"),g_srLevels[i]+zonePerc,g_srLevels[i]-zonePerc,t1,t2,col==InpColorSup?clrDarkGreen:clrDarkRed,col);
    }
}

//════════════════════════════════════════════════════════════════════
//  STATE MACHINE
//════════════════════════════════════════════════════════════════════
void SetTPSLLevels(bool isLong,double src)
{
    double dir=isLong?1.0:-1.0;
    g_entryPrice=src;
    g_tp1Line=src+dir*src*InpTP1Lvl/100.0;
    g_tp2Line=src+dir*src*InpTP2Lvl/100.0;
    g_tp3Line=src+dir*src*InpTP3Lvl/100.0;
    g_slLine =src-dir*src*InpSLLvl /100.0;
}
void UpdateCondition(bool leTrig,bool seTrig,double barH,double barL)
{
    double prev=g_condition;
    if(leTrig&&prev<=0.0){g_condition=1.0;return;}
    if(seTrig&&prev>=0.0){g_condition=-1.0;return;}
    bool tp1L=prev==1.0&&barH>g_tp1Line, tp1S=prev==-1.0&&barL<g_tp1Line;
    bool tp2L=prev==1.1&&barH>g_tp2Line, tp2S=prev==-1.1&&barL<g_tp2Line;
    bool tp3L=prev==1.2&&barH>g_tp3Line, tp3S=prev==-1.2&&barL<g_tp3Line;
    bool slL=prev>=1.0&&barL<g_slLine,   slS=prev<=-1.0&&barH>g_slLine;
    if(tp3L)      g_condition=1.3;
    else if(tp3S) g_condition=-1.3;
    else if(tp2L) g_condition=1.2;
    else if(tp2S) g_condition=-1.2;
    else if(tp1L) g_condition=1.1;
    else if(tp1S) g_condition=-1.1;
    else if(slL||slS) g_condition=0.0;
}

//════════════════════════════════════════════════════════════════════
//  ONINIT
//════════════════════════════════════════════════════════════════════
int OnInit()
{
    SetIndexBuffer(0,BufAlmaClose,INDICATOR_CALCULATIONS);
    SetIndexBuffer(1,BufAlmaOpen, INDICATOR_CALCULATIONS);
    SetIndexBuffer(2,BufSignal,   INDICATOR_DATA);

    PlotIndexSetDouble(2,PLOT_EMPTY_VALUE,0.0);
    PlotIndexSetInteger(2,PLOT_ARROW,159);
    PlotIndexSetInteger(0,PLOT_DRAW_TYPE,DRAW_NONE);
    PlotIndexSetInteger(1,PLOT_DRAW_TYPE,DRAW_NONE);

    IndicatorSetString(INDICATOR_SHORTNAME,"SAIYAN OCC v6.1.23");
    IndicatorSetInteger(INDICATOR_DIGITS,_Digits);

    g_condition=0.0; g_entryPrice=0.0;
    g_slLine=0.0; g_tp1Line=0.0; g_tp2Line=0.0; g_tp3Line=0.0;
    ArrayResize(g_supplyZones,0); ArrayResize(g_demandZones,0); ArrayResize(g_srLevels,21);
    return INIT_SUCCEEDED;
}

//════════════════════════════════════════════════════════════════════
//  ONDEINIT
//════════════════════════════════════════════════════════════════════
void OnDeinit(const int reason)
{
    string pfx[]={"AL","AS","TL","TS","EV","SW","LN_","LB_","SDZ","SR_"};
    for(int i=0;i<ArraySize(pfx);i++) ObjectsDeleteAll(0,pfx[i]);
}

//════════════════════════════════════════════════════════════════════
//  ONCALCULATE
//════════════════════════════════════════════════════════════════════
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
{
    if(rates_total<100) return 0;

    bool fullRecalc=(prev_calculated==0);
    int minRequired=MathMax(InpSwingLength*2+InpBasisLen+10,100);
    int limitedStart=InpLimitBars?MathMax(rates_total-InpMaxBars,minRequired):minRequired;
    int startBar=fullRecalc?limitedStart:rates_total-1;

    static datetime lastHTFTime=0;
    datetime curHTF=iTime(_Symbol,InpHTF,0);
    if(fullRecalc||curHTF!=lastHTFTime){if(!LoadHTF()) return 0; lastHTFTime=curHTF;}

    static double atrBuf[];
    if(fullRecalc)
    {
        ArrayResize(atrBuf,rates_total);
        BuildATR(high,low,close,atrBuf,rates_total,14);
        for(int i=0;i<limitedStart;i++){BufAlmaClose[i]=0;BufAlmaOpen[i]=0;BufSignal[i]=0;}
        g_condition=0.0; g_entryPrice=0.0;
        ArrayResize(g_supplyZones,0); ArrayResize(g_demandZones,0);
    }
    else
    {
        int i=rates_total-1;
        if(ArraySize(atrBuf)<rates_total) ArrayResize(atrBuf,rates_total);
        double tr=MathMax(high[i]-low[i],MathMax(MathAbs(high[i]-close[i-1]),MathAbs(low[i]-close[i-1])));
        atrBuf[i]=(atrBuf[i-1]*13+tr)/14.0;
    }

    for(int i=startBar;i<rates_total;i++)
    {
        int hi=HTFIndex(time[i]);
        if(hi<1){BufAlmaClose[i]=0;BufAlmaOpen[i]=0;BufSignal[i]=0;continue;}

        double almaC=g_htfAlmaClose[hi];
        double almaO=g_htfAlmaOpen[hi];
        BufAlmaClose[i]=almaC;
        BufAlmaOpen[i] =almaO;

        int    hiPrev=(i>0)?HTFIndex(time[i-1]):hi;
        double almaCprev=(hiPrev>=0)?g_htfAlmaClose[hiPrev]:almaC;
        double almaOprev=(hiPrev>=0)?g_htfAlmaOpen[hiPrev] :almaO;

        bool leTrigger=almaC>almaO&&almaCprev<=almaOprev;
        bool seTrigger=almaC<almaO&&almaCprev>=almaOprev;

        double prevCond=g_condition;
        if(leTrigger&&g_condition<=0.0) SetTPSLLevels(true, close[i]);
        if(seTrigger&&g_condition>=0.0) SetTPSLLevels(false,close[i]);

        UpdateCondition(leTrigger,seTrigger,high[i],low[i]);

        bool isFlat     =(g_condition==0.0);
        bool longSignal =leTrigger&&prevCond<=0.0&&g_condition==1.0;
        bool shortSignal=seTrigger&&prevCond>=0.0&&g_condition==-1.0;

        BufSignal[i]=0.0;
        if(longSignal  && InpShowLongSignals)  BufSignal[i]=low[i] -atrBuf[i]*0.5;
        if(shortSignal && InpShowShortSignals) BufSignal[i]=high[i]+atrBuf[i]*0.5;

        // draw objects for all bars in the window

        datetime t  =time[i];
        double   atr=atrBuf[i];

        if(longSignal)
        {
            DrawSignal(true,t,low[i],atr);
            if(InpShowEntryLine||InpShowTPLines||InpShowSLLine) DrawTPSLPanel(t);
        }
        if(shortSignal)
        {
            DrawSignal(false,t,high[i],atr);
            if(InpShowEntryLine||InpShowTPLines||InpShowSLLine) DrawTPSLPanel(t);
        }

        // TP/SL event labels — fire once per state change
        double c=g_condition;
        static double lastEvtCond=0.0;
        if(InpAlertLabels&&InpShowTPLabels&&c!=prevCond&&c!=lastEvtCond)
        {
            lastEvtCond=c;
            if(c==1.1||c==-1.1) DrawEventLabel("✓ TP1",t,close[i],clrOlive);
            if(c==1.2||c==-1.2) DrawEventLabel("✓ TP2",t,close[i],clrOlive);
            if(c==1.3||c==-1.3) DrawEventLabel("✓ TP3",t,close[i],clrOlive);
            if(c==0.0&&prevCond!=0.0)
            {
                bool bySL=(prevCond>=1.0&&low[i]<g_slLine)||(prevCond<=-1.0&&high[i]>g_slLine);
                DrawEventLabel(bySL?"✗ SL":"● Close",t,close[i],bySL?clrCrimson:clrGray);
            }
        }

        if(isFlat&&prevCond!=0.0) HideTPSLPanel();

        if(i>=InpSwingLength*2)
        {
            double atr50=atrBuf[i]*(InpBoxWidth/10.0);
            double pivH=0,pivL=0;
            if(IsPivotHigh(high,i,InpSwingLength,InpSwingLength,pivH))
            {
                if(InpShowPALabels){static double lPH=0;DrawSwingLabel(pivH>=lPH?"HH":"LH",time[i-InpSwingLength],pivH,true);lPH=pivH;}
                AddZone(g_supplyZones,pivH,pivH-atr50,time[i-InpSwingLength],true,atrBuf[i]);
            }
            if(IsPivotLow(low,i,InpSwingLength,InpSwingLength,pivL))
            {
                if(InpShowPALabels){static double lPL=0;DrawSwingLabel(pivL>=lPL?"HL":"LL",time[i-InpSwingLength],pivL,false);lPL=pivL;}
                AddZone(g_demandZones,pivL+atr50,pivL,time[i-InpSwingLength],false,atrBuf[i]);
            }
            for(int z=0;z<ArraySize(g_supplyZones);z++) if(g_supplyZones[z].active) ExtendZoneObj(g_supplyZones[z].id);
            for(int z=0;z<ArraySize(g_demandZones);z++) if(g_demandZones[z].active) ExtendZoneObj(g_demandZones[z].id);
            if(InpShowBOSMarkers){CheckBOS(g_supplyZones,close[i],t,true);CheckBOS(g_demandZones,close[i],t,false);}
        }

        static int lastSRBar=-1;
        if(InpEnableSR&&InpShowSRLines&&i==rates_total-1&&i!=lastSRBar)
        {
            lastSRBar=i;
            BuildSRLevels(high,low,rates_total,i);
            datetime t1sr=time[MathMax(0,i-355)];
            datetime t2sr=time[i]+PeriodSeconds(PERIOD_CURRENT)*400;
            RedrawSRLines(close,i,t1sr,t2sr);
        }
    }

    if(fullRecalc) ChartRedraw(0);
    return rates_total;
}
