//+------------------------------------------------------------------+
//|                                        HTF_BOS_CHoCH_v0.1.mq5    |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "MQL5 Professional Developer"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//--- Input Groups
input group "HTF 1 Settings"
input bool            InpEnableHTF1   = true;        // Enable HTF 1
input ENUM_TIMEFRAMES InpTF1          = PERIOD_H1;   // HTF 1 Timeframe
input int             InpPivotLen1    = 5;           // HTF 1 Pivot Length
input color           InpColor1       = clrDodgerBlue; // HTF 1 Line Color

input group "HTF 2 Settings"
input bool            InpEnableHTF2   = true;        // Enable HTF 2
input ENUM_TIMEFRAMES InpTF2          = PERIOD_H4;   // HTF 2 Timeframe
input int             InpPivotLen2    = 5;           // HTF 2 Pivot Length
input color           InpColor2       = clrOrange;   // HTF 2 Line Color

input group "Global Settings"
input int             InpLabelSize       = 10;          // Label Text Size
input color           InpBosBullColor    = clrLime;     // Bullish BOS Color
input color           InpBosBearColor    = clrRed;      // Bearish BOS Color
input color           InpChochBullColor  = clrLime;     // Bullish CHoCH Color
input color           InpChochBearColor  = clrRed;      // Bearish CHoCH Color
input bool            InpShowBOS         = true;        // Show BOS Labels
input bool            InpShowCHoCH       = true;        // Show CHoCH Labels
input int             InpLookback        = 500;         // Lookback Bars for State Initialization

//--- Forward Declaration
class CHTFTracker;

//--- Global Variables
CHTFTracker* HTF1;
CHTFTracker* HTF2;
string       IndicatorPrefix = "StructDetect_";

//+------------------------------------------------------------------+
//| Class: CHTFTracker                                               |
//| Purpose: Encapsulates per-HTF state, pivot logic, and rendering  |
//+------------------------------------------------------------------+
class CHTFTracker
{
private:
    string            m_name;
    ENUM_TIMEFRAMES   m_tf;
    int               m_pivot_len;
    color             m_line_color;
    
    // State Machine
    int               m_trend;         // 1 (bull), -1 (bear), 0 (undetermined)
    double            m_topPrice;
    double            m_btmPrice;
    bool              m_topBroken;
    bool              m_btmBroken;
    
    // Synchronization
    int               m_last_htf_idx;
    double            m_prev_chart_close;
    
    // Drawing references
    string            m_top_line_name;
    string            m_btm_line_name;

    //--- Helper: Draw Text Label
    void DrawLabel(string text, datetime time, double price, bool isBull)
    {
        string obj_name = IndicatorPrefix + m_name + "_Lbl_" + TimeToString(time) + "_" + DoubleToString(price, 5);
        ObjectCreate(0, obj_name, OBJ_TEXT, 0, time, price);
        ObjectSetString(0, obj_name, OBJPROP_TEXT, text);
        ObjectSetInteger(0, obj_name, OBJPROP_FONTSIZE, InpLabelSize);
        ObjectSetInteger(0, obj_name, OBJPROP_ANCHOR, isBull ? ANCHOR_RIGHT_UPPER : ANCHOR_RIGHT_LOWER);
        
        color col = clrNONE;
        if(text == "BOS")   col = isBull ? InpBosBullColor : InpBosBearColor;
        if(text == "CHoCH") col = isBull ? InpChochBullColor : InpChochBearColor;
        
        ObjectSetInteger(0, obj_name, OBJPROP_COLOR, col);
    }

    //--- Helper: Cap Trendline at Break or Supersede
    void CapLine(string name, datetime cap_time, double price)
    {
        if(ObjectFind(0, name) >= 0)
        {
            ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
            ObjectMove(0, name, 1, cap_time, price);
        }
    }

public:
    CHTFTracker(string name, ENUM_TIMEFRAMES tf, int pivot_len, color line_color)
    {
        m_name         = name;
        m_tf           = tf;
        m_pivot_len    = pivot_len;
        m_line_color   = line_color;
        ResetState();
    }
    
    void ResetState()
    {
        m_trend            = 0;
        m_topPrice         = -1.0;
        m_btmPrice         = -1.0;
        m_topBroken        = true;
        m_btmBroken        = true;
        m_last_htf_idx     = -1;
        m_prev_chart_close = -1.0;
        m_top_line_name    = "";
        m_btm_line_name    = "";
    }

    void ProcessChartBar(datetime chart_time, double chart_close, bool isHistory)
    {
        // 1. Sync with HTF without lookahead
        int current_htf_idx = iBarShift(Symbol(), m_tf, chart_time);
        if(current_htf_idx < 0) return; // Data not ready
        
        // 2. Pivot re-scanning: only run when a new HTF bar closes
        if(current_htf_idx != m_last_htf_idx && m_last_htf_idx != -1)
        {
            // Check High Pivot (Requires strictly closed bars)
            int candidate_idx = current_htf_idx + 1 + m_pivot_len;
            double candidate_high = iHigh(Symbol(), m_tf, candidate_idx);
            
            if(candidate_high > 0)
            {
                bool isPivotHigh = true;
                for(int j = current_htf_idx + 1; j <= current_htf_idx + 1 + 2 * m_pivot_len; j++)
                {
                    if(j == candidate_idx) continue;
                    if(iHigh(Symbol(), m_tf, j) >= candidate_high) 
                    {
                        isPivotHigh = false; // Strict inequality
                        break;
                    }
                }
                
                if(isPivotHigh)
                {
                    // Cap the old line if it was never broken before assigning a new one
                    if(m_top_line_name != "" && !m_topBroken) 
                    {
                        CapLine(m_top_line_name, chart_time, m_topPrice);
                    }

                    m_topPrice  = candidate_high;
                    m_topBroken = false;
                    
                    datetime pivot_time = iTime(Symbol(), m_tf, candidate_idx);
                    m_top_line_name = IndicatorPrefix + m_name + "_Top_" + TimeToString(pivot_time);
                    ObjectCreate(0, m_top_line_name, OBJ_TREND, 0, pivot_time, m_topPrice, chart_time, m_topPrice);
                    ObjectSetInteger(0, m_top_line_name, OBJPROP_RAY_RIGHT, true);
                    ObjectSetInteger(0, m_top_line_name, OBJPROP_COLOR, m_line_color);
                    ObjectSetInteger(0, m_top_line_name, OBJPROP_STYLE, STYLE_SOLID);
                }
            }

            // Check Low Pivot
            double candidate_low = iLow(Symbol(), m_tf, candidate_idx);
            if(candidate_low > 0)
            {
                bool isPivotLow = true;
                for(int j = current_htf_idx + 1; j <= current_htf_idx + 1 + 2 * m_pivot_len; j++)
                {
                    if(j == candidate_idx) continue;
                    if(iLow(Symbol(), m_tf, j) <= candidate_low)
                    {
                        isPivotLow = false; // Strict inequality
                        break;
                    }
                }
                
                if(isPivotLow)
                {
                    // Cap the old line if it was never broken before assigning a new one
                    if(m_btm_line_name != "" && !m_btmBroken) 
                    {
                        CapLine(m_btm_line_name, chart_time, m_btmPrice);
                    }

                    m_btmPrice  = candidate_low;
                    m_btmBroken = false;
                    
                    datetime pivot_time = iTime(Symbol(), m_tf, candidate_idx);
                    m_btm_line_name = IndicatorPrefix + m_name + "_Btm_" + TimeToString(pivot_time);
                    ObjectCreate(0, m_btm_line_name, OBJ_TREND, 0, pivot_time, m_btmPrice, chart_time, m_btmPrice);
                    ObjectSetInteger(0, m_btm_line_name, OBJPROP_RAY_RIGHT, true);
                    ObjectSetInteger(0, m_btm_line_name, OBJPROP_COLOR, m_line_color);
                    ObjectSetInteger(0, m_btm_line_name, OBJPROP_STYLE, STYLE_SOLID);
                }
            }
        }
        m_last_htf_idx = current_htf_idx;

        // 3. Continuous Break Classification (Close only, never a wick)
        if(m_prev_chart_close != -1.0)
        {
            // Check Bullish Break
            if(!m_topBroken && m_topPrice > 0 && chart_close > m_topPrice && m_prev_chart_close <= m_topPrice)
            {
                m_topBroken = true;
                bool isBOS = (m_trend == 1 || m_trend == 0); // BOS vs CHoCH logic
                m_trend = 1;
                
                CapLine(m_top_line_name, chart_time, m_topPrice);
                if((isBOS && InpShowBOS) || (!isBOS && InpShowCHoCH))
                    DrawLabel(isBOS ? "BOS" : "CHoCH", chart_time, m_topPrice, true);
            }
            
            // Check Bearish Break
            if(!m_btmBroken && m_btmPrice > 0 && chart_close < m_btmPrice && m_prev_chart_close >= m_btmPrice)
            {
                m_btmBroken = true;
                bool isBOS = (m_trend == -1 || m_trend == 0); // BOS vs CHoCH logic
                m_trend = -1;
                
                CapLine(m_btm_line_name, chart_time, m_btmPrice);
                if((isBOS && InpShowBOS) || (!isBOS && InpShowCHoCH))
                    DrawLabel(isBOS ? "BOS" : "CHoCH", chart_time, m_btmPrice, false);
            }
        }
        
        // Store close for next iteration's "previous close" comparison
        m_prev_chart_close = chart_close;
    }
};

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
    if(InpEnableHTF1) HTF1 = new CHTFTracker("HTF1", InpTF1, InpPivotLen1, InpColor1);
    if(InpEnableHTF2) HTF2 = new CHTFTracker("HTF2", InpTF2, InpPivotLen2, InpColor2);
    
    ObjectsDeleteAll(0, IndicatorPrefix);
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(CheckPointer(HTF1) != POINTER_INVALID) delete HTF1;
    if(CheckPointer(HTF2) != POINTER_INVALID) delete HTF2;
    ObjectsDeleteAll(0, IndicatorPrefix);
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    if(rates_total < 2) return 0;

    int start = prev_calculated;
    if(prev_calculated == 0)
    {
        // Restart/reload state re-derivation
        start = MathMax(0, rates_total - InpLookback);
        if(HTF1) HTF1.ResetState();
        if(HTF2) HTF2.ResetState();
    }
    else
    {
        start--; // Re-process the current forming bar
    }

    for(int i = start; i < rates_total; i++)
    {
        bool isHistory = (i < rates_total - 1); 
        
        if(HTF1) HTF1.ProcessChartBar(time[i], close[i], isHistory);
        if(HTF2) HTF2.ProcessChartBar(time[i], close[i], isHistory);
    }

    return(rates_total);
}
//+------------------------------------------------------------------+