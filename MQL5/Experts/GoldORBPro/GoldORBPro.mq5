//+------------------------------------------------------------------+
//|                                              GoldORBPro.mq5      |
//|                                   Gold ORB Pro EA - XAUUSD M15   |
//+------------------------------------------------------------------+
#property copyright "Gold ORB Pro EA"
#property version   "1.00"
#property description "Opening Range Breakout EA for XAUUSD (M15 execution, H1 trend filter)"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//====================================================================
// INPUTS
//====================================================================
input group "=== Opening Range (London Session) ==="
input int    InpLondonOpenHour     = 9;    // London session open hour (broker/server time)
input int    InpLondonOpenMinute   = 0;    // London session open minute (broker/server time)
input int    InpORBMinutes         = 30;   // Opening range duration (minutes)

input group "=== Trend Filter (H1) ==="
input int    InpEMAPeriod          = 200;  // H1 EMA period

input group "=== Entry Filters ==="
input double InpMinBodyPercent     = 60.0; // Minimum candle body % of full range

input group "=== Risk Management ==="
input double InpRiskPercent        = 0.5;  // Risk per trade (% of account balance)
input double InpRewardRiskRatio    = 2.0;  // Take-profit reward:risk ratio
input double InpBreakEvenR         = 1.0;  // Break-even trigger, in multiples of R
input double InpTrailingActivateR  = 1.5;  // Trailing-stop activation, in multiples of R
input double InpSLBufferPoints     = 20;   // Extra buffer beyond ORB level for SL (points)

input group "=== Daily Risk Limits ==="
input double InpMaxDailyLossPercent   = 2.0; // Stop trading after this daily loss (%)
input double InpMaxDailyProfitPercent = 3.0; // Stop trading after this daily profit (%)
input int    InpMaxTradesPerDay       = 2;   // Maximum trades per day (total)

input group "=== Spread & ORB Range Filters ==="
input int    InpMaxSpreadPoints    = 50;   // Maximum allowed spread (points)
input double InpMinORBRangePoints  = 50;   // Minimum acceptable ORB range (points)
input double InpMaxORBRangePoints  = 800;  // Maximum acceptable ORB range (points)

input group "=== Trade Execution ==="
input ulong  InpMagicNumber        = 20260719; // Magic number
input int    InpSlippagePoints     = 20;       // Allowed slippage (points)

input group "=== Dashboard ==="
input bool   InpShowDashboard      = true; // Show on-chart dashboard

//====================================================================
// GLOBALS
//====================================================================
CTrade         trade;
CPositionInfo  posInfo;

int            g_h1EmaHandle = INVALID_HANDLE;

// --- Opening range state (per trading day) ---
double         g_orbHigh          = 0.0;
double         g_orbLow           = 0.0;
bool           g_orbCalculated    = false;
bool           g_orbRangeValid    = false;
datetime       g_orbStartTime     = 0;
datetime       g_orbEndTime       = 0;

// --- Daily bookkeeping ---
int            g_currentDay       = -1;      // day-of-year marker used to detect day rollover
int            g_currentYear      = -1;
double         g_dailyStartBalance= 0.0;
double         g_dailyPnLPercent  = 0.0;
bool           g_dailyLimitHit    = false;
bool           g_buyTakenToday    = false;
bool           g_sellTakenToday   = false;
int            g_tradesToday      = 0;

// --- New-bar detection ---
datetime       g_lastM15BarTime   = 0;

// --- Managed open positions (break-even / trailing tracking) ---
struct ManagedTrade
  {
   ulong               ticket;
   ENUM_POSITION_TYPE  type;
   double              entryPrice;
   double              riskDistance;   // 1R in price terms
   bool                beApplied;
   bool                trailingActive;
  };
ManagedTrade   g_trades[2];
int            g_tradeCount = 0;

// --- Chart object names ---
#define OBJ_NAME_ORB_HIGH "GoldORBPro_ORB_High"
#define OBJ_NAME_ORB_LOW  "GoldORBPro_ORB_Low"

//====================================================================
// LOGGING HELPERS
//====================================================================
void Log(const string msg)
  {
   Print("[GoldORBPro] ", msg);
  }

void LogError(const string msg)
  {
   Print("[GoldORBPro][ERROR] ", msg, " | LastError=", GetLastError());
  }

//====================================================================
// SYMBOL VALIDATION
//====================================================================
bool IsSymbolAllowed()
  {
// Accepts XAUUSD and broker-specific variants such as XAUUSD.m, XAUUSDm, XAUUSD-ECN,
// but rejects any symbol that does not start with "XAUUSD".
   return (StringFind(_Symbol, "XAUUSD") == 0);
  }

//====================================================================
// EXPERT INITIALIZATION
//====================================================================
int OnInit()
  {
   if(!IsSymbolAllowed())
     {
      LogError(StringFormat("Symbol %s is not allowed. Gold ORB Pro EA trades XAUUSD only.", _Symbol));
      return(INIT_FAILED);
     }

   if(_Period != PERIOD_M15)
     {
      Log(StringFormat("Warning: chart period is %s, EA is designed for M15. Continuing anyway.",
                        EnumToString(_Period)));
     }

   g_h1EmaHandle = iMA(_Symbol, PERIOD_H1, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(g_h1EmaHandle == INVALID_HANDLE)
     {
      LogError("Failed to create H1 EMA indicator handle.");
      return(INIT_FAILED);
     }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   g_currentDay  = -1;
   g_currentYear = -1;
   g_tradeCount  = 0;

   ResetDailyState();
   RebuildManagedTradesFromOpenPositions();

   Log("Gold ORB Pro EA initialized successfully.");
   return(INIT_SUCCEEDED);
  }

//====================================================================
// EXPERT DEINITIALIZATION
//====================================================================
void OnDeinit(const int reason)
  {
   if(g_h1EmaHandle != INVALID_HANDLE)
      IndicatorRelease(g_h1EmaHandle);

   ObjectDelete(0, OBJ_NAME_ORB_HIGH);
   ObjectDelete(0, OBJ_NAME_ORB_LOW);
   Comment("");

   Log("Gold ORB Pro EA deinitialized. Reason=" + IntegerToString(reason));
  }

//====================================================================
// MAIN TICK HANDLER
//====================================================================
void OnTick()
  {
   if(!IsSymbolAllowed())
      return; // safety net, should never trigger since OnInit already rejects

   HandleDailyRollover();
   CalculateORB();
   ManageOpenPositions();
   UpdateDailyPnL();

   if(IsNewM15Bar())
      CheckEntrySignals();

   if(InpShowDashboard)
      UpdateDashboard();
  }

//====================================================================
// DAILY ROLLOVER / RESET
//====================================================================
void HandleDailyRollover()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   if(dt.day_of_year != g_currentDay || dt.year != g_currentYear)
     {
      g_currentDay  = dt.day_of_year;
      g_currentYear = dt.year;
      ResetDailyState();
     }
  }

void ResetDailyState()
  {
   g_orbHigh       = 0.0;
   g_orbLow        = 0.0;
   g_orbCalculated = false;
   g_orbRangeValid = false;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = InpLondonOpenHour;
   dt.min  = InpLondonOpenMinute;
   dt.sec  = 0;
   g_orbStartTime = StructToTime(dt);
   g_orbEndTime   = g_orbStartTime + InpORBMinutes * 60;

   g_dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_dailyPnLPercent   = 0.0;
   g_dailyLimitHit     = false;
   g_buyTakenToday     = false;
   g_sellTakenToday    = false;
   g_tradesToday       = 0;

   ObjectDelete(0, OBJ_NAME_ORB_HIGH);
   ObjectDelete(0, OBJ_NAME_ORB_LOW);

   Log("Daily state reset. ORB window: " + TimeToString(g_orbStartTime, TIME_MINUTES) +
       " - " + TimeToString(g_orbEndTime, TIME_MINUTES));
  }

//====================================================================
// RECOVER MANAGED TRADES AFTER RESTART/RECOMPILE
//====================================================================
void RebuildManagedTradesFromOpenPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!posInfo.SelectByIndex(i))
         continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != (long)InpMagicNumber)
         continue;
      if(g_tradeCount >= ArraySize(g_trades))
         break;

      double sl = posInfo.StopLoss();
      double entry = posInfo.PriceOpen();
      double riskDistance = MathAbs(entry - sl);
      if(riskDistance <= 0)
         continue;

      g_trades[g_tradeCount].ticket         = posInfo.Ticket();
      g_trades[g_tradeCount].type           = posInfo.PositionType();
      g_trades[g_tradeCount].entryPrice     = entry;
      g_trades[g_tradeCount].riskDistance   = riskDistance;
      g_trades[g_tradeCount].beApplied      = false;
      g_trades[g_tradeCount].trailingActive = false;
      g_tradeCount++;

      if(posInfo.PositionType() == POSITION_TYPE_BUY)
         g_buyTakenToday = true;
      else
         g_sellTakenToday = true;
      g_tradesToday++;
     }
  }

//====================================================================
// OPENING RANGE BREAKOUT CALCULATION
//====================================================================
void CalculateORB()
  {
   if(g_orbCalculated)
      return;
   if(TimeCurrent() < g_orbEndTime)
      return; // window not finished yet

   int shiftStart = iBarShift(_Symbol, PERIOD_M1, g_orbStartTime, false);
   int shiftEnd   = iBarShift(_Symbol, PERIOD_M1, g_orbEndTime - 60, false);

   if(shiftStart < 0 || shiftEnd < 0)
     {
      LogError("Unable to locate M1 bars for ORB window. Retrying next tick.");
      return;
     }

   double hi = -DBL_MAX;
   double lo = DBL_MAX;
   for(int i = shiftEnd; i <= shiftStart; i++)
     {
      double h = iHigh(_Symbol, PERIOD_M1, i);
      double l = iLow(_Symbol, PERIOD_M1, i);
      if(h > hi) hi = h;
      if(l < lo) lo = l;
     }

   if(hi <= -DBL_MAX || lo >= DBL_MAX)
     {
      LogError("Invalid ORB high/low computation.");
      return;
     }

   g_orbHigh       = hi;
   g_orbLow        = lo;
   g_orbCalculated = true;

   double rangePoints = (g_orbHigh - g_orbLow) / _Point;
   g_orbRangeValid = (rangePoints >= InpMinORBRangePoints && rangePoints <= InpMaxORBRangePoints);

   Log(StringFormat("ORB calculated: High=%.2f Low=%.2f Range=%.1f points ValidRange=%s",
                     g_orbHigh, g_orbLow, rangePoints, (g_orbRangeValid ? "YES" : "NO")));

   DrawORBLines();
  }

void DrawORBLines()
  {
   if(!ObjectCreate(0, OBJ_NAME_ORB_HIGH, OBJ_HLINE, 0, 0, g_orbHigh))
      ObjectMove(0, OBJ_NAME_ORB_HIGH, 0, 0, g_orbHigh);
   ObjectSetInteger(0, OBJ_NAME_ORB_HIGH, OBJPROP_COLOR, clrDodgerBlue);
   ObjectSetInteger(0, OBJ_NAME_ORB_HIGH, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, OBJ_NAME_ORB_HIGH, OBJPROP_WIDTH, 1);
   ObjectSetString(0, OBJ_NAME_ORB_HIGH, OBJPROP_TEXT, "ORB High");

   if(!ObjectCreate(0, OBJ_NAME_ORB_LOW, OBJ_HLINE, 0, 0, g_orbLow))
      ObjectMove(0, OBJ_NAME_ORB_LOW, 0, 0, g_orbLow);
   ObjectSetInteger(0, OBJ_NAME_ORB_LOW, OBJPROP_COLOR, clrOrangeRed);
   ObjectSetInteger(0, OBJ_NAME_ORB_LOW, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, OBJ_NAME_ORB_LOW, OBJPROP_WIDTH, 1);
   ObjectSetString(0, OBJ_NAME_ORB_LOW, OBJPROP_TEXT, "ORB Low");
  }

//====================================================================
// TREND FILTER (H1 200 EMA)
//====================================================================
// Returns  1 = bullish (price above EMA), -1 = bearish (price below EMA), 0 = unknown
int GetTrend()
  {
   double emaBuffer[];
   ArraySetAsSeries(emaBuffer, true);
   if(CopyBuffer(g_h1EmaHandle, 0, 1, 1, emaBuffer) <= 0)
     {
      LogError("Failed to copy H1 EMA buffer.");
      return 0;
     }

   double ema = emaBuffer[0];
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(price > ema) return 1;
   if(price < ema) return -1;
   return 0;
  }

//====================================================================
// NEW M15 BAR DETECTION
//====================================================================
bool IsNewM15Bar()
  {
   datetime barTime = iTime(_Symbol, PERIOD_M15, 0);
   if(barTime != g_lastM15BarTime)
     {
      g_lastM15BarTime = barTime;
      return true;
     }
   return false;
  }

//====================================================================
// SPREAD / RANGE / NEWS FILTERS
//====================================================================
bool IsSpreadOK()
  {
   long spreadPoints = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (spreadPoints <= InpMaxSpreadPoints);
  }

bool IsORBRangeOK()
  {
   return g_orbRangeValid;
  }

// Placeholder: hook up to an economic calendar / external news feed.
bool IsHighImpactNewsComing()
  {
   return false;
  }

// Placeholder: combines news proximity with any other blocking rules.
bool IsNewsBlocked()
  {
   return IsHighImpactNewsComing();
  }

//====================================================================
// DAILY RISK LIMIT TRACKING
//====================================================================
void UpdateDailyPnL()
  {
   if(g_dailyStartBalance <= 0)
      return;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dailyPnLPercent = (equity - g_dailyStartBalance) / g_dailyStartBalance * 100.0;

   if(!g_dailyLimitHit)
     {
      if(g_dailyPnLPercent <= -InpMaxDailyLossPercent)
        {
         g_dailyLimitHit = true;
         Log(StringFormat("Daily loss limit reached (%.2f%%). Trading halted for the rest of the day.",
                           g_dailyPnLPercent));
        }
      else
         if(g_dailyPnLPercent >= InpMaxDailyProfitPercent)
           {
            g_dailyLimitHit = true;
            Log(StringFormat("Daily profit target reached (%.2f%%). Trading halted for the rest of the day.",
                              g_dailyPnLPercent));
           }
     }
  }

//====================================================================
// ENTRY SIGNAL EVALUATION
//====================================================================
void CheckEntrySignals()
  {
   if(!g_orbCalculated)
      return;
   if(g_dailyLimitHit)
      return;
   if(g_tradesToday >= InpMaxTradesPerDay)
      return;
   if(!IsORBRangeOK())
      return;
   if(!IsSpreadOK())
     {
      Log("Entry skipped: spread filter blocked (spread too wide).");
      return;
     }
   if(IsNewsBlocked())
     {
      Log("Entry skipped: news filter blocked.");
      return;
     }

   // Evaluate the just-closed M15 candle (shift 1)
   double open  = iOpen(_Symbol, PERIOD_M15, 1);
   double close = iClose(_Symbol, PERIOD_M15, 1);
   double high  = iHigh(_Symbol, PERIOD_M15, 1);
   double low   = iLow(_Symbol, PERIOD_M15, 1);

   double range = high - low;
   if(range <= 0)
      return;

   double bodyPercent = MathAbs(close - open) / range * 100.0;
   if(bodyPercent < InpMinBodyPercent)
      return;

   int trend = GetTrend();

   bool buySignal  = (!g_buyTakenToday  && trend ==  1 && close > g_orbHigh);
   bool sellSignal = (!g_sellTakenToday && trend == -1 && close < g_orbLow);

   if(buySignal)
      OpenBuyTrade(close);
   else
      if(sellSignal)
         OpenSellTrade(close);
  }

//====================================================================
// POSITION SIZING
//====================================================================
double CalculateLotSize(double slDistancePrice)
  {
   if(slDistancePrice <= 0)
      return 0.0;

   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * InpRiskPercent / 100.0;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0 || tickSize <= 0)
     {
      LogError("Invalid tick value/size for lot size calculation.");
      return 0.0;
     }

   double valuePerPriceUnit = tickValue / tickSize;
   double lossPerLot = slDistancePrice * valuePerPriceUnit;
   if(lossPerLot <= 0)
      return 0.0;

   double lots = riskAmount / lossPerLot;

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lotStep <= 0)
      lotStep = 0.01;

   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));

   int stepDigits = (int)MathRound(-MathLog10(lotStep));
   if(stepDigits < 0) stepDigits = 2;
   lots = NormalizeDouble(lots, stepDigits);

   return lots;
  }

//====================================================================
// DUPLICATE PROTECTION HELPER
//====================================================================
bool HasOpenPosition(ENUM_POSITION_TYPE type)
  {
   for(int i = 0; i < g_tradeCount; i++)
      if(g_trades[i].type == type)
         return true;
   return false;
  }

// Locates the position ticket of a just-opened position that is not yet tracked.
// Needed because the order ticket returned by CTrade is not guaranteed to equal
// the resulting position ticket on every broker (relevant for hedging accounts).
ulong FindNewPositionTicket(ENUM_POSITION_TYPE type)
  {
   ulong bestTicket = 0;
   datetime bestTime = 0;

   for(int i = 0; i < PositionsTotal(); i++)
     {
      if(!posInfo.SelectByIndex(i))
         continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != (long)InpMagicNumber)
         continue;
      if(posInfo.PositionType() != type)
         continue;

      ulong tk = posInfo.Ticket();
      bool alreadyTracked = false;
      for(int j = 0; j < g_tradeCount; j++)
         if(g_trades[j].ticket == tk)
           {
            alreadyTracked = true;
            break;
           }
      if(alreadyTracked)
         continue;

      if(posInfo.Time() >= bestTime)
        {
         bestTime = posInfo.Time();
         bestTicket = tk;
        }
     }
   return bestTicket;
  }

//====================================================================
// TRADE EXECUTION
//====================================================================
void OpenBuyTrade(const double refPrice)
  {
   if(g_buyTakenToday || HasOpenPosition(POSITION_TYPE_BUY))
     {
      Log("Buy skipped: duplicate protection (already taken/open today).");
      return;
     }

   double sl = g_orbLow - InpSLBufferPoints * _Point;
   double slDistance = refPrice - sl;
   if(slDistance <= 0)
     {
      LogError("Buy skipped: invalid stop-loss distance.");
      return;
     }
   double tp = refPrice + slDistance * InpRewardRiskRatio;

   double lots = CalculateLotSize(slDistance);
   if(lots <= 0)
     {
      LogError("Buy skipped: computed lot size is zero.");
      return;
     }

   if(!trade.Buy(lots, _Symbol, 0.0, sl, tp, "GoldORBPro Buy"))
     {
      LogError(StringFormat("Buy order failed: retcode=%d (%s)",
                             trade.ResultRetcode(), trade.ResultRetcodeDescription()));
      return;
     }

   ulong ticket = FindNewPositionTicket(POSITION_TYPE_BUY);
   if(ticket == 0)
      ticket = trade.ResultOrder(); // fallback if position lookup failed

   double entry = trade.ResultPrice();
   if(PositionSelectByTicket(ticket))
      entry = PositionGetDouble(POSITION_PRICE_OPEN);
   if(entry <= 0)
      entry = refPrice;

   RegisterManagedTrade(ticket, POSITION_TYPE_BUY, entry, MathAbs(entry - sl));

   g_buyTakenToday = true;
   g_tradesToday++;

   Log(StringFormat("BUY opened: ticket=%I64u lots=%.2f entry=%.2f sl=%.2f tp=%.2f",
                     ticket, lots, entry, sl, tp));
  }

void OpenSellTrade(const double refPrice)
  {
   if(g_sellTakenToday || HasOpenPosition(POSITION_TYPE_SELL))
     {
      Log("Sell skipped: duplicate protection (already taken/open today).");
      return;
     }

   double sl = g_orbHigh + InpSLBufferPoints * _Point;
   double slDistance = sl - refPrice;
   if(slDistance <= 0)
     {
      LogError("Sell skipped: invalid stop-loss distance.");
      return;
     }
   double tp = refPrice - slDistance * InpRewardRiskRatio;

   double lots = CalculateLotSize(slDistance);
   if(lots <= 0)
     {
      LogError("Sell skipped: computed lot size is zero.");
      return;
     }

   if(!trade.Sell(lots, _Symbol, 0.0, sl, tp, "GoldORBPro Sell"))
     {
      LogError(StringFormat("Sell order failed: retcode=%d (%s)",
                             trade.ResultRetcode(), trade.ResultRetcodeDescription()));
      return;
     }

   ulong ticket = FindNewPositionTicket(POSITION_TYPE_SELL);
   if(ticket == 0)
      ticket = trade.ResultOrder(); // fallback if position lookup failed

   double entry = trade.ResultPrice();
   if(PositionSelectByTicket(ticket))
      entry = PositionGetDouble(POSITION_PRICE_OPEN);
   if(entry <= 0)
      entry = refPrice;

   RegisterManagedTrade(ticket, POSITION_TYPE_SELL, entry, MathAbs(sl - entry));

   g_sellTakenToday = true;
   g_tradesToday++;

   Log(StringFormat("SELL opened: ticket=%I64u lots=%.2f entry=%.2f sl=%.2f tp=%.2f",
                     ticket, lots, entry, sl, tp));
  }

void RegisterManagedTrade(ulong ticket, ENUM_POSITION_TYPE type, double entryPrice, double riskDistance)
  {
   if(g_tradeCount >= ArraySize(g_trades))
     {
      LogError("Managed trade slots full, cannot track new position for BE/trailing.");
      return;
     }
   g_trades[g_tradeCount].ticket         = ticket;
   g_trades[g_tradeCount].type           = type;
   g_trades[g_tradeCount].entryPrice     = entryPrice;
   g_trades[g_tradeCount].riskDistance   = riskDistance;
   g_trades[g_tradeCount].beApplied      = false;
   g_trades[g_tradeCount].trailingActive = false;
   g_tradeCount++;
  }

void RemoveManagedTrade(int index)
  {
   if(index < 0 || index >= g_tradeCount)
      return;
   for(int i = index; i < g_tradeCount - 1; i++)
      g_trades[i] = g_trades[i + 1];
   g_tradeCount--;
  }

//====================================================================
// TRADE MANAGEMENT: BREAK-EVEN + TRAILING STOP
//====================================================================
void ManageOpenPositions()
  {
   for(int i = g_tradeCount - 1; i >= 0; i--)
     {
      ulong ticket = g_trades[i].ticket;

      if(!PositionSelectByTicket(ticket))
        {
         Log(StringFormat("Position #%I64u no longer open, removed from management.", ticket));
         RemoveManagedTrade(i);
         continue;
        }

      double R = g_trades[i].riskDistance;
      if(R <= 0)
         continue;

      bool isBuy = (g_trades[i].type == POSITION_TYPE_BUY);
      double entry = g_trades[i].entryPrice;
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);

      double profitR = isBuy ? (bid - entry) / R : (entry - ask) / R;

      // --- Break-even ---
      if(!g_trades[i].beApplied && profitR >= InpBreakEvenR)
        {
         double spread = ask - bid;
         double newSL = isBuy ? entry + spread : entry - spread;
         bool improves = isBuy ? (currentSL <= 0 || newSL > currentSL)
                                : (currentSL <= 0 || newSL < currentSL);
         if(improves)
           {
            if(trade.PositionModify(ticket, newSL, currentTP))
              {
               g_trades[i].beApplied = true;
               currentSL = newSL;
               Log(StringFormat("Break-even applied on #%I64u: SL -> %.2f", ticket, newSL));
              }
            else
               LogError(StringFormat("Break-even modify failed on #%I64u: %s",
                                      ticket, trade.ResultRetcodeDescription()));
           }
         else
            g_trades[i].beApplied = true;
        }

      // --- Trailing stop (behind previous completed M15 candle) ---
      if(profitR >= InpTrailingActivateR)
        {
         g_trades[i].trailingActive = true;
         double trailLevel = isBuy ? iLow(_Symbol, PERIOD_M15, 1) : iHigh(_Symbol, PERIOD_M15, 1);
         bool improvesTrail = isBuy ? (currentSL <= 0 || trailLevel > currentSL)
                                     : (currentSL <= 0 || trailLevel < currentSL);
         if(improvesTrail)
           {
            if(trade.PositionModify(ticket, trailLevel, currentTP))
               Log(StringFormat("Trailing SL updated on #%I64u: SL -> %.2f", ticket, trailLevel));
            else
               LogError(StringFormat("Trailing modify failed on #%I64u: %s",
                                      ticket, trade.ResultRetcodeDescription()));
           }
        }
     }
  }

//====================================================================
// DASHBOARD
//====================================================================
void UpdateDashboard()
  {
   static datetime lastUpdate = 0;
   datetime now = TimeCurrent();
   if(now == lastUpdate)
      return;
   lastUpdate = now;

   int trend = GetTrend();
   string trendText = (trend == 1) ? "BULLISH (above H1 EMA)" :
                       (trend == -1) ? "BEARISH (below H1 EMA)" : "UNKNOWN";

   string newsText = IsHighImpactNewsComing() ? "BLOCKED (news)" : "CLEAR";

   string text = "";
   text += "===== Gold ORB Pro EA =====\n";
   text += StringFormat("ORB High:            %.2f\n", g_orbHigh);
   text += StringFormat("ORB Low:             %.2f\n", g_orbLow);
   text += StringFormat("Current Trend:       %s\n", trendText);
   text += StringFormat("Daily P/L:           %.2f%%\n", g_dailyPnLPercent);
   text += StringFormat("Trades Today:        %d / %d\n", g_tradesToday, InpMaxTradesPerDay);
   text += StringFormat("Risk Per Trade:      %.2f%%\n", InpRiskPercent);
   text += StringFormat("News Status:         %s\n", newsText);
   text += StringFormat("Daily Limit Hit:     %s\n", g_dailyLimitHit ? "YES" : "NO");
   text += StringFormat("Spread:              %d pts (max %d)\n",
                         (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD), InpMaxSpreadPoints);

   Comment(text);
  }
//+------------------------------------------------------------------+
