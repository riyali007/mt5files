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