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

Then open <http://localhost:5173>. Vite forwards `/api` to the server.

## Other commands

```sh
npm test         # unit and component tests (Vitest)
npm run typecheck
npm run e2e      # end-to-end tests (Playwright); needs `npx playwright install chromium` once
npm run build    # builds the web app to dist/web and the server to dist/server
npm start        # runs the built server, which also serves dist/web (http://127.0.0.1:4517)
```

## Where things live

The database is the file `data/amethyst.db`, created on first run (from this folder). It holds the account, sessions, settings and notifications, and is never committed. Port, host and database path can be changed with `AMETHYST_PORT`, `AMETHYST_HOST` and `AMETHYST_DB`.

## Run it on this Mac only, for now

The server listens on `127.0.0.1` so only this computer can reach it. Do not expose it to a network yet: it has no HTTPS, and the sign-in protections assume a trusted machine.
