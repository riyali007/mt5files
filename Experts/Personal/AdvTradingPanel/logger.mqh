#ifndef ADVTP_LOGGER_MQH
#define ADVTP_LOGGER_MQH

void InitializeLogger()
{
   Print(APP_NAME, " v", APP_VERSION, " logger initialized");
}

void LogInfo(const string category,const string message)
{
   if(!InpShowDeveloperControls)
      return;
   Print("[ATP][INFO][", category, "] ", message);
}

void LogDebug(const string scope,const string message)
{
   if(!InpShowDeveloperControls)
      return;
   if(InpEnableDebugLog)
      Print("[ATP][DEBUG][", scope, "] ", message);
}

void LogError(const string scope,const string message)
{
   if(!InpShowDeveloperControls)
      return;
   Print("[ATP][ERROR][", scope, "] ", message);
}

#endif