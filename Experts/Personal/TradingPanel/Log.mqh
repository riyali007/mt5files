#ifndef TM_LOG_MQH
#define TM_LOG_MQH
#define TM_BUILD "TM3 1.1.0"

string   g_logKeys[];
datetime g_logTimes[];

void TMLog(const string tag,const ulong ticket,const string reason,const double net)
  { PrintFormat("[%s] ticket=%I64u reason=%s net=%.2f",tag,ticket,reason,net); }

// Silent rate limiter (retry loops)
bool TMAllow(const string key,const int secs)
  {
   datetime now=TimeCurrent();
   int n=ArraySize(g_logKeys);
   for(int i=0;i<n;i++)
      if(g_logKeys[i]==key)
        { if(now-g_logTimes[i]<secs) return false; g_logTimes[i]=now; return true; }
   ArrayResize(g_logKeys,n+1); ArrayResize(g_logTimes,n+1);
   g_logKeys[n]=key; g_logTimes[n]=now; return true;
  }

// Log at most once per 'secs' for a given key
bool TMLogThrottled(const string key,const int secs,const string msg)
  {
   if(!TMAllow(key,secs)) return false;
   Print(msg);
   return true;
  }
#endif