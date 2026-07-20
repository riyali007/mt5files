#ifndef ADVTP_INPUTS_MQH
#define ADVTP_INPUTS_MQH

input group "General"
input ulong InpMagicNumber = 26071801;
input bool InpAllowOnlyHedgingAccounts = true;
input int InpTimerIntervalMs = 250;
input bool InpEnableDebugLog = true;

input group "Panel"
input ENUM_BASE_CORNER InpPanelCorner = CORNER_LEFT_UPPER;
input int InpPanelX = 10;
input int InpPanelY = 20;

input group "Order Defaults"
input double InpDefaultLot = 0.30;
input int InpDefaultSLPoints = 700;
input int InpDefaultTPPoints = 1500;
input int InpDefaultPartialCount = 5;
input int InpMaxPartialCount = 20;   // UI + engine max partial levels (was hard-coded 5)
input int InpDeviationPoints = 20;

input group "Partial Defaults"
input double InpFirstPartialPercent = 30.0;
input double InpSubsequentPartialPercent = 10.0;
input double InpManualPartialDefaultPercent = 10.0;

input group "Breakeven"
input int InpBETriggerPartial = 1;
input int InpBEOffsetPoints = 0;

input group "Developer Test Mode"
input bool InpShowDeveloperControls = false;
input bool InpEnableDeveloperTestMode = false;

input group "External Trade Monitoring"
input bool InpMonitorExternal = true;
input bool InpExternalAlerts = true;
input bool InpAutoAdoptExternal = false;
input bool InpAutoApplyDefaultSLTP = true;
input bool InpOverwriteExternalSLTP = false;

input group "Persistence"
input bool InpRestoreManagedTradesOnInit = true;
input bool InpPersistPartialState = true;

input group "Trailing Stop"
input bool InpEnableTrailingStop = false;
input int InpTrailingStopStartPoints = 1000;
input int InpTrailingStopDistancePoints = 500;
input int InpTrailingStopStepPoints = 100;

input group "Trade Journal CSV"
input bool InpEnableTradeJournalCsv = true;
input string InpTradeJournalCsvFileName = "AdvTradingPanel_Journal.csv";
input bool InpTradeJournalCsvInCommonFolder = true;
input bool InpTradeJournalLogPartials = true;
input bool InpTradeJournalLogBreakeven = true;
input bool InpTradeJournalLogTrailingStop = true;
input bool InpTradeJournalLogClose = true;
input bool InpTradeJournalLogAdoption = true;

input group "n8n Trade Journal Webhook"
input bool InpEnableN8nWebhook = false;
input string InpN8nWebhookUrl = "";
input int InpN8nWebhookTimeoutMs = 3000;
input bool InpN8nSendOpenEvents = true;
input bool InpN8nSendPartialEvents = true;
input bool InpN8nSendBreakevenEvents = true;
input bool InpN8nSendTrailingStopEvents = true;
input bool InpN8nSendCloseEvents = true;
input bool InpN8nSendAdoptionEvents = true;

input group "Breakeven Journal Delay"
input int InpBEJournalDelaySeconds = 2;   // 0=immediate; 1-2 recommended so PARTIAL webhook finishes first

input group "Trade Open Screenshot"
input bool InpCaptureScreenshotOnTradeOpen = true;
input int InpTradeOpenScreenshotWidth = 1600;
input int InpTradeOpenScreenshotHeight = 900;
input bool InpIncludePanelInTradeOpenScreenshot = false;

input group "Sounds"
input bool   InpEnableSounds = true;
input bool   InpSoundOnPartial = true;
input bool   InpSoundOnBreakeven = true;
input bool   InpSoundOnFullTP = true;
input bool   InpSoundOnSLHit = true;
// Built-in terminal sounds (MQL5\\Sounds) or your own .wav names
input string InpSoundPartial = "ok.wav";
input string InpSoundBreakeven = "news.wav";
input string InpSoundFullTP = "alert2.wav";
input string InpSoundSLHit = "timeout.wav";

input group "Basket Worst-First Close"
input bool InpEnableBasketWorstClose = true;           // Master switch
input int  InpBasketMinGroupSize = 2;                  // Need at least N same-direction trades
input int  InpBasketMinWorstProfitPoints = 50;          // Worst must be green by this many points
input int  InpBasketCoverBufferPoints = 20;             // Extra good-side points beyond covering worst
input bool InpBasketRequireCover = true;               // Option 2: green AND cover
input bool InpBasketIncludeExternal = true;            // Include adopted/external managed tickets

#endif