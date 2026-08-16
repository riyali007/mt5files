//+------------------------------------------------------------------+
//| ForexReplay.mq5                                                  |
//| Attach to a normal MT5 chart: one centered Start Simulation btn. |
//| The opened SIM.* chart contains replay controls and dashboard.   |
//| Partial TPs + SL-to-BE + trade journal (CSV + PNG screenshot).   |
//| Journal uses the native ChartScreenShot() — no external DLLs.    |
//+------------------------------------------------------------------+
#property copyright "Original replay tool"
#property version   "1.40"
#property strict

input int    InpDaysBack  = 60;
input int    InpStartAgo  = 20;
input int    InpTimerMs   = 100;
input double InpBalance0  = 10000.0;
input double InpLots0     = 0.10;
input int    InpSL0       = 200;
input int    InpTP0       = 400;
input int    InpSpeed0    = 1;
input int    InpPartials0 = 0;
input int    InpBEAfter0  = 0;
input bool   InpJournal   = true;   // save CSV row + PNG screenshot per trade close
input int    InpShotW     = 1280;
input int    InpShotH     = 720;

#define TPL_NAME    "ForexReplayAuto"
#define SIM_GROUP   "Simulators"
#define SIM_PREF    "SIM."
#define UI          "FR_"
#define JOURNAL_DIR "ForexReplayJournal"
#define JOURNAL_CSV "ForexReplayJournal\\journal.csv"

#define BTN_H     28
#define BAR_PAD   14
#define BTN_Y     (BAR_PAD + BTN_H)
#define LBL_Y     (BTN_Y + 16)
#define BAR_H     (LBL_Y + 12)

#define DASH_X      8
#define DASH_Y      28
#define DASH_W      420
#define DASH_LINE_H 15
#define DASH_MAXROW 30

#define MAX_PARTIALS 10

enum ENUM_SIDE { SIDE_BUY = 1, SIDE_SELL = -1 };

struct SimPos
  {
   ulong     ticket;
   ENUM_SIDE side;
   double    lots;
   double    orig_lots;
   double    price;
   double    sl;
   double    orig_sl;     // original SL, kept so journal can show BE vs original
   double    tp;
   datetime  open_time;
   datetime  close_time;
   double    close_price;
   double    pnl;
   bool      open;
   int       partials;
   int       be_after;
   int       next_partial;
   double    plevels[MAX_PARTIALS];
   bool      be_done;
   bool      shot_on_open_done;
  };

bool     g_is_sim=false;
bool     g_playing=false;
datetime g_from=0, g_to=0, g_cursor=0;
double   g_balance=0, g_equity=0, g_peak=0, g_maxdd=0, g_closed_pnl=0;
string   g_source="", g_sim="";
MqlRates g_m1[];
int      g_m1_n=0;
SimPos   g_pos[];
ulong    g_next=1;
int      g_speed=1;
int      g_wins=0, g_losses=0;

//+------------------------------------------------------------------+
int OnInit()
  {
   g_is_sim=(bool)SymbolInfoInteger(_Symbol,SYMBOL_CUSTOM) && StringFind(_Symbol,SIM_PREF)==0;
   ChartSetInteger(0,CHART_EVENT_MOUSE_MOVE,false);
   if(g_is_sim)
      return InitReplay();
   return InitLauncher();
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   ObjectsDeleteAll(0,UI);
   Comment("");
  }

void OnTimer()
  {
   if(!g_is_sim)
     {
      LayoutLauncher();
      return;
     }

   if(g_playing)
     {
      for(int i=0;i<MathMax(1,g_speed);i++)
        {
         if(!AdvanceOneBar())
           {
            g_playing=false;
            SetBtn(UI+"PLAY","Play");
            break;
           }
        }
     }
   MarkToMarket();
   RefreshDash();
   LayoutReplay();
  }

void OnTick()
  {
   if(g_is_sim)
     {
      MarkToMarket();
      RefreshDash();
     }
  }

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   if(id==CHARTEVENT_CHART_CHANGE)
     {
      if(g_is_sim) LayoutReplay(); else LayoutLauncher();
      return;
     }

   if(id==CHARTEVENT_OBJECT_ENDEDIT)
     {
      ReadEdits();
      if(g_is_sim && sparam==UI+"ED_BAL" && CountOpen()==0 && CountClosed()==0)
        {
         g_balance=MathMax(1.0,EditNum(UI+"ED_BAL"));
         g_equity=g_balance;
         g_peak=g_balance;
        }
      if(g_is_sim) RefreshDash();
      return;
     }

   if(id!=CHARTEVENT_OBJECT_CLICK)
      return;
   ObjectSetInteger(0,sparam,OBJPROP_STATE,false);

   if(!g_is_sim)
     {
      if(sparam==UI+"START") Launch();
      return;
     }

   ReadEdits();
   if(sparam==UI+"PLAY")
     {
      g_playing=!g_playing;
      SetBtn(UI+"PLAY",g_playing ? "Pause" : "Play");
     }
   else if(sparam==UI+"STEP")
     {
      g_playing=false;
      SetBtn(UI+"PLAY","Play");
      AdvanceOneBar();
     }
   else if(sparam==UI+"SPD_M")
     {
      g_speed=MathMax(1,g_speed/2);
      SetEdit(UI+"ED_SPD",IntegerToString(g_speed));
     }
   else if(sparam==UI+"SPD_P")
     {
      g_speed=MathMin(64,g_speed*2);
      SetEdit(UI+"ED_SPD",IntegerToString(g_speed));
     }
   else if(sparam==UI+"BUY") OpenVirt(SIDE_BUY);
   else if(sparam==UI+"SELL") OpenVirt(SIDE_SELL);
   else if(sparam==UI+"CLOSE") CloseAll("manual");

   MarkToMarket();
   RefreshDash();
   ChartRedraw();
  }

//============================= LAUNCHER =============================
int InitLauncher()
  {
   if(MQLInfoInteger(MQL_TESTER))
     {
      Alert("Attach ForexReplay to a normal chart, not Strategy Tester.");
      return INIT_FAILED;
     }
   EventSetMillisecondTimer(500);
   BuildLauncher();
   return INIT_SUCCEEDED;
  }

void BuildLauncher()
  {
   Dock(UI+"BAR");
   Btn(UI+"START",140,"Start simulation");
   LayoutLauncher();
   ChartRedraw();
  }

void LayoutLauncher()
  {
   int w=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
   if(w<=0) w=900;
   PlaceDock(w);
   PlaceBtn(UI+"START",MathMax(12,(w-140)/2),140);
  }

void Launch()
  {
   if(InpDaysBack<2 || InpStartAgo>=InpDaysBack)
     {
      Alert("InpDaysBack must be greater than InpStartAgo.");
      return;
     }

   g_to=TimeCurrent();
   g_from=g_to-(datetime)InpDaysBack*86400;
   g_cursor=g_to-(datetime)InpStartAgo*86400;
   g_source=_Symbol;
   g_sim=SIM_PREF+_Symbol;
   g_balance=InpBalance0;

   if(!EnsureSymbol(g_sim,g_source)) return;
   if(!SeedToCursor(g_sim,g_source,g_from,g_cursor)) return;
   SaveSession();

   ChartSaveTemplate(0,TPL_NAME);
   long id=ChartOpen(g_sim,_Period);
   if(id==0)
     {
      Alert("ChartOpen failed. Error: ",GetLastError());
      return;
     }
   ChartSetInteger(id,CHART_AUTOSCROLL,true);
   ChartSetInteger(id,CHART_SHIFT,true);
   ChartSetInteger(id,CHART_MODE,CHART_CANDLES);
   if(!ChartApplyTemplate(id,TPL_NAME))
      Print("Template apply failed: ",GetLastError(),". Drag ForexReplay to the SIM chart once.");
  }

bool EnsureSymbol(const string sim,const string origin)
  {
   if(!(bool)SymbolInfoInteger(sim,SYMBOL_EXIST))
     {
      if(!CustomSymbolCreate(sim,SIM_GROUP,origin))
        {
         Alert("Could not create ",sim,". Error: ",GetLastError());
         return false;
        }
     }
   CustomSymbolSetInteger(sim,SYMBOL_TRADE_MODE,SYMBOL_TRADE_MODE_DISABLED);
   CustomSymbolSetInteger(sim,SYMBOL_SPREAD_FLOAT,false);
   CustomSymbolSetInteger(sim,SYMBOL_SPREAD,MathMax(1,(int)SymbolInfoInteger(origin,SYMBOL_SPREAD)));
   CustomSymbolSetString(sim,SYMBOL_DESCRIPTION,"Replay "+origin);
   if(!SymbolSelect(sim,true))
     {
      Alert("Could not select ",sim,". Error: ",GetLastError());
      return false;
     }
   return true;
  }

bool SeedToCursor(const string sim,const string origin,const datetime from,const datetime until)
  {
   MqlRates rates[];
   int n=CopyRates(origin,PERIOD_M1,from,until,rates);
   if(n<=0)
     {
      Alert("No M1 history on ",origin,". Open an M1 chart, scroll left to load history, then try again.");
      return false;
     }

   CustomRatesDelete(sim,0,TimeCurrent()+86400);
   CustomTicksDelete(sim,0,LONG_MAX);
   if(CustomRatesReplace(sim,from,until,rates)<0)
     {
      Alert("CustomRatesReplace failed. Error: ",GetLastError());
      return false;
     }

   MqlTick ticks[];
   ArrayResize(ticks,n);
   double point=SymbolInfoDouble(origin,SYMBOL_POINT);
   int digits=(int)SymbolInfoInteger(origin,SYMBOL_DIGITS);
   int spread=MathMax(1,(int)SymbolInfoInteger(origin,SYMBOL_SPREAD));
   for(int i=0;i<n;i++)
     {
      ticks[i].time=rates[i].time+59;
      ticks[i].time_msc=(long)ticks[i].time*1000;
      ticks[i].bid=NormalizeDouble(rates[i].close,digits);
      ticks[i].ask=NormalizeDouble(rates[i].close+spread*point,digits);
      ticks[i].last=ticks[i].bid;
      ticks[i].flags=TICK_FLAG_BID|TICK_FLAG_ASK|TICK_FLAG_LAST;
     }
   if(CustomTicksReplace(sim,(long)from*1000,(long)until*1000,ticks)<0)
      Print("CustomTicksReplace: ",GetLastError());
   return true;
  }

void SaveSession()
  {
   int h=FileOpen("ForexReplay.session",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE) return;
   FileWrite(h,g_sim);
   FileWrite(h,g_source);
   FileWrite(h,(long)g_from);
   FileWrite(h,(long)g_to);
   FileWrite(h,(long)g_cursor);
   FileWrite(h,DoubleToString(InpBalance0,2));
   FileWrite(h,DoubleToString(InpLots0,2));
   FileWrite(h,IntegerToString(InpSL0));
   FileWrite(h,IntegerToString(InpTP0));
   FileWrite(h,IntegerToString(MathMax(1,InpSpeed0)));
   FileWrite(h,IntegerToString(InpPartials0));
   FileWrite(h,IntegerToString(InpBEAfter0));
   FileClose(h);
  }

//============================== REPLAY ==============================
int InitReplay()
  {
   double lots=InpLots0;
   int sl=InpSL0,tp=InpTP0,spd=MathMax(1,InpSpeed0);
   int partials=InpPartials0, beafter=InpBEAfter0;
   g_balance=InpBalance0;

   if(!LoadSession(lots,sl,tp,spd,partials,beafter))
     {
      g_source=StringSubstr(_Symbol,StringLen(SIM_PREF));
      g_to=TimeCurrent();
      g_from=g_to-(datetime)InpDaysBack*86400;
      g_cursor=g_to-(datetime)InpStartAgo*86400;
     }
   g_speed=MathMax(1,spd);
   g_m1_n=CopyRates(g_source,PERIOD_M1,g_from,g_to,g_m1);
   if(g_m1_n<=0)
     {
      Alert("Cannot read M1 history for ",g_source,". Error: ",GetLastError());
      return INIT_FAILED;
     }

   g_playing=false;
   g_equity=g_balance;
   g_peak=g_balance;
   g_maxdd=0;
   g_closed_pnl=0;
   EventSetMillisecondTimer(MathMax(40,InpTimerMs));
   BuildReplay(lots,sl,tp,g_speed,partials,beafter);
   BuildDash();
   RefreshDash();
   InitJournal();
   return INIT_SUCCEEDED;
  }

bool LoadSession(double &lots,int &sl,int &tp,int &spd,int &partials,int &beafter)
  {
   int h=FileOpen("ForexReplay.session",FILE_READ|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE) return false;
   FileReadString(h);
   g_source=FileReadString(h);
   g_from=(datetime)StringToInteger(FileReadString(h));
   g_to=(datetime)StringToInteger(FileReadString(h));
   g_cursor=(datetime)StringToInteger(FileReadString(h));
   g_balance=StringToDouble(FileReadString(h));
   lots=StringToDouble(FileReadString(h));
   sl=(int)StringToInteger(FileReadString(h));
   tp=(int)StringToInteger(FileReadString(h));
   spd=(int)StringToInteger(FileReadString(h));
   if(!FileIsEnding(h))
      partials=(int)StringToInteger(FileReadString(h));
   if(!FileIsEnding(h))
      beafter=(int)StringToInteger(FileReadString(h));
   FileClose(h);
   return (g_source!="" && g_from>0);
  }

void BuildReplay(const double lots,const int sl,const int tp,const int spd,
                 const int partials,const int beafter)
  {
   Dock(UI+"BAR");
   Label(UI+"L_BAL","Balance");
   Label(UI+"L_LOT","Lots");
   Label(UI+"L_SL","SL pts");
   Label(UI+"L_TP","TP pts");
   Label(UI+"L_SPD","Speed");
   Label(UI+"L_PRT","Partials");
   Label(UI+"L_BEA","BE after");
   Edit(UI+"ED_BAL",DoubleToString(g_balance,2));
   Edit(UI+"ED_LOT",DoubleToString(lots,2));
   Edit(UI+"ED_SL",IntegerToString(sl));
   Edit(UI+"ED_TP",IntegerToString(tp));
   Edit(UI+"ED_SPD",IntegerToString(MathMax(1,spd)));
   Edit(UI+"ED_PRT",IntegerToString(MathMax(0,partials)));
   Edit(UI+"ED_BEA",IntegerToString(MathMax(0,beafter)));
   Btn(UI+"SPD_M",36,"/2");
   Btn(UI+"SPD_P",36,"x2");
   Btn(UI+"PLAY",70,"Play");
   Btn(UI+"STEP",70,"Step");
   Btn(UI+"BUY",70,"Buy");
   Btn(UI+"SELL",70,"Sell");
   Btn(UI+"CLOSE",70,"Close");
   LayoutReplay();
   ChartRedraw();
  }

void LayoutReplay()
  {
   int w=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
   if(w<=0) w=1300;
   PlaceDock(w);

   const int fieldw=86;
   const int total=7*fieldw+36+4+36+8+70*5+4*4;
   int x=MathMax(12,(w-total)/2);
   PlaceField(UI+"L_BAL",UI+"ED_BAL",x,fieldw); x+=fieldw;
   PlaceField(UI+"L_LOT",UI+"ED_LOT",x,fieldw); x+=fieldw;
   PlaceField(UI+"L_SL", UI+"ED_SL", x,fieldw); x+=fieldw;
   PlaceField(UI+"L_TP", UI+"ED_TP", x,fieldw); x+=fieldw;
   PlaceField(UI+"L_PRT",UI+"ED_PRT",x,fieldw); x+=fieldw;
   PlaceField(UI+"L_BEA",UI+"ED_BEA",x,fieldw); x+=fieldw;
   PlaceField(UI+"L_SPD",UI+"ED_SPD",x,fieldw); x+=fieldw;
   PlaceBtn(UI+"SPD_M",x,36); x+=40;
   PlaceBtn(UI+"SPD_P",x,36); x+=44;
   PlaceBtn(UI+"PLAY",x,70); x+=74;
   PlaceBtn(UI+"STEP",x,70); x+=74;
   PlaceBtn(UI+"BUY",x,70); x+=74;
   PlaceBtn(UI+"SELL",x,70); x+=74;
   PlaceBtn(UI+"CLOSE",x,70);
  }

bool AdvanceOneBar()
  {
   int idx=FindBar(g_cursor);
   if(idx<0 || idx+1>=g_m1_n) return false;

   MqlRates one[1];
   one[0]=g_m1[idx+1];
   g_cursor=one[0].time;
   if(CustomRatesUpdate(_Symbol,one)<0)
     {
      Print("CustomRatesUpdate error: ",GetLastError());
      return false;
     }

   MqlTick tick[1];
   ZeroMemory(tick[0]);
   tick[0].time=one[0].time+59;
   tick[0].time_msc=(long)tick[0].time*1000;
   tick[0].bid=one[0].close;
   tick[0].ask=one[0].close+SpreadPx();
   tick[0].last=one[0].close;
   tick[0].flags=TICK_FLAG_BID|TICK_FLAG_ASK|TICK_FLAG_LAST;
   CustomTicksAdd(_Symbol,tick);

   CheckPartialsAndStops(one[0]);
   MarkToMarket();
   return true;
  }

int FindBar(const datetime t)
  {
   int lo=0,hi=g_m1_n-1,ans=-1;
   while(lo<=hi)
     {
      int mid=(lo+hi)>>1;
      if(g_m1[mid].time<=t) { ans=mid; lo=mid+1; }
      else hi=mid-1;
     }
   return ans;
  }

double SpreadPx()
  {
   return (double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)*_Point;
  }

//========================= ORDER OPEN / PARTIALS =====================
void OpenVirt(const ENUM_SIDE side)
  {
   MqlTick t;
   if(!SymbolInfoTick(_Symbol,t)) return;

   double lot_min=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double lots=MathMax(lot_min,EditNum(UI+"ED_LOT"));
   int slpts=(int)MathMax(0,EditNum(UI+"ED_SL"));
   int tppts=(int)MathMax(0,EditNum(UI+"ED_TP"));
   int partials=(int)MathMax(0,MathMin(MAX_PARTIALS,EditNum(UI+"ED_PRT")));
   int beafter=(int)MathMax(0,EditNum(UI+"ED_BEA"));
   double entry=(side==SIDE_BUY ? t.ask : t.bid);
   double sl=0,tp=0;
   if(slpts>0) sl=(side==SIDE_BUY ? entry-slpts*_Point : entry+slpts*_Point);
   if(tppts>0) tp=(side==SIDE_BUY ? entry+tppts*_Point : entry-tppts*_Point);

   if(partials>0 && tp==0)
      partials=0;
   if(beafter>partials)
      beafter=partials;

   int n=ArraySize(g_pos);
   ArrayResize(g_pos,n+1);
   g_pos[n].ticket=g_next++;
   g_pos[n].side=side;
   g_pos[n].lots=lots;
   g_pos[n].orig_lots=lots;
   g_pos[n].price=entry;
   g_pos[n].sl=sl;
   g_pos[n].orig_sl=sl;
   g_pos[n].tp=tp;
   g_pos[n].open_time=g_cursor;
   g_pos[n].close_time=0;
   g_pos[n].close_price=0;
   g_pos[n].pnl=0;
   g_pos[n].open=true;
   g_pos[n].partials=partials;
   g_pos[n].be_after=beafter;
   g_pos[n].next_partial=1;
   g_pos[n].be_done=false;
   g_pos[n].shot_on_open_done=false;

   ArrayInitialize(g_pos[n].plevels,0.0);
   if(partials>0)
     {
      double dist=(tp-entry);
      for(int k=1;k<=partials;k++)
         g_pos[n].plevels[k-1]=entry+dist*((double)k/partials);
     }

   DrawOrder(n);
   JournalOpen(n);
  }

void CheckPartialsAndStops(const MqlRates &bar)
  {
   for(int i=0;i<ArraySize(g_pos);i++)
     {
      if(!g_pos[i].open) continue;

      while(g_pos[i].open && g_pos[i].partials>0 && g_pos[i].next_partial<=g_pos[i].partials)
        {
         int k=g_pos[i].next_partial;
         double lvl=g_pos[i].plevels[k-1];
         bool hit=(g_pos[i].side==SIDE_BUY ? bar.high>=lvl : bar.low<=lvl);
         if(!hit) break;

         double closeLots=(k==g_pos[i].partials)
                          ? g_pos[i].lots
                          : MathMin(g_pos[i].lots,g_pos[i].orig_lots/g_pos[i].partials);
         PartialClose(i,lvl,closeLots,k);

         if(g_pos[i].be_after>0 && k==g_pos[i].be_after && !g_pos[i].be_done && g_pos[i].open)
            MoveSlToBreakeven(i);

         g_pos[i].next_partial++;
        }

      if(!g_pos[i].open) continue;

      if(g_pos[i].side==SIDE_BUY)
        {
         if(g_pos[i].sl>0 && bar.low<=g_pos[i].sl) { CloseOne(i,g_pos[i].sl,g_pos[i].be_done?"BE":"SL"); continue; }
        }
      else
        {
         if(g_pos[i].sl>0 && bar.high>=g_pos[i].sl) { CloseOne(i,g_pos[i].sl,g_pos[i].be_done?"BE":"SL"); continue; }
        }

      if(g_pos[i].tp>0 && g_pos[i].partials==0)
        {
         if(g_pos[i].side==SIDE_BUY && bar.high>=g_pos[i].tp) { CloseOne(i,g_pos[i].tp,"TP"); continue; }
         if(g_pos[i].side==SIDE_SELL && bar.low<=g_pos[i].tp) { CloseOne(i,g_pos[i].tp,"TP"); continue; }
        }
     }
  }

// Moves SL to entry price and REDRAWS the SL line from scratch at the
// CURRENT bar time, instead of trying to reuse/move the old ray. The old
// bug: ObjectMove() only touched anchor 1 (the far end), so anchor 0 kept
// the original SL price and the line looked tilted/frozen instead of
// jumping cleanly to breakeven.
void MoveSlToBreakeven(const int i)
  {
   g_pos[i].sl=g_pos[i].price;
   g_pos[i].be_done=true;
   RedrawSlLine(i);
  }

void PartialClose(const int i,const double price,const double closeLots,const int legIndex)
  {
   double lots=MathMin(closeLots,g_pos[i].lots);
   if(lots<=0) return;

   double pnl=MoneyPnl(g_pos[i].side,g_pos[i].price,price,lots);
   g_pos[i].lots-=lots;
   g_pos[i].pnl+=pnl;
   g_balance+=pnl;
   g_closed_pnl+=pnl;

   DrawPartial(i,price,legIndex,pnl);
   JournalPartial(i,price,legIndex,lots,pnl);

   if(g_pos[i].lots<=0.0000001)
     {
      g_pos[i].open=false;
      g_pos[i].close_price=price;
      g_pos[i].close_time=g_cursor;
      if(g_pos[i].pnl>=0) g_wins++; else g_losses++;
      DrawClose(i,"TP");
      JournalClose(i,"TP");
     }
   UpdateDd();
  }

void CloseAll(const string reason)
  {
   MqlTick t;
   if(!SymbolInfoTick(_Symbol,t)) return;
   for(int i=0;i<ArraySize(g_pos);i++)
      if(g_pos[i].open)
         CloseOne(i,g_pos[i].side==SIDE_BUY ? t.bid : t.ask,reason);
  }

void CloseOne(const int i,const double price,const string reason)
  {
   double pnl=MoneyPnl(g_pos[i].side,g_pos[i].price,price,g_pos[i].lots);
   g_pos[i].pnl+=pnl;
   g_pos[i].open=false;
   g_pos[i].close_price=price;
   g_pos[i].close_time=g_cursor;
   g_balance+=pnl;
   g_closed_pnl+=pnl;
   if(g_pos[i].pnl>=0) g_wins++; else g_losses++;
   DrawClose(i,reason);
   JournalClose(i,reason);
   UpdateDd();
  }

double MoneyPnl(const ENUM_SIDE side,const double entry,const double exit,const double lots)
  {
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   if(ts<=0) ts=_Point;
   if(tv<=0) tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE)*ts;
   return ((exit-entry)/ts)*tv*lots*(int)side;
  }

void MarkToMarket()
  {
   MqlTick t;
   if(!SymbolInfoTick(_Symbol,t)) return;
   double floating=0;
   for(int i=0;i<ArraySize(g_pos);i++)
     {
      if(!g_pos[i].open) continue;
      double px=(g_pos[i].side==SIDE_BUY ? t.bid : t.ask);
      double open_pnl=MoneyPnl(g_pos[i].side,g_pos[i].price,px,g_pos[i].lots);
      floating+=open_pnl;
     }
   g_equity=g_balance+floating;
   UpdateDd();
  }

void UpdateDd()
  {
   if(g_equity>g_peak) g_peak=g_equity;
   double dd=g_peak-g_equity;
   if(dd>g_maxdd) g_maxdd=dd;
  }

//========================== ORDER DRAWINGS ==========================
string Tag(const ulong ticket,const string suffix)
  {
   return UI+"ORD_"+IntegerToString((long)ticket)+"_"+suffix;
  }

void DrawOrder(const int i)
  {
   color col=(g_pos[i].side==SIDE_BUY ? clrDodgerBlue : clrOrangeRed);
   string a=Tag(g_pos[i].ticket,"IN");
   ObjectCreate(0,a,OBJ_ARROW,0,g_pos[i].open_time,g_pos[i].price);
   ObjectSetInteger(0,a,OBJPROP_ARROWCODE,g_pos[i].side==SIDE_BUY ? 233 : 234);
   ObjectSetInteger(0,a,OBJPROP_COLOR,col);
   ObjectSetInteger(0,a,OBJPROP_WIDTH,2);

   string label=Tag(g_pos[i].ticket,"LABEL");
   ObjectCreate(0,label,OBJ_TEXT,0,g_pos[i].open_time,g_pos[i].price);
   ObjectSetString(0,label,OBJPROP_TEXT,StringFormat(" #%I64u %s %.2f",g_pos[i].ticket,g_pos[i].side==SIDE_BUY ? "BUY" : "SELL",g_pos[i].orig_lots));
   ObjectSetInteger(0,label,OBJPROP_COLOR,col);
   ObjectSetInteger(0,label,OBJPROP_FONTSIZE,8);
   ObjectSetInteger(0,label,OBJPROP_ANCHOR,ANCHOR_LEFT_LOWER);

   if(g_pos[i].sl>0) RedrawSlLine(i);

   if(g_pos[i].partials>0)
     {
      for(int k=1;k<=g_pos[i].partials;k++)
        {
         string pl=Tag(g_pos[i].ticket,"P"+IntegerToString(k));
         double lvl=g_pos[i].plevels[k-1];
         color pcol=(k==g_pos[i].partials ? clrLimeGreen : clrYellow);
         OrderLine(pl,g_pos[i].open_time,lvl,pcol,
                   (k==g_pos[i].partials?"TP":StringFormat("P%d",k)));
        }
     }
   else if(g_pos[i].tp>0)
      OrderLine(Tag(g_pos[i].ticket,"TP"),g_pos[i].open_time,g_pos[i].tp,clrLimeGreen,"TP");
  }

void OrderLine(const string name,const datetime from,const double price,const color col,const string text)
  {
   if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
   ObjectCreate(0,name,OBJ_TREND,0,from,price,from+PeriodSeconds()*80,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,col);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DASH);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,true);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,text+" "+DoubleToString(price,_Digits));
  }

// Deletes and recreates the SL ray at the position's CURRENT sl price,
// anchored from open_time to (open_time + 80 bars). This replaces the old
// ObjectMove-based approach, which only ever updated one anchor and left
// the line visually stuck between the old and new SL price.
void RedrawSlLine(const int i)
  {
   string name=Tag(g_pos[i].ticket,"SL");
   color col=(g_pos[i].be_done ? clrDeepSkyBlue : clrTomato);
   string text=(g_pos[i].be_done ? "BE" : "SL");
   OrderLine(name,g_pos[i].open_time,g_pos[i].sl,col,text);
  }

void DrawPartial(const int i,const double price,const int legIndex,const double pnl)
  {
   color col=(pnl>=0 ? clrLimeGreen : clrTomato);
   string tag=Tag(g_pos[i].ticket,"PX"+IntegerToString(legIndex));
   ObjectCreate(0,tag,OBJ_ARROW,0,g_cursor,price);
   ObjectSetInteger(0,tag,OBJPROP_ARROWCODE,159);
   ObjectSetInteger(0,tag,OBJPROP_COLOR,col);
   ObjectSetString(0,tag,OBJPROP_TOOLTIP,StringFormat("Partial %d/%d  P/L %.2f",legIndex,g_pos[i].partials,pnl));
   ObjectDelete(0,Tag(g_pos[i].ticket,"P"+IntegerToString(legIndex)));
  }

void DrawClose(const int i,const string reason)
  {
   color col=(g_pos[i].pnl>=0 ? clrLimeGreen : clrTomato);
   string out=Tag(g_pos[i].ticket,"OUT");
   ObjectCreate(0,out,OBJ_ARROW,0,g_pos[i].close_time,g_pos[i].close_price);
   ObjectSetInteger(0,out,OBJPROP_ARROWCODE,251);
   ObjectSetInteger(0,out,OBJPROP_COLOR,col);

   string seg=Tag(g_pos[i].ticket,"SEG");
   ObjectCreate(0,seg,OBJ_TREND,0,g_pos[i].open_time,g_pos[i].price,g_pos[i].close_time,g_pos[i].close_price);
   ObjectSetInteger(0,seg,OBJPROP_COLOR,col);
   ObjectSetInteger(0,seg,OBJPROP_STYLE,STYLE_DOT);
   ObjectSetInteger(0,seg,OBJPROP_RAY_RIGHT,false);
   ObjectSetString(0,seg,OBJPROP_TOOLTIP,reason+" P/L "+DoubleToString(g_pos[i].pnl,2));

   ObjectDelete(0,Tag(g_pos[i].ticket,"SL"));
   ObjectDelete(0,Tag(g_pos[i].ticket,"TP"));
   for(int k=1;k<=g_pos[i].partials;k++)
      ObjectDelete(0,Tag(g_pos[i].ticket,"P"+IntegerToString(k)));
  }

//=========================== JOURNAL =================================
// Uses MQL5's native ChartScreenShot() (renders the real chart to PNG) —
// no user32.dll/gdi32.dll calls needed and no DLL-import permission
// prompts for the user. CSV rows go to MQL5\Files\ForexReplayJournal\.
void InitJournal()
  {
   if(!InpJournal) return;
   if(!FolderCreate(JOURNAL_DIR))
      { /* ok if it already exists */ }
   if(!FileIsExist(JOURNAL_CSV))
     {
      int h=FileOpen(JOURNAL_CSV,FILE_WRITE|FILE_CSV|FILE_ANSI,',');
      if(h!=INVALID_HANDLE)
        {
         FileWrite(h,"event","ticket","symbol","side","lots","orig_lots",
                   "entry","sl","orig_sl","tp","price","pnl","balance_after",
                   "equity_after","reason","sim_time","screenshot");
         FileClose(h);
        }
     }
  }

string JournalShot(const ulong ticket,const string tag)
  {
   if(!InpJournal) return "";
   MqlDateTime dt; TimeToStruct(g_cursor,dt);
   string file=StringFormat("%s\\%s_%I64u_%s_%04d%02d%02d_%02d%02d%02d.png",
                            JOURNAL_DIR,_Symbol,ticket,tag,
                            dt.year,dt.mon,dt.day,dt.hour,dt.min,dt.sec);
   if(ChartScreenShot(0,file,InpShotW,InpShotH))
      return file;
   Print("ChartScreenShot failed: ",GetLastError());
   return "";
  }

void JournalRow(const string event,const int i,const double price,const double pnl,const string reason,const string shot)
  {
   if(!InpJournal) return;
   int h=FileOpen(JOURNAL_CSV,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(h==INVALID_HANDLE) return;
   FileSeek(h,0,SEEK_END);
   FileWrite(h,event,
             IntegerToString((long)g_pos[i].ticket),
             _Symbol,
             g_pos[i].side==SIDE_BUY?"BUY":"SELL",
             DoubleToString(g_pos[i].lots,2),
             DoubleToString(g_pos[i].orig_lots,2),
             DoubleToString(g_pos[i].price,_Digits),
             DoubleToString(g_pos[i].sl,_Digits),
             DoubleToString(g_pos[i].orig_sl,_Digits),
             DoubleToString(g_pos[i].tp,_Digits),
             DoubleToString(price,_Digits),
             DoubleToString(pnl,2),
             DoubleToString(g_balance,2),
             DoubleToString(g_equity,2),
             reason,
             TimeToString(g_cursor,TIME_DATE|TIME_SECONDS),
             shot);
   FileClose(h);
  }

void JournalOpen(const int i)
  {
   string shot=JournalShot(g_pos[i].ticket,"OPEN");
   JournalRow("OPEN",i,g_pos[i].price,0.0,"open",shot);
  }

void JournalPartial(const int i,const double price,const int legIndex,const double lots,const double pnl)
  {
   string shot=JournalShot(g_pos[i].ticket,"P"+IntegerToString(legIndex));
   JournalRow("PARTIAL",i,price,pnl,StringFormat("leg %d/%d, %.2f lots",legIndex,g_pos[i].partials,lots),shot);
  }

void JournalClose(const int i,const string reason)
  {
   string shot=JournalShot(g_pos[i].ticket,"CLOSE_"+reason);
   JournalRow("CLOSE",i,g_pos[i].close_price,g_pos[i].pnl,reason,shot);
  }

//=========================== DASHBOARD ==============================
void BuildDash()
  {
   RectUp(UI+"DASH_BG",DASH_X,DASH_Y,DASH_W,DASH_MAXROW*DASH_LINE_H+20,C'18,22,28');
   LabelUp(UI+"DASH_TITLE","REPLAY DASHBOARD",DASH_X+10,DASH_Y+8,clrGold,10);
   for(int r=0;r<DASH_MAXROW;r++)
      LabelUp(UI+"DR_"+IntegerToString(r),"",DASH_X+10,DASH_Y+26+r*DASH_LINE_H,clrWhiteSmoke,9);
  }

void DashRow(int &row,const string text,const color col=clrWhiteSmoke)
  {
   if(row>=DASH_MAXROW) return;
   string name=UI+"DR_"+IntegerToString(row);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_COLOR,col);
   row++;
  }

void ClearDashRows(int fromRow)
  {
   for(int r=fromRow;r<DASH_MAXROW;r++)
      ObjectSetString(0,UI+"DR_"+IntegerToString(r),OBJPROP_TEXT,"");
  }

void RefreshDash()
  {
   if(!g_is_sim) return;
   int open=CountOpen();
   int closed=CountClosed();
   int total=g_wins+g_losses;
   double wr=(total>0 ? 100.0*g_wins/total : 0.0);
   double floating=g_equity-g_balance;

   int row=0;
   DashRow(row,StringFormat("Time: %s",TimeToString(g_cursor,TIME_DATE|TIME_MINUTES)));
   DashRow(row,StringFormat("State: %s     Speed: x%d",g_playing ? "PLAY" : "PAUSE",g_speed));
   DashRow(row,StringFormat("Start balance: %.2f",InpBalance0));
   DashRow(row,StringFormat("Balance: %.2f     Equity: %.2f",g_balance,g_equity));
   DashRow(row,StringFormat("Floating P/L: %.2f",floating),floating>=0?clrLimeGreen:clrTomato);
   DashRow(row,StringFormat("Closed P/L: %.2f",g_closed_pnl),g_closed_pnl>=0?clrLimeGreen:clrTomato);
   DashRow(row,StringFormat("Trades: %d open / %d closed",open,closed));
   DashRow(row,StringFormat("W/L: %d / %d   Win rate: %.1f%%",g_wins,g_losses,wr));
   DashRow(row,StringFormat("Max drawdown: %.2f",g_maxdd));
   DashRow(row,StringFormat("Journal: %s",InpJournal?"ON (Files\\"+JOURNAL_DIR+")":"OFF"));
   DashRow(row,"------------------------------------");
   DashRow(row,"OPEN TRADES",clrGold);

   int shown=0;
   for(int i=ArraySize(g_pos)-1;i>=0 && row<DASH_MAXROW-2;i--)
     {
      if(!g_pos[i].open) continue;
      MqlTick t; SymbolInfoTick(_Symbol,t);
      double px=(g_pos[i].side==SIDE_BUY ? t.bid : t.ask);
      double live_pnl=g_pos[i].pnl+MoneyPnl(g_pos[i].side,g_pos[i].price,px,g_pos[i].lots);

      DashRow(row,StringFormat("#%I64u %s %.2f/%.2f  entry %s",
              g_pos[i].ticket,
              g_pos[i].side==SIDE_BUY ? "BUY " : "SELL",
              g_pos[i].lots,g_pos[i].orig_lots,
              DoubleToString(g_pos[i].price,_Digits)));
      string pinfo="";
      if(g_pos[i].partials>0)
         pinfo=StringFormat("  leg %d/%d%s",
               MathMin(g_pos[i].next_partial,g_pos[i].partials),g_pos[i].partials,
               g_pos[i].be_done ? " BE" : "");
      DashRow(row,StringFormat("  P/L %s%.2f   SL %s%s",
              live_pnl>=0 ? "+" : "",
              live_pnl,
              g_pos[i].sl>0 ? DoubleToString(g_pos[i].sl,_Digits) : "-",
              pinfo),
              live_pnl>=0?clrLimeGreen:clrTomato);
      shown++;
      if(shown>=6) break;
     }
   if(shown==0)
      DashRow(row,"No open trades");

   ClearDashRows(row);
   Comment("");
  }

int CountOpen()
  {
   int n=0;
   for(int i=0;i<ArraySize(g_pos);i++) if(g_pos[i].open) n++;
   return n;
  }

int CountClosed()
  {
   int n=0;
   for(int i=0;i<ArraySize(g_pos);i++) if(!g_pos[i].open) n++;
   return n;
  }

//============================= UI ==================================
void Dock(const string name)
  {
   if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
   ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_LOWER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,0);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,BAR_H);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,1400);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,BAR_H);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,C'22,26,34');
   ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,C'70,76,88');
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,0);
  }

void PlaceDock(const int width)
  {
   ObjectSetInteger(0,UI+"BAR",OBJPROP_XDISTANCE,0);
   ObjectSetInteger(0,UI+"BAR",OBJPROP_YDISTANCE,BAR_H);
   ObjectSetInteger(0,UI+"BAR",OBJPROP_XSIZE,width);
   ObjectSetInteger(0,UI+"BAR",OBJPROP_YSIZE,BAR_H);
  }

void Btn(const string name,const int width,const string text)
  {
   if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
   ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_LOWER);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,BTN_Y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,width);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,BTN_H);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,C'45,49,58');
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,10);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
  }

void PlaceBtn(const string name,const int x,const int width)
  {
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_LOWER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,BTN_Y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,width);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,BTN_H);
  }

void Edit(const string name,const string text)
  {
   if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
   ObjectCreate(0,name,OBJ_EDIT,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_LOWER);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,BTN_Y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,80);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,BTN_H);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,C'28,32,40');
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,C'70,76,88');
   ObjectSetInteger(0,name,OBJPROP_ALIGN,ALIGN_CENTER);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,10);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
  }

void Label(const string name,const string text)
  {
   if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
   ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_LOWER);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,LBL_Y);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrSilver);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,10);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
  }

void PlaceField(const string label,const string edit,const int x,const int w)
  {
   ObjectSetInteger(0,label,OBJPROP_CORNER,CORNER_LEFT_LOWER);
   ObjectSetInteger(0,label,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,label,OBJPROP_YDISTANCE,LBL_Y);
   ObjectSetInteger(0,edit,OBJPROP_CORNER,CORNER_LEFT_LOWER);
   ObjectSetInteger(0,edit,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,edit,OBJPROP_YDISTANCE,BTN_Y);
   ObjectSetInteger(0,edit,OBJPROP_XSIZE,w-6);
  }

void RectUp(const string name,const int x,const int y,const int width,const int height,const color bg)
  {
   if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
   ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,width);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,height);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,C'70,76,88');
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
  }

void LabelUp(const string name,const string text,const int x,const int y,const color col,const int size)
  {
   if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
   ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_COLOR,col);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,size);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
  }

void SetBtn(const string name,const string text)
  {
   ObjectSetString(0,name,OBJPROP_TEXT,text);
  }

void SetEdit(const string name,const string text)
  {
   ObjectSetString(0,name,OBJPROP_TEXT,text);
  }

void ReadEdits()
  {
   if(g_is_sim) g_speed=(int)MathMax(1,EditNum(UI+"ED_SPD"));
  }

double EditNum(const string name)
  {
   return StringToDouble(ObjectGetString(0,name,OBJPROP_TEXT));
  }
//+------------------------------------------------------------------+