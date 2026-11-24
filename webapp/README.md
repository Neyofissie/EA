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

## TP1 / TP2 / TP3 (partial exits)
Settings → **Take profits** (on by default; switch to *Single TP* for the old behaviour):
- **TP1:** at *N*R (default 1R). Close 50%, then (optionally) move the stop to entry.
- **TP2:** the strategy's own target (the R:R setting for SMC, the next S/R level for S/R). Close 30%.
- **TP3:** the nearest **untaken swing high/low beyond TP2** (resting liquidity, only swings already confirmed at the signal). If there is none within 8R, it uses a fixed R multiple (default 3R). Close 20%.
- **Split:** change it with e.g. `40/40/20`.

The backtest simulates the partial exits candle by candle. The stop is checked first on every candle, so a candle touching both SL and TP counts against you. It reports TP1 / TP2 / TP3 hit rates and the real R per trade. In single-TP mode the results are identical to before.

## Broker · MT5 (auto-trading through MetaApi)
The app can place trades on your MT5 account through **MetaApi** (metaapi.cloud), which runs MT5 in the cloud.

1. Create a MetaApi account and copy your **API token** (app.metaapi.cloud → API access).
2. In the app press **Broker · MT5**, paste the token, then enter your **MT5 login, password and server** (exactly as shown in MT5), and press **Save & connect**.
   The password is sent only to MetaApi, which stores it, and it is not kept in this app. The token is saved in this browser unless you choose not to remember it.
3. Pick a **risk %** and **max open trades**. Add a **symbol suffix** or name map if your broker uses names like `EURUSD.m` or `GOLD`.
4. Either press **Send this trade to MT5** under *Current chart* when a signal fires, or switch **Auto-trade** on.

**How orders are placed:**
- **Lot size:** chosen so that hitting the SL loses *risk %* of the balance (MetaApi's tick value and lot step).
- **Hedging accounts:** three positions with TP1 / TP2 / TP3 on the broker's server. When TP1 fills, the app moves the other two to break-even.
- **Netting accounts:** one position with the SL and TP3 on the server. The app closes the TP1 / TP2 parts and moves the stop.

**Safety:**
- One trade per symbol.
- Max open trades.
- Skipped if price is already past TP1 or the SL.
- Demo data is never traded.

**Limits:**
- Auto-trading and the partial exits only run while the page is open. The SL/TP on the server always stay in place. For 24/7 trading use the MT5 EA in `/mt5`.
- MetaApi has a free tier with limits; check their pricing.
- Test with a **demo account** first.

## Quality filters, risk guards and the walk-forward optimizer
All of these are in **Settings**. The filters start **off** (except news and the risk guards), so you can switch them on one at a time and test each.

| Feature | What it does |
|---|---|
| **HTF filter** | *EMA bias* (as before), *HTF market structure* (direction of the last HTF break), or *both*. |
| **HTF discount / premium** | Buys only below the middle of the HTF dealing range (last HTF swing low → high); sells only above it. |
| **Min ADX** | Skips signals when ADX(14) is below the value (choppy market). Around 20–25 is typical. |
| **Volatility band** | Skips signals when ATR is far below or above its 100-candle average (e.g. 0.7–2.0). |
| **LTF CHoCH confirmation** | The previous and the signal candle must show a lower-timeframe break back in the trade direction inside the retest (15m→5m, 1h→15m, 4h→1h…). The stop moves just beyond that LTF swing, which gives a better R:R. Only LTF candles that had closed by the signal close are used. The backtest only counts the period that has LTF data. |
| **Trailing TP3** | *TP3 → Trailing stop*: after TP2 the runner has no fixed target; its stop follows the last confirmed swing low / high. |
| **News filter** | Loads this week's high-impact events from a free public calendar (nfs.faireconomy.media). No new alerts or broker trades on a pair from *N* minutes before to *N* minutes after news for either of its currencies. Live only: there is no historical calendar, so the backtest can't apply it. If the calendar can't be loaded, the Forecast panel says so. |
| **Correlated trades** | No new trade if an open one shares a currency on the same side (EURUSD long + GBPUSD long both sell USD). |
| **Max open / daily loss** | Backtest: max open trades and a daily loss limit in R. Broker: max open trades and a daily loss limit in % of the day's starting balance. |
| **By session** | The backtest shows results for Asia / London / New York / late entries. |

The backtest also always applies **one open trade per pair**, like live trading.

### Walk-forward optimizer (Backtest → Optimize)
1. **Grid:** tests 432 combinations of R:R, retest tolerance, SL buffer, minimum confluence score and minimum ADX.
2. **In-sample:** each combination is scored on the **oldest 70%** of every pair, by average R. The top 10 are listed.
3. **Out-of-sample:** each of those is then checked on the **newest 30%**, which it was never tuned on.
4. **Choosing:** only trust settings that are good on both halves; a big in-sample number with a weak out-of-sample number is overfitting. **Apply** copies a row's settings into the app.

The forecast's **Filters** row shows ✓ / ✗ for every active filter on the current setup, and **News** shows the next relevant event.

## Sharing signals to Telegram
- **Copy signal** (top of the Forecast, and *Copy* on every row of the signal history) copies a ready-to-paste message: pair, timeframe, BUY/SELL, entry, SL, TP1/TP2/TP3 with R multiples, R:R, exit plan, confluences, track record, time (UTC) and an optional disclaimer line.
- **Share…** (phones) opens the system share sheet, so you can pick Telegram and the group.
- **Send to Telegram** posts it directly through your own bot:
  1. In Telegram, open **@BotFather** → `/newbot` and copy the token.
  2. Add the bot to your group or channel as an **admin**, and send any message there.
  3. In the app: **Settings → Telegram**, paste the token, press **Find my groups**, pick the group (or type the chat ID / `@channel`), then press **Send test message**.
  4. Optionally switch on **Post new signals automatically** (and *setups forming*). Like the other alerts, this only runs while the app is open.

The bot token is stored only in this browser.

## SMC mode: Fast (current leg) vs Classic
Settings → **SMC mode**. **Fast** is the default.
- **Fast: follow the current leg.**
  - **Trend:** the direction of the last close through a swing high or low. A CHoCH flips it straight away instead of waiting for the 200 EMA.
  - **Setups:** come from **internal swings** (default 2 candles each side) inside that leg, so the strategy reacts to breaks in the move that is happening now. The bigger swings (swing length) still define the leg.
  - **Retest, confluences, TP1–TP3 and filters:** work exactly as before.
- **Classic:** the original behaviour. Swing-length structure and the selected trend filter (EMA / structure / last break). Classic gives the same backtest results as before this change.

Fast mode produces more setups. Compare both on your pairs with the Backtest or the walk-forward optimizer.

## High-probability alerts and phone notifications
- **Settings → Alerts:** *Only alert high-probability setups* (on by default). An alert fires only when at least **50%** of the chart's past setups succeeded, with at least **8** past setups. Both numbers can be changed. The same rule can also apply to MT5 auto-trading.
- **What gets the rule:** toasts, the sound, system notifications and automatic Telegram posts. Every alert shows the rate, e.g. "75% of 12 past setups hit TP1". This is history on that pair / timeframe / settings, not a guarantee.
- **Enable alerts on this device** is under *Account* (or *Settings → Enable notifications*).
- **Installable app:** the app now ships with `sw.js`, `manifest.webmanifest` and two icons.
  - **Upload the whole `webapp` folder** to Netlify, not only `index.html`.
  - Android needs the service worker for notifications.
  - On iPhone, add the app to the Home Screen and open it from there before enabling alerts (iOS 16.4+).
- **Limits:** a web page can only scan while it is open. Phones pause pages in the background or when locked. For alerts when you are away, leave the app open with *Auto* on, on a computer (or a phone kept on, plugged in, with the app in front), and turn on Telegram auto-post. Telegram then pushes to your phone.

### Alerts for 2:1 setups
*Settings → Alerts → Measure success as: Reached the R:R target before the stop* (default, target **2** = 2:1).
- **How it's measured:** for every past setup on the chart, the app checks whether price moved **2× the risk** in the trade's favour **before touching the original stop loss**. A candle that touches both counts as a loss.
- **When an alert fires:** that rate must be at least *min %* over at least *min past setups*, and the setup's own target (TP2) must be at least 2:1.
- **Where you see it:** the chart's % badge, the watchlist *Hit %* and the Forecast's *Reached 2R* line all show this rate. The badge turns **yellow** when a setup meets the rule.
- **Choosing the %:** by pure chance a 2:1 target is reached about one time in three. Charts at 50–60%+ are already strong, so the default is 50%.

## Multi-timeframe trend
- **What you see:** every scan shows the trend on **1D → 4H → 1H → 15m → 5m** (plus your chart and HTF timeframes), using the strategy's own trend rule. For example **1D ▲ 4H ▲ 1H ▲ 15M ▲ 5M ▲ · ALIGNED ▲**, or *MIXED 3▲ 2▼*.
- **Where:** the chart legend, the Forecast (*Timeframes*, plus whether they agree with the trade), the watchlist *Timeframes* column and Telegram messages.
- **Settings → Alerts → Only alert when every timeframe agrees:** alerts fire only if all timeframes point the same way as the trade.
- **Twelve Data free plan:** the check costs about 3 extra requests for the chart you are viewing, cached for up to 30 minutes, and arrives a few seconds after the chart. For the whole watchlist it is off by default on Twelve Data and can be switched on in Settings.

## Build your keys into the app (no typing on each device)
1. In the app: **Settings** → paste your Twelve Data key (and set up Telegram if you want it included).
2. **Build keys into the app → Create config.js**. This downloads `config.js`.
3. Put `config.js` in the app folder next to `index.html` and upload the whole folder to Netlify again.
4. Every phone and computer that opens the site now uses those keys automatically. A key typed in Settings on a device overrides the built-in one on that device.

**Things to know:**
- Keys built into a website can be read by anyone who opens it, so keep the link private.
- If a key leaks, create a new one and rebuild `config.js`.
- The MT5 login and MetaApi token are never put in this file.
- `config.js` is git-ignored, so it is never committed. `config.example.js` shows the format.

## Indices: US30, NAS100, SPX500
- **Typing a broker index name** switches to Twelve Data automatically: **US30** (also DJ30, WS30), **NAS100** (US100, USTEC) or **SPX500** (US500).
- **Data source:** the app first asks Twelve Data for the index itself (DJI / NDX / SPX). If your plan doesn't include it, it uses the ETF that tracks it (DIA / QQQ / SPY) and says so in the status line. The ETF moves the same way but only trades in US market hours. The choice is remembered.
- **Elsewhere:** the TradingView tab shows the real index. MT5 orders use your broker's name (US30 + your suffix, or the name map in Broker settings). News and correlation treat these indices as USD-linked.

## Scanning animation
- **The lamp:** while a chart scan is running, a scanner-lamp light glides left → right across the candles, brightening them as it passes. It eases in and out like a real scanner carriage.
- **The label** shows the real step: *Downloading candles…*, *Reading 4H trend…*, *Reading structure…*, *Drawing the setup…*. On Twelve Data's free plan it counts down: *Waiting 6 s for the free-plan data limit*.
- **When the scan ends:** the lamp slows to a stop at the latest candle and fades. The trade box is then laid down from the entry line (about 0.3 s), and the Setup tab dot pulses once if a setup is ready. Fast scans get one short pass.
- **When a scan fails:** the lamp stops where it is and turns red (*Scan stopped*) before the error shows.
- **Reduce Motion:** if it is turned on in the phone or computer settings, there is no lamp or draw-in, only the label.
