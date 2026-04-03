//+------------------------------------------------------------------+
//| CNewsCalendar.mqh                                                |
//| Copyright 2026, Carlos Oliveira                                  |
//| https://www.forextradingtools.eu                                 |
//|                                                                  |
//| Reusable MT5 economic-calendar engine.                          |
//| Fetches, caches and queries broker calendar data via the        |
//| built-in CalendarValueHistory / CalendarEventById API.          |
//|                                                                  |
//| Minimal usage in another indicator:                              |
//|   #include "CNewsCalendar.mqh"               |
//|   CNewsCalendar g_cal;                                          |
//|   int OnInit() {                                                 |
//|      SNewsCalendarSettings s = NewsCalendarSettingsDefault();   |
//|      s.currencies = "USD,EUR";                                  |
//|      return g_cal.Init(s) ? INIT_SUCCEEDED : INIT_FAILED; }    |
//|   void OnTimer() { g_cal.Refresh(); }                           |
//|   // Consume:                                                    |
//|   SNewsItem upcoming[]; g_cal.GetUpcoming(upcoming,now,5);     |
//+------------------------------------------------------------------+
#ifndef __FXTT_CNEWSCALENDAR_MQH__
#define __FXTT_CNEWSCALENDAR_MQH__

//+------------------------------------------------------------------+
//| One economic-calendar event                                      |
//+------------------------------------------------------------------+
struct SNewsItem
  {
   datetime                       time;
   string                         currency;
   string                         title;
   ENUM_CALENDAR_EVENT_IMPORTANCE importance;
  };

//+------------------------------------------------------------------+
//| Settings — populate and pass to CNewsCalendar::Init()           |
//+------------------------------------------------------------------+
struct SNewsCalendarSettings
  {
   int    daysBack;       // History window (days before now)  default 2
   int    daysForward;    // Future  window (days after  now)  default 7
   int    refreshSeconds; // Cache TTL in seconds              default 300
   string currencies;     // Comma-sep filter "USD,EUR" — empty = all
   ENUM_CALENDAR_EVENT_IMPORTANCE minImportance; // Skip events below this
  };

//--- Convenience factory: all defaults applied
SNewsCalendarSettings NewsCalendarSettingsDefault()
  {
   SNewsCalendarSettings s;
   s.daysBack        = 2;
   s.daysForward     = 7;
   s.refreshSeconds  = 300;
   s.currencies      = "USD,EUR,GBP,JPY,AUD,CAD,CHF,NZD";
   s.minImportance   = CALENDAR_IMPORTANCE_MODERATE;
   return s;
  }

//--- Single-char impact label ("H" / "M" / "L" / "-")
string NewsImpactLabel(const ENUM_CALENDAR_EVENT_IMPORTANCE imp)
  {
   switch(imp)
     {
      case CALENDAR_IMPORTANCE_HIGH:     return "H";
      case CALENDAR_IMPORTANCE_MODERATE: return "M";
      case CALENDAR_IMPORTANCE_LOW:      return "L";
      default:                           return "-";
     }
  }

//--- Three-dot impact indicator ("●●●" / "●●○" / "●○○" / "○○○")
string NewsImpactDots(const ENUM_CALENDAR_EVENT_IMPORTANCE imp)
  {
   switch(imp)
     {
      case CALENDAR_IMPORTANCE_HIGH:     return "●●●";
      case CALENDAR_IMPORTANCE_MODERATE: return "●●○";
      case CALENDAR_IMPORTANCE_LOW:      return "●○○";
      default:                           return "○○○";
     }
  }

//+------------------------------------------------------------------+
//| CNewsCalendar                                                    |
//| Fetch, cache and query MT5 economic calendar data.              |
//+------------------------------------------------------------------+
class CNewsCalendar
  {
private:
   SNewsCalendarSettings m_s;
   SNewsItem             m_items[];
   int                   m_count;
   datetime              m_lastRefresh;

   //--- Parsed currency filter
   string                m_filterCcy[];
   int                   m_filterCount;

   void     ParseCurrencyFilter();
   bool     PassesCurrencyFilter(const string &ccy) const;
   bool     PassesImportanceFilter(ENUM_CALENDAR_EVENT_IMPORTANCE imp) const;
   void     SortByTime();   // insertion sort — array is typically < 300 items

public:
            CNewsCalendar();

   //--- Call once from OnInit. Returns false only on internal error.
   bool     Init(const SNewsCalendarSettings &settings);

   //--- Reload data if stale (or force=true).
   //    Returns true when a reload actually happened.
   bool     Refresh(bool force = false);

   bool     IsStale()  const;
   int      Total()    const { return m_count; }

   //--- Access item by index (0-based).  Returns false if out of range.
   bool     Get(int index, SNewsItem &item) const;

   //--- Fill items[] with up to maxCount upcoming events (time >= from),
   //    chronologically ordered.  Returns count written.
   int      GetUpcoming(SNewsItem &items[], datetime from, int maxCount) const;

   //--- Fill items[] with up to maxCount historical events (time < to),
   //    most-recent first.  Returns count written.
   int      GetHistorical(SNewsItem &items[], datetime to, int maxCount) const;
  };

//+------------------------------------------------------------------+
CNewsCalendar::CNewsCalendar()
   : m_count(0), m_lastRefresh(0), m_filterCount(0) {}

//+------------------------------------------------------------------+
bool CNewsCalendar::Init(const SNewsCalendarSettings &settings)
  {
   m_s           = settings;
   m_count       = 0;
   m_lastRefresh = 0;
   ParseCurrencyFilter();
   return true;
  }

//+------------------------------------------------------------------+
void CNewsCalendar::ParseCurrencyFilter()
  {
   m_filterCount = 0;
   ArrayResize(m_filterCcy, 0);
   if(StringLen(m_s.currencies) == 0) return;

   string parts[];
   int n = StringSplit(m_s.currencies, ',', parts);
   ArrayResize(m_filterCcy, n);
   for(int i = 0; i < n; i++)
     {
      StringTrimLeft(parts[i]);
      StringTrimRight(parts[i]);
      StringToUpper(parts[i]);
      if(StringLen(parts[i]) > 0)
         m_filterCcy[m_filterCount++] = parts[i];
     }
   ArrayResize(m_filterCcy, m_filterCount);
  }

//+------------------------------------------------------------------+
bool CNewsCalendar::PassesCurrencyFilter(const string &ccy) const
  {
   if(m_filterCount == 0) return true;
   string upper = ccy;
   StringToUpper(upper);
   for(int i = 0; i < m_filterCount; i++)
      if(m_filterCcy[i] == upper) return true;
   return false;
  }

//+------------------------------------------------------------------+
bool CNewsCalendar::PassesImportanceFilter(ENUM_CALENDAR_EVENT_IMPORTANCE imp) const
  {
   return (imp != CALENDAR_IMPORTANCE_NONE && (int)imp >= (int)m_s.minImportance);
  }

//+------------------------------------------------------------------+
void CNewsCalendar::SortByTime()
  {
   for(int i = 1; i < m_count; i++)
     {
      SNewsItem key = m_items[i];
      int j = i - 1;
      while(j >= 0 && m_items[j].time > key.time)
        {
         m_items[j + 1] = m_items[j];
         j--;
        }
      m_items[j + 1] = key;
     }
  }

//+------------------------------------------------------------------+
bool CNewsCalendar::IsStale() const
  {
   return (TimeCurrent() - m_lastRefresh) >= (datetime)m_s.refreshSeconds;
  }

//+------------------------------------------------------------------+
bool CNewsCalendar::Refresh(bool force)
  {
   if(!force && !IsStale()) return false;

   datetime from = TimeCurrent() - (datetime)((long)m_s.daysBack    * 86400);
   datetime to   = TimeCurrent() + (datetime)((long)m_s.daysForward * 86400);

   MqlCalendarValue raw[];
   if(!CalendarValueHistory(raw, from, to))
     {
      Print("CNewsCalendar::Refresh — CalendarValueHistory failed, err=", GetLastError());
      //--- Mark as refreshed anyway to avoid hammering the API on every tick
      m_lastRefresh = TimeCurrent();
      return false;
     }

   int rawCount = ArraySize(raw);
   ArrayResize(m_items, rawCount);
   m_count = 0;

   for(int i = 0; i < rawCount; i++)
     {
      MqlCalendarEvent ev;
      if(!CalendarEventById(raw[i].event_id, ev))   continue;
      if(!PassesImportanceFilter(ev.importance))     continue;

      MqlCalendarCountry co;
      if(!CalendarCountryById(ev.country_id, co))   continue;
      if(!PassesCurrencyFilter(co.currency))         continue;

      m_items[m_count].time       = raw[i].time;
      m_items[m_count].currency   = co.currency;
      m_items[m_count].title      = ev.name;
      m_items[m_count].importance = ev.importance;
      m_count++;
     }

   ArrayResize(m_items, m_count);
   SortByTime();
   m_lastRefresh = TimeCurrent();
   return true;
  }

//+------------------------------------------------------------------+
bool CNewsCalendar::Get(int index, SNewsItem &item) const
  {
   if(index < 0 || index >= m_count) return false;
   item = m_items[index];
   return true;
  }

//+------------------------------------------------------------------+
int CNewsCalendar::GetUpcoming(SNewsItem &items[], datetime from, int maxCount) const
  {
   ArrayResize(items, 0);
   int added = 0;
   for(int i = 0; i < m_count && added < maxCount; i++)
      if(m_items[i].time >= from)
        {
         ArrayResize(items, added + 1);
         items[added++] = m_items[i];
        }
   return added;
  }

//+------------------------------------------------------------------+
int CNewsCalendar::GetHistorical(SNewsItem &items[], datetime to, int maxCount) const
  {
   ArrayResize(items, 0);
   int added = 0;
   for(int i = m_count - 1; i >= 0 && added < maxCount; i--)
      if(m_items[i].time < to)
        {
         ArrayResize(items, added + 1);
         items[added++] = m_items[i];
        }
   return added;
  }

#endif // __FXTT_CNEWSCALENDAR_MQH__
