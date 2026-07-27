#ifndef ADVTP_PANEL_PERSIST_MQH
#define ADVTP_PANEL_PERSIST_MQH

string PanelPersistPrefix()
{
   return("ATP_PNL_" + IntegerToString((int)ChartID()) + "_" + _Symbol + "_" + (string)InpMagicNumber + "_");
}

void ClearPersistedPanelInputs()
{
   string p = PanelPersistPrefix();
   string keys[] = {"lot","sl","tp","parts","mode","price","manpct","dir","valid"};

   for(int i=0; i<ArraySize(keys); i++)
      GlobalVariableDel(p + keys[i]);
}

void SavePanelInputsForChartChange()
{
   if(!InpPersistPanelInputsOnChartChange)
      return;

   if(ObjectFind(0,OBJ_LOT) >= 0)
      g_PlanLot = StringToDouble(ObjectGetString(0,OBJ_LOT,OBJPROP_TEXT));
   if(ObjectFind(0,OBJ_SLPTS) >= 0)
      g_PlanSLPoints = (int)StringToInteger(ObjectGetString(0,OBJ_SLPTS,OBJPROP_TEXT));
   if(ObjectFind(0,OBJ_TPPTS) >= 0)
      g_PlanTPPoints = (int)StringToInteger(ObjectGetString(0,OBJ_TPPTS,OBJPROP_TEXT));
   if(ObjectFind(0,OBJ_PARTS) >= 0)
      g_PlanPartialCount = (int)StringToInteger(ObjectGetString(0,OBJ_PARTS,OBJPROP_TEXT));
   if(ObjectFind(0,OBJ_MANPART) >= 0)
      g_ManualPartialPercent = StringToDouble(ObjectGetString(0,OBJ_MANPART,OBJPROP_TEXT));
   if(ObjectFind(0,OBJ_PRICE) >= 0)
      g_PlanPrice = StringToDouble(ObjectGetString(0,OBJ_PRICE,OBJPROP_TEXT));

   int max_parts = MathMax(1, InpMaxPartialCount);
   g_PlanPartialCount = MathMax(1, MathMin(max_parts, g_PlanPartialCount));

   string p = PanelPersistPrefix();
   GlobalVariableSet(p + "valid", 1.0);
   GlobalVariableSet(p + "lot", g_PlanLot);
   GlobalVariableSet(p + "sl", (double)g_PlanSLPoints);
   GlobalVariableSet(p + "tp", (double)g_PlanTPPoints);
   GlobalVariableSet(p + "parts", (double)g_PlanPartialCount);
   GlobalVariableSet(p + "mode", (double)g_OrderMode);
   GlobalVariableSet(p + "price", g_PlanPrice);
   GlobalVariableSet(p + "manpct", g_ManualPartialPercent);
   GlobalVariableSet(p + "dir", (double)g_PlanDirection);
}

bool LoadPanelInputsAfterChartChange()
{
   if(!InpPersistPanelInputsOnChartChange)
      return(false);

   string p = PanelPersistPrefix();
   if(!GlobalVariableCheck(p + "valid"))
      return(false);

   if(GlobalVariableGet(p + "valid") < 0.5)
      return(false);

   g_PlanLot = GlobalVariableGet(p + "lot");
   g_PlanSLPoints = (int)GlobalVariableGet(p + "sl");
   g_PlanTPPoints = (int)GlobalVariableGet(p + "tp");
   g_PlanPartialCount = (int)GlobalVariableGet(p + "parts");
   g_OrderMode = (ENUM_ATP_ORDER_MODE)(int)GlobalVariableGet(p + "mode");
   g_PlanPrice = GlobalVariableGet(p + "price");
   g_ManualPartialPercent = GlobalVariableGet(p + "manpct");
   g_PlanDirection = (ENUM_ORDER_TYPE)(int)GlobalVariableGet(p + "dir");

   int max_parts = MathMax(1, InpMaxPartialCount);
   if(g_PlanLot <= 0.0)
      g_PlanLot = InpDefaultLot;
   if(g_PlanSLPoints <= 0)
      g_PlanSLPoints = InpDefaultSLPoints;
   if(g_PlanTPPoints <= 0)
      g_PlanTPPoints = InpDefaultTPPoints;
   g_PlanPartialCount = MathMax(1, MathMin(max_parts, g_PlanPartialCount));
   if(g_ManualPartialPercent <= 0.0)
      g_ManualPartialPercent = InpManualPartialDefaultPercent;

   return(true);
}

#endif