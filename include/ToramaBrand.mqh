//+------------------------------------------------------------------+
//|                                                    ToramaBrand   |
//|                        MT5 include to brand charts for EAs       |
//| Draws bottom-right label: "(c) TORAMA CAPITAL" in red with       |
//| subtext "Algorithmic Solutions". Uses heavy font + shadow.       |
//+------------------------------------------------------------------+
#ifndef __TORAMA_BRAND_MQH__
#define __TORAMA_BRAND_MQH__

namespace ToramaBranding
{
   // Object names (per-chart)
   const string BRAND_TITLE      = "TORAMA_BRAND_TITLE";
   const string BRAND_TITLE_SH  = "TORAMA_BRAND_TITLE_SHADOW";
   const string BRAND_SUB       = "TORAMA_BRAND_SUB";

   // Internal helper: create/update a label
   bool CreateOrUpdateLabel(
      const long               chart_id,
      const string             name,
      const string             text,
      const string             font_name,
      const int                font_size,
      const color              col,
      const ENUM_BASE_CORNER   corner,
      const ENUM_ANCHOR_POINT  anchor,
      const int                x_pixels,
      const int                y_pixels
   )
   {
      if(ObjectFind(chart_id, name) < 0)
      {
         if(!ObjectCreate(chart_id, name, OBJ_LABEL, 0, 0, 0))
            return(false);
      }

      ObjectSetString (chart_id, name, OBJPROP_TEXT,       text);
      ObjectSetString (chart_id, name, OBJPROP_FONT,       font_name);
      ObjectSetInteger(chart_id, name, OBJPROP_FONTSIZE,   font_size);
      ObjectSetInteger(chart_id, name, OBJPROP_COLOR,      col);
      ObjectSetInteger(chart_id, name, OBJPROP_CORNER,     corner);
      ObjectSetInteger(chart_id, name, OBJPROP_ANCHOR,     anchor);
      ObjectSetInteger(chart_id, name, OBJPROP_XDISTANCE,  x_pixels);
      ObjectSetInteger(chart_id, name, OBJPROP_YDISTANCE,  y_pixels);
      ObjectSetInteger(chart_id, name, OBJPROP_BACK,       false);
      ObjectSetInteger(chart_id, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(chart_id, name, OBJPROP_HIDDEN,     true);

      return(true);
   }

   // Draw brand (call in OnInit and on chart changes)
   bool DrawBrand(
      const long  chart_id       = 0,
      const int   right_margin   = 12,   // distance from right edge (px)
      const int   bottom_margin  = 10,   // distance from bottom edge for subtitle
      const string title_text    = "© TORAMA CAPITAL",
      const string sub_text      = "Algorithmic Solutions",
      const int   title_size     = 16,
      const int   sub_size       = 12,
      const color title_color    = clrRed,
      const color sub_color      = clrSilver,
      const string title_font    = "Arial Black",       // heavy font for bold effect
      const string subtitle_font = "Segoe UI"           // clean subtitle font
   )
   {
      // Positions (relative to bottom-right)
      const int sh_offset = 1;                // 1px shadow offset
      const int padding   = 5;                // gap between lines
      const int y_sub     = bottom_margin;    // subtitle sits closest to the bottom
      const int y_title   = bottom_margin + sub_size + padding;

      // Shadow behind title (darker, slight offset)
      bool ok_title_sh = CreateOrUpdateLabel(
         chart_id, BRAND_TITLE_SH, title_text, title_font, title_size,
         (color)C'40,0,0',  // very dark red shadow
         CORNER_RIGHT_LOWER, ANCHOR_RIGHT_LOWER,
         right_margin - sh_offset, y_title + sh_offset
      );

      // Main title
      bool ok_title = CreateOrUpdateLabel(
         chart_id, BRAND_TITLE, title_text, title_font, title_size,
         title_color,
         CORNER_RIGHT_LOWER, ANCHOR_RIGHT_LOWER,
         right_margin, y_title
      );

      // Subtitle
      bool ok_sub = CreateOrUpdateLabel(
         chart_id, BRAND_SUB, sub_text, subtitle_font, sub_size,
         sub_color,
         CORNER_RIGHT_LOWER, ANCHOR_RIGHT_LOWER,
         right_margin, y_sub
      );

      return(ok_title && ok_title_sh && ok_sub);
   }

   // Remove brand (call in OnDeinit)
   void RemoveBrand(const long chart_id = 0)
   {
      ObjectDelete(chart_id, BRAND_TITLE);
      ObjectDelete(chart_id, BRAND_TITLE_SH);
      ObjectDelete(chart_id, BRAND_SUB);
      
   }

   // Re-draw on chart size/theme change
   void HandleChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
   {
      if(id == CHARTEVENT_CHART_CHANGE)
         DrawBrand();
   }
}

#endif // __TORAMA_BRAND_MQH__