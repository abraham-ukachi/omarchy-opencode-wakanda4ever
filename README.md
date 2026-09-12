# Wakanda4Ever — OpenCode Conversation Dashboard

> **"We'll always do more 😜"**

A pocket-sized **Omarchy** bar & panel plugin that turns your **OpenCode**
session history into a living, breathing dashboard right on your desktop —
prompt counts, hot session topics, and the storage footprint of your memory
files, all in your Omarchy theme.

<br>

## Demo / Usage

```sh
# from the plugin folder
omarchy plugin add /path/to/omarchy-opencode-wakanda4ever --enable
omarchy restart shell
```

A **Wakanda4Ever** button shows up in your bar. Click it to open the
dashboard:

- **PROMPTS · TOTAL** — how many prompts OpenCode has ever processed (compact
  `1.2k` big number + full `1,234` figure below it)
- **TOP 3 TOPICS** — your hottest session themes, ranked by recency & mention
  count, each with a representative *quote* from the actual conversation
- **MEMORY FOOTPRINT** — a log-scaled look at your `conversation-log.md`,
  `user-memory.md`, and the `opencode.db` database vs. a bounded budget
  (never more than `0.5%` of your free disk space)
- **DISK** — total / free / used space on your home filesystem

The panel refreshes quietly every `60s` while open, and closes when you click
outside the card.

<br>

## Installation details

The plugin also ships with an idempotent setup script that configures
**OpenCode persistence**, so the dashboard always has real data to show:

```sh
bash setup.sh
```

`setup.sh` will (only when missing, never overwrites):

1. create `~/.config/opencode/user-memory.md` **long-term memory template**,
2. create `~/.config/opencode/conversation-log.md` **timeline template**,
3. patch `~/.config/opencode/opencode.json` so OpenCode auto-loads
   `user-memory.md` as long-term instructions every session.

> **NOTE:** you only need this once — after that, your OpenCode memory files
> live on (and grow) silently in the background.

Afterwards, **restart opencode** (and `omarchy restart shell`) to apply.

<br>

## How the data is collected

Everything runs on your machine, no cloud involved:

- `collect.py` queries the local OpenCode SQLite database (`opencode.db`) in
  **read-only** mode to count `user` prompts and pull recent messages.
- It ranks topics with a lightweight unigram + bigram TF-style heuristic
  (stop-words & years filtered), keeps 60 days of daily counts, and persists
  them under
  `~/.local/state/omarchy/plugins/Wakanda4Ever/topics.json`.
- It measures your memory files and disk, then prints a single JSON payload to
  stdout for the QML panel to consume.

<br>

## Files

```
manifest.json          # plugin manifest (panel + bar-widget)
BarWidget.qml          # bar button that toggles the dashboard
Main.qml               # the dashboard panel (overlay window + card UI)
collect.py             # python collector that feeds the dashboard
setup.sh               # idempotent OpenCode persistence setup
templates/
  user-memory.md       # long-term memory template (auto-loaded by opencode)
  conversation-log.md  # timeline template (append-only session log)
```

<br>

## TODOs

- [ ] **Optimize** the opencode database (e.g. `VACUUM`, wal-checkpointing)
- [ ] **Create a graph** that shows the lifetime of prompt count per day,
      relative to each month of the current year

<br>

## License

MIT — see each file header. **Wakanda Forever 🫶🏼**