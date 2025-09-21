//+------------------------------------------------------------------+
//|                                     GapTrader Pro EA v16.3      |
//|                 Momentum-Only Strategy (Dollar-Based Calculations)|
//|              Buy Up Momentum | Sell Down Momentum              |
//|              SEPARATE MAX BUY & MAX SELL POSITIONS              |
//|              REBUILD ON TP/SL CLOSE (OPTIONAL)                  |
//|              SPREAD FILTER PROTECTION                           |
//+------------------------------------------------------------------+
#property copyright "GapTrader Pro v16.3 - © Torama Capital"
#property version   "16.03"
#property strict

#include <Trade\Trade.mqh>

enum ENUM_TRADE_DIRECTION { TRADE_BUY = 0, TRADE_SELL = 1, TRADE_BOTH = 2 };

// Input Parameters - Momentum Strategy
input group "=== Momentum Strategy ==="
input ENUM_TRADE_DIRECTION TradeDirection = TRADE_BOTH;
input double GapSizeDollars = 200.0;           // Gap size in dollars for momentum triggers
input double TakeProfitDollars = 100.0;       // TP in dollars per position
input double StopLossDollars = 0.0;           // SL in dollars per position (0=disabled)
input double GlobalTakeProfitDollars = 500.0; // Global TP in dollars
input double GlobalStopLossDollars = 0.0;     // Global SL in dollars (0=disabled)

// *** SEPARATE MAX POSITIONS FOR BUY AND SELL ***
input int MaxBuyPositions = 4;                // Maximum BUY positions
input int MaxSellPositions = 4;               // Maximum SELL positions

input int MagicNumber = 66618;

input group "=== Position Sizing ==="
input bool UseAutoLotSize = true;
input double AutoLotSize = 0.01;               // Lot size per $500 equity
input double AutoLotEquity = 500.0;            // Equity base for auto sizing
input double ManualLotSize = 0.1;              // Fixed lot size when auto disabled

input group "=== Spread Filter ==="
input bool EnableSpreadFilter = true;         // Enable spread protection
input int MaxSpreadPoints = 50;               // Maximum allowed spread in points (0=disabled)

input group "=== Auto Rebuild ==="
input bool EnableAutoRebuild = true;
input int RebuildIntervalMinutes = 30;
input int MaxRebuilds = 10;
input bool RebuildOnTPSL = true;              // Rebuild after TP/SL closes

input group "=== Panel Settings ==="
input int PanelX = 20;
input int PanelY = 20;
input bool ShowPanelOnStart = true;

// Momentum Trade Info Structure
struct TradeInfo {
   // Price levels for momentum strategy
   double centerPrice;
   double lastBuyPrice, lastSellPrice;  // Last prices where trades were opened
   
   // Position counters
   int buyPositions, sellPositions;
   int lastKnownBuyPositions, lastKnownSellPositions;  // For detecting TP/SL closes
   
   // System state
   double totalProfit;
   datetime startTime, nextAutoRebuild;
   bool isActive, isPaused;
   int autoRebuilds;
   int tpslRebuilds;  // Counter for TP/SL rebuilds
   int spreadBlockCount;  // Counter for trades blocked by spread
};

// Globals
CTrade trade;
TradeInfo ti;
bool panelCreated = false, panelVisible = true;
bool brandingCreated = false;

// State persistence
double savedData[8];
datetime savedTimes[3];
bool savedBools[3];
int savedInts[8];

//+------------------------------------------------------------------+
//| Utility Functions                                                |
//+------------------------------------------------------------------+
string FormatNumber(double value) {
   return DoubleToString(value, 2);
}

string FormatTimeRemaining(datetime targetTime) {
   if(targetTime <= 0) return "DISABLED";
   
   int remainingSeconds = (int)(targetTime - TimeCurrent());
   if(remainingSeconds <= 0) return "DUE";
   
   int hours = remainingSeconds / 3600;
   int minutes = (remainingSeconds % 3600) / 60;
   
   if(hours > 0) return IntegerToString(hours) + "h " + IntegerToString(minutes) + "m";
   else return IntegerToString(minutes) + "m";
}

double GetLotSize() {
   double lot;
   if(UseAutoLotSize) {
      lot = (AccountInfoDouble(ACCOUNT_EQUITY) / AutoLotEquity) * AutoLotSize;
      lot = MathMax(lot, 0.01);
      lot = MathRound(lot * 100.0) / 100.0;
   } else {
      lot = ManualLotSize;
   }
   
   lot = MathMax(lot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
   lot = MathMin(lot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));
   return lot;
}

double DollarsToPips(double dollars, double lotSize) {
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickValue <= 0) return 0;
   return dollars / (lotSize * tickValue);
}

double DollarGapToPrice(double dollarAmount) {
   double standardLot = 1.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(tickValue <= 0 || tickSize <= 0) {
      return dollarAmount / 10.0; // Fallback
   }
   
   double ticksNeeded = dollarAmount / (tickValue * standardLot);
   return ticksNeeded * tickSize;
}

int GetCurrentSpread() {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if(point <= 0) return 0;
   
   return (int)MathRound((ask - bid) / point);
}

bool IsSpreadAcceptable() {
   if(!EnableSpreadFilter || MaxSpreadPoints <= 0) {
      return true;  // Spread filter disabled
   }
   
   int currentSpread = GetCurrentSpread();
   return (currentSpread <= MaxSpreadPoints);
}

//+------------------------------------------------------------------+
//| Initialization and State Management                              |
//+------------------------------------------------------------------+
int OnInit() {
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   bool stateRestored = (savedData[0] > 0 && savedTimes[0] > 0);
   if(stateRestored) {
      RestoreState();
      Print("*** STATE RESTORED - MOMENTUM EA CONTINUING ***");
   } else {
      InitFreshState();
      Print("*** FRESH START - MOMENTUM STRATEGY INITIALIZED ***");
   }
   
   // Create branding outside panel
   CreateBranding();
   
   // Create panel
   panelVisible = ShowPanelOnStart;
   if(!CreatePanel()) return INIT_FAILED;
   
   SetPanelVisibility(panelVisible);
   
   PrintStrategyInfo();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   SaveState();
   ObjectsDeleteAll(0, "GT_");
   ChartRedraw();
   if(reason != REASON_PARAMETERS && reason != REASON_RECOMPILE) {
      ClearState();
      Print("*** EA REMOVED - State Cleared ***");
   }
}

void InitFreshState() {
   ZeroMemory(ti);
   ti.isActive = true;
   ti.isPaused = false;
   ti.startTime = TimeCurrent();
   
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   ti.centerPrice = currentPrice;
   ti.lastBuyPrice = ti.lastSellPrice = currentPrice;
   ti.lastKnownBuyPositions = 0;
   ti.lastKnownSellPositions = 0;
   
   if(EnableAutoRebuild && MaxRebuilds > 0) {
      ti.nextAutoRebuild = ti.startTime + (RebuildIntervalMinutes * 60);
   }
   
   Print("*** Momentum Strategy Initialized | Center: ", DoubleToString(currentPrice, _Digits), " ***");
}

void SaveState() {
   savedData[0] = ti.centerPrice;
   savedData[1] = ti.lastBuyPrice;
   savedData[2] = ti.lastSellPrice;
   savedData[3] = ti.totalProfit;
   
   savedTimes[0] = ti.startTime;
   savedTimes[1] = ti.nextAutoRebuild;
   
   savedBools[0] = ti.isActive;
   savedBools[1] = ti.isPaused;
   
   savedInts[0] = ti.buyPositions;
   savedInts[1] = ti.sellPositions;
   savedInts[2] = ti.autoRebuilds;
   savedInts[3] = ti.tpslRebuilds;
   savedInts[4] = ti.lastKnownBuyPositions;
   savedInts[5] = ti.lastKnownSellPositions;
   savedInts[6] = ti.spreadBlockCount;
}

void RestoreState() {
   ti.centerPrice = savedData[0];
   ti.lastBuyPrice = savedData[1];
   ti.lastSellPrice = savedData[2];
   
   ti.startTime = savedTimes[0];
   ti.nextAutoRebuild = savedTimes[1];
   
   ti.isActive = savedBools[0];
   ti.isPaused = savedBools[1];
   
   ti.buyPositions = savedInts[0];
   ti.sellPositions = savedInts[1];
   ti.autoRebuilds = savedInts[2];
   ti.tpslRebuilds = savedInts[3];
   ti.lastKnownBuyPositions = savedInts[4];
   ti.lastKnownSellPositions = savedInts[5];
   ti.spreadBlockCount = savedInts[6];
}

void ClearState() {
   ArrayInitialize(savedData, 0);
   ArrayInitialize(savedTimes, 0);
   ArrayInitialize(savedBools, false);
   ArrayInitialize(savedInts, 0);
}

void PrintStrategyInfo() {
   Print("===================================================================");
   Print("GapTrader Pro EA v16.3 - Momentum Strategy - © Torama Capital");
   Print("Email: ea@torama.biz | Web: money.torama.biz");
   Print("===================================================================");
   Print("MOMENTUM STRATEGY:");
   Print("- BUY: Opens on upward price momentum (price rises by gap)");
   Print("- SELL: Opens on downward price momentum (price falls by gap)");
   Print("-------------------------------------------------------------------");
   Print("Trading Direction: ", TradeDirection == TRADE_BOTH ? "BOTH (Buy Up + Sell Down)" : 
         (TradeDirection == TRADE_BUY ? "BUY MOMENTUM ONLY" : "SELL MOMENTUM ONLY"));
   Print("Gap Size: $", DoubleToString(GapSizeDollars, 2), " (momentum trigger)");
   Print("Take Profit: $", DoubleToString(TakeProfitDollars, 2), " per position");
   Print("*** MAX BUY POSITIONS: ", MaxBuyPositions, " | MAX SELL POSITIONS: ", MaxSellPositions, " ***");
   Print("Auto Lot Sizing: ", UseAutoLotSize ? "ENABLED" : "DISABLED");
   Print("Current Lot Size: ", DoubleToString(GetLotSize(), 2));
   Print("Auto Rebuild: ", EnableAutoRebuild ? "ENABLED" : "DISABLED");
   Print("Rebuild on TP/SL: ", RebuildOnTPSL ? "ENABLED" : "DISABLED");
   Print("Spread Filter: ", EnableSpreadFilter ? "ENABLED (Max: " + IntegerToString(MaxSpreadPoints) + " points)" : "DISABLED");
   Print("===================================================================");
}

//+------------------------------------------------------------------+
//| Main Trading Logic - Momentum Strategy                           |
//+------------------------------------------------------------------+
void OnTick() {
   CalcTotalPL();
   if(panelVisible) UpdatePanel();
   
   if(ti.isPaused || !ti.isActive) return;
   
   // Check for TP/SL closes and rebuild if enabled
   if(RebuildOnTPSL) {
      CheckTPSLCloses();
   }
   
   // Auto rebuild check
   if(EnableAutoRebuild && ti.autoRebuilds < MaxRebuilds && 
      ti.nextAutoRebuild > 0 && TimeCurrent() >= ti.nextAutoRebuild) {
      AutoRebuildGrid();
   }
   
   // Global TP/SL check
   if(CheckGlobalTPSL()) {
      CloseAllProfitableTrades();
      RebuildGrid("Global TP/SL Reached");
      return;
   }
   
   CheckMomentumTrades();
}

void CheckMomentumTrades() {
   // Check spread filter before attempting any trades
   if(!IsSpreadAcceptable()) {
      ti.spreadBlockCount++;
      if(ti.spreadBlockCount % 100 == 1) {  // Log every 100th block to avoid spam
         int currentSpread = GetCurrentSpread();
         Print(">>> TRADE BLOCKED: Spread too wide (", currentSpread, " > ", MaxSpreadPoints, " points) | Blocked count: ", ti.spreadBlockCount);
      }
      return;
   }
   
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double gapInPrice = DollarGapToPrice(GapSizeDollars);
   
   // *** BUY MOMENTUM: Strictly enforce MaxBuyPositions ***
   if((TradeDirection == TRADE_BUY || TradeDirection == TRADE_BOTH) && 
      ti.buyPositions < MaxBuyPositions) {  // SACROSANCT CHECK
      
      if(currentPrice >= ti.lastBuyPrice + gapInPrice) {
         if(OpenBuy()) {
            ti.lastBuyPrice = currentPrice;
            ti.buyPositions++;
            Print(">>> BUY MOMENTUM at ", DoubleToString(currentPrice, _Digits), 
                  " | Gap: $", DoubleToString(GapSizeDollars, 2), 
                  " | Spread: ", GetCurrentSpread(), " pts",
                  " | Total Buy: ", ti.buyPositions, "/", MaxBuyPositions);
         }
      }
   }
   
   // *** SELL MOMENTUM: Strictly enforce MaxSellPositions ***
   if((TradeDirection == TRADE_SELL || TradeDirection == TRADE_BOTH) && 
      ti.sellPositions < MaxSellPositions) {  // SACROSANCT CHECK
      
      if(currentPrice <= ti.lastSellPrice - gapInPrice) {
         if(OpenSell()) {
            ti.lastSellPrice = currentPrice;
            ti.sellPositions++;
            Print(">>> SELL MOMENTUM at ", DoubleToString(currentPrice, _Digits), 
                  " | Gap: $", DoubleToString(GapSizeDollars, 2), 
                  " | Spread: ", GetCurrentSpread(), " pts",
                  " | Total Sell: ", ti.sellPositions, "/", MaxSellPositions);
         }
      }
   }
}

bool OpenBuy() {
   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double lot = GetLotSize();
   double tp = 0, sl = 0;
   
   if(TakeProfitDollars > 0) {
      double tpPips = DollarsToPips(TakeProfitDollars, lot);
      tp = price + tpPips * _Point;
   }
   
   if(StopLossDollars > 0) {
      double slPips = DollarsToPips(StopLossDollars, lot);
      sl = price - slPips * _Point;
   }
   
   string comment = "GT16-BUY_MOMENTUM";
   return trade.Buy(lot, _Symbol, price, sl, tp, comment);
}

bool OpenSell() {
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double lot = GetLotSize();
   double tp = 0, sl = 0;
   
   if(TakeProfitDollars > 0) {
      double tpPips = DollarsToPips(TakeProfitDollars, lot);
      tp = price - tpPips * _Point;
   }
   
   if(StopLossDollars > 0) {
      double slPips = DollarsToPips(StopLossDollars, lot);
      sl = price + slPips * _Point;
   }
   
   string comment = "GT16-SELL_MOMENTUM";
   return trade.Sell(lot, _Symbol, price, sl, tp, comment);
}

void CalcTotalPL() {
   ti.totalProfit = 0;
   ti.buyPositions = ti.sellPositions = 0;
   
   for(int i = 0; i < PositionsTotal(); i++) {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket)) {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
            
            ti.totalProfit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
            
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
               ti.buyPositions++;
            } else {
               ti.sellPositions++;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check for TP/SL Closes and Rebuild if Detected                  |
//+------------------------------------------------------------------+
void CheckTPSLCloses() {
   // Detect if positions decreased (indicating TP/SL close)
   bool buyPositionClosed = (ti.buyPositions < ti.lastKnownBuyPositions);
   bool sellPositionClosed = (ti.sellPositions < ti.lastKnownSellPositions);
   
   if(buyPositionClosed || sellPositionClosed) {
      string closedType = "";
      if(buyPositionClosed && sellPositionClosed) {
         closedType = "BUY & SELL";
      } else if(buyPositionClosed) {
         closedType = "BUY";
      } else {
         closedType = "SELL";
      }
      
      ti.tpslRebuilds++;
      RebuildGrid("TP/SL Close (" + closedType + ") #" + IntegerToString(ti.tpslRebuilds));
      
      Print(">>> TP/SL DETECTED: ", closedType, " position(s) closed | Rebuilding grid");
   }
   
   // Update tracking
   ti.lastKnownBuyPositions = ti.buyPositions;
   ti.lastKnownSellPositions = ti.sellPositions;
}

void CalcNetAllPositions(double &netBuyLots, double &netSellLots, int &totalBuyCount, int &totalSellCount) {
   netBuyLots = 0; netSellLots = 0;
   totalBuyCount = 0; totalSellCount = 0;
   
   for(int i = 0; i < PositionsTotal(); i++) {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket)) {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol) {
            double volume = PositionGetDouble(POSITION_VOLUME);
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
               netBuyLots += volume;
               totalBuyCount++;
            } else {
               netSellLots += volume;
               totalSellCount++;
            }
         }
      }
   }
}

bool CheckGlobalTPSL() {
   return (GlobalTakeProfitDollars > 0 && ti.totalProfit >= GlobalTakeProfitDollars) || 
          (GlobalStopLossDollars > 0 && ti.totalProfit <= -GlobalStopLossDollars);
}

void CloseAllProfitableTrades() {
   int closedCount = 0;
   double totalProfitClosed = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket)) {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
            
            double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
            if(profit > 0) {
               totalProfitClosed += profit;
               if(trade.PositionClose(ticket)) closedCount++;
            }
         }
      }
   }
   Print("Closed ", closedCount, " profitable trades | Profit: $", FormatNumber(totalProfitClosed));
}

void RebuildGrid(string reason = "Manual") {
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double oldPrice = ti.centerPrice;
   
   ti.centerPrice = price;
   ti.lastBuyPrice = ti.lastSellPrice = price;
   
   Print("*** MOMENTUM GRID REBUILD (", reason, ") | ", DoubleToString(oldPrice, _Digits), 
         " -> ", DoubleToString(price, _Digits), " ***");
}

void AutoRebuildGrid() {
   if(ti.autoRebuilds >= MaxRebuilds) return;
   
   ti.autoRebuilds++;
   RebuildGrid("Auto #" + IntegerToString(ti.autoRebuilds));
   
   if(ti.autoRebuilds < MaxRebuilds) {
      ti.nextAutoRebuild = TimeCurrent() + (RebuildIntervalMinutes * 60);
   } else {
      ti.nextAutoRebuild = 0;
   }
}

//+------------------------------------------------------------------+
//| Event Handlers                                                   |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
   if(id == CHARTEVENT_KEYDOWN && lparam == 72) { // 'H' key
      panelVisible = !panelVisible;
      SetPanelVisibility(panelVisible);
      if(panelVisible) UpdatePanel();
      return;
   }
   
   if(id != CHARTEVENT_OBJECT_CLICK) return;
   
   if(sparam == "GT_CloseProfitsBtn") {
      CloseAllProfitableTrades();
   }
   else if(sparam == "GT_RebuildBtn") {
      RebuildGrid("Manual");
   }
   else if(sparam == "GT_PauseResumeBtn") {
      ti.isPaused = !ti.isPaused;
      if(ti.isPaused) {
         ti.nextAutoRebuild = 0;
         Print("*** MOMENTUM EA PAUSED ***");
      } else {
         RebuildGrid("Resume");
         if(EnableAutoRebuild && ti.autoRebuilds < MaxRebuilds) {
            ti.nextAutoRebuild = TimeCurrent() + (RebuildIntervalMinutes * 60);
         }
         Print("*** MOMENTUM EA RESUMED ***");
      }
   }
   
   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Enhanced Branding Functions                                      |
//+------------------------------------------------------------------+
void CreateBranding() {
   // Create main branding label - positioned outside panel area
   if(ObjectCreate(0, "GT_Brand_Main", OBJ_LABEL, 0, 0, 0)) {
      ObjectSetInteger(0, "GT_Brand_Main", OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, "GT_Brand_Main", OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, "GT_Brand_Main", OBJPROP_XDISTANCE, PanelX + 450);
      ObjectSetInteger(0, "GT_Brand_Main", OBJPROP_YDISTANCE, PanelY + 50);
      ObjectSetInteger(0, "GT_Brand_Main", OBJPROP_COLOR, C'30,30,80');
      ObjectSetInteger(0, "GT_Brand_Main", OBJPROP_FONTSIZE, 14);
      ObjectSetString(0, "GT_Brand_Main", OBJPROP_FONT, "Arial Black");
      ObjectSetString(0, "GT_Brand_Main", OBJPROP_TEXT, "TORAMA CAPITAL");
      ObjectSetInteger(0, "GT_Brand_Main", OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, "GT_Brand_Main", OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, "GT_Brand_Main", OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   }
   
   if(ObjectCreate(0, "GT_Brand_Email", OBJ_LABEL, 0, 0, 0)) {
      ObjectSetInteger(0, "GT_Brand_Email", OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, "GT_Brand_Email", OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, "GT_Brand_Email", OBJPROP_XDISTANCE, PanelX + 450);
      ObjectSetInteger(0, "GT_Brand_Email", OBJPROP_YDISTANCE, PanelY + 75);
      ObjectSetInteger(0, "GT_Brand_Email", OBJPROP_COLOR, C'60,60,60');
      ObjectSetInteger(0, "GT_Brand_Email", OBJPROP_FONTSIZE, 10);
      ObjectSetString(0, "GT_Brand_Email", OBJPROP_FONT, "Arial");
      ObjectSetString(0, "GT_Brand_Email", OBJPROP_TEXT, "ea@torama.biz");
      ObjectSetInteger(0, "GT_Brand_Email", OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, "GT_Brand_Email", OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, "GT_Brand_Email", OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   }
   
   brandingCreated = true;
}

//+------------------------------------------------------------------+
//| UI Functions                                                     |
//+------------------------------------------------------------------+
bool CreatePanel() {
   ObjectCreate(0, "GT_Panel", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "GT_Panel", OBJPROP_XDISTANCE, PanelX);
   ObjectSetInteger(0, "GT_Panel", OBJPROP_YDISTANCE, PanelY);
   ObjectSetInteger(0, "GT_Panel", OBJPROP_XSIZE, 400);
   ObjectSetInteger(0, "GT_Panel", OBJPROP_YSIZE, 395);
   ObjectSetInteger(0, "GT_Panel", OBJPROP_BGCOLOR, C'248,248,248');
   ObjectSetInteger(0, "GT_Panel", OBJPROP_BORDER_COLOR, C'70,70,70');
   ObjectSetInteger(0, "GT_Panel", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "GT_Panel", OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, "GT_Panel", OBJPROP_HIDDEN, true);
   
   CreateLabel("GT_Title", "GapTrader Pro v16.3 - Momentum Strategy", 10, 8, 11, clrNavy);
   CreateButton("GT_CloseProfitsBtn", "CLOSE PROFITS", 10, 30, 100, 25, clrGreen);
   CreateButton("GT_RebuildBtn", "REBUILD GRID", 120, 30, 100, 25, clrBlue);
   CreateButton("GT_PauseResumeBtn", "PAUSE", 230, 30, 80, 25, clrPurple);
   
   string labels[] = {
      "GT_Status", "GT_Direction", "GT_TotalPL", "GT_Positions", "GT_MaxPositions",
      "GT_MomentumLevels", "GT_NetAllPositions", "GT_CurrentPrice", "GT_GapSize", 
      "GT_NextTriggers", "GT_Spread", "GT_SpreadFilter", "GT_AutoRebuild", 
      "GT_TPSLRebuild", "GT_NextRebuild", "GT_DebugInfo"
   };
   
   int yPos = 70;
   for(int i = 0; i < ArraySize(labels); i++) {
      CreateLabel(labels[i], "", 10, yPos, 9, clrBlack);
      yPos += 18;
   }
   
   panelCreated = true;
   return true;
}

bool CreateLabel(string name, string text, int x, int y, int size, color clr) {
   if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0)) return false;
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, PanelX + x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, PanelY + y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   return true;
}

bool CreateButton(string name, string text, int x, int y, int w, int h, color clr) {
   if(!ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0)) return false;
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, PanelX + x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, PanelY + y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   return true;
}

void SetPanelVisibility(bool visible) {
   if(!panelCreated) return;
   long timeframes = visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
   
   string objects[] = {
      "GT_Panel", "GT_Title", "GT_CloseProfitsBtn", "GT_RebuildBtn", "GT_PauseResumeBtn",
      "GT_Status", "GT_Direction", "GT_TotalPL", "GT_Positions", "GT_MaxPositions",
      "GT_MomentumLevels", "GT_NetAllPositions", "GT_CurrentPrice", "GT_GapSize", 
      "GT_NextTriggers", "GT_Spread", "GT_SpreadFilter", "GT_AutoRebuild", 
      "GT_TPSLRebuild", "GT_NextRebuild", "GT_DebugInfo"
   };
   
   for(int i = 0; i < ArraySize(objects); i++) {
      ObjectSetInteger(0, objects[i], OBJPROP_TIMEFRAMES, timeframes);
   }
   ChartRedraw();
}

void UpdatePanel() {
   if(!panelCreated) return;
   
   string statusText = ti.isPaused ? "Status: PAUSED" : "Status: ACTIVE (Momentum)";
   color statusColor = ti.isPaused ? clrOrange : clrGreen;
   ObjectSetString(0, "GT_Status", OBJPROP_TEXT, statusText);
   ObjectSetInteger(0, "GT_Status", OBJPROP_COLOR, statusColor);
   
   string dir[] = {"BUY MOMENTUM ONLY", "SELL MOMENTUM ONLY", "BOTH (Buy Up + Sell Down)"};
   ObjectSetString(0, "GT_Direction", OBJPROP_TEXT, "Strategy: " + dir[TradeDirection]);
   
   string pl = "P/L: " + (ti.totalProfit >= 0 ? "+" : "") + "$" + FormatNumber(ti.totalProfit);
   ObjectSetString(0, "GT_TotalPL", OBJPROP_TEXT, pl);
   ObjectSetInteger(0, "GT_TotalPL", OBJPROP_COLOR, ti.totalProfit >= 0 ? clrGreen : clrRed);
   
   int totalPos = ti.buyPositions + ti.sellPositions;
   ObjectSetString(0, "GT_Positions", OBJPROP_TEXT, "EA Positions: " + IntegerToString(totalPos) + 
                   " (" + IntegerToString(ti.buyPositions) + "B / " + IntegerToString(ti.sellPositions) + "S)");
   
   // *** SHOW SEPARATE MAX LIMITS ***
   string maxPosText = "Max Limits: Buy=" + IntegerToString(MaxBuyPositions) + 
                      " | Sell=" + IntegerToString(MaxSellPositions);
   ObjectSetString(0, "GT_MaxPositions", OBJPROP_TEXT, maxPosText);
   color maxPosColor = clrBlue;
   if(ti.buyPositions >= MaxBuyPositions || ti.sellPositions >= MaxSellPositions) {
      maxPosColor = clrRed;
   }
   ObjectSetInteger(0, "GT_MaxPositions", OBJPROP_COLOR, maxPosColor);
   
   string momentumLevels = "Last: Buy@" + DoubleToString(ti.lastBuyPrice, _Digits) + 
                          " Sell@" + DoubleToString(ti.lastSellPrice, _Digits);
   ObjectSetString(0, "GT_MomentumLevels", OBJPROP_TEXT, momentumLevels);
   
   double netBuyLots, netSellLots;
   int totalBuyCount, totalSellCount;
   CalcNetAllPositions(netBuyLots, netSellLots, totalBuyCount, totalSellCount);
   
   string netAllText;
   color netAllColor;
   if(netBuyLots > netSellLots) {
      netAllText = "Symbol Net: BUY (" + DoubleToString(netBuyLots - netSellLots, 2) + " lots, " + 
                   IntegerToString(totalBuyCount + totalSellCount) + " pos)";
      netAllColor = clrGreen;
   } else if(netSellLots > netBuyLots) {
      netAllText = "Symbol Net: SELL (" + DoubleToString(netSellLots - netBuyLots, 2) + " lots, " + 
                   IntegerToString(totalBuyCount + totalSellCount) + " pos)";
      netAllColor = clrRed;
   } else {
      netAllText = "Symbol Net: NEUTRAL (" + IntegerToString(totalBuyCount + totalSellCount) + " pos)";
      netAllColor = clrGray;
   }
   ObjectSetString(0, "GT_NetAllPositions", OBJPROP_TEXT, netAllText);
   ObjectSetInteger(0, "GT_NetAllPositions", OBJPROP_COLOR, netAllColor);
   
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   ObjectSetString(0, "GT_CurrentPrice", OBJPROP_TEXT, "Current: " + DoubleToString(currentPrice, _Digits));
   
   double gapInPrice = DollarGapToPrice(GapSizeDollars);
   ObjectSetString(0, "GT_GapSize", OBJPROP_TEXT, "Gap: $" + FormatNumber(GapSizeDollars) + 
                   " (" + DoubleToString(gapInPrice, _Digits) + " pts)");
   
   string nextTriggers = "Next: Buy@" + DoubleToString(ti.lastBuyPrice + gapInPrice, _Digits) +
                        " Sell@" + DoubleToString(ti.lastSellPrice - gapInPrice, _Digits);
   ObjectSetString(0, "GT_NextTriggers", OBJPROP_TEXT, nextTriggers);
   
   // Current spread display
   int currentSpread = GetCurrentSpread();
   string spreadText = "Current Spread: " + IntegerToString(currentSpread) + " points";
   ObjectSetString(0, "GT_Spread", OBJPROP_TEXT, spreadText);
   
   // Spread filter status
   bool spreadOK = IsSpreadAcceptable();
   string filterText;
   color filterColor;
   
   if(EnableSpreadFilter) {
      if(spreadOK) {
         filterText = "Spread Filter: OK (Max: " + IntegerToString(MaxSpreadPoints) + " pts)";
         filterColor = clrGreen;
      } else {
         filterText = "Spread Filter: BLOCKED! (Max: " + IntegerToString(MaxSpreadPoints) + " pts) #" + IntegerToString(ti.spreadBlockCount);
         filterColor = clrRed;
      }
   } else {
      filterText = "Spread Filter: DISABLED";
      filterColor = clrGray;
   }
   
   ObjectSetString(0, "GT_SpreadFilter", OBJPROP_TEXT, filterText);
   ObjectSetInteger(0, "GT_SpreadFilter", OBJPROP_COLOR, filterColor);
   
   ObjectSetString(0, "GT_AutoRebuild", OBJPROP_TEXT, "Auto Rebuilds: " + IntegerToString(ti.autoRebuilds) + "/" + IntegerToString(MaxRebuilds));
   
   // TP/SL Rebuild counter
   string tpslRebuildText = "TP/SL Rebuilds: " + (RebuildOnTPSL ? IntegerToString(ti.tpslRebuilds) : "DISABLED");
   ObjectSetString(0, "GT_TPSLRebuild", OBJPROP_TEXT, tpslRebuildText);
   color tpslColor = RebuildOnTPSL ? clrBlue : clrGray;
   ObjectSetInteger(0, "GT_TPSLRebuild", OBJPROP_COLOR, tpslColor);
   
   string nextRebuildText = "Next Rebuild: " + FormatTimeRemaining(ti.nextAutoRebuild);
   ObjectSetString(0, "GT_NextRebuild", OBJPROP_TEXT, nextRebuildText);
   
   string debugText = "TickVal: " + DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), 2) +
                     " | Lot: " + DoubleToString(GetLotSize(), 2);
   ObjectSetString(0, "GT_DebugInfo", OBJPROP_TEXT, debugText);
   ObjectSetInteger(0, "GT_DebugInfo", OBJPROP_COLOR, clrGray);
   
   ObjectSetString(0, "GT_PauseResumeBtn", OBJPROP_TEXT, ti.isPaused ? "RESUME" : "PAUSE");
   ObjectSetInteger(0, "GT_PauseResumeBtn", OBJPROP_BGCOLOR, ti.isPaused ? clrGreen : clrPurple);
}