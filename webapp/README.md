# SMC BOS + Retest Scanner (web app)

A single-page app. It loads live candles, runs the SMC trend + break of structure + retest logic in the browser, and draws the signals on a TradingView Lightweight Charts chart. A second tab shows the official TradingView chart for the same symbol.

![screenshot](screenshot.png)

## Run it
- **Locally:** open `index.html` in Chrome or Edge. You can also run `npx serve webapp` and open the URL it prints.
- **Online:** turn on GitHub Pages for this repo and use `/webapp/index.html`.

## Live data sources
| Market | Source | Key needed? |
|---|---|---|
| Crypto (BTCUSDT, ETHUSDT…) | Binance public market data | No |
| Forex, gold, indices, stocks (EUR/USD, XAU/USD…) | Twelve Data | Free API key from twelvedata.com. Paste it in **Settings**. The free plan allows 8 requests/min, so the watchlist scans slowly. |
| Demo | Generated candles | No |

## Use
1. Pick a source, symbol, timeframe and HTF, then press **Scan chart**.
2. **Scan all** checks your watchlist. Click a row to load that symbol on the chart.
3. Set **Auto** to re-scan every 1/5/15 min. Enable notifications in Settings to get a popup and a sound on each new signal. The tab has to stay open.
4. All strategy settings (swing length, trend filter, retest tolerance, SL buffer, R:R) are under **Settings**.

## Backtest
Open the **Backtest** tab and pick *This chart* or *Whole watchlist*. Choose 1,000–5,000 candles and set costs per trade (in R) and risk per trade, then press **Run backtest**.
The backtest replays the same rules over past closed candles and checks which was hit first, SL or TP (SL wins ties on the same candle). It reports trades, win rate, profit factor, net R and %, max drawdown, the longest losing run, an equity curve, a per-pair breakdown and every trade.
Demo data is synthetic and very trendy, so use Binance or Twelve Data for real results. Checked for look-ahead bias: on pure random-walk data the strategy wins about 31% at 1:2 (break-even is 33%).

## Support & Resistance strategy
Pick **Support & Resistance** (or **Both strategies**) in the selector at the top left.
- **Zones:** confirmed swing highs and lows that land within `zone width × ATR` of each other are grouped into one zone. A zone counts once it has been touched at least *min touches* times (default 2). Zones not touched for *N* candles are dropped.
- **Bounce:** price dips into a support zone and a bullish candle closes back above it → BUY. Resistance mirrors this → SELL.
- **Flip:** a zone that price recently broke through and then retested from the other side (old resistance as new support) is labelled *S/R flip*.
- **Stop loss** goes beyond the zone (or the candle's wick) plus the SL buffer. **Take profit** is the next S/R level, or a fixed R:R. With *next level*, a trade is skipped when there is less than *min room* (default 1.5R) to that level.
- **Trend:** by default trades are only taken with the trend, and with the HTF bias when that is turned on.
- **On the chart:** the nearest zones are drawn with their touch count (S ×3 / R ×2). The forecast shows the nearest tradeable zone as a limit order. The backtest splits results into SMC / S/R bounce / S/R flip.

## SMC confluences
Settings → **SMC confluences**. All are off by default, so results match the original BOS + retest strategy until you turn something on.

| Confluence | How it's checked (buy side; sells are mirrored) |
|---|---|
| Order block | Last bearish candle at or just before the leg's low (up to 5 candles back). Counts when the entry candle trades into it. |
| Fair value gap | Most recent unfilled 3-candle gap (candle 1 high < candle 3 low) in the leg that broke structure. Counts when the entry candle trades into it. |
| Liquidity sweep | The leg's low wicked below the previous swing low, then closed back above it on the same or the next candle. |
| Displacement | A candle with body ≥ *N × ATR* (default 1.0) in the break direction, among the last 3 candles of the break. |
| Premium / discount | Entry is below 50% of the range from the leg low to the high made after the break. |
| Kill zone | Entry candle opens in London 07–10 or New York 12–15 UTC (always passes on 4h and above). |

- **Entry zone (POI):** broken level (default), order block, FVG, or any of them. The trade triggers when price taps the zone and a rejection candle closes back past the zone's middle. The setup is cancelled on a close beyond the deepest zone.
- **CHoCH reversals:** optional. A break against the current structure becomes a setup too, labelled *SMC CHoCH*.
- **Filters:** choose a *minimum confluence score* (0–6) and/or tick confluences as *required*.
- **Backtest:** shows win rate and average R **with vs without** each confluence, and by score, so you can see which ones help on your pairs.

## Forecast on the chart
The forecast is drawn as a position box to the right of price, the way a broker's long/short tool looks:
- **Box:** green box from entry to **TP**, red box from entry to **SL**, with price tags and a **▲ LONG / ▼ SHORT** pill (plus *LIMIT* or *IF BREAK* while it isn't triggered yet).
- **Badges:** **R:R** shows the reward-to-risk. The **%** badge is the share of past setups on this chart that hit TP (shown once there are at least 3).
- **Zones:** shaded rectangles labelled *Demand / Supply Order Block*, *FVG*, *Support ×n*, *Resistance ×n*.
- **Chart labels** (Settings → Chart labels): HH / HL / LH / LL swing points, **BSL / SSL** liquidity sweeps (a wick through a swing that closes back inside), and **LO / NY / LC KZ** kill zone starts (London open 07, New York 12, London close 15 UTC).
- **Faded box:** the forecast goes against the HTF bias, so the scanner won't signal it.
