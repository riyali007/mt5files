//+------------------------------------------------------------------+
//|                                        DynamicLiquidityZones.mq5 |
//+------------------------------------------------------------------+
#property copyright "Optimized for MT5 Performance"
#property link      ""
#property version   "3.03" // Extreme Performance Optimizations Applied
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

// --- Inputs ---
input group "Liquidity Detection"
input int    InpLeftLen       = 10;     
input int    InpRightLen      = 2;      
input double InpThresholdPct  = 0.03;   
input int    InpMaxActiveZones= 60;     

input group "Visuals"
input color  InpBullColor     = C'8,153,129';   
input color  InpBearColor     = C'242,54,69';   
input color  InpBullBgColor   = C'15,35,35';    
input color  InpBearBgColor   = C'50,20,25';    
input bool   InpShowMidline   = false;          
input color  InpMidlineColor  = C'120,123,134'; 
input bool   InpShowVolume    = true;           // Restored Volume Toggles
input int    InpDelayMinutes  = 15; // Time to keep swept boxes visible before deleting 

// --- Fast Math Cache ---
double m_threshold_mult; 
double m_cluster_mult;

// --- Types ---
struct PivotPoint {
    double   price;
    datetime time;
    long     vol;
};

class LiquidityZone {
public:
    int      id_num;
    string   id_bg, id_border, lbl, b1, b2, v1, v2;
    
    double   top, bottom, mid, sweepLevel;
    long     totalVol;
    datetime prev_time, curr_time, sweepTime, deleteTime;
    double   prev_price, curr_price;
    long     prev_vol, curr_vol;
    
    int      createdIdx;
    bool     isHigh;
    bool     isSwept;
    bool     isVisualized;
    bool     isDeleted;
    
    // Caching for Performance
    datetime lastDrawnTime;
    string   lastLabelText;

    void Init(int _id_num, bool _isHigh, double _top, double _bottom, double _mid, long _totalVol, 
              datetime _prev_time, double _prev_price, long _prev_vol, 
              datetime _curr_time, double _curr_price, long _curr_vol, 
              int _createdIdx) {
        
        id_num = _id_num;
        isHigh = _isHigh;
        top = _top; bottom = _bottom; mid = _mid;
        sweepLevel = isHigh ? top : bottom;
        totalVol = _totalVol;
        
        prev_time = _prev_time; prev_price = _prev_price; prev_vol = _prev_vol;
        curr_time = _curr_time; curr_price = _curr_price; curr_vol = _curr_vol;
        createdIdx = _createdIdx;
        
        isSwept = false;
        isVisualized = false;
        isDeleted = false;
        sweepTime = 0;
        deleteTime = 0;
        lastDrawnTime = 0;
        lastLabelText = "";
        
        string pfx = "DLZ_" + IntegerToString(id_num) + "_";
        id_bg     = pfx + "bg";
        id_border = pfx + "border";
        lbl       = pfx + "lbl";
        b1        = pfx + "b1"; b2 = pfx + "b2";
        v1        = pfx + "v1"; v2 = pfx + "v2";
    }

    void CreateObjects() {
        if(isVisualized) return;
        isVisualized = true;

        color zColor  = isHigh ? InpBearColor : InpBullColor;
        color bgColor = isHigh ? InpBearBgColor : InpBullBgColor;
        
        ObjectCreate(0, id_bg, OBJ_RECTANGLE, 0, prev_time, top, curr_time, bottom);
        ObjectSetInteger(0, id_bg, OBJPROP_COLOR, bgColor);
        ObjectSetInteger(0, id_bg, OBJPROP_BGCOLOR, bgColor);
        ObjectSetInteger(0, id_bg, OBJPROP_FILL, true);
        ObjectSetInteger(0, id_bg, OBJPROP_BACK, true); 

        ObjectCreate(0, id_border, OBJ_RECTANGLE, 0, prev_time, top, curr_time, bottom);
        ObjectSetInteger(0, id_border, OBJPROP_COLOR, zColor);
        ObjectSetInteger(0, id_border, OBJPROP_STYLE, STYLE_SOLID);
        ObjectSetInteger(0, id_border, OBJPROP_FILL, false);

        ObjectCreate(0, lbl, OBJ_TEXT, 0, curr_time, top);
        ObjectSetInteger(0, lbl, OBJPROP_COLOR, zColor);
        ObjectSetString(0, lbl, OBJPROP_FONT, "Arial");
        ObjectSetInteger(0, lbl, OBJPROP_FONTSIZE, 8);
        ObjectSetInteger(0, lbl, OBJPROP_ANCHOR, ANCHOR_LEFT);

        // Restored Bubbles (Dots)
        CreateDot(b1, prev_time, prev_price, zColor);
        CreateDot(b2, curr_time, curr_price, zColor);

        // Restored Volume Text at taps
        if(InpShowVolume) {
            CreateVolText(v1, prev_time, prev_price, prev_vol, zColor, isHigh);
            CreateVolText(v2, curr_time, curr_price, curr_vol, zColor, isHigh);
        }
    }

    void CreateDot(string name, datetime t, double p, color c) {
        ObjectCreate(0, name, OBJ_ARROW, 0, t, p);
        ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 159);
        ObjectSetInteger(0, name, OBJPROP_COLOR, c);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, 3); 
        ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_CENTER);
    }

    void CreateVolText(string name, datetime t, double p, long v, color c, bool highPivot) {
        ObjectCreate(0, name, OBJ_TEXT, 0, t, p);
        ObjectSetString(0, name, OBJPROP_TEXT, FormatVol(v));
        ObjectSetInteger(0, name, OBJPROP_COLOR, c);
        ObjectSetString(0, name, OBJPROP_FONT, "Arial");
        ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
        ObjectSetInteger(0, name, OBJPROP_ANCHOR, highPivot ? ANCHOR_BOTTOM : ANCHOR_TOP);
    }

    void UpdateRightEdge(datetime bar_time, string text) {
        if(!isVisualized || isDeleted || isSwept) return;
        
        // Caching Object modifications (Extreme speed boost on tick updates)
        if(bar_time != lastDrawnTime) {
            ObjectSetInteger(0, id_bg, OBJPROP_TIME, 1, bar_time);
            ObjectSetInteger(0, id_border, OBJPROP_TIME, 1, bar_time);
            ObjectSetInteger(0, lbl, OBJPROP_TIME, 0, bar_time);
            lastDrawnTime = bar_time;
        }
        
        if(text != lastLabelText) {
            ObjectSetString(0, lbl, OBJPROP_TEXT, text);
            lastLabelText = text;
        }
    }

    void MarkSwept(datetime sweep_t) {
        if(!isVisualized || isSwept) return;
        isSwept = true;
        sweepTime = sweep_t;
        deleteTime = sweep_t + (InpDelayMinutes * 60); 
        
        ObjectSetInteger(0, id_bg, OBJPROP_TIME, 1, sweepTime);
        ObjectSetInteger(0, id_border, OBJPROP_TIME, 1, sweepTime);
        ObjectSetInteger(0, lbl, OBJPROP_TIME, 0, sweepTime);
        
        color dimGray = C'60,60,60'; 
        ObjectSetInteger(0, id_bg, OBJPROP_COLOR, dimGray);
        ObjectSetInteger(0, id_bg, OBJPROP_BGCOLOR, dimGray);
        ObjectSetInteger(0, id_border, OBJPROP_COLOR, dimGray);
        ObjectSetInteger(0, lbl, OBJPROP_COLOR, dimGray);
        
        // Dim the tap bubbles and hide the text to clean up chart
        ObjectSetInteger(0, b1, OBJPROP_COLOR, dimGray);
        ObjectSetInteger(0, b2, OBJPROP_COLOR, dimGray);
        if(InpShowVolume) {
            ObjectSetString(0, v1, OBJPROP_TEXT, "");
            ObjectSetString(0, v2, OBJPROP_TEXT, "");
        }

        string sweptTxt = "Swept " + (isHigh ? "EQH" : "EQL");
        ObjectSetString(0, lbl, OBJPROP_TEXT, sweptTxt);
        lastLabelText = sweptTxt;
    }

    void DeleteVisuals() {
        if(!isVisualized || isDeleted) return;
        ObjectDelete(0, id_bg);
        ObjectDelete(0, id_border);
        ObjectDelete(0, lbl);
        ObjectDelete(0, b1);
        ObjectDelete(0, b2);
        ObjectDelete(0, v1);
        ObjectDelete(0, v2);
        
        isDeleted = true;
        isVisualized = false;
    }
};

// --- Storage arrays & counters ---
PivotPoint     historicalHighs[];
PivotPoint     historicalLows[];
LiquidityZone* activeZones[];
LiquidityZone* allZones[];     

int globalObjCounter = 0;

string FormatVol(long v) {
    if(v >= 1000000) return DoubleToString(v / 1000000.0, 1) + "M";
    if(v >= 1000)    return DoubleToString(v / 1000.0, 1) + "K";
    return IntegerToString(v);
}

void InsertPivot(PivotPoint& arr[], PivotPoint& new_pt) {
    int sz = ArraySize(arr);
    if(sz < 50) {
        ArrayResize(arr, sz + 1, 50); // Pre-allocate memory block
        sz++;
    }
    if(sz > 1) {
        ArrayCopy(arr, arr, 1, 0, sz - 1); // Native fast shift
    }
    arr[0] = new_pt;
}

void Cleanup() {
    for(int i = 0; i < ArraySize(allZones); i++) {
        if (CheckPointer(allZones[i]) != POINTER_INVALID) {
            allZones[i].DeleteVisuals();
            delete allZones[i]; 
        }
    }
    ArrayFree(allZones);
    ArrayFree(activeZones);
    ArrayFree(historicalHighs);
    ArrayFree(historicalLows);
    ObjectsDeleteAll(0, "DLZ_");
    globalObjCounter = 0;
}

int OnInit() {
    Cleanup();
    // Cache percentage logic for high-speed math
    m_threshold_mult = InpThresholdPct / 100.0;
    m_cluster_mult = m_threshold_mult * 3.0; 
    return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
    Cleanup();
}

// --- Main Calculation ---
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
    if(rates_total < InpLeftLen + InpRightLen + 1) return 0;
    
    ArraySetAsSeries(time, false);
    ArraySetAsSeries(high, false);
    ArraySetAsSeries(low, false);
    ArraySetAsSeries(tick_volume, false);

    bool isHistory = (prev_calculated == 0);
    int start = isHistory ? InpLeftLen + InpRightLen : prev_calculated - 1;
    bool needsVisualUpdate = false;
    
    if(isHistory) Cleanup();

    for(int i = start; i < rates_total; i++) {
        datetime current_time = time[i];
        
        // 1. Process Sweeps
        for(int z = ArraySize(activeZones) - 1; z >= 0; z--) {
            LiquidityZone* zone = activeZones[z];
            
            if(i > zone.createdIdx) {
                bool sweepOccurred = zone.isHigh ? high[i] > zone.sweepLevel : low[i] < zone.sweepLevel;
                if(sweepOccurred) {
                    if(!isHistory) zone.MarkSwept(current_time);
                    else {
                        zone.isSwept = true;
                        zone.sweepTime = current_time;
                        zone.deleteTime = current_time + (InpDelayMinutes * 60);
                    }
                    ArrayRemove(activeZones, z, 1); 
                    needsVisualUpdate = true;
                }
            }
        }

        // 2. Process Expirations
        for(int a = ArraySize(allZones) - 1; a >= 0; a--) {
            LiquidityZone* zone = allZones[a];
            if(zone.isSwept && current_time >= zone.deleteTime) {
                if(!isHistory) zone.DeleteVisuals(); 
                delete zone;                         
                ArrayRemove(allZones, a, 1);         
                needsVisualUpdate = true;
            }
        }

        // 3. Process Max Active Limits
        while(ArraySize(activeZones) > InpMaxActiveZones) {
            ArrayRemove(activeZones, 0, 1); 
        }

        // 4. Detect New Pivots
        int p_idx = i - InpRightLen;
        if(p_idx >= InpLeftLen) {
            long p_vol = tick_volume[p_idx];
            datetime p_time = time[p_idx];

            // Optimized inner loop checks
            bool isPH = true, isPL = true;
            double pH = high[p_idx], pL = low[p_idx];
            
            for(int j = 1; j <= InpLeftLen; j++) {
                if(isPH && high[p_idx - j] > pH) isPH = false;
                if(isPL && low[p_idx - j] < pL)  isPL = false;
                if(!isPH && !isPL) break;
            }
            if(isPH) for(int j = 1; j <= InpRightLen; j++) if(high[p_idx + j] >= pH) { isPH = false; break; }
            if(isPL) for(int j = 1; j <= InpRightLen; j++) if(low[p_idx + j] <= pL)  { isPL = false; break; }

            // Highs
            if(isPH) {
                for(int h = 0; h < ArraySize(historicalHighs); h++) {
                    PivotPoint prev = historicalHighs[h];
                    if(MathAbs(pH - prev.price) <= prev.price * m_threshold_mult) {
                        LiquidityZone* nz = new LiquidityZone();
                        nz.Init(globalObjCounter++, true, MathMax(pH, prev.price), MathMin(pH, prev.price), 
                                (MathMax(pH, prev.price) + MathMin(pH, prev.price))/2.0, prev.vol + p_vol, 
                                prev.time, prev.price, prev.vol, p_time, pH, p_vol, i);
                        
                        ArrayResize(activeZones, ArraySize(activeZones) + 1, InpMaxActiveZones + 5); 
                        activeZones[ArraySize(activeZones)-1] = nz;
                        ArrayResize(allZones, ArraySize(allZones) + 1, 500);    
                        allZones[ArraySize(allZones)-1] = nz;
                        
                        if(!isHistory) nz.CreateObjects();
                        needsVisualUpdate = true;
                        break; 
                    }
                }
                PivotPoint new_hp = {pH, p_time, p_vol};
                InsertPivot(historicalHighs, new_hp);
            }

            // Lows
            if(isPL) {
                for(int h = 0; h < ArraySize(historicalLows); h++) {
                    PivotPoint prev = historicalLows[h];
                    if(MathAbs(pL - prev.price) <= prev.price * m_threshold_mult) {
                        LiquidityZone* nz = new LiquidityZone();
                        nz.Init(globalObjCounter++, false, MathMax(pL, prev.price), MathMin(pL, prev.price), 
                                (MathMax(pL, prev.price) + MathMin(pL, prev.price))/2.0, prev.vol + p_vol, 
                                prev.time, prev.price, prev.vol, p_time, pL, p_vol, i);
                        
                        ArrayResize(activeZones, ArraySize(activeZones) + 1, InpMaxActiveZones + 5); 
                        activeZones[ArraySize(activeZones)-1] = nz;
                        ArrayResize(allZones, ArraySize(allZones) + 1, 500);    
                        allZones[ArraySize(allZones)-1] = nz;
                        
                        if(!isHistory) nz.CreateObjects();
                        needsVisualUpdate = true;
                        break;
                    }
                }
                PivotPoint new_lp = {pL, p_time, p_vol};
                InsertPivot(historicalLows, new_lp);
            }
        }
    }

    if(isHistory) {
        for(int i = 0; i < ArraySize(allZones); i++) {
            allZones[i].CreateObjects();
            if(allZones[i].isSwept) allZones[i].MarkSwept(allZones[i].sweepTime);
        }
    }

    // --- UI Update Pipeline ---
    static datetime last_bar_time = 0;
    datetime latest_time = time[rates_total - 1];
    
    if(latest_time != last_bar_time || needsVisualUpdate || isHistory) {
        
        int szActive = ArraySize(activeZones);
        bool processed[];
        ArrayResize(processed, szActive);
        ArrayInitialize(processed, false);
        
        for(int i = 0; i < szActive; i++) {
            if(processed[i]) continue;
            
            LiquidityZone* baseZone = activeZones[i];
            double clusterVol = (double)baseZone.totalVol;
            int clusterCount = 1;
            
            for(int j = i + 1; j < szActive; j++) {
                if(processed[j]) continue;
                LiquidityZone* comp = activeZones[j];
                
                if(baseZone.isHigh == comp.isHigh) {
                    if(MathAbs(baseZone.sweepLevel - comp.sweepLevel) <= baseZone.sweepLevel * m_cluster_mult) {
                        clusterVol += comp.totalVol;
                        clusterCount++;
                        processed[j] = true;
                        comp.UpdateRightEdge(latest_time, ""); // Hide child texts immediately
                    }
                }
            }
            
            string typeStr  = baseZone.isHigh ? "EQH" : "EQL";
            string countStr = clusterCount > 1 ? IntegerToString(clusterCount) + "x " : "";
            string volStr   = InpShowVolume ? " (" + FormatVol((long)clusterVol) + ")" : "";
            string finalTxt = countStr + typeStr + volStr;
            
            baseZone.UpdateRightEdge(latest_time, finalTxt);
        }
        
        last_bar_time = latest_time;
        ChartRedraw();
    }
    
    return(rates_total);
}