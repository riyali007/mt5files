//+------------------------------------------------------------------+
//|                                                          HMA.mq5 |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1
#property indicator_type1   DRAW_LINE
#property indicator_width1  2

//--- Inputs must be strictly in this order
input int InpPeriod = 14; 
input ENUM_APPLIED_PRICE InpPrice = PRICE_CLOSE;
input color InpColor = clrDodgerBlue; 

double ExtBuffer[];
int handle_WMA_half, handle_WMA_full;
double arr_half[], arr_full[];

int OnInit()
  {
   SetIndexBuffer(0, ExtBuffer, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpColor); // Set dynamic color
   IndicatorSetString(INDICATOR_SHORTNAME, "HMA(" + IntegerToString(InpPeriod) + ")");
   
   int half_period = (int)MathFloor(InpPeriod / 2.0);
   handle_WMA_half = iMA(_Symbol, _Period, half_period, 0, MODE_LWMA, InpPrice);
   handle_WMA_full = iMA(_Symbol, _Period, InpPeriod, 0, MODE_LWMA, InpPrice);
   
   ArraySetAsSeries(arr_half, true);
   ArraySetAsSeries(arr_full, true);
   
   return(INIT_SUCCEEDED);
  }

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
  {
   if(rates_total < InpPeriod) return 0;
   
   int limit = rates_total - prev_calculated;
   if(prev_calculated > 0) limit++;
   else limit = rates_total - InpPeriod;

   int sqrt_period = (int)MathFloor(MathSqrt(InpPeriod));
   
   if(CopyBuffer(handle_WMA_half, 0, 0, limit + sqrt_period, arr_half) <= 0) return 0;
   if(CopyBuffer(handle_WMA_full, 0, 0, limit + sqrt_period, arr_full) <= 0) return 0;

   double raw_hma[];
   ArrayResize(raw_hma, limit + sqrt_period);
   for(int i = 0; i < limit + sqrt_period; i++)
     {
      raw_hma[i] = (2.0 * arr_half[i]) - arr_full[i];
     }

   for(int i = 0; i < limit; i++)
     {
      double sum = 0.0, weight_sum = 0.0;
      for(int j = 0; j < sqrt_period; j++)
        {
         double weight = (double)(sqrt_period - j);
         sum += raw_hma[i + j] * weight;
         weight_sum += weight;
        }
      ExtBuffer[rates_total - 1 - i] = sum / weight_sum;
     }
   return(rates_total);
  }