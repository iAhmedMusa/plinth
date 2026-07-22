# Frontend

Next.js 16 user profile management UI with React 19, TypeScript, and Tailwind CSS. Part of the `plinth` monorepo — see the root [README.md](../README.md) for full-stack setup.

## Quick start

```bash
npm install
npm run dev
```

Open http://localhost:3000. API calls to `/api/*` will 404 without the backend running — use Docker Compose from the repo root for the full stack.

## Project structure

```
frontend/src/
  app/           # Next.js App Router pages
  components/    # React components (shadcn/ui)
  lib/           # API client, utilities
  types/         # TypeScript type definitions
```

## Environment variables

| Variable | Description | Default |
|---|---|---|
| `BACKEND_URL` | Backend base URL for the Next.js server-side rewrite | none — required at build time |
| `PORT` | Server port | `3000` |

`BACKEND_URL` is a build-time arg — it's baked into the image when `next build` runs.

## Docker

```bash
docker build --build-arg BACKEND_URL=http://backend:8080 -t frontend .
docker run -p 3000:3000 frontend
```

Or use Docker Compose from the repo root — see [README.md](../README.md).

## Scripts

- `npm run dev` — development server (Turbopack)
- `npm run build` — production build
- `npm run start` — production server
- `npm run lint` — ESLint
