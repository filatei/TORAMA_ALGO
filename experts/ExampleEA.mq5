//+------------------------------------------------------------------+
//|                         ExampleEA.mq5                            |
//|                       © TORAMA CAPITAL                           |
//+------------------------------------------------------------------+
#property copyright "TORAMA CAPITAL"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

input double Lots = 0.1;
input int StopLoss = 200;   // in points
input int TakeProfit = 400; // in points

int OnInit() { return(INIT_SUCCEEDED); }

void OnTick()
{
   if(PositionSelect(_Symbol)) return; // only one trade at a time
   if(iClose(_Symbol, PERIOD_M1, 1) > iOpen(_Symbol, PERIOD_M1, 1))
      trade.Buy(Lots, _Symbol, Ask, StopLoss*_Point, TakeProfit*_Point, "ExampleEA");
   else
      trade.Sell(Lots, _Symbol, Bid, StopLoss*_Point, TakeProfit*_Point, "ExampleEA");
}
