# $RABBIT — Deployment Guide

## What's Inside

```
deploy/
├── index.html        ← Landing page (main site)
├── rabbitrun.html     ← RabbitRun PvP game
├── radar.html         ← Rabbit Radar ecosystem dashboard
├── dao.html           ← Colony DAO governance
├── speedproof.html    ← Speed Proof benchmark
├── 404.html           ← Custom 404 page
├── logo.svg           ← $RABBIT logo (PFP, favicon, all platforms)
├── RabbitRun.sol      ← Smart contract (deploy separately)
├── vercel.json        ← Vercel deployment config
├── _headers           ← Netlify headers config
└── README.md          ← This file
```

All pages are self-contained HTML — no build step, no dependencies, no node_modules.

---

## Deploy in 2 Minutes

### Option A: Vercel (Recommended)

1. Go to [vercel.com](https://vercel.com) → Sign up (free)
2. Click "Add New Project" → "Upload"
3. Drag the entire `deploy/` folder
4. Done. Live at `your-project.vercel.app`

**Custom domain:**
- Go to Project Settings → Domains
- Add your domain (e.g., `rabbitonmega.com`)
- Update DNS: Add CNAME record pointing to `cname.vercel-dns.com`
- SSL is automatic

### Option B: Netlify

1. Go to [netlify.com](https://netlify.com) → Sign up (free)
2. Drag the `deploy/` folder onto the deploy area
3. Done. Live at `random-name.netlify.app`

**Custom domain:**
- Site Settings → Domain Management → Add domain
- Update DNS as instructed
- SSL is automatic

### Option C: Cloudflare Pages

1. Go to [pages.cloudflare.com](https://pages.cloudflare.com) → Sign up (free)
2. Create project → Direct Upload
3. Upload the `deploy/` folder
4. Done. Live at `your-project.pages.dev`

---

## After Deployment: Checklist

### 1. Update Social Links
In `index.html`, find these placeholder `href="#"` links and replace with real URLs:
- Twitter/X profile link (appears in nav, community section, footer)
- Telegram group link (appears in community section, footer)

Search for `href="#"` across all files to find every placeholder.

### 2. Add Contract Address
Once $RABBIT is deployed on SLVR:
- Update the SLVR buy links from `https://dex.slvr.fun/` to include the contract address
- Add contract address to the landing page (consider adding a copy-to-clipboard element)

### 3. Burrow Fund Wallet
- Create a multisig wallet on MegaETH
- Update the "Donate to The Burrow Fund" link in `index.html`

### 4. Smart Contract (RabbitRun.sol)
This deploys separately from the website:
1. Open [Remix IDE](https://remix.ethereum.org)
2. Import `RabbitRun.sol`
3. Install OpenZeppelin dependencies
4. Compile with Solidity 0.8.24+
5. Deploy to MegaETH with constructor args:
   - `_rabbitToken`: $RABBIT contract address
   - `_burrowFund`: Burrow Fund wallet address
6. **Get it audited before going live with real funds**

### 5. Platform Assets
Use `logo.svg` for:
- SLVR token image (upload during deployment)
- Twitter/X profile picture
- Telegram group avatar
- Discord server icon

---

## File Sizes

| File | Size | Notes |
|------|------|-------|
| index.html | ~37KB | Landing page, all CSS/JS inline |
| rabbitrun.html | ~25KB | Fully playable game |
| radar.html | ~25KB | Live-updating dashboard |
| dao.html | ~32KB | Governance with voting |
| speedproof.html | ~30KB | Benchmark with live data |
| logo.svg | ~1.4KB | Vector, scales to any size |

Total: ~152KB. No external assets except Google Fonts. Loads instantly.

---

## Navigation Structure

```
index.html (Landing)
  ├── rabbitrun.html ←→ radar.html ←→ dao.html ←→ speedproof.html
  │   (All utility pages have cross-nav to each other)
  └── External: dex.slvr.fun (Buy $RABBIT)
```

Every utility page has:
- "← Site" link back to landing
- Cross-nav tabs to all other utility apps
- Consistent branding (rabbit mark, palette, typography)

---

## Tech Notes

- **Zero build step** — all files are static HTML with inline CSS and JS
- **No frameworks** — vanilla JS, no React/Vue/Svelte
- **Fonts** — Google Fonts (Cormorant Garamond, Karla, IBM Plex Mono)
- **No images** — rabbit mark is inline SVG, grain is SVG filter
- **Simulated data** — all dashboards use JS-generated data. Connect to MegaETH RPC for real data
- **Mobile responsive** — all pages work on mobile (sidebars collapse, grids stack)

---

## What's Simulated vs What's Real

| Feature | Current State | To Make Real |
|---------|--------------|--------------|
| RabbitRun game | Playable with simulated opponent | Connect to RabbitRun.sol smart contract |
| Radar feed | Simulated events streaming | Connect to MegaETH RPC websocket |
| DAO voting | Click-to-vote UI works | Connect to governance smart contract |
| Speed Proof benchmark | Simulated timing | Send real $RABBIT tx and measure |
| Leaderboards | Static demo data | Read from smart contract events |
| Wallet connection | Simulated | Add ethers.js + MetaMask integration |
| Token prices | Simulated jitter | Connect to DEX price feed |

Each dashboard is production-ready UI that needs RPC/contract connections added.
