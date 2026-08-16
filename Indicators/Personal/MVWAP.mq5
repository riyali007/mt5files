//+------------------------------------------------------------------+
//|                                                        MVWAP.mq5 |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1
#property indicator_type1   DRAW_LINE
#property indicator_width1  2

//--- Inputs must be strictly in this order
input int InpPeriod = 14; 
input color InpColor = clrDarkOrange; 

double ExtBuffer[];

int OnInit()
  {
   SetIndexBuffer(0, ExtBuffer, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpColor); // Set dynamic color
   IndicatorSetString(INDICATOR_SHORTNAME, "MVWAP(" + IntegerToString(InpPeriod) + ")");
   return(INIT_SUCCEEDED);
  }

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
  {
   if(rates_total < InpPeriod) return 0;
   
   int limit = prev_calculated == 0 ? 0 : prev_calculated - 1;
   
   for(int i = limit; i < rates_total; i++)
     {
      double sum_pv = 0;
      double sum_v = 0;
      
      int start = i - InpPeriod + 1;
      if(start < 0) start = 0;
      
      for(int j = start; j <= i; j++)
        {
         double typical_price = (high[j] + low[j] + close[j]) / 3.0;
         double vol = (double)tick_volume[j];
         
         sum_pv += typical_price * vol;
         sum_v += vol;
        }
      ExtBuffer[i] = (sum_v > 0) ? (sum_pv / sum_v) : close[i];
     }
   return(rates_total);
  }