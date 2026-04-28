# ShopifyShelfMonitor

A Ruby script that monitors a Shopify store for product price/availability changes and collection updates, running on a schedule via GitHub Actions. Notifications are sent to Telegram.

Built on top of the [showroom](https://github.com/01max/showroom) gem for unauthenticated access to Shopify's public JSON API.

## Features

- **Product monitoring** — track a list of products by handle, get notified when price or availability changes
- **Collection monitoring** — track a collection, get notified when products are added/removed or when price/availability changes
- **Similar products** — weekly digest of similar products for each tracked handle
- **Telegram bot commands** — add products or inspect config directly from Telegram without touching the repo
- **State persistence** — stores a JSON report as a GitHub Actions artifact, compared against the next run to detect changes
- **Rate limiting** — configurable delay between API requests to avoid hitting Shopify's rate limits
- **Telegram notifications** — Markdown-formatted messages with product details, price diffs, and availability changes

## Setup

### Requirements

- Ruby >= 3.3
- A Telegram bot token ([create one via BotFather](https://core.telegram.org/bots#botfather))
- A Telegram chat ID to send notifications to

### Local development

```bash
git clone https://github.com/01max/shopify_shelf_monitor.git
cd shopify_shelf_monitor
bundle install
cp .env.example .env       # fill in Telegram credentials
cp config.yml.example config.yml  # fill in your watches
```

Run the product check:

```bash
bundle exec ruby check.rb
```

Force a notification even if nothing changed:

```bash
FORCE_NOTIFY=true bundle exec ruby check.rb
```

Poll pending Telegram commands:

```bash
bundle exec ruby poll_commands.rb
```

### GitHub Actions

1. Push the repository to GitHub
2. Add the following secrets in **Settings → Secrets and variables → Actions**:

| Secret | Description |
|--------|-------------|
| `TELEGRAM_BOT_TOKEN` | Your Telegram bot token |
| `TELEGRAM_DEFAULT_CHAT_ID` | Default chat ID for notifications and authorized command source |
| `SHELF_MONITOR_CONFIG` | Contents of your `config.yml` (used as fallback if no artifact exists) |

Four workflows run on schedule:

| Workflow | Schedule | What it does |
|----------|----------|--------------|
| `check.yml` | Every 4 hours | Checks product watches for price/availability changes |
| `check_collections.yml` | Mondays at 6 UTC | Checks collection watches |
| `check_similar.yml` | Tuesdays at 6 UTC | Sends a similar-products digest for each product watch |
| `poll_commands.yml` | Every 6 hours | Processes pending Telegram bot commands |

All workflows can also be triggered manually from the Actions tab. Product and collection checks accept a `force_notify` flag.

Each workflow auto-disables after 3 consecutive failures to avoid silent breakage.

**Config persistence:** when a `/add` command modifies `config.yml`, the updated file is uploaded as a `config` artifact. Subsequent workflow runs restore it before falling back to the `SHELF_MONITOR_CONFIG` secret, so changes survive across runs without a code push.

## Telegram commands

Send commands from the chat identified by `TELEGRAM_DEFAULT_CHAT_ID`. The bot processes them the next time the `poll_commands` workflow runs (within 6 hours).

### `/config`

Sends the current `config.yml` back as a code block.

### `/add <product_url> [config_key]`

Extracts the product handle from a Shopify product URL and appends it to a `products` watch.

```
/add https://my-store.myshopify.com/products/air-max-95
```

If your config has more than one `products` watch, pass the key explicitly:

```
/add https://my-store.myshopify.com/products/air-max-95 favorite_sneakers
```

## Configuration

Each top-level key in `config.yml` defines a watch. Two types are supported:

### Product watch

Monitors individual products by handle. Also used for the similar-products digest.

```yaml
favorite_sneakers:
  type: products
  store: my-store.myshopify.com
  handles:
    - air-max-90
    - ultraboost-22
  rate_limit_ms: 500             # optional, default 500ms between API calls
  telegram_chat_id: "123456789"  # optional, overrides TELEGRAM_DEFAULT_CHAT_ID
```

### Collection watch

Monitors all products in a collection. Detects new/removed products in addition to price and availability changes.

```yaml
new_arrivals:
  type: collection
  store: my-store.myshopify.com
  handle: new-arrivals
  rate_limit_ms: 600
```

## Development

Run the tests:

```bash
bundle exec rspec
```

Run the linter:

```bash
bundle exec rubocop
```

## License

GPL-3.0-or-later
