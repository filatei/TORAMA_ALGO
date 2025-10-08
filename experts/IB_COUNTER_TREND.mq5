//+------------------------------------------------------------------+
//|                           Enhanced CandlePatternEA v2.27        |
//|                   Optimized Edition with Trend Analysis         |
//|                        © TORAMA CAPITAL 2025                    |
//+------------------------------------------------------------------+
#property copyright "TORAMA CAPITAL - Advanced Trading Solutions"
#property version   "2.28"
#property description "Professional Enhanced Candle Pattern EA - Auto-Pause"
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
#define BULLISH_COLOR         C'0,200,100'
#define BEARISH_COLOR         C'255,80,80'
#define NEUTRAL_COLOR         C'200,200,0'

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
input int      DelayBetweenTradesMinutes = 30;
input int      TPWinsBeforePause = 10;  // Number of TP wins before auto-pause (0 = disabled)
input int      MagicNumber = 123456;
input string   TradeComment = "CandleEA";
input int      MaxRetries = 3;
input int      RetryDelay = 100;

// Global Variables
CTrade trade;
datetime lastBarTime = 0;
datetime lastBuyTradeTime = 0;
datetime lastSellTradeTime = 0;
int consecutiveBullish = 0, consecutiveBearish = 0;
bool tradingEnabled = true, isInitialized = false, isUIHidden = false;
int actualTradesPerSignal = 1;

// NEW: TP Win Tracking
int tpWinsThisSession = 0;
int totalPositionsOpened = 0;

// Trend Analysis Variables
int maShortHandle = INVALID_HANDLE;
int maMediumHandle = INVALID_HANDLE;
int maLongHandle = INVALID_HANDLE;
string shortTrend = "---", mediumTrend = "---", longTrend = "---";
color shortTrendColor = NEUTRAL_COLOR, mediumTrendColor = NEUTRAL_COLOR, longTrendColor = NEUTRAL_COLOR;

// UI Labels and Values Arrays
string labelNames[] = {"lblMarginLabel", "lblTimeframeLabel", "lblDailyPLLabel", "lblTotalPLLabel", 
                      "lblBuyPosLabel", "lblSellPosLabel", "lblWinRateLabel", "lblStatusLabel", 
                      "lblTradeDirectionLabel", "lblSpreadLabel", "lblBullishLabel", "lblBearishLabel",
                      "lblDelayLabel", "lblNextBuyLabel", "lblNextSellLabel",
                      "lblShortTrendLabel", "lblMediumTrendLabel", "lblLongTrendLabel",
                      "lblTPWinsLabel"};  // NEW
string labelTexts[] = {"Margin:", "Timeframe:", "Daily P/L:", "Total P/L:", "Buy Positions:", 
                      "Sell Positions:", "Win Rate:", "Status:", "Trade Direction:", 
                      "Spread:", "Bullish Candles:", "Bearish Candles:",
                      "Trade Delay:", "Next Buy:", "Next Sell:",
                      "Short Trend:", "Medium Trend:", "Long Trend:",
                      "TP Wins:"};  // NEW
string valueNames[] = {"lblMarginValue", "lblTimeframeValue", "lblDailyPLValue", "lblTotalPLValue", 
                      "lblBuyPosValue", "lblSellPosValue", "lblWinRateValue", "lblStatusValue", 
                      "lblTradeDirectionValue", "lblSpreadValue", "lblBullishValue", "lblBearishValue",
                      "lblDelayValue", "lblNextBuyValue", "lblNextSellValue",
                      "lblShortTrendValue", "lblMediumTrendValue", "lblLongTrendValue",
                      "lblTPWinsValue"};  // NEW
bool isBold[] = {true, true, false, false, true, true, false, false, true, false, false, false,
                true, false, false, true, true, true, true};  // NEW

//+------------------------------------------------------------------+
int OnInit()
{
   // Validate inputs
   if(LotSize <= 0 || (UseAutoLotSizing && (AutoLotPer1000 <= 0 || EquityIncrement <= 0)) ||
      TakeProfitDollars < 0 || GlobalProfitTarget <= 0 || 
      (EnableConsecutiveCandleExit && ConsecutiveCandleCount <= 0) ||
      TradesPerSignal <= 0 || MaxPositions <= 0 || DelayBetweenTradesMinutes < 0 ||
      TPWinsBeforePause < 0)
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
   
   // Initialize trend indicators (EMA for efficiency)
   maShortHandle = iMA(_Symbol, PERIOD_CURRENT, 20, 0, MODE_EMA, PRICE_CLOSE);
   maMediumHandle = iMA(_Symbol, PERIOD_CURRENT, 50, 0, MODE_EMA, PRICE_CLOSE);
   maLongHandle = iMA(_Symbol, PERIOD_CURRENT, 200, 0, MODE_EMA, PRICE_CLOSE);
   
   if(maShortHandle == INVALID_HANDLE || maMediumHandle == INVALID_HANDLE || maLongHandle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to initialize trend indicators");
      return(INIT_FAILED);
   }
   
   DeletePanel();
   Sleep(500);
   CountConsecutiveCandles();
   CalculateTrends();
   CreatePanel();
   isInitialized = true;
   
   // NEW: Track initial open positions
   totalPositionsOpened = HistoryDealsTotal();
   
   string pauseInfo = (TPWinsBeforePause > 0) ? 
                      (" - Auto-Pause: " + IntegerToString(TPWinsBeforePause) + " TP wins") : 
                      " - Auto-Pause: OFF";
   
   Print("=== TORAMA CAPITAL EA v2.28 with AUTO-PAUSE - ", GetEnumText(TradeDirection, true), 
         " - TF: ", GetEnumText(Timeframe, false), " - Delay: ", DelayBetweenTradesMinutes, 
         "min", pauseInfo, " ===");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(maShortHandle != INVALID_HANDLE) IndicatorRelease(maShortHandle);
   if(maMediumHandle != INVALID_HANDLE) IndicatorRelease(maMediumHandle);
   if(maLongHandle != INVALID_HANDLE) IndicatorRelease(maLongHandle);
   
   DeletePanel();
   isInitialized = false;
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(!isInitialized) return;
   
   CheckGlobalProfitTarget();
   CheckTPWins();  // NEW: Check for TP wins and auto-pause
   
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
         // NEW: Reset TP wins counter when manually resuming
         if(tradingEnabled)
         {
            tpWinsThisSession = 0;
            Print("Trading resumed - TP wins counter reset");
         }
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
void CalculateTrends()
{
   double maShort[], maMedium[], maLong[], close[];
   
   if(CopyBuffer(maShortHandle, 0, 0, 3, maShort) < 3 ||
      CopyBuffer(maMediumHandle, 0, 0, 3, maMedium) < 3 ||
      CopyBuffer(maLongHandle, 0, 0, 3, maLong) < 3 ||
      CopyClose(_Symbol, PERIOD_CURRENT, 0, 3, close) < 3)
      return;
   
   ArraySetAsSeries(maShort, true);
   ArraySetAsSeries(maMedium, true);
   ArraySetAsSeries(maLong, true);
   ArraySetAsSeries(close, true);
   
   // Short-term trend (20 EMA vs Price + slope)
   bool shortUp = close[0] > maShort[0] && maShort[0] > maShort[2];
   bool shortDown = close[0] < maShort[0] && maShort[0] < maShort[2];
   
   if(shortUp)
   {
      shortTrend = "BULLISH ▲";
      shortTrendColor = BULLISH_COLOR;
   }
   else if(shortDown)
   {
      shortTrend = "BEARISH ▼";
      shortTrendColor = BEARISH_COLOR;
   }
   else
   {
      shortTrend = "NEUTRAL ●";
      shortTrendColor = NEUTRAL_COLOR;
   }
   
   // Medium-term trend (20/50 EMA cross + slope)
   bool mediumUp = maShort[0] > maMedium[0] && maMedium[0] > maMedium[2];
   bool mediumDown = maShort[0] < maMedium[0] && maMedium[0] < maMedium[2];
   
   if(mediumUp)
   {
      mediumTrend = "BULLISH ▲";
      mediumTrendColor = BULLISH_COLOR;
   }
   else if(mediumDown)
   {
      mediumTrend = "BEARISH ▼";
      mediumTrendColor = BEARISH_COLOR;
   }
   else
   {
      mediumTrend = "NEUTRAL ●";
      mediumTrendColor = NEUTRAL_COLOR;
   }
   
   // Long-term trend (200 EMA position + slope)
   bool longUp = close[0] > maLong[0] && maLong[0] > maLong[2];
   bool longDown = close[0] < maLong[0] && maLong[0] < maLong[2];
   
   if(longUp)
   {
      longTrend = "BULLISH ▲";
      longTrendColor = BULLISH_COLOR;
   }
   else if(longDown)
   {
      longTrend = "BEARISH ▼";
      longTrendColor = BEARISH_COLOR;
   }
   else
   {
      longTrend = "NEUTRAL ●";
      longTrendColor = NEUTRAL_COLOR;
   }
}

//+------------------------------------------------------------------+
bool IsDelayPassed(ENUM_POSITION_TYPE posType)
{
   if(MaxPositions <= 1) return true;
   if(DelayBetweenTradesMinutes <= 0) return true;
   
   datetime lastTradeTime = (posType == POSITION_TYPE_BUY) ? lastBuyTradeTime : lastSellTradeTime;
   if(lastTradeTime == 0) return true;
   
   int elapsedMinutes = (int)((TimeCurrent() - lastTradeTime) / 60);
   return (elapsedMinutes >= DelayBetweenTradesMinutes);
}

//+------------------------------------------------------------------+
int GetRemainingDelayMinutes(ENUM_POSITION_TYPE posType)
{
   if(MaxPositions <= 1 || DelayBetweenTradesMinutes <= 0) return 0;
   
   datetime lastTradeTime = (posType == POSITION_TYPE_BUY) ? lastBuyTradeTime : lastSellTradeTime;
   if(lastTradeTime == 0) return 0;
   
   int elapsedMinutes = (int)((TimeCurrent() - lastTradeTime) / 60);
   int remainingMinutes = DelayBetweenTradesMinutes - elapsedMinutes;
   
   return (remainingMinutes > 0) ? remainingMinutes : 0;
}

//+------------------------------------------------------------------+
// NEW: Check for TP wins and auto-pause
void CheckTPWins()
{
   if(TPWinsBeforePause <= 0 || !tradingEnabled) return;
   
   // Access history from session start
   if(!HistorySelect(0, TimeCurrent())) return;
   
   int tpWins = 0;
   
   // Count closed deals that hit TP
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket <= 0) continue;
      
      // Check if deal belongs to this EA
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol ||
         HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber)
         continue;
      
      // Check if it's an exit deal (not entry)
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT)
         continue;
      
      // Check if profit is positive (TP hit)
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      if(profit > 0)
      {
         // Verify it was a TP exit by checking deal comment or price
         string comment = HistoryDealGetString(ticket, DEAL_COMMENT);
         if(StringFind(comment, "tp") >= 0 || StringFind(comment, "TP") >= 0 || 
            StringFind(comment, "take profit") >= 0)
         {
            tpWins++;
         }
      }
   }
   
   tpWinsThisSession = tpWins;
   
   // Auto-pause when target is reached
   if(tpWinsThisSession >= TPWinsBeforePause && tradingEnabled)
   {
      tradingEnabled = false;
      string msg = StringFormat("*** AUTO-PAUSED: %d TP wins reached! ***", tpWinsThisSession);
      Print(msg);
      Comment(msg);
      Alert(msg);
   }
}

//+------------------------------------------------------------------+
void OnNewBar()
{
   Print("=== NEW BAR - ", GetEnumText(TradeDirection, true), " - TF: ", GetEnumText(Timeframe, false), " ===");
   
   CountConsecutiveCandles();
   CalculateTrends();
   
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
      if(IsDelayPassed(POSITION_TYPE_BUY))
      {
         int currentPos = CountPositions(POSITION_TYPE_BUY);
         int toOpen = MathMin(actualTradesPerSignal, MaxPositions - currentPos);
         if(toOpen > 0) 
         {
            if(OpenMultiplePositions(POSITION_TYPE_BUY, toOpen))
               lastBuyTradeTime = TimeCurrent();
         }
      }
      else
      {
         int remaining = GetRemainingDelayMinutes(POSITION_TYPE_BUY);
         Print("BUY signal detected but delay active. ", remaining, " minutes remaining.");
      }
   }
   
   // Process sell signals on bullish candles
   if(isBullish && (TradeDirection == TRADE_BOTH || TradeDirection == TRADE_SELL_ONLY))
   {
      if(IsDelayPassed(POSITION_TYPE_SELL))
      {
         int currentPos = CountPositions(POSITION_TYPE_SELL);
         int toOpen = MathMin(actualTradesPerSignal, MaxPositions - currentPos);
         if(toOpen > 0) 
         {
            if(OpenMultiplePositions(POSITION_TYPE_SELL, toOpen))
               lastSellTradeTime = TimeCurrent();
         }
      }
      else
      {
         int remaining = GetRemainingDelayMinutes(POSITION_TYPE_SELL);
         Print("SELL signal detected but delay active. ", remaining, " minutes remaining.");
      }
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
   
   int panelWidth = 260, panelHeight = 424, margin = 10;  // Increased height to cover all content
   
   // Main panel
   CreateObject("mainPanel", OBJ_RECTANGLE_LABEL, margin, margin, panelWidth, panelHeight,
                PANEL_BG_COLOR, PANEL_BORDER_COLOR);
   
   // Title
   CreateLabel("panelTitle", margin + 10, margin + 10, "CandlePattern EA v2.28",
               VALUE_COLOR, "Arial Bold", 9);
   
   // Buttons
   CreateButton("btnCloseProfits", margin + 10, margin + 30, 115, 25, 
                "Close Profits", SUCCESS_COLOR);
   CreateButton("btnToggleTrading", margin + 135, margin + 30, 115, 25,
                tradingEnabled ? "PAUSE" : "RESUME", WARNING_COLOR);
   
   // EQ/BAL combined label
   CreateLabel("lblEqBalLabel", margin + 10, margin + 70, "EQ / BAL:", TEXT_COLOR, "Arial", 8);
   CreateLabel("lblEqBalValue", margin + 70, margin + 70, "", BOLD_VALUE_COLOR, "Arial Bold", 9);
   
   // Create all other labels and values with adjusted spacing
   for(int i = 0; i < ArraySize(labelNames); i++)
   {
      CreateLabel(labelNames[i], margin + 10, margin + 92 + (i * 20), labelTexts[i],  // Reduced spacing to 20px
                  TEXT_COLOR, "Arial", 8);
      CreateLabel(valueNames[i], margin + 130, margin + 92 + (i * 20), "",  // Adjusted X position for better fit
                  isBold[i] ? BOLD_VALUE_COLOR : VALUE_COLOR, 
                  isBold[i] ? "Arial Bold" : "Arial", isBold[i] ? 9 : 8);  // Reduced font sizes
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
   
   int buyDelayRemaining = GetRemainingDelayMinutes(POSITION_TYPE_BUY);
   int sellDelayRemaining = GetRemainingDelayMinutes(POSITION_TYPE_SELL);
   
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
   values[12] = IntegerToString(DelayBetweenTradesMinutes) + " min";
   values[13] = buyDelayRemaining > 0 ? IntegerToString(buyDelayRemaining) + " min" : "Ready";
   values[14] = sellDelayRemaining > 0 ? IntegerToString(sellDelayRemaining) + " min" : "Ready";
   values[15] = shortTrend;
   values[16] = mediumTrend;
   values[17] = longTrend;
   values[18] = IntegerToString(tpWinsThisSession) + "/" + IntegerToString(TPWinsBeforePause);  // NEW
   
   for(int i = 0; i < ArraySize(valueNames); i++)
   {
      ObjectSetString(0, valueNames[i], OBJPROP_TEXT, values[i]);
      
      // Update trend colors dynamically
      if(i == 15) ObjectSetInteger(0, valueNames[i], OBJPROP_COLOR, shortTrendColor);
      else if(i == 16) ObjectSetInteger(0, valueNames[i], OBJPROP_COLOR, mediumTrendColor);
      else if(i == 17) ObjectSetInteger(0, valueNames[i], OBJPROP_COLOR, longTrendColor);
      // NEW: Color code TP wins (warning color when approaching limit)
      else if(i == 18)
      {
         color tpColor = (tpWinsThisSession >= TPWinsBeforePause) ? BEARISH_COLOR :
                        (tpWinsThisSession >= TPWinsBeforePause - 2) ? WARNING_COLOR : 
                        BULLISH_COLOR;
         ObjectSetInteger(0, valueNames[i], OBJPROP_COLOR, tpColor);
      }
   }
   
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
bool OpenMultiplePositions(ENUM_POSITION_TYPE posType, int count)
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
   return (successCount > 0);
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
   else
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