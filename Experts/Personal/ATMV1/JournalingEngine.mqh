//+------------------------------------------------------------------+
//|                                            JournalingEngine.mqh |
//|                                              Trade Manager V1.01 |
//+------------------------------------------------------------------+
enum ENUM_JOURNAL_EVENT
{
    EV_OPEN_ENTRY = 1,
    EV_SL_HIT = 2,
    EV_BE_HIT = 3,
    EV_PARTIAL_HIT = 4,
    EV_SL_CHANGED_BE = 5,
    EV_TP_SL_UPDATED = 6
};

// Queue state machine
enum ENUM_QUEUE_STATE
{
    STATE_IDLE,
    STATE_TAKE_SCREENSHOT,
    STATE_WRITE_CSV,
    STATE_SEND_WEBHOOK,
    STATE_AWAIT_RESPONSE
};

struct SJournalPayload
{
    ENUM_JOURNAL_EVENT event_type;
    ulong              ticket;
    string             symbol;
    double             realized_pnl;
    string             screenshot_path;
};

class CAsyncWebhook
{
private:
    SJournalPayload    m_queue[];      // Simple array as a queue
    ENUM_QUEUE_STATE   m_current_state;
    string             m_webhook_url;

public:
                       CAsyncWebhook();
    void               Init(string url);
    void               PushEvent(ENUM_JOURNAL_EVENT ev, ulong ticket, double pnl = 0);
    void               ProcessTimer(); // The Coroutine Engine

private:
    bool               TakeScreenshot(SJournalPayload &payload);
    bool               WriteToCSV(SJournalPayload &payload);
    bool               FireWebhook(SJournalPayload &payload);
};

//+------------------------------------------------------------------+
//| Constructor & Init                                               |
//+------------------------------------------------------------------+
CAsyncWebhook::CAsyncWebhook() : m_current_state(STATE_IDLE) {}

void CAsyncWebhook::Init(string url)
{
    m_webhook_url = url;
}

//+------------------------------------------------------------------+
//| Push a new event to the end of the queue                         |
//+------------------------------------------------------------------+
void CAsyncWebhook::PushEvent(ENUM_JOURNAL_EVENT ev, ulong ticket, double pnl = 0)
{
    int size = ArraySize(m_queue);
    ArrayResize(m_queue, size + 1);
    
    m_queue[size].event_type = ev;
    m_queue[size].ticket = ticket;
    m_queue[size].symbol = Symbol();
    m_queue[size].realized_pnl = pnl;
    m_queue[size].screenshot_path = "";
}

//+------------------------------------------------------------------+
//| The Simulated Coroutine (Called in OnTimer every 500ms)          |
//+------------------------------------------------------------------+
void CAsyncWebhook::ProcessTimer()
{
    if(ArraySize(m_queue) == 0) return; // Nothing to do

    switch(m_current_state)
    {
        case STATE_IDLE:
            // We have an item, start processing it
            m_current_state = STATE_TAKE_SCREENSHOT;
            break;
            
        case STATE_TAKE_SCREENSHOT:
            if(TakeScreenshot(m_queue[0])) 
                m_current_state = STATE_WRITE_CSV;
            break;
            
        case STATE_WRITE_CSV:
            if(WriteToCSV(m_queue[0]))
                m_current_state = STATE_SEND_WEBHOOK;
            break;
            
        case STATE_SEND_WEBHOOK:
            if(FireWebhook(m_queue[0]))
            {
                // Finished processing this item. Remove from queue.
                ArrayRemove(m_queue, 0, 1);
                m_current_state = STATE_IDLE;
            }
            break;
    }
}

//+------------------------------------------------------------------+
//| Action Implementations                                           |
//+------------------------------------------------------------------+
bool CAsyncWebhook::TakeScreenshot(SJournalPayload &payload)
{
    // Only take screenshots for Entry (Event 1)
    if(payload.event_type != EV_OPEN_ENTRY) return true; 
    
    string filename = "Journaling\\" + IntegerToString(payload.ticket) + ".gif";
    if(ChartScreenShot(0, filename, 800, 600, ALIGN_RIGHT))
    {
        payload.screenshot_path = filename;
        return true;
    }
    return false;
}

bool CAsyncWebhook::WriteToCSV(SJournalPayload &payload)
{
    // Implementation for FileOpen(), FileWrite(), FileClose()
    Print("CSV Written for Ticket: ", payload.ticket);
    return true; // Proceed to next state
}

bool CAsyncWebhook::FireWebhook(SJournalPayload &payload)
{
    // MQL5 WebRequest implementation here to n8n
    // Construct JSON based on payload.event_type
    Print("Webhook Fired for Event: ", EnumToString(payload.event_type));
    return true; 
}