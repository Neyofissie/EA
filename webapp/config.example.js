// Example of the optional config.js that builds keys into the app, so you don't type them on every device.
// Easiest: in the app open Settings → "Build keys into the app" → "Create config.js".
// Or copy this file to config.js, fill in your values and upload it next to index.html.
// Anyone who opens your site can read these values. Never put your MT5 password or MetaApi token here.
window.SMC_CONFIG = {
  twelveDataKey: "YOUR_TWELVE_DATA_KEY",
  defaultSource: "twelvedata",          // what a brand-new device opens with: "twelvedata", "binance" or "demo"
  // telegram: { botToken: "123456789:AA...", chat: "-1001234567890" }
};
