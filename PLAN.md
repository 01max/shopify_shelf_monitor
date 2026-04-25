# Implementation Plan

## Phase 1 — Fix collection pagination missing last page

### Problem

`ShowroomClient#collection_products` (`services/showroom_client.rb:38-51`) paginates by fetching pages until `batch.empty?`. The Shopify storefront JSON API can return a non-empty result on pages beyond the last real page (wrapping back to the first page), which means the loop either never terminates or silently misses products on the boundary.

The collection object exposes `products_count` (from `Showroom::Collection#products_count`) which gives the server-reported total. The fix should use this count to know when all products have been fetched.

### Changes

**`services/showroom_client.rb`** — Rewrite `collection_products` to accept the expected total from `collection.products_count` and stop when `products.size >= expected_count` or when a page returns fewer items than the limit (whichever comes first). Keep the `batch.empty?` check as a secondary safety net.

```ruby
def collection_products(collection)
  products = []
  expected_count = collection.products_count
  page = 1
  limit = 250

  loop do
    batch = throttle { collection.products(limit: limit, page: page) }
    break if batch.empty?

    products.concat(batch)
    break if expected_count && products.size >= expected_count
    break if batch.size < limit

    page += 1
  end

  products
end
```

**`spec/services/showroom_client_spec.rb`** — Add specs:
- Collection with products_count matching fetched total stops cleanly.
- Collection where last page is exactly full (250 items) does not fetch an extra page that wraps around.
- Nil products_count falls back to `batch.size < limit` guard.

### Scope

- 2 files modified: `services/showroom_client.rb`, `spec/services/showroom_client_spec.rb`

---

## Phase 2 — Debug mode: output to file instead of Telegram

### Problem

During development and debugging, running `check.rb` sends real Telegram messages. A local debug mode should write formatted output to a file instead.

### Design

Add a `DebugNotifier` that replaces `Telegram::ChatService` when a `DEBUG` env var is set. The watch services (`Product::WatchService`, `Collection::WatchService`) already build a `Telegram::ChatService` in their private `send_notifications` method. Rather than threading a flag through every service, introduce a thin `Notifier` factory that returns either the real Telegram service or a file-based debug notifier, depending on the environment.

### Changes

**`services/notifier.rb`** (new) — Factory module with `.build(chat_params)` that returns a `Telegram::ChatService` or a `DebugNotifier` depending on `ENV['DEBUG']`.

**`services/debug_notifier.rb`** (new) — Duck-types to `Telegram::ChatService` (`deliver`, `send_media_group`). Writes output to `tmp/debug_output.txt` (appends, with timestamps). On `send_media_group`, logs the URLs.

**`services/product/watch_service.rb`** — Replace `Telegram::ChatService.new(**chat_params)` with `Notifier.build(chat_params)` in `send_notifications`.

**`services/collection/watch_service.rb`** — Same replacement in `send_notifications`.

**`spec/services/debug_notifier_spec.rb`** (new) — Verify file output format.

### Config

- `DEBUG=true bundle exec ruby check.rb` to activate.
- Output goes to `tmp/debug_output.txt`.

### Scope

- 2 new files: `services/notifier.rb`, `services/debug_notifier.rb`
- 2 files modified: `services/product/watch_service.rb`, `services/collection/watch_service.rb`
- 1 new spec: `spec/services/debug_notifier_spec.rb`

---

## Phase 3 — Run collection checks weekly on a separate GitHub Actions workflow

### Problem

`check.yml` runs every 4 hours and processes all watches (both `type: products` and `type: collection`). Collection watches should run only once a week on a separate schedule.

### Design

Split the concern at the entry-point level. Add a `CHECK_TYPE` environment variable filter to `check.rb` so it can selectively run only `products` or `collection` watches. Create a second workflow for the weekly collection run.

### Changes

**`check.rb`** — In `run_all_watches`, filter `config` entries by `CHECK_TYPE` env var when set. If `CHECK_TYPE=products`, skip `type: collection` entries. If `CHECK_TYPE=collection`, skip `type: products` entries. If unset, run everything (backward-compatible).

**`.github/workflows/check.yml`** — Add `CHECK_TYPE: products` to the "Run shelf check" step env. This makes the 4-hourly job run product watches only.

**`.github/workflows/check_collections.yml`** (new) — Weekly cron (`0 6 * * 1`, Monday 6am UTC), same structure as `check.yml` but with `CHECK_TYPE: collection`. Uses its own artifact name (`report-collections`) to avoid clobbering the product report.

**Report handling** — `ReportBuildService` currently writes a single `tmp/report.json`. With split workflows, each needs its own report file. Change `REPORT_PATH` to be derived from `CHECK_TYPE`:
- `tmp/report.json` when no filter (default, backward-compatible)
- `tmp/report-products.json` when `CHECK_TYPE=products`
- `tmp/report-collections.json` when `CHECK_TYPE=collection`

Similarly, `load_previous_data` in `check.rb` must read the matching report path.

**Specs** — Add specs for the filtering logic in `check.rb` (or extract it to a small helper).

### Scope

- 2 files modified: `check.rb`, `.github/workflows/check.yml`
- 1 new file: `.github/workflows/check_collections.yml`
- 1 file modified: `services/report_build_service.rb`

---

## Phase 4 — List similar products weekly, ordered by price

### Problem

For each product in a `type: products` watch, fetch similar products via `Showroom::Product#similar` and send a weekly digest listing them ordered by price.

### Design

This is a distinct action from the regular "change detection" check. It should:
1. Run on a weekly schedule (can share the `check_collections.yml` workflow day or have its own).
2. For each `type: products` watch, fetch each product, call `.similar` on it, and format a message listing similar products sorted by price.
3. Send the digest via Telegram (or debug notifier).

### Changes

**`services/product/similar_service.rb`** (new) — Takes a watch name, params, logger. For each handle, fetches the product via `ShowroomClient`, calls `product.similar` (which returns `Search::ProductSuggestion` objects already orderable by price), and collects results. Returns a structured hash per product with its similar products.

Note: `ShowroomClient#find_product` returns a `Showroom::Product` which has a `.similar` method. The `similar` method uses the client's `search` method internally and returns `Search::ProductSuggestion` objects with `.title`, `.handle`, `.price`. It already strips SKU fragments from handles and falls back to title-based search. Results can be ordered by price via `products(order: 'price')`.

**`services/similar_format_service.rb`** (new) — Formats the similar products into a Telegram message. For each watched product, list its title/price, then a numbered list of similar products with title, price, and handle.

**`check.rb`** — Add a `CHECK_TYPE=similar` branch that runs `Product::SimilarService` instead of the regular watch services.

**`.github/workflows/check_similar.yml`** (new) — Weekly cron, `CHECK_TYPE=similar`. No artifact needed (no state to persist across runs).

**`config.yml`** — No config changes needed. The similar check operates on existing `type: products` watches.

**`spec/services/product/similar_service_spec.rb`** (new) — Mock `ShowroomClient` and `Showroom::Product#similar`, verify output structure.

**`spec/services/similar_format_service_spec.rb`** (new) — Verify Telegram message formatting.

### Scope

- 2 new service files: `services/product/similar_service.rb`, `services/similar_format_service.rb`
- 1 new workflow: `.github/workflows/check_similar.yml`
- 1 file modified: `check.rb`
- 2 new specs

---

## Execution Order

Phases are designed to be built and merged sequentially:

1. **Phase 1** (pagination fix) — standalone bug fix, no dependencies
2. **Phase 2** (debug mode) — standalone, useful for testing phases 3-4
3. **Phase 3** (weekly collection split) — introduces `CHECK_TYPE` filtering and report splitting
4. **Phase 4** (similar products) — builds on `CHECK_TYPE` pattern from phase 3
