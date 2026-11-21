//+------------------------------------------------------------------+
//|  SMC_SR_EA.mq5                                                   |
//|  Auto-trading Expert Advisor for MetaTrader 5.                   |
//|  Same rules as the SMC + S/R web scanner:                        |
//|   - SMC: trend filter -> break of structure -> retest of the     |
//|     broken level / order block / FVG -> rejection candle         |
//|     (+ optional confluences: OB, FVG, liquidity sweep,           |
//|     displacement, premium/discount, kill zone; CHoCH entries)    |
//|   - Support & resistance: bounce / flip of multi-touch zones     |
//|   - HTF EMA bias filter                                          |
//|   - TP1 / TP2 / TP3 partial exits, stop to break-even after TP1  |
//|   - Lot size from risk % of balance                              |
//|  Signals are evaluated once per closed candle of the chart's     |
//|  timeframe. Attach one copy per chart / symbol.                  |
//|  TEST ON A DEMO ACCOUNT FIRST.                                   |
//+------------------------------------------------------------------+
#property copyright "SMC + S/R EA"
#property version   "1.00"
#property description "SMC BOS+retest and support/resistance EA with TP1/TP2/TP3. Test on demo first."

#include <Trade/Trade.mqh>
CTrade trade;

enum ENUM_STRAT   { STRAT_SMC = 0, STRAT_SR = 1, STRAT_BOTH = 2 };
enum ENUM_TRENDF  { TREND_EMA_STRUCT = 0, TREND_EMA = 1, TREND_STRUCT = 2, TREND_NONE = 3 };
enum ENUM_POI     { POI_LEVEL = 0, POI_OB = 1, POI_FVG = 2, POI_ANY = 3 };
enum ENUM_SESS    { SESS_LONDON_NY = 0, SESS_LONDON = 1, SESS_NY = 2 };
enum ENUM_TP3MODE { TP3_LIQUIDITY = 0, TP3_FIXED_R = 1 };
enum ENUM_SRTP    { SRTP_NEXT_LEVEL = 0, SRTP_FIXED_RR = 1 };

input group "General"
input ENUM_STRAT  InpStrategy      = STRAT_SMC;   // Strategy
input double      InpRiskPct       = 0.5;         // Risk per trade (% of balance)
input long        InpMagic         = 240521;      // Magic number
input int         InpMaxSpreadPts  = 30;          // Max spread (points), 0 = off
input int         InpMaxTradesDay  = 3;           // Max new trades per day (this symbol), 0 = off
input int         InpBars          = 1500;        // Candles to analyse
input int         InpGmtOffset     = -99;         // Broker GMT offset in hours (-99 = auto; set it in the Strategy Tester)
input bool        InpShowPanel     = true;        // Show status on chart

input group "Trend filter"
input ENUM_TRENDF InpTrend         = TREND_EMA_STRUCT; // Trend filter
input int         InpEma           = 200;         // Trend EMA length
input bool        InpUseHtf        = true;        // Require higher-timeframe bias
input ENUM_TIMEFRAMES InpHtf       = PERIOD_H4;   // HTF timeframe
input int         InpHtfEma        = 50;          // HTF EMA length

input group "Structure and retest"
input int         InpSwing         = 5;           // Swing length (candles each side)
input double      InpTol           = 0.25;        // Retest tolerance (x ATR)
input int         InpMaxRetest     = 20;          // Max candles to wait for retest
input bool        InpRej           = true;        // Require rejection candle
input double      InpSlAtr         = 0.5;         // SL buffer (x ATR)
input double      InpRR            = 2.0;         // SMC target R:R (this is TP2)

input group "SMC confluences"
input ENUM_POI    InpPoi           = POI_LEVEL;   // Entry zone
input bool        InpChoch         = false;       // Also trade CHoCH reversals
input double      InpDispAtr       = 1.0;         // Displacement: min body (x ATR)
input ENUM_SESS   InpSession       = SESS_LONDON_NY; // Kill zone sessions (UTC: London 07-10, NY 12-15)
input int         InpMinConf       = 0;           // Minimum confluence score (0-6)
input bool        InpReqOB         = false;       // Require: order block
input bool        InpReqFVG        = false;       // Require: fair value gap
input bool        InpReqSweep      = false;       // Require: liquidity sweep
input bool        InpReqDisp       = false;       // Require: displacement
input bool        InpReqDiscount   = false;       // Require: premium / discount
input bool        InpReqKillzone   = false;       // Require: kill zone

input group "Support and resistance"
input int         InpSrTouches     = 2;           // Min touches for a zone
input double      InpZoneW         = 0.5;         // Zone width (x ATR)
input int         InpSrLook        = 300;         // Forget zones after N candles
input bool        InpSrWithTrend   = true;        // Only trade S/R with the trend
input ENUM_SRTP   InpSrTp          = SRTP_NEXT_LEVEL; // S/R target (TP2)
input double      InpMinRR         = 1.5;         // Min room to next level (R)

input group "Take profits"
input bool        InpTpMulti       = true;        // Use TP1 / TP2 / TP3 partial exits
input double      InpTp1R          = 1.0;         // TP1 at (R)
input ENUM_TP3MODE InpTp3Mode      = TP3_LIQUIDITY; // TP3
input double      InpTp3R          = 3.0;         // TP3 fallback / fixed (R)
input double      InpPct1          = 50;          // % closed at TP1
input double      InpPct2          = 30;          // % closed at TP2 (rest runs to TP3)
input bool        InpBE            = true;        // Move SL to entry after TP1

//--- candle data (index 0 = oldest, N-1 = last closed candle)
MqlRates R[];
int      N = 0;
double   O[], Hh[], Ll[], Cc[];
datetime Tt[];
double   ema[], atr[];
int      trendArr[];
int      g_gmt = 0;
datetime g_lastBar = 0;
int      g_dayKey = -1, g_dayCount = 0;
string   g_status = "";

//--- swing points
int    pvJ[];  bool pvHi[];
double hpP[];  int hpJ[];
double lpP[];  int lpJ[];

struct Pend
  {
   bool   active;
   int    dir, lvlIdx, bosIdx, o;
   double lvl, obBot, obTop, fvgBot, fvgTop, ext, origin;
   bool   hasFvg, sweep, disp, choch;
  };

struct Zone { int kind; double bot, top, mid, ref; };   // kind: 0 level, 1 OB, 2 FVG

struct SRZone
  {
   double top, bot, mid;
   int    touches, first, last, lastSig, brokeUp, brokeDn;
  };
SRZone zones[];

struct Sig
  {
   bool   ok;
   int    dir;
   double entry, sl, tp;
   string kind;
   int    score;
  };

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(20);
   trade.SetTypeFillingBySymbol(_Symbol);
   if(InpGmtOffset != -99) g_gmt = InpGmtOffset;
   else g_gmt = (int)MathRound((double)(TimeTradeServer() - TimeGMT()) / 3600.0);
   if(InpPct1 + InpPct2 > 100.0) Print("Warning: TP1% + TP2% is over 100; nothing is left for TP3.");
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason) { Comment(""); }

//+------------------------------------------------------------------+
void OnTick()
  {
   ManageOpenTrades();
   datetime bar = iTime(_Symbol, _Period, 0);
   if(bar == 0 || bar == g_lastBar) return;
   g_lastBar = bar;
   Evaluate();
  }

//+------------------------------------------------------------------+
//| Indicators                                                        |
//+------------------------------------------------------------------+
void CalcEma(const double &src[], int len, double &out[])
  {
   int n = ArraySize(src);
   ArrayResize(out, n);
   double k = 2.0 / (len + 1.0);
   for(int i = 0; i < n; i++) out[i] = (i == 0) ? src[0] : src[i] * k + out[i-1] * (1.0 - k);
  }

void CalcAtr(int len)
  {
   ArrayResize(atr, N);
   for(int i = 0; i < N; i++)
     {
      double tr = Hh[i] - Ll[i];
      if(i > 0) tr = MathMax(tr, MathMax(MathAbs(Hh[i] - Cc[i-1]), MathAbs(Ll[i] - Cc[i-1])));
      atr[i] = (i == 0) ? tr : (atr[i-1] * (len - 1) + tr) / len;
     }
  }

int HtfBias()
  {
   MqlRates h[];
   int cnt = CopyRates(_Symbol, InpHtf, 1, MathMax(InpHtfEma * 4, 300), h);   // closed HTF candles only
   if(cnt < InpHtfEma + 5) return 0;
   double cl[]; ArrayResize(cl, cnt);
   for(int i = 0; i < cnt; i++) cl[i] = h[i].close;
   double e[]; CalcEma(cl, InpHtfEma, e);
   return cl[cnt-1] > e[cnt-1] ? 1 : -1;
  }

bool InSession(datetime t)
  {
   if(PeriodSeconds(_Period) >= 4 * 3600) return true;
   MqlDateTime d; TimeToStruct(t - g_gmt * 3600, d);
   bool lon = d.hour >= 7 && d.hour < 10, ny = d.hour >= 12 && d.hour < 15;
   if(InpSession == SESS_LONDON) return lon;
   if(InpSession == SESS_NY) return ny;
   return lon || ny;
  }

void PushD(double &a[], double v) { int n = ArraySize(a); ArrayResize(a, n + 1); a[n] = v; }
void PushI(int &a[], int v)       { int n = ArraySize(a); ArrayResize(a, n + 1); a[n] = v; }
void PushB(bool &a[], bool v)     { int n = ArraySize(a); ArrayResize(a, n + 1); a[n] = v; }

//+------------------------------------------------------------------+
//| SMC helpers                                                       |
//+------------------------------------------------------------------+
void MakePend(Pend &pd, int dir, int i, double lv, int lvIdx, bool choch)
  {
   pd.active = true; pd.dir = dir; pd.lvl = lv; pd.lvlIdx = lvIdx; pd.bosIdx = i; pd.choch = choch;
   int o = lvIdx;                                          // leg origin
   for(int k = lvIdx; k <= i; k++)
      if(dir == 1 ? Ll[k] < Ll[o] : Hh[k] > Hh[o]) o = k;
   pd.o = o;
   int ob = -1;                                            // order block
   for(int k = o; k >= MathMax(0, o - 5); k--)
      if(dir == 1 ? Cc[k] < O[k] : Cc[k] > O[k]) { ob = k; break; }
   if(ob < 0) ob = o;
   pd.obBot = Ll[ob]; pd.obTop = Hh[ob];
   pd.hasFvg = false;                                      // most recent unfilled FVG in the leg
   for(int k = i - 1; k > o && !pd.hasFvg; k--)
     {
      double gb = dir == 1 ? Hh[k-1] : Hh[k+1];
      double gt = dir == 1 ? Ll[k+1] : Ll[k-1];
      if(gt <= gb) continue;
      bool filled = false;
      for(int m = k + 2; m <= i; m++)
         if(dir == 1 ? Ll[m] <= gb : Hh[m] >= gt) { filled = true; break; }
      if(!filled) { pd.hasFvg = true; pd.fvgBot = gb; pd.fvgTop = gt; }
     }
   pd.sweep = false;                                       // liquidity sweep at the origin
   int cnt = dir == 1 ? ArraySize(lpJ) : ArraySize(hpJ);
   for(int k = cnt - 1; k >= 0; k--)
     {
      int    pj = dir == 1 ? lpJ[k] : hpJ[k];
      double pp = dir == 1 ? lpP[k] : hpP[k];
      if(pj >= o) continue;
      bool took = dir == 1 ? Ll[o] < pp : Hh[o] > pp;
      bool back = (dir == 1 ? Cc[o] > pp : Cc[o] < pp) || (o + 1 <= i && (dir == 1 ? Cc[o+1] > pp : Cc[o+1] < pp));
      pd.sweep = took && back;
      break;
     }
   pd.disp = false;                                        // displacement
   for(int k = MathMax(o, i - 2); k <= i; k++)
      if(MathAbs(Cc[k] - O[k]) >= InpDispAtr * atr[k] && (dir == 1 ? Cc[k] > O[k] : Cc[k] < O[k])) pd.disp = true;
   pd.ext = dir == 1 ? Hh[i] : Ll[i];
   pd.origin = dir == 1 ? Ll[o] : Hh[o];
  }

int ZonesOf(const Pend &pd, double tol, Zone &zs[])
  {
   ArrayResize(zs, 0);
   int n = 0;
   if(InpPoi == POI_LEVEL || InpPoi == POI_ANY)
     { ArrayResize(zs, n + 1); zs[n].kind = 0; zs[n].bot = pd.lvl - tol; zs[n].top = pd.lvl + tol; zs[n].mid = pd.lvl; zs[n].ref = pd.lvl; n++; }
   if(InpPoi == POI_OB || InpPoi == POI_ANY)
     { ArrayResize(zs, n + 1); zs[n].kind = 1; zs[n].bot = pd.obBot; zs[n].top = pd.obTop; zs[n].mid = (pd.obBot + pd.obTop) / 2; zs[n].ref = pd.dir == 1 ? pd.obBot : pd.obTop; n++; }
   if((InpPoi == POI_FVG || InpPoi == POI_ANY) && pd.hasFvg)
     { ArrayResize(zs, n + 1); zs[n].kind = 2; zs[n].bot = pd.fvgBot; zs[n].top = pd.fvgTop; zs[n].mid = (pd.fvgBot + pd.fvgTop) / 2; zs[n].ref = pd.dir == 1 ? pd.fvgBot : pd.fvgTop; n++; }
   return n;
  }

//+------------------------------------------------------------------+
//| SMC replay over history; returns a signal only on the last candle |
//+------------------------------------------------------------------+
void RunSmc(Sig &out, int &trendNow, string &pendTxt)
  {
   int Lw = InpSwing;
   bool hasLH = false, hasPH = false, hasLL = false, hasPL = false;
   double lastH = 0, prevH = 0, lastL = 0, prevL = 0;
   int lastHIdx = -1, lastLIdx = -1;
   bool hBroken = true, lBroken = true;
   Pend pend; pend.active = false;
   ArrayResize(trendArr, N);
   ArrayResize(pvJ, 0); ArrayResize(pvHi, 0); ArrayResize(hpP, 0); ArrayResize(hpJ, 0); ArrayResize(lpP, 0); ArrayResize(lpJ, 0);
   bool req[6]; req[0] = InpReqOB; req[1] = InpReqFVG; req[2] = InpReqSweep; req[3] = InpReqDisp; req[4] = InpReqDiscount; req[5] = InpReqKillzone;
   int trendDir = 0;

   for(int i = 0; i < N; i++)
     {
      int j = i - Lw;
      if(j >= Lw)
        {
         bool isH = true, isL = true;
         for(int k = j - Lw; k <= j + Lw; k++)
           {
            if(k == j) continue;
            if(Hh[k] >= Hh[j]) isH = false;
            if(Ll[k] <= Ll[j]) isL = false;
           }
         if(isH) { prevH = lastH; hasPH = hasLH; lastH = Hh[j]; hasLH = true; lastHIdx = j; hBroken = false; PushD(hpP, Hh[j]); PushI(hpJ, j); PushI(pvJ, j); PushB(pvHi, true); }
         if(isL) { prevL = lastL; hasPL = hasLL; lastL = Ll[j]; hasLL = true; lastLIdx = j; lBroken = false; PushD(lpP, Ll[j]); PushI(lpJ, j); PushI(pvJ, j); PushB(pvHi, false); }
        }
      bool haveS = hasPH && hasPL;
      bool sUp = haveS && lastH > prevH && lastL > prevL;
      bool sDn = haveS && lastH < prevH && lastL < prevL;
      bool eUp = i >= 3 && Cc[i] > ema[i] && ema[i] > ema[i-3];
      bool eDn = i >= 3 && Cc[i] < ema[i] && ema[i] < ema[i-3];
      bool tUp = true, tDn = true;
      if(InpTrend == TREND_EMA)        { tUp = eUp; tDn = eDn; }
      if(InpTrend == TREND_STRUCT)     { tUp = sUp; tDn = sDn; }
      if(InpTrend == TREND_EMA_STRUCT) { tUp = eUp && sUp; tDn = eDn && sDn; }
      trendDir = (tUp && !tDn) ? 1 : (tDn && !tUp) ? -1 : 0;
      trendArr[i] = trendDir;
      double tol = atr[i] * InpTol;

      if(pend.active)
        {
         int d = pend.dir;
         pend.ext = d == 1 ? MathMax(pend.ext, Hh[i]) : MathMin(pend.ext, Ll[i]);
         Zone zs[];
         int nzs = ZonesOf(pend, tol, zs);
         double deepest = 0;
         for(int z = 0; z < nzs; z++) deepest = (z == 0) ? (d == 1 ? zs[z].bot : zs[z].top) : (d == 1 ? MathMin(deepest, zs[z].bot) : MathMax(deepest, zs[z].top));
         if(nzs == 0 || (d == 1 ? Cc[i] < deepest : Cc[i] > deepest) || i - pend.bosIdx > InpMaxRetest)
            pend.active = false;
         else if(i > pend.bosIdx && (!InpRej || (d == 1 ? Cc[i] > O[i] : Cc[i] < O[i])))
           {
            int hit = -1;
            for(int z = 0; z < nzs; z++)
              {
               bool touched = d == 1 ? (Ll[i] <= zs[z].top && Cc[i] > zs[z].mid) : (Hh[i] >= zs[z].bot && Cc[i] < zs[z].mid);
               if(!touched) continue;
               if(hit < 0 || (d == 1 ? zs[z].bot < zs[hit].bot : zs[z].top > zs[hit].top)) hit = z;
              }
            if(hit >= 0)
              {
               double sl = d == 1 ? MathMin(Ll[i], zs[hit].ref) - InpSlAtr * atr[i] : MathMax(Hh[i], zs[hit].ref) + InpSlAtr * atr[i];
               double eq = (pend.origin + pend.ext) / 2.0;
               bool conf[6];
               conf[0] = d == 1 ? Ll[i] <= pend.obTop : Hh[i] >= pend.obBot;
               conf[1] = pend.hasFvg && (d == 1 ? Ll[i] <= pend.fvgTop : Hh[i] >= pend.fvgBot);
               conf[2] = pend.sweep;
               conf[3] = pend.disp;
               conf[4] = d == 1 ? Cc[i] < eq : Cc[i] > eq;
               conf[5] = InSession(Tt[i]);
               int score = 0; bool okReq = true;
               for(int q = 0; q < 6; q++) { if(conf[q]) score++; if(req[q] && !conf[q]) okReq = false; }
               if(score >= InpMinConf && okReq)
                 {
                  if(i == N - 1)
                    {
                     out.ok = true; out.dir = d; out.entry = Cc[i]; out.sl = sl;
                     out.tp = Cc[i] + d * InpRR * MathAbs(Cc[i] - sl);
                     out.kind = pend.choch ? "SMC-CHoCH" : "SMC"; out.score = score;
                    }
                  pend.active = false;
                 }
              }
           }
        }
      if(!hBroken && hasLH && Cc[i] > lastH)
        {
         hBroken = true;
         bool choch = !tUp && sDn;
         if(tUp || (InpChoch && choch)) MakePend(pend, 1, i, lastH, lastHIdx, !tUp);
        }
      if(!lBroken && hasLL && Cc[i] < lastL)
        {
         lBroken = true;
         bool choch = !tDn && sUp;
         if(tDn || (InpChoch && choch)) MakePend(pend, -1, i, lastL, lastLIdx, !tDn);
        }
     }
   trendNow = trendDir;
   pendTxt = pend.active ? StringFormat("%s setup armed at %s, waiting for retest", pend.dir == 1 ? "BUY" : "SELL", DoubleToString(pend.lvl, _Digits)) : "no SMC setup";
  }

//+------------------------------------------------------------------+
//| Support & resistance                                              |
//+------------------------------------------------------------------+
void SrBand(const SRZone &z, int i, double &zb, double &zt)
  {
   double pad = atr[i] * InpZoneW / 2.0;
   zb = MathMin(z.bot, z.mid - pad);
   zt = MathMax(z.top, z.mid + pad);
  }

// TP2 for S/R: next strong zone with at least InpMinRR of room, else fixed R:R. Returns false = no room.
bool SrTarget(int dir, double entry, double risk, int i, int self, double &tp)
  {
   if(InpSrTp == SRTP_FIXED_RR) { tp = entry + dir * InpRR * risk; return true; }
   bool found = false; double best = 0;
   for(int k = 0; k < ArraySize(zones); k++)
     {
      if(k == self || zones[k].touches < InpSrTouches) continue;
      double zb, zt; SrBand(zones[k], i, zb, zt);
      double lvl = dir == 1 ? zb : zt;
      if(dir == 1 ? lvl > entry : lvl < entry)
         if(!found || MathAbs(lvl - entry) < MathAbs(best - entry)) { best = lvl; found = true; }
     }
   if(!found) { tp = entry + dir * InpRR * risk; return true; }
   if(MathAbs(best - entry) < InpMinRR * risk) return false;
   tp = best; return true;
  }

void SrAddPivot(double price, int j, int i)
  {
   double w = atr[i] * InpZoneW;
   int best = -1; double bd = DBL_MAX;
   for(int k = 0; k < ArraySize(zones); k++)
     {
      double d = MathAbs(price - zones[k].mid);
      if(d <= w && d < bd) { best = k; bd = d; }
     }
   if(best >= 0 && MathMax(zones[best].top, price) - MathMin(zones[best].bot, price) <= 2 * w)
     {
      zones[best].top = MathMax(zones[best].top, price);
      zones[best].bot = MathMin(zones[best].bot, price);
      zones[best].mid = (zones[best].top + zones[best].bot) / 2.0;
      zones[best].touches++;
      zones[best].last = j;
     }
   else
     {
      int n = ArraySize(zones); ArrayResize(zones, n + 1);
      zones[n].top = price; zones[n].bot = price; zones[n].mid = price; zones[n].touches = 1;
      zones[n].first = j; zones[n].last = j; zones[n].lastSig = -1000000; zones[n].brokeUp = -1; zones[n].brokeDn = -1;
     }
  }

void RunSr(Sig &out)
  {
   int Lw = InpSwing;
   ArrayResize(zones, 0);
   for(int i = 1; i < N; i++)
     {
      int j = i - Lw;
      if(j >= Lw)
        {
         bool isH = true, isL = true;
         for(int k = j - Lw; k <= j + Lw; k++)
           {
            if(k == j) continue;
            if(Hh[k] >= Hh[j]) isH = false;
            if(Ll[k] <= Ll[j]) isL = false;
           }
         if(isH) SrAddPivot(Hh[j], j, i);
         if(isL) SrAddPivot(Ll[j], j, i);
        }
      int keep = 0;                                         // forget stale zones
      for(int k = 0; k < ArraySize(zones); k++) if(i - zones[k].last <= InpSrLook) { if(keep != k) zones[keep] = zones[k]; keep++; }
      ArrayResize(zones, keep);

      for(int k = 0; k < ArraySize(zones); k++)
        {
         if(zones[k].touches < InpSrTouches) continue;
         double zb, zt; SrBand(zones[k], i, zb, zt);
         if(Cc[i-1] <= zt && Cc[i] > zt) zones[k].brokeUp = i;
         if(Cc[i-1] >= zb && Cc[i] < zb) zones[k].brokeDn = i;
         if(i - zones[k].lastSig <= 2 * Lw) continue;
         bool allowUp = !InpSrWithTrend || trendArr[i] == 1;
         bool allowDn = !InpSrWithTrend || trendArr[i] == -1;
         if(Cc[i-1] > zt && Ll[i] <= zt && Cc[i] > zt && Cc[i] > O[i] && allowUp)
           {
            double sl = MathMin(Ll[i], zb) - InpSlAtr * atr[i], tp;
            if(SrTarget(1, Cc[i], Cc[i] - sl, i, k, tp))
              {
               if(i == N - 1) { out.ok = true; out.dir = 1; out.entry = Cc[i]; out.sl = sl; out.tp = tp; out.score = 0;
                  out.kind = (zones[k].brokeUp >= 0 && i - zones[k].brokeUp <= InpMaxRetest) ? "SR-flip" : "SR-bounce"; }
               zones[k].lastSig = i;
              }
           }
         else if(Cc[i-1] < zb && Hh[i] >= zb && Cc[i] < zb && Cc[i] < O[i] && allowDn)
           {
            double sl = MathMax(Hh[i], zt) + InpSlAtr * atr[i], tp;
            if(SrTarget(-1, Cc[i], sl - Cc[i], i, k, tp))
              {
               if(i == N - 1) { out.ok = true; out.dir = -1; out.entry = Cc[i]; out.sl = sl; out.tp = tp; out.score = 0;
                  out.kind = (zones[k].brokeDn >= 0 && i - zones[k].brokeDn <= InpMaxRetest) ? "SR-flip" : "SR-bounce"; }
               zones[k].lastSig = i;
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| TP1 / TP2 / TP3                                                   |
//+------------------------------------------------------------------+
void TpLevels(double entry, double sl, int d, double base, int i, double &t1, double &t2, double &t3)
  {
   double risk = MathAbs(entry - sl);
   t2 = base;
   t1 = entry + d * InpTp1R * risk;
   if(d * (t1 - t2) >= 0) t1 = entry + (t2 - entry) / 2.0;
   bool found = false; t3 = 0;
   if(InpTp3Mode == TP3_LIQUIDITY)
     {
      for(int k = ArraySize(pvJ) - 1; k >= 0; k--)
        {
         int j = pvJ[k];
         if(j + InpSwing > i || pvHi[k] != (d == 1)) continue;
         if(i - j > 400) break;
         double price = d == 1 ? Hh[j] : Ll[j];
         if(d * (price - t2) <= 0 || (found && d * (price - t3) >= 0)) continue;
         bool taken = false;
         for(int m = j + 1; m <= i; m++) if(d == 1 ? Hh[m] > price : Ll[m] < price) { taken = true; break; }
         if(!taken) { t3 = price; found = true; }
        }
     }
   if(!found || MathAbs(t3 - entry) > 8 * risk)
      t3 = entry + d * MathMax(InpTp3R, MathAbs(t2 - entry) / risk + 1.0) * risk;
  }

//+------------------------------------------------------------------+
//| Orders                                                            |
//+------------------------------------------------------------------+
double NormLot(double v)
  {
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(st <= 0) st = 0.01;
   v = MathFloor(v / st + 1e-9) * st;          // round down so risk is never exceeded
   if(v < mn) return 0;
   return MathMin(v, mx);
  }

double LotsForRisk(double dist)
  {
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tv <= 0 || ts <= 0 || dist <= 0) return 0;
   double money = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPct / 100.0;
   return money / (dist / ts * tv);
  }

bool HasOpenPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic) return true;
     }
   return false;
  }

string GvName(ulong ticket, string key) { return StringFormat("smcea_%I64d_%I64u_%s", InpMagic, ticket, key); }

void OpenTrade(const Sig &s, double t1, double t2, double t3)
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double price = s.dir == 1 ? ask : bid;
   double sl = NormalizeDouble(s.sl, _Digits);
   double finalTp = NormalizeDouble(InpTpMulti ? t3 : s.tp, _Digits);
   // price must still be between SL and TP1
   if(s.dir == 1 ? (price <= sl || price >= t1) : (price >= sl || price <= t1)) { g_status = "Signal skipped: price already past SL or TP1"; Print(g_status); return; }
   double stopsLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(MathAbs(price - sl) <= stopsLvl || MathAbs(finalTp - price) <= stopsLvl) { g_status = "Signal skipped: SL/TP closer than broker stop level"; Print(g_status); return; }
   double lots = NormLot(LotsForRisk(MathAbs(price - sl)));
   if(lots <= 0) { g_status = "Signal skipped: risk too small for the minimum lot"; Print(g_status); return; }
   string cmt = StringFormat("%s %s", s.kind, InpTpMulti ? "TP1-3" : "TP");
   bool ok = s.dir == 1 ? trade.Buy(lots, _Symbol, ask, sl, finalTp, cmt) : trade.Sell(lots, _Symbol, bid, sl, finalTp, cmt);
   if(!ok || (trade.ResultRetcode() != TRADE_RETCODE_DONE && trade.ResultRetcode() != TRADE_RETCODE_PLACED))
     { g_status = StringFormat("Order failed: %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription()); Print(g_status); return; }
   g_dayCount++;
   // remember TP1 / TP2 for partial exits, keyed by position ticket
   ulong posTicket = 0;
   ulong orderTicket = trade.ResultOrder();
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if((ulong)PositionGetInteger(POSITION_IDENTIFIER) == orderTicket || posTicket == 0) posTicket = tk;
     }
   if(posTicket > 0 && InpTpMulti)
     {
      GlobalVariableSet(GvName(posTicket, "tp1"), t1);
      GlobalVariableSet(GvName(posTicket, "tp2"), t2);
      GlobalVariableSet(GvName(posTicket, "v0"), lots);
      GlobalVariableSet(GvName(posTicket, "st"), 0);
     }
   g_status = StringFormat("%s %s %.2f lots @ %s  SL %s  TP1 %s  TP2 %s  TP3 %s", s.kind, s.dir == 1 ? "BUY" : "SELL", lots,
                           DoubleToString(price, _Digits), DoubleToString(sl, _Digits), DoubleToString(t1, _Digits),
                           DoubleToString(t2, _Digits), DoubleToString(t3, _Digits));
   Print(g_status);
  }

// Partial exits at TP1 / TP2 and break-even, checked on every tick
void ManageOpenTrades()
  {
   if(!InpTpMulti) return;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(!GlobalVariableCheck(GvName(tk, "tp1"))) continue;
      double tp1 = GlobalVariableGet(GvName(tk, "tp1")), tp2 = GlobalVariableGet(GvName(tk, "tp2"));
      double v0 = GlobalVariableGet(GvName(tk, "v0"));
      int st = (int)GlobalVariableGet(GvName(tk, "st"));
      long type = PositionGetInteger(POSITION_TYPE);
      double open = PositionGetDouble(POSITION_PRICE_OPEN), sl = PositionGetDouble(POSITION_SL), tp = PositionGetDouble(POSITION_TP);
      double vol = PositionGetDouble(POSITION_VOLUME);
      double px = type == POSITION_TYPE_BUY ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      bool buy = type == POSITION_TYPE_BUY;
      if(st == 0 && (buy ? px >= tp1 : px <= tp1))
        {
         double part = NormLot(v0 * InpPct1 / 100.0);
         if(part > 0 && part < vol) trade.PositionClosePartial(tk, part);
         if(InpBE && (buy ? sl < open : (sl > open || sl == 0))) trade.PositionModify(tk, NormalizeDouble(open, _Digits), tp);
         GlobalVariableSet(GvName(tk, "st"), 1);
         Print("TP1 reached on ticket ", tk);
        }
      else if(st == 1 && (buy ? px >= tp2 : px <= tp2))
        {
         if(PositionSelectByTicket(tk)) vol = PositionGetDouble(POSITION_VOLUME);
         double part = NormLot(v0 * InpPct2 / 100.0);
         if(part > 0 && part < vol) trade.PositionClosePartial(tk, part);
         GlobalVariableSet(GvName(tk, "st"), 2);
         Print("TP2 reached on ticket ", tk);
        }
     }
  }

//+------------------------------------------------------------------+
//| Main evaluation, once per closed candle                           |
//+------------------------------------------------------------------+
void Evaluate()
  {
   int got = CopyRates(_Symbol, _Period, 1, InpBars, R);      // closed candles, oldest first
   if(got < InpEma + 50) { g_status = "Not enough history yet"; ShowPanel(0, 0, ""); return; }
   N = got;
   ArrayResize(O, N); ArrayResize(Hh, N); ArrayResize(Ll, N); ArrayResize(Cc, N); ArrayResize(Tt, N);
   for(int i = 0; i < N; i++) { O[i] = R[i].open; Hh[i] = R[i].high; Ll[i] = R[i].low; Cc[i] = R[i].close; Tt[i] = R[i].time; }
   CalcEma(Cc, InpEma, ema);
   CalcAtr(14);

   Sig smc; smc.ok = false;
   Sig sr;  sr.ok = false;
   int trendNow = 0; string pendTxt = "";
   RunSmc(smc, trendNow, pendTxt);                  // always run: it also builds the trend + swing lists
   if(InpStrategy != STRAT_SMC) RunSr(sr);
   if(InpStrategy == STRAT_SR) smc.ok = false;

   Sig s;
   if(smc.ok) s = smc; else s = sr;
   int htf = InpUseHtf ? HtfBias() : 0;

   // daily trade counter
   MqlDateTime d; TimeToStruct(TimeCurrent(), d);
   int key = d.year * 1000 + d.day_of_year;
   if(key != g_dayKey) { g_dayKey = key; g_dayCount = 0; }

   if(s.ok)
     {
      string why = "";
      if(InpUseHtf && htf != s.dir) why = "HTF bias disagrees";
      else if(HasOpenPosition()) why = "a trade is already open on this symbol";
      else if(InpMaxTradesDay > 0 && g_dayCount >= InpMaxTradesDay) why = "daily trade limit reached";
      else if(InpMaxSpreadPts > 0 && SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpreadPts) why = "spread too wide";
      if(why != "")
        {
         g_status = StringFormat("%s %s signal skipped: %s", s.kind, s.dir == 1 ? "BUY" : "SELL", why);
         Print(g_status);
        }
      else
        {
         double t1, t2, t3;
         TpLevels(s.entry, s.sl, s.dir, s.tp, N - 1, t1, t2, t3);
         if(!InpTpMulti) { t1 = s.tp; t2 = s.tp; t3 = s.tp; }
         OpenTrade(s, t1, t2, t3);
        }
     }
   CleanupGlobals();
   ShowPanel(trendNow, htf, pendTxt);
  }

// Remove saved TP levels of positions that are already closed
void CleanupGlobals()
  {
   string prefix = StringFormat("smcea_%I64d_", InpMagic);
   for(int g = GlobalVariablesTotal() - 1; g >= 0; g--)
     {
      string name = GlobalVariableName(g);
      if(StringFind(name, prefix) != 0) continue;
      string rest = StringSubstr(name, StringLen(prefix));
      int us = StringFind(rest, "_");
      if(us <= 0) continue;
      ulong tk = (ulong)StringToInteger(StringSubstr(rest, 0, us));
      if(!PositionSelectByTicket(tk)) GlobalVariableDel(name);
     }
  }

void ShowPanel(int trendNow, int htf, string pendTxt)
  {
   if(!InpShowPanel) return;
   string st = InpStrategy == STRAT_SMC ? "SMC" : InpStrategy == STRAT_SR ? "Support & resistance" : "SMC + S/R";
   Comment(StringFormat("SMC + S/R EA  |  %s  |  risk %.2f%%\nTrend: %s   HTF %s: %s\n%s\nTrades today: %d\nLast: %s",
           st, InpRiskPct,
           trendNow == 1 ? "UP" : trendNow == -1 ? "DOWN" : "none",
           EnumToString(InpHtf), !InpUseHtf ? "off" : htf == 1 ? "UP" : htf == -1 ? "DOWN" : "n/a",
           pendTxt, g_dayCount, g_status == "" ? "waiting for a signal" : g_status));
  }
//+------------------------------------------------------------------+
