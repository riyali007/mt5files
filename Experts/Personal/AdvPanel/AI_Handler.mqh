//+------------------------------------------------------------------+
//|                                                   AI_Handler.mqh |
//|                     Integration for Gemini, OpenRouter & Ollama  |
//+------------------------------------------------------------------+
#property strict
#include "Defines.mqh"
#include "Inputs.mqh"

class CAIHandler {
private:
   ENUM_AI_PROVIDER m_provider;
   string         m_apiKey;
   string         m_model;
   string         m_baseUrl;
   string         m_system_prompt;
   int            m_timeout;
   
   double         m_max_daily_loss;
   int            m_max_concurrent_trades;
   
   // --- MTA Settings ---
   int            m_mta_count;
   ENUM_TIMEFRAMES m_mta_tf1;
   ENUM_TIMEFRAMES m_mta_tf2;
   ENUM_TIMEFRAMES m_mta_tf3;

   // --- LOGGING HELPER ---
   void WriteRawLog(string requestJson, string responseJson, int status) {
      string filename = "AI_Raw_Log.txt";
      int handle = FileOpen(filename, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
      
      if(handle != INVALID_HANDLE) {
         FileSeek(handle, 0, SEEK_END);
         string sep = "--------------------------------------------------";
         string time = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
         string provName = EnumToString(m_provider);
         FileWrite(handle, sep);
         FileWrite(handle, StringFormat("TIME: %s | PROVIDER: %s | STATUS: %d", time, provName, status));
         FileWrite(handle, ">>> REQUEST:");
         FileWrite(handle, requestJson);
         FileWrite(handle, "<<< RESPONSE:");
         FileWrite(handle, responseJson);
         FileWrite(handle, sep);
         FileWrite(handle, "\n");
         FileClose(handle);
      }
   }

   // --- ROBUST KEYWORD PARSER ---
   int ParseDirection(string aiText) {
      string upper = aiText;
      StringToUpper(upper);
      
      // BUY keywords
      if(StringFind(upper, "ACTION: BUY") >= 0) return 1;
      if(StringFind(upper, "ACTION: STRONG BUY") >= 0) return 1;
      if(StringFind(upper, "BUY NOW") >= 0) return 1;
      if(StringFind(upper, "BUY AT") >= 0) return 1;
      if(StringFind(upper, "SIGNAL: BUY") >= 0) return 1;
      if(StringFind(upper, "RECOMMENDATION: BUY") >= 0) return 1;
      
      // SELL keywords
      if(StringFind(upper, "ACTION: SELL") >= 0) return -1;
      if(StringFind(upper, "ACTION: STRONG SELL") >= 0) return -1;
      if(StringFind(upper, "SELL NOW") >= 0) return -1;
      if(StringFind(upper, "SELL AT") >= 0) return -1;
      if(StringFind(upper, "SIGNAL: SELL") >= 0) return -1;
      if(StringFind(upper, "RECOMMENDATION: SELL") >= 0) return -1;
      
      return 0; // HOLD
   }

   // --- RESPONSE PARSING ---
   string ExtractResponse(string json) {
      if(StringFind(json, "\"error\":") >= 0) return "API Error: See Log File";
      string result = "";
      int startPos = -1;

      string field = "";
      if(m_provider == PROVIDER_GEMINI) field = "\"text\"";
      else if(m_provider == PROVIDER_OLLAMA) field = "\"response\"";
      else field = "\"content\"";

      int fieldPos = StringFind(json, field);
      if(fieldPos < 0) return "";

      int colonPos = StringFind(json, ":", fieldPos);
      if(colonPos < 0) return "";
      
      startPos = StringFind(json, "\"", colonPos + 1);
      if(startPos < 0) return "";
      startPos += 1; 
      
      int endPos = startPos;
      while(true) {
         endPos = StringFind(json, "\"", endPos);
         if(endPos < 0) break;
         if(StringSubstr(json, endPos-1, 1) != "\\") break;
         endPos++;
      }
      
      if(endPos < 0) return "";
      result = StringSubstr(json, startPos, endPos - startPos);
      
      StringReplace(result, "\\n", "\n");
      StringReplace(result, "\\\"", "\"");
      StringReplace(result, "\\t", " ");
      
      result = StripThinking(result);
      return result;
   }
   
   string StripThinking(string text) {
      int startThink = StringFind(text, "<think>");
      if(startThink >= 0) {
         int endThink = StringFind(text, "</think>");
         if(endThink > startThink) {
            string before = StringSubstr(text, 0, startThink);
            string after = StringSubstr(text, endThink + 8); 
            StringTrimRight(before);
            StringTrimLeft(after);
            return before + " " + after;
         }
      }
      return text;
   }

   string EscapeJSON(string text) {
      string res = text;
      StringReplace(res, "\\", "\\\\");
      StringReplace(res, "\"", "\\\""); 
      StringReplace(res, "\n", "\\n");  
      StringReplace(res, "\r", "");     
      StringReplace(res, "\t", " ");    
      return res;
   }

public:
   CAIHandler() { 
      m_timeout = 20000; 
      // Defaults
      m_mta_count = 5; 
      m_mta_tf1 = PERIOD_M15;
      m_mta_tf2 = PERIOD_H1;
      m_mta_tf3 = PERIOD_H4;
   } 
   
   // --- NEW: Configure MTA Timeframes and Count ---
   void SetMTASettings(int count, ENUM_TIMEFRAMES tf1, ENUM_TIMEFRAMES tf2, ENUM_TIMEFRAMES tf3) {
      if(count > 0) m_mta_count = count;
      m_mta_tf1 = tf1;
      m_mta_tf2 = tf2;
      m_mta_tf3 = tf3;
   }
   
   void Init(ENUM_AI_PROVIDER prov, string key, string model, string url, string prompt, double maxLoss, int maxTrades) {
      m_provider = prov;
      m_apiKey = key;
      m_model = model;
      m_baseUrl = url;
      m_system_prompt = prompt;
      m_max_daily_loss = maxLoss;
      m_max_concurrent_trades = maxTrades;
      
      if(m_baseUrl == "") {
         if(m_provider == PROVIDER_GEMINI) m_baseUrl = "https://generativelanguage.googleapis.com";
         if(m_provider == PROVIDER_OPENROUTER) m_baseUrl = "https://openrouter.ai/api/v1";
         if(m_provider == PROVIDER_OLLAMA) m_baseUrl = "https://ollama.com";
      }
      if(StringSubstr(m_baseUrl, StringLen(m_baseUrl)-1) == "/") {
         m_baseUrl = StringSubstr(m_baseUrl, 0, StringLen(m_baseUrl)-1);
      }
   }

   int GetTradeDecision(string &reasoning) {
      if(PositionsTotal() >= m_max_concurrent_trades) {
         reasoning = "Guardrail: Max trades limit reached.";
         return 0;
      }

      string marketData = GenerateMarketData();
      string safePrompt = EscapeJSON(m_system_prompt + " " + marketData);
      
      string url, headers, jsonData;
      if(m_provider == PROVIDER_GEMINI) {
         url = m_baseUrl + "/v1beta/models/" + m_model + ":generateContent?key=" + m_apiKey;
         headers = "Content-Type: application/json\r\n";
         jsonData = "{ \"contents\": [{ \"parts\": [{ \"text\": \"" + safePrompt + "\" }] }] }";
      } 
      else if(m_provider == PROVIDER_OLLAMA) {
         string endpoint = "/api/generate";
         if(StringFind(m_baseUrl, "/api/generate") >= 0) endpoint = ""; 
         url = m_baseUrl + endpoint;
         headers = "Content-Type: application/json\r\n";
         if(m_apiKey != "") headers += "Authorization: Bearer " + m_apiKey + "\r\n";
         jsonData = "{\"model\": \"" + m_model + "\",\"prompt\": \"" + safePrompt + "\",\"stream\": false}";
      }
      else {
         string endpoint = "/chat/completions";
         if(StringFind(m_baseUrl, "chat/completions") >= 0) endpoint = ""; 
         url = m_baseUrl + endpoint;
         headers = "Content-Type: application/json\r\n";
         headers += "Authorization: Bearer " + m_apiKey + "\r\n";
         headers += "HTTP-Referer: https://metatrader.net\r\n"; 
         headers += "X-Title: MT5-AI-EA\r\n";
         jsonData = "{\"model\": \"" + m_model + "\",\"messages\": [{\"role\": \"user\", \"content\": \"" + safePrompt + "\"}]}";
      }
      
      char postData[];
      int len = StringLen(jsonData);
      StringToCharArray(jsonData, postData, 0, len); 
      
      char resultData[];
      string resultHeaders;
      
      ResetLastError();
      int res = WebRequest("POST", url, headers, m_timeout, postData, resultData, resultHeaders);
      string responseStr = CharArrayToString(resultData);
      WriteRawLog(jsonData, responseStr, res);
      
      if(res == 200) {
         string aiText = ExtractResponse(responseStr);
         reasoning = aiText;
         int decision = ParseDirection(aiText);
         if(decision == 1) Print("AI DECISION: BUY DETECTED");
         if(decision == -1) Print("AI DECISION: SELL DETECTED");
         return decision;
      } else {
         int err = GetLastError();
         Print("AI Request Failed. Status: ", res, " Err: ", err);
         if(res == -1) reasoning = "Error: Check URL Whitelist";
         else reasoning = "API Error: " + (string)res;
         return 0;
      }
   }

   // --- Helper to fetch candles for any TF ---
   string FetchCandles(ENUM_TIMEFRAMES tf, int count) {
       MqlRates rates[];
       ArraySetAsSeries(rates, true);
       int copied = CopyRates(_Symbol, tf, 0, count, rates);
       
       if(copied <= 0) return "";
       
       string tfName = EnumToString(tf);
       string tfData = "\\n[" + tfName + " DATA]: ";
       
       for(int i=0; i<copied; i++) {
           string candle = StringFormat("(T:%s O:%.5f H:%.5f L:%.5f C:%.5f)", 
               TimeToString(rates[i].time, TIME_MINUTES), rates[i].open, rates[i].high, rates[i].low, rates[i].close);
           tfData += candle;
           if(i < copied-1) tfData += ", ";
       }
       return tfData;
   }

   // --- UPDATED: Generate MTA Data Dynamically ---
   string GenerateMarketData() {
      string data = "Symbol: " + _Symbol + "\\n";
      
      // 1. Current Timeframe (Primary analysis)
      data += FetchCandles(_Period, InpAI_Bars);
      
      // 2. MTA Configured Timeframes
      // Only fetch if they are different from Current TF to avoid duplication
      if(_Period != m_mta_tf1) data += FetchCandles(m_mta_tf1, m_mta_count);
      if(_Period != m_mta_tf2) data += FetchCandles(m_mta_tf2, m_mta_count);
      if(_Period != m_mta_tf3) data += FetchCandles(m_mta_tf3, m_mta_count);

      return data;
   }
};