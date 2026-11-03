#ifndef TM_CONFIG_MQH
#define TM_CONFIG_MQH

datetime g_initTime=0;
datetime g_lastFillTime=0;      // server time of the latest fill of any managed entry
int SecondsSince(const datetime t){ return (int)(TimeCurrent()-t); }   // GR7 and post-fill waits

enum ENUM_EXIT_COST { EXIT_AUTO=0, EXIT_ZERO=1, EXIT_MANUAL=2 };

// Runtime settings snapshot. Rules and Closer read this, never inputs or panel.
struct TMConfig
  {
   long   magic;
   bool   disableAutomation;
   ENUM_EXIT_COST exitMode;
   double exitCostManual;
   int    maxOpenTrades;
   bool   inverse;
   double inverseOffset;
   double mainPartialPct, rollingPartialPct;
   int    defaultPartials;
   double bePoints, beOffset;
   bool   trailOn;
   double trailStart, trailStep;
   bool   runnerOn;
   double runnerPts;
   int    runnerMaxExt;
   bool   handlerOn;
   double handlerPts;
   bool   worstSLtoBE, exemptMain;
   bool   ddOn;
   int    ddCount;
   bool   ddAutoSpacing;
   double ddSpacing;
   bool   ddSameSL;
   double maxGroupRiskPct;
   bool   survOn;
   int    survNthFill;
   double survMinProfit;
   bool   survAllowRed, survCancelPending;
   int    fillLockoutSec;       // no automatic close / SL / TP change this long after any fill
  };

TMConfig g_cfg;
#endif