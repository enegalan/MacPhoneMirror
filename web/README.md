# MacPhoneMirror Official Website

## Develop

```bash
npm install
npm run dev
```

Open the URL printed in the terminal (usually `http://localhost:4321`).

## Build

```bash
npm run build
npm run preview
```

Output goes to `dist/`.

## Deploy on Vercel

1. Import the GitHub repo in [Vercel](https://vercel.com).
2. Set **Root Directory** to `web`.
3. Framework preset: Astro (build `npm run build`, output `dist`).
4. Deploy.
