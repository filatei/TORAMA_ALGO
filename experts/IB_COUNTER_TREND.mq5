//+------------------------------------------------------------------+
//|                           Enhanced CandlePatternEA v2.25        |
//|                        Optimized Edition                         |
//|                        © TORAMA CAPITAL 2025                    |
//+------------------------------------------------------------------+
#property copyright "TORAMA CAPITAL - Advanced Trading Solutions"
#property version   "2.25"
#property description "Professional Enhanced Candle Pattern EA - Optimized"
#property link      "www.toramacapital.com"

#include <Trade/Trade.mqh>

// Color Scheme
#define PANEL_BG_COLOR        C'35,35,35'
#define PANEL_BORDER_COLOR    C'70,70,70'
#define TEXT_COLOR            C'220,220,220'
#define SUCCESS_COLOR         C'0,150,0'
#define WARNING_COLOR         C'255,140,0'
#define VALUE_COLOR           C'255,255,255'
#define BOLD_VALUE_COLOR      C'255,215,0'

enum ENUM_TRADE_DIRECTION { TRADE_BOTH = 0, TRADE_BUY_ONLY = 1, TRADE_SELL_ONLY = 2 };

// Input Parameters
input ENUM_TIMEFRAMES Timeframe = PERIOD_M1;
input ENUM_TRADE_DIRECTION TradeDirection = TRADE_BOTH;
input double   LotSize = 0.1;
input bool     UseAutoLotSizing = false;
input double   AutoLotPer1000 = 0.01;
input double   EquityIncrement = 1000.0;
input int      StopLoss = 0;
input double   TakeProfitDollars = 50.0;
input double   GlobalProfitTarget = 100.0;
input bool     EnableConsecutiveCandleExit = true;
input int      ConsecutiveCandleCount = 3;
input int      TradesPerSignal = 1;
input int      MaxPositions = 5;
input int      MagicNumber = 123456;
input string   TradeComment = "CandleEA";
input int      MaxRetries = 3;
input int      RetryDelay = 100;

// Global Variables
CTrade trade;
datetime lastBarTime = 0;
int consecutiveBullish = 0, consecutiveBearish = 0;
bool tradingEnabled = true, isInitialized = false, isUIHidden = false;
int actualTradesPerSignal = 1;

// UI Labels and Values Arrays
string labelNames[] = {"lblMarginLabel", "lblTimeframeLabel", "lblDailyPLLabel", "lblTotalPLLabel", 
                      "lblBuyPosLabel", "lblSellPosLabel", "lblWinRateLabel", "lblStatusLabel", 
                      "lblTradeDirectionLabel", "lblSpreadLabel", "lblBullishLabel", "lblBearishLabel"};
string labelTexts[] = {"Margin:", "Timeframe:", "Daily P/L:", "Total P/L:", "Buy Positions:", 
                      "Sell Positions:", "Win Rate:", "Status:", "Trade Direction:", 
                      "Spread:", "Bullish Candles:", "Bearish Candles:"};
string valueNames[] = {"lblMarginValue", "lblTimeframeValue", "lblDailyPLValue", "lblTotalPLValue", 
                      "lblBuyPosValue", "lblSellPosValue", "lblWinRateValue", "lblStatusValue", 
                      "lblTradeDirectionValue", "lblSpreadValue", "lblBullishValue", "lblBearishValue"};
bool isBold[] = {true, true, false, false, true, true, false, false, true, false, false, false};

//+------------------------------------------------------------------+
int OnInit()
{
   // Validate inputs
   if(LotSize <= 0 || (UseAutoLotSizing && (AutoLotPer1000 <= 0 || EquityIncrement <= 0)) ||
      TakeProfitDollars < 0 || GlobalProfitTarget <= 0 || 
      (EnableConsecutiveCandleExit && ConsecutiveCandleCount <= 0) ||
      TradesPerSignal <= 0 || MaxPositions <= 0)
   {
      Print("ERROR: Invalid input parameters");
      return(INIT_PARAMETERS_INCORRECT);
   }
   
   actualTradesPerSignal = MathMin(TradesPerSignal, MaxPositions);
   if(TradesPerSignal > MaxPositions)
      Print("WARNING: TradesPerSignal adjusted to MaxPositions (", MaxPositions, ")");
   
   // Check trading permissions
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
   {
      Print("ERROR: Trading not allowed");
      return(INIT_FAILED);
   }
   
   if(!SymbolSelect(_Symbol, true))
   {
      Print("ERROR: Symbol not available");
      return(INIT_FAILED);
   }
   
   // Setup trade parameters
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   trade.SetAsyncMode(false);
   
   // Initialize chart data
   lastBarTime = iTime(_Symbol, Timeframe, 0);
   if(lastBarTime <= 0)
   {
      Print("ERROR: Cannot get chart data for timeframe ", EnumToString(Timeframe));
      return(INIT_FAILED);
   }
   
   DeletePanel();
   Sleep(500);
   CountConsecutiveCandles();
   CreatePanel();
   isInitialized = true;
   
   Print("=== TORAMA CAPITAL EA v2.25 OPTIMIZED - ", GetEnumText(TradeDirection, true), 
         " - TF: ", GetEnumText(Timeframe, false), " ===");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   DeletePanel();
   isInitialized = false;
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(!isInitialized) return;
   
   CheckGlobalProfitTarget();
   datetime currentCandle = iTime(_Symbol, Timeframe, 0);
   
   if(currentCandle != lastBarTime && currentCandle > 0)
   {
      if(lastBarTime > 0) OnNewBar();
      lastBarTime = currentCandle;
   }
   
   if(!isUIHidden) UpdatePanelContent();
}

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long& lparam, const double& dparam, const string& sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == "btnCloseProfits")
      {
         CloseProfitablePositions();
         ObjectSetInteger(0, "btnCloseProfits", OBJPROP_STATE, false);
      }
      else if(sparam == "btnToggleTrading")
      {
         tradingEnabled = !tradingEnabled;
         ObjectSetInteger(0, "btnToggleTrading", OBJPROP_STATE, false);
         UpdatePanelContent();
      }
      ChartRedraw();
   }
   else if(id == CHARTEVENT_KEYDOWN && lparam == 72) // 'H' key
   {
      isUIHidden = !isUIHidden;
      if(isUIHidden) 
         DeletePanel();
      else 
         CreatePanel();
      Print("UI ", isUIHidden ? "HIDDEN" : "VISIBLE");
   }
   else if(id == CHARTEVENT_CHART_CHANGE && !isUIHidden)
   {
      DeletePanel();
      Sleep(200);
      CreatePanel();
   }
}

//+------------------------------------------------------------------+
void OnNewBar()
{
   Print("=== NEW BAR - ", GetEnumText(TradeDirection, true), " - TF: ", GetEnumText(Timeframe, false), " ===");
   
   CountConsecutiveCandles();
   if(!tradingEnabled) return;
   
   // Check entry signals
   double open = iOpen(_Symbol, Timeframe, 1);
   double close = iClose(_Symbol, Timeframe, 1);
   if(open <= 0 || close <= 0) return;
   
   bool isBearish = close < open;
   bool isBullish = close > open;
   
   // Process buy signals on bearish candles
   if(isBearish && (TradeDirection == TRADE_BOTH || TradeDirection == TRADE_BUY_ONLY))
   {
      int currentPos = CountPositions(POSITION_TYPE_BUY);
      int toOpen = MathMin(actualTradesPerSignal, MaxPositions - currentPos);
      if(toOpen > 0) OpenMultiplePositions(POSITION_TYPE_BUY, toOpen);
   }
   
   // Process sell signals on bullish candles
   if(isBullish && (TradeDirection == TRADE_BOTH || TradeDirection == TRADE_SELL_ONLY))
   {
      int currentPos = CountPositions(POSITION_TYPE_SELL);
      int toOpen = MathMin(actualTradesPerSignal, MaxPositions - currentPos);
      if(toOpen > 0) OpenMultiplePositions(POSITION_TYPE_SELL, toOpen);
   }
   
   // Check exit signals
   if(EnableConsecutiveCandleExit)
   {
      if(consecutiveBullish >= ConsecutiveCandleCount && CountPositions(POSITION_TYPE_BUY) > 0)
         CloseProfitablePositionsByType(POSITION_TYPE_BUY);
      
      if(consecutiveBearish >= ConsecutiveCandleCount && CountPositions(POSITION_TYPE_SELL) > 0)
         CloseProfitablePositionsByType(POSITION_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
bool CreatePanel()
{
   long chartWidth = MathMax(ChartGetInteger(0, CHART_WIDTH_IN_PIXELS), 800);
   long chartHeight = MathMax(ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS), 600);
   
   int panelWidth = 260, panelHeight = 382, margin = 10;
   
   // Main panel
   CreateObject("mainPanel", OBJ_RECTANGLE_LABEL, margin, margin, panelWidth, panelHeight,
                PANEL_BG_COLOR, PANEL_BORDER_COLOR);
   
   // Title
   CreateLabel("panelTitle", margin + 10, margin + 10, "CandlePattern EA v2.25",
               VALUE_COLOR, "Arial Bold", 9);
   
   // Buttons
   CreateButton("btnCloseProfits", margin + 10, margin + 30, 115, 25, 
                "Close Profits", SUCCESS_COLOR);
   CreateButton("btnToggleTrading", margin + 135, margin + 30, 115, 25,
                tradingEnabled ? "PAUSE" : "RESUME", WARNING_COLOR);
   
   // EQ/BAL combined label
   CreateLabel("lblEqBalLabel", margin + 10, margin + 70, "EQ / BAL:", TEXT_COLOR, "Arial", 8);
   CreateLabel("lblEqBalValue", margin + 70, margin + 70, "", BOLD_VALUE_COLOR, "Arial Bold", 9);
   
   // Create all other labels and values
   for(int i = 0; i < ArraySize(labelNames); i++)
   {
      CreateLabel(labelNames[i], margin + 10, margin + 92 + (i * 22), labelTexts[i], 
                  TEXT_COLOR, "Arial", 8);
      CreateLabel(valueNames[i], margin + 140, margin + 92 + (i * 22), "",
                  isBold[i] ? BOLD_VALUE_COLOR : VALUE_COLOR, 
                  isBold[i] ? "Arial Bold" : "Arial", isBold[i] ? 10 : 8);
   }
   
   // Chart branding
   CreateLabel("chartBrandingMain", (int)(chartWidth - 240), (int)(chartHeight - 80),
               "© TORAMA CAPITAL", C'220,20,60', "Arial Bold", 16);
   CreateLabel("chartBrandingTagline", (int)(chartWidth - 190), (int)(chartHeight - 58),
               "Algorithmic Solutions", C'144,238,144', "Arial", 11);
   CreateLabel("chartBrandingEmail", (int)(chartWidth - 160), (int)(chartHeight - 36),
               "ea@torama.biz", C'176,196,222', "Arial", 10);
   
   UpdatePanelContent();
   ChartRedraw();
   return true;
}

//+------------------------------------------------------------------+
void CreateObject(string name, ENUM_OBJECT type, int x, int y, int width, int height,
                  color bgColor, color borderColor)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   if(!ObjectCreate(0, name, type, 0, 0, 0)) return;
   
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, borderColor);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
}

//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string text, color clr, string font, int size)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0)) return;
   
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
}

//+------------------------------------------------------------------+
void CreateButton(string name, int x, int y, int width, int height, string text, color bgColor)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   if(!ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0)) return;
   
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, C'255,255,255');
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, bgColor);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
}

//+------------------------------------------------------------------+
void UpdatePanelContent()
{
   if(!isInitialized) return;
   
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double margin = AccountInfoDouble(ACCOUNT_MARGIN);
   double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   double totalProfit = CalculateTotalProfit();
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
   
   // Update button text
   ObjectSetString(0, "btnToggleTrading", OBJPROP_TEXT, tradingEnabled ? "PAUSE" : "RESUME");
   
   // Update EQ/BAL
   ObjectSetString(0, "lblEqBalValue", OBJPROP_TEXT, 
                   FormatNumber(equity, true) + " / " + FormatNumber(balance, true));
   
   // Update all values
   string values[];
   ArrayResize(values, ArraySize(valueNames));
   
   values[0] = margin > 0 ? (FormatNumber(margin, true) + 
               (marginLevel > 0 ? " (" + DoubleToString(marginLevel, 0) + "%)" : "")) : "No positions";
   values[1] = GetEnumText(Timeframe, false);
   values[2] = FormatNumber(0, false);
   values[3] = FormatNumber(totalProfit, false);
   values[4] = IntegerToString(CountPositions(POSITION_TYPE_BUY)) + "/" + IntegerToString(MaxPositions);
   values[5] = IntegerToString(CountPositions(POSITION_TYPE_SELL)) + "/" + IntegerToString(MaxPositions);
   values[6] = "0.0%";
   values[7] = tradingEnabled ? "ACTIVE" : "PAUSED";
   values[8] = GetEnumText(TradeDirection, true);
   values[9] = DoubleToString(spread, 0);
   values[10] = IntegerToString(consecutiveBullish);
   values[11] = IntegerToString(consecutiveBearish);
   
   for(int i = 0; i < ArraySize(valueNames); i++)
      ObjectSetString(0, valueNames[i], OBJPROP_TEXT, values[i]);
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
void DeletePanel()
{
   string allObjects[] = {"mainPanel", "panelTitle", "btnCloseProfits", "btnToggleTrading",
                         "lblEqBalLabel", "lblEqBalValue", "chartBrandingMain", 
                         "chartBrandingTagline", "chartBrandingEmail"};
   
   for(int i = 0; i < ArraySize(allObjects); i++)
      ObjectDelete(0, allObjects[i]);
   
   for(int i = 0; i < ArraySize(labelNames); i++)
   {
      ObjectDelete(0, labelNames[i]);
      ObjectDelete(0, valueNames[i]);
   }
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
void CountConsecutiveCandles()
{
   double open = iOpen(_Symbol, Timeframe, 1);
   double close = iClose(_Symbol, Timeframe, 1);
   
   if(open <= 0 || close <= 0) return;
   
   if(close > open)
   {
      consecutiveBullish++;
      consecutiveBearish = 0;
      Print(">>> BULLISH CANDLE - Count: ", consecutiveBullish);
   }
   else if(close < open)
   {
      consecutiveBearish++;
      consecutiveBullish = 0;
      Print(">>> BEARISH CANDLE - Count: ", consecutiveBearish);
   }
}

//+------------------------------------------------------------------+
void OpenMultiplePositions(ENUM_POSITION_TYPE posType, int count)
{
   bool isBuy = (posType == POSITION_TYPE_BUY);
   int successCount = 0;
   
   for(int i = 1; i <= count; i++)
   {
      for(int attempt = 1; attempt <= MaxRetries; attempt++)
      {
         double price = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(price <= 0) break;
         
         double lot = GetEffectiveLotSize();
         if(lot <= 0) break;
         
         double sl = StopLoss > 0 ? (isBuy ? price - StopLoss * _Point : price + StopLoss * _Point) : 0;
         double tp = 0;
         
         if(TakeProfitDollars > 0)
         {
            double tpPoints = CalculateTakeProfitPoints(lot, TakeProfitDollars);
            if(tpPoints > 0)
               tp = isBuy ? price + tpPoints * _Point : price - tpPoints * _Point;
         }
         
         bool result = isBuy ? trade.Buy(lot, _Symbol, price, sl, tp, TradeComment) :
                              trade.Sell(lot, _Symbol, price, sl, tp, TradeComment);
         
         if(result)
         {
            Print("[SUCCESS] ", isBuy ? "BUY" : "SELL", " #", i, " opened at ", price);
            successCount++;
            break;
         }
         
         if(attempt < MaxRetries) Sleep(RetryDelay);
      }
      
      if(i < count) Sleep(50);
   }
   
   Print("=== SUMMARY: ", successCount, "/", count, " ", isBuy ? "BUY" : "SELL", " positions opened ===");
}

//+------------------------------------------------------------------+
double CalculateTakeProfitPoints(double lotSize, double dollarValue)
{
   if(dollarValue <= 0 || lotSize <= 0) return 0;
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if(tickValue <= 0 || tickSize <= 0 || pointSize <= 0) return 0;
   
   double ticksNeeded = dollarValue / (tickValue * lotSize);
   return ticksNeeded * (tickSize / pointSize);
}

//+------------------------------------------------------------------+
double GetEffectiveLotSize()
{
   double lots = UseAutoLotSizing ? 
                 (MathCeil(AccountInfoDouble(ACCOUNT_EQUITY) / EquityIncrement) * AutoLotPer1000) : 
                 LotSize;
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   if(minLot <= 0 || maxLot <= 0 || stepLot <= 0) return 0;
   
   lots = MathMax(minLot, MathMin(maxLot, MathRound(lots / stepLot) * stepLot));
   return lots;
}

//+------------------------------------------------------------------+
int CountPositions(ENUM_POSITION_TYPE posType)
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetTicket(i) && PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
         PositionGetInteger(POSITION_TYPE) == posType)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
void CloseProfitablePositions()
{
   int closedCount = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) && PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
         PositionGetDouble(POSITION_PROFIT) > 0)
      {
         if(trade.PositionClose(PositionGetInteger(POSITION_TICKET)))
            closedCount++;
      }
   }
   Print("Closed ", closedCount, " profitable positions");
}

//+------------------------------------------------------------------+
void CloseProfitablePositionsByType(ENUM_POSITION_TYPE posType)
{
   int closedCount = 0, keepCount = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) && PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
         PositionGetInteger(POSITION_TYPE) == posType)
      {
         double profit = PositionGetDouble(POSITION_PROFIT);
         if(profit > 0)
         {
            if(trade.PositionClose(PositionGetInteger(POSITION_TICKET)))
               closedCount++;
         }
         else
            keepCount++;
      }
   }
   
   Print("Closed ", closedCount, " profitable ", (posType == POSITION_TYPE_BUY ? "BUY" : "SELL"),
         " positions, kept ", keepCount, " losing positions");
}

//+------------------------------------------------------------------+
double CalculateTotalProfit()
{
   double total = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetTicket(i) && PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         total += PositionGetDouble(POSITION_PROFIT);
   }
   return total;
}

//+------------------------------------------------------------------+
void CheckGlobalProfitTarget()
{
   if(GlobalProfitTarget <= 0) return;
   
   double totalProfit = CalculateTotalProfit();
   if(totalProfit >= GlobalProfitTarget)
   {
      Print("*** GLOBAL PROFIT TARGET REACHED: $", DoubleToString(totalProfit, 2), " ***");
      CloseProfitablePositions();
   }
}

//+------------------------------------------------------------------+
string FormatNumber(double number, bool useCommas)
{
   string numStr = DoubleToString(number, 2);
   if(!useCommas) return numStr;
   
   string result = "";
   int dotPos = StringFind(numStr, ".");
   string intPart = (dotPos >= 0) ? StringSubstr(numStr, 0, dotPos) : numStr;
   string fracPart = (dotPos >= 0) ? StringSubstr(numStr, dotPos) : "";
   
   int len = StringLen(intPart);
   for(int i = 0; i < len; i++)
   {
      if(i > 0 && (len - i) % 3 == 0) result += ",";
      result += StringSubstr(intPart, i, 1);
   }
   
   return result + fracPart;
}

//+------------------------------------------------------------------+
string GetEnumText(int value, bool isTradeDirection)
{
   if(isTradeDirection)
   {
      switch(value)
      {
         case TRADE_BOTH: return "BOTH";
         case TRADE_BUY_ONLY: return "BUY ONLY";
         case TRADE_SELL_ONLY: return "SELL ONLY";
      }
   }
   else // Timeframe
   {
      switch(value)
      {
         case PERIOD_M1: return "M1";
         case PERIOD_M5: return "M5";
         case PERIOD_M15: return "M15";
         case PERIOD_M30: return "M30";
         case PERIOD_H1: return "H1";
         case PERIOD_H4: return "H4";
         case PERIOD_D1: return "D1";
         case PERIOD_W1: return "W1";
         case PERIOD_MN1: return "MN1";
      }
   }
   return "UNKNOWN";
}