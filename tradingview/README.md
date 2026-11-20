# SMC Break-of-Structure + Retest (trend-following) — TradingView

Two Pine Script v6 files:

| File | What it does |
|---|---|
| `SMC_BOS_Retest_Indicator.pine` | Runs on the chart you're viewing. Draws BOS levels, BUY/SELL retest signals, SL/TP lines, a status panel, and has alerts. |
| `SMC_BOS_Retest_Scanner.pine` | Scans up to 12 symbols you pick, on a timeframe you pick. Shows a table (trend, HTF bias, pending setups, latest signal with entry/SL/TP) and fires one alert per new signal. |

## Strategy logic
1. **Trend**: price above/below the trend EMA (default 200) with the EMA sloping that way, and/or market structure (HH+HL = up, LH+LL = down). There's also an optional HTF EMA bias (default 4H EMA 50).
2. **BOS**: a candle **closes** beyond the last confirmed swing high (bullish) or swing low (bearish), and only in the trend's direction. A break against the trend (a CHoCH) is ignored.
3. **Retest**: within *N* bars (default 20) price pulls back to the broken level (± `tolerance × ATR`) and closes back on the trend side. With the rejection-candle option on, the candle must also close in the trend direction. That candle gives the **signal**.
4. **Cancel**: the setup is dropped if price closes back through the level beyond the tolerance, or if the retest doesn't come in time.
5. **Risk**: SL goes beyond the retest wick or the level, plus `buffer × ATR`. TP = entry ± R:R × risk.

## Install
1. TradingView → **Pine Editor** → *New* → paste a file → **Save** → **Add to chart**.
2. Open the settings (gear icon) to change symbols, scan timeframe, HTF, trend filter, swing length, tolerance, and R:R.

## Scanner alerts
- Put the scanner on any chart. Use a chart timeframe **equal to or lower than** the scan timeframe (e.g. a 5m or 15m chart for a 15m scan).
- Create an alert → Condition: *SMC BOS + Retest Scanner* → **Any alert() function call** → once per bar close.
  The message includes the symbol, direction, entry, SL and TP.
- Symbol format is `EXCHANGE:TICKER` (e.g. `OANDA:EURUSD`, `FX:GBPJPY`, `BINANCE:BTCUSDT`). Untick a row to disable it.

## Notes
- "Use closed bars only" (on by default) prevents repainting. Signals appear after the scan-timeframe bar closes.
- An alert keeps the settings it was created with. If you change inputs, delete the alert and create it again.
- The indicator also outputs hidden `Signal` / `Pending BOS` / `Trend` plots. You can use them in TradingView's Pine Screener if your plan includes it.
- This is a signal tool, not financial advice. Backtest and forward-test before trading real money.
