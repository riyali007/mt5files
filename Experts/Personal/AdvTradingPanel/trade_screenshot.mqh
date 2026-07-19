#ifndef ADVTP_TRADE_SCREENSHOT_MQH
#define ADVTP_TRADE_SCREENSHOT_MQH

string GetTradeOpenScreenshotFileName(const ulong ticket)
{
   string compact_symbol = _Symbol;
   StringReplace(compact_symbol,".","");
   StringReplace(compact_symbol,"/","");
   StringReplace(compact_symbol," ","");

   string file_name = "ATP_" +
                      compact_symbol + "_" +
                      (string)ticket + "_" +
                      TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES);

   StringReplace(file_name,".","");
   StringReplace(file_name,":","");

   return(file_name + ".png");
}

bool IsPanelObjectName(const string object_name)
{
   return(StringFind(object_name,PANEL_PREFIX) == 0);
}

int MovePanelObjectsByX(const int delta_x)
{
   int moved = 0;
   int total = ObjectsTotal(0,0,-1);

   for(int i=0; i<total; i++)
   {
      string name = ObjectName(0,i,0,-1);

      if(!IsPanelObjectName(name))
         continue;

      int x = (int)ObjectGetInteger(0,name,OBJPROP_XDISTANCE);
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x + delta_x);
      moved++;
   }

   return(moved);
}

string CaptureTradeOpenScreenshot(const ulong ticket)
{
   if(!InpCaptureScreenshotOnTradeOpen)
      return("");

   if(g_PanelMovedForScreenshot)
   {
      MovePanelObjectsByX(-g_PanelScreenshotShiftX);
      g_PanelScreenshotShiftX = 0;
      g_PanelMovedForScreenshot = false;
   }

   int width = MathMax(400,InpTradeOpenScreenshotWidth);
   int height = MathMax(300,InpTradeOpenScreenshotHeight);
   string file_name = GetTradeOpenScreenshotFileName(ticket);

   bool move_panel = !InpIncludePanelInTradeOpenScreenshot;

   if(move_panel)
   {
      g_PanelScreenshotShiftX = -2000;
      MovePanelObjectsByX(g_PanelScreenshotShiftX);
      g_PanelMovedForScreenshot = true;
      ChartRedraw(0);
      Sleep(150);
   }
   else
   {
      ChartRedraw(0);
      Sleep(80);
   }

   ResetLastError();
   bool captured = ChartScreenShot(0,file_name,width,height,ALIGN_RIGHT);
   int capture_error = GetLastError();

   if(g_PanelMovedForScreenshot)
   {
      MovePanelObjectsByX(-g_PanelScreenshotShiftX);
      g_PanelScreenshotShiftX = 0;
      g_PanelMovedForScreenshot = false;
      ChartRedraw(0);
   }

   if(!captured)
   {
      LogError("SCREENSHOT",
               "Failed open screenshot #" + (string)ticket +
               " error=" + IntegerToString(capture_error));
      return("");
   }

   return(file_name);
}

#endif