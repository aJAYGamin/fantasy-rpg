# Amethyst Dashboard

A local web dashboard for the Amethyst fantasy RPG: accounts and sign-in, a themed layout (light and dark), search, notifications, settings and the debug pages. Later it connects to the Godot game; for now the debug pages show "waiting for the game".

It is one npm package with three parts:

- `shared/` constants and types used by both sides
- `server/` a small Fastify server with a local SQLite database, reached only through `/api`
- `web/` the React app, built with Vite

## Run it

```sh
npm install
npm run dev      # starts the server (port 4517) and Vite together
```

Then open <http://localhost:5173>. Vite forwards `/api` to the server on port 4517, so leave `AMETHYST_PORT` unset with `npm run dev`.

The first visit asks you to create the owner account. Type your real security answers only into that form; they are stored as one-way hashes and are never written anywhere else.

## Build it and run the built app

```sh
npm run build    # builds the web app to dist/web and the server to dist/server
npm start        # runs the built server, which also serves dist/web (http://127.0.0.1:4517)
```

## Test it

```sh
npm run typecheck
npm test         # unit and component tests (Vitest)
```

The end-to-end tests drive the built app in Chromium (1440 × 900):

```sh
npx playwright install chromium   # once
npm run build && npm run e2e      # e2e tests what the last build made, so build first
```

`npm run e2e` starts its own servers, one per spec file (ports 4618 and 4619), each with an empty database in a fresh temporary folder that is removed afterwards. They run with `NODE_ENV=test` and `AMETHYST_LOCK_SECONDS=3`, so the sign-in and reset pauses last 3 seconds instead of 5 minutes; the server honours that setting only when `NODE_ENV` is `test`. A failed run leaves its traces in `test-results/`.

Before calling a stage done, walk through the play-test checklist in [docs/stage1-playtest.md](docs/stage1-playtest.md).

## Where things live

The database is the file `data/amethyst.db`, created on first run (from this folder). It holds the account, sessions, settings and notifications, and is never committed. These environment variables change the defaults:

| Variable | Default | What it does |
| --- | --- | --- |
| `AMETHYST_PORT` | `4517` | The server's port |
| `AMETHYST_HOST` | `127.0.0.1` | The address it listens on |
| `AMETHYST_DB` | `data/amethyst.db` | The database file |
| `AMETHYST_WEB_DIST` | `dist/web` with `npm start`, none in development | A built web app for the server to serve |
| `AMETHYST_SECURE_COOKIES` | off | `1` marks the sign-in cookie Secure (only for HTTPS) |

## Run it on this Mac only, for now

The server listens on `127.0.0.1` so only this computer can reach it. Do not expose it to a network yet: it has no HTTPS, and the sign-in protections assume a trusted machine.
