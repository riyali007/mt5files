// partial_level.mqh
#include <Object.mqh>

class CPartialLevel : public CObject {
private:
    double m_price;
    double m_volume;
    bool   m_is_taken;

public:
    CPartialLevel(double price, double volume) {
        m_price = price;
        m_volume = volume;
        m_is_taken = false;
    }
    
    double Price() const     { return m_price; }
    double Volume() const    { return m_volume; }
    bool   IsTaken() const   { return m_is_taken; }
    
    void   MarkAsTaken()     { m_is_taken = true; }
    void   UpdatePrice(double new_price) { m_price = new_price; }
};