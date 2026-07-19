#ifndef ADVTP_POSITION_VISUALS_MQH
#define ADVTP_POSITION_VISUALS_MQH
#define VISUAL_PREFIX "Riy_"
string GetPositionVisualPrefix(const ulong ticket)
{
   return(PANEL_PREFIX + "POS_" + (string)ticket + "_");
}

string GetPositionSideText(const long position_type)
{
   return(position_type == POSITION_TYPE_BUY ? "BUY" : "SELL");
}

void DeletePositionVisuals(const ulong ticket)
{
   string prefix = GetPositionVisualPrefix(ticket);

   for(int i=ObjectsTotal(0,-1,-1)-1; i>=0; i--)
   {
      string name = ObjectName(0,i,-1,-1);

      if(StringFind(name,prefix) == 0)
         ObjectDelete(0,name);
   }
}

void CreateOrUpdatePositionLine(const string name,
                                const double price,
                                const color line_color,
                                const ENUM_LINE_STYLE line_style,
                                const int line_width)
{
   if(price <= 0.0)
      return;

   if(ObjectFind(0,name) < 0)
   {
      ResetLastError();

      if(!ObjectCreate(0,name,OBJ_HLINE,0,0,price))
      {
         LogError("VISUAL", "Cannot create " + name + ". Error=" + IntegerToString(GetLastError()));
         return;
      }
   }

   ObjectSetDouble(0,name,OBJPROP_PRICE,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,line_color);
   ObjectSetInteger(0,name,OBJPROP_STYLE,line_style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,line_width);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,500);
}

void CreateOrUpdatePositionText(const string name,
                                const double price,
                                const string text,
                                const color text_color,
                                const int time_shift_bars)
{
   if(price <= 0.0)
      return;

   datetime anchor_time = iTime(_Symbol,_Period,0);

   if(anchor_time <= 0)
      anchor_time = TimeCurrent();

   int seconds_per_bar = PeriodSeconds(_Period);

   if(seconds_per_bar <= 0)
      seconds_per_bar = 60;

   anchor_time += (datetime)(seconds_per_bar * time_shift_bars);

   if(ObjectFind(0,name) < 0)
   {
      ResetLastError();

      if(!ObjectCreate(0,name,OBJ_TEXT,0,anchor_time,price))
      {
         LogError("VISUAL", "Cannot create text " + name + ". Error=" + IntegerToString(GetLastError()));
         return;
      }
   }
   else
   {
      ObjectMove(0,name,0,anchor_time,price);
   }

   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetString(0,name,OBJPROP_FONT,"Arial");
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
   ObjectSetInteger(0,name,OBJPROP_COLOR,text_color);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,501);
}

void DrawManagedPositionVisuals(const int index)
{
   if(index < 0 || index >= ArraySize(g_TradeStates))
      return;

   TradeState state = g_TradeStates[index];

   if(!PositionSelectByTicket(state.ticket))
   {
      DeletePositionVisuals(state.ticket);
      return;
   }

   state.current_volume = PositionGetDouble(POSITION_VOLUME);
   state.entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
   state.stop_loss = PositionGetDouble(POSITION_SL);
   state.take_profit = PositionGetDouble(POSITION_TP);

   string prefix = GetPositionVisualPrefix(state.ticket);
   string side = GetPositionSideText(state.position_type);
   string source_tag = (state.is_adopted || state.is_external ? " EXT" : "");
   string ticket_text = "#" + (string)state.ticket + " " + side + source_tag + " " +
                        DoubleToString(state.current_volume,2);

   CreateOrUpdatePositionLine(prefix+"ENTRY",state.entry_price,clrDodgerBlue,STYLE_SOLID,2);
   CreateOrUpdatePositionText(prefix+"ENTRY_TXT",state.entry_price,"ENTRY " + ticket_text,clrDodgerBlue,2);

   if(state.stop_loss > 0.0)
   {
      CreateOrUpdatePositionLine(prefix+"SL",state.stop_loss,clrTomato,STYLE_DASH,2);
      CreateOrUpdatePositionText(prefix+"SL_TXT",state.stop_loss,"SL  " + DoubleToString(state.stop_loss,_Digits),clrTomato,3);
   }

   if(state.take_profit > 0.0)
   {
      CreateOrUpdatePositionLine(prefix+"TP_FINAL",state.take_profit,clrLimeGreen,STYLE_SOLID,2);
      CreateOrUpdatePositionText(prefix+"TP_FINAL_TXT",state.take_profit,"FINAL TP  " + DoubleToString(state.take_profit,_Digits),clrLimeGreen,4);
   }
   
   for(int p=0; p<state.partial_count; p++)
   {
      if(p >= ArraySize(state.partial_prices))
         continue;
   
      double partial_price = state.partial_prices[p];
   
      if(partial_price <= 0.0)
         continue;
   
      color partial_color = (state.partial_done[p] ? clrDimGray : clrYellow);
      string partial_status = (state.partial_done[p] ? " DONE" : "");
      string partial_text = "TP" + IntegerToString(p+1) +
                            partial_status +
                            "  " + DoubleToString(partial_price,_Digits);
   
      CreateOrUpdatePositionLine(prefix+"P"+IntegerToString(p+1),
                                 partial_price,
                                 partial_color,
                                 STYLE_DOT,
                                 1);
   
      CreateOrUpdatePositionText(prefix+"P"+IntegerToString(p+1)+"_TXT",
                                 partial_price,
                                 partial_text,
                                 partial_color,
                                 5+p);
   }

   ChartRedraw(0);
}

void RefreshAllManagedPositionVisuals()
{
   for(int i=0; i<ArraySize(g_TradeStates); i++)
      DrawManagedPositionVisuals(i);
}

void DeleteAllManagedPositionVisuals()
{
   for(int i=ObjectsTotal(0,-1,-1)-1; i>=0; i--)
   {
      string name = ObjectName(0,i,-1,-1);

      if(StringFind(name,PANEL_PREFIX+"POS_") == 0)
         ObjectDelete(0,name);
   }

   ChartRedraw(0);
}

#endif