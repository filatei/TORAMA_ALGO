//+------------------------------------------------------------------+
//| Torama Breakout Momentum Strategy                                |
//| Filename: Torama_Breakout_Momentum.mq5                           |
//+------------------------------------------------------------------+
#property copyright "Torama Capital"
#property version   "1.18"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//--- inputs
input int    xbars = 20;
input double lotSize = 0.10;
input int    MagicNumber = 20250920;
input int    ATRperiod = 14;
input double ATRmultiplierSL = 2.0;
input double ATRmultiplierTP = 3.0;
input ENUM_TIMEFRAMES ATRtf = PERIOD_CURRENT;
input double GlobalMaxDrawdown = 5.0;
input double GlobalMaxProfit   = 10.0;

//--- ATR
int atrHandle;
double atrBuffer[];

//--- globals
double startingBalance = 0;
bool tradingAllowed = true;

//--- object names
string PANEL_BG    = "EA_BG";
string PANEL_TITLE = "EA_Title";
string PANEL_LINE  = "EA_Line_";
string BTN_TOGGLE  = "EA_Toggle";
string BTN_CLOSE   = "EA_CloseAll";
string BRANDING    = "EA_Branding";

//+------------------------------------------------------------------+
int OnInit()
{
   atrHandle = iATR(_Symbol, ATRtf, ATRperiod);
   if(atrHandle == INVALID_HANDLE) 
   { 
      Print("❌ ATR init error: ", GetLastError()); 
      return INIT_FAILED; 
   }

   ArraySetAsSeries(atrBuffer, true);
   
   trade.SetExpertMagicNumber(MagicNumber);
   
   startingBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   tradingAllowed  = true;

   CreatePanel();
   CreateBranding();
   UpdatePanel();

   Print("✅ EA Initialized. Start Balance = ", startingBalance);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(atrHandle != INVALID_HANDLE) 
      IndicatorRelease(atrHandle);

   // Delete all panel objects
   ObjectDelete(0, PANEL_BG);
   ObjectDelete(0, PANEL_TITLE);
   for(int i = 0; i < 30; i++)
      ObjectDelete(0, PANEL_LINE + IntegerToString(i));
   ObjectDelete(0, BTN_TOGGLE);
   ObjectDelete(0, BTN_CLOSE);
   ObjectDelete(0, BRANDING);
}

//+------------------------------------------------------------------+
void OnTick()
{
   static datetime lastBarTime = 0;

   CheckGlobalRisk();
   UpdatePanel();

   if(!tradingAllowed) 
      return;

   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime == lastBarTime) 
      return;
   lastBarTime = currentBarTime;

   if(CopyBuffer(atrHandle, 0, 0, 2, atrBuffer) <= 0) 
      return;
   double atr = atrBuffer[0]; 
   if(atr <= 0) 
      return;

   bool longEntry = CheckLongConditions();
   bool shortEntry = CheckShortConditions();

   bool havePosition = PositionSelect(_Symbol);
   long posType = havePosition ? PositionGetInteger(POSITION_TYPE) : -1;

   if(longEntry)
   {
      if(havePosition && posType == POSITION_TYPE_SELL) 
         trade.PositionClose(_Symbol);
      if(!havePosition || posType == POSITION_TYPE_SELL)
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl = ask - atr * ATRmultiplierSL;
         double tp = ask + atr * ATRmultiplierTP;
         if(!trade.Buy(lotSize, _Symbol, ask, sl, tp, "Long entry"))
            Print("❌ Buy failed: ", trade.ResultRetcodeDescription());
      }
   }

   if(shortEntry)
   {
      if(havePosition && posType == POSITION_TYPE_BUY) 
         trade.PositionClose(_Symbol);
      if(!havePosition || posType == POSITION_TYPE_BUY)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl = bid + atr * ATRmultiplierSL;
         double tp = bid - atr * ATRmultiplierTP;
         if(!trade.Sell(lotSize, _Symbol, bid, sl, tp, "Short entry"))
            Print("❌ Sell failed: ", trade.ResultRetcodeDescription());
      }
   }

   ManageTrailingStops(atr);
}

//+------------------------------------------------------------------+
void ManageTrailingStops(double atr)
{
   if(!PositionSelect(_Symbol)) 
      return;

   long posType = PositionGetInteger(POSITION_TYPE);
   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl = PositionGetDouble(POSITION_SL);
   double tp = PositionGetDouble(POSITION_TP);
   double price = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                  : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double newSL = sl;
   double newTP = tp;
   
   if(posType == POSITION_TYPE_BUY)
   {
      if(price - entry >= atr) 
         newSL = MathMax(sl, price - atr * ATRmultiplierSL);
      newTP = price + atr * ATRmultiplierTP;
   }
   else if(posType == POSITION_TYPE_SELL)
   {
      if(entry - price >= atr) 
         newSL = (sl == 0) ? (price + atr * ATRmultiplierSL) : MathMin(sl, price + atr * ATRmultiplierSL);
      newTP = price - atr * ATRmultiplierTP;
   }

   if((MathAbs(newSL - sl) > _Point) || (MathAbs(newTP - tp) > _Point))
   {
      if(!trade.PositionModify(_Symbol, newSL, newTP))
         Print("❌ Modify failed: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
void CheckGlobalRisk()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(startingBalance <= 0) 
      return;

   double dd = ((startingBalance - equity) / startingBalance) * 100.0;
   double profit = ((equity - startingBalance) / startingBalance) * 100.0;

   if(dd >= GlobalMaxDrawdown)
   {
      Print("⚠️ Max DD hit: ", DoubleToString(dd, 2), "%");
      CloseAllPositions();
      tradingAllowed = false;
   }
   else if(profit >= GlobalMaxProfit)
   {
      Print("✅ Profit target hit: ", DoubleToString(profit, 2), "%");
      CloseAllPositions();
      tradingAllowed = false;
   }
}

//+------------------------------------------------------------------+
void CloseAllPositions()
{
   int totalPos = PositionsTotal();
   
   for(int i = totalPos - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) > 0)
      {
         ulong posTicket = PositionGetInteger(POSITION_TICKET);
         trade.PositionClose(posTicket);
      }
   }
}

//+------------------------------------------------------------------+
bool CheckLongConditions()
{
   double c0 = iClose(_Symbol, PERIOD_CURRENT, 0);
   double c1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double c2 = iClose(_Symbol, PERIOD_CURRENT, 2);
   double c3 = iClose(_Symbol, PERIOD_CURRENT, 3);
   double high = iHigh(_Symbol, PERIOD_CURRENT, iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, xbars, 1));
   
   return (c0 > high && c0 > c1 && c0 > c3 && c1 > c2);
}

//+------------------------------------------------------------------+
bool CheckShortConditions()
{
   double c0 = iClose(_Symbol, PERIOD_CURRENT, 0);
   double c1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double c2 = iClose(_Symbol, PERIOD_CURRENT, 2);
   double c3 = iClose(_Symbol, PERIOD_CURRENT, 3);
   double low = iLow(_Symbol, PERIOD_CURRENT, iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, xbars, 1));
   
   return (c0 < low && c0 < c1 && c0 < c3 && c1 < c2);
}

//+------------------------------------------------------------------+
string GetTimeframeName()
{
   string tf = "";
   switch(PERIOD_CURRENT)
   {
      case PERIOD_M1:  tf = "M1"; break;
      case PERIOD_M5:  tf = "M5"; break;
      case PERIOD_M15: tf = "M15"; break;
      case PERIOD_M30: tf = "M30"; break;
      case PERIOD_H1:  tf = "H1"; break;
      case PERIOD_H4:  tf = "H4"; break;
      case PERIOD_D1:  tf = "D1"; break;
      case PERIOD_W1:  tf = "W1"; break;
      case PERIOD_MN1: tf = "MN1"; break;
      default: tf = EnumToString(PERIOD_CURRENT);
   }
   return tf;
}

//+------------------------------------------------------------------+
string GetMarketDirection()
{
   double c0 = iClose(_Symbol, PERIOD_CURRENT, 0);
   double c5 = iClose(_Symbol, PERIOD_CURRENT, 5);
   double c10 = iClose(_Symbol, PERIOD_CURRENT, 10);
   double c20 = iClose(_Symbol, PERIOD_CURRENT, 20);
   
   if(c0 > c5 && c5 > c10 && c10 > c20)
      return "BULLISH";
   else if(c0 < c5 && c5 < c10 && c10 < c20)
      return "BEARISH";
   else
      return "RANGING";
}

//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string text, color clr, int size = 9)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

//+------------------------------------------------------------------+
void CreatePanel()
{
   // Background panel
   if(ObjectFind(0, PANEL_BG) < 0)
   {
      ObjectCreate(0, PANEL_BG, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, PANEL_BG, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, PANEL_BG, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, PANEL_BG, OBJPROP_YDISTANCE, 25);
      ObjectSetInteger(0, PANEL_BG, OBJPROP_XSIZE, 420);
      ObjectSetInteger(0, PANEL_BG, OBJPROP_YSIZE, 440);
      ObjectSetInteger(0, PANEL_BG, OBJPROP_BGCOLOR, clrBlack);
      ObjectSetInteger(0, PANEL_BG, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, PANEL_BG, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, PANEL_BG, OBJPROP_COLOR, clrCyan);
      ObjectSetInteger(0, PANEL_BG, OBJPROP_BACK, false);
   }
   
   // Toggle button
   if(ObjectFind(0, BTN_TOGGLE) < 0)
   {
      ObjectCreate(0, BTN_TOGGLE, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, BTN_TOGGLE, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, BTN_TOGGLE, OBJPROP_XDISTANCE, 15);
      ObjectSetInteger(0, BTN_TOGGLE, OBJPROP_YDISTANCE, 430);
      ObjectSetInteger(0, BTN_TOGGLE, OBJPROP_XSIZE, 155);
      ObjectSetInteger(0, BTN_TOGGLE, OBJPROP_YSIZE, 30);
      ObjectSetString(0, BTN_TOGGLE, OBJPROP_TEXT, "STOP TRADING");
      ObjectSetInteger(0, BTN_TOGGLE, OBJPROP_FONTSIZE, 10);
      ObjectSetInteger(0, BTN_TOGGLE, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, BTN_TOGGLE, OBJPROP_BGCOLOR, clrGreen);
   }
   
   // Close all button
   if(ObjectFind(0, BTN_CLOSE) < 0)
   {
      ObjectCreate(0, BTN_CLOSE, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, BTN_CLOSE, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, BTN_CLOSE, OBJPROP_XDISTANCE, 180);
      ObjectSetInteger(0, BTN_CLOSE, OBJPROP_YDISTANCE, 430);
      ObjectSetInteger(0, BTN_CLOSE, OBJPROP_XSIZE, 155);
      ObjectSetInteger(0, BTN_CLOSE, OBJPROP_YSIZE, 30);
      ObjectSetString(0, BTN_CLOSE, OBJPROP_TEXT, "CLOSE ALL");
      ObjectSetInteger(0, BTN_CLOSE, OBJPROP_FONTSIZE, 10);
      ObjectSetInteger(0, BTN_CLOSE, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, BTN_CLOSE, OBJPROP_BGCOLOR, clrRed);
   }
}

//+------------------------------------------------------------------+
void UpdatePanel()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double margin = AccountInfoDouble(ACCOUNT_MARGIN);
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double dd = 0;
   double profit = 0;
   
   if(startingBalance > 0)
   {
      dd = ((startingBalance - equity) / startingBalance) * 100.0;
      profit = ((equity - startingBalance) / startingBalance) * 100.0;
   }
   
   // Get ATR
   double atr = 0;
   if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0)
      atr = atrBuffer[0];
   
   // Get prices
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double c0 = iClose(_Symbol, PERIOD_CURRENT, 0);
   
   // Get high/low levels
   double high = iHigh(_Symbol, PERIOD_CURRENT, iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, xbars, 1));
   double low = iLow(_Symbol, PERIOD_CURRENT, iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, xbars, 1));
   
   // Determine colors
   color mainColor = clrCyan;
   color borderColor = clrCyan;
   
   if(!tradingAllowed)
   { 
      mainColor = clrOrange;
      borderColor = clrOrange;
   }
   else if(dd > 0)
   { 
      mainColor = clrRed;
      borderColor = clrRed;
   }
   else if(profit > 0)
   { 
      mainColor = clrLime;
      borderColor = clrLime;
   }
   
   ObjectSetInteger(0, PANEL_BG, OBJPROP_COLOR, borderColor);
   
   int lineY = 35;
   int lineSpacing = 18;
   int lineNum = 0;
   
   // Title
   CreateLabel(PANEL_LINE + IntegerToString(lineNum++), 20, lineY, "=== TORAMA BREAKOUT MOMENTUM ===", clrYellow, 10);
   lineY += 20;
   
   CreateLabel(PANEL_LINE + IntegerToString(lineNum++), 20, lineY, _Symbol + " | " + GetTimeframeName() + " | " + GetMarketDirection(), mainColor, 9);
   lineY += lineSpacing + 5;
   
   // Account section
   CreateLabel(PANEL_LINE + IntegerToString(lineNum++), 20, lineY, "--- ACCOUNT ---", clrWhite, 9);
   lineY += lineSpacing;
   CreateLabel(PANEL_LINE + IntegerToString(lineNum++), 20, lineY, "Balance:  $" + DoubleToString(balance, 2), mainColor, 9);
   lineY += lineSpacing;
   CreateLabel(PANEL_LINE + IntegerToString(lineNum++), 20, lineY, "Equity:   $" + DoubleToString(equity, 2), mainColor, 9);
   lineY += lineSpacing;
   CreateLabel(PANEL_LINE + IntegerToString(lineNum++), 20, lineY, "Margin:   $" + DoubleToString(margin, 2), mainColor, 9);
   lineY += lineSpacing;
   CreateLabel(PANEL_LINE + IntegerToString(lineNum++), 20, lineY, "Free:     $" + DoubleToString(freeMargin, 2), mainColor, 9);
   lineY += lineSpacing;
   CreateLabel(PANEL_LINE + IntegerToString(lineNum++), 20, lineY, "Drawdown: " + DoubleToString(dd, 2) + "% / Max: " + DoubleToString(GlobalMaxDrawdown, 1) + "%", mainColor, 9);
   lineY += lineSpacing;
   CreateLabel(PANEL_LINE + IntegerToString(lineNum++), 20, lineY, "Profit:   " + DoubleToString(profit, 2) + "% / Max: " + DoubleToString(GlobalMaxProfit, 1) + "%", mainColor, 9);
   lineY += lineSpacing + 5;
   
   // ATR section
   CreateLabel(PANEL_LINE + IntegerToString(lineNum++), 20, lineY, "--- ATR DATA ---", clrWhite, 9);
   lineY += lineSpacing;
   CreateLabel(PANEL_LINE + IntegerToString(lineNum++), 20, lineY, "ATR:      " + DoubleToString(atr, _Digits), mainColor, 9);
   lineY += lineSpacing;
   CreateLabel(PANEL_LINE + IntegerToString(lineNum++), 20, lineY, "SL Dist:  " + DoubleToString(atr * ATRmultiplierSL, _Digits) + " (" + DoubleToString((atr*ATRmultiplierSL)/_Point, 0) + " pts)", mainColor, 9);
   lineY += lineSpacing;
   CreateLabel(PANEL_LINE + IntegerToString(lineNum++), 20, lineY, "TP Dist:  " + DoubleToString(atr * ATRmultiplierTP, _Digits) + " (" + DoubleToString((atr*ATRmultiplierTP)/_Point, 0) + " pts)", mainColor, 9);
   lineY += lineSpacing + 5;
   
   // Market section
   CreateLabel(PANEL_LINE + IntegerToString(lineNum++), 20, lineY, "--- MARKET ---", clrWhite, 9);
   lineY += lineSpacing;
   CreateLabel(PANEL_LINE + IntegerToString(lineNum++), 20, lineY, "Bid: " + DoubleToString(bid, _Digits) + " | Ask: " + DoubleToString(ask, _Digits), mainColor, 9);
   lineY += lineSpacing;
   CreateLabel(PANEL_LINE + IntegerToString(lineNum++), 20, lineY, "Spread:   " + DoubleToString((ask-bid)/_Point, 1) + " points", mainColor, 9);
   lineY += lineSpacing + 5;
   
   // Position section
   CreateLabel(PANEL_LINE + IntegerToString(lineNum++), 20, lineY, "--- POSITION ---", clrWhite, 9);
   lineY += lineSpacing;
   
   if(PositionSelect(_Symbol))
   {
      long type = PositionGetInteger(POSITION_TYPE);
      double lots = PositionGetDouble(POSITION_VOLUME);
      double pl = PositionGetDouble(POSITION_PROFIT);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      
      CreateLabel(PANEL_LINE + IntegerToString(lineNum++), 20, lineY, (type == POSITION_TYPE_BUY ? "LONG ACTIVE" : "SHORT ACTIVE"), clrYellow, 9);
      lineY += lineSpacing;
      CreateLabel(PANEL_LINE + IntegerToString(lineNum++), 20, lineY, "Entry: " + DoubleToString(entry, _Digits) + " | Lots: " + DoubleToString(lots, 2), mainColor, 9);
      lineY += lineSpacing;
      CreateLabel(PANEL_LINE + IntegerToString(lineNum++), 20, lineY, "P/L: $" + DoubleToString(pl, 2), (pl >= 0 ? clrLime : clrRed), 9);
   }
   else
   {
      double distToLong = (high - c0) / _Point;
      double distToShort = (c0 - low) / _Point;
      
      CreateLabel(PANEL_LINE + IntegerToString(lineNum++), 20, lineY, "NO ACTIVE POSITION", clrGray, 9);
      lineY += lineSpacing;
      CreateLabel(PANEL_LINE + IntegerToString(lineNum++), 20, lineY, "Long Entry:  " + DoubleToString(high, _Digits) + " (+" + DoubleToString(distToLong, 0) + " pts)", mainColor, 9);
      lineY += lineSpacing;
      CreateLabel(PANEL_LINE + IntegerToString(lineNum++), 20, lineY, "Short Entry: " + DoubleToString(low, _Digits) + " (-" + DoubleToString(distToShort, 0) + " pts)", mainColor, 9);
   }
   lineY += lineSpacing + 5;
   
   // Status
   CreateLabel(PANEL_LINE + IntegerToString(lineNum++), 20, lineY, "Trading: " + (tradingAllowed ? "ENABLED" : "DISABLED"), (tradingAllowed ? clrLime : clrOrange), 10);
   
   // Update button
   ObjectSetString(0, BTN_TOGGLE, OBJPROP_TEXT, (tradingAllowed ? "STOP TRADING" : "START TRADING"));
   ObjectSetInteger(0, BTN_TOGGLE, OBJPROP_BGCOLOR, (tradingAllowed ? clrGreen : clrGray));
}

//+------------------------------------------------------------------+
void CreateBranding()
{
   if(ObjectFind(0, BRANDING) < 0)
   {
      ObjectCreate(0, BRANDING, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, BRANDING, OBJPROP_CORNER, CORNER_RIGHT_LOWER);
      ObjectSetInteger(0, BRANDING, OBJPROP_XDISTANCE, 15);
      ObjectSetInteger(0, BRANDING, OBJPROP_YDISTANCE, 15);
      ObjectSetInteger(0, BRANDING, OBJPROP_FONTSIZE, 10);
      ObjectSetString(0, BRANDING, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, BRANDING, OBJPROP_COLOR, clrGold);
      ObjectSetString(0, BRANDING, OBJPROP_TEXT, "TORAMA CAPITAL | ea@torama.money");
   }
}

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == BTN_TOGGLE)
      {
         tradingAllowed = !tradingAllowed;
         UpdatePanel();
         Print("🔘 Toggle clicked → Trading is now ", (tradingAllowed ? "ENABLED" : "DISABLED"));
      }
      else if(sparam == BTN_CLOSE)
      {
         Print("❌ Manual Close All triggered");
         CloseAllPositions();
      }
   }
}
//+------------------------------------------------------------------+