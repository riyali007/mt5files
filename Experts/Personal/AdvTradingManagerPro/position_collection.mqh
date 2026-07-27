// position_collection.mqh
#include <Object.mqh>
#include <Arrays\ArrayObj.mqh>
#include "managed_position.mqh"

class CPositionCollection {
private:
    CArrayObj m_list;

public:
    CPositionCollection() {}
    ~CPositionCollection() { m_list.Clear(); }

    void AddPosition(CManagedPosition* pos) {
        m_list.Add(pos);
    }

    CManagedPosition* FindByTicket(ulong ticket) {
        for(int i = 0; i < m_list.Total(); i++) {
            CManagedPosition* pos = m_list.At(i);
            if(pos != NULL && pos.Ticket() == ticket)
                return pos;
        }
        return NULL;
    }
     CManagedPosition* GetByIndex(int index) {
        if(index >= 0 && index < m_list.Total()) {
            return (CManagedPosition*)m_list.At(index);
        }
        return NULL;
    }
    bool DeleteByTicket(ulong ticket) {
        for(int i = 0; i < m_list.Total(); i++) {
            CManagedPosition* pos = m_list.At(i);
            if(pos != NULL && pos.Ticket() == ticket) {
                return m_list.Delete(i); // Deletes object and safely resizes array
            }
        }
        return false;
    }

    int Total() const { return m_list.Total(); }
};