# Gold ORB Pro EA

MetaTrader 5 Expert Advisor implementing an Opening Range Breakout (ORB)
strategy on **XAUUSD**, executing on the M15 timeframe with an H1 200 EMA
trend filter.

## Source

- `MQL5/Experts/GoldORBPro/GoldORBPro.mq5`

## Strategy summary

- Symbol: XAUUSD only (rejects all other symbols on init).
- Records the high/low of the first 30 minutes of the London session each
  day as `ORB_High` / `ORB_Low`, drawn as horizontal lines on the chart.
- H1 200 EMA trend filter: buys only above EMA, sells only below EMA.
- Entry: M15 candle closes beyond the ORB level with a body >= 60% of its
  range, executed at market immediately after the candle closes.
- Risk: 0.5% of balance per trade, lot size derived from SL distance.
- SL beyond the opposite ORB boundary (+ buffer), TP at fixed 2:1 R:R.
- Break-even at 1R, ATR-free trailing stop behind the previous completed
  M15 candle from 1.5R onward.
- Daily loss/profit circuit breakers (2% loss / 3% profit), max 2 trades
  per day, max 1 trade per direction per day.
- Spread filter, ORB range filter, and placeholder news-filter hooks
  (`IsHighImpactNewsComing`, `IsNewsBlocked`).
- On-chart dashboard with ORB levels, trend, daily P/L, trade count, risk
  per trade, and news status.

## Installation

1. Copy `GoldORBPro.mq5` into your MT5 data folder under
   `MQL5/Experts/GoldORBPro/`.
2. Compile in MetaEditor.
3. Attach to an XAUUSD M15 chart.
4. Adjust `InpLondonOpenHour` / `InpLondonOpenMinute` to match your
   broker's server-time offset for the London session open (08:00 GMT).
