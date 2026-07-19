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
   // Panel objects use PANEL_PREFIX (example: "ATP_UI_")
   return(StringFind(object_name,PANEL_PREFIX) == 0);
}

int HidePanelObjectsForScreenshot(long &saved_timeframes[])
{
   int total = ObjectsTotal(0,0,-1);
   ArrayResize(saved_timeframes,0);

   int hidden_count = 0;

   for(int i=total-1; i>=0; i--)
   {
      string name = ObjectName(0,i,0,-1);

      if(!IsPanelObjectName(name))
         continue;

      long current_tf = ObjectGetInteger(0,name,OBJPROP_TIMEFRAMES);

      int n = ArraySize(saved_timeframes);
      ArrayResize(saved_timeframes,n+1);
      saved_timeframes[n] = current_tf;

      // Hide on all periods
      ObjectSetInteger(0,name,OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
      hidden_count++;
   }

   return(hidden_count);
}

void RestorePanelObjectsAfterScreenshot(const long &saved_timeframes[])
{
   int total = ObjectsTotal(0,0,-1);
   int restore_index = 0;

   // Restore in the same reverse scan order used when hiding
   for(int i=total-1; i>=0; i--)
   {
      string name = ObjectName(0,i,0,-1);

      if(!IsPanelObjectName(name))
         continue;

      if(restore_index >= ArraySize(saved_timeframes))
         break;

      ObjectSetInteger(0,name,OBJPROP_TIMEFRAMES,saved_timeframes[restore_index]);
      restore_index++;
   }

   // Fallback: if count mismatched, force all panel objects visible again
   if(restore_index != ArraySize(saved_timeframes))
   {
      for(int j=ObjectsTotal(0,0,-1)-1; j>=0; j--)
      {
         string name = ObjectName(0,j,0,-1);

         if(!IsPanelObjectName(name))
            continue;

         ObjectSetInteger(0,name,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
      }
   }
}

string CaptureTradeOpenScreenshot(const ulong ticket)
{
   if(!InpCaptureScreenshotOnTradeOpen)
      return("");

   int width = MathMax(400,InpTradeOpenScreenshotWidth);
   int height = MathMax(300,InpTradeOpenScreenshotHeight);
   string file_name = GetTradeOpenScreenshotFileName(ticket);

   long saved_timeframes[];
   ArrayResize(saved_timeframes,0);

   bool hide_panel = !InpIncludePanelInTradeOpenScreenshot;
   int hidden_count = 0;

   if(hide_panel)
      hidden_count = HidePanelObjectsForScreenshot(saved_timeframes);

   // Force chart redraw without panel before capture
   ChartRedraw(0);
   Sleep(120);

   bool captured = ChartScreenShot(0,
                                   file_name,
                                   width,
                                   height,
                                   ALIGN_RIGHT);

   int capture_error = GetLastError();

   if(hide_panel)
   {
      RestorePanelObjectsAfterScreenshot(saved_timeframes);
      ChartRedraw(0);
   }

   if(!captured)
   {
      LogError("SCREENSHOT",
               "Failed to capture open screenshot for #" + (string)ticket +
               ". Error=" + IntegerToString(capture_error));
      return("");
   }

   LogInfo("SCREENSHOT",
           "Open screenshot saved for #" + (string)ticket +
           ": " + file_name +
           (hide_panel ? (" [panel hidden objects=" + IntegerToString(hidden_count) + "]")
                       : " [panel included]"));

   return(file_name);
}

#endif