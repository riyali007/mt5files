#ifndef TM_STATE_MQH
#define TM_STATE_MQH
#define TM_STATE_FILE "TM3State.bin"
#define TM_STATE_VER  1

struct TMPlan
  {
   ulong  posId; long groupId; bool isMain;
   double origTP, origVolume, entryCommission;
   int    partialCount; double mainPct, rollingPct;
   double bePoints, beOffset;
   int    partialsTaken; bool beDone, redEver; int runnerExt;
   datetime lastFill;
   datetime created;
  };
struct TMGroup { long groupId; int ddFills; bool armed; };

TMPlan  g_plans[];
TMGroup g_groups[];
bool    g_stateDirty=false;

int TMFindPlan(const ulong posId)
  { for(int i=ArraySize(g_plans)-1;i>=0;i--) if(g_plans[i].posId==posId) return i; return -1; }
int TMFindGroup(const long gid)
  { for(int i=ArraySize(g_groups)-1;i>=0;i--) if(g_groups[i].groupId==gid) return i; return -1; }

// Save-once: an existing plan is never overwritten (GR3)
int TMAddPlan(const TMPlan &p)
  {
   int i=TMFindPlan(p.posId);
   if(i>=0) return i;
   i=ArraySize(g_plans); ArrayResize(g_plans,i+1,64);
   g_plans[i]=p; g_stateDirty=true; return i;
  }
int TMGroupGet(const long gid)
  {
   int i=TMFindGroup(gid); if(i>=0) return i;
   i=ArraySize(g_groups); ArrayResize(g_groups,i+1,16);
   g_groups[i].groupId=gid; g_groups[i].ddFills=0; g_groups[i].armed=false;
   g_stateDirty=true; return i;
  }
void TMRemovePlan(const ulong posId)
  {
   int i=TMFindPlan(posId); if(i<0) return;
   int n=ArraySize(g_plans); g_plans[i]=g_plans[n-1]; ArrayResize(g_plans,n-1); g_stateDirty=true;
  }

bool TMSaveState(const bool force=false)
  {
   if(!g_stateDirty && !force) return true;
   string tmp=TM_STATE_FILE+".tmp";
   int h=FileOpen(tmp,FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(h==INVALID_HANDLE){ Print("State save failed: ",GetLastError()); return false; }
   FileWriteInteger(h,TM_STATE_VER);
   FileWriteInteger(h,ArraySize(g_plans));
   FileWriteInteger(h,ArraySize(g_groups));
   if(ArraySize(g_plans)>0)  FileWriteArray(h,g_plans);
   if(ArraySize(g_groups)>0) FileWriteArray(h,g_groups);
   FileClose(h);
   if(!FileMove(tmp,FILE_COMMON,TM_STATE_FILE,FILE_COMMON|FILE_REWRITE))
     { Print("State move failed: ",GetLastError()); return false; }
   g_stateDirty=false; return true;
  }

bool TMLoadState()
  {
   if(!FileIsExist(TM_STATE_FILE,FILE_COMMON)) return true;
   int h=FileOpen(TM_STATE_FILE,FILE_READ|FILE_BIN|FILE_COMMON);
   if(h==INVALID_HANDLE) return false;
   int ver=FileReadInteger(h), np=FileReadInteger(h), ng=FileReadInteger(h);
   if(ver!=TM_STATE_VER || np<0 || ng<0){ FileClose(h); Print("State version mismatch"); return false; }
   ArrayResize(g_plans,np); ArrayResize(g_groups,ng);
   if(np>0) FileReadArray(h,g_plans,0,np);
   if(ng>0) FileReadArray(h,g_groups,0,ng);
   FileClose(h); g_stateDirty=false; return true;
  }
#endif