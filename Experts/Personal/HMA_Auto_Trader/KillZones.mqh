//+------------------------------------------------------------------+
//| KillZones.mqh  -  ICT kill zone time filter                      |
//| Put next to the EA (MQL5/Experts) and #include "KillZones.mqh"   |
//+------------------------------------------------------------------+
#ifndef KILLZONES_MQH
#define KILLZONES_MQH

enum ENUM_KZ_TZ
{
   KZ_NEWYORK,   // New York time (ICT standard, US DST handled automatically)
   KZ_SERVER     // Broker/server time exactly as typed
};

input group "ICT Kill Zones (entry filter)"
input bool       InpUseKZ       = true;          // Use kill zone filter
input ENUM_KZ_TZ InpKZTime      = KZ_NEWYORK;    // Zone times below are in
input int        InpServerUTC   = 2;             // Server (broker) UTC offset, standard time
input bool       InpServerEUDST = false;         // Server shifts +1h during EU summer time
input bool       InpKZApplyDD   = false;         // Also filter DD (averaging) entries
input bool       InpKZLog       = true;          // Print converted zone times at start

input bool   InpKZ1On = true;  input string InpKZ1Name = "Asia";      input string InpKZ1Start = "20:00"; input string InpKZ1End = "00:00";
input bool   InpKZ2On = true;  input string InpKZ2Name = "London";    input string InpKZ2Start = "02:00"; input string InpKZ2End = "05:00";
input bool   InpKZ3On = true;  input string InpKZ3Name = "NY AM";     input string InpKZ3Start = "09:30"; input string InpKZ3End = "11:00";
input bool   InpKZ4On = true;  input string InpKZ4Name = "NY Lunch";  input string InpKZ4Start = "12:00"; input string InpKZ4End = "13:00";
input bool   InpKZ5On = true;  input string InpKZ5Name = "NY PM";     input string InpKZ5Start = "13:30"; input string InpKZ5End = "16:00";

bool   g_kzOn[5];
string g_kzName[5];
int    g_kzS[5], g_kzE[5];     // minutes of day

int KZ_ParseHM(const string s)
{
   string p[];
   if(StringSplit(s, ':', p) != 2) return -1;
   int h = (int)StringToInteger(p[0]), m = (int)StringToInteger(p[1]);
   if(h < 0 || h > 24 || m < 0 || m > 59) return -1;
   return (h % 24) * 60 + m;
}

datetime KZ_LastSunday(const int year, const int mon, const int hourUTC)
{
   MqlDateTime d;
   d.year = (mon == 12) ? year + 1 : year;
   d.mon  = (mon == 12) ? 1 : mon + 1;
   d.day = 1; d.hour = 0; d.min = 0; d.sec = 0;
   datetime t = StructToTime(d) - 86400;
   TimeToStruct(t, d);
   t -= (datetime)(d.day_of_week * 86400);
   return t + hourUTC * 3600;
}

datetime KZ_NthSunday(const int year, const int mon, const int n, const int hourUTC)
{
   MqlDateTime d;
   d.year = year; d.mon = mon; d.day = 1; d.hour = 0; d.min = 0; d.sec = 0;
   datetime t = StructToTime(d);
   TimeToStruct(t, d);
   int first = (7 - d.day_of_week) % 7;            // days from the 1st to the first Sunday
   return t + (first + (n - 1) * 7) * 86400 + hourUTC * 3600;
}

bool KZ_USDST(const datetime utc)
{
   MqlDateTime d; TimeToStruct(utc, d);
   // starts 2nd Sunday of March 02:00 EST (07:00 UTC), ends 1st Sunday of November 02:00 EDT (06:00 UTC)
   return (utc >= KZ_NthSunday(d.year, 3, 2, 7) && utc < KZ_NthSunday(d.year, 11, 1, 6));
}

bool KZ_EUDST(const datetime utc)
{
   MqlDateTime d; TimeToStruct(utc, d);
   // last Sunday of March 01:00 UTC -> last Sunday of October 01:00 UTC
   return (utc >= KZ_LastSunday(d.year, 3, 1) && utc < KZ_LastSunday(d.year, 10, 1));
}

datetime KZ_ServerToUTC(const datetime st)
{
   datetime utc = st - InpServerUTC * 3600;
   if(InpServerEUDST && KZ_EUDST(utc)) utc -= 3600;
   return utc;
}

int KZ_MinuteOfDay(const datetime serverTime)
{
   datetime t = serverTime;
   if(InpKZTime == KZ_NEWYORK)
   {
      datetime utc = KZ_ServerToUTC(serverTime);
      t = utc - 5 * 3600 + (KZ_USDST(utc) ? 3600 : 0);
   }
   MqlDateTime d; TimeToStruct(t, d);
   return d.hour * 60 + d.min;
}

bool KZ_Active(const datetime serverTime, string &name)
{
   int m = KZ_MinuteOfDay(serverTime);
   for(int k = 0; k < 5; k++)
   {
      if(!g_kzOn[k] || g_kzS[k] < 0 || g_kzE[k] < 0) continue;
      bool in = (g_kzS[k] == g_kzE[k]) ? true
              : (g_kzS[k] < g_kzE[k]) ? (m >= g_kzS[k] && m < g_kzE[k])
                                      : (m >= g_kzS[k] || m < g_kzE[k]);   // crosses midnight
      if(in) { name = g_kzName[k]; return true; }
   }
   return false;
}

bool KZ_Allow()
{
   if(!InpUseKZ) return true;
   string nm;
   return KZ_Active(TimeCurrent(), nm);
}

string KZ_Hm(int minutes)
{
   minutes = ((minutes % 1440) + 1440) % 1440;
   return StringFormat("%02d:%02d", minutes / 60, minutes % 60);
}

void KZ_Init()
{
   bool   on[5]   = {InpKZ1On, InpKZ2On, InpKZ3On, InpKZ4On, InpKZ5On};
   string nm[5]   = {InpKZ1Name, InpKZ2Name, InpKZ3Name, InpKZ4Name, InpKZ5Name};
   string st[5]   = {InpKZ1Start, InpKZ2Start, InpKZ3Start, InpKZ4Start, InpKZ5Start};
   string en[5]   = {InpKZ1End, InpKZ2End, InpKZ3End, InpKZ4End, InpKZ5End};
   for(int k = 0; k < 5; k++)
   {
      g_kzOn[k] = on[k]; g_kzName[k] = nm[k];
      g_kzS[k] = KZ_ParseHM(st[k]); g_kzE[k] = KZ_ParseHM(en[k]);
      if(on[k] && (g_kzS[k] < 0 || g_kzE[k] < 0)) Print("[KZ] invalid time for zone ", nm[k], " (use HH:MM)");
   }
   if(!InpUseKZ || !InpKZLog) return;

   int shiftMin = 0;
   if(InpKZTime == KZ_NEWYORK)
   {
      datetime now = TimeCurrent();
      datetime utc = KZ_ServerToUTC(now);
      int nyOff  = -5 * 60 + (KZ_USDST(utc) ? 60 : 0);
      int srvOff = (int)((now - utc) / 60);
      shiftMin = srvOff - nyOff;
      PrintFormat("[KZ] New York time -> server time, shift %+d h (US DST %s)", shiftMin / 60, KZ_USDST(utc) ? "ON" : "OFF");
   }
   else Print("[KZ] zone times are used as server time");
   for(int k = 0; k < 5; k++)
      if(g_kzOn[k] && g_kzS[k] >= 0 && g_kzE[k] >= 0)
         PrintFormat("[KZ] %-9s %s-%s  =>  server %s-%s", g_kzName[k], KZ_Hm(g_kzS[k]), KZ_Hm(g_kzE[k]),
                     KZ_Hm(g_kzS[k] + shiftMin), KZ_Hm(g_kzE[k] + shiftMin));
}

#endif
