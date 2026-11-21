# SMC + S/R Expert Advisor for MetaTrader 5

`SMC_SR_EA.mq5` trades the same rules as the web scanner, automatically, inside MT5.

## Install
1. In MT5: **File → Open Data Folder** → `MQL5/Experts/`. Copy `SMC_SR_EA.mq5` there.
2. Open **MetaEditor** (F4), open the file, and press **Compile** (F7). It should report *0 errors*.
3. Back in MT5, open a chart (e.g. EURUSD M15) and drag **SMC_SR_EA** from the Navigator onto it.
4. On the *Common* tab tick **Allow Algo Trading**, then turn on the **Algo Trading** button in the toolbar.
5. Attach one copy per symbol/chart. The chart's timeframe is the strategy timeframe.

## Test first
- **Strategy Tester** (Ctrl+R): choose the EA, symbol, timeframe and *Every tick based on real ticks*, and run.
  Set **Broker GMT offset** manually in the tester (e.g. 2 or 3), because auto-detect only works live.
- Then run it on a **demo account** for a few weeks before using real money.

## What it does
- **Evaluation:** once per closed candle it replays the last 1,500 candles (the same rules as the web app) and acts only on a signal from the candle that just closed.
- **SMC:** trend filter → BOS → retest of the level / order block / FVG → rejection candle. Optional: confluence score, required confluences, CHoCH entries.
- **Support & resistance:** bounce and flip trades at multi-touch zones.
- **HTF filter:** the last closed HTF candle must be above (buy) / below (sell) its EMA.
- **Lot size:** chosen so that hitting the SL loses *Risk %* of the balance (rounded down to the lot step).
- **One market order** with the SL and TP3 set on the broker's server:
  - **TP1:** the EA closes *TP1 %* of the position and moves the SL to entry.
  - **TP2:** it closes *TP2 %*.
  - **TP3:** the rest closes at TP3 on the server.
  - Partial exits need MT5 running (use a VPS). The SL and TP3 stay on the server even if MT5 is closed.
- **Safety:**
  - One trade per symbol at a time.
  - Max trades per day.
  - Max spread.
  - The signal is skipped if price is already past TP1 or the SL, or if the stops are inside the broker's stop level.
- **Status panel:** top-left of the chart (trend, HTF, pending setup, last action). Every action is also printed in the *Experts* log.

## Notes
- **Netting and hedging:** the EA works on both account types (a single position per symbol).
- **Kill zones** use UTC. The EA converts broker time with the GMT offset.
- **Different from the web app:** the EA enters at market on the next tick after the signal candle closes, so fills and spread differ slightly from the web app's backtest.
