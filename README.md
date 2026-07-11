# wlt

Erlang/Cowboy/ErlyDTL web application.

## Quick start

```bash
# Install inotify-tools (Debian/Ubuntu — needed for hot-reload)
sudo apt install inotify-tools

# Fetch deps + compile
rebar3 as dev compile

# Run dev server with hot-reload
rebar3 as dev shell
```

Open http://localhost:8080

## Hot reload

Save any `.erl` or `.html` file — changes are live within ~150ms.

## Adding a route

1. Add to `src/wlt_app.erl`: `{"/things/:id", thing_handler, []}`
2. Create `src/thing_handler.erl`
3. Create `priv/templates/thing.html`

## Database

Migrations run automatically at startup. Add new ones in `src/wlt_db.erl`:

```erlang
{"20240201_002_create_things",
 "CREATE TABLE things (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT);"}
```

## Nginx

- Dev:  `nginx/dev.conf`
- Prod: `nginx/prod.conf` (update domain + paths)

## Deploy

```bash
rebar3 release
sudo cp scripts/wlt.service /etc/systemd/system/
sudo systemctl enable --now wlt
```
# wlt
# wlt
