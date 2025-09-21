//+------------------------------------------------------------------+
//|                           Advanced Trend EA v10.06 - COMPLETE   |
//|              Clean Dashboard + Working Reverse Direction         |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Your Company"
#property version   "10.06"
#property description "Professional Trend EA - Optimized for Crypto Trading"

#include <Trade\Trade.mqh>
CTrade trade;

enum ENUM_TRADE_DIRECTION { TRADE_BUY_ONLY = 0, TRADE_SELL_ONLY = 1, TRADE_BOTH_SIDES = 2 };

// Input parameters
input group "TRADING SETTINGS"
input double InitialLotSize = 0.1;
input ENUM_TIMEFRAMES TradingTimeframe = PERIOD_M1;
input double IndividualTradeTP = 2.0;
input long TPPipsBackup = 50;
input double DrawdownLimit = 20.0;
input long MaxBuyTrades = 50;
input long MaxSellTrades = 50;

input group "LOT SIZE COMPOUNDING"
input bool EnableLotCompounding = true;
input double LotSizeIncrement = 0.01;
input double EquityThreshold = 500.0;

input group "CONSECUTIVE CANDLES TP"
input bool EnableConsecutiveCandlesTP = false;
input int ConsecutiveCandlesCount = 3;

input group "S/R SETTINGS"
input bool EnableSRDetection = true;
input int SRLookbackBars = 100;
input double SRProximityPercent = 0.2;
input bool ShowSRLines = true;
input color ResistanceColor = clrRed;
input color SupportColor = clrGreen;

input group "S/R BEHAVIOR"
input bool PauseBuyNearResistance = false;
input bool PauseSellNearSupport = false;
input bool ReverseTradingAtSR = false;
input bool SellAtResistanceInBuyMode = false;
input bool BuyAtSupportInSellMode = false;

input group "TRADING DIRECTION"
input ENUM_TRADE_DIRECTION TradeDirection = TRADE_BOTH_SIDES;

input group "CRYPTO SETTINGS"
input double CryptoMinMovement = 100.0;
input double CryptoMaxMovement = 50000.0;

input group "SESSION SETTINGS"
input bool ShowSessionLines = true;
input color LondonSessionColor = clrBlue;
input color NewYorkSessionColor = clrRed;

input group "EA SETTINGS"
input long MagicNumber = 777000;
input bool EnableSounds = false;
input bool EnableDashboard = true;
input long panelHeight = 340;

// Global variables
datetime lastCandleTime = 0;
double dailyStartBalance = 0;
double currentLotSize = 0;
bool tradingPaused = false;
bool buyPausedNearResistance = false;
bool sellPausedNearSupport = false;
bool shouldSellAtResistance = false;
bool shouldBuyAtSupport = false;
ENUM_TIMEFRAMES WorkingTimeframe = PERIOD_M1;
bool isCryptoPair = false;
string symbolType = "";
ENUM_TRADE_DIRECTION currentTradeDirection = TRADE_BOTH_SIDES;

// S/R levels
double currentH4Resistance = 0;
double currentH4Support = 0;
double currentH1Resistance = 0;
double currentH1Support = 0;
datetime lastSRCalculation = 0;

// Panel config
bool panelVisible = true;
long panelX = 15, panelY = 35, panelWidth = 300;

// Session times (GMT)
int LondonOpenHour = 8, LondonCloseHour = 16;
int NewYorkOpenHour = 13, NewYorkCloseHour = 21;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("==========================================");
    Print("Advanced Trend EA v10.06 INITIALIZING...");
    Print("==========================================");
    
    DetectSymbolType();
    
    trade.SetExpertMagicNumber((ulong)MagicNumber);
    trade.SetDeviationInPoints(20);
    trade.SetTypeFilling(ORDER_FILLING_FOK);
    trade.LogLevel(LOG_LEVEL_ERRORS);
    
    WorkingTimeframe = TradingTimeframe;
    currentTradeDirection = TradeDirection;
    dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    currentLotSize = CalculateCompoundedLotSize();
    lastCandleTime = iTime(_Symbol, WorkingTimeframe, 0);
    
    if(!ValidateAllInputs()) return INIT_PARAMETERS_INCORRECT;
    
    if(EnableSRDetection) {
        CalculateSupportResistance();
        if(ShowSRLines) DrawSRLines();
    }
    
    if(EnableDashboard) {
        CreateProfessionalPanel();
        CreateControlButtons();
    }
    
    if(ShowSessionLines) CreateSessionLines();
    
    EventSetTimer(2);
    
    Print("EA INITIALIZATION COMPLETE");
    Print("==========================================");
    Print("Symbol: ", _Symbol, " (", GetSymbolTypeString(), ")");
    Print("Working Timeframe: ", EnumToString(TradingTimeframe));
    Print("Starting Balance: $", DoubleToString(dailyStartBalance, 2));
    Print("Current Equity: $", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));
    Print("Current Lot Size: ", DoubleToString(currentLotSize, 3), " | Magic: ", (long)MagicNumber);
    
    if(EnableLotCompounding) {
        Print("LOT COMPOUNDING: ENABLED");
        Print("  - Increment: ", DoubleToString(LotSizeIncrement, 3), " lots per $", DoubleToString(EquityThreshold, 0));
        Print("  - Formula: (Equity ÷ ", DoubleToString(EquityThreshold, 0), ") × ", DoubleToString(LotSizeIncrement, 3));
        Print("  - Minimum Lot: ", DoubleToString(InitialLotSize, 3));
    } else {
        Print("LOT COMPOUNDING: DISABLED (Fixed lot: ", DoubleToString(currentLotSize, 3), ")");
    }
    
    Print("TP: ", IndividualTradeTP, "% = $", DoubleToString(CalculateTPAmount(), 2));
    Print("Trade Direction: ", GetTradeDirectionString());
    
    if(EnableConsecutiveCandlesTP) {
        Print("CONSECUTIVE CANDLES TP: ENABLED (", ConsecutiveCandlesCount, " candles)");
        Print("  - BUY positions close on ", ConsecutiveCandlesCount, " consecutive BULLISH candles");
        Print("  - SELL positions close on ", ConsecutiveCandlesCount, " consecutive BEARISH candles");
    } else {
        Print("CONSECUTIVE CANDLES TP: DISABLED");
    }
    
    Print("REVERSE DIRECTION BUTTON: ", (currentTradeDirection != TRADE_BOTH_SIDES ? "ACTIVE" : "DISABLED (Both Sides Mode)"));
    Print("==========================================");
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Calculate Compounded Lot Size Based on Equity                   |
//+------------------------------------------------------------------+
double CalculateCompoundedLotSize()
{
    if(!EnableLotCompounding) {
        return NormalizeLotSize(InitialLotSize);
    }
    
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(currentEquity <= 0 || EquityThreshold <= 0) {
        return NormalizeLotSize(InitialLotSize);
    }
    
    double equityMultiplier = currentEquity / EquityThreshold;
    double compoundedLotSize = equityMultiplier * LotSizeIncrement;
    compoundedLotSize = MathMax(InitialLotSize, compoundedLotSize);
    
    return NormalizeLotSize(compoundedLotSize);
}

//+------------------------------------------------------------------+
//| Check Consecutive Candles for Take Profit                       |
//+------------------------------------------------------------------+
bool CheckConsecutiveCandlesTP(ENUM_POSITION_TYPE positionType)
{
    if(!EnableConsecutiveCandlesTP || ConsecutiveCandlesCount <= 0) 
        return false;
    
    double closes[], opens[];
    ArrayResize(closes, ConsecutiveCandlesCount + 1);
    ArrayResize(opens, ConsecutiveCandlesCount + 1);
    
    if(CopyClose(_Symbol, WorkingTimeframe, 1, ConsecutiveCandlesCount + 1, closes) <= 0 ||
       CopyOpen(_Symbol, WorkingTimeframe, 1, ConsecutiveCandlesCount + 1, opens) <= 0)
        return false;
    
    int consecutiveCount = 0;
    bool lookingForBullish = (positionType == POSITION_TYPE_BUY);
    bool lookingForBearish = (positionType == POSITION_TYPE_SELL);
    
    for(int i = 0; i < ConsecutiveCandlesCount; i++) {
        bool isBullish = closes[i] > opens[i];
        bool isBearish = closes[i] < opens[i];
        
        if((lookingForBullish && isBullish) || (lookingForBearish && isBearish)) {
            consecutiveCount++;
        } else {
            break;
        }
    }
    
    return consecutiveCount >= ConsecutiveCandlesCount;
}

//+------------------------------------------------------------------+
//| Check Consecutive Candles TP for All Positions                  |
//+------------------------------------------------------------------+
void CheckConsecutiveCandlesTPForAllPositions()
{
    if(!EnableConsecutiveCandlesTP) return;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == (long)MagicNumber) {
            double profit = PositionGetDouble(POSITION_PROFIT);
            
            if(profit > 0) {
                ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                
                if(CheckConsecutiveCandlesTP(posType)) {
                    ulong ticket = PositionGetTicket(i);
                    double lotSize = PositionGetDouble(POSITION_VOLUME);
                    
                    if(trade.PositionClose(ticket)) {
                        string posTypeStr = (posType == POSITION_TYPE_BUY) ? "BUY" : "SELL";
                        string candleTypeStr = (posType == POSITION_TYPE_BUY) ? "BULLISH" : "BEARISH";
                        Print("CONSECUTIVE CANDLES TP HIT: ", posTypeStr, " #", ticket, 
                              " | Lot: ", DoubleToString(lotSize, 3),
                              " | ", ConsecutiveCandlesCount, " ", candleTypeStr, " candles | Profit: $", DoubleToString(profit, 2));
                        
                        if(EnableSounds) PlaySound("alert.wav");
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Reverse Trade Direction Function                                |
//+------------------------------------------------------------------+
void ReverseTradeDirection()
{
    if(currentTradeDirection == TRADE_BOTH_SIDES) {
        Print("ERROR: Cannot reverse direction when trading BOTH SIDES");
        return;
    }
    
    ENUM_TRADE_DIRECTION previousDirection = currentTradeDirection;
    
    if(currentTradeDirection == TRADE_BUY_ONLY) {
        currentTradeDirection = TRADE_SELL_ONLY;
    }
    else if(currentTradeDirection == TRADE_SELL_ONLY) {
        currentTradeDirection = TRADE_BUY_ONLY;
    }
    
    Print("==========================================");
    Print("TRADE DIRECTION REVERSED BY USER");
    Print("Previous: ", GetTradeDirectionStringFromEnum(previousDirection));
    Print("Current: ", GetTradeDirectionStringFromEnum(currentTradeDirection));
    Print("==========================================");
    
    if(EnableSounds) PlaySound("alert2.wav");
    
    // Update dashboard to reflect new direction
    if(EnableDashboard && panelVisible) {
        UpdateRealTimeDashboard();
    }
    
    // Force chart redraw to update display immediately
    ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Get Direction String from Enum                                  |
//+------------------------------------------------------------------+
string GetTradeDirectionStringFromEnum(ENUM_TRADE_DIRECTION direction)
{
    switch(direction) {
        case TRADE_BUY_ONLY:  return "BUY ONLY";
        case TRADE_SELL_ONLY: return "SELL ONLY";
        case TRADE_BOTH_SIDES: return "BOTH SIDES";
        default: return "UNKNOWN";
    }
}

//+------------------------------------------------------------------+
//| Calculate Support and Resistance Levels                         |
//+------------------------------------------------------------------+
void CalculateSupportResistance()
{
    if(!EnableSRDetection) return;
    
    CalculateTimeframeSR(PERIOD_H4, currentH4Resistance, currentH4Support);
    CalculateTimeframeSR(PERIOD_H1, currentH1Resistance, currentH1Support);
    
    lastSRCalculation = TimeCurrent();
}

void CalculateTimeframeSR(ENUM_TIMEFRAMES timeframe, double &resistance, double &support)
{
    int bars = iBars(_Symbol, timeframe);
    if(bars < SRLookbackBars) return;
    
    double highs[], lows[];
    ArrayResize(highs, SRLookbackBars);
    ArrayResize(lows, SRLookbackBars);
    
    if(CopyHigh(_Symbol, timeframe, 0, SRLookbackBars, highs) <= 0 ||
       CopyLow(_Symbol, timeframe, 0, SRLookbackBars, lows) <= 0) return;
    
    double highestHigh = highs[ArrayMaximum(highs)];
    double lowestLow = lows[ArrayMinimum(lows)];
    
    double significantResistance = 0;
    double significantSupport = DBL_MAX;
    
    for(int i = 10; i < SRLookbackBars - 10; i++) {
        double high = highs[i];
        double low = lows[i];
        
        bool isPeak = true;
        bool isTrough = true;
        
        for(int j = i-3; j <= i+3; j++) {
            if(j != i && j >= 0 && j < SRLookbackBars) {
                if(highs[j] > high) isPeak = false;
                if(lows[j] < low) isTrough = false;
            }
        }
        
        if(isPeak && high > significantResistance && high < highestHigh)
            significantResistance = high;
        
        if(isTrough && low < significantSupport && low > lowestLow)
            significantSupport = low;
    }
    
    resistance = significantResistance > 0 ? significantResistance : highestHigh;
    support = significantSupport < DBL_MAX ? significantSupport : lowestLow;
}

//+------------------------------------------------------------------+
//| Check S/R Trading Conditions                                    |
//+------------------------------------------------------------------+
void CheckSRTradingConditions()
{
    if(!EnableSRDetection) return;
    
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    buyPausedNearResistance = PauseBuyNearResistance && IsNearResistance(currentPrice);
    sellPausedNearSupport = PauseSellNearSupport && IsNearSupport(currentPrice);
    shouldSellAtResistance = ReverseTradingAtSR && currentTradeDirection == TRADE_BUY_ONLY && 
                            SellAtResistanceInBuyMode && IsNearResistance(currentPrice);
    shouldBuyAtSupport = ReverseTradingAtSR && currentTradeDirection == TRADE_SELL_ONLY && 
                        BuyAtSupportInSellMode && IsNearSupport(currentPrice);
}

bool IsNearResistance(double price)
{
    if(!EnableSRDetection || currentH4Resistance <= 0) return false;
    double proximity = currentH4Resistance * (SRProximityPercent / 100.0);
    return (price >= currentH4Resistance - proximity && price <= currentH4Resistance + proximity);
}

bool IsNearSupport(double price)
{
    if(!EnableSRDetection || currentH4Support <= 0) return false;
    double proximity = currentH4Support * (SRProximityPercent / 100.0);
    return (price >= currentH4Support - proximity && price <= currentH4Support + proximity);
}

//+------------------------------------------------------------------+
//| Draw S/R Lines                                                   |
//+------------------------------------------------------------------+
void DrawSRLines()
{
    if(!ShowSRLines || !EnableSRDetection) return;
    
    string objects[] = {"H4_Resistance_Line", "H4_Support_Line", "H1_Resistance_Line", "H1_Support_Line",
                       "H4_Resistance_Label", "H4_Support_Label", "H1_Resistance_Label", "H1_Support_Label"};
    
    for(int i = 0; i < ArraySize(objects); i++)
        ObjectDelete(0, objects[i]);
    
    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    
    CreateHLine("H4_Resistance_Line", currentH4Resistance, ResistanceColor, 3, STYLE_SOLID);
    CreateHLine("H4_Support_Line", currentH4Support, SupportColor, 3, STYLE_SOLID);
    CreateHLine("H1_Resistance_Line", currentH1Resistance, ResistanceColor, 1, STYLE_DASH);
    CreateHLine("H1_Support_Line", currentH1Support, SupportColor, 1, STYLE_DASH);
    
    CreateLabel("H4_Resistance_Label", " ← H4 RESISTANCE", currentH4Resistance, ResistanceColor, 10);
    CreateLabel("H4_Support_Label", " ← H4 SUPPORT", currentH4Support, SupportColor, 10);
    CreateLabel("H1_Resistance_Label", " ← H1 RES", currentH1Resistance, ResistanceColor, 8);
    CreateLabel("H1_Support_Label", " ← H1 SUP", currentH1Support, SupportColor, 8);
    
    ChartRedraw(0);
}

void CreateHLine(string name, double price, color clr, int width, ENUM_LINE_STYLE style)
{
    if(ObjectCreate(0, name, OBJ_HLINE, 0, 0, price)) {
        ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
        ObjectSetInteger(0, name, OBJPROP_STYLE, style);
        ObjectSetInteger(0, name, OBJPROP_BACK, false);
    }
}

void CreateLabel(string name, string text, double price, color clr, int size)
{
    if(ObjectCreate(0, name, OBJ_TEXT, 0, TimeCurrent(), price)) {
        ObjectSetString(0, name, OBJPROP_TEXT, text);
        ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
        ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
        ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT);
    }
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    EventKillTimer();
    
    string objects[] = {"EA_Panel_Background", "EA_Panel_Header", "EA_Panel_Title", "EA_Toggle_Hint",
                       "Btn_CloseProfits", "Btn_CloseAll", "Btn_PauseResume", "Btn_ReverseDirection",
                       "LondonSession_Line", "NewYorkSession_Line", "LondonSession_Label", 
                       "NewYorkSession_Label", "H4_Resistance_Line", "H4_Support_Line", 
                       "H4_Resistance_Label", "H4_Support_Label", "H1_Resistance_Line", 
                       "H1_Support_Line", "H1_Resistance_Label", "H1_Support_Label"};
    
    for(int i = 0; i < ArraySize(objects); i++)
        ObjectDelete(0, objects[i]);
    
    for(int i = 0; i < 70; i++)
        ObjectDelete(0, "Dashboard_" + IntegerToString(i));
    
    ChartRedraw(0);
    
    Print("Advanced Trend EA v10.06 DEINITIALIZED");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || 
       !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) ||
       !SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) || tradingPaused)
        return;
    
    if(EnableSRDetection && TimeCurrent() - lastSRCalculation > 1800) {
        CalculateSupportResistance();
        if(ShowSRLines) DrawSRLines();
    }
    
    CheckSRTradingConditions();
    
    datetime currentCandle = iTime(_Symbol, WorkingTimeframe, 0);
    if(currentCandle != lastCandleTime && currentCandle > 0) {
        lastCandleTime = currentCandle;
        
        if(EnableLotCompounding) {
            double newLotSize = CalculateCompoundedLotSize();
            if(newLotSize != currentLotSize) {
                Print("LOT SIZE UPDATED: ", DoubleToString(currentLotSize, 3), " → ", 
                      DoubleToString(newLotSize, 3), " (Equity: $", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2), ")");
                currentLotSize = newLotSize;
            }
        }
        
        long buyPositions = CountPositions(POSITION_TYPE_BUY);
        long sellPositions = CountPositions(POSITION_TYPE_SELL);
        
        bool canOpenBuy = (currentTradeDirection == TRADE_BUY_ONLY || currentTradeDirection == TRADE_BOTH_SIDES) && buyPositions < MaxBuyTrades;
        bool canOpenSell = (currentTradeDirection == TRADE_SELL_ONLY || currentTradeDirection == TRADE_BOTH_SIDES) && sellPositions < MaxSellTrades;
        
        if(canOpenBuy || canOpenSell)
            ExecuteAdvancedTradingLogic();
    }
    
    CheckPercentageBasedTP();
    CheckConsecutiveCandlesTPForAllPositions();
    
    if(ShowSessionLines) UpdateSessionLines();
    
    double currentDD = GetCurrentDrawdown();
    if(currentDD >= DrawdownLimit && !tradingPaused) {
        tradingPaused = true;
        Print("DRAWDOWN LIMIT REACHED: ", DoubleToString(currentDD, 2), "% - TRADING PAUSED");
        if(EnableSounds) PlaySound("alert.wav");
    }
}

//+------------------------------------------------------------------+
//| Execute Trading Logic                                            |
//+------------------------------------------------------------------+
void ExecuteAdvancedTradingLogic()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    if(ask <= 0 || bid <= 0) return;
    
    long buyPositions = CountPositions(POSITION_TYPE_BUY);
    long sellPositions = CountPositions(POSITION_TYPE_SELL);
    
    double lotSize = NormalizeLotSize(currentLotSize);
    bool executeBuy = false;
    bool executeSell = false;
    
    if((currentTradeDirection == TRADE_BUY_ONLY || currentTradeDirection == TRADE_BOTH_SIDES) && 
       !buyPausedNearResistance && buyPositions < MaxBuyTrades)
        executeBuy = true;
    
    if((currentTradeDirection == TRADE_SELL_ONLY || currentTradeDirection == TRADE_BOTH_SIDES) && 
       !sellPausedNearSupport && sellPositions < MaxSellTrades)
        executeSell = true;
    
    if(shouldSellAtResistance && sellPositions < MaxSellTrades) {
        executeBuy = false;
        executeSell = true;
    }
    
    if(shouldBuyAtSupport && buyPositions < MaxBuyTrades) {
        executeSell = false;
        executeBuy = true;
    }
    
    if(executeBuy) {
        double buyTP = CalculateTPPrice(true, ask);
        if(buyTP <= ask) buyTP = ask + (isCryptoPair ? CryptoMinMovement : TPPipsBackup * SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10);
        
        if(trade.Buy(lotSize, _Symbol, ask, 0, buyTP, "ADV_TRENDEA_v10.06")) {
            Print("BUY ORDER PLACED: #", trade.ResultOrder(), 
                  " | Lot: ", DoubleToString(lotSize, 3), 
                  " | Price: ", DoubleToString(ask, _Digits),
                  " | TP: ", DoubleToString(buyTP, _Digits),
                  " | Equity: $", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));
        }
    }
    
    if(executeSell) {
        double sellTP = CalculateTPPrice(false, bid);
        if(sellTP >= bid) sellTP = bid - (isCryptoPair ? CryptoMinMovement : TPPipsBackup * SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10);
        
        if(trade.Sell(lotSize, _Symbol, bid, 0, sellTP, "ADV_TRENDEA_v10.06")) {
            Print("SELL ORDER PLACED: #", trade.ResultOrder(), 
                  " | Lot: ", DoubleToString(lotSize, 3), 
                  " | Price: ", DoubleToString(bid, _Digits),
                  " | TP: ", DoubleToString(sellTP, _Digits),
                  " | Equity: $", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));
        }
    }
}

//+------------------------------------------------------------------+
//| Chart event function                                             |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    if(id == CHARTEVENT_KEYDOWN && (lparam == 72 || lparam == 104)) {
        TogglePanelVisibility();
    }
    
    if(id == CHARTEVENT_OBJECT_CLICK) {
        if(sparam == "Btn_CloseProfits") {
            CloseAllProfitablePositions();
            ObjectSetInteger(0, "Btn_CloseProfits", OBJPROP_STATE, false);
        }
        else if(sparam == "Btn_CloseAll") {
            CloseAllTrades();
            ObjectSetInteger(0, "Btn_CloseAll", OBJPROP_STATE, false);
        }
        else if(sparam == "Btn_PauseResume") {
            tradingPaused = !tradingPaused;
            ObjectSetString(0, "Btn_PauseResume", OBJPROP_TEXT, tradingPaused ? "Resume" : "Pause");
            ObjectSetInteger(0, "Btn_PauseResume", OBJPROP_BGCOLOR, tradingPaused ? clrBlue : clrOrange);
            ObjectSetInteger(0, "Btn_PauseResume", OBJPROP_STATE, false);
            Print("Trading ", tradingPaused ? "PAUSED" : "RESUMED", " by user");
        }
        else if(sparam == "Btn_ReverseDirection") {
            ReverseTradeDirection();
            ObjectSetInteger(0, "Btn_ReverseDirection", OBJPROP_STATE, false);
        }
        ChartRedraw(0);
    }
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
    if(EnableDashboard && panelVisible) UpdateRealTimeDashboard();
    if(ShowSessionLines) UpdateSessionLines();
    
    if(ShowSRLines && EnableSRDetection) {
        ObjectSetInteger(0, "H4_Resistance_Label", OBJPROP_TIME, TimeCurrent());
        ObjectSetInteger(0, "H4_Support_Label", OBJPROP_TIME, TimeCurrent());
        ObjectSetInteger(0, "H1_Resistance_Label", OBJPROP_TIME, TimeCurrent());
        ObjectSetInteger(0, "H1_Support_Label", OBJPROP_TIME, TimeCurrent());
    }
}

//+------------------------------------------------------------------+
//| Panel Functions                                                  |
//+------------------------------------------------------------------+
void CreateProfessionalPanel()
{
    CreateRectLabel("EA_Panel_Background", panelX, panelY, panelWidth, panelHeight, C'20,20,25', C'100,100,120');
    CreateRectLabel("EA_Panel_Header", panelX, panelY, panelWidth, 32, C'0,60,120', C'0,80,160');
    CreateTextLabel("EA_Panel_Title", panelX + 12, panelY + 7, "TigerTrend v10.06", clrWhite, 11);
    CreateTextLabel("EA_Toggle_Hint", panelX + panelWidth - 110, panelY + 10, "Press H to toggle", clrLightGray, 8);
    
    UpdateRealTimeDashboard();
}

void CreateControlButtons()
{
    long btnWidth = 100, btnHeight = 30, startX = panelX + 12, startY = panelY + 40;
    
    CreateButton("Btn_CloseProfits", startX, startY, btnWidth, btnHeight, "Close Profits", clrGreen);
    CreateButton("Btn_PauseResume", startX + btnWidth + 10, startY, btnWidth, btnHeight, 
                tradingPaused ? "Resume" : "Pause", tradingPaused ? clrBlue : clrOrange);
    
    // Bottom buttons side by side
    long bottomBtnWidth = 130;
    long bottomBtnY = panelY + panelHeight - 45;
    
    if(currentTradeDirection != TRADE_BOTH_SIDES) {
        CreateButton("Btn_ReverseDirection", panelX + 12, bottomBtnY, bottomBtnWidth, 35, 
                    "Reverse Dir", clrPurple);
    }
    
    CreateButton("Btn_CloseAll", panelX + 12 + bottomBtnWidth + 10, bottomBtnY, bottomBtnWidth, 35, "Close All", clrRed);
}

void CreateSessionLines()
{
    CreateVLine("LondonSession_Line", LondonSessionColor, STYLE_DASH);
    CreateVLine("NewYorkSession_Line", NewYorkSessionColor, STYLE_DASH);
    UpdateSessionLines();
}

void UpdateSessionLines()
{
    MqlDateTime currentTime;
    TimeToStruct(TimeCurrent(), currentTime);
    
    datetime todayLondonOpen = StructToTime(currentTime) - (currentTime.hour * 3600) - (currentTime.min * 60) - currentTime.sec + LondonOpenHour * 3600;
    datetime todayNYOpen = StructToTime(currentTime) - (currentTime.hour * 3600) - (currentTime.min * 60) - currentTime.sec + NewYorkOpenHour * 3600;
    
    ObjectSetInteger(0, "LondonSession_Line", OBJPROP_TIME, todayLondonOpen);
    ObjectSetInteger(0, "NewYorkSession_Line", OBJPROP_TIME, todayNYOpen);
}

void UpdateRealTimeDashboard()
{
    if(!panelVisible || !EnableDashboard) return;
    
    string dashObjects[] = {"Dashboard_BalanceEquity", "Dashboard_DailyPL", 
                           "Dashboard_TotalPos", "Dashboard_Buy_Count", "Dashboard_Sell_Count",
                           "Dashboard_TP_Percentage", "Dashboard_Trade_Direction", 
                           "Dashboard_ConsecutiveTP", "Dashboard_ConsecutiveStatus",
                           "Dashboard_LotSize", "Dashboard_LotCompounding", "Dashboard_NextLotLevel"};
    
    for(int i = 0; i < ArraySize(dashObjects); i++)
        ObjectDelete(0, dashObjects[i]);
    
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double dailyPL = equity - dailyStartBalance;
    double tpAmount = CalculateTPAmount();
    
    long totalPositions = CountPositions(-1);
    long buyPositions = CountPositions(POSITION_TYPE_BUY);
    long sellPositions = CountPositions(POSITION_TYPE_SELL);
    
    long leftX = panelX + 18, startY = panelY + 85;
    int spacing = 16, line = 0;
    
    // Combined Balance and Equity on one line
    CreateTextLabel("Dashboard_BalanceEquity", leftX, startY + (line++ * spacing), 
                   "Bal: $" + DoubleToString(balance, 2) + " | Eq: $" + DoubleToString(equity, 2), clrWhite, 11);
    line++;
    
    CreateTextLabel("Dashboard_DailyPL", leftX, startY + (line++ * spacing), 
                   "Daily: " + (dailyPL >= 0 ? "+" : "") + DoubleToString(dailyPL, 2), 
                   dailyPL >= 0 ? clrLime : clrRed, 10);
    CreateTextLabel("Dashboard_TotalPos", leftX, startY + (line++ * spacing), 
                   "Total Positions: " + IntegerToString((int)totalPositions), clrWhite, 10);
    CreateTextLabel("Dashboard_Buy_Count", leftX, startY + (line++ * spacing), 
                   "Buy: " + IntegerToString((int)buyPositions) + "/" + IntegerToString((int)MaxBuyTrades), clrLime, 10);
    CreateTextLabel("Dashboard_Sell_Count", leftX, startY + (line++ * spacing), 
                   "Sell: " + IntegerToString((int)sellPositions) + "/" + IntegerToString((int)MaxSellTrades), clrOrange, 10);
    line++;
    
    CreateTextLabel("Dashboard_Trade_Direction", leftX, startY + (line++ * spacing), 
                   "Direction: " + GetTradeDirectionString(), 
                   GetTradeDirectionColor(), 10);
    
    CreateTextLabel("Dashboard_LotSize", leftX, startY + (line++ * spacing), 
                   "Current Lot: " + DoubleToString(currentLotSize, 3), clrYellow, 10);
    
    if(EnableLotCompounding) {
        CreateTextLabel("Dashboard_LotCompounding", leftX, startY + (line++ * spacing), 
                       "Compounding: " + DoubleToString(LotSizeIncrement, 3) + " per $" + DoubleToString(EquityThreshold, 0), 
                       clrLightGreen, 9);
        
        double nextLotLevel = MathCeil(equity / EquityThreshold) * EquityThreshold;
        if(nextLotLevel > equity) {
            double neededForNextLot = nextLotLevel - equity;
            CreateTextLabel("Dashboard_NextLotLevel", leftX, startY + (line++ * spacing), 
                           "Next lot at: $" + DoubleToString(nextLotLevel, 0) + " (+" + DoubleToString(neededForNextLot, 0) + ")", 
                           clrAqua, 8);
        }
    } else {
        CreateTextLabel("Dashboard_LotCompounding", leftX, startY + (line++ * spacing), 
                       "Fixed Lot Size", clrGray, 9);
    }
    
    CreateTextLabel("Dashboard_ConsecutiveTP", leftX, startY + (line++ * spacing), 
                   "Candles TP: " + (EnableConsecutiveCandlesTP ? "ON (" + IntegerToString(ConsecutiveCandlesCount) + ")" : "OFF"), 
                   EnableConsecutiveCandlesTP ? clrLightGreen : clrGray, 9);
    
    if(EnableConsecutiveCandlesTP) {
        CreateTextLabel("Dashboard_ConsecutiveStatus", leftX, startY + (line++ * spacing), 
                       "BUY→Bull | SELL→Bear", clrLightBlue, 8);
    }
    
    CreateTextLabel("Dashboard_TP_Percentage", leftX, startY + (line++ * spacing), 
                   "TP: " + DoubleToString(IndividualTradeTP, 1) + "% = $" + DoubleToString(tpAmount, 2), 
                   clrCyan, 9);
    
    ChartRedraw(0);
}

void TogglePanelVisibility()
{
    panelVisible = !panelVisible;
    string objects[] = {"EA_Panel_Background", "EA_Panel_Header", "EA_Panel_Title", "EA_Toggle_Hint",
                       "Btn_CloseProfits", "Btn_CloseAll", "Btn_PauseResume", "Btn_ReverseDirection"};
    
    for(int i = 0; i < ArraySize(objects); i++)
        ObjectSetInteger(0, objects[i], OBJPROP_TIMEFRAMES, panelVisible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
    
    if(panelVisible) UpdateRealTimeDashboard();
    ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Helper Functions                                                 |
//+------------------------------------------------------------------+
void CreateRectLabel(string name, long x, long y, long width, long height, color bg, color border)
{
    ObjectDelete(0, name);
    if(ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0)) {
        ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
        ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
        ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
        ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
        ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
        ObjectSetInteger(0, name, OBJPROP_COLOR, border);
        ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
        ObjectSetInteger(0, name, OBJPROP_BACK, false);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
    }
}

void CreateTextLabel(string name, long x, long y, string text, color clr, int size)
{
    ObjectDelete(0, name);
    if(ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0)) {
        ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
        ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
        ObjectSetString(0, name, OBJPROP_TEXT, text);
        ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
        ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
    }
}

void CreateButton(string name, long x, long y, long width, long height, string text, color bg)
{
    ObjectDelete(0, name);
    if(ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0)) {
        ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
        ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
        ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
        ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
        ObjectSetString(0, name, OBJPROP_TEXT, text);
        ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
        ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
        ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
        ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
    }
}

void CreateVLine(string name, color clr, ENUM_LINE_STYLE style)
{
    ObjectDelete(0, name);
    if(ObjectCreate(0, name, OBJ_VLINE, 0, 0, 0)) {
        ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, name, OBJPROP_STYLE, style);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
        ObjectSetInteger(0, name, OBJPROP_BACK, false);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
    }
}

bool DetectSymbolType()
{
    string symbol = _Symbol;
    string cryptos[] = {"BTC", "ETH", "XRP", "LTC", "ADA", "DOT", "SOL", "MATIC", "AVAX", "LINK"};
    
    isCryptoPair = false;
    for(int i = 0; i < ArraySize(cryptos); i++) {
        if(StringFind(symbol, cryptos[i]) >= 0) {
            isCryptoPair = true;
            break;
        }
    }
    
    symbolType = isCryptoPair ? "CRYPTO" : "FOREX";
    return isCryptoPair;
}

string GetSymbolTypeString() { return symbolType; }

string GetTradeDirectionString()
{
    return GetTradeDirectionStringFromEnum(currentTradeDirection);
}

color GetTradeDirectionColor()
{
    switch(currentTradeDirection) {
        case TRADE_BUY_ONLY:  return clrLime;
        case TRADE_SELL_ONLY: return clrOrange;
        case TRADE_BOTH_SIDES: return clrCyan;
        default: return clrWhite;
    }
}

double CalculateTPAmount()
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    return balance > 0 ? balance * (IndividualTradeTP / 100.0) : 1000 * (IndividualTradeTP / 100.0);
}

double CalculateTPMovement()
{
    double tpAmountUSD = CalculateTPAmount();
    double lotSize = currentLotSize;
    
    if(isCryptoPair) {
        double pointValue = lotSize;
        double pointsNeeded = pointValue > 0 ? tpAmountUSD / pointValue : CryptoMinMovement;
        return MathMax(CryptoMinMovement, MathMin(pointsNeeded, CryptoMaxMovement));
    } else {
        double pipValue = lotSize * 10.0;
        double pipsNeeded = pipValue > 0 ? tpAmountUSD / pipValue : TPPipsBackup;
        return MathMax(5, MathMin(pipsNeeded, 500));
    }
}

double CalculateTPPrice(bool isBuy, double openPrice)
{
    double tpMovement = CalculateTPMovement();
    long digits = SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    
    if(isCryptoPair) {
        return NormalizeDouble(isBuy ? openPrice + tpMovement : openPrice - tpMovement, (int)digits);
    } else {
        double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
        double pipSize = (digits == 5 || digits == 3) ? point * 10 : point;
        return NormalizeDouble(isBuy ? openPrice + (tpMovement * pipSize) : openPrice - (tpMovement * pipSize), (int)digits);
    }
}

void CheckPercentageBasedTP()
{
    double tpAmount = CalculateTPAmount();
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == (long)MagicNumber) {
            double profit = PositionGetDouble(POSITION_PROFIT);
            if(profit >= tpAmount) {
                ulong ticket = PositionGetTicket(i);
                double lotSize = PositionGetDouble(POSITION_VOLUME);
                if(trade.PositionClose(ticket)) {
                    Print("PERCENTAGE TP HIT: #", ticket, " | Lot: ", DoubleToString(lotSize, 3), " | Profit: $", DoubleToString(profit, 2));
                }
            }
        }
    }
}

bool CloseAllProfitablePositions()
{
    int closedCount = 0;
    double totalProfit = 0;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == (long)MagicNumber &&
           PositionGetDouble(POSITION_PROFIT) > 0) {
            totalProfit += PositionGetDouble(POSITION_PROFIT);
            if(trade.PositionClose(PositionGetTicket(i))) closedCount++;
        }
    }
    
    if(closedCount > 0) {
        Print("CLOSED ", closedCount, " PROFITABLE POSITIONS | Total Profit: $", DoubleToString(totalProfit, 2));
        if(EnableSounds) PlaySound("alert.wav");
    }
    
    return closedCount > 0;
}

bool CloseAllTrades()
{
    int closedCount = 0;
    double totalProfit = 0;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == (long)MagicNumber) {
            totalProfit += PositionGetDouble(POSITION_PROFIT);
            if(trade.PositionClose(PositionGetTicket(i))) closedCount++;
        }
    }
    
    if(closedCount > 0) {
        Print("CLOSED ALL ", closedCount, " POSITIONS | Total P/L: $", DoubleToString(totalProfit, 2));
        if(EnableSounds) PlaySound("alert.wav");
    }
    
    return closedCount > 0;
}

long CountPositions(int posType = -1)
{
    long count = 0;
    for(int i = 0; i < PositionsTotal(); i++) {
        if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == (long)MagicNumber) {
            if(posType == -1 || PositionGetInteger(POSITION_TYPE) == posType) count++;
        }
    }
    return count;
}

double GetCurrentDrawdown()
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    return (balance > 0 && equity < dailyStartBalance) ? ((dailyStartBalance - equity) / dailyStartBalance) * 100.0 : 0.0;
}

double NormalizeLotSize(double lotSize)
{
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    lotSize = MathMax(minLot, MathMin(lotSize, maxLot));
    return NormalizeDouble(lotSize / lotStep, 0) * lotStep;
}

bool ValidateAllInputs()
{
    if(InitialLotSize <= 0 || IndividualTradeTP <= 0 || IndividualTradeTP > 100 ||
       TPPipsBackup <= 0 || DrawdownLimit <= 0 || DrawdownLimit > 100 ||
       MaxBuyTrades <= 0 || MaxSellTrades <= 0) {
        Print("ERROR: Invalid basic trading parameters");
        return false;
    }
    
    if(EnableConsecutiveCandlesTP && ConsecutiveCandlesCount <= 0) {
        Print("ERROR: ConsecutiveCandlesCount must be greater than 0 when EnableConsecutiveCandlesTP is true");
        return false;
    }
    
    if(EnableConsecutiveCandlesTP && ConsecutiveCandlesCount > 10) {
        Print("WARNING: ConsecutiveCandlesCount > 10 may be too restrictive for most markets");
    }
    
    if(EnableLotCompounding) {
        if(LotSizeIncrement <= 0) {
            Print("ERROR: LotSizeIncrement must be greater than 0 when EnableLotCompounding is true");
            return false;
        }
        if(EquityThreshold <= 0) {
            Print("ERROR: EquityThreshold must be greater than 0 when EnableLotCompounding is true");
            return false;
        }
        if(EquityThreshold < 100) {
            Print("WARNING: EquityThreshold < $100 may result in very aggressive lot scaling");
        }
        if(LotSizeIncrement > 1.0) {
            Print("WARNING: LotSizeIncrement > 1.0 may be too aggressive for most accounts");
        }
    }
    
    currentLotSize = EnableLotCompounding ? CalculateCompoundedLotSize() : NormalizeLotSize(InitialLotSize);
    
    Print("INPUT VALIDATION COMPLETE - All parameters are valid");
    return true;
}