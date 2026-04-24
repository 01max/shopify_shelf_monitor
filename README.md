# ShopifyShelfMonitor

A Ruby script that monitors a Shopify store for product price/availability changes and collection updates, running on a schedule via GitHub Actions. Notifications are sent to Telegram.

Built on top of the [showroom](https://github.com/01max/showroom) gem for unauthenticated access to Shopify's public JSON API.

## Features

- **Product monitoring** — track a list of products by handle, get notified when price or availability changes
- **Collection monitoring** — track a collection, get notified when products are added/removed or when price/availability changes
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

Run the check:

```bash
bundle exec ruby check.rb
```

Force a notification even if nothing changed:

```bash
FORCE_NOTIFY=true bundle exec ruby check.rb
```

### GitHub Actions

1. Push the repository to GitHub
2. Add the following secrets in **Settings → Secrets and variables → Actions**:

| Secret | Description |
|--------|-------------|
| `TELEGRAM_BOT_TOKEN` | Your Telegram bot token |
| `TELEGRAM_DEFAULT_CHAT_ID` | Default chat ID for notifications |
| `SHELF_MONITOR_CONFIG` | Contents of your `config.yml` |

The workflow runs every 4 hours by default. You can also trigger it manually from the Actions tab, with an optional `force_notify` flag.

The workflow auto-disables after 3 consecutive failures to avoid silent breakage.

## Configuration

Each top-level key in `config.yml` defines a watch. Two types are supported:

### Product watch

Monitors individual products by handle.

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
