#ifndef ADVTP_N8N_WEBHOOK_MQH
#define ADVTP_N8N_WEBHOOK_MQH

string EscapeJsonString(const string value)
{
   string result = value;

   StringReplace(result,"\\","\\\\");
   StringReplace(result,"\"","\\\"");
   StringReplace(result,"\r"," ");
   StringReplace(result,"\n"," ");

   return(result);
}

bool IsN8nEventEnabled(const string event_name)
{
   if(event_name == "OPEN")
      return(InpN8nSendOpenEvents);

   if(event_name == "PARTIAL")
      return(InpN8nSendPartialEvents);

   if(event_name == "BREAKEVEN")
      return(InpN8nSendBreakevenEvents);

   if(event_name == "TRAIL_STOP")
      return(InpN8nSendTrailingStopEvents);

   if(event_name == "CLOSE" || event_name == "CLOSE_REQUEST")
   return(InpN8nSendCloseEvents);

   if(event_name == "ADOPT")
      return(InpN8nSendAdoptionEvents);
   
   if(event_name == "SLTP_UPDATE")
      return(InpN8nSendOpenEvents);

   return(false);
}

bool IsN8nWebhookAvailable()
{
   if(!InpEnableN8nWebhook)
      return(false);

   if(MQLInfoInteger(MQL_TESTER))
      return(false);

   if(StringLen(InpN8nWebhookUrl) <= 8)
      return(false);

   return(true);
}

void LogN8nFailureThrottled(const string message)
{
   datetime now = TimeCurrent();

   if(now == g_N8nLastFailureLogTime)
      return;

   if(g_N8nLastFailureLogTime > 0 && (now - g_N8nLastFailureLogTime) < 60)
      return;

   g_N8nLastFailureLogTime = now;
   LogError("N8N",message);
}

string BuildN8nJournalPayload(const string event_name,
                               const ulong ticket,
                               const string symbol,
                               const string side,
                               const double volume,
                               const double price,
                               const double sl,
                               const double tp,
                               const double profit,
                               const string note,
                               const string source,
                               const string screenshot_file = "")
{
   string json = "{";

   json += "\"timestamp\":\"" + EscapeJsonString(TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS)) + "\",";
   json += "\"event\":\"" + EscapeJsonString(event_name) + "\",";
   json += "\"ticket\":\"" + (string)ticket + "\",";
   json += "\"symbol\":\"" + EscapeJsonString(symbol) + "\",";
   json += "\"side\":\"" + EscapeJsonString(side) + "\",";
   json += "\"volume\":" + DoubleToString(volume,2) + ",";
   json += "\"price\":" + DoubleToString(price,_Digits) + ",";
   json += "\"sl\":" + DoubleToString(sl,_Digits) + ",";
   json += "\"tp\":" + DoubleToString(tp,_Digits) + ",";
   json += "\"profit\":" + DoubleToString(profit,2) + ",";
   json += "\"note\":\"" + EscapeJsonString(note) + "\",";
   json += "\"magic\":\"" + (string)InpMagicNumber + "\",";
   json += "\"source\":\"" + EscapeJsonString(source) + "\",";
   json += "\"ea_name\":\"" + EscapeJsonString(APP_SHORT_NAME) + "\",";
   json += "\"account_login\":\"" + (string)AccountInfoInteger(ACCOUNT_LOGIN) + "\",";
   json += "\"account_server\":\"" + EscapeJsonString(AccountInfoString(ACCOUNT_SERVER)) + "\",";
   json += "\"chart_symbol\":\"" + EscapeJsonString(_Symbol) + "\",";
   json += "\"screenshot_file\":\"" + EscapeJsonString(screenshot_file) + "\"";

   json += "}";

   return(json);
}

string BuildN8nMultipartBoundary()
{
   return("----ATPBoundary" + IntegerToString((int)TimeLocal()) + IntegerToString(GetTickCount()));
}

bool ReadScreenshotFileToArray(const string file_name,uchar &data[])
{
   ArrayResize(data,0);

   if(StringLen(file_name) <= 0)
      return(false);

   // ChartScreenShot saves into terminal MQL5\Files (not FILE_COMMON)
   int handle = FileOpen(file_name,FILE_READ|FILE_BIN|FILE_SHARE_READ);
   if(handle == INVALID_HANDLE)
   {
      LogError("N8N","Cannot open screenshot '" + file_name + "' err=" + IntegerToString(GetLastError()));
      return(false);
   }

   ulong size = FileSize(handle);
   if(size == 0 || size > 15000000)
   {
      FileClose(handle);
      LogError("N8N","Screenshot size invalid: " + (string)size);
      return(false);
   }

   ArrayResize(data,(int)size);
   uint read = FileReadArray(handle,data,0,(int)size);
   FileClose(handle);

   if(read != size)
   {
      ArrayResize(data,0);
      LogError("N8N","Screenshot read incomplete");
      return(false);
   }

   return(true);
}

void CharArrayAppendString(char &body[],const string text)
{
   uchar tmp[];
   StringToCharArray(text,tmp,0,WHOLE_ARRAY,CP_UTF8);

   int add = ArraySize(tmp);
   if(add <= 0)
      return;

   // StringToCharArray includes trailing '\0' — drop it
   add--;
   if(add <= 0)
      return;

   int old = ArraySize(body);
   ArrayResize(body,old + add);
   for(int i=0; i<add; i++)
      body[old + i] = (char)tmp[i];
}

void CharArrayAppendBytes(char &body[],const uchar &data[])
{
   int add = ArraySize(data);
   if(add <= 0)
      return;

   int old = ArraySize(body);
   ArrayResize(body,old + add);
   for(int i=0; i<add; i++)
      body[old + i] = (char)data[i];
}

bool SendN8nOpenEventWithScreenshot(const ulong ticket,
                                     const string symbol,
                                     const string side,
                                     const double volume,
                                     const double price,
                                     const double sl,
                                     const double tp,
                                     const double profit,
                                     const string note,
                                     const string source,
                                     const string screenshot_file)
{
   if(!IsN8nWebhookAvailable())
      return(false);

   if(!IsN8nEventEnabled("OPEN"))
      return(false);

   uchar file_data[];
   bool has_file = ReadScreenshotFileToArray(screenshot_file,file_data);

   // Fallback: no file -> normal JSON open event
   if(!has_file)
   {
      return(SendN8nJournalEvent("OPEN",ticket,symbol,side,volume,price,sl,tp,profit,note,source,screenshot_file));
   }

   string boundary = BuildN8nMultipartBoundary();
   char body[];
   ArrayResize(body,0);

   // text fields
   string fields[16][2];
   fields[0][0] = "timestamp"; fields[0][1] = TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS);
   fields[1][0] = "event"; fields[1][1] = "OPEN";
   fields[2][0] = "ticket"; fields[2][1] = (string)ticket;
   fields[3][0] = "symbol"; fields[3][1] = symbol;
   fields[4][0] = "side"; fields[4][1] = side;
   fields[5][0] = "volume"; fields[5][1] = DoubleToString(volume,2);
   fields[6][0] = "price"; fields[6][1] = DoubleToString(price,_Digits);
   fields[7][0] = "sl"; fields[7][1] = DoubleToString(sl,_Digits);
   fields[8][0] = "tp"; fields[8][1] = DoubleToString(tp,_Digits);
   fields[9][0] = "profit"; fields[9][1] = DoubleToString(profit,2);
   fields[10][0] = "note"; fields[10][1] = note;
   fields[11][0] = "magic"; fields[11][1] = (string)InpMagicNumber;
   fields[12][0] = "source"; fields[12][1] = source;
   fields[13][0] = "ea_name"; fields[13][1] = APP_SHORT_NAME;
   fields[14][0] = "account_login"; fields[14][1] = (string)AccountInfoInteger(ACCOUNT_LOGIN);
   fields[15][0] = "screenshot_file"; fields[15][1] = screenshot_file;

   for(int i=0; i<16; i++)
   {
      CharArrayAppendString(body,"--" + boundary + "\r\n");
      CharArrayAppendString(body,"Content-Disposition: form-data; name=\"" + fields[i][0] + "\"\r\n\r\n");
      CharArrayAppendString(body,fields[i][1] + "\r\n");
   }

   // file field (name must match n8n binary property expectation)
   CharArrayAppendString(body,"--" + boundary + "\r\n");
   CharArrayAppendString(body,"Content-Disposition: form-data; name=\"screenshot\"; filename=\"" + screenshot_file + "\"\r\n");
   CharArrayAppendString(body,"Content-Type: image/png\r\n\r\n");
   CharArrayAppendBytes(body,file_data);
   CharArrayAppendString(body,"\r\n");
   CharArrayAppendString(body,"--" + boundary + "--\r\n");

   char response_body[];
   string response_headers;
   string headers = "Content-Type: multipart/form-data; boundary=" + boundary + "\r\n";

   ResetLastError();
   int http_code = WebRequest("POST",
                              InpN8nWebhookUrl,
                              headers,
                              InpN8nWebhookTimeoutMs,
                              body,
                              response_body,
                              response_headers);

   int terminal_error = GetLastError();

   if(http_code < 200 || http_code >= 300)
   {
      LogN8nFailureThrottled(
         "Multipart OPEN failed HTTP=" + IntegerToString(http_code) +
         " err=" + IntegerToString(terminal_error) +
         " ticket=#" + (string)ticket
      );
      return(false);
   }

   if(InpShowDeveloperControls)
      LogInfo("N8N","OPEN+screenshot sent HTTP=" + IntegerToString(http_code) + " ticket=#" + (string)ticket);

   return(true);
}

bool SendN8nJournalEvent(const string event_name,
                          const ulong ticket,
                          const string symbol,
                          const string side,
                          const double volume,
                          const double price,
                          const double sl,
                          const double tp,
                          const double profit,
                          const string note,
                          const string source,
                          const string screenshot_file = "")
{
   if(!IsN8nWebhookAvailable())
      return(false);

   if(!IsN8nEventEnabled(event_name))
      return(false);
  // Only OPEN uploads the image file
   if(event_name == "OPEN" && StringLen(screenshot_file) > 0)
   {
      return(SendN8nOpenEventWithScreenshot(ticket,symbol,side,volume,price,sl,tp,profit,note,source,screenshot_file));
   }

   string payload = BuildN8nJournalPayload(event_name,
                                        ticket,
                                        symbol,
                                        side,
                                        volume,
                                        price,
                                        sl,
                                        tp,
                                        profit,
                                        note,
                                        source,
                                        screenshot_file);

   char request_body[];
   char response_body[];
   string response_headers;

   StringToCharArray(payload,request_body,0,WHOLE_ARRAY,CP_UTF8);

   if(ArraySize(request_body) > 0)
      ArrayResize(request_body,ArraySize(request_body)-1);

   string headers = "Content-Type: application/json\r\n";

   ResetLastError();

   int http_code = WebRequest("POST",
                              InpN8nWebhookUrl,
                              headers,
                              InpN8nWebhookTimeoutMs,
                              request_body,
                              response_body,
                              response_headers);

   int terminal_error = GetLastError();

   if(http_code < 200 || http_code >= 300)
   {
      LogN8nFailureThrottled(
         "Webhook failed. HTTP=" + IntegerToString(http_code) +
         " terminal_error=" + IntegerToString(terminal_error) +
         " event=" + event_name +
         " ticket=#" + (string)ticket
      );

      return(false);
   }

   LogDebug("N8N",
            "Webhook sent. HTTP=" + IntegerToString(http_code) +
            " event=" + event_name +
            " ticket=#" + (string)ticket);

   return(true);
}

bool InitializeN8nWebhook()
{
   g_N8nWebhookReady = false;

   if(!InpEnableN8nWebhook)
   {
      LogInfo("N8N","Webhook disabled");
      return(true);
   }

   if(MQLInfoInteger(MQL_TESTER))
   {
      LogInfo("N8N","Webhook disabled in Strategy Tester");
      return(true);
   }

   if(StringLen(InpN8nWebhookUrl) <= 8)
   {
      LogError("N8N","Webhook enabled but URL is empty");
      return(false);
   }

   g_N8nWebhookReady = true;

   LogInfo("N8N","Webhook enabled: " + InpN8nWebhookUrl);
   return(true);
}

#endif