//+------------------------------------------------------------------+
//| news-calendar.mq5                                                |
//| Copyright 2026, Carlos Oliveira                                  |
//| https://www.forextradingtools.eu                                 |
//|                                                                  |
//| Displays an economic-calendar panel and vertical event lines    |
//| on the chart, powered by the MT5 built-in calendar API.         |
//+------------------------------------------------------------------+
#property copyright "2026, Carlos Oliveira"
#property link      "https://www.forextradingtools.eu"
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 0

#include "CNewsCalendar.mqh"

//--- Panel
input group "=== Panel ==="
input ENUM_BASE_CORNER InpCorner        = CORNER_LEFT_LOWER; // Corner
input int              InpOffsetX       = 10;                  // X offset (px)
input int              InpOffsetY       = 30;                  // Y offset (px)
input int              InpPanelRows     = 8;                   // Total panel rows
input int              InpPanelHistRows = 2;                   // Rows for past events

//--- Vertical lines
input group "=== Event Lines ==="
input int              InpUpcomingLines   = 5; // Upcoming event lines (X)
input int              InpHistoricalLines = 3; // Historical event lines (Y)

//--- Filter
input group "=== Filter ==="
input string           InpCurrencies   = "USD,EUR,GBP,JPY,AUD,CAD,CHF,NZD"; // Currencies (empty = all)
input ENUM_CALENDAR_EVENT_IMPORTANCE InpMinImportance = CALENDAR_IMPORTANCE_MODERATE; // Min importance

//--- Data
input group "=== Data ==="
input int              InpDaysBack    = 2; // Days back to load
input int              InpDaysForward = 7; // Days forward to load
input int              InpRefreshMins = 5; // Refresh interval (minutes)

//--- Colors
input group "=== Colors ==="
input color            InpColorHigh   = clrRed;                // High impact
input color            InpColorMedium = clrDarkOrange;         // Medium impact
input color            InpColorLow    = clrGold;               // Low impact
input color            InpPanelBg     = C'12,12,28';           // Panel background
input color            InpHeaderBg    = C'22,22,45';           // Header background
input color            InpTextColor   = C'220,220,230';        // Text color
input color            InpDimColor    = C'90,90,110';          // Dimmed / past text

//--- Appearance
input group "=== Appearance ==="
input string           InpFont                = "Courier New"; // Font (monospace recommended)
input int              InpFontSize            = 9;              // Font size
input bool             InpShowHeader          = true;           // Show header bar and columns
input bool             InpShowPanelBackground = true;           // Show panel background
input bool             InpShowEventLines      = true;           // Show event vertical lines

//--- Object name prefix (change to avoid collisions with multiple chart instances)
#define NC_PREFIX    "FXTT_NC_"
#define NC_VL_PREFIX "FXTT_NC_VL_"

//--- Panel layout constants (px)
#define NC_PANEL_MIN_W  302
#define NC_PAD_X      8
#define NC_PAD_Y      6
#define NC_TITLE_H   20
#define NC_HDR_H     16
#define NC_ROW_H     15
#define NC_SEP_H      1

//--- Globals
CNewsCalendar g_cal;

//+------------------------------------------------------------------+
int OnInit()
  {
   SNewsCalendarSettings s = NewsCalendarSettingsDefault();
   s.daysBack        = InpDaysBack;
   s.daysForward     = InpDaysForward;
   s.refreshSeconds  = InpRefreshMins * 60;
   s.currencies      = InpCurrencies;
   s.minImportance   = InpMinImportance;

   if(!g_cal.Init(s))
     {
      Alert("NewsCalendar: Init failed");
      return INIT_FAILED;
     }

   g_cal.Refresh(true);
   Redraw();
   EventSetTimer(60);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(reason == REASON_REMOVE || reason == REASON_CHARTCLOSE)
      ObjectsDeleteAll(0, NC_PREFIX);
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
  {
   if(prev_calculated == 0)
     {
      g_cal.Refresh(true);
      Redraw();
     }
   return rates_total;
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   if(g_cal.Refresh())
      Redraw();
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_CHART_CHANGE)
      Redraw();
  }

//=============================================================================
//  Color helpers
//=============================================================================

color ImpactColor(const ENUM_CALENDAR_EVENT_IMPORTANCE imp)
  {
   switch(imp)
     {
      case CALENDAR_IMPORTANCE_HIGH:     return InpColorHigh;
      case CALENDAR_IMPORTANCE_MODERATE: return InpColorMedium;
      case CALENDAR_IMPORTANCE_LOW:      return InpColorLow;
      default:                           return InpDimColor;
     }
  }

//--- Subtract 'amount' from each RGB channel (clamps to 0)
color ColorDarken(const color clr, const int amount)
  {
   int r = MathMax(0, (int)((clr >> 16) & 0xFF) - amount);
   int g = MathMax(0, (int)((clr >>  8) & 0xFF) - amount);
   int b = MathMax(0, (int)( clr        & 0xFF)  - amount);
   return (color)((r << 16) | (g << 8) | b);
  }

//=============================================================================
//  Format helpers
//=============================================================================

//--- "HH:MM" from datetime
string FmtTime(const datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return StringFormat("%02d:%02d", dt.hour, dt.min);
  }

//--- Signed relative offset from now: "+2h05m" / "-30m"
string FmtRelTime(const datetime t)
  {
   long diff = (long)t - (long)TimeCurrent();
   bool neg  = (diff < 0);
   if(neg) diff = -diff;
   int  h    = (int)(diff / 3600);
   int  m    = (int)((diff % 3600) / 60);
   if(h > 0) return StringFormat("%s%dh%02dm", neg ? "-" : "+", h, m);
   return StringFormat("%s%dm", neg ? "-" : "+", m);
  }

//--- Pad right with spaces or truncate to exactly n chars
string FixedW(const string s, const int n)
  {
   int len = StringLen(s);
   if(len >= n) return StringSubstr(s, 0, n);
   string r = s;
   for(int i = len; i < n; i++) r += " ";
   return r;
  }

//--- Truncate and append ".." if over maxChars
string Trunc(const string s, const int maxChars)
  {
   if(StringLen(s) <= maxChars) return s;
   return StringSubstr(s, 0, maxChars - 2) + "..";
  }

//=============================================================================
//  Chart object primitives
//=============================================================================

void SetRectLabel(const string name,
                  const int x, const int y, const int w, const int h,
                  const color bg, const color border)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE,  false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,       true);
      ObjectSetInteger(0, name, OBJPROP_BACK,         false);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE,  BORDER_FLAT);
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,     w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,     h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,   bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     border);
   ObjectSetInteger(0, name, OBJPROP_CORNER,    InpCorner);
  }

void SetLabel(const string name,
              const int x, const int y,
              const string text, const color clr,
              const string font = "", const int fontSize = 0)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR,    ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, name, OBJPROP_BACK,       false);
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString (0, name, OBJPROP_TEXT,      text);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetString (0, name, OBJPROP_FONT,      font == "" ? InpFont : font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  fontSize == 0 ? InpFontSize : fontSize);
   ObjectSetInteger(0, name, OBJPROP_CORNER,    InpCorner);
  }

void SetVLine(const string name,
              const datetime t, const color clr,
              const ENUM_LINE_STYLE style, const string tooltip)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_VLINE, 0, t, 0);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, name, OBJPROP_BACK,       true);
      ObjectSetInteger(0, name, OBJPROP_WIDTH,       1);
     }
   ObjectSetInteger(0, name, OBJPROP_TIME,    t);
   ObjectSetInteger(0, name, OBJPROP_COLOR,   clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE,   style);
   ObjectSetString (0, name, OBJPROP_TOOLTIP, tooltip);
  }

//=============================================================================
//  Corner-aware coordinate helpers
//
//  All panel elements use panel-local coords (localX/localY from panel top-left).
//
//  OBJPROP_CORNER only changes which chart edge XDISTANCE/YDISTANCE are
//  measured from — it does NOT change the anchor corner of the object.
//  Both OBJ_RECTANGLE_LABEL and OBJ_LABEL (ANCHOR_LEFT_UPPER) always anchor
//  at the top-left of the object in screen space; XSIZE/YSIZE always extend
//  rightward and downward regardless of corner.
//
//  CoordX / CoordY handle this uniformly for both object types:
//    Right corners : XDISTANCE measured from chart right  → add panel width
//    Lower corners : YDISTANCE measured from chart bottom → add panel height
//=============================================================================

bool IsRightCorner() { return InpCorner == CORNER_RIGHT_UPPER || InpCorner == CORNER_RIGHT_LOWER; }
bool IsLowerCorner() { return InpCorner == CORNER_LEFT_LOWER  || InpCorner == CORNER_RIGHT_LOWER; }

//--- Converts a panel-local X (px from panel left edge) to XDISTANCE
int CoordX(const int localX, const int panelW)
  {
   return IsRightCorner() ? InpOffsetX + panelW - localX
                          : InpOffsetX + localX;
  }

//--- Converts a panel-local Y (px from panel top edge) to YDISTANCE
int CoordY(const int localY, const int panelH)
  {
   return IsLowerCorner() ? InpOffsetY + panelH - localY
                          : InpOffsetY + localY;
  }

//=============================================================================
//  Panel drawing
//=============================================================================

bool MeasureTextWidth(const string text,
                      const string font,
                      const int fontSize,
                      int &width)
  {
   width = 0;
   uint textW = 0;
   uint textH = 0;
   if(!TextSetFont(font, fontSize * -10))
      return false;
   if(!TextGetSize(text, textW, textH))
      return false;
   width = (int)textW;
   return true;
  }

string BuildPanelRowText(const SNewsItem &it)
  {
   return FixedW(FmtTime(it.time), 5) + "  " +
          FixedW(it.currency, 3) + "  " +
          FixedW(NewsImpactLabel(it.importance), 1) + "  " +
          it.title;
  }

int CalcPanelWidth(const SNewsItem &hist[], const int histRows,
                   const SNewsItem &up[], const int upRows)
  {
   int maxTextW = 0;
   int textW    = 0;

   if(MeasureTextWidth("NEWS CALENDAR", "Arial Bold", 9, textW))
      maxTextW = MathMax(maxTextW, textW);

   string hdrText = FixedW("TIME", 5) + "  " + FixedW("CCY", 3) + "  " +
                    FixedW("I", 1) + "  " + "TITLE";
   if(MeasureTextWidth(hdrText, InpFont, InpFontSize, textW))
      maxTextW = MathMax(maxTextW, textW);

   for(int i = histRows - 1; i >= 0; i--)
     {
      if(MeasureTextWidth(BuildPanelRowText(hist[i]), InpFont, InpFontSize, textW))
         maxTextW = MathMax(maxTextW, textW);
     }

   for(int i = 0; i < upRows; i++)
     {
      if(MeasureTextWidth(BuildPanelRowText(up[i]), InpFont, InpFontSize, textW))
         maxTextW = MathMax(maxTextW, textW);
     }

   return MathMax(NC_PANEL_MIN_W, maxTextW + NC_PAD_X * 2);
  }

void DrawPanel(const SNewsItem &hist[], int nHist, const SNewsItem &up[], int nUp)
  {
   //--- Clamp to requested row counts
   int histRows  = MathMin(nHist, InpPanelHistRows);
   int upRows    = MathMin(nUp,   InpPanelRows - histRows);
   int totalRows = histRows + upRows;
   int panelW    = CalcPanelWidth(hist, histRows, up, upRows);

   //--- Header height (only if shown)
   int headerH = InpShowHeader ? (NC_TITLE_H + NC_HDR_H + NC_SEP_H) : 0;

   //--- Total panel height (needed by all Y helpers)
   int panelH = headerH + totalRows * NC_ROW_H + NC_PAD_Y * 2;

   //--- Panel-local Y anchors for each section (measured from panel top)
   const int lyTitle  = 0;                                     // title bar top
   const int lyHdr    = NC_TITLE_H;                            // header row top
   const int lySep    = NC_TITLE_H + NC_HDR_H;                 // separator top
   const int lyBase   = headerH;                               // first data row top

   //--- Background (only if enabled)
   if(InpShowPanelBackground)
     {
      SetRectLabel(NC_PREFIX + "PNL_BG",
                   CoordX(0, panelW), CoordY(0, panelH),
                   panelW, panelH,
                   InpPanelBg, C'35,35,60');
     }
   else
     {
      string bgName = NC_PREFIX + "PNL_BG";
      if(ObjectFind(0, bgName) >= 0)
         ObjectDelete(0, bgName);
     }

   //--- Header section (only if enabled)
   if(InpShowHeader)
     {
      //--- Title bar background
      SetRectLabel(NC_PREFIX + "PNL_TITLE_BG",
                   CoordX(0, panelW), CoordY(lyTitle, panelH),
                   panelW, NC_TITLE_H,
                   C'25,25,55', C'35,35,60');

      //--- Title text (vertically centred inside title bar)
      SetLabel(NC_PREFIX + "PNL_TITLE",
               CoordX(NC_PAD_X, panelW), CoordY(lyTitle + 4, panelH),
               "NEWS CALENDAR", InpTextColor, "Arial Bold", 9);

      //--- Header row background
      SetRectLabel(NC_PREFIX + "PNL_HDR_BG",
                   CoordX(0, panelW), CoordY(lyHdr, panelH),
                   panelW, NC_HDR_H,
                   InpHeaderBg, C'35,35,60');

      //--- Column header text
      string hdrText = FixedW("TIME", 5) + "  " + FixedW("CCY", 3) + "  " +
                       FixedW("I", 1) + "  " + "TITLE";
      SetLabel(NC_PREFIX + "PNL_HDR",
               CoordX(NC_PAD_X, panelW), CoordY(lyHdr + 2, panelH),
               hdrText, InpDimColor);

      //--- 1px separator
      SetRectLabel(NC_PREFIX + "PNL_SEP",
                   CoordX(0, panelW), CoordY(lySep, panelH),
                   panelW, NC_SEP_H,
                   C'35,35,60', C'35,35,60');
     }
   else
     {
      //--- Delete header objects when disabled
      ObjectDelete(0, NC_PREFIX + "PNL_TITLE_BG");
      ObjectDelete(0, NC_PREFIX + "PNL_TITLE");
      ObjectDelete(0, NC_PREFIX + "PNL_HDR_BG");
      ObjectDelete(0, NC_PREFIX + "PNL_HDR");
      ObjectDelete(0, NC_PREFIX + "PNL_SEP");
     }

   //--- Data rows: historical first (GetHistorical returns newest-first, so
   //    reverse to display oldest-first at the top), then upcoming
   int row = 0;

   for(int i = histRows - 1; i >= 0; i--, row++)
     {
      SNewsItem it     = hist[i];
      string    rowTxt = BuildPanelRowText(it);
      SetLabel(NC_PREFIX + "PNL_R" + IntegerToString(row),
               CoordX(NC_PAD_X, panelW), CoordY(lyBase + row * NC_ROW_H + 2, panelH),
               rowTxt, InpDimColor);
     }

   for(int i = 0; i < upRows; i++, row++)
     {
      SNewsItem it     = up[i];
      string    rowTxt = BuildPanelRowText(it);
      SetLabel(NC_PREFIX + "PNL_R" + IntegerToString(row),
               CoordX(NC_PAD_X, panelW), CoordY(lyBase + row * NC_ROW_H + 2, panelH),
               rowTxt, ImpactColor(it.importance));
     }

   //--- Blank out rows left over from a previous draw with more items
   for(int i = row; i < InpPanelRows + InpPanelHistRows + 2; i++)
     {
      string name = NC_PREFIX + "PNL_R" + IntegerToString(i);
      if(ObjectFind(0, name) >= 0)
         ObjectSetString(0, name, OBJPROP_TEXT, "");
     }
  }

//=============================================================================
//  Vertical lines
//=============================================================================

void DrawVLines(const SNewsItem &up[], int nUp, const SNewsItem &hist[], int nHist)
  {
   //--- Delete all existing VLINEs so stale ones don't persist
   ObjectsDeleteAll(0, NC_VL_PREFIX);

   //--- If event lines are disabled, skip drawing
   if(!InpShowEventLines)
      return;

   //--- Upcoming: solid line, full impact color
   for(int i = 0; i < nUp; i++)
     {
      string name    = NC_VL_PREFIX + "UP_" + IntegerToString(i);
      string tooltip = FmtRelTime(up[i].time) + "  " +
                       up[i].currency + "  [" + NewsImpactLabel(up[i].importance) + "]  " +
                       up[i].title;
      SetVLine(name, up[i].time, ImpactColor(up[i].importance), STYLE_DASH, tooltip);
     }

   //--- Historical: dotted line, same dim color as past rows in the panel
   for(int i = 0; i < nHist; i++)
     {
      string name    = NC_VL_PREFIX + "HIS_" + IntegerToString(i);
      string tooltip = FmtRelTime(hist[i].time) + "  " +
                       hist[i].currency + "  [" + NewsImpactLabel(hist[i].importance) + "]  " +
                       hist[i].title;
      SetVLine(name, hist[i].time, InpDimColor, STYLE_DOT, tooltip);
     }
  }

//=============================================================================
//  Redraw — full repaint
//=============================================================================

void Redraw()
  {
   datetime now = TimeCurrent();

   SNewsItem upcoming[], historical[];
   int nUp   = g_cal.GetUpcoming  (upcoming,   now, InpUpcomingLines);
   int nHist = g_cal.GetHistorical(historical, now, InpHistoricalLines);

   //--- Panel needs a wider upcoming slice (panel rows > VLine count possible)
   SNewsItem panelUp[];
   int panelUpMax = MathMax(InpPanelRows - InpPanelHistRows, 0);
   int nPanelUp   = g_cal.GetUpcoming(panelUp, now, panelUpMax);

   SNewsItem panelHist[];
   int nPanelHist = g_cal.GetHistorical(panelHist, now, InpPanelHistRows);

   DrawPanel(panelHist, nPanelHist, panelUp, nPanelUp);
   DrawVLines(upcoming, nUp, historical, nHist);
   ChartRedraw(0);
  }
