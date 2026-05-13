# WebUI Modern Redesign Research & Implementation Plan

> **Project:** `theontho/gui-for-cli` — WebUI layer  
> **Prepared from:** 8 focused research subagent dispatches covering current implementation, design inspiration, responsive/mobile strategy, accessibility, command palette feasibility, and implementation sequencing  
> **Status:** Research + planning only — no source files were modified

---

## Executive Summary

The GUI for CLI WebUI is a ~971-line vanilla TypeScript + single-CSS-file single-page application served by a plain Node.js HTTP server. It renders via full `innerHTML` string replacement with no framework, no bundler, and no CSS preprocessor. The visual layer is entirely contained in `platform/typescript/web/styles.css` and HTML template functions in `platform/typescript/web/src/client/view.ts`.

The UI is functional but visually dated: it uses a single 900 px breakpoint, has no `prefers-reduced-motion` support, delegates brand colour entirely to the OS (`AccentColor`), lacks focus rings on most interactive elements, and has several WCAG 2.2 accessibility failures. The architecture is well-suited to a **CSS-token-first redesign** because all class names are semantic and factored; the first five redesign milestones can be done primarily in `styles.css`.

The recommended design direction is a **"Precision Shell"** aesthetic inspired primarily by Vercel Geist, with interaction and accessibility patterns borrowed from shadcn/ui, Linear, Warp, GitHub Primer, and Framer Motion. The redesign is sequenced into 8 milestones, 5 of which are pure CSS with minimal risk to the TypeScript build or test suite.

---

## Query Classification

| Dimension | Classification |
|---|---|
| **Type** | Design Research + Implementation Planning |
| **Scope** | Full WebUI visual layer — `platform/typescript/web/styles.css`, `platform/typescript/web/index.html`, `platform/typescript/web/src/client/` |
| **Risk** | Low-Medium; CSS-only changes are low risk, TypeScript template changes are moderate risk |
| **Dependencies** | No new npm packages required for Milestones 1-7; Geist font is optional additive-only |
| **Test surface** | CSS changes do not affect `make test-webui`; TS template changes require `npm --prefix platform/typescript test` |
| **Deferred** | Command palette implementation, framework migration, page-transition animations, bundler introduction |

---

## Current WebUI Findings

### Architecture Overview

| File | Role | Size |
|---|---|---|
| `platform/typescript/web/styles.css` | All visual rules — single source of truth for design | ~971 lines |
| `platform/typescript/web/index.html` | Shell HTML; loads Bootstrap Icons from jsDelivr CDN | 21 lines |
| `platform/typescript/web/src/client/app.ts` | Root render loop; full `innerHTML` replacement on every state change | 107 lines |
| `platform/typescript/web/src/client/view.ts` | HTML template string functions for nav, cards, forms, tables, modals | 426 lines |
| `platform/typescript/web/src/client/terminal.ts` | Terminal pane templates + tab/status management | 124 lines |
| `platform/typescript/web/src/client/events.ts` | DOM event binding, action handling, splitter drag | 210 lines |
| `platform/typescript/web/src/client/model.ts` | Shared helpers: `renderIcon`, `renderTooltip`, `renderLoadingBox` | 156 lines |
| `platform/typescript/web/src/client/state.ts` | `WebUIState` shape + localStorage hydration | 36 lines |
| `platform/typescript/web/src/client/icons.ts` | `emojiIconMap`, `bootstrapIconMap` | 90 lines |
| `platform/typescript/tests/rendering.test.mjs` | Node test runner — covers shared rendering/localisation logic, not CSS | — |

The render loop in `app.ts:50-76`[^1] does a **full synchronous `innerHTML` replacement**. There is no virtual DOM, diffing, or batching. This is the key architectural constraint: any feature that requires a live input, such as a command palette search field, **must not** call `scheduleRender()` on each keystroke or it will destroy its own DOM node.

### CSS Design Token Inventory

The current `:root` block at `platform/typescript/web/styles.css:1-38`[^2] defines:

**Tokens that exist:**

- `--background`, `--sidebar`, `--panel`, `--panel-subtle`, `--panel-raised`
- `--text`, `--muted`, `--border`, `--separator`, `--accent`, `--accent-soft`
- `--danger`, `--success`, `--warning`
- `--terminal-bg`, `--control-height: 30px`

**Tokens that are hardcoded everywhere:**

- Border radius: `7px` (button[^4]), `6px` (input[^5]), `8px` (card[^6], table-wrap[^7]), `12px` (modal[^8]), `999px` (pill[^9])
- Shadows: `0 12px 36px rgb(0 0 0 / 20%)` (tooltip[^10]), `0 24px 80px rgb(0 0 0 / 30%)` (modal[^11])
- Transitions: no `transition:` properties in the file[^12]
- Font sizes: `0.86rem`, `0.82rem`, `0.72rem` are hardcoded in multiple places

### Identified Pain Points

| Issue | Location | Severity |
|---|---|---|
| `--accent: AccentColor` gives no brand control | `styles.css:20`[^13] | Medium |
| `body { min-width: 760px }` breaks mobile | `styles.css:46`[^14] | High |
| `minmax(520px, 1fr)` content column can force overflow | `styles.css:77`[^15] | High |
| Only one breakpoint at 900 px | `styles.css:857`[^16] | High |
| No `prefers-reduced-motion` | absent from file[^12] | High |
| No `prefers-reduced-transparency` | absent from file | Medium |
| No `viewport-fit=cover` + no safe-area insets | `index.html:5`[^17] | High |
| `100vh` used in multiple full-height areas | `styles.css:79,87,204,849,944`[^18] | High |
| No `:focus-visible` on `button`, `input`, `select`, `.nav-item` | `styles.css:57-74`[^19] | High |
| Button hover `brightness(0.98)` is nearly invisible | `styles.css:67`[^20] | Medium |
| `.terminal-tab-close` touch target: 18 px | `styles.css:711-723`[^21] | High |
| `.tooltip` touch target: 18 px | `styles.css:562-575`[^22] | High |
| Missing `aria-current="page"` on active nav | `view.ts:55`[^23] | High |
| No focus trap in confirmation modal | `view.ts:409`[^24] | High |
| No skip link | `index.html` | Medium |
| `window.prompt()` for path picking | `events.ts:51-58`, `events.ts:89-94`[^25] | Medium |
| `color-mix()` has no fallback for older browsers | `styles.css:4-17`[^2] | Medium |
| Zero-width third column in `.form-row` | `styles.css:329`[^26] | Low |
| Tooltip `role="button"` anti-pattern on `<span>` | `model.ts:96`[^27] | Medium |

### Build & Validation Commands

```bash
# Type-check only
npm --prefix platform/typescript run check

# Full build + test suite
npm --prefix platform/typescript test
# OR:
make test-webui

# Build only
npm --prefix platform/typescript run build

# Live dev server with WGSExtract bundle
make webui BUNDLE=examples/WGSExtract PORT=8787

# Accessibility smoke tests
make ax-smoke
make ax-smoke-ios
```

CSS-only changes should still be validated visually with the live dev server even though they do not affect the Node test suite.

---

## Inspiration Research

### Comparative Overview

| Source | Visual Language | Audience Fit | License | Practical Role |
|---|---|---|---|---|
| **Vercel Geist** | Swiss minimalism, monochrome, precision | Excellent for dev tools | Font: OFL; components proprietary | Lead inspiration |
| **shadcn/ui** | Neutral minimal, composable, semantic tokens | Excellent | MIT | Token naming + structure |
| **Linear** | Dense, dark-default, keyboard-first | Strong | Proprietary | UX patterns |
| **Warp** | Modern dark terminal, block-based output | Strong for CLI users | UI crates MIT; core AGPL | Terminal design inspiration |
| **GitHub Primer** | Dense, functional, accessibility-first | Strong | MIT | Accessibility + typography |
| **Framer Motion** | Physics-based animation | Optional | MIT | Deferred motion ideas |
| **Raycast** | macOS native, command-first | Good but platform-specific | Proprietary | ActionPanel concept |
| **Arc Browser** | Spatial, proprietary chrome | Weak fit | Proprietary | Skip |

### What to Take from Each Source

**From Vercel Geist**[^28]:

- `Geist Sans` and `Geist Mono` fonts, which are licensed under SIL OFL 1.1[^29]
- A 10-step neutral gray scale model: Background 1/2 -> Component 1-3 -> Border 4-6 -> Text 9-10[^30]
- Swiss typographic precision, high contrast, fine 1 px borders, and grid-line structure[^30]

**From shadcn/ui**[^31]:

- Semantic token naming: `background/foreground` pairs, `--muted/--muted-foreground`, `--sidebar-*`
- Radius scale from a single `--radius` base: `--radius-sm`, `--radius-md`, `--radius-lg`, `--radius-xl`
- Sidebar composition model: `SidebarHeader -> SidebarContent -> SidebarGroup -> SidebarMenu`
- Command palette structure and visual language[^32]

**From Linear**[^33]:

- Dark-default product feel for developer workflows
- Keyboard shortcut badges (`Cmd/Ctrl`, `Enter`, etc.) beside action buttons[^34]
- Ultra-compact sidebar density: 30-32 px nav items and small uppercase group labels

**From Warp**[^35]:

- Block-based terminal output: each command invocation can become a `.terminal-block` with a status-coloured left border
- Colour-coded status bands that extend the existing terminal tab status classes[^36]
- Copy-on-select and terminal-friendly monospace styling

**From GitHub Primer**[^37]:

- Typography scale concepts such as caption, body, title, and code text roles[^38]
- Warm `dark-dimmed` theme ideas for long sessions
- Motion duration/easing token concepts[^39]
- Accessibility and high-contrast theme patterns

**From Framer Motion**[^40]:

- Post-redesign ideas only: `AnimatePresence`, spring physics, and CSS variable animation for panel open/close. Avoid adding this dependency in the first redesign pass.

### What NOT to Copy

| Source | What to avoid | Reason |
|---|---|---|
| Vercel Geist | React components on vercel.com | Not open-sourced |
| Linear, Raycast | Any UI code | Proprietary; emulate patterns only |
| Raycast | macOS vibrancy/blur and native chrome | Unavailable in standard web browsers |
| Warp | Any non-MIT code | License incompatibility risk |
| Arc Browser | Browser chrome design | Proprietary and poor fit |
| shadcn/ui | React component code verbatim | This project is vanilla TypeScript |

---

## Recommended Design Direction

### Concept: "Precision Shell"

A developer-centric, dark-first precision UI drawing from Vercel Geist's Swiss minimalism and Linear's keyboard-first density. The look should be crisp and layered, not heavy: barely-there elevation, explicit semantic tokens, strong focus states, dense but readable controls, and a terminal panel that feels intentionally distinct from the rest of the app.

### Visual Principles

1. **Dark-first, light-equal** — full explicit token sets for both modes; avoid relying entirely on `Canvas` and `CanvasText`.
2. **Three surface layers** — `--bg` -> `--surface-0` -> `--surface-1`; plus a permanently-dark `--terminal-bg`.
3. **Precision borders** — 1 px subtle lines with different alpha per mode.
4. **Minimal gradients** — only primary action buttons keep a micro-gradient.
5. **Explicit brand blue** — `#2563eb` in light mode and `#3b82f6` in dark mode replace OS `AccentColor` for consistent identity.
6. **Four-step radius system** — `--radius-sm: 4px`, `--radius-md: 6px`, `--radius-lg: 10px`, `--radius-xl: 14px`.
7. **Motion layer** — short transitions only on interactive elements, guarded by `prefers-reduced-motion`.

### Proposed Token System

Replace `platform/typescript/web/styles.css:1-38`[^2] with an expanded token block in this direction:

```css
:root {
  color-scheme: light dark;

  --bg:              #fafafa;
  --surface-0:       #ffffff;
  --surface-1:       #f4f4f5;
  --surface-2:       #e4e4e7;
  --sidebar-bg:      #f0f0f1;
  --terminal-bg:     #18181b;
  --terminal-text:   #e4e4e7;

  --text-primary:    #09090b;
  --text-secondary:  #52525b;
  --text-tertiary:   #a1a1aa;

  --accent:          #2563eb;
  --accent-hover:    #1d4ed8;
  --accent-soft:     #dbeafe;
  --accent-text:     #1e40af;

  --danger:          #dc2626;
  --danger-soft:     #fee2e2;
  --success:         #16a34a;
  --success-soft:    #dcfce7;
  --warning:         #d97706;
  --warning-soft:    #fef3c7;

  --border:          rgba(0, 0, 0, 0.09);
  --border-strong:   rgba(0, 0, 0, 0.16);
  --border-focus:    var(--accent);

  --radius-sm:       4px;
  --radius-md:       6px;
  --radius-lg:       10px;
  --radius-xl:       14px;
  --radius-full:     9999px;

  --shadow-focus:    0 0 0 3px rgba(37, 99, 235, 0.25);
  --shadow-card:     0 1px 3px rgba(0,0,0,0.06), 0 1px 2px rgba(0,0,0,0.04);
  --shadow-modal:    0 16px 64px rgba(0,0,0,0.18), 0 4px 16px rgba(0,0,0,0.08);
  --shadow-tooltip:  0 4px 16px rgba(0,0,0,0.12), 0 1px 4px rgba(0,0,0,0.06);

  --control-height:  32px;
  --sidebar-default: 220px;

  --font-sans:       "Geist", "Inter", ui-sans-serif, system-ui, -apple-system, sans-serif;
  --font-mono:       "Geist Mono", ui-monospace, "Cascadia Code", SFMono-Regular, Menlo, monospace;
  --font-size-xs:    0.75rem;
  --font-size-sm:    0.8125rem;
  --font-size-base:  0.875rem;
  --font-size-md:    0.9375rem;
  --font-size-xl:    1.25rem;
  --font-size-2xl:   1.75rem;

  --ease-out:        cubic-bezier(0.16, 1, 0.3, 1);
  --duration-fast:   100ms;
  --duration-base:   150ms;
}

@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --bg:            #0a0a0b;
    --surface-0:     #111113;
    --surface-1:     #18181b;
    --surface-2:     #27272a;
    --sidebar-bg:    #0f0f11;
    --terminal-bg:   #0a0a0b;
    --text-primary:  #fafafa;
    --text-secondary:#a1a1aa;
    --text-tertiary: #52525b;
    --accent:        #3b82f6;
    --accent-hover:  #60a5fa;
    --accent-soft:   rgba(59,130,246,0.12);
    --accent-text:   #93c5fd;
    --danger:        #f87171;
    --danger-soft:   rgba(248,113,113,0.12);
    --success:       #4ade80;
    --success-soft:  rgba(74,222,128,0.12);
    --warning:       #fbbf24;
    --warning-soft:  rgba(251,191,36,0.12);
    --border:        rgba(255,255,255,0.08);
    --border-strong: rgba(255,255,255,0.12);
    --shadow-focus:  0 0 0 3px rgba(59,130,246,0.35);
    --shadow-card:   0 1px 3px rgba(0,0,0,0.3), 0 1px 2px rgba(0,0,0,0.2);
    --shadow-modal:  0 16px 64px rgba(0,0,0,0.6), 0 4px 16px rgba(0,0,0,0.3);
  }
}
```

---

## Cross-Platform Responsive Strategy

### Current State

One breakpoint at `max-width: 900px`[^16] handles all non-desktop cases. Body has `min-width: 760px`[^14]. The desktop grid uses `minmax(520px, 1fr)` for the content column[^15]. Multiple `100vh` rules risk iOS Safari layout issues[^18]. No safe-area insets or `@media (pointer: coarse)` adaptations exist.

### Recommended Breakpoint System

| Name | Range | Layout |
|---|---|---|
| **xs** | 0-599 px | Single column; sidebar as sticky top chip bar; safe-area padding |
| **sm** | 600-767 px | Same as xs; wider chips; terminal toggle as floating action button |
| **md** | 768-1023 px | 56 px icon-rail sidebar fixed left; full content column |
| **lg** | 1024-1279 px | Full sidebar + resizable splitter; current desktop layout |
| **xl** | >= 1280 px | Same as lg; wider content and max sidebar width |

### Key CSS/HTML Fixes

**Viewport meta** (`platform/typescript/web/index.html:5`[^17]):

```html
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
```

**Replace `100vh` with `100dvh` fallback pattern**:

```css
.app-shell {
  min-height: 100vh;
  min-height: 100dvh;
}
```

Apply this pattern to the app shell, sidebar, detail shell, and loading screen rules that currently use `100vh`[^18]. `dvh` is supported by modern Chrome, Firefox, and Safari versions[^41].

**Safe-area insets**:

```css
.sidebar {
  padding-bottom: env(safe-area-inset-bottom, 0px);
}

.terminal-toggle {
  bottom: max(12px, calc(12px + env(safe-area-inset-bottom, 0px)));
  right: max(16px, calc(16px + env(safe-area-inset-right, 0px)));
}

.page-panel article {
  padding-left: max(24px, calc(24px + env(safe-area-inset-left, 0px)));
  padding-right: max(24px, calc(24px + env(safe-area-inset-right, 0px)));
}
```

**Touch targets**:

```css
@media (pointer: coarse) {
  :root { --control-height: 44px; }
  .nav-item { min-height: 44px; }
  .terminal-tab-close,
  .terminal-toggle {
    min-height: 44px;
    min-width: 44px;
  }
  .tooltip {
    min-height: 36px;
    min-width: 36px;
  }
}
```

**Eliminate tap delay and improve touch feedback**:

```css
button, a, [role="button"], input, select, label {
  touch-action: manipulation;
}

button:active:not(:disabled) {
  filter: brightness(0.93);
}
```

**Prevent iOS input zoom**:

```css
@media (pointer: coarse) {
  input[type="text"],
  select {
    font-size: max(16px, 1em);
  }
}
```

### Browser Support Matrix

| Feature | Chrome/Edge | Firefox | Safari/iOS | Notes |
|---|---|---|---|---|
| `color-mix(in srgb)` | 111+ | 113+ | 16.2+ | Add rgba fallbacks[^52] |
| `100dvh` | 108+ | 101+ | 15.4+ | Keep `100vh` fallback[^41] |
| `env(safe-area-inset-*)` | Supported | Supported | Supported | Needs `viewport-fit=cover` |
| `@media (pointer: coarse)` | Supported | Supported | Supported | Use for touch target scaling |
| `@media (prefers-reduced-motion)` | Supported | Supported | Supported | Required guard[^43] |
| `@media (prefers-reduced-transparency)` | Not broad | Not broad | Safari 17+ | Progressive enhancement[^51] |
| Native `<dialog>` | 98+ | 98+ | 15.4+ | Defer migration |

---

## Accessibility Plan

### WCAG 2.2 Failures to Fix

1. **Touch target size — WCAG 2.5.8 AA**[^42]  
   `.terminal-tab-close` is 18x18 px[^21] and `.tooltip` is 18x18 px[^22], both below the 24x24 px WCAG minimum. Use at least 24 px visually and 44 px in coarse pointer contexts.

2. **Focus visibility — WCAG 2.4.11 AA**[^43]  
   Buttons, inputs, selects, and nav items lack consistent `:focus-visible` styling[^19].

3. **Name, role, value — WCAG 4.1.2**[^44]  
   Active nav items use only CSS class `active` with no `aria-current="page"`[^23].

4. **Modal focus trap — ARIA APG Dialog Pattern**[^45]  
   The confirmation modal has `role="dialog" aria-modal="true"`[^24], but event code lacks Tab containment and Escape-to-close handling.

5. **Animations without reduced-motion guard**  
   Spinner animation runs unconditionally[^46]. Add `@media (prefers-reduced-motion: reduce)`.

### Important Improvements

- Add a skip link before `<div id="app">` and add `id="main-content" tabindex="-1"` on the rendered `<main>`[^47].
- Add a polite live region to announce page navigation, because the app silently replaces `innerHTML` on navigation[^48].
- Add `aria-label` for icon-only action buttons; `title` alone is not reliable[^49].
- Link `infoGrid` labels to their grids with `aria-labelledby`[^50].
- Add reduced-transparency fallbacks for `color-mix(... transparent)` tokens[^51].
- Add `color-mix()` fallback values for older major browser versions[^52].
- Add forced-colors styles for Windows High Contrast:

```css
@media (forced-colors: active) {
  .spinner,
  .mini-spinner {
    border-color: ButtonText;
    border-top-color: Highlight;
  }
  .pill {
    outline: 1px solid ButtonText;
  }
  .nav-item.active {
    outline: 2px solid Highlight;
  }
}
```

---

## Implementation Plan

### Dependency Order

```text
Milestone 1 (Design Token Expansion)
  -> Milestone 2 (Focus Rings + Transitions)
      -> Milestone 3 (App Shell + Nav Polish)
          -> Milestone 4 (Card + Table + Button Lift)
              -> Milestone 5 (Terminal Visual Distinction)
                  -> Milestone 6 (Responsive Hardening)
                      -> Milestone 7 (Accessibility Hardening)
                          -> Milestone 8 (Optional Micro-interactions)
```

### Milestone 1 — Design Token Expansion

**Files:** `platform/typescript/web/styles.css:1-38`

Replace the current token block with an expanded token system:

- Explicit light and dark surfaces
- Radius scale
- Shadow scale
- Typography scale
- Motion scale
- Font stacks
- `rgba()` fallbacks before each `color-mix()` token

Then sweep and replace hardcoded radii/shadows with tokens:

- `styles.css:59` -> `var(--radius-md)`[^4]
- `styles.css:298` -> `var(--radius-md)`[^6]
- `styles.css:419` -> `var(--radius-md)`[^7]
- `styles.css:586` -> `var(--shadow-tooltip)`[^10]
- `styles.css:792` -> `var(--shadow-modal)`[^11]
- `styles.css:602` -> `var(--radius-full)`[^9]

**Acceptance:** `npm --prefix platform/typescript run check` passes; `make test-webui` passes; visual diff is intentionally minimal.

### Milestone 2 — Focus Rings + Transition Layer

**Files:** `platform/typescript/web/styles.css`

Add:

```css
button:focus-visible,
input:focus-visible,
select:focus-visible {
  outline: 2px solid var(--accent);
  outline-offset: 2px;
}
```

Add transitions to buttons, inputs, selects, nav items, and splitters. Add reduced-motion guard:

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
  }
  .spinner,
  .mini-spinner {
    animation: none;
  }
}
```

Fix the `.form-row` grid:

```css
grid-template-columns: 190px minmax(220px, 1fr);
```

**Acceptance:** Keyboard tabbing shows visible focus on all interactive elements; `make ax-smoke` has no new failures.

### Milestone 3 — App Shell & Navigation Polish

**Files:** `platform/typescript/web/styles.css`

- Convert the bundle header from a large centered icon to a compact horizontal lockup.
- Add `.nav-item:hover:not(.active)` state and transition.
- Keep nav items dense on desktop but enlarge them in `pointer: coarse` contexts.
- Change the visible sidebar resizer from an 8 px dead zone to a 1 px visual line with an expanded `::before` hit area[^53].
- Use `var(--sidebar-bg)` explicitly.

**Acceptance:** Navigation feels modern and responsive; resizer is visually precise but still easy to hit.

### Milestone 4 — Card, Table & Action Button Lift

**Files:** `platform/typescript/web/styles.css`

- Add `box-shadow: var(--shadow-card)` to `.card`[^6].
- Add subtle dark-mode card highlight:

```css
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) .card {
    background: linear-gradient(160deg, rgba(255,255,255,0.03) 0%, var(--surface-0) 100%);
  }
}
```

- Add clearer table header separation.
- Add per-role action button hover styles:

```css
.action-button.primary:hover:not(:disabled) { filter: brightness(1.06); }
.action-button.danger:hover:not(:disabled) { filter: brightness(1.05); }
```

**Acceptance:** Cards, tables, and action rows gain depth without adding clutter.

### Milestone 5 — Terminal Visual Distinction

**Files:** `platform/typescript/web/styles.css`

- Make terminal background darker and stable across themes.
- Refine terminal header and tab active state.
- Use `var(--font-mono)` for terminal output[^54].
- Add `overscroll-behavior: contain` to `.terminal-log`.
- Add optional WebKit scrollbar styling.

**Acceptance:** Terminal is visually distinct from content panel; active tab is obvious in both themes.

### Milestone 6 — Responsive Hardening

**Files:** `platform/typescript/web/styles.css`, `platform/typescript/web/index.html`

1. Add `viewport-fit=cover` to `index.html:5`[^17].
2. Add safe-area padding rules.
3. Replace all `100vh` rules with `100vh` + `100dvh` fallback[^18].
4. Remove `body { min-width: 760px }` and replace with `min-width: 320px` or no hard floor[^14].
5. Add `@media (pointer: coarse)` touch target rules.
6. Add `touch-action: manipulation`.
7. Add `button:active` feedback.
8. Add `@media (max-width: 480px)` for phones.
9. Add `color-mix()` fallbacks.

**Acceptance:** No horizontal scroll at 375 px viewport width; primary content readable at iPhone SE size; tablet portrait layout is usable.

### Milestone 7 — Accessibility Hardening

**Files:** `platform/typescript/web/styles.css`, `platform/typescript/web/index.html`, `platform/typescript/web/src/client/view.ts`, `platform/typescript/web/src/client/events.ts`, `platform/typescript/web/src/client/model.ts`

- `view.ts:55` — add `aria-current="page"` to active nav item[^23].
- `view.ts:202-210` — add `id` on label div and `aria-labelledby` on `.info-grid`[^50].
- `view.ts:331-337` — add `aria-label` for `iconOnly` action buttons[^49].
- `events.ts` — add modal focus trap and Escape-to-close handling[^45].
- `model.ts:96` — replace or supplement tooltip `role="button"` with keyboard activation[^27].
- Add skip link in `index.html` and `id="main-content"` to `<main>`.
- Add a polite live region and update it after page navigation.

**Acceptance:** `make ax-smoke` passes; Tab order is usable end-to-end; forced-colors mode remains legible.

### Milestone 8 — Optional Micro-interactions

**Files:** `platform/typescript/web/styles.css`

Add CSS-only modal entrance animation, guarded by `prefers-reduced-motion`:

```css
@keyframes modal-in {
  from { opacity: 0; transform: scale(0.96) translateY(8px); }
  to { opacity: 1; transform: scale(1) translateY(0); }
}

.confirmation-modal {
  animation: modal-in var(--duration-base) var(--ease-out);
}

@media (prefers-reduced-motion: reduce) {
  .confirmation-modal { animation: none; }
}
```

Add a subtle modal backdrop blur only if contrast remains acceptable:

```css
.modal-backdrop {
  backdrop-filter: blur(4px);
  -webkit-backdrop-filter: blur(4px);
}
```

---

## Command Palette — Architecture Notes

A command palette (`Cmd/Ctrl+K`) is architecturally feasible but should be deferred to Phase 2. The visual redesign should not introduce any patterns that prevent it.

The critical constraint is the app's full `innerHTML` replacement render loop[^1]. A palette search input must not call `scheduleRender()` on each keystroke. The confirmation dialog already demonstrates the correct approach: the confirmation input updates the button state imperatively without rerendering the shell[^55].

Recommended palette model:

- `state.commandPaletteOpen: boolean` only; do not store the query in global state.
- Search query lives in the input DOM node.
- Filter list items imperatively inside the palette DOM.
- Use ARIA Combobox + Listbox: input with `role="combobox"`, list with `role="listbox"`, options with `role="option"`, and keyboard focus via `aria-activedescendant`[^56].
- Build actions from section-level actions in `state.manifest.pages[].sections[].actions[]`.
- Exclude row actions until there is a selected row context.

References: ARIA APG Combobox Pattern[^56], shadcn/ui Command component[^32], cmdk architecture[^57].

---

## What to Defer

| Item | Why defer | Risk if done now |
|---|---|---|
| **Command palette** | Behavioral-layer work that needs deliberate event architecture | Tight coupling to render loop |
| **Self-hosting Bootstrap Icons** | Requires asset pipeline or package addition | Unrelated dependency/tooling change |
| **Page transition animations** | Requires JS render-loop changes | High risk with `innerHTML` replacement |
| **Tooltip full rewrite** | Needs extra keyboard/touch testing | Moderate TypeScript scope |
| **Virtual terminal scrolling** | Separate performance feature | Not visual redesign |
| **Bundle-manifest theming** | Requires Swift-side bundle format changes | Out of WebUI scope |
| **CSS Modules/Sass/PostCSS** | Tooling stack change | Breaks no-bundler constraint |
| **Framer Motion integration** | Adds dependency | CSS-only motion is enough first |
| **Warp-style terminal blocks** | Requires `terminal.ts` data/template changes | Separate feature |
| **`window.prompt()` -> custom dialog** | Medium TS scope | Functional replacement, not visual polish |
| **Native `<dialog>` migration** | Browser support is acceptable but migration is separate | Focus/scroll behavior changes |

---

## Validation Plan

### At Each Milestone

1. `npm --prefix platform/typescript run check`
2. `make test-webui`
3. `make webui BUNDLE=examples/WGSExtract PORT=8787`
4. Manual visual inspection at 375 px, 768 px, 1024 px, and 1440 px

### At Accessibility Milestones

5. `make ax-smoke`
6. `make ax-smoke-ios`
7. Manual keyboard-only navigation: Tab, Shift+Tab, Enter, Space, Escape

### At Responsive Milestone

8. iPhone SE viewport: 375 x 667
9. iPad portrait viewport: 768 x 1024
10. iPhone 14/15 notch/safe-area simulation

### Regression Criteria

- No horizontal scroll at any viewport >= 320 px.
- All tokens resolve; no computed `initial` values.
- Existing resizer focus rings do not regress[^58][^59].
- `make test-webui` remains green.

---

## Confidence Assessment

| Research Area | Confidence | Evidence Quality |
|---|---|---|
| Current CSS audit | High | Direct file reads of `styles.css` and subagent line citations |
| Current TS architecture | High | Direct citations in `app.ts`, `events.ts`, `view.ts`, `state.ts` |
| WCAG 2.2 issue identification | High | Mapped to WCAG and ARIA APG references |
| iOS/mobile platform issues | High | Confirmed `100vh`, missing viewport fit, and safe-area gaps |
| Design inspiration analysis | High | Public design-system docs and product pages |
| Proposed token palette | Medium-High | Derived from leading design systems; still needs visual validation |
| Milestone sequencing | High | Based on CSS-only vs TS-required classification |
| Command palette architecture | High | Based on current render loop and existing imperative modal input pattern |
| Browser support matrix | High | Based on MDN/caniuse-supported feature baselines |
| Font licensing | High | Confirmed via Geist font repository license |

**Known gaps:**

- No visual test infrastructure exists, so acceptance criteria include manual inspection.
- `make ax-smoke` requires the macOS dev app to be running with accessibility permission.
- The exact dark palette should be validated in the live server before implementation is considered finished.
- The deferred command palette has not been type-checked against final manifest types.

---

## Footnotes

[^1]: `platform/typescript/web/src/client/app.ts:50-76` — full synchronous `innerHTML` replacement render loop; `bindEvents(bootstrap)` re-runs after every render.
[^2]: `platform/typescript/web/styles.css:1-38` — complete CSS custom property `:root` block and current token definitions.
[^3]: `platform/typescript/web/styles.css:7` — `--panel-raised` is defined as `color-mix(in srgb, CanvasText 3%, Canvas)`; subagent audit found no references elsewhere in the file.
[^4]: `platform/typescript/web/styles.css:59` — `button { border-radius: 7px }`.
[^5]: `platform/typescript/web/styles.css:357` — `input[type="text"] { border-radius: 6px }`.
[^6]: `platform/typescript/web/styles.css:296-301` — `.card` has border, radius, background, padding, and no shadow.
[^7]: `platform/typescript/web/styles.css:419` — `.table-wrap { border-radius: 8px }`.
[^8]: `platform/typescript/web/styles.css:789` — `.confirmation-modal { border-radius: 12px }`.
[^9]: `platform/typescript/web/styles.css:602` — `.pill { border-radius: 999px }`.
[^10]: `platform/typescript/web/styles.css:586` — `.floating-tooltip { box-shadow: 0 12px 36px rgb(0 0 0 / 20%) }`.
[^11]: `platform/typescript/web/styles.css:792` — `.confirmation-modal { box-shadow: 0 24px 80px rgb(0 0 0 / 30%) }`.
[^12]: `platform/typescript/web/styles.css` — subagent audit reported zero `transition:` properties and no `prefers-reduced-motion` block.
[^13]: `platform/typescript/web/styles.css:20` — `--accent: AccentColor`.
[^14]: `platform/typescript/web/styles.css:46` — `body { min-width: 760px }`.
[^15]: `platform/typescript/web/styles.css:77` — `.app-shell { grid-template-columns: var(--sidebar-width, 220px) 8px minmax(520px, 1fr) }`.
[^16]: `platform/typescript/web/styles.css:857-970` — the only responsive breakpoint is `@media (max-width: 900px)`.
[^17]: `platform/typescript/web/index.html:5` — viewport meta lacks `viewport-fit=cover`.
[^18]: `platform/typescript/web/styles.css:79,87,204,849,944` — `100vh` uses in app shell, sidebar, detail shell, loading screen, and mobile detail shell.
[^19]: `platform/typescript/web/styles.css:57-74` — base button block; no general `:focus-visible` rule.
[^20]: `platform/typescript/web/styles.css:67-69` — `button:hover:not(:disabled) { filter: brightness(0.98) }`.
[^21]: `platform/typescript/web/styles.css:711-723` — `.terminal-tab-close` has 18 px dimensions; compare WCAG 2.5.8 target-size minimum: https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html.
[^22]: `platform/typescript/web/styles.css:562-575` — `.tooltip` has 18 px dimensions.
[^23]: `platform/typescript/web/src/client/view.ts:55` — nav item active state uses class only; no `aria-current`.
[^24]: `platform/typescript/web/src/client/view.ts:409` — confirmation modal has `role="dialog" aria-modal="true" aria-labelledby="confirm-title"` but no focus trap in events.
[^25]: `platform/typescript/web/src/client/events.ts:51-58` and `platform/typescript/web/src/client/events.ts:89-94` — `window.prompt()` path prompts.
[^26]: `platform/typescript/web/styles.css:329` — `.form-row, .toggle-row { grid-template-columns: 190px minmax(220px, 1fr) minmax(0, 0) }`.
[^27]: `platform/typescript/web/src/client/model.ts:96` — tooltip rendered as `<span class="tooltip" tabindex="0" role="button" ...>i</span>`.
[^28]: Vercel Geist design system: https://vercel.com/geist.
[^29]: Geist font repository and OFL license: https://github.com/vercel/geist-font.
[^30]: Vercel Geist grid and color system references: https://vercel.com/geist/grid and https://vercel.com/geist/colors.
[^31]: shadcn/ui theming and component model: https://ui.shadcn.com/docs/theming.
[^32]: shadcn/ui Command component: https://ui.shadcn.com/docs/components/command.
[^33]: Linear features: https://linear.app/features.
[^34]: Linear changelog with shortcut cues and agent hotkeys: https://linear.app/changelog.
[^35]: Warp terminal editor docs: https://docs.warp.dev/terminal/editor.
[^36]: `platform/typescript/web/styles.css:688-697` — `.terminal-tab-wrap.error/.warning/.success` status classes.
[^37]: GitHub Primer primitives: https://primer.style/product/primitives.
[^38]: GitHub Primer typography: https://primer.style/product/primitives/typography.
[^39]: Primer primitives repository, including token structure and motion references: https://github.com/primer/primitives.
[^40]: Framer Motion documentation: https://motion.dev/docs/react-animation.
[^41]: MDN viewport-relative lengths and `dvh`: https://developer.mozilla.org/en-US/docs/Web/CSS/length#viewport-relative_lengths.
[^42]: WCAG 2.5.8 Target Size Minimum: https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html.
[^43]: WCAG 2.4.11 Focus Appearance: https://www.w3.org/WAI/WCAG22/Understanding/focus-appearance.html.
[^44]: WCAG 4.1.2 Name, Role, Value: https://www.w3.org/WAI/WCAG21/quickref/#name-role-value.
[^45]: ARIA APG Dialog Modal Pattern: https://www.w3.org/WAI/ARIA/apg/patterns/dialog-modal/.
[^46]: `platform/typescript/web/styles.css:812-819` and `platform/typescript/web/styles.css:851-854` — spinner animation and keyframes.
[^47]: WCAG 2.4.1 Bypass Blocks: https://www.w3.org/WAI/WCAG21/quickref/#bypass-blocks.
[^48]: WCAG 4.1.3 Status Messages: https://www.w3.org/WAI/WCAG22/Understanding/status-messages.html.
[^49]: `platform/typescript/web/src/client/view.ts:331-337` — action button rendering uses `title`; icon-only actions need `aria-label`.
[^50]: `platform/typescript/web/src/client/view.ts:202-210` — `renderInfoGrid()` label and grid are not linked.
[^51]: MDN `prefers-reduced-transparency`: https://developer.mozilla.org/en-US/docs/Web/CSS/@media/prefers-reduced-transparency.
[^52]: MDN `color-mix()`: https://developer.mozilla.org/en-US/docs/Web/CSS/color_value/color-mix.
[^53]: `platform/typescript/web/styles.css:94-114` — `.sidebar-resizer` currently uses an 8 px visible track.
[^54]: `platform/typescript/web/styles.css:753-759` — `.terminal-log pre` monospace font stack.
[^55]: `platform/typescript/web/src/client/events.ts:155-163` — confirmation dialog input updates button disabled state imperatively without rerendering.
[^56]: ARIA APG Combobox Pattern: https://www.w3.org/WAI/ARIA/apg/patterns/combobox/.
[^57]: cmdk architecture: https://github.com/pacocoursey/cmdk/blob/main/ARCHITECTURE.md.
[^58]: `platform/typescript/web/styles.css:110-114` — existing `.sidebar-resizer:focus-visible` rule.
[^59]: `platform/typescript/web/styles.css:233-237` — existing `.terminal-resizer:focus-visible` rule.
