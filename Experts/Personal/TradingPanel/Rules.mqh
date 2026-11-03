#ifndef TM_RULES_MQH
#define TM_RULES_MQH
#include "State.mqh"

double TMFloorToStep(const double v,const double step)
  { return NormalizeDouble(MathFloor(v/step+1e-9)*step,8); }

// F4: level k (1-based) in points from entry
double TMPartialLevelPts(const double entry,const double origTP,const double point,const int N,const int k)
  { return MathAbs(origTP-entry)/point*k/(N+1); }

// F4: volume to close, or 0 = skip (caller logs)
double TMPartialVolume(const double curVol,const bool first,const double mainPct,const double rollPct,
                       const double step,const double minVol)
  {
   double v=TMFloorToStep(curVol*(first?mainPct:rollPct)/100.0,step);
   if(v<minVol || v>=curVol) return 0.0;
   return v;
  }

bool TMPartialDue(const TMPlan &p,const double entry,const double ptsInFavor,const double point)
  {
   if(p.origTP<=0 || p.partialsTaken>=p.partialCount) return false;
   return ptsInFavor>=TMPartialLevelPts(entry,p.origTP,point,p.partialCount,p.partialsTaken+1);
  }

// F5: new SL or 0 = no action; alreadyBetter = SL already tighter (mark BE done)
double TMBETarget(const bool isBuy,const double open,const double curSL,const TMPlan &p,
                  const double ptsInFavor,const double point,const int digits,bool &alreadyBetter)
  {
   alreadyBetter=false;
   if(p.beDone || p.bePoints<=0 || ptsInFavor<p.bePoints) return 0.0;
   double t=NormalizeDouble(isBuy? open+p.beOffset*point : open-p.beOffset*point,digits);
   if(curSL>0 && (isBuy? curSL>=t : curSL<=t)){ alreadyBetter=true; return 0.0; }
   return t;
  }

// F10: tighten-only
double TMTrailTarget(const bool isBuy,const double price,const double curSL,
                     const double ptsInFavor,const double start,const double step,
                     const double point,const int digits)
  {
   if(ptsInFavor<start) return 0.0;
   double t=NormalizeDouble(isBuy? price-step*point : price+step*point,digits);
   if(curSL>0 && (isBuy? t<=curSL : t>=curSL)) return 0.0;
   return t;
  }

// F11 (parked)
double TMRunnerTarget(const bool isBuy,const double price,const double tp,const int ext,const int maxExt,
                      const double runnerPts,const double point,const int digits)
  {
   if(tp<=0 || ext>=maxExt) return 0.0;
   double dist=isBuy? tp-price : price-tp;
   if(dist>runnerPts*point) return 0.0;
   return NormalizeDouble(isBuy? tp+runnerPts*point : tp-runnerPts*point,digits);
  }

// F7 (parked)
bool TMWorstShouldClose(const TMPlan &p,const bool greenNow,const int secsSinceFill)
  { return secsSinceFill>=3 && p.redEver && greenNow; }

// F6: auto spacing in points, rounded to whole points and tick size
double TMAutoSpacingPts(const double slPts,const int count,const double point,const double tickSize)
  {
   double pts=MathRound(slPts/(count+1));
   double tickPts=tickSize/point;
   return MathMax(tickPts,MathRound(pts/tickPts)*tickPts);
  }
#endif