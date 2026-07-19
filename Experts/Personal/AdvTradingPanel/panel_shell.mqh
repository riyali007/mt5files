#ifndef ADVTP_PANEL_SHELL_MQH
#define ADVTP_PANEL_SHELL_MQH

void SetPanelObjectCommon(const string name)
{
   ObjectSetInteger(0,name,OBJPROP_CORNER,InpPanelCorner);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,1000);
}

void CreateRect(const string name,const int x,const int y,const int w,const int h,const color bg,const color border)
{
   if(ObjectFind(0,name) < 0)
      ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);

   SetPanelObjectCommon(name);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,name,OBJPROP_COLOR,border);
   ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
}

void CreateLabel(const string name,const int x,const int y,const string text,const color clr,const int size=8)
{
   if(ObjectFind(0,name) < 0)
      ObjectCreate(0,name,OBJ_LABEL,0,0,0);

   SetPanelObjectCommon(name);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,size);
   ObjectSetString(0,name,OBJPROP_FONT,"Arial");
   ObjectSetString(0,name,OBJPROP_TEXT,text);
}

void CreateButton(const string name,const int x,const int y,const int w,const int h,const string text,const color bg,const color clr=clrWhite)
{
   if(ObjectFind(0,name) < 0)
      ObjectCreate(0,name,OBJ_BUTTON,0,0,0);

   SetPanelObjectCommon(name);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
   ObjectSetString(0,name,OBJPROP_FONT,"Arial");
   ObjectSetString(0,name,OBJPROP_TEXT,text);
}

void CreateEdit(const string name,const int x,const int y,const int w,const int h,const string text)
{
   if(ObjectFind(0,name) < 0)
      ObjectCreate(0,name,OBJ_EDIT,0,0,0);

   SetPanelObjectCommon(name);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,clrDimGray);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
   ObjectSetString(0,name,OBJPROP_FONT,"Arial");
   ObjectSetString(0,name,OBJPROP_TEXT,text);
}

void DeleteDeveloperTestControls()
{
   string dev_objects[] =
   {
      OBJ_DEV_TOGGLE,
      OBJ_DEV_TP1,
      OBJ_DEV_NEXT,
      OBJ_DEV_BE,
      OBJ_DEV_STATUS,
      PANEL_PREFIX+"LblDev"
   };

   for(int i=0; i<ArraySize(dev_objects); i++)
      ObjectDelete(0,dev_objects[i]);
}
void SetTextIfChanged(const string name,const string text)
{
   if(ObjectGetString(0,name,OBJPROP_TEXT) != text)
      ObjectSetString(0,name,OBJPROP_TEXT,text);
}

void InitializePanelShell()
{
   int x = InpPanelX;
   int y = InpPanelY;

   int panel_height = (InpShowDeveloperControls ? 640 : 530);
   CreateRect(OBJ_BG,x,y,310,panel_height,clrBlack,clrDimGray);
   CreateLabel(OBJ_TITLE,x+8,y+7,APP_NAME+" v"+APP_VERSION,clrWhite,9);
   CreateLabel(OBJ_STATUS,x+8,y+28,"HEDGING | Engine: IDLE",clrGold,8);

   CreateButton(OBJ_MKT,x+4,y+48,150,24,"MARKET",clrDodgerBlue);
   CreateButton(OBJ_LIM,x+156,y+48,150,24,"LIMIT",clrDimGray);

   CreateLabel(PANEL_PREFIX+"LblPrice",x+5,y+78,"Price:",clrSilver,8);
   CreateEdit(OBJ_PRICE,x+53,y+75,250,21,"0.00000");

   CreateButton(OBJ_BUY,x+4,y+101,150,25,"BUY",clrGreen);
   CreateButton(OBJ_SELL,x+156,y+101,150,25,"SELL",clrTomato);

   CreateLabel(PANEL_PREFIX+"LblLot",x+5,y+135,"Lot:",clrSilver,8);
   CreateEdit(OBJ_LOT,x+53,y+132,250,21,DoubleToString(InpDefaultLot,2));

   CreateLabel(PANEL_PREFIX+"LblSL",x+5,y+161,"SL pts:",clrSilver,8);
   CreateEdit(OBJ_SLPTS,x+53,y+158,70,21,IntegerToString(InpDefaultSLPoints));
   CreateLabel(PANEL_PREFIX+"LblSLP",x+132,y+161,"Prc:",clrSilver,8);
   CreateEdit(OBJ_SLPRICE,x+162,y+158,141,21,"0.00000");

   CreateLabel(PANEL_PREFIX+"LblTP",x+5,y+187,"TP pts:",clrSilver,8);
   CreateEdit(OBJ_TPPTS,x+53,y+184,70,21,IntegerToString(InpDefaultTPPoints));
   CreateLabel(PANEL_PREFIX+"LblTPP",x+132,y+187,"Prc:",clrSilver,8);
   CreateEdit(OBJ_TPPRICE,x+162,y+184,141,21,"0.00000");

   CreateLabel(PANEL_PREFIX+"LblParts",x+5,y+213,"Partials #:",clrSilver,8);
   CreateEdit(OBJ_PARTS,x+112,y+210,191,21,IntegerToString(InpDefaultPartialCount));

   CreateLabel(OBJ_PARTLINE,x+5,y+239,"TP levels:",clrSilver,7);
   CreateLabel(PANEL_PREFIX+"LblRisk",x+5,y+263,"Risk:",clrSilver,8);
   CreateLabel(OBJ_RISK,x+45,y+263,"$0.00",clrTomato,8);
   CreateLabel(PANEL_PREFIX+"LblReward",x+156,y+263,"Profit:",clrSilver,8);
   CreateLabel(OBJ_REWARD,x+202,y+263,"$0.00",clrLimeGreen,8);

   CreateButton(OBJ_VISUALIZE,x+4,y+286,299,25,"VISUALIZE",clrDimGray);
   CreateLabel(OBJ_MESSAGE,x+100,y+315,"Ready",clrSilver,7);
   
   CreateLabel(PANEL_PREFIX+"LblSel",x+5,y+319,"Trade Selector:",clrSilver,8);
   CreateButton(OBJ_SEL_PREV,x+5,y+337,34,22,"<",clrDimGray);
   CreateLabel(OBJ_SELECTED,x+45,y+340,"Selected: none",clrGold,8);
   CreateButton(OBJ_SEL_NEXT,x+269,y+337,34,22,">",clrDimGray);
   
   CreateLabel(PANEL_PREFIX+"LblManPart",x+5,y+366,"Manual %:",clrSilver,8);
   CreateEdit(OBJ_MANPART,x+69,y+363,70,21,DoubleToString(InpManualPartialDefaultPercent,1));
   CreateButton(OBJ_PARTIAL_SEL,x+145,y+363,158,21,"PARTIAL % (SEL)",clrOlive);
   
   CreateButton(OBJ_BE_SEL,x+5,y+389,298,21,"BE (SEL)",clrTeal);
   if(InpShowDeveloperControls)
   {
      CreateLabel(PANEL_PREFIX+"LblDev",x+5,y+419,"Developer Test Mode (real actions):",clrTomato,8);
      CreateButton(OBJ_DEV_TOGGLE,x+5,y+438,298,22,"DEV MODE: OFF",clrMaroon);
   
      CreateButton(OBJ_DEV_TP1,x+5,y+466,94,22,"SIM TP1",clrOlive);
      CreateButton(OBJ_DEV_NEXT,x+104,y+466,112,22,"SIM NEXT TP",clrOlive);
      CreateButton(OBJ_DEV_BE,x+221,y+466,82,22,"TEST BE",clrTeal);
   
      CreateLabel(OBJ_DEV_STATUS,x+5,y+495,"Disabled in Inputs",clrSilver,7);
   }
   else
   {
      DeleteDeveloperTestControls();
   }
   
   int action_y = (InpShowDeveloperControls ? 540 : 435);

   CreateButton(OBJ_CLOSE_SEL,x+5,action_y,298,23,"CLOSE (SEL)",clrSaddleBrown);
   CreateButton(OBJ_CLOSE_ALL,x+5,action_y+28,298,24,"CLOSE ALL - THIS SYMBOL",clrRed);
   
   CreateLabel(OBJ_EXT_STATUS,x+5,action_y+55,"Unmanaged external: none",clrSilver,7);
   CreateButton(OBJ_EXT_PREV,x+5,action_y+75,40,24,"Prev",clrDimGray);
   CreateButton(OBJ_ADOPT_SEL,x+50,action_y+75,210,24,"ADOPT SELECTED EXTERNAL",clrDarkOrange);
   CreateButton(OBJ_EXT_NEXT,x+265,action_y+75,40,24,"Next",clrDimGray);
   ChartRedraw(0);
}

void UpdateModeButtons()
{
   ObjectSetInteger(0,OBJ_MKT,OBJPROP_BGCOLOR,g_OrderMode == ATP_ORDER_MARKET ? clrDodgerBlue : clrDimGray);
   ObjectSetInteger(0,OBJ_LIM,OBJPROP_BGCOLOR,g_OrderMode == ATP_ORDER_LIMIT ? clrDodgerBlue : clrDimGray);
}

void UpdatePanelShell(const bool force)
{
   if(!force && !g_PanelDirty)
      return;

   RefreshCurrentPlan();

   string status = "HEDGING | Engine: ";
   status += g_HasManagedTrades ? "ACTIVE" : "IDLE";

   SetTextIfChanged(OBJ_STATUS,status);
   ObjectSetInteger(0,OBJ_STATUS,OBJPROP_COLOR,g_HasManagedTrades ? clrLimeGreen : clrGold);

   if(g_OrderMode == ATP_ORDER_MARKET && !g_IsEditingPrice)
   {
      double live_price = (g_PlanDirection == ORDER_TYPE_BUY ? g_Ask : g_Bid);
      SetTextIfChanged(OBJ_PRICE,DoubleToString(live_price,_Digits));
   }

   SetTextIfChanged(OBJ_LOT,DoubleToString(g_PlanLot,2));
   SetTextIfChanged(OBJ_SLPTS,IntegerToString(g_PlanSLPoints));
   SetTextIfChanged(OBJ_TPPTS,IntegerToString(g_PlanTPPoints));
   SetTextIfChanged(OBJ_PARTS,IntegerToString(g_PlanPartialCount));

   if(g_CurrentPlan.valid)
   {
      SetTextIfChanged(OBJ_SLPRICE,DoubleToString(g_CurrentPlan.sl,_Digits));
      SetTextIfChanged(OBJ_TPPRICE,DoubleToString(g_CurrentPlan.tp,_Digits));
      SetTextIfChanged(OBJ_PARTLINE,GetPartialSummary(g_CurrentPlan));
      SetTextIfChanged(OBJ_RISK,"$" + DoubleToString(g_CurrentPlan.risk_money,2));
      SetTextIfChanged(OBJ_REWARD,"$" + DoubleToString(g_CurrentPlan.reward_money,2));
   }
   else
   {
      SetTextIfChanged(OBJ_PARTLINE,"TP levels: invalid plan");
      SetTextIfChanged(OBJ_RISK,"$0.00");
      SetTextIfChanged(OBJ_REWARD,"$0.00");
   }

   UpdateModeButtons();
   EnsureSelectedTicket();
   
   if(g_ManualPartialPercent <= 0.0)
      g_ManualPartialPercent = InpManualPartialDefaultPercent;
   
   SetTextIfChanged(OBJ_SELECTED,GetSelectedTicketText());
   SetTextIfChanged(OBJ_MANPART,DoubleToString(g_ManualPartialPercent,1));
   if(InpShowDeveloperControls)
   {
      string dev_text = "Disabled in Inputs";
      color dev_status_color = clrSilver;
   
      if(InpEnableDeveloperTestMode)
      {
         dev_text = (g_DeveloperTestMode ? "ON: Real partial/BE actions enabled" : "OFF: Click DEV MODE to arm");
         dev_status_color = (g_DeveloperTestMode ? clrTomato : clrGold);
      }
   
      SetTextIfChanged(OBJ_DEV_STATUS,dev_text);
      ObjectSetInteger(0,OBJ_DEV_STATUS,OBJPROP_COLOR,dev_status_color);
   
      SetTextIfChanged(OBJ_DEV_TOGGLE,g_DeveloperTestMode ? "DEV MODE: ON" : "DEV MODE: OFF");
      ObjectSetInteger(0,OBJ_DEV_TOGGLE,OBJPROP_BGCOLOR,g_DeveloperTestMode ? clrFireBrick : clrMaroon);
   
      color dev_button_color = (InpEnableDeveloperTestMode && g_DeveloperTestMode ? clrOlive : clrDimGray);
   
      ObjectSetInteger(0,OBJ_DEV_TP1,OBJPROP_BGCOLOR,dev_button_color);
      ObjectSetInteger(0,OBJ_DEV_NEXT,OBJPROP_BGCOLOR,dev_button_color);
      ObjectSetInteger(0,OBJ_DEV_BE,OBJPROP_BGCOLOR,
                       (InpEnableDeveloperTestMode && g_DeveloperTestMode ? clrTeal : clrDimGray));
   }
   else
   {
      if(g_DeveloperTestMode)
         g_DeveloperTestMode = false;
   
      DeleteDeveloperTestControls();
   }
   g_PanelDirty = false;
   
   ChartRedraw(0);
}

void SetPanelMessage(const string message,const color clr=clrSilver)
{
   SetTextIfChanged(OBJ_MESSAGE,message);
   ObjectSetInteger(0,OBJ_MESSAGE,OBJPROP_COLOR,clr);
}

void DeletePlanObjects()
{
   for(int i=ObjectsTotal(0,-1,-1)-1; i>=0; i--)
   {
      string name = ObjectName(0,i,-1,-1);

      if(StringFind(name,PLAN_PREFIX) == 0)
         ObjectDelete(0,name);
   }
}

void DrawPlanLine(const string name,const double price,const color clr,const string label)
{
   ObjectCreate(0,name,OBJ_HLINE,0,0,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DASH);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetString(0,name,OBJPROP_TEXT,label);
}

void DrawPlanPreviewForSide(const ENUM_ORDER_TYPE direction,const string side_tag)
{
   string reason;
   TradePlan plan;

   if(!BuildTradePlan(direction,plan,reason))
   {
      LogDebug("PREVIEW", side_tag + " blocked: " + reason);
      return;
   }

   // Distinct object names per side so BUY and SELL can coexist
   string pfx = PLAN_PREFIX + side_tag + "_";

   color entry_clr = (direction == ORDER_TYPE_BUY ? clrDodgerBlue : clrMediumPurple);
   color sl_clr    = clrTomato;
   color tp_clr    = (direction == ORDER_TYPE_BUY ? clrLimeGreen : clrSpringGreen);
   color part_clr  = (direction == ORDER_TYPE_BUY ? clrGold : clrOrange);

   DrawPlanLine(pfx+"Entry",plan.entry,entry_clr,side_tag+" ENTRY");
   DrawPlanLine(pfx+"SL",plan.sl,sl_clr,side_tag+" SL");
   DrawPlanLine(pfx+"TP",plan.tp,tp_clr,side_tag+" FINAL TP");

   for(int i=0; i<plan.partial_count; i++)
      DrawPlanLine(pfx+"P"+IntegerToString(i+1),
                   plan.partial_prices[i],
                   part_clr,
                   side_tag+" TP"+IntegerToString(i+1));
}

void TogglePlanPreview()
{
   if(g_PreviewVisible)
   {
      DeletePlanObjects();
      g_PreviewVisible = false;
      SetPanelMessage("Preview hidden",clrSilver);
      ChartRedraw(0);
      return;
   }

   // Always draw BOTH buy and sell plan levels at the same time
   DeletePlanObjects();

   string buy_reason = "";
   string sell_reason = "";
   TradePlan buy_plan, sell_plan;
   bool buy_ok  = BuildTradePlan(ORDER_TYPE_BUY,buy_plan,buy_reason);
   bool sell_ok = BuildTradePlan(ORDER_TYPE_SELL,sell_plan,sell_reason);

   if(!buy_ok && !sell_ok)
   {
      SetPanelMessage("Preview blocked: " + buy_reason,clrTomato);
      return;
   }

   if(buy_ok)
      DrawPlanPreviewForSide(ORDER_TYPE_BUY,"BUY");

   if(sell_ok)
      DrawPlanPreviewForSide(ORDER_TYPE_SELL,"SELL");

   g_PreviewVisible = true;

   if(buy_ok && sell_ok)
      SetPanelMessage("Preview: BUY + SELL levels",clrLimeGreen);
   else if(buy_ok)
      SetPanelMessage("Preview: BUY only (" + sell_reason + ")",clrGold);
   else
      SetPanelMessage("Preview: SELL only (" + buy_reason + ")",clrGold);

   ChartRedraw(0);
}

void ReadPlanInputs()
{
   g_PlanLot = StringToDouble(ObjectGetString(0,OBJ_LOT,OBJPROP_TEXT));
   g_PlanSLPoints = (int)StringToInteger(ObjectGetString(0,OBJ_SLPTS,OBJPROP_TEXT));
   g_PlanTPPoints = (int)StringToInteger(ObjectGetString(0,OBJ_TPPTS,OBJPROP_TEXT));
   g_PlanPartialCount = (int)StringToInteger(ObjectGetString(0,OBJ_PARTS,OBJPROP_TEXT));

   if(g_OrderMode == ATP_ORDER_LIMIT)
      g_PlanPrice = StringToDouble(ObjectGetString(0,OBJ_PRICE,OBJPROP_TEXT));

   g_PlanPartialCount = MathMax(1,MathMin(5,g_PlanPartialCount));
   g_IsEditingPrice = false;
   g_PanelDirty = true;
}

void ReadManualPartialInput()
{
   g_ManualPartialPercent = StringToDouble(ObjectGetString(0,OBJ_MANPART,OBJPROP_TEXT));
   g_PanelDirty = true;
}

void ExecutePlanFromPanel(const ENUM_ORDER_TYPE direction)
{
   ReadPlanInputs();

   string reason;
   TradePlan plan;

   if(!BuildTradePlan(direction,plan,reason))
   {
      SetPanelMessage("Order blocked: " + reason,clrTomato);
      return;
   }

   g_PlanDirection = direction;

   if(ExecuteTradePlan(plan))
      SetPanelMessage("Order accepted by server",clrLimeGreen);
   else
      SetPanelMessage("Order rejected - see Experts log",clrTomato);
}

void HandlePanelShellEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      if(sparam == OBJ_MANPART)
      {
         ReadManualPartialInput();
         return;
      }
      
      if(sparam == OBJ_PRICE || sparam == OBJ_LOT || sparam == OBJ_SLPTS ||
         sparam == OBJ_TPPTS || sparam == OBJ_PARTS)
      {
         ReadPlanInputs();
         return;
      }
   }

   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   if(sparam == OBJ_MKT)
   {
      g_OrderMode = ATP_ORDER_MARKET;
      g_IsEditingPrice = false;
      g_PanelDirty = true;
      SetPanelMessage("Market mode",clrLightSteelBlue);
      return;
   }

   if(sparam == OBJ_LIM)
   {
      g_OrderMode = ATP_ORDER_LIMIT;

      if(g_PlanPrice <= 0.0)
         g_PlanPrice = (g_PlanDirection == ORDER_TYPE_BUY ? g_Ask - 100 * _Point : g_Bid + 100 * _Point);

      g_PanelDirty = true;
      SetPanelMessage("Limit mode: enter price",clrLightSteelBlue);
      return;
   }

   if(sparam == OBJ_BUY)
   {
      ExecutePlanFromPanel(ORDER_TYPE_BUY);
      return;
   }

   if(sparam == OBJ_SELL)
   {
      ExecutePlanFromPanel(ORDER_TYPE_SELL);
      return;
   }

   if(sparam == OBJ_VISUALIZE)
   {
      ReadPlanInputs();
      TogglePlanPreview();
      return;
   }
   if(sparam == OBJ_SEL_PREV)
   {
      SelectRelativeTicket(-1);
      return;
   }
   
   if(sparam == OBJ_SEL_NEXT)
   {
      SelectRelativeTicket(1);
      return;
   }
   
   if(sparam == OBJ_PARTIAL_SEL)
   {
      ReadManualPartialInput();
      ExecuteManualPartialSelected();
      return;
   }
   
   if(sparam == OBJ_BE_SEL)
   {
      ExecuteManualBESelected();
      return;
   }
   if(InpShowDeveloperControls && sparam == OBJ_DEV_TOGGLE)
   {
      ToggleDeveloperTestMode();
      return;
   }
   
   if(InpShowDeveloperControls && sparam == OBJ_DEV_TP1)
   {
      ForcePartialForSelectedTicket(0);
      return;
   }
   
   if(InpShowDeveloperControls && sparam == OBJ_DEV_NEXT)
   {
      ForcePartialForSelectedTicket(-1);
      return;
   }
   
   if(InpShowDeveloperControls && sparam == OBJ_DEV_BE)
   {
      ForceBEForSelectedTicket();
      return;
   }
   if(sparam == OBJ_CLOSE_SEL)
   {
      CloseSelectedPosition();
      return;
   }
   
   if(sparam == OBJ_CLOSE_ALL)
   {
      CloseAllManagedCurrentSymbol();
      return;
   }
   if(sparam == OBJ_EXT_PREV)
   {
      SelectRelativeExternal(-1);
      return;
   }
   
   if(sparam == OBJ_EXT_NEXT)
   {
      SelectRelativeExternal(1);
      return;
   }
   
   if(sparam == OBJ_ADOPT_SEL)
   {
      AdoptSelectedExternal();
      return;
   }
}


void DestroyPanelShell()
{
   DeletePlanObjects();

   string objects[] =
   {
      OBJ_BG,OBJ_TITLE,OBJ_STATUS,OBJ_MKT,OBJ_LIM,OBJ_PRICE,OBJ_BUY,OBJ_SELL,
      OBJ_LOT,OBJ_SLPTS,OBJ_SLPRICE,OBJ_TPPTS,OBJ_TPPRICE,OBJ_PARTS,
      OBJ_PARTLINE,OBJ_RISK,OBJ_REWARD,OBJ_VISUALIZE,OBJ_MESSAGE,
      PANEL_PREFIX+"LblPrice",PANEL_PREFIX+"LblLot",PANEL_PREFIX+"LblSL",
      PANEL_PREFIX+"LblSLP",PANEL_PREFIX+"LblTP",PANEL_PREFIX+"LblTPP",
      PANEL_PREFIX+"LblParts",PANEL_PREFIX+"LblRisk",PANEL_PREFIX+"LblReward",
      OBJ_SEL_PREV,OBJ_SEL_NEXT,OBJ_SELECTED,OBJ_MANPART,OBJ_PARTIAL_SEL,OBJ_BE_SEL,
      PANEL_PREFIX+"LblSel",PANEL_PREFIX+"LblManPart",
      OBJ_DEV_TOGGLE,OBJ_DEV_TP1,OBJ_DEV_NEXT,OBJ_DEV_BE,OBJ_DEV_STATUS,PANEL_PREFIX+"LblDev",
      OBJ_CLOSE_SEL,OBJ_CLOSE_ALL,OBJ_ADOPT_SEL,OBJ_EXT_STATUS,OBJ_EXT_PREV,OBJ_EXT_NEXT,
      
   };

   for(int i=0; i<ArraySize(objects); i++)
      ObjectDelete(0,objects[i]);

   ChartRedraw(0);
}

#endif