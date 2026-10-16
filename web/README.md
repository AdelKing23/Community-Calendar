# Coast Calendar Web

Public web access for Coast Calendar. This gives Android users and desktop
visitors a simple read-only view of approved local listings and approved member
hosts from the same Supabase backend as the iOS app.

## Prerequisites

- Node.js `>=22.13.0`

## Quick Start

```bash
pnpm install
pnpm run dev
pnpm run build
```

## Shape

- edit site code under `app/`
- static assets live under `public/`
- `.openai/hosting.json` stores the Sites project metadata
- Supabase access is public read-only through RLS and the publishable anon key

## Environment

Set these in Sites production runtime variables before deploying:

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`

The app has safe launch fallbacks for the current Supabase project, but
production deploys should still set the variables in Sites so future backend
changes do not require code edits.

## Useful Commands

- `pnpm run dev`: start local development
- `pnpm run build`: verify the vinext build output
- `pnpm test`: build verification alias
