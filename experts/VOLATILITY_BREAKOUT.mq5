//+------------------------------------------------------------------+
//| Torama Capital Strategy EA                                       |
//| Complete Dashboard with Market Analysis                          |
//+------------------------------------------------------------------+
#property copyright "Torama Capital"
#property version   "1.16"
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
string PANEL_BG   = "EA_BG";
string PANEL_TXT  = "EA_Dashboard";
string BTN_TOGGLE = "EA_Toggle";
string BTN_CLOSE  = "EA_CloseAll";
string BRANDING   = "EA_Branding";

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

   ObjectDelete(0, PANEL_BG);
   ObjectDelete(0, PANEL_TXT);
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
      return "BULLISH ↗";
   else if(c0 < c5 && c5 < c10 && c10 < c20)
      return "BEARISH ↘";
   else
      return "RANGING →";
}

//+------------------------------------------------------------------+
void CreatePanel()
{
   // background
   if(ObjectFind(0, PANEL_BG) < 0)
   {
      ObjectCreate(0, PANEL_BG, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, PANEL_BG, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, PANEL_BG, OBJPROP_XDISTANCE, 5);
      ObjectSetInteger(0, PANEL_BG, OBJPROP_YDISTANCE, 20);
      ObjectSetInteger(0, PANEL_BG, OBJPROP_XSIZE, 400);
      ObjectSetInteger(0, PANEL_BG, OBJPROP_YSIZE, 380);
      ObjectSetInteger(0, PANEL_BG, OBJPROP_BGCOLOR, C'20,20,20');
      ObjectSetInteger(0, PANEL_BG, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, PANEL_BG, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, PANEL_BG, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, PANEL_BG, OBJPROP_BACK, false);
   }
   
   // text
   if(ObjectFind(0, PANEL_TXT) < 0)
   {
      ObjectCreate(0, PANEL_TXT, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, PANEL_TXT, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, PANEL_TXT, OBJPROP_XDISTANCE, 15);
      ObjectSetInteger(0, PANEL_TXT, OBJPROP_YDISTANCE, 30);
      ObjectSetInteger(0, PANEL_TXT, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, PANEL_TXT, OBJPROP_FONT, "Courier New");
      ObjectSetInteger(0, PANEL_TXT, OBJPROP_COLOR, clrWhite);
   }
   
   // toggle button
   if(ObjectFind(0, BTN_TOGGLE) < 0)
   {
      ObjectCreate(0, BTN_TOGGLE, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, BTN_TOGGLE, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, BTN_TOGGLE, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, BTN_TOGGLE, OBJPROP_YDISTANCE, 370);
      ObjectSetInteger(0, BTN_TOGGLE, OBJPROP_XSIZE, 130);
      ObjectSetInteger(0, BTN_TOGGLE, OBJPROP_YSIZE, 25);
      ObjectSetString(0, BTN_TOGGLE, OBJPROP_TEXT, "⏸ STOP TRADING");
      ObjectSetInteger(0, BTN_TOGGLE, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, BTN_TOGGLE, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, BTN_TOGGLE, OBJPROP_BGCOLOR, clrDarkGreen);
   }
   
   // close-all button
   if(ObjectFind(0, BTN_CLOSE) < 0)
   {
      ObjectCreate(0, BTN_CLOSE, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, BTN_CLOSE, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, BTN_CLOSE, OBJPROP_XDISTANCE, 150);
      ObjectSetInteger(0, BTN_CLOSE, OBJPROP_YDISTANCE, 370);
      ObjectSetInteger(0, BTN_CLOSE, OBJPROP_XSIZE, 130);
      ObjectSetInteger(0, BTN_CLOSE, OBJPROP_YSIZE, 25);
      ObjectSetString(0, BTN_CLOSE, OBJPROP_TEXT, "✕ CLOSE ALL");
      ObjectSetInteger(0, BTN_CLOSE, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, BTN_CLOSE, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, BTN_CLOSE, OBJPROP_BGCOLOR, clrDarkRed);
   }
}

//+------------------------------------------------------------------+
void UpdatePanel()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double margin = AccountInfoDouble(ACCOUNT_MARGIN);
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double dd = ((startingBalance - equity) / startingBalance) * 100.0;
   double profit = ((equity - startingBalance) / startingBalance) * 100.0;
   
   // Get ATR data
   double atr = 0;
   if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0)
      atr = atrBuffer[0];
   
   // Get price data
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double c0 = iClose(_Symbol, PERIOD_CURRENT, 0);
   double c1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double c2 = iClose(_Symbol, PERIOD_CURRENT, 2);
   double c3 = iClose(_Symbol, PERIOD_CURRENT, 3);
   
   // Get high/low levels
   double high = iHigh(_Symbol, PERIOD_CURRENT, iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, xbars, 1));
   double low = iLow(_Symbol, PERIOD_CURRENT, iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, xbars, 1));
   
   // Calculate distances
   double distToLong = high - c0;
   double distToShort = c0 - low;
   
   // Check conditions
   bool longReady = (c0 > c1 && c0 > c3 && c1 > c2);
   bool shortReady = (c0 < c1 && c0 < c3 && c1 < c2);
   
   string posInfo = "═════════════ POSITION ═════════════\n";
   if(PositionSelect(_Symbol))
   {
      long type = PositionGetInteger(POSITION_TYPE);
      double lots = PositionGetDouble(POSITION_VOLUME);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double pl = PositionGetDouble(POSITION_PROFIT);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      
      posInfo += "Type:     " + (type == POSITION_TYPE_BUY ? "BUY  ▲" : "SELL ▼") + "\n";
      posInfo += "Volume:   " + DoubleToString(lots, 2) + " lots\n";
      posInfo += "Entry:    " + DoubleToString(entry, _Digits) + "\n";
      posInfo += "SL:       " + DoubleToString(sl, _Digits) + "\n";
      posInfo += "TP:       " + DoubleToString(tp, _Digits) + "\n";
      posInfo += "P/L:      " + DoubleToString(pl, 2) + " USD\n";
   }
   else
   {
      posInfo += "Status:   NO ACTIVE POSITION\n";
      posInfo += "\n";
      posInfo += "Next Long:  " + DoubleToString(high, _Digits) + " (+" + DoubleToString(distToLong/_Point, 0) + " pts)\n";
      posInfo += "Next Short: " + DoubleToString(low, _Digits) + " (-" + DoubleToString(distToShort/_Point, 0) + " pts)\n";
      posInfo += "\n";
      posInfo += "Long Signal:  " + (longReady ? "✓ READY" : "✗ Waiting") + "\n";
      posInfo += "Short Signal: " + (shortReady ? "✓ READY" : "✗ Waiting") + "\n";
   }

   string text =
      "╔════ TORAMA CAPITAL EA v1.16 ════╗\n" +
      "║ " + _Symbol + " | " + GetTimeframeName() + " | " + GetMarketDirection() + "\n" +
      "╠══════════ ACCOUNT ══════════╣\n" +
      "Balance:     " + DoubleToString(balance, 2) + " USD\n" +
      "Equity:      " + DoubleToString(equity, 2) + " USD\n" +
      "Margin:      " + DoubleToString(margin, 2) + " USD\n" +
      "Free:        " + DoubleToString(freeMargin, 2) + " USD\n" +
      "Drawdown:    " + DoubleToString(dd, 2) + "%\n" +
      "Profit:      " + DoubleToString(profit, 2) + "%\n" +
      "\n" +
      "╠═══════════ ATR DATA ═══════════╣\n" +
      "ATR Value:   " + DoubleToString(atr, _Digits) + "\n" +
      "SL Distance: " + DoubleToString(atr * ATRmultiplierSL, _Digits) + " (" + DoubleToString((atr*ATRmultiplierSL)/_Point, 0) + " pts)\n" +
      "TP Distance: " + DoubleToString(atr * ATRmultiplierTP, _Digits) + " (" + DoubleToString((atr*ATRmultiplierTP)/_Point, 0) + " pts)\n" +
      "\n" +
      "╠══════════ MARKET ══════════╣\n" +
      "Bid:         " + DoubleToString(bid, _Digits) + "\n" +
      "Ask:         " + DoubleToString(ask, _Digits) + "\n" +
      "Spread:      " + DoubleToString((ask-bid)/_Point, 1) + " pts\n" +
      "\n" +
      posInfo +
      "\n" +
      "╠════════════ STATUS ════════════╣\n" +
      "Trading:     " + (tradingAllowed ? "ENABLED ✓" : "DISABLED ✗") + "\n" +
      "Max DD:      " + DoubleToString(GlobalMaxDrawdown, 1) + "%\n" +
      "Max Profit:  " + DoubleToString(GlobalMaxProfit, 1) + "%\n" +
      "╚═══════════════════════════════╝";

   // Color scheme
   color borderCol = clrWhite;
   color txtCol = clrWhite;
   
   if(!tradingAllowed)
   { 
      borderCol = clrOrange;
      txtCol = clrOrange;
   }
   else if(dd > 0)
   { 
      borderCol = clrRed;
      txtCol = clrRed;
   }
   else if(profit > 0)
   { 
      borderCol = clrLime;
      txtCol = clrLime;
   }

   ObjectSetString(0, PANEL_TXT, OBJPROP_TEXT, text);
   ObjectSetInteger(0, PANEL_TXT, OBJPROP_COLOR, txtCol);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_COLOR, borderCol);

   // Update buttons
   ObjectSetString(0, BTN_TOGGLE, OBJPROP_TEXT, (tradingAllowed ? "⏸ STOP TRADING" : "▶ START TRADING"));
   ObjectSetInteger(0, BTN_TOGGLE, OBJPROP_BGCOLOR, (tradingAllowed ? clrDarkGreen : clrGray));
}

//+------------------------------------------------------------------+
void CreateBranding()
{
   if(ObjectFind(0, BRANDING) < 0)
   {
      ObjectCreate(0, BRANDING, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, BRANDING, OBJPROP_CORNER, CORNER_RIGHT_LOWER);
      ObjectSetInteger(0, BRANDING, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, BRANDING, OBJPROP_YDISTANCE, 10);
      ObjectSetInteger(0, BRANDING, OBJPROP_FONTSIZE, 9);
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